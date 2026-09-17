#define _GNU_SOURCE

#include <arpa/inet.h>
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <netdb.h>
#include <netinet/in.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include <uci.h>

#define MAX_PLAYERS 16
#define MAX_SUBSCRIBERS 12
#define HTTP_BUFFER 65536
#define SSDP_ADDR "239.255.255.250"
#define SSDP_PORT 1900
#define DEFAULT_PORT 49152
#define DEFAULT_PLAYER_DIR "/usr/share/audiowrt/dlna/players"
#define DEFAULT_RUNTIME_DIR "/var/run/audiowrt-dlna"

struct player {
    char id[32];
    char name[96];
    char command[512];
    char auto_command[256];
    char pause_command[512];
    char resume_command[512];
    char stop_command[512];
    char mime[384];
    char extensions[192];
    char package[96];
    bool custom;
    bool managed;
};

struct subscriber {
    bool used;
    char service[32];
    char sid[80];
    char host[128];
    char path[256];
    int port;
    unsigned seq;
    time_t expires;
};

enum transport_state {
    STATE_NO_MEDIA,
    STATE_STOPPED,
    STATE_PLAYING,
    STATE_PAUSED
};

struct renderer {
    char friendly_name[128];
    char uuid[80];
    char player_dir[256];
    char runtime_dir[256];
    char alsa_device[128];
    int port;
    int volume;
    bool mute;
    struct player players[MAX_PLAYERS];
    size_t player_count;
    struct subscriber subscribers[MAX_SUBSCRIBERS];

    char uri[2048];
    char metadata[8192];
    char codec[32];
    char controller[INET6_ADDRSTRLEN];
    pid_t player_pid;
    enum transport_state state;
    time_t play_started;
    unsigned position_base;
};

static struct renderer g;
static volatile sig_atomic_t running = 1;

static void notify_service(const char *service);

static void copystr(char *dst, size_t len, const char *src)
{
    size_t n;
    if (!len)
        return;
    if (!src)
        src = "";
    n = strnlen(src, len - 1);
    memmove(dst, src, n);
    dst[n] = 0;
}

static void trim(char *s)
{
    char *p = s;
    size_t n;
    while (*p && isspace((unsigned char)*p))
        p++;
    if (p != s)
        memmove(s, p, strlen(p) + 1);
    n = strlen(s);
    while (n && isspace((unsigned char)s[n - 1]))
        s[--n] = 0;
}

static int parse_bool(const char *s, int def)
{
    if (!s || !*s)
        return def;
    return !strcasecmp(s, "1") || !strcasecmp(s, "yes") ||
           !strcasecmp(s, "true") || !strcasecmp(s, "on");
}

static const char *state_name(enum transport_state st)
{
    switch (st) {
    case STATE_PLAYING: return "PLAYING";
    case STATE_PAUSED: return "PAUSED_PLAYBACK";
    case STATE_STOPPED: return "STOPPED";
    default: return "NO_MEDIA_PRESENT";
    }
}

static void mkdir_runtime(void)
{
    if (mkdir(g.runtime_dir, 0755) < 0 && errno != EEXIST)
        fprintf(stderr, "audiowrt-dlna: mkdir %s: %s\n", g.runtime_dir, strerror(errno));
}

static void json_escape(FILE *f, const char *s)
{
    const unsigned char *p = (const unsigned char *)(s ? s : "");
    for (; *p; p++) {
        switch (*p) {
        case '\\': fputs("\\\\", f); break;
        case '"': fputs("\\\"", f); break;
        case '\n': fputs("\\n", f); break;
        case '\r': fputs("\\r", f); break;
        case '\t': fputs("\\t", f); break;
        default:
            if (*p < 0x20)
                fprintf(f, "\\u%04x", *p);
            else
                fputc(*p, f);
        }
    }
}

static unsigned current_position(void)
{
    if (g.state == STATE_PLAYING && g.play_started > 0) {
        time_t now = time(NULL);
        if (now > g.play_started)
            return g.position_base + (unsigned)(now - g.play_started);
    }
    return g.position_base;
}

static void format_time(unsigned seconds, char *buf, size_t len)
{
    unsigned h = seconds / 3600;
    unsigned m = (seconds % 3600) / 60;
    unsigned s = seconds % 60;
    snprintf(buf, len, "%u:%02u:%02u", h, m, s);
}

static void write_volume_file(void)
{
    char path[320];
    FILE *f;
    snprintf(path, sizeof(path), "%s/volume", g.runtime_dir);
    f = fopen(path, "w");
    if (!f)
        return;
    fprintf(f, "%d\n", g.mute ? 0 : g.volume);
    fclose(f);
}

static void write_status(void)
{
    char path[320], tmp[336], pos[32];
    FILE *f;
    mkdir_runtime();
    snprintf(path, sizeof(path), "%s/status.json", g.runtime_dir);
    snprintf(tmp, sizeof(tmp), "%s.tmp", path);
    f = fopen(tmp, "w");
    if (!f)
        return;
    format_time(current_position(), pos, sizeof(pos));
    fputs("{\"state\":\"", f); json_escape(f, state_name(g.state));
    fputs("\",\"codec\":\"", f); json_escape(f, g.codec);
    fputs("\",\"uri\":\"", f); json_escape(f, g.uri);
    fputs("\",\"controller\":\"", f); json_escape(f, g.controller);
    fputs("\",\"position\":\"", f); json_escape(f, pos);
    fprintf(f, "\",\"volume\":%d,\"mute\":%s,\"pid\":%ld}\n",
            g.volume, g.mute ? "true" : "false", (long)g.player_pid);
    fclose(f);
    rename(tmp, path);
    write_volume_file();
}

static struct player *find_player_id(const char *id)
{
    size_t i;
    for (i = 0; i < g.player_count; i++)
        if (!strcmp(g.players[i].id, id))
            return &g.players[i];
    return NULL;
}

static int token_in_list(const char *list, const char *needle)
{
    char copy[512], *save = NULL, *tok;
    if (!list || !needle)
        return 0;
    copystr(copy, sizeof(copy), list);
    for (tok = strtok_r(copy, " ,\t", &save); tok; tok = strtok_r(NULL, " ,\t", &save))
        if (!strcasecmp(tok, needle))
            return 1;
    return 0;
}

static int descriptor_load(const char *path, struct player *p)
{
    FILE *f = fopen(path, "r");
    char line[1024];
    if (!f)
        return -1;
    memset(p, 0, sizeof(*p));
    p->managed = true;
    while (fgets(line, sizeof(line), f)) {
        char *eq;
        trim(line);
        if (!*line || *line == '#')
            continue;
        eq = strchr(line, '=');
        if (!eq)
            continue;
        *eq++ = 0;
        trim(line);
        trim(eq);
        if (!strcmp(line, "id")) copystr(p->id, sizeof(p->id), eq);
        else if (!strcmp(line, "name")) copystr(p->name, sizeof(p->name), eq);
        else if (!strcmp(line, "command")) copystr(p->command, sizeof(p->command), eq);
        else if (!strcmp(line, "mime")) copystr(p->mime, sizeof(p->mime), eq);
        else if (!strcmp(line, "extensions")) copystr(p->extensions, sizeof(p->extensions), eq);
        else if (!strcmp(line, "package")) copystr(p->package, sizeof(p->package), eq);
    }
    fclose(f);
    if (!p->id[0] || !p->command[0])
        return -1;
    copystr(p->auto_command, sizeof(p->auto_command), p->command);
    if (!p->name[0])
        copystr(p->name, sizeof(p->name), p->id);
    return 0;
}

static void load_descriptors(void)
{
    DIR *d;
    struct dirent *de;
    g.player_count = 0;
    d = opendir(g.player_dir);
    if (!d)
        return;
    while ((de = readdir(d)) && g.player_count < MAX_PLAYERS) {
        char path[512];
        size_t n = strlen(de->d_name);
        if (n < 6 || strcmp(de->d_name + n - 5, ".conf"))
            continue;
        snprintf(path, sizeof(path), "%s/%s", g.player_dir, de->d_name);
        if (!descriptor_load(path, &g.players[g.player_count]))
            g.player_count++;
    }
    closedir(d);
}

static const char *uci_opt(struct uci_context *ctx, struct uci_section *s, const char *name)
{
    return uci_lookup_option_string(ctx, s, name);
}
