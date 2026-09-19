#define _GNU_SOURCE
#include <audiowrt/player.h>

#include <FLAC/stream_decoder.h>
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

struct flac_ctx {
    int fd;
    int rc;
    snd_pcm_t *pcm;
    unsigned int rate;
    unsigned int channels;
    unsigned int bits;
};

static void flac_metadata(const FLAC__StreamDecoder *decoder,
                          const FLAC__StreamMetadata *metadata,
                          void *client_data)
{
    struct flac_ctx *ctx = client_data;
    snd_pcm_format_t fmt;
    (void)decoder;

    if (metadata->type != FLAC__METADATA_TYPE_STREAMINFO)
        return;

    ctx->rate = metadata->data.stream_info.sample_rate;
    ctx->channels = metadata->data.stream_info.channels;
    ctx->bits = metadata->data.stream_info.bits_per_sample;

    if (!ctx->rate || !ctx->channels || ctx->channels > 8 || !ctx->bits) {
        ctx->rc = EINVAL;
        return;
    }

    fmt = ctx->bits <= 16 ? SND_PCM_FORMAT_S16 : SND_PCM_FORMAT_S32;
    if (aw_pcm_open(&ctx->pcm, ctx->rate, ctx->channels, fmt) < 0)
        ctx->rc = EIO;
}

static FLAC__StreamDecoderWriteStatus flac_write(
    const FLAC__StreamDecoder *decoder,
    const FLAC__Frame *frame,
    const FLAC__int32 *const buffer[],
    void *client_data)
{
    struct flac_ctx *ctx = client_data;
    size_t frames = frame->header.blocksize;
    size_t samples = frames * ctx->channels;
    size_t i, ch;
    (void)decoder;

    if (ctx->rc || !ctx->pcm)
        return FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;

    if (ctx->bits <= 16) {
        int shift = 16 - (int)ctx->bits;
        int16_t *out = malloc(samples * sizeof(*out));
        if (!out) {
            ctx->rc = ENOMEM;
            return FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
        }
        for (i = 0; i < frames; i++) {
            for (ch = 0; ch < ctx->channels; ch++) {
                int32_t v = buffer[ch][i];
                if (shift > 0)
                    v <<= shift;
                out[i * ctx->channels + ch] = (int16_t)v;
            }
        }
        aw_scale_s16(out, samples);
        if (aw_pcm_write(ctx->pcm, out, frames) < 0)
            ctx->rc = EIO;
        free(out);
    } else {
        int shift = 32 - (int)ctx->bits;
        int32_t *out = malloc(samples * sizeof(*out));
        if (!out) {
            ctx->rc = ENOMEM;
            return FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
        }
        for (i = 0; i < frames; i++) {
            for (ch = 0; ch < ctx->channels; ch++) {
                int32_t v = buffer[ch][i];
                if (shift > 0)
                    v <<= shift;
                out[i * ctx->channels + ch] = v;
            }
        }
        aw_scale_s32(out, samples);
        if (aw_pcm_write(ctx->pcm, out, frames) < 0)
            ctx->rc = EIO;
        free(out);
    }

    return ctx->rc ? FLAC__STREAM_DECODER_WRITE_STATUS_ABORT
                   : FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE;
}

static void flac_error(const FLAC__StreamDecoder *decoder,
                       FLAC__StreamDecoderErrorStatus status,
                       void *client_data)
{
    struct flac_ctx *ctx = client_data;
    (void)decoder;
    (void)status;
    if (!ctx->rc)
        ctx->rc = EIO;
}

static void *decode_thread(void *arg)
{
    struct flac_ctx *ctx = arg;
    FLAC__StreamDecoder *decoder = NULL;
    FLAC__StreamDecoderInitStatus init;
    FILE *input = NULL;

    input = fdopen(ctx->fd, "rb");
    if (!input) {
        ctx->rc = errno ? errno : EIO;
        close(ctx->fd);
        return NULL;
    }

    decoder = FLAC__stream_decoder_new();
    if (!decoder) {
        ctx->rc = ENOMEM;
        fclose(input);
        return NULL;
    }

    init = FLAC__stream_decoder_init_FILE(decoder, input, flac_write,
                                           flac_metadata, flac_error, ctx);
    if (init != FLAC__STREAM_DECODER_INIT_STATUS_OK) {
        ctx->rc = EIO;
    } else if (!FLAC__stream_decoder_process_until_end_of_stream(decoder) && !ctx->rc) {
        ctx->rc = EIO;
    }

    FLAC__stream_decoder_finish(decoder);
    FLAC__stream_decoder_delete(decoder);
    aw_pcm_close(ctx->pcm);
    ctx->pcm = NULL;
    return NULL;
}

int main(int argc, char **argv)
{
    int p[2];
    int net_rc;
    pthread_t thread;
    struct flac_ctx ctx = {0};

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
