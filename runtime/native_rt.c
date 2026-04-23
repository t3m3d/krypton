/* Krypton native runtime — minimal, position-independent, no libc */
/* Compiled with: gcc -c -O1 -fno-stack-protector -mno-stack-arg-probe native_rt.c -o native_rt.o */
/* All functions use Windows x64 ABI */

#include <stddef.h>
#include <stdint.h>

/* ── Windows API imports (called via IAT) ─────────────────────────── */
extern void*    __imp_GetStdHandle;
extern void*    __imp_WriteFile;
extern void*    __imp_ExitProcess;
extern void*    __imp_VirtualAlloc;
extern void*    __imp_GetProcessHeap;
extern void*    __imp_HeapAlloc;
extern void*    __imp_HeapFree;
extern void*    __imp_HeapReAlloc;
extern void*    __imp_GetEnvironmentVariableA;

typedef unsigned long DWORD;
typedef unsigned long long QWORD;
typedef void* HANDLE;
typedef int BOOL;

#define STD_OUTPUT_HANDLE ((DWORD)-11)
#define STD_ERROR_HANDLE  ((DWORD)-12)
#define MEM_COMMIT  0x1000
#define MEM_RESERVE 0x2000
#define PAGE_READWRITE 0x04

/* ── Heap allocator ──────────────────────────────────────────────── */
/* Each allocation has an 8-byte header: [uint32 magic][uint32 pad]  */
/* magic = 0xABCDABCD → ptr is heap-allocated (can HeapReAlloc it)  */
/* Only used for StringBuilder internal buffers (need HeapReAlloc).  */
#define _HEAP_MAGIC 0xABCDABCDu

static void* _kheap = 0;

static void* _get_heap(void) {
    if (!_kheap) {
        typedef void* (*GH_t)(void);
        _kheap = ((GH_t)__imp_GetProcessHeap)();
    }
    return _kheap;
}

static char* _alloc(int n) {
    typedef char* (*HA_t)(void*, unsigned int, size_t);
    if (n < 1) n = 1;
    char* raw = ((HA_t)__imp_HeapAlloc)(_get_heap(), 0, (size_t)n + 8);
    if (!raw) { volatile int* p = 0; *p = 0; }
    *((unsigned int*)raw)       = _HEAP_MAGIC;
    *((unsigned int*)(raw + 4)) = (unsigned int)n;
    return raw + 8;
}

/* ── Arena allocator ─────────────────────────────────────────────── */
/* All short-lived string results (kr_plus, kr_str, etc.) go here.  */
/* Never freed individually — whole slabs released at process exit.  */
#define _ARENA_SLAB (64 * 1024 * 1024)

static char* _ar_cur  = NULL;
static char* _ar_end  = NULL;

static char* _arena_alloc(int n) {
    typedef char* (*HA_t)(void*, unsigned int, size_t);
    if (n < 1) n = 1;
    n = (n + 7) & ~7;  /* align to 8 bytes */
    if (!_ar_cur || _ar_cur + n > _ar_end) {
        size_t sz = (size_t)n > _ARENA_SLAB ? (size_t)n : _ARENA_SLAB;
        _ar_cur = ((HA_t)__imp_HeapAlloc)(_get_heap(), 0, sz);
        if (!_ar_cur) { volatile int* p = 0; *p = 0; }
        _ar_end = _ar_cur + sz;
    }
    char* p = _ar_cur;
    _ar_cur += n;
    return p;
}

/* True if s was returned by _alloc (heap-allocated, has magic header) */
static int _is_heap(const char* s) {
    return *((const unsigned int*)(s - 8)) == _HEAP_MAGIC;
}

/* Grow a heap-allocated string's buffer to newsize bytes of content */
static char* _realloc_heap(char* s, int newsize) {
    typedef char* (*HR_t)(void*, unsigned int, void*, size_t);
    if (newsize < 1) newsize = 1;
    char* raw    = s - 8;
    char* newraw = ((HR_t)__imp_HeapReAlloc)(_get_heap(), 0, raw, (size_t)newsize + 8);
    if (!newraw) { volatile int* p = 0; *p = 0; }
    *((unsigned int*)newraw)       = _HEAP_MAGIC;
    *((unsigned int*)(newraw + 4)) = (unsigned int)newsize;
    return newraw + 8;
}

/* ── String constants ─────────────────────────────────────────────── */
static char _K_EMPTY[] = "";
static char _K_ZERO[]  = "0";
static char _K_ONE[]   = "1";

/* ── strlen (no libc) ─────────────────────────────────────────────── */
static int _kstrlen(const char* s) {
    int n = 0;
    while (s[n]) n++;
    return n;
}

/* ── memcpy (no libc) ─────────────────────────────────────────────── */
static void _kmemcpy(char* dst, const char* src, int n) {
    for (int i = 0; i < n; i++) dst[i] = src[i];
}

/* ── atoi (no libc) ──────────────────────────────────────────────── */
static int _katoi(const char* s) {
    int neg = 0, v = 0;
    if (!s) return 0;
    if (*s == '-') { neg = 1; s++; }
    while (*s >= '0' && *s <= '9') { v = v * 10 + (*s - '0'); s++; }
    return neg ? -v : v;
}

/* ── itoa (no libc) ──────────────────────────────────────────────── */
static char* _kitoa(int v) {
    if (v == 0) return _K_ZERO;
    if (v == 1) return _K_ONE;
    char buf[24];
    int neg = 0, n;
    if (v < 0) { neg = 1; v = -v; }
    int i = 23; buf[i] = 0;
    while (v > 0) { buf[--i] = (char)('0' + (v % 10)); v /= 10; }
    if (neg) buf[--i] = '-';
    /* inline kr_str to avoid forward-decl issue */
    n = _kstrlen(buf + i) + 1;
    char* p = _arena_alloc(n);
    _kmemcpy(p, buf + i, n);
    return p;
}

/* ── isnum ────────────────────────────────────────────────────────── */
static int _kisnum(const char* s) {
    if (!s || !*s) return 0;
    const char* p = s;
    if (*p == '-') p++;
    if (!*p) return 0;
    while (*p) { if (*p < '0' || *p > '9') return 0; p++; }
    return 1;
}

/* ── Runtime API ──────────────────────────────────────────────────── */

char* kr_str(const char* s) {
    if (!s || !*s) return _K_EMPTY;
    if (s[0]=='0' && !s[1]) return _K_ZERO;
    if (s[0]=='1' && !s[1]) return _K_ONE;
    int n = _kstrlen(s) + 1;
    char* p = _arena_alloc(n);
    _kmemcpy(p, s, n);
    return p;
}

char* kr_plus(const char* a, const char* b) {
    if (_kisnum(a) && _kisnum(b))
        return _kitoa(_katoi(a) + _katoi(b));
    /* concat */
    int la = _kstrlen(a), lb = _kstrlen(b);
    if (lb == 0) return (char*)a;
    if (la == 0) {
        /* a is empty — fresh heap copy of b */
        char* p = _arena_alloc(lb + 1);
        _kmemcpy(p, b, lb + 1);
        return p;
    }
    /* always fresh alloc — HeapReAlloc would invalidate caller's reference to a */
    char* p = _arena_alloc(la + lb + 1);
    _kmemcpy(p, a, la);
    _kmemcpy(p + la, b, lb + 1);
    return p;
}

char* kr_sub(const char* a, const char* b) { return _kitoa(_katoi(a) - _katoi(b)); }
char* kr_mul(const char* a, const char* b) { return _kitoa(_katoi(a) * _katoi(b)); }
char* kr_div(const char* a, const char* b) {
    int bv = _katoi(b);
    if (bv == 0) return _K_ZERO;
    return _kitoa(_katoi(a) / bv);
}
char* kr_mod(const char* a, const char* b) {
    int bv = _katoi(b);
    if (bv == 0) return _K_ZERO;
    return _kitoa(_katoi(a) % bv);
}
char* kr_neg(const char* a)  { return _kitoa(-_katoi(a)); }

static int _kr_truthy_int(const char* s) {
    if (!s || !*s) return 0;
    if (s[0]=='0' && !s[1]) return 0;
    return 1;
}
char* kr_truthy(const char* s) { return _kr_truthy_int(s) ? _K_ONE : _K_ZERO; }

char* kr_eq(const char* a, const char* b) {
    int i = 0;
    while (a[i] && b[i] && a[i]==b[i]) i++;
    return (a[i]==b[i]) ? _K_ONE : _K_ZERO;
}
char* kr_neq(const char* a, const char* b) { return _kr_truthy_int(kr_eq(a,b)) ? _K_ZERO : _K_ONE; }

/* strcmp (no libc) */
static int _kstrcmp(const char* a, const char* b) {
    while (*a && *b && *a == *b) { a++; b++; }
    return (unsigned char)*a - (unsigned char)*b;
}

/* Comparisons: numeric if both are numbers, else lexicographic (like C runtime) */
char* kr_lt(const char* a, const char* b) {
    if (_kisnum(a) && _kisnum(b)) return _katoi(a) < _katoi(b) ? _K_ONE : _K_ZERO;
    return _kstrcmp(a, b) < 0 ? _K_ONE : _K_ZERO;
}
char* kr_gt(const char* a, const char* b) {
    if (_kisnum(a) && _kisnum(b)) return _katoi(a) > _katoi(b) ? _K_ONE : _K_ZERO;
    return _kstrcmp(a, b) > 0 ? _K_ONE : _K_ZERO;
}
char* kr_lte(const char* a, const char* b) {
    if (_kisnum(a) && _kisnum(b)) return _katoi(a) <= _katoi(b) ? _K_ONE : _K_ZERO;
    return _kstrcmp(a, b) <= 0 ? _K_ONE : _K_ZERO;
}
char* kr_gte(const char* a, const char* b) {
    if (_kisnum(a) && _kisnum(b)) return _katoi(a) >= _katoi(b) ? _K_ONE : _K_ZERO;
    return _kstrcmp(a, b) >= 0 ? _K_ONE : _K_ZERO;
}

static void _write_handle(HANDLE h, const char* s) {
    int len = _kstrlen(s);
    if (len == 0) return;
    DWORD written;
    typedef BOOL (*WriteFile_t)(HANDLE,const void*,DWORD,DWORD*,void*);
    WriteFile_t wf = (WriteFile_t)__imp_WriteFile;
    wf(h, s, (DWORD)len, &written, 0);
    wf(h, "\n", 1, &written, 0);
}

char* kr_print(const char* s) {
    typedef HANDLE (*GSH_t)(DWORD);
    GSH_t gsh = (GSH_t)__imp_GetStdHandle;
    _write_handle(gsh(STD_OUTPUT_HANDLE), s);
    return _K_EMPTY;
}

char* kr_printerr(const char* s) {
    typedef HANDLE (*GSH_t)(DWORD);
    GSH_t gsh = (GSH_t)__imp_GetStdHandle;
    _write_handle(gsh(STD_ERROR_HANDLE), s);
    return _K_EMPTY;
}

char* kr_exit(const char* code) {
    typedef void (*EP_t)(DWORD);
    EP_t ep = (EP_t)__imp_ExitProcess;
    ep((DWORD)_katoi(code));
    return _K_EMPTY;
}

/* ── Extended builtins ────────────────────────────────────────────── */

char* kr_len(const char* s) { return _kitoa(_kstrlen(s)); }

char* kr_idx(const char* s, const char* is) {
    int i = _katoi(is);
    if (i < 0 || !s[i]) return _K_EMPTY;
    char buf[2]; buf[0] = s[i]; buf[1] = 0;
    char* p = _arena_alloc(2); p[0] = s[i]; p[1] = 0;
    return p;
}

char* kr_substring(const char* s, const char* starts, const char* ends) {
    int st = _katoi(starts), en = _katoi(ends);
    int sl = _kstrlen(s);
    if (st < 0) st = 0;
    if (en > sl) en = sl;
    if (st >= en) return _K_EMPTY;
    int n = en - st;
    char* p = _arena_alloc(n + 1);
    _kmemcpy(p, s + st, n);
    p[n] = 0;
    return p;
}

char* kr_startswith(const char* s, const char* prefix) {
    int i = 0;
    while (prefix[i] && s[i] == prefix[i]) i++;
    return prefix[i] == 0 ? _K_ONE : _K_ZERO;
}

char* kr_contains(const char* haystack, const char* needle) {
    int hl = _kstrlen(haystack), nl = _kstrlen(needle);
    if (nl == 0) return _K_ONE;
    for (int i = 0; i <= hl - nl; i++) {
        int j = 0;
        while (j < nl && haystack[i+j] == needle[j]) j++;
        if (j == nl) return _K_ONE;
    }
    return _K_ZERO;
}

char* kr_indexof(const char* haystack, const char* needle) {
    int hl = _kstrlen(haystack), nl = _kstrlen(needle);
    if (nl == 0) return _K_ZERO;
    for (int i = 0; i <= hl - nl; i++) {
        int j = 0;
        while (j < nl && haystack[i+j] == needle[j]) j++;
        if (j == nl) return _kitoa(i);
    }
    return _kitoa(-1);
}

static char* _ktrim(const char* s) {
    int len = _kstrlen(s);
    int st = 0, en = len;
    while (st < en && (s[st]==' '||s[st]=='\t'||s[st]=='\r'||s[st]=='\n')) st++;
    while (en > st && (s[en-1]==' '||s[en-1]=='\t'||s[en-1]=='\r'||s[en-1]=='\n')) en--;
    if (st == 0 && en == len) return (char*)s;
    int n = en - st;
    char* p = _arena_alloc(n + 1);
    _kmemcpy(p, s + st, n);
    p[n] = 0;
    return p;
}

char* kr_trim(const char* s) { return _ktrim(s); }

char* kr_toint(const char* s) { return _kitoa(_katoi(s)); }
char* kr_not(const char* s) { return _kr_truthy_int(s) ? _K_ZERO : _K_ONE; }

char* kr_charcode(const char* s) {
    return _kitoa((unsigned char)s[0]);
}

char* kr_isdigit(const char* s) {
    return (s[0] >= '0' && s[0] <= '9') ? _K_ONE : _K_ZERO;
}

char* kr_replace(const char* s, const char* from, const char* to) {
    int sl = _kstrlen(s), fl = _kstrlen(from), tl = _kstrlen(to);
    if (fl == 0) return (char*)s;
    /* count occurrences */
    int count = 0;
    for (int i = 0; i <= sl - fl; ) {
        int j = 0;
        while (j < fl && s[i+j] == from[j]) j++;
        if (j == fl) { count++; i += fl; } else { i++; }
    }
    int newlen = sl + count * (tl - fl);
    char* out = _arena_alloc(newlen + 1);
    int wi = 0;
    for (int i = 0; i < sl; ) {
        if (i + fl <= sl) {
            int j = 0;
            while (j < fl && s[i+j] == from[j]) j++;
            if (j == fl) {
                _kmemcpy(out + wi, to, tl);
                wi += tl; i += fl;
                continue;
            }
        }
        out[wi++] = s[i++];
    }
    out[wi] = 0;
    return out;
}

char* kr_split(const char* s, const char* idxs) {
    int idx = _katoi(idxs);
    int count = 0;
    const char* start = s;
    const char* p = s;
    while (*p) {
        if (*p == ',') {
            if (count == idx) {
                int n = (int)(p - start);
                char* r = _arena_alloc(n + 1);
                _kmemcpy(r, start, n);
                r[n] = 0;
                return r;
            }
            count++;
            start = p + 1;
        }
        p++;
    }
    if (count == idx) {
        int n = _kstrlen(start);
        char* r = _arena_alloc(n + 1);
        _kmemcpy(r, start, n + 1);
        return r;
    }
    return _K_EMPTY;
}

/* ── List helpers ─────────────────────────────────────────────────── */
static int _klistlen(const char* s) {
    if (!s || !*s) return 0;
    int count = 1;
    const char* p = s;
    while (*p) { if (*p == ',') count++; p++; }
    return count;
}

char* kr_range(const char* starts, const char* ends) {
    int s = _katoi(starts), e = _katoi(ends);
    if (s >= e) return _K_EMPTY;
    /* build "s,s+1,...,e-1" */
    char* out = _kitoa(s);
    for (int i = s + 1; i < e; i++) {
        char* n = _kitoa(i);
        int ol = _kstrlen(out), nl = _kstrlen(n);
        char* p = _arena_alloc(ol + 1 + nl + 1);
        _kmemcpy(p, out, ol);
        p[ol] = ',';
        _kmemcpy(p + ol + 1, n, nl + 1);
        out = p;
    }
    return out;
}

char* kr_length(const char* lst) {
    return _kitoa(_klistlen(lst));
}

/* Windows file I/O */
extern void* __imp_CreateFileA;
extern void* __imp_ReadFile;
extern void* __imp_CloseHandle;
extern void* __imp_GetFileSize;

char* kr_readfile(const char* path) {
    typedef void* (*CF_t)(const char*,DWORD,DWORD,void*,DWORD,DWORD,void*);
    typedef int   (*RF_t)(void*,void*,DWORD,DWORD*,void*);
    typedef DWORD (*GFS_t)(void*,DWORD*);
    typedef int   (*CH_t)(void*);
    CF_t  cf  = (CF_t) __imp_CreateFileA;
    RF_t  rf  = (RF_t) __imp_ReadFile;
    GFS_t gfs = (GFS_t)__imp_GetFileSize;
    CH_t  ch  = (CH_t) __imp_CloseHandle;
    void* h = cf(path, 0x80000000/*GENERIC_READ*/, 1, 0, 3/*OPEN_EXISTING*/, 0, 0);
    if ((long long)h == -1) return _K_EMPTY;
    DWORD sz = gfs(h, 0);
    char* buf = _arena_alloc(sz + 1);
    DWORD rd = 0;
    rf(h, buf, sz, &rd, 0);
    buf[rd] = 0;
    ch(h);
    return buf;
}

/* Command-line args — parsed from GetCommandLineA on first use */
extern void* __imp_GetCommandLineA;

static char** _g_argv = 0;
static int    _g_argc = 0;

static void _parse_cmdline() {
    if (_g_argv) return;  /* already parsed */
    typedef char* (*GCL_t)(void);
    GCL_t gcl = (GCL_t)__imp_GetCommandLineA;
    char* cmd = gcl();
    /* simple tokenize: split on spaces, handle quoted args */
    static char* _argv_buf[256];
    int argc = 0;
    char* p = cmd;
    while (*p && argc < 255) {
        while (*p == ' ') p++;
        if (!*p) break;
        if (*p == '"') {
            p++;
            char* start = p;
            int len = 0;
            while (*p && *p != '"') { len++; p++; }
            char* arg = _arena_alloc(len + 1);
            _kmemcpy(arg, start, len);
            arg[len] = 0;
            _argv_buf[argc++] = arg;
            if (*p == '"') p++;
        } else {
            char* start = p;
            int len = 0;
            while (*p && *p != ' ') { len++; p++; }
            char* arg = _arena_alloc(len + 1);
            _kmemcpy(arg, start, len);
            arg[len] = 0;
            _argv_buf[argc++] = arg;
        }
    }
    _argv_buf[argc] = 0;
    _g_argc = argc;
    _g_argv = _argv_buf;
}

/* Called from entry point (no-op now, kept for ABI compat) */
void kr_init_args(int argc, char** argv) { (void)argc; (void)argv; }

char* kr_arg(const char* idxs) {
    _parse_cmdline();
    int idx = _katoi(idxs);
    /* arg(0) = argv[1], arg(1) = argv[2], etc. — raw, no flag skipping.
       compile.k does its own flag parsing. */
    int i = idx + 1; /* +1 to skip argv[0] (program name) */
    if (i < _g_argc) {
        char* a = _g_argv[i];
        int n = _kstrlen(a);
        char* p = _arena_alloc(n + 1);
        _kmemcpy(p, a, n + 1);
        return p;
    }
    return _K_EMPTY;
}

/* String builder */
#define KR_SB_MAX 64
static char* _sb_bufs[KR_SB_MAX];
static int   _sb_lens[KR_SB_MAX];
static int   _sb_caps[KR_SB_MAX];
static int   _sb_count = 0;

char* kr_sbnew() {
    if (_sb_count >= KR_SB_MAX) return _K_ZERO;
    int idx = _sb_count++;
    _sb_caps[idx] = 4096;
    _sb_bufs[idx] = _alloc(4096);  /* must be heap-allocated for HeapReAlloc in sbappend */
    _sb_lens[idx] = 0;
    _sb_bufs[idx][0] = 0;
    return _kitoa(idx);
}

char* kr_sbappend(const char* handles, const char* s) {
    int idx = _katoi(handles);
    int sl = _kstrlen(s);
    int newlen = _sb_lens[idx] + sl;
    if (newlen + 1 > _sb_caps[idx]) {
        int newcap = newlen * 2 + 1;
        /* HeapReAlloc in-place — no copy needed, no arena waste */
        char* newbuf = _realloc_heap(_sb_bufs[idx], newcap);
        _sb_bufs[idx] = newbuf;
        _sb_caps[idx] = newcap;
    }
    _kmemcpy(_sb_bufs[idx] + _sb_lens[idx], s, sl);
    _sb_lens[idx] += sl;
    _sb_bufs[idx][_sb_lens[idx]] = 0;
    return (char*)handles;
}

char* kr_sbtostring(const char* handles) {
    int idx = _katoi(handles);
    return _sb_bufs[idx];
}

/* ── Line/count builtins ──────────────────────────────────────────── */

char* kr_getline(const char* s, const char* idxs) {
    int idx = _katoi(idxs);
    int cur = 0;
    const char* start = s;
    const char* p = s;
    while (*p) {
        if (*p == '\n') {
            if (cur == idx) {
                int n = (int)(p - start);
                char* r = _arena_alloc(n + 1);
                _kmemcpy(r, start, n);
                r[n] = 0;
                return r;
            }
            cur++;
            start = p + 1;
        }
        p++;
    }
    if (cur == idx) return kr_str(start);
    return _K_EMPTY;
}

char* kr_linecount(const char* s) {
    if (!*s) return _K_ZERO;
    int count = 1;
    const char* p = s;
    while (*p) { if (*p == '\n') count++; p++; }
    if (*(p - 1) == '\n') count--;
    return _kitoa(count);
}

char* kr_count(const char* s) { return kr_linecount(s); }

char* kr_argcount() {
    _parse_cmdline();
    return _kitoa(_g_argc - 1);
}

/* ── File write builtins ──────────────────────────────────────────── */

static int _krhex(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

char* kr_writefile(const char* path, const char* data) {
    typedef void* (*CF_t)(const char*,DWORD,DWORD,void*,DWORD,DWORD,void*);
    typedef int   (*WF_t)(void*,const void*,DWORD,DWORD*,void*);
    typedef int   (*CH_t)(void*);
    CF_t cf = (CF_t)__imp_CreateFileA;
    WF_t wf = (WF_t)__imp_WriteFile;
    CH_t ch = (CH_t)__imp_CloseHandle;
    void* h = cf(path, 0x40000000/*GENERIC_WRITE*/, 0, 0, 2/*CREATE_ALWAYS*/, 0x80/*FILE_ATTRIBUTE_NORMAL*/, 0);
    if ((long long)h == -1) return _K_ZERO;
    int len = _kstrlen(data);
    DWORD written;
    wf(h, data, (DWORD)len, &written, 0);
    ch(h);
    return _K_ONE;
}

char* kr_writebytes(const char* path, const char* hexstr) {
    typedef void* (*CF_t)(const char*,DWORD,DWORD,void*,DWORD,DWORD,void*);
    typedef int   (*WF_t)(void*,const void*,DWORD,DWORD*,void*);
    typedef int   (*CH_t)(void*);
    CF_t cf = (CF_t)__imp_CreateFileA;
    WF_t wf = (WF_t)__imp_WriteFile;
    CH_t ch = (CH_t)__imp_CloseHandle;
    void* h = cf(path, 0x40000000/*GENERIC_WRITE*/, 0, 0, 2/*CREATE_ALWAYS*/, 0x80/*FILE_ATTRIBUTE_NORMAL*/, 0);
    if ((long long)h == -1) return _K_ZERO;
    const char* p = hexstr;
    while (*p) {
        if (*p == 'x' && p[1] && p[2]) {
            int hi = _krhex(p[1]), lo = _krhex(p[2]);
            if (hi >= 0 && lo >= 0) {
                unsigned char b = (unsigned char)(hi * 16 + lo);
                DWORD wr;
                wf(h, &b, 1, &wr, 0);
            }
            p += 3;
        } else { p++; }
    }
    ch(h);
    return _K_ONE;
}

/* ── printl (print without newline) ──────────────────────────────── */

char* kr_printl(const char* s) {
    typedef HANDLE (*GSH_t)(DWORD);
    typedef BOOL (*WF_t)(HANDLE,const void*,DWORD,DWORD*,void*);
    GSH_t gsh = (GSH_t)__imp_GetStdHandle;
    WF_t wf = (WF_t)__imp_WriteFile;
    HANDLE h = gsh(STD_OUTPUT_HANDLE);
    int len = _kstrlen(s);
    DWORD written;
    if (len > 0) wf(h, s, (DWORD)len, &written, 0);
    return _K_EMPTY;
}

/* ── String / char builtins ──────────────────────────────────────── */

char* kr_fromcharcode(const char* ns) {
    int n = _katoi(ns);
    char* out = _arena_alloc(2);
    out[0] = (char)(n & 0xFF);
    out[1] = 0;
    return out;
}

char* kr_tolower(const char* s) {
    int len = _kstrlen(s);
    char* out = _arena_alloc(len + 1);
    for (int i = 0; i < len; i++) {
        char c = s[i];
        if (c >= 'A' && c <= 'Z') c = c + 32;
        out[i] = c;
    }
    out[len] = 0;
    return out;
}

/* toHandle: parse integer string -> integer cast to char* (matches C backend) */
char* kr_tohandle(const char* s) {
    unsigned long long v = 0;
    const char* p = s;
    int neg = 0;
    if (*p == '-') { neg = 1; p++; }
    while (*p >= '0' && *p <= '9') { v = v * 10 + (*p - '0'); p++; }
    if (neg) return (char*)(uintptr_t)(unsigned long long)(-(long long)v);
    return (char*)(uintptr_t)v;
}

/* ── Bitwise builtins ────────────────────────────────────────────── */

char* kr_bitor(const char* a, const char* b) {
    return _kitoa((int)((unsigned int)_katoi(a) | (unsigned int)_katoi(b)));
}

char* kr_bitand(const char* a, const char* b) {
    return _kitoa((int)((unsigned int)_katoi(a) & (unsigned int)_katoi(b)));
}

char* kr_bitxor(const char* a, const char* b) {
    return _kitoa((int)((unsigned int)_katoi(a) ^ (unsigned int)_katoi(b)));
}

char* kr_bitnot(const char* a) {
    return _kitoa((int)(~(unsigned int)_katoi(a)));
}

char* kr_shl(const char* a, const char* b) {
    return _kitoa((int)((unsigned int)_katoi(a) << _katoi(b)));
}

char* kr_shr(const char* a, const char* b) {
    return _kitoa((int)((unsigned int)_katoi(a) >> _katoi(b)));
}

/* ── Buffer builtins ─────────────────────────────────────────────── */
/* Buffers are raw heap blocks; handle IS the char* pointer directly  */
/* This matches the C backend convention (direct pointer, not decimal) */

char* kr_bufnew(const char* sizes) {
    int sz = _katoi(sizes);
    if (sz < 1) sz = 1;
    char* buf = _arena_alloc(sz);
    for (int i = 0; i < sz; i++) buf[i] = 0;
    return buf;  /* return raw pointer as char* */
}

char* kr_bufstr(const char* buf) {
    return kr_str(buf);  /* buf IS a char* string, return a copy */
}

char* kr_bufsetdword(const char* buf, const char* vals) {
    *((unsigned int*)buf) = (unsigned int)_katoi(vals);
    return _K_EMPTY;
}

char* kr_bufgetdword(const char* buf) {
    return _kitoa((int)*((unsigned int*)buf));
}

char* kr_bufsetdwordat(const char* buf, const char* offs, const char* vals) {
    *((unsigned int*)(buf + _katoi(offs))) = (unsigned int)_katoi(vals);
    return _K_EMPTY;
}

char* kr_bufgetdwordat(const char* buf, const char* offs) {
    return _kitoa((int)*((unsigned int*)(buf + _katoi(offs))));
}

char* kr_bufgetword(const char* buf) {
    return _kitoa((int)*((unsigned short*)buf));
}

char* kr_bufgetqword(const char* buf) {
    unsigned long long v = *((unsigned long long*)buf);
    char tmp[24]; int i = 23; tmp[i] = 0;
    if (v == 0) { tmp[--i] = '0'; }
    else { while (v) { tmp[--i] = '0' + (int)(v % 10); v /= 10; } }
    return kr_str(tmp + i);
}

char* kr_bufgetqwordat(const char* buf, const char* offs) {
    unsigned long long v = *((unsigned long long*)(buf + _katoi(offs)));
    char tmp[24]; int i = 23; tmp[i] = 0;
    if (v == 0) { tmp[--i] = '0'; }
    else { while (v) { tmp[--i] = '0' + (int)(v % 10); v /= 10; } }
    return kr_str(tmp + i);
}

char* kr_bufsetbyte(const char* buf, const char* offs, const char* vals) {
    *((char*)buf + _katoi(offs)) = (char)_katoi(vals);
    return _K_EMPTY;
}

/* handleOut: allocate 8-byte slot to receive a HANDLE from Win32 */
char* kr_handleout(void) {
    char* buf = _arena_alloc(8);
    *((void**)buf) = (void*)0;
    return buf;
}

/* handleGet: read the HANDLE value stored in an 8-byte slot */
char* kr_handleget(const char* buf) {
    return *((char**)buf);
}

/* handleValid: check that h is not NULL and not INVALID_HANDLE_VALUE */
char* kr_handlevalid(const char* h) {
    return (h != (char*)0 && h != (char*)(uintptr_t)(unsigned long long)-1)
           ? _K_ONE : _K_ZERO;
}

/* handleInt: return handle pointer value as decimal string */
char* kr_handleint(const char* ptr) {
    unsigned long long v = (unsigned long long)(uintptr_t)ptr;
    char tmp[24]; int i = 23; tmp[i] = 0;
    if (v == 0) { tmp[--i] = '0'; }
    else { while (v) { tmp[--i] = '0' + (int)(v % 10); v /= 10; } }
    return kr_str(tmp + i);
}

/* ptrDeref: read char** as char* */
char* kr_ptrderef(const char* ptr) {
    return *((char**)ptr);
}

/* ptrIndex: return element n of a char** array */
char* kr_ptrindex(const char* ptr, const char* n) {
    return ((char**)ptr)[_katoi(n)];
}

/* callPtr: call a function pointer with 1-4 args */
char* kr_callptr1(const char* fn, char* a0) {
    return ((char*(*)(char*))(fn))(a0);
}
char* kr_callptr2(const char* fn, char* a0, char* a1) {
    return ((char*(*)(char*,char*))(fn))(a0,a1);
}
char* kr_callptr3(const char* fn, char* a0, char* a1, char* a2) {
    return ((char*(*)(char*,char*,char*))(fn))(a0,a1,a2);
}
char* kr_callptr4(const char* fn, char* a0, char* a1, char* a2, char* a3) {
    return ((char*(*)(char*,char*,char*,char*))(fn))(a0,a1,a2,a3);
}

/* hex: integer to lowercase hex string */
char* kr_hex(const char* s) {
    int v = _katoi(s);
    unsigned int u = (unsigned int)v;
    char tmp[16]; int i = 15; tmp[i] = 0;
    if (u == 0) { tmp[--i] = '0'; }
    else { while (u) { int d = u & 0xF; tmp[--i] = d < 10 ? '0'+d : 'a'+d-10; u >>= 4; } }
    return kr_str(tmp + i);
}

/* toUpper: uppercase a string */
char* kr_touppers(const char* s) {
    int n = 0; while (s[n]) n++;
    char* r = _arena_alloc(n + 1);
    for (int i = 0; i <= n; i++) {
        char c = s[i];
        if (c >= 'a' && c <= 'z') c -= 32;
        r[i] = c;
    }
    return r;
}

/* div64: 64-bit integer division */
char* kr_div64(const char* a, const char* b) {
    long long bv = 0;
    const char* p = b;
    int neg = 0; if (*p == '-') { neg = 1; p++; }
    while (*p >= '0' && *p <= '9') { bv = bv * 10 + (*p - '0'); p++; }
    if (neg) bv = -bv;
    if (bv == 0) return kr_str("0");
    long long av = 0;
    p = a; neg = 0; if (*p == '-') { neg = 1; p++; }
    while (*p >= '0' && *p <= '9') { av = av * 10 + (*p - '0'); p++; }
    if (neg) av = -av;
    long long rv = av / bv;
    int rneg = rv < 0;
    unsigned long long uv = (unsigned long long)(rneg ? -rv : rv);
    char tmp[24]; int i = 23; tmp[i] = 0;
    if (uv == 0) { tmp[--i] = '0'; }
    else { while (uv) { tmp[--i] = '0' + (int)(uv % 10); uv /= 10; } }
    if (rneg) { tmp[--i] = '-'; }
    return kr_str(tmp + i);
}

/* environ: get environment variable via GetEnvironmentVariableA */
typedef unsigned int (*_GEVA_t)(const char*, char*, unsigned int);
char* kr_environ(const char* name) {
    _GEVA_t geva = (_GEVA_t)__imp_GetEnvironmentVariableA;
    char buf[1024];
    unsigned int n = geva(name, buf, sizeof(buf));
    if (n == 0 || n >= sizeof(buf)) return _K_EMPTY;
    buf[n] = 0;
    return kr_str(buf);
}

/* ── Struct builtins ─────────────────────────────────────────────── */
/* Structs are raw heap blocks; handle IS the char* pointer directly  */
/* Field offsets are hardcoded for the Windows structs kryofetch uses */

typedef struct { const char* name; int size; } _KrStruct;
typedef struct { const char* sname; const char* fname; int off; int sz; } _KrField;

static const _KrStruct _kr_structs[] = {
    { "CONSOLE_SCREEN_BUFFER_INFO", 22  },
    { "PROCESSENTRY32",             304 },
    { "MEMORYSTATUSEX",             64  },
    { "SYSTEM_INFO",                48  },
    { "SYSTEM_POWER_STATUS",        12  },
    { "FILETIME",                   8   },
    { "WIN32_FIND_DATAA",           320 },
    { "ULARGE_INTEGER",             8   },
    { 0, 0 }
};

/* offsets: CONSOLE_SCREEN_BUFFER_INFO (COORD dwSize=0, COORD dwCursorPos=4,
   WORD wAttr=8, SMALL_RECT srWindow=10[L=10,T=12,R=14,B=16], COORD dwMax=18) */
/* PROCESSENTRY32: dwSize=0, cntUsage=4, th32ProcessID=8, pad=12,
   th32DefaultHeapID=16, th32ModuleID=24, cntThreads=28,
   th32ParentProcessID=32, pcPriClassBase=36, dwFlags=40, szExeFile=44 */
static const _KrField _kr_fields[] = {
    { "CONSOLE_SCREEN_BUFFER_INFO", "dwSizeX",        0,  2 },
    { "CONSOLE_SCREEN_BUFFER_INFO", "dwSizeY",        2,  2 },
    { "CONSOLE_SCREEN_BUFFER_INFO", "dwCursorX",      4,  2 },
    { "CONSOLE_SCREEN_BUFFER_INFO", "dwCursorY",      6,  2 },
    { "CONSOLE_SCREEN_BUFFER_INFO", "wAttributes",    8,  2 },
    { "CONSOLE_SCREEN_BUFFER_INFO", "srWindowLeft",   10, 2 },
    { "CONSOLE_SCREEN_BUFFER_INFO", "srWindowTop",    12, 2 },
    { "CONSOLE_SCREEN_BUFFER_INFO", "srWindowRight",  14, 2 },
    { "CONSOLE_SCREEN_BUFFER_INFO", "srWindowBottom", 16, 2 },
    { "CONSOLE_SCREEN_BUFFER_INFO", "dwMaxX",         18, 2 },
    { "CONSOLE_SCREEN_BUFFER_INFO", "dwMaxY",         20, 2 },
    { "PROCESSENTRY32", "dwSize",              0,   4 },
    { "PROCESSENTRY32", "th32ProcessID",       8,   4 },
    { "PROCESSENTRY32", "th32ParentProcessID", 32,  4 },
    { "PROCESSENTRY32", "szExeFile",           44,  260 },
    { "MEMORYSTATUSEX", "dwLength",            0,   4 },
    { "MEMORYSTATUSEX", "dwMemoryLoad",        4,   4 },
    { "MEMORYSTATUSEX", "ullTotalPhys",        8,   8 },
    { "MEMORYSTATUSEX", "ullAvailPhys",        16,  8 },
    { "SYSTEM_POWER_STATUS", "ACLineStatus",       0, 1 },
    { "SYSTEM_POWER_STATUS", "BatteryFlag",        1, 1 },
    { "SYSTEM_POWER_STATUS", "BatteryLifePercent", 2, 1 },
    { "SYSTEM_POWER_STATUS", "BatteryLifeTime",    4, 4 },
    { "SYSTEM_INFO", "wProcessorArchitecture", 0, 2 },
    { "SYSTEM_INFO", "dwNumberOfProcessors",   32, 4 },
    { "WIN32_FIND_DATAA", "dwFileAttributes", 0,   4 },
    { "WIN32_FIND_DATAA", "cFileName",        44,  260 },
    { "ULARGE_INTEGER", "QuadPart", 0, 8 },
    { 0, 0, 0, 0 }
};

static int _kstreq(const char* a, const char* b) {
    while (*a && *b) { if (*a != *b) return 0; a++; b++; }
    return *a == *b;
}

char* kr_structnew(const char* name) {
    int sz = 0;
    for (int i = 0; _kr_structs[i].name; i++) {
        if (_kstreq(_kr_structs[i].name, name)) { sz = _kr_structs[i].size; break; }
    }
    if (sz == 0) sz = 256; /* fallback */
    char* buf = _arena_alloc(sz);
    for (int i = 0; i < sz; i++) buf[i] = 0;
    return buf;  /* return raw pointer directly */
}

char* kr_sizeof(const char* name) {
    for (int i = 0; _kr_structs[i].name; i++) {
        if (_kstreq(_kr_structs[i].name, name)) return _kitoa(_kr_structs[i].size);
    }
    return _kitoa(0);
}

char* kr_structget(const char* buf, const char* sname, const char* fname) {
    for (int i = 0; _kr_fields[i].sname; i++) {
        if (_kstreq(_kr_fields[i].sname, sname) && _kstreq(_kr_fields[i].fname, fname)) {
            int off = _kr_fields[i].off;
            int sz  = _kr_fields[i].sz;
            if (sz == 1) return _kitoa((int)(unsigned char)buf[off]);
            if (sz == 2) return _kitoa((int)*((unsigned short*)(buf + off)));
            if (sz == 4) return _kitoa((int)*((unsigned int*)(buf + off)));
            if (sz == 8) {
                unsigned long long v = *((unsigned long long*)(buf + off));
                char tmp[24]; int i2 = 23; tmp[i2] = 0;
                if (v == 0) { tmp[--i2] = '0'; }
                else { while (v) { tmp[--i2] = '0'+(int)(v%10); v/=10; } }
                return kr_str(tmp + i2);
            }
            /* CHAR_ARRAY: return as string */
            return kr_str(buf + off);
        }
    }
    return _K_EMPTY;
}

char* kr_structset(const char* buf, const char* sname, const char* fname, const char* val) {
    for (int i = 0; _kr_fields[i].sname; i++) {
        if (_kstreq(_kr_fields[i].sname, sname) && _kstreq(_kr_fields[i].fname, fname)) {
            int off = _kr_fields[i].off;
            int sz  = _kr_fields[i].sz;
            char* wbuf = (char*)buf;
            unsigned int v = (unsigned int)_katoi(val);
            if (sz == 1) wbuf[off] = (char)v;
            else if (sz == 2) *((unsigned short*)(wbuf + off)) = (unsigned short)v;
            else if (sz == 4) *((unsigned int*)(wbuf + off)) = v;
            return _K_EMPTY;
        }
    }
    return _K_EMPTY;
}

/* ── Phase 1: Raw memory primitives ─────────────────────────────── */

/* rawAlloc: heap-allocate n bytes with no krypton header, return raw ptr */
char* kr_rawalloc(const char* size) {
    typedef char* (*HA_t)(void*, unsigned int, size_t);
    int n = _katoi(size);
    if (n < 1) n = 1;
    return ((HA_t)__imp_HeapAlloc)(_get_heap(), 0, (size_t)n);
}

/* rawFree: free a raw pointer (no header offset) */
char* kr_rawfree(const char* ptr) {
    typedef int (*HF_t)(void*, unsigned int, void*);
    if (ptr) ((HF_t)__imp_HeapFree)(_get_heap(), 0, (void*)ptr);
    return _K_EMPTY;
}

/* rawRealloc: resize a raw pointer */
char* kr_rawrealloc(const char* ptr, const char* size) {
    typedef char* (*HR_t)(void*, unsigned int, void*, size_t);
    int n = _katoi(size);
    if (n < 1) n = 1;
    char* p = ((HR_t)__imp_HeapReAlloc)(_get_heap(), 0, (void*)ptr, (size_t)n);
    return p ? p : (char*)ptr;
}

/* ptrAdd: pointer + integer offset -> new pointer */
char* kr_ptradd(const char* ptr, const char* n) {
    return (char*)ptr + _katoi(n);
}

/* ptrToInt: pointer -> full 64-bit integer string */
char* kr_ptrtoint(const char* ptr) {
    unsigned long long v = (unsigned long long)(uintptr_t)ptr;
    char tmp[24]; int i = 23; tmp[i] = 0;
    if (v == 0) { tmp[--i] = '0'; }
    else { while (v) { tmp[--i] = '0' + (int)(v % 10); v /= 10; } }
    return kr_str(tmp + i);
}

/* rawReadByte: read 1 byte at ptr+offset */
char* kr_rawreadbyte(const char* ptr, const char* offset) {
    return _kitoa((int)(unsigned char)ptr[_katoi(offset)]);
}

/* rawReadWord: read 2 bytes (unsigned) at ptr+offset */
char* kr_rawreadword(const char* ptr, const char* offset) {
    return _kitoa((int)*((unsigned short*)(ptr + _katoi(offset))));
}

/* rawWriteWord: write 2 bytes at ptr+offset */
char* kr_rawwriteword(const char* ptr, const char* offset, const char* val) {
    *((unsigned short*)((char*)ptr + _katoi(offset))) = (unsigned short)_katoi(val);
    return _K_EMPTY;
}

/* rawWriteQword: write 8 bytes at ptr+offset */
char* kr_rawwriteqword(const char* ptr, const char* offset, const char* val) {
    unsigned long long v = 0;
    const char* p = val;
    int neg = 0;
    if (*p == '-') { neg = 1; p++; }
    while (*p >= '0' && *p <= '9') { v = v * 10 + (*p - '0'); p++; }
    if (neg) v = (unsigned long long)(-(long long)v);
    *((unsigned long long*)((char*)ptr + _katoi(offset))) = v;
    return _K_EMPTY;
}
