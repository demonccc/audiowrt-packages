#define _GNU_SOURCE
#include <audiowrt/player.h>

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static uint16_t le16(const unsigned char *p)
{
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t le32(const unsigned char *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static int read_exact(int fd, void *dst, size_t len)
{
    unsigned char *p = dst;
    while (len) {
        ssize_t n = read(fd, p, len);
        if (n == 0)
            return -1;
        if (n < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        p += n;
        len -= (size_t)n;
    }
    return 0;
}

static int skip_bytes(int fd, uint32_t len)
{
    unsigned char buf[512];
    while (len) {
        size_t chunk = len > sizeof(buf) ? sizeof(buf) : len;
        if (read_exact(fd, buf, chunk) < 0)
            return -1;
        len -= (uint32_t)chunk;
    }
    return 0;
}

static int play_faad_wav(int fd)
{
    unsigned char hdr[12];
    unsigned int rate = 0, channels = 0, bits = 0;
    uint16_t audio_format = 0;
    int data_found = 0;
    snd_pcm_t *pcm = NULL;
    int rc = 0;

    if (read_exact(fd, hdr, sizeof(hdr)) < 0 ||
        memcmp(hdr, "RIFF", 4) || memcmp(hdr + 8, "WAVE", 4))
        return EPROTO;

    for (;;) {
        unsigned char chdr[8];
        uint32_t size;

        if (read_exact(fd, chdr, sizeof(chdr)) < 0)
            return EPROTO;
        size = le32(chdr + 4);

        if (!memcmp(chdr, "fmt ", 4)) {
            unsigned char fmt[40];
            size_t keep = size < sizeof(fmt) ? size : sizeof(fmt);
            if (size < 16 || read_exact(fd, fmt, keep) < 0)
                return EPROTO;
            if (size > keep && skip_bytes(fd, size - (uint32_t)keep) < 0)
                return EPROTO;
            audio_format = le16(fmt);
            channels = le16(fmt + 2);
            rate = le32(fmt + 4);
            bits = le16(fmt + 14);
        } else if (!memcmp(chdr, "data", 4)) {
            data_found = 1;
            break;
        } else if (skip_bytes(fd, size) < 0) {
            return EPROTO;
        }

        if (size & 1) {
            unsigned char pad;
            if (read_exact(fd, &pad, 1) < 0)
                return EPROTO;
        }
    }

    if (!data_found || audio_format != 1 || !channels || channels > 8 ||
        !rate || bits != 16)
        return ENOTSUP;

    if (aw_pcm_open(&pcm, rate, channels, SND_PCM_FORMAT_S16) < 0)
        return EIO;

    {
        unsigned char raw[6148];
        size_t pending = 0;
        const size_t frame_bytes = (size_t)channels * 2U;

        for (;;) {
            ssize_t n;
            size_t usable, frames, count, i;
            int16_t samples[3074];

            do {
                n = read(fd, raw + pending, sizeof(raw) - pending);
            } while (n < 0 && errno == EINTR);

            if (n < 0) {
                rc = errno ? errno : EIO;
                break;
            }
            if (n == 0)
                break;

            pending += (size_t)n;
            usable = pending - (pending % frame_bytes);
            frames = usable / frame_bytes;
            count = frames * channels;

            for (i = 0; i < count; i++)
                samples[i] = (int16_t)le16(raw + i * 2);

            aw_scale_s16(samples, count);
            if (aw_pcm_write(pcm, samples, frames) < 0) {
                rc = EIO;
                break;
            }

            pending -= usable;
            if (pending)
                memmove(raw, raw + usable, pending);
        }

        if (pending && !rc)
            rc = EPROTO;
    }

    aw_pcm_close(pcm);
    return rc;
}

int main(int argc, char **argv)
{
    char path[] = "/tmp/audiowrt/m4a-XXXXXX";
    int media_fd = -1, pcm_pipe[2] = {-1, -1};
    int fetch_rc, play_rc = 0, status = 0;
    pid_t child = -1;

    if (argc != 2) {
        fprintf(stderr, "usage: %s <http-or-https-uri>\n", argv[0]);
        return 2;
    }

    if (mkdir("/tmp/audiowrt", 0755) < 0 && errno != EEXIST) {
        perror("mkdir");
        return 1;
    }

    media_fd = mkstemp(path);
    if (media_fd < 0) {
        perror("mkstemp");
        return 1;
    }

    fetch_rc = aw_http_stream_to_fd(argv[1], media_fd);
    close(media_fd);
    media_fd = -1;
    if (fetch_rc)
        goto out;

    if (pipe(pcm_pipe) < 0) {
        play_rc = errno ? errno : EIO;
        goto out;
    }

    child = fork();
    if (child < 0) {
        play_rc = errno ? errno : EIO;
        goto out;
    }

    if (child == 0) {
        close(pcm_pipe[0]);
        if (dup2(pcm_pipe[1], STDOUT_FILENO) < 0)
            _exit(126);
        close(pcm_pipe[1]);
        execl("/usr/bin/faad", "faad", "-q", "-w", path, (char *)NULL);
        _exit(127);
    }

    close(pcm_pipe[1]);
    pcm_pipe[1] = -1;
    play_rc = play_faad_wav(pcm_pipe[0]);
    close(pcm_pipe[0]);
    pcm_pipe[0] = -1;

    while (waitpid(child, &status, 0) < 0 && errno == EINTR)
        ;
    child = -1;
    if ((!WIFEXITED(status) || WEXITSTATUS(status) != 0) && !play_rc)
        play_rc = EPROTO;

out:
    if (media_fd >= 0)
        close(media_fd);
    if (pcm_pipe[0] >= 0)
        close(pcm_pipe[0]);
    if (pcm_pipe[1] >= 0)
        close(pcm_pipe[1]);
    if (child > 0) {
        kill(child, SIGTERM);
        waitpid(child, NULL, 0);
    }
    unlink(path);
    return (fetch_rc || play_rc) ? 1 : 0;
}
