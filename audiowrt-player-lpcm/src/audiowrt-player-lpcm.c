#define _GNU_SOURCE
#include <audiowrt/player.h>

#include <ctype.h>
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

struct lpcm_ctx {
    int fd;
    int rc;
    unsigned int rate;
    unsigned int channels;
    snd_pcm_t *pcm;
};

static unsigned int metadata_uint(const char *metadata, const char *key,
                                  unsigned int fallback)
{
    const char *p;
    size_t key_len;

    if (!metadata || !*metadata)
        return fallback;

    key_len = strlen(key);
    for (p = metadata; *p; p++) {
        unsigned char previous = p == metadata ? 0 : (unsigned char)p[-1];
        if ((p == metadata || (!isalnum(previous) && previous != '_' && previous != '-')) &&
            strncasecmp(p, key, key_len) == 0 && p[key_len] == '=') {
            char *end = NULL;
            unsigned long value = strtoul(p + key_len + 1, &end, 10);
            if (end != p + key_len + 1 && value <= 384000)
                return (unsigned int)value;
        }
    }
    return fallback;
}

static void *decode_thread(void *arg)
{
    struct lpcm_ctx *ctx = arg;
    unsigned char input[8208];
    int16_t output[4104];
    size_t pending = 0;
    const size_t frame_bytes = (size_t)ctx->channels * 2U;

    if (!ctx->channels || ctx->channels > 8 || !ctx->rate ||
        ctx->rate > 384000 || frame_bytes > sizeof(input)) {
        ctx->rc = EINVAL;
        goto out;
    }

    if (aw_pcm_open(&ctx->pcm, ctx->rate, ctx->channels,
                    SND_PCM_FORMAT_S16) < 0) {
        ctx->rc = EIO;
        goto out;
    }

    for (;;) {
        ssize_t n;
        size_t usable, frames, samples, i;

        do {
            n = read(ctx->fd, input + pending, sizeof(input) - pending);
        } while (n < 0 && errno == EINTR);

        if (n < 0) {
            ctx->rc = errno ? errno : EIO;
            break;
        }
        if (n == 0)
            break;

        pending += (size_t)n;
        usable = pending - (pending % frame_bytes);
        frames = usable / frame_bytes;
        samples = frames * ctx->channels;

        for (i = 0; i < samples; i++) {
            const unsigned char *p = input + i * 2;
            output[i] = (int16_t)(((uint16_t)p[0] << 8) | p[1]);
        }

        aw_scale_s16(output, samples);
        if (aw_pcm_write(ctx->pcm, output, frames) < 0) {
            ctx->rc = EIO;
            break;
        }

        pending -= usable;
        if (pending)
            memmove(input, input + usable, pending);
    }

    if (pending)
        ctx->rc = EPROTO;

out:
    aw_pcm_close(ctx->pcm);
    close(ctx->fd);
    return NULL;
}

int main(int argc, char **argv)
{
    int p[2];
    int net_rc;
    pthread_t thread;
    const char *metadata = getenv("AUDIOWRT_METADATA");
    struct lpcm_ctx ctx = {0};

    if (argc != 2) {
        fprintf(stderr, "usage: %s <http-or-https-uri>\n", argv[0]);
        return 2;
    }

    ctx.rate = metadata_uint(metadata, "rate", 44100);
    ctx.channels = metadata_uint(metadata, "channels", 2);

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
