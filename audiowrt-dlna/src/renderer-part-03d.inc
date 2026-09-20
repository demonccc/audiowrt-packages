            char cl[64];
            size_t header_len = (size_t)(header_end + 4 - buf);
            if (header_value(buf, "Content-Length", cl, sizeof(cl)))
                need = header_len + (size_t)strtoul(cl, NULL, 10);
            else
                need = header_len;
            if (used >= need) break;
        }
    }
    return (int)used;
}

static bool avtransport_action_changes_state(const char *action)
{
    return !strcmp(action, "SetAVTransportURI") ||
           !strcmp(action, "Play") ||
           !strcmp(action, "Pause") ||
           !strcmp(action, "Stop");
}

static bool rendering_action_changes_state(const char *action)
{
    return !strcmp(action, "SetVolume") ||
           !strcmp(action, "SetMute");
}

static void handle_http_client(int fd, struct sockaddr_storage *peer)
{
    char *req = malloc(HTTP_BUFFER);
    char method[16], path[512], version[16], action_hdr[512], action[128];
    char *body, *hash, *quote;
    int n;
    if (!req) { close(fd); return; }
    n = read_http_request(fd, req, HTTP_BUFFER);
    if (n <= 0 || sscanf(req, "%15s %511s %15s", method, path, version) != 3) {
        free(req); close(fd); return;
    }
    body = strstr(req, "\r\n\r\n");
    if (body) body += 4; else body = req + n;

    if (!strcmp(method, "GET")) {
        if (!strcmp(path, "/description.xml")) http_reply(fd, 200, "text/xml", NULL, device_description());
        else if (!strcmp(path, "/avtransport.xml")) http_reply(fd, 200, "text/xml", NULL, avtransport_scpd());
        else if (!strcmp(path, "/renderingcontrol.xml")) http_reply(fd, 200, "text/xml", NULL, rendering_scpd());
        else if (!strcmp(path, "/connectionmanager.xml")) http_reply(fd, 200, "text/xml", NULL, connection_scpd());
        else http_reply(fd, 404, "text/plain", NULL, "Not found\n");
    } else if (!strcmp(method, "SUBSCRIBE") && !strncmp(path, "/event/", 7)) {
        handle_subscribe(fd, req, path + 7);
    } else if (!strcmp(method, "UNSUBSCRIBE") && !strncmp(path, "/event/", 7)) {
        handle_unsubscribe(fd, req);
    } else if (!strcmp(method, "POST") && !strncmp(path, "/control/", 9)) {
        set_controller(peer);
        write_status();
        action[0] = 0;
        if (header_value(req, "SOAPACTION", action_hdr, sizeof(action_hdr))) {
            hash = strrchr(action_hdr, '#');
            if (hash) {
                copystr(action, sizeof(action), hash + 1);
                quote = strchr(action, '"'); if (quote) *quote = 0;
                trim(action);
            }
        }
        if (!action[0]) soap_fault(fd, 401, "Invalid Action");
        else if (!strcmp(path + 9, "AVTransport")) {
            handle_avtransport(fd, action, body);
            if (avtransport_action_changes_state(action))
                notify_service("AVTransport");
        } else if (!strcmp(path + 9, "RenderingControl")) {
            handle_rendering(fd, action, body);
            if (rendering_action_changes_state(action))
                notify_service("RenderingControl");
        }
        else if (!strcmp(path + 9, "ConnectionManager")) handle_connection(fd, action);
        else soap_fault(fd, 401, "Invalid Action");
    } else {
        http_reply(fd, 404, "text/plain", NULL, "Not found\n");
    }
    free(req);
    close(fd);
}
