// lsp/jsonrpc.k — Content-Length framed JSON-RPC over stdio.
//
// Wire format (per LSP spec, mirroring vscode-jsonrpc):
//
//     Content-Length: <N>\r\n
//     \r\n
//     <N bytes of UTF-8 JSON body>
//
// We use a cfunc { } block to drop into setvbuf+fread for stdin, since
// Windows' default text-mode CRLF translation would mangle the body
// byte count. stdout is also switched to binary so our framing isn't
// corrupted.
//
// Public API:
//   jrInit()                  — once at startup; sets stdin/stdout binary.
//   jrReadFrame()             — blocks until next full frame, returns body.
//                               Returns "" on EOF.
//   jrWriteFrame(body)        — writes a Content-Length-prefixed frame.
//   jrLog(s)                  — stderr trace; LSP clients ignore stderr.

module jsonrpc

jxt {
    func krLspInit()
    func krLspReadFrame() -> char_ptr
    func krLspWriteFrame(body)
    func krLspLog(s)
}

cfunc {
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <io.h>
    #include <fcntl.h>

    static int g_inited = 0;

    char* krLspInit(void) {
        if (!g_inited) {
            // Defeat CRLF translation; binary mode preserves \r\n in headers
            // and clean byte counts in bodies.
            _setmode(_fileno(stdin), _O_BINARY);
            _setmode(_fileno(stdout), _O_BINARY);
            // Disable buffering on stdout so frames flush immediately.
            setvbuf(stdout, NULL, _IONBF, 0);
            // Line-buffer stderr so logs interleave readably.
            setvbuf(stderr, NULL, _IOLBF, 0);
            g_inited = 1;
        }
        return (char*)"1";
    }

    // Reads one JSON-RPC frame. Returns a malloc'd null-terminated string
    // containing the body. Returns NULL-equivalent (a static "") on EOF.
    char* krLspReadFrame(void) {
        char header[256];
        int contentLen = -1;

        for (;;) {
            int hi = 0;
            // Read one CRLF-terminated header line.
            for (;;) {
                int ch = fgetc(stdin);
                if (ch == EOF) return (char*)"";
                if (ch == '\r') {
                    int nx = fgetc(stdin);
                    if (nx == '\n') break;
                    if (nx == EOF) return (char*)"";
                    if (hi < (int)sizeof(header) - 2) {
                        header[hi++] = (char)ch;
                        header[hi++] = (char)nx;
                    }
                } else if (ch == '\n') {
                    // tolerate bare LF
                    break;
                } else {
                    if (hi < (int)sizeof(header) - 1) header[hi++] = (char)ch;
                }
            }
            header[hi] = 0;

            // Empty line — end of header block.
            if (hi == 0) break;

            // Parse "Content-Length: N"
            const char* prefix = "Content-Length:";
            size_t plen = strlen(prefix);
            if (hi >= (int)plen && _strnicmp(header, prefix, plen) == 0) {
                const char* p = header + plen;
                while (*p == ' ' || *p == '\t') p++;
                contentLen = atoi(p);
            }
            // Other headers (Content-Type) ignored.
        }

        if (contentLen < 0) return (char*)"";
        if (contentLen == 0) {
            char* empty = (char*)malloc(1);
            empty[0] = 0;
            return empty;
        }

        char* buf = (char*)malloc((size_t)contentLen + 1);
        if (!buf) return (char*)"";
        size_t got = 0;
        while (got < (size_t)contentLen) {
            size_t n = fread(buf + got, 1, (size_t)contentLen - got, stdin);
            if (n == 0) { free(buf); return (char*)""; }
            got += n;
        }
        buf[contentLen] = 0;
        return buf;
    }

    char* krLspWriteFrame(char* body) {
        if (!body) body = (char*)"";
        size_t n = strlen(body);
        fprintf(stdout, "Content-Length: %zu\r\n\r\n", n);
        fwrite(body, 1, n, stdout);
        fflush(stdout);
        return (char*)"1";
    }

    char* krLspLog(char* s) {
        if (s) fprintf(stderr, "[kls] %s\n", s);
        else   fprintf(stderr, "[kls] (null)\n");
        fflush(stderr);
        return (char*)"1";
    }
}

func jrInit()        { emit krLspInit() }
func jrReadFrame()   { emit krLspReadFrame() }
func jrWriteFrame(b) { emit krLspWriteFrame(b) }
func jrLog(s)        { emit krLspLog(s) }
