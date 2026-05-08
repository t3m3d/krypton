// stdlib/fs.k — filesystem helpers for Krypton.
//
// Things you can't do without a syscall: enumerate a directory,
// stat-check whether a path is a dir, etc. Pure-Krypton string ops
// (basename, dirname, join) live alongside the cfunc-backed ones —
// no DLL dance needed for those.
//
// Wire format for fsListDir:
//
//   "<type>\t<name>\n<type>\t<name>\n..."
//
// type is "D" for directory, "F" for file. Skips "." and "..".
// Entries are unsorted; caller can sort via builtin sort if desired.

module fs


jxt {
    func krFsListDir(path)              -> char_ptr
    func krFsIsDir(path)                -> char_ptr
    func krFsFileExists(path)           -> char_ptr
    func krFsMkdir(path)                -> char_ptr
    func krFsHexDump(path, maxBytes)    -> char_ptr
    func krFsLooksBinary(path)          -> char_ptr
}


cfunc {
#if defined(_WIN32)

    #ifndef _WIN32_WINNT
    #define _WIN32_WINNT 0x0601
    #endif
    #include <windows.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>

    static char* kr_fs_dup(const char* s) {
        size_t n = strlen(s);
        char* p = (char*)malloc(n + 1);
        if (!p) return (char*)"";
        memcpy(p, s, n + 1);
        return p;
    }

    __declspec(dllexport) char* krFsListDir(char* path) {
        if (!path || !*path) return (char*)"";
        // Build pattern: <path>\*
        size_t n = strlen(path);
        char* pattern = (char*)malloc(n + 4);
        if (!pattern) return (char*)"";
        memcpy(pattern, path, n);
        // Tolerate trailing slash either way.
        if (n > 0 && pattern[n - 1] != '\\' && pattern[n - 1] != '/') {
            pattern[n++] = '\\';
        }
        pattern[n++] = '*';
        pattern[n]   = '\0';

        WIN32_FIND_DATAA fd;
        HANDLE h = FindFirstFileA(pattern, &fd);
        free(pattern);
        if (h == INVALID_HANDLE_VALUE) return (char*)"";

        // Build result string. Cap at 1 MB to keep things sane.
        size_t cap = 4096, used = 0;
        char* out = (char*)malloc(cap);
        if (!out) { FindClose(h); return (char*)""; }
        out[0] = '\0';

        do {
            const char* name = fd.cFileName;
            if (name[0] == '.' && (name[1] == '\0' ||
                (name[1] == '.' && name[2] == '\0'))) {
                continue;
            }
            char type = (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ? 'D' : 'F';
            size_t nl = strlen(name);
            size_t need = used + 1 + 1 + nl + 1 + 1;   // type + \t + name + \n + NUL
            if (need > cap) {
                while (cap < need) cap *= 2;
                if (cap > 1048576) break;
                char* nu = (char*)realloc(out, cap);
                if (!nu) break;
                out = nu;
            }
            out[used++] = type;
            out[used++] = '\t';
            memcpy(out + used, name, nl);
            used += nl;
            out[used++] = '\n';
            out[used]   = '\0';
        } while (FindNextFileA(h, &fd));
        FindClose(h);

        char* dup = kr_fs_dup(out);
        free(out);
        return dup;
    }

    __declspec(dllexport) char* krFsIsDir(char* path) {
        if (!path) return (char*)"0";
        DWORD a = GetFileAttributesA(path);
        if (a == INVALID_FILE_ATTRIBUTES) return (char*)"0";
        return (a & FILE_ATTRIBUTE_DIRECTORY) ? (char*)"1" : (char*)"0";
    }

    __declspec(dllexport) char* krFsFileExists(char* path) {
        if (!path) return (char*)"0";
        DWORD a = GetFileAttributesA(path);
        return (a == INVALID_FILE_ATTRIBUTES) ? (char*)"0" : (char*)"1";
    }

    __declspec(dllexport) char* krFsMkdir(char* path) {
        if (!path) return (char*)"0";
        return CreateDirectoryA(path, NULL) ? (char*)"1" : (char*)"0";
    }

    // Sniff the first 1 KB for NUL bytes — if any present, treat
    // the file as binary. Cheap heuristic that handles UTF-8 text
    // (no embedded NULs) vs PE/object/image files (lots of NULs).
    __declspec(dllexport) char* krFsLooksBinary(char* path) {
        if (!path) return (char*)"0";
        FILE* f = fopen(path, "rb");
        if (!f) return (char*)"0";
        unsigned char buf[1024];
        size_t got = fread(buf, 1, sizeof(buf), f);
        fclose(f);
        for (size_t i = 0; i < got; i++) {
            if (buf[i] == 0) return (char*)"1";
        }
        return (char*)"0";
    }

    // Hex-dump up to maxBytes of `path` as a multi-line string in
    // the classic format:
    //
    //   00000000  4d 5a 90 00 03 00 00 00 04 00 00 00 ff ff 00 00  MZ..............
    //
    // 16 bytes per row. ASCII gutter renders printable bytes as
    // themselves and everything else as '.'. Caps maxBytes at
    // 4 MB so the IDE doesn't try to render a 1 GB iso.
    __declspec(dllexport) char* krFsHexDump(char* path, char* maxBytesStr) {
        if (!path) return (char*)"";
        int maxBytes = atoi(maxBytesStr ? maxBytesStr : "65536");
        if (maxBytes <= 0)        maxBytes = 65536;
        if (maxBytes > 4194304)   maxBytes = 4194304;

        FILE* f = fopen(path, "rb");
        if (!f) return (char*)"";

        unsigned char* bytes = (unsigned char*)malloc(maxBytes);
        if (!bytes) { fclose(f); return (char*)""; }
        int got = (int)fread(bytes, 1, (size_t)maxBytes, f);
        fclose(f);

        // Each 16-byte row is ~75 chars including \r\n. Allocate
        // accordingly.
        size_t cap = (size_t)((got / 16 + 2) * 80) + 256;
        char* out = (char*)malloc(cap);
        if (!out) { free(bytes); return (char*)""; }
        size_t pos = 0;

        const char* hex = "0123456789abcdef";
        int i = 0;
        while (i < got) {
            int rowLen = got - i;
            if (rowLen > 16) rowLen = 16;

            // 8-digit offset
            unsigned int off = (unsigned int)i;
            for (int s = 28; s >= 0; s -= 4) {
                out[pos++] = hex[(off >> s) & 0xF];
            }
            out[pos++] = ' ';
            out[pos++] = ' ';

            // 16 bytes hex (extra space mid-row at byte 8 for
            // readability).
            for (int b = 0; b < 16; b++) {
                if (b == 8) out[pos++] = ' ';
                if (b < rowLen) {
                    unsigned char v = bytes[i + b];
                    out[pos++] = hex[v >> 4];
                    out[pos++] = hex[v & 0xF];
                } else {
                    out[pos++] = ' ';
                    out[pos++] = ' ';
                }
                out[pos++] = ' ';
            }
            out[pos++] = ' ';

            // ASCII gutter
            for (int b = 0; b < rowLen; b++) {
                unsigned char v = bytes[i + b];
                out[pos++] = (v >= 32 && v < 127) ? (char)v : '.';
            }

            out[pos++] = '\r';
            out[pos++] = '\n';
            i += 16;
        }
        if (got >= maxBytes) {
            const char* tail = "\r\n[truncated]\r\n";
            size_t tlen = strlen(tail);
            if (pos + tlen < cap) { memcpy(out + pos, tail, tlen); pos += tlen; }
        }
        out[pos] = '\0';

        free(bytes);
        // Caller-managed: copy into a fresh small allocation, free
        // the oversized scratch.
        char* dup = (char*)malloc(pos + 1);
        if (!dup) { free(out); return (char*)""; }
        memcpy(dup, out, pos + 1);
        free(out);
        return dup;
    }

#else
    __declspec(dllexport) char* krFsListDir(char* p)         { (void)p; return (char*)""; }
    __declspec(dllexport) char* krFsIsDir(char* p)           { (void)p; return (char*)"0"; }
    __declspec(dllexport) char* krFsFileExists(char* p)      { (void)p; return (char*)"0"; }
    __declspec(dllexport) char* krFsMkdir(char* p)           { (void)p; return (char*)"0"; }
    __declspec(dllexport) char* krFsLooksBinary(char* p)     { (void)p; return (char*)"0"; }
    __declspec(dllexport) char* krFsHexDump(char* p, char* m){ (void)p;(void)m; return (char*)""; }
#endif
}


// ── Krypton public API ─────────────────────────────────────────

func fsListDir(path)         { emit krFsListDir(path) }
func fsIsDir(path)           { emit krFsIsDir(path) }
func fsFileExists(path)      { emit krFsFileExists(path) }
func fsMkdir(path)           { emit krFsMkdir(path) }
func fsLooksBinary(path)     { emit krFsLooksBinary(path) }
func fsHexDump(path, maxBytes) { emit krFsHexDump(path, maxBytes + "") }


// ── Pure-Krypton path helpers ─────────────────────────────────

func fsBaseName(path) {
    let i = len(path) - 1
    while i >= 0 {
        if path[i] == "\\" || path[i] == "/" { emit substring(path, i + 1, len(path)) }
        i -= 1
    }
    emit path
}

func fsDirName(path) {
    let i = len(path) - 1
    while i >= 0 {
        if path[i] == "\\" || path[i] == "/" { emit substring(path, 0, i) }
        i -= 1
    }
    emit ""
}

func fsJoin(a, b) {
    if len(a) == 0 { emit b }
    if len(b) == 0 { emit a }
    let last = a[len(a) - 1]
    if last == "\\" || last == "/" { emit a + b }
    emit a + "\\" + b
}

// Test if a name has one of the listed extensions (CSV).
func fsHasExt(name, extCsv) {
    let i = len(name) - 1
    while i >= 0 {
        if name[i] == "." {
            let ext = substring(name, i, len(name))
            if contains("," + extCsv + ",", "," + ext + ",") { emit "1" }
            emit "0"
        }
        i -= 1
    }
    emit "0"
}
