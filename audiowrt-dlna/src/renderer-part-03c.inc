    return rc;
}

static void notify_service(const char *service)
{
    size_t i;
    time_t now = time(NULL);
    for (i = 0; i < MAX_SUBSCRIBERS; i++) {
        if (!g.subscribers[i].used) continue;
        if (g.subscribers[i].expires < now) { g.subscribers[i].used = false; continue; }
        if (!strcmp(g.subscribers[i].service, service))
            notify_one(&g.subscribers[i]);
    }
}

static void handle_subscribe(int fd, const char *req, const char *service)
{
    char sid[128], callback[512], extra[256];
    size_t i;
    if (header_value(req, "SID", sid, sizeof(sid))) {
        for (i = 0; i < MAX_SUBSCRIBERS; i++) {
            if (g.subscribers[i].used && !strcmp(g.subscribers[i].sid, sid)) {
                g.subscribers[i].expires = time(NULL) + 1800;
                snprintf(extra, sizeof(extra), "SID: %s\r\nTIMEOUT: Second-1800\r\n", sid);
                http_reply(fd, 200, "text/plain", extra, "");
                return;
            }
        }
        http_reply(fd, 404, "text/plain", NULL, "");
        return;
    }
    if (!header_value(req, "CALLBACK", callback, sizeof(callback))) {
        http_reply(fd, 500, "text/plain", NULL, "");
        return;
    }
    for (i = 0; i < MAX_SUBSCRIBERS; i++) if (!g.subscribers[i].used) break;
    if (i == MAX_SUBSCRIBERS) { http_reply(fd, 500, "text/plain", NULL, ""); return; }
    memset(&g.subscribers[i], 0, sizeof(g.subscribers[i]));
    if (parse_callback(callback, g.subscribers[i].host, sizeof(g.subscribers[i].host),
                       &g.subscribers[i].port, g.subscribers[i].path, sizeof(g.subscribers[i].path)) < 0) {
        http_reply(fd, 500, "text/plain", NULL, ""); return;
    }
    g.subscribers[i].used = true;
    copystr(g.subscribers[i].service, sizeof(g.subscribers[i].service), service);
    snprintf(g.subscribers[i].sid, sizeof(g.subscribers[i].sid), "uuid:audiowrt-%ld-%zu", (long)getpid(), i);
    g.subscribers[i].expires = time(NULL) + 1800;
    snprintf(extra, sizeof(extra), "SID: %s\r\nTIMEOUT: Second-1800\r\n", g.subscribers[i].sid);
    http_reply(fd, 200, "text/plain", extra, "");
    notify_one(&g.subscribers[i]);
}

static void handle_unsubscribe(int fd, const char *req)
{
    char sid[128];
    size_t i;
    if (header_value(req, "SID", sid, sizeof(sid))) {
        for (i = 0; i < MAX_SUBSCRIBERS; i++)
            if (g.subscribers[i].used && !strcmp(g.subscribers[i].sid, sid))
                g.subscribers[i].used = false;
    }
    http_reply(fd, 200, "text/plain", NULL, "");
}

static int read_http_request(int fd, char *buf, size_t len)
{
    size_t used = 0, need = 0;
    struct timeval tv = { .tv_sec = 3, .tv_usec = 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    while (used + 1 < len) {
        ssize_t n = recv(fd, buf + used, len - used - 1, 0);
        char *header_end;
        if (n == 0) break;
        if (n < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        used += (size_t)n;
        buf[used] = 0;
        header_end = strstr(buf, "\r\n\r\n");
        if (header_end) {
