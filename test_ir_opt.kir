#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <ctype.h>
#include <stdarg.h>

static int _argc; static char** _argv;

typedef struct ABlock { struct ABlock* next; int cap; int used; } ABlock;
static ABlock* _arena = 0;
static char* _alloc(int n) {
    n = (n + 7) & ~7;
    if (!_arena || _arena->used + n > _arena->cap) {
        int cap = 64*1024*1024;
        if (n > cap) cap = n;
        ABlock* b = (ABlock*)malloc(sizeof(ABlock) + cap);
        if (!b) { fprintf(stderr, "out of memory\n"); exit(1); }
        b->cap = cap; b->used = 0; b->next = _arena; _arena = b;
    }
    char* p = (char*)(_arena + 1) + _arena->used;
    _arena->used += n;
    return p;
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
    char buf[32];
    snprintf(buf, sizeof(buf), "%d", v);
    return kr_str(buf);
}

static int kr_atoi(const char* s) { return atoi(s); }

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
    int cur = 0;
    const char* start = s;
    const char* p = s;
    while (*p) {
        if (*p == '\n') {
            if (cur == idx) {
                int len = (int)(p - start);
                char* r = _alloc(len + 1);
                memcpy(r, start, len);
                r[len] = 0;
                return r;
            }
            cur++;
            start = p + 1;
        }
        p++;
    }
    if (cur == idx) return kr_str(start);
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
    return kr_linecount(s);
}

static char* kr_writefile(const char* path, const char* data) {
    FILE* f = fopen(path, "wb");
    if (!f) return _K_ZERO;
    fwrite(data, 1, strlen(data), f);
    fclose(f);
    return _K_ONE;
}

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
    char buf[2] = {(char)atoi(ns), 0};
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
#define MAX_SBS 4096
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
char* irGetOp(char*);
char* irGetArg1(char*);
char* irGetArg2(char*);
char* irIsNumeric(char*);
char* passDeadCode(char*);
char* passFold(char*);
char* passStrength(char*);
char* passStoreLoad(char*);
char* passEmptyJump(char*);
char* passUnusedLocals(char*);
char* optimize(char*);
char* countInstructions(char*);

char* irGetOp(char* line) {
    char* i = kr_str("0");
    while (kr_truthy((kr_truthy(kr_lt(i, kr_len(line))) && kr_truthy(kr_neq(kr_idx(line, kr_atoi(i)), kr_str(" "))) ? kr_str("1") : kr_str("0")))) {
        i = kr_plus(i, kr_str("1"));
    }
    return kr_substr(line, kr_str("0"), i);
}

char* irGetArg1(char* line) {
    char* i = kr_str("0");
    while (kr_truthy((kr_truthy(kr_lt(i, kr_len(line))) && kr_truthy(kr_neq(kr_idx(line, kr_atoi(i)), kr_str(" "))) ? kr_str("1") : kr_str("0")))) {
        i = kr_plus(i, kr_str("1"));
    }
    if (kr_truthy(kr_gte(i, kr_len(line)))) {
        return kr_str("");
    }
    i = kr_plus(i, kr_str("1"));
    char* start = i;
    while (kr_truthy((kr_truthy(kr_lt(i, kr_len(line))) && kr_truthy(kr_neq(kr_idx(line, kr_atoi(i)), kr_str(" "))) ? kr_str("1") : kr_str("0")))) {
        i = kr_plus(i, kr_str("1"));
    }
    return kr_substr(line, start, i);
}

char* irGetArg2(char* line) {
    char* i = kr_str("0");
    char* spaces = kr_str("0");
    while (kr_truthy(kr_lt(i, kr_len(line)))) {
        if (kr_truthy(kr_eq(kr_idx(line, kr_atoi(i)), kr_str(" ")))) {
            spaces = kr_plus(spaces, kr_str("1"));
            if (kr_truthy(kr_eq(spaces, kr_str("2")))) {
                char* start = kr_plus(i, kr_str("1"));
                char* j = start;
                while (kr_truthy(kr_lt(j, kr_len(line)))) {
                    j = kr_plus(j, kr_str("1"));
                }
                return kr_substr(line, start, j);
            }
        }
        i = kr_plus(i, kr_str("1"));
    }
    return kr_str("");
}

char* irIsNumeric(char* s) {
    if (kr_truthy(kr_eq(kr_len(s), kr_str("0")))) {
        return kr_str("0");
    }
    char* i = kr_str("0");
    if (kr_truthy(kr_eq(kr_idx(s, kr_atoi(kr_str("0"))), kr_str("-")))) {
        i = kr_str("1");
    }
    if (kr_truthy(kr_gte(i, kr_len(s)))) {
        return kr_str("0");
    }
    while (kr_truthy(kr_lt(i, kr_len(s)))) {
        if (kr_truthy((kr_truthy(kr_lt(kr_idx(s, kr_atoi(i)), kr_str("0"))) || kr_truthy(kr_gt(kr_idx(s, kr_atoi(i)), kr_str("9"))) ? kr_str("1") : kr_str("0")))) {
            return kr_str("0");
        }
        i = kr_plus(i, kr_str("1"));
    }
    return kr_str("1");
}

char* passDeadCode(char* ir) {
    char* lines = ir;
    char* count = kr_linecount(lines);
    char* out = kr_str("");
    char* dead = kr_str("0");
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, count))) {
        char* line = kr_getline(lines, i);
        char* op = irGetOp(line);
        if (kr_truthy((kr_truthy((kr_truthy(kr_eq(op, kr_str("LABEL"))) || kr_truthy(kr_eq(op, kr_str("END"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(op, kr_str("FUNC"))) ? kr_str("1") : kr_str("0")))) {
            dead = kr_str("0");
        }
        if (kr_truthy(kr_eq(dead, kr_str("0")))) {
            if (kr_truthy(kr_gt(kr_len(out), kr_str("0")))) {
                out = kr_plus(out, kr_str("\n"));
            }
            out = kr_plus(out, line);
        }
        if (kr_truthy((kr_truthy(kr_eq(op, kr_str("RETURN"))) || kr_truthy(kr_eq(op, kr_str("JUMP"))) ? kr_str("1") : kr_str("0")))) {
            dead = kr_str("1");
        }
        i = kr_plus(i, kr_str("1"));
    }
    return out;
}

char* passFold(char* ir) {
    char* lines = ir;
    char* count = kr_linecount(lines);
    char* out = kr_str("");
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, count))) {
        char* line = kr_getline(lines, i);
        char* op = irGetOp(line);
        if (kr_truthy((kr_truthy(kr_eq(op, kr_str("PUSH"))) && kr_truthy(kr_lt(kr_plus(i, kr_str("2")), count)) ? kr_str("1") : kr_str("0")))) {
            char* a = irGetArg1(line);
            char* next = kr_getline(lines, kr_plus(i, kr_str("1")));
            char* nextOp = irGetOp(next);
            if (kr_truthy(kr_eq(nextOp, kr_str("PUSH")))) {
                char* b = irGetArg1(next);
                char* arith = kr_getline(lines, kr_plus(i, kr_str("2")));
                char* arithOp = irGetOp(arith);
                if (kr_truthy((kr_truthy(irIsNumeric(a)) && kr_truthy(irIsNumeric(b)) ? kr_str("1") : kr_str("0")))) {
                    char* av = kr_toint(a);
                    char* bv = kr_toint(b);
                    char* folded = kr_str("");
                    if (kr_truthy(kr_eq(arithOp, kr_str("ADD")))) {
                        folded = kr_plus(kr_plus(av, bv), kr_str(""));
                    }
                    if (kr_truthy(kr_eq(arithOp, kr_str("SUB")))) {
                        folded = kr_plus(kr_sub(av, bv), kr_str(""));
                    }
                    if (kr_truthy(kr_eq(arithOp, kr_str("MUL")))) {
                        folded = kr_plus(kr_mul(av, bv), kr_str(""));
                    }
                    if (kr_truthy((kr_truthy(kr_eq(arithOp, kr_str("DIV"))) && kr_truthy(kr_neq(bv, kr_str("0"))) ? kr_str("1") : kr_str("0")))) {
                        folded = kr_plus(kr_div(av, bv), kr_str(""));
                    }
                    if (kr_truthy(kr_gt(kr_len(folded), kr_str("0")))) {
                        if (kr_truthy(kr_gt(kr_len(out), kr_str("0")))) {
                            out = kr_plus(out, kr_str("\n"));
                        }
                        out = kr_plus(kr_plus(out, kr_str("PUSH ")), folded);
                        i = kr_plus(i, kr_str("3"));
                    } else {
                        if (kr_truthy(kr_gt(kr_len(out), kr_str("0")))) {
                            out = kr_plus(out, kr_str("\n"));
                        }
                        out = kr_plus(out, line);
                        i = kr_plus(i, kr_str("1"));
                    }
                } else {
                    if (kr_truthy(kr_gt(kr_len(out), kr_str("0")))) {
                        out = kr_plus(out, kr_str("\n"));
                    }
                    out = kr_plus(out, line);
                    i = kr_plus(i, kr_str("1"));
                }
            } else {
                if (kr_truthy(kr_gt(kr_len(out), kr_str("0")))) {
                    out = kr_plus(out, kr_str("\n"));
                }
                out = kr_plus(out, line);
                i = kr_plus(i, kr_str("1"));
            }
        } else {
            if (kr_truthy(kr_gt(kr_len(out), kr_str("0")))) {
                out = kr_plus(out, kr_str("\n"));
            }
            out = kr_plus(out, line);
            i = kr_plus(i, kr_str("1"));
        }
    }
    return out;
}

char* passStrength(char* ir) {
    char* lines = ir;
    char* count = kr_linecount(lines);
    char* out = kr_str("");
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, count))) {
        char* line = kr_getline(lines, i);
        char* op = irGetOp(line);
        char* skip = kr_str("0");
        if (kr_truthy((kr_truthy(kr_eq(op, kr_str("PUSH"))) && kr_truthy(kr_lt(kr_plus(i, kr_str("1")), count)) ? kr_str("1") : kr_str("0")))) {
            char* val = irGetArg1(line);
            char* nextLine = kr_getline(lines, kr_plus(i, kr_str("1")));
            char* nextOp = irGetOp(nextLine);
            if (kr_truthy((kr_truthy(kr_eq(val, kr_str("0"))) && kr_truthy(kr_eq(nextOp, kr_str("ADD"))) ? kr_str("1") : kr_str("0")))) {
                skip = kr_str("1");
            }
            if (kr_truthy((kr_truthy(kr_eq(val, kr_str("1"))) && kr_truthy(kr_eq(nextOp, kr_str("MUL"))) ? kr_str("1") : kr_str("0")))) {
                skip = kr_str("1");
            }
            if (kr_truthy((kr_truthy(kr_eq(val, kr_str("0"))) && kr_truthy(kr_eq(nextOp, kr_str("SUB"))) ? kr_str("1") : kr_str("0")))) {
                skip = kr_str("1");
            }
        }
        if (kr_truthy(skip)) {
            i = kr_plus(i, kr_str("2"));
        } else {
            if (kr_truthy(kr_gt(kr_len(out), kr_str("0")))) {
                out = kr_plus(out, kr_str("\n"));
            }
            out = kr_plus(out, line);
            i = kr_plus(i, kr_str("1"));
        }
    }
    return out;
}

char* passStoreLoad(char* ir) {
    char* lines = ir;
    char* count = kr_linecount(lines);
    char* out = kr_str("");
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, count))) {
        char* line = kr_getline(lines, i);
        char* op = irGetOp(line);
        if (kr_truthy((kr_truthy(kr_eq(op, kr_str("STORE"))) && kr_truthy(kr_lt(kr_plus(i, kr_str("1")), count)) ? kr_str("1") : kr_str("0")))) {
            char* varName = irGetArg1(line);
            char* nextLine = kr_getline(lines, kr_plus(i, kr_str("1")));
            char* nextOp = irGetOp(nextLine);
            char* nextVar = irGetArg1(nextLine);
            if (kr_truthy((kr_truthy(kr_eq(nextOp, kr_str("LOAD"))) && kr_truthy(kr_eq(nextVar, varName)) ? kr_str("1") : kr_str("0")))) {
                if (kr_truthy(kr_gt(kr_len(out), kr_str("0")))) {
                    out = kr_plus(out, kr_str("\n"));
                }
                out = kr_plus(out, line);
                i = kr_plus(i, kr_str("2"));
            } else {
                if (kr_truthy(kr_gt(kr_len(out), kr_str("0")))) {
                    out = kr_plus(out, kr_str("\n"));
                }
                out = kr_plus(out, line);
                i = kr_plus(i, kr_str("1"));
            }
        } else {
            if (kr_truthy(kr_gt(kr_len(out), kr_str("0")))) {
                out = kr_plus(out, kr_str("\n"));
            }
            out = kr_plus(out, line);
            i = kr_plus(i, kr_str("1"));
        }
    }
    return out;
}

char* passEmptyJump(char* ir) {
    char* lines = ir;
    char* count = kr_linecount(lines);
    char* out = kr_str("");
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, count))) {
        char* line = kr_getline(lines, i);
        char* op = irGetOp(line);
        if (kr_truthy((kr_truthy(kr_eq(op, kr_str("JUMP"))) && kr_truthy(kr_lt(kr_plus(i, kr_str("1")), count)) ? kr_str("1") : kr_str("0")))) {
            char* target = irGetArg1(line);
            char* nextLine = kr_getline(lines, kr_plus(i, kr_str("1")));
            char* nextOp = irGetOp(nextLine);
            char* nextLabel = irGetArg1(nextLine);
            if (kr_truthy((kr_truthy(kr_eq(nextOp, kr_str("LABEL"))) && kr_truthy(kr_eq(nextLabel, target)) ? kr_str("1") : kr_str("0")))) {
                i = kr_plus(i, kr_str("1"));
            } else {
                if (kr_truthy(kr_gt(kr_len(out), kr_str("0")))) {
                    out = kr_plus(out, kr_str("\n"));
                }
                out = kr_plus(out, line);
                i = kr_plus(i, kr_str("1"));
            }
        } else {
            if (kr_truthy(kr_gt(kr_len(out), kr_str("0")))) {
                out = kr_plus(out, kr_str("\n"));
            }
            out = kr_plus(out, line);
            i = kr_plus(i, kr_str("1"));
        }
    }
    return out;
}

char* passUnusedLocals(char* ir) {
    char* lines = ir;
    char* count = kr_linecount(lines);
    char* used = kr_str("");
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, count))) {
        char* line = kr_getline(lines, i);
        char* op = irGetOp(line);
        if (kr_truthy((kr_truthy(kr_eq(op, kr_str("LOAD"))) || kr_truthy(kr_eq(op, kr_str("STORE"))) ? kr_str("1") : kr_str("0")))) {
            char* varName = irGetArg1(line);
            if (kr_truthy(kr_not(kr_contains(used, kr_plus(kr_plus(kr_str(","), varName), kr_str(",")))))) {
                used = kr_plus(kr_plus(kr_plus(used, kr_str(",")), varName), kr_str(","));
            }
        }
        i = kr_plus(i, kr_str("1"));
    }
    char* out = kr_str("");
    i = kr_str("0");
    while (kr_truthy(kr_lt(i, count))) {
        char* line = kr_getline(lines, i);
        char* op = irGetOp(line);
        char* keep = kr_str("1");
        if (kr_truthy(kr_eq(op, kr_str("LOCAL")))) {
            char* varName = irGetArg1(line);
            if (kr_truthy(kr_not(kr_contains(used, kr_plus(kr_plus(kr_str(","), varName), kr_str(",")))))) {
                keep = kr_str("0");
            }
        }
        if (kr_truthy(keep)) {
            if (kr_truthy(kr_gt(kr_len(out), kr_str("0")))) {
                out = kr_plus(out, kr_str("\n"));
            }
            out = kr_plus(out, line);
        }
        i = kr_plus(i, kr_str("1"));
    }
    return out;
}

char* optimize(char* ir) {
    char* result = ir;
    char* pass = kr_str("0");
    while (kr_truthy(kr_lt(pass, kr_str("3")))) {
        result = passDeadCode(result);
        result = passFold(result);
        result = passStrength(result);
        result = passStoreLoad(result);
        result = passEmptyJump(result);
        pass = kr_plus(pass, kr_str("1"));
    }
    result = passUnusedLocals(result);
    return result;
}

char* countInstructions(char* ir) {
    char* count = kr_linecount(ir);
    char* real = kr_str("0");
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, count))) {
        char* line = kr_getline(ir, i);
        if (kr_truthy(kr_gt(kr_len(line), kr_str("0")))) {
            char* first = kr_idx(line, kr_atoi(kr_str("0")));
            if (kr_truthy((kr_truthy(kr_neq(first, kr_str(";"))) && kr_truthy(kr_neq(first, kr_str(" "))) ? kr_str("1") : kr_str("0")))) {
                real = kr_plus(real, kr_str("1"));
            }
        }
        i = kr_plus(i, kr_str("1"));
    }
    return kr_plus(real, kr_str(""));
}

int main(int argc, char** argv) {
    _argc = argc; _argv = argv;
    srand((unsigned)time(NULL));
    char* file = kr_arg(kr_str("0"));
    char* ir = kr_readfile(file);
    if (kr_truthy(kr_eq(kr_len(ir), kr_str("0")))) {
        kr_printerr(kr_plus(kr_str("optimize: cannot read file: "), file));
        return 0;
    }
    char* before = countInstructions(ir);
    char* optimized = optimize(ir);
    char* after = countInstructions(optimized);
    kr_printerr(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("; optimizer: "), before), kr_str(" -> ")), after), kr_str(" instructions (")), kr_sub(kr_toint(before), kr_toint(after))), kr_str(" removed)")));
    kr_print(optimized);
    return 0;
}

