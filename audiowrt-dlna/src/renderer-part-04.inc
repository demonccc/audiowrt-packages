static int primary_ipv4(char *out, size_t len)
{
    struct ifaddrs *ifas = NULL, *ifa;
    if (getifaddrs(&ifas) < 0) return -1;
    for (ifa = ifas; ifa; ifa = ifa->ifa_next) {
        struct sockaddr_in *sin;
        uint32_t a;
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET) continue;
        if (ifa->ifa_flags & 0x8) continue; /* IFF_LOOPBACK */
        sin = (struct sockaddr_in *)ifa->ifa_addr;
        a = ntohl(sin->sin_addr.s_addr);
        if ((a >> 24) == 127 || !a) continue;
        if (inet_ntop(AF_INET, &sin->sin_addr, out, len)) { freeifaddrs(ifas); return 0; }
    }
    freeifaddrs(ifas);
    return -1;
}

static int local_ip_for_peer(const struct sockaddr_in *peer, char *out, size_t len)
{
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in local;
    socklen_t slen = sizeof(local);
    if (fd >= 0) {
        if (!connect(fd, (const struct sockaddr *)peer, sizeof(*peer)) &&
            !getsockname(fd, (struct sockaddr *)&local, &slen) &&
            inet_ntop(AF_INET, &local.sin_addr, out, len)) {
            close(fd); return 0;
        }
        close(fd);
    }
    return primary_ipv4(out, len);
}

static const char *ssdp_targets[] = {
    "upnp:rootdevice",
    "urn:schemas-upnp-org:device:MediaRenderer:1",
    "urn:schemas-upnp-org:service:AVTransport:1",
    "urn:schemas-upnp-org:service:RenderingControl:1",
    "urn:schemas-upnp-org:service:ConnectionManager:1",
    NULL
};

static void make_usn(const char *target, char *out, size_t len)
{
    if (!strncmp(target, "uuid:", 5))
        copystr(out, len, target);
    else
        snprintf(out, len, "uuid:%s::%s", g.uuid, target);
}

static void ssdp_reply_one(int fd, const struct sockaddr_in *peer, const char *st)
{
    char ip[INET_ADDRSTRLEN] = "127.0.0.1", usn[512], msg[2048];
    local_ip_for_peer(peer, ip, sizeof(ip));
    make_usn(st, usn, sizeof(usn));
    snprintf(msg, sizeof(msg),
        "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nEXT:\r\nLOCATION: http://%s:%d/description.xml\r\nSERVER: OpenWrt UPnP/1.0 AudioWRT/1.0\r\nST: %s\r\nUSN: %s\r\n\r\n",
        ip, g.port, st, usn);
    sendto(fd, msg, strlen(msg), 0, (const struct sockaddr *)peer, sizeof(*peer));
}

static void handle_ssdp(int fd)
{
    char buf[4096], st[512];
    struct sockaddr_in peer;
    socklen_t plen = sizeof(peer);
    ssize_t n = recvfrom(fd, buf, sizeof(buf) - 1, 0, (struct sockaddr *)&peer, &plen);
    size_t i;
    if (n <= 0) return;
    buf[n] = 0;
    if (strncasecmp(buf, "M-SEARCH", 8) || !strcasestr(buf, "ssdp:discover")) return;
    if (!header_value(buf, "ST", st, sizeof(st))) return;
    if (!strcasecmp(st, "ssdp:all")) {
        char uuidst[128];
        ssdp_reply_one(fd, &peer, "upnp:rootdevice");
        snprintf(uuidst, sizeof(uuidst), "uuid:%s", g.uuid);
        ssdp_reply_one(fd, &peer, uuidst);
        for (i = 1; ssdp_targets[i]; i++) ssdp_reply_one(fd, &peer, ssdp_targets[i]);
    } else if (!strcasecmp(st, "upnp:rootdevice")) {
        ssdp_reply_one(fd, &peer, st);
    } else if (!strncasecmp(st, "uuid:", 5)) {
        char uuidst[128]; snprintf(uuidst, sizeof(uuidst), "uuid:%s", g.uuid);
        if (!strcasecmp(st, uuidst)) ssdp_reply_one(fd, &peer, st);
    } else {
        for (i = 1; ssdp_targets[i]; i++) if (!strcasecmp(st, ssdp_targets[i])) ssdp_reply_one(fd, &peer, st);
    }
}

static void ssdp_notify(int fd, const char *nts)
{
    struct sockaddr_in dest = {0};
    char ip[INET_ADDRSTRLEN] = "127.0.0.1", uuidst[128], usn[512], msg[2048];
    size_t i;
    primary_ipv4(ip, sizeof(ip));
    dest.sin_family = AF_INET;
    dest.sin_port = htons(SSDP_PORT);
    inet_pton(AF_INET, SSDP_ADDR, &dest.sin_addr);

    snprintf(uuidst, sizeof(uuidst), "uuid:%s", g.uuid);
    for (i = 0; i < 7; i++) {
        const char *nt;
        if (i == 0) nt = "upnp:rootdevice";
        else if (i == 1) nt = uuidst;
        else nt = ssdp_targets[i - 1];
        if (!nt) break;
        make_usn(nt, usn, sizeof(usn));
        snprintf(msg, sizeof(msg),
            "NOTIFY * HTTP/1.1\r\nHOST: %s:%d\r\nCACHE-CONTROL: max-age=1800\r\nLOCATION: http://%s:%d/description.xml\r\nNT: %s\r\nNTS: %s\r\nSERVER: OpenWrt UPnP/1.0 AudioWRT/1.0\r\nUSN: %s\r\n\r\n",
            SSDP_ADDR, SSDP_PORT, ip, g.port, nt, nts, usn);
        sendto(fd, msg, strlen(msg), 0, (struct sockaddr *)&dest, sizeof(dest));
    }
}

static int open_ssdp(void)
{
    int fd, yes = 1;
    struct sockaddr_in addr = {0};
    struct ip_mreq mreq;
    fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return -1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(SSDP_PORT);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) { close(fd); return -1; }
    inet_pton(AF_INET, SSDP_ADDR, &mreq.imr_multiaddr);
    mreq.imr_interface.s_addr = htonl(INADDR_ANY);
    if (setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, sizeof(mreq)) < 0) {
        close(fd); return -1;
    }
    return fd;
}

static int open_http(void)
{
    int fd, yes = 1;
    struct sockaddr_in addr = {0};
    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)g.port);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 || listen(fd, 8) < 0) {
        close(fd); return -1;
    }
    return fd;
}

static void signal_handler(int sig)
{
    (void)sig;
    running = 0;
}

static int daemon_main(void)
{
    int sfd, hfd, mfd;
    struct pollfd fds[3];
    time_t next_alive, next_mdns;

    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    signal(SIGPIPE, SIG_IGN);

    write_status();
    sfd = open_ssdp();
    hfd = open_http();
    mfd = open_mdns();
    if (sfd < 0 || hfd < 0 || mfd < 0) {
        fprintf(stderr, "audiowrt-renderer: could not open SSDP, mDNS or HTTP listener: %s\n", strerror(errno));
        if (sfd >= 0) close(sfd);
        if (hfd >= 0) close(hfd);
        if (mfd >= 0) close(mfd);
        return 1;
    }

    fds[0].fd = sfd; fds[0].events = POLLIN;
    fds[1].fd = hfd; fds[1].events = POLLIN;
    fds[2].fd = mfd; fds[2].events = POLLIN;
    ssdp_notify(sfd, "ssdp:alive");
    mdns_announce(mfd);
    next_alive = time(NULL) + 300;
    next_mdns = time(NULL) + 60;

    while (running) {
        int rc = poll(fds, 3, 1000);
        if (rc > 0) {
            if (fds[0].revents & POLLIN) handle_ssdp(sfd);
            if (fds[1].revents & POLLIN) {
                struct sockaddr_storage peer;
                socklen_t plen = sizeof(peer);
                int cfd = accept(hfd, (struct sockaddr *)&peer, &plen);
                if (cfd >= 0) handle_http_client(cfd, &peer);
            }
            if (fds[2].revents & POLLIN) handle_mdns(mfd);
        }
        reap_player();
        if (time(NULL) >= next_alive) {
            ssdp_notify(sfd, "ssdp:alive");
            next_alive = time(NULL) + 300;
        }
        if (time(NULL) >= next_mdns) {
            mdns_announce(mfd);
            next_mdns = time(NULL) + 60;
        }
    }

    stop_current(false);
    ssdp_notify(sfd, "ssdp:byebye");
    close(mfd);
    close(hfd);
    close(sfd);
    return 0;
}

static int show_status(void)
{
    char path[320], buf[4096];
    FILE *f;
    snprintf(path, sizeof(path), "%s/status.json", g.runtime_dir);
    f = fopen(path, "r");
    if (!f) {
        puts("{\"state\":\"STOPPED\",\"codec\":\"\",\"uri\":\"\",\"controller\":\"\",\"position\":\"0:00:00\",\"volume\":100,\"mute\":false,\"pid\":0}");
        return 0;
    }
    while (fgets(buf, sizeof(buf), f)) fputs(buf, stdout);
    fclose(f);
    return 0;
}

int main(int argc, char **argv)
{
    const char *cmd = argc > 1 ? argv[1] : "daemon";
    if (load_config() < 0) {
        fprintf(stderr, "audiowrt-renderer: unable to load renderer configuration\n");
        return 1;
    }
    if (!strcmp(cmd, "daemon")) return daemon_main();
    if (!strcmp(cmd, "players")) { print_players_json(); return 0; }
    if (!strcmp(cmd, "status")) return show_status();
    fprintf(stderr, "usage: %s {daemon|players|status}\n", argv[0]);
    return 2;
}
