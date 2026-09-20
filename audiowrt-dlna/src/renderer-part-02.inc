        case '&': r = "&amp;"; break;
        case '<': r = "&lt;"; break;
        case '>': r = "&gt;"; break;
        case '"': r = "&quot;"; break;
        case '\'': r = "&apos;"; break;
        default: dst[used++] = *s++; continue;
        }
        if (used + strlen(r) >= len)
            break;
        memcpy(dst + used, r, strlen(r));
        used += strlen(r);
        s++;
    }
    dst[used] = 0;
}

static void xml_unescape(char *s)
{
    struct repl { const char *from; const char *to; } repls[] = {
        {"&amp;", "&"}, {"&lt;", "<"}, {"&gt;", ">"},
        {"&quot;", "\""}, {"&apos;", "'"}, {NULL, NULL}
    };
    int i;
    for (i = 0; repls[i].from; i++) {
        char *p;
        while ((p = strstr(s, repls[i].from))) {
            size_t a = strlen(repls[i].from), b = strlen(repls[i].to);
            memcpy(p, repls[i].to, b);
            memmove(p + b, p + a, strlen(p + a) + 1);
        }
    }
}

static int xml_value(const char *body, const char *tag, char *out, size_t len)
{
    const char *p = body;
    size_t taglen = strlen(tag);
    while ((p = strstr(p, tag))) {
        if ((p > body && (p[-1] == '<' || p[-1] == ':')) &&
            (p[taglen] == '>' || isspace((unsigned char)p[taglen]))) {
            const char *start = strchr(p + taglen, '>');
            const char *end;
            size_t n;
            if (!start) return -1;
            start++;
            end = strchr(start, '<');
            if (!end) return -1;
            n = (size_t)(end - start);
            if (n >= len) n = len - 1;
            memcpy(out, start, n);
            out[n] = 0;
            xml_unescape(out);
            return 0;
        }
        p += taglen;
    }
    if (len) out[0] = 0;
    return -1;
}

static const char *header_value(const char *req, const char *name, char *out, size_t len)
{
    const char *p = req;
    size_t namelen = strlen(name);
    while (*p) {
        const char *eol = strstr(p, "\r\n");
        const char *v;
        size_t n;
        if (!eol) break;
        if (eol == p) break;
        if ((size_t)(eol - p) > namelen && !strncasecmp(p, name, namelen) && p[namelen] == ':') {
            v = p + namelen + 1;
            while (v < eol && isspace((unsigned char)*v)) v++;
            n = (size_t)(eol - v);
            if (n >= len) n = len - 1;
            memcpy(out, v, n);
            out[n] = 0;
            trim(out);
            return out;
        }
        p = eol + 2;
    }
    if (len) out[0] = 0;
    return NULL;
}

static int send_all(int fd, const char *buf, size_t len)
{
    while (len) {
        ssize_t n = send(fd, buf, len, MSG_NOSIGNAL);
        if (n < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        buf += n;
        len -= (size_t)n;
    }
    return 0;
}

static void http_reply(int fd, int code, const char *type, const char *extra, const char *body)
{
    char header[2048];
    const char *msg = code == 200 ? "OK" : code == 404 ? "Not Found" : "Error";
    size_t bodylen = body ? strlen(body) : 0;
    int n = snprintf(header, sizeof(header),
        "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %zu\r\n"
        "Connection: close\r\n%s\r\n",
        code, msg, type ? type : "text/plain", bodylen, extra ? extra : "");
    send_all(fd, header, (size_t)n);
    if (bodylen) send_all(fd, body, bodylen);
}

static void soap_response(int fd, const char *service, const char *action, const char *inner)
{
    char body[32768];
    snprintf(body, sizeof(body),
        "<?xml version=\"1.0\"?>"
        "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">"
        "<s:Body><u:%sResponse xmlns:u=\"urn:schemas-upnp-org:service:%s:1\">%s</u:%sResponse></s:Body></s:Envelope>",
        action, service, inner ? inner : "", action);
    http_reply(fd, 200, "text/xml; charset=\"utf-8\"", "EXT:\r\n", body);
}

static void soap_fault(int fd, int error_code, const char *description)
{
    char body[4096];
    snprintf(body, sizeof(body),
        "<?xml version=\"1.0\"?>"
        "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">"
        "<s:Body><s:Fault><faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring>"
        "<detail><UPnPError xmlns=\"urn:schemas-upnp-org:control-1-0\"><errorCode>%d</errorCode>"
        "<errorDescription>%s</errorDescription></UPnPError></detail></s:Fault></s:Body></s:Envelope>",
        error_code, description ? description : "Action Failed");
    http_reply(fd, 500, "text/xml; charset=\"utf-8\"", "EXT:\r\n", body);
}

static void build_protocol_info(char *out, size_t len)
{
    size_t i;
    out[0] = 0;
    for (i = 0; i < g.codec_count; i++) {
        struct codec *codec = &g.codecs[i];
        char copy[384], *save = NULL, *tok;

        if (!effective_player(codec))
            continue;
        copystr(copy, sizeof(copy), codec->mime);
        for (tok = strtok_r(copy, " ,\t", &save); tok;
             tok = strtok_r(NULL, " ,\t", &save)) {
            char item[512];
            snprintf(item, sizeof(item), "%shttp-get:*:%s:*",
                     out[0] ? "," : "", tok);
            if (strlen(out) + strlen(item) + 1 < len)
                strcat(out, item);
        }
    }
}

static void set_controller(const struct sockaddr_storage *peer)
{
    const void *addr = NULL;
    if (peer->ss_family == AF_INET)
        addr = &((const struct sockaddr_in *)peer)->sin_addr;
    else if (peer->ss_family == AF_INET6)
        addr = &((const struct sockaddr_in6 *)peer)->sin6_addr;
    if (addr)
        inet_ntop(peer->ss_family, addr, g.controller, sizeof(g.controller));
}

static int handle_avtransport(int fd, const char *action, const char *body)
{
    char tmp[24576], timebuf[32];
    if (!strcmp(action, "SetAVTransportURI")) {
        struct codec *codec;
        char uri[2048], meta[8192];
        if (xml_value(body, "CurrentURI", uri, sizeof(uri)) < 0 || !uri[0]) {
            soap_fault(fd, 714, "Illegal MIME-type");
            return 0;
        }
        xml_value(body, "CurrentURIMetaData", meta, sizeof(meta));
        codec = player_for_uri(uri, meta);
        if (!codec) {
            soap_fault(fd, 714, "Unsupported media");
            return 0;
        }
        stop_current(true);
        copystr(g.uri, sizeof(g.uri), uri);
        copystr(g.metadata, sizeof(g.metadata), meta);
        copystr(g.codec, sizeof(g.codec), codec->id);
        g.state = STATE_STOPPED;
        write_status();
        soap_response(fd, "AVTransport", action, "");
    } else if (!strcmp(action, "Play")) {
        if (start_current() < 0) soap_fault(fd, 701, "Transition not available");
        else soap_response(fd, "AVTransport", action, "");
    } else if (!strcmp(action, "Pause")) {
        if (pause_current() < 0) soap_fault(fd, 701, "Transition not available");
        else soap_response(fd, "AVTransport", action, "");
    } else if (!strcmp(action, "Stop")) {
        stop_current(true);
        soap_response(fd, "AVTransport", action, "");
    } else if (!strcmp(action, "GetTransportInfo")) {
        snprintf(tmp, sizeof(tmp), "<CurrentTransportState>%s</CurrentTransportState><CurrentTransportStatus>OK</CurrentTransportStatus><CurrentSpeed>1</CurrentSpeed>", state_name(g.state));
        soap_response(fd, "AVTransport", action, tmp);
    } else if (!strcmp(action, "GetPositionInfo")) {
        char uri_esc[4096], meta_esc[12000];
        xml_escape_buf(g.uri, uri_esc, sizeof(uri_esc));
        xml_escape_buf(g.metadata, meta_esc, sizeof(meta_esc));
        format_time(current_position(), timebuf, sizeof(timebuf));
        snprintf(tmp, sizeof(tmp), "<Track>1</Track><TrackDuration>00:00:00</TrackDuration><TrackMetaData>%s</TrackMetaData><TrackURI>%s</TrackURI><RelTime>%s</RelTime><AbsTime>%s</AbsTime><RelCount>2147483647</RelCount><AbsCount>2147483647</AbsCount>", meta_esc, uri_esc, timebuf, timebuf);
        soap_response(fd, "AVTransport", action, tmp);
    } else if (!strcmp(action, "GetMediaInfo")) {
        char uri_esc[4096], meta_esc[12000];
        xml_escape_buf(g.uri, uri_esc, sizeof(uri_esc));
        xml_escape_buf(g.metadata, meta_esc, sizeof(meta_esc));
        snprintf(tmp, sizeof(tmp), "<NrTracks>%d</NrTracks><MediaDuration>00:00:00</MediaDuration><CurrentURI>%s</CurrentURI><CurrentURIMetaData>%s</CurrentURIMetaData><NextURI></NextURI><NextURIMetaData></NextURIMetaData><PlayMedium>NETWORK</PlayMedium><RecordMedium>NOT_IMPLEMENTED</RecordMedium><WriteStatus>NOT_IMPLEMENTED</WriteStatus>", g.uri[0] ? 1 : 0, uri_esc, meta_esc);
        soap_response(fd, "AVTransport", action, tmp);
    } else if (!strcmp(action, "GetDeviceCapabilities")) {
        soap_response(fd, "AVTransport", action, "<PlayMedia>NETWORK</PlayMedia><RecMedia>NOT_IMPLEMENTED</RecMedia><RecQualityModes>NOT_IMPLEMENTED</RecQualityModes>");
    } else if (!strcmp(action, "GetTransportSettings")) {
        soap_response(fd, "AVTransport", action, "<PlayMode>NORMAL</PlayMode><RecQualityMode>NOT_IMPLEMENTED</RecQualityMode>");
    } else if (!strcmp(action, "SetPlayMode")) {
        soap_response(fd, "AVTransport", action, "");
    } else if (!strcmp(action, "GetCurrentTransportActions")) {
        const char *a = g.state == STATE_PLAYING ? "Stop,Pause" : g.state == STATE_PAUSED ? "Play,Stop" : g.uri[0] ? "Play" : "";
        snprintf(tmp, sizeof(tmp), "<Actions>%s</Actions>", a);
        soap_response(fd, "AVTransport", action, tmp);
    } else if (!strcmp(action, "Seek")) {
        soap_fault(fd, 710, "Seek mode not supported");
    } else {
        soap_fault(fd, 401, "Invalid Action");
    }
    return 0;
}

static int handle_rendering(int fd, const char *action, const char *body)
{
    char tmp[512], v[64];
    if (!strcmp(action, "GetVolume")) {
        snprintf(tmp, sizeof(tmp), "<CurrentVolume>%d</CurrentVolume>", g.volume);
        soap_response(fd, "RenderingControl", action, tmp);
    } else if (!strcmp(action, "SetVolume")) {
        int volume;
        if (xml_value(body, "DesiredVolume", v, sizeof(v)) < 0) {
            soap_fault(fd, 402, "Invalid Args"); return 0;
        }
        volume = atoi(v);
        if (volume < 0) volume = 0;
        if (volume > 100) volume = 100;
        g.volume = volume;
        write_status();
        soap_response(fd, "RenderingControl", action, "");
    } else if (!strcmp(action, "GetMute")) {
        snprintf(tmp, sizeof(tmp), "<CurrentMute>%d</CurrentMute>", g.mute ? 1 : 0);
        soap_response(fd, "RenderingControl", action, tmp);
    } else if (!strcmp(action, "SetMute")) {
        if (xml_value(body, "DesiredMute", v, sizeof(v)) < 0) {
            soap_fault(fd, 402, "Invalid Args"); return 0;
        }
        g.mute = parse_bool(v, 0);
        write_status();
        soap_response(fd, "RenderingControl", action, "");
    } else if (!strcmp(action, "ListPresets")) {
        soap_response(fd, "RenderingControl", action, "<CurrentPresetNameList>FactoryDefaults</CurrentPresetNameList>");
    } else if (!strcmp(action, "SelectPreset")) {
        soap_response(fd, "RenderingControl", action, "");
    } else {
        soap_fault(fd, 401, "Invalid Action");
    }
    return 0;
}

static int handle_connection(int fd, const char *action)
{
    char protocols[4096], escaped[8192], tmp[10000];
    build_protocol_info(protocols, sizeof(protocols));
    xml_escape_buf(protocols, escaped, sizeof(escaped));
    if (!strcmp(action, "GetProtocolInfo")) {
        snprintf(tmp, sizeof(tmp), "<Source></Source><Sink>%s</Sink>", escaped);
        soap_response(fd, "ConnectionManager", action, tmp);
    } else if (!strcmp(action, "GetCurrentConnectionIDs")) {
        soap_response(fd, "ConnectionManager", action, "<ConnectionIDs>0</ConnectionIDs>");
    } else if (!strcmp(action, "GetCurrentConnectionInfo")) {
        snprintf(tmp, sizeof(tmp), "<RcsID>0</RcsID><AVTransportID>0</AVTransportID><ProtocolInfo></ProtocolInfo><PeerConnectionManager></PeerConnectionManager><PeerConnectionID>-1</PeerConnectionID><Direction>Input</Direction><Status>OK</Status>");
        soap_response(fd, "ConnectionManager", action, tmp);
    } else {
        soap_fault(fd, 401, "Invalid Action");
    }
    return 0;
}

static const char *device_description(void)
{
    static char xml[16384];
    char friendly[768];
    xml_escape_buf(g.friendly_name, friendly, sizeof(friendly));
    snprintf(xml, sizeof(xml),
        "<?xml version=\"1.0\"?>"
        "<root xmlns=\"urn:schemas-upnp-org:device-1-0\"><specVersion><major>1</major><minor>0</minor></specVersion>"
        "<device><deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>"
        "<friendlyName>%s</friendlyName><manufacturer>AudioWRT</manufacturer><manufacturerURL>https://github.com/demonccc/audiowrt</manufacturerURL>"
        "<modelDescription>AudioWRT native modular DLNA renderer</modelDescription><modelName>AudioWRT Renderer</modelName><modelNumber>1</modelNumber>"
        "<UDN>uuid:%s</UDN><serviceList>"
        "<service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType><serviceId>urn:upnp-org:serviceId:AVTransport</serviceId><SCPDURL>/avtransport.xml</SCPDURL><controlURL>/control/AVTransport</controlURL><eventSubURL>/event/AVTransport</eventSubURL></service>"
        "<service><serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType><serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId><SCPDURL>/renderingcontrol.xml</SCPDURL><controlURL>/control/RenderingControl</controlURL><eventSubURL>/event/RenderingControl</eventSubURL></service>"
