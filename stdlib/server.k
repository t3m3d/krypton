// server.k — cross-platform HTTP server for Krypton .htk web apps
// Windows: Winsock2 (ws2_32.dll)
// Linux / macOS / BSD / Unix: POSIX sockets
//
// Build:
//   Windows:  kcc app.htk > /tmp/app.c && gcc /tmp/app.c -o app.exe -lws2_32 -w
//   Linux:    kcc app.htk > /tmp/app.c && gcc /tmp/app.c -o app -w
//   macOS:    kcc app.htk > /tmp/app.c && clang /tmp/app.c -o app -w
//   Or:       khtk app.htk   (auto-detects platform)

module server

jxt {
    func _srvInit(port)
    func _srvNext()
    func _srvMethod()
    func _srvPath()
    func _srvQuery()
    func _srvBody()
    func _srvRespond(status, contentType, body)
    func _srvRespondFile(path)
    func _srvStop()
}

cfunc {
    #include <stdio.h>
    #include <string.h>
    #include <stdlib.h>

    #ifdef _WIN32
      #include <winsock2.h>
      #include <windows.h>
      typedef SOCKET kr_socket_t;
      #define KR_INVALID_SOCKET INVALID_SOCKET
      #define kr_closesocket closesocket
      #define kr_stricmp _stricmp
    #else
      #include <sys/socket.h>
      #include <netinet/in.h>
      #include <arpa/inet.h>
      #include <unistd.h>
      #include <fcntl.h>
      #include <strings.h>
      typedef int kr_socket_t;
      #define KR_INVALID_SOCKET (-1)
      #define kr_closesocket close
      #define kr_stricmp strcasecmp
    #endif

    #define KR_SRV_RBUF (1024 * 256)

    static kr_socket_t kr_srv_sock   = KR_INVALID_SOCKET;
    static kr_socket_t kr_srv_client = KR_INVALID_SOCKET;
    static char kr_srv_method[16]       = {0};
    static char kr_srv_path[1024]       = {0};
    static char kr_srv_query[2048]      = {0};
    static char kr_srv_body[KR_SRV_RBUF] = {0};

    static void kr_set_nonblocking(kr_socket_t s) {
    #ifdef _WIN32
        u_long nb = 1;
        ioctlsocket(s, FIONBIO, &nb);
    #else
        int flags = fcntl(s, F_GETFL, 0);
        fcntl(s, F_SETFL, flags | O_NONBLOCK);
    #endif
    }

    static void kr_set_blocking(kr_socket_t s) {
    #ifdef _WIN32
        u_long nb = 0;
        ioctlsocket(s, FIONBIO, &nb);
    #else
        int flags = fcntl(s, F_GETFL, 0);
        fcntl(s, F_SETFL, flags & ~O_NONBLOCK);
    #endif
    }

    char* _srvInit(char* port) {
    #ifdef _WIN32
        WSADATA wsa;
        WSAStartup(MAKEWORD(2,2), &wsa);
    #endif
        kr_srv_sock = socket(AF_INET, SOCK_STREAM, 0);
        int opt = 1;
        setsockopt(kr_srv_sock, SOL_SOCKET, SO_REUSEADDR, (char*)&opt, sizeof(opt));
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family      = AF_INET;
        addr.sin_port        = htons((unsigned short)atoi(port));
        addr.sin_addr.s_addr = INADDR_ANY;
        bind(kr_srv_sock, (struct sockaddr*)&addr, sizeof(addr));
        listen(kr_srv_sock, 16);
        kr_set_nonblocking(kr_srv_sock);
        fprintf(stderr, "server: http://127.0.0.1:%s\n", port);
        return (char*)"1";
    }

    char* _srvNext(void) {
        if (kr_srv_sock == KR_INVALID_SOCKET) return (char*)"";
        kr_socket_t c = accept(kr_srv_sock, NULL, NULL);
        if (c == KR_INVALID_SOCKET) return (char*)"";

        kr_set_blocking(c);

        static char buf[KR_SRV_RBUF];
        int n = recv(c, buf, KR_SRV_RBUF - 1, 0);
        if (n <= 0) { kr_closesocket(c); return (char*)""; }
        buf[n] = 0;

        char method[16] = {0}, path_raw[1024] = {0};
        char* line_end = strstr(buf, "\r\n");
        if (line_end) { char tmp = *line_end; *line_end = 0; sscanf(buf, "%15s %1023s", method, path_raw); *line_end = tmp; }
        else { sscanf(buf, "%15s %1023s", method, path_raw); }

        strncpy(kr_srv_method, method, 15);

        char* qmark = strchr(path_raw, '?');
        if (qmark) {
            *qmark = 0;
            strncpy(kr_srv_query, qmark + 1, 2047);
        } else {
            kr_srv_query[0] = 0;
        }
        strncpy(kr_srv_path, path_raw, 1023);

        char* body_start = strstr(buf, "\r\n\r\n");
        if (body_start) strncpy(kr_srv_body, body_start + 4, KR_SRV_RBUF - 1);
        else kr_srv_body[0] = 0;

        kr_srv_client = c;
        return (char*)"1";
    }

    char* _srvMethod(void) { return kr_srv_method; }
    char* _srvPath(void)   { return kr_srv_path; }
    char* _srvQuery(void)  { return kr_srv_query; }
    char* _srvBody(void)   { return kr_srv_body; }

    char* _srvRespond(char* status, char* contentType, char* body) {
        if (kr_srv_client == KR_INVALID_SOCKET) return (char*)"";
        int blen = (int)strlen(body);
        char hdr[512];
        snprintf(hdr, sizeof(hdr),
            "HTTP/1.1 %s\r\nContent-Type: %s; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n",
            status, contentType, blen);
        send(kr_srv_client, hdr,  (int)strlen(hdr), 0);
        send(kr_srv_client, body, blen, 0);
        kr_closesocket(kr_srv_client);
        kr_srv_client = KR_INVALID_SOCKET;
        return (char*)"";
    }

    static const char* kr_mime(const char* path) {
        const char* dot = strrchr(path, '.');
        if (!dot) return "application/octet-stream";
        if (kr_stricmp(dot, ".html") == 0 || kr_stricmp(dot, ".htk") == 0) return "text/html";
        if (kr_stricmp(dot, ".css")  == 0) return "text/css";
        if (kr_stricmp(dot, ".js")   == 0) return "application/javascript";
        if (kr_stricmp(dot, ".json") == 0) return "application/json";
        if (kr_stricmp(dot, ".png")  == 0) return "image/png";
        if (kr_stricmp(dot, ".jpg")  == 0 || kr_stricmp(dot, ".jpeg") == 0) return "image/jpeg";
        if (kr_stricmp(dot, ".gif")  == 0) return "image/gif";
        if (kr_stricmp(dot, ".svg")  == 0) return "image/svg+xml";
        if (kr_stricmp(dot, ".ico")  == 0) return "image/x-icon";
        if (kr_stricmp(dot, ".txt")  == 0) return "text/plain";
        if (kr_stricmp(dot, ".woff2")== 0) return "font/woff2";
        if (kr_stricmp(dot, ".woff") == 0) return "font/woff";
        if (kr_stricmp(dot, ".wasm") == 0) return "application/wasm";
        return "application/octet-stream";
    }

    char* _srvRespondFile(char* path) {
        if (kr_srv_client == KR_INVALID_SOCKET) return (char*)"0";
        FILE* f = fopen(path, "rb");
        if (!f) {
            const char* r404 = "HTTP/1.1 404 Not Found\r\nContent-Length: 13\r\n\r\n404 Not Found";
            send(kr_srv_client, r404, (int)strlen(r404), 0);
            kr_closesocket(kr_srv_client);
            kr_srv_client = KR_INVALID_SOCKET;
            return (char*)"0";
        }
        fseek(f, 0, SEEK_END);
        long flen = ftell(f);
        fseek(f, 0, SEEK_SET);
        char* fbuf = (char*)malloc(flen + 1);
        if (!fbuf) { fclose(f); return (char*)"0"; }
        fread(fbuf, 1, flen, f);
        fclose(f);

        const char* mime = kr_mime(path);
        char hdr[512];
        snprintf(hdr, sizeof(hdr),
            "HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %ld\r\nConnection: close\r\n\r\n",
            mime, flen);
        send(kr_srv_client, hdr,  (int)strlen(hdr), 0);
        send(kr_srv_client, fbuf, (int)flen, 0);
        free(fbuf);
        kr_closesocket(kr_srv_client);
        kr_srv_client = KR_INVALID_SOCKET;
        return (char*)"1";
    }

    char* _srvStop(void) {
        if (kr_srv_client != KR_INVALID_SOCKET) { kr_closesocket(kr_srv_client); kr_srv_client = KR_INVALID_SOCKET; }
        if (kr_srv_sock   != KR_INVALID_SOCKET) { kr_closesocket(kr_srv_sock);   kr_srv_sock   = KR_INVALID_SOCKET; }
    #ifdef _WIN32
        WSACleanup();
    #endif
        return (char*)"";
    }
}

// ── Krypton-side API ──────────────────────────────────────────────────────

func serverInit(port)     { _srvInit(port) }
func serverStop()         { _srvStop() }
func serverNext()         { emit _srvNext() }
func serverReqMethod()    { emit _srvMethod() }
func serverReqPath()      { emit _srvPath() }
func serverReqQuery()     { emit _srvQuery() }
func serverReqBody()      { emit _srvBody() }

func serverRespond(html)              { _srvRespond("200 OK", "text/html", html) }
func serverRespondJSON(json)          { _srvRespond("200 OK", "application/json", json) }
func serverRespondText(text)          { _srvRespond("200 OK", "text/plain", text) }
func serverRespondFile(path)          { emit _srvRespondFile(path) }
func serverRespond404()               { _srvRespond("404 Not Found", "text/html", "<h1>404 Not Found</h1>") }
func serverRedirect(url)              { _srvRespond("302 Found", "text/html", "") }
func serverRespondWith(status, ct, b) { _srvRespond(status, ct, b) }

// ── URL decode ────────────────────────────────────────────────────────────

func _srvHexVal(c) {
    if c >= "0" && c <= "9" { emit charCode(c) - charCode("0") }
    if c >= "a" && c <= "f" { emit charCode(c) - charCode("a") + 10 }
    if c >= "A" && c <= "F" { emit charCode(c) - charCode("A") + 10 }
    emit 0
}

func urlDecode(s) {
    let out = sbNew()
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == "+" {
            out = sbAppend(out, " ")
            i += 1
        } else if c == "%" && i + 2 < len(s) {
            let hi = _srvHexVal(s[i + 1])
            let lo = _srvHexVal(s[i + 2])
            out = sbAppend(out, fromCharCode(hi * 16 + lo))
            i += 3
        } else {
            out = sbAppend(out, c)
            i += 1
        }
    }
    emit sbToString(out)
}

// ── Query / form param parsing ────────────────────────────────────────────

func queryParam(qs, key) {
    let i = 0
    let n = len(qs)
    while i < n {
        let eq = indexOf(substring(qs, i, n), "=")
        if eq < 0 { emit "" }
        eq += i
        let k = urlDecode(substring(qs, i, eq))
        let amp = indexOf(substring(qs, eq + 1, n), "&")
        let vEnd = n
        if amp >= 0 { vEnd = eq + 1 + amp }
        let v = urlDecode(substring(qs, eq + 1, vEnd))
        if k == key { emit v }
        i = vEnd + 1
    }
    emit ""
}

func queryParamAll(qs, key) {
    let out = ""
    let i = 0
    let n = len(qs)
    while i < n {
        let eq = indexOf(substring(qs, i, n), "=")
        if eq < 0 { emit out }
        eq += i
        let k = urlDecode(substring(qs, i, eq))
        let amp = indexOf(substring(qs, eq + 1, n), "&")
        let vEnd = n
        if amp >= 0 { vEnd = eq + 1 + amp }
        let v = urlDecode(substring(qs, eq + 1, vEnd))
        if k == key {
            if len(out) > 0 { out = out + "," }
            out = out + v
        }
        i = vEnd + 1
    }
    emit out
}
