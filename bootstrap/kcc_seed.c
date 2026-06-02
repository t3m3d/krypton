#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <ctype.h>
#include <stdarg.h>
#include <stdint.h>
#if defined(_WIN32) || defined(_WIN64)
#include <string.h>
#else
#include <strings.h>
#define _stricmp strcasecmp
#endif

static int _argc; static char** _argv;

typedef struct ABlock { struct ABlock* next; int cap; int used; } ABlock;
static ABlock* _arena = 0;
typedef struct AllocHdr { struct AllocHdr* next; uint32_t size; uint32_t mark; } AllocHdr;
static AllocHdr* _alloc_head = 0;
static char* _stack_bottom = 0;
static long _gc_arena_bytes = 0;
static long _gc_threshold = 268435456L;
static int _gc_enabled = -1;
static void _gc_collect(void);
static char* _arena_addr_lo = (char*)~(uintptr_t)0;
static char* _arena_addr_hi = 0;
static char* _alloc(int n) __attribute__((noinline));
static char* _alloc(int n) {
    n = (n + 7) & ~7;
    if (_gc_enabled < 0) {
        const char* env = getenv("KR_NOGC");
        _gc_enabled = (env && *env) ? 0 : 1;
    }
    int total = sizeof(AllocHdr) + n;
    if (!_arena || _arena->used + total > _arena->cap) {
        if (_gc_enabled && _gc_arena_bytes > _gc_threshold) {
            _gc_collect();
            if (_arena && _arena->used + total <= _arena->cap) goto have_room;
        }
        int cap = 64*1024*1024;
        if (total > cap) cap = total;
        ABlock* b = (ABlock*)malloc(sizeof(ABlock) + cap);
        if (!b) { fprintf(stderr, "out of memory\n"); exit(1); }
        b->cap = cap; b->used = 0; b->next = _arena; _arena = b;
        _gc_arena_bytes += cap;
    }
    have_room:;
    AllocHdr* h = (AllocHdr*)((char*)(_arena + 1) + _arena->used);
    h->next = _alloc_head;
    h->size = (uint32_t)n;
    h->mark = 0;
    _alloc_head = h;
    _arena->used += total;
    char* user = (char*)(h + 1);
    if (user < _arena_addr_lo) _arena_addr_lo = user;
    if (user + n > _arena_addr_hi) _arena_addr_hi = user + n;
    return user;
}

#include <setjmp.h>
static int _gc_in_range(ABlock* b, char* p) {
    char* base = (char*)(b + 1);
    return p >= base && p < base + b->cap;
}
static AllocHdr** _gc_sorted = 0;
static int _gc_sorted_cap = 0;
static int _gc_sorted_n = 0;
static int _gc_alloc_cmp(const void* a, const void* b) {
    char* pa = (char*)*(AllocHdr* const*)a;
    char* pb = (char*)*(AllocHdr* const*)b;
    return pa < pb ? -1 : (pa > pb ? 1 : 0);
}
static void _gc_mark_word(void* word) {
    char* p = (char*)word;
    if (p < _arena_addr_lo || p >= _arena_addr_hi) return;
    if (_gc_sorted_n == 0) return;
    // Binary search for greatest alloc with start <= p.
    int lo = 0, hi = _gc_sorted_n;
    while (lo < hi) {
        int mid = (lo + hi) / 2;
        char* mid_start = (char*)_gc_sorted[mid];
        if (mid_start <= p) lo = mid + 1; else hi = mid;
    }
    if (lo == 0) return;
    AllocHdr* a = _gc_sorted[lo - 1];
    char* user = (char*)(a + 1);
    if (p >= user && p < user + a->size) a->mark = 1;
}
static void _gc_collect(void) {
    // Clear all marks + count.
    AllocHdr* a = _alloc_head;
    long n_total = 0, n_live = 0;
    while (a) { a->mark = 0; n_total++; a = a->next; }
    // Build sorted-by-address index for binary-search mark phase.
    if (n_total > _gc_sorted_cap) {
        int newcap = _gc_sorted_cap ? _gc_sorted_cap : 1024;
        while (newcap < n_total) newcap *= 2;
        _gc_sorted = (AllocHdr**)realloc(_gc_sorted, newcap * sizeof(AllocHdr*));
        _gc_sorted_cap = newcap;
    }
    int idx = 0;
    for (a = _alloc_head; a; a = a->next) _gc_sorted[idx++] = a;
    _gc_sorted_n = idx;
    qsort(_gc_sorted, idx, sizeof(AllocHdr*), _gc_alloc_cmp);
    // Mark roots: spill regs to jmp_buf, then scan stack.
    jmp_buf regs;
    setjmp(regs);
    char* lo = (char*)&regs;
    char* hi = _stack_bottom;
    if (lo > hi) { char* t = lo; lo = hi; hi = t; }
    char* p = (char*)(((uintptr_t)lo + 7) & ~(uintptr_t)7);
    while (p < hi) {
        _gc_mark_word(*(void**)p);
        p += 8;
    }
    // Sweep: unlink unmarked from the global list.
    AllocHdr** pp = &_alloc_head;
    while (*pp) {
        if ((*pp)->mark == 0) { *pp = (*pp)->next; }
        else { n_live++; pp = &(*pp)->next; }
    }
    // Free any fully-dead arena blocks (no live allocs in their range).
    ABlock** bpp = &_arena;
    while (*bpp) {
        int has_live = 0;
        AllocHdr* la = _alloc_head;
        while (la) { if (_gc_in_range(*bpp, (char*)la)) { has_live = 1; break; } la = la->next; }
        if (!has_live && *bpp != _arena) {
            ABlock* dead = *bpp;
            *bpp = dead->next;
            _gc_arena_bytes -= dead->cap;
            free(dead);
        } else {
            bpp = &(*bpp)->next;
        }
    }
    // Reset _gc_threshold to roughly 4x current live size, min 64 MB.
    long live_bytes = 0;
    a = _alloc_head; while (a) { live_bytes += a->size; a = a->next; }
    _gc_threshold = live_bytes * 4;
    if (_gc_threshold < 536870912L) _gc_threshold = 536870912L;
    if (getenv("KR_GC_LOG")) fprintf(stderr, "[gc] swept %ld/%ld allocs, %ldMB live, threshold->%ldMB\n", n_total - n_live, n_total, live_bytes/1048576, _gc_threshold/1048576);
}

typedef struct { ABlock* block; int used; } _AllocMark;
static char* _alloc_mark(void) {
    _AllocMark m;
    m.block = _arena;
    m.used = _arena ? _arena->used : 0;
    char* tok = _alloc(sizeof(_AllocMark));
    memcpy(tok, &m, sizeof(_AllocMark));
    return tok;
}
static char* _kr_itoa_cache[1024];
static char* _alloc_reset(const char* tok) {
    _AllocMark m;
    memcpy(&m, tok, sizeof(_AllocMark));
    // Prune the global alloc list: anything in a block we're about
    // to free (or above m.used within m.block) gets dropped first so
    // the GC mark phase doesn't dereference freed memory.
    AllocHdr** pp = &_alloc_head;
    while (*pp) {
        AllocHdr* h = *pp;
        int dead = 0;
        ABlock* b = _arena;
        while (b && b != m.block) {
            if (_gc_in_range(b, (char*)h)) { dead = 1; break; }
            b = b->next;
        }
        if (!dead && m.block && _gc_in_range(m.block, (char*)h)
             && (char*)h >= (char*)(m.block + 1) + m.used) dead = 1;
        if (dead) *pp = h->next;
        else pp = &h->next;
    }
    while (_arena && _arena != m.block) {
        ABlock* deadb = _arena;
        _arena = deadb->next;
        _gc_arena_bytes -= deadb->cap;
        free(deadb);
    }
    if (_arena) _arena->used = m.used;
    // kr_itoa cached strings point into arena; reset invalidates them.
    for (int i = 0; i < 1024; i++) _kr_itoa_cache[i] = 0;
    return "";
}

static long _intSlots[32];
static char* intSlotStore(const char* slot, const char* val) {
    int s = atoi(slot);
    if (s < 0 || s >= 32) return "";
    _intSlots[s] = atol(val);
    return "";
}
static char* kr_str(const char*);
static char* intSlotLoad(const char* slot) {
    int s = atoi(slot);
    char buf[32];
    if (s < 0 || s >= 32) { buf[0]='0'; buf[1]=0; return kr_str(buf); }
    snprintf(buf, sizeof(buf), "%ld", _intSlots[s]);
    return kr_str(buf);
}

static char _K_EMPTY[] = "";
static char _K_ZERO[] = "0";
static char _K_ONE[] = "1";

static char* kr_str(const char* s) {
if (!s[0]) return _K_EMPTY;
    if (s[0] == '0' && !s[1]) return _K_ZERO;
    if (s[0] == '1' && !s[1]) return _K_ONE;
    int n = (int)strlen(s) + 1;
    char* p = _alloc(n);
    memcpy(p, s, n);
    return p;
}

static char* kr_cat(const char* a, const char* b) {
int la = (int)strlen(a), lb = (int)strlen(b);
    char* p = _alloc(la + lb + 1);
    memcpy(p, a, la);
    memcpy(p + la, b, lb + 1);
    return p;
}

static int kr_isnum(const char* s) {
    if (!*s) return 0;
    const char* p = s;
    if (*p == '-') p++;
    if (!*p) return 0;
    while (*p) { if (*p < '0' || *p > '9') return 0; p++; }
    return 1;
}

static char* kr_itoa(int v) {
    if (v == 0) return _K_ZERO;
    if (v == 1) return _K_ONE;
    if (v >= 0 && v < 1024) {
        char* c = _kr_itoa_cache[v];
        if (c) return c;
        char buf[8];
        snprintf(buf, sizeof(buf), "%d", v);
        c = kr_str(buf);
        _kr_itoa_cache[v] = c;
        return c;
    }
    char buf[32];
    snprintf(buf, sizeof(buf), "%d", v);
    return kr_str(buf);
}

static int kr_atoi(const char* s) { return atoi(s); }

static char* kr_itoa64(long long v) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%lld", v);
    return kr_str(buf);
}

static char* kr_plus(const char* a, const char* b) {
    if (kr_isnum(a) && kr_isnum(b))
        return kr_itoa(atoi(a) + atoi(b));
    return kr_cat(a, b);
}

static char* kr_sub(const char* a, const char* b) { return kr_itoa(atoi(a) - atoi(b)); }
static char* kr_mul(const char* a, const char* b) { return kr_itoa(atoi(a) * atoi(b)); }
static char* kr_div(const char* a, const char* b) { return kr_itoa(atoi(a) / atoi(b)); }
static char* kr_mod(const char* a, const char* b) { return kr_itoa(atoi(a) % atoi(b)); }
static char* kr_neg(const char* a) { return kr_itoa(-atoi(a)); }
static char* kr_not(const char* a) { return atoi(a) ? _K_ZERO : _K_ONE; }

static char* kr_eq(const char* a, const char* b) {
    return strcmp(a, b) == 0 ? _K_ONE : _K_ZERO;
}
static char* kr_neq(const char* a, const char* b) {
    return strcmp(a, b) != 0 ? _K_ONE : _K_ZERO;
}
static char* kr_lt(const char* a, const char* b) {
    if (kr_isnum(a) && kr_isnum(b)) return atoi(a) < atoi(b) ? _K_ONE : _K_ZERO;
    return strcmp(a, b) < 0 ? _K_ONE : _K_ZERO;
}
static char* kr_gt(const char* a, const char* b) {
    if (kr_isnum(a) && kr_isnum(b)) return atoi(a) > atoi(b) ? _K_ONE : _K_ZERO;
    return strcmp(a, b) > 0 ? _K_ONE : _K_ZERO;
}
static char* kr_lte(const char* a, const char* b) {
    return kr_gt(a, b) == _K_ZERO ? _K_ONE : _K_ZERO;
}
static char* kr_gte(const char* a, const char* b) {
    return kr_lt(a, b) == _K_ZERO ? _K_ONE : _K_ZERO;
}

static int kr_truthy(const char* s) {
    if (!s || !*s) return 0;
    if (strcmp(s, "0") == 0) return 0;
    if (strcmp(s, "false") == 0) return 0;
    return 1;
}

static char* kr_print(const char* s) {
    printf("%s\n", s);
    return _K_EMPTY;
}

static char* kr_len(const char* s) { return kr_itoa((int)strlen(s)); }

static char* kr_idx(const char* s, int i) {
    char buf[2] = {s[i], 0};
    return kr_str(buf);
}

static char* kr_split(const char* s, const char* idxs) {
    int idx = atoi(idxs);
    int count = 0;
    const char* start = s;
    const char* p = s;
    while (*p) {
        if (*p == ',') {
            if (count == idx) {
                int len = (int)(p - start);
                char* r = _alloc(len + 1);
                memcpy(r, start, len);
                r[len] = 0;
                return r;
            }
            count++;
            start = p + 1;
        }
        p++;
    }
    if (count == idx) return kr_str(start);
    return kr_str("");
}

static char* kr_startswith(const char* s, const char* prefix) {
    return strncmp(s, prefix, strlen(prefix)) == 0 ? _K_ONE : _K_ZERO;
}

static char* kr_substr(const char* s, const char* starts, const char* ends) {
    int st = atoi(starts), en = atoi(ends);
    int slen = (int)strlen(s);
    if (st >= slen) return kr_str("");
    if (en > slen) en = slen;
    int n = en - st;
    if (n <= 0) return kr_str("");
    char* r = _alloc(n + 1);
    memcpy(r, s + st, n);
    r[n] = 0;
    return r;
}

static char* kr_toint(const char* s) { return kr_itoa(atoi(s)); }

static char* kr_exec(const char* cmd) {
    char* buf=_alloc(8192); buf[0]=0;
#ifdef _WIN32
    FILE* p=_popen(cmd,"r");
#else
    FILE* p=popen(cmd,"r");
#endif
    if(!p) return buf;
    int pos=0,ch;
    while(pos<8191&&(ch=fgetc(p))!=EOF) buf[pos++]=(char)ch;
    buf[pos]=0;
#ifdef _WIN32
    _pclose(p);
#else
    pclose(p);
#endif
    while(pos>0&&(buf[pos-1]==13||buf[pos-1]==10||buf[pos-1]==32)) buf[--pos]=0;
    return buf;
}



static char* kr_readfile(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) return kr_str("");
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    char* buf = _alloc((int)sz + 1);
    fread(buf, 1, sz, f);
    buf[sz] = 0;
    fclose(f);
    return buf;
}

static char* kr_arg(const char* idxs) {
    int idx = atoi(idxs) + 1;
    if (idx < _argc) return kr_str(_argv[idx]);
    return kr_str("");
}

static char* kr_argcount() {
    return kr_itoa(_argc - 1);
}

static char* kr_getline(const char* s, const char* idxs) {
    int idx = atoi(idxs);
    static const char* _gl_s = 0;
    static int _gl_idx = 0;
    static const char* _gl_start = 0;
    const char* start; int cur;
    if (s == _gl_s && _gl_start && idx >= _gl_idx) {
        start = _gl_start; cur = _gl_idx;
    } else {
        start = s; cur = 0; _gl_s = s; _gl_start = s; _gl_idx = 0;
    }
    const char* p = start;
    while (*p) {
        if (*p == '\n') {
            if (cur == idx) {
                int len = (int)(p - start);
                char* r = _alloc(len + 1);
                memcpy(r, start, len); r[len] = 0;
                _gl_s = s; _gl_idx = idx; _gl_start = start;
                return r;
            }
            cur++; start = p + 1;
        }
        p++;
    }
    if (cur == idx) { _gl_s = s; _gl_idx = idx; _gl_start = start; return kr_str(start); }
    return kr_str("");
}

static char* kr_linecount(const char* s) {
    if (!*s) return kr_str("0");
    int count = 1;
    const char* p = s;
    while (*p) { if (*p == '\n') count++; p++; }
    if (*(p - 1) == '\n') count--;
    return kr_itoa(count);
}

static char* kr_count(const char* s) {
    int n = 1;
    if (s) { const char* p = s; while (*p) { if (*p == ',') n++; p++; } }
    return kr_itoa(n);
}

static char* kr_writefile(const char* path, const char* data) {
    FILE* f = fopen(path, "wb");
    if (!f) return _K_ZERO;
    fwrite(data, 1, strlen(data), f);
    fclose(f);
    return _K_ONE;
}

static int _krhex(char c){if(c>='0'&&c<='9')return c-'0';if(c>='a'&&c<='f')return c-'a'+10;if(c>='A'&&c<='F')return c-'A'+10;return -1;}
static char* kr_writebytes(const char* path, const char* hexstr) {
    FILE* f = fopen(path, "wb");
    if (!f) return _K_ZERO;
    const char* p = hexstr;
    while (*p) {
        if (*p == 'x' && p[1] && p[2]) {
            int hi = _krhex(p[1]), lo = _krhex(p[2]);
            if (hi >= 0 && lo >= 0) { unsigned char b = (unsigned char)(hi*16+lo); fwrite(&b,1,1,f); }
            p += 3;
        } else { p++; }
    }
    fclose(f);
    return _K_ONE;
}

static char* kr_shellrun(const char* cmd){int r=system(cmd);return kr_itoa(r);}
static char* kr_deletefile(const char* path){remove(path);return _K_EMPTY;}
static char* exec(const char* cmd){return kr_exec(cmd);}
static char* shellRun(const char* cmd){return kr_shellrun(cmd);}
static char* deleteFile(const char* path){return kr_deletefile(path);}

static char* kr_input() {
    char buf[4096];
    if (!fgets(buf, sizeof(buf), stdin)) return _K_EMPTY;
    int len = (int)strlen(buf);
    if (len > 0 && buf[len-1] == '\n') buf[--len] = 0;
    if (len > 0 && buf[len-1] == '\r') buf[--len] = 0;
    return kr_str(buf);
}

static char* kr_indexof(const char* s, const char* sub) {
    const char* p = strstr(s, sub);
    if (!p) return kr_itoa(-1);
    return kr_itoa((int)(p - s));
}

static char* kr_replace(const char* s, const char* old, const char* rep) {
    int slen = (int)strlen(s), olen = (int)strlen(old), rlen = (int)strlen(rep);
    if (olen == 0) return kr_str(s);
    int count = 0;
    const char* p = s;
    while ((p = strstr(p, old)) != 0) { count++; p += olen; }
    int nlen = slen + count * (rlen - olen);
    char* out = _alloc(nlen + 1);
    char* dst = out;
    p = s;
    while (*p) {
        if (strncmp(p, old, olen) == 0) {
            memcpy(dst, rep, rlen); dst += rlen; p += olen;
        } else { *dst++ = *p++; }
    }
    *dst = 0;
    return out;
}

static char* kr_charat(const char* s, const char* idxs) {
    int i = atoi(idxs);
    int slen = (int)strlen(s);
    if (i < 0 || i >= slen) return _K_EMPTY;
    char buf[2] = {s[i], 0};
    return kr_str(buf);
}

static char* kr_trim(const char* s) {
    while (*s == ' ' || *s == '\t' || *s == '\n' || *s == '\r') s++;
    int len = (int)strlen(s);
    while (len > 0 && (s[len-1]==' '||s[len-1]=='\t'||s[len-1]=='\n'||s[len-1]=='\r')) len--;
    char* r = _alloc(len + 1);
    memcpy(r, s, len);
    r[len] = 0;
    return r;
}

static char* kr_tolower(const char* s) {
    int len = (int)strlen(s);
    char* out = _alloc(len + 1);
    for (int i = 0; i <= len; i++)
        out[i] = (s[i] >= 'A' && s[i] <= 'Z') ? s[i] + 32 : s[i];
    return out;
}

static char* kr_toupper(const char* s) {
    int len = (int)strlen(s);
    char* out = _alloc(len + 1);
    for (int i = 0; i <= len; i++)
        out[i] = (s[i] >= 'a' && s[i] <= 'z') ? s[i] - 32 : s[i];
    return out;
}

static char* kr_contains(const char* s, const char* sub) {
    return strstr(s, sub) ? _K_ONE : _K_ZERO;
}

static char* kr_endswith(const char* s, const char* suffix) {
    int slen = (int)strlen(s), suflen = (int)strlen(suffix);
    if (suflen > slen) return _K_ZERO;
    return strcmp(s + slen - suflen, suffix) == 0 ? _K_ONE : _K_ZERO;
}

static char* kr_abs(const char* a) { int v = atoi(a); return kr_itoa(v < 0 ? -v : v); }
static char* kr_min(const char* a, const char* b) { return atoi(a) <= atoi(b) ? kr_str(a) : kr_str(b); }
static char* kr_max(const char* a, const char* b) { return atoi(a) >= atoi(b) ? kr_str(a) : kr_str(b); }

static char* kr_exit(const char* code) { exit(atoi(code)); return _K_EMPTY; }

static char* kr_type(const char* s) {
    if (kr_isnum(s)) return kr_str("number");
    return kr_str("string");
}

static char* kr_append(const char* lst, const char* item) {
    if (!*lst) return kr_str(item);
    return kr_cat(kr_cat(lst, ","), item);
}

static char* kr_join(const char* lst, const char* sep) {
    int llen = (int)strlen(lst), slen = (int)strlen(sep);
    int rlen = 0;
    for (int i = 0; i < llen; i++) {
        if (lst[i] == ',') rlen += slen; else rlen++;
    }
    char* out = _alloc(rlen + 1);
    int j = 0;
    for (int i = 0; i < llen; i++) {
        if (lst[i] == ',') { memcpy(out+j, sep, slen); j += slen; }
        else { out[j++] = lst[i]; }
    }
    out[j] = 0;
    return out;
}

static char* kr_reverse(const char* lst) {
    int cnt = 0;
    const char* p = lst;
    while (*p) { if (*p == ',') cnt++; p++; }
    cnt++;
    char* out = _K_EMPTY;
    for (int i = cnt - 1; i >= 0; i--) {
        char* item = kr_split(lst, kr_itoa(i));
        if (i == cnt - 1) out = item;
        else out = kr_cat(kr_cat(out, ","), item);
    }
    return out;
}

static int _kr_cmp(const void* a, const void* b) {
    const char* sa = *(const char**)a;
    const char* sb = *(const char**)b;
    if (kr_isnum(sa) && kr_isnum(sb)) return atoi(sa) - atoi(sb);
    return strcmp(sa, sb);
}
static char* kr_sort(const char* lst) {
    if (!*lst) return _K_EMPTY;
    int cnt = 1;
    const char* p = lst;
    while (*p) { if (*p == ',') cnt++; p++; }
    char** arr = (char**)_alloc(cnt * sizeof(char*));
    for (int i = 0; i < cnt; i++) arr[i] = kr_split(lst, kr_itoa(i));
    qsort(arr, cnt, sizeof(char*), _kr_cmp);
    char* out = arr[0];
    for (int i = 1; i < cnt; i++) out = kr_cat(kr_cat(out, ","), arr[i]);
    return out;
}

static char* kr_keys(const char* map) {
    if (!*map) return _K_EMPTY;
    int cnt = 1;
    const char* p = map;
    while (*p) { if (*p == ',') cnt++; p++; }
    char* out = _K_EMPTY; int first = 1;
    for (int i = 0; i < cnt; i += 2) {
        char* k = kr_split(map, kr_itoa(i));
        if (first) { out = k; first = 0; }
        else out = kr_cat(kr_cat(out, ","), k);
    }
    return out;
}

static char* kr_values(const char* map) {
    if (!*map) return _K_EMPTY;
    int cnt = 1;
    const char* p = map;
    while (*p) { if (*p == ',') cnt++; p++; }
    char* out = _K_EMPTY; int first = 1;
    for (int i = 1; i < cnt; i += 2) {
        char* v = kr_split(map, kr_itoa(i));
        if (first) { out = v; first = 0; }
        else out = kr_cat(kr_cat(out, ","), v);
    }
    return out;
}

static char* kr_haskey(const char* map, const char* key) {
    if (!*map) return _K_ZERO;
    int cnt = 1;
    const char* p = map;
    while (*p) { if (*p == ',') cnt++; p++; }
    for (int i = 0; i < cnt; i += 2) {
        if (strcmp(kr_split(map, kr_itoa(i)), key) == 0) return _K_ONE;
    }
    return _K_ZERO;
}

static char* kr_remove(const char* lst, const char* item) {
    if (!*lst) return _K_EMPTY;
    int cnt = 1;
    const char* p = lst;
    while (*p) { if (*p == ',') cnt++; p++; }
    char* out = _K_EMPTY; int first = 1;
    for (int i = 0; i < cnt; i++) {
        char* el = kr_split(lst, kr_itoa(i));
        if (strcmp(el, item) != 0) {
            if (first) { out = el; first = 0; }
            else out = kr_cat(kr_cat(out, ","), el);
        }
    }
    return out;
}

static char* kr_repeat(const char* s, const char* ns) {
    int n = atoi(ns);
    if (n <= 0) return _K_EMPTY;
    int slen = (int)strlen(s);
    char* out = _alloc(slen * n + 1);
    for (int i = 0; i < n; i++) memcpy(out + i * slen, s, slen);
    out[slen * n] = 0;
    return out;
}

static char* kr_format(const char* fmt, const char* arg) {
    char buf[4096];
    const char* p = strstr(fmt, "{}");
    if (!p) return kr_str(fmt);
    int pre = (int)(p - fmt);
    int alen = (int)strlen(arg);
    int postlen = (int)strlen(p + 2);
    if (pre + alen + postlen >= 4096) return kr_str(fmt);
    memcpy(buf, fmt, pre);
    memcpy(buf + pre, arg, alen);
    memcpy(buf + pre + alen, p + 2, postlen + 1);
    return kr_str(buf);
}

static char* kr_parseint(const char* s) {
    const char* p = s;
    while (*p == ' ' || *p == '\t') p++;
    if (!*p) return _K_ZERO;
    return kr_itoa(atoi(p));
}

static char* kr_tostr(const char* s) { return kr_str(s); }

static int kr_listlen(const char* s) {
    if (!*s) return 0;
    int cnt = 1;
    while (*s) { if (*s == ',') cnt++; s++; }
    return cnt;
}

static char* kr_range(const char* starts, const char* ends) {
    int s = atoi(starts), e = atoi(ends);
    if (s >= e) return _K_EMPTY;
    char* out = kr_itoa(s);
    for (int i = s + 1; i < e; i++) out = kr_cat(kr_cat(out, ","), kr_itoa(i));
    return out;
}

static char* kr_pow(const char* bs, const char* es) {
    int b = atoi(bs), e = atoi(es), r = 1;
    for (int i = 0; i < e; i++) r *= b;
    return kr_itoa(r);
}

static char* kr_sqrt(const char* s) {
    int v = atoi(s);
    if (v <= 0) return _K_ZERO;
    int r = 0;
    while ((r + 1) * (r + 1) <= v) r++;
    return kr_itoa(r);
}

static char* kr_sign(const char* s) {
    int v = atoi(s);
    if (v > 0) return _K_ONE;
    if (v < 0) return kr_str("-1");
    return _K_ZERO;
}

static char* kr_clamp(const char* vs, const char* los, const char* his) {
    int v = atoi(vs), lo = atoi(los), hi = atoi(his);
    if (v < lo) return kr_str(los);
    if (v > hi) return kr_str(his);
    return kr_str(vs);
}

static char* kr_padleft(const char* s, const char* ws, const char* pad) {
    int w = atoi(ws), slen = (int)strlen(s), plen = (int)strlen(pad);
    if (slen >= w || plen == 0) return kr_str(s);
    int need = w - slen;
    char* out = _alloc(w + 1);
    for (int i = 0; i < need; i++) out[i] = pad[i % plen];
    memcpy(out + need, s, slen + 1);
    return out;
}

static char* kr_padright(const char* s, const char* ws, const char* pad) {
    int w = atoi(ws), slen = (int)strlen(s), plen = (int)strlen(pad);
    if (slen >= w || plen == 0) return kr_str(s);
    int need = w - slen;
    char* out = _alloc(w + 1);
    memcpy(out, s, slen);
    for (int i = 0; i < need; i++) out[slen + i] = pad[i % plen];
    out[w] = 0;
    return out;
}

static char* kr_charcode(const char* s) {
    if (!*s) return _K_ZERO;
    return kr_itoa((unsigned char)s[0]);
}

static char* kr_fromcharcode(const char* ns) {
    unsigned int v = (unsigned int)atoi(ns);
    char buf[5] = {0};
    if (v < 0x80) { buf[0] = (char)v; }
    else if (v < 0x800) {
        buf[0] = (char)(0xC0 | (v >> 6));
        buf[1] = (char)(0x80 | (v & 0x3F));
    } else if (v < 0x10000) {
        buf[0] = (char)(0xE0 | (v >> 12));
        buf[1] = (char)(0x80 | ((v >> 6) & 0x3F));
        buf[2] = (char)(0x80 | (v & 0x3F));
    } else {
        buf[0] = (char)(0xF0 | (v >> 18));
        buf[1] = (char)(0x80 | ((v >> 12) & 0x3F));
        buf[2] = (char)(0x80 | ((v >> 6) & 0x3F));
        buf[3] = (char)(0x80 | (v & 0x3F));
    }
    return kr_str(buf);
}

static char* kr_slice(const char* lst, const char* starts, const char* ends) {
    int cnt = kr_listlen(lst);
    int s = atoi(starts), e = atoi(ends);
    if (s < 0) s = cnt + s;
    if (e < 0) e = cnt + e;
    if (s < 0) s = 0;
    if (e > cnt) e = cnt;
    if (s >= e) return _K_EMPTY;
    char* out = kr_split(lst, kr_itoa(s));
    for (int i = s + 1; i < e; i++)
        out = kr_cat(kr_cat(out, ","), kr_split(lst, kr_itoa(i)));
    return out;
}

static char* kr_length(const char* lst) {
    return kr_itoa(kr_listlen(lst));
}

static char* kr_unique(const char* lst) {
    if (!*lst) return _K_EMPTY;
    int cnt = kr_listlen(lst);
    char* out = _K_EMPTY; int oc = 0;
    for (int i = 0; i < cnt; i++) {
        char* item = kr_split(lst, kr_itoa(i));
        int dup = 0;
        for (int j = 0; j < oc; j++) {
            if (strcmp(kr_split(out, kr_itoa(j)), item) == 0) { dup = 1; break; }
        }
        if (!dup) {
            if (oc == 0) out = item; else out = kr_cat(kr_cat(out, ","), item);
            oc++;
        }
    }
    return out;
}

static char* kr_printerr(const char* s) {
    fprintf(stderr, "%s\n", s);
    fflush(stderr);
    return _K_EMPTY;
}

static char* kr_readline(const char* prompt) {
    if (*prompt) printf("%s", prompt);
    fflush(stdout);
    char buf[4096];
    if (!fgets(buf, sizeof(buf), stdin)) return _K_EMPTY;
    int len = (int)strlen(buf);
    if (len > 0 && buf[len-1] == '\n') buf[--len] = 0;
    if (len > 0 && buf[len-1] == '\r') buf[--len] = 0;
    return kr_str(buf);
}

static char* kr_assert(const char* cond, const char* msg) {
    if (!kr_truthy(cond)) {
        fprintf(stderr, "ASSERTION FAILED: %s\n", msg);
        exit(1);
    }
    return _K_ONE;
}

static char* kr_splitby(const char* s, const char* delim) {
    int slen = (int)strlen(s), dlen = (int)strlen(delim);
    if (dlen == 0 || slen == 0) return kr_str(s);
    char* out = _K_EMPTY; int first = 1;
    const char* p = s;
    while (*p) {
        const char* f = strstr(p, delim);
        if (!f) { 
            if (first) out = kr_str(p); else out = kr_cat(kr_cat(out, ","), kr_str(p));
            break;
        }
        int n = (int)(f - p);
        char* chunk = _alloc(n + 1);
        memcpy(chunk, p, n); chunk[n] = 0;
        if (first) { out = chunk; first = 0; }
        else out = kr_cat(kr_cat(out, ","), chunk);
        p = f + dlen;
        if (!*p) { out = kr_cat(kr_cat(out, ","), _K_EMPTY); break; }
    }
    return out;
}

static char* kr_listindexof(const char* lst, const char* item) {
    if (!*lst) return kr_itoa(-1);
    int cnt = kr_listlen(lst);
    for (int i = 0; i < cnt; i++) {
        if (strcmp(kr_split(lst, kr_itoa(i)), item) == 0) return kr_itoa(i);
    }
    return kr_itoa(-1);
}

static char* kr_insertat(const char* lst, const char* idxs, const char* item) {
    int idx = atoi(idxs);
    int cnt = kr_listlen(lst);
    if (!*lst && idx == 0) return kr_str(item);
    if (idx < 0) idx = 0;
    if (idx >= cnt) return kr_cat(kr_cat(lst, ","), item);
    char* out = _K_EMPTY; int first = 1;
    for (int i = 0; i < cnt; i++) {
        if (i == idx) {
            if (first) { out = kr_str(item); first = 0; }
            else out = kr_cat(kr_cat(out, ","), item);
        }
        char* el = kr_split(lst, kr_itoa(i));
        if (first) { out = el; first = 0; }
        else out = kr_cat(kr_cat(out, ","), el);
    }
    return out;
}

static char* kr_removeat(const char* lst, const char* idxs) {
    int idx = atoi(idxs);
    int cnt = kr_listlen(lst);
    if (idx < 0 || idx >= cnt) return kr_str(lst);
    char* out = _K_EMPTY; int first = 1;
    for (int i = 0; i < cnt; i++) {
        if (i == idx) continue;
        char* el = kr_split(lst, kr_itoa(i));
        if (first) { out = el; first = 0; }
        else out = kr_cat(kr_cat(out, ","), el);
    }
    return out;
}

static char* kr_replaceat(const char* lst, const char* idxs, const char* val) {
    int idx = atoi(idxs);
    int cnt = kr_listlen(lst);
    if (idx < 0 || idx >= cnt) return kr_str(lst);
    char* out = _K_EMPTY; int first = 1;
    for (int i = 0; i < cnt; i++) {
        char* el = (i == idx) ? (char*)val : kr_split(lst, kr_itoa(i));
        if (first) { out = el; first = 0; }
        else out = kr_cat(kr_cat(out, ","), el);
    }
    return out;
}

static char* kr_fill(const char* ns, const char* val) {
    int n = atoi(ns);
    if (n <= 0) return _K_EMPTY;
    char* out = kr_str(val);
    for (int i = 1; i < n; i++) out = kr_cat(kr_cat(out, ","), val);
    return out;
}

static char* kr_zip(const char* a, const char* b) {
    int ac = kr_listlen(a), bc = kr_listlen(b);
    int mc = ac < bc ? ac : bc;
    if (!*a || !*b) return _K_EMPTY;
    char* out = _K_EMPTY; int first = 1;
    for (int i = 0; i < mc; i++) {
        char* ai = kr_split(a, kr_itoa(i));
        char* bi = kr_split(b, kr_itoa(i));
        if (first) { out = kr_cat(kr_cat(ai, ","), bi); first = 0; }
        else { out = kr_cat(kr_cat(out, ","), kr_cat(kr_cat(ai, ","), bi)); }
    }
    return out;
}

static char* kr_every(const char* lst, const char* val) {
    if (!*lst) return _K_ONE;
    int cnt = kr_listlen(lst);
    for (int i = 0; i < cnt; i++) {
        if (strcmp(kr_split(lst, kr_itoa(i)), val) != 0) return _K_ZERO;
    }
    return _K_ONE;
}

static char* kr_some(const char* lst, const char* val) {
    if (!*lst) return _K_ZERO;
    int cnt = kr_listlen(lst);
    for (int i = 0; i < cnt; i++) {
        if (strcmp(kr_split(lst, kr_itoa(i)), val) == 0) return _K_ONE;
    }
    return _K_ZERO;
}

static char* kr_countof(const char* lst, const char* item) {
    if (!*lst) return _K_ZERO;
    int cnt = kr_listlen(lst), c = 0;
    for (int i = 0; i < cnt; i++) {
        if (strcmp(kr_split(lst, kr_itoa(i)), item) == 0) c++;
    }
    return kr_itoa(c);
}

static char* kr_sumlist(const char* lst) {
    if (!*lst) return _K_ZERO;
    int cnt = kr_listlen(lst), s = 0;
    for (int i = 0; i < cnt; i++) s += atoi(kr_split(lst, kr_itoa(i)));
    return kr_itoa(s);
}

static char* kr_maxlist(const char* lst) {
    if (!*lst) return _K_ZERO;
    int cnt = kr_listlen(lst);
    int m = atoi(kr_split(lst, _K_ZERO));
    for (int i = 1; i < cnt; i++) {
        int v = atoi(kr_split(lst, kr_itoa(i)));
        if (v > m) m = v;
    }
    return kr_itoa(m);
}

static char* kr_minlist(const char* lst) {
    if (!*lst) return _K_ZERO;
    int cnt = kr_listlen(lst);
    int m = atoi(kr_split(lst, _K_ZERO));
    for (int i = 1; i < cnt; i++) {
        int v = atoi(kr_split(lst, kr_itoa(i)));
        if (v < m) m = v;
    }
    return kr_itoa(m);
}

static char* kr_hex(const char* s) {
    int v = atoi(s);
    char buf[32];
    snprintf(buf, sizeof(buf), "%x", v < 0 ? -v : v);
    if (v < 0) return kr_cat("-", kr_str(buf));
    return kr_str(buf);
}

static char* kr_bin(const char* s) {
    int v = atoi(s);
    if (v == 0) return _K_ZERO;
    int neg = v < 0; if (neg) v = -v;
    char buf[64]; int i = 63; buf[i] = 0;
    while (v > 0) { buf[--i] = '0' + (v & 1); v >>= 1; }
    if (neg) return kr_cat("-", kr_str(&buf[i]));
    return kr_str(&buf[i]);
}

typedef struct EnvEntry { char* name; char* value; struct EnvEntry* prev; } EnvEntry;

static char* kr_envnew() { return (char*)0; }

static char* kr_envset(char* envp, const char* name, const char* val) {
    EnvEntry* e = (EnvEntry*)_alloc(sizeof(EnvEntry));
    e->name = (char*)name;
    e->value = (char*)val;
    e->prev = (EnvEntry*)envp;
    return (char*)e;
}

static char* kr_envget(char* envp, const char* name) {
    EnvEntry* e = (EnvEntry*)envp;
    while (e) {
        if (strcmp(e->name, name) == 0) return e->value;
        e = e->prev;
    }
    if (strcmp(name, "__argOffset") != 0)
        fprintf(stderr, "ERROR: undefined variable: %s\n", name);
    return kr_str("");
}

typedef struct ResultStruct { char tag; char* val; char* env; int pos; } ResultStruct;

static char* kr_makeresult(const char* tag, const char* val, const char* env, const char* pos) {
    ResultStruct* r = (ResultStruct*)_alloc(sizeof(ResultStruct));
    r->tag = tag[0];
    r->val = (char*)val;
    r->env = (char*)env;
    r->pos = atoi(pos);
    return (char*)r;
}

static char* kr_getresulttag(const char* r) {
    char buf[2] = {((ResultStruct*)r)->tag, 0};
    return kr_str(buf);
}

static char* kr_getresultval(const char* r) {
    return ((ResultStruct*)r)->val;
}

static char* kr_getresultenv(const char* r) {
    return ((ResultStruct*)r)->env;
}

static char* kr_getresultpos(const char* r) {
    return kr_itoa(((ResultStruct*)r)->pos);
}

static char* kr_istruthy(const char* s) {
    if (!s || !*s || strcmp(s, "0") == 0 || strcmp(s, "false") == 0)
        return _K_ZERO;
    return _K_ONE;
}

typedef struct { int cap; int len; } SBHdr;
#define MAX_SBS 1048576
static SBHdr* _sb_table[MAX_SBS];
static int _sb_count = 0;

static char* kr_sbnew() {
    int initcap = 65536;
    SBHdr* h = (SBHdr*)malloc(sizeof(SBHdr) + initcap);
    h->cap = initcap;
    h->len = 0;
    ((char*)(h + 1))[0] = 0;
    _sb_table[_sb_count] = h;
    return kr_itoa(_sb_count++);
}

static char* kr_sbappend(const char* handle, const char* s) {
    int idx = atoi(handle);
    SBHdr* h = _sb_table[idx];
    int slen = (int)strlen(s);
    while (h->len + slen + 1 > h->cap) {
        int newcap = h->cap * 2;
        h = (SBHdr*)realloc(h, sizeof(SBHdr) + newcap);
        h->cap = newcap;
    }
    memcpy((char*)(h + 1) + h->len, s, slen);
    h->len += slen;
    ((char*)(h + 1))[h->len] = 0;
    _sb_table[idx] = h;
    return kr_str(handle);
}

static char* kr_sbtostring(const char* handle) {
    int idx = atoi(handle);
    SBHdr* h = _sb_table[idx];
    return (char*)(h + 1);
}

#include <setjmp.h>
#define _KR_TRY_MAX 256
static jmp_buf _kr_try_stack[_KR_TRY_MAX];
static char*   _kr_err_stack[_KR_TRY_MAX];
static int     _kr_try_depth = 0;

static jmp_buf* _kr_pushtry() {
    _kr_err_stack[_kr_try_depth] = _K_EMPTY;
    return &_kr_try_stack[_kr_try_depth++];
}

static char* _kr_poptry() {
    if (_kr_try_depth > 0) _kr_try_depth--;
    return _kr_err_stack[_kr_try_depth];
}

static char* _kr_throw(const char* msg) {
    if (_kr_try_depth > 0) {
        _kr_err_stack[_kr_try_depth - 1] = (char*)msg;
        longjmp(_kr_try_stack[_kr_try_depth - 1], 1);
    }
    fprintf(stderr, "Uncaught exception: %s\n", msg);
    exit(1);
    return _K_EMPTY;
}

static char* kr_strreverse(const char* s) {
    int n = (int)strlen(s);
    char* out = _alloc(n + 1);
    for (int i = 0; i < n; i++) out[i] = s[n - 1 - i];
    out[n] = 0;
    return out;
}

static char* kr_words(const char* s) {
    if (!*s) return _K_EMPTY;
    char* out = _K_EMPTY; int first = 1;
    const char* p = s;
    while (*p == ' ' || *p == '\t') p++;
    const char* start = p;
    while (1) {
        if (*p == ' ' || *p == '\t' || *p == 0) {
            if (p > start) {
                int n = (int)(p - start);
                char* w = _alloc(n + 1);
                memcpy(w, start, n); w[n] = 0;
                if (first) { out = w; first = 0; }
                else out = kr_cat(kr_cat(out, ","), w);
            }
            if (!*p) break;
            while (*p == ' ' || *p == '\t') p++;
            start = p;
        } else { p++; }
    }
    return out;
}

static char* kr_lines(const char* s) {
    if (!*s) return _K_EMPTY;
    char* out = _K_EMPTY; int first = 1;
    const char* p = s, *start = s;
    while (1) {
        if (*p == '\n' || *p == 0) {
            int n = (int)(p - start);
            if (n > 0 && start[n-1] == '\r') n--;
            char* ln = _alloc(n + 1);
            memcpy(ln, start, n); ln[n] = 0;
            if (first) { out = ln; first = 0; }
            else out = kr_cat(kr_cat(out, ","), ln);
            if (!*p) break;
            start = p + 1;
        }
        p++;
    }
    return out;
}

static char* kr_first(const char* lst) { return kr_split(lst, _K_ZERO); }

static char* kr_last(const char* lst) {
    int cnt = kr_listlen(lst);
    if (cnt == 0) return _K_EMPTY;
    return kr_split(lst, kr_itoa(cnt - 1));
}

static char* kr_head(const char* lst, const char* ns) {
    int n = atoi(ns), cnt = kr_listlen(lst);
    if (n <= 0 || !*lst) return _K_EMPTY;
    if (n >= cnt) return kr_str(lst);
    char* out = kr_split(lst, _K_ZERO);
    for (int i = 1; i < n; i++) out = kr_cat(kr_cat(out, ","), kr_split(lst, kr_itoa(i)));
    return out;
}

static char* kr_tail(const char* lst, const char* ns) {
    int n = atoi(ns), cnt = kr_listlen(lst);
    if (n <= 0 || !*lst) return _K_EMPTY;
    if (n >= cnt) return kr_str(lst);
    int start = cnt - n;
    char* out = kr_split(lst, kr_itoa(start));
    for (int i = start + 1; i < cnt; i++) out = kr_cat(kr_cat(out, ","), kr_split(lst, kr_itoa(i)));
    return out;
}

static char* kr_lstrip(const char* s) {
    while (*s == ' ' || *s == '\t' || *s == '\n' || *s == '\r') s++;
    return kr_str(s);
}

static char* kr_rstrip(const char* s) {
    int len = (int)strlen(s);
    while (len > 0 && (s[len-1]==' '||s[len-1]=='\t'||s[len-1]=='\n'||s[len-1]=='\r')) len--;
    char* r = _alloc(len + 1);
    memcpy(r, s, len); r[len] = 0;
    return r;
}

static char* kr_center(const char* s, const char* ws, const char* pad) {
    int w = atoi(ws), slen = (int)strlen(s), plen = (int)strlen(pad);
    if (slen >= w || plen == 0) return kr_str(s);
    int total = w - slen;
    int left = total / 2, right = total - left;
    char* out = _alloc(w + 1);
    for (int i = 0; i < left; i++) out[i] = pad[i % plen];
    memcpy(out + left, s, slen);
    for (int i = 0; i < right; i++) out[left + slen + i] = pad[i % plen];
    out[w] = 0;
    return out;
}

static char* kr_isalpha(const char* s) {
    if (!*s) return _K_ZERO;
    for (const char* p = s; *p; p++) if (!isalpha((unsigned char)*p)) return _K_ZERO;
    return _K_ONE;
}

static char* kr_isdigit(const char* s) {
    if (!*s) return _K_ZERO;
    for (const char* p = s; *p; p++) if (!isdigit((unsigned char)*p)) return _K_ZERO;
    return _K_ONE;
}

static char* kr_isspace(const char* s) {
    if (!*s) return _K_ZERO;
    for (const char* p = s; *p; p++) if (!isspace((unsigned char)*p)) return _K_ZERO;
    return _K_ONE;
}

static char* kr_random(const char* ns) {
    int n = atoi(ns);
    if (n <= 0) return _K_ZERO;
    return kr_itoa(rand() % n);
}

static char* kr_timestamp() {
    return kr_itoa((int)time(NULL));
}

static char* kr_environ(const char* name) {
    const char* v = getenv(name);
    if (!v) return _K_EMPTY;
    return kr_str(v);
}

static char* kr_floor(const char* s) { return kr_itoa((int)atoi(s)); }
static char* kr_ceil(const char* s)  { return kr_itoa((int)atoi(s)); }
static char* kr_round(const char* s) { return kr_itoa((int)atoi(s)); }

static char* kr_throw(const char* msg) { return _kr_throw(msg); }

static char* kr_structnew() {
    // 2 slots for count + up to 32 fields (name+val pairs)
    char** s = (char**)_alloc(66 * sizeof(char*));
    s[0] = _K_ZERO; // field count
    return (char*)s;
}

static char* kr_setfield(char* obj, const char* name, const char* val) {
    char** s = (char**)obj;
    int cnt = atoi(s[0]);
    // search for existing field
    for (int i = 0; i < cnt; i++) {
        if (strcmp(s[1 + i*2], name) == 0) {
            s[2 + i*2] = (char*)val;
            return obj;
        }
    }
    // add new field
    s[1 + cnt*2] = (char*)name;
    s[2 + cnt*2] = (char*)val;
    s[0] = kr_itoa(cnt + 1);
    return obj;
}

static char* kr_getfield(char* obj, const char* name) {
    if (!obj) return _K_EMPTY;
    char** s = (char**)obj;
    int cnt = atoi(s[0]);
    for (int i = 0; i < cnt; i++) {
        if (strcmp(s[1 + i*2], name) == 0) return s[2 + i*2];
    }
    return _K_EMPTY;
}

static char* kr_hasfield(char* obj, const char* name) {
    if (!obj) return _K_ZERO;
    char** s = (char**)obj;
    int cnt = atoi(s[0]);
    for (int i = 0; i < cnt; i++) {
        if (strcmp(s[1 + i*2], name) == 0) return _K_ONE;
    }
    return _K_ZERO;
}

static char* kr_structfields(char* obj) {
    if (!obj) return _K_EMPTY;
    char** s = (char**)obj;
    int cnt = atoi(s[0]);
    if (cnt == 0) return _K_EMPTY;
    char* out = s[1];
    for (int i = 1; i < cnt; i++) out = kr_cat(kr_cat(out, ","), s[1 + i*2]);
    return out;
}

static char* kr_mapget(const char* map, const char* key) {
    if (!*map) return _K_EMPTY;
    int cnt = kr_listlen(map);
    for (int i = 0; i < cnt - 1; i += 2) {
        if (strcmp(kr_split(map, kr_itoa(i)), key) == 0)
            return kr_split(map, kr_itoa(i + 1));
    }
    return _K_EMPTY;
}

static char* kr_mapset(const char* map, const char* key, const char* val) {
    if (!*map) return kr_cat(kr_cat(kr_str(key), ","), val);
    int cnt = kr_listlen(map);
    char* out = _K_EMPTY; int first = 1; int found = 0;
    for (int i = 0; i < cnt - 1; i += 2) {
        char* k = kr_split(map, kr_itoa(i));
        char* v = (strcmp(k, key) == 0) ? (char*)val : kr_split(map, kr_itoa(i+1));
        if (strcmp(k, key) == 0) found = 1;
        if (first) { out = kr_cat(k, kr_cat(",", v)); first = 0; }
        else out = kr_cat(out, kr_cat(",", kr_cat(k, kr_cat(",", v))));
    }
    if (!found) {
        if (first) out = kr_cat(kr_str(key), kr_cat(",", val));
        else out = kr_cat(out, kr_cat(",", kr_cat(kr_str(key), kr_cat(",", val))));
    }
    return out;
}

static char* kr_mapdel(const char* map, const char* key) {
    if (!*map) return _K_EMPTY;
    int cnt = kr_listlen(map);
    char* out = _K_EMPTY; int first = 1;
    for (int i = 0; i < cnt - 1; i += 2) {
        char* k = kr_split(map, kr_itoa(i));
        if (strcmp(k, key) != 0) {
            char* v = kr_split(map, kr_itoa(i+1));
            if (first) { out = kr_cat(k, kr_cat(",", v)); first = 0; }
            else out = kr_cat(out, kr_cat(",", kr_cat(k, kr_cat(",", v))));
        }
    }
    return out;
}

static char* kr_sprintf(const char* fmt, ...) {
    char buf[4096];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    return kr_str(buf);
}

static char* kr_strsplit(const char* s, const char* delim) {
    return kr_splitby(s, delim);
}

static char* kr_listmap(const char* lst, const char* prefix, const char* suffix) {
    if (!*lst) return _K_EMPTY;
    int cnt = kr_listlen(lst);
    char* out = _K_EMPTY; int first = 1;
    for (int i = 0; i < cnt; i++) {
        char* item = kr_split(lst, kr_itoa(i));
        char* mapped = kr_cat(kr_cat(kr_str(prefix), item), suffix);
        if (first) { out = mapped; first = 0; }
        else out = kr_cat(out, kr_cat(",", mapped));
    }
    return out;
}

static char* kr_listfilter(const char* lst, const char* val) {
    if (!*lst) return _K_EMPTY;
    int cnt = kr_listlen(lst), negate = 0;
    const char* match = val;
    if (val[0] == '!') { negate = 1; match = val + 1; }
    char* out = _K_EMPTY; int first = 1;
    for (int i = 0; i < cnt; i++) {
        char* item = kr_split(lst, kr_itoa(i));
        int eq = (strcmp(item, match) == 0);
        int keep = negate ? !eq : eq;
        if (keep) {
            if (first) { out = item; first = 0; }
            else out = kr_cat(out, kr_cat(",", item));
        }
    }
    return out;
}

#include <math.h>
static char* kr_tofloat(const char* s) {
    return s;
}

static char* kr_fadd(const char* a,const char* b){char buf[64];snprintf(buf,64,"%g",atof(a)+atof(b));return kr_str(buf);}
static char* kr_fsub(const char* a,const char* b){char buf[64];snprintf(buf,64,"%g",atof(a)-atof(b));return kr_str(buf);}
static char* kr_fmul(const char* a,const char* b){char buf[64];snprintf(buf,64,"%g",atof(a)*atof(b));return kr_str(buf);}
static char* kr_fdiv(const char* a,const char* b){char buf[64];if(atof(b)==0.0)return kr_str("0");snprintf(buf,64,"%g",atof(a)/atof(b));return kr_str(buf);}
static char* kr_flt(const char* a,const char* b){return atof(a)<atof(b)?_K_ONE:_K_ZERO;}
static char* kr_fgt(const char* a,const char* b){return atof(a)>atof(b)?_K_ONE:_K_ZERO;}
static char* kr_feq(const char* a,const char* b){return atof(a)==atof(b)?_K_ONE:_K_ZERO;}
static char* kr_fsqrt(const char* a) {
    char buf[64]; snprintf(buf,64,"%g",sqrt(atof(a)));
    return kr_str(buf);
}

static char* kr_ffloor(const char* a) {
    char buf[64]; snprintf(buf,64,"%.0f",floor(atof(a)));
    return kr_str(buf);
}

static char* kr_fceil(const char* a) {
    char buf[64]; snprintf(buf,64,"%.0f",ceil(atof(a)));
    return kr_str(buf);
}

static char* kr_fround(const char* a) {
    char buf[64]; snprintf(buf,64,"%.0f",round(atof(a)));
    return kr_str(buf);
}

static char* kr_fformat(const char* a,const char* prec){char fmt[32],buf[64];snprintf(fmt,32,"%%.%sf",prec);snprintf(buf,64,fmt,atof(a));return kr_str(buf);}
static char* kr_bitand(const char* a,const char* b){return kr_itoa((int)((unsigned int)atoi(a)&(unsigned int)atoi(b)));}
static char* kr_bitor(const char* a,const char* b){return kr_itoa((int)((unsigned int)atoi(a)|(unsigned int)atoi(b)));}
static char* kr_bitxor(const char* a,const char* b){return kr_itoa((int)((unsigned int)atoi(a)^(unsigned int)atoi(b)));}
static char* kr_bitnot(const char* a){return kr_itoa((int)(~(unsigned int)atoi(a)));}
static char* kr_bitshl(const char* a,const char* b){return kr_itoa((int)((unsigned int)atoi(a)<<atoi(b)));}
static char* kr_bitshr(const char* a,const char* b){return kr_itoa((int)((unsigned int)atoi(a)>>atoi(b)));}
static char* kr_tolong(const char* s){char buf[32];snprintf(buf,32,"%lld",(long long)atoll(s));return kr_str(buf);}
static char* kr_div64(const char* a,const char* b){if(atoll(b)==0)return kr_str("0");char buf[32];snprintf(buf,32,"%lld",atoll(a)/atoll(b));return kr_str(buf);}
static char* kr_mod64(const char* a,const char* b){if(atoll(b)==0)return kr_str("0");char buf[32];long long r2=atoll(a)%atoll(b);snprintf(buf,32,"%lld",r2);return kr_str(buf);}
static char* kr_mul64(const char* a,const char* b){char buf[32];snprintf(buf,32,"%lld",atoll(a)*atoll(b));return kr_str(buf);}
static char* kr_add64(const char* a,const char* b){char buf[32];snprintf(buf,32,"%lld",atoll(a)+atoll(b));return kr_str(buf);}
static char* kr_eqignorecase(const char* a,const char* b){return _stricmp(a,b)==0?kr_str("1"):kr_str("0");}
static char* kr_handlevalid(const char* h){return (h!=NULL&&h!=(char*)(intptr_t)-1)?kr_str("1"):kr_str("0");}
static char* kr_bufgetdword(char* buf){unsigned int v=*(unsigned int*)buf;return kr_itoa((int)v);}
static char* kr_bufsetdword(char* buf,const char* vs){*(unsigned int*)buf=(unsigned int)atoi(vs);return _K_EMPTY;}
static char* kr_bufgetword(char* buf){return kr_itoa((int)(*(unsigned short*)buf));}
static char* kr_bufgetqword(char* buf){unsigned long long v=*(unsigned long long*)buf;char s[32];snprintf(s,32,"%llu",v);return kr_str(s);}
static char* kr_bufgetdwordat(char* buf,const char* off){unsigned int v=*(unsigned int*)(buf+atoi(off));return kr_itoa((int)v);}
static char* kr_bufgetqwordat(char* buf,const char* off){unsigned long long v=*(unsigned long long*)(buf+atoi(off));char s[32];snprintf(s,32,"%llu",v);return kr_str(s);}
static char* kr_bufsetbyte(char* buf,const char* off,const char* val){buf[atoi(off)]=(unsigned char)atoi(val);return _K_EMPTY;}
static char* kr_bufgetbyte(char* buf,const char* off){return kr_itoa((int)(unsigned char)buf[atoi(off)]);}
static char* kr_bufsetdwordat(char* buf,const char* off,const char* val){*(unsigned int*)(buf+atoi(off))=(unsigned int)atoll(val);return _K_EMPTY;}
static char* kr_bufsetqwordat(char* buf,const char* off,const char* val){*(unsigned long long*)(buf+atoi(off))=(unsigned long long)atoll(val);return _K_EMPTY;}
static char* kr_bufgetwordat(char* buf,const char* off){unsigned short v=*(unsigned short*)(buf+atoi(off));return kr_itoa((int)v);}
static char* kr_bufsetwordat(char* buf,const char* off,const char* val){*(unsigned short*)(buf+atoi(off))=(unsigned short)atoi(val);return _K_EMPTY;}
static char* kr_handleget(char* buf){return *(char**)buf;}
static char* kr_handleint(char* ptr){char s[32];snprintf(s,32,"%d",(int)(intptr_t)ptr);return kr_str(s);}
static char* kr_ptrderef(char* ptr){return *(char**)ptr;}
static char* kr_ptrindex(char* ptr,const char* n){return ((char**)ptr)[atoi(n)];}
static char* kr_callptr1(char* fn,char* a0){return ((char*(*)(char*))(fn))(a0);}
static char* kr_callptr2(char* fn,char* a0,char* a1){return ((char*(*)(char*,char*))(fn))(a0,a1);}
static char* kr_callptr3(char* fn,char* a0,char* a1,char* a2){return ((char*(*)(char*,char*,char*))(fn))(a0,a1,a2);}
static char* kr_callptr4(char* fn,char* a0,char* a1,char* a2,char* a3){return ((char*(*)(char*,char*,char*,char*))(fn))(a0,a1,a2,a3);}
static char* kr_mkclosure(const char* fn,const char* env){int fl=strlen(fn),el=strlen(env);char* p=_alloc(fl+el+2);memcpy(p,fn,fl);p[fl]='|';memcpy(p+fl+1,env,el+1);return p;}
static char* kr_closure_fn(const char* c){const char* p=strchr(c,'|');if(!p)return(char*)c;int n=p-c;char* r2=_alloc(n+1);memcpy(r2,c,n);r2[n]=0;return r2;}
static char* kr_closure_env(const char* c){const char* p=strchr(c,'|');return p?(char*)(p+1):(char*)_K_EMPTY;}
char* findLastComma(char*);
char* pairVal(char*);
char* pairPos(char*);
char* isDigit(char*);
char* charIsAlpha(char*);
char* charIsAlphaNum(char*);
char* hexDigitVal(char*);
char* readNumber(char*, char*);
char* readIdent(char*, char*);
char* readString(char*, char*);
char* skipWS(char*, char*);
char* skipComment(char*, char*);
char* isKW(char*);
char* readBacktickString(char*, char*);
char* tokenize(char*);
char* tokAt(char*, char*);
char* tokType(char*);
char* tokVal(char*);
char* cEscape(char*);
char* expandEscapes(char*);
char* scanFunctions(char*, char*);
char* funcLookup(char*, char*);
char* funcParamCount(char*);
char* funcParams(char*);
char* funcStart(char*);
char* getNthParam(char*, char*);
char* findEntry(char*, char*);
char* skipBlock(char*, char*);
char* indent(char*);
char* cIdent(char*);
char* compileExpr(char*, char*, char*);
char* compileTernary(char*, char*, char*);
char* compileOr(char*, char*, char*);
char* compileAnd(char*, char*, char*);
char* compileEquality(char*, char*, char*);
char* compileRelational(char*, char*, char*);
char* compileAdditive(char*, char*, char*);
char* compileMult(char*, char*, char*);
char* compilePow(char*, char*, char*);
char* compileUnary(char*, char*, char*);
char* compilePostfix(char*, char*, char*);
char* compilePrimary(char*, char*, char*);
char* compileWin32IntArgs(char*);
char* compileWin32Return64(char*);
char* compileWin32IntReturn(char*);
char* compileCsvHas(char*, char*);
char* compileCall(char*, char*, char*);
char* compileStmt(char*, char*, char*, char*, char*);
char* compileLet(char*, char*, char*, char*);
char* compileAssign(char*, char*, char*, char*);
char* compileEmit(char*, char*, char*, char*, char*);
char* compileIf(char*, char*, char*, char*, char*);
char* compileWhile(char*, char*, char*, char*, char*);
char* compileLambda(char*, char*, char*);
char* compileListLiteral(char*, char*, char*);
char* compileInterp(char*);
char* compileStructDecl(char*, char*, char*, char*);
char* compileFieldAssign(char*, char*, char*, char*);
char* compileStructLiteral(char*, char*, char*);
char* compileCompoundAssign(char*, char*, char*, char*);
char* compileFor(char*, char*, char*, char*, char*);
char* compileMatch(char*, char*, char*, char*, char*);
char* compileDoWhile(char*, char*, char*, char*, char*);
char* compileLoop(char*, char*, char*, char*, char*);
char* compileExprStmt(char*, char*, char*, char*);
char* compileBlock(char*, char*, char*, char*, char*);
char* hoistLambdas(char*);
char* compileFunc(char*, char*, char*);
char* compileCallbackFunc(char*, char*, char*);
char* sbNew();
char* sbAppend(char*, char*);
char* sbToString(char*);
char* cRuntime();
char* scanModuleFunctions(char*, char*);
char* compileImportedFunctions(char*, char*, char*);
char* compileImportedForwardDecls(char*, char*, char*);
char* irLabel(char*, char*);
char* irExpr(char*, char*, char*, char*, char*);
char* irTernary(char*, char*, char*, char*, char*);
char* irOr(char*, char*, char*, char*, char*);
char* irAnd(char*, char*, char*, char*, char*);
char* irEquality(char*, char*, char*, char*, char*);
char* irRelational(char*, char*, char*, char*, char*);
char* irAdditive(char*, char*, char*, char*, char*);
char* irMultiplicative(char*, char*, char*, char*, char*);
char* irPow(char*, char*, char*, char*, char*);
char* irUnary(char*, char*, char*, char*, char*);
char* irPostfix(char*, char*, char*, char*, char*);
char* irPrimary(char*, char*, char*, char*, char*);
char* irInterpToIR(char*, char*, char*, char*);
char* irListLiteralIR(char*, char*, char*, char*, char*);
char* irStructLiteralIR(char*, char*, char*, char*, char*);
char* irCall(char*, char*, char*, char*, char*);
char* irStmt(char*, char*, char*, char*, char*, char*);
char* irTypeStr(char*, char*, char*);
char* irTypeOf(char*, char*);
char* irStructSizeOf(char*, char*);
char* irSkipTypeBody(char*, char*);
char* irSkipTypeAnnotation(char*, char*);
char* irLetIR(char*, char*, char*, char*, char*, char*);
char* irBlockIR(char*, char*, char*, char*, char*, char*);
char* irIfIR(char*, char*, char*, char*, char*, char*);
char* irWhileIR(char*, char*, char*, char*, char*, char*);
char* irForIR(char*, char*, char*, char*, char*, char*);
char* irMatchIR(char*, char*, char*, char*, char*, char*);
char* irTryIR(char*, char*, char*, char*, char*, char*);
char* irScanStructTypes(char*, char*);
char* irScanStructTypesOnce(char*, char*, char*);
char* irScanFuncTypes(char*, char*);
char* irLambdaIR(char*, char*, char*, char*);
char* irFuncIR(char*, char*, char*);
char* findFreeVars(char*, char*, char*, char*);
char* emitPortWarnings(char*, char*, char*);

char* findLastComma(char* s) {
    char* i = kr_sub(kr_len(s), ((char*)"1"));
    while (kr_truthy(kr_gte(i, ((char*)"0")))) {
        if (kr_truthy(kr_eq(kr_idx(s, kr_atoi(i)), ((char*)",")))) {
            return i;
        }
        i = kr_sub(i, ((char*)"1"));
    }
    return kr_neg(((char*)"1"));
}

char* pairVal(char* pair) {
    char* c = ((char*(*)(char*))findLastComma)(pair);
    if (kr_truthy(kr_lt(c, ((char*)"0")))) {
        return pair;
    }
    return kr_substr(pair, ((char*)"0"), c);
}

char* pairPos(char* pair) {
    char* c = ((char*(*)(char*))findLastComma)(pair);
    return kr_toint(kr_substr(pair, kr_plus(c, ((char*)"1")), kr_len(pair)));
}

char* isDigit(char* c) {
    return (kr_truthy(kr_gte(c, ((char*)"0"))) && kr_truthy(kr_lte(c, ((char*)"9"))) ? kr_str("1") : kr_str("0"));
}

char* charIsAlpha(char* c) {
    return (kr_truthy((kr_truthy((kr_truthy(kr_gte(c, ((char*)"a"))) && kr_truthy(kr_lte(c, ((char*)"z"))) ? kr_str("1") : kr_str("0"))) || kr_truthy((kr_truthy(kr_gte(c, ((char*)"A"))) && kr_truthy(kr_lte(c, ((char*)"Z"))) ? kr_str("1") : kr_str("0"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(c, ((char*)"_"))) ? kr_str("1") : kr_str("0"));
}

char* charIsAlphaNum(char* c) {
    return (kr_truthy(((char*(*)(char*))charIsAlpha)(c)) || kr_truthy((kr_truthy(kr_gte(c, ((char*)"0"))) && kr_truthy(kr_lte(c, ((char*)"9"))) ? kr_str("1") : kr_str("0"))) ? kr_str("1") : kr_str("0"));
}

char* hexDigitVal(char* c) {
    if (kr_truthy((kr_truthy(kr_gte(c, ((char*)"0"))) && kr_truthy(kr_lte(c, ((char*)"9"))) ? kr_str("1") : kr_str("0")))) {
        return kr_sub(kr_charcode(c), kr_charcode(((char*)"0")));
    }
    if (kr_truthy((kr_truthy(kr_gte(c, ((char*)"a"))) && kr_truthy(kr_lte(c, ((char*)"f"))) ? kr_str("1") : kr_str("0")))) {
        return kr_plus(kr_sub(kr_charcode(c), kr_charcode(((char*)"a"))), ((char*)"10"));
    }
    if (kr_truthy((kr_truthy(kr_gte(c, ((char*)"A"))) && kr_truthy(kr_lte(c, ((char*)"F"))) ? kr_str("1") : kr_str("0")))) {
        return kr_plus(kr_sub(kr_charcode(c), kr_charcode(((char*)"A"))), ((char*)"10"));
    }
    return kr_neg(((char*)"1"));
}

char* readNumber(char* text, char* i) {
    char* start = i;
    if (kr_truthy((kr_truthy((kr_truthy(kr_eq(kr_idx(text, kr_atoi(i)), ((char*)"0"))) && kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) ? kr_str("1") : kr_str("0"))) && kr_truthy((kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"x"))) || kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"X"))) ? kr_str("1") : kr_str("0"))) ? kr_str("1") : kr_str("0")))) {
        i = kr_plus(i, ((char*)"2"));
        char* hexVal = ((char*)"0");
        while (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy(kr_gte(((char*(*)(char*))hexDigitVal)(kr_idx(text, kr_atoi(i))), ((char*)"0"))) ? kr_str("1") : kr_str("0")))) {
            hexVal = kr_plus(kr_mul(hexVal, ((char*)"16")), ((char*(*)(char*))hexDigitVal)(kr_idx(text, kr_atoi(i))));
            i = kr_plus(i, ((char*)"1"));
        }
        return kr_plus(kr_plus(hexVal, ((char*)",")), i);
    }
    while (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy(kr_isdigit(kr_idx(text, kr_atoi(i)))) ? kr_str("1") : kr_str("0")))) {
        i = kr_plus(i, ((char*)"1"));
    }
    if (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(i)), ((char*)"."))) ? kr_str("1") : kr_str("0")))) {
        if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) && kr_truthy(kr_isdigit(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))))) ? kr_str("1") : kr_str("0")))) {
            i = kr_plus(i, ((char*)"1"));
            while (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy(kr_isdigit(kr_idx(text, kr_atoi(i)))) ? kr_str("1") : kr_str("0")))) {
                i = kr_plus(i, ((char*)"1"));
            }
        }
    }
    return kr_plus(kr_plus(kr_substr(text, start, i), ((char*)",")), i);
}

char* readIdent(char* text, char* i) {
    char* start = i;
    while (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy(((char*(*)(char*))charIsAlphaNum)(kr_idx(text, kr_atoi(i)))) ? kr_str("1") : kr_str("0")))) {
        i = kr_plus(i, ((char*)"1"));
    }
    return kr_plus(kr_plus(kr_substr(text, start, i), ((char*)",")), i);
}

char* readString(char* text, char* i) {
    i = kr_plus(i, ((char*)"1"));
    char* start = i;
    char* sb = kr_sbnew();
    while (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy(kr_neq(kr_idx(text, kr_atoi(i)), ((char*)"\""))) ? kr_str("1") : kr_str("0")))) {
        if (kr_truthy((kr_truthy(kr_eq(kr_idx(text, kr_atoi(i)), ((char*)"\\"))) && kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) ? kr_str("1") : kr_str("0")))) {
            if (kr_truthy(kr_gt(i, start))) {
                sb = kr_sbappend(sb, kr_substr(text, start, i));
            }
            sb = kr_sbappend(sb, kr_substr(text, i, kr_plus(i, ((char*)"2"))));
            i = kr_plus(i, ((char*)"2"));
            start = i;
        } else {
            i = kr_plus(i, ((char*)"1"));
        }
    }
    if (kr_truthy(kr_gt(i, start))) {
        sb = kr_sbappend(sb, kr_substr(text, start, i));
    }
    return kr_plus(kr_plus(kr_sbtostring(sb), ((char*)",")), kr_plus(i, ((char*)"1")));
}

char* skipWS(char* text, char* i) {
    while (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(kr_idx(text, kr_atoi(i)), ((char*)" "))) || kr_truthy(kr_eq(kr_idx(text, kr_atoi(i)), ((char*)"\n"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(kr_idx(text, kr_atoi(i)), ((char*)"\t"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(kr_idx(text, kr_atoi(i)), ((char*)"\\r"))) ? kr_str("1") : kr_str("0"))) ? kr_str("1") : kr_str("0")))) {
        i = kr_plus(i, ((char*)"1"));
    }
    return i;
}

char* skipComment(char* text, char* i) {
    if (kr_truthy((kr_truthy((kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(i)), ((char*)"/"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"/"))) ? kr_str("1") : kr_str("0")))) {
        while (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy(kr_neq(kr_idx(text, kr_atoi(i)), ((char*)"\n"))) ? kr_str("1") : kr_str("0")))) {
            i = kr_plus(i, ((char*)"1"));
        }
        return i;
    } else if (kr_truthy((kr_truthy((kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(i)), ((char*)"/"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"*"))) ? kr_str("1") : kr_str("0")))) {
        i = kr_plus(i, ((char*)"2"));
        while (kr_truthy((kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) && kr_truthy((kr_truthy(kr_neq(kr_idx(text, kr_atoi(i)), ((char*)"*"))) || kr_truthy(kr_neq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"/"))) ? kr_str("1") : kr_str("0"))) ? kr_str("1") : kr_str("0")))) {
            i = kr_plus(i, ((char*)"1"));
        }
        return kr_plus(i, ((char*)"2"));
    }
    return i;
}

char* isKW(char* word) {
    if (kr_truthy(kr_eq(word, ((char*)"just")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"go")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"func")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"fn")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"let")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"emit")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"return")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"if")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"else")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"while")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"break")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"continue")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"for")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"in")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"match")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"do")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"const")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"module")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"import")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"export")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"struct")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"class")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"type")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"try")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"catch")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"throw")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"quantum")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"qpute")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"process")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"true")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"false")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"null")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"measure")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"prepare")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"jxt")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"callback")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"loop")))) {
        return ((char*)"1");
    } else if (kr_truthy(kr_eq(word, ((char*)"until")))) {
        return ((char*)"1");
    } else {
        return ((char*)"0");
    }
}

char* readBacktickString(char* text, char* i) {
    i = kr_plus(i, ((char*)"1"));
    char* sb = kr_sbnew();
    while (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy(kr_neq(kr_idx(text, kr_atoi(i)), ((char*)"`"))) ? kr_str("1") : kr_str("0")))) {
        sb = kr_sbappend(sb, kr_idx(text, kr_atoi(i)));
        i = kr_plus(i, ((char*)"1"));
    }
    return kr_plus(kr_plus(kr_sbtostring(sb), ((char*)",")), kr_plus(i, ((char*)"1")));
}

char* tokenize(char* text) {
    char* out = kr_sbnew();
    char* i = ((char*)"0");
    if (kr_truthy((kr_truthy((kr_truthy(kr_gte(kr_len(text), ((char*)"2"))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(((char*)"0"))), ((char*)"#"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(((char*)"1"))), ((char*)"!"))) ? kr_str("1") : kr_str("0")))) {
        while (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy(kr_neq(kr_idx(text, kr_atoi(i)), ((char*)"\n"))) ? kr_str("1") : kr_str("0")))) {
            i = kr_plus(i, ((char*)"1"));
        }
        if (kr_truthy(kr_lt(i, kr_len(text)))) {
            i = kr_plus(i, ((char*)"1"));
        }
    }
    while (kr_truthy(kr_lt(i, kr_len(text)))) {
        i = ((char*(*)(char*,char*))skipWS)(text, i);
        if (kr_truthy(kr_gte(i, kr_len(text)))) {
            break;
        }
        char* c = kr_idx(text, kr_atoi(i));
        if (kr_truthy((kr_truthy((kr_truthy(kr_eq(c, ((char*)"/"))) && kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) ? kr_str("1") : kr_str("0"))) && kr_truthy((kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"/"))) || kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"*"))) ? kr_str("1") : kr_str("0"))) ? kr_str("1") : kr_str("0")))) {
            i = ((char*(*)(char*,char*))skipComment)(text, i);
        } else if (kr_truthy(kr_isdigit(c))) {
            char* pair = ((char*(*)(char*,char*))readNumber)(text, i);
            char* k_num = ((char*(*)(char*))pairVal)(pair);
            i = ((char*(*)(char*))pairPos)(pair);
            out = kr_sbappend(out, kr_plus(kr_plus(((char*)"INT:"), k_num), ((char*)"\n")));
        } else if (kr_truthy(kr_eq(c, ((char*)"\"")))) {
            char* pair = ((char*(*)(char*,char*))readString)(text, i);
            char* str = ((char*(*)(char*))pairVal)(pair);
            i = ((char*(*)(char*))pairPos)(pair);
            out = kr_sbappend(out, kr_plus(kr_plus(((char*)"STR:"), str), ((char*)"\n")));
        } else if (kr_truthy(((char*(*)(char*))charIsAlpha)(c))) {
            char* pair = ((char*(*)(char*,char*))readIdent)(text, i);
            char* id = ((char*(*)(char*))pairVal)(pair);
            i = ((char*(*)(char*))pairPos)(pair);
            if (kr_truthy(kr_eq(id, ((char*)"cfunc")))) {
                char* ci2 = ((char*(*)(char*,char*))skipWS)(text, i);
                if (kr_truthy((kr_truthy(kr_lt(ci2, kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(ci2)), ((char*)"{"))) ? kr_str("1") : kr_str("0")))) {
                    ci2 = kr_plus(ci2, ((char*)"1"));
                    char* ctext = ((char*)"");
                    char* cdepth = ((char*)"1");
                    char* inStr = ((char*)"0");
                    while (kr_truthy((kr_truthy(kr_lt(ci2, kr_len(text))) && kr_truthy(kr_gt(cdepth, ((char*)"0"))) ? kr_str("1") : kr_str("0")))) {
                        char* ch = kr_idx(text, kr_atoi(ci2));
                        if (kr_truthy(kr_eq(inStr, ((char*)"1")))) {
                            if (kr_truthy((kr_truthy(kr_eq(ch, ((char*)"\\"))) && kr_truthy(kr_lt(kr_plus(ci2, ((char*)"1")), kr_len(text))) ? kr_str("1") : kr_str("0")))) {
                                ctext = kr_plus(kr_plus(ctext, ch), kr_idx(text, kr_atoi(kr_plus(ci2, ((char*)"1")))));
                                ci2 = kr_plus(ci2, ((char*)"2"));
                            } else {
                                if (kr_truthy(kr_eq(ch, ((char*)"\"")))) {
                                    inStr = ((char*)"0");
                                }
                                if (kr_truthy(kr_eq(ch, ((char*)"\n")))) {
                                    ctext = kr_plus(ctext, ((char*)"\\x01"));
                                } else {
                                    ctext = kr_plus(ctext, ch);
                                }
                                ci2 = kr_plus(ci2, ((char*)"1"));
                            }
                        } else {
                            if (kr_truthy(kr_eq(ch, ((char*)"\"")))) {
                                inStr = ((char*)"1");
                                ctext = kr_plus(ctext, ch);
                                ci2 = kr_plus(ci2, ((char*)"1"));
                            } else if (kr_truthy(kr_eq(ch, ((char*)"{")))) {
                                cdepth = kr_plus(cdepth, ((char*)"1"));
                                ctext = kr_plus(ctext, ch);
                                ci2 = kr_plus(ci2, ((char*)"1"));
                            } else if (kr_truthy(kr_eq(ch, ((char*)"}")))) {
                                cdepth = kr_sub(cdepth, ((char*)"1"));
                                if (kr_truthy(kr_gt(cdepth, ((char*)"0")))) {
                                    ctext = kr_plus(ctext, ch);
                                }
                                ci2 = kr_plus(ci2, ((char*)"1"));
                            } else if (kr_truthy(kr_eq(ch, ((char*)"\n")))) {
                                ctext = kr_plus(ctext, ((char*)"\\x01"));
                                ci2 = kr_plus(ci2, ((char*)"1"));
                            } else if (kr_truthy(kr_eq(ch, ((char*)"\\r")))) {
                                ci2 = kr_plus(ci2, ((char*)"1"));
                            } else {
                                ctext = kr_plus(ctext, ch);
                                ci2 = kr_plus(ci2, ((char*)"1"));
                            }
                        }
                    }
                    i = ci2;
                    out = kr_sbappend(out, kr_plus(kr_plus(((char*)"CBLOCK:"), ctext), ((char*)"\n")));
                }
            } else if (kr_truthy(((char*(*)(char*))isKW)(id))) {
                out = kr_sbappend(out, kr_plus(kr_plus(((char*)"KW:"), id), ((char*)"\n")));
                if (kr_truthy(kr_eq(id, ((char*)"jxt")))) {
                    char* ji = ((char*(*)(char*,char*))skipWS)(text, i);
                    char* bracketless = ((char*)"0");
                    if (kr_truthy(kr_lt(ji, kr_len(text)))) {
                        if (kr_truthy(kr_neq(kr_idx(text, kr_atoi(ji)), ((char*)"{")))) {
                            bracketless = ((char*)"1");
                        }
                    }
                    if (kr_truthy(kr_eq(bracketless, ((char*)"1")))) {
                        out = kr_sbappend(out, ((char*)"LBRACE\n"));
                        char* done = ((char*)"0");
                        while (kr_truthy(kr_eq(done, ((char*)"0")))) {
                            char* ji2 = ((char*(*)(char*,char*))skipWS)(text, ji);
                            if (kr_truthy(kr_gte(ji2, kr_len(text)))) {
                                done = ((char*)"1");
                            } else {
                                if (kr_truthy(((char*(*)(char*))charIsAlpha)(kr_idx(text, kr_atoi(ji2))))) {
                                    char* pp = ((char*(*)(char*,char*))readIdent)(text, ji2);
                                    char* nm = ((char*(*)(char*))pairVal)(pp);
                                    if (kr_truthy(kr_eq(nm, ((char*)"inc")))) {
                                        char* ji3 = ((char*(*)(char*))pairPos)(pp);
                                        ji3 = ((char*(*)(char*,char*))skipWS)(text, ji3);
                                        char* haveStr = ((char*)"0");
                                        if (kr_truthy(kr_lt(ji3, kr_len(text)))) {
                                            if (kr_truthy(kr_eq(kr_idx(text, kr_atoi(ji3)), ((char*)"\"")))) {
                                                haveStr = ((char*)"1");
                                            }
                                        }
                                        if (kr_truthy(kr_eq(haveStr, ((char*)"1")))) {
                                            char* sp = ((char*(*)(char*,char*))readString)(text, ji3);
                                            char* path = ((char*(*)(char*))pairVal)(sp);
                                            ji = ((char*(*)(char*))pairPos)(sp);
                                            char* lang = ((char*)"k");
                                            if (kr_truthy(kr_endswith(path, ((char*)".h")))) {
                                                lang = ((char*)"c");
                                            }
                                            if (kr_truthy(kr_endswith(path, ((char*)".krh")))) {
                                                lang = ((char*)"c");
                                            }
                                            out = kr_sbappend(out, kr_plus(kr_plus(((char*)"ID:"), lang), ((char*)"\n")));
                                            out = kr_sbappend(out, kr_plus(kr_plus(((char*)"STR:"), path), ((char*)"\n")));
                                        } else {
                                            done = ((char*)"1");
                                        }
                                    } else {
                                        done = ((char*)"1");
                                    }
                                } else {
                                    done = ((char*)"1");
                                }
                            }
                        }
                        out = kr_sbappend(out, ((char*)"RBRACE\n"));
                        i = ji;
                    }
                }
            } else {
                out = kr_sbappend(out, kr_plus(kr_plus(((char*)"ID:"), id), ((char*)"\n")));
            }
        } else if (kr_truthy(kr_eq(c, ((char*)"+")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"+"))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, ((char*)"PLUSPLUS\n"));
                i = kr_plus(i, ((char*)"2"));
            } else if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, ((char*)"PLUSEQ\n"));
                i = kr_plus(i, ((char*)"2"));
            } else {
                out = kr_sbappend(out, ((char*)"PLUS\n"));
                i = kr_plus(i, ((char*)"1"));
            }
        } else if (kr_truthy(kr_eq(c, ((char*)"-")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)">"))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, ((char*)"ARROW\n"));
                i = kr_plus(i, ((char*)"2"));
            } else if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"-"))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, ((char*)"MINUSMINUS\n"));
                i = kr_plus(i, ((char*)"2"));
            } else if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, ((char*)"MINUSEQ\n"));
                i = kr_plus(i, ((char*)"2"));
            } else {
                out = kr_sbappend(out, ((char*)"MINUS\n"));
                i = kr_plus(i, ((char*)"1"));
            }
        } else if (kr_truthy(kr_eq(c, ((char*)"*")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"*"))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, ((char*)"STARSTAR\n"));
                i = kr_plus(i, ((char*)"2"));
            } else if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, ((char*)"STAREQ\n"));
                i = kr_plus(i, ((char*)"2"));
            } else {
                out = kr_sbappend(out, ((char*)"STAR\n"));
                i = kr_plus(i, ((char*)"1"));
            }
        } else if (kr_truthy(kr_eq(c, ((char*)"/")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, ((char*)"SLASHEQ\n"));
                i = kr_plus(i, ((char*)"2"));
            } else {
                out = kr_sbappend(out, ((char*)"SLASH\n"));
                i = kr_plus(i, ((char*)"1"));
            }
        } else if (kr_truthy(kr_eq(c, ((char*)"(")))) {
            out = kr_sbappend(out, ((char*)"LPAREN\n"));
            i = kr_plus(i, ((char*)"1"));
        } else if (kr_truthy(kr_eq(c, ((char*)")")))) {
            out = kr_sbappend(out, ((char*)"RPAREN\n"));
            i = kr_plus(i, ((char*)"1"));
        } else if (kr_truthy(kr_eq(c, ((char*)"{")))) {
            out = kr_sbappend(out, ((char*)"LBRACE\n"));
            i = kr_plus(i, ((char*)"1"));
        } else if (kr_truthy(kr_eq(c, ((char*)"}")))) {
            out = kr_sbappend(out, ((char*)"RBRACE\n"));
            i = kr_plus(i, ((char*)"1"));
        } else if (kr_truthy(kr_eq(c, ((char*)"[")))) {
            out = kr_sbappend(out, ((char*)"LBRACK\n"));
            i = kr_plus(i, ((char*)"1"));
        } else if (kr_truthy(kr_eq(c, ((char*)"]")))) {
            out = kr_sbappend(out, ((char*)"RBRACK\n"));
            i = kr_plus(i, ((char*)"1"));
        } else if (kr_truthy(kr_eq(c, ((char*)":")))) {
            out = kr_sbappend(out, ((char*)"COLON\n"));
            i = kr_plus(i, ((char*)"1"));
        } else if (kr_truthy(kr_eq(c, ((char*)";")))) {
            out = kr_sbappend(out, ((char*)"SEMI\n"));
            i = kr_plus(i, ((char*)"1"));
        } else if (kr_truthy(kr_eq(c, ((char*)",")))) {
            out = kr_sbappend(out, ((char*)"COMMA\n"));
            i = kr_plus(i, ((char*)"1"));
        } else if (kr_truthy(kr_eq(c, ((char*)"=")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, ((char*)"EQ\n"));
                i = kr_plus(i, ((char*)"2"));
            } else {
                out = kr_sbappend(out, ((char*)"ASSIGN\n"));
                i = kr_plus(i, ((char*)"1"));
            }
        } else if (kr_truthy(kr_eq(c, ((char*)"!")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, ((char*)"NEQ\n"));
                i = kr_plus(i, ((char*)"2"));
            } else {
                out = kr_sbappend(out, ((char*)"BANG\n"));
                i = kr_plus(i, ((char*)"1"));
            }
        } else if (kr_truthy(kr_eq(c, ((char*)"<")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, ((char*)"LTE\n"));
                i = kr_plus(i, ((char*)"2"));
            } else {
                out = kr_sbappend(out, ((char*)"LT\n"));
                i = kr_plus(i, ((char*)"1"));
            }
        } else if (kr_truthy(kr_eq(c, ((char*)">")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, ((char*)"GTE\n"));
                i = kr_plus(i, ((char*)"2"));
            } else {
                out = kr_sbappend(out, ((char*)"GT\n"));
                i = kr_plus(i, ((char*)"1"));
            }
        } else if (kr_truthy(kr_eq(c, ((char*)"&")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"&"))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, ((char*)"AND\n"));
                i = kr_plus(i, ((char*)"2"));
            } else {
                i = kr_plus(i, ((char*)"1"));
            }
        } else if (kr_truthy(kr_eq(c, ((char*)"|")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"|"))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, ((char*)"OR\n"));
                i = kr_plus(i, ((char*)"2"));
            } else {
                i = kr_plus(i, ((char*)"1"));
            }
        } else if (kr_truthy(kr_eq(c, ((char*)"%")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, ((char*)"1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, ((char*)"1")))), ((char*)"="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, ((char*)"MODEQ\n"));
                i = kr_plus(i, ((char*)"2"));
            } else {
                out = kr_sbappend(out, ((char*)"MOD\n"));
                i = kr_plus(i, ((char*)"1"));
            }
        } else if (kr_truthy(kr_eq(c, ((char*)"?")))) {
            out = kr_sbappend(out, ((char*)"QUESTION\n"));
            i = kr_plus(i, ((char*)"1"));
        } else if (kr_truthy(kr_eq(c, ((char*)".")))) {
            out = kr_sbappend(out, ((char*)"DOT\n"));
            i = kr_plus(i, ((char*)"1"));
        } else if (kr_truthy(kr_eq(c, ((char*)"`")))) {
            char* pair = ((char*(*)(char*,char*))readBacktickString)(text, i);
            char* str = ((char*(*)(char*))pairVal)(pair);
            i = ((char*(*)(char*))pairPos)(pair);
            out = kr_sbappend(out, kr_plus(kr_plus(((char*)"INTERP:"), str), ((char*)"\n")));
        } else {
            i = kr_plus(i, ((char*)"1"));
        }
    }
    return kr_sbtostring(out);
}

char* tokAt(char* tokens, char* idx) {
    return kr_getline(tokens, idx);
}

char* tokType(char* tok) {
    char* i = ((char*)"0");
    while (kr_truthy(kr_lt(i, kr_len(tok)))) {
        if (kr_truthy(kr_eq(kr_idx(tok, kr_atoi(i)), ((char*)":")))) {
            return kr_substr(tok, ((char*)"0"), i);
        }
        i = kr_plus(i, ((char*)"1"));
    }
    return tok;
}

char* tokVal(char* tok) {
    char* i = ((char*)"0");
    while (kr_truthy(kr_lt(i, kr_len(tok)))) {
        if (kr_truthy(kr_eq(kr_idx(tok, kr_atoi(i)), ((char*)":")))) {
            return kr_substr(tok, kr_plus(i, ((char*)"1")), kr_len(tok));
        }
        i = kr_plus(i, ((char*)"1"));
    }
    return ((char*)"");
}

char* cEscape(char* s) {
    char* sb = kr_sbnew();
    char* i = ((char*)"0");
    char* start = ((char*)"0");
    while (kr_truthy(kr_lt(i, kr_len(s)))) {
        char* c = kr_idx(s, kr_atoi(i));
        if (kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(c, ((char*)"\\"))) || kr_truthy(kr_eq(c, ((char*)"\""))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(c, ((char*)"\n"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(c, ((char*)"\\r"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(c, ((char*)"\t"))) ? kr_str("1") : kr_str("0")))) {
            if (kr_truthy(kr_gt(i, start))) {
                sb = kr_sbappend(sb, kr_substr(s, start, i));
            }
            if (kr_truthy(kr_eq(c, ((char*)"\\")))) {
                sb = kr_sbappend(sb, ((char*)"\\\\"));
            } else if (kr_truthy(kr_eq(c, ((char*)"\"")))) {
                sb = kr_sbappend(sb, ((char*)"\\\""));
            } else if (kr_truthy(kr_eq(c, ((char*)"\n")))) {
                sb = kr_sbappend(sb, ((char*)"\\n"));
            } else if (kr_truthy(kr_eq(c, ((char*)"\\r")))) {
                sb = kr_sbappend(sb, ((char*)"\\r"));
            } else if (kr_truthy(kr_eq(c, ((char*)"\t")))) {
                sb = kr_sbappend(sb, ((char*)"\\t"));
            }
            start = kr_plus(i, ((char*)"1"));
        }
        i = kr_plus(i, ((char*)"1"));
    }
    if (kr_truthy(kr_gt(i, start))) {
        sb = kr_sbappend(sb, kr_substr(s, start, i));
    }
    return kr_sbtostring(sb);
}

char* expandEscapes(char* s) {
    char* sb = kr_sbnew();
    char* i = ((char*)"0");
    char* start = ((char*)"0");
    while (kr_truthy(kr_lt(i, kr_len(s)))) {
        if (kr_truthy(kr_eq(kr_idx(s, kr_atoi(i)), ((char*)"\\")))) {
            if (kr_truthy(kr_gt(i, start))) {
                sb = kr_sbappend(sb, kr_substr(s, start, i));
            }
            i = kr_plus(i, ((char*)"1"));
            if (kr_truthy(kr_lt(i, kr_len(s)))) {
                char* c = kr_idx(s, kr_atoi(i));
                if (kr_truthy(kr_eq(c, ((char*)"n")))) {
                    sb = kr_sbappend(sb, ((char*)"\n"));
                } else if (kr_truthy(kr_eq(c, ((char*)"t")))) {
                    sb = kr_sbappend(sb, ((char*)"\t"));
                } else if (kr_truthy(kr_eq(c, ((char*)"r")))) {
                    sb = kr_sbappend(sb, ((char*)"\\r"));
                } else if (kr_truthy(kr_eq(c, ((char*)"\\")))) {
                    sb = kr_sbappend(sb, ((char*)"\\"));
                } else if (kr_truthy(kr_eq(c, ((char*)"\"")))) {
                    sb = kr_sbappend(sb, ((char*)"\""));
                } else {
                    sb = kr_sbappend(sb, ((char*)"\\"));
                    sb = kr_sbappend(sb, c);
                }
            }
            start = kr_plus(i, ((char*)"1"));
        }
        i = kr_plus(i, ((char*)"1"));
    }
    if (kr_truthy(kr_gt(i, start))) {
        sb = kr_sbappend(sb, kr_substr(s, start, i));
    }
    return kr_sbtostring(sb);
}

char* scanFunctions(char* tokens, char* ntoks) {
    char* table = kr_sbnew();
    char* i = ((char*)"0");
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* tok = ((char*(*)(char*,char*))tokAt)(tokens, i);
        if (kr_truthy(kr_eq(tok, ((char*)"KW:jxt")))) {
            i = ((char*(*)(char*,char*))skipBlock)(tokens, kr_plus(i, ((char*)"1")));
        } else if (kr_truthy(kr_eq(tok, ((char*)"KW:func")))) {
            char* nameTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1")));
            char* fname = ((char*(*)(char*))tokVal)(nameTok);
            char* j = kr_plus(i, ((char*)"3"));
            char* params = ((char*)"");
            char* pc = ((char*)"0");
            while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, j), ((char*)"RPAREN")))) {
                char* pt = ((char*(*)(char*,char*))tokAt)(tokens, j);
                if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(pt), ((char*)"ID")))) {
                    if (kr_truthy(kr_gt(pc, ((char*)"0")))) {
                        params = kr_plus(kr_plus(params, ((char*)",")), ((char*(*)(char*))tokVal)(pt));
                    } else {
                        params = ((char*(*)(char*))tokVal)(pt);
                    }
                    pc = kr_plus(pc, ((char*)"1"));
                    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(j, ((char*)"1"))), ((char*)"COLON")))) {
                        j = kr_plus(j, ((char*)"3"));
                        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, j), ((char*)"LBRACK")))) {
                            char* std = ((char*)"1");
                            j = kr_plus(j, ((char*)"1"));
                            while (kr_truthy(kr_gt(std, ((char*)"0")))) {
                                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, j), ((char*)"LBRACK")))) {
                                    std = kr_plus(std, ((char*)"1"));
                                }
                                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, j), ((char*)"RBRACK")))) {
                                    std = kr_sub(std, ((char*)"1"));
                                }
                                j = kr_plus(j, ((char*)"1"));
                            }
                        }
                        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, j), ((char*)"COMMA")))) {
                            j = kr_plus(j, ((char*)"1"));
                        }
                    } else {
                        j = kr_plus(j, ((char*)"1"));
                    }
                } else {
                    j = kr_plus(j, ((char*)"1"));
                }
            }
            char* bodyStart = kr_plus(j, ((char*)"1"));
            table = kr_sbappend(table, kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(fname, ((char*)"~")), pc), ((char*)"~")), params), ((char*)"~")), bodyStart), ((char*)"\n")));
        }
        i = kr_plus(i, ((char*)"1"));
    }
    return kr_sbtostring(table);
}

char* funcLookup(char* table, char* name) {
    char* i = ((char*)"0");
    char* tlen = kr_len(table);
    while (kr_truthy(kr_lt(i, tlen))) {
        char* nl = i;
        while (kr_truthy(kr_lt(nl, tlen))) {
            if (kr_truthy(kr_eq(kr_idx(table, kr_atoi(nl)), ((char*)"\n")))) {
                break;
            }
            nl = kr_plus(nl, ((char*)"1"));
        }
        char* line = kr_substr(table, i, nl);
        char* t1 = ((char*)"0");
        while (kr_truthy(kr_lt(t1, kr_len(line)))) {
            if (kr_truthy(kr_eq(kr_idx(line, kr_atoi(t1)), ((char*)"~")))) {
                break;
            }
            t1 = kr_plus(t1, ((char*)"1"));
        }
        char* fnom = kr_substr(line, ((char*)"0"), t1);
        if (kr_truthy(kr_eq(fnom, name))) {
            return kr_substr(line, kr_plus(t1, ((char*)"1")), kr_len(line));
        }
        i = kr_plus(nl, ((char*)"1"));
    }
    return ((char*)"");
}

char* funcParamCount(char* info) {
    char* i = ((char*)"0");
    while (kr_truthy(kr_lt(i, kr_len(info)))) {
        if (kr_truthy(kr_eq(kr_idx(info, kr_atoi(i)), ((char*)"~")))) {
            return kr_toint(kr_substr(info, ((char*)"0"), i));
        }
        i = kr_plus(i, ((char*)"1"));
    }
    return ((char*)"0");
}

char* funcParams(char* info) {
    char* i = ((char*)"0");
    while (kr_truthy(kr_lt(i, kr_len(info)))) {
        if (kr_truthy(kr_eq(kr_idx(info, kr_atoi(i)), ((char*)"~")))) {
            char* rest = kr_substr(info, kr_plus(i, ((char*)"1")), kr_len(info));
            char* j = ((char*)"0");
            while (kr_truthy(kr_lt(j, kr_len(rest)))) {
                if (kr_truthy(kr_eq(kr_idx(rest, kr_atoi(j)), ((char*)"~")))) {
                    return kr_substr(rest, ((char*)"0"), j);
                }
                j = kr_plus(j, ((char*)"1"));
            }
            return rest;
        }
        i = kr_plus(i, ((char*)"1"));
    }
    return ((char*)"");
}

char* funcStart(char* info) {
    char* i = kr_sub(kr_len(info), ((char*)"1"));
    while (kr_truthy(kr_gte(i, ((char*)"0")))) {
        if (kr_truthy(kr_eq(kr_idx(info, kr_atoi(i)), ((char*)"~")))) {
            return kr_toint(kr_substr(info, kr_plus(i, ((char*)"1")), kr_len(info)));
        }
        i = kr_sub(i, ((char*)"1"));
    }
    return ((char*)"0");
}

char* getNthParam(char* params, char* idx) {
    char* count = ((char*)"0");
    char* start = ((char*)"0");
    char* i = ((char*)"0");
    while (kr_truthy(kr_lt(i, kr_len(params)))) {
        if (kr_truthy(kr_eq(kr_idx(params, kr_atoi(i)), ((char*)",")))) {
            if (kr_truthy(kr_eq(count, idx))) {
                return kr_substr(params, start, i);
            }
            count = kr_plus(count, ((char*)"1"));
            start = kr_plus(i, ((char*)"1"));
        }
        i = kr_plus(i, ((char*)"1"));
    }
    if (kr_truthy(kr_eq(count, idx))) {
        return kr_substr(params, start, kr_len(params));
    }
    return ((char*)"");
}

char* findEntry(char* tokens, char* ntoks) {
    char* i = ((char*)"0");
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* tok = ((char*(*)(char*,char*))tokAt)(tokens, i);
        if (kr_truthy((kr_truthy(kr_eq(tok, ((char*)"KW:just"))) || kr_truthy(kr_eq(tok, ((char*)"KW:go"))) ? kr_str("1") : kr_str("0")))) {
            if (kr_truthy(kr_lt(kr_plus(i, ((char*)"2")), ntoks))) {
                char* next = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1")));
                if (kr_truthy(kr_eq(next, ((char*)"ID:run")))) {
                    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"2"))), ((char*)"LBRACE")))) {
                        return kr_plus(i, ((char*)"2"));
                    }
                }
            }
        }
        i = kr_plus(i, ((char*)"1"));
    }
    return kr_sub(((char*)"0"), ((char*)"1"));
}

char* skipBlock(char* tokens, char* pos) {
    char* depth = ((char*)"1");
    char* p = kr_plus(pos, ((char*)"1"));
    while (kr_truthy(kr_gt(depth, ((char*)"0")))) {
        char* t = ((char*(*)(char*,char*))tokAt)(tokens, p);
        if (kr_truthy(kr_eq(t, ((char*)"LBRACE")))) {
            depth = kr_plus(depth, ((char*)"1"));
        }
        if (kr_truthy(kr_eq(t, ((char*)"RBRACE")))) {
            depth = kr_sub(depth, ((char*)"1"));
        }
        p = kr_plus(p, ((char*)"1"));
    }
    return p;
}

char* indent(char* depth) {
    char* sb = kr_sbnew();
    char* i = ((char*)"0");
    while (kr_truthy(kr_lt(i, depth))) {
        sb = kr_sbappend(sb, ((char*)"    "));
        i = kr_plus(i, ((char*)"1"));
    }
    return kr_sbtostring(sb);
}

char* cIdent(char* name) {
    if (kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(name, ((char*)"int"))) || kr_truthy(kr_eq(name, ((char*)"char"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"void"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"return"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"if"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"else"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"while"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"break"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"for"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"do"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"switch"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"case"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"default"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"struct"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"const"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"static"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"long"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"short"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"double"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"float"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"auto"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"register"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"extern"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"typedef"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"union"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"enum"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"sizeof"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"goto"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"volatile"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"signed"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"unsigned"))) ? kr_str("1") : kr_str("0")))) {
        return kr_plus(((char*)"k_"), name);
    }
    if (kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(name, ((char*)"abs"))) || kr_truthy(kr_eq(name, ((char*)"exit"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"rand"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"free"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"malloc"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"printf"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"strlen"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"strcmp"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"strcpy"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"time"))) ? kr_str("1") : kr_str("0")))) {
        return kr_plus(((char*)"k_"), name);
    }
    if (kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(name, ((char*)"double"))) || kr_truthy(kr_eq(name, ((char*)"float"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"int"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"bool"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"string"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"list"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"map"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"any"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"void"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, ((char*)"num"))) ? kr_str("1") : kr_str("0")))) {
        return kr_plus(((char*)"k_"), name);
    }
    return name;
}

char* compileExpr(char* tokens, char* pos, char* ntoks) {
    return ((char*(*)(char*,char*,char*))compileTernary)(tokens, pos, ntoks);
}

char* compileTernary(char* tokens, char* pos, char* ntoks) {
    char* pair = ((char*(*)(char*,char*,char*))compileOr)(tokens, pos, ntoks);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"QUESTION")))) {
        char* tp = ((char*(*)(char*,char*,char*))compileExpr)(tokens, kr_plus(p, ((char*)"1")), ntoks);
        char* tcode = ((char*(*)(char*))pairVal)(tp);
        p = ((char*(*)(char*))pairPos)(tp);
        p = kr_plus(p, ((char*)"1"));
        char* fp = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
        char* fcode = ((char*(*)(char*))pairVal)(fp);
        p = ((char*(*)(char*))pairPos)(fp);
        code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"(kr_truthy("), code), ((char*)") ? ")), tcode), ((char*)" : ")), fcode), ((char*)")"));
    }
    return kr_plus(kr_plus(code, ((char*)",")), p);
}

char* compileOr(char* tokens, char* pos, char* ntoks) {
    char* pair = ((char*(*)(char*,char*,char*))compileAnd)(tokens, pos, ntoks);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"OR")))) {
        char* rp = ((char*(*)(char*,char*,char*))compileAnd)(tokens, kr_plus(p, ((char*)"1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        code = kr_plus(kr_plus(kr_plus(kr_plus(((char*)"(kr_truthy("), code), ((char*)") || kr_truthy(")), rcode), ((char*)") ? kr_str(\"1\") : kr_str(\"0\"))"));
    }
    return kr_plus(kr_plus(code, ((char*)",")), p);
}

char* compileAnd(char* tokens, char* pos, char* ntoks) {
    char* pair = ((char*(*)(char*,char*,char*))compileEquality)(tokens, pos, ntoks);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"AND")))) {
        char* rp = ((char*(*)(char*,char*,char*))compileEquality)(tokens, kr_plus(p, ((char*)"1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        code = kr_plus(kr_plus(kr_plus(kr_plus(((char*)"(kr_truthy("), code), ((char*)") && kr_truthy(")), rcode), ((char*)") ? kr_str(\"1\") : kr_str(\"0\"))"));
    }
    return kr_plus(kr_plus(code, ((char*)",")), p);
}

char* compileEquality(char* tokens, char* pos, char* ntoks) {
    char* pair = ((char*(*)(char*,char*,char*))compileRelational)(tokens, pos, ntoks);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"EQ"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"NEQ"))) ? kr_str("1") : kr_str("0")))) {
        char* op = ((char*(*)(char*,char*))tokAt)(tokens, p);
        char* rp = ((char*(*)(char*,char*,char*))compileRelational)(tokens, kr_plus(p, ((char*)"1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        if (kr_truthy(kr_eq(op, ((char*)"EQ")))) {
            code = kr_plus(kr_plus(kr_plus(kr_plus(((char*)"kr_eq("), code), ((char*)", ")), rcode), ((char*)")"));
        } else {
            code = kr_plus(kr_plus(kr_plus(kr_plus(((char*)"kr_neq("), code), ((char*)", ")), rcode), ((char*)")"));
        }
    }
    return kr_plus(kr_plus(code, ((char*)",")), p);
}

char* compileRelational(char* tokens, char* pos, char* ntoks) {
    char* pair = ((char*(*)(char*,char*,char*))compileAdditive)(tokens, pos, ntoks);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"LT"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"GT"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"LTE"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"GTE"))) ? kr_str("1") : kr_str("0")))) {
        char* op = ((char*(*)(char*,char*))tokAt)(tokens, p);
        char* rp = ((char*(*)(char*,char*,char*))compileAdditive)(tokens, kr_plus(p, ((char*)"1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        if (kr_truthy(kr_eq(op, ((char*)"LT")))) {
            code = kr_plus(kr_plus(kr_plus(kr_plus(((char*)"kr_lt("), code), ((char*)", ")), rcode), ((char*)")"));
        } else if (kr_truthy(kr_eq(op, ((char*)"GT")))) {
            code = kr_plus(kr_plus(kr_plus(kr_plus(((char*)"kr_gt("), code), ((char*)", ")), rcode), ((char*)")"));
        } else if (kr_truthy(kr_eq(op, ((char*)"LTE")))) {
            code = kr_plus(kr_plus(kr_plus(kr_plus(((char*)"kr_lte("), code), ((char*)", ")), rcode), ((char*)")"));
        } else {
            code = kr_plus(kr_plus(kr_plus(kr_plus(((char*)"kr_gte("), code), ((char*)", ")), rcode), ((char*)")"));
        }
    }
    return kr_plus(kr_plus(code, ((char*)",")), p);
}

char* compileAdditive(char* tokens, char* pos, char* ntoks) {
    char* pair = ((char*(*)(char*,char*,char*))compileMult)(tokens, pos, ntoks);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"PLUS"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"MINUS"))) ? kr_str("1") : kr_str("0")))) {
        char* op = ((char*(*)(char*,char*))tokAt)(tokens, p);
        char* rp = ((char*(*)(char*,char*,char*))compileMult)(tokens, kr_plus(p, ((char*)"1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        if (kr_truthy(kr_eq(op, ((char*)"PLUS")))) {
            code = kr_plus(kr_plus(kr_plus(kr_plus(((char*)"kr_plus("), code), ((char*)", ")), rcode), ((char*)")"));
        } else {
            code = kr_plus(kr_plus(kr_plus(kr_plus(((char*)"kr_sub("), code), ((char*)", ")), rcode), ((char*)")"));
        }
    }
    return kr_plus(kr_plus(code, ((char*)",")), p);
}

char* compileMult(char* tokens, char* pos, char* ntoks) {
    char* pair = ((char*(*)(char*,char*,char*))compilePow)(tokens, pos, ntoks);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy((kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"STAR"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SLASH"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"MOD"))) ? kr_str("1") : kr_str("0")))) {
        char* op = ((char*(*)(char*,char*))tokAt)(tokens, p);
        char* rp = ((char*(*)(char*,char*,char*))compilePow)(tokens, kr_plus(p, ((char*)"1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        if (kr_truthy(kr_eq(op, ((char*)"STAR")))) {
            code = kr_plus(kr_plus(kr_plus(kr_plus(((char*)"kr_mul("), code), ((char*)", ")), rcode), ((char*)")"));
        } else if (kr_truthy(kr_eq(op, ((char*)"SLASH")))) {
            code = kr_plus(kr_plus(kr_plus(kr_plus(((char*)"kr_div("), code), ((char*)", ")), rcode), ((char*)")"));
        } else {
            code = kr_plus(kr_plus(kr_plus(kr_plus(((char*)"kr_mod("), code), ((char*)", ")), rcode), ((char*)")"));
        }
    }
    return kr_plus(kr_plus(code, ((char*)",")), p);
}

char* compilePow(char* tokens, char* pos, char* ntoks) {
    char* pair = ((char*(*)(char*,char*,char*))compileUnary)(tokens, pos, ntoks);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"STARSTAR")))) {
        char* rp = ((char*(*)(char*,char*,char*))compilePow)(tokens, kr_plus(p, ((char*)"1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        code = kr_plus(kr_plus(kr_plus(kr_plus(((char*)"kr_pow("), code), ((char*)", ")), rcode), ((char*)")"));
    }
    return kr_plus(kr_plus(code, ((char*)",")), p);
}

char* compileUnary(char* tokens, char* pos, char* ntoks) {
    char* tok = ((char*(*)(char*,char*))tokAt)(tokens, pos);
    if (kr_truthy(kr_eq(tok, ((char*)"MINUS")))) {
        char* rp = ((char*(*)(char*,char*,char*))compileUnary)(tokens, kr_plus(pos, ((char*)"1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        char* p = ((char*(*)(char*))pairPos)(rp);
        return kr_plus(kr_plus(kr_plus(((char*)"kr_neg("), rcode), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"BANG")))) {
        char* rp = ((char*(*)(char*,char*,char*))compileUnary)(tokens, kr_plus(pos, ((char*)"1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        char* p = ((char*(*)(char*))pairPos)(rp);
        return kr_plus(kr_plus(kr_plus(((char*)"kr_not("), rcode), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"PLUSPLUS")))) {
        char* rp = ((char*(*)(char*,char*,char*))compilePostfix)(tokens, kr_plus(pos, ((char*)"1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        char* p = ((char*(*)(char*))pairPos)(rp);
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"("), rcode), ((char*)" = kr_plus(")), rcode), ((char*)", kr_str(\"1\"))),")), p);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"MINUSMINUS")))) {
        char* rp = ((char*(*)(char*,char*,char*))compilePostfix)(tokens, kr_plus(pos, ((char*)"1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        char* p = ((char*(*)(char*))pairPos)(rp);
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"("), rcode), ((char*)" = kr_sub(")), rcode), ((char*)", kr_str(\"1\"))),")), p);
    }
    return ((char*(*)(char*,char*,char*))compilePostfix)(tokens, pos, ntoks);
}

char* compilePostfix(char* tokens, char* pos, char* ntoks) {
    char* pair = ((char*(*)(char*,char*,char*))compilePrimary)(tokens, pos, ntoks);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"LBRACK"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"DOT"))) ? kr_str("1") : kr_str("0")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"LBRACK")))) {
            char* ip = ((char*(*)(char*,char*,char*))compileExpr)(tokens, kr_plus(p, ((char*)"1")), ntoks);
            char* icode = ((char*(*)(char*))pairVal)(ip);
            p = ((char*(*)(char*))pairPos)(ip);
            p = kr_plus(p, ((char*)"1"));
            code = kr_plus(kr_plus(kr_plus(kr_plus(((char*)"kr_idx("), code), ((char*)", kr_atoi(")), icode), ((char*)"))"));
        } else {
            char* field = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, ((char*)"1"))));
            p = kr_plus(p, ((char*)"2"));
            code = kr_plus(kr_plus(kr_plus(kr_plus(((char*)"kr_getfield("), code), ((char*)", \"")), field), ((char*)"\")"));
        }
    }
    return kr_plus(kr_plus(code, ((char*)",")), p);
}

char* compilePrimary(char* tokens, char* pos, char* ntoks) {
    char* tok = ((char*(*)(char*,char*))tokAt)(tokens, pos);
    char* tt = ((char*(*)(char*))tokType)(tok);
    char* tv = ((char*(*)(char*))tokVal)(tok);
    if (kr_truthy(kr_eq(tt, ((char*)"INTERP")))) {
        return kr_plus(kr_plus(((char*(*)(char*))compileInterp)(tv), ((char*)",")), kr_plus(pos, ((char*)"1")));
    }
    if (kr_truthy(kr_eq(tt, ((char*)"INT")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"((char*)\""), tv), ((char*)"\"),")), kr_plus(pos, ((char*)"1")));
    }
    if (kr_truthy(kr_eq(tt, ((char*)"STR")))) {
        char* expanded = ((char*(*)(char*))expandEscapes)(tv);
        char* escaped = ((char*(*)(char*))cEscape)(expanded);
        return kr_plus(kr_plus(kr_plus(((char*)"((char*)\""), escaped), ((char*)"\"),")), kr_plus(pos, ((char*)"1")));
    }
    if (kr_truthy(kr_eq(tt, ((char*)"KW")))) {
        if (kr_truthy(kr_eq(tv, ((char*)"true")))) {
            return kr_plus(((char*)"((char*)\"true\"),"), kr_plus(pos, ((char*)"1")));
        }
        if (kr_truthy(kr_eq(tv, ((char*)"false")))) {
            return kr_plus(((char*)"((char*)\"false\"),"), kr_plus(pos, ((char*)"1")));
        }
        if (kr_truthy(kr_eq(tv, ((char*)"null")))) {
            return kr_plus(((char*)"((char*)0),"), kr_plus(pos, ((char*)"1")));
        }
    }
    if (kr_truthy(kr_eq(tok, ((char*)"LPAREN")))) {
        char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, kr_plus(pos, ((char*)"1")), ntoks);
        char* ecode = ((char*(*)(char*))pairVal)(ep);
        char* p = ((char*(*)(char*))pairPos)(ep);
        return kr_plus(kr_plus(ecode, ((char*)",")), kr_plus(p, ((char*)"1")));
    }
    if (kr_truthy(kr_eq(tok, ((char*)"LBRACK")))) {
        return ((char*(*)(char*,char*,char*))compileListLiteral)(tokens, pos, ntoks);
    }
    if (kr_truthy((kr_truthy(kr_eq(tok, ((char*)"KW:func"))) || kr_truthy(kr_eq(tok, ((char*)"KW:fn"))) ? kr_str("1") : kr_str("0")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1"))), ((char*)"LPAREN")))) {
            return ((char*(*)(char*,char*,char*))compileLambda)(tokens, pos, ntoks);
        }
        return kr_plus(kr_plus(((char*(*)(char*))cIdent)(tv), ((char*)",")), kr_plus(pos, ((char*)"1")));
    }
    if (kr_truthy(kr_eq(tt, ((char*)"ID")))) {
        char* name = tv;
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1"))), ((char*)"LPAREN")))) {
            return ((char*(*)(char*,char*,char*))compileCall)(tokens, pos, ntoks);
        }
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1"))), ((char*)"LBRACE")))) {
            char* firstChar = kr_idx(name, kr_atoi(((char*)"0")));
            if (kr_truthy((kr_truthy(kr_gte(firstChar, ((char*)"A"))) && kr_truthy(kr_lte(firstChar, ((char*)"Z"))) ? kr_str("1") : kr_str("0")))) {
                char* inner1c = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"2")));
                char* inner2c = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"3")));
                if (kr_truthy(kr_eq(kr_startswith(inner1c, ((char*)"ID:")), ((char*)"1")))) {
                    if (kr_truthy(kr_eq(inner2c, ((char*)"COLON")))) {
                        return ((char*(*)(char*,char*,char*))compileStructLiteral)(tokens, pos, ntoks);
                    }
                }
            }
        }
        return kr_plus(kr_plus(((char*(*)(char*))cIdent)(name), ((char*)",")), kr_plus(pos, ((char*)"1")));
    }
    return kr_plus(((char*)"((char*)\"\"),"), kr_plus(pos, ((char*)"1")));
}

char* compileWin32IntArgs(char* name) {
    if (kr_truthy(kr_eq(name, ((char*)"GetStdHandle")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"SetConsoleOutputCP")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"SetConsoleMode")))) {
        return ((char*)"0,1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetConsoleMode")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetConsoleScreenBufferInfo")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"Sleep")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetTickCount")))) {
        return ((char*)"");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetTickCount64")))) {
        return ((char*)"");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetSystemMetrics")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"ExitProcess")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"WriteFile")))) {
        return ((char*)"0,2,4");
    }
    if (kr_truthy(kr_eq(name, ((char*)"ReadFile")))) {
        return ((char*)"0,2,4");
    }
    if (kr_truthy(kr_eq(name, ((char*)"CloseHandle")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"CreateToolhelp32Snapshot")))) {
        return ((char*)"0,1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"Process32First")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"Process32Next")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetLogicalDrives")))) {
        return ((char*)"");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetFileAttributesA")))) {
        return ((char*)"");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetFileSizeEx")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"FreeLibrary")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"FindFirstFileA")))) {
        return ((char*)"");
    }
    if (kr_truthy(kr_eq(name, ((char*)"FindNextFileA")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"FindClose")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"CreateDirectoryA")))) {
        return ((char*)"");
    }
    if (kr_truthy(kr_eq(name, ((char*)"DeleteFileA")))) {
        return ((char*)"");
    }
    if (kr_truthy(kr_eq(name, ((char*)"RemoveDirectoryA")))) {
        return ((char*)"");
    }
    if (kr_truthy(kr_eq(name, ((char*)"MoveFileA")))) {
        return ((char*)"");
    }
    if (kr_truthy(kr_eq(name, ((char*)"CopyFileA")))) {
        return ((char*)"2");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetCurrentDirectoryA")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"SetCurrentDirectoryA")))) {
        return ((char*)"");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetTempPathA")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"CreatePipe")))) {
        return ((char*)"3");
    }
    if (kr_truthy(kr_eq(name, ((char*)"CreateProcessA")))) {
        return ((char*)"4,5");
    }
    if (kr_truthy(kr_eq(name, ((char*)"PeekNamedPipe")))) {
        return ((char*)"0,2");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetExitCodeProcess")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"SetHandleInformation")))) {
        return ((char*)"0,1,2");
    }
    if (kr_truthy(kr_eq(name, ((char*)"RegOpenKeyExA")))) {
        return ((char*)"0,2,3");
    }
    if (kr_truthy(kr_eq(name, ((char*)"RegQueryValueExA")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"RegEnumKeyExA")))) {
        return ((char*)"0,1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"RegCloseKey")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetUserNameA")))) {
        return ((char*)"");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GlobalMemoryStatusEx")))) {
        return ((char*)"");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetSystemPowerStatus")))) {
        return ((char*)"");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetDiskFreeSpaceExA")))) {
        return ((char*)"");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetCurrentProcessId")))) {
        return ((char*)"");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetCurrentThreadId")))) {
        return ((char*)"");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetLastError")))) {
        return ((char*)"");
    }
    if (kr_truthy(kr_eq(name, ((char*)"SetLastError")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"WaitForSingleObject")))) {
        return ((char*)"0,1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"TerminateProcess")))) {
        return ((char*)"0,1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"OpenProcess")))) {
        return ((char*)"0,1,2");
    }
    if (kr_truthy(kr_eq(name, ((char*)"CreateFileA")))) {
        return ((char*)"1,2,3,4,5,6");
    }
    if (kr_truthy(kr_eq(name, ((char*)"VirtualAlloc")))) {
        return ((char*)"0,1,2,3");
    }
    if (kr_truthy(kr_eq(name, ((char*)"VirtualFree")))) {
        return ((char*)"0,1,2");
    }
    if (kr_truthy(kr_eq(name, ((char*)"HeapAlloc")))) {
        return ((char*)"0,1,2");
    }
    if (kr_truthy(kr_eq(name, ((char*)"HeapReAlloc")))) {
        return ((char*)"0,1,3");
    }
    if (kr_truthy(kr_eq(name, ((char*)"HeapFree")))) {
        return ((char*)"0,1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetEnvironmentVariableA")))) {
        return ((char*)"2");
    }
    if (kr_truthy(kr_eq(name, ((char*)"CreateFileMappingA")))) {
        return ((char*)"0,1,2,3,4,5");
    }
    if (kr_truthy(kr_eq(name, ((char*)"MapViewOfFile")))) {
        return ((char*)"0,1,2,3,4");
    }
    if (kr_truthy(kr_eq(name, ((char*)"MessageBoxA")))) {
        return ((char*)"0,3");
    }
    if (kr_truthy(kr_eq(name, ((char*)"ShowWindow")))) {
        return ((char*)"0,1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"SetTimer")))) {
        return ((char*)"0,1,2");
    }
    if (kr_truthy(kr_eq(name, ((char*)"KillTimer")))) {
        return ((char*)"0,1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"SetForegroundWindow")))) {
        return ((char*)"0");
    }
    if (kr_truthy(kr_eq(name, ((char*)"ShellExecuteA")))) {
        return ((char*)"0,5");
    }
    return ((char*)"");
}

char* compileWin32Return64(char* name) {
    if (kr_truthy(kr_eq(name, ((char*)"GetStdHandle")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetProcessHeap")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"CreateToolhelp32Snapshot")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"CreateFileA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"FindFirstFileA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"CreateFileMappingA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"MapViewOfFile")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetForegroundWindow")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"VirtualAlloc")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"HeapAlloc")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"HeapReAlloc")))) {
        return ((char*)"1");
    }
    return ((char*)"");
}

char* compileWin32IntReturn(char* name) {
    if (kr_truthy(kr_eq(name, ((char*)"GetStdHandle")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetTickCount")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetTickCount64")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetSystemMetrics")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"WriteFile")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"ReadFile")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"CloseHandle")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"CreateToolhelp32Snapshot")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"Process32First")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"Process32Next")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetLogicalDrives")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetFileAttributesA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetFileSizeEx")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"FindFirstFileA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"FindNextFileA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"FindClose")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"CreateDirectoryA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"DeleteFileA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"RemoveDirectoryA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"MoveFileA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"CopyFileA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetCurrentDirectoryA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"SetCurrentDirectoryA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetTempPathA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"CreateFileA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"CreatePipe")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"CreateProcessA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"PeekNamedPipe")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetExitCodeProcess")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"SetHandleInformation")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"RegOpenKeyExA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"RegQueryValueExA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"RegEnumKeyExA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"RegCloseKey")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetUserNameA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GlobalMemoryStatusEx")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetSystemPowerStatus")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetDiskFreeSpaceExA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetCurrentProcessId")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetCurrentThreadId")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetLastError")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"WaitForSingleObject")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"TerminateProcess")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetProcessHeap")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"SetConsoleMode")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetConsoleMode")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"SetConsoleOutputCP")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetConsoleScreenBufferInfo")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"VirtualFree")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"HeapFree")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"FreeLibrary")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"MessageBoxA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"ShowWindow")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"SetTimer")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"KillTimer")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"GetForegroundWindow")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"SetForegroundWindow")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"CreateFileMappingA")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"UnmapViewOfFile")))) {
        return ((char*)"1");
    }
    if (kr_truthy(kr_eq(name, ((char*)"ShellExecuteA")))) {
        return ((char*)"1");
    }
    return ((char*)"");
}

char* compileCsvHas(char* csv, char* idx) {
    if (kr_truthy(kr_eq(kr_len(csv), ((char*)"0")))) {
        return ((char*)"0");
    }
    char* target = kr_plus(((char*)""), idx);
    char* i = ((char*)"0");
    char* cur = ((char*)"");
    while (kr_truthy(kr_lte(i, kr_len(csv)))) {
        char* ch = ((char*)"");
        if (kr_truthy(kr_lt(i, kr_len(csv)))) {
            ch = kr_substr(csv, i, kr_plus(i, ((char*)"1")));
        }
        if (kr_truthy((kr_truthy(kr_eq(i, kr_len(csv))) || kr_truthy(kr_eq(ch, ((char*)","))) ? kr_str("1") : kr_str("0")))) {
            if (kr_truthy(kr_eq(cur, target))) {
                return ((char*)"1");
            }
            cur = ((char*)"");
        } else {
            cur = kr_plus(cur, ch);
        }
        i = kr_plus(i, ((char*)"1"));
    }
    return ((char*)"0");
}

char* compileCall(char* tokens, char* pos, char* ntoks) {
    char* fname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* p = kr_plus(pos, ((char*)"2"));
    char* args = ((char*)"");
    char* argList = ((char*)"");
    char* argc = ((char*)"0");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RPAREN")))) {
        if (kr_truthy(kr_gt(argc, ((char*)"0")))) {
            p = kr_plus(p, ((char*)"1"));
        }
        char* ap = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
        char* acode = ((char*(*)(char*))pairVal)(ap);
        p = ((char*(*)(char*))pairPos)(ap);
        if (kr_truthy(kr_gt(argc, ((char*)"0")))) {
            args = kr_plus(kr_plus(args, ((char*)", ")), acode);
            argList = kr_plus(kr_plus(argList, ((char*)"\n")), acode);
        } else {
            args = acode;
            argList = acode;
        }
        argc = kr_plus(argc, ((char*)"1"));
    }
    p = kr_plus(p, ((char*)"1"));
    if (kr_truthy((kr_truthy(kr_eq(fname, ((char*)"kp"))) || kr_truthy(kr_eq(fname, ((char*)"print"))) ? kr_str("1") : kr_str("0")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_print("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"len")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_len("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"substring")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_substr("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"toInt")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_toint("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"split")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_split("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"startsWith")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_startswith("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"exec")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_exec("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"shellRun")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_shellrun("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"deleteFile")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_deletefile("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"structNew")))) {
        char* snArg = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"2")));
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(snArg), ((char*)"STR")))) {
            return kr_plus(kr_plus(kr_plus(((char*)"structnew_"), ((char*(*)(char*))tokVal)(snArg)), ((char*)"(),")), p);
        } else {
            return kr_plus(((char*)"structnew_unknown(),"), p);
        }
    }
    if (kr_truthy(kr_eq(fname, ((char*)"structGet")))) {
        char* sgType = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"4")));
        char* sgField = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"6")));
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(sgType), ((char*)"STR")))) {
            char* sgPtr = kr_split(args, ((char*)"0"));
            return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"structget_"), ((char*(*)(char*))tokVal)(sgType)), ((char*)"(")), sgPtr), ((char*)", kr_str(\"")), ((char*(*)(char*))tokVal)(sgField)), ((char*)"\")),")), p);
        } else {
            return kr_plus(((char*)"kr_str(\"\"),"), p);
        }
    }
    if (kr_truthy(kr_eq(fname, ((char*)"structSet")))) {
        char* ssType = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"4")));
        char* ssField = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"6")));
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(ssType), ((char*)"STR")))) {
            char* ssPtr = kr_split(args, ((char*)"0"));
            char* ssVal = kr_split(args, ((char*)"3"));
            return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"structset_"), ((char*(*)(char*))tokVal)(ssType)), ((char*)"(")), ssPtr), ((char*)", kr_str(\"")), ((char*(*)(char*))tokVal)(ssField)), ((char*)"\"), ")), ssVal), ((char*)"),")), p);
        } else {
            return kr_plus(((char*)"_K_EMPTY,"), p);
        }
    }
    if (kr_truthy(kr_eq(fname, ((char*)"sizeOf")))) {
        char* soArg = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"2")));
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(soArg), ((char*)"STR")))) {
            return kr_plus(kr_plus(kr_plus(((char*)"structsizeof_"), ((char*(*)(char*))tokVal)(soArg)), ((char*)"(),")), p);
        } else {
            return kr_plus(((char*)"kr_str(\"0\"),"), p);
        }
    }
    if (kr_truthy(kr_eq(fname, ((char*)"structAddr")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"((char*)("), args), ((char*)")),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"arenaMark")))) {
        return kr_plus(((char*)"_alloc_mark(),"), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"arenaReset")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"_alloc_reset("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"intSlotStore")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"intSlotStore("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"intSlotLoad")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"intSlotLoad("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"readFile")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_readfile("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"arg")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_arg("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"argCount")))) {
        return kr_plus(((char*)"kr_argcount(),"), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"getLine")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_getline("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"lineCount")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_linecount("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"count")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_count("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"envNew")))) {
        return kr_plus(((char*)"kr_envnew(),"), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"envSet")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_envset("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"envGet")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_envget("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"makeResult")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_makeresult("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"getResultTag")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_getresulttag("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"getResultVal")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_getresultval("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"getResultEnv")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_getresultenv("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"getResultPos")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_getresultpos("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"isTruthy")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_istruthy("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"sbNew")))) {
        return kr_plus(((char*)"kr_sbnew(),"), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"sbAppend")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_sbappend("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"sbToString")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_sbtostring("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"writeFile")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_writefile("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"writeBytes")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_writebytes("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"input")))) {
        return kr_plus(((char*)"kr_input(),"), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"indexOf")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_indexof("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"replace")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_replace("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"charAt")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_charat("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"trim")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_trim("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"toLower")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_tolower("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"toUpper")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_toupper("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"contains")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_contains("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"endsWith")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_endswith("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"abs")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_abs("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"min")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_min("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"max")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_max("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"exit")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_exit("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"type")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_type("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"append")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_append("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"join")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_join("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"reverse")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_reverse("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"sort")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_sort("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"keys")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_keys("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"values")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_values("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"hasKey")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_haskey("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"remove")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_remove("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"repeat")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_repeat("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"format")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_format("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"parseInt")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_parseint("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"toStr")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_tostr("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"range")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_range("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"pow")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_pow("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"sqrt")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_sqrt("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"sign")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_sign("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"clamp")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_clamp("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"padLeft")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_padleft("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"padRight")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_padright("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"charCode")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_charcode("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"fromCharCode")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_fromcharcode("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"slice")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_slice("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"length")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_length("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"unique")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_unique("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"printErr")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_printerr("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"readLine")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_readline("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"assert")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_assert("), args), ((char*)", \"assertion failed\"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"splitBy")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_splitby("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"listIndexOf")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_listindexof("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"insertAt")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_insertat("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"removeAt")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_removeat("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"replaceAt")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_replaceat("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"fill")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_fill("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"zip")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_zip("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"every")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_every("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"some")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_some("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"countOf")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_countof("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"sumList")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_sumlist("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"maxList")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_maxlist("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"minList")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_minlist("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"hex")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_hex("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bin")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_bin("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"strReverse")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_strreverse("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"words")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_words("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"lines")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_lines("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"first")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_first("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"last")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_last("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"head")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_head("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"tail")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_tail("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"lstrip")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_lstrip("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"rstrip")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_rstrip("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"center")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_center("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"isAlpha")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_isalpha("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"isDigit")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_isdigit("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"isSpace")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_isspace("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"random")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_random("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"timestamp")))) {
        return kr_plus(((char*)"kr_timestamp(),"), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"environ")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_environ("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"floor")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_floor("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"ceil")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_ceil("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"round")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_round("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"throw")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_throw("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"fadd")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_fadd("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"fsub")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_fsub("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"fmul")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_fmul("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"fdiv")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_fdiv("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"flt")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_flt("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"fgt")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_fgt("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"feq")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_feq("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"fsqrt")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_fsqrt("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"ffloor")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_ffloor("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"fceil")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_fceil("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"fround")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_fround("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"fformat")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_fformat("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"toFloat")))) {
        return kr_plus(kr_plus(args, ((char*)",")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bitAnd")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_bitand("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bitOr")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_bitor("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bitXor")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_bitxor("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bitNot")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_bitnot("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bitShl")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_bitshl("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bitShr")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_bitshr("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"toLong")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_tolong("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"div64")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_div64("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"mod64")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_mod64("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"mul64")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_mul64("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"add64")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_add64("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"eqIgnoreCase")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_eqignorecase("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"handleValid")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_handlevalid("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bufNew")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"({int _bn=atoi("), args), ((char*)");char* _bp=_alloc(_bn);memset(_bp,0,_bn);_bp;}),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bufStr")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_str("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bufGetDword")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_bufgetdword("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bufSetDword")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_bufsetdword("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bufGetWord")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_bufgetword("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bufGetQword")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_bufgetqword("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bufGetDwordAt")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_bufgetdwordat("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bufGetQwordAt")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_bufgetqwordat("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bufSetQwordAt")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_bufsetqwordat("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bufGetWordAt")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_bufgetwordat("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bufSetWordAt")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_bufsetwordat("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bufSetByte")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_bufsetbyte("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bufGetByte")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_bufgetbyte("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"bufSetDwordAt")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_bufsetdwordat("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"handleOut")))) {
        return kr_plus(((char*)"((char*)_alloc(sizeof(void*))),"), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"handleGet")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_handleget("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"handleInt")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_handleint("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"toHandle")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"((char*)(intptr_t)atoll("), args), ((char*)")),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"ptrDeref")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_ptrderef("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"ptrIndex")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_ptrindex("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"callPtr")))) {
        if (kr_truthy(kr_eq(argc, ((char*)"2")))) {
            return kr_plus(kr_plus(kr_plus(((char*)"kr_callptr1("), args), ((char*)"),")), p);
        }
        if (kr_truthy(kr_eq(argc, ((char*)"3")))) {
            return kr_plus(kr_plus(kr_plus(((char*)"kr_callptr2("), args), ((char*)"),")), p);
        }
        if (kr_truthy(kr_eq(argc, ((char*)"4")))) {
            return kr_plus(kr_plus(kr_plus(((char*)"kr_callptr3("), args), ((char*)"),")), p);
        }
        if (kr_truthy(kr_eq(argc, ((char*)"5")))) {
            return kr_plus(kr_plus(kr_plus(((char*)"kr_callptr4("), args), ((char*)"),")), p);
        }
    }
    if (kr_truthy(kr_eq(fname, ((char*)"mapGet")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_mapget("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"mapSet")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_mapset("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"mapDel")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_mapdel("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"sprintf")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_sprintf("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"listMap")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_listmap("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"listFilter")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_listfilter("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"strSplit")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_strsplit("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"structNew")))) {
        return kr_plus(((char*)"kr_structnew(),"), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"getField")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_getfield("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"setField")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_setfield("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"hasField")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_hasfield("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"structFields")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"kr_structfields("), args), ((char*)"),")), p);
    }
    if (kr_truthy(kr_eq(fname, ((char*)"funcptr")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"((char*)"), ((char*(*)(char*))cIdent)(args)), ((char*)"),")), p);
    }
    char* castArgs = ((char*)"char*");
    char* ci = ((char*)"1");
    while (kr_truthy(kr_lt(ci, argc))) {
        castArgs = kr_plus(castArgs, ((char*)",char*"));
        ci = kr_plus(ci, ((char*)"1"));
    }
    if (kr_truthy(kr_eq(argc, ((char*)"0")))) {
        castArgs = ((char*)"void");
    }
    char* intArgsCsv = ((char*(*)(char*))compileWin32IntArgs)(fname);
    char* intRet = ((char*(*)(char*))compileWin32IntReturn)(fname);
    if (kr_truthy((kr_truthy(kr_gt(kr_len(intArgsCsv), ((char*)"0"))) || kr_truthy(kr_eq(intRet, ((char*)"1"))) ? kr_str("1") : kr_str("0")))) {
        char* mCast = ((char*)"");
        char* mArgs = ((char*)"");
        char* mi = ((char*)"0");
        while (kr_truthy(kr_lt(mi, argc))) {
            char* acode = kr_getline(argList, mi);
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))compileCsvHas)(intArgsCsv, mi), ((char*)"1")))) {
                if (kr_truthy(kr_eq(mi, ((char*)"0")))) {
                    mCast = ((char*)"void*");
                    mArgs = kr_plus(kr_plus(((char*)"(void*)(intptr_t)atoll("), acode), ((char*)")"));
                } else {
                    mCast = kr_plus(mCast, ((char*)",void*"));
                    mArgs = kr_plus(kr_plus(kr_plus(mArgs, ((char*)", (void*)(intptr_t)atoll(")), acode), ((char*)")"));
                }
            } else {
                if (kr_truthy(kr_eq(mi, ((char*)"0")))) {
                    mCast = ((char*)"char*");
                    mArgs = acode;
                } else {
                    mCast = kr_plus(mCast, ((char*)",char*"));
                    mArgs = kr_plus(kr_plus(mArgs, ((char*)", ")), acode);
                }
            }
            mi = kr_plus(mi, ((char*)"1"));
        }
        if (kr_truthy(kr_eq(argc, ((char*)"0")))) {
            mCast = ((char*)"void");
        }
        char* retType = ((char*)"char*");
        char* mCall = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"(("), retType), ((char*)"(*)(")), mCast), ((char*)"))")), ((char*(*)(char*))cIdent)(fname)), ((char*)")(")), mArgs), ((char*)")"));
        if (kr_truthy(kr_eq(intRet, ((char*)"1")))) {
            char* is64 = ((char*(*)(char*))compileWin32Return64)(fname);
            if (kr_truthy(kr_eq(is64, ((char*)"1")))) {
                mCall = kr_plus(kr_plus(((char*)"kr_itoa64((long long)(intptr_t)("), mCall), ((char*)"))"));
            } else {
                mCall = kr_plus(kr_plus(((char*)"kr_itoa((int)(intptr_t)("), mCall), ((char*)"))"));
            }
        }
        return kr_plus(kr_plus(mCall, ((char*)",")), p);
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"((char*(*)("), castArgs), ((char*)"))")), ((char*(*)(char*))cIdent)(fname)), ((char*)")(")), args), ((char*)"),")), p);
}

char* compileStmt(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* tok = ((char*(*)(char*,char*))tokAt)(tokens, pos);
    if (kr_truthy((kr_truthy((kr_truthy(kr_eq(tok, ((char*)"KW:struct"))) || kr_truthy(kr_eq(tok, ((char*)"KW:class"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(tok, ((char*)"KW:type"))) ? kr_str("1") : kr_str("0")))) {
        return ((char*(*)(char*,char*,char*,char*))compileStructDecl)(tokens, kr_plus(pos, ((char*)"1")), ntoks, depth);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:try")))) {
        char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, kr_plus(pos, ((char*)"1")), ntoks, depth, inFunc);
        char* bcode = ((char*(*)(char*))pairVal)(bp);
        char* p = ((char*(*)(char*))pairPos)(bp);
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"KW:catch")))) {
            p = kr_plus(p, ((char*)"1"));
            char* catchVar = ((char*)"__err");
            if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, p)), ((char*)"ID")))) {
                catchVar = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, p));
                p = kr_plus(p, ((char*)"1"));
            }
            char* cbp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, p, ntoks, depth, inFunc);
            char* cbcode = ((char*(*)(char*))pairVal)(cbp);
            p = ((char*(*)(char*))pairPos)(cbp);
            char* ind = ((char*(*)(char*))indent)(depth);
            char* ind1 = ((char*(*)(char*))indent)(kr_plus(depth, ((char*)"1")));
            char* out = kr_plus(ind, ((char*)"{\n"));
            out = kr_plus(kr_plus(out, ind1), ((char*)"if (setjmp(*_kr_pushtry()) == 0) {\n"));
            out = kr_plus(out, bcode);
            out = kr_plus(kr_plus(out, ind1), ((char*)"_kr_poptry();\n"));
            out = kr_plus(kr_plus(out, ind1), ((char*)"} else {\n"));
            out = kr_plus(kr_plus(kr_plus(kr_plus(out, ind1), ((char*)"    char* ")), catchVar), ((char*)" = _kr_poptry();\n"));
            out = kr_plus(out, cbcode);
            out = kr_plus(kr_plus(out, ind1), ((char*)"}\n"));
            out = kr_plus(kr_plus(out, ind), ((char*)"}\n"));
            return kr_plus(kr_plus(out, ((char*)",")), p);
        } else {
            char* ind = ((char*(*)(char*))indent)(depth);
            char* ind1 = ((char*(*)(char*))indent)(kr_plus(depth, ((char*)"1")));
            char* out = kr_plus(ind, ((char*)"{\n"));
            out = kr_plus(kr_plus(out, ind1), ((char*)"if (setjmp(*_kr_pushtry()) == 0) {\n"));
            out = kr_plus(out, bcode);
            out = kr_plus(kr_plus(out, ind1), ((char*)"_kr_poptry();\n"));
            out = kr_plus(kr_plus(out, ind1), ((char*)"}\n"));
            out = kr_plus(kr_plus(out, ind), ((char*)"}\n"));
            return kr_plus(kr_plus(out, ((char*)",")), p);
        }
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:throw")))) {
        char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, kr_plus(pos, ((char*)"1")), ntoks);
        char* ecode = ((char*(*)(char*))pairVal)(ep);
        char* p = ((char*(*)(char*))pairPos)(ep);
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
            p = kr_plus(p, ((char*)"1"));
        }
        return kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ((char*)"_kr_throw(")), ecode), ((char*)");\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:let")))) {
        return ((char*(*)(char*,char*,char*,char*))compileLet)(tokens, kr_plus(pos, ((char*)"1")), ntoks, depth);
    }
    if (kr_truthy((kr_truthy(kr_eq(tok, ((char*)"KW:emit"))) || kr_truthy(kr_eq(tok, ((char*)"KW:return"))) ? kr_str("1") : kr_str("0")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))compileEmit)(tokens, kr_plus(pos, ((char*)"1")), ntoks, depth, inFunc);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:if")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))compileIf)(tokens, kr_plus(pos, ((char*)"1")), ntoks, depth, inFunc);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:while")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))compileWhile)(tokens, kr_plus(pos, ((char*)"1")), ntoks, depth, inFunc);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:for")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))compileFor)(tokens, kr_plus(pos, ((char*)"1")), ntoks, depth, inFunc);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:break")))) {
        char* p = kr_plus(pos, ((char*)"1"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
            p = kr_plus(p, ((char*)"1"));
        }
        return kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ((char*)"break;\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:continue")))) {
        char* p = kr_plus(pos, ((char*)"1"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
            p = kr_plus(p, ((char*)"1"));
        }
        return kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ((char*)"continue;\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:match")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))compileMatch)(tokens, kr_plus(pos, ((char*)"1")), ntoks, depth, inFunc);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:do")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))compileDoWhile)(tokens, kr_plus(pos, ((char*)"1")), ntoks, depth, inFunc);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:loop")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))compileLoop)(tokens, kr_plus(pos, ((char*)"1")), ntoks, depth, inFunc);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:const")))) {
        return ((char*(*)(char*,char*,char*,char*))compileLet)(tokens, kr_plus(pos, ((char*)"1")), ntoks, depth);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:module")))) {
        char* mname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1"))));
        char* p = kr_plus(pos, ((char*)"2"));
        return kr_plus(kr_plus(kr_plus(((char*)"// module: "), mname), ((char*)"\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:import")))) {
        char* importPath = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1"))));
        char* p = kr_plus(pos, ((char*)"2"));
        char* importSrc = kr_readfile(importPath);
        if (kr_truthy(kr_gt(kr_len(importSrc), ((char*)"0")))) {
            return kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ((char*)"// imported: ")), importPath), ((char*)"\n,")), p);
        } else {
            return kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ((char*)"// import not found: ")), importPath), ((char*)"\n,")), p);
        }
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:export")))) {
        char* nextTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1")));
        if (kr_truthy((kr_truthy(kr_eq(nextTok, ((char*)"KW:func"))) || kr_truthy(kr_eq(nextTok, ((char*)"KW:fn"))) ? kr_str("1") : kr_str("0")))) {
            char* fp = ((char*(*)(char*,char*,char*))compileFunc)(tokens, kr_plus(pos, ((char*)"1")), ntoks);
            return kr_plus(kr_plus(((char*(*)(char*))pairVal)(fp), ((char*)",")), ((char*(*)(char*))pairPos)(fp));
        }
        if (kr_truthy((kr_truthy((kr_truthy(kr_eq(nextTok, ((char*)"KW:struct"))) || kr_truthy(kr_eq(nextTok, ((char*)"KW:class"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(nextTok, ((char*)"KW:type"))) ? kr_str("1") : kr_str("0")))) {
            return ((char*(*)(char*,char*,char*,char*))compileStructDecl)(tokens, kr_plus(pos, ((char*)"2")), ntoks, depth);
        }
        char* p = kr_plus(pos, ((char*)"2"));
        return kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ((char*)"// export\n,")), p);
    }
    if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(tok), ((char*)"CBLOCK")))) {
        char* craw = kr_replace(((char*(*)(char*))tokVal)(tok), ((char*)"\\x01"), ((char*)"\n"));
        return kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), craw), ((char*)"\n,")), kr_plus(pos, ((char*)"1")));
    }
    if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(tok), ((char*)"ID")))) {
        char* nextTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1")));
        if (kr_truthy(kr_eq(nextTok, ((char*)"PLUSPLUS")))) {
            char* vname = ((char*(*)(char*))cIdent)(((char*(*)(char*))tokVal)(tok));
            char* p = kr_plus(pos, ((char*)"2"));
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
                p = kr_plus(p, ((char*)"1"));
            }
            return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), vname), ((char*)" = kr_plus(")), vname), ((char*)", kr_str(\"1\"));\n,")), p);
        }
        if (kr_truthy(kr_eq(nextTok, ((char*)"MINUSMINUS")))) {
            char* vname = ((char*(*)(char*))cIdent)(((char*(*)(char*))tokVal)(tok));
            char* p = kr_plus(pos, ((char*)"2"));
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
                p = kr_plus(p, ((char*)"1"));
            }
            return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), vname), ((char*)" = kr_sub(")), vname), ((char*)", kr_str(\"1\"));\n,")), p);
        }
    }
    if (kr_truthy(kr_eq(tok, ((char*)"PLUSPLUS")))) {
        char* vname = ((char*(*)(char*))cIdent)(((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1")))));
        char* p = kr_plus(pos, ((char*)"2"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
            p = kr_plus(p, ((char*)"1"));
        }
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), vname), ((char*)" = kr_plus(")), vname), ((char*)", kr_str(\"1\"));\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"MINUSMINUS")))) {
        char* vname = ((char*(*)(char*))cIdent)(((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1")))));
        char* p = kr_plus(pos, ((char*)"2"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
            p = kr_plus(p, ((char*)"1"));
        }
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), vname), ((char*)" = kr_sub(")), vname), ((char*)", kr_str(\"1\"));\n,")), p);
    }
    if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(tok), ((char*)"ID")))) {
        char* nextTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1")));
        if (kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(nextTok, ((char*)"PLUSEQ"))) || kr_truthy(kr_eq(nextTok, ((char*)"MINUSEQ"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(nextTok, ((char*)"STAREQ"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(nextTok, ((char*)"SLASHEQ"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(nextTok, ((char*)"MODEQ"))) ? kr_str("1") : kr_str("0")))) {
            return ((char*(*)(char*,char*,char*,char*))compileCompoundAssign)(tokens, pos, ntoks, depth);
        }
    }
    if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(tok), ((char*)"ID")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1"))), ((char*)"DOT")))) {
            if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"2")))), ((char*)"ID")))) {
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"3"))), ((char*)"ASSIGN")))) {
                    return ((char*(*)(char*,char*,char*,char*))compileFieldAssign)(tokens, pos, ntoks, depth);
                }
            }
        }
    }
    if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(tok), ((char*)"ID")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1"))), ((char*)"ASSIGN")))) {
            return ((char*(*)(char*,char*,char*,char*))compileAssign)(tokens, pos, ntoks, depth);
        }
    }
    return ((char*(*)(char*,char*,char*,char*))compileExprStmt)(tokens, pos, ntoks, depth);
}

char* compileLet(char* tokens, char* pos, char* ntoks, char* depth) {
    char* name = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* p = kr_plus(pos, ((char*)"1"));
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"COLON")))) {
        p = kr_plus(p, ((char*)"2"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"LBRACK")))) {
            char* depth2 = ((char*)"1");
            p = kr_plus(p, ((char*)"1"));
            while (kr_truthy(kr_gt(depth2, ((char*)"0")))) {
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"LBRACK")))) {
                    depth2 = kr_plus(depth2, ((char*)"1"));
                }
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RBRACK")))) {
                    depth2 = kr_sub(depth2, ((char*)"1"));
                }
                p = kr_plus(p, ((char*)"1"));
            }
        }
    }
    p = kr_plus(p, ((char*)"1"));
    char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
    char* ecode = ((char*(*)(char*))pairVal)(ep);
    p = ((char*(*)(char*))pairPos)(ep);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
        p = kr_plus(p, ((char*)"1"));
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ((char*)"char* ")), ((char*(*)(char*))cIdent)(name)), ((char*)" = ")), ecode), ((char*)";\n,")), p);
}

char* compileAssign(char* tokens, char* pos, char* ntoks, char* depth) {
    char* name = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* p = kr_plus(pos, ((char*)"2"));
    char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
    char* ecode = ((char*(*)(char*))pairVal)(ep);
    p = ((char*(*)(char*))pairPos)(ep);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
        p = kr_plus(p, ((char*)"1"));
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ((char*(*)(char*))cIdent)(name)), ((char*)" = ")), ecode), ((char*)";\n,")), p);
}

char* compileEmit(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, pos, ntoks);
    char* ecode = ((char*(*)(char*))pairVal)(ep);
    char* p = ((char*(*)(char*))pairPos)(ep);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
        p = kr_plus(p, ((char*)"1"));
    }
    if (kr_truthy(kr_eq(inFunc, ((char*)"0")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ((char*)"return atoi(")), ecode), ((char*)");\n,")), p);
    }
    if (kr_truthy(kr_eq(inFunc, ((char*)"int")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ((char*)"return atoi(")), ecode), ((char*)");\n,")), p);
    }
    if (kr_truthy(kr_eq(inFunc, ((char*)"zero")))) {
        return kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ecode), ((char*)";\n,")), p);
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ((char*)"return ")), ecode), ((char*)";\n,")), p);
}

char* compileIf(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* cp = ((char*(*)(char*,char*,char*))compileExpr)(tokens, pos, ntoks);
    char* cond = ((char*(*)(char*))pairVal)(cp);
    char* p = ((char*(*)(char*))pairPos)(cp);
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, p, ntoks, depth, inFunc);
    char* bcode = ((char*(*)(char*))pairVal)(bp);
    p = ((char*(*)(char*))pairPos)(bp);
    char* out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ((char*)"if (kr_truthy(")), cond), ((char*)")) {\n")), bcode), ((char*(*)(char*))indent)(depth)), ((char*)"}"));
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"KW:else")))) {
        p = kr_plus(p, ((char*)"1"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"KW:if")))) {
            char* eip = ((char*(*)(char*,char*,char*,char*,char*))compileIf)(tokens, kr_plus(p, ((char*)"1")), ntoks, depth, inFunc);
            char* eicode = ((char*(*)(char*))pairVal)(eip);
            p = ((char*(*)(char*))pairPos)(eip);
            char* stripped = kr_substr(eicode, kr_len(((char*(*)(char*))indent)(depth)), kr_len(eicode));
            out = kr_plus(kr_plus(out, ((char*)" else ")), stripped);
            return kr_plus(kr_plus(out, ((char*)",")), p);
        } else {
            char* ebp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, p, ntoks, depth, inFunc);
            char* ebcode = ((char*(*)(char*))pairVal)(ebp);
            p = ((char*(*)(char*))pairPos)(ebp);
            out = kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*)" else {\n")), ebcode), ((char*(*)(char*))indent)(depth)), ((char*)"}\n"));
            return kr_plus(kr_plus(out, ((char*)",")), p);
        }
    }
    out = kr_plus(out, ((char*)"\n"));
    return kr_plus(kr_plus(out, ((char*)",")), p);
}

char* compileWhile(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* cp = ((char*(*)(char*,char*,char*))compileExpr)(tokens, pos, ntoks);
    char* cond = ((char*(*)(char*))pairVal)(cp);
    char* p = ((char*(*)(char*))pairPos)(cp);
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, p, ntoks, depth, inFunc);
    char* bcode = ((char*(*)(char*))pairVal)(bp);
    p = ((char*(*)(char*))pairPos)(bp);
    char* out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ((char*)"while (kr_truthy(")), cond), ((char*)")) {\n")), bcode), ((char*(*)(char*))indent)(depth)), ((char*)"}\n"));
    return kr_plus(kr_plus(out, ((char*)",")), p);
}

char* compileLambda(char* tokens, char* pos, char* ntoks) {
    char* lname = kr_plus(((char*)"_krlam"), pos);
    char* p = kr_plus(pos, ((char*)"2"));
    char* lparams = ((char*)"");
    char* lpc = ((char*)"0");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RPAREN")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, p)), ((char*)"ID")))) {
            if (kr_truthy(kr_gt(lpc, ((char*)"0")))) {
                lparams = kr_plus(lparams, ((char*)","));
            }
            lparams = kr_plus(lparams, ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, p)));
            lpc = kr_plus(lpc, ((char*)"1"));
        }
        p = kr_plus(p, ((char*)"1"));
    }
    p = kr_plus(p, ((char*)"1"));
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"ARROW")))) {
        p = kr_plus(p, ((char*)"2"));
    }
    char* bp = ((char*(*)(char*,char*))skipBlock)(tokens, p);
    char* lfv2 = ((char*(*)(char*,char*,char*,char*))findFreeVars)(tokens, kr_sub(p, ((char*)"1")), bp, lparams);
    char* lfvc2 = ((char*)"0");
    if (kr_truthy(kr_gt(kr_len(lfv2), ((char*)"0")))) {
        lfvc2 = kr_linecount(lfv2);
    }
    char* captureCode = ((char*)"");
    char* lfvi3 = ((char*)"0");
    while (kr_truthy(kr_lt(lfvi3, lfvc2))) {
        char* fvn3 = ((char*(*)(char*))cIdent)(kr_split(lfv2, lfvi3));
        captureCode = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(captureCode, ((char*)"_krlam")), pos), ((char*)"_")), ((char*(*)(char*))cIdent)(fvn3)), ((char*)" = ")), ((char*(*)(char*))cIdent)(fvn3)), ((char*)"; "));
        lfvi3 = kr_plus(lfvi3, ((char*)"1"));
    }
    if (kr_truthy(kr_gt(kr_len(captureCode), ((char*)"0")))) {
        char* cc = kr_trim(captureCode);
        char* ccExpr = kr_trim(kr_replace(cc, ((char*)";"), ((char*)"")));
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"("), ccExpr), ((char*)", (char*)&")), lname), ((char*)"),")), bp);
    } else {
        return kr_plus(kr_plus(kr_plus(((char*)"(char*)&"), lname), ((char*)",")), bp);
    }
}

char* compileListLiteral(char* tokens, char* pos, char* ntoks) {
    char* p = kr_plus(pos, ((char*)"1"));
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RBRACK")))) {
        return kr_plus(kr_plus(((char*)"kr_str(\"\")"), ((char*)",")), kr_plus(p, ((char*)"1")));
    }
    char* elems = ((char*)"");
    char* ec = ((char*)"0");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RBRACK")))) {
        if (kr_truthy(kr_gt(ec, ((char*)"0")))) {
            p = kr_plus(p, ((char*)"1"));
        }
        char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
        char* ecode = ((char*(*)(char*))pairVal)(ep);
        p = ((char*(*)(char*))pairPos)(ep);
        if (kr_truthy(kr_gt(ec, ((char*)"0")))) {
            elems = kr_plus(kr_plus(elems, ((char*)"\n")), ecode);
        } else {
            elems = ecode;
        }
        ec = kr_plus(ec, ((char*)"1"));
    }
    p = kr_plus(p, ((char*)"1"));
    if (kr_truthy(kr_eq(ec, ((char*)"1")))) {
        return kr_plus(kr_plus(elems, ((char*)",")), p);
    }
    char* result = kr_getline(elems, ((char*)"0"));
    char* ei = ((char*)"1");
    while (kr_truthy(kr_lt(ei, ec))) {
        char* elem = kr_getline(elems, ei);
        result = kr_plus(kr_plus(kr_plus(kr_plus(((char*)"kr_cat(kr_cat("), result), ((char*)", kr_str(\",\")), ")), elem), ((char*)")"));
        ei = kr_plus(ei, ((char*)"1"));
    }
    return kr_plus(kr_plus(result, ((char*)",")), p);
}

char* compileInterp(char* s) {
    char* parts = ((char*)"");
    char* pc = ((char*)"0");
    char* i = ((char*)"0");
    char* seg = ((char*)"");
    while (kr_truthy(kr_lt(i, kr_len(s)))) {
        if (kr_truthy(kr_eq(kr_idx(s, kr_atoi(i)), ((char*)"{")))) {
            if (kr_truthy(kr_gt(kr_len(seg), ((char*)"0")))) {
                char* escaped = ((char*(*)(char*))cEscape)(seg);
                if (kr_truthy(kr_gt(pc, ((char*)"0")))) {
                    parts = kr_plus(kr_plus(kr_plus(parts, ((char*)"\n")), ((char*)"L:")), escaped);
                } else {
                    parts = kr_plus(((char*)"L:"), escaped);
                }
                pc = kr_plus(pc, ((char*)"1"));
                seg = ((char*)"");
            }
            i = kr_plus(i, ((char*)"1"));
            char* expr = ((char*)"");
            while (kr_truthy((kr_truthy(kr_lt(i, kr_len(s))) && kr_truthy(kr_neq(kr_idx(s, kr_atoi(i)), ((char*)"}"))) ? kr_str("1") : kr_str("0")))) {
                expr = kr_plus(expr, kr_idx(s, kr_atoi(i)));
                i = kr_plus(i, ((char*)"1"));
            }
            i = kr_plus(i, ((char*)"1"));
            if (kr_truthy(kr_gt(pc, ((char*)"0")))) {
                parts = kr_plus(kr_plus(kr_plus(parts, ((char*)"\n")), ((char*)"E:")), expr);
            } else {
                parts = kr_plus(((char*)"E:"), expr);
            }
            pc = kr_plus(pc, ((char*)"1"));
        } else {
            seg = kr_plus(seg, kr_idx(s, kr_atoi(i)));
            i = kr_plus(i, ((char*)"1"));
        }
    }
    if (kr_truthy(kr_gt(kr_len(seg), ((char*)"0")))) {
        char* escaped = ((char*(*)(char*))cEscape)(seg);
        if (kr_truthy(kr_gt(pc, ((char*)"0")))) {
            parts = kr_plus(kr_plus(kr_plus(parts, ((char*)"\n")), ((char*)"L:")), escaped);
        } else {
            parts = kr_plus(((char*)"L:"), escaped);
        }
        pc = kr_plus(pc, ((char*)"1"));
    }
    if (kr_truthy(kr_eq(pc, ((char*)"0")))) {
        return ((char*)"kr_str(\"\")");
    }
    char* result = ((char*)"");
    char* j = ((char*)"0");
    while (kr_truthy(kr_lt(j, pc))) {
        char* part = kr_getline(parts, j);
        char* ptype = kr_substr(part, ((char*)"0"), ((char*)"2"));
        char* pval = kr_substr(part, ((char*)"2"), kr_len(part));
        char* cpart = ((char*)"");
        if (kr_truthy(kr_eq(ptype, ((char*)"L:")))) {
            cpart = kr_plus(kr_plus(((char*)"kr_str(\""), pval), ((char*)"\")"));
        } else {
            char* exprToks = ((char*(*)(char*))tokenize)(pval);
            char* exprNtoks = kr_linecount(exprToks);
            if (kr_truthy(kr_gt(exprNtoks, ((char*)"0")))) {
                char* ep = ((char*(*)(char*,char*,char*))compileExpr)(exprToks, ((char*)"0"), exprNtoks);
                cpart = ((char*(*)(char*))pairVal)(ep);
            } else {
                cpart = ((char*)"kr_str(\"\")");
            }
        }
        if (kr_truthy(kr_eq(j, ((char*)"0")))) {
            result = cpart;
        } else {
            result = kr_plus(kr_plus(kr_plus(kr_plus(((char*)"kr_cat("), result), ((char*)", ")), cpart), ((char*)")"));
        }
        j = kr_plus(j, ((char*)"1"));
    }
    return result;
}

char* compileStructDecl(char* tokens, char* pos, char* ntoks, char* depth) {
    char* name = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* p = kr_plus(pos, ((char*)"1"));
    p = kr_plus(p, ((char*)"1"));
    char* fields = ((char*)"");
    char* fc = ((char*)"0");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RBRACE")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"KW:let")))) {
            char* fname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, ((char*)"1"))));
            if (kr_truthy(kr_gt(fc, ((char*)"0")))) {
                fields = kr_plus(kr_plus(fields, ((char*)",")), fname);
            } else {
                fields = fname;
            }
            fc = kr_plus(fc, ((char*)"1"));
            p = kr_plus(p, ((char*)"2"));
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"COLON")))) {
                p = kr_plus(p, ((char*)"2"));
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"LBRACK")))) {
                    char* sfd = ((char*)"1");
                    p = kr_plus(p, ((char*)"1"));
                    while (kr_truthy(kr_gt(sfd, ((char*)"0")))) {
                        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"LBRACK")))) {
                            sfd = kr_plus(sfd, ((char*)"1"));
                        }
                        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RBRACK")))) {
                            sfd = kr_sub(sfd, ((char*)"1"));
                        }
                        p = kr_plus(p, ((char*)"1"));
                    }
                }
            }
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"ASSIGN")))) {
                char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, kr_plus(p, ((char*)"1")), ntoks);
                p = ((char*(*)(char*))pairPos)(ep);
            }
        } else {
            p = kr_plus(p, ((char*)"1"));
        }
    }
    p = kr_plus(p, ((char*)"1"));
    char* cname = ((char*(*)(char*))cIdent)(name);
    char* out = kr_plus(kr_plus(((char*)"typedef struct "), cname), ((char*)"_s {\n"));
    char* i = ((char*)"0");
    while (kr_truthy(kr_lt(i, fc))) {
        char* fld = ((char*(*)(char*,char*))getNthParam)(fields, i);
        out = kr_plus(kr_plus(kr_plus(out, ((char*)"    char* ")), ((char*(*)(char*))cIdent)(fld)), ((char*)";\n"));
        i = kr_plus(i, ((char*)"1"));
    }
    out = kr_plus(kr_plus(kr_plus(out, ((char*)"} ")), cname), ((char*)"_t;\n\n"));
    out = kr_plus(kr_plus(kr_plus(out, ((char*)"static char* ")), cname), ((char*)"() {\n"));
    out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*)"    ")), cname), ((char*)"_t* _s = (")), cname), ((char*)"_t*)_alloc(sizeof(")), cname), ((char*)"_t));\n"));
    char* i2 = ((char*)"0");
    while (kr_truthy(kr_lt(i2, fc))) {
        char* fld2 = ((char*(*)(char*,char*))getNthParam)(fields, i2);
        out = kr_plus(kr_plus(kr_plus(out, ((char*)"    _s->")), ((char*(*)(char*))cIdent)(fld2)), ((char*)" = _K_EMPTY;\n"));
        i2 = kr_plus(i2, ((char*)"1"));
    }
    out = kr_plus(out, ((char*)"    return (char*)_s;\n"));
    out = kr_plus(out, ((char*)"}\n\n"));
    return kr_plus(kr_plus(out, ((char*)",")), p);
}

char* compileFieldAssign(char* tokens, char* pos, char* ntoks, char* depth) {
    char* objName = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* field = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"2"))));
    char* p = kr_plus(pos, ((char*)"4"));
    char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
    char* ecode = ((char*(*)(char*))pairVal)(ep);
    p = ((char*(*)(char*))pairPos)(ep);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
        p = kr_plus(p, ((char*)"1"));
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ((char*)"kr_setfield(")), ((char*(*)(char*))cIdent)(objName)), ((char*)", \"")), field), ((char*)"\", ")), ecode), ((char*)");\n,")), p);
}

char* compileStructLiteral(char* tokens, char* pos, char* ntoks) {
    char* name = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* cname = ((char*(*)(char*))cIdent)(name);
    char* p = kr_plus(pos, ((char*)"2"));
    char* fields = ((char*)"");
    char* vals = ((char*)"");
    char* fc = ((char*)"0");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RBRACE")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, p)), ((char*)"ID")))) {
            char* fname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, p));
            p = kr_plus(p, ((char*)"2"));
            char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
            char* ecode = ((char*(*)(char*))pairVal)(ep);
            p = ((char*(*)(char*))pairPos)(ep);
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"COMMA")))) {
                p = kr_plus(p, ((char*)"1"));
            }
            if (kr_truthy(kr_gt(fc, ((char*)"0")))) {
                fields = kr_plus(kr_plus(fields, ((char*)",")), fname);
                vals = kr_plus(kr_plus(vals, ecode), ((char*)"\n"));
            } else {
                fields = fname;
                vals = kr_plus(ecode, ((char*)"\n"));
            }
            fc = kr_plus(fc, ((char*)"1"));
        } else {
            p = kr_plus(p, ((char*)"1"));
        }
    }
    p = kr_plus(p, ((char*)"1"));
    char* out = ((char*)"({ char* _sl = kr_structnew();");
    char* i3 = ((char*)"0");
    while (kr_truthy(kr_lt(i3, fc))) {
        char* fn3 = ((char*(*)(char*,char*))getNthParam)(fields, i3);
        char* fv3 = kr_getline(vals, i3);
        out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*)" kr_setfield(_sl, \"")), fn3), ((char*)"\", ")), fv3), ((char*)");"));
        i3 = kr_plus(i3, ((char*)"1"));
    }
    out = kr_plus(out, ((char*)" _sl; })"));
    return kr_plus(kr_plus(out, ((char*)",")), p);
}

char* compileCompoundAssign(char* tokens, char* pos, char* ntoks, char* depth) {
    char* name = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* op = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1")));
    char* p = kr_plus(pos, ((char*)"2"));
    char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
    char* ecode = ((char*(*)(char*))pairVal)(ep);
    p = ((char*(*)(char*))pairPos)(ep);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
        p = kr_plus(p, ((char*)"1"));
    }
    char* cname = ((char*(*)(char*))cIdent)(name);
    if (kr_truthy(kr_eq(op, ((char*)"PLUSEQ")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), cname), ((char*)" = kr_plus(")), cname), ((char*)", ")), ecode), ((char*)");\n,")), p);
    }
    if (kr_truthy(kr_eq(op, ((char*)"MINUSEQ")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), cname), ((char*)" = kr_sub(")), cname), ((char*)", ")), ecode), ((char*)");\n,")), p);
    }
    if (kr_truthy(kr_eq(op, ((char*)"STAREQ")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), cname), ((char*)" = kr_mul(")), cname), ((char*)", ")), ecode), ((char*)");\n,")), p);
    }
    if (kr_truthy(kr_eq(op, ((char*)"SLASHEQ")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), cname), ((char*)" = kr_div(")), cname), ((char*)", ")), ecode), ((char*)");\n,")), p);
    }
    if (kr_truthy(kr_eq(op, ((char*)"MODEQ")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), cname), ((char*)" = kr_mod(")), cname), ((char*)", ")), ecode), ((char*)");\n,")), p);
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), cname), ((char*)" = ")), ecode), ((char*)";\n,")), p);
}

char* compileFor(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* varName = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* p = kr_plus(pos, ((char*)"2"));
    char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
    char* collection = ((char*(*)(char*))pairVal)(ep);
    p = ((char*(*)(char*))pairPos)(ep);
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, p, ntoks, depth, inFunc);
    char* bcode = ((char*(*)(char*))pairVal)(bp);
    p = ((char*(*)(char*))pairPos)(bp);
    char* cvar = ((char*(*)(char*))cIdent)(varName);
    char* dstr = kr_plus(depth, ((char*)""));
    char* colVar = kr_plus(((char*)"_for_col_"), dstr);
    char* cntVar = kr_plus(((char*)"_for_cnt_"), dstr);
    char* idxVar = kr_plus(((char*)"_for_i_"), dstr);
    char* out = kr_plus(((char*(*)(char*))indent)(depth), ((char*)"{\n"));
    out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*(*)(char*))indent)(kr_plus(depth, ((char*)"1")))), ((char*)"char* ")), colVar), ((char*)" = ")), collection), ((char*)";\n"));
    out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*(*)(char*))indent)(kr_plus(depth, ((char*)"1")))), ((char*)"int ")), cntVar), ((char*)" = kr_listlen(")), colVar), ((char*)");\n"));
    out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*(*)(char*))indent)(kr_plus(depth, ((char*)"1")))), ((char*)"for (int ")), idxVar), ((char*)" = 0; ")), idxVar), ((char*)" < ")), cntVar), ((char*)"; ")), idxVar), ((char*)"++) {\n"));
    out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*(*)(char*))indent)(kr_plus(depth, ((char*)"2")))), ((char*)"char* ")), cvar), ((char*)" = kr_split(")), colVar), ((char*)", kr_itoa(")), idxVar), ((char*)"));\n"));
    out = kr_plus(out, bcode);
    out = kr_plus(kr_plus(out, ((char*(*)(char*))indent)(kr_plus(depth, ((char*)"1")))), ((char*)"}\n"));
    out = kr_plus(kr_plus(out, ((char*(*)(char*))indent)(depth)), ((char*)"}\n"));
    return kr_plus(kr_plus(out, ((char*)",")), p);
}

char* compileMatch(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, pos, ntoks);
    char* mexpr = ((char*(*)(char*))pairVal)(ep);
    char* p = ((char*(*)(char*))pairPos)(ep);
    p = kr_plus(p, ((char*)"1"));
    char* out = kr_plus(((char*(*)(char*))indent)(depth), ((char*)"{\n"));
    out = kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*(*)(char*))indent)(kr_plus(depth, ((char*)"1")))), ((char*)"char* _match_val = ")), mexpr), ((char*)";\n"));
    char* first = ((char*)"1");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RBRACE")))) {
        char* ct = ((char*(*)(char*,char*))tokAt)(tokens, p);
        if (kr_truthy(kr_eq(ct, ((char*)"KW:else")))) {
            p = kr_plus(p, ((char*)"1"));
            char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, p, ntoks, kr_plus(depth, ((char*)"1")), inFunc);
            char* bcode = ((char*(*)(char*))pairVal)(bp);
            p = ((char*(*)(char*))pairPos)(bp);
            if (kr_truthy(kr_eq(first, ((char*)"1")))) {
                out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*(*)(char*))indent)(kr_plus(depth, ((char*)"1")))), ((char*)"{\n")), bcode), ((char*(*)(char*))indent)(kr_plus(depth, ((char*)"1")))), ((char*)"}\n"));
            } else {
                out = kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*)" else {\n")), bcode), ((char*(*)(char*))indent)(kr_plus(depth, ((char*)"1")))), ((char*)"}\n"));
            }
        } else {
            char* vp = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
            char* vcode = ((char*(*)(char*))pairVal)(vp);
            p = ((char*(*)(char*))pairPos)(vp);
            char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, p, ntoks, kr_plus(depth, ((char*)"1")), inFunc);
            char* bcode = ((char*(*)(char*))pairVal)(bp);
            p = ((char*(*)(char*))pairPos)(bp);
            if (kr_truthy(kr_eq(first, ((char*)"1")))) {
                out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*(*)(char*))indent)(kr_plus(depth, ((char*)"1")))), ((char*)"if (strcmp(_match_val, ")), vcode), ((char*)") == 0) {\n")), bcode), ((char*(*)(char*))indent)(kr_plus(depth, ((char*)"1")))), ((char*)"}"));
                first = ((char*)"0");
            } else {
                out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*)" else if (strcmp(_match_val, ")), vcode), ((char*)") == 0) {\n")), bcode), ((char*(*)(char*))indent)(kr_plus(depth, ((char*)"1")))), ((char*)"}"));
            }
        }
    }
    p = kr_plus(p, ((char*)"1"));
    out = kr_plus(kr_plus(kr_plus(out, ((char*)"\n")), ((char*(*)(char*))indent)(depth)), ((char*)"}\n"));
    return kr_plus(kr_plus(out, ((char*)",")), p);
}

char* compileDoWhile(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, pos, ntoks, depth, inFunc);
    char* bcode = ((char*(*)(char*))pairVal)(bp);
    char* p = ((char*(*)(char*))pairPos)(bp);
    p = kr_plus(p, ((char*)"1"));
    char* cp = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
    char* cond = ((char*(*)(char*))pairVal)(cp);
    p = ((char*(*)(char*))pairPos)(cp);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
        p = kr_plus(p, ((char*)"1"));
    }
    char* out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ((char*)"do {\n")), bcode), ((char*(*)(char*))indent)(depth)), ((char*)"} while (kr_truthy(")), cond), ((char*)"));\n"));
    return kr_plus(kr_plus(out, ((char*)",")), p);
}

char* compileLoop(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, pos, ntoks, depth, inFunc);
    char* bcode = ((char*(*)(char*))pairVal)(bp);
    char* p = ((char*(*)(char*))pairPos)(bp);
    p = kr_plus(p, ((char*)"1"));
    char* cp = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
    char* cond = ((char*(*)(char*))pairVal)(cp);
    p = ((char*(*)(char*))pairPos)(cp);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
        p = kr_plus(p, ((char*)"1"));
    }
    char* out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ((char*)"do {\n")), bcode), ((char*(*)(char*))indent)(depth)), ((char*)"} while (!kr_truthy(")), cond), ((char*)"));\n"));
    return kr_plus(kr_plus(out, ((char*)",")), p);
}

char* compileExprStmt(char* tokens, char* pos, char* ntoks, char* depth) {
    char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, pos, ntoks);
    char* ecode = ((char*(*)(char*))pairVal)(ep);
    char* p = ((char*(*)(char*))pairPos)(ep);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
        p = kr_plus(p, ((char*)"1"));
    }
    return kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ecode), ((char*)";\n,")), p);
}

char* compileBlock(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* p = kr_plus(pos, ((char*)"1"));
    char* code = kr_sbnew();
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RBRACE")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
            p = kr_plus(p, ((char*)"1"));
        } else {
            char* sp = ((char*(*)(char*,char*,char*,char*,char*))compileStmt)(tokens, p, ntoks, kr_plus(depth, ((char*)"1")), inFunc);
            char* sCode = ((char*(*)(char*))pairVal)(sp);
            p = ((char*(*)(char*))pairPos)(sp);
            code = kr_sbappend(code, sCode);
        }
    }
    p = kr_plus(p, ((char*)"1"));
    return kr_plus(kr_plus(kr_sbtostring(code), ((char*)",")), p);
}

char* hoistLambdas(char* code) {
    char* hoisted = kr_sbnew();
    char* clean = kr_sbnew();
    char* i = ((char*)"0");
    char* clen = kr_len(code);
    while (kr_truthy(kr_lt(i, clen))) {
        if (kr_truthy((kr_truthy(kr_lte(kr_plus(i, ((char*)"6")), clen)) && kr_truthy(kr_eq(kr_substr(code, i, kr_plus(i, ((char*)"6"))), ((char*)"/*LS*/"))) ? kr_str("1") : kr_str("0")))) {
            char* le = kr_indexof(kr_substr(code, kr_plus(i, ((char*)"6")), clen), ((char*)"/*LE*/"));
            if (kr_truthy(kr_gte(kr_toint(le), ((char*)"0")))) {
                char* bodyStart = kr_plus(i, ((char*)"6"));
                char* bodyEnd = kr_plus(bodyStart, kr_toint(le));
                char* leEnd = kr_plus(bodyEnd, ((char*)"6"));
                hoisted = kr_sbappend(hoisted, kr_plus(kr_substr(code, bodyStart, bodyEnd), ((char*)"\n")));
                i = leEnd;
            } else {
                clean = kr_sbappend(clean, kr_idx(code, kr_atoi(i)));
                i = kr_plus(i, ((char*)"1"));
            }
        } else {
            clean = kr_sbappend(clean, kr_idx(code, kr_atoi(i)));
            i = kr_plus(i, ((char*)"1"));
        }
    }
    return kr_plus(kr_plus(kr_sbtostring(hoisted), ((char*)"/*SPLIT*/")), kr_sbtostring(clean));
}

char* compileFunc(char* tokens, char* pos, char* ntoks) {
    char* nameTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1")));
    char* fname = ((char*(*)(char*))tokVal)(nameTok);
    char* p = kr_plus(pos, ((char*)"3"));
    char* params = ((char*)"");
    char* pnames = ((char*)"");
    char* pc = ((char*)"0");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RPAREN")))) {
        char* pt = ((char*(*)(char*,char*))tokAt)(tokens, p);
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(pt), ((char*)"ID")))) {
            char* pname = ((char*(*)(char*))cIdent)(((char*(*)(char*))tokVal)(pt));
            if (kr_truthy(kr_gt(pc, ((char*)"0")))) {
                params = kr_plus(kr_plus(params, ((char*)", char* ")), pname);
                pnames = kr_plus(kr_plus(pnames, ((char*)",")), pname);
            } else {
                params = kr_plus(((char*)"char* "), pname);
                pnames = pname;
            }
            pc = kr_plus(pc, ((char*)"1"));
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, ((char*)"1"))), ((char*)"COLON")))) {
                p = kr_plus(p, ((char*)"3"));
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"LBRACK")))) {
                    char* td = ((char*)"1");
                    p = kr_plus(p, ((char*)"1"));
                    while (kr_truthy(kr_gt(td, ((char*)"0")))) {
                        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"LBRACK")))) {
                            td = kr_plus(td, ((char*)"1"));
                        }
                        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RBRACK")))) {
                            td = kr_sub(td, ((char*)"1"));
                        }
                        p = kr_plus(p, ((char*)"1"));
                    }
                }
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"COMMA")))) {
                    p = kr_plus(p, ((char*)"1"));
                }
            } else {
                p = kr_plus(p, ((char*)"1"));
            }
        } else {
            p = kr_plus(p, ((char*)"1"));
        }
    }
    p = kr_plus(p, ((char*)"1"));
    char* fnRetType = ((char*)"");
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"ARROW")))) {
        fnRetType = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, ((char*)"1"))));
        p = kr_plus(p, ((char*)"2"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"LBRACK")))) {
            char* rd = ((char*)"1");
            p = kr_plus(p, ((char*)"1"));
            while (kr_truthy(kr_gt(rd, ((char*)"0")))) {
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"LBRACK")))) {
                    rd = kr_plus(rd, ((char*)"1"));
                }
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RBRACK")))) {
                    rd = kr_sub(rd, ((char*)"1"));
                }
                p = kr_plus(p, ((char*)"1"));
            }
        }
    }
    char* fnInFunc = ((char*)"1");
    if (kr_truthy(kr_eq(fnRetType, ((char*)"int")))) {
        fnInFunc = ((char*)"int");
    }
    if (kr_truthy(kr_eq(fnRetType, ((char*)"bool")))) {
        fnInFunc = ((char*)"int");
    }
    if (kr_truthy(kr_eq(fnRetType, ((char*)"zero")))) {
        fnInFunc = ((char*)"zero");
    }
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, p, ntoks, ((char*)"0"), fnInFunc);
    char* bcode = ((char*(*)(char*))pairVal)(bp);
    p = ((char*(*)(char*))pairPos)(bp);
    char* wrapParams = params;
    if (kr_truthy(kr_eq(pc, ((char*)"0")))) {
        wrapParams = ((char*)"void");
    }
    char* out = ((char*)"");
    if (kr_truthy(kr_eq(fnRetType, ((char*)"zero")))) {
        char* vbody = kr_replace(bcode, ((char*)"return _K_EMPTY;\n"), ((char*)""));
        vbody = kr_replace(vbody, ((char*)"return _K_ZERO;\n"), ((char*)""));
        vbody = kr_replace(vbody, ((char*)"return _K_ONE;\n"), ((char*)""));
        char* innerName = kr_plus(((char*)"_krv_"), ((char*(*)(char*))cIdent)(fname));
        out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"static void "), innerName), ((char*)"(")), wrapParams), ((char*)") {\n")), vbody), ((char*)"}\n"));
        out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*)"char* ")), ((char*(*)(char*))cIdent)(fname)), ((char*)"(")), wrapParams), ((char*)") { ")), innerName), ((char*)"(")), pnames), ((char*)"); return _K_EMPTY; }\n\n"));
    } else if (kr_truthy(kr_eq(fnRetType, ((char*)"int")))) {
        char* innerName = kr_plus(((char*)"_kri_"), ((char*(*)(char*))cIdent)(fname));
        out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"static int "), innerName), ((char*)"(")), wrapParams), ((char*)") {\n")), bcode), ((char*)"}\n"));
        out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*)"char* ")), ((char*(*)(char*))cIdent)(fname)), ((char*)"(")), wrapParams), ((char*)") { return kr_itoa(")), innerName), ((char*)"(")), pnames), ((char*)")); }\n\n"));
    } else if (kr_truthy(kr_eq(fnRetType, ((char*)"bool")))) {
        char* innerName = kr_plus(((char*)"_krb_"), ((char*(*)(char*))cIdent)(fname));
        out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"static int "), innerName), ((char*)"(")), wrapParams), ((char*)") {\n")), bcode), ((char*)"}\n"));
        out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*)"char* ")), ((char*(*)(char*))cIdent)(fname)), ((char*)"(")), wrapParams), ((char*)") { return ")), innerName), ((char*)"(")), pnames), ((char*)") ? _K_ONE : _K_ZERO; }\n\n"));
    } else {
        out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"char* "), ((char*(*)(char*))cIdent)(fname)), ((char*)"(")), params), ((char*)") {\n")), bcode), ((char*)"}\n\n"));
    }
    return kr_plus(kr_plus(out, ((char*)",")), p);
}

char* compileCallbackFunc(char* tokens, char* pos, char* ntoks) {
    char* nameTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1")));
    char* fname = ((char*(*)(char*))tokVal)(nameTok);
    char* p = kr_plus(pos, ((char*)"3"));
    char* params = ((char*)"");
    char* pc = ((char*)"0");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RPAREN")))) {
        char* pt = ((char*(*)(char*,char*))tokAt)(tokens, p);
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(pt), ((char*)"ID")))) {
            if (kr_truthy(kr_gt(pc, ((char*)"0")))) {
                params = kr_plus(kr_plus(params, ((char*)", char* ")), ((char*(*)(char*))cIdent)(((char*(*)(char*))tokVal)(pt)));
            } else {
                params = kr_plus(((char*)"char* "), ((char*(*)(char*))cIdent)(((char*(*)(char*))tokVal)(pt)));
            }
            pc = kr_plus(pc, ((char*)"1"));
            p = kr_plus(p, ((char*)"1"));
        } else {
            p = kr_plus(p, ((char*)"1"));
        }
    }
    p = kr_plus(p, ((char*)"1"));
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"ARROW")))) {
        p = kr_plus(p, ((char*)"2"));
    }
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, p, ntoks, ((char*)"0"), ((char*)"1"));
    char* bcode = ((char*(*)(char*))pairVal)(bp);
    p = ((char*(*)(char*))pairPos)(bp);
    char* bodyStripped = kr_replace(bcode, ((char*)"return _K_EMPTY;\n"), ((char*)""));
    bodyStripped = kr_replace(bodyStripped, ((char*)"return _K_ZERO;\n"), ((char*)""));
    bodyStripped = kr_replace(bodyStripped, ((char*)"return _K_ONE;\n"), ((char*)""));
    char* out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"void "), ((char*(*)(char*))cIdent)(fname)), ((char*)"(")), params), ((char*)") {\n")), bodyStripped), ((char*)"}\n\n"));
    return kr_plus(kr_plus(out, ((char*)",")), p);
}

char* sbNew() {
    return ((char*)"");
}

char* sbAppend(char* sb, char* s) {
    return kr_plus(sb, s);
}

char* sbToString(char* sb) {
    return sb;
}

char* cRuntime() {
    char* r = kr_sbnew();
    r = kr_sbappend(r, ((char*)"#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <time.h>\n#include <ctype.h>\n#include <stdarg.h>\n#include <stdint.h>\n#if defined(_WIN32) || defined(_WIN64)\n#include <string.h>\n#else\n#include <strings.h>\n#define _stricmp strcasecmp\n#endif\n\nstatic int _argc; static char** _argv;\n\ntypedef struct ABlock { struct ABlock* next; int cap; int used; } ABlock;\n"));
    r = kr_sbappend(r, ((char*)"static ABlock* _arena = 0;\n"));
    r = kr_sbappend(r, ((char*)"typedef struct AllocHdr { struct AllocHdr* next; uint32_t size; uint32_t mark; } AllocHdr;\n"));
    r = kr_sbappend(r, ((char*)"static AllocHdr* _alloc_head = 0;\n"));
    r = kr_sbappend(r, ((char*)"static char* _stack_bottom = 0;\n"));
    r = kr_sbappend(r, ((char*)"static long _gc_arena_bytes = 0;\n"));
    r = kr_sbappend(r, ((char*)"static long _gc_threshold = 268435456L;\n"));
    r = kr_sbappend(r, ((char*)"static int _gc_enabled = -1;\n"));
    r = kr_sbappend(r, ((char*)"static void _gc_collect(void);\n"));
    r = kr_sbappend(r, ((char*)"static char* _arena_addr_lo = (char*)~(uintptr_t)0;\n"));
    r = kr_sbappend(r, ((char*)"static char* _arena_addr_hi = 0;\n"));
    r = kr_sbappend(r, ((char*)"static char* _alloc(int n) __attribute__((noinline));\n"));
    r = kr_sbappend(r, ((char*)"static char* _alloc(int n) {\n"));
    r = kr_sbappend(r, ((char*)"    n = (n + 7) & ~7;\n"));
    r = kr_sbappend(r, ((char*)"    if (_gc_enabled < 0) {\n"));
    r = kr_sbappend(r, ((char*)"        const char* env = getenv(\"KR_NOGC\");\n"));
    r = kr_sbappend(r, ((char*)"        _gc_enabled = (env && *env) ? 0 : 1;\n"));
    r = kr_sbappend(r, ((char*)"    }\n"));
    r = kr_sbappend(r, ((char*)"    int total = sizeof(AllocHdr) + n;\n"));
    r = kr_sbappend(r, ((char*)"    if (!_arena || _arena->used + total > _arena->cap) {\n"));
    r = kr_sbappend(r, ((char*)"        if (_gc_enabled && _gc_arena_bytes > _gc_threshold) {\n"));
    r = kr_sbappend(r, ((char*)"            _gc_collect();\n"));
    r = kr_sbappend(r, ((char*)"            if (_arena && _arena->used + total <= _arena->cap) goto have_room;\n"));
    r = kr_sbappend(r, ((char*)"        }\n"));
    r = kr_sbappend(r, ((char*)"        int cap = 64*1024*1024;\n"));
    r = kr_sbappend(r, ((char*)"        if (total > cap) cap = total;\n"));
    r = kr_sbappend(r, ((char*)"        ABlock* b = (ABlock*)malloc(sizeof(ABlock) + cap);\n"));
    r = kr_sbappend(r, ((char*)"        if (!b) { fprintf(stderr, \"out of memory\\n\"); exit(1); }\n"));
    r = kr_sbappend(r, ((char*)"        b->cap = cap; b->used = 0; b->next = _arena; _arena = b;\n"));
    r = kr_sbappend(r, ((char*)"        _gc_arena_bytes += cap;\n"));
    r = kr_sbappend(r, ((char*)"    }\n"));
    r = kr_sbappend(r, ((char*)"    have_room:;\n"));
    r = kr_sbappend(r, ((char*)"    AllocHdr* h = (AllocHdr*)((char*)(_arena + 1) + _arena->used);\n"));
    r = kr_sbappend(r, ((char*)"    h->next = _alloc_head;\n"));
    r = kr_sbappend(r, ((char*)"    h->size = (uint32_t)n;\n"));
    r = kr_sbappend(r, ((char*)"    h->mark = 0;\n"));
    r = kr_sbappend(r, ((char*)"    _alloc_head = h;\n"));
    r = kr_sbappend(r, ((char*)"    _arena->used += total;\n"));
    r = kr_sbappend(r, ((char*)"    char* user = (char*)(h + 1);\n"));
    r = kr_sbappend(r, ((char*)"    if (user < _arena_addr_lo) _arena_addr_lo = user;\n"));
    r = kr_sbappend(r, ((char*)"    if (user + n > _arena_addr_hi) _arena_addr_hi = user + n;\n"));
    r = kr_sbappend(r, ((char*)"    return user;\n"));
    r = kr_sbappend(r, ((char*)"}\n\n"));
    r = kr_sbappend(r, ((char*)"#include <setjmp.h>\n"));
    r = kr_sbappend(r, ((char*)"static int _gc_in_range(ABlock* b, char* p) {\n"));
    r = kr_sbappend(r, ((char*)"    char* base = (char*)(b + 1);\n"));
    r = kr_sbappend(r, ((char*)"    return p >= base && p < base + b->cap;\n"));
    r = kr_sbappend(r, ((char*)"}\n"));
    r = kr_sbappend(r, ((char*)"static AllocHdr** _gc_sorted = 0;\n"));
    r = kr_sbappend(r, ((char*)"static int _gc_sorted_cap = 0;\n"));
    r = kr_sbappend(r, ((char*)"static int _gc_sorted_n = 0;\n"));
    r = kr_sbappend(r, ((char*)"static int _gc_alloc_cmp(const void* a, const void* b) {\n"));
    r = kr_sbappend(r, ((char*)"    char* pa = (char*)*(AllocHdr* const*)a;\n"));
    r = kr_sbappend(r, ((char*)"    char* pb = (char*)*(AllocHdr* const*)b;\n"));
    r = kr_sbappend(r, ((char*)"    return pa < pb ? -1 : (pa > pb ? 1 : 0);\n"));
    r = kr_sbappend(r, ((char*)"}\n"));
    r = kr_sbappend(r, ((char*)"static void _gc_mark_word(void* word) {\n"));
    r = kr_sbappend(r, ((char*)"    char* p = (char*)word;\n"));
    r = kr_sbappend(r, ((char*)"    if (p < _arena_addr_lo || p >= _arena_addr_hi) return;\n"));
    r = kr_sbappend(r, ((char*)"    if (_gc_sorted_n == 0) return;\n"));
    r = kr_sbappend(r, ((char*)"    // Binary search for greatest alloc with start <= p.\n"));
    r = kr_sbappend(r, ((char*)"    int lo = 0, hi = _gc_sorted_n;\n"));
    r = kr_sbappend(r, ((char*)"    while (lo < hi) {\n"));
    r = kr_sbappend(r, ((char*)"        int mid = (lo + hi) / 2;\n"));
    r = kr_sbappend(r, ((char*)"        char* mid_start = (char*)_gc_sorted[mid];\n"));
    r = kr_sbappend(r, ((char*)"        if (mid_start <= p) lo = mid + 1; else hi = mid;\n"));
    r = kr_sbappend(r, ((char*)"    }\n"));
    r = kr_sbappend(r, ((char*)"    if (lo == 0) return;\n"));
    r = kr_sbappend(r, ((char*)"    AllocHdr* a = _gc_sorted[lo - 1];\n"));
    r = kr_sbappend(r, ((char*)"    char* user = (char*)(a + 1);\n"));
    r = kr_sbappend(r, ((char*)"    if (p >= user && p < user + a->size) a->mark = 1;\n"));
    r = kr_sbappend(r, ((char*)"}\n"));
    r = kr_sbappend(r, ((char*)"static void _gc_collect(void) {\n"));
    r = kr_sbappend(r, ((char*)"    // Clear all marks + count.\n"));
    r = kr_sbappend(r, ((char*)"    AllocHdr* a = _alloc_head;\n"));
    r = kr_sbappend(r, ((char*)"    long n_total = 0, n_live = 0;\n"));
    r = kr_sbappend(r, ((char*)"    while (a) { a->mark = 0; n_total++; a = a->next; }\n"));
    r = kr_sbappend(r, ((char*)"    // Build sorted-by-address index for binary-search mark phase.\n"));
    r = kr_sbappend(r, ((char*)"    if (n_total > _gc_sorted_cap) {\n"));
    r = kr_sbappend(r, ((char*)"        int newcap = _gc_sorted_cap ? _gc_sorted_cap : 1024;\n"));
    r = kr_sbappend(r, ((char*)"        while (newcap < n_total) newcap *= 2;\n"));
    r = kr_sbappend(r, ((char*)"        _gc_sorted = (AllocHdr**)realloc(_gc_sorted, newcap * sizeof(AllocHdr*));\n"));
    r = kr_sbappend(r, ((char*)"        _gc_sorted_cap = newcap;\n"));
    r = kr_sbappend(r, ((char*)"    }\n"));
    r = kr_sbappend(r, ((char*)"    int idx = 0;\n"));
    r = kr_sbappend(r, ((char*)"    for (a = _alloc_head; a; a = a->next) _gc_sorted[idx++] = a;\n"));
    r = kr_sbappend(r, ((char*)"    _gc_sorted_n = idx;\n"));
    r = kr_sbappend(r, ((char*)"    qsort(_gc_sorted, idx, sizeof(AllocHdr*), _gc_alloc_cmp);\n"));
    r = kr_sbappend(r, ((char*)"    // Mark roots: spill regs to jmp_buf, then scan stack.\n"));
    r = kr_sbappend(r, ((char*)"    jmp_buf regs;\n"));
    r = kr_sbappend(r, ((char*)"    setjmp(regs);\n"));
    r = kr_sbappend(r, ((char*)"    char* lo = (char*)&regs;\n"));
    r = kr_sbappend(r, ((char*)"    char* hi = _stack_bottom;\n"));
    r = kr_sbappend(r, ((char*)"    if (lo > hi) { char* t = lo; lo = hi; hi = t; }\n"));
    r = kr_sbappend(r, ((char*)"    char* p = (char*)(((uintptr_t)lo + 7) & ~(uintptr_t)7);\n"));
    r = kr_sbappend(r, ((char*)"    while (p < hi) {\n"));
    r = kr_sbappend(r, ((char*)"        _gc_mark_word(*(void**)p);\n"));
    r = kr_sbappend(r, ((char*)"        p += 8;\n"));
    r = kr_sbappend(r, ((char*)"    }\n"));
    r = kr_sbappend(r, ((char*)"    // Sweep: unlink unmarked from the global list.\n"));
    r = kr_sbappend(r, ((char*)"    AllocHdr** pp = &_alloc_head;\n"));
    r = kr_sbappend(r, ((char*)"    while (*pp) {\n"));
    r = kr_sbappend(r, ((char*)"        if ((*pp)->mark == 0) { *pp = (*pp)->next; }\n"));
    r = kr_sbappend(r, ((char*)"        else { n_live++; pp = &(*pp)->next; }\n"));
    r = kr_sbappend(r, ((char*)"    }\n"));
    r = kr_sbappend(r, ((char*)"    // Free any fully-dead arena blocks (no live allocs in their range).\n"));
    r = kr_sbappend(r, ((char*)"    ABlock** bpp = &_arena;\n"));
    r = kr_sbappend(r, ((char*)"    while (*bpp) {\n"));
    r = kr_sbappend(r, ((char*)"        int has_live = 0;\n"));
    r = kr_sbappend(r, ((char*)"        AllocHdr* la = _alloc_head;\n"));
    r = kr_sbappend(r, ((char*)"        while (la) { if (_gc_in_range(*bpp, (char*)la)) { has_live = 1; break; } la = la->next; }\n"));
    r = kr_sbappend(r, ((char*)"        if (!has_live && *bpp != _arena) {\n"));
    r = kr_sbappend(r, ((char*)"            ABlock* dead = *bpp;\n"));
    r = kr_sbappend(r, ((char*)"            *bpp = dead->next;\n"));
    r = kr_sbappend(r, ((char*)"            _gc_arena_bytes -= dead->cap;\n"));
    r = kr_sbappend(r, ((char*)"            free(dead);\n"));
    r = kr_sbappend(r, ((char*)"        } else {\n"));
    r = kr_sbappend(r, ((char*)"            bpp = &(*bpp)->next;\n"));
    r = kr_sbappend(r, ((char*)"        }\n"));
    r = kr_sbappend(r, ((char*)"    }\n"));
    r = kr_sbappend(r, ((char*)"    // Reset _gc_threshold to roughly 4x current live size, min 64 MB.\n"));
    r = kr_sbappend(r, ((char*)"    long live_bytes = 0;\n"));
    r = kr_sbappend(r, ((char*)"    a = _alloc_head; while (a) { live_bytes += a->size; a = a->next; }\n"));
    r = kr_sbappend(r, ((char*)"    _gc_threshold = live_bytes * 4;\n"));
    r = kr_sbappend(r, ((char*)"    if (_gc_threshold < 536870912L) _gc_threshold = 536870912L;\n"));
    r = kr_sbappend(r, ((char*)"    if (getenv(\"KR_GC_LOG\")) fprintf(stderr, \"[gc] swept %ld/%ld allocs, %ldMB live, threshold->%ldMB\\n\", n_total - n_live, n_total, live_bytes/1048576, _gc_threshold/1048576);\n"));
    r = kr_sbappend(r, ((char*)"}\n\n"));
    r = kr_sbappend(r, ((char*)"typedef struct { ABlock* block; int used; } _AllocMark;\n"));
    r = kr_sbappend(r, ((char*)"static char* _alloc_mark(void) {\n"));
    r = kr_sbappend(r, ((char*)"    _AllocMark m;\n"));
    r = kr_sbappend(r, ((char*)"    m.block = _arena;\n"));
    r = kr_sbappend(r, ((char*)"    m.used = _arena ? _arena->used : 0;\n"));
    r = kr_sbappend(r, ((char*)"    char* tok = _alloc(sizeof(_AllocMark));\n"));
    r = kr_sbappend(r, ((char*)"    memcpy(tok, &m, sizeof(_AllocMark));\n"));
    r = kr_sbappend(r, ((char*)"    return tok;\n"));
    r = kr_sbappend(r, ((char*)"}\n"));
    r = kr_sbappend(r, ((char*)"static char* _kr_itoa_cache[1024];\n"));
    r = kr_sbappend(r, ((char*)"static char* _alloc_reset(const char* tok) {\n"));
    r = kr_sbappend(r, ((char*)"    _AllocMark m;\n"));
    r = kr_sbappend(r, ((char*)"    memcpy(&m, tok, sizeof(_AllocMark));\n"));
    r = kr_sbappend(r, ((char*)"    // Prune the global alloc list: anything in a block we're about\n"));
    r = kr_sbappend(r, ((char*)"    // to free (or above m.used within m.block) gets dropped first so\n"));
    r = kr_sbappend(r, ((char*)"    // the GC mark phase doesn't dereference freed memory.\n"));
    r = kr_sbappend(r, ((char*)"    AllocHdr** pp = &_alloc_head;\n"));
    r = kr_sbappend(r, ((char*)"    while (*pp) {\n"));
    r = kr_sbappend(r, ((char*)"        AllocHdr* h = *pp;\n"));
    r = kr_sbappend(r, ((char*)"        int dead = 0;\n"));
    r = kr_sbappend(r, ((char*)"        ABlock* b = _arena;\n"));
    r = kr_sbappend(r, ((char*)"        while (b && b != m.block) {\n"));
    r = kr_sbappend(r, ((char*)"            if (_gc_in_range(b, (char*)h)) { dead = 1; break; }\n"));
    r = kr_sbappend(r, ((char*)"            b = b->next;\n"));
    r = kr_sbappend(r, ((char*)"        }\n"));
    r = kr_sbappend(r, ((char*)"        if (!dead && m.block && _gc_in_range(m.block, (char*)h)\n"));
    r = kr_sbappend(r, ((char*)"             && (char*)h >= (char*)(m.block + 1) + m.used) dead = 1;\n"));
    r = kr_sbappend(r, ((char*)"        if (dead) *pp = h->next;\n"));
    r = kr_sbappend(r, ((char*)"        else pp = &h->next;\n"));
    r = kr_sbappend(r, ((char*)"    }\n"));
    r = kr_sbappend(r, ((char*)"    while (_arena && _arena != m.block) {\n"));
    r = kr_sbappend(r, ((char*)"        ABlock* deadb = _arena;\n"));
    r = kr_sbappend(r, ((char*)"        _arena = deadb->next;\n"));
    r = kr_sbappend(r, ((char*)"        _gc_arena_bytes -= deadb->cap;\n"));
    r = kr_sbappend(r, ((char*)"        free(deadb);\n"));
    r = kr_sbappend(r, ((char*)"    }\n"));
    r = kr_sbappend(r, ((char*)"    if (_arena) _arena->used = m.used;\n"));
    r = kr_sbappend(r, ((char*)"    // kr_itoa cached strings point into arena; reset invalidates them.\n"));
    r = kr_sbappend(r, ((char*)"    for (int i = 0; i < 1024; i++) _kr_itoa_cache[i] = 0;\n"));
    r = kr_sbappend(r, ((char*)"    return \"\";\n"));
    r = kr_sbappend(r, ((char*)"}\n\n"));
    r = kr_sbappend(r, ((char*)"static long _intSlots[32];\n"));
    r = kr_sbappend(r, ((char*)"static char* intSlotStore(const char* slot, const char* val) {\n"));
    r = kr_sbappend(r, ((char*)"    int s = atoi(slot);\n"));
    r = kr_sbappend(r, ((char*)"    if (s < 0 || s >= 32) return \"\";\n"));
    r = kr_sbappend(r, ((char*)"    _intSlots[s] = atol(val);\n"));
    r = kr_sbappend(r, ((char*)"    return \"\";\n"));
    r = kr_sbappend(r, ((char*)"}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_str(const char*);\n"));
    r = kr_sbappend(r, ((char*)"static char* intSlotLoad(const char* slot) {\n"));
    r = kr_sbappend(r, ((char*)"    int s = atoi(slot);\n"));
    r = kr_sbappend(r, ((char*)"    char buf[32];\n"));
    r = kr_sbappend(r, ((char*)"    if (s < 0 || s >= 32) { buf[0]='0'; buf[1]=0; return kr_str(buf); }\n"));
    r = kr_sbappend(r, ((char*)"    snprintf(buf, sizeof(buf), \"%ld\", _intSlots[s]);\n"));
    r = kr_sbappend(r, ((char*)"    return kr_str(buf);\n"));
    r = kr_sbappend(r, ((char*)"}\n\n"));
    r = kr_sbappend(r, ((char*)"static char _K_EMPTY[] = \"\";\nstatic char _K_ZERO[] = \"0\";\nstatic char _K_ONE[] = \"1\";\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_str(const char* s) {\nif (!s[0]) return _K_EMPTY;\n    if (s[0] == '0' && !s[1]) return _K_ZERO;\n    if (s[0] == '1' && !s[1]) return _K_ONE;\n    int n = (int)strlen(s) + 1;\n    char* p = _alloc(n);\n    memcpy(p, s, n);\n    return p;\n"));
    r = kr_sbappend(r, ((char*)"}\n\nstatic char* kr_cat(const char* a, const char* b) {\nint la = (int)strlen(a), lb = (int)strlen(b);\n    char* p = _alloc(la + lb + 1);\n    memcpy(p, a, la);\n    memcpy(p + la, b, lb + 1);\n    return p;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static int kr_isnum(const char* s) {\n    if (!*s) return 0;\n    const char* p = s;\n    if (*p == '-') p++;\n    if (!*p) return 0;\n    while (*p) { if (*p < '0' || *p > '9') return 0; p++; }\n    return 1;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_itoa(int v) {\n"));
    r = kr_sbappend(r, ((char*)"    if (v == 0) return _K_ZERO;\n"));
    r = kr_sbappend(r, ((char*)"    if (v == 1) return _K_ONE;\n"));
    r = kr_sbappend(r, ((char*)"    if (v >= 0 && v < 1024) {\n"));
    r = kr_sbappend(r, ((char*)"        char* c = _kr_itoa_cache[v];\n"));
    r = kr_sbappend(r, ((char*)"        if (c) return c;\n"));
    r = kr_sbappend(r, ((char*)"        char buf[8];\n"));
    r = kr_sbappend(r, ((char*)"        snprintf(buf, sizeof(buf), \"%d\", v);\n"));
    r = kr_sbappend(r, ((char*)"        c = kr_str(buf);\n"));
    r = kr_sbappend(r, ((char*)"        _kr_itoa_cache[v] = c;\n"));
    r = kr_sbappend(r, ((char*)"        return c;\n"));
    r = kr_sbappend(r, ((char*)"    }\n"));
    r = kr_sbappend(r, ((char*)"    char buf[32];\n"));
    r = kr_sbappend(r, ((char*)"    snprintf(buf, sizeof(buf), \"%d\", v);\n"));
    r = kr_sbappend(r, ((char*)"    return kr_str(buf);\n"));
    r = kr_sbappend(r, ((char*)"}\n\nstatic int kr_atoi(const char* s) { return atoi(s); }\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_itoa64(long long v) {\n    char buf[32];\n    snprintf(buf, sizeof(buf), \"%lld\", v);\n    return kr_str(buf);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_plus(const char* a, const char* b) {\n    if (kr_isnum(a) && kr_isnum(b))\n        return kr_itoa(atoi(a) + atoi(b));\n    return kr_cat(a, b);\n}\n\nstatic char* kr_sub(const char* a, const char* b) { return kr_itoa(atoi(a) - atoi(b)); }\nstatic char* kr_mul(const char* a, const char* b) { return kr_itoa(atoi(a) * atoi(b)); }\nstatic char* kr_div(const char* a, const char* b) { return kr_itoa(atoi(a) / atoi(b)); }\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_mod(const char* a, const char* b) { return kr_itoa(atoi(a) % atoi(b)); }\nstatic char* kr_neg(const char* a) { return kr_itoa(-atoi(a)); }\nstatic char* kr_not(const char* a) { return atoi(a) ? _K_ZERO : _K_ONE; }\n\nstatic char* kr_eq(const char* a, const char* b) {\n    return strcmp(a, b) == 0 ? _K_ONE : _K_ZERO;\n}\nstatic char* kr_neq(const char* a, const char* b) {\n    return strcmp(a, b) != 0 ? _K_ONE : _K_ZERO;\n"));
    r = kr_sbappend(r, ((char*)"}\nstatic char* kr_lt(const char* a, const char* b) {\n    if (kr_isnum(a) && kr_isnum(b)) return atoi(a) < atoi(b) ? _K_ONE : _K_ZERO;\n    return strcmp(a, b) < 0 ? _K_ONE : _K_ZERO;\n}\nstatic char* kr_gt(const char* a, const char* b) {\n    if (kr_isnum(a) && kr_isnum(b)) return atoi(a) > atoi(b) ? _K_ONE : _K_ZERO;\n    return strcmp(a, b) > 0 ? _K_ONE : _K_ZERO;\n"));
    r = kr_sbappend(r, ((char*)"}\nstatic char* kr_lte(const char* a, const char* b) {\n    return kr_gt(a, b) == _K_ZERO ? _K_ONE : _K_ZERO;\n}\nstatic char* kr_gte(const char* a, const char* b) {\n    return kr_lt(a, b) == _K_ZERO ? _K_ONE : _K_ZERO;\n}\n\nstatic int kr_truthy(const char* s) {\n"));
    r = kr_sbappend(r, ((char*)"    if (!s || !*s) return 0;\n    if (strcmp(s, \"0\") == 0) return 0;\n    if (strcmp(s, \"false\") == 0) return 0;\n    return 1;\n}\n\nstatic char* kr_print(const char* s) {\n"));
    r = kr_sbappend(r, ((char*)"    printf(\"%s\\n\", s);\n"));
    r = kr_sbappend(r, ((char*)"    return _K_EMPTY;\n}\n\nstatic char* kr_len(const char* s) { return kr_itoa((int)strlen(s)); }\n\nstatic char* kr_idx(const char* s, int i) {\n    char buf[2] = {s[i], 0};\n    return kr_str(buf);\n}\n\nstatic char* kr_split(const char* s, const char* idxs) {\n"));
    r = kr_sbappend(r, ((char*)"    int idx = atoi(idxs);\n    int count = 0;\n    const char* start = s;\n    const char* p = s;\n    while (*p) {\n        if (*p == ',') {\n            if (count == idx) {\n                int len = (int)(p - start);\n"));
    r = kr_sbappend(r, ((char*)"                char* r = _alloc(len + 1);\n                memcpy(r, start, len);\n                r[len] = 0;\n                return r;\n            }\n            count++;\n            start = p + 1;\n        }\n"));
    r = kr_sbappend(r, ((char*)"        p++;\n    }\n    if (count == idx) return kr_str(start);\n    return kr_str(\"\");\n}\n\nstatic char* kr_startswith(const char* s, const char* prefix) {\n    return strncmp(s, prefix, strlen(prefix)) == 0 ? _K_ONE : _K_ZERO;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_substr(const char* s, const char* starts, const char* ends) {\n    int st = atoi(starts), en = atoi(ends);\n    int slen = (int)strlen(s);\n    if (st >= slen) return kr_str(\"\");\n    if (en > slen) en = slen;\n    int n = en - st;\n    if (n <= 0) return kr_str(\"\");\n    char* r = _alloc(n + 1);\n"));
    r = kr_sbappend(r, ((char*)"    memcpy(r, s + st, n);\n    r[n] = 0;\n    return r;\n}\n\nstatic char* kr_toint(const char* s) { return kr_itoa(atoi(s)); }\n\nstatic char* kr_exec(const char* cmd) {\n    char* buf=_alloc(8192); buf[0]=0;\n#ifdef _WIN32\n    FILE* p=_popen(cmd,\"r\");\n#else\n    FILE* p=popen(cmd,\"r\");\n#endif\n    if(!p) return buf;\n    int pos=0,ch;\n    while(pos<8191&&(ch=fgetc(p))!=EOF) buf[pos++]=(char)ch;\n    buf[pos]=0;\n#ifdef _WIN32\n    _pclose(p);\n#else\n    pclose(p);\n#endif\n    while(pos>0&&(buf[pos-1]==13||buf[pos-1]==10||buf[pos-1]==32)) buf[--pos]=0;\n    return buf;\n}\n\n\n\nstatic char* kr_readfile(const char* path) {\n    FILE* f = fopen(path, \"rb\");\n    if (!f) return kr_str(\"\");\n"));
    r = kr_sbappend(r, ((char*)"    fseek(f, 0, SEEK_END);\n    long sz = ftell(f);\n    fseek(f, 0, SEEK_SET);\n    char* buf = _alloc((int)sz + 1);\n    fread(buf, 1, sz, f);\n    buf[sz] = 0;\n    fclose(f);\n    return buf;\n"));
    r = kr_sbappend(r, ((char*)"}\n\nstatic char* kr_arg(const char* idxs) {\n    int idx = atoi(idxs) + 1;\n    if (idx < _argc) return kr_str(_argv[idx]);\n    return kr_str(\"\");\n}\n\nstatic char* kr_argcount() {\n    return kr_itoa(_argc - 1);\n"));
    r = kr_sbappend(r, ((char*)"}\n\nstatic char* kr_getline(const char* s, const char* idxs) {\n"));
    r = kr_sbappend(r, ((char*)"    int idx = atoi(idxs);\n    static const char* _gl_s = 0;\n    static int _gl_idx = 0;\n    static const char* _gl_start = 0;\n"));
    r = kr_sbappend(r, ((char*)"    const char* start; int cur;\n    if (s == _gl_s && _gl_start && idx >= _gl_idx) {\n        start = _gl_start; cur = _gl_idx;\n    } else {\n        start = s; cur = 0; _gl_s = s; _gl_start = s; _gl_idx = 0;\n    }\n"));
    r = kr_sbappend(r, ((char*)"    const char* p = start;\n    while (*p) {\n        if (*p == '\\n') {\n            if (cur == idx) {\n                int len = (int)(p - start);\n                char* r = _alloc(len + 1);\n                memcpy(r, start, len); r[len] = 0;\n"));
    r = kr_sbappend(r, ((char*)"                _gl_s = s; _gl_idx = idx; _gl_start = start;\n                return r;\n            }\n            cur++; start = p + 1;\n        }\n        p++;\n    }\n    if (cur == idx) { _gl_s = s; _gl_idx = idx; _gl_start = start; return kr_str(start); }\n    return kr_str(\"\");\n}\n\nstatic char* kr_linecount(const char* s) {\n"));
    r = kr_sbappend(r, ((char*)"    if (!*s) return kr_str(\"0\");\n    int count = 1;\n    const char* p = s;\n"));
    r = kr_sbappend(r, ((char*)"    while (*p) { if (*p == '\\n') count++; p++; }\n"));
    r = kr_sbappend(r, ((char*)"    if (*(p - 1) == '\\n') count--;\n"));
    r = kr_sbappend(r, ((char*)"    return kr_itoa(count);\n}\n\nstatic char* kr_count(const char* s) {\n    int n = 1;\n    if (s) { const char* p = s; while (*p) { if (*p == ',') n++; p++; } }\n    return kr_itoa(n);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_writefile(const char* path, const char* data) {\n    FILE* f = fopen(path, \"wb\");\n    if (!f) return _K_ZERO;\n    fwrite(data, 1, strlen(data), f);\n    fclose(f);\n    return _K_ONE;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static int _krhex(char c){if(c>='0'&&c<='9')return c-'0';if(c>='a'&&c<='f')return c-'a'+10;if(c>='A'&&c<='F')return c-'A'+10;return -1;}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_writebytes(const char* path, const char* hexstr) {\n    FILE* f = fopen(path, \"wb\");\n    if (!f) return _K_ZERO;\n    const char* p = hexstr;\n    while (*p) {\n        if (*p == 'x' && p[1] && p[2]) {\n            int hi = _krhex(p[1]), lo = _krhex(p[2]);\n            if (hi >= 0 && lo >= 0) { unsigned char b = (unsigned char)(hi*16+lo); fwrite(&b,1,1,f); }\n            p += 3;\n        } else { p++; }\n    }\n    fclose(f);\n    return _K_ONE;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_shellrun(const char* cmd){int r=system(cmd);return kr_itoa(r);}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_deletefile(const char* path){remove(path);return _K_EMPTY;}\n"));
    r = kr_sbappend(r, ((char*)"static char* exec(const char* cmd){return kr_exec(cmd);}\n"));
    r = kr_sbappend(r, ((char*)"static char* shellRun(const char* cmd){return kr_shellrun(cmd);}\n"));
    r = kr_sbappend(r, ((char*)"static char* deleteFile(const char* path){return kr_deletefile(path);}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_input() {\n    char buf[4096];\n    if (!fgets(buf, sizeof(buf), stdin)) return _K_EMPTY;\n    int len = (int)strlen(buf);\n"));
    r = kr_sbappend(r, ((char*)"    if (len > 0 && buf[len-1] == '\\n') buf[--len] = 0;\n"));
    r = kr_sbappend(r, ((char*)"    if (len > 0 && buf[len-1] == '\\r') buf[--len] = 0;\n"));
    r = kr_sbappend(r, ((char*)"    return kr_str(buf);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_indexof(const char* s, const char* sub) {\n    const char* p = strstr(s, sub);\n    if (!p) return kr_itoa(-1);\n    return kr_itoa((int)(p - s));\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_replace(const char* s, const char* old, const char* rep) {\n    int slen = (int)strlen(s), olen = (int)strlen(old), rlen = (int)strlen(rep);\n    if (olen == 0) return kr_str(s);\n    int count = 0;\n    const char* p = s;\n    while ((p = strstr(p, old)) != 0) { count++; p += olen; }\n    int nlen = slen + count * (rlen - olen);\n    char* out = _alloc(nlen + 1);\n"));
    r = kr_sbappend(r, ((char*)"    char* dst = out;\n    p = s;\n    while (*p) {\n        if (strncmp(p, old, olen) == 0) {\n            memcpy(dst, rep, rlen); dst += rlen; p += olen;\n        } else { *dst++ = *p++; }\n    }\n    *dst = 0;\n"));
    r = kr_sbappend(r, ((char*)"    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_charat(const char* s, const char* idxs) {\n    int i = atoi(idxs);\n    int slen = (int)strlen(s);\n    if (i < 0 || i >= slen) return _K_EMPTY;\n    char buf[2] = {s[i], 0};\n    return kr_str(buf);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_trim(const char* s) {\n"));
    r = kr_sbappend(r, ((char*)"    while (*s == ' ' || *s == '\\t' || *s == '\\n' || *s == '\\r') s++;\n"));
    r = kr_sbappend(r, ((char*)"    int len = (int)strlen(s);\n"));
    r = kr_sbappend(r, ((char*)"    while (len > 0 && (s[len-1]==' '||s[len-1]=='\\t'||s[len-1]=='\\n'||s[len-1]=='\\r')) len--;\n"));
    r = kr_sbappend(r, ((char*)"    char* r = _alloc(len + 1);\n    memcpy(r, s, len);\n    r[len] = 0;\n    return r;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_tolower(const char* s) {\n    int len = (int)strlen(s);\n    char* out = _alloc(len + 1);\n    for (int i = 0; i <= len; i++)\n        out[i] = (s[i] >= 'A' && s[i] <= 'Z') ? s[i] + 32 : s[i];\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_toupper(const char* s) {\n    int len = (int)strlen(s);\n    char* out = _alloc(len + 1);\n    for (int i = 0; i <= len; i++)\n        out[i] = (s[i] >= 'a' && s[i] <= 'z') ? s[i] - 32 : s[i];\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_contains(const char* s, const char* sub) {\n    return strstr(s, sub) ? _K_ONE : _K_ZERO;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_endswith(const char* s, const char* suffix) {\n    int slen = (int)strlen(s), suflen = (int)strlen(suffix);\n    if (suflen > slen) return _K_ZERO;\n    return strcmp(s + slen - suflen, suffix) == 0 ? _K_ONE : _K_ZERO;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_abs(const char* a) { int v = atoi(a); return kr_itoa(v < 0 ? -v : v); }\nstatic char* kr_min(const char* a, const char* b) { return atoi(a) <= atoi(b) ? kr_str(a) : kr_str(b); }\nstatic char* kr_max(const char* a, const char* b) { return atoi(a) >= atoi(b) ? kr_str(a) : kr_str(b); }\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_exit(const char* code) { exit(atoi(code)); return _K_EMPTY; }\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_type(const char* s) {\n    if (kr_isnum(s)) return kr_str(\"number\");\n    return kr_str(\"string\");\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_append(const char* lst, const char* item) {\n    if (!*lst) return kr_str(item);\n    return kr_cat(kr_cat(lst, \",\"), item);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_join(const char* lst, const char* sep) {\n    int llen = (int)strlen(lst), slen = (int)strlen(sep);\n    int rlen = 0;\n    for (int i = 0; i < llen; i++) {\n        if (lst[i] == ',') rlen += slen; else rlen++;\n    }\n    char* out = _alloc(rlen + 1);\n    int j = 0;\n"));
    r = kr_sbappend(r, ((char*)"    for (int i = 0; i < llen; i++) {\n        if (lst[i] == ',') { memcpy(out+j, sep, slen); j += slen; }\n        else { out[j++] = lst[i]; }\n    }\n    out[j] = 0;\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_reverse(const char* lst) {\n    int cnt = 0;\n    const char* p = lst;\n    while (*p) { if (*p == ',') cnt++; p++; }\n    cnt++;\n    char* out = _K_EMPTY;\n    for (int i = cnt - 1; i >= 0; i--) {\n        char* item = kr_split(lst, kr_itoa(i));\n"));
    r = kr_sbappend(r, ((char*)"        if (i == cnt - 1) out = item;\n        else out = kr_cat(kr_cat(out, \",\"), item);\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static int _kr_cmp(const void* a, const void* b) {\n    const char* sa = *(const char**)a;\n    const char* sb = *(const char**)b;\n    if (kr_isnum(sa) && kr_isnum(sb)) return atoi(sa) - atoi(sb);\n    return strcmp(sa, sb);\n}\nstatic char* kr_sort(const char* lst) {\n    if (!*lst) return _K_EMPTY;\n"));
    r = kr_sbappend(r, ((char*)"    int cnt = 1;\n    const char* p = lst;\n    while (*p) { if (*p == ',') cnt++; p++; }\n    char** arr = (char**)_alloc(cnt * sizeof(char*));\n    for (int i = 0; i < cnt; i++) arr[i] = kr_split(lst, kr_itoa(i));\n    qsort(arr, cnt, sizeof(char*), _kr_cmp);\n    char* out = arr[0];\n    for (int i = 1; i < cnt; i++) out = kr_cat(kr_cat(out, \",\"), arr[i]);\n"));
    r = kr_sbappend(r, ((char*)"    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_keys(const char* map) {\n    if (!*map) return _K_EMPTY;\n    int cnt = 1;\n    const char* p = map;\n    while (*p) { if (*p == ',') cnt++; p++; }\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i += 2) {\n        char* k = kr_split(map, kr_itoa(i));\n"));
    r = kr_sbappend(r, ((char*)"        if (first) { out = k; first = 0; }\n        else out = kr_cat(kr_cat(out, \",\"), k);\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_values(const char* map) {\n    if (!*map) return _K_EMPTY;\n    int cnt = 1;\n    const char* p = map;\n    while (*p) { if (*p == ',') cnt++; p++; }\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 1; i < cnt; i += 2) {\n        char* v = kr_split(map, kr_itoa(i));\n"));
    r = kr_sbappend(r, ((char*)"        if (first) { out = v; first = 0; }\n        else out = kr_cat(kr_cat(out, \",\"), v);\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_haskey(const char* map, const char* key) {\n    if (!*map) return _K_ZERO;\n    int cnt = 1;\n    const char* p = map;\n    while (*p) { if (*p == ',') cnt++; p++; }\n    for (int i = 0; i < cnt; i += 2) {\n        if (strcmp(kr_split(map, kr_itoa(i)), key) == 0) return _K_ONE;\n    }\n"));
    r = kr_sbappend(r, ((char*)"    return _K_ZERO;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_remove(const char* lst, const char* item) {\n    if (!*lst) return _K_EMPTY;\n    int cnt = 1;\n    const char* p = lst;\n    while (*p) { if (*p == ',') cnt++; p++; }\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i++) {\n        char* el = kr_split(lst, kr_itoa(i));\n"));
    r = kr_sbappend(r, ((char*)"        if (strcmp(el, item) != 0) {\n            if (first) { out = el; first = 0; }\n            else out = kr_cat(kr_cat(out, \",\"), el);\n        }\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_repeat(const char* s, const char* ns) {\n    int n = atoi(ns);\n    if (n <= 0) return _K_EMPTY;\n    int slen = (int)strlen(s);\n    char* out = _alloc(slen * n + 1);\n    for (int i = 0; i < n; i++) memcpy(out + i * slen, s, slen);\n    out[slen * n] = 0;\n    return out;\n"));
    r = kr_sbappend(r, ((char*)"}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_format(const char* fmt, const char* arg) {\n    char buf[4096];\n    const char* p = strstr(fmt, \"{}\");\n    if (!p) return kr_str(fmt);\n    int pre = (int)(p - fmt);\n    int alen = (int)strlen(arg);\n    int postlen = (int)strlen(p + 2);\n    if (pre + alen + postlen >= 4096) return kr_str(fmt);\n"));
    r = kr_sbappend(r, ((char*)"    memcpy(buf, fmt, pre);\n    memcpy(buf + pre, arg, alen);\n    memcpy(buf + pre + alen, p + 2, postlen + 1);\n    return kr_str(buf);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_parseint(const char* s) {\n    const char* p = s;\n"));
    r = kr_sbappend(r, ((char*)"    while (*p == ' ' || *p == '\\t') p++;\n"));
    r = kr_sbappend(r, ((char*)"    if (!*p) return _K_ZERO;\n    return kr_itoa(atoi(p));\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_tostr(const char* s) { return kr_str(s); }\n\n"));
    r = kr_sbappend(r, ((char*)"static int kr_listlen(const char* s) {\n    if (!*s) return 0;\n    int cnt = 1;\n    while (*s) { if (*s == ',') cnt++; s++; }\n    return cnt;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_range(const char* starts, const char* ends) {\n    int s = atoi(starts), e = atoi(ends);\n    if (s >= e) return _K_EMPTY;\n    char* out = kr_itoa(s);\n    for (int i = s + 1; i < e; i++) out = kr_cat(kr_cat(out, \",\"), kr_itoa(i));\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_pow(const char* bs, const char* es) {\n    int b = atoi(bs), e = atoi(es), r = 1;\n    for (int i = 0; i < e; i++) r *= b;\n    return kr_itoa(r);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_sqrt(const char* s) {\n    int v = atoi(s);\n    if (v <= 0) return _K_ZERO;\n    int r = 0;\n    while ((r + 1) * (r + 1) <= v) r++;\n    return kr_itoa(r);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_sign(const char* s) {\n    int v = atoi(s);\n    if (v > 0) return _K_ONE;\n    if (v < 0) return kr_str(\"-1\");\n    return _K_ZERO;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_clamp(const char* vs, const char* los, const char* his) {\n    int v = atoi(vs), lo = atoi(los), hi = atoi(his);\n    if (v < lo) return kr_str(los);\n    if (v > hi) return kr_str(his);\n    return kr_str(vs);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_padleft(const char* s, const char* ws, const char* pad) {\n    int w = atoi(ws), slen = (int)strlen(s), plen = (int)strlen(pad);\n    if (slen >= w || plen == 0) return kr_str(s);\n    int need = w - slen;\n    char* out = _alloc(w + 1);\n    for (int i = 0; i < need; i++) out[i] = pad[i % plen];\n    memcpy(out + need, s, slen + 1);\n    return out;\n"));
    r = kr_sbappend(r, ((char*)"}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_padright(const char* s, const char* ws, const char* pad) {\n    int w = atoi(ws), slen = (int)strlen(s), plen = (int)strlen(pad);\n    if (slen >= w || plen == 0) return kr_str(s);\n    int need = w - slen;\n    char* out = _alloc(w + 1);\n    memcpy(out, s, slen);\n    for (int i = 0; i < need; i++) out[slen + i] = pad[i % plen];\n    out[w] = 0;\n"));
    r = kr_sbappend(r, ((char*)"    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_charcode(const char* s) {\n    if (!*s) return _K_ZERO;\n    return kr_itoa((unsigned char)s[0]);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_fromcharcode(const char* ns) {\n    unsigned int v = (unsigned int)atoi(ns);\n    char buf[5] = {0};\n    if (v < 0x80) { buf[0] = (char)v; }\n    else if (v < 0x800) {\n        buf[0] = (char)(0xC0 | (v >> 6));\n        buf[1] = (char)(0x80 | (v & 0x3F));\n    } else if (v < 0x10000) {\n        buf[0] = (char)(0xE0 | (v >> 12));\n        buf[1] = (char)(0x80 | ((v >> 6) & 0x3F));\n        buf[2] = (char)(0x80 | (v & 0x3F));\n    } else {\n        buf[0] = (char)(0xF0 | (v >> 18));\n        buf[1] = (char)(0x80 | ((v >> 12) & 0x3F));\n        buf[2] = (char)(0x80 | ((v >> 6) & 0x3F));\n        buf[3] = (char)(0x80 | (v & 0x3F));\n    }\n    return kr_str(buf);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_slice(const char* lst, const char* starts, const char* ends) {\n    int cnt = kr_listlen(lst);\n    int s = atoi(starts), e = atoi(ends);\n    if (s < 0) s = cnt + s;\n    if (e < 0) e = cnt + e;\n    if (s < 0) s = 0;\n    if (e > cnt) e = cnt;\n    if (s >= e) return _K_EMPTY;\n"));
    r = kr_sbappend(r, ((char*)"    char* out = kr_split(lst, kr_itoa(s));\n    for (int i = s + 1; i < e; i++)\n        out = kr_cat(kr_cat(out, \",\"), kr_split(lst, kr_itoa(i)));\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_length(const char* lst) {\n    return kr_itoa(kr_listlen(lst));\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_unique(const char* lst) {\n    if (!*lst) return _K_EMPTY;\n    int cnt = kr_listlen(lst);\n    char* out = _K_EMPTY; int oc = 0;\n    for (int i = 0; i < cnt; i++) {\n        char* item = kr_split(lst, kr_itoa(i));\n        int dup = 0;\n        for (int j = 0; j < oc; j++) {\n"));
    r = kr_sbappend(r, ((char*)"            if (strcmp(kr_split(out, kr_itoa(j)), item) == 0) { dup = 1; break; }\n        }\n        if (!dup) {\n            if (oc == 0) out = item; else out = kr_cat(kr_cat(out, \",\"), item);\n            oc++;\n        }\n    }\n    return out;\n"));
    r = kr_sbappend(r, ((char*)"}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_printerr(const char* s) {\n"));
    r = kr_sbappend(r, ((char*)"    fprintf(stderr, \"%s\\n\", s);\n"));
    r = kr_sbappend(r, ((char*)"    fflush(stderr);\n"));
    r = kr_sbappend(r, ((char*)"    return _K_EMPTY;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_readline(const char* prompt) {\n    if (*prompt) printf(\"%s\", prompt);\n    fflush(stdout);\n    char buf[4096];\n    if (!fgets(buf, sizeof(buf), stdin)) return _K_EMPTY;\n    int len = (int)strlen(buf);\n"));
    r = kr_sbappend(r, ((char*)"    if (len > 0 && buf[len-1] == '\\n') buf[--len] = 0;\n"));
    r = kr_sbappend(r, ((char*)"    if (len > 0 && buf[len-1] == '\\r') buf[--len] = 0;\n"));
    r = kr_sbappend(r, ((char*)"    return kr_str(buf);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_assert(const char* cond, const char* msg) {\n    if (!kr_truthy(cond)) {\n"));
    r = kr_sbappend(r, ((char*)"        fprintf(stderr, \"ASSERTION FAILED: %s\\n\", msg);\n"));
    r = kr_sbappend(r, ((char*)"        exit(1);\n    }\n    return _K_ONE;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_splitby(const char* s, const char* delim) {\n    int slen = (int)strlen(s), dlen = (int)strlen(delim);\n    if (dlen == 0 || slen == 0) return kr_str(s);\n    char* out = _K_EMPTY; int first = 1;\n    const char* p = s;\n    while (*p) {\n        const char* f = strstr(p, delim);\n        if (!f) { \n"));
    r = kr_sbappend(r, ((char*)"            if (first) out = kr_str(p); else out = kr_cat(kr_cat(out, \",\"), kr_str(p));\n            break;\n        }\n        int n = (int)(f - p);\n        char* chunk = _alloc(n + 1);\n        memcpy(chunk, p, n); chunk[n] = 0;\n        if (first) { out = chunk; first = 0; }\n        else out = kr_cat(kr_cat(out, \",\"), chunk);\n"));
    r = kr_sbappend(r, ((char*)"        p = f + dlen;\n        if (!*p) { out = kr_cat(kr_cat(out, \",\"), _K_EMPTY); break; }\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_listindexof(const char* lst, const char* item) {\n    if (!*lst) return kr_itoa(-1);\n    int cnt = kr_listlen(lst);\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(kr_split(lst, kr_itoa(i)), item) == 0) return kr_itoa(i);\n    }\n    return kr_itoa(-1);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_insertat(const char* lst, const char* idxs, const char* item) {\n    int idx = atoi(idxs);\n    int cnt = kr_listlen(lst);\n    if (!*lst && idx == 0) return kr_str(item);\n    if (idx < 0) idx = 0;\n    if (idx >= cnt) return kr_cat(kr_cat(lst, \",\"), item);\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i++) {\n"));
    r = kr_sbappend(r, ((char*)"        if (i == idx) {\n            if (first) { out = kr_str(item); first = 0; }\n            else out = kr_cat(kr_cat(out, \",\"), item);\n        }\n        char* el = kr_split(lst, kr_itoa(i));\n        if (first) { out = el; first = 0; }\n        else out = kr_cat(kr_cat(out, \",\"), el);\n    }\n"));
    r = kr_sbappend(r, ((char*)"    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_removeat(const char* lst, const char* idxs) {\n    int idx = atoi(idxs);\n    int cnt = kr_listlen(lst);\n    if (idx < 0 || idx >= cnt) return kr_str(lst);\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i++) {\n        if (i == idx) continue;\n        char* el = kr_split(lst, kr_itoa(i));\n"));
    r = kr_sbappend(r, ((char*)"        if (first) { out = el; first = 0; }\n        else out = kr_cat(kr_cat(out, \",\"), el);\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_replaceat(const char* lst, const char* idxs, const char* val) {\n    int idx = atoi(idxs);\n    int cnt = kr_listlen(lst);\n    if (idx < 0 || idx >= cnt) return kr_str(lst);\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i++) {\n        char* el = (i == idx) ? (char*)val : kr_split(lst, kr_itoa(i));\n        if (first) { out = el; first = 0; }\n"));
    r = kr_sbappend(r, ((char*)"        else out = kr_cat(kr_cat(out, \",\"), el);\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_fill(const char* ns, const char* val) {\n    int n = atoi(ns);\n    if (n <= 0) return _K_EMPTY;\n    char* out = kr_str(val);\n    for (int i = 1; i < n; i++) out = kr_cat(kr_cat(out, \",\"), val);\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_zip(const char* a, const char* b) {\n    int ac = kr_listlen(a), bc = kr_listlen(b);\n    int mc = ac < bc ? ac : bc;\n    if (!*a || !*b) return _K_EMPTY;\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < mc; i++) {\n        char* ai = kr_split(a, kr_itoa(i));\n        char* bi = kr_split(b, kr_itoa(i));\n"));
    r = kr_sbappend(r, ((char*)"        if (first) { out = kr_cat(kr_cat(ai, \",\"), bi); first = 0; }\n        else { out = kr_cat(kr_cat(out, \",\"), kr_cat(kr_cat(ai, \",\"), bi)); }\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_every(const char* lst, const char* val) {\n    if (!*lst) return _K_ONE;\n    int cnt = kr_listlen(lst);\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(kr_split(lst, kr_itoa(i)), val) != 0) return _K_ZERO;\n    }\n    return _K_ONE;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_some(const char* lst, const char* val) {\n    if (!*lst) return _K_ZERO;\n    int cnt = kr_listlen(lst);\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(kr_split(lst, kr_itoa(i)), val) == 0) return _K_ONE;\n    }\n    return _K_ZERO;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_countof(const char* lst, const char* item) {\n    if (!*lst) return _K_ZERO;\n    int cnt = kr_listlen(lst), c = 0;\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(kr_split(lst, kr_itoa(i)), item) == 0) c++;\n    }\n    return kr_itoa(c);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_sumlist(const char* lst) {\n    if (!*lst) return _K_ZERO;\n    int cnt = kr_listlen(lst), s = 0;\n    for (int i = 0; i < cnt; i++) s += atoi(kr_split(lst, kr_itoa(i)));\n    return kr_itoa(s);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_maxlist(const char* lst) {\n    if (!*lst) return _K_ZERO;\n    int cnt = kr_listlen(lst);\n    int m = atoi(kr_split(lst, _K_ZERO));\n    for (int i = 1; i < cnt; i++) {\n        int v = atoi(kr_split(lst, kr_itoa(i)));\n        if (v > m) m = v;\n    }\n"));
    r = kr_sbappend(r, ((char*)"    return kr_itoa(m);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_minlist(const char* lst) {\n    if (!*lst) return _K_ZERO;\n    int cnt = kr_listlen(lst);\n    int m = atoi(kr_split(lst, _K_ZERO));\n    for (int i = 1; i < cnt; i++) {\n        int v = atoi(kr_split(lst, kr_itoa(i)));\n        if (v < m) m = v;\n    }\n"));
    r = kr_sbappend(r, ((char*)"    return kr_itoa(m);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_hex(const char* s) {\n    int v = atoi(s);\n    char buf[32];\n    snprintf(buf, sizeof(buf), \"%x\", v < 0 ? -v : v);\n    if (v < 0) return kr_cat(\"-\", kr_str(buf));\n    return kr_str(buf);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_bin(const char* s) {\n    int v = atoi(s);\n    if (v == 0) return _K_ZERO;\n    int neg = v < 0; if (neg) v = -v;\n    char buf[64]; int i = 63; buf[i] = 0;\n    while (v > 0) { buf[--i] = '0' + (v & 1); v >>= 1; }\n    if (neg) return kr_cat(\"-\", kr_str(&buf[i]));\n    return kr_str(&buf[i]);\n"));
    r = kr_sbappend(r, ((char*)"}\n\n"));
    r = kr_sbappend(r, ((char*)"typedef struct EnvEntry { char* name; char* value; struct EnvEntry* prev; } EnvEntry;\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_envnew() { return (char*)0; }\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_envset(char* envp, const char* name, const char* val) {\n    EnvEntry* e = (EnvEntry*)_alloc(sizeof(EnvEntry));\n    e->name = (char*)name;\n    e->value = (char*)val;\n    e->prev = (EnvEntry*)envp;\n    return (char*)e;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_envget(char* envp, const char* name) {\n    EnvEntry* e = (EnvEntry*)envp;\n    while (e) {\n        if (strcmp(e->name, name) == 0) return e->value;\n        e = e->prev;\n    }\n    if (strcmp(name, \"__argOffset\") != 0)\n"));
    r = kr_sbappend(r, ((char*)"        fprintf(stderr, \"ERROR: undefined variable: %s\\n\", name);\n"));
    r = kr_sbappend(r, ((char*)"    return kr_str(\"\");\n}\n\n"));
    r = kr_sbappend(r, ((char*)"typedef struct ResultStruct { char tag; char* val; char* env; int pos; } ResultStruct;\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_makeresult(const char* tag, const char* val, const char* env, const char* pos) {\n    ResultStruct* r = (ResultStruct*)_alloc(sizeof(ResultStruct));\n    r->tag = tag[0];\n    r->val = (char*)val;\n    r->env = (char*)env;\n    r->pos = atoi(pos);\n    return (char*)r;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_getresulttag(const char* r) {\n    char buf[2] = {((ResultStruct*)r)->tag, 0};\n    return kr_str(buf);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_getresultval(const char* r) {\n    return ((ResultStruct*)r)->val;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_getresultenv(const char* r) {\n    return ((ResultStruct*)r)->env;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_getresultpos(const char* r) {\n    return kr_itoa(((ResultStruct*)r)->pos);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_istruthy(const char* s) {\n    if (!s || !*s || strcmp(s, \"0\") == 0 || strcmp(s, \"false\") == 0)\n        return _K_ZERO;\n    return _K_ONE;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"typedef struct { int cap; int len; } SBHdr;\n#define MAX_SBS 1048576\nstatic SBHdr* _sb_table[MAX_SBS];\nstatic int _sb_count = 0;\n\nstatic char* kr_sbnew() {\n    int initcap = 65536;\n    SBHdr* h = (SBHdr*)malloc(sizeof(SBHdr) + initcap);\n    h->cap = initcap;\n"));
    r = kr_sbappend(r, ((char*)"    h->len = 0;\n    ((char*)(h + 1))[0] = 0;\n    _sb_table[_sb_count] = h;\n    return kr_itoa(_sb_count++);\n}\n\nstatic char* kr_sbappend(const char* handle, const char* s) {\n    int idx = atoi(handle);\n    SBHdr* h = _sb_table[idx];\n"));
    r = kr_sbappend(r, ((char*)"    int slen = (int)strlen(s);\n    while (h->len + slen + 1 > h->cap) {\n        int newcap = h->cap * 2;\n        h = (SBHdr*)realloc(h, sizeof(SBHdr) + newcap);\n        h->cap = newcap;\n    }\n    memcpy((char*)(h + 1) + h->len, s, slen);\n    h->len += slen;\n"));
    r = kr_sbappend(r, ((char*)"    ((char*)(h + 1))[h->len] = 0;\n    _sb_table[idx] = h;\n    return kr_str(handle);\n}\n\nstatic char* kr_sbtostring(const char* handle) {\n    int idx = atoi(handle);\n    SBHdr* h = _sb_table[idx];\n    return (char*)(h + 1);\n"));
    r = kr_sbappend(r, ((char*)"}\n\n"));
    r = kr_sbappend(r, ((char*)"#include <setjmp.h>\n#define _KR_TRY_MAX 256\nstatic jmp_buf _kr_try_stack[_KR_TRY_MAX];\nstatic char*   _kr_err_stack[_KR_TRY_MAX];\nstatic int     _kr_try_depth = 0;\n\nstatic jmp_buf* _kr_pushtry() {\n    _kr_err_stack[_kr_try_depth] = _K_EMPTY;\n    return &_kr_try_stack[_kr_try_depth++];\n"));
    r = kr_sbappend(r, ((char*)"}\n\nstatic char* _kr_poptry() {\n    if (_kr_try_depth > 0) _kr_try_depth--;\n    return _kr_err_stack[_kr_try_depth];\n}\n\nstatic char* _kr_throw(const char* msg) {\n    if (_kr_try_depth > 0) {\n        _kr_err_stack[_kr_try_depth - 1] = (char*)msg;\n"));
    r = kr_sbappend(r, ((char*)"        longjmp(_kr_try_stack[_kr_try_depth - 1], 1);\n    }\n"));
    r = kr_sbappend(r, ((char*)"    fprintf(stderr, \"Uncaught exception: %s\\n\", msg);\n"));
    r = kr_sbappend(r, ((char*)"    exit(1);\n    return _K_EMPTY;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_strreverse(const char* s) {\n    int n = (int)strlen(s);\n    char* out = _alloc(n + 1);\n    for (int i = 0; i < n; i++) out[i] = s[n - 1 - i];\n    out[n] = 0;\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_words(const char* s) {\n    if (!*s) return _K_EMPTY;\n    char* out = _K_EMPTY; int first = 1;\n    const char* p = s;\n"));
    r = kr_sbappend(r, ((char*)"    while (*p == ' ' || *p == '\\t') p++;\n"));
    r = kr_sbappend(r, ((char*)"    const char* start = p;\n    while (1) {\n"));
    r = kr_sbappend(r, ((char*)"        if (*p == ' ' || *p == '\\t' || *p == 0) {\n"));
    r = kr_sbappend(r, ((char*)"            if (p > start) {\n                int n = (int)(p - start);\n                char* w = _alloc(n + 1);\n                memcpy(w, start, n); w[n] = 0;\n                if (first) { out = w; first = 0; }\n                else out = kr_cat(kr_cat(out, \",\"), w);\n            }\n            if (!*p) break;\n"));
    r = kr_sbappend(r, ((char*)"            while (*p == ' ' || *p == '\\t') p++;\n"));
    r = kr_sbappend(r, ((char*)"            start = p;\n        } else { p++; }\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_lines(const char* s) {\n    if (!*s) return _K_EMPTY;\n    char* out = _K_EMPTY; int first = 1;\n    const char* p = s, *start = s;\n    while (1) {\n"));
    r = kr_sbappend(r, ((char*)"        if (*p == '\\n' || *p == 0) {\n"));
    r = kr_sbappend(r, ((char*)"            int n = (int)(p - start);\n"));
    r = kr_sbappend(r, ((char*)"            if (n > 0 && start[n-1] == '\\r') n--;\n"));
    r = kr_sbappend(r, ((char*)"            char* ln = _alloc(n + 1);\n            memcpy(ln, start, n); ln[n] = 0;\n            if (first) { out = ln; first = 0; }\n            else out = kr_cat(kr_cat(out, \",\"), ln);\n            if (!*p) break;\n            start = p + 1;\n        }\n        p++;\n"));
    r = kr_sbappend(r, ((char*)"    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_first(const char* lst) { return kr_split(lst, _K_ZERO); }\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_last(const char* lst) {\n    int cnt = kr_listlen(lst);\n    if (cnt == 0) return _K_EMPTY;\n    return kr_split(lst, kr_itoa(cnt - 1));\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_head(const char* lst, const char* ns) {\n    int n = atoi(ns), cnt = kr_listlen(lst);\n    if (n <= 0 || !*lst) return _K_EMPTY;\n    if (n >= cnt) return kr_str(lst);\n    char* out = kr_split(lst, _K_ZERO);\n    for (int i = 1; i < n; i++) out = kr_cat(kr_cat(out, \",\"), kr_split(lst, kr_itoa(i)));\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_tail(const char* lst, const char* ns) {\n    int n = atoi(ns), cnt = kr_listlen(lst);\n    if (n <= 0 || !*lst) return _K_EMPTY;\n    if (n >= cnt) return kr_str(lst);\n    int start = cnt - n;\n    char* out = kr_split(lst, kr_itoa(start));\n    for (int i = start + 1; i < cnt; i++) out = kr_cat(kr_cat(out, \",\"), kr_split(lst, kr_itoa(i)));\n    return out;\n"));
    r = kr_sbappend(r, ((char*)"}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_lstrip(const char* s) {\n"));
    r = kr_sbappend(r, ((char*)"    while (*s == ' ' || *s == '\\t' || *s == '\\n' || *s == '\\r') s++;\n"));
    r = kr_sbappend(r, ((char*)"    return kr_str(s);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_rstrip(const char* s) {\n    int len = (int)strlen(s);\n"));
    r = kr_sbappend(r, ((char*)"    while (len > 0 && (s[len-1]==' '||s[len-1]=='\\t'||s[len-1]=='\\n'||s[len-1]=='\\r')) len--;\n"));
    r = kr_sbappend(r, ((char*)"    char* r = _alloc(len + 1);\n    memcpy(r, s, len); r[len] = 0;\n    return r;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_center(const char* s, const char* ws, const char* pad) {\n    int w = atoi(ws), slen = (int)strlen(s), plen = (int)strlen(pad);\n    if (slen >= w || plen == 0) return kr_str(s);\n    int total = w - slen;\n    int left = total / 2, right = total - left;\n    char* out = _alloc(w + 1);\n    for (int i = 0; i < left; i++) out[i] = pad[i % plen];\n    memcpy(out + left, s, slen);\n"));
    r = kr_sbappend(r, ((char*)"    for (int i = 0; i < right; i++) out[left + slen + i] = pad[i % plen];\n    out[w] = 0;\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_isalpha(const char* s) {\n    if (!*s) return _K_ZERO;\n    for (const char* p = s; *p; p++) if (!isalpha((unsigned char)*p)) return _K_ZERO;\n    return _K_ONE;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_isdigit(const char* s) {\n    if (!*s) return _K_ZERO;\n    for (const char* p = s; *p; p++) if (!isdigit((unsigned char)*p)) return _K_ZERO;\n    return _K_ONE;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_isspace(const char* s) {\n    if (!*s) return _K_ZERO;\n    for (const char* p = s; *p; p++) if (!isspace((unsigned char)*p)) return _K_ZERO;\n    return _K_ONE;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_random(const char* ns) {\n    int n = atoi(ns);\n    if (n <= 0) return _K_ZERO;\n    return kr_itoa(rand() % n);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_timestamp() {\n    return kr_itoa((int)time(NULL));\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_environ(const char* name) {\n    const char* v = getenv(name);\n    if (!v) return _K_EMPTY;\n    return kr_str(v);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_floor(const char* s) { return kr_itoa((int)atoi(s)); }\nstatic char* kr_ceil(const char* s)  { return kr_itoa((int)atoi(s)); }\nstatic char* kr_round(const char* s) { return kr_itoa((int)atoi(s)); }\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_throw(const char* msg) { return _kr_throw(msg); }\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_structnew() {\n    // 2 slots for count + up to 32 fields (name+val pairs)\n    char** s = (char**)_alloc(66 * sizeof(char*));\n    s[0] = _K_ZERO; // field count\n    return (char*)s;\n}\n\nstatic char* kr_setfield(char* obj, const char* name, const char* val) {\n    char** s = (char**)obj;\n"));
    r = kr_sbappend(r, ((char*)"    int cnt = atoi(s[0]);\n    // search for existing field\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(s[1 + i*2], name) == 0) {\n            s[2 + i*2] = (char*)val;\n            return obj;\n        }\n    }\n"));
    r = kr_sbappend(r, ((char*)"    // add new field\n    s[1 + cnt*2] = (char*)name;\n    s[2 + cnt*2] = (char*)val;\n    s[0] = kr_itoa(cnt + 1);\n    return obj;\n}\n\nstatic char* kr_getfield(char* obj, const char* name) {\n    if (!obj) return _K_EMPTY;\n"));
    r = kr_sbappend(r, ((char*)"    char** s = (char**)obj;\n    int cnt = atoi(s[0]);\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(s[1 + i*2], name) == 0) return s[2 + i*2];\n    }\n    return _K_EMPTY;\n}\n\nstatic char* kr_hasfield(char* obj, const char* name) {\n"));
    r = kr_sbappend(r, ((char*)"    if (!obj) return _K_ZERO;\n    char** s = (char**)obj;\n    int cnt = atoi(s[0]);\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(s[1 + i*2], name) == 0) return _K_ONE;\n    }\n    return _K_ZERO;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_structfields(char* obj) {\n    if (!obj) return _K_EMPTY;\n    char** s = (char**)obj;\n    int cnt = atoi(s[0]);\n    if (cnt == 0) return _K_EMPTY;\n    char* out = s[1];\n    for (int i = 1; i < cnt; i++) out = kr_cat(kr_cat(out, \",\"), s[1 + i*2]);\n    return out;\n"));
    r = kr_sbappend(r, ((char*)"}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_mapget(const char* map, const char* key) {\n    if (!*map) return _K_EMPTY;\n    int cnt = kr_listlen(map);\n    for (int i = 0; i < cnt - 1; i += 2) {\n        if (strcmp(kr_split(map, kr_itoa(i)), key) == 0)\n            return kr_split(map, kr_itoa(i + 1));\n    }\n    return _K_EMPTY;\n"));
    r = kr_sbappend(r, ((char*)"}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_mapset(const char* map, const char* key, const char* val) {\n    if (!*map) return kr_cat(kr_cat(kr_str(key), \",\"), val);\n    int cnt = kr_listlen(map);\n    char* out = _K_EMPTY; int first = 1; int found = 0;\n    for (int i = 0; i < cnt - 1; i += 2) {\n        char* k = kr_split(map, kr_itoa(i));\n        char* v = (strcmp(k, key) == 0) ? (char*)val : kr_split(map, kr_itoa(i+1));\n        if (strcmp(k, key) == 0) found = 1;\n"));
    r = kr_sbappend(r, ((char*)"        if (first) { out = kr_cat(k, kr_cat(\",\", v)); first = 0; }\n        else out = kr_cat(out, kr_cat(\",\", kr_cat(k, kr_cat(\",\", v))));\n    }\n    if (!found) {\n        if (first) out = kr_cat(kr_str(key), kr_cat(\",\", val));\n        else out = kr_cat(out, kr_cat(\",\", kr_cat(kr_str(key), kr_cat(\",\", val))));\n    }\n    return out;\n"));
    r = kr_sbappend(r, ((char*)"}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_mapdel(const char* map, const char* key) {\n    if (!*map) return _K_EMPTY;\n    int cnt = kr_listlen(map);\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt - 1; i += 2) {\n        char* k = kr_split(map, kr_itoa(i));\n        if (strcmp(k, key) != 0) {\n            char* v = kr_split(map, kr_itoa(i+1));\n"));
    r = kr_sbappend(r, ((char*)"            if (first) { out = kr_cat(k, kr_cat(\",\", v)); first = 0; }\n            else out = kr_cat(out, kr_cat(\",\", kr_cat(k, kr_cat(\",\", v))));\n        }\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_sprintf(const char* fmt, ...) {\n    char buf[4096];\n    va_list args;\n    va_start(args, fmt);\n    vsnprintf(buf, sizeof(buf), fmt, args);\n    va_end(args);\n    return kr_str(buf);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_strsplit(const char* s, const char* delim) {\n    return kr_splitby(s, delim);\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_listmap(const char* lst, const char* prefix, const char* suffix) {\n    if (!*lst) return _K_EMPTY;\n    int cnt = kr_listlen(lst);\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i++) {\n        char* item = kr_split(lst, kr_itoa(i));\n        char* mapped = kr_cat(kr_cat(kr_str(prefix), item), suffix);\n        if (first) { out = mapped; first = 0; }\n"));
    r = kr_sbappend(r, ((char*)"        else out = kr_cat(out, kr_cat(\",\", mapped));\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_listfilter(const char* lst, const char* val) {\n    if (!*lst) return _K_EMPTY;\n    int cnt = kr_listlen(lst), negate = 0;\n    const char* match = val;\n    if (val[0] == '!') { negate = 1; match = val + 1; }\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i++) {\n        char* item = kr_split(lst, kr_itoa(i));\n"));
    r = kr_sbappend(r, ((char*)"        int eq = (strcmp(item, match) == 0);\n        int keep = negate ? !eq : eq;\n        if (keep) {\n            if (first) { out = item; first = 0; }\n            else out = kr_cat(out, kr_cat(\",\", item));\n        }\n    }\n    return out;\n"));
    r = kr_sbappend(r, ((char*)"}\n\n"));
    r = kr_sbappend(r, ((char*)"#include <math.h>\nstatic char* kr_tofloat(const char* s) {\n    return s;\n}\n\nstatic char* kr_fadd(const char* a,const char* b){char buf[64];snprintf(buf,64,\"%g\",atof(a)+atof(b));return kr_str(buf);}\nstatic char* kr_fsub(const char* a,const char* b){char buf[64];snprintf(buf,64,\"%g\",atof(a)-atof(b));return kr_str(buf);}\nstatic char* kr_fmul(const char* a,const char* b){char buf[64];snprintf(buf,64,\"%g\",atof(a)*atof(b));return kr_str(buf);}\nstatic char* kr_fdiv(const char* a,const char* b){char buf[64];if(atof(b)==0.0)return kr_str(\"0\");snprintf(buf,64,\"%g\",atof(a)/atof(b));return kr_str(buf);}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_flt(const char* a,const char* b){return atof(a)<atof(b)?_K_ONE:_K_ZERO;}\nstatic char* kr_fgt(const char* a,const char* b){return atof(a)>atof(b)?_K_ONE:_K_ZERO;}\nstatic char* kr_feq(const char* a,const char* b){return atof(a)==atof(b)?_K_ONE:_K_ZERO;}\nstatic char* kr_fsqrt(const char* a) {\n    char buf[64]; snprintf(buf,64,\"%g\",sqrt(atof(a)));\n    return kr_str(buf);\n}\n\nstatic char* kr_ffloor(const char* a) {\n"));
    r = kr_sbappend(r, ((char*)"    char buf[64]; snprintf(buf,64,\"%.0f\",floor(atof(a)));\n    return kr_str(buf);\n}\n\nstatic char* kr_fceil(const char* a) {\n    char buf[64]; snprintf(buf,64,\"%.0f\",ceil(atof(a)));\n    return kr_str(buf);\n}\n\nstatic char* kr_fround(const char* a) {\n"));
    r = kr_sbappend(r, ((char*)"    char buf[64]; snprintf(buf,64,\"%.0f\",round(atof(a)));\n    return kr_str(buf);\n}\n\nstatic char* kr_fformat(const char* a,const char* prec){char fmt[32],buf[64];snprintf(fmt,32,\"%%.%sf\",prec);snprintf(buf,64,fmt,atof(a));return kr_str(buf);}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_bitand(const char* a,const char* b){return kr_itoa((int)((unsigned int)atoi(a)&(unsigned int)atoi(b)));}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_bitor(const char* a,const char* b){return kr_itoa((int)((unsigned int)atoi(a)|(unsigned int)atoi(b)));}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_bitxor(const char* a,const char* b){return kr_itoa((int)((unsigned int)atoi(a)^(unsigned int)atoi(b)));}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_bitnot(const char* a){return kr_itoa((int)(~(unsigned int)atoi(a)));}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_bitshl(const char* a,const char* b){return kr_itoa((int)((unsigned int)atoi(a)<<atoi(b)));}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_bitshr(const char* a,const char* b){return kr_itoa((int)((unsigned int)atoi(a)>>atoi(b)));}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_tolong(const char* s){char buf[32];snprintf(buf,32,\"%lld\",(long long)atoll(s));return kr_str(buf);}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_div64(const char* a,const char* b){if(atoll(b)==0)return kr_str(\"0\");char buf[32];snprintf(buf,32,\"%lld\",atoll(a)/atoll(b));return kr_str(buf);}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_mod64(const char* a,const char* b){if(atoll(b)==0)return kr_str(\"0\");char buf[32];long long r2=atoll(a)%atoll(b);snprintf(buf,32,\"%lld\",r2);return kr_str(buf);}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_mul64(const char* a,const char* b){char buf[32];snprintf(buf,32,\"%lld\",atoll(a)*atoll(b));return kr_str(buf);}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_add64(const char* a,const char* b){char buf[32];snprintf(buf,32,\"%lld\",atoll(a)+atoll(b));return kr_str(buf);}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_eqignorecase(const char* a,const char* b){return _stricmp(a,b)==0?kr_str(\"1\"):kr_str(\"0\");}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_handlevalid(const char* h){return (h!=NULL&&h!=(char*)(intptr_t)-1)?kr_str(\"1\"):kr_str(\"0\");}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_bufgetdword(char* buf){unsigned int v=*(unsigned int*)buf;return kr_itoa((int)v);}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_bufsetdword(char* buf,const char* vs){*(unsigned int*)buf=(unsigned int)atoi(vs);return _K_EMPTY;}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_bufgetword(char* buf){return kr_itoa((int)(*(unsigned short*)buf));}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_bufgetqword(char* buf){unsigned long long v=*(unsigned long long*)buf;char s[32];snprintf(s,32,\"%llu\",v);return kr_str(s);}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_bufgetdwordat(char* buf,const char* off){unsigned int v=*(unsigned int*)(buf+atoi(off));return kr_itoa((int)v);}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_bufgetqwordat(char* buf,const char* off){unsigned long long v=*(unsigned long long*)(buf+atoi(off));char s[32];snprintf(s,32,\"%llu\",v);return kr_str(s);}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_bufsetbyte(char* buf,const char* off,const char* val){buf[atoi(off)]=(unsigned char)atoi(val);return _K_EMPTY;}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_bufgetbyte(char* buf,const char* off){return kr_itoa((int)(unsigned char)buf[atoi(off)]);}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_bufsetdwordat(char* buf,const char* off,const char* val){*(unsigned int*)(buf+atoi(off))=(unsigned int)atoll(val);return _K_EMPTY;}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_bufsetqwordat(char* buf,const char* off,const char* val){*(unsigned long long*)(buf+atoi(off))=(unsigned long long)atoll(val);return _K_EMPTY;}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_bufgetwordat(char* buf,const char* off){unsigned short v=*(unsigned short*)(buf+atoi(off));return kr_itoa((int)v);}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_bufsetwordat(char* buf,const char* off,const char* val){*(unsigned short*)(buf+atoi(off))=(unsigned short)atoi(val);return _K_EMPTY;}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_handleget(char* buf){return *(char**)buf;}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_handleint(char* ptr){char s[32];snprintf(s,32,\"%d\",(int)(intptr_t)ptr);return kr_str(s);}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_ptrderef(char* ptr){return *(char**)ptr;}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_ptrindex(char* ptr,const char* n){return ((char**)ptr)[atoi(n)];}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_callptr1(char* fn,char* a0){return ((char*(*)(char*))(fn))(a0);}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_callptr2(char* fn,char* a0,char* a1){return ((char*(*)(char*,char*))(fn))(a0,a1);}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_callptr3(char* fn,char* a0,char* a1,char* a2){return ((char*(*)(char*,char*,char*))(fn))(a0,a1,a2);}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_callptr4(char* fn,char* a0,char* a1,char* a2,char* a3){return ((char*(*)(char*,char*,char*,char*))(fn))(a0,a1,a2,a3);}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_mkclosure(const char* fn,const char* env){"));
    r = kr_sbappend(r, ((char*)"int fl=strlen(fn),el=strlen(env);char* p=_alloc(fl+el+2);"));
    r = kr_sbappend(r, ((char*)"memcpy(p,fn,fl);p[fl]='|';memcpy(p+fl+1,env,el+1);return p;}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_closure_fn(const char* c){"));
    r = kr_sbappend(r, ((char*)"const char* p=strchr(c,'|');if(!p)return(char*)c;"));
    r = kr_sbappend(r, ((char*)"int n=p-c;char* r2=_alloc(n+1);memcpy(r2,c,n);r2[n]=0;return r2;}\n"));
    r = kr_sbappend(r, ((char*)"static char* kr_closure_env(const char* c){"));
    r = kr_sbappend(r, ((char*)"const char* p=strchr(c,'|');return p?(char*)(p+1):(char*)_K_EMPTY;}\n"));
    return kr_sbtostring(r);
}

char* scanModuleFunctions(char* tokens, char* ntoks) {
    char* i = ((char*)"0");
    char* bodyStart = ((char*)"0");
    char* hasWrapper = ((char*)"0");
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* tok = ((char*(*)(char*,char*))tokAt)(tokens, i);
        if (kr_truthy(kr_eq(tok, ((char*)"KW:go")))) {
            if (kr_truthy(kr_lt(kr_plus(i, ((char*)"2")), ntoks))) {
                if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1")))), ((char*)"ID")))) {
                    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"2"))), ((char*)"LBRACE")))) {
                        bodyStart = kr_plus(i, ((char*)"2"));
                        hasWrapper = ((char*)"1");
                    }
                }
            }
        }
        i = kr_plus(i, ((char*)"1"));
    }
    return ((char*(*)(char*,char*))scanFunctions)(tokens, ntoks);
}

char* compileImportedFunctions(char* tokens, char* ntoks, char* ftable) {
    char* sb = kr_sbnew();
    char* i = ((char*)"0");
    char* inWrapper = ((char*)"0");
    char* depth = ((char*)"0");
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* tok = ((char*(*)(char*,char*))tokAt)(tokens, i);
        if (kr_truthy(kr_eq(tok, ((char*)"KW:go")))) {
            if (kr_truthy(kr_lt(kr_plus(i, ((char*)"2")), ntoks))) {
                if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1")))), ((char*)"ID")))) {
                    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"2"))), ((char*)"LBRACE")))) {
                        i = kr_plus(i, ((char*)"3"));
                        inWrapper = ((char*)"1");
                    }
                }
            }
        }
        if (kr_truthy(kr_eq(tok, ((char*)"KW:jxt")))) {
            i = ((char*(*)(char*,char*))skipBlock)(tokens, kr_plus(i, ((char*)"1")));
        } else if (kr_truthy((kr_truthy(kr_eq(tok, ((char*)"KW:func"))) || kr_truthy(kr_eq(tok, ((char*)"KW:fn"))) ? kr_str("1") : kr_str("0")))) {
            char* fp = ((char*(*)(char*,char*,char*))compileFunc)(tokens, i, ntoks);
            sb = kr_sbappend(sb, ((char*(*)(char*))pairVal)(fp));
            i = ((char*(*)(char*))pairPos)(fp);
        } else if (kr_truthy(kr_eq(tok, ((char*)"KW:callback")))) {
            char* fp = ((char*(*)(char*,char*,char*))compileCallbackFunc)(tokens, kr_plus(i, ((char*)"1")), ntoks);
            sb = kr_sbappend(sb, ((char*(*)(char*))pairVal)(fp));
            i = ((char*(*)(char*))pairPos)(fp);
        } else if (kr_truthy(kr_eq(tok, ((char*)"KW:export")))) {
            i = kr_plus(i, ((char*)"1"));
        } else {
            i = kr_plus(i, ((char*)"1"));
        }
    }
    return kr_sbtostring(sb);
}

char* compileImportedForwardDecls(char* tokens, char* ntoks, char* ftable) {
    char* sb = kr_sbnew();
    char* i = ((char*)"0");
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* tok = ((char*(*)(char*,char*))tokAt)(tokens, i);
        if (kr_truthy((kr_truthy(kr_eq(tok, ((char*)"KW:func"))) || kr_truthy(kr_eq(tok, ((char*)"KW:fn"))) ? kr_str("1") : kr_str("0")))) {
            char* nameTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1")));
            char* fname = ((char*(*)(char*))tokVal)(nameTok);
            char* info = ((char*(*)(char*,char*))funcLookup)(ftable, fname);
            char* pc = ((char*(*)(char*))funcParamCount)(info);
            char* decl = kr_plus(kr_plus(((char*)"char* "), ((char*(*)(char*))cIdent)(fname)), ((char*)"("));
            char* pi = ((char*)"0");
            while (kr_truthy(kr_lt(pi, pc))) {
                if (kr_truthy(kr_gt(pi, ((char*)"0")))) {
                    decl = kr_plus(decl, ((char*)", "));
                }
                decl = kr_plus(decl, ((char*)"char*"));
                pi = kr_plus(pi, ((char*)"1"));
            }
            decl = kr_plus(decl, ((char*)");\n"));
            sb = kr_sbappend(sb, decl);
            char* fp = ((char*(*)(char*,char*))skipBlock)(tokens, kr_plus(kr_plus(i, ((char*)"3")), kr_mul(pc, ((char*)"2"))));
            i = fp;
        } else if (kr_truthy(kr_eq(tok, ((char*)"KW:export")))) {
            i = kr_plus(i, ((char*)"1"));
        } else {
            i = kr_plus(i, ((char*)"1"));
        }
    }
    return kr_sbtostring(sb);
}

char* irLabel(char* prefix, char* n) {
    return kr_plus(kr_plus(prefix, ((char*)"_")), n);
}

char* irExpr(char* tokens, char* pos, char* ntoks, char* lc, char* types) {
    return ((char*(*)(char*,char*,char*,char*,char*))irTernary)(tokens, pos, ntoks, lc, types);
}

char* irTernary(char* tokens, char* pos, char* ntoks, char* lc, char* types) {
    char* pair = ((char*(*)(char*,char*,char*,char*,char*))irOr)(tokens, pos, ntoks, lc, types);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    char* nlc = lc;
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"QUESTION")))) {
        char* trueLabel = ((char*(*)(char*,char*))irLabel)(((char*)"_tern_t"), p);
        char* endLabel = ((char*(*)(char*,char*))irLabel)(((char*)"_tern_e"), p);
        nlc = kr_plus(nlc, ((char*)"1"));
        char* tp = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, kr_plus(p, ((char*)"1")), ntoks, nlc, types);
        char* tcode = ((char*(*)(char*))pairVal)(tp);
        p = ((char*(*)(char*))pairPos)(tp);
        nlc = kr_plus(nlc, ((char*)"1"));
        p = kr_plus(p, ((char*)"1"));
        char* fp = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, p, ntoks, nlc, types);
        char* fcode = ((char*(*)(char*))pairVal)(fp);
        p = ((char*(*)(char*))pairPos)(fp);
        nlc = kr_plus(nlc, ((char*)"1"));
        char* out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, ((char*)"JUMPIFNOT ")), trueLabel), ((char*)"\n")), tcode), ((char*)"JUMP ")), endLabel), ((char*)"\n")), ((char*)"LABEL ")), trueLabel), ((char*)"\n")), fcode), ((char*)"LABEL ")), endLabel), ((char*)"\n"));
        return kr_plus(kr_plus(out, ((char*)",")), p);
    }
    return kr_plus(kr_plus(code, ((char*)",")), p);
}

char* irOr(char* tokens, char* pos, char* ntoks, char* lc, char* types) {
    char* pair = ((char*(*)(char*,char*,char*,char*,char*))irAnd)(tokens, pos, ntoks, lc, types);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    char* nlc = lc;
    while (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"OR")))) {
        char* shortLabel = ((char*(*)(char*,char*))irLabel)(((char*)"_or"), p);
        char* endLabel = ((char*(*)(char*,char*))irLabel)(((char*)"_orend"), p);
        nlc = kr_plus(nlc, ((char*)"1"));
        char* rp = ((char*(*)(char*,char*,char*,char*,char*))irAnd)(tokens, kr_plus(p, ((char*)"1")), ntoks, nlc, types);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, ((char*)"JUMPIF ")), shortLabel), ((char*)"\n")), rcode), ((char*)"JUMP ")), endLabel), ((char*)"\n")), ((char*)"LABEL ")), shortLabel), ((char*)"\n")), ((char*)"PUSH 1\n")), ((char*)"LABEL ")), endLabel), ((char*)"\n"));
    }
    return kr_plus(kr_plus(code, ((char*)",")), p);
}

char* irAnd(char* tokens, char* pos, char* ntoks, char* lc, char* types) {
    char* pair = ((char*(*)(char*,char*,char*,char*,char*))irEquality)(tokens, pos, ntoks, lc, types);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    char* nlc = lc;
    while (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"AND")))) {
        char* shortLabel = ((char*(*)(char*,char*))irLabel)(((char*)"_and"), p);
        char* endLabel = ((char*(*)(char*,char*))irLabel)(((char*)"_andend"), p);
        nlc = kr_plus(nlc, ((char*)"1"));
        char* rp = ((char*(*)(char*,char*,char*,char*,char*))irEquality)(tokens, kr_plus(p, ((char*)"1")), ntoks, nlc, types);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, ((char*)"JUMPIFNOT ")), shortLabel), ((char*)"\n")), rcode), ((char*)"JUMP ")), endLabel), ((char*)"\n")), ((char*)"LABEL ")), shortLabel), ((char*)"\n")), ((char*)"PUSH 0\n")), ((char*)"LABEL ")), endLabel), ((char*)"\n"));
    }
    return kr_plus(kr_plus(code, ((char*)",")), p);
}

char* irEquality(char* tokens, char* pos, char* ntoks, char* lc, char* types) {
    char* pair = ((char*(*)(char*,char*,char*,char*,char*))irRelational)(tokens, pos, ntoks, lc, types);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"EQ"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"NEQ"))) ? kr_str("1") : kr_str("0")))) {
        char* op = ((char*(*)(char*,char*))tokAt)(tokens, p);
        char* rp = ((char*(*)(char*,char*,char*,char*,char*))irRelational)(tokens, kr_plus(p, ((char*)"1")), ntoks, lc, types);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        if (kr_truthy(kr_eq(op, ((char*)"EQ")))) {
            code = kr_plus(kr_plus(code, rcode), ((char*)"EQ\n"));
        } else {
            code = kr_plus(kr_plus(code, rcode), ((char*)"NEQ\n"));
        }
    }
    return kr_plus(kr_plus(code, ((char*)",")), p);
}

char* irRelational(char* tokens, char* pos, char* ntoks, char* lc, char* types) {
    char* pair = ((char*(*)(char*,char*,char*,char*,char*))irAdditive)(tokens, pos, ntoks, lc, types);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"LT"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"GT"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"LTE"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"GTE"))) ? kr_str("1") : kr_str("0")))) {
        char* op = ((char*(*)(char*,char*))tokAt)(tokens, p);
        char* rp = ((char*(*)(char*,char*,char*,char*,char*))irAdditive)(tokens, kr_plus(p, ((char*)"1")), ntoks, lc, types);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        if (kr_truthy(kr_eq(op, ((char*)"LT")))) {
            code = kr_plus(kr_plus(code, rcode), ((char*)"LT\n"));
        }
        if (kr_truthy(kr_eq(op, ((char*)"GT")))) {
            code = kr_plus(kr_plus(code, rcode), ((char*)"GT\n"));
        }
        if (kr_truthy(kr_eq(op, ((char*)"LTE")))) {
            code = kr_plus(kr_plus(code, rcode), ((char*)"LTE\n"));
        }
        if (kr_truthy(kr_eq(op, ((char*)"GTE")))) {
            code = kr_plus(kr_plus(code, rcode), ((char*)"GTE\n"));
        }
    }
    return kr_plus(kr_plus(code, ((char*)",")), p);
}

char* irAdditive(char* tokens, char* pos, char* ntoks, char* lc, char* types) {
    char* pair = ((char*(*)(char*,char*,char*,char*,char*))irMultiplicative)(tokens, pos, ntoks, lc, types);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"PLUS"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"MINUS"))) ? kr_str("1") : kr_str("0")))) {
        char* op = ((char*(*)(char*,char*))tokAt)(tokens, p);
        char* rp = ((char*(*)(char*,char*,char*,char*,char*))irMultiplicative)(tokens, kr_plus(p, ((char*)"1")), ntoks, lc, types);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        if (kr_truthy(kr_eq(op, ((char*)"PLUS")))) {
            code = kr_plus(kr_plus(code, rcode), ((char*)"ADD\n"));
        } else {
            code = kr_plus(kr_plus(code, rcode), ((char*)"SUB\n"));
        }
    }
    return kr_plus(kr_plus(code, ((char*)",")), p);
}

char* irMultiplicative(char* tokens, char* pos, char* ntoks, char* lc, char* types) {
    char* pair = ((char*(*)(char*,char*,char*,char*,char*))irPow)(tokens, pos, ntoks, lc, types);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy((kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"STAR"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SLASH"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"MOD"))) ? kr_str("1") : kr_str("0")))) {
        char* op = ((char*(*)(char*,char*))tokAt)(tokens, p);
        char* rp = ((char*(*)(char*,char*,char*,char*,char*))irPow)(tokens, kr_plus(p, ((char*)"1")), ntoks, lc, types);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        if (kr_truthy(kr_eq(op, ((char*)"STAR")))) {
            code = kr_plus(kr_plus(code, rcode), ((char*)"MUL\n"));
        }
        if (kr_truthy(kr_eq(op, ((char*)"SLASH")))) {
            code = kr_plus(kr_plus(code, rcode), ((char*)"DIV\n"));
        }
        if (kr_truthy(kr_eq(op, ((char*)"MOD")))) {
            code = kr_plus(kr_plus(code, rcode), ((char*)"MOD\n"));
        }
    }
    return kr_plus(kr_plus(code, ((char*)",")), p);
}

char* irPow(char* tokens, char* pos, char* ntoks, char* lc, char* types) {
    char* pair = ((char*(*)(char*,char*,char*,char*,char*))irUnary)(tokens, pos, ntoks, lc, types);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"STARSTAR")))) {
        char* rp = ((char*(*)(char*,char*,char*,char*,char*))irPow)(tokens, kr_plus(p, ((char*)"1")), ntoks, lc, types);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        code = kr_plus(kr_plus(code, rcode), ((char*)"BUILTIN pow 2\n"));
    }
    return kr_plus(kr_plus(code, ((char*)",")), p);
}

char* irUnary(char* tokens, char* pos, char* ntoks, char* lc, char* types) {
    char* tok = ((char*(*)(char*,char*))tokAt)(tokens, pos);
    if (kr_truthy(kr_eq(tok, ((char*)"MINUS")))) {
        char* pair = ((char*(*)(char*,char*,char*,char*,char*))irUnary)(tokens, kr_plus(pos, ((char*)"1")), ntoks, lc, types);
        char* code = ((char*(*)(char*))pairVal)(pair);
        char* p = ((char*(*)(char*))pairPos)(pair);
        return kr_plus(kr_plus(code, ((char*)"NEG\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"BANG")))) {
        char* pair = ((char*(*)(char*,char*,char*,char*,char*))irUnary)(tokens, kr_plus(pos, ((char*)"1")), ntoks, lc, types);
        char* code = ((char*(*)(char*))pairVal)(pair);
        char* p = ((char*(*)(char*))pairPos)(pair);
        return kr_plus(kr_plus(code, ((char*)"NOT\n,")), p);
    }
    return ((char*(*)(char*,char*,char*,char*,char*))irPostfix)(tokens, pos, ntoks, lc, types);
}

char* irPostfix(char* tokens, char* pos, char* ntoks, char* lc, char* types) {
    char* pair = ((char*(*)(char*,char*,char*,char*,char*))irPrimary)(tokens, pos, ntoks, lc, types);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    char* accumOff = ((char*)"0");
    char* deferredType = ((char*)"");
    char* nLines0 = kr_linecount(code);
    if (kr_truthy(kr_gt(nLines0, ((char*)"0")))) {
        char* last0 = kr_getline(code, kr_sub(nLines0, ((char*)"1")));
        if (kr_truthy(kr_eq(kr_startswith(last0, ((char*)"; TYPE ")), ((char*)"1")))) {
            deferredType = kr_substr(last0, ((char*)"7"), kr_len(last0));
        }
    }
    while (kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"LBRACK"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"DOT"))) ? kr_str("1") : kr_str("0")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"LBRACK")))) {
            char* idxp = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, kr_plus(p, ((char*)"1")), ntoks, lc, types);
            char* idxcode = ((char*(*)(char*))pairVal)(idxp);
            p = kr_plus(((char*(*)(char*))pairPos)(idxp), ((char*)"1"));
            char* addAcc = ((char*)"");
            if (kr_truthy(kr_neq(accumOff, ((char*)"0")))) {
                addAcc = kr_plus(kr_plus(((char*)"PUSH "), accumOff), ((char*)"\nADD\n"));
            }
            if (kr_truthy(kr_eq(deferredType, ((char*)"*u8")))) {
                code = kr_plus(kr_plus(kr_plus(code, idxcode), addAcc), ((char*)"BUILTIN bufGetByte 2\n"));
            } else if (kr_truthy((kr_truthy(kr_eq(deferredType, ((char*)"*u16"))) || kr_truthy(kr_eq(deferredType, ((char*)"*i16"))) ? kr_str("1") : kr_str("0")))) {
                code = kr_plus(kr_plus(kr_plus(kr_plus(code, idxcode), ((char*)"PUSH 2\nMUL\n")), addAcc), ((char*)"BUILTIN bufGetWordAt 2\n"));
            } else if (kr_truthy((kr_truthy(kr_eq(deferredType, ((char*)"*u32"))) || kr_truthy(kr_eq(deferredType, ((char*)"*i32"))) ? kr_str("1") : kr_str("0")))) {
                code = kr_plus(kr_plus(kr_plus(kr_plus(code, idxcode), ((char*)"PUSH 4\nMUL\n")), addAcc), ((char*)"BUILTIN bufGetDwordAt 2\n"));
            } else if (kr_truthy((kr_truthy(kr_eq(deferredType, ((char*)"*u64"))) || kr_truthy(kr_eq(deferredType, ((char*)"*i64"))) ? kr_str("1") : kr_str("0")))) {
                code = kr_plus(kr_plus(kr_plus(kr_plus(code, idxcode), ((char*)"PUSH 8\nMUL\n")), addAcc), ((char*)"BUILTIN bufGetQwordAt 2\n"));
            } else {
                code = kr_plus(kr_plus(code, idxcode), ((char*)"INDEX\n"));
            }
            accumOff = ((char*)"0");
            deferredType = ((char*)"");
        } else {
            char* field = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, ((char*)"1"))));
            p = kr_plus(p, ((char*)"2"));
            char* didTypedField = ((char*)"0");
            if (kr_truthy(kr_eq(kr_startswith(deferredType, ((char*)"*")), ((char*)"1")))) {
                char* sname = kr_substr(deferredType, ((char*)"1"), kr_len(deferredType));
                char* info = ((char*(*)(char*,char*))irTypeOf)(types, kr_plus(kr_plus(sname, ((char*)".")), field));
                if (kr_truthy(kr_gt(kr_len(info), ((char*)"0")))) {
                    char* pipe1 = kr_indexof(info, ((char*)"|"));
                    char* offStr = kr_substr(info, ((char*)"0"), pipe1);
                    char* ftype = kr_substr(info, kr_plus(pipe1, ((char*)"1")), kr_len(info));
                    char* fOff = kr_toint(offStr);
                    if (kr_truthy(kr_eq(kr_startswith(ftype, ((char*)"*")), ((char*)"1")))) {
                        accumOff = kr_plus(accumOff, fOff);
                        deferredType = ftype;
                        didTypedField = ((char*)"1");
                    } else {
                        char* fop = ((char*)"");
                        if (kr_truthy((kr_truthy(kr_eq(ftype, ((char*)"u8"))) || kr_truthy(kr_eq(ftype, ((char*)"i8"))) ? kr_str("1") : kr_str("0")))) {
                            fop = ((char*)"BUILTIN bufGetByte 2\n");
                        }
                        if (kr_truthy((kr_truthy(kr_eq(ftype, ((char*)"u16"))) || kr_truthy(kr_eq(ftype, ((char*)"i16"))) ? kr_str("1") : kr_str("0")))) {
                            fop = ((char*)"BUILTIN bufGetWordAt 2\n");
                        }
                        if (kr_truthy((kr_truthy(kr_eq(ftype, ((char*)"u32"))) || kr_truthy(kr_eq(ftype, ((char*)"i32"))) ? kr_str("1") : kr_str("0")))) {
                            fop = ((char*)"BUILTIN bufGetDwordAt 2\n");
                        }
                        if (kr_truthy((kr_truthy(kr_eq(ftype, ((char*)"u64"))) || kr_truthy(kr_eq(ftype, ((char*)"i64"))) ? kr_str("1") : kr_str("0")))) {
                            fop = ((char*)"BUILTIN bufGetQwordAt 2\n");
                        }
                        if (kr_truthy(kr_gt(kr_len(fop), ((char*)"0")))) {
                            code = kr_plus(kr_plus(kr_plus(kr_plus(code, ((char*)"PUSH ")), kr_plus(accumOff, fOff)), ((char*)"\n")), fop);
                            didTypedField = ((char*)"1");
                            accumOff = ((char*)"0");
                            deferredType = ((char*)"");
                        }
                    }
                }
            }
            if (kr_truthy(kr_eq(didTypedField, ((char*)"0")))) {
                code = kr_plus(kr_plus(kr_plus(code, ((char*)"GETFIELD ")), field), ((char*)"\n"));
                deferredType = ((char*)"");
                accumOff = ((char*)"0");
            }
        }
    }
    return kr_plus(kr_plus(code, ((char*)",")), p);
}

char* irPrimary(char* tokens, char* pos, char* ntoks, char* lc, char* types) {
    char* tok = ((char*(*)(char*,char*))tokAt)(tokens, pos);
    char* tt = ((char*(*)(char*))tokType)(tok);
    char* tv = ((char*(*)(char*))tokVal)(tok);
    if (kr_truthy(kr_eq(tt, ((char*)"INT")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"PUSH "), tv), ((char*)"\n,")), kr_plus(pos, ((char*)"1")));
    }
    if (kr_truthy(kr_eq(tt, ((char*)"STR")))) {
        return kr_plus(kr_plus(kr_plus(((char*)"PUSH \""), tv), ((char*)"\"\n,")), kr_plus(pos, ((char*)"1")));
    }
    if (kr_truthy(kr_eq(tt, ((char*)"INTERP")))) {
        return kr_plus(kr_plus(((char*(*)(char*,char*,char*,char*))irInterpToIR)(tv, pos, lc, types), ((char*)",")), kr_plus(pos, ((char*)"1")));
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:true")))) {
        return kr_plus(((char*)"PUSH \"true\"\n,"), kr_plus(pos, ((char*)"1")));
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:false")))) {
        return kr_plus(((char*)"PUSH \"false\"\n,"), kr_plus(pos, ((char*)"1")));
    }
    if (kr_truthy(kr_eq(tok, ((char*)"LPAREN")))) {
        char* pair = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, kr_plus(pos, ((char*)"1")), ntoks, lc, types);
        char* code = ((char*(*)(char*))pairVal)(pair);
        char* p = ((char*(*)(char*))pairPos)(pair);
        return kr_plus(kr_plus(code, ((char*)",")), kr_plus(p, ((char*)"1")));
    }
    if (kr_truthy(kr_eq(tok, ((char*)"LBRACK")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))irListLiteralIR)(tokens, pos, ntoks, lc, types);
    }
    if (kr_truthy((kr_truthy((kr_truthy(kr_eq(tok, ((char*)"KW:func"))) || kr_truthy(kr_eq(tok, ((char*)"KW:fn"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1"))), ((char*)"LPAREN"))) ? kr_str("1") : kr_str("0")))) {
        char* lp = kr_plus(pos, ((char*)"2"));
        char* lpc = ((char*)"");
        while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, lp), ((char*)"RPAREN")))) {
            char* lpt = ((char*(*)(char*,char*))tokAt)(tokens, lp);
            if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(lpt), ((char*)"ID")))) {
                if (kr_truthy(kr_gt(kr_len(lpc), ((char*)"0")))) {
                    lpc = kr_plus(lpc, ((char*)","));
                }
                lpc = kr_plus(lpc, ((char*(*)(char*))tokVal)(lpt));
            }
            lp = kr_plus(lp, ((char*)"1"));
        }
        lp = kr_plus(lp, ((char*)"1"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, lp), ((char*)"ARROW")))) {
            lp = kr_plus(lp, ((char*)"2"));
        }
        char* lpEnd = ((char*(*)(char*,char*))skipBlock)(tokens, lp);
        char* lFree = ((char*(*)(char*,char*,char*,char*))findFreeVars)(tokens, lp, lpEnd, lpc);
        char* envCode = ((char*)"BUILTIN envNew 0\n");
        if (kr_truthy(kr_gt(kr_len(lFree), ((char*)"0")))) {
            char* lfc = kr_count(lFree);
            char* lfi = ((char*)"0");
            while (kr_truthy(kr_lt(lfi, lfc))) {
                char* lfname = kr_split(lFree, lfi);
                envCode = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(envCode, ((char*)"PUSH \"")), lfname), ((char*)"\"\n")), ((char*)"LOAD ")), lfname), ((char*)"\n")), ((char*)"BUILTIN envSet 3\n"));
                lfi = kr_plus(lfi, ((char*)"1"));
            }
        }
        envCode = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(envCode, ((char*)"PUSH \"__fp__\"\n")), ((char*)"FUNCPTR _krlam")), pos), ((char*)"\n")), ((char*)"BUILTIN envSet 3\n"));
        return kr_plus(kr_plus(envCode, ((char*)",")), lpEnd);
    }
    if (kr_truthy(kr_eq(tt, ((char*)"ID")))) {
        char* nextTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1")));
        if (kr_truthy(kr_eq(nextTok, ((char*)"LPAREN")))) {
            return ((char*(*)(char*,char*,char*,char*,char*))irCall)(tokens, pos, ntoks, lc, types);
        }
        char* firstChar = kr_idx(tv, kr_atoi(((char*)"0")));
        if (kr_truthy(kr_eq(nextTok, ((char*)"LBRACE")))) {
            if (kr_truthy((kr_truthy(kr_gte(firstChar, ((char*)"A"))) && kr_truthy(kr_lte(firstChar, ((char*)"Z"))) ? kr_str("1") : kr_str("0")))) {
                char* inner1 = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"2")));
                char* inner2 = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"3")));
                if (kr_truthy(kr_eq(kr_startswith(inner1, ((char*)"ID:")), ((char*)"1")))) {
                    if (kr_truthy(kr_eq(inner2, ((char*)"COLON")))) {
                        return ((char*(*)(char*,char*,char*,char*,char*))irStructLiteralIR)(tokens, pos, ntoks, lc, types);
                    }
                }
            }
        }
        char* varType = ((char*(*)(char*,char*))irTypeOf)(types, tv);
        if (kr_truthy(kr_gt(kr_len(varType), ((char*)"0")))) {
            if (kr_truthy(kr_eq(kr_startswith(varType, ((char*)"__cap__:")), ((char*)"1")))) {
                char* capName = kr_substr(varType, ((char*)"8"), kr_len(varType));
                return kr_plus(kr_plus(kr_plus(((char*)"LOAD __env\nPUSH \""), capName), ((char*)"\"\nBUILTIN envGet 2\n,")), kr_plus(pos, ((char*)"1")));
            }
            return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"LOAD "), tv), ((char*)"\n; TYPE ")), varType), ((char*)"\n,")), kr_plus(pos, ((char*)"1")));
        }
        return kr_plus(kr_plus(kr_plus(((char*)"LOAD "), tv), ((char*)"\n,")), kr_plus(pos, ((char*)"1")));
    }
    return kr_plus(((char*)"PUSH \"\"\n,"), kr_plus(pos, ((char*)"1")));
}

char* irInterpToIR(char* s, char* pos, char* lc, char* types) {
    char* code = ((char*)"");
    char* i = ((char*)"0");
    char* seg = ((char*)"");
    char* parts = ((char*)"0");
    while (kr_truthy(kr_lt(i, kr_len(s)))) {
        if (kr_truthy(kr_eq(kr_idx(s, kr_atoi(i)), ((char*)"{")))) {
            if (kr_truthy(kr_gt(kr_len(seg), ((char*)"0")))) {
                code = kr_plus(kr_plus(kr_plus(code, ((char*)"PUSH \"")), seg), ((char*)"\"\n"));
                if (kr_truthy(kr_gt(parts, ((char*)"0")))) {
                    code = kr_plus(code, ((char*)"CAT\n"));
                }
                parts = kr_plus(parts, ((char*)"1"));
                seg = ((char*)"");
            }
            i = kr_plus(i, ((char*)"1"));
            char* expr = ((char*)"");
            while (kr_truthy((kr_truthy(kr_lt(i, kr_len(s))) && kr_truthy(kr_neq(kr_idx(s, kr_atoi(i)), ((char*)"}"))) ? kr_str("1") : kr_str("0")))) {
                expr = kr_plus(expr, kr_idx(s, kr_atoi(i)));
                i = kr_plus(i, ((char*)"1"));
            }
            i = kr_plus(i, ((char*)"1"));
            char* exprToks = ((char*(*)(char*))tokenize)(expr);
            char* exprNtoks = kr_linecount(exprToks);
            if (kr_truthy(kr_gt(exprNtoks, ((char*)"0")))) {
                char* ep = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(exprToks, ((char*)"0"), exprNtoks, lc, types);
                code = kr_plus(code, ((char*(*)(char*))pairVal)(ep));
            } else {
                code = kr_plus(code, ((char*)"PUSH \"\"\n"));
            }
            if (kr_truthy(kr_gt(parts, ((char*)"0")))) {
                code = kr_plus(code, ((char*)"CAT\n"));
            }
            parts = kr_plus(parts, ((char*)"1"));
        } else {
            seg = kr_plus(seg, kr_idx(s, kr_atoi(i)));
            i = kr_plus(i, ((char*)"1"));
        }
    }
    if (kr_truthy(kr_gt(kr_len(seg), ((char*)"0")))) {
        code = kr_plus(kr_plus(kr_plus(code, ((char*)"PUSH \"")), seg), ((char*)"\"\n"));
        if (kr_truthy(kr_gt(parts, ((char*)"0")))) {
            code = kr_plus(code, ((char*)"CAT\n"));
        }
        parts = kr_plus(parts, ((char*)"1"));
    }
    if (kr_truthy(kr_eq(parts, ((char*)"0")))) {
        return ((char*)"PUSH \"\"\n");
    }
    return code;
}

char* irListLiteralIR(char* tokens, char* pos, char* ntoks, char* lc, char* types) {
    char* p = kr_plus(pos, ((char*)"1"));
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RBRACK")))) {
        return kr_plus(((char*)"PUSH \"\"\n,"), kr_plus(p, ((char*)"1")));
    }
    char* code = ((char*)"");
    char* ec = ((char*)"0");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RBRACK")))) {
        if (kr_truthy(kr_gt(ec, ((char*)"0")))) {
            p = kr_plus(p, ((char*)"1"));
        }
        char* ep = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, p, ntoks, lc, types);
        char* ecode = ((char*(*)(char*))pairVal)(ep);
        p = ((char*(*)(char*))pairPos)(ep);
        if (kr_truthy(kr_gt(ec, ((char*)"0")))) {
            code = kr_plus(kr_plus(code, ecode), ((char*)"PUSH \",\"\nCAT\nCAT\n"));
        } else {
            code = ecode;
        }
        ec = kr_plus(ec, ((char*)"1"));
    }
    return kr_plus(kr_plus(code, ((char*)",")), kr_plus(p, ((char*)"1")));
}

char* irStructLiteralIR(char* tokens, char* pos, char* ntoks, char* lc, char* types) {
    char* name = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* p = kr_plus(pos, ((char*)"2"));
    char* code = ((char*)"STRUCTNEW\n");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RBRACE")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, p)), ((char*)"ID")))) {
            char* fname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, p));
            p = kr_plus(p, ((char*)"2"));
            char* ep = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, p, ntoks, lc, types);
            char* ecode = ((char*(*)(char*))pairVal)(ep);
            p = ((char*(*)(char*))pairPos)(ep);
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"COMMA")))) {
                p = kr_plus(p, ((char*)"1"));
            }
            code = kr_plus(kr_plus(kr_plus(kr_plus(code, ecode), ((char*)"SETFIELD ")), fname), ((char*)"\n"));
        } else {
            p = kr_plus(p, ((char*)"1"));
        }
    }
    return kr_plus(kr_plus(code, ((char*)",")), kr_plus(p, ((char*)"1")));
}

char* irCall(char* tokens, char* pos, char* ntoks, char* lc, char* types) {
    char* fname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    if (kr_truthy(kr_eq(fname, ((char*)"funcptr")))) {
        char* argTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"2")));
        if (kr_truthy((kr_truthy(kr_eq(((char*(*)(char*))tokType)(argTok), ((char*)"ID"))) && kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"3"))), ((char*)"RPAREN"))) ? kr_str("1") : kr_str("0")))) {
            char* funcName = ((char*(*)(char*))tokVal)(argTok);
            return kr_plus(kr_plus(kr_plus(((char*)"FUNCPTR "), funcName), ((char*)"\n,")), kr_plus(pos, ((char*)"4")));
        }
    }
    char* p = kr_plus(pos, ((char*)"2"));
    char* code = ((char*)"");
    char* argc = ((char*)"0");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RPAREN")))) {
        if (kr_truthy(kr_gt(argc, ((char*)"0")))) {
            p = kr_plus(p, ((char*)"1"));
        }
        char* ap = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, p, ntoks, lc, types);
        code = kr_plus(code, ((char*(*)(char*))pairVal)(ap));
        p = ((char*(*)(char*))pairPos)(ap);
        argc = kr_plus(argc, ((char*)"1"));
    }
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))irTypeOf)(types, fname), ((char*)"fp")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"LOAD "), fname), ((char*)"\n")), code), ((char*)"BUILTIN callPtr ")), kr_plus(argc, ((char*)"1"))), ((char*)"\n,")), kr_plus(p, ((char*)"1")));
    }
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))irTypeOf)(types, fname), ((char*)"closure")))) {
        char* fpExtract = kr_plus(kr_plus(((char*)"LOAD "), fname), ((char*)"\nPUSH \"__fp__\"\nBUILTIN envGet 2\n"));
        char* envPush = kr_plus(kr_plus(((char*)"LOAD "), fname), ((char*)"\n"));
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(fpExtract, envPush), code), ((char*)"BUILTIN callPtr ")), kr_plus(argc, ((char*)"2"))), ((char*)"\n,")), kr_plus(p, ((char*)"1")));
    }
    char* builtins = ((char*)"print,kp,printErr,readLine,input,readFile,writeFile,arg,argCount,len,count,substring,charAt,indexOf,contains,startsWith,endsWith,replace,trim,lstrip,rstrip,center,toLower,toUpper,repeat,padLeft,padRight,charCode,fromCharCode,splitBy,format,strReverse,isAlpha,isDigit,isSpace,toInt,parseInt,abs,min,max,pow,sqrt,sign,clamp,hex,bin,floor,ceil,round,split,length,first,last,head,tail,append,join,reverse,sort,unique,fill,zip,slice,listIndexOf,every,some,countOf,sumList,maxList,minList,range,words,lines,keys,values,hasKey,structNew,getField,setField,hasField,structFields,random,timestamp,environ,exit,assert,type,isTruthy,toStr,throw,mapHas,mapGet,mapSet,mapDel,exec,shellRun,fadd,fsub,fmul,fdiv,fsqrt,ffloor,fceil,fround,fformat,flt,fgt,feq,sbNew,sbAppend,sbToString,bufNew,bufStr,bufGetDword,bufSetDword,bufGetWord,bufGetQword,bufGetDwordAt,bufGetQwordAt,bufSetByte,bufGetByte,bufSetDwordAt,bufSetQwordAt,bufGetWordAt,bufSetWordAt,bufGetWordAtBE,bufGetDwordAtBE,bufGetQwordAtBE,handleOut,handleGet,handleInt,toHandle,ptrDeref,ptrIndex,callPtr,getLine,lineCount,envNew,envSet,envGet,makeResult,getResultTag,getResultVal,getResultEnv,getResultPos,gcAllocated,gcAllocCount,gcShadowCount,gcShadowPop,gcShadowPush,gcWalkAllocs,gcMark,gcSweep,gcFreelistCount,rdtsc,pause,mfence,lfence,sfence,gcLimit,gcSetLimit,gcCollect,gcReset,gcCheckpoint,gcRestore,gcSlabCount,gcSlabBytes,sockMake,sockBind,sockListen,sockAccept,sockRecv,sockSend,sockClose,sockRecvStr");
    if (kr_truthy(kr_contains(kr_plus(kr_plus(((char*)","), builtins), ((char*)",")), kr_plus(kr_plus(((char*)","), fname), ((char*)","))))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, ((char*)"BUILTIN ")), fname), ((char*)" ")), argc), ((char*)"\n,")), kr_plus(p, ((char*)"1")));
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, ((char*)"CALL ")), fname), ((char*)" ")), argc), ((char*)"\n,")), kr_plus(p, ((char*)"1")));
}

char* irStmt(char* tokens, char* pos, char* ntoks, char* lc, char* inFunc, char* types) {
    char* tok = ((char*(*)(char*,char*))tokAt)(tokens, pos);
    char* tt = ((char*(*)(char*))tokType)(tok);
    if (kr_truthy((kr_truthy(kr_eq(tok, ((char*)"KW:let"))) || kr_truthy(kr_eq(tok, ((char*)"KW:const"))) ? kr_str("1") : kr_str("0")))) {
        return ((char*(*)(char*,char*,char*,char*,char*,char*))irLetIR)(tokens, kr_plus(pos, ((char*)"1")), ntoks, lc, inFunc, types);
    }
    if (kr_truthy((kr_truthy(kr_eq(tok, ((char*)"KW:emit"))) || kr_truthy(kr_eq(tok, ((char*)"KW:return"))) ? kr_str("1") : kr_str("0")))) {
        char* pair = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, kr_plus(pos, ((char*)"1")), ntoks, lc, types);
        char* code = ((char*(*)(char*))pairVal)(pair);
        char* p = ((char*(*)(char*))pairPos)(pair);
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
            p = kr_plus(p, ((char*)"1"));
        }
        char* restoreCode = ((char*)"");
        if (kr_truthy(kr_eq(inFunc, ((char*)"1")))) {
            restoreCode = ((char*)"BUILTIN gcShadowCount 0\nLOAD __sh_save\nSUB\nBUILTIN gcShadowPop 1\nPOP\n");
        }
        return kr_plus(kr_plus(kr_plus(code, restoreCode), ((char*)"RETURN\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:if")))) {
        return ((char*(*)(char*,char*,char*,char*,char*,char*))irIfIR)(tokens, kr_plus(pos, ((char*)"1")), ntoks, lc, inFunc, types);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:while")))) {
        return ((char*(*)(char*,char*,char*,char*,char*,char*))irWhileIR)(tokens, kr_plus(pos, ((char*)"1")), ntoks, lc, inFunc, types);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:for")))) {
        return ((char*(*)(char*,char*,char*,char*,char*,char*))irForIR)(tokens, kr_plus(pos, ((char*)"1")), ntoks, lc, inFunc, types);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:match")))) {
        return ((char*(*)(char*,char*,char*,char*,char*,char*))irMatchIR)(tokens, kr_plus(pos, ((char*)"1")), ntoks, lc, inFunc, types);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:break")))) {
        char* p = kr_plus(pos, ((char*)"1"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
            p = kr_plus(p, ((char*)"1"));
        }
        return kr_plus(((char*)"BREAK\n,"), p);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:continue")))) {
        char* p = kr_plus(pos, ((char*)"1"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
            p = kr_plus(p, ((char*)"1"));
        }
        return kr_plus(((char*)"CONTINUE\n,"), p);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:throw")))) {
        char* pair = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, kr_plus(pos, ((char*)"1")), ntoks, lc, types);
        char* code = ((char*(*)(char*))pairVal)(pair);
        char* p = ((char*(*)(char*))pairPos)(pair);
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
            p = kr_plus(p, ((char*)"1"));
        }
        return kr_plus(kr_plus(code, ((char*)"THROW\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, ((char*)"KW:try")))) {
        return ((char*(*)(char*,char*,char*,char*,char*,char*))irTryIR)(tokens, kr_plus(pos, ((char*)"1")), ntoks, lc, inFunc, types);
    }
    if (kr_truthy((kr_truthy((kr_truthy(kr_eq(tok, ((char*)"KW:func"))) || kr_truthy(kr_eq(tok, ((char*)"KW:fn"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1")))), ((char*)"ID"))) ? kr_str("1") : kr_str("0")))) {
        char* p = kr_plus(pos, ((char*)"2"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"LPAREN")))) {
            char* pdepth = ((char*)"1");
            p = kr_plus(p, ((char*)"1"));
            while (kr_truthy((kr_truthy(kr_lt(p, ntoks)) && kr_truthy(kr_gt(pdepth, ((char*)"0"))) ? kr_str("1") : kr_str("0")))) {
                char* tt2 = ((char*(*)(char*,char*))tokAt)(tokens, p);
                if (kr_truthy(kr_eq(tt2, ((char*)"LPAREN")))) {
                    pdepth = kr_plus(pdepth, ((char*)"1"));
                }
                if (kr_truthy(kr_eq(tt2, ((char*)"RPAREN")))) {
                    pdepth = kr_sub(pdepth, ((char*)"1"));
                }
                p = kr_plus(p, ((char*)"1"));
            }
        }
        while (kr_truthy((kr_truthy(kr_lt(p, ntoks)) && kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"LBRACE"))) ? kr_str("1") : kr_str("0")))) {
            p = kr_plus(p, ((char*)"1"));
        }
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"LBRACE")))) {
            char* bdepth = ((char*)"1");
            p = kr_plus(p, ((char*)"1"));
            while (kr_truthy((kr_truthy(kr_lt(p, ntoks)) && kr_truthy(kr_gt(bdepth, ((char*)"0"))) ? kr_str("1") : kr_str("0")))) {
                char* tt3 = ((char*(*)(char*,char*))tokAt)(tokens, p);
                if (kr_truthy(kr_eq(tt3, ((char*)"LBRACE")))) {
                    bdepth = kr_plus(bdepth, ((char*)"1"));
                }
                if (kr_truthy(kr_eq(tt3, ((char*)"RBRACE")))) {
                    bdepth = kr_sub(bdepth, ((char*)"1"));
                }
                p = kr_plus(p, ((char*)"1"));
            }
        }
        return kr_plus(((char*)","), p);
    }
    if (kr_truthy(kr_eq(tt, ((char*)"ID")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1"))), ((char*)"DOT")))) {
            if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"2")))), ((char*)"ID")))) {
                char* chainEnd = kr_plus(pos, ((char*)"2"));
                while (kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(chainEnd, ((char*)"1"))), ((char*)"DOT"))) && kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(chainEnd, ((char*)"2")))), ((char*)"ID"))) ? kr_str("1") : kr_str("0")))) {
                    chainEnd = kr_plus(chainEnd, ((char*)"2"));
                }
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(chainEnd, ((char*)"1"))), ((char*)"ASSIGN")))) {
                    char* objName = ((char*(*)(char*))tokVal)(tok);
                    char* objType = ((char*(*)(char*,char*))irTypeOf)(types, objName);
                    char* didTypedWrite = ((char*)"0");
                    if (kr_truthy((kr_truthy(kr_eq(kr_startswith(objType, ((char*)"*")), ((char*)"1"))) && kr_truthy(kr_gt(kr_len(objType), ((char*)"1"))) ? kr_str("1") : kr_str("0")))) {
                        char* curType = objType;
                        char* acc = ((char*)"0");
                        char* fpos = kr_plus(pos, ((char*)"2"));
                        char* walkOK = ((char*)"1");
                        char* leafType = ((char*)"");
                        while (kr_truthy((kr_truthy(kr_lte(fpos, chainEnd)) && kr_truthy(kr_eq(walkOK, ((char*)"1"))) ? kr_str("1") : kr_str("0")))) {
                            char* fname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, fpos));
                            char* sname = kr_substr(curType, ((char*)"1"), kr_len(curType));
                            char* info = ((char*(*)(char*,char*))irTypeOf)(types, kr_plus(kr_plus(sname, ((char*)".")), fname));
                            if (kr_truthy(kr_eq(kr_len(info), ((char*)"0")))) {
                                walkOK = ((char*)"0");
                            }
                            if (kr_truthy(kr_eq(walkOK, ((char*)"1")))) {
                                char* pipe1 = kr_indexof(info, ((char*)"|"));
                                char* off = kr_toint(kr_substr(info, ((char*)"0"), pipe1));
                                char* ft = kr_substr(info, kr_plus(pipe1, ((char*)"1")), kr_len(info));
                                acc = kr_plus(acc, off);
                                if (kr_truthy(kr_eq(fpos, chainEnd))) {
                                    leafType = ft;
                                } else {
                                    if (kr_truthy(kr_eq(kr_startswith(ft, ((char*)"*")), ((char*)"1")))) {
                                        curType = ft;
                                    } else {
                                        walkOK = ((char*)"0");
                                    }
                                }
                            }
                            fpos = kr_plus(fpos, ((char*)"2"));
                        }
                        if (kr_truthy(kr_eq(walkOK, ((char*)"1")))) {
                            char* setOp = ((char*)"");
                            if (kr_truthy((kr_truthy(kr_eq(leafType, ((char*)"u8"))) || kr_truthy(kr_eq(leafType, ((char*)"i8"))) ? kr_str("1") : kr_str("0")))) {
                                setOp = ((char*)"BUILTIN bufSetByte 3\n");
                            }
                            if (kr_truthy((kr_truthy(kr_eq(leafType, ((char*)"u16"))) || kr_truthy(kr_eq(leafType, ((char*)"i16"))) ? kr_str("1") : kr_str("0")))) {
                                setOp = ((char*)"BUILTIN bufSetWordAt 3\n");
                            }
                            if (kr_truthy((kr_truthy(kr_eq(leafType, ((char*)"u32"))) || kr_truthy(kr_eq(leafType, ((char*)"i32"))) ? kr_str("1") : kr_str("0")))) {
                                setOp = ((char*)"BUILTIN bufSetDwordAt 3\n");
                            }
                            if (kr_truthy((kr_truthy(kr_eq(leafType, ((char*)"u64"))) || kr_truthy(kr_eq(leafType, ((char*)"i64"))) ? kr_str("1") : kr_str("0")))) {
                                setOp = ((char*)"BUILTIN bufSetQwordAt 3\n");
                            }
                            if (kr_truthy(kr_gt(kr_len(setOp), ((char*)"0")))) {
                                char* valp = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, kr_plus(chainEnd, ((char*)"2")), ntoks, lc, types);
                                char* p2 = ((char*(*)(char*))pairPos)(valp);
                                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p2), ((char*)"SEMI")))) {
                                    p2 = kr_plus(p2, ((char*)"1"));
                                }
                                return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"LOAD "), objName), ((char*)"\nPUSH ")), acc), ((char*)"\n")), ((char*(*)(char*))pairVal)(valp)), setOp), ((char*)"POP\n,")), p2);
                                didTypedWrite = ((char*)"1");
                            }
                        }
                    }
                    if (kr_truthy((kr_truthy(kr_eq(didTypedWrite, ((char*)"0"))) && kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"3"))), ((char*)"ASSIGN"))) ? kr_str("1") : kr_str("0")))) {
                        char* field = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"2"))));
                        char* pair = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, kr_plus(pos, ((char*)"4")), ntoks, lc, types);
                        char* code = ((char*(*)(char*))pairVal)(pair);
                        char* p = ((char*(*)(char*))pairPos)(pair);
                        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
                            p = kr_plus(p, ((char*)"1"));
                        }
                        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"LOAD "), objName), ((char*)"\n")), code), ((char*)"SETFIELD ")), field), ((char*)"\nSTORE ")), objName), ((char*)"\n,")), p);
                    }
                }
            }
        }
    }
    if (kr_truthy(kr_eq(tt, ((char*)"ID")))) {
        char* nt = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1")));
        if (kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(nt, ((char*)"PLUSEQ"))) || kr_truthy(kr_eq(nt, ((char*)"MINUSEQ"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(nt, ((char*)"STAREQ"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(nt, ((char*)"SLASHEQ"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(nt, ((char*)"MODEQ"))) ? kr_str("1") : kr_str("0")))) {
            char* name = ((char*(*)(char*))tokVal)(tok);
            char* pair = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, kr_plus(pos, ((char*)"2")), ntoks, lc, types);
            char* rcode = ((char*(*)(char*))pairVal)(pair);
            char* p = ((char*(*)(char*))pairPos)(pair);
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
                p = kr_plus(p, ((char*)"1"));
            }
            char* op = ((char*)"ADD\n");
            if (kr_truthy(kr_eq(nt, ((char*)"MINUSEQ")))) {
                op = ((char*)"SUB\n");
            }
            if (kr_truthy(kr_eq(nt, ((char*)"STAREQ")))) {
                op = ((char*)"MUL\n");
            }
            if (kr_truthy(kr_eq(nt, ((char*)"SLASHEQ")))) {
                op = ((char*)"DIV\n");
            }
            if (kr_truthy(kr_eq(nt, ((char*)"MODEQ")))) {
                op = ((char*)"MOD\n");
            }
            return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"LOAD "), name), ((char*)"\n")), rcode), op), ((char*)"STORE ")), name), ((char*)"\nLOAD ")), name), ((char*)"\nBUILTIN gcShadowPush 1\nPOP\n,")), p);
        }
    }
    if (kr_truthy(kr_eq(tt, ((char*)"ID")))) {
        char* nt = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1")));
        if (kr_truthy((kr_truthy(kr_eq(nt, ((char*)"PLUSPLUS"))) || kr_truthy(kr_eq(nt, ((char*)"MINUSMINUS"))) ? kr_str("1") : kr_str("0")))) {
            char* name = ((char*(*)(char*))tokVal)(tok);
            char* p = kr_plus(pos, ((char*)"2"));
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
                p = kr_plus(p, ((char*)"1"));
            }
            char* op = ((char*)"ADD\n");
            if (kr_truthy(kr_eq(nt, ((char*)"MINUSMINUS")))) {
                op = ((char*)"SUB\n");
            }
            return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"LOAD "), name), ((char*)"\nPUSH 1\n")), op), ((char*)"STORE ")), name), ((char*)"\n,")), p);
        }
    }
    if (kr_truthy((kr_truthy(kr_eq(tok, ((char*)"PLUSPLUS"))) || kr_truthy(kr_eq(tok, ((char*)"MINUSMINUS"))) ? kr_str("1") : kr_str("0")))) {
        char* name = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1"))));
        char* p = kr_plus(pos, ((char*)"2"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
            p = kr_plus(p, ((char*)"1"));
        }
        char* op = ((char*)"ADD\n");
        if (kr_truthy(kr_eq(tok, ((char*)"MINUSMINUS")))) {
            op = ((char*)"SUB\n");
        }
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"LOAD "), name), ((char*)"\nPUSH 1\n")), op), ((char*)"STORE ")), name), ((char*)"\n,")), p);
    }
    if (kr_truthy((kr_truthy(kr_eq(tt, ((char*)"ID"))) && kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1"))), ((char*)"LBRACK"))) ? kr_str("1") : kr_str("0")))) {
        char* name = ((char*(*)(char*))tokVal)(tok);
        char* varType = ((char*(*)(char*,char*))irTypeOf)(types, name);
        if (kr_truthy(kr_gt(kr_len(varType), ((char*)"0")))) {
            char* depth = ((char*)"1");
            char* pB = kr_plus(pos, ((char*)"2"));
            while (kr_truthy((kr_truthy(kr_lt(pB, ntoks)) && kr_truthy(kr_gt(depth, ((char*)"0"))) ? kr_str("1") : kr_str("0")))) {
                char* tk = ((char*(*)(char*,char*))tokAt)(tokens, pB);
                if (kr_truthy(kr_eq(tk, ((char*)"LBRACK")))) {
                    depth = kr_plus(depth, ((char*)"1"));
                }
                if (kr_truthy(kr_eq(tk, ((char*)"RBRACK")))) {
                    depth = kr_sub(depth, ((char*)"1"));
                }
                if (kr_truthy(kr_gt(depth, ((char*)"0")))) {
                    pB = kr_plus(pB, ((char*)"1"));
                }
            }
            if (kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, pB), ((char*)"RBRACK"))) && kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pB, ((char*)"1"))), ((char*)"ASSIGN"))) ? kr_str("1") : kr_str("0")))) {
                char* setOp = ((char*)"");
                char* scaleOp = ((char*)"");
                if (kr_truthy(kr_eq(varType, ((char*)"*u8")))) {
                    setOp = ((char*)"BUILTIN bufSetByte 3\n");
                } else if (kr_truthy((kr_truthy(kr_eq(varType, ((char*)"*u16"))) || kr_truthy(kr_eq(varType, ((char*)"*i16"))) ? kr_str("1") : kr_str("0")))) {
                    setOp = ((char*)"BUILTIN bufSetWordAt 3\n");
                    scaleOp = ((char*)"PUSH 2\nMUL\n");
                } else if (kr_truthy((kr_truthy(kr_eq(varType, ((char*)"*u32"))) || kr_truthy(kr_eq(varType, ((char*)"*i32"))) ? kr_str("1") : kr_str("0")))) {
                    setOp = ((char*)"BUILTIN bufSetDwordAt 3\n");
                    scaleOp = ((char*)"PUSH 4\nMUL\n");
                } else if (kr_truthy((kr_truthy(kr_eq(varType, ((char*)"*u64"))) || kr_truthy(kr_eq(varType, ((char*)"*i64"))) ? kr_str("1") : kr_str("0")))) {
                    setOp = ((char*)"BUILTIN bufSetQwordAt 3\n");
                    scaleOp = ((char*)"PUSH 8\nMUL\n");
                }
                if (kr_truthy(kr_gt(kr_len(setOp), ((char*)"0")))) {
                    char* idxp = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, kr_plus(pos, ((char*)"2")), ntoks, lc, types);
                    char* valp = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, kr_plus(pB, ((char*)"2")), ntoks, lc, types);
                    char* p = ((char*(*)(char*))pairPos)(valp);
                    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
                        p = kr_plus(p, ((char*)"1"));
                    }
                    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"LOAD "), name), ((char*)"\n")), ((char*(*)(char*))pairVal)(idxp)), scaleOp), ((char*(*)(char*))pairVal)(valp)), setOp), ((char*)"POP\n,")), p);
                }
            }
        }
    }
    if (kr_truthy((kr_truthy(kr_eq(tt, ((char*)"ID"))) && kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1"))), ((char*)"ASSIGN"))) ? kr_str("1") : kr_str("0")))) {
        char* name = ((char*(*)(char*))tokVal)(tok);
        char* pair = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, kr_plus(pos, ((char*)"2")), ntoks, lc, types);
        char* code = ((char*(*)(char*))pairVal)(pair);
        char* p = ((char*(*)(char*))pairPos)(pair);
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
            p = kr_plus(p, ((char*)"1"));
        }
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, ((char*)"STORE ")), name), ((char*)"\nLOAD ")), name), ((char*)"\nBUILTIN gcShadowPush 1\nPOP\n,")), p);
    }
    char* pair = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, pos, ntoks, lc, types);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
        p = kr_plus(p, ((char*)"1"));
    }
    return kr_plus(kr_plus(code, ((char*)"POP\n,")), p);
}

char* irTypeStr(char* tokens, char* start, char* end) {
    char* p = start;
    char* sb = kr_sbnew();
    while (kr_truthy(kr_lt(p, end))) {
        char* tk = ((char*(*)(char*,char*))tokAt)(tokens, p);
        if (kr_truthy(kr_eq(tk, ((char*)"STAR")))) {
            sb = kr_sbappend(sb, ((char*)"*"));
        }
        if (kr_truthy(kr_eq(tk, ((char*)"LBRACK")))) {
            sb = kr_sbappend(sb, ((char*)"["));
        }
        if (kr_truthy(kr_eq(tk, ((char*)"RBRACK")))) {
            sb = kr_sbappend(sb, ((char*)"]"));
        }
        if (kr_truthy(kr_eq(kr_startswith(tk, ((char*)"ID:")), ((char*)"1")))) {
            sb = kr_sbappend(sb, kr_substr(tk, ((char*)"3"), kr_len(tk)));
        }
        if (kr_truthy(kr_eq(kr_startswith(tk, ((char*)"KW:")), ((char*)"1")))) {
            sb = kr_sbappend(sb, kr_substr(tk, ((char*)"3"), kr_len(tk)));
        }
        p = kr_plus(p, ((char*)"1"));
    }
    return kr_sbtostring(sb);
}

char* irTypeOf(char* types, char* name) {
    char* n = kr_linecount(types);
    char* i = ((char*)"0");
    while (kr_truthy(kr_lt(i, n))) {
        char* line = kr_getline(types, i);
        char* pipePos = kr_indexof(line, ((char*)"|"));
        if (kr_truthy(kr_gt(pipePos, ((char*)"0")))) {
            if (kr_truthy(kr_eq(kr_substr(line, ((char*)"0"), pipePos), name))) {
                return kr_substr(line, kr_plus(pipePos, ((char*)"1")), kr_len(line));
            }
        }
        i = kr_plus(i, ((char*)"1"));
    }
    return ((char*)"");
}

char* irStructSizeOf(char* types, char* sname) {
    char* sizeKey = kr_plus(((char*)"__size__."), sname);
    char* sizeRec = ((char*(*)(char*,char*))irTypeOf)(types, sizeKey);
    if (kr_truthy(kr_gt(kr_len(sizeRec), ((char*)"0")))) {
        return kr_toint(sizeRec);
    }
    char* n = kr_linecount(types);
    char* i = ((char*)"0");
    char* prefix = kr_plus(sname, ((char*)"."));
    char* totalSize = ((char*)"0");
    while (kr_truthy(kr_lt(i, n))) {
        char* line = kr_getline(types, i);
        if (kr_truthy(kr_eq(kr_startswith(line, prefix), ((char*)"1")))) {
            char* pipe1 = kr_indexof(line, ((char*)"|"));
            char* rest = kr_substr(line, kr_plus(pipe1, ((char*)"1")), kr_len(line));
            char* pipe2 = kr_indexof(rest, ((char*)"|"));
            char* off = kr_toint(kr_substr(rest, ((char*)"0"), pipe2));
            char* ft = kr_substr(rest, kr_plus(pipe2, ((char*)"1")), kr_len(rest));
            char* fsize = ((char*)"4");
            if (kr_truthy((kr_truthy(kr_eq(ft, ((char*)"u8"))) || kr_truthy(kr_eq(ft, ((char*)"i8"))) ? kr_str("1") : kr_str("0")))) {
                fsize = ((char*)"1");
            }
            if (kr_truthy((kr_truthy(kr_eq(ft, ((char*)"u16"))) || kr_truthy(kr_eq(ft, ((char*)"i16"))) ? kr_str("1") : kr_str("0")))) {
                fsize = ((char*)"2");
            }
            if (kr_truthy((kr_truthy(kr_eq(ft, ((char*)"u32"))) || kr_truthy(kr_eq(ft, ((char*)"i32"))) ? kr_str("1") : kr_str("0")))) {
                fsize = ((char*)"4");
            }
            if (kr_truthy((kr_truthy(kr_eq(ft, ((char*)"u64"))) || kr_truthy(kr_eq(ft, ((char*)"i64"))) ? kr_str("1") : kr_str("0")))) {
                fsize = ((char*)"8");
            }
            char* endOff = kr_plus(off, fsize);
            if (kr_truthy(kr_gt(endOff, totalSize))) {
                totalSize = endOff;
            }
        }
        i = kr_plus(i, ((char*)"1"));
    }
    return totalSize;
}

char* irSkipTypeBody(char* tokens, char* pos) {
    char* p = pos;
    while (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"STAR")))) {
        p = kr_plus(p, ((char*)"1"));
    }
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"LBRACK")))) {
        p = kr_plus(p, ((char*)"1"));
        p = ((char*(*)(char*,char*))irSkipTypeBody)(tokens, p);
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RBRACK")))) {
            p = kr_plus(p, ((char*)"1"));
        }
        return p;
    }
    char* tk = ((char*(*)(char*,char*))tokAt)(tokens, p);
    if (kr_truthy((kr_truthy(kr_eq(kr_startswith(tk, ((char*)"ID:")), ((char*)"1"))) || kr_truthy(kr_eq(kr_startswith(tk, ((char*)"KW:")), ((char*)"1"))) ? kr_str("1") : kr_str("0")))) {
        p = kr_plus(p, ((char*)"1"));
    }
    return p;
}

char* irSkipTypeAnnotation(char* tokens, char* pos) {
    if (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, pos), ((char*)"COLON")))) {
        return pos;
    }
    return ((char*(*)(char*,char*))irSkipTypeBody)(tokens, kr_plus(pos, ((char*)"1")));
}

char* irLetIR(char* tokens, char* pos, char* ntoks, char* lc, char* inFunc, char* types) {
    char* name = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    if (kr_truthy(kr_eq(name, ((char*)"local")))) {
        char* typeTk = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1")));
        char* varTk = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"2")));
        if (kr_truthy((kr_truthy(kr_eq(kr_startswith(typeTk, ((char*)"ID:")), ((char*)"1"))) && kr_truthy(kr_eq(kr_startswith(varTk, ((char*)"ID:")), ((char*)"1"))) ? kr_str("1") : kr_str("0")))) {
            char* typeName = kr_substr(typeTk, ((char*)"3"), kr_len(typeTk));
            char* varName = kr_substr(varTk, ((char*)"3"), kr_len(varTk));
            char* structSize = ((char*(*)(char*,char*))irStructSizeOf)(types, typeName);
            if (kr_truthy(kr_gt(structSize, ((char*)"0")))) {
                char* p = kr_plus(pos, ((char*)"3"));
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
                    p = kr_plus(p, ((char*)"1"));
                }
                char* baseCode = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"LOCAL "), varName), ((char*)"\nPUSH ")), structSize), ((char*)"\nBUILTIN bufNew 1\nSTORE ")), varName), ((char*)"\n"));
                char* initCode = ((char*)"");
                char* dpfx = kr_plus(kr_plus(((char*)"__default__."), typeName), ((char*)"."));
                char* dn = kr_linecount(types);
                char* di = ((char*)"0");
                while (kr_truthy(kr_lt(di, dn))) {
                    char* dline = kr_getline(types, di);
                    if (kr_truthy(kr_eq(kr_startswith(dline, dpfx), ((char*)"1")))) {
                        char* dpipe = kr_indexof(dline, ((char*)"|"));
                        char* dfname = kr_substr(dline, kr_len(dpfx), dpipe);
                        char* dval = kr_substr(dline, kr_plus(dpipe, ((char*)"1")), kr_len(dline));
                        char* finfo = ((char*(*)(char*,char*))irTypeOf)(types, kr_plus(kr_plus(typeName, ((char*)".")), dfname));
                        if (kr_truthy(kr_gt(kr_len(finfo), ((char*)"0")))) {
                            char* fpipe = kr_indexof(finfo, ((char*)"|"));
                            char* foff = kr_substr(finfo, ((char*)"0"), fpipe);
                            char* ft = kr_substr(finfo, kr_plus(fpipe, ((char*)"1")), kr_len(finfo));
                            char* setOp = ((char*)"");
                            if (kr_truthy((kr_truthy(kr_eq(ft, ((char*)"u8"))) || kr_truthy(kr_eq(ft, ((char*)"i8"))) ? kr_str("1") : kr_str("0")))) {
                                setOp = ((char*)"BUILTIN bufSetByte 3\n");
                            }
                            if (kr_truthy((kr_truthy(kr_eq(ft, ((char*)"u16"))) || kr_truthy(kr_eq(ft, ((char*)"i16"))) ? kr_str("1") : kr_str("0")))) {
                                setOp = ((char*)"BUILTIN bufSetWordAt 3\n");
                            }
                            if (kr_truthy((kr_truthy(kr_eq(ft, ((char*)"u32"))) || kr_truthy(kr_eq(ft, ((char*)"i32"))) ? kr_str("1") : kr_str("0")))) {
                                setOp = ((char*)"BUILTIN bufSetDwordAt 3\n");
                            }
                            if (kr_truthy((kr_truthy(kr_eq(ft, ((char*)"u64"))) || kr_truthy(kr_eq(ft, ((char*)"i64"))) ? kr_str("1") : kr_str("0")))) {
                                setOp = ((char*)"BUILTIN bufSetQwordAt 3\n");
                            }
                            if (kr_truthy(kr_gt(kr_len(setOp), ((char*)"0")))) {
                                initCode = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(initCode, ((char*)"LOAD ")), varName), ((char*)"\nPUSH ")), foff), ((char*)"\nPUSH ")), dval), ((char*)"\n")), setOp), ((char*)"POP\n"));
                            }
                        }
                    }
                    di = kr_plus(di, ((char*)"1"));
                }
                return kr_plus(kr_plus(kr_plus(baseCode, initCode), ((char*)",")), p);
            }
        }
    }
    char* p = ((char*(*)(char*,char*))irSkipTypeAnnotation)(tokens, kr_plus(pos, ((char*)"1")));
    p = kr_plus(p, ((char*)"1"));
    char* pair = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, p, ntoks, lc, types);
    char* code = ((char*(*)(char*))pairVal)(pair);
    p = ((char*(*)(char*))pairPos)(pair);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"SEMI")))) {
        p = kr_plus(p, ((char*)"1"));
    }
    char* pushCode = kr_plus(kr_plus(((char*)"LOAD "), name), ((char*)"\nBUILTIN gcShadowPush 1\nPOP\n"));
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"LOCAL "), name), ((char*)"\n")), code), ((char*)"STORE ")), name), ((char*)"\n")), pushCode), ((char*)",")), p);
}

char* irBlockIR(char* tokens, char* pos, char* ntoks, char* lc, char* inFunc, char* types) {
    char* p = kr_plus(pos, ((char*)"1"));
    char* sbBlock = kr_sbnew();
    char* nlc = lc;
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RBRACE")))) {
        char* sp = ((char*(*)(char*,char*,char*,char*,char*,char*))irStmt)(tokens, p, ntoks, nlc, inFunc, types);
        sbBlock = kr_sbappend(sbBlock, ((char*(*)(char*))pairVal)(sp));
        p = ((char*(*)(char*))pairPos)(sp);
        nlc = kr_plus(nlc, ((char*)"1"));
    }
    return kr_plus(kr_plus(kr_sbtostring(sbBlock), ((char*)",")), kr_plus(p, ((char*)"1")));
}

char* irIfIR(char* tokens, char* pos, char* ntoks, char* lc, char* inFunc, char* types) {
    char* pair = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, pos, ntoks, lc, types);
    char* condCode = kr_plus(((char*(*)(char*))pairVal)(pair), ((char*)"BUILTIN isTruthy 1\n"));
    char* p = ((char*(*)(char*))pairPos)(pair);
    char* elseLabel = ((char*(*)(char*,char*))irLabel)(((char*)"_else"), pos);
    char* endLabel = ((char*(*)(char*,char*))irLabel)(((char*)"_endif"), pos);
    char* nlc = kr_plus(lc, ((char*)"1"));
    char* bp = ((char*(*)(char*,char*,char*,char*,char*,char*))irBlockIR)(tokens, p, ntoks, nlc, inFunc, types);
    char* bodyCode = ((char*(*)(char*))pairVal)(bp);
    p = ((char*(*)(char*))pairPos)(bp);
    nlc = kr_plus(nlc, ((char*)"1"));
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"KW:else")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, ((char*)"1"))), ((char*)"KW:if")))) {
            char* ep = ((char*(*)(char*,char*,char*,char*,char*,char*))irIfIR)(tokens, kr_plus(p, ((char*)"2")), ntoks, nlc, inFunc, types);
            char* elseCode = ((char*(*)(char*))pairVal)(ep);
            p = ((char*(*)(char*))pairPos)(ep);
            return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(condCode, ((char*)"JUMPIFNOT ")), elseLabel), ((char*)"\n")), bodyCode), ((char*)"JUMP ")), endLabel), ((char*)"\n")), ((char*)"LABEL ")), elseLabel), ((char*)"\n")), elseCode), ((char*)"LABEL ")), endLabel), ((char*)"\n,")), p);
        } else {
            char* ep = ((char*(*)(char*,char*,char*,char*,char*,char*))irBlockIR)(tokens, kr_plus(p, ((char*)"1")), ntoks, nlc, inFunc, types);
            char* elseCode = ((char*(*)(char*))pairVal)(ep);
            p = ((char*(*)(char*))pairPos)(ep);
            return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(condCode, ((char*)"JUMPIFNOT ")), elseLabel), ((char*)"\n")), bodyCode), ((char*)"JUMP ")), endLabel), ((char*)"\n")), ((char*)"LABEL ")), elseLabel), ((char*)"\n")), elseCode), ((char*)"LABEL ")), endLabel), ((char*)"\n,")), p);
        }
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(condCode, ((char*)"JUMPIFNOT ")), endLabel), ((char*)"\n")), bodyCode), ((char*)"LABEL ")), endLabel), ((char*)"\n,")), p);
}

char* irWhileIR(char* tokens, char* pos, char* ntoks, char* lc, char* inFunc, char* types) {
    char* loopLabel = ((char*(*)(char*,char*))irLabel)(((char*)"_wloop"), pos);
    char* endLabel = ((char*(*)(char*,char*))irLabel)(((char*)"_wend"), pos);
    char* nlc = kr_plus(lc, ((char*)"1"));
    char* pair = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, pos, ntoks, nlc, types);
    char* condCode = kr_plus(((char*(*)(char*))pairVal)(pair), ((char*)"BUILTIN isTruthy 1\n"));
    char* p = ((char*(*)(char*))pairPos)(pair);
    char* bp = ((char*(*)(char*,char*,char*,char*,char*,char*))irBlockIR)(tokens, p, ntoks, nlc, inFunc, types);
    char* bodyCode = ((char*(*)(char*))pairVal)(bp);
    p = ((char*(*)(char*))pairPos)(bp);
    bodyCode = kr_replace(bodyCode, ((char*)"BREAK\n"), kr_plus(kr_plus(((char*)"JUMP "), endLabel), ((char*)"\n")));
    bodyCode = kr_replace(bodyCode, ((char*)"CONTINUE\n"), kr_plus(kr_plus(((char*)"JUMP "), loopLabel), ((char*)"\n")));
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"LABEL "), loopLabel), ((char*)"\n")), condCode), ((char*)"JUMPIFNOT ")), endLabel), ((char*)"\n")), bodyCode), ((char*)"JUMP ")), loopLabel), ((char*)"\n")), ((char*)"LABEL ")), endLabel), ((char*)"\n,")), p);
}

char* irForIR(char* tokens, char* pos, char* ntoks, char* lc, char* inFunc, char* types) {
    char* varName = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* p = kr_plus(pos, ((char*)"2"));
    char* pair = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, p, ntoks, lc, types);
    char* collCode = ((char*(*)(char*))pairVal)(pair);
    p = ((char*(*)(char*))pairPos)(pair);
    char* loopLabel = ((char*(*)(char*,char*))irLabel)(((char*)"_floop"), pos);
    char* endLabel = ((char*(*)(char*,char*))irLabel)(((char*)"_fend"), pos);
    char* idxVar = kr_plus(((char*)"_for_i_"), pos);
    char* cntVar = kr_plus(((char*)"_for_cnt_"), pos);
    char* colVar = kr_plus(((char*)"_for_col_"), pos);
    char* nlc = kr_plus(lc, ((char*)"1"));
    char* bp = ((char*(*)(char*,char*,char*,char*,char*,char*))irBlockIR)(tokens, p, ntoks, nlc, inFunc, types);
    char* bodyCode = ((char*(*)(char*))pairVal)(bp);
    p = ((char*(*)(char*))pairPos)(bp);
    char* contLabel = ((char*(*)(char*,char*))irLabel)(((char*)"_fcont"), pos);
    bodyCode = kr_replace(bodyCode, ((char*)"BREAK\n"), kr_plus(kr_plus(((char*)"JUMP "), endLabel), ((char*)"\n")));
    bodyCode = kr_replace(bodyCode, ((char*)"CONTINUE\n"), kr_plus(kr_plus(((char*)"JUMP "), contLabel), ((char*)"\n")));
    char* code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(collCode, ((char*)"LOCAL ")), colVar), ((char*)"\n")), ((char*)"STORE ")), colVar), ((char*)"\n"));
    code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, ((char*)"LOCAL ")), idxVar), ((char*)"\n")), ((char*)"PUSH 0\n")), ((char*)"STORE ")), idxVar), ((char*)"\n"));
    code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, ((char*)"LOCAL ")), cntVar), ((char*)"\n")), ((char*)"LOAD ")), colVar), ((char*)"\n")), ((char*)"BUILTIN length 1\n")), ((char*)"STORE ")), cntVar), ((char*)"\n"));
    code = kr_plus(kr_plus(kr_plus(code, ((char*)"LABEL ")), loopLabel), ((char*)"\n"));
    code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, ((char*)"LOAD ")), idxVar), ((char*)"\n")), ((char*)"LOAD ")), cntVar), ((char*)"\n")), ((char*)"LT\n"));
    code = kr_plus(kr_plus(kr_plus(code, ((char*)"JUMPIFNOT ")), endLabel), ((char*)"\n"));
    code = kr_plus(kr_plus(kr_plus(code, ((char*)"LOCAL ")), varName), ((char*)"\n"));
    code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, ((char*)"LOAD ")), colVar), ((char*)"\n")), ((char*)"LOAD ")), idxVar), ((char*)"\n")), ((char*)"BUILTIN split 2\n")), ((char*)"STORE ")), varName), ((char*)"\n"));
    code = kr_plus(code, bodyCode);
    code = kr_plus(kr_plus(kr_plus(code, ((char*)"LABEL ")), contLabel), ((char*)"\n"));
    code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, ((char*)"LOAD ")), idxVar), ((char*)"\n")), ((char*)"PUSH 1\n")), ((char*)"ADD\n")), ((char*)"STORE ")), idxVar), ((char*)"\n"));
    code = kr_plus(kr_plus(kr_plus(code, ((char*)"JUMP ")), loopLabel), ((char*)"\n"));
    code = kr_plus(kr_plus(kr_plus(code, ((char*)"LABEL ")), endLabel), ((char*)"\n"));
    return kr_plus(kr_plus(code, ((char*)",")), p);
}

char* irMatchIR(char* tokens, char* pos, char* ntoks, char* lc, char* inFunc, char* types) {
    char* pair = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, pos, ntoks, lc, types);
    char* matchCode = ((char*(*)(char*))pairVal)(pair);
    char* p = kr_plus(((char*(*)(char*))pairPos)(pair), ((char*)"1"));
    char* endLabel = ((char*(*)(char*,char*))irLabel)(((char*)"_mend"), pos);
    char* matchVar = kr_plus(((char*)"_match_"), pos);
    char* code = kr_plus(kr_plus(kr_plus(matchCode, ((char*)"STORE ")), matchVar), ((char*)"\n"));
    char* nlc = kr_plus(lc, ((char*)"1"));
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RBRACE")))) {
        char* caseLabel = ((char*(*)(char*,char*))irLabel)(((char*)"_mcase"), p);
        char* nextLabel = ((char*(*)(char*,char*))irLabel)(((char*)"_mnext"), p);
        nlc = kr_plus(nlc, ((char*)"1"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"KW:else")))) {
            p = kr_plus(p, ((char*)"1"));
            char* bp = ((char*(*)(char*,char*,char*,char*,char*,char*))irBlockIR)(tokens, p, ntoks, nlc, inFunc, types);
            code = kr_plus(code, ((char*(*)(char*))pairVal)(bp));
            p = ((char*(*)(char*))pairPos)(bp);
        } else {
            char* cp = ((char*(*)(char*,char*,char*,char*,char*))irExpr)(tokens, p, ntoks, nlc, types);
            char* caseCode = ((char*(*)(char*))pairVal)(cp);
            p = ((char*(*)(char*))pairPos)(cp);
            char* bp = ((char*(*)(char*,char*,char*,char*,char*,char*))irBlockIR)(tokens, p, ntoks, nlc, inFunc, types);
            char* bodyCode = ((char*(*)(char*))pairVal)(bp);
            p = ((char*(*)(char*))pairPos)(bp);
            code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, ((char*)"LOAD ")), matchVar), ((char*)"\n")), caseCode), ((char*)"EQ\n")), ((char*)"JUMPIFNOT ")), nextLabel), ((char*)"\n")), bodyCode), ((char*)"JUMP ")), endLabel), ((char*)"\n")), ((char*)"LABEL ")), nextLabel), ((char*)"\n"));
        }
        nlc = kr_plus(nlc, ((char*)"1"));
    }
    p = kr_plus(p, ((char*)"1"));
    return kr_plus(kr_plus(kr_plus(kr_plus(code, ((char*)"LABEL ")), endLabel), ((char*)"\n,")), p);
}

char* irTryIR(char* tokens, char* pos, char* ntoks, char* lc, char* inFunc, char* types) {
    char* catchLabel = ((char*(*)(char*,char*))irLabel)(((char*)"_catch"), pos);
    char* endLabel = ((char*(*)(char*,char*))irLabel)(((char*)"_tryend"), pos);
    char* nlc = kr_plus(lc, ((char*)"1"));
    char* bp = ((char*(*)(char*,char*,char*,char*,char*,char*))irBlockIR)(tokens, pos, ntoks, nlc, inFunc, types);
    char* bodyCode = ((char*(*)(char*))pairVal)(bp);
    char* p = ((char*(*)(char*))pairPos)(bp);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"KW:catch")))) {
        p = kr_plus(p, ((char*)"1"));
        char* catchVar = ((char*)"_err");
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, p)), ((char*)"ID")))) {
            catchVar = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, p));
            p = kr_plus(p, ((char*)"1"));
        }
        char* cp = ((char*(*)(char*,char*,char*,char*,char*,char*))irBlockIR)(tokens, p, ntoks, nlc, inFunc, types);
        char* catchCode = ((char*(*)(char*))pairVal)(cp);
        p = ((char*(*)(char*))pairPos)(cp);
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"TRY "), catchLabel), ((char*)"\n")), bodyCode), ((char*)"ENDTRY\n")), ((char*)"JUMP ")), endLabel), ((char*)"\n")), ((char*)"LABEL ")), catchLabel), ((char*)"\n")), ((char*)"LOCAL ")), catchVar), ((char*)"\n")), ((char*)"STORE ")), catchVar), ((char*)"\n")), catchCode), ((char*)"LABEL ")), endLabel), ((char*)"\n,")), p);
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"TRY "), catchLabel), ((char*)"\n")), bodyCode), ((char*)"ENDTRY\n")), ((char*)"LABEL ")), catchLabel), ((char*)"\n")), ((char*)"LABEL ")), endLabel), ((char*)"\n,")), p);
}

char* irScanStructTypes(char* tokens, char* ntoks) {
    char* prev = ((char*)"");
    char* curr = ((char*(*)(char*,char*,char*))irScanStructTypesOnce)(tokens, ntoks, ((char*)""));
    char* iters = ((char*)"0");
    while (kr_truthy((kr_truthy(kr_neq(curr, prev)) && kr_truthy(kr_lt(iters, ((char*)"16"))) ? kr_str("1") : kr_str("0")))) {
        prev = curr;
        curr = ((char*(*)(char*,char*,char*))irScanStructTypesOnce)(tokens, ntoks, curr);
        iters = kr_plus(iters, ((char*)"1"));
    }
    return curr;
}

char* irScanStructTypesOnce(char* tokens, char* ntoks, char* sizeHints) {
    char* sb = kr_sbnew();
    char* i = ((char*)"0");
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* tk = ((char*(*)(char*,char*))tokAt)(tokens, i);
        if (kr_truthy((kr_truthy((kr_truthy(kr_eq(tk, ((char*)"KW:struct"))) || kr_truthy(kr_eq(tk, ((char*)"KW:class"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(tk, ((char*)"KW:type"))) ? kr_str("1") : kr_str("0")))) {
            char* snameTk = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1")));
            if (kr_truthy((kr_truthy(kr_eq(kr_startswith(snameTk, ((char*)"ID:")), ((char*)"1"))) && kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"2"))), ((char*)"LBRACE"))) ? kr_str("1") : kr_str("0")))) {
                char* sname = kr_substr(snameTk, ((char*)"3"), kr_len(snameTk));
                char* p = kr_plus(i, ((char*)"3"));
                char* off = ((char*)"0");
                char* maxAlign = ((char*)"1");
                while (kr_truthy((kr_truthy(kr_lt(p, ntoks)) && kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RBRACE"))) ? kr_str("1") : kr_str("0")))) {
                    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"KW:let")))) {
                        char* fnameTk = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, ((char*)"1")));
                        if (kr_truthy(kr_eq(kr_startswith(fnameTk, ((char*)"ID:")), ((char*)"1")))) {
                            char* fname = kr_substr(fnameTk, ((char*)"3"), kr_len(fnameTk));
                            char* ftype = ((char*)"u32");
                            char* fsize = ((char*)"4");
                            char* falign = ((char*)"4");
                            char* q = kr_plus(p, ((char*)"2"));
                            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, q), ((char*)"COLON")))) {
                                char* typeStart = kr_plus(q, ((char*)"1"));
                                char* typeEnd = ((char*(*)(char*,char*))irSkipTypeBody)(tokens, typeStart);
                                ftype = ((char*(*)(char*,char*,char*))irTypeStr)(tokens, typeStart, typeEnd);
                                if (kr_truthy((kr_truthy(kr_eq(ftype, ((char*)"u8"))) || kr_truthy(kr_eq(ftype, ((char*)"i8"))) ? kr_str("1") : kr_str("0")))) {
                                    fsize = ((char*)"1");
                                    falign = ((char*)"1");
                                }
                                if (kr_truthy((kr_truthy(kr_eq(ftype, ((char*)"u16"))) || kr_truthy(kr_eq(ftype, ((char*)"i16"))) ? kr_str("1") : kr_str("0")))) {
                                    fsize = ((char*)"2");
                                    falign = ((char*)"2");
                                }
                                if (kr_truthy((kr_truthy(kr_eq(ftype, ((char*)"u32"))) || kr_truthy(kr_eq(ftype, ((char*)"i32"))) ? kr_str("1") : kr_str("0")))) {
                                    fsize = ((char*)"4");
                                    falign = ((char*)"4");
                                }
                                if (kr_truthy((kr_truthy(kr_eq(ftype, ((char*)"u64"))) || kr_truthy(kr_eq(ftype, ((char*)"i64"))) ? kr_str("1") : kr_str("0")))) {
                                    fsize = ((char*)"8");
                                    falign = ((char*)"8");
                                }
                                char* nestedSize = ((char*(*)(char*,char*))irStructSizeOf)(sizeHints, ftype);
                                if (kr_truthy(kr_gt(nestedSize, ((char*)"0")))) {
                                    fsize = nestedSize;
                                    char* nalignRec = ((char*(*)(char*,char*))irTypeOf)(sizeHints, kr_plus(((char*)"__align__."), ftype));
                                    if (kr_truthy(kr_gt(kr_len(nalignRec), ((char*)"0")))) {
                                        falign = kr_toint(nalignRec);
                                    } else {
                                        falign = ((char*)"4");
                                    }
                                    ftype = kr_plus(((char*)"*"), ftype);
                                }
                                q = typeEnd;
                            }
                            if (kr_truthy(kr_neq(kr_mod(off, falign), ((char*)"0")))) {
                                off = kr_plus(off, kr_sub(falign, kr_mod(off, falign)));
                            }
                            if (kr_truthy(kr_gt(falign, maxAlign))) {
                                maxAlign = falign;
                            }
                            sb = kr_sbappend(sb, kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(sname, ((char*)".")), fname), ((char*)"|")), off), ((char*)"|")), ftype), ((char*)"\n")));
                            off = kr_plus(off, fsize);
                            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, q), ((char*)"ASSIGN")))) {
                                char* dvTk = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(q, ((char*)"1")));
                                if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(dvTk), ((char*)"INT")))) {
                                    sb = kr_sbappend(sb, kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"__default__."), sname), ((char*)".")), fname), ((char*)"|")), ((char*(*)(char*))tokVal)(dvTk)), ((char*)"\n")));
                                }
                                while (kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_lt(q, ntoks)) && kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, q), ((char*)"SEMI"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, q), ((char*)"KW:let"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, q), ((char*)"RBRACE"))) ? kr_str("1") : kr_str("0")))) {
                                    q = kr_plus(q, ((char*)"1"));
                                }
                            }
                            p = q;
                            continue;
                        }
                    }
                    p = kr_plus(p, ((char*)"1"));
                }
                char* totalSize = off;
                if (kr_truthy(kr_neq(kr_mod(totalSize, maxAlign), ((char*)"0")))) {
                    totalSize = kr_plus(totalSize, kr_sub(maxAlign, kr_mod(totalSize, maxAlign)));
                }
                sb = kr_sbappend(sb, kr_plus(kr_plus(kr_plus(kr_plus(((char*)"__size__."), sname), ((char*)"|")), totalSize), ((char*)"\n")));
                sb = kr_sbappend(sb, kr_plus(kr_plus(kr_plus(kr_plus(((char*)"__align__."), sname), ((char*)"|")), maxAlign), ((char*)"\n")));
            }
        }
        i = kr_plus(i, ((char*)"1"));
    }
    return kr_sbtostring(sb);
}

char* irScanFuncTypes(char* tokens, char* bodyStart) {
    if (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, bodyStart), ((char*)"LBRACE")))) {
        return ((char*)"");
    }
    char* p = kr_plus(bodyStart, ((char*)"1"));
    char* depth = ((char*)"1");
    char* nTok = kr_linecount(tokens);
    char* sb = kr_sbnew();
    while (kr_truthy((kr_truthy(kr_lt(p, nTok)) && kr_truthy(kr_gt(depth, ((char*)"0"))) ? kr_str("1") : kr_str("0")))) {
        char* tk = ((char*(*)(char*,char*))tokAt)(tokens, p);
        if (kr_truthy(kr_eq(tk, ((char*)"LBRACE")))) {
            depth = kr_plus(depth, ((char*)"1"));
            p = kr_plus(p, ((char*)"1"));
            continue;
        }
        if (kr_truthy(kr_eq(tk, ((char*)"RBRACE")))) {
            depth = kr_sub(depth, ((char*)"1"));
            p = kr_plus(p, ((char*)"1"));
            continue;
        }
        if (kr_truthy((kr_truthy(kr_eq(tk, ((char*)"KW:let"))) || kr_truthy(kr_eq(tk, ((char*)"KW:const"))) ? kr_str("1") : kr_str("0")))) {
            char* nameTk = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, ((char*)"1")));
            if (kr_truthy(kr_eq(kr_startswith(nameTk, ((char*)"ID:")), ((char*)"1")))) {
                char* nameStr = kr_substr(nameTk, ((char*)"3"), kr_len(nameTk));
                if (kr_truthy(kr_eq(nameStr, ((char*)"local")))) {
                    char* typeTk = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, ((char*)"2")));
                    char* varTk = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, ((char*)"3")));
                    if (kr_truthy((kr_truthy(kr_eq(kr_startswith(typeTk, ((char*)"ID:")), ((char*)"1"))) && kr_truthy(kr_eq(kr_startswith(varTk, ((char*)"ID:")), ((char*)"1"))) ? kr_str("1") : kr_str("0")))) {
                        char* typeName = kr_substr(typeTk, ((char*)"3"), kr_len(typeTk));
                        char* varName = kr_substr(varTk, ((char*)"3"), kr_len(varTk));
                        sb = kr_sbappend(sb, kr_plus(kr_plus(kr_plus(varName, ((char*)"|*")), typeName), ((char*)"\n")));
                        p = kr_plus(p, ((char*)"4"));
                        continue;
                    }
                }
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, ((char*)"2"))), ((char*)"COLON")))) {
                    char* typeStart = kr_plus(p, ((char*)"3"));
                    char* typeEnd = ((char*(*)(char*,char*))irSkipTypeBody)(tokens, typeStart);
                    sb = kr_sbappend(sb, kr_plus(kr_plus(kr_plus(nameStr, ((char*)"|")), ((char*(*)(char*,char*,char*))irTypeStr)(tokens, typeStart, typeEnd)), ((char*)"\n")));
                    p = typeEnd;
                    continue;
                }
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, ((char*)"2"))), ((char*)"ASSIGN")))) {
                    char* rhsTk = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, ((char*)"3")));
                    char* isLam = ((char*)"0");
                    char* isFuncPtr = ((char*)"0");
                    if (kr_truthy((kr_truthy(kr_eq(rhsTk, ((char*)"KW:func"))) || kr_truthy(kr_eq(rhsTk, ((char*)"KW:fn"))) ? kr_str("1") : kr_str("0")))) {
                        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, ((char*)"4"))), ((char*)"LPAREN")))) {
                            isLam = ((char*)"1");
                        }
                    }
                    if (kr_truthy(kr_eq(rhsTk, ((char*)"ID:funcptr")))) {
                        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, ((char*)"4"))), ((char*)"LPAREN")))) {
                            isFuncPtr = ((char*)"1");
                        }
                    }
                    if (kr_truthy(kr_eq(isLam, ((char*)"1")))) {
                        sb = kr_sbappend(sb, kr_plus(nameStr, ((char*)"|closure\n")));
                    } else {
                        if (kr_truthy(kr_eq(isFuncPtr, ((char*)"1")))) {
                            sb = kr_sbappend(sb, kr_plus(nameStr, ((char*)"|fp\n")));
                        }
                    }
                }
            }
        }
        p = kr_plus(p, ((char*)"1"));
    }
    return kr_sbtostring(sb);
}

char* irLambdaIR(char* tokens, char* pos, char* ntoks, char* lambdaName) {
    char* p = kr_plus(pos, ((char*)"2"));
    char* userParams = ((char*)"");
    char* paramTypes = ((char*)"");
    char* pc = ((char*)"0");
    char* paramCsv = ((char*)"");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RPAREN")))) {
        char* pt = ((char*(*)(char*,char*))tokAt)(tokens, p);
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(pt), ((char*)"ID")))) {
            char* pname = ((char*(*)(char*))tokVal)(pt);
            userParams = kr_plus(kr_plus(kr_plus(userParams, ((char*)"PARAM ")), pname), ((char*)"\n"));
            if (kr_truthy(kr_gt(kr_len(paramCsv), ((char*)"0")))) {
                paramCsv = kr_plus(paramCsv, ((char*)","));
            }
            paramCsv = kr_plus(paramCsv, pname);
            pc = kr_plus(pc, ((char*)"1"));
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, ((char*)"1"))), ((char*)"COLON")))) {
                char* typeStart = kr_plus(p, ((char*)"2"));
                char* typeEnd = ((char*(*)(char*,char*))irSkipTypeBody)(tokens, typeStart);
                char* ptype = ((char*(*)(char*,char*,char*))irTypeStr)(tokens, typeStart, typeEnd);
                paramTypes = kr_plus(kr_plus(kr_plus(kr_plus(paramTypes, pname), ((char*)"|")), ptype), ((char*)"\n"));
                p = typeEnd;
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"COMMA")))) {
                    p = kr_plus(p, ((char*)"1"));
                }
            } else {
                p = kr_plus(p, ((char*)"1"));
            }
        } else {
            p = kr_plus(p, ((char*)"1"));
        }
    }
    p = kr_plus(p, ((char*)"1"));
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"ARROW")))) {
        p = kr_plus(p, ((char*)"2"));
    }
    char* bodyEnd = ((char*(*)(char*,char*))skipBlock)(tokens, p);
    char* freeVars = ((char*(*)(char*,char*,char*,char*))findFreeVars)(tokens, p, bodyEnd, paramCsv);
    char* captureTypes = ((char*)"");
    char* allParams = kr_plus(((char*)"PARAM __env\n"), userParams);
    pc = kr_plus(pc, ((char*)"1"));
    if (kr_truthy(kr_gt(kr_len(freeVars), ((char*)"0")))) {
        char* fcount = kr_count(freeVars);
        char* fi = ((char*)"0");
        while (kr_truthy(kr_lt(fi, fcount))) {
            char* fname = kr_split(freeVars, fi);
            captureTypes = kr_plus(kr_plus(kr_plus(kr_plus(captureTypes, fname), ((char*)"|__cap__:")), fname), ((char*)"\n"));
            fi = kr_plus(fi, ((char*)"1"));
        }
    }
    char* funcTypes = kr_plus(kr_plus(kr_plus(((char*(*)(char*,char*))irScanStructTypes)(tokens, ntoks), ((char*(*)(char*,char*))irScanFuncTypes)(tokens, p)), paramTypes), captureTypes);
    char* bp = ((char*(*)(char*,char*,char*,char*,char*,char*))irBlockIR)(tokens, p, ntoks, ((char*)"0"), ((char*)"1"), funcTypes);
    char* bodyCode = ((char*(*)(char*))pairVal)(bp);
    p = ((char*(*)(char*))pairPos)(bp);
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"FUNC "), lambdaName), ((char*)" ")), pc), ((char*)"\n")), allParams), bodyCode), ((char*)"RETURN\nEND\n\n,")), p);
}

char* irFuncIR(char* tokens, char* pos, char* ntoks) {
    char* fname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, ((char*)"1"))));
    char* p = kr_plus(pos, ((char*)"3"));
    char* params = ((char*)"");
    char* paramTypes = ((char*)"");
    char* pc = ((char*)"0");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"RPAREN")))) {
        char* pt = ((char*(*)(char*,char*))tokAt)(tokens, p);
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(pt), ((char*)"ID")))) {
            char* pname = ((char*(*)(char*))tokVal)(pt);
            params = kr_plus(kr_plus(kr_plus(params, ((char*)"PARAM ")), pname), ((char*)"\n"));
            pc = kr_plus(pc, ((char*)"1"));
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, ((char*)"1"))), ((char*)"COLON")))) {
                char* typeStart = kr_plus(p, ((char*)"2"));
                char* typeEnd = ((char*(*)(char*,char*))irSkipTypeBody)(tokens, typeStart);
                char* ptype = ((char*(*)(char*,char*,char*))irTypeStr)(tokens, typeStart, typeEnd);
                paramTypes = kr_plus(kr_plus(kr_plus(kr_plus(paramTypes, pname), ((char*)"|")), ptype), ((char*)"\n"));
                p = typeEnd;
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"COMMA")))) {
                    p = kr_plus(p, ((char*)"1"));
                }
            } else {
                p = kr_plus(p, ((char*)"1"));
            }
        } else {
            p = kr_plus(p, ((char*)"1"));
        }
    }
    p = kr_plus(p, ((char*)"1"));
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), ((char*)"ARROW")))) {
        p = kr_plus(p, ((char*)"2"));
    }
    char* funcTypes = kr_plus(kr_plus(((char*(*)(char*,char*))irScanStructTypes)(tokens, ntoks), ((char*(*)(char*,char*))irScanFuncTypes)(tokens, p)), paramTypes);
    char* bp = ((char*(*)(char*,char*,char*,char*,char*,char*))irBlockIR)(tokens, p, ntoks, ((char*)"0"), ((char*)"1"), funcTypes);
    char* bodyCode = ((char*(*)(char*))pairVal)(bp);
    p = ((char*(*)(char*))pairPos)(bp);
    if (kr_truthy(kr_startswith(fname, ((char*)"pure_")))) {
        bodyCode = kr_plus(kr_plus(((char*)"LOCAL _gc_ck\nBUILTIN gcCheckpoint 0\nSTORE _gc_ck\n"), bodyCode), ((char*)"LOAD _gc_ck\nBUILTIN gcRestore 1\nPOP\n"));
    }
    char* paramPushes = ((char*)"");
    char* plnCount = kr_linecount(params);
    char* pli = ((char*)"0");
    while (kr_truthy(kr_lt(pli, plnCount))) {
        char* pln = kr_getline(params, pli);
        if (kr_truthy(kr_eq(kr_startswith(pln, ((char*)"PARAM ")), ((char*)"1")))) {
            char* pn = kr_substr(pln, ((char*)"6"), kr_len(pln));
            paramPushes = kr_plus(kr_plus(kr_plus(paramPushes, ((char*)"LOAD ")), pn), ((char*)"\nBUILTIN gcShadowPush 1\nPOP\n"));
        }
        pli = kr_plus(pli, ((char*)"1"));
    }
    bodyCode = kr_plus(kr_plus(kr_plus(((char*)"LOCAL __sh_save\nBUILTIN gcShadowCount 0\nSTORE __sh_save\n"), paramPushes), bodyCode), ((char*)"BUILTIN gcShadowCount 0\nLOAD __sh_save\nSUB\nBUILTIN gcShadowPop 1\nPOP\n"));
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*)"FUNC "), fname), ((char*)" ")), pc), ((char*)"\n")), params), bodyCode), ((char*)"END\n\n,")), p);
}

char* findFreeVars(char* tokens, char* bodyStart, char* bodyEnd, char* params) {
    char* localDecls = params;
    char* i = kr_plus(bodyStart, ((char*)"1"));
    while (kr_truthy(kr_lt(i, bodyEnd))) {
        char* tok = ((char*(*)(char*,char*))tokAt)(tokens, i);
        if (kr_truthy((kr_truthy(kr_eq(tok, ((char*)"KW:let"))) || kr_truthy(kr_eq(tok, ((char*)"KW:const"))) ? kr_str("1") : kr_str("0")))) {
            char* lname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1"))));
            if (kr_truthy(kr_not(kr_contains(localDecls, kr_plus(kr_plus(((char*)","), lname), ((char*)",")))))) {
                localDecls = kr_plus(kr_plus(kr_plus(localDecls, ((char*)",")), lname), ((char*)","));
            }
        }
        i = kr_plus(i, ((char*)"1"));
    }
    char* freeVars = ((char*)"");
    i = kr_plus(bodyStart, ((char*)"1"));
    while (kr_truthy(kr_lt(i, bodyEnd))) {
        char* tok = ((char*(*)(char*,char*))tokAt)(tokens, i);
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(tok), ((char*)"ID")))) {
            char* name = ((char*(*)(char*))tokVal)(tok);
            char* nextTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1")));
            if (kr_truthy(kr_neq(nextTok, ((char*)"LPAREN")))) {
                if (kr_truthy(kr_not(kr_contains(kr_plus(kr_plus(((char*)","), localDecls), ((char*)",")), kr_plus(kr_plus(((char*)","), name), ((char*)",")))))) {
                    if (kr_truthy((kr_truthy(kr_gt(kr_len(name), ((char*)"0"))) && kr_truthy(kr_not(kr_startswith(name, ((char*)"kr_")))) ? kr_str("1") : kr_str("0")))) {
                        if (kr_truthy(kr_not(kr_contains(freeVars, kr_plus(kr_plus(((char*)","), name), ((char*)",")))))) {
                            freeVars = kr_plus(kr_plus(kr_plus(freeVars, ((char*)",")), name), ((char*)","));
                        }
                    }
                }
            }
        }
        i = kr_plus(i, ((char*)"1"));
    }
    if (kr_truthy(kr_gt(kr_len(freeVars), ((char*)"2")))) {
        return kr_substr(freeVars, ((char*)"1"), kr_sub(kr_len(freeVars), ((char*)"1")));
    }
    return ((char*)"");
}

char* emitPortWarnings(char* tokens, char* ntoks, char* fname) {
    char* warnings = ((char*)"0");
    char* i = ((char*)"0");
    char* topLevelLets = ((char*)"");
    char* pp = ((char*)"0");
    char* ppDepth = ((char*)"0");
    while (kr_truthy(kr_lt(pp, ntoks))) {
        char* pt = ((char*(*)(char*,char*))tokAt)(tokens, pp);
        if (kr_truthy(kr_eq(pt, ((char*)"LBRACE")))) {
            ppDepth = kr_plus(ppDepth, ((char*)"1"));
        }
        if (kr_truthy(kr_eq(pt, ((char*)"RBRACE")))) {
            ppDepth = kr_sub(ppDepth, ((char*)"1"));
        }
        if (kr_truthy((kr_truthy(kr_eq(ppDepth, ((char*)"0"))) && kr_truthy((kr_truthy(kr_eq(pt, ((char*)"KW:let"))) || kr_truthy(kr_eq(pt, ((char*)"KW:const"))) ? kr_str("1") : kr_str("0"))) ? kr_str("1") : kr_str("0")))) {
            char* nameTk = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pp, ((char*)"1")));
            if (kr_truthy(kr_eq(kr_startswith(nameTk, ((char*)"ID:")), ((char*)"1")))) {
                char* nm = kr_substr(nameTk, ((char*)"3"), kr_len(nameTk));
                if (kr_truthy(kr_gt(kr_len(topLevelLets), ((char*)"0")))) {
                    topLevelLets = kr_plus(topLevelLets, ((char*)","));
                }
                topLevelLets = kr_plus(topLevelLets, nm);
            }
        }
        pp = kr_plus(pp, ((char*)"1"));
    }
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* tok = ((char*(*)(char*,char*))tokAt)(tokens, i);
        if (kr_truthy((kr_truthy(kr_eq(tok, ((char*)"ID:bufNew"))) && kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1"))), ((char*)"LPAREN"))) ? kr_str("1") : kr_str("0")))) {
            kr_printerr(kr_plus(fname, ((char*)": warning [port-1to2]: bufNew() — manual heap allocation. In 2.0, prefer typed `let local TYPE name` (stack alloc) or wait for GC reclamation.")));
            warnings = kr_plus(warnings, ((char*)"1"));
        }
        if (kr_truthy((kr_truthy(kr_eq(tok, ((char*)"ID:rawAlloc"))) && kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1"))), ((char*)"LPAREN"))) ? kr_str("1") : kr_str("0")))) {
            kr_printerr(kr_plus(fname, ((char*)": warning [port-1to2]: rawAlloc() — escapes GC; 2.0 will require explicit `unsafe` block or paired rawFree.")));
            warnings = kr_plus(warnings, ((char*)"1"));
        }
        if (kr_truthy((kr_truthy(kr_eq(tok, ((char*)"ID:rawFree"))) && kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1"))), ((char*)"LPAREN"))) ? kr_str("1") : kr_str("0")))) {
            kr_printerr(kr_plus(fname, ((char*)": warning [port-1to2]: rawFree() — only needed for rawAlloc'd memory under 2.0 GC.")));
            warnings = kr_plus(warnings, ((char*)"1"));
        }
        if (kr_truthy((kr_truthy(kr_eq(tok, ((char*)"ID:ptrAdd"))) && kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1"))), ((char*)"LPAREN"))) ? kr_str("1") : kr_str("0")))) {
            kr_printerr(kr_plus(fname, ((char*)": warning [port-1to2]: ptrAdd() — raw pointer arithmetic. Prefer typed `*u8 + n` syntax in 2.0.")));
            warnings = kr_plus(warnings, ((char*)"1"));
        }
        if (kr_truthy((kr_truthy(kr_eq(tok, ((char*)"ID:ptrToInt"))) && kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1"))), ((char*)"LPAREN"))) ? kr_str("1") : kr_str("0")))) {
            kr_printerr(kr_plus(fname, ((char*)": warning [port-1to2]: ptrToInt() — converts pointer to int. Loses GC-tracking under 2.0.")));
            warnings = kr_plus(warnings, ((char*)"1"));
        }
        if (kr_truthy((kr_truthy((kr_truthy(kr_eq(tok, ((char*)"ID:rawReadByte"))) || kr_truthy(kr_eq(tok, ((char*)"ID:rawReadWord"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(tok, ((char*)"ID:rawReadQword"))) ? kr_str("1") : kr_str("0")))) {
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1"))), ((char*)"LPAREN")))) {
                char* fn = kr_substr(tok, ((char*)"3"), kr_len(tok));
                kr_printerr(kr_plus(kr_plus(kr_plus(fname, ((char*)": warning [port-1to2]: ")), fn), ((char*)"() — raw memory read. Prefer typed pointer indexing (`p[i]` with `let p: *u8 = ...`) for 2.0 safety.")));
                warnings = kr_plus(warnings, ((char*)"1"));
            }
        }
        if (kr_truthy((kr_truthy(kr_eq(tok, ((char*)"ID:rawWriteWord"))) || kr_truthy(kr_eq(tok, ((char*)"ID:rawWriteQword"))) ? kr_str("1") : kr_str("0")))) {
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1"))), ((char*)"LPAREN")))) {
                char* fn = kr_substr(tok, ((char*)"3"), kr_len(tok));
                kr_printerr(kr_plus(kr_plus(kr_plus(fname, ((char*)": warning [port-1to2]: ")), fn), ((char*)"() — raw memory write. Prefer typed pointer assignment in 2.0.")));
                warnings = kr_plus(warnings, ((char*)"1"));
            }
        }
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(tok), ((char*)"CBLOCK")))) {
            kr_printerr(kr_plus(fname, ((char*)": warning [port-1to2]: `cfunc { }` block — C-language body. 2.0 prefers pure-Krypton implementations once Win32 ABI marshalling lands.")));
            warnings = kr_plus(warnings, ((char*)"1"));
        }
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(tok), ((char*)"ID")))) {
            char* nm2 = ((char*(*)(char*))tokVal)(tok);
            if (kr_truthy(kr_contains(kr_plus(kr_plus(((char*)","), topLevelLets), ((char*)",")), kr_plus(kr_plus(((char*)","), nm2), ((char*)","))))) {
                char* nextTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1")));
                if (kr_truthy(kr_eq(nextTok, ((char*)"ASSIGN")))) {
                    char* prev = ((char*)"");
                    if (kr_truthy(kr_gt(i, ((char*)"0")))) {
                        prev = ((char*(*)(char*,char*))tokAt)(tokens, kr_sub(i, ((char*)"1")));
                    }
                    if (kr_truthy((kr_truthy(kr_neq(prev, ((char*)"KW:let"))) && kr_truthy(kr_neq(prev, ((char*)"KW:const"))) ? kr_str("1") : kr_str("0")))) {
                        kr_printerr(kr_plus(kr_plus(kr_plus(fname, ((char*)": warning [port-1to2]: file-scope `")), nm2), ((char*)"` reassigned — mutable module globals are broken in the native pipeline. Confine state to function scope or pass explicitly.")));
                        warnings = kr_plus(warnings, ((char*)"1"));
                    }
                }
            }
        }
        i = kr_plus(i, ((char*)"1"));
    }
    if (kr_truthy(kr_eq(warnings, ((char*)"0")))) {
        kr_printerr(kr_plus(fname, ((char*)": port-1to2 clean — no 2.0 migration concerns flagged.")));
    } else {
        kr_printerr(kr_plus(kr_plus(kr_plus(fname, ((char*)": port-1to2 done — ")), warnings), ((char*)" warning(s).")));
    }
}

int main(int argc, char** argv) {
    char _stack_anchor; _stack_bottom = &_stack_anchor;
    _argc = argc; _argv = argv;
    srand((unsigned)time(NULL));
    char* kccVer = ((char*)"2.2.0");
    char* irMode = ((char*)"0");
    char* portMode = ((char*)"0");
    char* installRoot = kr_environ(((char*)"KRYPTON_ROOT"));
    if (kr_truthy(kr_eq(installRoot, ((char*)"")))) {
        if (kr_truthy(kr_eq(kr_environ(((char*)"OS")), ((char*)"Windows_NT")))) {
            installRoot = ((char*)"C:\\krypton");
        } else if (kr_truthy(kr_neq(kr_environ(((char*)"HOME")), ((char*)"")))) {
            installRoot = ((char*)"/usr/local/krypton");
        } else {
            installRoot = ((char*)"C:\\krypton");
        }
    }
    char* headersDir = kr_plus(installRoot, ((char*)"/headers"));
    char* outFile = ((char*)"");
    char* file = kr_arg(((char*)"0"));
    char* argIdx = ((char*)"0");
    if (kr_truthy((kr_truthy(kr_eq(file, ((char*)"--version"))) || kr_truthy(kr_eq(file, ((char*)"-v"))) ? kr_str("1") : kr_str("0")))) {
        kr_printerr(kr_plus(kr_plus(((char*)"kcc version "), kccVer), ((char*)"\n")));
        return atoi(((char*)"0"));
    }
    if (kr_truthy(kr_eq(kr_argcount(), ((char*)"0")))) {
        kr_printerr(((char*)"kcc: no input file"));
        kr_printerr(((char*)"usage: kcc [-o out.exe] [--port-1to2] source.k"));
        return atoi(((char*)"1"));
    }
    while (kr_truthy((kr_truthy((kr_truthy(kr_eq(file, ((char*)"--ir"))) || kr_truthy(kr_eq(file, ((char*)"-o"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(file, ((char*)"--port-1to2"))) ? kr_str("1") : kr_str("0")))) {
        if (kr_truthy(kr_eq(file, ((char*)"--ir")))) {
            irMode = ((char*)"1");
            argIdx = kr_plus(argIdx, ((char*)"1"));
        }
        if (kr_truthy(kr_eq(file, ((char*)"-o")))) {
            argIdx = kr_plus(argIdx, ((char*)"1"));
            outFile = kr_arg(kr_plus(argIdx, ((char*)"")));
            argIdx = kr_plus(argIdx, ((char*)"1"));
        }
        if (kr_truthy(kr_eq(file, ((char*)"--port-1to2")))) {
            portMode = ((char*)"1");
            argIdx = kr_plus(argIdx, ((char*)"1"));
        }
        file = kr_arg(kr_plus(argIdx, ((char*)"")));
    }
    if (kr_truthy(kr_gt(kr_len(outFile), ((char*)"0")))) {
        irMode = ((char*)"1");
    }
    char* source = kr_readfile(file);
    if (kr_truthy(kr_eq(kr_len(source), ((char*)"0")))) {
        kr_printerr(kr_plus(((char*)"kcc: cannot read file: "), file));
        return atoi(((char*)"1"));
    }
    char* tokens = ((char*(*)(char*))tokenize)(source);
    char* ntoks = kr_linecount(tokens);
    if (kr_truthy(kr_eq(portMode, ((char*)"1")))) {
        ((char*(*)(char*,char*,char*))emitPortWarnings)(tokens, ntoks, file);
        return atoi(((char*)"0"));
    }
    char* baseDir = ((char*)"");
    char* lastSlash = kr_sub(((char*)"0"), ((char*)"1"));
    char* fi = ((char*)"0");
    while (kr_truthy(kr_lt(fi, kr_len(file)))) {
        if (kr_truthy((kr_truthy(kr_eq(kr_idx(file, kr_atoi(fi)), ((char*)"/"))) || kr_truthy(kr_eq(kr_idx(file, kr_atoi(fi)), ((char*)"\\"))) ? kr_str("1") : kr_str("0")))) {
            lastSlash = fi;
        }
        fi = kr_plus(fi, ((char*)"1"));
    }
    if (kr_truthy(kr_gte(lastSlash, ((char*)"0")))) {
        baseDir = kr_substr(file, ((char*)"0"), kr_plus(lastSlash, ((char*)"1")));
    }
    char* ftable = ((char*(*)(char*,char*))scanFunctions)(tokens, ntoks);
    char* sb = kr_sbnew();
    sb = kr_sbappend(sb, ((char*(*)(void))cRuntime)());
    char* imported = ((char*)"");
    char* importFwdDecls = ((char*)"");
    char* importBodies = ((char*)"");
    char* importedIR = ((char*)"");
    char* lambdaBank = ((char*)"");
    char* lambdaFreeVars = ((char*)"");
    char* structTable = ((char*)"");
    char* lsi = ((char*)"0");
    while (kr_truthy(kr_lt(lsi, ntoks))) {
        char* lsTok = ((char*(*)(char*,char*))tokAt)(tokens, lsi);
        if (kr_truthy((kr_truthy(kr_eq(lsTok, ((char*)"KW:func"))) || kr_truthy(kr_eq(lsTok, ((char*)"KW:fn"))) ? kr_str("1") : kr_str("0")))) {
            char* prevTok = ((char*)"");
            if (kr_truthy(kr_gt(lsi, ((char*)"0")))) {
                prevTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_sub(lsi, ((char*)"1")));
            }
            char* nextTok2 = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(lsi, ((char*)"1")));
            if (kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(prevTok, ((char*)"ASSIGN"))) || kr_truthy(kr_eq(prevTok, ((char*)"LPAREN"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(prevTok, ((char*)"COMMA"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(prevTok, ((char*)"KW:emit"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(prevTok, ((char*)"KW:return"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(prevTok, ((char*)"KW:in"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_eq(nextTok2, ((char*)"LPAREN"))) ? kr_str("1") : kr_str("0")))) {
                char* lp2 = kr_plus(lsi, ((char*)"2"));
                char* lparams2 = ((char*)"");
                char* lpc2 = ((char*)"0");
                while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, lp2), ((char*)"RPAREN")))) {
                    if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, lp2)), ((char*)"ID")))) {
                        if (kr_truthy(kr_gt(lpc2, ((char*)"0")))) {
                            lparams2 = kr_plus(lparams2, ((char*)","));
                        }
                        lparams2 = kr_plus(lparams2, ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, lp2)));
                        lpc2 = kr_plus(lpc2, ((char*)"1"));
                    }
                    lp2 = kr_plus(lp2, ((char*)"1"));
                }
                lp2 = kr_plus(lp2, ((char*)"1"));
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, lp2), ((char*)"ARROW")))) {
                    lp2 = kr_plus(lp2, ((char*)"2"));
                }
                char* lbp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, lp2, ntoks, ((char*)"1"), kr_plus(((char*)"_krlam"), lsi));
                char* lbcode = ((char*(*)(char*))pairVal)(lbp);
                char* lsig = kr_plus(kr_plus(((char*)"char* _krlam"), lsi), ((char*)"(void)"));
                if (kr_truthy(kr_gt(lpc2, ((char*)"0")))) {
                    lsig = kr_plus(kr_plus(kr_plus(((char*)"char* _krlam"), lsi), ((char*)"(char* ")), ((char*(*)(char*))cIdent)(((char*(*)(char*,char*))getNthParam)(lparams2, ((char*)"0"))));
                    char* lpi2 = ((char*)"1");
                    while (kr_truthy(kr_lt(lpi2, lpc2))) {
                        lsig = kr_plus(kr_plus(lsig, ((char*)", char* ")), ((char*(*)(char*))cIdent)(((char*(*)(char*,char*))getNthParam)(lparams2, lpi2)));
                        lpi2 = kr_plus(lpi2, ((char*)"1"));
                    }
                    lsig = kr_plus(lsig, ((char*)")"));
                }
                char* lbodyEnd = ((char*(*)(char*,char*))skipBlock)(tokens, lp2);
                char* lfreeVars = ((char*(*)(char*,char*,char*,char*))findFreeVars)(tokens, lp2, lbodyEnd, lparams2);
                char* lfvc = ((char*)"0");
                if (kr_truthy(kr_gt(kr_len(lfreeVars), ((char*)"0")))) {
                    lfvc = kr_linecount(lfreeVars);
                }
                char* lcapDecls = ((char*)"");
                char* lcapInits = ((char*)"");
                char* lfvi2 = ((char*)"0");
                while (kr_truthy(kr_lt(lfvi2, lfvc))) {
                    char* fvn2 = ((char*(*)(char*))cIdent)(kr_split(lfreeVars, lfvi2));
                    lcapDecls = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(lcapDecls, ((char*)"static char* _krlam")), lsi), ((char*)"_")), fvn2), ((char*)";\n"));
                    lcapInits = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(lcapInits, ((char*)"    char* ")), fvn2), ((char*)" = _krlam")), lsi), ((char*)"_")), fvn2), ((char*)";\n"));
                    lfvi2 = kr_plus(lfvi2, ((char*)"1"));
                }
                lambdaBank = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(lambdaBank, lcapDecls), ((char*)"static ")), lsig), ((char*)" {\n")), lbcode), ((char*)"return _K_EMPTY;\n}\n\n"));
            }
        }
        lsi = kr_plus(lsi, ((char*)"1"));
    }
    char* ii = ((char*)"0");
    while (kr_truthy(kr_lt(ii, ntoks))) {
        char* itok = ((char*(*)(char*,char*))tokAt)(tokens, ii);
        if (kr_truthy(kr_eq(itok, ((char*)"KW:import")))) {
            char* importPath = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(ii, ((char*)"1"))));
            char* fullPath = importPath;
            char* colonAt = kr_indexof(importPath, ((char*)":"));
            if (kr_truthy((kr_truthy(kr_gt(colonAt, ((char*)"0"))) && kr_truthy(kr_lt(colonAt, ((char*)"8"))) ? kr_str("1") : kr_str("0")))) {
                char* prefix = kr_substr(importPath, ((char*)"0"), colonAt);
                char* sub = kr_substr(importPath, kr_plus(colonAt, ((char*)"1")), kr_len(importPath));
                if (kr_truthy(kr_eq(prefix, ((char*)"k")))) {
                    fullPath = kr_plus(kr_plus(kr_plus(installRoot, ((char*)"/stdlib/")), sub), ((char*)".k"));
                }
                if (kr_truthy(kr_eq(prefix, ((char*)"core")))) {
                    fullPath = kr_plus(kr_plus(kr_plus(installRoot, ((char*)"/stdlib/")), sub), ((char*)".k"));
                }
                if (kr_truthy(kr_eq(prefix, ((char*)"head")))) {
                    fullPath = kr_plus(kr_plus(kr_plus(installRoot, ((char*)"/headers/")), sub), ((char*)".krh"));
                }
                if (kr_truthy(kr_eq(prefix, ((char*)"headers")))) {
                    fullPath = kr_plus(kr_plus(kr_plus(installRoot, ((char*)"/headers/")), sub), ((char*)".krh"));
                }
            }
            if (kr_truthy(kr_gt(kr_len(baseDir), ((char*)"0")))) {
                if (kr_truthy(kr_not(kr_startswith(importPath, ((char*)"/"))))) {
                    if (kr_truthy(kr_not(kr_startswith(importPath, ((char*)"C:"))))) {
                        if (kr_truthy(kr_not(kr_startswith(fullPath, installRoot)))) {
                            char* relPath = kr_plus(baseDir, importPath);
                            char* testSrc = kr_readfile(relPath);
                            if (kr_truthy(kr_gt(kr_len(testSrc), ((char*)"0")))) {
                                fullPath = relPath;
                            }
                        }
                    }
                }
            }
            char* testSrc2 = kr_readfile(fullPath);
            if (kr_truthy(kr_eq(kr_len(testSrc2), ((char*)"0")))) {
                char* hdPath = kr_plus(kr_plus(installRoot, ((char*)"/headers/")), importPath);
                char* testSrc3 = kr_readfile(hdPath);
                if (kr_truthy(kr_gt(kr_len(testSrc3), ((char*)"0")))) {
                    fullPath = hdPath;
                }
            }
            char* testSrc4 = kr_readfile(fullPath);
            if (kr_truthy(kr_eq(kr_len(testSrc4), ((char*)"0")))) {
                char* stdPath = kr_plus(kr_plus(installRoot, ((char*)"/")), importPath);
                char* testSrc5 = kr_readfile(stdPath);
                if (kr_truthy(kr_gt(kr_len(testSrc5), ((char*)"0")))) {
                    fullPath = stdPath;
                }
            }
            if (kr_truthy(kr_not(kr_contains(imported, kr_plus(fullPath, ((char*)"|")))))) {
                imported = kr_plus(kr_plus(imported, fullPath), ((char*)"|"));
                char* importSrc = kr_readfile(fullPath);
                if (kr_truthy(kr_gt(kr_len(importSrc), ((char*)"0")))) {
                    char* iToks = ((char*(*)(char*))tokenize)(importSrc);
                    char* iNtoks = kr_linecount(iToks);
                    char* iFtable = ((char*(*)(char*,char*))scanFunctions)(iToks, iNtoks);
                    char* iDecls = ((char*)"");
                    char* ij = ((char*)"0");
                    while (kr_truthy(kr_lt(ij, iNtoks))) {
                        char* itk = ((char*(*)(char*,char*))tokAt)(iToks, ij);
                        if (kr_truthy(kr_eq(itk, ((char*)"KW:jxt")))) {
                            char* ijxtPos = kr_plus(ij, ((char*)"2"));
                            char* ijxtHasCHeader = ((char*)"0");
                            while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(iToks, ijxtPos), ((char*)"RBRACE")))) {
                                char* ijLang = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(iToks, ijxtPos));
                                if (kr_truthy((kr_truthy(kr_eq(ijLang, ((char*)"c"))) || kr_truthy(kr_eq(ijLang, ((char*)"t"))) ? kr_str("1") : kr_str("0")))) {
                                    char* ijPath = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(iToks, kr_plus(ijxtPos, ((char*)"1"))));
                                    ijxtHasCHeader = ((char*)"1");
                                    char* ijIncLine = ((char*)"");
                                    if (kr_truthy((kr_truthy(kr_contains(ijPath, ((char*)"/"))) || kr_truthy(kr_contains(ijPath, ((char*)"\\"))) ? kr_str("1") : kr_str("0")))) {
                                        ijIncLine = kr_plus(kr_plus(((char*)"#include \""), ijPath), ((char*)"\"\n"));
                                    } else {
                                        ijIncLine = kr_plus(kr_plus(((char*)"#include <"), ijPath), ((char*)">\n"));
                                    }
                                    if (kr_truthy(kr_eq(ijLang, ((char*)"c")))) {
                                        iDecls = kr_plus(ijIncLine, iDecls);
                                    } else {
                                        iDecls = kr_plus(iDecls, ijIncLine);
                                    }
                                    ijxtPos = kr_plus(ijxtPos, ((char*)"2"));
                                } else if (kr_truthy(kr_eq(ijLang, ((char*)"struct")))) {
                                    char* isName = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(iToks, kr_plus(ijxtPos, ((char*)"1"))));
                                    char* isfPos = kr_plus(ijxtPos, ((char*)"3"));
                                    char* isEntry = kr_plus(isName, ((char*)":"));
                                    char* isFirst = ((char*)"1");
                                    char* getBody = ((char*)"");
                                    char* setBody = ((char*)"");
                                    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(iToks, isfPos), ((char*)"RBRACE")))) {
                                        if (kr_truthy(kr_eq(((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(iToks, isfPos)), ((char*)"field")))) {
                                            char* isfName = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(iToks, kr_plus(isfPos, ((char*)"1"))));
                                            char* isfType = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(iToks, kr_plus(isfPos, ((char*)"2"))));
                                            char* isfCPath = isfName;
                                            if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(iToks, kr_plus(isfPos, ((char*)"3")))), ((char*)"STR")))) {
                                                isfCPath = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(iToks, kr_plus(isfPos, ((char*)"3"))));
                                                isfPos = kr_plus(isfPos, ((char*)"4"));
                                            } else {
                                                isfPos = kr_plus(isfPos, ((char*)"3"));
                                            }
                                            if (kr_truthy(kr_eq(isFirst, ((char*)"0")))) {
                                                isEntry = kr_plus(isEntry, ((char*)","));
                                            }
                                            isEntry = kr_plus(kr_plus(kr_plus(isEntry, isfName), ((char*)":")), isfType);
                                            isFirst = ((char*)"0");
                                            char* getExpr = kr_plus(kr_plus(((char*)"kr_itoa(s->"), isfCPath), ((char*)")"));
                                            if (kr_truthy((kr_truthy((kr_truthy(kr_eq(isfType, ((char*)"ULONGLONG"))) || kr_truthy(kr_eq(isfType, ((char*)"SIZE_T"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(isfType, ((char*)"ULONG_PTR"))) ? kr_str("1") : kr_str("0")))) {
                                                getExpr = kr_plus(kr_plus(((char*)"({ char _b[32]; snprintf(_b,32,\"%llu\",(unsigned long long)s->"), isfCPath), ((char*)"); kr_str(_b); })"));
                                            }
                                            if (kr_truthy(kr_eq(isfType, ((char*)"LONGLONG")))) {
                                                getExpr = kr_plus(kr_plus(((char*)"({ char _b[32]; snprintf(_b,32,\"%lld\",(long long)s->"), isfCPath), ((char*)"); kr_str(_b); })"));
                                            }
                                            if (kr_truthy((kr_truthy(kr_eq(isfType, ((char*)"HANDLE"))) || kr_truthy(kr_eq(isfType, ((char*)"PVOID"))) ? kr_str("1") : kr_str("0")))) {
                                                getExpr = kr_plus(kr_plus(((char*)"((char*)s->"), isfCPath), ((char*)")"));
                                            }
                                            if (kr_truthy(kr_eq(isfType, ((char*)"CHAR_ARRAY")))) {
                                                getExpr = kr_plus(kr_plus(((char*)"kr_str(s->"), isfCPath), ((char*)")"));
                                            }
                                            if (kr_truthy((kr_truthy((kr_truthy(kr_eq(isfType, ((char*)"BYTE"))) || kr_truthy(kr_eq(isfType, ((char*)"UCHAR"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(isfType, ((char*)"BOOL"))) ? kr_str("1") : kr_str("0")))) {
                                                getExpr = kr_plus(kr_plus(((char*)"kr_itoa((int)(unsigned char)s->"), isfCPath), ((char*)")"));
                                            }
                                            getBody = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(getBody, ((char*)"    if(strcmp(f,\"")), isfName), ((char*)"\")==0) return ")), getExpr), ((char*)";\n"));
                                            char* setStmt = kr_plus(kr_plus(((char*)"s->"), isfCPath), ((char*)"=(DWORD)atoi(v);"));
                                            if (kr_truthy((kr_truthy((kr_truthy(kr_eq(isfType, ((char*)"ULONGLONG"))) || kr_truthy(kr_eq(isfType, ((char*)"SIZE_T"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(isfType, ((char*)"ULONG_PTR"))) ? kr_str("1") : kr_str("0")))) {
                                                setStmt = kr_plus(kr_plus(((char*)"s->"), isfCPath), ((char*)"=(ULONGLONG)atoll(v);"));
                                            }
                                            if (kr_truthy(kr_eq(isfType, ((char*)"LONGLONG")))) {
                                                setStmt = kr_plus(kr_plus(((char*)"s->"), isfCPath), ((char*)"=(LONGLONG)atoll(v);"));
                                            }
                                            if (kr_truthy((kr_truthy(kr_eq(isfType, ((char*)"WORD"))) || kr_truthy(kr_eq(isfType, ((char*)"USHORT"))) ? kr_str("1") : kr_str("0")))) {
                                                setStmt = kr_plus(kr_plus(((char*)"s->"), isfCPath), ((char*)"=(WORD)atoi(v);"));
                                            }
                                            if (kr_truthy((kr_truthy((kr_truthy(kr_eq(isfType, ((char*)"BYTE"))) || kr_truthy(kr_eq(isfType, ((char*)"UCHAR"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(isfType, ((char*)"BOOL"))) ? kr_str("1") : kr_str("0")))) {
                                                setStmt = kr_plus(kr_plus(((char*)"s->"), isfCPath), ((char*)"=(BYTE)atoi(v);"));
                                            }
                                            if (kr_truthy((kr_truthy(kr_eq(isfType, ((char*)"HANDLE"))) || kr_truthy(kr_eq(isfType, ((char*)"PVOID"))) ? kr_str("1") : kr_str("0")))) {
                                                setStmt = kr_plus(kr_plus(((char*)"s->"), isfCPath), ((char*)"=(HANDLE)v;"));
                                            }
                                            if (kr_truthy(kr_eq(isfType, ((char*)"CHAR_ARRAY")))) {
                                                setStmt = kr_plus(kr_plus(kr_plus(kr_plus(((char*)"strncpy(s->"), isfCPath), ((char*)",v,sizeof(s->")), isfCPath), ((char*)")-1);"));
                                            }
                                            setBody = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(setBody, ((char*)"    if(strcmp(f,\"")), isfName), ((char*)"\")==0){")), setStmt), ((char*)" return _K_EMPTY;}\n"));
                                        } else {
                                            isfPos = kr_plus(isfPos, ((char*)"1"));
                                        }
                                    }
                                    structTable = kr_plus(kr_plus(structTable, isEntry), ((char*)"\n"));
                                    char* sAcc = kr_plus(kr_plus(((char*)"static char* structnew_"), isName), ((char*)"(void){"));
                                    sAcc = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(sAcc, isName), ((char*)"* s=(")), isName), ((char*)"*)_alloc(sizeof(")), isName), ((char*)"));"));
                                    sAcc = kr_plus(kr_plus(kr_plus(sAcc, ((char*)"memset(s,0,sizeof(")), isName), ((char*)")); return (char*)s;}\n"));
                                    sAcc = kr_plus(kr_plus(kr_plus(sAcc, ((char*)"static char* structget_")), isName), ((char*)"(char* p,char* f){"));
                                    sAcc = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(sAcc, isName), ((char*)"* s=(")), isName), ((char*)"*)p;\n")), getBody);
                                    sAcc = kr_plus(sAcc, ((char*)"    return _K_EMPTY;}\n"));
                                    sAcc = kr_plus(kr_plus(kr_plus(sAcc, ((char*)"static char* structset_")), isName), ((char*)"(char* p,char* f,char* v){"));
                                    sAcc = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(sAcc, isName), ((char*)"* s=(")), isName), ((char*)"*)p;\n")), setBody);
                                    sAcc = kr_plus(sAcc, ((char*)"    return _K_EMPTY;}\n"));
                                    sAcc = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(sAcc, ((char*)"static char* structsizeof_")), isName), ((char*)"(void){return kr_itoa(sizeof(")), isName), ((char*)"));}\n"));
                                    iDecls = kr_plus(iDecls, sAcc);
                                    ijxtPos = kr_plus(isfPos, ((char*)"1"));
                                } else if (kr_truthy(kr_eq(ijLang, ((char*)"func")))) {
                                    char* ijfName = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(iToks, kr_plus(ijxtPos, ((char*)"1"))));
                                    char* ijfPos = kr_plus(ijxtPos, ((char*)"3"));
                                    char* ijfPc = ((char*)"0");
                                    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(iToks, ijfPos), ((char*)"RPAREN")))) {
                                        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(iToks, ijfPos)), ((char*)"ID")))) {
                                            ijfPc = kr_plus(ijfPc, ((char*)"1"));
                                        }
                                        ijfPos = kr_plus(ijfPos, ((char*)"1"));
                                    }
                                    if (kr_truthy(kr_eq(ijxtHasCHeader, ((char*)"0")))) {
                                        char* ijfDecl = kr_plus(kr_plus(((char*)"char* "), ((char*(*)(char*))cIdent)(ijfName)), ((char*)"(char*"));
                                        if (kr_truthy(kr_eq(ijfPc, ((char*)"0")))) {
                                            ijfDecl = kr_plus(kr_plus(((char*)"char* "), ((char*(*)(char*))cIdent)(ijfName)), ((char*)"("));
                                        }
                                        char* ijfPi = ((char*)"1");
                                        while (kr_truthy(kr_lt(ijfPi, ijfPc))) {
                                            ijfDecl = kr_plus(ijfDecl, ((char*)", char*"));
                                            ijfPi = kr_plus(ijfPi, ((char*)"1"));
                                        }
                                        ijfDecl = kr_plus(ijfDecl, ((char*)");\n"));
                                        iDecls = kr_plus(iDecls, ijfDecl);
                                    }
                                    char* ijfInfo = kr_plus(kr_plus(kr_plus(ijfName, ((char*)":")), ijfPc), ((char*)":0"));
                                    if (kr_truthy(kr_gt(kr_len(ftable), ((char*)"0")))) {
                                        ftable = kr_plus(kr_plus(ftable, ((char*)"\n")), ijfInfo);
                                    } else {
                                        ftable = ijfInfo;
                                    }
                                    ijfPos = kr_plus(ijfPos, ((char*)"1"));
                                    char* ijfRetType = ((char*)"");
                                    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(iToks, ijfPos), ((char*)"ARROW")))) {
                                        ijfRetType = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(iToks, kr_plus(ijfPos, ((char*)"1"))));
                                        ijfPos = kr_plus(ijfPos, ((char*)"2"));
                                    }
                                    char* ijfCName = ((char*(*)(char*))cIdent)(ijfName);
                                    char* _iHasMarshal = ((char*)"0");
                                    if (kr_truthy(kr_gt(kr_len(((char*(*)(char*))compileWin32IntReturn)(ijfCName)), ((char*)"0")))) {
                                        _iHasMarshal = ((char*)"1");
                                    }
                                    if (kr_truthy(kr_gt(kr_len(((char*(*)(char*))compileWin32IntArgs)(ijfCName)), ((char*)"0")))) {
                                        _iHasMarshal = ((char*)"1");
                                    }
                                    if (kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(ijfRetType, ((char*)"INT"))) || kr_truthy(kr_eq(ijfRetType, ((char*)"UINT"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(ijfRetType, ((char*)"DWORD"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(ijfRetType, ((char*)"LONG"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(ijfRetType, ((char*)"BOOL"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_eq(_iHasMarshal, ((char*)"0"))) ? kr_str("1") : kr_str("0")))) {
                                        char* iwd = kr_plus(kr_plus(((char*)"static char* _krw_"), ijfCName), ((char*)"("));
                                        char* iwpi = ((char*)"0");
                                        while (kr_truthy(kr_lt(iwpi, ijfPc))) {
                                            if (kr_truthy(kr_gt(iwpi, ((char*)"0")))) {
                                                iwd = kr_plus(iwd, ((char*)","));
                                            }
                                            iwd = kr_plus(kr_plus(iwd, ((char*)"char* _a")), iwpi);
                                            iwpi = kr_plus(iwpi, ((char*)"1"));
                                        }
                                        if (kr_truthy(kr_eq(ijfPc, ((char*)"0")))) {
                                            iwd = kr_plus(iwd, ((char*)"void"));
                                        }
                                        iwd = kr_plus(kr_plus(kr_plus(iwd, ((char*)"){return kr_itoa((int)")), ijfCName), ((char*)"("));
                                        iwpi = ((char*)"0");
                                        while (kr_truthy(kr_lt(iwpi, ijfPc))) {
                                            if (kr_truthy(kr_gt(iwpi, ((char*)"0")))) {
                                                iwd = kr_plus(iwd, ((char*)","));
                                            }
                                            iwd = kr_plus(kr_plus(iwd, ((char*)"_a")), iwpi);
                                            iwpi = kr_plus(iwpi, ((char*)"1"));
                                        }
                                        iwd = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(iwd, ((char*)"));}\n#define ")), ijfCName), ((char*)" _krw_")), ijfCName), ((char*)"\n"));
                                        iDecls = kr_plus(iDecls, iwd);
                                    }
                                    if (kr_truthy((kr_truthy((kr_truthy(kr_eq(ijfRetType, ((char*)"UINT64"))) || kr_truthy(kr_eq(ijfRetType, ((char*)"ULONGLONG"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_eq(_iHasMarshal, ((char*)"0"))) ? kr_str("1") : kr_str("0")))) {
                                        char* iwd = kr_plus(kr_plus(((char*)"static char* _krw_"), ijfCName), ((char*)"("));
                                        char* iwpi = ((char*)"0");
                                        while (kr_truthy(kr_lt(iwpi, ijfPc))) {
                                            if (kr_truthy(kr_gt(iwpi, ((char*)"0")))) {
                                                iwd = kr_plus(iwd, ((char*)","));
                                            }
                                            iwd = kr_plus(kr_plus(iwd, ((char*)"char* _a")), iwpi);
                                            iwpi = kr_plus(iwpi, ((char*)"1"));
                                        }
                                        if (kr_truthy(kr_eq(ijfPc, ((char*)"0")))) {
                                            iwd = kr_plus(iwd, ((char*)"void"));
                                        }
                                        iwd = kr_plus(kr_plus(kr_plus(iwd, ((char*)"){char _b[32];snprintf(_b,32,\"%llu\",(unsigned long long)")), ijfCName), ((char*)"("));
                                        iwpi = ((char*)"0");
                                        while (kr_truthy(kr_lt(iwpi, ijfPc))) {
                                            if (kr_truthy(kr_gt(iwpi, ((char*)"0")))) {
                                                iwd = kr_plus(iwd, ((char*)","));
                                            }
                                            iwd = kr_plus(kr_plus(iwd, ((char*)"_a")), iwpi);
                                            iwpi = kr_plus(iwpi, ((char*)"1"));
                                        }
                                        iwd = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(iwd, ((char*)"));return kr_str(_b);}\n#define ")), ijfCName), ((char*)" _krw_")), ijfCName), ((char*)"\n"));
                                        iDecls = kr_plus(iDecls, iwd);
                                    }
                                    if (kr_truthy((kr_truthy(kr_eq(ijfRetType, ((char*)"zero"))) && kr_truthy(kr_eq(_iHasMarshal, ((char*)"0"))) ? kr_str("1") : kr_str("0")))) {
                                        char* iwd = kr_plus(kr_plus(((char*)"static char* _krw_"), ijfCName), ((char*)"("));
                                        char* iwpi = ((char*)"0");
                                        while (kr_truthy(kr_lt(iwpi, ijfPc))) {
                                            if (kr_truthy(kr_gt(iwpi, ((char*)"0")))) {
                                                iwd = kr_plus(iwd, ((char*)","));
                                            }
                                            iwd = kr_plus(kr_plus(iwd, ((char*)"char* _a")), iwpi);
                                            iwpi = kr_plus(iwpi, ((char*)"1"));
                                        }
                                        if (kr_truthy(kr_eq(ijfPc, ((char*)"0")))) {
                                            iwd = kr_plus(iwd, ((char*)"void"));
                                        }
                                        iwd = kr_plus(kr_plus(kr_plus(iwd, ((char*)"){")), ijfCName), ((char*)"("));
                                        iwpi = ((char*)"0");
                                        while (kr_truthy(kr_lt(iwpi, ijfPc))) {
                                            if (kr_truthy(kr_gt(iwpi, ((char*)"0")))) {
                                                iwd = kr_plus(iwd, ((char*)","));
                                            }
                                            iwd = kr_plus(kr_plus(iwd, ((char*)"_a")), iwpi);
                                            iwpi = kr_plus(iwpi, ((char*)"1"));
                                        }
                                        iwd = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(iwd, ((char*)");return _K_EMPTY;}\n#define ")), ijfCName), ((char*)" _krw_")), ijfCName), ((char*)"\n"));
                                        iDecls = kr_plus(iDecls, iwd);
                                    }
                                    ijxtPos = ijfPos;
                                } else {
                                    ijxtPos = kr_plus(ijxtPos, ((char*)"2"));
                                }
                            }
                            ij = kr_sub(((char*(*)(char*,char*))skipBlock)(iToks, kr_plus(ij, ((char*)"1"))), ((char*)"1"));
                        } else if (kr_truthy((kr_truthy(kr_eq(itk, ((char*)"KW:func"))) || kr_truthy(kr_eq(itk, ((char*)"KW:fn"))) ? kr_str("1") : kr_str("0")))) {
                            char* iname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(iToks, kr_plus(ij, ((char*)"1"))));
                            if (kr_truthy(kr_gt(kr_len(iname), ((char*)"0")))) {
                                char* iinfo = ((char*(*)(char*,char*))funcLookup)(iFtable, iname);
                                char* ipc = ((char*(*)(char*))funcParamCount)(iinfo);
                                char* idecl = kr_plus(kr_plus(((char*)"char* "), ((char*(*)(char*))cIdent)(iname)), ((char*)"(char*"));
                                char* ipj = ((char*)"1");
                                while (kr_truthy(kr_lt(kr_toint(ipj), kr_toint(ipc)))) {
                                    idecl = kr_plus(idecl, ((char*)", char*"));
                                    ipj = kr_plus(ipj, ((char*)"1"));
                                }
                                if (kr_truthy(kr_eq(kr_toint(ipc), ((char*)"0")))) {
                                    idecl = kr_plus(kr_plus(((char*)"char* "), ((char*(*)(char*))cIdent)(iname)), ((char*)"("));
                                }
                                idecl = kr_plus(idecl, ((char*)");\n"));
                                iDecls = kr_plus(iDecls, idecl);
                            }
                        } else if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(itk), ((char*)"CBLOCK")))) {
                            char* icraw = kr_replace(((char*(*)(char*))tokVal)(itk), ((char*)"\\x01"), ((char*)"\n"));
                            iDecls = kr_plus(kr_plus(iDecls, icraw), ((char*)"\n"));
                        }
                        ij = kr_plus(ij, ((char*)"1"));
                    }
                    importFwdDecls = kr_plus(kr_plus(kr_plus(importFwdDecls, ((char*)"// --- imported: ")), fullPath), ((char*)" ---\n"));
                    importFwdDecls = kr_plus(importFwdDecls, iDecls);
                    char* iBodies = ((char*(*)(char*,char*,char*))compileImportedFunctions)(iToks, iNtoks, iFtable);
                    importBodies = kr_plus(importBodies, iBodies);
                    if (kr_truthy(kr_eq(irMode, ((char*)"1")))) {
                        char* iIRi = ((char*)"0");
                        char* iIRinJxt = ((char*)"0");
                        while (kr_truthy(kr_lt(iIRi, iNtoks))) {
                            char* iIRtok = ((char*(*)(char*,char*))tokAt)(iToks, iIRi);
                            if (kr_truthy(kr_eq(iIRtok, ((char*)"KW:jxt")))) {
                                iIRi = ((char*(*)(char*,char*))skipBlock)(iToks, kr_plus(iIRi, ((char*)"1")));
                            } else if (kr_truthy((kr_truthy(kr_eq(iIRtok, ((char*)"KW:func"))) || kr_truthy(kr_eq(iIRtok, ((char*)"KW:fn"))) ? kr_str("1") : kr_str("0")))) {
                                char* iIRfp = ((char*(*)(char*,char*,char*))irFuncIR)(iToks, iIRi, iNtoks);
                                importedIR = kr_plus(importedIR, ((char*(*)(char*))pairVal)(iIRfp));
                                iIRi = ((char*(*)(char*))pairPos)(iIRfp);
                            } else {
                                iIRi = kr_plus(iIRi, ((char*)"1"));
                            }
                        }
                    }
                    if (kr_truthy(kr_gt(kr_len(iFtable), ((char*)"0")))) {
                        if (kr_truthy(kr_gt(kr_len(ftable), ((char*)"0")))) {
                            ftable = kr_plus(kr_plus(ftable, ((char*)"\n")), iFtable);
                        } else {
                            ftable = iFtable;
                        }
                    }
                } else {
                    kr_printerr(kr_plus(((char*)"kcc: import not found: "), fullPath));
                }
            }
            ii = kr_plus(ii, ((char*)"2"));
        } else if (kr_truthy(kr_eq(itok, ((char*)"KW:jxt")))) {
            char* jxtPos = kr_plus(ii, ((char*)"2"));
            char* jxtHasCHeader = ((char*)"0");
            while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, jxtPos), ((char*)"RBRACE")))) {
                char* lang = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, jxtPos));
                char* jxtPath = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(jxtPos, ((char*)"1"))));
                if (kr_truthy(kr_eq(lang, ((char*)"k")))) {
                    char* jFullPath = jxtPath;
                    if (kr_truthy(kr_gt(kr_len(baseDir), ((char*)"0")))) {
                        if (kr_truthy((kr_truthy(kr_not(kr_startswith(jxtPath, ((char*)"/")))) && kr_truthy(kr_not(kr_startswith(jxtPath, ((char*)"C:")))) ? kr_str("1") : kr_str("0")))) {
                            jFullPath = kr_plus(baseDir, jxtPath);
                        }
                    }
                    if (kr_truthy(kr_not(kr_contains(imported, kr_plus(jFullPath, ((char*)"|")))))) {
                        imported = kr_plus(kr_plus(imported, jFullPath), ((char*)"|"));
                        char* jSrc = kr_readfile(jFullPath);
                        if (kr_truthy(kr_gt(kr_len(jSrc), ((char*)"0")))) {
                            char* jToks = ((char*(*)(char*))tokenize)(jSrc);
                            char* jNt = kr_linecount(jToks);
                            char* jFt = ((char*(*)(char*,char*))scanFunctions)(jToks, jNt);
                            importFwdDecls = kr_plus(kr_plus(kr_plus(importFwdDecls, ((char*)"// --- jxt: ")), jFullPath), ((char*)" ---\n"));
                            importBodies = kr_plus(importBodies, ((char*(*)(char*,char*,char*))compileImportedFunctions)(jToks, jNt, jFt));
                            if (kr_truthy(kr_gt(kr_len(jFt), ((char*)"0")))) {
                                if (kr_truthy(kr_gt(kr_len(ftable), ((char*)"0")))) {
                                    ftable = kr_plus(kr_plus(ftable, ((char*)"\n")), jFt);
                                } else {
                                    ftable = jFt;
                                }
                            }
                        } else {
                            kr_printerr(kr_plus(((char*)"kcc: jxt k not found: "), jFullPath));
                        }
                    }
                    jxtPos = kr_plus(jxtPos, ((char*)"2"));
                } else if (kr_truthy((kr_truthy(kr_eq(lang, ((char*)"c"))) || kr_truthy(kr_eq(lang, ((char*)"t"))) ? kr_str("1") : kr_str("0")))) {
                    jxtHasCHeader = ((char*)"1");
                    char* jIncLine = ((char*)"");
                    if (kr_truthy((kr_truthy(kr_contains(jxtPath, ((char*)"/"))) || kr_truthy(kr_contains(jxtPath, ((char*)"\\"))) ? kr_str("1") : kr_str("0")))) {
                        jIncLine = kr_plus(kr_plus(((char*)"#include \""), jxtPath), ((char*)"\"\n"));
                    } else {
                        jIncLine = kr_plus(kr_plus(((char*)"#include <"), jxtPath), ((char*)">\n"));
                    }
                    if (kr_truthy(kr_eq(lang, ((char*)"c")))) {
                        importFwdDecls = kr_plus(jIncLine, importFwdDecls);
                    } else {
                        importFwdDecls = kr_plus(importFwdDecls, jIncLine);
                    }
                    jxtPos = kr_plus(jxtPos, ((char*)"2"));
                } else if (kr_truthy(kr_eq(lang, ((char*)"struct")))) {
                    char* sName = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(jxtPos, ((char*)"1"))));
                    char* sfPos = kr_plus(jxtPos, ((char*)"3"));
                    char* sEntry = kr_plus(sName, ((char*)":"));
                    char* sfFirst = ((char*)"1");
                    char* getBody = ((char*)"");
                    char* setBody = ((char*)"");
                    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, sfPos), ((char*)"RBRACE")))) {
                        if (kr_truthy(kr_eq(((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, sfPos)), ((char*)"field")))) {
                            char* sfName = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(sfPos, ((char*)"1"))));
                            char* sfType = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(sfPos, ((char*)"2"))));
                            char* sfCPath = sfName;
                            if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(sfPos, ((char*)"3")))), ((char*)"STR")))) {
                                sfCPath = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(sfPos, ((char*)"3"))));
                                sfPos = kr_plus(sfPos, ((char*)"4"));
                            } else {
                                sfPos = kr_plus(sfPos, ((char*)"3"));
                            }
                            if (kr_truthy(kr_eq(sfFirst, ((char*)"0")))) {
                                sEntry = kr_plus(sEntry, ((char*)","));
                            }
                            sEntry = kr_plus(kr_plus(kr_plus(sEntry, sfName), ((char*)":")), sfType);
                            sfFirst = ((char*)"0");
                            char* getExpr = kr_plus(kr_plus(((char*)"kr_itoa(s->"), sfCPath), ((char*)")"));
                            if (kr_truthy((kr_truthy((kr_truthy(kr_eq(sfType, ((char*)"ULONGLONG"))) || kr_truthy(kr_eq(sfType, ((char*)"SIZE_T"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(sfType, ((char*)"ULONG_PTR"))) ? kr_str("1") : kr_str("0")))) {
                                getExpr = kr_plus(kr_plus(((char*)"({ char _b[32]; snprintf(_b,32,\"%llu\",(unsigned long long)s->"), sfCPath), ((char*)"); kr_str(_b); })"));
                            }
                            if (kr_truthy(kr_eq(sfType, ((char*)"LONGLONG")))) {
                                getExpr = kr_plus(kr_plus(((char*)"({ char _b[32]; snprintf(_b,32,\"%lld\",(long long)s->"), sfCPath), ((char*)"); kr_str(_b); })"));
                            }
                            if (kr_truthy((kr_truthy((kr_truthy(kr_eq(sfType, ((char*)"HANDLE"))) || kr_truthy(kr_eq(sfType, ((char*)"PVOID"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(sfType, ((char*)"LPVOID"))) ? kr_str("1") : kr_str("0")))) {
                                getExpr = kr_plus(kr_plus(((char*)"((char*)s->"), sfCPath), ((char*)")"));
                            }
                            if (kr_truthy(kr_eq(sfType, ((char*)"CHAR_ARRAY")))) {
                                getExpr = kr_plus(kr_plus(((char*)"kr_str(s->"), sfCPath), ((char*)")"));
                            }
                            if (kr_truthy((kr_truthy((kr_truthy(kr_eq(sfType, ((char*)"BYTE"))) || kr_truthy(kr_eq(sfType, ((char*)"UCHAR"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(sfType, ((char*)"BOOL"))) ? kr_str("1") : kr_str("0")))) {
                                getExpr = kr_plus(kr_plus(((char*)"kr_itoa((int)(unsigned char)s->"), sfCPath), ((char*)")"));
                            }
                            getBody = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(getBody, ((char*)"    if(strcmp(f,\"")), sfName), ((char*)"\")==0) return ")), getExpr), ((char*)";\n"));
                            char* setStmt = kr_plus(kr_plus(((char*)"s->"), sfCPath), ((char*)"=(DWORD)atoi(v);"));
                            if (kr_truthy((kr_truthy((kr_truthy(kr_eq(sfType, ((char*)"ULONGLONG"))) || kr_truthy(kr_eq(sfType, ((char*)"SIZE_T"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(sfType, ((char*)"ULONG_PTR"))) ? kr_str("1") : kr_str("0")))) {
                                setStmt = kr_plus(kr_plus(((char*)"s->"), sfCPath), ((char*)"=(ULONGLONG)atoll(v);"));
                            }
                            if (kr_truthy(kr_eq(sfType, ((char*)"LONGLONG")))) {
                                setStmt = kr_plus(kr_plus(((char*)"s->"), sfCPath), ((char*)"=(LONGLONG)atoll(v);"));
                            }
                            if (kr_truthy((kr_truthy(kr_eq(sfType, ((char*)"WORD"))) || kr_truthy(kr_eq(sfType, ((char*)"USHORT"))) ? kr_str("1") : kr_str("0")))) {
                                setStmt = kr_plus(kr_plus(((char*)"s->"), sfCPath), ((char*)"=(WORD)atoi(v);"));
                            }
                            if (kr_truthy((kr_truthy((kr_truthy(kr_eq(sfType, ((char*)"BYTE"))) || kr_truthy(kr_eq(sfType, ((char*)"UCHAR"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(sfType, ((char*)"BOOL"))) ? kr_str("1") : kr_str("0")))) {
                                setStmt = kr_plus(kr_plus(((char*)"s->"), sfCPath), ((char*)"=(BYTE)atoi(v);"));
                            }
                            if (kr_truthy((kr_truthy(kr_eq(sfType, ((char*)"HANDLE"))) || kr_truthy(kr_eq(sfType, ((char*)"PVOID"))) ? kr_str("1") : kr_str("0")))) {
                                setStmt = kr_plus(kr_plus(((char*)"s->"), sfCPath), ((char*)"=(HANDLE)v;"));
                            }
                            if (kr_truthy(kr_eq(sfType, ((char*)"CHAR_ARRAY")))) {
                                setStmt = kr_plus(kr_plus(kr_plus(kr_plus(((char*)"strncpy(s->"), sfCPath), ((char*)",v,sizeof(s->")), sfCPath), ((char*)")-1);"));
                            }
                            setBody = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(setBody, ((char*)"    if(strcmp(f,\"")), sfName), ((char*)"\")==0){")), setStmt), ((char*)" return _K_EMPTY;}\n"));
                        } else {
                            sfPos = kr_plus(sfPos, ((char*)"1"));
                        }
                    }
                    structTable = kr_plus(kr_plus(structTable, sEntry), ((char*)"\n"));
                    char* sAccessors = kr_plus(kr_plus(((char*)"static char* structnew_"), sName), ((char*)"(void){"));
                    sAccessors = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(sAccessors, sName), ((char*)"* s=(")), sName), ((char*)"*)_alloc(sizeof(")), sName), ((char*)"));"));
                    sAccessors = kr_plus(kr_plus(kr_plus(sAccessors, ((char*)"memset(s,0,sizeof(")), sName), ((char*)")); return (char*)s;}\n"));
                    sAccessors = kr_plus(kr_plus(kr_plus(sAccessors, ((char*)"static char* structget_")), sName), ((char*)"(char* p,char* f){"));
                    sAccessors = kr_plus(kr_plus(kr_plus(kr_plus(sAccessors, sName), ((char*)"* s=(")), sName), ((char*)"*)p;\n"));
                    sAccessors = kr_plus(sAccessors, getBody);
                    sAccessors = kr_plus(sAccessors, ((char*)"    return _K_EMPTY;}\n"));
                    sAccessors = kr_plus(kr_plus(kr_plus(sAccessors, ((char*)"static char* structset_")), sName), ((char*)"(char* p,char* f,char* v){"));
                    sAccessors = kr_plus(kr_plus(kr_plus(kr_plus(sAccessors, sName), ((char*)"* s=(")), sName), ((char*)"*)p;\n"));
                    sAccessors = kr_plus(sAccessors, setBody);
                    sAccessors = kr_plus(sAccessors, ((char*)"    return _K_EMPTY;}\n"));
                    sAccessors = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(sAccessors, ((char*)"static char* structsizeof_")), sName), ((char*)"(void){return kr_itoa(sizeof(")), sName), ((char*)"));}\n"));
                    importFwdDecls = kr_plus(importFwdDecls, sAccessors);
                    jxtPos = kr_plus(sfPos, ((char*)"1"));
                } else if (kr_truthy(kr_eq(lang, ((char*)"func")))) {
                    char* jfName = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(jxtPos, ((char*)"1"))));
                    char* jfCName = ((char*(*)(char*))cIdent)(jfName);
                    char* jfPos = kr_plus(jxtPos, ((char*)"3"));
                    char* jfParams = ((char*)"");
                    char* jfPc = ((char*)"0");
                    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, jfPos), ((char*)"RPAREN")))) {
                        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, jfPos)), ((char*)"ID")))) {
                            if (kr_truthy(kr_gt(jfPc, ((char*)"0")))) {
                                jfParams = kr_plus(jfParams, ((char*)","));
                            }
                            jfParams = kr_plus(jfParams, ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, jfPos)));
                            jfPc = kr_plus(jfPc, ((char*)"1"));
                        }
                        jfPos = kr_plus(jfPos, ((char*)"1"));
                    }
                    if (kr_truthy(kr_eq(jxtHasCHeader, ((char*)"0")))) {
                        char* jfDecl = kr_plus(kr_plus(((char*)"char* "), jfCName), ((char*)"(char*"));
                        char* jfPi = ((char*)"1");
                        while (kr_truthy(kr_lt(jfPi, jfPc))) {
                            jfDecl = kr_plus(jfDecl, ((char*)", char*"));
                            jfPi = kr_plus(jfPi, ((char*)"1"));
                        }
                        if (kr_truthy(kr_eq(jfPc, ((char*)"0")))) {
                            jfDecl = kr_plus(kr_plus(((char*)"char* "), jfCName), ((char*)"("));
                        }
                        jfDecl = kr_plus(jfDecl, ((char*)");\n"));
                        importFwdDecls = kr_plus(importFwdDecls, jfDecl);
                    }
                    char* jfInfo = kr_plus(kr_plus(kr_plus(jfName, ((char*)":")), jfPc), ((char*)":0"));
                    if (kr_truthy(kr_gt(kr_len(ftable), ((char*)"0")))) {
                        ftable = kr_plus(kr_plus(ftable, ((char*)"\n")), jfInfo);
                    } else {
                        ftable = jfInfo;
                    }
                    jfPos = kr_plus(jfPos, ((char*)"1"));
                    char* jfRetType = ((char*)"");
                    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, jfPos), ((char*)"ARROW")))) {
                        jfRetType = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(jfPos, ((char*)"1"))));
                        jfPos = kr_plus(jfPos, ((char*)"2"));
                    }
                    char* _hasNewMarshal = ((char*(*)(char*))compileWin32IntReturn)(jfCName);
                    if (kr_truthy((kr_truthy(kr_gt(kr_len(_hasNewMarshal), ((char*)"0"))) || kr_truthy(kr_gt(kr_len(((char*(*)(char*))compileWin32IntArgs)(jfCName)), ((char*)"0"))) ? kr_str("1") : kr_str("0")))) {
                    }
                    if (kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(jfRetType, ((char*)"INT"))) || kr_truthy(kr_eq(jfRetType, ((char*)"UINT"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(jfRetType, ((char*)"DWORD"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(jfRetType, ((char*)"LONG"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(jfRetType, ((char*)"BOOL"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_eq(kr_len(_hasNewMarshal), ((char*)"0"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_eq(kr_len(((char*(*)(char*))compileWin32IntArgs)(jfCName)), ((char*)"0"))) ? kr_str("1") : kr_str("0")))) {
                        char* wd = kr_plus(kr_plus(((char*)"static char* _krw_"), jfCName), ((char*)"("));
                        char* wpi = ((char*)"0");
                        while (kr_truthy(kr_lt(wpi, jfPc))) {
                            if (kr_truthy(kr_gt(wpi, ((char*)"0")))) {
                                wd = kr_plus(wd, ((char*)","));
                            }
                            wd = kr_plus(kr_plus(wd, ((char*)"char* _a")), wpi);
                            wpi = kr_plus(wpi, ((char*)"1"));
                        }
                        if (kr_truthy(kr_eq(jfPc, ((char*)"0")))) {
                            wd = kr_plus(wd, ((char*)"void"));
                        }
                        wd = kr_plus(kr_plus(kr_plus(wd, ((char*)"){return kr_itoa((int)")), jfCName), ((char*)"("));
                        wpi = ((char*)"0");
                        while (kr_truthy(kr_lt(wpi, jfPc))) {
                            if (kr_truthy(kr_gt(wpi, ((char*)"0")))) {
                                wd = kr_plus(wd, ((char*)","));
                            }
                            wd = kr_plus(kr_plus(wd, ((char*)"_a")), wpi);
                            wpi = kr_plus(wpi, ((char*)"1"));
                        }
                        wd = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(wd, ((char*)");}\n#define ")), jfCName), ((char*)" _krw_")), jfCName), ((char*)"\n"));
                        importFwdDecls = kr_plus(importFwdDecls, wd);
                    }
                    if (kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(jfRetType, ((char*)"UINT64"))) || kr_truthy(kr_eq(jfRetType, ((char*)"ULONGLONG"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_eq(kr_len(_hasNewMarshal), ((char*)"0"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_eq(kr_len(((char*(*)(char*))compileWin32IntArgs)(jfCName)), ((char*)"0"))) ? kr_str("1") : kr_str("0")))) {
                        char* wd = kr_plus(kr_plus(((char*)"static char* _krw_"), jfCName), ((char*)"("));
                        char* wpi = ((char*)"0");
                        while (kr_truthy(kr_lt(wpi, jfPc))) {
                            if (kr_truthy(kr_gt(wpi, ((char*)"0")))) {
                                wd = kr_plus(wd, ((char*)","));
                            }
                            wd = kr_plus(kr_plus(wd, ((char*)"char* _a")), wpi);
                            wpi = kr_plus(wpi, ((char*)"1"));
                        }
                        if (kr_truthy(kr_eq(jfPc, ((char*)"0")))) {
                            wd = kr_plus(wd, ((char*)"void"));
                        }
                        wd = kr_plus(kr_plus(kr_plus(wd, ((char*)"){char _b[32];snprintf(_b,32,\"%llu\",(unsigned long long)")), jfCName), ((char*)"("));
                        wpi = ((char*)"0");
                        while (kr_truthy(kr_lt(wpi, jfPc))) {
                            if (kr_truthy(kr_gt(wpi, ((char*)"0")))) {
                                wd = kr_plus(wd, ((char*)","));
                            }
                            wd = kr_plus(kr_plus(wd, ((char*)"_a")), wpi);
                            wpi = kr_plus(wpi, ((char*)"1"));
                        }
                        wd = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(wd, ((char*)"));return kr_str(_b);}\n#define ")), jfCName), ((char*)" _krw_")), jfCName), ((char*)"\n"));
                        importFwdDecls = kr_plus(importFwdDecls, wd);
                    }
                    if (kr_truthy((kr_truthy((kr_truthy(kr_eq(jfRetType, ((char*)"zero"))) && kr_truthy(kr_eq(kr_len(_hasNewMarshal), ((char*)"0"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_eq(kr_len(((char*(*)(char*))compileWin32IntArgs)(jfCName)), ((char*)"0"))) ? kr_str("1") : kr_str("0")))) {
                        char* wd = kr_plus(kr_plus(((char*)"static char* _krw_"), jfCName), ((char*)"("));
                        char* wpi = ((char*)"0");
                        while (kr_truthy(kr_lt(wpi, jfPc))) {
                            if (kr_truthy(kr_gt(wpi, ((char*)"0")))) {
                                wd = kr_plus(wd, ((char*)","));
                            }
                            wd = kr_plus(kr_plus(wd, ((char*)"char* _a")), wpi);
                            wpi = kr_plus(wpi, ((char*)"1"));
                        }
                        if (kr_truthy(kr_eq(jfPc, ((char*)"0")))) {
                            wd = kr_plus(wd, ((char*)"void"));
                        }
                        wd = kr_plus(kr_plus(kr_plus(wd, ((char*)"){")), jfCName), ((char*)"("));
                        wpi = ((char*)"0");
                        while (kr_truthy(kr_lt(wpi, jfPc))) {
                            if (kr_truthy(kr_gt(wpi, ((char*)"0")))) {
                                wd = kr_plus(wd, ((char*)","));
                            }
                            wd = kr_plus(kr_plus(wd, ((char*)"_a")), wpi);
                            wpi = kr_plus(wpi, ((char*)"1"));
                        }
                        wd = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(wd, ((char*)");return _K_EMPTY;}\n#define ")), jfCName), ((char*)" _krw_")), jfCName), ((char*)"\n"));
                        importFwdDecls = kr_plus(importFwdDecls, wd);
                    }
                    jxtPos = jfPos;
                } else {
                    jxtPos = kr_plus(jxtPos, ((char*)"2"));
                }
            }
            ii = kr_plus(jxtPos, ((char*)"1"));
        } else {
            ii = kr_plus(ii, ((char*)"1"));
        }
    }
    if (kr_truthy(kr_gt(kr_len(importFwdDecls), ((char*)"0")))) {
        sb = kr_sbappend(sb, importFwdDecls);
        sb = kr_sbappend(sb, ((char*)"\n"));
    }
    if (kr_truthy(kr_gt(kr_len(lambdaBank), ((char*)"0")))) {
        sb = kr_sbappend(sb, ((char*)"// --- lambda functions ---\n"));
        sb = kr_sbappend(sb, lambdaBank);
    }
    if (kr_truthy(kr_gt(kr_len(importBodies), ((char*)"0")))) {
        sb = kr_sbappend(sb, importBodies);
    }
    char* i = ((char*)"0");
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* tok = ((char*(*)(char*,char*))tokAt)(tokens, i);
        if (kr_truthy((kr_truthy(kr_eq(tok, ((char*)"KW:func"))) || kr_truthy(kr_eq(tok, ((char*)"KW:fn"))) ? kr_str("1") : kr_str("0")))) {
            char* nameTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1")));
            if (kr_truthy(kr_eq(nameTok, ((char*)"LPAREN")))) {
                char* lskip = kr_plus(i, ((char*)"2"));
                while (kr_truthy((kr_truthy(kr_lt(lskip, ntoks)) && kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, lskip), ((char*)"RPAREN"))) ? kr_str("1") : kr_str("0")))) {
                    lskip = kr_plus(lskip, ((char*)"1"));
                }
                lskip = kr_plus(lskip, ((char*)"1"));
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, lskip), ((char*)"ARROW")))) {
                    lskip = kr_plus(lskip, ((char*)"2"));
                }
                i = kr_sub(((char*(*)(char*,char*))skipBlock)(tokens, lskip), ((char*)"1"));
            }
            char* fname = ((char*(*)(char*))tokVal)(nameTok);
            if (kr_truthy(kr_gt(kr_len(fname), ((char*)"0")))) {
                char* info = ((char*(*)(char*,char*))funcLookup)(ftable, fname);
                char* pc = ((char*(*)(char*))funcParamCount)(info);
                char* decl = kr_plus(kr_plus(((char*)"char* "), ((char*(*)(char*))cIdent)(fname)), ((char*)"(char*"));
                char* pi = ((char*)"1");
                while (kr_truthy(kr_lt(kr_toint(pi), kr_toint(pc)))) {
                    decl = kr_plus(decl, ((char*)", char*"));
                    pi = kr_plus(pi, ((char*)"1"));
                }
                if (kr_truthy(kr_eq(kr_toint(pc), ((char*)"0")))) {
                    decl = kr_plus(kr_plus(((char*)"char* "), ((char*(*)(char*))cIdent)(fname)), ((char*)"("));
                }
                decl = kr_plus(decl, ((char*)");\n"));
                sb = kr_sbappend(sb, decl);
            }
        } else if (kr_truthy(kr_eq(tok, ((char*)"KW:callback")))) {
            char* cbSkip = kr_plus(i, ((char*)"3"));
            while (kr_truthy((kr_truthy(kr_lt(cbSkip, ntoks)) && kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, cbSkip), ((char*)"RPAREN"))) ? kr_str("1") : kr_str("0")))) {
                cbSkip = kr_plus(cbSkip, ((char*)"1"));
            }
            cbSkip = kr_plus(cbSkip, ((char*)"1"));
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, cbSkip), ((char*)"ARROW")))) {
                cbSkip = kr_plus(cbSkip, ((char*)"2"));
            }
            i = kr_sub(((char*(*)(char*,char*))skipBlock)(tokens, cbSkip), ((char*)"1"));
        } else if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(tok), ((char*)"CBLOCK")))) {
        } else if (kr_truthy(kr_eq(tok, ((char*)"KW:let")))) {
            char* gfp = kr_plus(i, ((char*)"2"));
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, gfp), ((char*)"COLON")))) {
                gfp = kr_plus(gfp, ((char*)"2"));
            }
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, gfp), ((char*)"ASSIGN")))) {
                char* gfv = ((char*(*)(char*,char*,char*))compileExpr)(tokens, kr_plus(gfp, ((char*)"1")), ntoks);
                i = kr_sub(((char*(*)(char*))pairPos)(gfv), ((char*)"1"));
            } else {
                i = kr_sub(gfp, ((char*)"1"));
            }
        } else if (kr_truthy(kr_eq(tok, ((char*)"KW:jxt")))) {
            i = kr_sub(((char*(*)(char*,char*))skipBlock)(tokens, kr_plus(i, ((char*)"1"))), ((char*)"1"));
        } else if (kr_truthy(kr_eq(tok, ((char*)"KW:export")))) {
        } else if (kr_truthy(kr_eq(tok, ((char*)"KW:jxt")))) {
            i = ((char*(*)(char*,char*))skipBlock)(tokens, kr_plus(i, ((char*)"1")));
        } else if (kr_truthy((kr_truthy((kr_truthy(kr_eq(tok, ((char*)"KW:struct"))) || kr_truthy(kr_eq(tok, ((char*)"KW:class"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(tok, ((char*)"KW:type"))) ? kr_str("1") : kr_str("0")))) {
            char* sn = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1"))));
            if (kr_truthy(kr_gt(kr_len(sn), ((char*)"0")))) {
                sb = kr_sbappend(sb, kr_plus(kr_plus(((char*)"static char* "), ((char*(*)(char*))cIdent)(sn)), ((char*)"();\n")));
            }
            i = kr_sub(((char*(*)(char*,char*))skipBlock)(tokens, kr_plus(i, ((char*)"2"))), ((char*)"1"));
        }
        i = kr_plus(i, ((char*)"1"));
    }
    sb = kr_sbappend(sb, ((char*)"\n"));
    char* sbGlobals = kr_sbnew();
    char* glDepth = ((char*)"0");
    i = ((char*)"0");
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* tok = ((char*(*)(char*,char*))tokAt)(tokens, i);
        if (kr_truthy(kr_eq(tok, ((char*)"LBRACE")))) {
            glDepth = kr_plus(glDepth, ((char*)"1"));
        }
        if (kr_truthy(kr_eq(tok, ((char*)"RBRACE")))) {
            glDepth = kr_sub(glDepth, ((char*)"1"));
        }
        if (kr_truthy((kr_truthy(kr_eq(tok, ((char*)"KW:let"))) && kr_truthy(kr_eq(glDepth, ((char*)"0"))) ? kr_str("1") : kr_str("0")))) {
            char* gname = ((char*(*)(char*))cIdent)(((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1")))));
            char* gp = kr_plus(i, ((char*)"2"));
            char* gtype = ((char*)"str");
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, gp), ((char*)"COLON")))) {
                gtype = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(gp, ((char*)"1"))));
                gp = kr_plus(gp, ((char*)"2"));
            }
            sb = kr_sbappend(sb, kr_plus(kr_plus(((char*)"static char* "), gname), ((char*)" = NULL;\n")));
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, gp), ((char*)"ASSIGN")))) {
                gp = kr_plus(gp, ((char*)"1"));
                char* gval = ((char*(*)(char*,char*,char*))compileExpr)(tokens, gp, ntoks);
                char* gvalCode = ((char*(*)(char*))pairVal)(gval);
                sbGlobals = kr_sbappend(sbGlobals, kr_plus(kr_plus(kr_plus(kr_plus(((char*)"    "), gname), ((char*)" = ")), gvalCode), ((char*)";\n")));
                i = ((char*(*)(char*))pairPos)(gval);
            } else {
                i = gp;
            }
        } else if (kr_truthy((kr_truthy(kr_eq(tok, ((char*)"KW:func"))) || kr_truthy(kr_eq(tok, ((char*)"KW:fn"))) ? kr_str("1") : kr_str("0")))) {
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1"))), ((char*)"LPAREN")))) {
                char* lskip2 = kr_plus(i, ((char*)"2"));
                while (kr_truthy((kr_truthy(kr_lt(lskip2, ntoks)) && kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, lskip2), ((char*)"RPAREN"))) ? kr_str("1") : kr_str("0")))) {
                    lskip2 = kr_plus(lskip2, ((char*)"1"));
                }
                lskip2 = kr_plus(lskip2, ((char*)"1"));
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, lskip2), ((char*)"ARROW")))) {
                    lskip2 = kr_plus(lskip2, ((char*)"2"));
                }
                i = ((char*(*)(char*,char*))skipBlock)(tokens, lskip2);
            } else {
                char* fp = ((char*(*)(char*,char*,char*))compileFunc)(tokens, i, ntoks);
                char* fcode = ((char*(*)(char*))pairVal)(fp);
                sb = kr_sbappend(sb, fcode);
                i = ((char*(*)(char*))pairPos)(fp);
            }
        } else if (kr_truthy(kr_eq(tok, ((char*)"KW:callback")))) {
            char* fp = ((char*(*)(char*,char*,char*))compileCallbackFunc)(tokens, kr_plus(i, ((char*)"1")), ntoks);
            char* fcode = ((char*(*)(char*))pairVal)(fp);
            sb = kr_sbappend(sb, fcode);
            i = ((char*(*)(char*))pairPos)(fp);
        } else if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(tok), ((char*)"CBLOCK")))) {
            char* craw = kr_replace(((char*(*)(char*))tokVal)(tok), ((char*)"\\x01"), ((char*)"\n"));
            sb = kr_sbappend(sb, kr_plus(craw, ((char*)"\n")));
            i = kr_plus(i, ((char*)"1"));
        } else if (kr_truthy(kr_eq(tok, ((char*)"KW:jxt")))) {
            i = kr_sub(((char*(*)(char*,char*))skipBlock)(tokens, kr_plus(i, ((char*)"1"))), ((char*)"1"));
        } else if (kr_truthy(kr_eq(tok, ((char*)"KW:export")))) {
            i = kr_plus(i, ((char*)"1"));
        } else if (kr_truthy((kr_truthy((kr_truthy(kr_eq(tok, ((char*)"KW:struct"))) || kr_truthy(kr_eq(tok, ((char*)"KW:class"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(tok, ((char*)"KW:type"))) ? kr_str("1") : kr_str("0")))) {
            char* sname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, ((char*)"1"))));
            char* scname = ((char*(*)(char*))cIdent)(sname);
            char* sp2 = kr_plus(i, ((char*)"3"));
            char* sfields = ((char*)"");
            char* sfc = ((char*)"0");
            while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, sp2), ((char*)"RBRACE")))) {
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, sp2), ((char*)"KW:let")))) {
                    char* sfname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(sp2, ((char*)"1"))));
                    if (kr_truthy(kr_gt(sfc, ((char*)"0")))) {
                        sfields = kr_plus(kr_plus(sfields, ((char*)",")), sfname);
                    } else {
                        sfields = sfname;
                    }
                    sfc = kr_plus(sfc, ((char*)"1"));
                    sp2 = kr_plus(sp2, ((char*)"2"));
                    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, sp2), ((char*)"COLON")))) {
                        sp2 = kr_plus(sp2, ((char*)"2"));
                    }
                    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, sp2), ((char*)"ASSIGN")))) {
                        char* sep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, kr_plus(sp2, ((char*)"1")), ntoks);
                        sp2 = ((char*(*)(char*))pairPos)(sep);
                    }
                } else {
                    sp2 = kr_plus(sp2, ((char*)"1"));
                }
            }
            char* sout = kr_plus(kr_plus(((char*)"typedef struct "), scname), ((char*)"_s {\n"));
            char* si = ((char*)"0");
            while (kr_truthy(kr_lt(si, sfc))) {
                char* sfn = ((char*(*)(char*,char*))getNthParam)(sfields, si);
                sout = kr_plus(kr_plus(kr_plus(sout, ((char*)"    char* ")), ((char*(*)(char*))cIdent)(sfn)), ((char*)";\n"));
                si = kr_plus(si, ((char*)"1"));
            }
            sout = kr_plus(kr_plus(kr_plus(sout, ((char*)"} ")), scname), ((char*)"_t;\n\n"));
            sout = kr_plus(kr_plus(kr_plus(sout, ((char*)"static char* ")), scname), ((char*)"() {\n"));
            sout = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(sout, ((char*)"    ")), scname), ((char*)"_t* _s = (")), scname), ((char*)"_t*)_alloc(sizeof(")), scname), ((char*)"_t));\n"));
            char* si2 = ((char*)"0");
            while (kr_truthy(kr_lt(si2, sfc))) {
                char* sfn2 = ((char*(*)(char*,char*))getNthParam)(sfields, si2);
                sout = kr_plus(kr_plus(kr_plus(sout, ((char*)"    _s->")), ((char*(*)(char*))cIdent)(sfn2)), ((char*)" = _K_EMPTY;\n"));
                si2 = kr_plus(si2, ((char*)"1"));
            }
            sout = kr_plus(sout, ((char*)"    return (char*)_s;\n}\n\n"));
            sb = kr_sbappend(sb, sout);
            i = sp2;
        } else {
            i = kr_plus(i, ((char*)"1"));
        }
    }
    char* entry = ((char*(*)(char*,char*))findEntry)(tokens, ntoks);
    if (kr_truthy(kr_gte(entry, ((char*)"0")))) {
        char* runkBase = kr_substr(file, kr_plus(lastSlash, ((char*)"1")), kr_len(file));
        if (kr_truthy((kr_truthy(kr_neq(runkBase, ((char*)"run.k"))) && kr_truthy(kr_neq(runkBase, ((char*)"run.ks"))) ? kr_str("1") : kr_str("0")))) {
            char* hasModule = ((char*)"0");
            char* modI = ((char*)"0");
            while (kr_truthy((kr_truthy(kr_lt(modI, ntoks)) && kr_truthy(kr_eq(hasModule, ((char*)"0"))) ? kr_str("1") : kr_str("0")))) {
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, modI), ((char*)"KW:module")))) {
                    hasModule = ((char*)"1");
                }
                modI = kr_plus(modI, ((char*)"1"));
            }
            if (kr_truthy(kr_eq(hasModule, ((char*)"1")))) {
                kr_printerr(((char*)"kcc: warning: entry-point file should be named `run.k` (got `"));
                kr_printerr(kr_plus(runkBase, ((char*)"`)\n")));
                kr_printerr(((char*)"  Multi-file projects (those with `module <name>`) must place\n"));
                kr_printerr(((char*)"  their `just run { ... }` body in `run.k`. This is a warning in\n"));
                kr_printerr(((char*)"  2.3 and becomes an error in 2.4 — rename now to stay forward-compatible.\n"));
            }
        }
    }
    if (kr_truthy(kr_lt(entry, ((char*)"0")))) {
        if (kr_truthy(irMode)) {
            char* sbIRlib = kr_sbnew();
            sbIRlib = kr_sbappend(sbIRlib, kr_plus(kr_plus(((char*)"; Krypton IR\n; Source: "), file), ((char*)"\n\n")));
            sbIRlib = kr_sbappend(sbIRlib, importedIR);
            char* irlibI = ((char*)"0");
            while (kr_truthy(kr_lt(irlibI, ntoks))) {
                char* irlibTok = ((char*(*)(char*,char*))tokAt)(tokens, irlibI);
                if (kr_truthy((kr_truthy(kr_eq(irlibTok, ((char*)"KW:func"))) || kr_truthy(kr_eq(irlibTok, ((char*)"KW:fn"))) ? kr_str("1") : kr_str("0")))) {
                    char* irlibFp = ((char*(*)(char*,char*,char*))irFuncIR)(tokens, irlibI, ntoks);
                    sbIRlib = kr_sbappend(sbIRlib, ((char*(*)(char*))pairVal)(irlibFp));
                    irlibI = ((char*(*)(char*))pairPos)(irlibFp);
                } else if (kr_truthy(kr_eq(irlibTok, ((char*)"KW:export")))) {
                    char* irlibNext = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(irlibI, ((char*)"1")));
                    if (kr_truthy((kr_truthy(kr_eq(irlibNext, ((char*)"KW:func"))) || kr_truthy(kr_eq(irlibNext, ((char*)"KW:fn"))) ? kr_str("1") : kr_str("0")))) {
                        char* irlibFname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(irlibI, ((char*)"2"))));
                        char* irlibFp = ((char*(*)(char*,char*,char*))irFuncIR)(tokens, kr_plus(irlibI, ((char*)"1")), ntoks);
                        sbIRlib = kr_sbappend(sbIRlib, kr_plus(kr_plus(((char*)"EXPORT "), irlibFname), ((char*)"\n")));
                        sbIRlib = kr_sbappend(sbIRlib, ((char*(*)(char*))pairVal)(irlibFp));
                        irlibI = ((char*(*)(char*))pairPos)(irlibFp);
                    } else {
                        irlibI = kr_plus(irlibI, ((char*)"1"));
                    }
                } else {
                    irlibI = kr_plus(irlibI, ((char*)"1"));
                }
            }
            char* irLibText = kr_sbtostring(sbIRlib);
            if (kr_truthy(kr_gt(kr_len(outFile), ((char*)"0")))) {
                char* compilerDir = kr_replace(headersDir, ((char*)"headers"), ((char*)"bin"));
                char* tmpDir = ((char*)"C:\\krypton");
                if (kr_truthy(kr_neq(kr_environ(((char*)"HOME")), ((char*)"")))) {
                    tmpDir = kr_environ(((char*)"TMPDIR"));
                    if (kr_truthy(kr_eq(tmpDir, ((char*)"")))) {
                        tmpDir = ((char*)"/tmp");
                    }
                }
                char* tmpIR = kr_plus(tmpDir, ((char*)"/tmp_kcc_build.ir"));
                char* tmpOpt = kr_plus(tmpDir, ((char*)"/tmp_kcc_build_opt.ir"));
                kr_writefile(tmpIR, irLibText);
                char* optCmd2 = kr_plus(kr_plus(kr_plus(kr_plus(compilerDir, ((char*)"\\optimize_host.exe ")), tmpIR), ((char*)" > ")), tmpOpt);
                char* codeCmd2 = kr_plus(kr_plus(kr_plus(kr_plus(compilerDir, ((char*)"\\x64_host_new.exe ")), tmpOpt), ((char*)" ")), outFile);
                kr_shellrun(optCmd2);
                kr_shellrun(codeCmd2);
                kr_deletefile(tmpIR);
                kr_deletefile(tmpOpt);
                return atoi(((char*)"0"));
            }
            kr_print(irLibText);
            return atoi(((char*)"0"));
        }
        kr_print(kr_sbtostring(sb));
        return atoi(((char*)"0"));
    }
    sb = kr_sbappend(sb, ((char*)"int main(int argc, char** argv) {\n"));
    sb = kr_sbappend(sb, ((char*)"    char _stack_anchor; _stack_bottom = &_stack_anchor;\n"));
    sb = kr_sbappend(sb, ((char*)"    _argc = argc; _argv = argv;\n"));
    sb = kr_sbappend(sb, ((char*)"    srand((unsigned)time(NULL));\n"));
    char* globInitCode = kr_sbtostring(sbGlobals);
    if (kr_truthy(kr_gt(kr_len(globInitCode), ((char*)"0")))) {
        sb = kr_sbappend(sb, globInitCode);
    }
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, entry, ntoks, ((char*)"0"), ((char*)"0"));
    char* bcode = ((char*(*)(char*))pairVal)(bp);
    sb = kr_sbappend(sb, bcode);
    sb = kr_sbappend(sb, ((char*)"    return 0;\n"));
    sb = kr_sbappend(sb, ((char*)"}\n"));
    if (kr_truthy(irMode)) {
        char* sbIR = kr_sbnew();
        sbIR = kr_sbappend(sbIR, kr_plus(kr_plus(((char*)"; Krypton IR\n; Source: "), file), ((char*)"\n\n")));
        sbIR = kr_sbappend(sbIR, importedIR);
        char* sbGlobInit = kr_sbnew();
        char* iri = ((char*)"0");
        while (kr_truthy(kr_lt(iri, ntoks))) {
            char* irtok = ((char*(*)(char*,char*))tokAt)(tokens, iri);
            if (kr_truthy((kr_truthy(kr_eq(irtok, ((char*)"KW:func"))) || kr_truthy(kr_eq(irtok, ((char*)"KW:fn"))) ? kr_str("1") : kr_str("0")))) {
                char* fp = ((char*(*)(char*,char*,char*))irFuncIR)(tokens, iri, ntoks);
                sbIR = kr_sbappend(sbIR, ((char*(*)(char*))pairVal)(fp));
                iri = ((char*(*)(char*))pairPos)(fp);
            } else if (kr_truthy(kr_eq(irtok, ((char*)"KW:export")))) {
                char* expNext = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(iri, ((char*)"1")));
                if (kr_truthy((kr_truthy(kr_eq(expNext, ((char*)"KW:func"))) || kr_truthy(kr_eq(expNext, ((char*)"KW:fn"))) ? kr_str("1") : kr_str("0")))) {
                    char* expFname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(iri, ((char*)"2"))));
                    char* efp = ((char*(*)(char*,char*,char*))irFuncIR)(tokens, kr_plus(iri, ((char*)"1")), ntoks);
                    sbIR = kr_sbappend(sbIR, kr_plus(kr_plus(((char*)"EXPORT "), expFname), ((char*)"\n")));
                    sbIR = kr_sbappend(sbIR, ((char*(*)(char*))pairVal)(efp));
                    iri = ((char*(*)(char*))pairPos)(efp);
                } else {
                    iri = kr_plus(iri, ((char*)"1"));
                }
            } else if (kr_truthy((kr_truthy(kr_eq(irtok, ((char*)"KW:just"))) || kr_truthy(kr_eq(irtok, ((char*)"KW:go"))) ? kr_str("1") : kr_str("0")))) {
                char* bodyOpen = kr_plus(iri, ((char*)"2"));
                while (kr_truthy((kr_truthy(kr_lt(bodyOpen, ntoks)) && kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, bodyOpen), ((char*)"LBRACE"))) ? kr_str("1") : kr_str("0")))) {
                    bodyOpen = kr_plus(bodyOpen, ((char*)"1"));
                }
                char* scanP = kr_plus(bodyOpen, ((char*)"1"));
                char* scanDepth = ((char*)"1");
                while (kr_truthy((kr_truthy(kr_lt(scanP, ntoks)) && kr_truthy(kr_gt(scanDepth, ((char*)"0"))) ? kr_str("1") : kr_str("0")))) {
                    char* st = ((char*(*)(char*,char*))tokAt)(tokens, scanP);
                    if (kr_truthy(kr_eq(st, ((char*)"LBRACE")))) {
                        scanDepth = kr_plus(scanDepth, ((char*)"1"));
                        scanP = kr_plus(scanP, ((char*)"1"));
                    } else if (kr_truthy(kr_eq(st, ((char*)"RBRACE")))) {
                        scanDepth = kr_sub(scanDepth, ((char*)"1"));
                        scanP = kr_plus(scanP, ((char*)"1"));
                    } else if (kr_truthy((kr_truthy((kr_truthy(kr_eq(st, ((char*)"KW:func"))) || kr_truthy(kr_eq(st, ((char*)"KW:fn"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(scanP, ((char*)"1")))), ((char*)"ID"))) ? kr_str("1") : kr_str("0")))) {
                        char* nfp = ((char*(*)(char*,char*,char*))irFuncIR)(tokens, scanP, ntoks);
                        sbIR = kr_sbappend(sbIR, ((char*(*)(char*))pairVal)(nfp));
                        scanP = ((char*(*)(char*))pairPos)(nfp);
                    } else {
                        scanP = kr_plus(scanP, ((char*)"1"));
                    }
                }
                iri = scanP;
            } else if (kr_truthy((kr_truthy((kr_truthy(kr_eq(irtok, ((char*)"KW:struct"))) || kr_truthy(kr_eq(irtok, ((char*)"KW:class"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(irtok, ((char*)"KW:type"))) ? kr_str("1") : kr_str("0")))) {
                char* structName = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(iri, ((char*)"1"))));
                sbIR = kr_sbappend(sbIR, kr_plus(kr_plus(((char*)"FUNC "), structName), ((char*)" 0\nSTRUCTNEW\nRETURN\nEND\n\n")));
                char* entryP = kr_plus(iri, ((char*)"2"));
                while (kr_truthy((kr_truthy(kr_lt(entryP, ntoks)) && kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, entryP), ((char*)"LBRACE"))) ? kr_str("1") : kr_str("0")))) {
                    entryP = kr_plus(entryP, ((char*)"1"));
                }
                char* depth = ((char*)"0");
                while (kr_truthy(kr_lt(entryP, ntoks))) {
                    char* bt = ((char*(*)(char*,char*))tokAt)(tokens, entryP);
                    if (kr_truthy(kr_eq(bt, ((char*)"LBRACE")))) {
                        depth = kr_plus(depth, ((char*)"1"));
                    }
                    if (kr_truthy(kr_eq(bt, ((char*)"RBRACE")))) {
                        depth = kr_sub(depth, ((char*)"1"));
                        if (kr_truthy(kr_eq(depth, ((char*)"0")))) {
                            entryP = kr_plus(entryP, ((char*)"1"));
                            break;
                        }
                    }
                    entryP = kr_plus(entryP, ((char*)"1"));
                }
                iri = entryP;
            } else if (kr_truthy((kr_truthy(kr_eq(irtok, ((char*)"KW:let"))) || kr_truthy(kr_eq(irtok, ((char*)"KW:const"))) ? kr_str("1") : kr_str("0")))) {
                char* glp = ((char*(*)(char*,char*,char*,char*,char*,char*))irLetIR)(tokens, kr_plus(iri, ((char*)"1")), ntoks, ((char*)"0"), ((char*)"0"), ((char*)""));
                sbGlobInit = kr_sbappend(sbGlobInit, ((char*(*)(char*))pairVal)(glp));
                iri = ((char*(*)(char*))pairPos)(glp);
            } else {
                iri = kr_plus(iri, ((char*)"1"));
            }
        }
        char* lamI = ((char*)"0");
        while (kr_truthy(kr_lt(lamI, ntoks))) {
            char* lamTok = ((char*(*)(char*,char*))tokAt)(tokens, lamI);
            if (kr_truthy((kr_truthy((kr_truthy(kr_eq(lamTok, ((char*)"KW:func"))) || kr_truthy(kr_eq(lamTok, ((char*)"KW:fn"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(lamI, ((char*)"1"))), ((char*)"LPAREN"))) ? kr_str("1") : kr_str("0")))) {
                char* lampair = ((char*(*)(char*,char*,char*,char*))irLambdaIR)(tokens, lamI, ntoks, kr_plus(((char*)"_krlam"), lamI));
                sbIR = kr_sbappend(sbIR, ((char*(*)(char*))pairVal)(lampair));
                lamI = ((char*(*)(char*))pairPos)(lampair);
            } else {
                lamI = kr_plus(lamI, ((char*)"1"));
            }
        }
        char* irEntry = ((char*(*)(char*,char*))findEntry)(tokens, ntoks);
        if (kr_truthy(kr_gte(irEntry, ((char*)"0")))) {
            char* mainTypes = kr_plus(((char*(*)(char*,char*))irScanStructTypes)(tokens, ntoks), ((char*(*)(char*,char*))irScanFuncTypes)(tokens, irEntry));
            char* ep = ((char*(*)(char*,char*,char*,char*,char*,char*))irBlockIR)(tokens, irEntry, ntoks, ((char*)"0"), ((char*)"0"), mainTypes);
            char* mainBody = kr_plus(kr_sbtostring(sbGlobInit), ((char*(*)(char*))pairVal)(ep));
            mainBody = kr_plus(kr_plus(((char*)"LOCAL __sh_save\nBUILTIN gcShadowCount 0\nSTORE __sh_save\n"), mainBody), ((char*)"BUILTIN gcShadowCount 0\nLOAD __sh_save\nSUB\nBUILTIN gcShadowPop 1\nPOP\n"));
            sbIR = kr_sbappend(sbIR, kr_plus(kr_plus(((char*)"FUNC __main__ 0\n"), mainBody), ((char*)"END\n")));
        }
        char* irText = kr_sbtostring(sbIR);
        if (kr_truthy(kr_gt(kr_len(outFile), ((char*)"0")))) {
            char* compilerDir = kr_replace(headersDir, ((char*)"headers"), ((char*)"bin"));
            char* tmpDir = ((char*)"C:\\krypton");
            if (kr_truthy(kr_neq(kr_environ(((char*)"HOME")), ((char*)"")))) {
                tmpDir = kr_environ(((char*)"TMPDIR"));
                if (kr_truthy(kr_eq(tmpDir, ((char*)"")))) {
                    tmpDir = ((char*)"/tmp");
                }
            }
            char* tmpIR = kr_plus(tmpDir, ((char*)"/tmp_kcc_build.ir"));
            char* tmpOpt = kr_plus(tmpDir, ((char*)"/tmp_kcc_build_opt.ir"));
            kr_writefile(tmpIR, irText);
            char* optCmd = kr_plus(kr_plus(kr_plus(kr_plus(compilerDir, ((char*)"\\optimize_host.exe ")), tmpIR), ((char*)" > ")), tmpOpt);
            char* codeCmd = kr_plus(kr_plus(kr_plus(kr_plus(compilerDir, ((char*)"\\x64_host_new.exe ")), tmpOpt), ((char*)" ")), outFile);
            kr_shellrun(optCmd);
            kr_shellrun(codeCmd);
            kr_deletefile(tmpIR);
            kr_deletefile(tmpOpt);
            return atoi(((char*)"0"));
        }
        kr_print(irText);
        return atoi(((char*)"0"));
    }
    kr_print(kr_sbtostring(sb));
    return 0;
}

