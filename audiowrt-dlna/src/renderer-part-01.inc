static void apply_player_overrides(struct uci_context *ctx, struct uci_package *pkg)
{
    struct uci_element *e;
    uci_foreach_element(&pkg->sections, e) {
        struct uci_section *s = uci_to_section(e);
        const char *codec, *command, *v;
        struct player *p;
        if (strcmp(s->type, "player"))
            continue;
        codec = uci_opt(ctx, s, "codec");
        command = uci_opt(ctx, s, "command");
        if (!codec || !*codec || !command || !*command)
            continue;
        v = uci_opt(ctx, s, "enabled");
        if (!parse_bool(v, 1))
            continue;
        p = find_player_id(codec);
        if (!p && g.player_count < MAX_PLAYERS) {
            p = &g.players[g.player_count++];
            memset(p, 0, sizeof(*p));
            copystr(p->id, sizeof(p->id), codec);
            copystr(p->name, sizeof(p->name), codec);
        }
        if (!p)
            continue;
        p->custom = true;
        p->managed = parse_bool(uci_opt(ctx, s, "managed"), 0);
        copystr(p->command, sizeof(p->command), command);
        v = uci_opt(ctx, s, "pause_command");
        if (v) copystr(p->pause_command, sizeof(p->pause_command), v);
        v = uci_opt(ctx, s, "resume_command");
        if (v) copystr(p->resume_command, sizeof(p->resume_command), v);
        v = uci_opt(ctx, s, "stop_command");
        if (v) copystr(p->stop_command, sizeof(p->stop_command), v);
        v = uci_opt(ctx, s, "mime");
        if (v && *v) copystr(p->mime, sizeof(p->mime), v);
        v = uci_opt(ctx, s, "extensions");
        if (v && *v) copystr(p->extensions, sizeof(p->extensions), v);
    }
}

static int load_config(void)
{
    struct uci_context *ctx;
    struct uci_package *pkg = NULL;
    struct uci_element *e;

    memset(&g, 0, sizeof(g));
    copystr(g.friendly_name, sizeof(g.friendly_name), "AudioWRT");
    copystr(g.player_dir, sizeof(g.player_dir), DEFAULT_PLAYER_DIR);
    copystr(g.runtime_dir, sizeof(g.runtime_dir), DEFAULT_RUNTIME_DIR);
    copystr(g.alsa_device, sizeof(g.alsa_device), "default");
    g.port = DEFAULT_PORT;
    g.volume = 100;
    g.state = STATE_NO_MEDIA;

    ctx = uci_alloc_context();
    if (!ctx)
        return -1;
    if (uci_load(ctx, "audiowrt-dlna", &pkg) != UCI_OK) {
        uci_free_context(ctx);
        return -1;
    }

    uci_foreach_element(&pkg->sections, e) {
        struct uci_section *s = uci_to_section(e);
        const char *v;
        if (strcmp(s->type, "renderer") && strcmp(s->e.name, "main"))
            continue;
        v = uci_opt(ctx, s, "friendly_name"); if (v) copystr(g.friendly_name, sizeof(g.friendly_name), v);
        v = uci_opt(ctx, s, "uuid"); if (v) copystr(g.uuid, sizeof(g.uuid), v);
        v = uci_opt(ctx, s, "player_dir"); if (v) copystr(g.player_dir, sizeof(g.player_dir), v);
        v = uci_opt(ctx, s, "runtime_dir"); if (v) copystr(g.runtime_dir, sizeof(g.runtime_dir), v);
        v = uci_opt(ctx, s, "alsa_device"); if (v) copystr(g.alsa_device, sizeof(g.alsa_device), v);
        v = uci_opt(ctx, s, "port"); if (v) g.port = atoi(v);
        v = uci_opt(ctx, s, "volume"); if (v) g.volume = atoi(v);
        break;
    }
    if (g.port < 1024 || g.port > 65535)
        g.port = DEFAULT_PORT;
    if (g.volume < 0) g.volume = 0;
    if (g.volume > 100) g.volume = 100;

    load_descriptors();
    apply_player_overrides(ctx, pkg);
    uci_unload(ctx, pkg);
    uci_free_context(ctx);

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
