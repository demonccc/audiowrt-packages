#define _GNU_SOURCE
#include <audiowrt/player.h>

#include <mad.h>

#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define INPUT_BUFFER_SIZE 8192

struct mp3_ctx {
    int fd;
    int rc;
    int eof;
    snd_pcm_t *pcm;
    unsigned int rate;
    unsigned int channels;
    unsigned char input[INPUT_BUFFER_SIZE + MAD_BUFFER_GUARD];
};

static signed int scale_sample(mad_fixed_t sample)
{
    sample += (mad_fixed_t)1L << (MAD_F_FRACBITS - 16);

    if (sample >= MAD_F_ONE)
        sample = MAD_F_ONE - 1;
    else if (sample < -MAD_F_ONE)
        sample = -MAD_F_ONE;

    return sample >> (MAD_F_FRACBITS + 1 - 16);
}

static enum mad_flow input_cb(void *data, struct mad_stream *stream)
{
    struct mp3_ctx *ctx = data;
    size_t remaining = 0;
    ssize_t n;

    if (ctx->eof)
        return MAD_FLOW_STOP;

    if (stream->next_frame) {
        remaining = (size_t)(stream->bufend - stream->next_frame);
        memmove(ctx->input, stream->next_frame, remaining);
    }

    do {
        n = read(ctx->fd, ctx->input + remaining,
                 INPUT_BUFFER_SIZE - remaining);
    } while (n < 0 && errno == EINTR);

    if (n < 0) {
        ctx->rc = errno ? errno : EIO;
        return MAD_FLOW_STOP;
    }

    if (n == 0) {
        if (!remaining)
            return MAD_FLOW_STOP;
        memset(ctx->input + remaining, 0, MAD_BUFFER_GUARD);
        mad_stream_buffer(stream, ctx->input, remaining + MAD_BUFFER_GUARD);
        ctx->eof = 1;
        return MAD_FLOW_CONTINUE;
    }

    mad_stream_buffer(stream, ctx->input, remaining + (size_t)n);
    stream->error = MAD_ERROR_NONE;
    return MAD_FLOW_CONTINUE;
}

static enum mad_flow output_cb(void *data, const struct mad_header *header,
                               struct mad_pcm *pcm)
{
    struct mp3_ctx *ctx = data;
    int16_t output[1152 * 2];
    unsigned int i;

    (void)header;

    if (pcm->channels < 1 || pcm->channels > 2 || !pcm->samplerate ||
        pcm->length > 1152) {
        ctx->rc = EPROTO;
        return MAD_FLOW_STOP;
    }

    if (!ctx->pcm || ctx->rate != pcm->samplerate ||
        ctx->channels != pcm->channels) {
        aw_pcm_close(ctx->pcm);
        ctx->pcm = NULL;
        if (aw_pcm_open(&ctx->pcm, pcm->samplerate, pcm->channels,
                        SND_PCM_FORMAT_S16) < 0) {
            ctx->rc = EIO;
            return MAD_FLOW_STOP;
        }
        ctx->rate = pcm->samplerate;
        ctx->channels = pcm->channels;
    }

    for (i = 0; i < pcm->length; i++) {
        output[i * pcm->channels] =
            (int16_t)scale_sample(pcm->samples[0][i]);
        if (pcm->channels == 2)
            output[i * 2 + 1] =
                (int16_t)scale_sample(pcm->samples[1][i]);
    }

    aw_scale_s16(output, (size_t)pcm->length * pcm->channels);
    if (aw_pcm_write(ctx->pcm, output, pcm->length) < 0) {
        ctx->rc = EIO;
        return MAD_FLOW_STOP;
    }

    return MAD_FLOW_CONTINUE;
}

static enum mad_flow error_cb(void *data, struct mad_stream *stream,
                              struct mad_frame *frame)
{
    struct mp3_ctx *ctx = data;
    (void)frame;

    if (MAD_RECOVERABLE(stream->error))
        return MAD_FLOW_CONTINUE;

    ctx->rc = EPROTO;
    return MAD_FLOW_STOP;
}

static void *decode_thread(void *arg)
{
    struct mp3_ctx *ctx = arg;
    struct mad_decoder decoder;
    int rc;

    mad_decoder_init(&decoder, ctx, input_cb, NULL, NULL,
                     output_cb, error_cb, NULL);
    rc = mad_decoder_run(&decoder, MAD_DECODER_MODE_SYNC);
    mad_decoder_finish(&decoder);

    if (rc < 0 && !ctx->rc)
        ctx->rc = EPROTO;

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
