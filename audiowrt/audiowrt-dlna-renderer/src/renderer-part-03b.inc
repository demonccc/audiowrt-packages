        copystr(path, plen, slash);
        *slash = 0;
    } else copystr(path, plen, "/");
    colon = strrchr(p, ':');
    *port = 80;
    if (colon) {
        *colon++ = 0;
        *port = atoi(colon);
    }
    n = strlen(p);
    if (!n || n >= hlen || *port <= 0 || *port > 65535) return -1;
    copystr(host, hlen, p);
    return 0;
}

static void event_body(const char *service, char *body, size_t len)
{
    char protocols[4096], esc[8192];
    if (!strcmp(service, "AVTransport")) {
        snprintf(body, len,
            "<?xml version=\"1.0\"?><e:propertyset xmlns:e=\"urn:schemas-upnp-org:event-1-0\"><e:property><LastChange>&lt;Event xmlns=\"urn:schemas-upnp-org:metadata-1-0/AVT/\"&gt;&lt;InstanceID val=\"0\"&gt;&lt;TransportState val=\"%s\"/&gt;&lt;/InstanceID&gt;&lt;/Event&gt;</LastChange></e:property></e:propertyset>", state_name(g.state));
    } else if (!strcmp(service, "RenderingControl")) {
        snprintf(body, len,
            "<?xml version=\"1.0\"?><e:propertyset xmlns:e=\"urn:schemas-upnp-org:event-1-0\"><e:property><LastChange>&lt;Event xmlns=\"urn:schemas-upnp-org:metadata-1-0/RCS/\"&gt;&lt;InstanceID val=\"0\"&gt;&lt;Volume channel=\"Master\" val=\"%d\"/&gt;&lt;Mute channel=\"Master\" val=\"%d\"/&gt;&lt;/InstanceID&gt;&lt;/Event&gt;</LastChange></e:property></e:propertyset>", g.volume, g.mute ? 1 : 0);
    } else {
        build_protocol_info(protocols, sizeof(protocols));
        xml_escape_buf(protocols, esc, sizeof(esc));
        snprintf(body, len,
            "<?xml version=\"1.0\"?><e:propertyset xmlns:e=\"urn:schemas-upnp-org:event-1-0\"><e:property><SourceProtocolInfo></SourceProtocolInfo></e:property><e:property><SinkProtocolInfo>%s</SinkProtocolInfo></e:property><e:property><CurrentConnectionIDs>0</CurrentConnectionIDs></e:property></e:propertyset>", esc);
    }
}

static int connect_timeout(int fd, const struct sockaddr *addr, socklen_t addrlen, int timeout_ms)
{
    int flags, err = 0;
    socklen_t errlen = sizeof(err);
    struct pollfd pfd = { .fd = fd, .events = POLLOUT };

    flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0)
        return -1;
    if (connect(fd, addr, addrlen) == 0) {
        (void)fcntl(fd, F_SETFL, flags);
        return 0;
    }
    if (errno != EINPROGRESS)
        return -1;
    if (poll(&pfd, 1, timeout_ms) <= 0) {
        errno = ETIMEDOUT;
        return -1;
    }
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &errlen) < 0 || err) {
        if (err) errno = err;
        return -1;
    }
    if (fcntl(fd, F_SETFL, flags) < 0)
        return -1;
    return 0;
}

static int notify_one(struct subscriber *s)
{
    struct addrinfo hints = {0}, *res = NULL;
    char port[16], body[16384], req[20480];
    int fd = -1, rc = -1, n;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_family = AF_UNSPEC;
    snprintf(port, sizeof(port), "%d", s->port);
    if (getaddrinfo(s->host, port, &hints, &res)) return -1;
    fd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (fd < 0) goto out;
    if (connect_timeout(fd, res->ai_addr, res->ai_addrlen, 500) < 0) goto out;
    event_body(s->service, body, sizeof(body));
    n = snprintf(req, sizeof(req),
        "NOTIFY %s HTTP/1.1\r\nHOST: %s:%d\r\nCONTENT-TYPE: text/xml; charset=\"utf-8\"\r\nNT: upnp:event\r\nNTS: upnp:propchange\r\nSID: %s\r\nSEQ: %u\r\nCONTENT-LENGTH: %zu\r\nCONNECTION: close\r\n\r\n%s",
        s->path, s->host, s->port, s->sid, s->seq++, strlen(body), body);
    rc = send_all(fd, req, (size_t)n);
out:
    if (fd >= 0) close(fd);
    if (res) freeaddrinfo(res);
