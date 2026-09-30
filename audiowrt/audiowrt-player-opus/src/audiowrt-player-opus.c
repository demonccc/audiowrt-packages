#define _GNU_SOURCE
#include <audiowrt/player.h>

#include <errno.h>
#include <opus/opusfile.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

struct opus_ctx {
    int fd;
    int rc;
    snd_pcm_t *pcm;
};

static int stream_read(void *source, unsigned char *ptr, int nbytes)
{
    int fd = *(int *)source;
    ssize_t n;

    do {
        n = read(fd, ptr, (size_t)nbytes);
    } while (n < 0 && errno == EINTR);

    if (n < 0)
        return -1;
    return (int)n;
}

static int stream_close(void *source)
{
    int *fd = source;
    if (*fd >= 0) {
        close(*fd);
        *fd = -1;
    }
    return 0;
}

static void *decode_thread(void *arg)
{
    struct opus_ctx *ctx = arg;
    OpusFileCallbacks callbacks = {
        .read = stream_read,
        .seek = NULL,
        .tell = NULL,
        .close = stream_close,
    };
    OggOpusFile *of;
    int error = 0;

    of = op_open_callbacks(&ctx->fd, &callbacks, NULL, 0, &error);
    if (!of) {
        ctx->rc = EPROTO;
        stream_close(&ctx->fd);
        return NULL;
    }

    if (aw_pcm_open(&ctx->pcm, 48000, 2, SND_PCM_FORMAT_S16) < 0) {
        ctx->rc = EIO;
        op_free(of);
        return NULL;
    }

    for (;;) {
        opus_int16 pcm[5760 * 2];
        int frames = op_read_stereo(of, pcm, 5760);
        if (frames == 0)
            break;
        if (frames < 0) {
            if (frames == OP_HOLE)
                continue;
            ctx->rc = EPROTO;
            break;
        }

        aw_scale_s16((int16_t *)pcm, (size_t)frames * 2U);
        if (aw_pcm_write(ctx->pcm, pcm, (snd_pcm_uframes_t)frames) < 0) {
            ctx->rc = EIO;
            break;
        }
    }

    aw_pcm_close(ctx->pcm);
    ctx->pcm = NULL;
    op_free(of);
    return NULL;
}

int main(int argc, char **argv)
{
    int p[2];
    int net_rc;
    pthread_t thread;
    struct opus_ctx ctx = { .fd = -1 };

    if (argc != 2) {
        fprintf(stderr, "usage: %s <http-or-https-uri>\n", argv[0]);
        return 2;
    }

    if (pipe(p) < 0) {
        perror("pipe");
        return 1;
    }

    ctx.fd = p[0];
    if (pthread_create(&thread, NULL, decode_thread, &ctx) != 0) {
        close(p[0]);
        close(p[1]);
        return 1;
    }

    net_rc = aw_http_stream_to_fd(argv[1], p[1]);
    close(p[1]);
    pthread_join(thread, NULL);

    if (net_rc && !ctx.rc)
        ctx.rc = net_rc;
    return ctx.rc ? 1 : 0;
}
