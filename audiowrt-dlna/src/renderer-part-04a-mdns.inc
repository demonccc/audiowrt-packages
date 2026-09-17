#define MDNS_ADDR "224.0.0.251"
#define MDNS_PORT 5353
#define MDNS_TTL 120U
#define DNS_TYPE_A 1
#define DNS_TYPE_PTR 12
#define DNS_TYPE_TXT 16
#define DNS_TYPE_SRV 33
#define DNS_TYPE_ANY 255
#define DNS_CLASS_IN 1
#define DNS_CACHE_FLUSH 0x8000

static uint16_t mdns_get_u16(const unsigned char *p)
{
    return (uint16_t)(((uint16_t)p[0] << 8) | p[1]);
}

static void mdns_put_u16(unsigned char *p, uint16_t value)
{
    p[0] = (unsigned char)(value >> 8);
    p[1] = (unsigned char)(value & 0xff);
}

static void mdns_put_u32(unsigned char *p, uint32_t value)
{
    p[0] = (unsigned char)(value >> 24);
    p[1] = (unsigned char)((value >> 16) & 0xff);
    p[2] = (unsigned char)((value >> 8) & 0xff);
    p[3] = (unsigned char)(value & 0xff);
}

static int mdns_encode_name(unsigned char *buf, size_t cap, const char *name)
{
    const char *p = name;
    size_t used = 0;

    while (p && *p) {
        const char *dot = strchr(p, '.');
        size_t n = dot ? (size_t)(dot - p) : strlen(p);
        if (!n || n > 63 || used + n + 2 > cap)
            return -1;
        buf[used++] = (unsigned char)n;
        memcpy(buf + used, p, n);
        used += n;
        if (!dot)
            break;
        p = dot + 1;
    }
    if (used + 1 > cap)
        return -1;
    buf[used++] = 0;
    return (int)used;
}

static int mdns_decode_name(const unsigned char *packet, size_t packet_len,
                            size_t *offset, char *out, size_t out_len)
{
    size_t pos = *offset, resume = 0, used = 0;
    bool jumped = false;
    unsigned jumps = 0;

    while (pos < packet_len) {
        unsigned label = packet[pos];
        if ((label & 0xc0) == 0xc0) {
            size_t target;
            if (pos + 1 >= packet_len || ++jumps > 16)
                return -1;
            target = (size_t)(((label & 0x3f) << 8) | packet[pos + 1]);
            if (target >= packet_len)
                return -1;
            if (!jumped) {
                resume = pos + 2;
                jumped = true;
            }
            pos = target;
            continue;
        }
        if (!label) {
            if (!jumped)
                *offset = pos + 1;
            else
                *offset = resume;
            if (!out_len)
                return -1;
            out[used] = 0;
            return 0;
        }
        if (label > 63 || pos + 1 + label > packet_len)
            return -1;
        pos++;
        if (used) {
            if (used + 1 >= out_len)
                return -1;
            out[used++] = '.';
        }
        if (used + label >= out_len)
            return -1;
        memcpy(out + used, packet + pos, label);
        used += label;
        pos += label;
    }
    return -1;
}

static void mdns_host_name(char *host, size_t host_len, char *fqdn, size_t fqdn_len)
{
    size_t i;
    if (gethostname(host, host_len) < 0 || !host[0])
        copystr(host, host_len, "AudioWRT");
    host[host_len - 1] = 0;
    if (strchr(host, '.'))
        *strchr(host, '.') = 0;
    for (i = 0; host[i]; i++) {
        unsigned char c = (unsigned char)host[i];
        if (!(isalnum(c) || c == '-'))
            host[i] = '-';
    }
    snprintf(fqdn, fqdn_len, "%s.local", host);
}

static int mdns_primary_ipv4(struct in_addr *address)
{
    struct ifaddrs *ifas = NULL, *ifa;
    if (getifaddrs(&ifas) < 0)
        return -1;
    for (ifa = ifas; ifa; ifa = ifa->ifa_next) {
        struct sockaddr_in *sin;
        uint32_t a;
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET)
            continue;
        if (ifa->ifa_flags & 0x8)
            continue;
        sin = (struct sockaddr_in *)ifa->ifa_addr;
        a = ntohl(sin->sin_addr.s_addr);
        if (!a || (a >> 24) == 127)
            continue;
        *address = sin->sin_addr;
        freeifaddrs(ifas);
        return 0;
    }
    freeifaddrs(ifas);
    return -1;
}

static int mdns_write_name(unsigned char *packet, size_t cap, size_t *used, const char *name)
{
    int n;
    if (*used >= cap)
        return -1;
    n = mdns_encode_name(packet + *used, cap - *used, name);
    if (n < 0)
        return -1;
    *used += (size_t)n;
    return 0;
}

static int mdns_rr_header(unsigned char *packet, size_t cap, size_t *used,
                          const char *name, uint16_t type, uint16_t klass,
                          uint32_t ttl, size_t *rdlen_pos)
{
    if (mdns_write_name(packet, cap, used, name) < 0 || *used + 10 > cap)
        return -1;
    mdns_put_u16(packet + *used, type); *used += 2;
    mdns_put_u16(packet + *used, klass); *used += 2;
    mdns_put_u32(packet + *used, ttl); *used += 4;
    *rdlen_pos = *used;
    mdns_put_u16(packet + *used, 0); *used += 2;
    return 0;
}

static int mdns_add_a(unsigned char *packet, size_t cap, size_t *used,
                      const char *host_fqdn, struct in_addr address)
{
    size_t rlen;
    if (mdns_rr_header(packet, cap, used, host_fqdn, DNS_TYPE_A,
                       DNS_CLASS_IN | DNS_CACHE_FLUSH, MDNS_TTL, &rlen) < 0 ||
        *used + 4 > cap)
        return -1;
    memcpy(packet + *used, &address.s_addr, 4);
    *used += 4;
    mdns_put_u16(packet + rlen, 4);
    return 0;
}

static int mdns_add_ptr(unsigned char *packet, size_t cap, size_t *used,
                        const char *owner, const char *target)
{
    size_t rlen, start;
    if (mdns_rr_header(packet, cap, used, owner, DNS_TYPE_PTR,
                       DNS_CLASS_IN, MDNS_TTL, &rlen) < 0)
        return -1;
    start = *used;
    if (mdns_write_name(packet, cap, used, target) < 0)
        return -1;
    mdns_put_u16(packet + rlen, (uint16_t)(*used - start));
    return 0;
}

static int mdns_add_srv(unsigned char *packet, size_t cap, size_t *used,
                        const char *instance, const char *host_fqdn, uint16_t port)
{
    size_t rlen, start;
    if (mdns_rr_header(packet, cap, used, instance, DNS_TYPE_SRV,
                       DNS_CLASS_IN | DNS_CACHE_FLUSH, MDNS_TTL, &rlen) < 0 ||
        *used + 6 > cap)
        return -1;
    start = *used;
    mdns_put_u16(packet + *used, 0); *used += 2;
    mdns_put_u16(packet + *used, 0); *used += 2;
    mdns_put_u16(packet + *used, port); *used += 2;
    if (mdns_write_name(packet, cap, used, host_fqdn) < 0)
        return -1;
    mdns_put_u16(packet + rlen, (uint16_t)(*used - start));
    return 0;
}

static int mdns_add_txt(unsigned char *packet, size_t cap, size_t *used,
                        const char *instance)
{
    static const char txt[] = "path=/";
    size_t rlen;
    if (mdns_rr_header(packet, cap, used, instance, DNS_TYPE_TXT,
                       DNS_CLASS_IN | DNS_CACHE_FLUSH, MDNS_TTL, &rlen) < 0 ||
        *used + sizeof(txt) > cap)
        return -1;
    packet[(*used)++] = (unsigned char)(sizeof(txt) - 1);
    memcpy(packet + *used, txt, sizeof(txt) - 1);
    *used += sizeof(txt) - 1;
    mdns_put_u16(packet + rlen, (uint16_t)sizeof(txt));
    return 0;
}

static int mdns_build_response(unsigned char *packet, size_t cap, bool include_host,
                               bool include_http, bool include_services)
{
    char host[64] = "", host_fqdn[96] = "", instance[256];
    struct in_addr address;
    size_t used = 12;
    unsigned answers = 0;

    if (cap < 12 || mdns_primary_ipv4(&address) < 0)
        return -1;
    memset(packet, 0, cap);
    mdns_put_u16(packet + 2, 0x8400);
    mdns_host_name(host, sizeof(host), host_fqdn, sizeof(host_fqdn));
    snprintf(instance, sizeof(instance), "%s._http._tcp.local", g.friendly_name);

    if (include_services) {
        if (mdns_add_ptr(packet, cap, &used, "_services._dns-sd._udp.local",
                         "_http._tcp.local") < 0)
            return -1;
        answers++;
    }
    if (include_http) {
        if (mdns_add_ptr(packet, cap, &used, "_http._tcp.local", instance) < 0 ||
            mdns_add_srv(packet, cap, &used, instance, host_fqdn, 80) < 0 ||
            mdns_add_txt(packet, cap, &used, instance) < 0)
            return -1;
        answers += 3;
        include_host = true;
    }
    if (include_host) {
        if (mdns_add_a(packet, cap, &used, host_fqdn, address) < 0)
            return -1;
        answers++;
    }

    mdns_put_u16(packet + 6, (uint16_t)answers);
    return (int)used;
}

static int mdns_send_multicast(int fd, const unsigned char *packet, size_t len)
{
    struct sockaddr_in dest = {0};
    dest.sin_family = AF_INET;
    dest.sin_port = htons(MDNS_PORT);
    inet_pton(AF_INET, MDNS_ADDR, &dest.sin_addr);
    return sendto(fd, packet, len, 0, (struct sockaddr *)&dest, sizeof(dest)) < 0 ? -1 : 0;
}

static void mdns_announce(int fd)
{
    unsigned char packet[1400];
    int n = mdns_build_response(packet, sizeof(packet), true, true, true);
    if (n > 0)
        mdns_send_multicast(fd, packet, (size_t)n);
}

static void handle_mdns(int fd)
{
    unsigned char query[1400], response[1400];
    struct sockaddr_in peer;
    socklen_t plen = sizeof(peer);
    ssize_t n;
    size_t off = 12;
    uint16_t questions, i;
    bool host = false, http = false, services = false;
    char hostname[64] = "", host_fqdn[96] = "", instance[256];

    n = recvfrom(fd, query, sizeof(query), 0, (struct sockaddr *)&peer, &plen);
    if (n < 12)
        return;
    if (mdns_get_u16(query + 2) & 0x8000)
        return;

    mdns_host_name(hostname, sizeof(hostname), host_fqdn, sizeof(host_fqdn));
    snprintf(instance, sizeof(instance), "%s._http._tcp.local", g.friendly_name);
    questions = mdns_get_u16(query + 4);

    for (i = 0; i < questions; i++) {
        char name[256];
        uint16_t type, klass;
        if (mdns_decode_name(query, (size_t)n, &off, name, sizeof(name)) < 0 || off + 4 > (size_t)n)
            return;
        type = mdns_get_u16(query + off); off += 2;
        klass = (uint16_t)(mdns_get_u16(query + off) & 0x7fff); off += 2;
        if (klass != DNS_CLASS_IN)
            continue;
        if (!strcasecmp(name, host_fqdn) && (type == DNS_TYPE_A || type == DNS_TYPE_ANY))
            host = true;
        if ((!strcasecmp(name, "_http._tcp.local") || !strcasecmp(name, instance)) &&
            (type == DNS_TYPE_PTR || type == DNS_TYPE_SRV || type == DNS_TYPE_TXT || type == DNS_TYPE_ANY))
            http = true;
        if (!strcasecmp(name, "_services._dns-sd._udp.local") &&
            (type == DNS_TYPE_PTR || type == DNS_TYPE_ANY))
            services = true;
    }

    if (host || http || services) {
        int len = mdns_build_response(response, sizeof(response), host, http, services);
        if (len > 0)
            mdns_send_multicast(fd, response, (size_t)len);
    }
}

static int open_mdns(void)
{
    int fd, yes = 1;
    unsigned char ttl = 255;
    struct sockaddr_in addr = {0};
    struct ip_mreq mreq;

    fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0)
        return -1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, sizeof(ttl));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(MDNS_PORT);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }
    inet_pton(AF_INET, MDNS_ADDR, &mreq.imr_multiaddr);
    mreq.imr_interface.s_addr = htonl(INADDR_ANY);
    if (setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, sizeof(mreq)) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}
