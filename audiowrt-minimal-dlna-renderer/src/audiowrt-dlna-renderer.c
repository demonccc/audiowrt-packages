#define _GNU_SOURCE
#include <alsa/asoundlib.h>
#include <FLAC/stream_decoder.h>
#include <mad.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <upnp/upnp.h>
#include <upnp/upnptools.h>
#include <upnp/ixml.h>

#define AVT_TYPE "urn:schemas-upnp-org:service:AVTransport:1"
#define AVT_ID   "urn:upnp-org:serviceId:AVTransport"
#define RCS_TYPE "urn:schemas-upnp-org:service:RenderingControl:1"
#define RCS_ID   "urn:upnp-org:serviceId:RenderingControl"
#define CM_TYPE  "urn:schemas-upnp-org:service:ConnectionManager:1"
#define CM_ID    "urn:upnp-org:serviceId:ConnectionManager"
#define SINK_PROTOCOLS "http-get:*:audio/flac:*,http-get:*:audio/x-flac:*,http-get:*:audio/mpeg:*"

struct player {
    pthread_mutex_t lock;
    pthread_cond_t cond;
    pthread_t thread;
    int thread_valid;
    int stop;
    int paused;
    int volume;
    int mute;
    char uri[2048];
    char transport[32];
    uint64_t frames_played;
    unsigned sample_rate;
};

struct stream_ctx {
    void *http;
    char *content_type;
    snd_pcm_t *pcm;
    unsigned rate;
    unsigned channels;
};

static struct player g_player = {
    .lock = PTHREAD_MUTEX_INITIALIZER,
    .cond = PTHREAD_COND_INITIALIZER,
    .volume = 70,
    .transport = "STOPPED",
};
static UpnpDevice_Handle g_device = -1;
static char g_udn[128];
static volatile sig_atomic_t g_quit;

static void on_signal(int sig)
{
    (void)sig;
    g_quit = 1;
}

static char *xml_arg(IXML_Document *doc, const char *name)
{
    IXML_NodeList *list;
    IXML_Node *node, *text;
    const char *value;
    char *out = NULL;

    if (!doc || !name)
        return NULL;
    list = ixmlDocument_getElementsByTagName(doc, name);
    if (!list)
        return NULL;
    node = ixmlNodeList_item(list, 0);
    text = node ? ixmlNode_getFirstChild(node) : NULL;
    value = text ? ixmlNode_getNodeValue(text) : NULL;
    if (value)
        out = strdup(value);
    ixmlNodeList_free(list);
    return out;
}

static void action_error(UpnpActionRequest *req, int code, const char *message)
{
    UpnpActionRequest_set_ErrCode(req, code);
    UpnpActionRequest_strcpy_ErrStr(req, message ? message : "Action failed");
}

static IXML_Document *action_response(const char *action, const char *type)
{
    IXML_Document *doc = NULL;
    if (UpnpAddToActionResponse(&doc, action, type, NULL, NULL) != UPNP_E_SUCCESS)
        return NULL;
    return doc;
}

static int response_add(IXML_Document **doc, const char *action, const char *type,
                        const char *name, const char *value)
{
    return UpnpAddToActionResponse(doc, action, type, name, value);
}

static void finish_action(UpnpActionRequest *req, IXML_Document *doc)
{
    if (!doc) {
        action_error(req, 501, "Action failed");
        return;
    }
    UpnpActionRequest_set_ActionResult(req, doc);
    UpnpActionRequest_set_ErrCode(req, UPNP_E_SUCCESS);
}

static void snapshot(char *state, size_t state_len, char *uri, size_t uri_len,
                     int *volume, int *mute, uint64_t *frames, unsigned *rate)
{
    pthread_mutex_lock(&g_player.lock);
    if (state)
        snprintf(state, state_len, "%s", g_player.transport);
    if (uri)
        snprintf(uri, uri_len, "%s", g_player.uri);
    if (volume)
        *volume = g_player.volume;
    if (mute)
        *mute = g_player.mute;
    if (frames)
        *frames = g_player.frames_played;
    if (rate)
        *rate = g_player.sample_rate;
    pthread_mutex_unlock(&g_player.lock);
}

static void notify_avtransport(void)
{
    char state[32], uri[2048], lastchange[2600];
    const char *names[] = { "LastChange" };
    const char *values[] = { lastchange };

    if (g_device < 0)
        return;
    snapshot(state, sizeof(state), uri, sizeof(uri), NULL, NULL, NULL, NULL);
    snprintf(lastchange, sizeof(lastchange),
             "<Event xmlns=\"urn:schemas-upnp-org:metadata-1-0/AVT/\">"
             "<InstanceID val=\"0\"><TransportState val=\"%s\"/>"
             "<AVTransportURI val=\"%s\"/></InstanceID></Event>", state, uri);
    UpnpNotify(g_device, g_udn, AVT_ID, names, values, 1);
}

static void notify_rendering(void)
{
    char lastchange[512];
    int v, m;
    const char *names[] = { "LastChange" };
    const char *values[] = { lastchange };

    if (g_device < 0)
        return;
    snapshot(NULL, 0, NULL, 0, &v, &m, NULL, NULL);
    snprintf(lastchange, sizeof(lastchange),
             "<Event xmlns=\"urn:schemas-upnp-org:metadata-1-0/RCS/\">"
             "<InstanceID val=\"0\"><Volume channel=\"Master\" val=\"%d\"/>"
             "<Mute channel=\"Master\" val=\"%d\"/></InstanceID></Event>", v, m);
    UpnpNotify(g_device, g_udn, RCS_ID, names, values, 1);
}

static int player_stopped(void)
{
    int stop;
    pthread_mutex_lock(&g_player.lock);
    stop = g_player.stop;
    pthread_mutex_unlock(&g_player.lock);
    return stop;
}

static int player_wait_if_paused(void)
{
    int stop;
    pthread_mutex_lock(&g_player.lock);
    while (g_player.paused && !g_player.stop)
        pthread_cond_wait(&g_player.cond, &g_player.lock);
    stop = g_player.stop;
    pthread_mutex_unlock(&g_player.lock);
    return stop;
}

static void set_transport(const char *state)
{
    pthread_mutex_lock(&g_player.lock);
    snprintf(g_player.transport, sizeof(g_player.transport), "%s", state);
    pthread_mutex_unlock(&g_player.lock);
    notify_avtransport();
}

static int alsa_prepare(struct stream_ctx *ctx, unsigned rate, unsigned channels)
{
    if (ctx->pcm && ctx->rate == rate && ctx->channels == channels)
        return 0;
    if (ctx->pcm) {
        snd_pcm_drop(ctx->pcm);
        snd_pcm_close(ctx->pcm);
        ctx->pcm = NULL;
    }
    if (snd_pcm_open(&ctx->pcm, "default", SND_PCM_STREAM_PLAYBACK, 0) < 0)
        return -1;
    if (snd_pcm_set_params(ctx->pcm, SND_PCM_FORMAT_S16_LE,
                           SND_PCM_ACCESS_RW_INTERLEAVED, channels, rate,
                           1, 300000) < 0) {
        snd_pcm_close(ctx->pcm);
        ctx->pcm = NULL;
        return -1;
    }
    ctx->rate = rate;
    ctx->channels = channels;
    pthread_mutex_lock(&g_player.lock);
    g_player.sample_rate = rate;
    pthread_mutex_unlock(&g_player.lock);
    return 0;
}

static int pcm_write(struct stream_ctx *ctx, int16_t *samples, size_t frames)
{
    size_t off = 0;
    int volume, mute;

    snapshot(NULL, 0, NULL, 0, &volume, &mute, NULL, NULL);
    if (mute)
        volume = 0;
    if (volume < 100) {
        size_t count = frames * ctx->channels;
        size_t i;
        for (i = 0; i < count; ++i)
            samples[i] = (int16_t)((int32_t)samples[i] * volume / 100);
    }
    while (off < frames) {
        snd_pcm_sframes_t n;
        if (player_wait_if_paused())
            return -1;
        n = snd_pcm_writei(ctx->pcm, samples + off * ctx->channels, frames - off);
        if (n < 0) {
            n = snd_pcm_recover(ctx->pcm, (int)n, 1);
            if (n < 0)
                return -1;
            continue;
        }
        off += (size_t)n;
        pthread_mutex_lock(&g_player.lock);
        g_player.frames_played += (uint64_t)n;
        pthread_mutex_unlock(&g_player.lock);
    }
    return 0;
}

static FLAC__StreamDecoderReadStatus flac_read_cb(const FLAC__StreamDecoder *decoder,
                                                   FLAC__byte buffer[], size_t *bytes,
                                                   void *client_data)
{
    struct stream_ctx *ctx = client_data;
    size_t want = *bytes;
    int rc;
    (void)decoder;
    if (player_stopped())
        return FLAC__STREAM_DECODER_READ_STATUS_ABORT;
    rc = UpnpReadHttpGet(ctx->http, (char *)buffer, &want, 5);
    *bytes = want;
    if (rc != UPNP_E_SUCCESS)
        return FLAC__STREAM_DECODER_READ_STATUS_ABORT;
    if (!want)
        return FLAC__STREAM_DECODER_READ_STATUS_END_OF_STREAM;
    return FLAC__STREAM_DECODER_READ_STATUS_CONTINUE;
}

static void flac_meta_cb(const FLAC__StreamDecoder *decoder,
                         const FLAC__StreamMetadata *metadata, void *client_data)
{
    struct stream_ctx *ctx = client_data;
    (void)decoder;
    if (metadata->type != FLAC__METADATA_TYPE_STREAMINFO)
        return;
    if (alsa_prepare(ctx, metadata->data.stream_info.sample_rate,
                     metadata->data.stream_info.channels) == 0)
        set_transport("PLAYING");
}

static FLAC__StreamDecoderWriteStatus flac_write_cb(const FLAC__StreamDecoder *decoder,
                                                      const FLAC__Frame *frame,
                                                      const FLAC__int32 *const buffer[],
                                                      void *client_data)
{
    struct stream_ctx *ctx = client_data;
    size_t frames = frame->header.blocksize;
    unsigned channels = frame->header.channels;
    unsigned bits = frame->header.bits_per_sample;
    int16_t *pcm;
    size_t i;
    unsigned ch;
    int rc;
    (void)decoder;

    if (!ctx->pcm && alsa_prepare(ctx, frame->header.sample_rate, channels) < 0)
        return FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
    pcm = malloc(frames * channels * sizeof(*pcm));
    if (!pcm)
        return FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
    for (i = 0; i < frames; ++i) {
        for (ch = 0; ch < channels; ++ch) {
            int64_t v = buffer[ch][i];
            if (bits > 16)
                v >>= bits - 16;
            else if (bits < 16)
                v <<= 16 - bits;
            if (v > 32767) v = 32767;
            if (v < -32768) v = -32768;
            pcm[i * channels + ch] = (int16_t)v;
        }
    }
    rc = pcm_write(ctx, pcm, frames);
    free(pcm);
    return rc == 0 ? FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE
                   : FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
}

static void flac_error_cb(const FLAC__StreamDecoder *decoder,
                          FLAC__StreamDecoderErrorStatus status, void *client_data)
{
    (void)decoder;
    (void)status;
    (void)client_data;
}

static int play_flac(struct stream_ctx *ctx)
{
    FLAC__StreamDecoder *dec = FLAC__stream_decoder_new();
    FLAC__bool ok;
    if (!dec)
        return -1;
    FLAC__stream_decoder_set_md5_checking(dec, false);
    if (FLAC__stream_decoder_init_stream(dec, flac_read_cb, NULL, NULL, NULL, NULL,
                                          flac_write_cb, flac_meta_cb, flac_error_cb,
                                          ctx) != FLAC__STREAM_DECODER_INIT_STATUS_OK) {
        FLAC__stream_decoder_delete(dec);
        return -1;
    }
    ok = FLAC__stream_decoder_process_until_end_of_stream(dec);
    FLAC__stream_decoder_finish(dec);
    FLAC__stream_decoder_delete(dec);
    return ok ? 0 : -1;
}

static inline int16_t mad_sample(mad_fixed_t sample)
{
    sample += (1L << (MAD_F_FRACBITS - 16));
    if (sample >= MAD_F_ONE) sample = MAD_F_ONE - 1;
    if (sample < -MAD_F_ONE) sample = -MAD_F_ONE;
    return (int16_t)(sample >> (MAD_F_FRACBITS + 1 - 16));
}

static int play_mp3(struct stream_ctx *ctx)
{
    struct mad_stream stream;
    struct mad_frame frame;
    struct mad_synth synth;
    unsigned char input[16384 + MAD_BUFFER_GUARD];
    size_t remaining = 0;
    int eof = 0, rc = -1;

    mad_stream_init(&stream);
    mad_frame_init(&frame);
    mad_synth_init(&synth);

    for (;;) {
        unsigned channels, rate, frames, i;
        int16_t pcm[1152 * 2];
        if (player_stopped())
            break;
        if (!stream.buffer || stream.error == MAD_ERROR_BUFLEN) {
            if (stream.next_frame) {
                remaining = (size_t)(stream.bufend - stream.next_frame);
                memmove(input, stream.next_frame, remaining);
            } else {
                remaining = 0;
            }
            if (!eof) {
                size_t n = sizeof(input) - MAD_BUFFER_GUARD - remaining;
                int hr = UpnpReadHttpGet(ctx->http, (char *)input + remaining, &n, 5);
                if (hr != UPNP_E_SUCCESS)
                    break;
                if (!n) {
                    eof = 1;
                    memset(input + remaining, 0, MAD_BUFFER_GUARD);
                    n = MAD_BUFFER_GUARD;
                }
                mad_stream_buffer(&stream, input, remaining + n);
                stream.error = MAD_ERROR_NONE;
            } else if (remaining == 0) {
                rc = 0;
                break;
            }
        }
        if (mad_frame_decode(&frame, &stream)) {
            if (MAD_RECOVERABLE(stream.error))
                continue;
            if (stream.error == MAD_ERROR_BUFLEN)
                continue;
            break;
        }
        mad_synth_frame(&synth, &frame);
        channels = synth.pcm.channels;
        rate = synth.pcm.samplerate;
        frames = synth.pcm.length;
        if (alsa_prepare(ctx, rate, channels) < 0)
            break;
        set_transport("PLAYING");
        for (i = 0; i < frames; ++i) {
            pcm[i * channels] = mad_sample(synth.pcm.samples[0][i]);
            if (channels == 2)
                pcm[i * channels + 1] = mad_sample(synth.pcm.samples[1][i]);
        }
        if (pcm_write(ctx, pcm, frames) < 0)
            break;
    }

    mad_synth_finish(&synth);
    mad_frame_finish(&frame);
    mad_stream_finish(&stream);
    return rc;
}

static int mime_is(const char *ctype, const char *needle)
{
    return ctype && strcasestr(ctype, needle) != NULL;
}

static void *playback_thread(void *unused)
{
    struct stream_ctx ctx = {0};
    char uri[2048];
    int length = 0, status = 0, rc;
    (void)unused;

    pthread_mutex_lock(&g_player.lock);
    snprintf(uri, sizeof(uri), "%s", g_player.uri);
    g_player.frames_played = 0;
    g_player.sample_rate = 0;
    pthread_mutex_unlock(&g_player.lock);

    set_transport("TRANSITIONING");
    rc = UpnpOpenHttpGet(uri, &ctx.http, &ctx.content_type, &length, &status, 8);
    if (rc != UPNP_E_SUCCESS || status < 200 || status >= 300) {
        set_transport("STOPPED");
        goto out;
    }

    if (mime_is(ctx.content_type, "flac") || strcasestr(uri, ".flac"))
        rc = play_flac(&ctx);
    else if (mime_is(ctx.content_type, "mpeg") || mime_is(ctx.content_type, "mp3") || strcasestr(uri, ".mp3"))
        rc = play_mp3(&ctx);
    else
        rc = -1;

    (void)rc;
    set_transport("STOPPED");
out:
    if (ctx.pcm) {
        snd_pcm_drain(ctx.pcm);
        snd_pcm_close(ctx.pcm);
    }
    if (ctx.http)
        UpnpCloseHttpGet(ctx.http);
    pthread_mutex_lock(&g_player.lock);
    g_player.thread_valid = 0;
    pthread_mutex_unlock(&g_player.lock);
    return NULL;
}

static void player_stop_join(void)
{
    pthread_t t;
    int join = 0;
    pthread_mutex_lock(&g_player.lock);
    if (g_player.thread_valid) {
        g_player.stop = 1;
        g_player.paused = 0;
        pthread_cond_broadcast(&g_player.cond);
        t = g_player.thread;
        join = 1;
    }
    pthread_mutex_unlock(&g_player.lock);
    if (join)
        pthread_join(t, NULL);
    pthread_mutex_lock(&g_player.lock);
    g_player.thread_valid = 0;
    g_player.stop = 0;
    g_player.paused = 0;
    snprintf(g_player.transport, sizeof(g_player.transport), "STOPPED");
    pthread_mutex_unlock(&g_player.lock);
    notify_avtransport();
}

static int player_play(void)
{
    pthread_mutex_lock(&g_player.lock);
    if (g_player.thread_valid) {
        g_player.paused = 0;
        pthread_cond_broadcast(&g_player.cond);
        snprintf(g_player.transport, sizeof(g_player.transport), "PLAYING");
        pthread_mutex_unlock(&g_player.lock);
        notify_avtransport();
        return 0;
    }
    if (!g_player.uri[0]) {
        pthread_mutex_unlock(&g_player.lock);
        return -1;
    }
    g_player.stop = 0;
    g_player.paused = 0;
    if (pthread_create(&g_player.thread, NULL, playback_thread, NULL) != 0) {
        pthread_mutex_unlock(&g_player.lock);
        return -1;
    }
    g_player.thread_valid = 1;
    pthread_mutex_unlock(&g_player.lock);
    return 0;
}

static void player_pause(void)
{
    pthread_mutex_lock(&g_player.lock);
    if (g_player.thread_valid) {
        g_player.paused = 1;
        snprintf(g_player.transport, sizeof(g_player.transport), "PAUSED_PLAYBACK");
    }
    pthread_mutex_unlock(&g_player.lock);
    notify_avtransport();
}

static void format_time(char *out, size_t len, uint64_t frames, unsigned rate)
{
    uint64_t sec = rate ? frames / rate : 0;
    snprintf(out, len, "%02llu:%02llu:%02llu",
             (unsigned long long)(sec / 3600),
             (unsigned long long)((sec / 60) % 60),
             (unsigned long long)(sec % 60));
}

static void handle_avt(UpnpActionRequest *req, const char *action)
{
    IXML_Document *in = UpnpActionRequest_get_ActionRequest(req);
    IXML_Document *out = action_response(action, AVT_TYPE);

    if (!strcmp(action, "SetAVTransportURI")) {
        char *uri = xml_arg(in, "CurrentURI");
        if (!uri || strncmp(uri, "http://", 7)) {
            free(uri);
            if (out) ixmlDocument_free(out);
            action_error(req, 714, "Only HTTP FLAC/MP3 URIs are supported");
            return;
        }
        player_stop_join();
        pthread_mutex_lock(&g_player.lock);
        snprintf(g_player.uri, sizeof(g_player.uri), "%s", uri);
        pthread_mutex_unlock(&g_player.lock);
        free(uri);
        notify_avtransport();
    } else if (!strcmp(action, "Play")) {
        if (player_play() < 0) {
            if (out) ixmlDocument_free(out);
            action_error(req, 701, "No media URI");
            return;
        }
    } else if (!strcmp(action, "Pause")) {
        player_pause();
    } else if (!strcmp(action, "Stop")) {
        player_stop_join();
    } else if (!strcmp(action, "GetTransportInfo")) {
        char state[32];
        snapshot(state, sizeof(state), NULL, 0, NULL, NULL, NULL, NULL);
        response_add(&out, action, AVT_TYPE, "CurrentTransportState", state);
        response_add(&out, action, AVT_TYPE, "CurrentTransportStatus", "OK");
        response_add(&out, action, AVT_TYPE, "CurrentSpeed", "1");
    } else if (!strcmp(action, "GetPositionInfo")) {
        char uri[2048], rel[32];
        uint64_t frames;
        unsigned rate;
        snapshot(NULL, 0, uri, sizeof(uri), NULL, NULL, &frames, &rate);
        format_time(rel, sizeof(rel), frames, rate);
        response_add(&out, action, AVT_TYPE, "Track", "1");
        response_add(&out, action, AVT_TYPE, "TrackDuration", "00:00:00");
        response_add(&out, action, AVT_TYPE, "TrackMetaData", "");
        response_add(&out, action, AVT_TYPE, "TrackURI", uri);
        response_add(&out, action, AVT_TYPE, "RelTime", rel);
        response_add(&out, action, AVT_TYPE, "AbsTime", rel);
        response_add(&out, action, AVT_TYPE, "RelCount", "2147483647");
        response_add(&out, action, AVT_TYPE, "AbsCount", "2147483647");
    } else if (!strcmp(action, "GetMediaInfo")) {
        char uri[2048];
        snapshot(NULL, 0, uri, sizeof(uri), NULL, NULL, NULL, NULL);
        response_add(&out, action, AVT_TYPE, "NrTracks", uri[0] ? "1" : "0");
        response_add(&out, action, AVT_TYPE, "MediaDuration", "00:00:00");
        response_add(&out, action, AVT_TYPE, "CurrentURI", uri);
        response_add(&out, action, AVT_TYPE, "CurrentURIMetaData", "");
        response_add(&out, action, AVT_TYPE, "NextURI", "");
        response_add(&out, action, AVT_TYPE, "NextURIMetaData", "");
        response_add(&out, action, AVT_TYPE, "PlayMedium", "NETWORK");
        response_add(&out, action, AVT_TYPE, "RecordMedium", "NOT_IMPLEMENTED");
        response_add(&out, action, AVT_TYPE, "WriteStatus", "NOT_WRITABLE");
    } else if (!strcmp(action, "GetDeviceCapabilities")) {
        response_add(&out, action, AVT_TYPE, "PlayMedia", "NETWORK");
        response_add(&out, action, AVT_TYPE, "RecMedia", "NOT_IMPLEMENTED");
        response_add(&out, action, AVT_TYPE, "RecQualityModes", "NOT_IMPLEMENTED");
    } else if (!strcmp(action, "GetTransportSettings")) {
        response_add(&out, action, AVT_TYPE, "PlayMode", "NORMAL");
        response_add(&out, action, AVT_TYPE, "RecQualityMode", "NOT_IMPLEMENTED");
    } else {
        if (out) ixmlDocument_free(out);
        action_error(req, 401, "Invalid Action");
        return;
    }
    finish_action(req, out);
}

static void handle_rcs(UpnpActionRequest *req, const char *action)
{
    IXML_Document *in = UpnpActionRequest_get_ActionRequest(req);
    IXML_Document *out = action_response(action, RCS_TYPE);
    if (!strcmp(action, "GetVolume")) {
        int v;
        char buf[8];
        snapshot(NULL, 0, NULL, 0, &v, NULL, NULL, NULL);
        snprintf(buf, sizeof(buf), "%d", v);
        response_add(&out, action, RCS_TYPE, "CurrentVolume", buf);
    } else if (!strcmp(action, "SetVolume")) {
        char *value = xml_arg(in, "DesiredVolume");
        int v = value ? atoi(value) : -1;
        free(value);
        if (v < 0 || v > 100) {
            if (out) ixmlDocument_free(out);
            action_error(req, 601, "Invalid volume");
            return;
        }
        pthread_mutex_lock(&g_player.lock);
        g_player.volume = v;
        pthread_mutex_unlock(&g_player.lock);
        notify_rendering();
    } else if (!strcmp(action, "GetMute")) {
        int m;
        snapshot(NULL, 0, NULL, 0, NULL, &m, NULL, NULL);
        response_add(&out, action, RCS_TYPE, "CurrentMute", m ? "1" : "0");
    } else if (!strcmp(action, "SetMute")) {
        char *value = xml_arg(in, "DesiredMute");
        int m = value ? atoi(value) : 0;
        free(value);
        pthread_mutex_lock(&g_player.lock);
        g_player.mute = !!m;
        pthread_mutex_unlock(&g_player.lock);
        notify_rendering();
    } else {
        if (out) ixmlDocument_free(out);
        action_error(req, 401, "Invalid Action");
        return;
    }
    finish_action(req, out);
}

static void handle_cm(UpnpActionRequest *req, const char *action)
{
    IXML_Document *out = action_response(action, CM_TYPE);
    if (!strcmp(action, "GetProtocolInfo")) {
        response_add(&out, action, CM_TYPE, "Source", "");
        response_add(&out, action, CM_TYPE, "Sink", SINK_PROTOCOLS);
    } else if (!strcmp(action, "GetCurrentConnectionIDs")) {
        response_add(&out, action, CM_TYPE, "ConnectionIDs", "0");
    } else if (!strcmp(action, "GetCurrentConnectionInfo")) {
        response_add(&out, action, CM_TYPE, "RcsID", "0");
        response_add(&out, action, CM_TYPE, "AVTransportID", "0");
        response_add(&out, action, CM_TYPE, "ProtocolInfo", SINK_PROTOCOLS);
        response_add(&out, action, CM_TYPE, "PeerConnectionManager", "");
        response_add(&out, action, CM_TYPE, "PeerConnectionID", "-1");
        response_add(&out, action, CM_TYPE, "Direction", "Input");
        response_add(&out, action, CM_TYPE, "Status", "OK");
    } else {
        if (out) ixmlDocument_free(out);
        action_error(req, 401, "Invalid Action");
        return;
    }
    finish_action(req, out);
}

static void handle_action(UpnpActionRequest *req)
{
    const char *service = UpnpActionRequest_get_ServiceID_cstr(req);
    const char *action = UpnpActionRequest_get_ActionName_cstr(req);
    UpnpActionRequest_set_ActionResult(req, NULL);
    UpnpActionRequest_set_ErrCode(req, 0);
    if (!service || !action) {
        action_error(req, 401, "Invalid Action");
        return;
    }
    if (!strcmp(service, AVT_ID))
        handle_avt(req, action);
    else if (!strcmp(service, RCS_ID))
        handle_rcs(req, action);
    else if (!strcmp(service, CM_ID))
        handle_cm(req, action);
    else
        action_error(req, 401, "Invalid Action");
}

static void handle_subscription(const UpnpSubscriptionRequest *event)
{
    const char *service = UpnpString_get_String(UpnpSubscriptionRequest_get_ServiceId(event));
    const char *udn = UpnpSubscriptionRequest_get_UDN_cstr(event);
    const char *sid = UpnpSubscriptionRequest_get_SID_cstr(event);
    if (!service || !udn || !sid || strcmp(udn, g_udn))
        return;

    if (!strcmp(service, AVT_ID)) {
        char state[32], uri[2048], lc[2600];
        const char *names[] = { "LastChange" };
        const char *values[] = { lc };
        snapshot(state, sizeof(state), uri, sizeof(uri), NULL, NULL, NULL, NULL);
        snprintf(lc, sizeof(lc),
                 "<Event xmlns=\"urn:schemas-upnp-org:metadata-1-0/AVT/\"><InstanceID val=\"0\"><TransportState val=\"%s\"/><AVTransportURI val=\"%s\"/></InstanceID></Event>",
                 state, uri);
        UpnpAcceptSubscription(g_device, udn, service, names, values, 1, sid);
    } else if (!strcmp(service, RCS_ID)) {
        int v, m;
        char lc[512];
        const char *names[] = { "LastChange" };
        const char *values[] = { lc };
        snapshot(NULL, 0, NULL, 0, &v, &m, NULL, NULL);
        snprintf(lc, sizeof(lc),
                 "<Event xmlns=\"urn:schemas-upnp-org:metadata-1-0/RCS/\"><InstanceID val=\"0\"><Volume channel=\"Master\" val=\"%d\"/><Mute channel=\"Master\" val=\"%d\"/></InstanceID></Event>",
                 v, m);
        UpnpAcceptSubscription(g_device, udn, service, names, values, 1, sid);
    } else if (!strcmp(service, CM_ID)) {
        const char *names[] = { "SourceProtocolInfo", "SinkProtocolInfo", "CurrentConnectionIDs" };
        const char *values[] = { "", SINK_PROTOCOLS, "0" };
        UpnpAcceptSubscription(g_device, udn, service, names, values, 3, sid);
    }
}

static int upnp_callback(Upnp_EventType type, const void *event, void *cookie)
{
    (void)cookie;
    switch (type) {
    case UPNP_CONTROL_ACTION_REQUEST:
        handle_action((UpnpActionRequest *)event);
        break;
    case UPNP_EVENT_SUBSCRIPTION_REQUEST:
        handle_subscription((const UpnpSubscriptionRequest *)event);
        break;
    default:
        break;
    }
    return 0;
}

int main(int argc, char **argv)
{
    int rc;
    if (argc != 4) {
        fprintf(stderr, "usage: %s WEBROOT DESCRIPTION_XML UDN\n", argv[0]);
        return 2;
    }
    snprintf(g_udn, sizeof(g_udn), "%s", argv[3]);
    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);

    rc = UpnpInit2(NULL, 0);
    if (rc != UPNP_E_SUCCESS) {
        fprintf(stderr, "UpnpInit2: %s\n", UpnpGetErrorMessage(rc));
        return 1;
    }
    rc = UpnpSetWebServerRootDir(argv[1]);
    if (rc != UPNP_E_SUCCESS) {
        fprintf(stderr, "UpnpSetWebServerRootDir: %s\n", UpnpGetErrorMessage(rc));
        UpnpFinish();
        return 1;
    }
    rc = UpnpRegisterRootDevice2(UPNPREG_FILENAME_DESC, argv[2], 0, 1,
                                 upnp_callback, NULL, &g_device);
    if (rc != UPNP_E_SUCCESS) {
        fprintf(stderr, "UpnpRegisterRootDevice2: %s\n", UpnpGetErrorMessage(rc));
        UpnpFinish();
        return 1;
    }
    rc = UpnpSendAdvertisement(g_device, 1800);
    if (rc != UPNP_E_SUCCESS) {
        fprintf(stderr, "UpnpSendAdvertisement: %s\n", UpnpGetErrorMessage(rc));
        UpnpUnRegisterRootDevice(g_device);
        UpnpFinish();
        return 1;
    }

    while (!g_quit)
        sleep(1);

    player_stop_join();
    UpnpUnRegisterRootDevice(g_device);
    g_device = -1;
    UpnpFinish();
    return 0;
}
