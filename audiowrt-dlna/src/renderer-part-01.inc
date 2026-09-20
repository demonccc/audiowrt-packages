static int config_next_token(char **cursor, char *out, size_t len)
{
    char *p = *cursor;
    size_t used = 0;
    char quote = 0;

    while (*p && isspace((unsigned char)*p))
        p++;
    if (!*p || *p == '#') {
        *cursor = p;
        if (len) out[0] = 0;
        return 0;
    }

    while (*p) {
        if (!quote && (isspace((unsigned char)*p) || *p == '#'))
            break;
        if (*p == '\\' && p[1]) {
            p++;
            if (used + 1 < len)
                out[used++] = *p;
            p++;
            continue;
        }
        if (*p == '\'' || *p == '"') {
            if (!quote) {
                quote = *p++;
                continue;
            }
            if (quote == *p) {
                quote = 0;
                p++;
                continue;
            }
        }
        if (used + 1 < len)
            out[used++] = *p;
        p++;
    }

    if (len)
        out[used] = 0;
    *cursor = p;
    return 1;
}


static void apply_renderer_option(const char *key, const char *value)
{
    if (!strcmp(key, "friendly_name"))
        copystr(g.friendly_name, sizeof(g.friendly_name), value);
    else if (!strcmp(key, "uuid"))
        copystr(g.uuid, sizeof(g.uuid), value);
    else if (!strcmp(key, "runtime_dir"))
        copystr(g.runtime_dir, sizeof(g.runtime_dir), value);
    else if (!strcmp(key, "alsa_device"))
        copystr(g.alsa_device, sizeof(g.alsa_device), value);
    else if (!strcmp(key, "port"))
        g.port = atoi(value);
    else if (!strcmp(key, "volume"))
        g.volume = atoi(value);
}

static int load_renderer_options(const char *path)
{
    FILE *f = fopen(path, "r");
    char line[2048];
    bool in_renderer = false;
    bool renderer_seen = false;

    if (!f)
        return -1;

    while (fgets(line, sizeof(line), f)) {
        char *cursor = line;
        char directive[32], type[64], name[128], key[128], value[1536];

        if (!config_next_token(&cursor, directive, sizeof(directive)))
            continue;

        if (!strcmp(directive, "config")) {
            type[0] = name[0] = 0;
            config_next_token(&cursor, type, sizeof(type));
            config_next_token(&cursor, name, sizeof(name));
            in_renderer = !strcmp(type, "renderer") &&
                (!renderer_seen || !name[0] || !strcmp(name, "main"));
            if (in_renderer)
                renderer_seen = true;
            continue;
        }

        if (in_renderer && !strcmp(directive, "option")) {
            if (!config_next_token(&cursor, key, sizeof(key)) ||
                !config_next_token(&cursor, value, sizeof(value)))
                continue;
            apply_renderer_option(key, value);
        }
    }

    fclose(f);
    return 0;
}

static struct codec *registry_codec(const char *id)
{
    struct codec *codec;

    codec = find_codec_id(id);
    if (codec)
        return codec;
    if (!id || !*id || g.codec_count >= MAX_CODECS)
        return NULL;

    codec = &g.codecs[g.codec_count++];
    memset(codec, 0, sizeof(*codec));
    copystr(codec->id, sizeof(codec->id), id);
    return codec;
}

static struct player *registry_player(const char *id)
{
    struct player *player;

    player = find_player_id(id);
    if (player)
        return player;
    if (!id || !*id || g.player_count >= MAX_PLAYERS)
        return NULL;

    player = &g.players[g.player_count++];
    memset(player, 0, sizeof(*player));
    copystr(player->id, sizeof(player->id), id);
    copystr(player->name, sizeof(player->name), id);
    return player;
}

static int load_registry(const char *path)
{
    FILE *f = fopen(path, "r");
    char line[2048];
    struct codec *codec = NULL;
    struct player *player = NULL;

    g.codec_count = 0;
    g.player_count = 0;
    memset(g.codecs, 0, sizeof(g.codecs));
    memset(g.players, 0, sizeof(g.players));

    if (!f)
        return -1;

    while (fgets(line, sizeof(line), f)) {
        char *cursor = line;
        char directive[32], type[64], name[128], key[128], value[1536];

        if (!config_next_token(&cursor, directive, sizeof(directive)))
            continue;

        if (!strcmp(directive, "config")) {
            type[0] = name[0] = 0;
            config_next_token(&cursor, type, sizeof(type));
            config_next_token(&cursor, name, sizeof(name));
            codec = NULL;
            player = NULL;
            if (!strcmp(type, "codec"))
                codec = registry_codec(name);
            else if (!strcmp(type, "player"))
                player = registry_player(name);
            continue;
        }

        if (strcmp(directive, "option") && strcmp(directive, "list"))
            continue;
        if (!config_next_token(&cursor, key, sizeof(key)) ||
            !config_next_token(&cursor, value, sizeof(value)))
            continue;

        if (codec) {
            if (!strcmp(directive, "list") && !strcmp(key, "mime"))
                append_token(codec->mime, sizeof(codec->mime), value);
            else if (!strcmp(directive, "list") && !strcmp(key, "extension"))
                append_token(codec->extensions, sizeof(codec->extensions), value);
            else if (!strcmp(directive, "option") && !strcmp(key, "default_player"))
                copystr(codec->default_player, sizeof(codec->default_player), value);
        } else if (player) {
            if (!strcmp(directive, "option") && !strcmp(key, "name"))
                copystr(player->name, sizeof(player->name), value);
            else if (!strcmp(directive, "option") && !strcmp(key, "executable"))
                copystr(player->executable, sizeof(player->executable), value);
            else if (!strcmp(directive, "list") && !strcmp(key, "codec"))
                append_token(player->codecs, sizeof(player->codecs), value);
        }
    }

    fclose(f);
    return 0;
}

static int reload_registry(void)
{
    return load_registry("/etc/config/audiowrt");
}

static int load_config(void)
{
    const char *renderer_path = "/etc/config/audiowrt-dlna";

    memset(&g, 0, sizeof(g));
    copystr(g.friendly_name, sizeof(g.friendly_name), "AudioWRT");
    copystr(g.runtime_dir, sizeof(g.runtime_dir), DEFAULT_RUNTIME_DIR);
    copystr(g.alsa_device, sizeof(g.alsa_device), "default");
    g.port = DEFAULT_PORT;
    g.volume = 100;
    g.state = STATE_NO_MEDIA;

    if (load_renderer_options(renderer_path) < 0)
        return -1;

    if (g.port < 1024 || g.port > 65535)
        g.port = DEFAULT_PORT;
    if (g.volume < 0) g.volume = 0;
    if (g.volume > 100) g.volume = 100;

    reload_registry();

    if (!g.uuid[0])
        copystr(g.uuid, sizeof(g.uuid), "00000000-0000-0000-0000-000000000000");
    mkdir_runtime();
    return 0;
}

static void print_players_json(void)
{
    size_t i, j;

    putchar('[');
    for (i = 0; i < g.codec_count; i++) {
        struct codec *codec = &g.codecs[i];
        struct player *effective = effective_player(codec);
        bool first_player = true;

        if (i) putchar(',');
        fputs("{\"id\":\"", stdout); json_escape(stdout, codec->id);
        fputs("\",\"mime\":\"", stdout); json_escape(stdout, codec->mime);
        fputs("\",\"extensions\":\"", stdout); json_escape(stdout, codec->extensions);
        fputs("\",\"default_player\":\"", stdout); json_escape(stdout, codec->default_player);
        fputs("\",\"effective_player\":\"", stdout);
        json_escape(stdout, effective ? effective->id : "");
        fprintf(stdout, "\",\"available\":%s,\"players\":[", effective ? "true" : "false");

        for (j = 0; j < g.player_count; j++) {
            struct player *p = &g.players[j];
            if (!player_supports_codec(p, codec->id))
                continue;
            if (!first_player)
                putchar(',');
            first_player = false;
            fputs("{\"id\":\"", stdout); json_escape(stdout, p->id);
            fputs("\",\"name\":\"", stdout); json_escape(stdout, p->name);
            fputs("\",\"executable\":\"", stdout); json_escape(stdout, p->executable);
            fprintf(stdout, "\",\"available\":%s}", player_available(p) ? "true" : "false");
        }
        fputs("]}", stdout);
    }
    puts("]");
}

static struct codec *player_for_uri(const char *uri, const char *metadata)
{
    size_t i;
    char ext[32] = "";
    const char *q, *dot, *slash;

    for (i = 0; i < g.codec_count; i++) {
        char copy[384], *save = NULL, *tok;
        struct codec *codec = &g.codecs[i];

        if (!effective_player(codec))
            continue;
        copystr(copy, sizeof(copy), codec->mime);
        for (tok = strtok_r(copy, " ,\t", &save); tok;
             tok = strtok_r(NULL, " ,\t", &save))
            if (metadata && *metadata && strcasestr(metadata, tok))
                return codec;
    }

    q = uri ? strchr(uri, '?') : NULL;
    slash = uri ? strrchr(uri, '/') : NULL;
    dot = uri ? strrchr(uri, '.') : NULL;
    if (dot && (!slash || dot > slash) && (!q || dot < q)) {
        size_t n = q ? (size_t)(q - dot - 1) : strlen(dot + 1);
        if (n >= sizeof(ext)) n = sizeof(ext) - 1;
        memcpy(ext, dot + 1, n);
        ext[n] = 0;
        for (i = 0; ext[i]; i++)
            ext[i] = (char)tolower((unsigned char)ext[i]);
        for (i = 0; i < g.codec_count; i++) {
            struct codec *codec = &g.codecs[i];
            if (effective_player(codec) && token_in_list(codec->extensions, ext))
                return codec;
        }
    }
    return NULL;
}

static int signal_player_group(int sig)
{
    if (g.player_pid <= 0)
        return -1;
    if (kill(-g.player_pid, sig) == 0)
        return 0;
    return kill(g.player_pid, sig);
}

static int spawn_player(struct player *p)
{
    int exec_pipe[2];
    int child_errno = 0;
    ssize_t n;
    pid_t pid;

    if (!p || !player_available(p))
        return -1;
    if (pipe(exec_pipe) < 0)
        return -1;
    if (fcntl(exec_pipe[1], F_SETFD, FD_CLOEXEC) < 0) {
        close(exec_pipe[0]);
        close(exec_pipe[1]);
        return -1;
    }

    pid = fork();
    if (pid < 0) {
        close(exec_pipe[0]);
        close(exec_pipe[1]);
        return -1;
    }

    if (pid == 0) {
        close(exec_pipe[0]);
        setpgid(0, 0);
        execl(p->executable, p->executable, g.uri, (char *)NULL);
        child_errno = errno;
        (void)write(exec_pipe[1], &child_errno, sizeof(child_errno));
        _exit(127);
    }

    close(exec_pipe[1]);
    (void)setpgid(pid, pid);
    do {
        n = read(exec_pipe[0], &child_errno, sizeof(child_errno));
    } while (n < 0 && errno == EINTR);
    close(exec_pipe[0]);

    if (n > 0) {
        waitpid(pid, NULL, 0);
        return -1;
    }

    g.player_pid = pid;
    copystr(g.active_player, sizeof(g.active_player), p->id);
    return 0;
}

static int launch_next_player(struct codec *codec)
{
    struct player *p;
    size_t i;

    if (!codec)
        return -1;

    if (codec->default_player[0]) {
        p = find_player_id(codec->default_player);
        if (p && player_supports_codec(p, codec->id)) {
            i = (size_t)(p - g.players);
            if (i < 32 && !(g.attempted_players & (1U << i))) {
                g.attempted_players |= 1U << i;
                if (spawn_player(p) == 0)
                    return 0;
            }
        }
    }

    for (i = 0; i < g.player_count && i < 32; i++) {
        p = &g.players[i];
        if (g.attempted_players & (1U << i))
            continue;
        if (!player_supports_codec(p, codec->id))
            continue;
        g.attempted_players |= 1U << i;
        if (spawn_player(p) == 0)
            return 0;
    }

    return -1;
}

static void stop_current(bool reset_position)
{
    if (g.player_pid > 0) {
        int i, status;
        signal_player_group(SIGTERM);
        for (i = 0; i < 20; i++) {
            pid_t r = waitpid(g.player_pid, &status, WNOHANG);
            if (r == g.player_pid || r < 0)
                break;
            usleep(50000);
        }
        if (waitpid(g.player_pid, &status, WNOHANG) == 0) {
            signal_player_group(SIGKILL);
            waitpid(g.player_pid, &status, 0);
        }
        g.player_pid = 0;
    }

    g.active_player[0] = 0;
    g.attempted_players = 0;
    g.state = g.uri[0] ? STATE_STOPPED : STATE_NO_MEDIA;
    if (reset_position)
        g.position_base = 0;
    g.play_started = 0;
    write_status();
}

static int start_current(void)
{
    struct codec *codec;
    char volume_path[320];
    char mime[384], *first_mime;

    if (!g.uri[0] || !g.codec[0])
        return -1;
    codec = find_codec_id(g.codec);
    if (!codec)
        return -1;

    if (g.state == STATE_PAUSED) {
        if (g.player_pid <= 0 || signal_player_group(SIGCONT) < 0)
            return -1;
        g.state = STATE_PLAYING;
        g.play_started = time(NULL);
        write_status();
        return 0;
    }

    if (g.state == STATE_PLAYING)
        return 0;

    snprintf(volume_path, sizeof(volume_path), "%s/volume", g.runtime_dir);
    setenv("AUDIOWRT_URI", g.uri, 1);
    setenv("AUDIOWRT_CODEC", codec->id, 1);
    copystr(mime, sizeof(mime), codec->mime);
    first_mime = strtok(mime, " ,\t");
    setenv("AUDIOWRT_MIME", first_mime ? first_mime : "", 1);
    setenv("AUDIOWRT_ALSA_DEVICE", g.alsa_device, 1);
    setenv("AUDIOWRT_VOLUME_FILE", volume_path, 1);

    g.attempted_players = 0;
    if (launch_next_player(codec) < 0)
        return -1;

    g.state = STATE_PLAYING;
    g.play_started = time(NULL);
    write_status();
    return 0;
}

static int pause_current(void)
{
    if (g.state != STATE_PLAYING || g.player_pid <= 0)
        return -1;

    g.position_base = current_position();
    if (signal_player_group(SIGSTOP) < 0)
        return -1;

    g.state = STATE_PAUSED;
    g.play_started = 0;
    write_status();
    return 0;
}

static void reap_player(void)
{
    int status;
    pid_t r;

    if (g.player_pid <= 0)
        return;

    r = waitpid(g.player_pid, &status, WNOHANG);
    if (r != g.player_pid)
        return;

    g.player_pid = 0;

    if (g.state == STATE_PLAYING &&
        (!WIFEXITED(status) || WEXITSTATUS(status) != 0)) {
        struct codec *codec = find_codec_id(g.codec);
        if (launch_next_player(codec) == 0) {
            write_status();
            return;
        }
    }

    g.active_player[0] = 0;
    g.attempted_players = 0;
    if (g.state == STATE_PLAYING || g.state == STATE_PAUSED)
        g.state = g.uri[0] ? STATE_STOPPED : STATE_NO_MEDIA;
    g.play_started = 0;
    write_status();
    notify_service("AVTransport");
}

static void xml_escape_buf(const char *src, char *dst, size_t len)
{
    size_t used = 0;
    const char *s = src ? src : "";
    while (*s && used + 1 < len) {
        const char *r = NULL;
        switch (*s) {
