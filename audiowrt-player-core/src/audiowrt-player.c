#define _GNU_SOURCE
#include "audiowrt-player.h"

#include <errno.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <libubox/uloop.h>
#include <libubox/uclient.h>

struct aw_fetch {
    int fd;
    int rc;
    unsigned redirects;
};

static struct ustream_ssl_ctx *ssl_ctx;
static const struct ustream_ssl_ops *ssl_ops;

static void fetch_done(struct uclient *cl, int rc)
{
    struct aw_fetch *f = cl->priv;
    if (!f->rc)
        f->rc = rc;
    uclient_disconnect(cl);
    uloop_end();
}

static void header_done_cb(struct uclient *cl)
{
    struct aw_fetch *f = cl->priv;
    int ret;

    if (uclient_http_status_redirect(cl)) {
        if (f->redirects++ >= 10) {
            fetch_done(cl, ELOOP);
            return;
        }
        ret = uclient_http_redirect(cl);
        if (ret <= 0)
            fetch_done(cl, EPROTO);
        return;
    }

    if (cl->status_code != 200 && cl->status_code != 206)
        fetch_done(cl, EPROTO);
}

static void data_read_cb(struct uclient *cl)
{
    struct aw_fetch *f = cl->priv;
    char buf[4096];
    int len;

    while ((len = uclient_read(cl, buf, sizeof(buf))) > 0) {
        int off = 0;
        while (off < len) {
            ssize_t written = write(f->fd, buf + off, (size_t)(len - off));
            if (written < 0) {
                if (errno == EINTR)
                    continue;
                fetch_done(cl, errno ? errno : EIO);
                return;
            }
            off += (int)written;
        }
    }
}

static void data_eof_cb(struct uclient *cl)
{
    if (cl->data_eof)
        fetch_done(cl, 0);
    else
        fetch_done(cl, ECONNRESET);
}

static void error_cb(struct uclient *cl, int code)
{
    int rc = EIO;
    switch (code) {
    case UCLIENT_ERROR_CONNECT:
        rc = ECONNREFUSED;
        break;
    case UCLIENT_ERROR_TIMEDOUT:
        rc = ETIMEDOUT;
        break;
    case UCLIENT_ERROR_SSL_INVALID_CERT:
    case UCLIENT_ERROR_SSL_CN_MISMATCH:
        rc = EACCES;
        break;
    default:
        break;
    }
    fetch_done(cl, rc);
}

static const struct uclient_cb fetch_cb = {
    .data_read = data_read_cb,
    .data_eof = data_eof_cb,
    .header_done = header_done_cb,
    .error = error_cb,
};

int aw_http_stream_to_fd(const char *uri, int fd)
{
    struct aw_fetch fetch = { .fd = fd };
    struct uclient *cl = NULL;
    int rc = 0;

    if (!uri || !*uri || fd < 0)
        return EINVAL;

    signal(SIGPIPE, SIG_IGN);
    uloop_init();

    cl = uclient_new(uri, NULL, &fetch_cb);
    if (!cl) {
        rc = ENOMEM;
        goto out;
    }
    cl->priv = &fetch;
    uclient_set_timeout(cl, 30000);

    ssl_ctx = uclient_new_ssl_context(&ssl_ops);
    if (!strncmp(uri, "https://", 8)) {
        if (!ssl_ctx || !ssl_ops) {
            rc = ENOTSUP;
            goto out;
        }
        uclient_http_set_ssl_ctx(cl, ssl_ops, ssl_ctx, false);
    }

    rc = uclient_connect(cl);
    if (rc)
        goto out;

    rc = uclient_http_set_request_type(cl, "GET");
    if (rc)
        goto out;

    uclient_http_reset_headers(cl);
    uclient_http_set_header(cl, "User-Agent", "AudioWRT/1.0");
    uclient_http_set_header(cl, "Connection", "close");

    rc = uclient_request(cl);
    if (rc)
        goto out;

    uloop_run();
    rc = fetch.rc;

out:
    if (cl)
        uclient_free(cl);
    if (ssl_ctx && ssl_ops)
        ssl_ops->context_free(ssl_ctx);
    ssl_ctx = NULL;
    ssl_ops = NULL;
    uloop_done();
    return rc;
}

int aw_pcm_open(snd_pcm_t **pcm, unsigned int rate, unsigned int channels,
                snd_pcm_format_t format)
{
    const char *device = getenv("AUDIOWRT_ALSA_DEVICE");
    int rc;

    if (!device || !*device)
        device = "default";

    rc = snd_pcm_open(pcm, device, SND_PCM_STREAM_PLAYBACK, 0);
    if (rc < 0)
        return rc;

    rc = snd_pcm_set_params(*pcm, format, SND_PCM_ACCESS_RW_INTERLEAVED,
                            channels, rate, 1, 250000);
    if (rc < 0) {
        snd_pcm_close(*pcm);
        *pcm = NULL;
        return rc;
    }
    return 0;
}

int aw_pcm_write(snd_pcm_t *pcm, const void *buffer, snd_pcm_uframes_t frames)
{
    const unsigned char *p = buffer;
    snd_pcm_sframes_t rc;
    snd_pcm_uframes_t left = frames;
    size_t frame_bytes;

    if (!pcm || !buffer)
        return -EINVAL;

    frame_bytes = (size_t)snd_pcm_frames_to_bytes(pcm, 1);
    while (left > 0) {
        rc = snd_pcm_writei(pcm, p, left);
        if (rc == -EPIPE) {
            snd_pcm_prepare(pcm);
            continue;
        }
        if (rc == -ESTRPIPE) {
            while ((rc = snd_pcm_resume(pcm)) == -EAGAIN)
                usleep(10000);
            if (rc < 0)
                snd_pcm_prepare(pcm);
            continue;
        }
        if (rc < 0)
            return (int)rc;
        p += (size_t)rc * frame_bytes;
        left -= (snd_pcm_uframes_t)rc;
    }
    return 0;
}

void aw_pcm_close(snd_pcm_t *pcm)
{
    if (!pcm)
        return;
    snd_pcm_drain(pcm);
    snd_pcm_close(pcm);
}

int aw_volume_percent(void)
{
    const char *path = getenv("AUDIOWRT_VOLUME_FILE");
    const char *env = getenv("AUDIOWRT_VOLUME");
    FILE *f;
    int volume = 100;

    if (path && *path) {
        f = fopen(path, "r");
        if (f) {
            if (fscanf(f, "%d", &volume) != 1)
                volume = 100;
            fclose(f);
        }
    } else if (env && *env) {
        volume = atoi(env);
    }

    if (volume < 0)
        volume = 0;
    if (volume > 100)
        volume = 100;
    return volume;
}

void aw_scale_s16(int16_t *samples, size_t count)
{
    int volume = aw_volume_percent();
    size_t i;
    if (volume >= 100)
        return;
    for (i = 0; i < count; i++)
        samples[i] = (int16_t)(((int32_t)samples[i] * volume) / 100);
}

void aw_scale_s32(int32_t *samples, size_t count)
{
    int volume = aw_volume_percent();
    size_t i;
    if (volume >= 100)
        return;
    for (i = 0; i < count; i++)
        samples[i] = (int32_t)(((int64_t)samples[i] * volume) / 100);
}
