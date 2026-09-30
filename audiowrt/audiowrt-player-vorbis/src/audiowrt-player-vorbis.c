#define _GNU_SOURCE
#include <audiowrt/player.h>

#include <vorbis/vorbisfile.h>

#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#if __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#define AUDIOWRT_BIG_ENDIAN 1
#else
#define AUDIOWRT_BIG_ENDIAN 0
#endif

struct vorbis_ctx {
    int fd;
    int rc;
    snd_pcm_t *pcm;
};

struct vorbis_source {
    int fd;
};

static size_t stream_read(void *ptr, size_t size, size_t nmemb, void *datasource)
{
    struct vorbis_source *src = datasource;
    size_t want;
    ssize_t n;

    if (!size || !nmemb)
        return 0;
    want = size * nmemb;
    do {
        n = read(src->fd, ptr, want);
    } while (n < 0 && errno == EINTR);
    if (n <= 0)
        return 0;
    return (size_t)n / size;
}

static int stream_close(void *datasource)
{
    struct vorbis_source *src = datasource;
    int rc = 0;

    if (src->fd >= 0)
        rc = close(src->fd);
    src->fd = -1;
    return rc;
}

static int stream_seek(void *datasource, ogg_int64_t offset, int whence)
{
    (void)datasource;
    (void)offset;
    (void)whence;
    return -1;
}

static long stream_tell(void *datasource)
{
    (void)datasource;
    return -1;
}

static void *decode_thread(void *arg)
{
    struct vorbis_ctx *ctx = arg;
    struct vorbis_source source = { .fd = ctx->fd };
    ov_callbacks callbacks = {
        .read_func = stream_read,
        .seek_func = stream_seek,
        .close_func = stream_close,
        .tell_func = stream_tell,
    };
    OggVorbis_File vf;
    char buffer[8192];
    int current_stream = -1;
    int bitstream = 0;
    long n;
    size_t decoded = 0;

    if (ov_open_callbacks(&source, &vf, NULL, 0, callbacks) < 0) {
        ctx->rc = EPROTO;
        close(ctx->fd);
        return NULL;
    }

    for (;;) {
        vorbis_info *info;

        n = ov_read(&vf, buffer, sizeof(buffer), AUDIOWRT_BIG_ENDIAN, 2, 1,
                    &bitstream);
        if (n == 0)
            break;
        if (n == OV_HOLE)
            continue;
        if (n < 0) {
            ctx->rc = EPROTO;
            break;
        }

        if (bitstream != current_stream || !ctx->pcm) {
            info = ov_info(&vf, bitstream);
            if (!info || info->rate <= 0 || info->channels < 1 ||
                info->channels > 8) {
                ctx->rc = EPROTO;
                break;
            }
            aw_pcm_close(ctx->pcm);
            ctx->pcm = NULL;
            if (aw_pcm_open(&ctx->pcm, (unsigned int)info->rate,
                            (unsigned int)info->channels,
                            SND_PCM_FORMAT_S16) < 0) {
                ctx->rc = EIO;
                break;
            }
            current_stream = bitstream;
        }

        info = ov_info(&vf, bitstream);
        if (!info || info->channels < 1) {
            ctx->rc = EPROTO;
            break;
        }

        aw_scale_s16((int16_t *)buffer, (size_t)n / sizeof(int16_t));
        if (aw_pcm_write(ctx->pcm, buffer,
                         (snd_pcm_uframes_t)((size_t)n /
                         ((size_t)info->channels * sizeof(int16_t)))) < 0) {
            ctx->rc = EIO;
            break;
        }
        decoded += (size_t)n;
    }

    if (!ctx->rc && !decoded)
        ctx->rc = EPROTO;

    aw_pcm_close(ctx->pcm);
    ctx->pcm = NULL;
    ov_clear(&vf);
    ctx->fd = -1;
    return NULL;
}

int main(int argc, char **argv)
{
    int p[2];
    int net_rc;
    pthread_t thread;
    struct vorbis_ctx ctx = { .fd = -1 };

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
