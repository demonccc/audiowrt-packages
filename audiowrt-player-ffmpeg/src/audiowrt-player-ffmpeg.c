#define _GNU_SOURCE
#include <audiowrt/player.h>

#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static int play_pcm(int fd)
{
    unsigned char input[8196];
    int16_t samples[4098];
    size_t pending = 0;
    snd_pcm_t *pcm = NULL;
    int rc = 0;

    if (aw_pcm_open(&pcm, 48000, 2, SND_PCM_FORMAT_S16) < 0)
        return EIO;

    for (;;) {
        ssize_t n;
        size_t usable, frames, count, i;

        do {
            n = read(fd, input + pending, sizeof(input) - pending);
        } while (n < 0 && errno == EINTR);

        if (n < 0) {
            rc = errno ? errno : EIO;
            break;
        }
        if (n == 0)
            break;

        pending += (size_t)n;
        usable = pending - (pending % 4U);
        frames = usable / 4U;
        count = frames * 2U;

        for (i = 0; i < count; i++) {
            const unsigned char *p = input + i * 2U;
#if __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
            samples[i] = (int16_t)(((uint16_t)p[1] << 8) | p[0]);
#else
            samples[i] = (int16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
#endif
        }

        aw_scale_s16(samples, count);
        if (aw_pcm_write(pcm, samples, frames) < 0) {
            rc = EIO;
            break;
        }

        pending -= usable;
        if (pending)
            memmove(input, input + usable, pending);
    }

    if (pending && !rc)
        rc = EPROTO;
    aw_pcm_close(pcm);
    return rc;
}

int main(int argc, char **argv)
{
    int p[2] = {-1, -1};
    pid_t child;
    int status = 0;
    int rc;

    if (argc != 2) {
        fprintf(stderr, "usage: %s <http-or-https-uri>\n", argv[0]);
        return 2;
    }

    if (pipe(p) < 0) {
        perror("pipe");
        return 1;
    }

    child = fork();
    if (child < 0) {
        close(p[0]);
        close(p[1]);
        return 1;
    }

    if (child == 0) {
        close(p[0]);
        if (dup2(p[1], STDOUT_FILENO) < 0)
            _exit(126);
        close(p[1]);

        execl("/usr/bin/ffmpeg", "ffmpeg",
              "-nostdin", "-hide_banner", "-loglevel", "error",
              "-i", argv[1],
              "-vn", "-sn", "-dn",
              "-f", "s16le", "-acodec", "pcm_s16le",
              "-ar", "48000", "-ac", "2", "pipe:1",
              (char *)NULL);
        _exit(127);
    }

    close(p[1]);
    p[1] = -1;
    rc = play_pcm(p[0]);
    close(p[0]);
    p[0] = -1;

    if (rc)
        kill(child, SIGTERM);

    while (waitpid(child, &status, 0) < 0 && errno == EINTR)
        ;

    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
        rc = rc ? rc : EPROTO;

    return rc ? 1 : 0;
}
