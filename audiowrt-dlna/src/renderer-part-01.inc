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
    else if (!strcmp(key, "player_dir"))
        copystr(g.player_dir, sizeof(g.player_dir), value);
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

static void commit_player_override(struct player *override, bool enabled)
{
    struct player *p;

    if (!enabled || !override->id[0] || !override->command[0])
        return;

    p = find_player_id(override->id);
    if (!p && g.player_count < MAX_PLAYERS) {
        p = &g.players[g.player_count++];
        memset(p, 0, sizeof(*p));
        copystr(p->id, sizeof(p->id), override->id);
        copystr(p->name, sizeof(p->name), override->id);
    }
    if (!p)
        return;

    p->custom = true;
    p->managed = override->managed;
    copystr(p->command, sizeof(p->command), override->command);
    if (override->pause_command[0])
        copystr(p->pause_command, sizeof(p->pause_command), override->pause_command);
    if (override->resume_command[0])
        copystr(p->resume_command, sizeof(p->resume_command), override->resume_command);
    if (override->stop_command[0])
        copystr(p->stop_command, sizeof(p->stop_command), override->stop_command);
    if (override->mime[0])
        copystr(p->mime, sizeof(p->mime), override->mime);
    if (override->extensions[0])
        copystr(p->extensions, sizeof(p->extensions), override->extensions);
}

static int load_player_overrides(const char *path)
{
    FILE *f = fopen(path, "r");
    char line[2048];
    struct player override;
    bool in_player = false;
    bool enabled = true;

    if (!f)
        return -1;

    memset(&override, 0, sizeof(override));
    while (fgets(line, sizeof(line), f)) {
        char *cursor = line;
        char directive[32], type[64], ignored_name[128], key[128], value[1536];

        if (!config_next_token(&cursor, directive, sizeof(directive)))
            continue;

        if (!strcmp(directive, "config")) {
            if (in_player)
                commit_player_override(&override, enabled);

            type[0] = ignored_name[0] = 0;
            config_next_token(&cursor, type, sizeof(type));
            config_next_token(&cursor, ignored_name, sizeof(ignored_name));
            in_player = !strcmp(type, "player");
            memset(&override, 0, sizeof(override));
            enabled = true;
            continue;
        }

        if (!in_player || strcmp(directive, "option"))
            continue;
        if (!config_next_token(&cursor, key, sizeof(key)) ||
            !config_next_token(&cursor, value, sizeof(value)))
            continue;

        if (!strcmp(key, "codec"))
            copystr(override.id, sizeof(override.id), value);
        else if (!strcmp(key, "command"))
            copystr(override.command, sizeof(override.command), value);
        else if (!strcmp(key, "enabled"))
            enabled = parse_bool(value, 1);
        else if (!strcmp(key, "managed"))
            override.managed = parse_bool(value, 0);
        else if (!strcmp(key, "pause_command"))
            copystr(override.pause_command, sizeof(override.pause_command), value);
        else if (!strcmp(key, "resume_command"))
            copystr(override.resume_command, sizeof(override.resume_command), value);
        else if (!strcmp(key, "stop_command"))
            copystr(override.stop_command, sizeof(override.stop_command), value);
        else if (!strcmp(key, "mime"))
            copystr(override.mime, sizeof(override.mime), value);
        else if (!strcmp(key, "extensions"))
            copystr(override.extensions, sizeof(override.extensions), value);
    }

    if (in_player)
        commit_player_override(&override, enabled);
    fclose(f);
    return 0;
}

static int load_config(void)
{
    const char *path = "/etc/config/audiowrt-dlna";

    memset(&g, 0, sizeof(g));
    copystr(g.friendly_name, sizeof(g.friendly_name), "AudioWRT");
    copystr(g.player_dir, sizeof(g.player_dir), DEFAULT_PLAYER_DIR);
    copystr(g.runtime_dir, sizeof(g.runtime_dir), DEFAULT_RUNTIME_DIR);
    copystr(g.alsa_device, sizeof(g.alsa_device), "default");
    g.port = DEFAULT_PORT;
    g.volume = 100;
    g.state = STATE_NO_MEDIA;

    if (load_renderer_options(path) < 0)
        return -1;

    if (g.port < 1024 || g.port > 65535)
        g.port = DEFAULT_PORT;
    if (g.volume < 0) g.volume = 0;
    if (g.volume > 100) g.volume = 100;

    load_descriptors();
    if (load_player_overrides(path) < 0)
        return -1;

    if (!g.uuid[0])
        copystr(g.uuid, sizeof(g.uuid), "00000000-0000-0000-0000-000000000000");
    mkdir_runtime();
    return 0;
}

static void print_players_json(void)
{
    size_t i;
    putchar('[');
    for (i = 0; i < g.player_count; i++) {
        struct player *p = &g.players[i];
        if (i) putchar(',');
        fputs("{\"id\":\"", stdout); json_escape(stdout, p->id);
        fputs("\",\"name\":\"", stdout); json_escape(stdout, p->name);
        fputs("\",\"mode\":\"", stdout); fputs(p->custom ? "custom" : "automatic", stdout);
        fputs("\",\"command\":\"", stdout); json_escape(stdout, p->command);
        fputs("\",\"auto_command\":\"", stdout); json_escape(stdout, p->auto_command);
        fputs("\",\"package\":\"", stdout); json_escape(stdout, p->package);
        fputs("\",\"mime\":\"", stdout); json_escape(stdout, p->mime);
        fputs("\",\"extensions\":\"", stdout); json_escape(stdout, p->extensions);
        fprintf(stdout, "\",\"available\":%s,\"managed\":%s}",
                (!p->custom && access(p->command, X_OK) == 0) || p->custom ? "true" : "false",
                p->managed ? "true" : "false");
    }
    puts("]");
}

static struct player *player_for_uri(const char *uri, const char *metadata)
{
    size_t i;
    char ext[32] = "";
    const char *q, *dot, *slash;

    for (i = 0; i < g.player_count; i++) {
        char copy[384], *save = NULL, *tok;
        copystr(copy, sizeof(copy), g.players[i].mime);
        for (tok = strtok_r(copy, " ,\t", &save); tok; tok = strtok_r(NULL, " ,\t", &save))
            if (metadata && *metadata && strcasestr(metadata, tok))
                return &g.players[i];
    }

    q = uri ? strchr(uri, '?') : NULL;
    slash = uri ? strrchr(uri, '/') : NULL;
    dot = uri ? strrchr(uri, '.') : NULL;
    if (dot && (!slash || dot > slash) && (!q || dot < q)) {
        size_t n = q ? (size_t)(q - dot - 1) : strlen(dot + 1);
        if (n >= sizeof(ext)) n = sizeof(ext) - 1;
        memcpy(ext, dot + 1, n);
        ext[n] = 0;
        for (i = 0; ext[i]; i++) ext[i] = (char)tolower((unsigned char)ext[i]);
        for (i = 0; i < g.player_count; i++)
            if (token_in_list(g.players[i].extensions, ext))
                return &g.players[i];
    }
    return NULL;
}

static int shell_command(const char *command, bool wait_child)
{
    pid_t pid;
    int status = 0;
    if (!command || !*command)
        return -1;
    pid = fork();
    if (pid < 0)
        return -1;
    if (pid == 0) {
        execl("/bin/sh", "sh", "-c", command, (char *)NULL);
        _exit(127);
    }
    if (wait_child) {
        if (waitpid(pid, &status, 0) < 0)
            return -1;
        return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : -1;
    }
    return 0;
}

static void stop_current(bool reset_position)
{
    struct player *p = g.codec[0] ? find_player_id(g.codec) : NULL;
    if (p && p->custom && p->stop_command[0])
        shell_command(p->stop_command, true);

    if (g.player_pid > 0) {
        int i, status;
        kill(g.player_pid, SIGTERM);
        for (i = 0; i < 20; i++) {
            pid_t r = waitpid(g.player_pid, &status, WNOHANG);
            if (r == g.player_pid || r < 0)
                break;
            usleep(50000);
        }
        if (waitpid(g.player_pid, &status, WNOHANG) == 0) {
            kill(g.player_pid, SIGKILL);
            waitpid(g.player_pid, &status, 0);
        }
        g.player_pid = 0;
    }
    g.state = g.uri[0] ? STATE_STOPPED : STATE_NO_MEDIA;
    if (reset_position)
        g.position_base = 0;
    g.play_started = 0;
    write_status();
}

static int start_current(void)
{
    struct player *p;
    char volume_path[320];

    if (!g.uri[0] || !g.codec[0])
        return -1;
    p = find_player_id(g.codec);
    if (!p || !p->command[0])
        return -1;

    if (g.state == STATE_PAUSED) {
        if (p->custom && p->resume_command[0]) {
            if (shell_command(p->resume_command, true) < 0)
                return -1;
        } else if (g.player_pid > 0) {
            kill(g.player_pid, SIGCONT);
        }
        g.state = STATE_PLAYING;
        g.play_started = time(NULL);
        write_status();
        return 0;
    }

    if (g.state == STATE_PLAYING)
        return 0;

    snprintf(volume_path, sizeof(volume_path), "%s/volume", g.runtime_dir);
    setenv("AUDIOWRT_URI", g.uri, 1);
    setenv("AUDIOWRT_ALSA_DEVICE", g.alsa_device, 1);
    setenv("AUDIOWRT_VOLUME_FILE", volume_path, 1);

    if (p->custom) {
        if (p->managed) {
            pid_t pid = fork();
            if (pid < 0) return -1;
            if (pid == 0) {
                execl("/bin/sh", "sh", "-c", p->command, (char *)NULL);
                _exit(127);
            }
            g.player_pid = pid;
        } else if (shell_command(p->command, true) < 0) {
            return -1;
        }
    } else {
        pid_t pid = fork();
        if (pid < 0) return -1;
        if (pid == 0) {
            execl(p->command, p->command, g.uri, (char *)NULL);
            _exit(127);
        }
        g.player_pid = pid;
    }

    g.state = STATE_PLAYING;
    g.play_started = time(NULL);
    write_status();
    return 0;
}

static int pause_current(void)
{
    struct player *p;
    if (g.state != STATE_PLAYING)
        return -1;
    p = find_player_id(g.codec);
    g.position_base = current_position();
    if (p && p->custom && p->pause_command[0]) {
        if (shell_command(p->pause_command, true) < 0)
            return -1;
    } else if (g.player_pid > 0) {
        kill(g.player_pid, SIGSTOP);
    } else {
        return -1;
    }
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
    if (r == g.player_pid) {
        g.player_pid = 0;
        if (g.state == STATE_PLAYING || g.state == STATE_PAUSED)
            g.state = g.uri[0] ? STATE_STOPPED : STATE_NO_MEDIA;
        g.play_started = 0;
        write_status();
        notify_service("AVTransport");
    }
}

static void xml_escape_buf(const char *src, char *dst, size_t len)
{
    size_t used = 0;
    const char *s = src ? src : "";
    while (*s && used + 1 < len) {
        const char *r = NULL;
        switch (*s) {
