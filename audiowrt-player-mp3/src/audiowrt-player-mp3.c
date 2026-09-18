#define _GNU_SOURCE
#include <audiowrt/player.h>

#include <mpg123.h>
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

struct mp3_ctx {
    int fd;
    int rc;
    snd_pcm_t *pcm;
};

static void *decode_thread(void *arg)
{
    struct mp3_ctx *ctx = arg;
    mpg123_handle *mh = NULL;
    const long *rates = NULL;
    size_t nrates = 0;
    unsigned char buffer[8192];
    size_t done = 0;
    long rate = 0;
    int channels = 0;
    int encoding = 0;
    int err = MPG123_OK;
    int rc;
    size_t i;

    if (mpg123_init() != MPG123_OK) {
        ctx->rc = EIO;
        close(ctx->fd);
        return NULL;
    }

    mh = mpg123_new(NULL, &err);
    if (!mh) {
        ctx->rc = EIO;
        goto out;
    }

    mpg123_format_none(mh);
    mpg123_rates(&rates, &nrates);
    for (i = 0; i < nrates; i++)
        mpg123_format(mh, rates[i], MPG123_MONO | MPG123_STEREO,
                      MPG123_ENC_SIGNED_16);

    if (mpg123_open_fd(mh, ctx->fd) != MPG123_OK) {
        ctx->rc = EIO;
        goto out;
    }

    for (;;) {
        done = 0;
        rc = mpg123_read(mh, buffer, sizeof(buffer), &done);
        if (rc == MPG123_NEW_FORMAT) {
            if (mpg123_getformat(mh, &rate, &channels, &encoding) != MPG123_OK ||
                encoding != MPG123_ENC_SIGNED_16 || rate <= 0 ||
                channels < 1 || channels > 2) {
                ctx->rc = EINVAL;
                break;
            }
            aw_pcm_close(ctx->pcm);
            ctx->pcm = NULL;
            if (aw_pcm_open(&ctx->pcm, (unsigned int)rate,
                            (unsigned int)channels, SND_PCM_FORMAT_S16_LE) < 0) {
                ctx->rc = EIO;
                break;
            }
        }

        if (done > 0) {
            if (!ctx->pcm || channels <= 0) {
                ctx->rc = EPROTO;
                break;
            }
            aw_scale_s16((int16_t *)buffer, done / sizeof(int16_t));
            if (aw_pcm_write(ctx->pcm, buffer,
                             done / ((size_t)channels * sizeof(int16_t))) < 0) {
                ctx->rc = EIO;
                break;
            }
        }

        if (rc == MPG123_DONE)
            break;
        if (rc != MPG123_OK && rc != MPG123_NEW_FORMAT) {
            ctx->rc = EIO;
            break;
        }
    }

out:
    aw_pcm_close(ctx->pcm);
    ctx->pcm = NULL;
    if (mh) {
        mpg123_close(mh);
        mpg123_delete(mh);
    }
    mpg123_exit();
    close(ctx->fd);
    return NULL;
}

int main(int argc, char **argv)
{
    int p[2];
    int net_rc;
    pthread_t thread;
    struct mp3_ctx ctx = {0};

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
