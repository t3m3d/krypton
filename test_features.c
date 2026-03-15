#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int _argc; static char** _argv;

typedef struct ABlock { struct ABlock* next; int cap; int used; } ABlock;
static ABlock* _arena = 0;
static char* _alloc(int n) {
    n = (n + 7) & ~7;
    if (!_arena || _arena->used + n > _arena->cap) {
        int cap = 256*1024*1024;
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

char* findLastComma(char*);
char* pairVal(char*);
char* pairPos(char*);
char* isDigit(char*);
char* isAlpha(char*);
char* isAlphaNum(char*);
char* readNumber(char*, char*);
char* readIdent(char*, char*);
char* readString(char*, char*);
char* skipWS(char*, char*);
char* skipComment(char*, char*);
char* isKW(char*);
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
char* compileUnary(char*, char*, char*);
char* compilePostfix(char*, char*, char*);
char* compilePrimary(char*, char*, char*);
char* compileCall(char*, char*, char*);
char* compileStmt(char*, char*, char*, char*, char*);
char* compileLet(char*, char*, char*, char*);
char* compileAssign(char*, char*, char*, char*);
char* compileEmit(char*, char*, char*, char*, char*);
char* compileIf(char*, char*, char*, char*, char*);
char* compileWhile(char*, char*, char*, char*, char*);
char* compileCompoundAssign(char*, char*, char*, char*);
char* compileFor(char*, char*, char*, char*, char*);
char* compileMatch(char*, char*, char*, char*, char*);
char* compileDoWhile(char*, char*, char*, char*, char*);
char* compileExprStmt(char*, char*, char*, char*);
char* compileBlock(char*, char*, char*, char*, char*);
char* compileFunc(char*, char*, char*);
char* sbNew();
char* sbAppend(char*, char*);
char* sbToString(char*);
char* cRuntime();

char* findLastComma(char* s) {
    char* i = kr_sub(kr_len(s), kr_str("1"));
    while (kr_truthy(kr_gte(i, kr_str("0")))) {
        if (kr_truthy(kr_eq(kr_idx(s, kr_atoi(i)), kr_str(",")))) {
            return i;
        }
        i = kr_sub(i, kr_str("1"));
    }
    return kr_neg(kr_str("1"));
}

char* pairVal(char* pair) {
    char* c = findLastComma(pair);
    if (kr_truthy(kr_lt(c, kr_str("0")))) {
        return pair;
    }
    return kr_substr(pair, kr_str("0"), c);
}

char* pairPos(char* pair) {
    char* c = findLastComma(pair);
    return kr_toint(kr_substr(pair, kr_plus(c, kr_str("1")), kr_len(pair)));
}

char* isDigit(char* c) {
    return (kr_truthy(kr_gte(c, kr_str("0"))) && kr_truthy(kr_lte(c, kr_str("9"))) ? kr_str("1") : kr_str("0"));
}

char* isAlpha(char* c) {
    return (kr_truthy((kr_truthy((kr_truthy(kr_gte(c, kr_str("a"))) && kr_truthy(kr_lte(c, kr_str("z"))) ? kr_str("1") : kr_str("0"))) || kr_truthy((kr_truthy(kr_gte(c, kr_str("A"))) && kr_truthy(kr_lte(c, kr_str("Z"))) ? kr_str("1") : kr_str("0"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(c, kr_str("_"))) ? kr_str("1") : kr_str("0"));
}

char* isAlphaNum(char* c) {
    return (kr_truthy(isAlpha(c)) || kr_truthy(isDigit(c)) ? kr_str("1") : kr_str("0"));
}

char* readNumber(char* text, char* i) {
    char* start = i;
    while (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy(isDigit(kr_idx(text, kr_atoi(i)))) ? kr_str("1") : kr_str("0")))) {
        i = kr_plus(i, kr_str("1"));
    }
    return kr_plus(kr_plus(kr_substr(text, start, i), kr_str(",")), i);
}

char* readIdent(char* text, char* i) {
    char* start = i;
    while (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy(isAlphaNum(kr_idx(text, kr_atoi(i)))) ? kr_str("1") : kr_str("0")))) {
        i = kr_plus(i, kr_str("1"));
    }
    return kr_plus(kr_plus(kr_substr(text, start, i), kr_str(",")), i);
}

char* readString(char* text, char* i) {
    i = kr_plus(i, kr_str("1"));
    char* start = i;
    char* s = kr_str("");
    while (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy(kr_neq(kr_idx(text, kr_atoi(i)), kr_str("\""))) ? kr_str("1") : kr_str("0")))) {
        if (kr_truthy((kr_truthy(kr_eq(kr_idx(text, kr_atoi(i)), kr_str("\\"))) && kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) ? kr_str("1") : kr_str("0")))) {
            if (kr_truthy(kr_gt(i, start))) {
                s = kr_plus(s, kr_substr(text, start, i));
            }
            s = kr_plus(s, kr_substr(text, i, kr_plus(i, kr_str("2"))));
            i = kr_plus(i, kr_str("2"));
            start = i;
        } else {
            i = kr_plus(i, kr_str("1"));
        }
    }
    if (kr_truthy(kr_gt(i, start))) {
        s = kr_plus(s, kr_substr(text, start, i));
    }
    return kr_plus(kr_plus(s, kr_str(",")), kr_plus(i, kr_str("1")));
}

char* skipWS(char* text, char* i) {
    while (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(kr_idx(text, kr_atoi(i)), kr_str(" "))) || kr_truthy(kr_eq(kr_idx(text, kr_atoi(i)), kr_str("\n"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(kr_idx(text, kr_atoi(i)), kr_str("\t"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(kr_idx(text, kr_atoi(i)), kr_str("\\r"))) ? kr_str("1") : kr_str("0"))) ? kr_str("1") : kr_str("0")))) {
        i = kr_plus(i, kr_str("1"));
    }
    return i;
}

char* skipComment(char* text, char* i) {
    if (kr_truthy((kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(i)), kr_str("/"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("/"))) ? kr_str("1") : kr_str("0")))) {
        while (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy(kr_neq(kr_idx(text, kr_atoi(i)), kr_str("\n"))) ? kr_str("1") : kr_str("0")))) {
            i = kr_plus(i, kr_str("1"));
        }
        return i;
    } else if (kr_truthy((kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(i)), kr_str("/"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("*"))) ? kr_str("1") : kr_str("0")))) {
        i = kr_plus(i, kr_str("2"));
        while (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy((kr_truthy(kr_neq(kr_idx(text, kr_atoi(i)), kr_str("*"))) || kr_truthy(kr_neq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("/"))) ? kr_str("1") : kr_str("0"))) ? kr_str("1") : kr_str("0")))) {
            i = kr_plus(i, kr_str("1"));
        }
        return kr_plus(i, kr_str("2"));
    }
    return i;
}

char* isKW(char* word) {
    if (kr_truthy(kr_eq(word, kr_str("just")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("go")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("func")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("fn")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("let")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("emit")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("return")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("if")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("else")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("while")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("break")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("continue")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("for")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("in")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("match")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("do")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("const")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("module")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("import")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("export")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("quantum")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("qpute")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("process")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("true")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("false")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("measure")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("prepare")))) {
        return kr_str("1");
    } else {
        return kr_str("0");
    }
}

char* tokenize(char* text) {
    char* out = kr_str("");
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, kr_len(text)))) {
        i = skipWS(text, i);
        if (kr_truthy(kr_gte(i, kr_len(text)))) {
            break;
        }
        char* c = kr_idx(text, kr_atoi(i));
        if (kr_truthy((kr_truthy((kr_truthy(kr_eq(c, kr_str("/"))) && kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) ? kr_str("1") : kr_str("0"))) && kr_truthy((kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("/"))) || kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("*"))) ? kr_str("1") : kr_str("0"))) ? kr_str("1") : kr_str("0")))) {
            i = skipComment(text, i);
        } else if (kr_truthy(isDigit(c))) {
            char* pair = readNumber(text, i);
            char* num = pairVal(pair);
            i = pairPos(pair);
            out = kr_plus(kr_plus(kr_plus(out, kr_str("INT:")), num), kr_str("\n"));
        } else if (kr_truthy(kr_eq(c, kr_str("\"")))) {
            char* pair = readString(text, i);
            char* str = pairVal(pair);
            i = pairPos(pair);
            out = kr_plus(kr_plus(kr_plus(out, kr_str("STR:")), str), kr_str("\n"));
        } else if (kr_truthy(isAlpha(c))) {
            char* pair = readIdent(text, i);
            char* id = pairVal(pair);
            i = pairPos(pair);
            if (kr_truthy(isKW(id))) {
                out = kr_plus(kr_plus(kr_plus(out, kr_str("KW:")), id), kr_str("\n"));
            } else {
                out = kr_plus(kr_plus(kr_plus(out, kr_str("ID:")), id), kr_str("\n"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("+")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_plus(out, kr_str("PLUSEQ\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                out = kr_plus(out, kr_str("PLUS\n"));
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("-")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str(">"))) ? kr_str("1") : kr_str("0")))) {
                out = kr_plus(out, kr_str("ARROW\n"));
                i = kr_plus(i, kr_str("2"));
            } else if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_plus(out, kr_str("MINUSEQ\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                out = kr_plus(out, kr_str("MINUS\n"));
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("*")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_plus(out, kr_str("STAREQ\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                out = kr_plus(out, kr_str("STAR\n"));
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("/")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_plus(out, kr_str("SLASHEQ\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                out = kr_plus(out, kr_str("SLASH\n"));
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("(")))) {
            out = kr_plus(out, kr_str("LPAREN\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str(")")))) {
            out = kr_plus(out, kr_str("RPAREN\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str("{")))) {
            out = kr_plus(out, kr_str("LBRACE\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str("}")))) {
            out = kr_plus(out, kr_str("RBRACE\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str("[")))) {
            out = kr_plus(out, kr_str("LBRACK\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str("]")))) {
            out = kr_plus(out, kr_str("RBRACK\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str(":")))) {
            out = kr_plus(out, kr_str("COLON\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str(";")))) {
            out = kr_plus(out, kr_str("SEMI\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str(",")))) {
            out = kr_plus(out, kr_str("COMMA\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str("=")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_plus(out, kr_str("EQ\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                out = kr_plus(out, kr_str("ASSIGN\n"));
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("!")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_plus(out, kr_str("NEQ\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                out = kr_plus(out, kr_str("BANG\n"));
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("<")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_plus(out, kr_str("LTE\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                out = kr_plus(out, kr_str("LT\n"));
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str(">")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_plus(out, kr_str("GTE\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                out = kr_plus(out, kr_str("GT\n"));
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("&")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("&"))) ? kr_str("1") : kr_str("0")))) {
                out = kr_plus(out, kr_str("AND\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("|")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("|"))) ? kr_str("1") : kr_str("0")))) {
                out = kr_plus(out, kr_str("OR\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("%")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_plus(out, kr_str("MODEQ\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                out = kr_plus(out, kr_str("MOD\n"));
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("?")))) {
            out = kr_plus(out, kr_str("QUESTION\n"));
            i = kr_plus(i, kr_str("1"));
        } else {
            i = kr_plus(i, kr_str("1"));
        }
    }
    return out;
}

char* tokAt(char* tokens, char* idx) {
    return kr_getline(tokens, idx);
}

char* tokType(char* tok) {
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, kr_len(tok)))) {
        if (kr_truthy(kr_eq(kr_idx(tok, kr_atoi(i)), kr_str(":")))) {
            return kr_substr(tok, kr_str("0"), i);
        }
        i = kr_plus(i, kr_str("1"));
    }
    return tok;
}

char* tokVal(char* tok) {
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, kr_len(tok)))) {
        if (kr_truthy(kr_eq(kr_idx(tok, kr_atoi(i)), kr_str(":")))) {
            return kr_substr(tok, kr_plus(i, kr_str("1")), kr_len(tok));
        }
        i = kr_plus(i, kr_str("1"));
    }
    return kr_str("");
}

char* cEscape(char* s) {
    char* out = kr_str("");
    char* i = kr_str("0");
    char* start = kr_str("0");
    while (kr_truthy(kr_lt(i, kr_len(s)))) {
        char* c = kr_idx(s, kr_atoi(i));
        if (kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(c, kr_str("\\"))) || kr_truthy(kr_eq(c, kr_str("\""))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(c, kr_str("\n"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(c, kr_str("\\r"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(c, kr_str("\t"))) ? kr_str("1") : kr_str("0")))) {
            if (kr_truthy(kr_gt(i, start))) {
                out = kr_plus(out, kr_substr(s, start, i));
            }
            if (kr_truthy(kr_eq(c, kr_str("\\")))) {
                out = kr_plus(out, kr_str("\\\\"));
            } else if (kr_truthy(kr_eq(c, kr_str("\"")))) {
                out = kr_plus(out, kr_str("\\\""));
            } else if (kr_truthy(kr_eq(c, kr_str("\n")))) {
                out = kr_plus(out, kr_str("\\n"));
            } else if (kr_truthy(kr_eq(c, kr_str("\\r")))) {
                out = kr_plus(out, kr_str("\\r"));
            } else if (kr_truthy(kr_eq(c, kr_str("\t")))) {
                out = kr_plus(out, kr_str("\\t"));
            }
            start = kr_plus(i, kr_str("1"));
        }
        i = kr_plus(i, kr_str("1"));
    }
    if (kr_truthy(kr_gt(i, start))) {
        out = kr_plus(out, kr_substr(s, start, i));
    }
    return out;
}

char* expandEscapes(char* s) {
    char* out = kr_str("");
    char* i = kr_str("0");
    char* start = kr_str("0");
    while (kr_truthy(kr_lt(i, kr_len(s)))) {
        if (kr_truthy(kr_eq(kr_idx(s, kr_atoi(i)), kr_str("\\")))) {
            if (kr_truthy(kr_gt(i, start))) {
                out = kr_plus(out, kr_substr(s, start, i));
            }
            i = kr_plus(i, kr_str("1"));
            if (kr_truthy(kr_lt(i, kr_len(s)))) {
                char* c = kr_idx(s, kr_atoi(i));
                if (kr_truthy(kr_eq(c, kr_str("n")))) {
                    out = kr_plus(out, kr_str("\n"));
                } else if (kr_truthy(kr_eq(c, kr_str("t")))) {
                    out = kr_plus(out, kr_str("\t"));
                } else if (kr_truthy(kr_eq(c, kr_str("r")))) {
                    out = kr_plus(out, kr_str("\\r"));
                } else if (kr_truthy(kr_eq(c, kr_str("\\")))) {
                    out = kr_plus(out, kr_str("\\"));
                } else if (kr_truthy(kr_eq(c, kr_str("\"")))) {
                    out = kr_plus(out, kr_str("\""));
                } else {
                    out = kr_plus(kr_plus(out, kr_str("\\")), c);
                }
            }
            start = kr_plus(i, kr_str("1"));
        }
        i = kr_plus(i, kr_str("1"));
    }
    if (kr_truthy(kr_gt(i, start))) {
        out = kr_plus(out, kr_substr(s, start, i));
    }
    return out;
}

char* scanFunctions(char* tokens, char* ntoks) {
    char* table = kr_str("");
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* tok = tokAt(tokens, i);
        if (kr_truthy(kr_eq(tok, kr_str("KW:func")))) {
            char* nameTok = tokAt(tokens, kr_plus(i, kr_str("1")));
            char* fname = tokVal(nameTok);
            char* j = kr_plus(i, kr_str("3"));
            char* params = kr_str("");
            char* pc = kr_str("0");
            while (kr_truthy(kr_neq(tokAt(tokens, j), kr_str("RPAREN")))) {
                char* pt = tokAt(tokens, j);
                if (kr_truthy(kr_eq(tokType(pt), kr_str("ID")))) {
                    if (kr_truthy(kr_gt(pc, kr_str("0")))) {
                        params = kr_plus(kr_plus(params, kr_str(",")), tokVal(pt));
                    } else {
                        params = tokVal(pt);
                    }
                    pc = kr_plus(pc, kr_str("1"));
                }
                j = kr_plus(j, kr_str("1"));
            }
            char* bodyStart = kr_plus(j, kr_str("1"));
            table = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(table, fname), kr_str("~")), pc), kr_str("~")), params), kr_str("~")), bodyStart), kr_str("\n"));
        }
        i = kr_plus(i, kr_str("1"));
    }
    return table;
}

char* funcLookup(char* table, char* name) {
    char* i = kr_str("0");
    char* tlen = kr_len(table);
    while (kr_truthy(kr_lt(i, tlen))) {
        char* nl = i;
        while (kr_truthy(kr_lt(nl, tlen))) {
            if (kr_truthy(kr_eq(kr_idx(table, kr_atoi(nl)), kr_str("\n")))) {
                break;
            }
            nl = kr_plus(nl, kr_str("1"));
        }
        char* line = kr_substr(table, i, nl);
        char* t1 = kr_str("0");
        while (kr_truthy(kr_lt(t1, kr_len(line)))) {
            if (kr_truthy(kr_eq(kr_idx(line, kr_atoi(t1)), kr_str("~")))) {
                break;
            }
            t1 = kr_plus(t1, kr_str("1"));
        }
        char* fnom = kr_substr(line, kr_str("0"), t1);
        if (kr_truthy(kr_eq(fnom, name))) {
            return kr_substr(line, kr_plus(t1, kr_str("1")), kr_len(line));
        }
        i = kr_plus(nl, kr_str("1"));
    }
    return kr_str("");
}

char* funcParamCount(char* info) {
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, kr_len(info)))) {
        if (kr_truthy(kr_eq(kr_idx(info, kr_atoi(i)), kr_str("~")))) {
            return kr_toint(kr_substr(info, kr_str("0"), i));
        }
        i = kr_plus(i, kr_str("1"));
    }
    return kr_str("0");
}

char* funcParams(char* info) {
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, kr_len(info)))) {
        if (kr_truthy(kr_eq(kr_idx(info, kr_atoi(i)), kr_str("~")))) {
            char* rest = kr_substr(info, kr_plus(i, kr_str("1")), kr_len(info));
            char* j = kr_str("0");
            while (kr_truthy(kr_lt(j, kr_len(rest)))) {
                if (kr_truthy(kr_eq(kr_idx(rest, kr_atoi(j)), kr_str("~")))) {
                    return kr_substr(rest, kr_str("0"), j);
                }
                j = kr_plus(j, kr_str("1"));
            }
            return rest;
        }
        i = kr_plus(i, kr_str("1"));
    }
    return kr_str("");
}

char* funcStart(char* info) {
    char* i = kr_sub(kr_len(info), kr_str("1"));
    while (kr_truthy(kr_gte(i, kr_str("0")))) {
        if (kr_truthy(kr_eq(kr_idx(info, kr_atoi(i)), kr_str("~")))) {
            return kr_toint(kr_substr(info, kr_plus(i, kr_str("1")), kr_len(info)));
        }
        i = kr_sub(i, kr_str("1"));
    }
    return kr_str("0");
}

char* getNthParam(char* params, char* idx) {
    char* count = kr_str("0");
    char* start = kr_str("0");
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, kr_len(params)))) {
        if (kr_truthy(kr_eq(kr_idx(params, kr_atoi(i)), kr_str(",")))) {
            if (kr_truthy(kr_eq(count, idx))) {
                return kr_substr(params, start, i);
            }
            count = kr_plus(count, kr_str("1"));
            start = kr_plus(i, kr_str("1"));
        }
        i = kr_plus(i, kr_str("1"));
    }
    if (kr_truthy(kr_eq(count, idx))) {
        return kr_substr(params, start, kr_len(params));
    }
    return kr_str("");
}

char* findEntry(char* tokens, char* ntoks) {
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* tok = tokAt(tokens, i);
        if (kr_truthy((kr_truthy(kr_eq(tok, kr_str("KW:just"))) || kr_truthy(kr_eq(tok, kr_str("KW:go"))) ? kr_str("1") : kr_str("0")))) {
            if (kr_truthy(kr_lt(kr_plus(i, kr_str("2")), ntoks))) {
                char* next = tokAt(tokens, kr_plus(i, kr_str("1")));
                if (kr_truthy(kr_eq(next, kr_str("ID:run")))) {
                    if (kr_truthy(kr_eq(tokAt(tokens, kr_plus(i, kr_str("2"))), kr_str("LBRACE")))) {
                        return kr_plus(i, kr_str("2"));
                    }
                }
            }
        }
        i = kr_plus(i, kr_str("1"));
    }
    return kr_sub(kr_str("0"), kr_str("1"));
}

char* skipBlock(char* tokens, char* pos) {
    char* depth = kr_str("1");
    char* p = kr_plus(pos, kr_str("1"));
    while (kr_truthy(kr_gt(depth, kr_str("0")))) {
        char* t = tokAt(tokens, p);
        if (kr_truthy(kr_eq(t, kr_str("LBRACE")))) {
            depth = kr_plus(depth, kr_str("1"));
        }
        if (kr_truthy(kr_eq(t, kr_str("RBRACE")))) {
            depth = kr_sub(depth, kr_str("1"));
        }
        p = kr_plus(p, kr_str("1"));
    }
    return p;
}

char* indent(char* depth) {
    char* out = kr_str("");
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, depth))) {
        out = kr_plus(out, kr_str("    "));
        i = kr_plus(i, kr_str("1"));
    }
    return out;
}

char* cIdent(char* name) {
    if (kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(name, kr_str("int"))) || kr_truthy(kr_eq(name, kr_str("char"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("void"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("return"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("if"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("else"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("while"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("break"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("for"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("do"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("switch"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("case"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("default"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("struct"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("const"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("static"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("long"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("short"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("double"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("float"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("auto"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("register"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("extern"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("typedef"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("union"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("enum"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("sizeof"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("goto"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("volatile"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("signed"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("unsigned"))) ? kr_str("1") : kr_str("0")))) {
        return kr_plus(kr_str("k_"), name);
    }
    return name;
}

char* compileExpr(char* tokens, char* pos, char* ntoks) {
    return compileTernary(tokens, pos, ntoks);
}

char* compileTernary(char* tokens, char* pos, char* ntoks) {
    char* pair = compileOr(tokens, pos, ntoks);
    char* code = pairVal(pair);
    char* p = pairPos(pair);
    if (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("QUESTION")))) {
        char* tp = compileExpr(tokens, kr_plus(p, kr_str("1")), ntoks);
        char* tcode = pairVal(tp);
        p = pairPos(tp);
        p = kr_plus(p, kr_str("1"));
        char* fp = compileExpr(tokens, p, ntoks);
        char* fcode = pairVal(fp);
        p = pairPos(fp);
        code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("(kr_truthy("), code), kr_str(") ? ")), tcode), kr_str(" : ")), fcode), kr_str(")"));
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* compileOr(char* tokens, char* pos, char* ntoks) {
    char* pair = compileAnd(tokens, pos, ntoks);
    char* code = pairVal(pair);
    char* p = pairPos(pair);
    while (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("OR")))) {
        char* rp = compileAnd(tokens, kr_plus(p, kr_str("1")), ntoks);
        char* rcode = pairVal(rp);
        p = pairPos(rp);
        code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("(kr_truthy("), code), kr_str(") || kr_truthy(")), rcode), kr_str(") ? kr_str(\"1\") : kr_str(\"0\"))"));
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* compileAnd(char* tokens, char* pos, char* ntoks) {
    char* pair = compileEquality(tokens, pos, ntoks);
    char* code = pairVal(pair);
    char* p = pairPos(pair);
    while (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("AND")))) {
        char* rp = compileEquality(tokens, kr_plus(p, kr_str("1")), ntoks);
        char* rcode = pairVal(rp);
        p = pairPos(rp);
        code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("(kr_truthy("), code), kr_str(") && kr_truthy(")), rcode), kr_str(") ? kr_str(\"1\") : kr_str(\"0\"))"));
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* compileEquality(char* tokens, char* pos, char* ntoks) {
    char* pair = compileRelational(tokens, pos, ntoks);
    char* code = pairVal(pair);
    char* p = pairPos(pair);
    while (kr_truthy((kr_truthy(kr_eq(tokAt(tokens, p), kr_str("EQ"))) || kr_truthy(kr_eq(tokAt(tokens, p), kr_str("NEQ"))) ? kr_str("1") : kr_str("0")))) {
        char* op = tokAt(tokens, p);
        char* rp = compileRelational(tokens, kr_plus(p, kr_str("1")), ntoks);
        char* rcode = pairVal(rp);
        p = pairPos(rp);
        if (kr_truthy(kr_eq(op, kr_str("EQ")))) {
            code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_eq("), code), kr_str(", ")), rcode), kr_str(")"));
        } else {
            code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_neq("), code), kr_str(", ")), rcode), kr_str(")"));
        }
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* compileRelational(char* tokens, char* pos, char* ntoks) {
    char* pair = compileAdditive(tokens, pos, ntoks);
    char* code = pairVal(pair);
    char* p = pairPos(pair);
    while (kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(tokAt(tokens, p), kr_str("LT"))) || kr_truthy(kr_eq(tokAt(tokens, p), kr_str("GT"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(tokAt(tokens, p), kr_str("LTE"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(tokAt(tokens, p), kr_str("GTE"))) ? kr_str("1") : kr_str("0")))) {
        char* op = tokAt(tokens, p);
        char* rp = compileAdditive(tokens, kr_plus(p, kr_str("1")), ntoks);
        char* rcode = pairVal(rp);
        p = pairPos(rp);
        if (kr_truthy(kr_eq(op, kr_str("LT")))) {
            code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_lt("), code), kr_str(", ")), rcode), kr_str(")"));
        } else if (kr_truthy(kr_eq(op, kr_str("GT")))) {
            code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_gt("), code), kr_str(", ")), rcode), kr_str(")"));
        } else if (kr_truthy(kr_eq(op, kr_str("LTE")))) {
            code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_lte("), code), kr_str(", ")), rcode), kr_str(")"));
        } else {
            code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_gte("), code), kr_str(", ")), rcode), kr_str(")"));
        }
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* compileAdditive(char* tokens, char* pos, char* ntoks) {
    char* pair = compileMult(tokens, pos, ntoks);
    char* code = pairVal(pair);
    char* p = pairPos(pair);
    while (kr_truthy((kr_truthy(kr_eq(tokAt(tokens, p), kr_str("PLUS"))) || kr_truthy(kr_eq(tokAt(tokens, p), kr_str("MINUS"))) ? kr_str("1") : kr_str("0")))) {
        char* op = tokAt(tokens, p);
        char* rp = compileMult(tokens, kr_plus(p, kr_str("1")), ntoks);
        char* rcode = pairVal(rp);
        p = pairPos(rp);
        if (kr_truthy(kr_eq(op, kr_str("PLUS")))) {
            code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_plus("), code), kr_str(", ")), rcode), kr_str(")"));
        } else {
            code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_sub("), code), kr_str(", ")), rcode), kr_str(")"));
        }
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* compileMult(char* tokens, char* pos, char* ntoks) {
    char* pair = compileUnary(tokens, pos, ntoks);
    char* code = pairVal(pair);
    char* p = pairPos(pair);
    while (kr_truthy((kr_truthy((kr_truthy(kr_eq(tokAt(tokens, p), kr_str("STAR"))) || kr_truthy(kr_eq(tokAt(tokens, p), kr_str("SLASH"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(tokAt(tokens, p), kr_str("MOD"))) ? kr_str("1") : kr_str("0")))) {
        char* op = tokAt(tokens, p);
        char* rp = compileUnary(tokens, kr_plus(p, kr_str("1")), ntoks);
        char* rcode = pairVal(rp);
        p = pairPos(rp);
        if (kr_truthy(kr_eq(op, kr_str("STAR")))) {
            code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_mul("), code), kr_str(", ")), rcode), kr_str(")"));
        } else if (kr_truthy(kr_eq(op, kr_str("SLASH")))) {
            code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_div("), code), kr_str(", ")), rcode), kr_str(")"));
        } else {
            code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_mod("), code), kr_str(", ")), rcode), kr_str(")"));
        }
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* compileUnary(char* tokens, char* pos, char* ntoks) {
    char* tok = tokAt(tokens, pos);
    if (kr_truthy(kr_eq(tok, kr_str("MINUS")))) {
        char* rp = compileUnary(tokens, kr_plus(pos, kr_str("1")), ntoks);
        char* rcode = pairVal(rp);
        char* p = pairPos(rp);
        return kr_plus(kr_plus(kr_plus(kr_str("kr_neg("), rcode), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("BANG")))) {
        char* rp = compileUnary(tokens, kr_plus(pos, kr_str("1")), ntoks);
        char* rcode = pairVal(rp);
        char* p = pairPos(rp);
        return kr_plus(kr_plus(kr_plus(kr_str("kr_not("), rcode), kr_str("),")), p);
    }
    return compilePostfix(tokens, pos, ntoks);
}

char* compilePostfix(char* tokens, char* pos, char* ntoks) {
    char* pair = compilePrimary(tokens, pos, ntoks);
    char* code = pairVal(pair);
    char* p = pairPos(pair);
    while (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("LBRACK")))) {
        char* ip = compileExpr(tokens, kr_plus(p, kr_str("1")), ntoks);
        char* icode = pairVal(ip);
        p = pairPos(ip);
        p = kr_plus(p, kr_str("1"));
        code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_idx("), code), kr_str(", kr_atoi(")), icode), kr_str("))"));
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* compilePrimary(char* tokens, char* pos, char* ntoks) {
    char* tok = tokAt(tokens, pos);
    char* tt = tokType(tok);
    char* tv = tokVal(tok);
    if (kr_truthy(kr_eq(tt, kr_str("INT")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_str(\""), tv), kr_str("\"),")), kr_plus(pos, kr_str("1")));
    }
    if (kr_truthy(kr_eq(tt, kr_str("STR")))) {
        char* expanded = expandEscapes(tv);
        char* escaped = cEscape(expanded);
        return kr_plus(kr_plus(kr_plus(kr_str("kr_str(\""), escaped), kr_str("\"),")), kr_plus(pos, kr_str("1")));
    }
    if (kr_truthy(kr_eq(tt, kr_str("KW")))) {
        if (kr_truthy(kr_eq(tv, kr_str("true")))) {
            return kr_plus(kr_str("kr_str(\"1\"),"), kr_plus(pos, kr_str("1")));
        }
        if (kr_truthy(kr_eq(tv, kr_str("false")))) {
            return kr_plus(kr_str("kr_str(\"0\"),"), kr_plus(pos, kr_str("1")));
        }
    }
    if (kr_truthy(kr_eq(tok, kr_str("LPAREN")))) {
        char* ep = compileExpr(tokens, kr_plus(pos, kr_str("1")), ntoks);
        char* ecode = pairVal(ep);
        char* p = pairPos(ep);
        return kr_plus(kr_plus(ecode, kr_str(",")), kr_plus(p, kr_str("1")));
    }
    if (kr_truthy(kr_eq(tt, kr_str("ID")))) {
        char* name = tv;
        if (kr_truthy(kr_eq(tokAt(tokens, kr_plus(pos, kr_str("1"))), kr_str("LPAREN")))) {
            return compileCall(tokens, pos, ntoks);
        }
        return kr_plus(kr_plus(cIdent(name), kr_str(",")), kr_plus(pos, kr_str("1")));
    }
    return kr_plus(kr_str("kr_str(\"\"),"), kr_plus(pos, kr_str("1")));
}

char* compileCall(char* tokens, char* pos, char* ntoks) {
    char* fname = tokVal(tokAt(tokens, pos));
    char* p = kr_plus(pos, kr_str("2"));
    char* args = kr_str("");
    char* argc = kr_str("0");
    while (kr_truthy(kr_neq(tokAt(tokens, p), kr_str("RPAREN")))) {
        if (kr_truthy(kr_gt(argc, kr_str("0")))) {
            p = kr_plus(p, kr_str("1"));
        }
        char* ap = compileExpr(tokens, p, ntoks);
        char* acode = pairVal(ap);
        p = pairPos(ap);
        if (kr_truthy(kr_gt(argc, kr_str("0")))) {
            args = kr_plus(kr_plus(args, kr_str(", ")), acode);
        } else {
            args = acode;
        }
        argc = kr_plus(argc, kr_str("1"));
    }
    p = kr_plus(p, kr_str("1"));
    if (kr_truthy((kr_truthy(kr_eq(fname, kr_str("kp"))) || kr_truthy(kr_eq(fname, kr_str("print"))) ? kr_str("1") : kr_str("0")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_print("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("len")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_len("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("substring")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_substr("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("toInt")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_toint("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("split")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_split("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("startsWith")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_startswith("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("readFile")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_readfile("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("arg")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_arg("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("argCount")))) {
        return kr_plus(kr_str("kr_argcount(),"), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("getLine")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_getline("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("lineCount")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_linecount("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("count")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_count("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("envNew")))) {
        return kr_plus(kr_str("kr_envnew(),"), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("envSet")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_envset("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("envGet")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_envget("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("makeResult")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_makeresult("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("getResultTag")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_getresulttag("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("getResultVal")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_getresultval("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("getResultEnv")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_getresultenv("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("getResultPos")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_getresultpos("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("isTruthy")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_istruthy("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("sbNew")))) {
        return kr_plus(kr_str("kr_sbnew(),"), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("sbAppend")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_sbappend("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("sbToString")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_sbtostring("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("writeFile")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_writefile("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("input")))) {
        return kr_plus(kr_str("kr_input(),"), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("indexOf")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_indexof("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("replace")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_replace("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("charAt")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_charat("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("trim")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_trim("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("toLower")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_tolower("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("toUpper")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_toupper("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("contains")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_contains("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("endsWith")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_endswith("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("abs")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_abs("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("min")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_min("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("max")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_max("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("exit")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_exit("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("type")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_type("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("append")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_append("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("join")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_join("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("reverse")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_reverse("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("sort")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_sort("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("keys")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_keys("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("values")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_values("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("hasKey")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_haskey("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("remove")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_remove("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("repeat")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_repeat("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("format")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_format("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("parseInt")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_parseint("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("toStr")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_tostr("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("range")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_range("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("pow")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_pow("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("sqrt")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_sqrt("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("sign")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_sign("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("clamp")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_clamp("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("padLeft")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_padleft("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("padRight")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_padright("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("charCode")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_charcode("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("fromCharCode")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_fromcharcode("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("slice")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_slice("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("length")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_length("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("unique")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_unique("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("printErr")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_printerr("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("readLine")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_readline("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("assert")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_assert("), args), kr_str(", \"assertion failed\"),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("splitBy")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_splitby("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("listIndexOf")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_listindexof("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("insertAt")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_insertat("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("removeAt")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_removeat("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("replaceAt")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_replaceat("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("fill")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_fill("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("zip")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_zip("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("every")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_every("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("some")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_some("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("countOf")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_countof("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("sumList")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_sumlist("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("maxList")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_maxlist("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("minList")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_minlist("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("hex")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_hex("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("bin")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_bin("), args), kr_str("),")), p);
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(cIdent(fname), kr_str("(")), args), kr_str("),")), p);
}

char* compileStmt(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* tok = tokAt(tokens, pos);
    if (kr_truthy((kr_truthy((kr_truthy(kr_eq(tok, kr_str("KW:struct"))) || kr_truthy(kr_eq(tok, kr_str("KW:class"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(tok, kr_str("KW:type"))) ? kr_str("1") : kr_str("0")))) {
        char* name = tokVal(tokAt(tokens, kr_plus(pos, kr_str("1"))));
        char* p = kr_plus(pos, kr_str("2"));
        char* bp = compileBlock(tokens, p, ntoks, depth, inFunc);
        char* bcode = pairVal(bp);
        p = pairPos(bp);
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(indent(depth), kr_str("// struct/class/type declaration\n")), indent(depth)), kr_str("typedef struct ")), cIdent(name)), kr_str(" {\n")), bcode), indent(depth)), kr_str("} ")), cIdent(name)), kr_str(";\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:try")))) {
        char* bp = compileBlock(tokens, kr_plus(pos, kr_str("1")), ntoks, depth, inFunc);
        char* bcode = pairVal(bp);
        char* p = pairPos(bp);
        if (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("KW:catch")))) {
            p = kr_plus(p, kr_str("1"));
            char* cbp = compileBlock(tokens, p, ntoks, depth, inFunc);
            char* cbcode = pairVal(cbp);
            p = pairPos(cbp);
            return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(indent(depth), kr_str("// try-catch\n")), indent(depth)), kr_str("try {\n")), bcode), indent(depth)), kr_str("} catch {\n")), cbcode), indent(depth)), kr_str("}\n,")), p);
        } else {
            return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(indent(depth), kr_str("// try block\n")), indent(depth)), kr_str("try {\n")), bcode), indent(depth)), kr_str("}\n,")), p);
        }
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:throw")))) {
        char* ep = compileExpr(tokens, kr_plus(pos, kr_str("1")), ntoks);
        char* ecode = pairVal(ep);
        char* p = pairPos(ep);
        if (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("SEMI")))) {
            p = kr_plus(p, kr_str("1"));
        }
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(indent(depth), kr_str("// throw statement\n")), indent(depth)), kr_str("throw ")), ecode), kr_str(";\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:let")))) {
        return compileLet(tokens, kr_plus(pos, kr_str("1")), ntoks, depth);
    }
    if (kr_truthy((kr_truthy(kr_eq(tok, kr_str("KW:emit"))) || kr_truthy(kr_eq(tok, kr_str("KW:return"))) ? kr_str("1") : kr_str("0")))) {
        return compileEmit(tokens, kr_plus(pos, kr_str("1")), ntoks, depth, inFunc);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:if")))) {
        return compileIf(tokens, kr_plus(pos, kr_str("1")), ntoks, depth, inFunc);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:while")))) {
        return compileWhile(tokens, kr_plus(pos, kr_str("1")), ntoks, depth, inFunc);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:for")))) {
        return compileFor(tokens, kr_plus(pos, kr_str("1")), ntoks, depth, inFunc);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:break")))) {
        char* p = kr_plus(pos, kr_str("1"));
        if (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("SEMI")))) {
            p = kr_plus(p, kr_str("1"));
        }
        return kr_plus(kr_plus(indent(depth), kr_str("break;\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:continue")))) {
        char* p = kr_plus(pos, kr_str("1"));
        if (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("SEMI")))) {
            p = kr_plus(p, kr_str("1"));
        }
        return kr_plus(kr_plus(indent(depth), kr_str("continue;\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:match")))) {
        return compileMatch(tokens, kr_plus(pos, kr_str("1")), ntoks, depth, inFunc);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:do")))) {
        return compileDoWhile(tokens, kr_plus(pos, kr_str("1")), ntoks, depth, inFunc);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:const")))) {
        return compileLet(tokens, kr_plus(pos, kr_str("1")), ntoks, depth);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:module")))) {
        char* name = tokVal(tokAt(tokens, kr_plus(pos, kr_str("1"))));
        char* p = kr_plus(pos, kr_str("2"));
        return kr_plus(kr_plus(kr_plus(kr_plus(indent(depth), kr_str("// module ")), name), kr_str("\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:import")))) {
        char* name = tokVal(tokAt(tokens, kr_plus(pos, kr_str("1"))));
        char* p = kr_plus(pos, kr_str("2"));
        return kr_plus(kr_plus(kr_plus(kr_plus(indent(depth), kr_str("// import ")), name), kr_str("\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:export")))) {
        char* name = tokVal(tokAt(tokens, kr_plus(pos, kr_str("1"))));
        char* p = kr_plus(pos, kr_str("2"));
        return kr_plus(kr_plus(kr_plus(kr_plus(indent(depth), kr_str("// export ")), name), kr_str("\n,")), p);
    }
    if (kr_truthy(kr_eq(tokType(tok), kr_str("ID")))) {
        char* nextTok = tokAt(tokens, kr_plus(pos, kr_str("1")));
        if (kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(nextTok, kr_str("PLUSEQ"))) || kr_truthy(kr_eq(nextTok, kr_str("MINUSEQ"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(nextTok, kr_str("STAREQ"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(nextTok, kr_str("SLASHEQ"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(nextTok, kr_str("MODEQ"))) ? kr_str("1") : kr_str("0")))) {
            return compileCompoundAssign(tokens, pos, ntoks, depth);
        }
    }
    if (kr_truthy(kr_eq(tokType(tok), kr_str("ID")))) {
        if (kr_truthy(kr_eq(tokAt(tokens, kr_plus(pos, kr_str("1"))), kr_str("ASSIGN")))) {
            return compileAssign(tokens, pos, ntoks, depth);
        }
    }
    return compileExprStmt(tokens, pos, ntoks, depth);
}

char* compileLet(char* tokens, char* pos, char* ntoks, char* depth) {
    char* name = tokVal(tokAt(tokens, pos));
    char* p = kr_plus(pos, kr_str("2"));
    char* ep = compileExpr(tokens, p, ntoks);
    char* ecode = pairVal(ep);
    p = pairPos(ep);
    if (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("SEMI")))) {
        p = kr_plus(p, kr_str("1"));
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(indent(depth), kr_str("char* ")), cIdent(name)), kr_str(" = ")), ecode), kr_str(";\n,")), p);
}

char* compileAssign(char* tokens, char* pos, char* ntoks, char* depth) {
    char* name = tokVal(tokAt(tokens, pos));
    char* p = kr_plus(pos, kr_str("2"));
    char* ep = compileExpr(tokens, p, ntoks);
    char* ecode = pairVal(ep);
    p = pairPos(ep);
    if (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("SEMI")))) {
        p = kr_plus(p, kr_str("1"));
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(indent(depth), cIdent(name)), kr_str(" = ")), ecode), kr_str(";\n,")), p);
}

char* compileEmit(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* ep = compileExpr(tokens, pos, ntoks);
    char* ecode = pairVal(ep);
    char* p = pairPos(ep);
    if (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("SEMI")))) {
        p = kr_plus(p, kr_str("1"));
    }
    if (kr_truthy(kr_eq(inFunc, kr_str("1")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(indent(depth), kr_str("return ")), ecode), kr_str(";\n,")), p);
    }
    return kr_plus(kr_plus(indent(depth), kr_str("return 0;\n,")), p);
}

char* compileIf(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* cp = compileExpr(tokens, pos, ntoks);
    char* cond = pairVal(cp);
    char* p = pairPos(cp);
    char* bp = compileBlock(tokens, p, ntoks, depth, inFunc);
    char* bcode = pairVal(bp);
    p = pairPos(bp);
    char* out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(indent(depth), kr_str("if (kr_truthy(")), cond), kr_str(")) {\n")), bcode), indent(depth)), kr_str("}"));
    if (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("KW:else")))) {
        p = kr_plus(p, kr_str("1"));
        if (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("KW:if")))) {
            char* eip = compileIf(tokens, kr_plus(p, kr_str("1")), ntoks, depth, inFunc);
            char* eicode = pairVal(eip);
            p = pairPos(eip);
            char* stripped = kr_substr(eicode, kr_len(indent(depth)), kr_len(eicode));
            out = kr_plus(kr_plus(out, kr_str(" else ")), stripped);
            return kr_plus(kr_plus(out, kr_str(",")), p);
        } else {
            char* ebp = compileBlock(tokens, p, ntoks, depth, inFunc);
            char* ebcode = pairVal(ebp);
            p = pairPos(ebp);
            out = kr_plus(kr_plus(kr_plus(kr_plus(out, kr_str(" else {\n")), ebcode), indent(depth)), kr_str("}\n"));
            return kr_plus(kr_plus(out, kr_str(",")), p);
        }
    }
    out = kr_plus(out, kr_str("\n"));
    return kr_plus(kr_plus(out, kr_str(",")), p);
}

char* compileWhile(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* cp = compileExpr(tokens, pos, ntoks);
    char* cond = pairVal(cp);
    char* p = pairPos(cp);
    char* bp = compileBlock(tokens, p, ntoks, depth, inFunc);
    char* bcode = pairVal(bp);
    p = pairPos(bp);
    char* out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(indent(depth), kr_str("while (kr_truthy(")), cond), kr_str(")) {\n")), bcode), indent(depth)), kr_str("}\n"));
    return kr_plus(kr_plus(out, kr_str(",")), p);
}

char* compileCompoundAssign(char* tokens, char* pos, char* ntoks, char* depth) {
    char* name = tokVal(tokAt(tokens, pos));
    char* op = tokAt(tokens, kr_plus(pos, kr_str("1")));
    char* p = kr_plus(pos, kr_str("2"));
    char* ep = compileExpr(tokens, p, ntoks);
    char* ecode = pairVal(ep);
    p = pairPos(ep);
    if (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("SEMI")))) {
        p = kr_plus(p, kr_str("1"));
    }
    char* cname = cIdent(name);
    if (kr_truthy(kr_eq(op, kr_str("PLUSEQ")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(indent(depth), cname), kr_str(" = kr_plus(")), cname), kr_str(", ")), ecode), kr_str(");\n,")), p);
    }
    if (kr_truthy(kr_eq(op, kr_str("MINUSEQ")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(indent(depth), cname), kr_str(" = kr_sub(")), cname), kr_str(", ")), ecode), kr_str(");\n,")), p);
    }
    if (kr_truthy(kr_eq(op, kr_str("STAREQ")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(indent(depth), cname), kr_str(" = kr_mul(")), cname), kr_str(", ")), ecode), kr_str(");\n,")), p);
    }
    if (kr_truthy(kr_eq(op, kr_str("SLASHEQ")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(indent(depth), cname), kr_str(" = kr_div(")), cname), kr_str(", ")), ecode), kr_str(");\n,")), p);
    }
    if (kr_truthy(kr_eq(op, kr_str("MODEQ")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(indent(depth), cname), kr_str(" = kr_mod(")), cname), kr_str(", ")), ecode), kr_str(");\n,")), p);
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(indent(depth), cname), kr_str(" = ")), ecode), kr_str(";\n,")), p);
}

char* compileFor(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* varName = tokVal(tokAt(tokens, pos));
    char* p = kr_plus(pos, kr_str("2"));
    char* ep = compileExpr(tokens, p, ntoks);
    char* collection = pairVal(ep);
    p = pairPos(ep);
    char* bp = compileBlock(tokens, p, ntoks, depth, inFunc);
    char* bcode = pairVal(bp);
    p = pairPos(bp);
    char* cvar = cIdent(varName);
    char* out = kr_plus(indent(depth), kr_str("{\n"));
    out = kr_plus(kr_plus(kr_plus(kr_plus(out, indent(kr_plus(depth, kr_str("1")))), kr_str("char* _for_col = ")), collection), kr_str(";\n"));
    out = kr_plus(kr_plus(out, indent(kr_plus(depth, kr_str("1")))), kr_str("int _for_cnt = kr_listlen(_for_col);\n"));
    out = kr_plus(kr_plus(out, indent(kr_plus(depth, kr_str("1")))), kr_str("for (int _for_i = 0; _for_i < _for_cnt; _for_i++) {\n"));
    out = kr_plus(kr_plus(kr_plus(kr_plus(out, indent(kr_plus(depth, kr_str("2")))), kr_str("char* ")), cvar), kr_str(" = kr_split(_for_col, kr_itoa(_for_i));\n"));
    out = kr_plus(out, bcode);
    out = kr_plus(kr_plus(out, indent(kr_plus(depth, kr_str("1")))), kr_str("}\n"));
    out = kr_plus(kr_plus(out, indent(depth)), kr_str("}\n"));
    return kr_plus(kr_plus(out, kr_str(",")), p);
}

char* compileMatch(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* ep = compileExpr(tokens, pos, ntoks);
    char* mexpr = pairVal(ep);
    char* p = pairPos(ep);
    p = kr_plus(p, kr_str("1"));
    char* out = kr_plus(indent(depth), kr_str("{\n"));
    out = kr_plus(kr_plus(kr_plus(kr_plus(out, indent(kr_plus(depth, kr_str("1")))), kr_str("char* _match_val = ")), mexpr), kr_str(";\n"));
    char* first = kr_str("1");
    while (kr_truthy(kr_neq(tokAt(tokens, p), kr_str("RBRACE")))) {
        char* ct = tokAt(tokens, p);
        if (kr_truthy(kr_eq(ct, kr_str("KW:else")))) {
            p = kr_plus(p, kr_str("1"));
            char* bp = compileBlock(tokens, p, ntoks, kr_plus(depth, kr_str("1")), inFunc);
            char* bcode = pairVal(bp);
            p = pairPos(bp);
            if (kr_truthy(kr_eq(first, kr_str("1")))) {
                out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, indent(kr_plus(depth, kr_str("1")))), kr_str("{\n")), bcode), indent(kr_plus(depth, kr_str("1")))), kr_str("}\n"));
            } else {
                out = kr_plus(kr_plus(kr_plus(kr_plus(out, kr_str(" else {\n")), bcode), indent(kr_plus(depth, kr_str("1")))), kr_str("}\n"));
            }
        } else {
            char* vp = compileExpr(tokens, p, ntoks);
            char* vcode = pairVal(vp);
            p = pairPos(vp);
            char* bp = compileBlock(tokens, p, ntoks, kr_plus(depth, kr_str("1")), inFunc);
            char* bcode = pairVal(bp);
            p = pairPos(bp);
            if (kr_truthy(kr_eq(first, kr_str("1")))) {
                out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, indent(kr_plus(depth, kr_str("1")))), kr_str("if (strcmp(_match_val, ")), vcode), kr_str(") == 0) {\n")), bcode), indent(kr_plus(depth, kr_str("1")))), kr_str("}"));
                first = kr_str("0");
            } else {
                out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, kr_str(" else if (strcmp(_match_val, ")), vcode), kr_str(") == 0) {\n")), bcode), indent(kr_plus(depth, kr_str("1")))), kr_str("}"));
            }
        }
    }
    p = kr_plus(p, kr_str("1"));
    out = kr_plus(kr_plus(kr_plus(out, kr_str("\n")), indent(depth)), kr_str("}\n"));
    return kr_plus(kr_plus(out, kr_str(",")), p);
}

char* compileDoWhile(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* bp = compileBlock(tokens, pos, ntoks, depth, inFunc);
    char* bcode = pairVal(bp);
    char* p = pairPos(bp);
    p = kr_plus(p, kr_str("1"));
    char* cp = compileExpr(tokens, p, ntoks);
    char* cond = pairVal(cp);
    p = pairPos(cp);
    if (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("SEMI")))) {
        p = kr_plus(p, kr_str("1"));
    }
    char* out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(indent(depth), kr_str("do {\n")), bcode), indent(depth)), kr_str("} while (kr_truthy(")), cond), kr_str("));\n"));
    return kr_plus(kr_plus(out, kr_str(",")), p);
}

char* compileExprStmt(char* tokens, char* pos, char* ntoks, char* depth) {
    char* ep = compileExpr(tokens, pos, ntoks);
    char* ecode = pairVal(ep);
    char* p = pairPos(ep);
    if (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("SEMI")))) {
        p = kr_plus(p, kr_str("1"));
    }
    return kr_plus(kr_plus(kr_plus(indent(depth), ecode), kr_str(";\n,")), p);
}

char* compileBlock(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* p = kr_plus(pos, kr_str("1"));
    char* code = kr_str("");
    while (kr_truthy(kr_neq(tokAt(tokens, p), kr_str("RBRACE")))) {
        if (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("SEMI")))) {
            p = kr_plus(p, kr_str("1"));
        } else {
            char* sp = compileStmt(tokens, p, ntoks, kr_plus(depth, kr_str("1")), inFunc);
            char* sCode = pairVal(sp);
            p = pairPos(sp);
            code = kr_plus(code, sCode);
        }
    }
    p = kr_plus(p, kr_str("1"));
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* compileFunc(char* tokens, char* pos, char* ntoks) {
    char* nameTok = tokAt(tokens, kr_plus(pos, kr_str("1")));
    char* fname = tokVal(nameTok);
    char* p = kr_plus(pos, kr_str("3"));
    char* params = kr_str("");
    char* pc = kr_str("0");
    while (kr_truthy(kr_neq(tokAt(tokens, p), kr_str("RPAREN")))) {
        char* pt = tokAt(tokens, p);
        if (kr_truthy(kr_eq(tokType(pt), kr_str("ID")))) {
            if (kr_truthy(kr_gt(pc, kr_str("0")))) {
                params = kr_plus(kr_plus(params, kr_str(", char* ")), cIdent(tokVal(pt)));
            } else {
                params = kr_plus(kr_str("char* "), cIdent(tokVal(pt)));
            }
            pc = kr_plus(pc, kr_str("1"));
        }
        p = kr_plus(p, kr_str("1"));
    }
    p = kr_plus(p, kr_str("1"));
    char* bp = compileBlock(tokens, p, ntoks, kr_str("0"), kr_str("1"));
    char* bcode = pairVal(bp);
    p = pairPos(bp);
    char* out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("char* "), cIdent(fname)), kr_str("(")), params), kr_str(") {\n")), bcode), kr_str("}\n\n"));
    return kr_plus(kr_plus(out, kr_str(",")), p);
}

char* sbNew() {
    return kr_str("");
}

char* sbAppend(char* sb, char* s) {
    return kr_plus(sb, s);
}

char* sbToString(char* sb) {
    return sb;
}

char* cRuntime() {
    char* r = kr_sbnew();
    r = kr_sbappend(r, kr_str("#include <stdio.h>\n"));
    r = kr_sbappend(r, kr_str("#include <stdlib.h>\n"));
    r = kr_sbappend(r, kr_str("#include <string.h>\n\n"));
    r = kr_sbappend(r, kr_str("static int _argc; static char** _argv;\n\n"));
    r = kr_sbappend(r, kr_str("typedef struct ABlock { struct ABlock* next; int cap; int used; } ABlock;\n"));
    r = kr_sbappend(r, kr_str("static ABlock* _arena = 0;\n"));
    r = kr_sbappend(r, kr_str("static char* _alloc(int n) {\n"));
    r = kr_sbappend(r, kr_str("    n = (n + 7) & ~7;\n"));
    r = kr_sbappend(r, kr_str("    if (!_arena || _arena->used + n > _arena->cap) {\n"));
    r = kr_sbappend(r, kr_str("        int cap = 256*1024*1024;\n"));
    r = kr_sbappend(r, kr_str("        if (n > cap) cap = n;\n"));
    r = kr_sbappend(r, kr_str("        ABlock* b = (ABlock*)malloc(sizeof(ABlock) + cap);\n"));
    r = kr_sbappend(r, kr_str("        if (!b) { fprintf(stderr, \"out of memory\\n\"); exit(1); }\n"));
    r = kr_sbappend(r, kr_str("        b->cap = cap; b->used = 0; b->next = _arena; _arena = b;\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    char* p = (char*)(_arena + 1) + _arena->used;\n"));
    r = kr_sbappend(r, kr_str("    _arena->used += n;\n"));
    r = kr_sbappend(r, kr_str("    return p;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char _K_EMPTY[] = \"\";\n"));
    r = kr_sbappend(r, kr_str("static char _K_ZERO[] = \"0\";\n"));
    r = kr_sbappend(r, kr_str("static char _K_ONE[] = \"1\";\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_str(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    if (!s[0]) return _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("    if (s[0] == '0' && !s[1]) return _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("    if (s[0] == '1' && !s[1]) return _K_ONE;\n"));
    r = kr_sbappend(r, kr_str("    int n = (int)strlen(s) + 1;\n"));
    r = kr_sbappend(r, kr_str("    char* p = _alloc(n);\n"));
    r = kr_sbappend(r, kr_str("    memcpy(p, s, n);\n"));
    r = kr_sbappend(r, kr_str("    return p;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_cat(const char* a, const char* b) {\n"));
    r = kr_sbappend(r, kr_str("    int la = (int)strlen(a), lb = (int)strlen(b);\n"));
    r = kr_sbappend(r, kr_str("    char* p = _alloc(la + lb + 1);\n"));
    r = kr_sbappend(r, kr_str("    memcpy(p, a, la);\n"));
    r = kr_sbappend(r, kr_str("    memcpy(p + la, b, lb + 1);\n"));
    r = kr_sbappend(r, kr_str("    return p;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static int kr_isnum(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    if (!*s) return 0;\n"));
    r = kr_sbappend(r, kr_str("    const char* p = s;\n"));
    r = kr_sbappend(r, kr_str("    if (*p == '-') p++;\n"));
    r = kr_sbappend(r, kr_str("    if (!*p) return 0;\n"));
    r = kr_sbappend(r, kr_str("    while (*p) { if (*p < '0' || *p > '9') return 0; p++; }\n"));
    r = kr_sbappend(r, kr_str("    return 1;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_itoa(int v) {\n"));
    r = kr_sbappend(r, kr_str("    if (v == 0) return _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("    if (v == 1) return _K_ONE;\n"));
    r = kr_sbappend(r, kr_str("    char buf[32];\n"));
    r = kr_sbappend(r, kr_str("    snprintf(buf, sizeof(buf), \"%d\", v);\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(buf);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static int kr_atoi(const char* s) { return atoi(s); }\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_plus(const char* a, const char* b) {\n"));
    r = kr_sbappend(r, kr_str("    if (kr_isnum(a) && kr_isnum(b))\n"));
    r = kr_sbappend(r, kr_str("        return kr_itoa(atoi(a) + atoi(b));\n"));
    r = kr_sbappend(r, kr_str("    return kr_cat(a, b);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_sub(const char* a, const char* b) { return kr_itoa(atoi(a) - atoi(b)); }\n"));
    r = kr_sbappend(r, kr_str("static char* kr_mul(const char* a, const char* b) { return kr_itoa(atoi(a) * atoi(b)); }\n"));
    r = kr_sbappend(r, kr_str("static char* kr_div(const char* a, const char* b) { return kr_itoa(atoi(a) / atoi(b)); }\n"));
    r = kr_sbappend(r, kr_str("static char* kr_mod(const char* a, const char* b) { return kr_itoa(atoi(a) % atoi(b)); }\n"));
    r = kr_sbappend(r, kr_str("static char* kr_neg(const char* a) { return kr_itoa(-atoi(a)); }\n"));
    r = kr_sbappend(r, kr_str("static char* kr_not(const char* a) { return atoi(a) ? _K_ZERO : _K_ONE; }\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_eq(const char* a, const char* b) {\n"));
    r = kr_sbappend(r, kr_str("    return strcmp(a, b) == 0 ? _K_ONE : _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_neq(const char* a, const char* b) {\n"));
    r = kr_sbappend(r, kr_str("    return strcmp(a, b) != 0 ? _K_ONE : _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_lt(const char* a, const char* b) {\n"));
    r = kr_sbappend(r, kr_str("    if (kr_isnum(a) && kr_isnum(b)) return atoi(a) < atoi(b) ? _K_ONE : _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("    return strcmp(a, b) < 0 ? _K_ONE : _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_gt(const char* a, const char* b) {\n"));
    r = kr_sbappend(r, kr_str("    if (kr_isnum(a) && kr_isnum(b)) return atoi(a) > atoi(b) ? _K_ONE : _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("    return strcmp(a, b) > 0 ? _K_ONE : _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_lte(const char* a, const char* b) {\n"));
    r = kr_sbappend(r, kr_str("    return kr_gt(a, b) == _K_ZERO ? _K_ONE : _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_gte(const char* a, const char* b) {\n"));
    r = kr_sbappend(r, kr_str("    return kr_lt(a, b) == _K_ZERO ? _K_ONE : _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static int kr_truthy(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    if (!s || !*s) return 0;\n"));
    r = kr_sbappend(r, kr_str("    if (strcmp(s, \"0\") == 0) return 0;\n"));
    r = kr_sbappend(r, kr_str("    return 1;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_print(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    printf(\"%s\\n\", s);\n"));
    r = kr_sbappend(r, kr_str("    return _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_len(const char* s) { return kr_itoa((int)strlen(s)); }\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_idx(const char* s, int i) {\n"));
    r = kr_sbappend(r, kr_str("    char buf[2] = {s[i], 0};\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(buf);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_split(const char* s, const char* idxs) {\n"));
    r = kr_sbappend(r, kr_str("    int idx = atoi(idxs);\n"));
    r = kr_sbappend(r, kr_str("    int count = 0;\n"));
    r = kr_sbappend(r, kr_str("    const char* start = s;\n"));
    r = kr_sbappend(r, kr_str("    const char* p = s;\n"));
    r = kr_sbappend(r, kr_str("    while (*p) {\n"));
    r = kr_sbappend(r, kr_str("        if (*p == ',') {\n"));
    r = kr_sbappend(r, kr_str("            if (count == idx) {\n"));
    r = kr_sbappend(r, kr_str("                int len = (int)(p - start);\n"));
    r = kr_sbappend(r, kr_str("                char* r = _alloc(len + 1);\n"));
    r = kr_sbappend(r, kr_str("                memcpy(r, start, len);\n"));
    r = kr_sbappend(r, kr_str("                r[len] = 0;\n"));
    r = kr_sbappend(r, kr_str("                return r;\n"));
    r = kr_sbappend(r, kr_str("            }\n"));
    r = kr_sbappend(r, kr_str("            count++;\n"));
    r = kr_sbappend(r, kr_str("            start = p + 1;\n"));
    r = kr_sbappend(r, kr_str("        }\n"));
    r = kr_sbappend(r, kr_str("        p++;\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    if (count == idx) return kr_str(start);\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(\"\");\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_startswith(const char* s, const char* prefix) {\n"));
    r = kr_sbappend(r, kr_str("    return strncmp(s, prefix, strlen(prefix)) == 0 ? _K_ONE : _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_substr(const char* s, const char* starts, const char* ends) {\n"));
    r = kr_sbappend(r, kr_str("    int st = atoi(starts), en = atoi(ends);\n"));
    r = kr_sbappend(r, kr_str("    int slen = (int)strlen(s);\n"));
    r = kr_sbappend(r, kr_str("    if (st >= slen) return kr_str(\"\");\n"));
    r = kr_sbappend(r, kr_str("    if (en > slen) en = slen;\n"));
    r = kr_sbappend(r, kr_str("    int n = en - st;\n"));
    r = kr_sbappend(r, kr_str("    if (n <= 0) return kr_str(\"\");\n"));
    r = kr_sbappend(r, kr_str("    char* r = _alloc(n + 1);\n"));
    r = kr_sbappend(r, kr_str("    memcpy(r, s + st, n);\n"));
    r = kr_sbappend(r, kr_str("    r[n] = 0;\n"));
    r = kr_sbappend(r, kr_str("    return r;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_toint(const char* s) { return kr_itoa(atoi(s)); }\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_readfile(const char* path) {\n"));
    r = kr_sbappend(r, kr_str("    FILE* f = fopen(path, \"rb\");\n"));
    r = kr_sbappend(r, kr_str("    if (!f) return kr_str(\"\");\n"));
    r = kr_sbappend(r, kr_str("    fseek(f, 0, SEEK_END);\n"));
    r = kr_sbappend(r, kr_str("    long sz = ftell(f);\n"));
    r = kr_sbappend(r, kr_str("    fseek(f, 0, SEEK_SET);\n"));
    r = kr_sbappend(r, kr_str("    char* buf = _alloc((int)sz + 1);\n"));
    r = kr_sbappend(r, kr_str("    fread(buf, 1, sz, f);\n"));
    r = kr_sbappend(r, kr_str("    buf[sz] = 0;\n"));
    r = kr_sbappend(r, kr_str("    fclose(f);\n"));
    r = kr_sbappend(r, kr_str("    return buf;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_arg(const char* idxs) {\n"));
    r = kr_sbappend(r, kr_str("    int idx = atoi(idxs) + 1;\n"));
    r = kr_sbappend(r, kr_str("    if (idx < _argc) return kr_str(_argv[idx]);\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(\"\");\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_argcount() {\n"));
    r = kr_sbappend(r, kr_str("    return kr_itoa(_argc - 1);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_getline(const char* s, const char* idxs) {\n"));
    r = kr_sbappend(r, kr_str("    int idx = atoi(idxs);\n"));
    r = kr_sbappend(r, kr_str("    int cur = 0;\n"));
    r = kr_sbappend(r, kr_str("    const char* start = s;\n"));
    r = kr_sbappend(r, kr_str("    const char* p = s;\n"));
    r = kr_sbappend(r, kr_str("    while (*p) {\n"));
    r = kr_sbappend(r, kr_str("        if (*p == '\\n') {\n"));
    r = kr_sbappend(r, kr_str("            if (cur == idx) {\n"));
    r = kr_sbappend(r, kr_str("                int len = (int)(p - start);\n"));
    r = kr_sbappend(r, kr_str("                char* r = _alloc(len + 1);\n"));
    r = kr_sbappend(r, kr_str("                memcpy(r, start, len);\n"));
    r = kr_sbappend(r, kr_str("                r[len] = 0;\n"));
    r = kr_sbappend(r, kr_str("                return r;\n"));
    r = kr_sbappend(r, kr_str("            }\n"));
    r = kr_sbappend(r, kr_str("            cur++;\n"));
    r = kr_sbappend(r, kr_str("            start = p + 1;\n"));
    r = kr_sbappend(r, kr_str("        }\n"));
    r = kr_sbappend(r, kr_str("        p++;\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    if (cur == idx) return kr_str(start);\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(\"\");\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_linecount(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    if (!*s) return kr_str(\"0\");\n"));
    r = kr_sbappend(r, kr_str("    int count = 1;\n"));
    r = kr_sbappend(r, kr_str("    const char* p = s;\n"));
    r = kr_sbappend(r, kr_str("    while (*p) { if (*p == '\\n') count++; p++; }\n"));
    r = kr_sbappend(r, kr_str("    if (*(p - 1) == '\\n') count--;\n"));
    r = kr_sbappend(r, kr_str("    return kr_itoa(count);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_count(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    return kr_linecount(s);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_writefile(const char* path, const char* data) {\n"));
    r = kr_sbappend(r, kr_str("    FILE* f = fopen(path, \"wb\");\n"));
    r = kr_sbappend(r, kr_str("    if (!f) return _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("    fwrite(data, 1, strlen(data), f);\n"));
    r = kr_sbappend(r, kr_str("    fclose(f);\n"));
    r = kr_sbappend(r, kr_str("    return _K_ONE;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_input() {\n"));
    r = kr_sbappend(r, kr_str("    char buf[4096];\n"));
    r = kr_sbappend(r, kr_str("    if (!fgets(buf, sizeof(buf), stdin)) return _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("    int len = (int)strlen(buf);\n"));
    r = kr_sbappend(r, kr_str("    if (len > 0 && buf[len-1] == '\\n') buf[--len] = 0;\n"));
    r = kr_sbappend(r, kr_str("    if (len > 0 && buf[len-1] == '\\r') buf[--len] = 0;\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(buf);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_indexof(const char* s, const char* sub) {\n"));
    r = kr_sbappend(r, kr_str("    const char* p = strstr(s, sub);\n"));
    r = kr_sbappend(r, kr_str("    if (!p) return kr_itoa(-1);\n"));
    r = kr_sbappend(r, kr_str("    return kr_itoa((int)(p - s));\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_replace(const char* s, const char* old, const char* rep) {\n"));
    r = kr_sbappend(r, kr_str("    int slen = (int)strlen(s), olen = (int)strlen(old), rlen = (int)strlen(rep);\n"));
    r = kr_sbappend(r, kr_str("    if (olen == 0) return kr_str(s);\n"));
    r = kr_sbappend(r, kr_str("    int count = 0;\n"));
    r = kr_sbappend(r, kr_str("    const char* p = s;\n"));
    r = kr_sbappend(r, kr_str("    while ((p = strstr(p, old)) != 0) { count++; p += olen; }\n"));
    r = kr_sbappend(r, kr_str("    int nlen = slen + count * (rlen - olen);\n"));
    r = kr_sbappend(r, kr_str("    char* out = _alloc(nlen + 1);\n"));
    r = kr_sbappend(r, kr_str("    char* dst = out;\n"));
    r = kr_sbappend(r, kr_str("    p = s;\n"));
    r = kr_sbappend(r, kr_str("    while (*p) {\n"));
    r = kr_sbappend(r, kr_str("        if (strncmp(p, old, olen) == 0) {\n"));
    r = kr_sbappend(r, kr_str("            memcpy(dst, rep, rlen); dst += rlen; p += olen;\n"));
    r = kr_sbappend(r, kr_str("        } else { *dst++ = *p++; }\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    *dst = 0;\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_charat(const char* s, const char* idxs) {\n"));
    r = kr_sbappend(r, kr_str("    int i = atoi(idxs);\n"));
    r = kr_sbappend(r, kr_str("    int slen = (int)strlen(s);\n"));
    r = kr_sbappend(r, kr_str("    if (i < 0 || i >= slen) return _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("    char buf[2] = {s[i], 0};\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(buf);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_trim(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    while (*s == ' ' || *s == '\\t' || *s == '\\n' || *s == '\\r') s++;\n"));
    r = kr_sbappend(r, kr_str("    int len = (int)strlen(s);\n"));
    r = kr_sbappend(r, kr_str("    while (len > 0 && (s[len-1]==' '||s[len-1]=='\\t'||s[len-1]=='\\n'||s[len-1]=='\\r')) len--;\n"));
    r = kr_sbappend(r, kr_str("    char* r = _alloc(len + 1);\n"));
    r = kr_sbappend(r, kr_str("    memcpy(r, s, len);\n"));
    r = kr_sbappend(r, kr_str("    r[len] = 0;\n"));
    r = kr_sbappend(r, kr_str("    return r;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_tolower(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    int len = (int)strlen(s);\n"));
    r = kr_sbappend(r, kr_str("    char* out = _alloc(len + 1);\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i <= len; i++)\n"));
    r = kr_sbappend(r, kr_str("        out[i] = (s[i] >= 'A' && s[i] <= 'Z') ? s[i] + 32 : s[i];\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_toupper(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    int len = (int)strlen(s);\n"));
    r = kr_sbappend(r, kr_str("    char* out = _alloc(len + 1);\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i <= len; i++)\n"));
    r = kr_sbappend(r, kr_str("        out[i] = (s[i] >= 'a' && s[i] <= 'z') ? s[i] - 32 : s[i];\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_contains(const char* s, const char* sub) {\n"));
    r = kr_sbappend(r, kr_str("    return strstr(s, sub) ? _K_ONE : _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_endswith(const char* s, const char* suffix) {\n"));
    r = kr_sbappend(r, kr_str("    int slen = (int)strlen(s), suflen = (int)strlen(suffix);\n"));
    r = kr_sbappend(r, kr_str("    if (suflen > slen) return _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("    return strcmp(s + slen - suflen, suffix) == 0 ? _K_ONE : _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_abs(const char* a) { int v = atoi(a); return kr_itoa(v < 0 ? -v : v); }\n"));
    r = kr_sbappend(r, kr_str("static char* kr_min(const char* a, const char* b) { return atoi(a) <= atoi(b) ? kr_str(a) : kr_str(b); }\n"));
    r = kr_sbappend(r, kr_str("static char* kr_max(const char* a, const char* b) { return atoi(a) >= atoi(b) ? kr_str(a) : kr_str(b); }\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_exit(const char* code) { exit(atoi(code)); return _K_EMPTY; }\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_type(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    if (kr_isnum(s)) return kr_str(\"number\");\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(\"string\");\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_append(const char* lst, const char* item) {\n"));
    r = kr_sbappend(r, kr_str("    if (!*lst) return kr_str(item);\n"));
    r = kr_sbappend(r, kr_str("    return kr_cat(kr_cat(lst, \",\"), item);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_join(const char* lst, const char* sep) {\n"));
    r = kr_sbappend(r, kr_str("    int llen = (int)strlen(lst), slen = (int)strlen(sep);\n"));
    r = kr_sbappend(r, kr_str("    int rlen = 0;\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < llen; i++) {\n"));
    r = kr_sbappend(r, kr_str("        if (lst[i] == ',') rlen += slen; else rlen++;\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    char* out = _alloc(rlen + 1);\n"));
    r = kr_sbappend(r, kr_str("    int j = 0;\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < llen; i++) {\n"));
    r = kr_sbappend(r, kr_str("        if (lst[i] == ',') { memcpy(out+j, sep, slen); j += slen; }\n"));
    r = kr_sbappend(r, kr_str("        else { out[j++] = lst[i]; }\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    out[j] = 0;\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_reverse(const char* lst) {\n"));
    r = kr_sbappend(r, kr_str("    int cnt = 0;\n"));
    r = kr_sbappend(r, kr_str("    const char* p = lst;\n"));
    r = kr_sbappend(r, kr_str("    while (*p) { if (*p == ',') cnt++; p++; }\n"));
    r = kr_sbappend(r, kr_str("    cnt++;\n"));
    r = kr_sbappend(r, kr_str("    char* out = _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("    for (int i = cnt - 1; i >= 0; i--) {\n"));
    r = kr_sbappend(r, kr_str("        char* item = kr_split(lst, kr_itoa(i));\n"));
    r = kr_sbappend(r, kr_str("        if (i == cnt - 1) out = item;\n"));
    r = kr_sbappend(r, kr_str("        else out = kr_cat(kr_cat(out, \",\"), item);\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static int _kr_cmp(const void* a, const void* b) {\n"));
    r = kr_sbappend(r, kr_str("    const char* sa = *(const char**)a;\n"));
    r = kr_sbappend(r, kr_str("    const char* sb = *(const char**)b;\n"));
    r = kr_sbappend(r, kr_str("    if (kr_isnum(sa) && kr_isnum(sb)) return atoi(sa) - atoi(sb);\n"));
    r = kr_sbappend(r, kr_str("    return strcmp(sa, sb);\n"));
    r = kr_sbappend(r, kr_str("}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_sort(const char* lst) {\n"));
    r = kr_sbappend(r, kr_str("    if (!*lst) return _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("    int cnt = 1;\n"));
    r = kr_sbappend(r, kr_str("    const char* p = lst;\n"));
    r = kr_sbappend(r, kr_str("    while (*p) { if (*p == ',') cnt++; p++; }\n"));
    r = kr_sbappend(r, kr_str("    char** arr = (char**)_alloc(cnt * sizeof(char*));\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < cnt; i++) arr[i] = kr_split(lst, kr_itoa(i));\n"));
    r = kr_sbappend(r, kr_str("    qsort(arr, cnt, sizeof(char*), _kr_cmp);\n"));
    r = kr_sbappend(r, kr_str("    char* out = arr[0];\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 1; i < cnt; i++) out = kr_cat(kr_cat(out, \",\"), arr[i]);\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_keys(const char* map) {\n"));
    r = kr_sbappend(r, kr_str("    if (!*map) return _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("    int cnt = 1;\n"));
    r = kr_sbappend(r, kr_str("    const char* p = map;\n"));
    r = kr_sbappend(r, kr_str("    while (*p) { if (*p == ',') cnt++; p++; }\n"));
    r = kr_sbappend(r, kr_str("    char* out = _K_EMPTY; int first = 1;\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < cnt; i += 2) {\n"));
    r = kr_sbappend(r, kr_str("        char* k = kr_split(map, kr_itoa(i));\n"));
    r = kr_sbappend(r, kr_str("        if (first) { out = k; first = 0; }\n"));
    r = kr_sbappend(r, kr_str("        else out = kr_cat(kr_cat(out, \",\"), k);\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_values(const char* map) {\n"));
    r = kr_sbappend(r, kr_str("    if (!*map) return _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("    int cnt = 1;\n"));
    r = kr_sbappend(r, kr_str("    const char* p = map;\n"));
    r = kr_sbappend(r, kr_str("    while (*p) { if (*p == ',') cnt++; p++; }\n"));
    r = kr_sbappend(r, kr_str("    char* out = _K_EMPTY; int first = 1;\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 1; i < cnt; i += 2) {\n"));
    r = kr_sbappend(r, kr_str("        char* v = kr_split(map, kr_itoa(i));\n"));
    r = kr_sbappend(r, kr_str("        if (first) { out = v; first = 0; }\n"));
    r = kr_sbappend(r, kr_str("        else out = kr_cat(kr_cat(out, \",\"), v);\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_haskey(const char* map, const char* key) {\n"));
    r = kr_sbappend(r, kr_str("    if (!*map) return _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("    int cnt = 1;\n"));
    r = kr_sbappend(r, kr_str("    const char* p = map;\n"));
    r = kr_sbappend(r, kr_str("    while (*p) { if (*p == ',') cnt++; p++; }\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < cnt; i += 2) {\n"));
    r = kr_sbappend(r, kr_str("        if (strcmp(kr_split(map, kr_itoa(i)), key) == 0) return _K_ONE;\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    return _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_remove(const char* lst, const char* item) {\n"));
    r = kr_sbappend(r, kr_str("    if (!*lst) return _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("    int cnt = 1;\n"));
    r = kr_sbappend(r, kr_str("    const char* p = lst;\n"));
    r = kr_sbappend(r, kr_str("    while (*p) { if (*p == ',') cnt++; p++; }\n"));
    r = kr_sbappend(r, kr_str("    char* out = _K_EMPTY; int first = 1;\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < cnt; i++) {\n"));
    r = kr_sbappend(r, kr_str("        char* el = kr_split(lst, kr_itoa(i));\n"));
    r = kr_sbappend(r, kr_str("        if (strcmp(el, item) != 0) {\n"));
    r = kr_sbappend(r, kr_str("            if (first) { out = el; first = 0; }\n"));
    r = kr_sbappend(r, kr_str("            else out = kr_cat(kr_cat(out, \",\"), el);\n"));
    r = kr_sbappend(r, kr_str("        }\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_repeat(const char* s, const char* ns) {\n"));
    r = kr_sbappend(r, kr_str("    int n = atoi(ns);\n"));
    r = kr_sbappend(r, kr_str("    if (n <= 0) return _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("    int slen = (int)strlen(s);\n"));
    r = kr_sbappend(r, kr_str("    char* out = _alloc(slen * n + 1);\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < n; i++) memcpy(out + i * slen, s, slen);\n"));
    r = kr_sbappend(r, kr_str("    out[slen * n] = 0;\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_format(const char* fmt, const char* arg) {\n"));
    r = kr_sbappend(r, kr_str("    char buf[4096];\n"));
    r = kr_sbappend(r, kr_str("    const char* p = strstr(fmt, \"{}\");\n"));
    r = kr_sbappend(r, kr_str("    if (!p) return kr_str(fmt);\n"));
    r = kr_sbappend(r, kr_str("    int pre = (int)(p - fmt);\n"));
    r = kr_sbappend(r, kr_str("    int alen = (int)strlen(arg);\n"));
    r = kr_sbappend(r, kr_str("    int postlen = (int)strlen(p + 2);\n"));
    r = kr_sbappend(r, kr_str("    if (pre + alen + postlen >= 4096) return kr_str(fmt);\n"));
    r = kr_sbappend(r, kr_str("    memcpy(buf, fmt, pre);\n"));
    r = kr_sbappend(r, kr_str("    memcpy(buf + pre, arg, alen);\n"));
    r = kr_sbappend(r, kr_str("    memcpy(buf + pre + alen, p + 2, postlen + 1);\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(buf);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_parseint(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    const char* p = s;\n"));
    r = kr_sbappend(r, kr_str("    while (*p == ' ' || *p == '\\t') p++;\n"));
    r = kr_sbappend(r, kr_str("    if (!*p) return _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("    return kr_itoa(atoi(p));\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_tostr(const char* s) { return kr_str(s); }\n\n"));
    r = kr_sbappend(r, kr_str("static int kr_listlen(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    if (!*s) return 0;\n"));
    r = kr_sbappend(r, kr_str("    int cnt = 1;\n"));
    r = kr_sbappend(r, kr_str("    while (*s) { if (*s == ',') cnt++; s++; }\n"));
    r = kr_sbappend(r, kr_str("    return cnt;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_range(const char* starts, const char* ends) {\n"));
    r = kr_sbappend(r, kr_str("    int s = atoi(starts), e = atoi(ends);\n"));
    r = kr_sbappend(r, kr_str("    if (s >= e) return _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("    char* out = kr_itoa(s);\n"));
    r = kr_sbappend(r, kr_str("    for (int i = s + 1; i < e; i++) out = kr_cat(kr_cat(out, \",\"), kr_itoa(i));\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_pow(const char* bs, const char* es) {\n"));
    r = kr_sbappend(r, kr_str("    int b = atoi(bs), e = atoi(es), r = 1;\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < e; i++) r *= b;\n"));
    r = kr_sbappend(r, kr_str("    return kr_itoa(r);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_sqrt(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    int v = atoi(s);\n"));
    r = kr_sbappend(r, kr_str("    if (v <= 0) return _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("    int r = 0;\n"));
    r = kr_sbappend(r, kr_str("    while ((r + 1) * (r + 1) <= v) r++;\n"));
    r = kr_sbappend(r, kr_str("    return kr_itoa(r);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_sign(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    int v = atoi(s);\n"));
    r = kr_sbappend(r, kr_str("    if (v > 0) return _K_ONE;\n"));
    r = kr_sbappend(r, kr_str("    if (v < 0) return kr_str(\"-1\");\n"));
    r = kr_sbappend(r, kr_str("    return _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_clamp(const char* vs, const char* los, const char* his) {\n"));
    r = kr_sbappend(r, kr_str("    int v = atoi(vs), lo = atoi(los), hi = atoi(his);\n"));
    r = kr_sbappend(r, kr_str("    if (v < lo) return kr_str(los);\n"));
    r = kr_sbappend(r, kr_str("    if (v > hi) return kr_str(his);\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(vs);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_padleft(const char* s, const char* ws, const char* pad) {\n"));
    r = kr_sbappend(r, kr_str("    int w = atoi(ws), slen = (int)strlen(s), plen = (int)strlen(pad);\n"));
    r = kr_sbappend(r, kr_str("    if (slen >= w || plen == 0) return kr_str(s);\n"));
    r = kr_sbappend(r, kr_str("    int need = w - slen;\n"));
    r = kr_sbappend(r, kr_str("    char* out = _alloc(w + 1);\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < need; i++) out[i] = pad[i % plen];\n"));
    r = kr_sbappend(r, kr_str("    memcpy(out + need, s, slen + 1);\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_padright(const char* s, const char* ws, const char* pad) {\n"));
    r = kr_sbappend(r, kr_str("    int w = atoi(ws), slen = (int)strlen(s), plen = (int)strlen(pad);\n"));
    r = kr_sbappend(r, kr_str("    if (slen >= w || plen == 0) return kr_str(s);\n"));
    r = kr_sbappend(r, kr_str("    int need = w - slen;\n"));
    r = kr_sbappend(r, kr_str("    char* out = _alloc(w + 1);\n"));
    r = kr_sbappend(r, kr_str("    memcpy(out, s, slen);\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < need; i++) out[slen + i] = pad[i % plen];\n"));
    r = kr_sbappend(r, kr_str("    out[w] = 0;\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_charcode(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    if (!*s) return _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("    return kr_itoa((unsigned char)s[0]);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_fromcharcode(const char* ns) {\n"));
    r = kr_sbappend(r, kr_str("    char buf[2] = {(char)atoi(ns), 0};\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(buf);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_slice(const char* lst, const char* starts, const char* ends) {\n"));
    r = kr_sbappend(r, kr_str("    int cnt = kr_listlen(lst);\n"));
    r = kr_sbappend(r, kr_str("    int s = atoi(starts), e = atoi(ends);\n"));
    r = kr_sbappend(r, kr_str("    if (s < 0) s = cnt + s;\n"));
    r = kr_sbappend(r, kr_str("    if (e < 0) e = cnt + e;\n"));
    r = kr_sbappend(r, kr_str("    if (s < 0) s = 0;\n"));
    r = kr_sbappend(r, kr_str("    if (e > cnt) e = cnt;\n"));
    r = kr_sbappend(r, kr_str("    if (s >= e) return _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("    char* out = kr_split(lst, kr_itoa(s));\n"));
    r = kr_sbappend(r, kr_str("    for (int i = s + 1; i < e; i++)\n"));
    r = kr_sbappend(r, kr_str("        out = kr_cat(kr_cat(out, \",\"), kr_split(lst, kr_itoa(i)));\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_length(const char* lst) {\n"));
    r = kr_sbappend(r, kr_str("    return kr_itoa(kr_listlen(lst));\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_unique(const char* lst) {\n"));
    r = kr_sbappend(r, kr_str("    if (!*lst) return _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("    int cnt = kr_listlen(lst);\n"));
    r = kr_sbappend(r, kr_str("    char* out = _K_EMPTY; int oc = 0;\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < cnt; i++) {\n"));
    r = kr_sbappend(r, kr_str("        char* item = kr_split(lst, kr_itoa(i));\n"));
    r = kr_sbappend(r, kr_str("        int dup = 0;\n"));
    r = kr_sbappend(r, kr_str("        for (int j = 0; j < oc; j++) {\n"));
    r = kr_sbappend(r, kr_str("            if (strcmp(kr_split(out, kr_itoa(j)), item) == 0) { dup = 1; break; }\n"));
    r = kr_sbappend(r, kr_str("        }\n"));
    r = kr_sbappend(r, kr_str("        if (!dup) {\n"));
    r = kr_sbappend(r, kr_str("            if (oc == 0) out = item; else out = kr_cat(kr_cat(out, \",\"), item);\n"));
    r = kr_sbappend(r, kr_str("            oc++;\n"));
    r = kr_sbappend(r, kr_str("        }\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_printerr(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    fprintf(stderr, \"%s\\n\", s);\n"));
    r = kr_sbappend(r, kr_str("    return _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_readline(const char* prompt) {\n"));
    r = kr_sbappend(r, kr_str("    if (*prompt) printf(\"%s\", prompt);\n"));
    r = kr_sbappend(r, kr_str("    fflush(stdout);\n"));
    r = kr_sbappend(r, kr_str("    char buf[4096];\n"));
    r = kr_sbappend(r, kr_str("    if (!fgets(buf, sizeof(buf), stdin)) return _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("    int len = (int)strlen(buf);\n"));
    r = kr_sbappend(r, kr_str("    if (len > 0 && buf[len-1] == '\\n') buf[--len] = 0;\n"));
    r = kr_sbappend(r, kr_str("    if (len > 0 && buf[len-1] == '\\r') buf[--len] = 0;\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(buf);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_assert(const char* cond, const char* msg) {\n"));
    r = kr_sbappend(r, kr_str("    if (!kr_truthy(cond)) {\n"));
    r = kr_sbappend(r, kr_str("        fprintf(stderr, \"ASSERTION FAILED: %s\\n\", msg);\n"));
    r = kr_sbappend(r, kr_str("        exit(1);\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    return _K_ONE;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_splitby(const char* s, const char* delim) {\n"));
    r = kr_sbappend(r, kr_str("    int slen = (int)strlen(s), dlen = (int)strlen(delim);\n"));
    r = kr_sbappend(r, kr_str("    if (dlen == 0 || slen == 0) return kr_str(s);\n"));
    r = kr_sbappend(r, kr_str("    char* out = _K_EMPTY; int first = 1;\n"));
    r = kr_sbappend(r, kr_str("    const char* p = s;\n"));
    r = kr_sbappend(r, kr_str("    while (*p) {\n"));
    r = kr_sbappend(r, kr_str("        const char* f = strstr(p, delim);\n"));
    r = kr_sbappend(r, kr_str("        if (!f) { \n"));
    r = kr_sbappend(r, kr_str("            if (first) out = kr_str(p); else out = kr_cat(kr_cat(out, \",\"), kr_str(p));\n"));
    r = kr_sbappend(r, kr_str("            break;\n"));
    r = kr_sbappend(r, kr_str("        }\n"));
    r = kr_sbappend(r, kr_str("        int n = (int)(f - p);\n"));
    r = kr_sbappend(r, kr_str("        char* chunk = _alloc(n + 1);\n"));
    r = kr_sbappend(r, kr_str("        memcpy(chunk, p, n); chunk[n] = 0;\n"));
    r = kr_sbappend(r, kr_str("        if (first) { out = chunk; first = 0; }\n"));
    r = kr_sbappend(r, kr_str("        else out = kr_cat(kr_cat(out, \",\"), chunk);\n"));
    r = kr_sbappend(r, kr_str("        p = f + dlen;\n"));
    r = kr_sbappend(r, kr_str("        if (!*p) { out = kr_cat(kr_cat(out, \",\"), _K_EMPTY); break; }\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_listindexof(const char* lst, const char* item) {\n"));
    r = kr_sbappend(r, kr_str("    if (!*lst) return kr_itoa(-1);\n"));
    r = kr_sbappend(r, kr_str("    int cnt = kr_listlen(lst);\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < cnt; i++) {\n"));
    r = kr_sbappend(r, kr_str("        if (strcmp(kr_split(lst, kr_itoa(i)), item) == 0) return kr_itoa(i);\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    return kr_itoa(-1);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_insertat(const char* lst, const char* idxs, const char* item) {\n"));
    r = kr_sbappend(r, kr_str("    int idx = atoi(idxs);\n"));
    r = kr_sbappend(r, kr_str("    int cnt = kr_listlen(lst);\n"));
    r = kr_sbappend(r, kr_str("    if (!*lst && idx == 0) return kr_str(item);\n"));
    r = kr_sbappend(r, kr_str("    if (idx < 0) idx = 0;\n"));
    r = kr_sbappend(r, kr_str("    if (idx >= cnt) return kr_cat(kr_cat(lst, \",\"), item);\n"));
    r = kr_sbappend(r, kr_str("    char* out = _K_EMPTY; int first = 1;\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < cnt; i++) {\n"));
    r = kr_sbappend(r, kr_str("        if (i == idx) {\n"));
    r = kr_sbappend(r, kr_str("            if (first) { out = kr_str(item); first = 0; }\n"));
    r = kr_sbappend(r, kr_str("            else out = kr_cat(kr_cat(out, \",\"), item);\n"));
    r = kr_sbappend(r, kr_str("        }\n"));
    r = kr_sbappend(r, kr_str("        char* el = kr_split(lst, kr_itoa(i));\n"));
    r = kr_sbappend(r, kr_str("        if (first) { out = el; first = 0; }\n"));
    r = kr_sbappend(r, kr_str("        else out = kr_cat(kr_cat(out, \",\"), el);\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_removeat(const char* lst, const char* idxs) {\n"));
    r = kr_sbappend(r, kr_str("    int idx = atoi(idxs);\n"));
    r = kr_sbappend(r, kr_str("    int cnt = kr_listlen(lst);\n"));
    r = kr_sbappend(r, kr_str("    if (idx < 0 || idx >= cnt) return kr_str(lst);\n"));
    r = kr_sbappend(r, kr_str("    char* out = _K_EMPTY; int first = 1;\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < cnt; i++) {\n"));
    r = kr_sbappend(r, kr_str("        if (i == idx) continue;\n"));
    r = kr_sbappend(r, kr_str("        char* el = kr_split(lst, kr_itoa(i));\n"));
    r = kr_sbappend(r, kr_str("        if (first) { out = el; first = 0; }\n"));
    r = kr_sbappend(r, kr_str("        else out = kr_cat(kr_cat(out, \",\"), el);\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_replaceat(const char* lst, const char* idxs, const char* val) {\n"));
    r = kr_sbappend(r, kr_str("    int idx = atoi(idxs);\n"));
    r = kr_sbappend(r, kr_str("    int cnt = kr_listlen(lst);\n"));
    r = kr_sbappend(r, kr_str("    if (idx < 0 || idx >= cnt) return kr_str(lst);\n"));
    r = kr_sbappend(r, kr_str("    char* out = _K_EMPTY; int first = 1;\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < cnt; i++) {\n"));
    r = kr_sbappend(r, kr_str("        char* el = (i == idx) ? (char*)val : kr_split(lst, kr_itoa(i));\n"));
    r = kr_sbappend(r, kr_str("        if (first) { out = el; first = 0; }\n"));
    r = kr_sbappend(r, kr_str("        else out = kr_cat(kr_cat(out, \",\"), el);\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_fill(const char* ns, const char* val) {\n"));
    r = kr_sbappend(r, kr_str("    int n = atoi(ns);\n"));
    r = kr_sbappend(r, kr_str("    if (n <= 0) return _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("    char* out = kr_str(val);\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 1; i < n; i++) out = kr_cat(kr_cat(out, \",\"), val);\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_zip(const char* a, const char* b) {\n"));
    r = kr_sbappend(r, kr_str("    int ac = kr_listlen(a), bc = kr_listlen(b);\n"));
    r = kr_sbappend(r, kr_str("    int mc = ac < bc ? ac : bc;\n"));
    r = kr_sbappend(r, kr_str("    if (!*a || !*b) return _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("    char* out = _K_EMPTY; int first = 1;\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < mc; i++) {\n"));
    r = kr_sbappend(r, kr_str("        char* ai = kr_split(a, kr_itoa(i));\n"));
    r = kr_sbappend(r, kr_str("        char* bi = kr_split(b, kr_itoa(i));\n"));
    r = kr_sbappend(r, kr_str("        if (first) { out = kr_cat(kr_cat(ai, \",\"), bi); first = 0; }\n"));
    r = kr_sbappend(r, kr_str("        else { out = kr_cat(kr_cat(out, \",\"), kr_cat(kr_cat(ai, \",\"), bi)); }\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_every(const char* lst, const char* val) {\n"));
    r = kr_sbappend(r, kr_str("    if (!*lst) return _K_ONE;\n"));
    r = kr_sbappend(r, kr_str("    int cnt = kr_listlen(lst);\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < cnt; i++) {\n"));
    r = kr_sbappend(r, kr_str("        if (strcmp(kr_split(lst, kr_itoa(i)), val) != 0) return _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    return _K_ONE;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_some(const char* lst, const char* val) {\n"));
    r = kr_sbappend(r, kr_str("    if (!*lst) return _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("    int cnt = kr_listlen(lst);\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < cnt; i++) {\n"));
    r = kr_sbappend(r, kr_str("        if (strcmp(kr_split(lst, kr_itoa(i)), val) == 0) return _K_ONE;\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    return _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_countof(const char* lst, const char* item) {\n"));
    r = kr_sbappend(r, kr_str("    if (!*lst) return _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("    int cnt = kr_listlen(lst), c = 0;\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < cnt; i++) {\n"));
    r = kr_sbappend(r, kr_str("        if (strcmp(kr_split(lst, kr_itoa(i)), item) == 0) c++;\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    return kr_itoa(c);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_sumlist(const char* lst) {\n"));
    r = kr_sbappend(r, kr_str("    if (!*lst) return _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("    int cnt = kr_listlen(lst), s = 0;\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < cnt; i++) s += atoi(kr_split(lst, kr_itoa(i)));\n"));
    r = kr_sbappend(r, kr_str("    return kr_itoa(s);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_maxlist(const char* lst) {\n"));
    r = kr_sbappend(r, kr_str("    if (!*lst) return _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("    int cnt = kr_listlen(lst);\n"));
    r = kr_sbappend(r, kr_str("    int m = atoi(kr_split(lst, _K_ZERO));\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 1; i < cnt; i++) {\n"));
    r = kr_sbappend(r, kr_str("        int v = atoi(kr_split(lst, kr_itoa(i)));\n"));
    r = kr_sbappend(r, kr_str("        if (v > m) m = v;\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    return kr_itoa(m);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_minlist(const char* lst) {\n"));
    r = kr_sbappend(r, kr_str("    if (!*lst) return _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("    int cnt = kr_listlen(lst);\n"));
    r = kr_sbappend(r, kr_str("    int m = atoi(kr_split(lst, _K_ZERO));\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 1; i < cnt; i++) {\n"));
    r = kr_sbappend(r, kr_str("        int v = atoi(kr_split(lst, kr_itoa(i)));\n"));
    r = kr_sbappend(r, kr_str("        if (v < m) m = v;\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    return kr_itoa(m);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_hex(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    int v = atoi(s);\n"));
    r = kr_sbappend(r, kr_str("    char buf[32];\n"));
    r = kr_sbappend(r, kr_str("    snprintf(buf, sizeof(buf), \"%x\", v < 0 ? -v : v);\n"));
    r = kr_sbappend(r, kr_str("    if (v < 0) return kr_cat(\"-\", kr_str(buf));\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(buf);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_bin(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    int v = atoi(s);\n"));
    r = kr_sbappend(r, kr_str("    if (v == 0) return _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("    int neg = v < 0; if (neg) v = -v;\n"));
    r = kr_sbappend(r, kr_str("    char buf[64]; int i = 63; buf[i] = 0;\n"));
    r = kr_sbappend(r, kr_str("    while (v > 0) { buf[--i] = '0' + (v & 1); v >>= 1; }\n"));
    r = kr_sbappend(r, kr_str("    if (neg) return kr_cat(\"-\", kr_str(&buf[i]));\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(&buf[i]);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("typedef struct EnvEntry { char* name; char* value; struct EnvEntry* prev; } EnvEntry;\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_envnew() { return (char*)0; }\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_envset(char* envp, const char* name, const char* val) {\n"));
    r = kr_sbappend(r, kr_str("    EnvEntry* e = (EnvEntry*)_alloc(sizeof(EnvEntry));\n"));
    r = kr_sbappend(r, kr_str("    e->name = (char*)name;\n"));
    r = kr_sbappend(r, kr_str("    e->value = (char*)val;\n"));
    r = kr_sbappend(r, kr_str("    e->prev = (EnvEntry*)envp;\n"));
    r = kr_sbappend(r, kr_str("    return (char*)e;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_envget(char* envp, const char* name) {\n"));
    r = kr_sbappend(r, kr_str("    EnvEntry* e = (EnvEntry*)envp;\n"));
    r = kr_sbappend(r, kr_str("    while (e) {\n"));
    r = kr_sbappend(r, kr_str("        if (strcmp(e->name, name) == 0) return e->value;\n"));
    r = kr_sbappend(r, kr_str("        e = e->prev;\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    if (strcmp(name, \"__argOffset\") != 0)\n"));
    r = kr_sbappend(r, kr_str("        fprintf(stderr, \"ERROR: undefined variable: %s\\n\", name);\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(\"\");\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("typedef struct ResultStruct { char tag; char* val; char* env; int pos; } ResultStruct;\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_makeresult(const char* tag, const char* val, const char* env, const char* pos) {\n"));
    r = kr_sbappend(r, kr_str("    ResultStruct* r = (ResultStruct*)_alloc(sizeof(ResultStruct));\n"));
    r = kr_sbappend(r, kr_str("    r->tag = tag[0];\n"));
    r = kr_sbappend(r, kr_str("    r->val = (char*)val;\n"));
    r = kr_sbappend(r, kr_str("    r->env = (char*)env;\n"));
    r = kr_sbappend(r, kr_str("    r->pos = atoi(pos);\n"));
    r = kr_sbappend(r, kr_str("    return (char*)r;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_getresulttag(const char* r) {\n"));
    r = kr_sbappend(r, kr_str("    char buf[2] = {((ResultStruct*)r)->tag, 0};\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(buf);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_getresultval(const char* r) {\n"));
    r = kr_sbappend(r, kr_str("    return ((ResultStruct*)r)->val;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_getresultenv(const char* r) {\n"));
    r = kr_sbappend(r, kr_str("    return ((ResultStruct*)r)->env;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_getresultpos(const char* r) {\n"));
    r = kr_sbappend(r, kr_str("    return kr_itoa(((ResultStruct*)r)->pos);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_istruthy(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    if (!s || !*s || strcmp(s, \"0\") == 0 || strcmp(s, \"false\") == 0)\n"));
    r = kr_sbappend(r, kr_str("        return _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("    return _K_ONE;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("typedef struct { int cap; int len; } SBHdr;\n"));
    r = kr_sbappend(r, kr_str("#define MAX_SBS 4096\n"));
    r = kr_sbappend(r, kr_str("static SBHdr* _sb_table[MAX_SBS];\n"));
    r = kr_sbappend(r, kr_str("static int _sb_count = 0;\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_sbnew() {\n"));
    r = kr_sbappend(r, kr_str("    int initcap = 65536;\n"));
    r = kr_sbappend(r, kr_str("    SBHdr* h = (SBHdr*)malloc(sizeof(SBHdr) + initcap);\n"));
    r = kr_sbappend(r, kr_str("    h->cap = initcap;\n"));
    r = kr_sbappend(r, kr_str("    h->len = 0;\n"));
    r = kr_sbappend(r, kr_str("    ((char*)(h + 1))[0] = 0;\n"));
    r = kr_sbappend(r, kr_str("    _sb_table[_sb_count] = h;\n"));
    r = kr_sbappend(r, kr_str("    return kr_itoa(_sb_count++);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_sbappend(const char* handle, const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    int idx = atoi(handle);\n"));
    r = kr_sbappend(r, kr_str("    SBHdr* h = _sb_table[idx];\n"));
    r = kr_sbappend(r, kr_str("    int slen = (int)strlen(s);\n"));
    r = kr_sbappend(r, kr_str("    while (h->len + slen + 1 > h->cap) {\n"));
    r = kr_sbappend(r, kr_str("        int newcap = h->cap * 2;\n"));
    r = kr_sbappend(r, kr_str("        h = (SBHdr*)realloc(h, sizeof(SBHdr) + newcap);\n"));
    r = kr_sbappend(r, kr_str("        h->cap = newcap;\n"));
    r = kr_sbappend(r, kr_str("    }\n"));
    r = kr_sbappend(r, kr_str("    memcpy((char*)(h + 1) + h->len, s, slen);\n"));
    r = kr_sbappend(r, kr_str("    h->len += slen;\n"));
    r = kr_sbappend(r, kr_str("    ((char*)(h + 1))[h->len] = 0;\n"));
    r = kr_sbappend(r, kr_str("    _sb_table[idx] = h;\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(handle);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_sbtostring(const char* handle) {\n"));
    r = kr_sbappend(r, kr_str("    int idx = atoi(handle);\n"));
    r = kr_sbappend(r, kr_str("    SBHdr* h = _sb_table[idx];\n"));
    r = kr_sbappend(r, kr_str("    return (char*)(h + 1);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    return kr_sbtostring(r);
}

int main(int argc, char** argv) {
    _argc = argc; _argv = argv;
    char* file = kr_arg(kr_str("0"));
    char* source = kr_readfile(file);
    char* tokens = tokenize(source);
    char* ntoks = kr_linecount(tokens);
    char* ftable = scanFunctions(tokens, ntoks);
    char* sb = kr_sbnew();
    sb = kr_sbappend(sb, cRuntime());
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* tok = tokAt(tokens, i);
        if (kr_truthy(kr_eq(tok, kr_str("KW:func")))) {
            char* nameTok = tokAt(tokens, kr_plus(i, kr_str("1")));
            char* fname = tokVal(nameTok);
            char* info = funcLookup(ftable, fname);
            char* pc = funcParamCount(info);
            char* paramStr = funcParams(info);
            char* decl = kr_plus(kr_plus(kr_str("char* "), cIdent(fname)), kr_str("("));
            char* pi = kr_str("0");
            while (kr_truthy(kr_lt(pi, pc))) {
                if (kr_truthy(kr_gt(pi, kr_str("0")))) {
                    decl = kr_plus(decl, kr_str(", "));
                }
                decl = kr_plus(decl, kr_str("char*"));
                pi = kr_plus(pi, kr_str("1"));
            }
            decl = kr_plus(decl, kr_str(");\n"));
            sb = kr_sbappend(sb, decl);
        }
        i = kr_plus(i, kr_str("1"));
    }
    sb = kr_sbappend(sb, kr_str("\n"));
    i = kr_str("0");
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* tok = tokAt(tokens, i);
        if (kr_truthy(kr_eq(tok, kr_str("KW:func")))) {
            char* fp = compileFunc(tokens, i, ntoks);
            char* fcode = pairVal(fp);
            sb = kr_sbappend(sb, fcode);
            i = pairPos(fp);
        } else {
            i = kr_plus(i, kr_str("1"));
        }
    }
    char* entry = findEntry(tokens, ntoks);
    if (kr_truthy(kr_lt(entry, kr_str("0")))) {
        return 0;
    }
    sb = kr_sbappend(sb, kr_str("int main(int argc, char** argv) {\n"));
    sb = kr_sbappend(sb, kr_str("    _argc = argc; _argv = argv;\n"));
    char* bp = compileBlock(tokens, entry, ntoks, kr_str("0"), kr_str("0"));
    char* bcode = pairVal(bp);
    sb = kr_sbappend(sb, bcode);
    sb = kr_sbappend(sb, kr_str("    return 0;\n"));
    sb = kr_sbappend(sb, kr_str("}\n"));
    kr_print(kr_sbtostring(sb));
    return 0;
}

