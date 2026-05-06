# macOS LSP Port Plan — kls on M1

Target: build `kls` (the Krypton Language Server) for macOS arm64 so the
LSP works in VS Code / Helix / Neovim on a Mac.

**Source of truth: Windows kls.exe (working).** All `.k` modules are
already cross-platform. Only one file needs OS-specific changes:

- `lsp/jsonrpc.k` — the `cfunc { }` block uses Windows-only `_setmode` /
  `_strnicmp`. Everything else is portable.

---

## What's portable as-is

These compile and run unchanged via `kcc.exe` C path on macOS once
jsonrpc.k is ported:

| File | Lines | Notes |
|------|------:|-------|
| `lsp/lex.k`         | ~225 | pure Krypton |
| `lsp/validate.k`    | ~210 | pure Krypton |
| `lsp/symbols.k`     | ~85  | pure Krypton |
| `lsp/complete.k`    | ~110 | pure Krypton |
| `lsp/json_parse.k`  | ~470 | pure Krypton |
| `lsp/json_emit.k`   | ~135 | pure Krypton |
| `lsp/kls.k`         | ~245 | pure Krypton |

---

## What needs porting

**Only [`lsp/jsonrpc.k`](../lsp/jsonrpc.k)**, specifically its `cfunc { }`
block. Strategy: detect platform with `#ifdef _WIN32` and provide both
paths in the same cfunc.

### Diff to apply

Replace the `cfunc { ... }` block in `lsp/jsonrpc.k` with this
cross-platform version:

```c
cfunc {
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #ifdef _WIN32
        #include <io.h>
        #include <fcntl.h>
        #define KR_STRNICMP _strnicmp
    #else
        #include <strings.h>     // strncasecmp
        #define KR_STRNICMP strncasecmp
    #endif

    static int g_inited = 0;

    char* krLspInit(void) {
        if (!g_inited) {
            #ifdef _WIN32
                _setmode(_fileno(stdin),  _O_BINARY);
                _setmode(_fileno(stdout), _O_BINARY);
            #endif
            // POSIX stdin/stdout are already byte-clean — no setmode needed.
            setvbuf(stdout, NULL, _IONBF, 0);
            setvbuf(stderr, NULL, _IOLBF, 0);
            g_inited = 1;
        }
        return (char*)"1";
    }

    char* krLspReadFrame(void) {
        char header[256];
        int contentLen = -1;
        for (;;) {
            int hi = 0;
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
                    break;
                } else {
                    if (hi < (int)sizeof(header) - 1) header[hi++] = (char)ch;
                }
            }
            header[hi] = 0;
            if (hi == 0) break;
            const char* prefix = "Content-Length:";
            size_t plen = strlen(prefix);
            if (hi >= (int)plen && KR_STRNICMP(header, prefix, plen) == 0) {
                const char* p = header + plen;
                while (*p == ' ' || *p == '\t') p++;
                contentLen = atoi(p);
            }
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
```

Two changes from the current Windows-only block:
1. `#ifdef _WIN32` gates `_setmode` (no-op on POSIX)
2. `KR_STRNICMP` macro picks `strncasecmp` on POSIX, `_strnicmp` on Windows

After this, `lsp/jsonrpc.k` builds on both platforms with the same source.

---

## Build on macOS

Pre-req: working macOS `kcc` binary (the one self-host pipeline produces
via [macho_arm64_self.k](../compiler/macos_arm64/macho_arm64_self.k)).

```bash
# from repo root
./kcc --headers headers/ lsp/kls.k > lsp/_kls.c
cc lsp/_kls.c -o kls
```

(macOS `cc` is clang; no `-w` needed but harmless. The `kr_tofloat`
const-discard warning that appears on Windows gcc may or may not show on
clang — ignore either way.)

Output: `kls` (no `.exe` extension) ~500 KB. Drop in repo root.

---

## Test on macOS

Both test drivers run unchanged once kls binary is built:

```bash
python3 lsp/test_kls.py        # path lookup uses kls or kls.exe
node lsp/test_extension.js     # same
```

You may need to update the path lookup in `test_kls.py` and
`test_extension.js` from `kls.exe` to `kls` on macOS, or write a
platform-aware lookup.

Expected output: same as Windows — initialize handshake, didOpen,
publishDiagnostics, documentSymbol, completion all working.

---

## VS Code wiring on macOS

The [krypton-lang extension](../krypton-lang/) bundles `kls.exe` for
Windows. To add macOS support:

**Option A (cleanest)**: ship a separate per-platform .vsix:
- `krypton-language-1.8.x-win32-x64.vsix` — bundles `kls.exe`
- `krypton-language-1.8.x-darwin-arm64.vsix` — bundles `kls`

This requires VS Code's [platform-specific extensions](https://code.visualstudio.com/api/working-with-extensions/publishing-extension#platformspecific-extensions) feature.

**Option B (quick & dirty)**: extension binary lookup falls back to PATH.
User builds `kls` on macOS, drops it in `/usr/local/bin/`, sets
`krypton.kls.path` in settings — done. Already supported by
[extension.js](../krypton-lang/extension.js)'s `findKlsBinary`.

Recommend Option B for now; revisit Option A if there's demand.

---

## Files to grep when porting fails

If the build dies on macOS, these are the suspects in priority order:

1. **`lsp/jsonrpc.k`** — only file with platform-specific code
2. **`bootstrap/kcc_seed.c`** — runtime helpers; uses `_alloc`,
   `kr_str`, etc. Should be portable but watch for `<windows.h>` includes
3. **kcc itself** — if the macOS kcc binary is older than 1.8.0, it
   may not understand some builtins. Rebuild via macho_arm64_self.k first

---

## Order-of-operations recommendation

If GC port is also pending, do it **first**:

1. macOS GC port → see [macos_gc_port_plan.md](macos_gc_port_plan.md)
2. macOS kls port → this doc

The GC port unblocks proper diagnostics (kls is a long-running process
and benefits from gcCheckpoint/gcRestore once macOS has them). You can
ship kls on macOS without GC, but it'll leak memory on long sessions
just like Windows kcc did pre-1.7.0.
