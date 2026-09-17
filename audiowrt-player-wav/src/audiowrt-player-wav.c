#define _GNU_SOURCE
#include <audiowrt/player.h>

#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

struct wav_ctx {
    int fd;
    int rc;
    snd_pcm_t *pcm;
};

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

static void *decode_thread(void *arg)
{
    struct wav_ctx *ctx = arg;
    unsigned char hdr[12];
    unsigned int rate = 0, channels = 0, bits = 0;
    uint16_t audio_format = 0;
    uint32_t data_left = 0;
    snd_pcm_format_t alsa_fmt;
    size_t in_frame_bytes;

    if (read_exact(ctx->fd, hdr, sizeof(hdr)) < 0 ||
        memcmp(hdr, "RIFF", 4) || memcmp(hdr + 8, "WAVE", 4)) {
        ctx->rc = EPROTO;
        goto out;
    }

    for (;;) {
        unsigned char chdr[8];
        uint32_t size;
        if (read_exact(ctx->fd, chdr, sizeof(chdr)) < 0) {
            ctx->rc = EPROTO;
            goto out;
        }
        size = le32(chdr + 4);

        if (!memcmp(chdr, "fmt ", 4)) {
            unsigned char fmt[40];
            size_t keep = size < sizeof(fmt) ? size : sizeof(fmt);
            if (size < 16 || read_exact(ctx->fd, fmt, keep) < 0) {
                ctx->rc = EPROTO;
                goto out;
            }
            if (size > keep && skip_bytes(ctx->fd, size - (uint32_t)keep) < 0) {
                ctx->rc = EPROTO;
                goto out;
            }
            audio_format = le16(fmt);
            channels = le16(fmt + 2);
            rate = le32(fmt + 4);
            bits = le16(fmt + 14);
            if (audio_format != 1 || !channels || channels > 8 || !rate ||
                (bits != 8 && bits != 16 && bits != 24 && bits != 32)) {
                ctx->rc = ENOTSUP;
                goto out;
            }
        } else if (!memcmp(chdr, "data", 4)) {
            data_left = size;
            break;
        } else if (skip_bytes(ctx->fd, size) < 0) {
            ctx->rc = EPROTO;
            goto out;
        }
        if (size & 1) {
            unsigned char pad;
            if (read_exact(ctx->fd, &pad, 1) < 0) {
                ctx->rc = EPROTO;
                goto out;
            }
        }
    }

    if (!audio_format || !data_left) {
        ctx->rc = EPROTO;
        goto out;
    }

    alsa_fmt = bits == 16 ? SND_PCM_FORMAT_S16_LE : SND_PCM_FORMAT_S32_LE;
    if (aw_pcm_open(&ctx->pcm, rate, channels, alsa_fmt) < 0) {
        ctx->rc = EIO;
        goto out;
    }

    in_frame_bytes = (size_t)channels * (bits / 8);
    while (data_left >= in_frame_bytes) {
        unsigned char in[6144];
        size_t want = data_left > sizeof(in) ? sizeof(in) : data_left;
        size_t frames;
        want -= want % in_frame_bytes;
        if (!want)
            break;
        if (read_exact(ctx->fd, in, want) < 0) {
            ctx->rc = EPROTO;
            break;
        }
        data_left -= (uint32_t)want;
        frames = want / in_frame_bytes;

        if (bits == 16) {
            aw_scale_s16((int16_t *)in, frames * channels);
            if (aw_pcm_write(ctx->pcm, in, frames) < 0) {
                ctx->rc = EIO;
                break;
            }
        } else {
            size_t samples = frames * channels;
            int32_t *out = malloc(samples * sizeof(*out));
            size_t i;
            if (!out) {
                ctx->rc = ENOMEM;
                break;
            }
            for (i = 0; i < samples; i++) {
                const unsigned char *p = in + i * (bits / 8);
                if (bits == 8) {
                    out[i] = ((int32_t)p[0] - 128) << 24;
                } else if (bits == 24) {
                    int32_t v = (int32_t)p[0] | ((int32_t)p[1] << 8) |
                                ((int32_t)p[2] << 16);
                    if (v & 0x00800000)
                        v |= (int32_t)0xff000000;
                    out[i] = v << 8;
                } else {
                    out[i] = (int32_t)le32(p);
                }
            }
            aw_scale_s32(out, samples);
            if (aw_pcm_write(ctx->pcm, out, frames) < 0)
                ctx->rc = EIO;
            free(out);
            if (ctx->rc)
                break;
        }
    }

out:
    aw_pcm_close(ctx->pcm);
    ctx->pcm = NULL;
    close(ctx->fd);
    return NULL;
}

int main(int argc, char **argv)
{
    int p[2];
    int net_rc;
    pthread_t thread;
    struct wav_ctx ctx = {0};

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
