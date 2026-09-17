#define _GNU_SOURCE
#include <audiowrt/player.h>

#include <neaacdec.h>
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define AAC_BUFFER_SIZE 65536

struct aac_ctx {
    int fd;
    int rc;
    snd_pcm_t *pcm;
};

static ssize_t fill_buffer(int fd, unsigned char *buf, size_t *len)
{
    ssize_t n;
    if (*len >= AAC_BUFFER_SIZE)
        return 0;
    do {
        n = read(fd, buf + *len, AAC_BUFFER_SIZE - *len);
    } while (n < 0 && errno == EINTR);
    if (n > 0)
        *len += (size_t)n;
    return n;
}

static void consume(unsigned char *buf, size_t *len, size_t count)
{
    if (count >= *len) {
        *len = 0;
        return;
    }
    memmove(buf, buf + count, *len - count);
    *len -= count;
}

static void *decode_thread(void *arg)
{
    struct aac_ctx *ctx = arg;
    NeAACDecHandle dec = NULL;
    NeAACDecConfigurationPtr cfg;
    unsigned char *buf = NULL;
    size_t len = 0;
    unsigned long init_rate = 0;
    unsigned char init_channels = 0;
    long init_consumed;
    int eof = 0;

    buf = malloc(AAC_BUFFER_SIZE);
    if (!buf) {
        ctx->rc = ENOMEM;
        close(ctx->fd);
        return NULL;
    }

    dec = NeAACDecOpen();
    if (!dec) {
        ctx->rc = ENOMEM;
        goto out;
    }

    cfg = NeAACDecGetCurrentConfiguration(dec);
    cfg->outputFormat = FAAD_FMT_16BIT;
    if (!NeAACDecSetConfiguration(dec, cfg)) {
        ctx->rc = EINVAL;
        goto out;
    }

    while (len < 8192 && !eof) {
        ssize_t n = fill_buffer(ctx->fd, buf, &len);
        if (n == 0)
            eof = 1;
        else if (n < 0) {
            ctx->rc = errno ? errno : EIO;
            goto out;
        }
    }

    if (!len) {
        ctx->rc = EPROTO;
        goto out;
    }

    init_consumed = NeAACDecInit(dec, buf, (unsigned long)len,
                                 &init_rate, &init_channels);
    if (init_consumed < 0) {
        ctx->rc = EPROTO;
        goto out;
    }
    consume(buf, &len, (size_t)init_consumed);

    for (;;) {
        NeAACDecFrameInfo info;
        void *samples;

        while (len < 8192 && !eof) {
            ssize_t n = fill_buffer(ctx->fd, buf, &len);
            if (n == 0)
                eof = 1;
            else if (n < 0) {
                ctx->rc = errno ? errno : EIO;
                goto out;
            }
        }

        if (!len && eof)
            break;

        memset(&info, 0, sizeof(info));
        samples = NeAACDecDecode(dec, &info, buf, (unsigned long)len);

        if (info.bytesconsumed > 0)
            consume(buf, &len, info.bytesconsumed);

        if (info.error) {
            if (!info.bytesconsumed) {
                if (!eof && len < AAC_BUFFER_SIZE) {
                    ssize_t n = fill_buffer(ctx->fd, buf, &len);
                    if (n > 0)
                        continue;
                }
                ctx->rc = EPROTO;
                break;
            }
            continue;
        }

        if (samples && info.samples > 0) {
            if (!ctx->pcm) {
                if (!info.samplerate || !info.channels || info.channels > 8) {
                    ctx->rc = EINVAL;
                    break;
                }
                if (aw_pcm_open(&ctx->pcm, info.samplerate, info.channels,
                                SND_PCM_FORMAT_S16_LE) < 0) {
                    ctx->rc = EIO;
                    break;
                }
            }
            aw_scale_s16(samples, info.samples);
            if (aw_pcm_write(ctx->pcm, samples, info.samples / info.channels) < 0) {
                ctx->rc = EIO;
                break;
            }
        }

        if (!info.bytesconsumed && !info.samples) {
            if (eof)
                break;
            if (len >= AAC_BUFFER_SIZE) {
                ctx->rc = EPROTO;
                break;
            }
        }
    }

out:
    aw_pcm_close(ctx->pcm);
    ctx->pcm = NULL;
    if (dec)
        NeAACDecClose(dec);
    free(buf);
    close(ctx->fd);
    return NULL;
}

int main(int argc, char **argv)
{
    int p[2];
    int net_rc;
    pthread_t thread;
    struct aac_ctx ctx = {0};

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
