// SPDX-License-Identifier: GPL-2.0-only
#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define CONFIG_PATH "/etc/config/audiowrt_mpd"
#define DEFAULT_HOST "127.0.0.1"
#define DEFAULT_PORT "6600"

static volatile sig_atomic_t terminate_requested;

struct endpoint {
    char host[128];
    char port[16];
};

static void on_terminate(int sig)
{
    (void)sig;
    terminate_requested = 1;
}

static void copystr(char *dst, size_t len, const char *src)
{
    size_t n;
    if (!len) return;
    if (!src) src = "";
    n = strnlen(src, len - 1);
    memcpy(dst, src, n);
    dst[n] = 0;
}

static void trim_value(char *s)
{
    char *p = s;
    size_t n;
    while (*p == ' ' || *p == '\t') p++;
    if (p != s) memmove(s, p, strlen(p) + 1);
    n = strlen(s);
    while (n && (s[n - 1] == '\r' || s[n - 1] == '\n' || s[n - 1] == ' ' || s[n - 1] == '\t'))
        s[--n] = 0;
    if (n >= 2 && ((s[0] == '\'' && s[n - 1] == '\'') || (s[0] == '"' && s[n - 1] == '"'))) {
        memmove(s, s + 1, n - 2);
        s[n - 2] = 0;
    }
}

static void load_endpoint(struct endpoint *ep)
{
    FILE *f;
    char line[512];

    copystr(ep->host, sizeof(ep->host), DEFAULT_HOST);
    copystr(ep->port, sizeof(ep->port), DEFAULT_PORT);

    f = fopen(CONFIG_PATH, "r");
    if (!f) return;

    while (fgets(line, sizeof(line), f)) {
        char key[64], value[384];
        if (sscanf(line, " option %63s %383[^\n]", key, value) != 2)
            continue;
        trim_value(value);
        if (!strcmp(key, "host"))
            copystr(ep->host, sizeof(ep->host), value);
        else if (!strcmp(key, "port"))
            copystr(ep->port, sizeof(ep->port), value);
    }
    fclose(f);
}

static int read_line(int fd, char *buf, size_t len)
{
    size_t used = 0;
    while (used + 1 < len) {
        char c;
        ssize_t n = recv(fd, &c, 1, 0);
        if (n == 0) break;
        if (n < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (c == '\n') break;
        if (c != '\r') buf[used++] = c;
    }
    buf[used] = 0;
    return used ? 1 : 0;
}

static int send_all(int fd, const char *buf, size_t len)
{
    while (len) {
        ssize_t n = send(fd, buf, len, 0);
        if (n < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        buf += n;
        len -= (size_t)n;
    }
    return 0;
}

static int mpd_open(const struct endpoint *ep, char *version, size_t version_len)
{
    struct addrinfo hints, *res = NULL, *it;
    int fd = -1;
    char line[512];

    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(ep->host, ep->port, &hints, &res) != 0)
        return -1;

    for (it = res; it; it = it->ai_next) {
        fd = socket(it->ai_family, it->ai_socktype, it->ai_protocol);
        if (fd < 0) continue;
        if (connect(fd, it->ai_addr, it->ai_addrlen) == 0)
            break;
        close(fd);
        fd = -1;
    }
    freeaddrinfo(res);
    if (fd < 0) return -1;

    if (read_line(fd, line, sizeof(line)) <= 0 || strncmp(line, "OK MPD ", 7)) {
        close(fd);
        return -1;
    }
    if (version && version_len)
        copystr(version, version_len, line + 7);
    return fd;
}

static int mpd_command(const struct endpoint *ep, const char *command, FILE *out,
                       char *state, size_t state_len, char *volume, size_t volume_len,
                       char *version, size_t version_len)
{
    int fd = mpd_open(ep, version, version_len);
    char line[2048];
    char wire[4096];

    if (fd < 0) return -1;
    snprintf(wire, sizeof(wire), "%s\n", command);
    if (send_all(fd, wire, strlen(wire)) < 0) {
        close(fd);
        return -1;
    }

    while (read_line(fd, line, sizeof(line)) > 0) {
        if (!strcmp(line, "OK")) {
            close(fd);
            return 0;
        }
        if (!strncmp(line, "ACK ", 4)) {
            if (out) fprintf(out, "%s\n", line);
            close(fd);
            return -1;
        }
        if (state && !strncmp(line, "state: ", 7))
            copystr(state, state_len, line + 7);
        if (volume && !strncmp(line, "volume: ", 8))
            copystr(volume, volume_len, line + 8);
        if (out) fprintf(out, "%s\n", line);
    }
    close(fd);
    return -1;
}

static void quote_arg(const char *src, char *dst, size_t len)
{
    size_t used = 0;
    if (!len) return;
    if (used + 1 < len) dst[used++] = '"';
    while (*src && used + 2 < len) {
        if (*src == '\\' || *src == '"')
            dst[used++] = '\\';
        dst[used++] = *src++;
    }
    if (used + 1 < len) dst[used++] = '"';
    dst[used] = 0;
}

static int simple_command(const struct endpoint *ep, const char *cmd)
{
    return mpd_command(ep, cmd, NULL, NULL, 0, NULL, 0, NULL, 0);
}

static char proc_state(pid_t pid)
{
    char path[64], buf[512], *end;
    FILE *f;
    snprintf(path, sizeof(path), "/proc/%ld/stat", (long)pid);
    f = fopen(path, "r");
    if (!f) return 0;
    if (!fgets(buf, sizeof(buf), f)) {
        fclose(f);
        return 0;
    }
    fclose(f);
    end = strrchr(buf, ')');
    if (!end || end[1] != ' ' || !end[2]) return 0;
    return end[2];
}

static void pause_watchdog(const struct endpoint *ep, pid_t parent)
{
    bool paused = false;
    if (setsid() < 0)
        _exit(1);

    for (;;) {
        char st;
        if (kill(parent, 0) < 0 && errno == ESRCH)
            break;
        st = proc_state(parent);
        if (!st || st == 'Z')
            break;
        if (st == 'T' || st == 't') {
            if (!paused) {
                (void)simple_command(ep, "pause 1");
                paused = true;
            }
        } else if (paused) {
            (void)simple_command(ep, "pause 0");
            paused = false;
        }
        usleep(100000);
    }
    (void)simple_command(ep, "stop");
    _exit(0);
}

static int read_volume(const char *path, int *value)
{
    FILE *f;
    int v;
    if (!path || !*path) return -1;
    f = fopen(path, "r");
    if (!f) return -1;
    if (fscanf(f, "%d", &v) != 1) {
        fclose(f);
        return -1;
    }
    fclose(f);
    if (v < 0) v = 0;
    if (v > 100) v = 100;
    *value = v;
    return 0;
}

static int play_url(const struct endpoint *ep, const char *url)
{
    char quoted[4096], cmd[4608], state[32];
    const char *volume_file = getenv("AUDIOWRT_VOLUME_FILE");
    int last_volume = -1;
    pid_t watchdog;

    quote_arg(url, quoted, sizeof(quoted));
    if (simple_command(ep, "clear") < 0)
        return 1;
    snprintf(cmd, sizeof(cmd), "add %s", quoted);
    if (simple_command(ep, cmd) < 0)
        return 1;
    if (simple_command(ep, "play") < 0)
        return 1;

    watchdog = fork();
    if (watchdog == 0)
        pause_watchdog(ep, getppid());

    signal(SIGTERM, on_terminate);
    signal(SIGINT, on_terminate);

    while (!terminate_requested) {
        int volume;
        state[0] = 0;
        if (mpd_command(ep, "status", NULL, state, sizeof(state), NULL, 0, NULL, 0) < 0)
            break;
        if (!strcmp(state, "stop"))
            break;
        if (read_volume(volume_file, &volume) == 0 && volume != last_volume) {
            snprintf(cmd, sizeof(cmd), "setvol %d", volume);
            if (simple_command(ep, cmd) == 0)
                last_volume = volume;
        }
        sleep(1);
    }

    if (terminate_requested)
        (void)simple_command(ep, "stop");
    if (watchdog > 0) {
        kill(watchdog, SIGTERM);
        waitpid(watchdog, NULL, 0);
    }
    return 0;
}

static int show_status(const struct endpoint *ep)
{
    char state[32] = "", volume[32] = "", version[64] = "";
    int rc = mpd_command(ep, "status", NULL, state, sizeof(state), volume, sizeof(volume), version, sizeof(version));
    printf("host=%s\nport=%s\n", ep->host, ep->port);
    if (rc < 0) {
        puts("reachable=0");
        return 1;
    }
    puts("reachable=1");
    printf("version=%s\nstate=%s\nvolume=%s\n", version, state, volume);
    return 0;
}

int main(int argc, char **argv)
{
    struct endpoint ep;
    char version[64];

    load_endpoint(&ep);

    if (argc < 2) {
        fprintf(stderr, "usage: %s <URL>|ping|status|decoders|outputs|pause|resume|stop\n", argv[0]);
        return 2;
    }

    if (!strcmp(argv[1], "ping")) {
        int fd = mpd_open(&ep, version, sizeof(version));
        if (fd < 0) return 1;
        close(fd);
        return 0;
    }
    if (!strcmp(argv[1], "status"))
        return show_status(&ep);
    if (!strcmp(argv[1], "decoders"))
        return mpd_command(&ep, "decoders", stdout, NULL, 0, NULL, 0, NULL, 0) < 0;
    if (!strcmp(argv[1], "outputs"))
        return mpd_command(&ep, "outputs", stdout, NULL, 0, NULL, 0, NULL, 0) < 0;
    if (!strcmp(argv[1], "pause"))
        return simple_command(&ep, "pause 1") < 0;
    if (!strcmp(argv[1], "resume"))
        return simple_command(&ep, "pause 0") < 0;
    if (!strcmp(argv[1], "stop"))
        return simple_command(&ep, "stop") < 0;

    return play_url(&ep, argv[1]);
}
