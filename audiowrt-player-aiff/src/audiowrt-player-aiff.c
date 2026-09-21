#define _GNU_SOURCE
#include <audiowrt/player.h>

#include <errno.h>
#include <math.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

struct aiff_ctx {
    int fd;
    int rc;
    snd_pcm_t *pcm;
};

static uint16_t be16(const unsigned char *p)
{
    return ((uint16_t)p[0] << 8) | p[1];
}

static uint32_t be32(const unsigned char *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) | p[3];
}

static unsigned int extended80_rate(const unsigned char *p)
{
    unsigned int exponent = ((unsigned int)(p[0] & 0x7f) << 8) | p[1];
    uint64_t mantissa = ((uint64_t)be32(p + 2) << 32) | be32(p + 6);
    double value;

    if (!exponent || !mantissa || (p[0] & 0x80))
        return 0;

    value = ldexp((double)mantissa, (int)exponent - 16383 - 63);
    if (value < 1.0 || value > 384000.0)
        return 0;
    return (unsigned int)(value + 0.5);
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
    struct aiff_ctx *ctx = arg;
    unsigned char hdr[12];
    unsigned int rate = 0, channels = 0, bits = 0;
    uint32_t data_left = 0;
    snd_pcm_format_t alsa_fmt;
    size_t frame_bytes;

    if (read_exact(ctx->fd, hdr, sizeof(hdr)) < 0 ||
        memcmp(hdr, "FORM", 4) || memcmp(hdr + 8, "AIFF", 4)) {
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
        size = be32(chdr + 4);

        if (!memcmp(chdr, "COMM", 4)) {
            unsigned char comm[18];
            if (size < sizeof(comm) || read_exact(ctx->fd, comm, sizeof(comm)) < 0) {
                ctx->rc = EPROTO;
                goto out;
            }
            channels = be16(comm);
            bits = be16(comm + 6);
            rate = extended80_rate(comm + 8);
            if (size > sizeof(comm) &&
                skip_bytes(ctx->fd, size - (uint32_t)sizeof(comm)) < 0) {
                ctx->rc = EPROTO;
                goto out;
            }
        } else if (!memcmp(chdr, "SSND", 4)) {
            unsigned char ssnd[8];
            uint32_t offset;
            if (size < 8 || read_exact(ctx->fd, ssnd, sizeof(ssnd)) < 0) {
                ctx->rc = EPROTO;
                goto out;
            }
            offset = be32(ssnd);
            if (offset > size - 8 || skip_bytes(ctx->fd, offset) < 0) {
                ctx->rc = EPROTO;
                goto out;
            }
            data_left = size - 8 - offset;
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

    if (!channels || channels > 8 || !rate ||
        (bits != 8 && bits != 16 && bits != 24 && bits != 32) || !data_left) {
        ctx->rc = ENOTSUP;
        goto out;
    }

    alsa_fmt = bits == 16 ? SND_PCM_FORMAT_S16 : SND_PCM_FORMAT_S32;
    if (aw_pcm_open(&ctx->pcm, rate, channels, alsa_fmt) < 0) {
        ctx->rc = EIO;
        goto out;
    }

    frame_bytes = (size_t)channels * (bits / 8);
    while (data_left >= frame_bytes) {
        unsigned char in[6144];
        size_t want = data_left > sizeof(in) ? sizeof(in) : data_left;
        size_t frames, samples, i;

        want -= want % frame_bytes;
        if (!want)
            break;
        if (read_exact(ctx->fd, in, want) < 0) {
            ctx->rc = EPROTO;
            break;
        }
        data_left -= (uint32_t)want;
        frames = want / frame_bytes;
        samples = frames * channels;

        if (bits == 16) {
            int16_t out16[3072];
            for (i = 0; i < samples; i++)
                out16[i] = (int16_t)be16(in + i * 2);
            aw_scale_s16(out16, samples);
            if (aw_pcm_write(ctx->pcm, out16, frames) < 0) {
                ctx->rc = EIO;
                break;
            }
        } else {
            int32_t out32[1536];
            if (samples > sizeof(out32) / sizeof(out32[0])) {
                ctx->rc = EOVERFLOW;
                break;
            }
            for (i = 0; i < samples; i++) {
                const unsigned char *p = in + i * (bits / 8);
                if (bits == 8) {
                    out32[i] = ((int32_t)(int8_t)p[0]) << 24;
                } else if (bits == 24) {
                    int32_t v = ((int32_t)p[0] << 16) |
                                ((int32_t)p[1] << 8) | p[2];
                    if (v & 0x00800000)
                        v |= (int32_t)0xff000000;
                    out32[i] = v << 8;
                } else {
                    out32[i] = (int32_t)be32(p);
                }
            }
            aw_scale_s32(out32, samples);
            if (aw_pcm_write(ctx->pcm, out32, frames) < 0) {
                ctx->rc = EIO;
                break;
            }
        }
    }

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
    struct aiff_ctx ctx = {0};

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
