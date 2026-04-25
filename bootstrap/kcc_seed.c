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
    return kr_linecount(s);
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
static char* kr_bufsetdwordat(char* buf,const char* off,const char* val){*(unsigned int*)(buf+atoi(off))=(unsigned int)atoll(val);return _K_EMPTY;}
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
char* irExpr(char*, char*, char*, char*);
char* irTernary(char*, char*, char*, char*);
char* irOr(char*, char*, char*, char*);
char* irAnd(char*, char*, char*, char*);
char* irEquality(char*, char*, char*, char*);
char* irRelational(char*, char*, char*, char*);
char* irAdditive(char*, char*, char*, char*);
char* irMultiplicative(char*, char*, char*, char*);
char* irUnary(char*, char*, char*, char*);
char* irPostfix(char*, char*, char*, char*);
char* irPrimary(char*, char*, char*, char*);
char* irInterpToIR(char*, char*);
char* irListLiteralIR(char*, char*, char*, char*);
char* irStructLiteralIR(char*, char*, char*, char*);
char* irCall(char*, char*, char*, char*);
char* irStmt(char*, char*, char*, char*, char*);
char* irLetIR(char*, char*, char*, char*, char*);
char* irBlockIR(char*, char*, char*, char*, char*);
char* irIfIR(char*, char*, char*, char*, char*);
char* irWhileIR(char*, char*, char*, char*, char*);
char* irForIR(char*, char*, char*, char*, char*);
char* irMatchIR(char*, char*, char*, char*, char*);
char* irTryIR(char*, char*, char*, char*, char*);
char* irFuncIR(char*, char*, char*);
char* findFreeVars(char*, char*, char*, char*);

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
    char* c = ((char*(*)(char*))findLastComma)(pair);
    if (kr_truthy(kr_lt(c, kr_str("0")))) {
        return pair;
    }
    return kr_substr(pair, kr_str("0"), c);
}

char* pairPos(char* pair) {
    char* c = ((char*(*)(char*))findLastComma)(pair);
    return kr_toint(kr_substr(pair, kr_plus(c, kr_str("1")), kr_len(pair)));
}

char* isDigit(char* c) {
    return (kr_truthy(kr_gte(c, kr_str("0"))) && kr_truthy(kr_lte(c, kr_str("9"))) ? kr_str("1") : kr_str("0"));
}

char* charIsAlpha(char* c) {
    return (kr_truthy((kr_truthy((kr_truthy(kr_gte(c, kr_str("a"))) && kr_truthy(kr_lte(c, kr_str("z"))) ? kr_str("1") : kr_str("0"))) || kr_truthy((kr_truthy(kr_gte(c, kr_str("A"))) && kr_truthy(kr_lte(c, kr_str("Z"))) ? kr_str("1") : kr_str("0"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(c, kr_str("_"))) ? kr_str("1") : kr_str("0"));
}

char* charIsAlphaNum(char* c) {
    return (kr_truthy(((char*(*)(char*))charIsAlpha)(c)) || kr_truthy((kr_truthy(kr_gte(c, kr_str("0"))) && kr_truthy(kr_lte(c, kr_str("9"))) ? kr_str("1") : kr_str("0"))) ? kr_str("1") : kr_str("0"));
}

char* hexDigitVal(char* c) {
    if (kr_truthy((kr_truthy(kr_gte(c, kr_str("0"))) && kr_truthy(kr_lte(c, kr_str("9"))) ? kr_str("1") : kr_str("0")))) {
        return kr_sub(kr_charcode(c), kr_charcode(kr_str("0")));
    }
    if (kr_truthy((kr_truthy(kr_gte(c, kr_str("a"))) && kr_truthy(kr_lte(c, kr_str("f"))) ? kr_str("1") : kr_str("0")))) {
        return kr_plus(kr_sub(kr_charcode(c), kr_charcode(kr_str("a"))), kr_str("10"));
    }
    if (kr_truthy((kr_truthy(kr_gte(c, kr_str("A"))) && kr_truthy(kr_lte(c, kr_str("F"))) ? kr_str("1") : kr_str("0")))) {
        return kr_plus(kr_sub(kr_charcode(c), kr_charcode(kr_str("A"))), kr_str("10"));
    }
    return kr_neg(kr_str("1"));
}

char* readNumber(char* text, char* i) {
    char* start = i;
    if (kr_truthy((kr_truthy((kr_truthy(kr_eq(kr_idx(text, kr_atoi(i)), kr_str("0"))) && kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) ? kr_str("1") : kr_str("0"))) && kr_truthy((kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("x"))) || kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("X"))) ? kr_str("1") : kr_str("0"))) ? kr_str("1") : kr_str("0")))) {
        i = kr_plus(i, kr_str("2"));
        char* hexVal = kr_str("0");
        while (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy(kr_gte(((char*(*)(char*))hexDigitVal)(kr_idx(text, kr_atoi(i))), kr_str("0"))) ? kr_str("1") : kr_str("0")))) {
            hexVal = kr_plus(kr_mul(hexVal, kr_str("16")), ((char*(*)(char*))hexDigitVal)(kr_idx(text, kr_atoi(i))));
            i = kr_plus(i, kr_str("1"));
        }
        return kr_plus(kr_plus(hexVal, kr_str(",")), i);
    }
    while (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy(kr_isdigit(kr_idx(text, kr_atoi(i)))) ? kr_str("1") : kr_str("0")))) {
        i = kr_plus(i, kr_str("1"));
    }
    if (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(i)), kr_str("."))) ? kr_str("1") : kr_str("0")))) {
        if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_isdigit(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))))) ? kr_str("1") : kr_str("0")))) {
            i = kr_plus(i, kr_str("1"));
            while (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy(kr_isdigit(kr_idx(text, kr_atoi(i)))) ? kr_str("1") : kr_str("0")))) {
                i = kr_plus(i, kr_str("1"));
            }
        }
    }
    return kr_plus(kr_plus(kr_substr(text, start, i), kr_str(",")), i);
}

char* readIdent(char* text, char* i) {
    char* start = i;
    while (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy(((char*(*)(char*))charIsAlphaNum)(kr_idx(text, kr_atoi(i)))) ? kr_str("1") : kr_str("0")))) {
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
    } else if (kr_truthy(kr_eq(word, kr_str("struct")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("class")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("type")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("try")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("catch")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("throw")))) {
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
    } else if (kr_truthy(kr_eq(word, kr_str("null")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("measure")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("prepare")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("jxt")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("callback")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("loop")))) {
        return kr_str("1");
    } else if (kr_truthy(kr_eq(word, kr_str("until")))) {
        return kr_str("1");
    } else {
        return kr_str("0");
    }
}

char* readBacktickString(char* text, char* i) {
    i = kr_plus(i, kr_str("1"));
    char* s = kr_str("");
    while (kr_truthy((kr_truthy(kr_lt(i, kr_len(text))) && kr_truthy(kr_neq(kr_idx(text, kr_atoi(i)), kr_str("`"))) ? kr_str("1") : kr_str("0")))) {
        s = kr_plus(s, kr_idx(text, kr_atoi(i)));
        i = kr_plus(i, kr_str("1"));
    }
    return kr_plus(kr_plus(s, kr_str(",")), kr_plus(i, kr_str("1")));
}

char* tokenize(char* text) {
    char* out = kr_sbnew();
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, kr_len(text)))) {
        i = ((char*(*)(char*,char*))skipWS)(text, i);
        if (kr_truthy(kr_gte(i, kr_len(text)))) {
            break;
        }
        char* c = kr_idx(text, kr_atoi(i));
        if (kr_truthy((kr_truthy((kr_truthy(kr_eq(c, kr_str("/"))) && kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) ? kr_str("1") : kr_str("0"))) && kr_truthy((kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("/"))) || kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("*"))) ? kr_str("1") : kr_str("0"))) ? kr_str("1") : kr_str("0")))) {
            i = ((char*(*)(char*,char*))skipComment)(text, i);
        } else if (kr_truthy(kr_isdigit(c))) {
            char* pair = ((char*(*)(char*,char*))readNumber)(text, i);
            char* k_num = ((char*(*)(char*))pairVal)(pair);
            i = ((char*(*)(char*))pairPos)(pair);
            out = kr_sbappend(out, kr_plus(kr_plus(kr_str("INT:"), k_num), kr_str("\n")));
        } else if (kr_truthy(kr_eq(c, kr_str("\"")))) {
            char* pair = ((char*(*)(char*,char*))readString)(text, i);
            char* str = ((char*(*)(char*))pairVal)(pair);
            i = ((char*(*)(char*))pairPos)(pair);
            out = kr_sbappend(out, kr_plus(kr_plus(kr_str("STR:"), str), kr_str("\n")));
        } else if (kr_truthy(((char*(*)(char*))charIsAlpha)(c))) {
            char* pair = ((char*(*)(char*,char*))readIdent)(text, i);
            char* id = ((char*(*)(char*))pairVal)(pair);
            i = ((char*(*)(char*))pairPos)(pair);
            if (kr_truthy(kr_eq(id, kr_str("cfunc")))) {
                char* ci2 = ((char*(*)(char*,char*))skipWS)(text, i);
                if (kr_truthy((kr_truthy(kr_lt(ci2, kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(ci2)), kr_str("{"))) ? kr_str("1") : kr_str("0")))) {
                    ci2 = kr_plus(ci2, kr_str("1"));
                    char* ctext = kr_str("");
                    char* cdepth = kr_str("1");
                    char* inStr = kr_str("0");
                    while (kr_truthy((kr_truthy(kr_lt(ci2, kr_len(text))) && kr_truthy(kr_gt(cdepth, kr_str("0"))) ? kr_str("1") : kr_str("0")))) {
                        char* ch = kr_idx(text, kr_atoi(ci2));
                        if (kr_truthy(kr_eq(inStr, kr_str("1")))) {
                            if (kr_truthy((kr_truthy(kr_eq(ch, kr_str("\\"))) && kr_truthy(kr_lt(kr_plus(ci2, kr_str("1")), kr_len(text))) ? kr_str("1") : kr_str("0")))) {
                                ctext = kr_plus(kr_plus(ctext, ch), kr_idx(text, kr_atoi(kr_plus(ci2, kr_str("1")))));
                                ci2 = kr_plus(ci2, kr_str("2"));
                            } else {
                                if (kr_truthy(kr_eq(ch, kr_str("\"")))) {
                                    inStr = kr_str("0");
                                }
                                if (kr_truthy(kr_eq(ch, kr_str("\n")))) {
                                    ctext = kr_plus(ctext, kr_str("\\x01"));
                                } else {
                                    ctext = kr_plus(ctext, ch);
                                }
                                ci2 = kr_plus(ci2, kr_str("1"));
                            }
                        } else {
                            if (kr_truthy(kr_eq(ch, kr_str("\"")))) {
                                inStr = kr_str("1");
                                ctext = kr_plus(ctext, ch);
                                ci2 = kr_plus(ci2, kr_str("1"));
                            } else if (kr_truthy(kr_eq(ch, kr_str("{")))) {
                                cdepth = kr_plus(cdepth, kr_str("1"));
                                ctext = kr_plus(ctext, ch);
                                ci2 = kr_plus(ci2, kr_str("1"));
                            } else if (kr_truthy(kr_eq(ch, kr_str("}")))) {
                                cdepth = kr_sub(cdepth, kr_str("1"));
                                if (kr_truthy(kr_gt(cdepth, kr_str("0")))) {
                                    ctext = kr_plus(ctext, ch);
                                }
                                ci2 = kr_plus(ci2, kr_str("1"));
                            } else if (kr_truthy(kr_eq(ch, kr_str("\n")))) {
                                ctext = kr_plus(ctext, kr_str("\\x01"));
                                ci2 = kr_plus(ci2, kr_str("1"));
                            } else if (kr_truthy(kr_eq(ch, kr_str("\\r")))) {
                                ci2 = kr_plus(ci2, kr_str("1"));
                            } else {
                                ctext = kr_plus(ctext, ch);
                                ci2 = kr_plus(ci2, kr_str("1"));
                            }
                        }
                    }
                    i = ci2;
                    out = kr_sbappend(out, kr_plus(kr_plus(kr_str("CBLOCK:"), ctext), kr_str("\n")));
                }
            } else if (kr_truthy(((char*(*)(char*))isKW)(id))) {
                out = kr_sbappend(out, kr_plus(kr_plus(kr_str("KW:"), id), kr_str("\n")));
            } else {
                out = kr_sbappend(out, kr_plus(kr_plus(kr_str("ID:"), id), kr_str("\n")));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("+")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("+"))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, kr_str("PLUSPLUS\n"));
                i = kr_plus(i, kr_str("2"));
            } else if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, kr_str("PLUSEQ\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                out = kr_sbappend(out, kr_str("PLUS\n"));
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("-")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str(">"))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, kr_str("ARROW\n"));
                i = kr_plus(i, kr_str("2"));
            } else if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("-"))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, kr_str("MINUSMINUS\n"));
                i = kr_plus(i, kr_str("2"));
            } else if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, kr_str("MINUSEQ\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                out = kr_sbappend(out, kr_str("MINUS\n"));
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("*")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("*"))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, kr_str("STARSTAR\n"));
                i = kr_plus(i, kr_str("2"));
            } else if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, kr_str("STAREQ\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                out = kr_sbappend(out, kr_str("STAR\n"));
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("/")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, kr_str("SLASHEQ\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                out = kr_sbappend(out, kr_str("SLASH\n"));
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("(")))) {
            out = kr_sbappend(out, kr_str("LPAREN\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str(")")))) {
            out = kr_sbappend(out, kr_str("RPAREN\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str("{")))) {
            out = kr_sbappend(out, kr_str("LBRACE\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str("}")))) {
            out = kr_sbappend(out, kr_str("RBRACE\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str("[")))) {
            out = kr_sbappend(out, kr_str("LBRACK\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str("]")))) {
            out = kr_sbappend(out, kr_str("RBRACK\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str(":")))) {
            out = kr_sbappend(out, kr_str("COLON\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str(";")))) {
            out = kr_sbappend(out, kr_str("SEMI\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str(",")))) {
            out = kr_sbappend(out, kr_str("COMMA\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str("=")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, kr_str("EQ\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                out = kr_sbappend(out, kr_str("ASSIGN\n"));
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("!")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, kr_str("NEQ\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                out = kr_sbappend(out, kr_str("BANG\n"));
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("<")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, kr_str("LTE\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                out = kr_sbappend(out, kr_str("LT\n"));
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str(">")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, kr_str("GTE\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                out = kr_sbappend(out, kr_str("GT\n"));
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("&")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("&"))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, kr_str("AND\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("|")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("|"))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, kr_str("OR\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("%")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str("="))) ? kr_str("1") : kr_str("0")))) {
                out = kr_sbappend(out, kr_str("MODEQ\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                out = kr_sbappend(out, kr_str("MOD\n"));
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("?")))) {
            out = kr_sbappend(out, kr_str("QUESTION\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str(".")))) {
            out = kr_sbappend(out, kr_str("DOT\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str("`")))) {
            char* pair = ((char*(*)(char*,char*))readBacktickString)(text, i);
            char* str = ((char*(*)(char*))pairVal)(pair);
            i = ((char*(*)(char*))pairPos)(pair);
            out = kr_sbappend(out, kr_plus(kr_plus(kr_str("INTERP:"), str), kr_str("\n")));
        } else {
            i = kr_plus(i, kr_str("1"));
        }
    }
    return kr_sbtostring(out);
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
    char* table = kr_sbnew();
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* tok = ((char*(*)(char*,char*))tokAt)(tokens, i);
        if (kr_truthy(kr_eq(tok, kr_str("KW:jxt")))) {
            i = ((char*(*)(char*,char*))skipBlock)(tokens, kr_plus(i, kr_str("1")));
        } else if (kr_truthy(kr_eq(tok, kr_str("KW:func")))) {
            char* nameTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, kr_str("1")));
            char* fname = ((char*(*)(char*))tokVal)(nameTok);
            char* j = kr_plus(i, kr_str("3"));
            char* params = kr_str("");
            char* pc = kr_str("0");
            while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, j), kr_str("RPAREN")))) {
                char* pt = ((char*(*)(char*,char*))tokAt)(tokens, j);
                if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(pt), kr_str("ID")))) {
                    if (kr_truthy(kr_gt(pc, kr_str("0")))) {
                        params = kr_plus(kr_plus(params, kr_str(",")), ((char*(*)(char*))tokVal)(pt));
                    } else {
                        params = ((char*(*)(char*))tokVal)(pt);
                    }
                    pc = kr_plus(pc, kr_str("1"));
                    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(j, kr_str("1"))), kr_str("COLON")))) {
                        j = kr_plus(j, kr_str("3"));
                        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, j), kr_str("LBRACK")))) {
                            char* std = kr_str("1");
                            j = kr_plus(j, kr_str("1"));
                            while (kr_truthy(kr_gt(std, kr_str("0")))) {
                                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, j), kr_str("LBRACK")))) {
                                    std = kr_plus(std, kr_str("1"));
                                }
                                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, j), kr_str("RBRACK")))) {
                                    std = kr_sub(std, kr_str("1"));
                                }
                                j = kr_plus(j, kr_str("1"));
                            }
                        }
                        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, j), kr_str("COMMA")))) {
                            j = kr_plus(j, kr_str("1"));
                        }
                    } else {
                        j = kr_plus(j, kr_str("1"));
                    }
                } else {
                    j = kr_plus(j, kr_str("1"));
                }
            }
            char* bodyStart = kr_plus(j, kr_str("1"));
            table = kr_sbappend(table, kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(fname, kr_str("~")), pc), kr_str("~")), params), kr_str("~")), bodyStart), kr_str("\n")));
        }
        i = kr_plus(i, kr_str("1"));
    }
    return kr_sbtostring(table);
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
        char* tok = ((char*(*)(char*,char*))tokAt)(tokens, i);
        if (kr_truthy((kr_truthy(kr_eq(tok, kr_str("KW:just"))) || kr_truthy(kr_eq(tok, kr_str("KW:go"))) ? kr_str("1") : kr_str("0")))) {
            if (kr_truthy(kr_lt(kr_plus(i, kr_str("2")), ntoks))) {
                char* next = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, kr_str("1")));
                if (kr_truthy(kr_eq(next, kr_str("ID:run")))) {
                    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, kr_str("2"))), kr_str("LBRACE")))) {
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
        char* t = ((char*(*)(char*,char*))tokAt)(tokens, p);
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
    if (kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(name, kr_str("abs"))) || kr_truthy(kr_eq(name, kr_str("exit"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("rand"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("free"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("malloc"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("printf"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("strlen"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("strcmp"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("strcpy"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("time"))) ? kr_str("1") : kr_str("0")))) {
        return kr_plus(kr_str("k_"), name);
    }
    if (kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(name, kr_str("double"))) || kr_truthy(kr_eq(name, kr_str("float"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("int"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("bool"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("string"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("list"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("map"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("any"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("void"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(name, kr_str("num"))) ? kr_str("1") : kr_str("0")))) {
        return kr_plus(kr_str("k_"), name);
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
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("QUESTION")))) {
        char* tp = ((char*(*)(char*,char*,char*))compileExpr)(tokens, kr_plus(p, kr_str("1")), ntoks);
        char* tcode = ((char*(*)(char*))pairVal)(tp);
        p = ((char*(*)(char*))pairPos)(tp);
        p = kr_plus(p, kr_str("1"));
        char* fp = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
        char* fcode = ((char*(*)(char*))pairVal)(fp);
        p = ((char*(*)(char*))pairPos)(fp);
        code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("(kr_truthy("), code), kr_str(") ? ")), tcode), kr_str(" : ")), fcode), kr_str(")"));
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* compileOr(char* tokens, char* pos, char* ntoks) {
    char* pair = ((char*(*)(char*,char*,char*))compileAnd)(tokens, pos, ntoks);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("OR")))) {
        char* rp = ((char*(*)(char*,char*,char*))compileAnd)(tokens, kr_plus(p, kr_str("1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("(kr_truthy("), code), kr_str(") || kr_truthy(")), rcode), kr_str(") ? kr_str(\"1\") : kr_str(\"0\"))"));
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* compileAnd(char* tokens, char* pos, char* ntoks) {
    char* pair = ((char*(*)(char*,char*,char*))compileEquality)(tokens, pos, ntoks);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("AND")))) {
        char* rp = ((char*(*)(char*,char*,char*))compileEquality)(tokens, kr_plus(p, kr_str("1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("(kr_truthy("), code), kr_str(") && kr_truthy(")), rcode), kr_str(") ? kr_str(\"1\") : kr_str(\"0\"))"));
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* compileEquality(char* tokens, char* pos, char* ntoks) {
    char* pair = ((char*(*)(char*,char*,char*))compileRelational)(tokens, pos, ntoks);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("EQ"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("NEQ"))) ? kr_str("1") : kr_str("0")))) {
        char* op = ((char*(*)(char*,char*))tokAt)(tokens, p);
        char* rp = ((char*(*)(char*,char*,char*))compileRelational)(tokens, kr_plus(p, kr_str("1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        if (kr_truthy(kr_eq(op, kr_str("EQ")))) {
            code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_eq("), code), kr_str(", ")), rcode), kr_str(")"));
        } else {
            code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_neq("), code), kr_str(", ")), rcode), kr_str(")"));
        }
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* compileRelational(char* tokens, char* pos, char* ntoks) {
    char* pair = ((char*(*)(char*,char*,char*))compileAdditive)(tokens, pos, ntoks);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("LT"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("GT"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("LTE"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("GTE"))) ? kr_str("1") : kr_str("0")))) {
        char* op = ((char*(*)(char*,char*))tokAt)(tokens, p);
        char* rp = ((char*(*)(char*,char*,char*))compileAdditive)(tokens, kr_plus(p, kr_str("1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
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
    char* pair = ((char*(*)(char*,char*,char*))compileMult)(tokens, pos, ntoks);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("PLUS"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("MINUS"))) ? kr_str("1") : kr_str("0")))) {
        char* op = ((char*(*)(char*,char*))tokAt)(tokens, p);
        char* rp = ((char*(*)(char*,char*,char*))compileMult)(tokens, kr_plus(p, kr_str("1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        if (kr_truthy(kr_eq(op, kr_str("PLUS")))) {
            code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_plus("), code), kr_str(", ")), rcode), kr_str(")"));
        } else {
            code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_sub("), code), kr_str(", ")), rcode), kr_str(")"));
        }
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* compileMult(char* tokens, char* pos, char* ntoks) {
    char* pair = ((char*(*)(char*,char*,char*))compilePow)(tokens, pos, ntoks);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy((kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("STAR"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SLASH"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("MOD"))) ? kr_str("1") : kr_str("0")))) {
        char* op = ((char*(*)(char*,char*))tokAt)(tokens, p);
        char* rp = ((char*(*)(char*,char*,char*))compilePow)(tokens, kr_plus(p, kr_str("1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
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

char* compilePow(char* tokens, char* pos, char* ntoks) {
    char* pair = ((char*(*)(char*,char*,char*))compileUnary)(tokens, pos, ntoks);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("STARSTAR")))) {
        char* rp = ((char*(*)(char*,char*,char*))compilePow)(tokens, kr_plus(p, kr_str("1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_pow("), code), kr_str(", ")), rcode), kr_str(")"));
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* compileUnary(char* tokens, char* pos, char* ntoks) {
    char* tok = ((char*(*)(char*,char*))tokAt)(tokens, pos);
    if (kr_truthy(kr_eq(tok, kr_str("MINUS")))) {
        char* rp = ((char*(*)(char*,char*,char*))compileUnary)(tokens, kr_plus(pos, kr_str("1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        char* p = ((char*(*)(char*))pairPos)(rp);
        return kr_plus(kr_plus(kr_plus(kr_str("kr_neg("), rcode), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("BANG")))) {
        char* rp = ((char*(*)(char*,char*,char*))compileUnary)(tokens, kr_plus(pos, kr_str("1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        char* p = ((char*(*)(char*))pairPos)(rp);
        return kr_plus(kr_plus(kr_plus(kr_str("kr_not("), rcode), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("PLUSPLUS")))) {
        char* rp = ((char*(*)(char*,char*,char*))compilePostfix)(tokens, kr_plus(pos, kr_str("1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        char* p = ((char*(*)(char*))pairPos)(rp);
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("("), rcode), kr_str(" = kr_plus(")), rcode), kr_str(", kr_str(\"1\"))),")), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("MINUSMINUS")))) {
        char* rp = ((char*(*)(char*,char*,char*))compilePostfix)(tokens, kr_plus(pos, kr_str("1")), ntoks);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        char* p = ((char*(*)(char*))pairPos)(rp);
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("("), rcode), kr_str(" = kr_sub(")), rcode), kr_str(", kr_str(\"1\"))),")), p);
    }
    return ((char*(*)(char*,char*,char*))compilePostfix)(tokens, pos, ntoks);
}

char* compilePostfix(char* tokens, char* pos, char* ntoks) {
    char* pair = ((char*(*)(char*,char*,char*))compilePrimary)(tokens, pos, ntoks);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("LBRACK"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("DOT"))) ? kr_str("1") : kr_str("0")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("LBRACK")))) {
            char* ip = ((char*(*)(char*,char*,char*))compileExpr)(tokens, kr_plus(p, kr_str("1")), ntoks);
            char* icode = ((char*(*)(char*))pairVal)(ip);
            p = ((char*(*)(char*))pairPos)(ip);
            p = kr_plus(p, kr_str("1"));
            code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_idx("), code), kr_str(", kr_atoi(")), icode), kr_str("))"));
        } else {
            char* field = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, kr_str("1"))));
            p = kr_plus(p, kr_str("2"));
            code = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_getfield("), code), kr_str(", \"")), field), kr_str("\")"));
        }
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* compilePrimary(char* tokens, char* pos, char* ntoks) {
    char* tok = ((char*(*)(char*,char*))tokAt)(tokens, pos);
    char* tt = ((char*(*)(char*))tokType)(tok);
    char* tv = ((char*(*)(char*))tokVal)(tok);
    if (kr_truthy(kr_eq(tt, kr_str("INTERP")))) {
        return kr_plus(kr_plus(((char*(*)(char*))compileInterp)(tv), kr_str(",")), kr_plus(pos, kr_str("1")));
    }
    if (kr_truthy(kr_eq(tt, kr_str("INT")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_str(\""), tv), kr_str("\"),")), kr_plus(pos, kr_str("1")));
    }
    if (kr_truthy(kr_eq(tt, kr_str("STR")))) {
        char* expanded = ((char*(*)(char*))expandEscapes)(tv);
        char* escaped = ((char*(*)(char*))cEscape)(expanded);
        return kr_plus(kr_plus(kr_plus(kr_str("kr_str(\""), escaped), kr_str("\"),")), kr_plus(pos, kr_str("1")));
    }
    if (kr_truthy(kr_eq(tt, kr_str("KW")))) {
        if (kr_truthy(kr_eq(tv, kr_str("true")))) {
            return kr_plus(kr_str("kr_str(\"1\"),"), kr_plus(pos, kr_str("1")));
        }
        if (kr_truthy(kr_eq(tv, kr_str("false")))) {
            return kr_plus(kr_str("kr_str(\"0\"),"), kr_plus(pos, kr_str("1")));
        }
        if (kr_truthy(kr_eq(tv, kr_str("null")))) {
            return kr_plus(kr_str("((char*)0),"), kr_plus(pos, kr_str("1")));
        }
    }
    if (kr_truthy(kr_eq(tok, kr_str("LPAREN")))) {
        char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, kr_plus(pos, kr_str("1")), ntoks);
        char* ecode = ((char*(*)(char*))pairVal)(ep);
        char* p = ((char*(*)(char*))pairPos)(ep);
        return kr_plus(kr_plus(ecode, kr_str(",")), kr_plus(p, kr_str("1")));
    }
    if (kr_truthy(kr_eq(tok, kr_str("LBRACK")))) {
        return ((char*(*)(char*,char*,char*))compileListLiteral)(tokens, pos, ntoks);
    }
    if (kr_truthy((kr_truthy(kr_eq(tok, kr_str("KW:func"))) || kr_truthy(kr_eq(tok, kr_str("KW:fn"))) ? kr_str("1") : kr_str("0")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("1"))), kr_str("LPAREN")))) {
            return ((char*(*)(char*,char*,char*))compileLambda)(tokens, pos, ntoks);
        }
        return kr_plus(kr_plus(((char*(*)(char*))cIdent)(tv), kr_str(",")), kr_plus(pos, kr_str("1")));
    }
    if (kr_truthy(kr_eq(tt, kr_str("ID")))) {
        char* name = tv;
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("1"))), kr_str("LPAREN")))) {
            return ((char*(*)(char*,char*,char*))compileCall)(tokens, pos, ntoks);
        }
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("1"))), kr_str("LBRACE")))) {
            char* firstChar = kr_idx(name, kr_atoi(kr_str("0")));
            if (kr_truthy((kr_truthy(kr_gte(firstChar, kr_str("A"))) && kr_truthy(kr_lte(firstChar, kr_str("Z"))) ? kr_str("1") : kr_str("0")))) {
                return ((char*(*)(char*,char*,char*))compileStructLiteral)(tokens, pos, ntoks);
            }
        }
        return kr_plus(kr_plus(((char*(*)(char*))cIdent)(name), kr_str(",")), kr_plus(pos, kr_str("1")));
    }
    return kr_plus(kr_str("kr_str(\"\"),"), kr_plus(pos, kr_str("1")));
}

char* compileCall(char* tokens, char* pos, char* ntoks) {
    char* fname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* p = kr_plus(pos, kr_str("2"));
    char* args = kr_str("");
    char* argc = kr_str("0");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RPAREN")))) {
        if (kr_truthy(kr_gt(argc, kr_str("0")))) {
            p = kr_plus(p, kr_str("1"));
        }
        char* ap = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
        char* acode = ((char*(*)(char*))pairVal)(ap);
        p = ((char*(*)(char*))pairPos)(ap);
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
    if (kr_truthy(kr_eq(fname, kr_str("exec")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_exec("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("shellRun")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_shellrun("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("deleteFile")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_deletefile("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("structNew")))) {
        char* snArg = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("2")));
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(snArg), kr_str("STR")))) {
            return kr_plus(kr_plus(kr_plus(kr_str("structnew_"), ((char*(*)(char*))tokVal)(snArg)), kr_str("(),")), p);
        } else {
            return kr_plus(kr_str("structnew_unknown(),"), p);
        }
    }
    if (kr_truthy(kr_eq(fname, kr_str("structGet")))) {
        char* sgType = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("4")));
        char* sgField = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("6")));
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(sgType), kr_str("STR")))) {
            char* sgPtr = kr_split(args, kr_str("0"));
            return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("structget_"), ((char*(*)(char*))tokVal)(sgType)), kr_str("(")), sgPtr), kr_str(", kr_str(\"")), ((char*(*)(char*))tokVal)(sgField)), kr_str("\")),")), p);
        } else {
            return kr_plus(kr_str("kr_str(\"\"),"), p);
        }
    }
    if (kr_truthy(kr_eq(fname, kr_str("structSet")))) {
        char* ssType = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("4")));
        char* ssField = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("6")));
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(ssType), kr_str("STR")))) {
            char* ssPtr = kr_split(args, kr_str("0"));
            char* ssVal = kr_split(args, kr_str("3"));
            return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("structset_"), ((char*(*)(char*))tokVal)(ssType)), kr_str("(")), ssPtr), kr_str(", kr_str(\"")), ((char*(*)(char*))tokVal)(ssField)), kr_str("\"), ")), ssVal), kr_str("),")), p);
        } else {
            return kr_plus(kr_str("_K_EMPTY,"), p);
        }
    }
    if (kr_truthy(kr_eq(fname, kr_str("sizeOf")))) {
        char* soArg = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("2")));
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(soArg), kr_str("STR")))) {
            return kr_plus(kr_plus(kr_plus(kr_str("structsizeof_"), ((char*(*)(char*))tokVal)(soArg)), kr_str("(),")), p);
        } else {
            return kr_plus(kr_str("kr_str(\"0\"),"), p);
        }
    }
    if (kr_truthy(kr_eq(fname, kr_str("structAddr")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("((char*)("), args), kr_str(")),")), p);
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
    if (kr_truthy(kr_eq(fname, kr_str("writeBytes")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_writebytes("), args), kr_str("),")), p);
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
    if (kr_truthy(kr_eq(fname, kr_str("strReverse")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_strreverse("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("words")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_words("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("lines")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_lines("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("first")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_first("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("last")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_last("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("head")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_head("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("tail")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_tail("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("lstrip")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_lstrip("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("rstrip")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_rstrip("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("center")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_center("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("isAlpha")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_isalpha("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("isDigit")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_isdigit("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("isSpace")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_isspace("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("random")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_random("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("timestamp")))) {
        return kr_plus(kr_str("kr_timestamp(),"), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("environ")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_environ("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("floor")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_floor("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("ceil")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_ceil("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("round")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_round("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("throw")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_throw("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("fadd")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_fadd("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("fsub")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_fsub("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("fmul")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_fmul("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("fdiv")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_fdiv("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("flt")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_flt("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("fgt")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_fgt("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("feq")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_feq("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("fsqrt")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_fsqrt("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("ffloor")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_ffloor("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("fceil")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_fceil("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("fround")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_fround("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("fformat")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_fformat("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("toFloat")))) {
        return kr_plus(kr_plus(args, kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("bitAnd")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_bitand("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("bitOr")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_bitor("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("bitXor")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_bitxor("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("bitNot")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_bitnot("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("bitShl")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_bitshl("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("bitShr")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_bitshr("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("toLong")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_tolong("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("div64")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_div64("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("mod64")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_mod64("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("mul64")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_mul64("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("add64")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_add64("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("eqIgnoreCase")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_eqignorecase("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("handleValid")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_handlevalid("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("bufNew")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("_alloc(atoi("), args), kr_str(")),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("bufStr")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_str("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("bufGetDword")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_bufgetdword("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("bufSetDword")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_bufsetdword("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("bufGetWord")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_bufgetword("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("bufGetQword")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_bufgetqword("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("bufGetDwordAt")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_bufgetdwordat("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("bufGetQwordAt")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_bufgetqwordat("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("bufSetByte")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_bufsetbyte("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("bufSetDwordAt")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_bufsetdwordat("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("handleOut")))) {
        return kr_plus(kr_str("((char*)_alloc(sizeof(void*))),"), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("handleGet")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_handleget("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("handleInt")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_handleint("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("toHandle")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("((char*)(intptr_t)atoll("), args), kr_str(")),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("ptrDeref")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_ptrderef("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("ptrIndex")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_ptrindex("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("callPtr")))) {
        if (kr_truthy(kr_eq(argc, kr_str("2")))) {
            return kr_plus(kr_plus(kr_plus(kr_str("kr_callptr1("), args), kr_str("),")), p);
        }
        if (kr_truthy(kr_eq(argc, kr_str("3")))) {
            return kr_plus(kr_plus(kr_plus(kr_str("kr_callptr2("), args), kr_str("),")), p);
        }
        if (kr_truthy(kr_eq(argc, kr_str("4")))) {
            return kr_plus(kr_plus(kr_plus(kr_str("kr_callptr3("), args), kr_str("),")), p);
        }
        if (kr_truthy(kr_eq(argc, kr_str("5")))) {
            return kr_plus(kr_plus(kr_plus(kr_str("kr_callptr4("), args), kr_str("),")), p);
        }
    }
    if (kr_truthy(kr_eq(fname, kr_str("mapGet")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_mapget("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("mapSet")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_mapset("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("mapDel")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_mapdel("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("sprintf")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_sprintf("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("listMap")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_listmap("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("listFilter")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_listfilter("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("strSplit")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_strsplit("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("structNew")))) {
        return kr_plus(kr_str("kr_structnew(),"), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("getField")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_getfield("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("setField")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_setfield("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("hasField")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_hasfield("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("structFields")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("kr_structfields("), args), kr_str("),")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("funcptr")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("((char*)"), ((char*(*)(char*))cIdent)(args)), kr_str("),")), p);
    }
    char* castArgs = kr_str("char*");
    char* ci = kr_str("1");
    while (kr_truthy(kr_lt(ci, argc))) {
        castArgs = kr_plus(castArgs, kr_str(",char*"));
        ci = kr_plus(ci, kr_str("1"));
    }
    if (kr_truthy(kr_eq(argc, kr_str("0")))) {
        castArgs = kr_str("void");
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("((char*(*)("), castArgs), kr_str("))")), ((char*(*)(char*))cIdent)(fname)), kr_str(")(")), args), kr_str("),")), p);
}

char* compileStmt(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* tok = ((char*(*)(char*,char*))tokAt)(tokens, pos);
    if (kr_truthy((kr_truthy((kr_truthy(kr_eq(tok, kr_str("KW:struct"))) || kr_truthy(kr_eq(tok, kr_str("KW:class"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(tok, kr_str("KW:type"))) ? kr_str("1") : kr_str("0")))) {
        return ((char*(*)(char*,char*,char*,char*))compileStructDecl)(tokens, kr_plus(pos, kr_str("1")), ntoks, depth);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:try")))) {
        char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, kr_plus(pos, kr_str("1")), ntoks, depth, inFunc);
        char* bcode = ((char*(*)(char*))pairVal)(bp);
        char* p = ((char*(*)(char*))pairPos)(bp);
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("KW:catch")))) {
            p = kr_plus(p, kr_str("1"));
            char* catchVar = kr_str("__err");
            if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, p)), kr_str("ID")))) {
                catchVar = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, p));
                p = kr_plus(p, kr_str("1"));
            }
            char* cbp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, p, ntoks, depth, inFunc);
            char* cbcode = ((char*(*)(char*))pairVal)(cbp);
            p = ((char*(*)(char*))pairPos)(cbp);
            char* ind = ((char*(*)(char*))indent)(depth);
            char* ind1 = ((char*(*)(char*))indent)(kr_plus(depth, kr_str("1")));
            char* out = kr_plus(ind, kr_str("{\n"));
            out = kr_plus(kr_plus(out, ind1), kr_str("if (setjmp(*_kr_pushtry()) == 0) {\n"));
            out = kr_plus(out, bcode);
            out = kr_plus(kr_plus(out, ind1), kr_str("_kr_poptry();\n"));
            out = kr_plus(kr_plus(out, ind1), kr_str("} else {\n"));
            out = kr_plus(kr_plus(kr_plus(kr_plus(out, ind1), kr_str("    char* ")), catchVar), kr_str(" = _kr_poptry();\n"));
            out = kr_plus(out, cbcode);
            out = kr_plus(kr_plus(out, ind1), kr_str("}\n"));
            out = kr_plus(kr_plus(out, ind), kr_str("}\n"));
            return kr_plus(kr_plus(out, kr_str(",")), p);
        } else {
            char* ind = ((char*(*)(char*))indent)(depth);
            char* ind1 = ((char*(*)(char*))indent)(kr_plus(depth, kr_str("1")));
            char* out = kr_plus(ind, kr_str("{\n"));
            out = kr_plus(kr_plus(out, ind1), kr_str("if (setjmp(*_kr_pushtry()) == 0) {\n"));
            out = kr_plus(out, bcode);
            out = kr_plus(kr_plus(out, ind1), kr_str("_kr_poptry();\n"));
            out = kr_plus(kr_plus(out, ind1), kr_str("}\n"));
            out = kr_plus(kr_plus(out, ind), kr_str("}\n"));
            return kr_plus(kr_plus(out, kr_str(",")), p);
        }
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:throw")))) {
        char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, kr_plus(pos, kr_str("1")), ntoks);
        char* ecode = ((char*(*)(char*))pairVal)(ep);
        char* p = ((char*(*)(char*))pairPos)(ep);
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
            p = kr_plus(p, kr_str("1"));
        }
        return kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), kr_str("_kr_throw(")), ecode), kr_str(");\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:let")))) {
        return ((char*(*)(char*,char*,char*,char*))compileLet)(tokens, kr_plus(pos, kr_str("1")), ntoks, depth);
    }
    if (kr_truthy((kr_truthy(kr_eq(tok, kr_str("KW:emit"))) || kr_truthy(kr_eq(tok, kr_str("KW:return"))) ? kr_str("1") : kr_str("0")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))compileEmit)(tokens, kr_plus(pos, kr_str("1")), ntoks, depth, inFunc);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:if")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))compileIf)(tokens, kr_plus(pos, kr_str("1")), ntoks, depth, inFunc);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:while")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))compileWhile)(tokens, kr_plus(pos, kr_str("1")), ntoks, depth, inFunc);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:for")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))compileFor)(tokens, kr_plus(pos, kr_str("1")), ntoks, depth, inFunc);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:break")))) {
        char* p = kr_plus(pos, kr_str("1"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
            p = kr_plus(p, kr_str("1"));
        }
        return kr_plus(kr_plus(((char*(*)(char*))indent)(depth), kr_str("break;\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:continue")))) {
        char* p = kr_plus(pos, kr_str("1"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
            p = kr_plus(p, kr_str("1"));
        }
        return kr_plus(kr_plus(((char*(*)(char*))indent)(depth), kr_str("continue;\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:match")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))compileMatch)(tokens, kr_plus(pos, kr_str("1")), ntoks, depth, inFunc);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:do")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))compileDoWhile)(tokens, kr_plus(pos, kr_str("1")), ntoks, depth, inFunc);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:loop")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))compileLoop)(tokens, kr_plus(pos, kr_str("1")), ntoks, depth, inFunc);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:const")))) {
        return ((char*(*)(char*,char*,char*,char*))compileLet)(tokens, kr_plus(pos, kr_str("1")), ntoks, depth);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:module")))) {
        char* mname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("1"))));
        char* p = kr_plus(pos, kr_str("2"));
        return kr_plus(kr_plus(kr_plus(kr_str("// module: "), mname), kr_str("\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:import")))) {
        char* importPath = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("1"))));
        char* p = kr_plus(pos, kr_str("2"));
        char* importSrc = kr_readfile(importPath);
        if (kr_truthy(kr_gt(kr_len(importSrc), kr_str("0")))) {
            return kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), kr_str("// imported: ")), importPath), kr_str("\n,")), p);
        } else {
            return kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), kr_str("// import not found: ")), importPath), kr_str("\n,")), p);
        }
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:export")))) {
        char* nextTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("1")));
        if (kr_truthy((kr_truthy(kr_eq(nextTok, kr_str("KW:func"))) || kr_truthy(kr_eq(nextTok, kr_str("KW:fn"))) ? kr_str("1") : kr_str("0")))) {
            char* fp = ((char*(*)(char*,char*,char*))compileFunc)(tokens, kr_plus(pos, kr_str("1")), ntoks);
            return kr_plus(kr_plus(((char*(*)(char*))pairVal)(fp), kr_str(",")), ((char*(*)(char*))pairPos)(fp));
        }
        if (kr_truthy((kr_truthy((kr_truthy(kr_eq(nextTok, kr_str("KW:struct"))) || kr_truthy(kr_eq(nextTok, kr_str("KW:class"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(nextTok, kr_str("KW:type"))) ? kr_str("1") : kr_str("0")))) {
            return ((char*(*)(char*,char*,char*,char*))compileStructDecl)(tokens, kr_plus(pos, kr_str("2")), ntoks, depth);
        }
        char* p = kr_plus(pos, kr_str("2"));
        return kr_plus(kr_plus(((char*(*)(char*))indent)(depth), kr_str("// export\n,")), p);
    }
    if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(tok), kr_str("CBLOCK")))) {
        char* craw = kr_replace(((char*(*)(char*))tokVal)(tok), kr_str("\\x01"), kr_str("\n"));
        return kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), craw), kr_str("\n,")), kr_plus(pos, kr_str("1")));
    }
    if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(tok), kr_str("ID")))) {
        char* nextTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("1")));
        if (kr_truthy(kr_eq(nextTok, kr_str("PLUSPLUS")))) {
            char* vname = ((char*(*)(char*))cIdent)(((char*(*)(char*))tokVal)(tok));
            char* p = kr_plus(pos, kr_str("2"));
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
                p = kr_plus(p, kr_str("1"));
            }
            return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), vname), kr_str(" = kr_plus(")), vname), kr_str(", kr_str(\"1\"));\n,")), p);
        }
        if (kr_truthy(kr_eq(nextTok, kr_str("MINUSMINUS")))) {
            char* vname = ((char*(*)(char*))cIdent)(((char*(*)(char*))tokVal)(tok));
            char* p = kr_plus(pos, kr_str("2"));
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
                p = kr_plus(p, kr_str("1"));
            }
            return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), vname), kr_str(" = kr_sub(")), vname), kr_str(", kr_str(\"1\"));\n,")), p);
        }
    }
    if (kr_truthy(kr_eq(tok, kr_str("PLUSPLUS")))) {
        char* vname = ((char*(*)(char*))cIdent)(((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("1")))));
        char* p = kr_plus(pos, kr_str("2"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
            p = kr_plus(p, kr_str("1"));
        }
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), vname), kr_str(" = kr_plus(")), vname), kr_str(", kr_str(\"1\"));\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("MINUSMINUS")))) {
        char* vname = ((char*(*)(char*))cIdent)(((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("1")))));
        char* p = kr_plus(pos, kr_str("2"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
            p = kr_plus(p, kr_str("1"));
        }
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), vname), kr_str(" = kr_sub(")), vname), kr_str(", kr_str(\"1\"));\n,")), p);
    }
    if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(tok), kr_str("ID")))) {
        char* nextTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("1")));
        if (kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(nextTok, kr_str("PLUSEQ"))) || kr_truthy(kr_eq(nextTok, kr_str("MINUSEQ"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(nextTok, kr_str("STAREQ"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(nextTok, kr_str("SLASHEQ"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(nextTok, kr_str("MODEQ"))) ? kr_str("1") : kr_str("0")))) {
            return ((char*(*)(char*,char*,char*,char*))compileCompoundAssign)(tokens, pos, ntoks, depth);
        }
    }
    if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(tok), kr_str("ID")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("1"))), kr_str("DOT")))) {
            if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("2")))), kr_str("ID")))) {
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("3"))), kr_str("ASSIGN")))) {
                    return ((char*(*)(char*,char*,char*,char*))compileFieldAssign)(tokens, pos, ntoks, depth);
                }
            }
        }
    }
    if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(tok), kr_str("ID")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("1"))), kr_str("ASSIGN")))) {
            return ((char*(*)(char*,char*,char*,char*))compileAssign)(tokens, pos, ntoks, depth);
        }
    }
    return ((char*(*)(char*,char*,char*,char*))compileExprStmt)(tokens, pos, ntoks, depth);
}

char* compileLet(char* tokens, char* pos, char* ntoks, char* depth) {
    char* name = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* p = kr_plus(pos, kr_str("1"));
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("COLON")))) {
        p = kr_plus(p, kr_str("2"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("LBRACK")))) {
            char* depth2 = kr_str("1");
            p = kr_plus(p, kr_str("1"));
            while (kr_truthy(kr_gt(depth2, kr_str("0")))) {
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("LBRACK")))) {
                    depth2 = kr_plus(depth2, kr_str("1"));
                }
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RBRACK")))) {
                    depth2 = kr_sub(depth2, kr_str("1"));
                }
                p = kr_plus(p, kr_str("1"));
            }
        }
    }
    p = kr_plus(p, kr_str("1"));
    char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
    char* ecode = ((char*(*)(char*))pairVal)(ep);
    p = ((char*(*)(char*))pairPos)(ep);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
        p = kr_plus(p, kr_str("1"));
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), kr_str("char* ")), ((char*(*)(char*))cIdent)(name)), kr_str(" = ")), ecode), kr_str(";\n,")), p);
}

char* compileAssign(char* tokens, char* pos, char* ntoks, char* depth) {
    char* name = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* p = kr_plus(pos, kr_str("2"));
    char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
    char* ecode = ((char*(*)(char*))pairVal)(ep);
    p = ((char*(*)(char*))pairPos)(ep);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
        p = kr_plus(p, kr_str("1"));
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ((char*(*)(char*))cIdent)(name)), kr_str(" = ")), ecode), kr_str(";\n,")), p);
}

char* compileEmit(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, pos, ntoks);
    char* ecode = ((char*(*)(char*))pairVal)(ep);
    char* p = ((char*(*)(char*))pairPos)(ep);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
        p = kr_plus(p, kr_str("1"));
    }
    if (kr_truthy(kr_eq(inFunc, kr_str("0")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), kr_str("return atoi(")), ecode), kr_str(");\n,")), p);
    }
    if (kr_truthy(kr_eq(inFunc, kr_str("int")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), kr_str("return atoi(")), ecode), kr_str(");\n,")), p);
    }
    if (kr_truthy(kr_eq(inFunc, kr_str("zero")))) {
        return kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ecode), kr_str(";\n,")), p);
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), kr_str("return ")), ecode), kr_str(";\n,")), p);
}

char* compileIf(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* cp = ((char*(*)(char*,char*,char*))compileExpr)(tokens, pos, ntoks);
    char* cond = ((char*(*)(char*))pairVal)(cp);
    char* p = ((char*(*)(char*))pairPos)(cp);
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, p, ntoks, depth, inFunc);
    char* bcode = ((char*(*)(char*))pairVal)(bp);
    p = ((char*(*)(char*))pairPos)(bp);
    char* out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), kr_str("if (kr_truthy(")), cond), kr_str(")) {\n")), bcode), ((char*(*)(char*))indent)(depth)), kr_str("}"));
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("KW:else")))) {
        p = kr_plus(p, kr_str("1"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("KW:if")))) {
            char* eip = ((char*(*)(char*,char*,char*,char*,char*))compileIf)(tokens, kr_plus(p, kr_str("1")), ntoks, depth, inFunc);
            char* eicode = ((char*(*)(char*))pairVal)(eip);
            p = ((char*(*)(char*))pairPos)(eip);
            char* stripped = kr_substr(eicode, kr_len(((char*(*)(char*))indent)(depth)), kr_len(eicode));
            out = kr_plus(kr_plus(out, kr_str(" else ")), stripped);
            return kr_plus(kr_plus(out, kr_str(",")), p);
        } else {
            char* ebp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, p, ntoks, depth, inFunc);
            char* ebcode = ((char*(*)(char*))pairVal)(ebp);
            p = ((char*(*)(char*))pairPos)(ebp);
            out = kr_plus(kr_plus(kr_plus(kr_plus(out, kr_str(" else {\n")), ebcode), ((char*(*)(char*))indent)(depth)), kr_str("}\n"));
            return kr_plus(kr_plus(out, kr_str(",")), p);
        }
    }
    out = kr_plus(out, kr_str("\n"));
    return kr_plus(kr_plus(out, kr_str(",")), p);
}

char* compileWhile(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* cp = ((char*(*)(char*,char*,char*))compileExpr)(tokens, pos, ntoks);
    char* cond = ((char*(*)(char*))pairVal)(cp);
    char* p = ((char*(*)(char*))pairPos)(cp);
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, p, ntoks, depth, inFunc);
    char* bcode = ((char*(*)(char*))pairVal)(bp);
    p = ((char*(*)(char*))pairPos)(bp);
    char* out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), kr_str("while (kr_truthy(")), cond), kr_str(")) {\n")), bcode), ((char*(*)(char*))indent)(depth)), kr_str("}\n"));
    return kr_plus(kr_plus(out, kr_str(",")), p);
}

char* compileLambda(char* tokens, char* pos, char* ntoks) {
    char* lname = kr_plus(kr_str("_krlam"), pos);
    char* p = kr_plus(pos, kr_str("2"));
    char* lparams = kr_str("");
    char* lpc = kr_str("0");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RPAREN")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, p)), kr_str("ID")))) {
            if (kr_truthy(kr_gt(lpc, kr_str("0")))) {
                lparams = kr_plus(lparams, kr_str(","));
            }
            lparams = kr_plus(lparams, ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, p)));
            lpc = kr_plus(lpc, kr_str("1"));
        }
        p = kr_plus(p, kr_str("1"));
    }
    p = kr_plus(p, kr_str("1"));
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("ARROW")))) {
        p = kr_plus(p, kr_str("2"));
    }
    char* bp = ((char*(*)(char*,char*))skipBlock)(tokens, p);
    char* lfv2 = ((char*(*)(char*,char*,char*,char*))findFreeVars)(tokens, kr_sub(p, kr_str("1")), bp, lparams);
    char* lfvc2 = kr_str("0");
    if (kr_truthy(kr_gt(kr_len(lfv2), kr_str("0")))) {
        lfvc2 = kr_linecount(lfv2);
    }
    char* captureCode = kr_str("");
    char* lfvi3 = kr_str("0");
    while (kr_truthy(kr_lt(lfvi3, lfvc2))) {
        char* fvn3 = ((char*(*)(char*))cIdent)(kr_split(lfv2, lfvi3));
        captureCode = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(captureCode, kr_str("_krlam")), pos), kr_str("_")), ((char*(*)(char*))cIdent)(fvn3)), kr_str(" = ")), ((char*(*)(char*))cIdent)(fvn3)), kr_str("; "));
        lfvi3 = kr_plus(lfvi3, kr_str("1"));
    }
    if (kr_truthy(kr_gt(kr_len(captureCode), kr_str("0")))) {
        char* cc = kr_trim(captureCode);
        char* ccExpr = kr_trim(kr_replace(cc, kr_str(";"), kr_str("")));
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("("), ccExpr), kr_str(", (char*)&")), lname), kr_str("),")), bp);
    } else {
        return kr_plus(kr_plus(kr_plus(kr_str("(char*)&"), lname), kr_str(",")), bp);
    }
}

char* compileListLiteral(char* tokens, char* pos, char* ntoks) {
    char* p = kr_plus(pos, kr_str("1"));
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RBRACK")))) {
        return kr_plus(kr_plus(kr_str("kr_str(\"\")"), kr_str(",")), kr_plus(p, kr_str("1")));
    }
    char* elems = kr_str("");
    char* ec = kr_str("0");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RBRACK")))) {
        if (kr_truthy(kr_gt(ec, kr_str("0")))) {
            p = kr_plus(p, kr_str("1"));
        }
        char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
        char* ecode = ((char*(*)(char*))pairVal)(ep);
        p = ((char*(*)(char*))pairPos)(ep);
        if (kr_truthy(kr_gt(ec, kr_str("0")))) {
            elems = kr_plus(kr_plus(elems, kr_str("\n")), ecode);
        } else {
            elems = ecode;
        }
        ec = kr_plus(ec, kr_str("1"));
    }
    p = kr_plus(p, kr_str("1"));
    if (kr_truthy(kr_eq(ec, kr_str("1")))) {
        return kr_plus(kr_plus(elems, kr_str(",")), p);
    }
    char* result = kr_getline(elems, kr_str("0"));
    char* ei = kr_str("1");
    while (kr_truthy(kr_lt(ei, ec))) {
        char* elem = kr_getline(elems, ei);
        result = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_cat(kr_cat("), result), kr_str(", kr_str(\",\")), ")), elem), kr_str(")"));
        ei = kr_plus(ei, kr_str("1"));
    }
    return kr_plus(kr_plus(result, kr_str(",")), p);
}

char* compileInterp(char* s) {
    char* parts = kr_str("");
    char* pc = kr_str("0");
    char* i = kr_str("0");
    char* seg = kr_str("");
    while (kr_truthy(kr_lt(i, kr_len(s)))) {
        if (kr_truthy(kr_eq(kr_idx(s, kr_atoi(i)), kr_str("{")))) {
            if (kr_truthy(kr_gt(kr_len(seg), kr_str("0")))) {
                char* escaped = ((char*(*)(char*))cEscape)(seg);
                if (kr_truthy(kr_gt(pc, kr_str("0")))) {
                    parts = kr_plus(kr_plus(kr_plus(parts, kr_str("\n")), kr_str("L:")), escaped);
                } else {
                    parts = kr_plus(kr_str("L:"), escaped);
                }
                pc = kr_plus(pc, kr_str("1"));
                seg = kr_str("");
            }
            i = kr_plus(i, kr_str("1"));
            char* expr = kr_str("");
            while (kr_truthy((kr_truthy(kr_lt(i, kr_len(s))) && kr_truthy(kr_neq(kr_idx(s, kr_atoi(i)), kr_str("}"))) ? kr_str("1") : kr_str("0")))) {
                expr = kr_plus(expr, kr_idx(s, kr_atoi(i)));
                i = kr_plus(i, kr_str("1"));
            }
            i = kr_plus(i, kr_str("1"));
            if (kr_truthy(kr_gt(pc, kr_str("0")))) {
                parts = kr_plus(kr_plus(kr_plus(parts, kr_str("\n")), kr_str("E:")), expr);
            } else {
                parts = kr_plus(kr_str("E:"), expr);
            }
            pc = kr_plus(pc, kr_str("1"));
        } else {
            seg = kr_plus(seg, kr_idx(s, kr_atoi(i)));
            i = kr_plus(i, kr_str("1"));
        }
    }
    if (kr_truthy(kr_gt(kr_len(seg), kr_str("0")))) {
        char* escaped = ((char*(*)(char*))cEscape)(seg);
        if (kr_truthy(kr_gt(pc, kr_str("0")))) {
            parts = kr_plus(kr_plus(kr_plus(parts, kr_str("\n")), kr_str("L:")), escaped);
        } else {
            parts = kr_plus(kr_str("L:"), escaped);
        }
        pc = kr_plus(pc, kr_str("1"));
    }
    if (kr_truthy(kr_eq(pc, kr_str("0")))) {
        return kr_str("kr_str(\"\")");
    }
    char* result = kr_str("");
    char* j = kr_str("0");
    while (kr_truthy(kr_lt(j, pc))) {
        char* part = kr_getline(parts, j);
        char* ptype = kr_substr(part, kr_str("0"), kr_str("2"));
        char* pval = kr_substr(part, kr_str("2"), kr_len(part));
        char* cpart = kr_str("");
        if (kr_truthy(kr_eq(ptype, kr_str("L:")))) {
            cpart = kr_plus(kr_plus(kr_str("kr_str(\""), pval), kr_str("\")"));
        } else {
            char* exprToks = ((char*(*)(char*))tokenize)(pval);
            char* exprNtoks = kr_linecount(exprToks);
            if (kr_truthy(kr_gt(exprNtoks, kr_str("0")))) {
                char* ep = ((char*(*)(char*,char*,char*))compileExpr)(exprToks, kr_str("0"), exprNtoks);
                cpart = ((char*(*)(char*))pairVal)(ep);
            } else {
                cpart = kr_str("kr_str(\"\")");
            }
        }
        if (kr_truthy(kr_eq(j, kr_str("0")))) {
            result = cpart;
        } else {
            result = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("kr_cat("), result), kr_str(", ")), cpart), kr_str(")"));
        }
        j = kr_plus(j, kr_str("1"));
    }
    return result;
}

char* compileStructDecl(char* tokens, char* pos, char* ntoks, char* depth) {
    char* name = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* p = kr_plus(pos, kr_str("1"));
    p = kr_plus(p, kr_str("1"));
    char* fields = kr_str("");
    char* fc = kr_str("0");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RBRACE")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("KW:let")))) {
            char* fname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, kr_str("1"))));
            if (kr_truthy(kr_gt(fc, kr_str("0")))) {
                fields = kr_plus(kr_plus(fields, kr_str(",")), fname);
            } else {
                fields = fname;
            }
            fc = kr_plus(fc, kr_str("1"));
            p = kr_plus(p, kr_str("2"));
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("COLON")))) {
                p = kr_plus(p, kr_str("2"));
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("LBRACK")))) {
                    char* sfd = kr_str("1");
                    p = kr_plus(p, kr_str("1"));
                    while (kr_truthy(kr_gt(sfd, kr_str("0")))) {
                        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("LBRACK")))) {
                            sfd = kr_plus(sfd, kr_str("1"));
                        }
                        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RBRACK")))) {
                            sfd = kr_sub(sfd, kr_str("1"));
                        }
                        p = kr_plus(p, kr_str("1"));
                    }
                }
            }
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("ASSIGN")))) {
                char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, kr_plus(p, kr_str("1")), ntoks);
                p = ((char*(*)(char*))pairPos)(ep);
            }
        } else {
            p = kr_plus(p, kr_str("1"));
        }
    }
    p = kr_plus(p, kr_str("1"));
    char* cname = ((char*(*)(char*))cIdent)(name);
    char* out = kr_plus(kr_plus(kr_str("typedef struct "), cname), kr_str("_s {\n"));
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, fc))) {
        char* fld = ((char*(*)(char*,char*))getNthParam)(fields, i);
        out = kr_plus(kr_plus(kr_plus(out, kr_str("    char* ")), ((char*(*)(char*))cIdent)(fld)), kr_str(";\n"));
        i = kr_plus(i, kr_str("1"));
    }
    out = kr_plus(kr_plus(kr_plus(out, kr_str("} ")), cname), kr_str("_t;\n\n"));
    out = kr_plus(kr_plus(kr_plus(out, kr_str("static char* ")), cname), kr_str("() {\n"));
    out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, kr_str("    ")), cname), kr_str("_t* _s = (")), cname), kr_str("_t*)_alloc(sizeof(")), cname), kr_str("_t));\n"));
    char* i2 = kr_str("0");
    while (kr_truthy(kr_lt(i2, fc))) {
        char* fld2 = ((char*(*)(char*,char*))getNthParam)(fields, i2);
        out = kr_plus(kr_plus(kr_plus(out, kr_str("    _s->")), ((char*(*)(char*))cIdent)(fld2)), kr_str(" = _K_EMPTY;\n"));
        i2 = kr_plus(i2, kr_str("1"));
    }
    out = kr_plus(out, kr_str("    return (char*)_s;\n"));
    out = kr_plus(out, kr_str("}\n\n"));
    return kr_plus(kr_plus(out, kr_str(",")), p);
}

char* compileFieldAssign(char* tokens, char* pos, char* ntoks, char* depth) {
    char* objName = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* field = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("2"))));
    char* p = kr_plus(pos, kr_str("4"));
    char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
    char* ecode = ((char*(*)(char*))pairVal)(ep);
    p = ((char*(*)(char*))pairPos)(ep);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
        p = kr_plus(p, kr_str("1"));
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), kr_str("kr_setfield(")), ((char*(*)(char*))cIdent)(objName)), kr_str(", \"")), field), kr_str("\", ")), ecode), kr_str(");\n,")), p);
}

char* compileStructLiteral(char* tokens, char* pos, char* ntoks) {
    char* name = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* cname = ((char*(*)(char*))cIdent)(name);
    char* p = kr_plus(pos, kr_str("2"));
    char* fields = kr_str("");
    char* vals = kr_str("");
    char* fc = kr_str("0");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RBRACE")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, p)), kr_str("ID")))) {
            char* fname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, p));
            p = kr_plus(p, kr_str("2"));
            char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
            char* ecode = ((char*(*)(char*))pairVal)(ep);
            p = ((char*(*)(char*))pairPos)(ep);
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("COMMA")))) {
                p = kr_plus(p, kr_str("1"));
            }
            if (kr_truthy(kr_gt(fc, kr_str("0")))) {
                fields = kr_plus(kr_plus(fields, kr_str(",")), fname);
                vals = kr_plus(kr_plus(vals, ecode), kr_str("\n"));
            } else {
                fields = fname;
                vals = kr_plus(ecode, kr_str("\n"));
            }
            fc = kr_plus(fc, kr_str("1"));
        } else {
            p = kr_plus(p, kr_str("1"));
        }
    }
    p = kr_plus(p, kr_str("1"));
    char* out = kr_str("({ char* _sl = kr_structnew();");
    char* i3 = kr_str("0");
    while (kr_truthy(kr_lt(i3, fc))) {
        char* fn3 = ((char*(*)(char*,char*))getNthParam)(fields, i3);
        char* fv3 = kr_getline(vals, i3);
        out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, kr_str(" kr_setfield(_sl, \"")), fn3), kr_str("\", ")), fv3), kr_str(");"));
        i3 = kr_plus(i3, kr_str("1"));
    }
    out = kr_plus(out, kr_str(" _sl; })"));
    return kr_plus(kr_plus(out, kr_str(",")), p);
}

char* compileCompoundAssign(char* tokens, char* pos, char* ntoks, char* depth) {
    char* name = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* op = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("1")));
    char* p = kr_plus(pos, kr_str("2"));
    char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
    char* ecode = ((char*(*)(char*))pairVal)(ep);
    p = ((char*(*)(char*))pairPos)(ep);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
        p = kr_plus(p, kr_str("1"));
    }
    char* cname = ((char*(*)(char*))cIdent)(name);
    if (kr_truthy(kr_eq(op, kr_str("PLUSEQ")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), cname), kr_str(" = kr_plus(")), cname), kr_str(", ")), ecode), kr_str(");\n,")), p);
    }
    if (kr_truthy(kr_eq(op, kr_str("MINUSEQ")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), cname), kr_str(" = kr_sub(")), cname), kr_str(", ")), ecode), kr_str(");\n,")), p);
    }
    if (kr_truthy(kr_eq(op, kr_str("STAREQ")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), cname), kr_str(" = kr_mul(")), cname), kr_str(", ")), ecode), kr_str(");\n,")), p);
    }
    if (kr_truthy(kr_eq(op, kr_str("SLASHEQ")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), cname), kr_str(" = kr_div(")), cname), kr_str(", ")), ecode), kr_str(");\n,")), p);
    }
    if (kr_truthy(kr_eq(op, kr_str("MODEQ")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), cname), kr_str(" = kr_mod(")), cname), kr_str(", ")), ecode), kr_str(");\n,")), p);
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), cname), kr_str(" = ")), ecode), kr_str(";\n,")), p);
}

char* compileFor(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* varName = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* p = kr_plus(pos, kr_str("2"));
    char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
    char* collection = ((char*(*)(char*))pairVal)(ep);
    p = ((char*(*)(char*))pairPos)(ep);
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, p, ntoks, depth, inFunc);
    char* bcode = ((char*(*)(char*))pairVal)(bp);
    p = ((char*(*)(char*))pairPos)(bp);
    char* cvar = ((char*(*)(char*))cIdent)(varName);
    char* dstr = kr_plus(depth, kr_str(""));
    char* colVar = kr_plus(kr_str("_for_col_"), dstr);
    char* cntVar = kr_plus(kr_str("_for_cnt_"), dstr);
    char* idxVar = kr_plus(kr_str("_for_i_"), dstr);
    char* out = kr_plus(((char*(*)(char*))indent)(depth), kr_str("{\n"));
    out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*(*)(char*))indent)(kr_plus(depth, kr_str("1")))), kr_str("char* ")), colVar), kr_str(" = ")), collection), kr_str(";\n"));
    out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*(*)(char*))indent)(kr_plus(depth, kr_str("1")))), kr_str("int ")), cntVar), kr_str(" = kr_listlen(")), colVar), kr_str(");\n"));
    out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*(*)(char*))indent)(kr_plus(depth, kr_str("1")))), kr_str("for (int ")), idxVar), kr_str(" = 0; ")), idxVar), kr_str(" < ")), cntVar), kr_str("; ")), idxVar), kr_str("++) {\n"));
    out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*(*)(char*))indent)(kr_plus(depth, kr_str("2")))), kr_str("char* ")), cvar), kr_str(" = kr_split(")), colVar), kr_str(", kr_itoa(")), idxVar), kr_str("));\n"));
    out = kr_plus(out, bcode);
    out = kr_plus(kr_plus(out, ((char*(*)(char*))indent)(kr_plus(depth, kr_str("1")))), kr_str("}\n"));
    out = kr_plus(kr_plus(out, ((char*(*)(char*))indent)(depth)), kr_str("}\n"));
    return kr_plus(kr_plus(out, kr_str(",")), p);
}

char* compileMatch(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, pos, ntoks);
    char* mexpr = ((char*(*)(char*))pairVal)(ep);
    char* p = ((char*(*)(char*))pairPos)(ep);
    p = kr_plus(p, kr_str("1"));
    char* out = kr_plus(((char*(*)(char*))indent)(depth), kr_str("{\n"));
    out = kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*(*)(char*))indent)(kr_plus(depth, kr_str("1")))), kr_str("char* _match_val = ")), mexpr), kr_str(";\n"));
    char* first = kr_str("1");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RBRACE")))) {
        char* ct = ((char*(*)(char*,char*))tokAt)(tokens, p);
        if (kr_truthy(kr_eq(ct, kr_str("KW:else")))) {
            p = kr_plus(p, kr_str("1"));
            char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, p, ntoks, kr_plus(depth, kr_str("1")), inFunc);
            char* bcode = ((char*(*)(char*))pairVal)(bp);
            p = ((char*(*)(char*))pairPos)(bp);
            if (kr_truthy(kr_eq(first, kr_str("1")))) {
                out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*(*)(char*))indent)(kr_plus(depth, kr_str("1")))), kr_str("{\n")), bcode), ((char*(*)(char*))indent)(kr_plus(depth, kr_str("1")))), kr_str("}\n"));
            } else {
                out = kr_plus(kr_plus(kr_plus(kr_plus(out, kr_str(" else {\n")), bcode), ((char*(*)(char*))indent)(kr_plus(depth, kr_str("1")))), kr_str("}\n"));
            }
        } else {
            char* vp = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
            char* vcode = ((char*(*)(char*))pairVal)(vp);
            p = ((char*(*)(char*))pairPos)(vp);
            char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, p, ntoks, kr_plus(depth, kr_str("1")), inFunc);
            char* bcode = ((char*(*)(char*))pairVal)(bp);
            p = ((char*(*)(char*))pairPos)(bp);
            if (kr_truthy(kr_eq(first, kr_str("1")))) {
                out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, ((char*(*)(char*))indent)(kr_plus(depth, kr_str("1")))), kr_str("if (strcmp(_match_val, ")), vcode), kr_str(") == 0) {\n")), bcode), ((char*(*)(char*))indent)(kr_plus(depth, kr_str("1")))), kr_str("}"));
                first = kr_str("0");
            } else {
                out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, kr_str(" else if (strcmp(_match_val, ")), vcode), kr_str(") == 0) {\n")), bcode), ((char*(*)(char*))indent)(kr_plus(depth, kr_str("1")))), kr_str("}"));
            }
        }
    }
    p = kr_plus(p, kr_str("1"));
    out = kr_plus(kr_plus(kr_plus(out, kr_str("\n")), ((char*(*)(char*))indent)(depth)), kr_str("}\n"));
    return kr_plus(kr_plus(out, kr_str(",")), p);
}

char* compileDoWhile(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, pos, ntoks, depth, inFunc);
    char* bcode = ((char*(*)(char*))pairVal)(bp);
    char* p = ((char*(*)(char*))pairPos)(bp);
    p = kr_plus(p, kr_str("1"));
    char* cp = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
    char* cond = ((char*(*)(char*))pairVal)(cp);
    p = ((char*(*)(char*))pairPos)(cp);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
        p = kr_plus(p, kr_str("1"));
    }
    char* out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), kr_str("do {\n")), bcode), ((char*(*)(char*))indent)(depth)), kr_str("} while (kr_truthy(")), cond), kr_str("));\n"));
    return kr_plus(kr_plus(out, kr_str(",")), p);
}

char* compileLoop(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, pos, ntoks, depth, inFunc);
    char* bcode = ((char*(*)(char*))pairVal)(bp);
    char* p = ((char*(*)(char*))pairPos)(bp);
    p = kr_plus(p, kr_str("1"));
    char* cp = ((char*(*)(char*,char*,char*))compileExpr)(tokens, p, ntoks);
    char* cond = ((char*(*)(char*))pairVal)(cp);
    p = ((char*(*)(char*))pairPos)(cp);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
        p = kr_plus(p, kr_str("1"));
    }
    char* out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), kr_str("do {\n")), bcode), ((char*(*)(char*))indent)(depth)), kr_str("} while (!kr_truthy(")), cond), kr_str("));\n"));
    return kr_plus(kr_plus(out, kr_str(",")), p);
}

char* compileExprStmt(char* tokens, char* pos, char* ntoks, char* depth) {
    char* ep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, pos, ntoks);
    char* ecode = ((char*(*)(char*))pairVal)(ep);
    char* p = ((char*(*)(char*))pairPos)(ep);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
        p = kr_plus(p, kr_str("1"));
    }
    return kr_plus(kr_plus(kr_plus(((char*(*)(char*))indent)(depth), ecode), kr_str(";\n,")), p);
}

char* compileBlock(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* p = kr_plus(pos, kr_str("1"));
    char* code = kr_sbnew();
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RBRACE")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
            p = kr_plus(p, kr_str("1"));
        } else {
            char* sp = ((char*(*)(char*,char*,char*,char*,char*))compileStmt)(tokens, p, ntoks, kr_plus(depth, kr_str("1")), inFunc);
            char* sCode = ((char*(*)(char*))pairVal)(sp);
            p = ((char*(*)(char*))pairPos)(sp);
            code = kr_sbappend(code, sCode);
        }
    }
    p = kr_plus(p, kr_str("1"));
    return kr_plus(kr_plus(kr_sbtostring(code), kr_str(",")), p);
}

char* hoistLambdas(char* code) {
    char* hoisted = kr_sbnew();
    char* clean = kr_sbnew();
    char* i = kr_str("0");
    char* clen = kr_len(code);
    while (kr_truthy(kr_lt(i, clen))) {
        if (kr_truthy((kr_truthy(kr_lte(kr_plus(i, kr_str("6")), clen)) && kr_truthy(kr_eq(kr_substr(code, i, kr_plus(i, kr_str("6"))), kr_str("/*LS*/"))) ? kr_str("1") : kr_str("0")))) {
            char* le = kr_indexof(kr_substr(code, kr_plus(i, kr_str("6")), clen), kr_str("/*LE*/"));
            if (kr_truthy(kr_gte(kr_toint(le), kr_str("0")))) {
                char* bodyStart = kr_plus(i, kr_str("6"));
                char* bodyEnd = kr_plus(bodyStart, kr_toint(le));
                char* leEnd = kr_plus(bodyEnd, kr_str("6"));
                hoisted = kr_sbappend(hoisted, kr_plus(kr_substr(code, bodyStart, bodyEnd), kr_str("\n")));
                i = leEnd;
            } else {
                clean = kr_sbappend(clean, kr_idx(code, kr_atoi(i)));
                i = kr_plus(i, kr_str("1"));
            }
        } else {
            clean = kr_sbappend(clean, kr_idx(code, kr_atoi(i)));
            i = kr_plus(i, kr_str("1"));
        }
    }
    return kr_plus(kr_plus(kr_sbtostring(hoisted), kr_str("/*SPLIT*/")), kr_sbtostring(clean));
}

char* compileFunc(char* tokens, char* pos, char* ntoks) {
    char* nameTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("1")));
    char* fname = ((char*(*)(char*))tokVal)(nameTok);
    char* p = kr_plus(pos, kr_str("3"));
    char* params = kr_str("");
    char* pnames = kr_str("");
    char* pc = kr_str("0");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RPAREN")))) {
        char* pt = ((char*(*)(char*,char*))tokAt)(tokens, p);
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(pt), kr_str("ID")))) {
            char* pname = ((char*(*)(char*))cIdent)(((char*(*)(char*))tokVal)(pt));
            if (kr_truthy(kr_gt(pc, kr_str("0")))) {
                params = kr_plus(kr_plus(params, kr_str(", char* ")), pname);
                pnames = kr_plus(kr_plus(pnames, kr_str(",")), pname);
            } else {
                params = kr_plus(kr_str("char* "), pname);
                pnames = pname;
            }
            pc = kr_plus(pc, kr_str("1"));
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, kr_str("1"))), kr_str("COLON")))) {
                p = kr_plus(p, kr_str("3"));
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("LBRACK")))) {
                    char* td = kr_str("1");
                    p = kr_plus(p, kr_str("1"));
                    while (kr_truthy(kr_gt(td, kr_str("0")))) {
                        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("LBRACK")))) {
                            td = kr_plus(td, kr_str("1"));
                        }
                        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RBRACK")))) {
                            td = kr_sub(td, kr_str("1"));
                        }
                        p = kr_plus(p, kr_str("1"));
                    }
                }
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("COMMA")))) {
                    p = kr_plus(p, kr_str("1"));
                }
            } else {
                p = kr_plus(p, kr_str("1"));
            }
        } else {
            p = kr_plus(p, kr_str("1"));
        }
    }
    p = kr_plus(p, kr_str("1"));
    char* fnRetType = kr_str("");
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("ARROW")))) {
        fnRetType = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, kr_str("1"))));
        p = kr_plus(p, kr_str("2"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("LBRACK")))) {
            char* rd = kr_str("1");
            p = kr_plus(p, kr_str("1"));
            while (kr_truthy(kr_gt(rd, kr_str("0")))) {
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("LBRACK")))) {
                    rd = kr_plus(rd, kr_str("1"));
                }
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RBRACK")))) {
                    rd = kr_sub(rd, kr_str("1"));
                }
                p = kr_plus(p, kr_str("1"));
            }
        }
    }
    char* fnInFunc = kr_str("1");
    if (kr_truthy(kr_eq(fnRetType, kr_str("int")))) {
        fnInFunc = kr_str("int");
    }
    if (kr_truthy(kr_eq(fnRetType, kr_str("bool")))) {
        fnInFunc = kr_str("int");
    }
    if (kr_truthy(kr_eq(fnRetType, kr_str("zero")))) {
        fnInFunc = kr_str("zero");
    }
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, p, ntoks, kr_str("0"), fnInFunc);
    char* bcode = ((char*(*)(char*))pairVal)(bp);
    p = ((char*(*)(char*))pairPos)(bp);
    char* wrapParams = params;
    if (kr_truthy(kr_eq(pc, kr_str("0")))) {
        wrapParams = kr_str("void");
    }
    char* out = kr_str("");
    if (kr_truthy(kr_eq(fnRetType, kr_str("zero")))) {
        char* vbody = kr_replace(bcode, kr_str("return _K_EMPTY;\n"), kr_str(""));
        vbody = kr_replace(vbody, kr_str("return _K_ZERO;\n"), kr_str(""));
        vbody = kr_replace(vbody, kr_str("return _K_ONE;\n"), kr_str(""));
        char* innerName = kr_plus(kr_str("_krv_"), ((char*(*)(char*))cIdent)(fname));
        out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("static void "), innerName), kr_str("(")), wrapParams), kr_str(") {\n")), vbody), kr_str("}\n"));
        out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, kr_str("char* ")), ((char*(*)(char*))cIdent)(fname)), kr_str("(")), wrapParams), kr_str(") { ")), innerName), kr_str("(")), pnames), kr_str("); return _K_EMPTY; }\n\n"));
    } else if (kr_truthy(kr_eq(fnRetType, kr_str("int")))) {
        char* innerName = kr_plus(kr_str("_kri_"), ((char*(*)(char*))cIdent)(fname));
        out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("static int "), innerName), kr_str("(")), wrapParams), kr_str(") {\n")), bcode), kr_str("}\n"));
        out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, kr_str("char* ")), ((char*(*)(char*))cIdent)(fname)), kr_str("(")), wrapParams), kr_str(") { return kr_itoa(")), innerName), kr_str("(")), pnames), kr_str(")); }\n\n"));
    } else if (kr_truthy(kr_eq(fnRetType, kr_str("bool")))) {
        char* innerName = kr_plus(kr_str("_krb_"), ((char*(*)(char*))cIdent)(fname));
        out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("static int "), innerName), kr_str("(")), wrapParams), kr_str(") {\n")), bcode), kr_str("}\n"));
        out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(out, kr_str("char* ")), ((char*(*)(char*))cIdent)(fname)), kr_str("(")), wrapParams), kr_str(") { return ")), innerName), kr_str("(")), pnames), kr_str(") ? _K_ONE : _K_ZERO; }\n\n"));
    } else {
        out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("char* "), ((char*(*)(char*))cIdent)(fname)), kr_str("(")), params), kr_str(") {\n")), bcode), kr_str("}\n\n"));
    }
    return kr_plus(kr_plus(out, kr_str(",")), p);
}

char* compileCallbackFunc(char* tokens, char* pos, char* ntoks) {
    char* nameTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("1")));
    char* fname = ((char*(*)(char*))tokVal)(nameTok);
    char* p = kr_plus(pos, kr_str("3"));
    char* params = kr_str("");
    char* pc = kr_str("0");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RPAREN")))) {
        char* pt = ((char*(*)(char*,char*))tokAt)(tokens, p);
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(pt), kr_str("ID")))) {
            if (kr_truthy(kr_gt(pc, kr_str("0")))) {
                params = kr_plus(kr_plus(params, kr_str(", char* ")), ((char*(*)(char*))cIdent)(((char*(*)(char*))tokVal)(pt)));
            } else {
                params = kr_plus(kr_str("char* "), ((char*(*)(char*))cIdent)(((char*(*)(char*))tokVal)(pt)));
            }
            pc = kr_plus(pc, kr_str("1"));
            p = kr_plus(p, kr_str("1"));
        } else {
            p = kr_plus(p, kr_str("1"));
        }
    }
    p = kr_plus(p, kr_str("1"));
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("ARROW")))) {
        p = kr_plus(p, kr_str("2"));
    }
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, p, ntoks, kr_str("0"), kr_str("1"));
    char* bcode = ((char*(*)(char*))pairVal)(bp);
    p = ((char*(*)(char*))pairPos)(bp);
    char* bodyStripped = kr_replace(bcode, kr_str("return _K_EMPTY;\n"), kr_str(""));
    bodyStripped = kr_replace(bodyStripped, kr_str("return _K_ZERO;\n"), kr_str(""));
    bodyStripped = kr_replace(bodyStripped, kr_str("return _K_ONE;\n"), kr_str(""));
    char* out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("void "), ((char*(*)(char*))cIdent)(fname)), kr_str("(")), params), kr_str(") {\n")), bodyStripped), kr_str("}\n\n"));
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
    r = kr_sbappend(r, kr_str("#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <time.h>\n#include <ctype.h>\n#include <stdarg.h>\n#include <stdint.h>\n#if defined(_WIN32) || defined(_WIN64)\n#include <string.h>\n#else\n#include <strings.h>\n#define _stricmp strcasecmp\n#endif\n\nstatic int _argc; static char** _argv;\n\ntypedef struct ABlock { struct ABlock* next; int cap; int used; } ABlock;\n"));
    r = kr_sbappend(r, kr_str("static ABlock* _arena = 0;\nstatic char* _alloc(int n) {\n    n = (n + 7) & ~7;\n    if (!_arena || _arena->used + n > _arena->cap) {\n        int cap = 64*1024*1024;\n        if (n > cap) cap = n;\n        ABlock* b = (ABlock*)malloc(sizeof(ABlock) + cap);\n"));
    r = kr_sbappend(r, kr_str("        if (!b) { fprintf(stderr, \"out of memory\\n\"); exit(1); }\n"));
    r = kr_sbappend(r, kr_str("        b->cap = cap; b->used = 0; b->next = _arena; _arena = b;\n    }\n    char* p = (char*)(_arena + 1) + _arena->used;\n    _arena->used += n;\n    return p;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char _K_EMPTY[] = \"\";\nstatic char _K_ZERO[] = \"0\";\nstatic char _K_ONE[] = \"1\";\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_str(const char* s) {\n    if (!s[0]) return _K_EMPTY;\n    if (s[0] == '0' && !s[1]) return _K_ZERO;\n    if (s[0] == '1' && !s[1]) return _K_ONE;\n    int n = (int)strlen(s) + 1;\n    char* p = _alloc(n);\n    memcpy(p, s, n);\n    return p;\n"));
    r = kr_sbappend(r, kr_str("}\n\nstatic char* kr_cat(const char* a, const char* b) {\n    int la = (int)strlen(a), lb = (int)strlen(b);\n    char* p = _alloc(la + lb + 1);\n    memcpy(p, a, la);\n    memcpy(p + la, b, lb + 1);\n    return p;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static int kr_isnum(const char* s) {\n    if (!*s) return 0;\n    const char* p = s;\n    if (*p == '-') p++;\n    if (!*p) return 0;\n    while (*p) { if (*p < '0' || *p > '9') return 0; p++; }\n    return 1;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_itoa(int v) {\n    if (v == 0) return _K_ZERO;\n    if (v == 1) return _K_ONE;\n    char buf[32];\n    snprintf(buf, sizeof(buf), \"%d\", v);\n    return kr_str(buf);\n}\n\nstatic int kr_atoi(const char* s) { return atoi(s); }\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_plus(const char* a, const char* b) {\n    if (kr_isnum(a) && kr_isnum(b))\n        return kr_itoa(atoi(a) + atoi(b));\n    return kr_cat(a, b);\n}\n\nstatic char* kr_sub(const char* a, const char* b) { return kr_itoa(atoi(a) - atoi(b)); }\nstatic char* kr_mul(const char* a, const char* b) { return kr_itoa(atoi(a) * atoi(b)); }\nstatic char* kr_div(const char* a, const char* b) { return kr_itoa(atoi(a) / atoi(b)); }\n"));
    r = kr_sbappend(r, kr_str("static char* kr_mod(const char* a, const char* b) { return kr_itoa(atoi(a) % atoi(b)); }\nstatic char* kr_neg(const char* a) { return kr_itoa(-atoi(a)); }\nstatic char* kr_not(const char* a) { return atoi(a) ? _K_ZERO : _K_ONE; }\n\nstatic char* kr_eq(const char* a, const char* b) {\n    return strcmp(a, b) == 0 ? _K_ONE : _K_ZERO;\n}\nstatic char* kr_neq(const char* a, const char* b) {\n    return strcmp(a, b) != 0 ? _K_ONE : _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("}\nstatic char* kr_lt(const char* a, const char* b) {\n    if (kr_isnum(a) && kr_isnum(b)) return atoi(a) < atoi(b) ? _K_ONE : _K_ZERO;\n    return strcmp(a, b) < 0 ? _K_ONE : _K_ZERO;\n}\nstatic char* kr_gt(const char* a, const char* b) {\n    if (kr_isnum(a) && kr_isnum(b)) return atoi(a) > atoi(b) ? _K_ONE : _K_ZERO;\n    return strcmp(a, b) > 0 ? _K_ONE : _K_ZERO;\n"));
    r = kr_sbappend(r, kr_str("}\nstatic char* kr_lte(const char* a, const char* b) {\n    return kr_gt(a, b) == _K_ZERO ? _K_ONE : _K_ZERO;\n}\nstatic char* kr_gte(const char* a, const char* b) {\n    return kr_lt(a, b) == _K_ZERO ? _K_ONE : _K_ZERO;\n}\n\nstatic int kr_truthy(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    if (!s || !*s) return 0;\n    if (strcmp(s, \"0\") == 0) return 0;\n    return 1;\n}\n\nstatic char* kr_print(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    printf(\"%s\\n\", s);\n"));
    r = kr_sbappend(r, kr_str("    return _K_EMPTY;\n}\n\nstatic char* kr_len(const char* s) { return kr_itoa((int)strlen(s)); }\n\nstatic char* kr_idx(const char* s, int i) {\n    char buf[2] = {s[i], 0};\n    return kr_str(buf);\n}\n\nstatic char* kr_split(const char* s, const char* idxs) {\n"));
    r = kr_sbappend(r, kr_str("    int idx = atoi(idxs);\n    int count = 0;\n    const char* start = s;\n    const char* p = s;\n    while (*p) {\n        if (*p == ',') {\n            if (count == idx) {\n                int len = (int)(p - start);\n"));
    r = kr_sbappend(r, kr_str("                char* r = _alloc(len + 1);\n                memcpy(r, start, len);\n                r[len] = 0;\n                return r;\n            }\n            count++;\n            start = p + 1;\n        }\n"));
    r = kr_sbappend(r, kr_str("        p++;\n    }\n    if (count == idx) return kr_str(start);\n    return kr_str(\"\");\n}\n\nstatic char* kr_startswith(const char* s, const char* prefix) {\n    return strncmp(s, prefix, strlen(prefix)) == 0 ? _K_ONE : _K_ZERO;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_substr(const char* s, const char* starts, const char* ends) {\n    int st = atoi(starts), en = atoi(ends);\n    int slen = (int)strlen(s);\n    if (st >= slen) return kr_str(\"\");\n    if (en > slen) en = slen;\n    int n = en - st;\n    if (n <= 0) return kr_str(\"\");\n    char* r = _alloc(n + 1);\n"));
    r = kr_sbappend(r, kr_str("    memcpy(r, s + st, n);\n    r[n] = 0;\n    return r;\n}\n\nstatic char* kr_toint(const char* s) { return kr_itoa(atoi(s)); }\n\nstatic char* kr_exec(const char* cmd) {\n    char* buf=_alloc(8192); buf[0]=0;\n#ifdef _WIN32\n    FILE* p=_popen(cmd,\"r\");\n#else\n    FILE* p=popen(cmd,\"r\");\n#endif\n    if(!p) return buf;\n    int pos=0,ch;\n    while(pos<8191&&(ch=fgetc(p))!=EOF) buf[pos++]=(char)ch;\n    buf[pos]=0;\n#ifdef _WIN32\n    _pclose(p);\n#else\n    pclose(p);\n#endif\n    while(pos>0&&(buf[pos-1]==13||buf[pos-1]==10||buf[pos-1]==32)) buf[--pos]=0;\n    return buf;\n}\n\n\n\nstatic char* kr_readfile(const char* path) {\n    FILE* f = fopen(path, \"rb\");\n    if (!f) return kr_str(\"\");\n"));
    r = kr_sbappend(r, kr_str("    fseek(f, 0, SEEK_END);\n    long sz = ftell(f);\n    fseek(f, 0, SEEK_SET);\n    char* buf = _alloc((int)sz + 1);\n    fread(buf, 1, sz, f);\n    buf[sz] = 0;\n    fclose(f);\n    return buf;\n"));
    r = kr_sbappend(r, kr_str("}\n\nstatic char* kr_arg(const char* idxs) {\n    int idx = atoi(idxs) + 1;\n    if (idx < _argc) return kr_str(_argv[idx]);\n    return kr_str(\"\");\n}\n\nstatic char* kr_argcount() {\n    return kr_itoa(_argc - 1);\n"));
    r = kr_sbappend(r, kr_str("}\n\nstatic char* kr_getline(const char* s, const char* idxs) {\n"));
    r = kr_sbappend(r, kr_str("    int idx = atoi(idxs);\n    static const char* _gl_s = 0;\n    static int _gl_idx = 0;\n    static const char* _gl_start = 0;\n"));
    r = kr_sbappend(r, kr_str("    const char* start; int cur;\n    if (s == _gl_s && _gl_start && idx >= _gl_idx) {\n        start = _gl_start; cur = _gl_idx;\n    } else {\n        start = s; cur = 0; _gl_s = s; _gl_start = s; _gl_idx = 0;\n    }\n"));
    r = kr_sbappend(r, kr_str("    const char* p = start;\n    while (*p) {\n        if (*p == '\\n') {\n            if (cur == idx) {\n                int len = (int)(p - start);\n                char* r = _alloc(len + 1);\n                memcpy(r, start, len); r[len] = 0;\n"));
    r = kr_sbappend(r, kr_str("                _gl_s = s; _gl_idx = idx; _gl_start = start;\n                return r;\n            }\n            cur++; start = p + 1;\n        }\n        p++;\n    }\n    if (cur == idx) { _gl_s = s; _gl_idx = idx; _gl_start = start; return kr_str(start); }\n    return kr_str(\"\");\n}\n\nstatic char* kr_linecount(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    if (!*s) return kr_str(\"0\");\n    int count = 1;\n    const char* p = s;\n"));
    r = kr_sbappend(r, kr_str("    while (*p) { if (*p == '\\n') count++; p++; }\n"));
    r = kr_sbappend(r, kr_str("    if (*(p - 1) == '\\n') count--;\n"));
    r = kr_sbappend(r, kr_str("    return kr_itoa(count);\n}\n\nstatic char* kr_count(const char* s) {\n    return kr_linecount(s);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_writefile(const char* path, const char* data) {\n    FILE* f = fopen(path, \"wb\");\n    if (!f) return _K_ZERO;\n    fwrite(data, 1, strlen(data), f);\n    fclose(f);\n    return _K_ONE;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static int _krhex(char c){if(c>='0'&&c<='9')return c-'0';if(c>='a'&&c<='f')return c-'a'+10;if(c>='A'&&c<='F')return c-'A'+10;return -1;}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_writebytes(const char* path, const char* hexstr) {\n    FILE* f = fopen(path, \"wb\");\n    if (!f) return _K_ZERO;\n    const char* p = hexstr;\n    while (*p) {\n        if (*p == 'x' && p[1] && p[2]) {\n            int hi = _krhex(p[1]), lo = _krhex(p[2]);\n            if (hi >= 0 && lo >= 0) { unsigned char b = (unsigned char)(hi*16+lo); fwrite(&b,1,1,f); }\n            p += 3;\n        } else { p++; }\n    }\n    fclose(f);\n    return _K_ONE;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_shellrun(const char* cmd){int r=system(cmd);return kr_itoa(r);}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_deletefile(const char* path){remove(path);return _K_EMPTY;}\n"));
    r = kr_sbappend(r, kr_str("static char* exec(const char* cmd){return kr_exec(cmd);}\n"));
    r = kr_sbappend(r, kr_str("static char* shellRun(const char* cmd){return kr_shellrun(cmd);}\n"));
    r = kr_sbappend(r, kr_str("static char* deleteFile(const char* path){return kr_deletefile(path);}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_input() {\n    char buf[4096];\n    if (!fgets(buf, sizeof(buf), stdin)) return _K_EMPTY;\n    int len = (int)strlen(buf);\n"));
    r = kr_sbappend(r, kr_str("    if (len > 0 && buf[len-1] == '\\n') buf[--len] = 0;\n"));
    r = kr_sbappend(r, kr_str("    if (len > 0 && buf[len-1] == '\\r') buf[--len] = 0;\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(buf);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_indexof(const char* s, const char* sub) {\n    const char* p = strstr(s, sub);\n    if (!p) return kr_itoa(-1);\n    return kr_itoa((int)(p - s));\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_replace(const char* s, const char* old, const char* rep) {\n    int slen = (int)strlen(s), olen = (int)strlen(old), rlen = (int)strlen(rep);\n    if (olen == 0) return kr_str(s);\n    int count = 0;\n    const char* p = s;\n    while ((p = strstr(p, old)) != 0) { count++; p += olen; }\n    int nlen = slen + count * (rlen - olen);\n    char* out = _alloc(nlen + 1);\n"));
    r = kr_sbappend(r, kr_str("    char* dst = out;\n    p = s;\n    while (*p) {\n        if (strncmp(p, old, olen) == 0) {\n            memcpy(dst, rep, rlen); dst += rlen; p += olen;\n        } else { *dst++ = *p++; }\n    }\n    *dst = 0;\n"));
    r = kr_sbappend(r, kr_str("    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_charat(const char* s, const char* idxs) {\n    int i = atoi(idxs);\n    int slen = (int)strlen(s);\n    if (i < 0 || i >= slen) return _K_EMPTY;\n    char buf[2] = {s[i], 0};\n    return kr_str(buf);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_trim(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    while (*s == ' ' || *s == '\\t' || *s == '\\n' || *s == '\\r') s++;\n"));
    r = kr_sbappend(r, kr_str("    int len = (int)strlen(s);\n"));
    r = kr_sbappend(r, kr_str("    while (len > 0 && (s[len-1]==' '||s[len-1]=='\\t'||s[len-1]=='\\n'||s[len-1]=='\\r')) len--;\n"));
    r = kr_sbappend(r, kr_str("    char* r = _alloc(len + 1);\n    memcpy(r, s, len);\n    r[len] = 0;\n    return r;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_tolower(const char* s) {\n    int len = (int)strlen(s);\n    char* out = _alloc(len + 1);\n    for (int i = 0; i <= len; i++)\n        out[i] = (s[i] >= 'A' && s[i] <= 'Z') ? s[i] + 32 : s[i];\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_toupper(const char* s) {\n    int len = (int)strlen(s);\n    char* out = _alloc(len + 1);\n    for (int i = 0; i <= len; i++)\n        out[i] = (s[i] >= 'a' && s[i] <= 'z') ? s[i] - 32 : s[i];\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_contains(const char* s, const char* sub) {\n    return strstr(s, sub) ? _K_ONE : _K_ZERO;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_endswith(const char* s, const char* suffix) {\n    int slen = (int)strlen(s), suflen = (int)strlen(suffix);\n    if (suflen > slen) return _K_ZERO;\n    return strcmp(s + slen - suflen, suffix) == 0 ? _K_ONE : _K_ZERO;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_abs(const char* a) { int v = atoi(a); return kr_itoa(v < 0 ? -v : v); }\nstatic char* kr_min(const char* a, const char* b) { return atoi(a) <= atoi(b) ? kr_str(a) : kr_str(b); }\nstatic char* kr_max(const char* a, const char* b) { return atoi(a) >= atoi(b) ? kr_str(a) : kr_str(b); }\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_exit(const char* code) { exit(atoi(code)); return _K_EMPTY; }\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_type(const char* s) {\n    if (kr_isnum(s)) return kr_str(\"number\");\n    return kr_str(\"string\");\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_append(const char* lst, const char* item) {\n    if (!*lst) return kr_str(item);\n    return kr_cat(kr_cat(lst, \",\"), item);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_join(const char* lst, const char* sep) {\n    int llen = (int)strlen(lst), slen = (int)strlen(sep);\n    int rlen = 0;\n    for (int i = 0; i < llen; i++) {\n        if (lst[i] == ',') rlen += slen; else rlen++;\n    }\n    char* out = _alloc(rlen + 1);\n    int j = 0;\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < llen; i++) {\n        if (lst[i] == ',') { memcpy(out+j, sep, slen); j += slen; }\n        else { out[j++] = lst[i]; }\n    }\n    out[j] = 0;\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_reverse(const char* lst) {\n    int cnt = 0;\n    const char* p = lst;\n    while (*p) { if (*p == ',') cnt++; p++; }\n    cnt++;\n    char* out = _K_EMPTY;\n    for (int i = cnt - 1; i >= 0; i--) {\n        char* item = kr_split(lst, kr_itoa(i));\n"));
    r = kr_sbappend(r, kr_str("        if (i == cnt - 1) out = item;\n        else out = kr_cat(kr_cat(out, \",\"), item);\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static int _kr_cmp(const void* a, const void* b) {\n    const char* sa = *(const char**)a;\n    const char* sb = *(const char**)b;\n    if (kr_isnum(sa) && kr_isnum(sb)) return atoi(sa) - atoi(sb);\n    return strcmp(sa, sb);\n}\nstatic char* kr_sort(const char* lst) {\n    if (!*lst) return _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("    int cnt = 1;\n    const char* p = lst;\n    while (*p) { if (*p == ',') cnt++; p++; }\n    char** arr = (char**)_alloc(cnt * sizeof(char*));\n    for (int i = 0; i < cnt; i++) arr[i] = kr_split(lst, kr_itoa(i));\n    qsort(arr, cnt, sizeof(char*), _kr_cmp);\n    char* out = arr[0];\n    for (int i = 1; i < cnt; i++) out = kr_cat(kr_cat(out, \",\"), arr[i]);\n"));
    r = kr_sbappend(r, kr_str("    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_keys(const char* map) {\n    if (!*map) return _K_EMPTY;\n    int cnt = 1;\n    const char* p = map;\n    while (*p) { if (*p == ',') cnt++; p++; }\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i += 2) {\n        char* k = kr_split(map, kr_itoa(i));\n"));
    r = kr_sbappend(r, kr_str("        if (first) { out = k; first = 0; }\n        else out = kr_cat(kr_cat(out, \",\"), k);\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_values(const char* map) {\n    if (!*map) return _K_EMPTY;\n    int cnt = 1;\n    const char* p = map;\n    while (*p) { if (*p == ',') cnt++; p++; }\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 1; i < cnt; i += 2) {\n        char* v = kr_split(map, kr_itoa(i));\n"));
    r = kr_sbappend(r, kr_str("        if (first) { out = v; first = 0; }\n        else out = kr_cat(kr_cat(out, \",\"), v);\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_haskey(const char* map, const char* key) {\n    if (!*map) return _K_ZERO;\n    int cnt = 1;\n    const char* p = map;\n    while (*p) { if (*p == ',') cnt++; p++; }\n    for (int i = 0; i < cnt; i += 2) {\n        if (strcmp(kr_split(map, kr_itoa(i)), key) == 0) return _K_ONE;\n    }\n"));
    r = kr_sbappend(r, kr_str("    return _K_ZERO;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_remove(const char* lst, const char* item) {\n    if (!*lst) return _K_EMPTY;\n    int cnt = 1;\n    const char* p = lst;\n    while (*p) { if (*p == ',') cnt++; p++; }\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i++) {\n        char* el = kr_split(lst, kr_itoa(i));\n"));
    r = kr_sbappend(r, kr_str("        if (strcmp(el, item) != 0) {\n            if (first) { out = el; first = 0; }\n            else out = kr_cat(kr_cat(out, \",\"), el);\n        }\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_repeat(const char* s, const char* ns) {\n    int n = atoi(ns);\n    if (n <= 0) return _K_EMPTY;\n    int slen = (int)strlen(s);\n    char* out = _alloc(slen * n + 1);\n    for (int i = 0; i < n; i++) memcpy(out + i * slen, s, slen);\n    out[slen * n] = 0;\n    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_format(const char* fmt, const char* arg) {\n    char buf[4096];\n    const char* p = strstr(fmt, \"{}\");\n    if (!p) return kr_str(fmt);\n    int pre = (int)(p - fmt);\n    int alen = (int)strlen(arg);\n    int postlen = (int)strlen(p + 2);\n    if (pre + alen + postlen >= 4096) return kr_str(fmt);\n"));
    r = kr_sbappend(r, kr_str("    memcpy(buf, fmt, pre);\n    memcpy(buf + pre, arg, alen);\n    memcpy(buf + pre + alen, p + 2, postlen + 1);\n    return kr_str(buf);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_parseint(const char* s) {\n    const char* p = s;\n"));
    r = kr_sbappend(r, kr_str("    while (*p == ' ' || *p == '\\t') p++;\n"));
    r = kr_sbappend(r, kr_str("    if (!*p) return _K_ZERO;\n    return kr_itoa(atoi(p));\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_tostr(const char* s) { return kr_str(s); }\n\n"));
    r = kr_sbappend(r, kr_str("static int kr_listlen(const char* s) {\n    if (!*s) return 0;\n    int cnt = 1;\n    while (*s) { if (*s == ',') cnt++; s++; }\n    return cnt;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_range(const char* starts, const char* ends) {\n    int s = atoi(starts), e = atoi(ends);\n    if (s >= e) return _K_EMPTY;\n    char* out = kr_itoa(s);\n    for (int i = s + 1; i < e; i++) out = kr_cat(kr_cat(out, \",\"), kr_itoa(i));\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_pow(const char* bs, const char* es) {\n    int b = atoi(bs), e = atoi(es), r = 1;\n    for (int i = 0; i < e; i++) r *= b;\n    return kr_itoa(r);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_sqrt(const char* s) {\n    int v = atoi(s);\n    if (v <= 0) return _K_ZERO;\n    int r = 0;\n    while ((r + 1) * (r + 1) <= v) r++;\n    return kr_itoa(r);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_sign(const char* s) {\n    int v = atoi(s);\n    if (v > 0) return _K_ONE;\n    if (v < 0) return kr_str(\"-1\");\n    return _K_ZERO;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_clamp(const char* vs, const char* los, const char* his) {\n    int v = atoi(vs), lo = atoi(los), hi = atoi(his);\n    if (v < lo) return kr_str(los);\n    if (v > hi) return kr_str(his);\n    return kr_str(vs);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_padleft(const char* s, const char* ws, const char* pad) {\n    int w = atoi(ws), slen = (int)strlen(s), plen = (int)strlen(pad);\n    if (slen >= w || plen == 0) return kr_str(s);\n    int need = w - slen;\n    char* out = _alloc(w + 1);\n    for (int i = 0; i < need; i++) out[i] = pad[i % plen];\n    memcpy(out + need, s, slen + 1);\n    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_padright(const char* s, const char* ws, const char* pad) {\n    int w = atoi(ws), slen = (int)strlen(s), plen = (int)strlen(pad);\n    if (slen >= w || plen == 0) return kr_str(s);\n    int need = w - slen;\n    char* out = _alloc(w + 1);\n    memcpy(out, s, slen);\n    for (int i = 0; i < need; i++) out[slen + i] = pad[i % plen];\n    out[w] = 0;\n"));
    r = kr_sbappend(r, kr_str("    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_charcode(const char* s) {\n    if (!*s) return _K_ZERO;\n    return kr_itoa((unsigned char)s[0]);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_fromcharcode(const char* ns) {\n    char buf[2] = {(char)atoi(ns), 0};\n    return kr_str(buf);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_slice(const char* lst, const char* starts, const char* ends) {\n    int cnt = kr_listlen(lst);\n    int s = atoi(starts), e = atoi(ends);\n    if (s < 0) s = cnt + s;\n    if (e < 0) e = cnt + e;\n    if (s < 0) s = 0;\n    if (e > cnt) e = cnt;\n    if (s >= e) return _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("    char* out = kr_split(lst, kr_itoa(s));\n    for (int i = s + 1; i < e; i++)\n        out = kr_cat(kr_cat(out, \",\"), kr_split(lst, kr_itoa(i)));\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_length(const char* lst) {\n    return kr_itoa(kr_listlen(lst));\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_unique(const char* lst) {\n    if (!*lst) return _K_EMPTY;\n    int cnt = kr_listlen(lst);\n    char* out = _K_EMPTY; int oc = 0;\n    for (int i = 0; i < cnt; i++) {\n        char* item = kr_split(lst, kr_itoa(i));\n        int dup = 0;\n        for (int j = 0; j < oc; j++) {\n"));
    r = kr_sbappend(r, kr_str("            if (strcmp(kr_split(out, kr_itoa(j)), item) == 0) { dup = 1; break; }\n        }\n        if (!dup) {\n            if (oc == 0) out = item; else out = kr_cat(kr_cat(out, \",\"), item);\n            oc++;\n        }\n    }\n    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_printerr(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    fprintf(stderr, \"%s\\n\", s);\n"));
    r = kr_sbappend(r, kr_str("    return _K_EMPTY;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_readline(const char* prompt) {\n    if (*prompt) printf(\"%s\", prompt);\n    fflush(stdout);\n    char buf[4096];\n    if (!fgets(buf, sizeof(buf), stdin)) return _K_EMPTY;\n    int len = (int)strlen(buf);\n"));
    r = kr_sbappend(r, kr_str("    if (len > 0 && buf[len-1] == '\\n') buf[--len] = 0;\n"));
    r = kr_sbappend(r, kr_str("    if (len > 0 && buf[len-1] == '\\r') buf[--len] = 0;\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(buf);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_assert(const char* cond, const char* msg) {\n    if (!kr_truthy(cond)) {\n"));
    r = kr_sbappend(r, kr_str("        fprintf(stderr, \"ASSERTION FAILED: %s\\n\", msg);\n"));
    r = kr_sbappend(r, kr_str("        exit(1);\n    }\n    return _K_ONE;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_splitby(const char* s, const char* delim) {\n    int slen = (int)strlen(s), dlen = (int)strlen(delim);\n    if (dlen == 0 || slen == 0) return kr_str(s);\n    char* out = _K_EMPTY; int first = 1;\n    const char* p = s;\n    while (*p) {\n        const char* f = strstr(p, delim);\n        if (!f) { \n"));
    r = kr_sbappend(r, kr_str("            if (first) out = kr_str(p); else out = kr_cat(kr_cat(out, \",\"), kr_str(p));\n            break;\n        }\n        int n = (int)(f - p);\n        char* chunk = _alloc(n + 1);\n        memcpy(chunk, p, n); chunk[n] = 0;\n        if (first) { out = chunk; first = 0; }\n        else out = kr_cat(kr_cat(out, \",\"), chunk);\n"));
    r = kr_sbappend(r, kr_str("        p = f + dlen;\n        if (!*p) { out = kr_cat(kr_cat(out, \",\"), _K_EMPTY); break; }\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_listindexof(const char* lst, const char* item) {\n    if (!*lst) return kr_itoa(-1);\n    int cnt = kr_listlen(lst);\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(kr_split(lst, kr_itoa(i)), item) == 0) return kr_itoa(i);\n    }\n    return kr_itoa(-1);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_insertat(const char* lst, const char* idxs, const char* item) {\n    int idx = atoi(idxs);\n    int cnt = kr_listlen(lst);\n    if (!*lst && idx == 0) return kr_str(item);\n    if (idx < 0) idx = 0;\n    if (idx >= cnt) return kr_cat(kr_cat(lst, \",\"), item);\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i++) {\n"));
    r = kr_sbappend(r, kr_str("        if (i == idx) {\n            if (first) { out = kr_str(item); first = 0; }\n            else out = kr_cat(kr_cat(out, \",\"), item);\n        }\n        char* el = kr_split(lst, kr_itoa(i));\n        if (first) { out = el; first = 0; }\n        else out = kr_cat(kr_cat(out, \",\"), el);\n    }\n"));
    r = kr_sbappend(r, kr_str("    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_removeat(const char* lst, const char* idxs) {\n    int idx = atoi(idxs);\n    int cnt = kr_listlen(lst);\n    if (idx < 0 || idx >= cnt) return kr_str(lst);\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i++) {\n        if (i == idx) continue;\n        char* el = kr_split(lst, kr_itoa(i));\n"));
    r = kr_sbappend(r, kr_str("        if (first) { out = el; first = 0; }\n        else out = kr_cat(kr_cat(out, \",\"), el);\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_replaceat(const char* lst, const char* idxs, const char* val) {\n    int idx = atoi(idxs);\n    int cnt = kr_listlen(lst);\n    if (idx < 0 || idx >= cnt) return kr_str(lst);\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i++) {\n        char* el = (i == idx) ? (char*)val : kr_split(lst, kr_itoa(i));\n        if (first) { out = el; first = 0; }\n"));
    r = kr_sbappend(r, kr_str("        else out = kr_cat(kr_cat(out, \",\"), el);\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_fill(const char* ns, const char* val) {\n    int n = atoi(ns);\n    if (n <= 0) return _K_EMPTY;\n    char* out = kr_str(val);\n    for (int i = 1; i < n; i++) out = kr_cat(kr_cat(out, \",\"), val);\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_zip(const char* a, const char* b) {\n    int ac = kr_listlen(a), bc = kr_listlen(b);\n    int mc = ac < bc ? ac : bc;\n    if (!*a || !*b) return _K_EMPTY;\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < mc; i++) {\n        char* ai = kr_split(a, kr_itoa(i));\n        char* bi = kr_split(b, kr_itoa(i));\n"));
    r = kr_sbappend(r, kr_str("        if (first) { out = kr_cat(kr_cat(ai, \",\"), bi); first = 0; }\n        else { out = kr_cat(kr_cat(out, \",\"), kr_cat(kr_cat(ai, \",\"), bi)); }\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_every(const char* lst, const char* val) {\n    if (!*lst) return _K_ONE;\n    int cnt = kr_listlen(lst);\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(kr_split(lst, kr_itoa(i)), val) != 0) return _K_ZERO;\n    }\n    return _K_ONE;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_some(const char* lst, const char* val) {\n    if (!*lst) return _K_ZERO;\n    int cnt = kr_listlen(lst);\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(kr_split(lst, kr_itoa(i)), val) == 0) return _K_ONE;\n    }\n    return _K_ZERO;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_countof(const char* lst, const char* item) {\n    if (!*lst) return _K_ZERO;\n    int cnt = kr_listlen(lst), c = 0;\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(kr_split(lst, kr_itoa(i)), item) == 0) c++;\n    }\n    return kr_itoa(c);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_sumlist(const char* lst) {\n    if (!*lst) return _K_ZERO;\n    int cnt = kr_listlen(lst), s = 0;\n    for (int i = 0; i < cnt; i++) s += atoi(kr_split(lst, kr_itoa(i)));\n    return kr_itoa(s);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_maxlist(const char* lst) {\n    if (!*lst) return _K_ZERO;\n    int cnt = kr_listlen(lst);\n    int m = atoi(kr_split(lst, _K_ZERO));\n    for (int i = 1; i < cnt; i++) {\n        int v = atoi(kr_split(lst, kr_itoa(i)));\n        if (v > m) m = v;\n    }\n"));
    r = kr_sbappend(r, kr_str("    return kr_itoa(m);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_minlist(const char* lst) {\n    if (!*lst) return _K_ZERO;\n    int cnt = kr_listlen(lst);\n    int m = atoi(kr_split(lst, _K_ZERO));\n    for (int i = 1; i < cnt; i++) {\n        int v = atoi(kr_split(lst, kr_itoa(i)));\n        if (v < m) m = v;\n    }\n"));
    r = kr_sbappend(r, kr_str("    return kr_itoa(m);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_hex(const char* s) {\n    int v = atoi(s);\n    char buf[32];\n    snprintf(buf, sizeof(buf), \"%x\", v < 0 ? -v : v);\n    if (v < 0) return kr_cat(\"-\", kr_str(buf));\n    return kr_str(buf);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_bin(const char* s) {\n    int v = atoi(s);\n    if (v == 0) return _K_ZERO;\n    int neg = v < 0; if (neg) v = -v;\n    char buf[64]; int i = 63; buf[i] = 0;\n    while (v > 0) { buf[--i] = '0' + (v & 1); v >>= 1; }\n    if (neg) return kr_cat(\"-\", kr_str(&buf[i]));\n    return kr_str(&buf[i]);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("typedef struct EnvEntry { char* name; char* value; struct EnvEntry* prev; } EnvEntry;\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_envnew() { return (char*)0; }\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_envset(char* envp, const char* name, const char* val) {\n    EnvEntry* e = (EnvEntry*)_alloc(sizeof(EnvEntry));\n    e->name = (char*)name;\n    e->value = (char*)val;\n    e->prev = (EnvEntry*)envp;\n    return (char*)e;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_envget(char* envp, const char* name) {\n    EnvEntry* e = (EnvEntry*)envp;\n    while (e) {\n        if (strcmp(e->name, name) == 0) return e->value;\n        e = e->prev;\n    }\n    if (strcmp(name, \"__argOffset\") != 0)\n"));
    r = kr_sbappend(r, kr_str("        fprintf(stderr, \"ERROR: undefined variable: %s\\n\", name);\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(\"\");\n}\n\n"));
    r = kr_sbappend(r, kr_str("typedef struct ResultStruct { char tag; char* val; char* env; int pos; } ResultStruct;\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_makeresult(const char* tag, const char* val, const char* env, const char* pos) {\n    ResultStruct* r = (ResultStruct*)_alloc(sizeof(ResultStruct));\n    r->tag = tag[0];\n    r->val = (char*)val;\n    r->env = (char*)env;\n    r->pos = atoi(pos);\n    return (char*)r;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_getresulttag(const char* r) {\n    char buf[2] = {((ResultStruct*)r)->tag, 0};\n    return kr_str(buf);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_getresultval(const char* r) {\n    return ((ResultStruct*)r)->val;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_getresultenv(const char* r) {\n    return ((ResultStruct*)r)->env;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_getresultpos(const char* r) {\n    return kr_itoa(((ResultStruct*)r)->pos);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_istruthy(const char* s) {\n    if (!s || !*s || strcmp(s, \"0\") == 0 || strcmp(s, \"false\") == 0)\n        return _K_ZERO;\n    return _K_ONE;\n}\n\n"));
    r = kr_sbappend(r, kr_str("typedef struct { int cap; int len; } SBHdr;\n#define MAX_SBS 4096\nstatic SBHdr* _sb_table[MAX_SBS];\nstatic int _sb_count = 0;\n\nstatic char* kr_sbnew() {\n    int initcap = 65536;\n    SBHdr* h = (SBHdr*)malloc(sizeof(SBHdr) + initcap);\n    h->cap = initcap;\n"));
    r = kr_sbappend(r, kr_str("    h->len = 0;\n    ((char*)(h + 1))[0] = 0;\n    _sb_table[_sb_count] = h;\n    return kr_itoa(_sb_count++);\n}\n\nstatic char* kr_sbappend(const char* handle, const char* s) {\n    int idx = atoi(handle);\n    SBHdr* h = _sb_table[idx];\n"));
    r = kr_sbappend(r, kr_str("    int slen = (int)strlen(s);\n    while (h->len + slen + 1 > h->cap) {\n        int newcap = h->cap * 2;\n        h = (SBHdr*)realloc(h, sizeof(SBHdr) + newcap);\n        h->cap = newcap;\n    }\n    memcpy((char*)(h + 1) + h->len, s, slen);\n    h->len += slen;\n"));
    r = kr_sbappend(r, kr_str("    ((char*)(h + 1))[h->len] = 0;\n    _sb_table[idx] = h;\n    return kr_str(handle);\n}\n\nstatic char* kr_sbtostring(const char* handle) {\n    int idx = atoi(handle);\n    SBHdr* h = _sb_table[idx];\n    return (char*)(h + 1);\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("#include <setjmp.h>\n#define _KR_TRY_MAX 256\nstatic jmp_buf _kr_try_stack[_KR_TRY_MAX];\nstatic char*   _kr_err_stack[_KR_TRY_MAX];\nstatic int     _kr_try_depth = 0;\n\nstatic jmp_buf* _kr_pushtry() {\n    _kr_err_stack[_kr_try_depth] = _K_EMPTY;\n    return &_kr_try_stack[_kr_try_depth++];\n"));
    r = kr_sbappend(r, kr_str("}\n\nstatic char* _kr_poptry() {\n    if (_kr_try_depth > 0) _kr_try_depth--;\n    return _kr_err_stack[_kr_try_depth];\n}\n\nstatic char* _kr_throw(const char* msg) {\n    if (_kr_try_depth > 0) {\n        _kr_err_stack[_kr_try_depth - 1] = (char*)msg;\n"));
    r = kr_sbappend(r, kr_str("        longjmp(_kr_try_stack[_kr_try_depth - 1], 1);\n    }\n"));
    r = kr_sbappend(r, kr_str("    fprintf(stderr, \"Uncaught exception: %s\\n\", msg);\n"));
    r = kr_sbappend(r, kr_str("    exit(1);\n    return _K_EMPTY;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_strreverse(const char* s) {\n    int n = (int)strlen(s);\n    char* out = _alloc(n + 1);\n    for (int i = 0; i < n; i++) out[i] = s[n - 1 - i];\n    out[n] = 0;\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_words(const char* s) {\n    if (!*s) return _K_EMPTY;\n    char* out = _K_EMPTY; int first = 1;\n    const char* p = s;\n"));
    r = kr_sbappend(r, kr_str("    while (*p == ' ' || *p == '\\t') p++;\n"));
    r = kr_sbappend(r, kr_str("    const char* start = p;\n    while (1) {\n"));
    r = kr_sbappend(r, kr_str("        if (*p == ' ' || *p == '\\t' || *p == 0) {\n"));
    r = kr_sbappend(r, kr_str("            if (p > start) {\n                int n = (int)(p - start);\n                char* w = _alloc(n + 1);\n                memcpy(w, start, n); w[n] = 0;\n                if (first) { out = w; first = 0; }\n                else out = kr_cat(kr_cat(out, \",\"), w);\n            }\n            if (!*p) break;\n"));
    r = kr_sbappend(r, kr_str("            while (*p == ' ' || *p == '\\t') p++;\n"));
    r = kr_sbappend(r, kr_str("            start = p;\n        } else { p++; }\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_lines(const char* s) {\n    if (!*s) return _K_EMPTY;\n    char* out = _K_EMPTY; int first = 1;\n    const char* p = s, *start = s;\n    while (1) {\n"));
    r = kr_sbappend(r, kr_str("        if (*p == '\\n' || *p == 0) {\n"));
    r = kr_sbappend(r, kr_str("            int n = (int)(p - start);\n"));
    r = kr_sbappend(r, kr_str("            if (n > 0 && start[n-1] == '\\r') n--;\n"));
    r = kr_sbappend(r, kr_str("            char* ln = _alloc(n + 1);\n            memcpy(ln, start, n); ln[n] = 0;\n            if (first) { out = ln; first = 0; }\n            else out = kr_cat(kr_cat(out, \",\"), ln);\n            if (!*p) break;\n            start = p + 1;\n        }\n        p++;\n"));
    r = kr_sbappend(r, kr_str("    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_first(const char* lst) { return kr_split(lst, _K_ZERO); }\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_last(const char* lst) {\n    int cnt = kr_listlen(lst);\n    if (cnt == 0) return _K_EMPTY;\n    return kr_split(lst, kr_itoa(cnt - 1));\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_head(const char* lst, const char* ns) {\n    int n = atoi(ns), cnt = kr_listlen(lst);\n    if (n <= 0 || !*lst) return _K_EMPTY;\n    if (n >= cnt) return kr_str(lst);\n    char* out = kr_split(lst, _K_ZERO);\n    for (int i = 1; i < n; i++) out = kr_cat(kr_cat(out, \",\"), kr_split(lst, kr_itoa(i)));\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_tail(const char* lst, const char* ns) {\n    int n = atoi(ns), cnt = kr_listlen(lst);\n    if (n <= 0 || !*lst) return _K_EMPTY;\n    if (n >= cnt) return kr_str(lst);\n    int start = cnt - n;\n    char* out = kr_split(lst, kr_itoa(start));\n    for (int i = start + 1; i < cnt; i++) out = kr_cat(kr_cat(out, \",\"), kr_split(lst, kr_itoa(i)));\n    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_lstrip(const char* s) {\n"));
    r = kr_sbappend(r, kr_str("    while (*s == ' ' || *s == '\\t' || *s == '\\n' || *s == '\\r') s++;\n"));
    r = kr_sbappend(r, kr_str("    return kr_str(s);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_rstrip(const char* s) {\n    int len = (int)strlen(s);\n"));
    r = kr_sbappend(r, kr_str("    while (len > 0 && (s[len-1]==' '||s[len-1]=='\\t'||s[len-1]=='\\n'||s[len-1]=='\\r')) len--;\n"));
    r = kr_sbappend(r, kr_str("    char* r = _alloc(len + 1);\n    memcpy(r, s, len); r[len] = 0;\n    return r;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_center(const char* s, const char* ws, const char* pad) {\n    int w = atoi(ws), slen = (int)strlen(s), plen = (int)strlen(pad);\n    if (slen >= w || plen == 0) return kr_str(s);\n    int total = w - slen;\n    int left = total / 2, right = total - left;\n    char* out = _alloc(w + 1);\n    for (int i = 0; i < left; i++) out[i] = pad[i % plen];\n    memcpy(out + left, s, slen);\n"));
    r = kr_sbappend(r, kr_str("    for (int i = 0; i < right; i++) out[left + slen + i] = pad[i % plen];\n    out[w] = 0;\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_isalpha(const char* s) {\n    if (!*s) return _K_ZERO;\n    for (const char* p = s; *p; p++) if (!isalpha((unsigned char)*p)) return _K_ZERO;\n    return _K_ONE;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_isdigit(const char* s) {\n    if (!*s) return _K_ZERO;\n    for (const char* p = s; *p; p++) if (!isdigit((unsigned char)*p)) return _K_ZERO;\n    return _K_ONE;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_isspace(const char* s) {\n    if (!*s) return _K_ZERO;\n    for (const char* p = s; *p; p++) if (!isspace((unsigned char)*p)) return _K_ZERO;\n    return _K_ONE;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_random(const char* ns) {\n    int n = atoi(ns);\n    if (n <= 0) return _K_ZERO;\n    return kr_itoa(rand() % n);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_timestamp() {\n    return kr_itoa((int)time(NULL));\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_environ(const char* name) {\n    const char* v = getenv(name);\n    if (!v) return _K_EMPTY;\n    return kr_str(v);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_floor(const char* s) { return kr_itoa((int)atoi(s)); }\nstatic char* kr_ceil(const char* s)  { return kr_itoa((int)atoi(s)); }\nstatic char* kr_round(const char* s) { return kr_itoa((int)atoi(s)); }\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_throw(const char* msg) { return _kr_throw(msg); }\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_structnew() {\n    // 2 slots for count + up to 32 fields (name+val pairs)\n    char** s = (char**)_alloc(66 * sizeof(char*));\n    s[0] = _K_ZERO; // field count\n    return (char*)s;\n}\n\nstatic char* kr_setfield(char* obj, const char* name, const char* val) {\n    char** s = (char**)obj;\n"));
    r = kr_sbappend(r, kr_str("    int cnt = atoi(s[0]);\n    // search for existing field\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(s[1 + i*2], name) == 0) {\n            s[2 + i*2] = (char*)val;\n            return obj;\n        }\n    }\n"));
    r = kr_sbappend(r, kr_str("    // add new field\n    s[1 + cnt*2] = (char*)name;\n    s[2 + cnt*2] = (char*)val;\n    s[0] = kr_itoa(cnt + 1);\n    return obj;\n}\n\nstatic char* kr_getfield(char* obj, const char* name) {\n    if (!obj) return _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("    char** s = (char**)obj;\n    int cnt = atoi(s[0]);\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(s[1 + i*2], name) == 0) return s[2 + i*2];\n    }\n    return _K_EMPTY;\n}\n\nstatic char* kr_hasfield(char* obj, const char* name) {\n"));
    r = kr_sbappend(r, kr_str("    if (!obj) return _K_ZERO;\n    char** s = (char**)obj;\n    int cnt = atoi(s[0]);\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(s[1 + i*2], name) == 0) return _K_ONE;\n    }\n    return _K_ZERO;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_structfields(char* obj) {\n    if (!obj) return _K_EMPTY;\n    char** s = (char**)obj;\n    int cnt = atoi(s[0]);\n    if (cnt == 0) return _K_EMPTY;\n    char* out = s[1];\n    for (int i = 1; i < cnt; i++) out = kr_cat(kr_cat(out, \",\"), s[1 + i*2]);\n    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_mapget(const char* map, const char* key) {\n    if (!*map) return _K_EMPTY;\n    int cnt = kr_listlen(map);\n    for (int i = 0; i < cnt - 1; i += 2) {\n        if (strcmp(kr_split(map, kr_itoa(i)), key) == 0)\n            return kr_split(map, kr_itoa(i + 1));\n    }\n    return _K_EMPTY;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_mapset(const char* map, const char* key, const char* val) {\n    if (!*map) return kr_cat(kr_cat(kr_str(key), \",\"), val);\n    int cnt = kr_listlen(map);\n    char* out = _K_EMPTY; int first = 1; int found = 0;\n    for (int i = 0; i < cnt - 1; i += 2) {\n        char* k = kr_split(map, kr_itoa(i));\n        char* v = (strcmp(k, key) == 0) ? (char*)val : kr_split(map, kr_itoa(i+1));\n        if (strcmp(k, key) == 0) found = 1;\n"));
    r = kr_sbappend(r, kr_str("        if (first) { out = kr_cat(k, kr_cat(\",\", v)); first = 0; }\n        else out = kr_cat(out, kr_cat(\",\", kr_cat(k, kr_cat(\",\", v))));\n    }\n    if (!found) {\n        if (first) out = kr_cat(kr_str(key), kr_cat(\",\", val));\n        else out = kr_cat(out, kr_cat(\",\", kr_cat(kr_str(key), kr_cat(\",\", val))));\n    }\n    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_mapdel(const char* map, const char* key) {\n    if (!*map) return _K_EMPTY;\n    int cnt = kr_listlen(map);\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt - 1; i += 2) {\n        char* k = kr_split(map, kr_itoa(i));\n        if (strcmp(k, key) != 0) {\n            char* v = kr_split(map, kr_itoa(i+1));\n"));
    r = kr_sbappend(r, kr_str("            if (first) { out = kr_cat(k, kr_cat(\",\", v)); first = 0; }\n            else out = kr_cat(out, kr_cat(\",\", kr_cat(k, kr_cat(\",\", v))));\n        }\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_sprintf(const char* fmt, ...) {\n    char buf[4096];\n    va_list args;\n    va_start(args, fmt);\n    vsnprintf(buf, sizeof(buf), fmt, args);\n    va_end(args);\n    return kr_str(buf);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_strsplit(const char* s, const char* delim) {\n    return kr_splitby(s, delim);\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_listmap(const char* lst, const char* prefix, const char* suffix) {\n    if (!*lst) return _K_EMPTY;\n    int cnt = kr_listlen(lst);\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i++) {\n        char* item = kr_split(lst, kr_itoa(i));\n        char* mapped = kr_cat(kr_cat(kr_str(prefix), item), suffix);\n        if (first) { out = mapped; first = 0; }\n"));
    r = kr_sbappend(r, kr_str("        else out = kr_cat(out, kr_cat(\",\", mapped));\n    }\n    return out;\n}\n\n"));
    r = kr_sbappend(r, kr_str("static char* kr_listfilter(const char* lst, const char* val) {\n    if (!*lst) return _K_EMPTY;\n    int cnt = kr_listlen(lst), negate = 0;\n    const char* match = val;\n    if (val[0] == '!') { negate = 1; match = val + 1; }\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i++) {\n        char* item = kr_split(lst, kr_itoa(i));\n"));
    r = kr_sbappend(r, kr_str("        int eq = (strcmp(item, match) == 0);\n        int keep = negate ? !eq : eq;\n        if (keep) {\n            if (first) { out = item; first = 0; }\n            else out = kr_cat(out, kr_cat(\",\", item));\n        }\n    }\n    return out;\n"));
    r = kr_sbappend(r, kr_str("}\n\n"));
    r = kr_sbappend(r, kr_str("#include <math.h>\nstatic char* kr_tofloat(const char* s) {\n    return s;\n}\n\nstatic char* kr_fadd(const char* a,const char* b){char buf[64];snprintf(buf,64,\"%g\",atof(a)+atof(b));return kr_str(buf);}\nstatic char* kr_fsub(const char* a,const char* b){char buf[64];snprintf(buf,64,\"%g\",atof(a)-atof(b));return kr_str(buf);}\nstatic char* kr_fmul(const char* a,const char* b){char buf[64];snprintf(buf,64,\"%g\",atof(a)*atof(b));return kr_str(buf);}\nstatic char* kr_fdiv(const char* a,const char* b){char buf[64];if(atof(b)==0.0)return kr_str(\"0\");snprintf(buf,64,\"%g\",atof(a)/atof(b));return kr_str(buf);}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_flt(const char* a,const char* b){return atof(a)<atof(b)?_K_ONE:_K_ZERO;}\nstatic char* kr_fgt(const char* a,const char* b){return atof(a)>atof(b)?_K_ONE:_K_ZERO;}\nstatic char* kr_feq(const char* a,const char* b){return atof(a)==atof(b)?_K_ONE:_K_ZERO;}\nstatic char* kr_fsqrt(const char* a) {\n    char buf[64]; snprintf(buf,64,\"%g\",sqrt(atof(a)));\n    return kr_str(buf);\n}\n\nstatic char* kr_ffloor(const char* a) {\n"));
    r = kr_sbappend(r, kr_str("    char buf[64]; snprintf(buf,64,\"%.0f\",floor(atof(a)));\n    return kr_str(buf);\n}\n\nstatic char* kr_fceil(const char* a) {\n    char buf[64]; snprintf(buf,64,\"%.0f\",ceil(atof(a)));\n    return kr_str(buf);\n}\n\nstatic char* kr_fround(const char* a) {\n"));
    r = kr_sbappend(r, kr_str("    char buf[64]; snprintf(buf,64,\"%.0f\",round(atof(a)));\n    return kr_str(buf);\n}\n\nstatic char* kr_fformat(const char* a,const char* prec){char fmt[32],buf[64];snprintf(fmt,32,\"%%.%sf\",prec);snprintf(buf,64,fmt,atof(a));return kr_str(buf);}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_bitand(const char* a,const char* b){return kr_itoa((int)((unsigned int)atoi(a)&(unsigned int)atoi(b)));}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_bitor(const char* a,const char* b){return kr_itoa((int)((unsigned int)atoi(a)|(unsigned int)atoi(b)));}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_bitxor(const char* a,const char* b){return kr_itoa((int)((unsigned int)atoi(a)^(unsigned int)atoi(b)));}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_bitnot(const char* a){return kr_itoa((int)(~(unsigned int)atoi(a)));}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_bitshl(const char* a,const char* b){return kr_itoa((int)((unsigned int)atoi(a)<<atoi(b)));}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_bitshr(const char* a,const char* b){return kr_itoa((int)((unsigned int)atoi(a)>>atoi(b)));}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_tolong(const char* s){char buf[32];snprintf(buf,32,\"%lld\",(long long)atoll(s));return kr_str(buf);}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_div64(const char* a,const char* b){if(atoll(b)==0)return kr_str(\"0\");char buf[32];snprintf(buf,32,\"%lld\",atoll(a)/atoll(b));return kr_str(buf);}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_mod64(const char* a,const char* b){if(atoll(b)==0)return kr_str(\"0\");char buf[32];long long r2=atoll(a)%atoll(b);snprintf(buf,32,\"%lld\",r2);return kr_str(buf);}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_mul64(const char* a,const char* b){char buf[32];snprintf(buf,32,\"%lld\",atoll(a)*atoll(b));return kr_str(buf);}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_add64(const char* a,const char* b){char buf[32];snprintf(buf,32,\"%lld\",atoll(a)+atoll(b));return kr_str(buf);}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_eqignorecase(const char* a,const char* b){return _stricmp(a,b)==0?kr_str(\"1\"):kr_str(\"0\");}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_handlevalid(const char* h){return (h!=NULL&&h!=(char*)(intptr_t)-1)?kr_str(\"1\"):kr_str(\"0\");}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_bufgetdword(char* buf){unsigned int v=*(unsigned int*)buf;return kr_itoa((int)v);}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_bufsetdword(char* buf,const char* vs){*(unsigned int*)buf=(unsigned int)atoi(vs);return _K_EMPTY;}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_bufgetword(char* buf){return kr_itoa((int)(*(unsigned short*)buf));}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_bufgetqword(char* buf){unsigned long long v=*(unsigned long long*)buf;char s[32];snprintf(s,32,\"%llu\",v);return kr_str(s);}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_bufgetdwordat(char* buf,const char* off){unsigned int v=*(unsigned int*)(buf+atoi(off));return kr_itoa((int)v);}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_bufgetqwordat(char* buf,const char* off){unsigned long long v=*(unsigned long long*)(buf+atoi(off));char s[32];snprintf(s,32,\"%llu\",v);return kr_str(s);}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_bufsetbyte(char* buf,const char* off,const char* val){buf[atoi(off)]=(unsigned char)atoi(val);return _K_EMPTY;}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_bufsetdwordat(char* buf,const char* off,const char* val){*(unsigned int*)(buf+atoi(off))=(unsigned int)atoll(val);return _K_EMPTY;}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_handleget(char* buf){return *(char**)buf;}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_handleint(char* ptr){char s[32];snprintf(s,32,\"%d\",(int)(intptr_t)ptr);return kr_str(s);}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_ptrderef(char* ptr){return *(char**)ptr;}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_ptrindex(char* ptr,const char* n){return ((char**)ptr)[atoi(n)];}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_callptr1(char* fn,char* a0){return ((char*(*)(char*))(fn))(a0);}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_callptr2(char* fn,char* a0,char* a1){return ((char*(*)(char*,char*))(fn))(a0,a1);}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_callptr3(char* fn,char* a0,char* a1,char* a2){return ((char*(*)(char*,char*,char*))(fn))(a0,a1,a2);}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_callptr4(char* fn,char* a0,char* a1,char* a2,char* a3){return ((char*(*)(char*,char*,char*,char*))(fn))(a0,a1,a2,a3);}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_mkclosure(const char* fn,const char* env){"));
    r = kr_sbappend(r, kr_str("int fl=strlen(fn),el=strlen(env);char* p=_alloc(fl+el+2);"));
    r = kr_sbappend(r, kr_str("memcpy(p,fn,fl);p[fl]='|';memcpy(p+fl+1,env,el+1);return p;}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_closure_fn(const char* c){"));
    r = kr_sbappend(r, kr_str("const char* p=strchr(c,'|');if(!p)return(char*)c;"));
    r = kr_sbappend(r, kr_str("int n=p-c;char* r2=_alloc(n+1);memcpy(r2,c,n);r2[n]=0;return r2;}\n"));
    r = kr_sbappend(r, kr_str("static char* kr_closure_env(const char* c){"));
    r = kr_sbappend(r, kr_str("const char* p=strchr(c,'|');return p?(char*)(p+1):(char*)_K_EMPTY;}\n"));
    return kr_sbtostring(r);
}

char* scanModuleFunctions(char* tokens, char* ntoks) {
    char* i = kr_str("0");
    char* bodyStart = kr_str("0");
    char* hasWrapper = kr_str("0");
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* tok = ((char*(*)(char*,char*))tokAt)(tokens, i);
        if (kr_truthy(kr_eq(tok, kr_str("KW:go")))) {
            if (kr_truthy(kr_lt(kr_plus(i, kr_str("2")), ntoks))) {
                if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, kr_str("1")))), kr_str("ID")))) {
                    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, kr_str("2"))), kr_str("LBRACE")))) {
                        bodyStart = kr_plus(i, kr_str("2"));
                        hasWrapper = kr_str("1");
                    }
                }
            }
        }
        i = kr_plus(i, kr_str("1"));
    }
    return ((char*(*)(char*,char*))scanFunctions)(tokens, ntoks);
}

char* compileImportedFunctions(char* tokens, char* ntoks, char* ftable) {
    char* sb = kr_sbnew();
    char* i = kr_str("0");
    char* inWrapper = kr_str("0");
    char* depth = kr_str("0");
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* tok = ((char*(*)(char*,char*))tokAt)(tokens, i);
        if (kr_truthy(kr_eq(tok, kr_str("KW:go")))) {
            if (kr_truthy(kr_lt(kr_plus(i, kr_str("2")), ntoks))) {
                if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, kr_str("1")))), kr_str("ID")))) {
                    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, kr_str("2"))), kr_str("LBRACE")))) {
                        i = kr_plus(i, kr_str("3"));
                        inWrapper = kr_str("1");
                    }
                }
            }
        }
        if (kr_truthy(kr_eq(tok, kr_str("KW:jxt")))) {
            i = ((char*(*)(char*,char*))skipBlock)(tokens, kr_plus(i, kr_str("1")));
        } else if (kr_truthy((kr_truthy(kr_eq(tok, kr_str("KW:func"))) || kr_truthy(kr_eq(tok, kr_str("KW:fn"))) ? kr_str("1") : kr_str("0")))) {
            char* fp = ((char*(*)(char*,char*,char*))compileFunc)(tokens, i, ntoks);
            sb = kr_sbappend(sb, ((char*(*)(char*))pairVal)(fp));
            i = ((char*(*)(char*))pairPos)(fp);
        } else if (kr_truthy(kr_eq(tok, kr_str("KW:callback")))) {
            char* fp = ((char*(*)(char*,char*,char*))compileCallbackFunc)(tokens, kr_plus(i, kr_str("1")), ntoks);
            sb = kr_sbappend(sb, ((char*(*)(char*))pairVal)(fp));
            i = ((char*(*)(char*))pairPos)(fp);
        } else if (kr_truthy(kr_eq(tok, kr_str("KW:export")))) {
            i = kr_plus(i, kr_str("1"));
        } else {
            i = kr_plus(i, kr_str("1"));
        }
    }
    return kr_sbtostring(sb);
}

char* compileImportedForwardDecls(char* tokens, char* ntoks, char* ftable) {
    char* sb = kr_sbnew();
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* tok = ((char*(*)(char*,char*))tokAt)(tokens, i);
        if (kr_truthy((kr_truthy(kr_eq(tok, kr_str("KW:func"))) || kr_truthy(kr_eq(tok, kr_str("KW:fn"))) ? kr_str("1") : kr_str("0")))) {
            char* nameTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, kr_str("1")));
            char* fname = ((char*(*)(char*))tokVal)(nameTok);
            char* info = ((char*(*)(char*,char*))funcLookup)(ftable, fname);
            char* pc = ((char*(*)(char*))funcParamCount)(info);
            char* decl = kr_plus(kr_plus(kr_str("char* "), ((char*(*)(char*))cIdent)(fname)), kr_str("("));
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
            char* fp = ((char*(*)(char*,char*))skipBlock)(tokens, kr_plus(kr_plus(i, kr_str("3")), kr_mul(pc, kr_str("2"))));
            i = fp;
        } else if (kr_truthy(kr_eq(tok, kr_str("KW:export")))) {
            i = kr_plus(i, kr_str("1"));
        } else {
            i = kr_plus(i, kr_str("1"));
        }
    }
    return kr_sbtostring(sb);
}

char* irLabel(char* prefix, char* n) {
    return kr_plus(kr_plus(prefix, kr_str("_")), n);
}

char* irExpr(char* tokens, char* pos, char* ntoks, char* lc) {
    return ((char*(*)(char*,char*,char*,char*))irTernary)(tokens, pos, ntoks, lc);
}

char* irTernary(char* tokens, char* pos, char* ntoks, char* lc) {
    char* pair = ((char*(*)(char*,char*,char*,char*))irOr)(tokens, pos, ntoks, lc);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    char* nlc = lc;
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("QUESTION")))) {
        char* trueLabel = ((char*(*)(char*,char*))irLabel)(kr_str("_tern_t"), p);
        char* endLabel = ((char*(*)(char*,char*))irLabel)(kr_str("_tern_e"), p);
        nlc = kr_plus(nlc, kr_str("1"));
        char* tp = ((char*(*)(char*,char*,char*,char*))irExpr)(tokens, kr_plus(p, kr_str("1")), ntoks, nlc);
        char* tcode = ((char*(*)(char*))pairVal)(tp);
        p = ((char*(*)(char*))pairPos)(tp);
        nlc = kr_plus(nlc, kr_str("1"));
        p = kr_plus(p, kr_str("1"));
        char* fp = ((char*(*)(char*,char*,char*,char*))irExpr)(tokens, p, ntoks, nlc);
        char* fcode = ((char*(*)(char*))pairVal)(fp);
        p = ((char*(*)(char*))pairPos)(fp);
        nlc = kr_plus(nlc, kr_str("1"));
        char* out = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, kr_str("JUMPIFNOT ")), trueLabel), kr_str("\n")), tcode), kr_str("JUMP ")), endLabel), kr_str("\n")), kr_str("LABEL ")), trueLabel), kr_str("\n")), fcode), kr_str("LABEL ")), endLabel), kr_str("\n"));
        return kr_plus(kr_plus(out, kr_str(",")), p);
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* irOr(char* tokens, char* pos, char* ntoks, char* lc) {
    char* pair = ((char*(*)(char*,char*,char*,char*))irAnd)(tokens, pos, ntoks, lc);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    char* nlc = lc;
    while (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("OR")))) {
        char* shortLabel = ((char*(*)(char*,char*))irLabel)(kr_str("_or"), p);
        nlc = kr_plus(nlc, kr_str("1"));
        char* rp = ((char*(*)(char*,char*,char*,char*))irAnd)(tokens, kr_plus(p, kr_str("1")), ntoks, nlc);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, kr_str("JUMPIF ")), shortLabel), kr_str("\n")), rcode), kr_str("LABEL ")), shortLabel), kr_str("\n"));
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* irAnd(char* tokens, char* pos, char* ntoks, char* lc) {
    char* pair = ((char*(*)(char*,char*,char*,char*))irEquality)(tokens, pos, ntoks, lc);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    char* nlc = lc;
    while (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("AND")))) {
        char* shortLabel = ((char*(*)(char*,char*))irLabel)(kr_str("_and"), p);
        nlc = kr_plus(nlc, kr_str("1"));
        char* rp = ((char*(*)(char*,char*,char*,char*))irEquality)(tokens, kr_plus(p, kr_str("1")), ntoks, nlc);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, kr_str("JUMPIFNOT ")), shortLabel), kr_str("\n")), rcode), kr_str("LABEL ")), shortLabel), kr_str("\n"));
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* irEquality(char* tokens, char* pos, char* ntoks, char* lc) {
    char* pair = ((char*(*)(char*,char*,char*,char*))irRelational)(tokens, pos, ntoks, lc);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("EQ"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("NEQ"))) ? kr_str("1") : kr_str("0")))) {
        char* op = ((char*(*)(char*,char*))tokAt)(tokens, p);
        char* rp = ((char*(*)(char*,char*,char*,char*))irRelational)(tokens, kr_plus(p, kr_str("1")), ntoks, lc);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        if (kr_truthy(kr_eq(op, kr_str("EQ")))) {
            code = kr_plus(kr_plus(code, rcode), kr_str("EQ\n"));
        } else {
            code = kr_plus(kr_plus(code, rcode), kr_str("NEQ\n"));
        }
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* irRelational(char* tokens, char* pos, char* ntoks, char* lc) {
    char* pair = ((char*(*)(char*,char*,char*,char*))irAdditive)(tokens, pos, ntoks, lc);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("LT"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("GT"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("LTE"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("GTE"))) ? kr_str("1") : kr_str("0")))) {
        char* op = ((char*(*)(char*,char*))tokAt)(tokens, p);
        char* rp = ((char*(*)(char*,char*,char*,char*))irAdditive)(tokens, kr_plus(p, kr_str("1")), ntoks, lc);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        if (kr_truthy(kr_eq(op, kr_str("LT")))) {
            code = kr_plus(kr_plus(code, rcode), kr_str("LT\n"));
        }
        if (kr_truthy(kr_eq(op, kr_str("GT")))) {
            code = kr_plus(kr_plus(code, rcode), kr_str("GT\n"));
        }
        if (kr_truthy(kr_eq(op, kr_str("LTE")))) {
            code = kr_plus(kr_plus(code, rcode), kr_str("LTE\n"));
        }
        if (kr_truthy(kr_eq(op, kr_str("GTE")))) {
            code = kr_plus(kr_plus(code, rcode), kr_str("GTE\n"));
        }
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* irAdditive(char* tokens, char* pos, char* ntoks, char* lc) {
    char* pair = ((char*(*)(char*,char*,char*,char*))irMultiplicative)(tokens, pos, ntoks, lc);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("PLUS"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("MINUS"))) ? kr_str("1") : kr_str("0")))) {
        char* op = ((char*(*)(char*,char*))tokAt)(tokens, p);
        char* rp = ((char*(*)(char*,char*,char*,char*))irMultiplicative)(tokens, kr_plus(p, kr_str("1")), ntoks, lc);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        if (kr_truthy(kr_eq(op, kr_str("PLUS")))) {
            code = kr_plus(kr_plus(code, rcode), kr_str("ADD\n"));
        } else {
            code = kr_plus(kr_plus(code, rcode), kr_str("SUB\n"));
        }
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* irMultiplicative(char* tokens, char* pos, char* ntoks, char* lc) {
    char* pair = ((char*(*)(char*,char*,char*,char*))irUnary)(tokens, pos, ntoks, lc);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy((kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("STAR"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SLASH"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("MOD"))) ? kr_str("1") : kr_str("0")))) {
        char* op = ((char*(*)(char*,char*))tokAt)(tokens, p);
        char* rp = ((char*(*)(char*,char*,char*,char*))irUnary)(tokens, kr_plus(p, kr_str("1")), ntoks, lc);
        char* rcode = ((char*(*)(char*))pairVal)(rp);
        p = ((char*(*)(char*))pairPos)(rp);
        if (kr_truthy(kr_eq(op, kr_str("STAR")))) {
            code = kr_plus(kr_plus(code, rcode), kr_str("MUL\n"));
        }
        if (kr_truthy(kr_eq(op, kr_str("SLASH")))) {
            code = kr_plus(kr_plus(code, rcode), kr_str("DIV\n"));
        }
        if (kr_truthy(kr_eq(op, kr_str("MOD")))) {
            code = kr_plus(kr_plus(code, rcode), kr_str("MOD\n"));
        }
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* irUnary(char* tokens, char* pos, char* ntoks, char* lc) {
    char* tok = ((char*(*)(char*,char*))tokAt)(tokens, pos);
    if (kr_truthy(kr_eq(tok, kr_str("MINUS")))) {
        char* pair = ((char*(*)(char*,char*,char*,char*))irUnary)(tokens, kr_plus(pos, kr_str("1")), ntoks, lc);
        char* code = ((char*(*)(char*))pairVal)(pair);
        char* p = ((char*(*)(char*))pairPos)(pair);
        return kr_plus(kr_plus(code, kr_str("NEG\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("BANG")))) {
        char* pair = ((char*(*)(char*,char*,char*,char*))irUnary)(tokens, kr_plus(pos, kr_str("1")), ntoks, lc);
        char* code = ((char*(*)(char*))pairVal)(pair);
        char* p = ((char*(*)(char*))pairPos)(pair);
        return kr_plus(kr_plus(code, kr_str("NOT\n,")), p);
    }
    return ((char*(*)(char*,char*,char*,char*))irPostfix)(tokens, pos, ntoks, lc);
}

char* irPostfix(char* tokens, char* pos, char* ntoks, char* lc) {
    char* pair = ((char*(*)(char*,char*,char*,char*))irPrimary)(tokens, pos, ntoks, lc);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    while (kr_truthy((kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("LBRACK"))) || kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("DOT"))) ? kr_str("1") : kr_str("0")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("LBRACK")))) {
            char* idxp = ((char*(*)(char*,char*,char*,char*))irExpr)(tokens, kr_plus(p, kr_str("1")), ntoks, lc);
            char* idxcode = ((char*(*)(char*))pairVal)(idxp);
            p = kr_plus(((char*(*)(char*))pairPos)(idxp), kr_str("1"));
            code = kr_plus(kr_plus(code, idxcode), kr_str("INDEX\n"));
        } else {
            char* field = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, kr_str("1"))));
            p = kr_plus(p, kr_str("2"));
            code = kr_plus(kr_plus(kr_plus(code, kr_str("GETFIELD ")), field), kr_str("\n"));
        }
    }
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* irPrimary(char* tokens, char* pos, char* ntoks, char* lc) {
    char* tok = ((char*(*)(char*,char*))tokAt)(tokens, pos);
    char* tt = ((char*(*)(char*))tokType)(tok);
    char* tv = ((char*(*)(char*))tokVal)(tok);
    if (kr_truthy(kr_eq(tt, kr_str("INT")))) {
        return kr_plus(kr_plus(kr_plus(kr_str("PUSH "), tv), kr_str("\n,")), kr_plus(pos, kr_str("1")));
    }
    if (kr_truthy(kr_eq(tt, kr_str("STR")))) {
        char* escaped = kr_replace(kr_replace(tv, kr_str("\\n"), kr_str("\\\\n")), kr_str("\\t"), kr_str("\\\\t"));
        return kr_plus(kr_plus(kr_plus(kr_str("PUSH \""), escaped), kr_str("\"\n,")), kr_plus(pos, kr_str("1")));
    }
    if (kr_truthy(kr_eq(tt, kr_str("INTERP")))) {
        return kr_plus(kr_plus(((char*(*)(char*,char*))irInterpToIR)(tv, pos), kr_str(",")), kr_plus(pos, kr_str("1")));
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:true")))) {
        return kr_plus(kr_str("PUSH 1\n,"), kr_plus(pos, kr_str("1")));
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:false")))) {
        return kr_plus(kr_str("PUSH 0\n,"), kr_plus(pos, kr_str("1")));
    }
    if (kr_truthy(kr_eq(tok, kr_str("LPAREN")))) {
        char* pair = ((char*(*)(char*,char*,char*,char*))irExpr)(tokens, kr_plus(pos, kr_str("1")), ntoks, lc);
        char* code = ((char*(*)(char*))pairVal)(pair);
        char* p = ((char*(*)(char*))pairPos)(pair);
        return kr_plus(kr_plus(code, kr_str(",")), kr_plus(p, kr_str("1")));
    }
    if (kr_truthy(kr_eq(tok, kr_str("LBRACK")))) {
        return ((char*(*)(char*,char*,char*,char*))irListLiteralIR)(tokens, pos, ntoks, lc);
    }
    if (kr_truthy(kr_eq(tt, kr_str("ID")))) {
        char* nextTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("1")));
        if (kr_truthy(kr_eq(nextTok, kr_str("LPAREN")))) {
            return ((char*(*)(char*,char*,char*,char*))irCall)(tokens, pos, ntoks, lc);
        }
        char* firstChar = kr_idx(tv, kr_atoi(kr_str("0")));
        if (kr_truthy(kr_eq(nextTok, kr_str("LBRACE")))) {
            if (kr_truthy((kr_truthy(kr_gte(firstChar, kr_str("A"))) && kr_truthy(kr_lte(firstChar, kr_str("Z"))) ? kr_str("1") : kr_str("0")))) {
                return ((char*(*)(char*,char*,char*,char*))irStructLiteralIR)(tokens, pos, ntoks, lc);
            }
        }
        return kr_plus(kr_plus(kr_plus(kr_str("LOAD "), tv), kr_str("\n,")), kr_plus(pos, kr_str("1")));
    }
    return kr_plus(kr_str("PUSH \"\"\n,"), kr_plus(pos, kr_str("1")));
}

char* irInterpToIR(char* s, char* pos) {
    char* code = kr_str("");
    char* i = kr_str("0");
    char* seg = kr_str("");
    char* parts = kr_str("0");
    while (kr_truthy(kr_lt(i, kr_len(s)))) {
        if (kr_truthy(kr_eq(kr_idx(s, kr_atoi(i)), kr_str("{")))) {
            if (kr_truthy(kr_gt(kr_len(seg), kr_str("0")))) {
                code = kr_plus(kr_plus(kr_plus(code, kr_str("PUSH \"")), seg), kr_str("\"\n"));
                if (kr_truthy(kr_gt(parts, kr_str("0")))) {
                    code = kr_plus(code, kr_str("CAT\n"));
                }
                parts = kr_plus(parts, kr_str("1"));
                seg = kr_str("");
            }
            i = kr_plus(i, kr_str("1"));
            char* expr = kr_str("");
            while (kr_truthy((kr_truthy(kr_lt(i, kr_len(s))) && kr_truthy(kr_neq(kr_idx(s, kr_atoi(i)), kr_str("}"))) ? kr_str("1") : kr_str("0")))) {
                expr = kr_plus(expr, kr_idx(s, kr_atoi(i)));
                i = kr_plus(i, kr_str("1"));
            }
            i = kr_plus(i, kr_str("1"));
            code = kr_plus(kr_plus(kr_plus(code, kr_str("LOAD ")), expr), kr_str("\n"));
            if (kr_truthy(kr_gt(parts, kr_str("0")))) {
                code = kr_plus(code, kr_str("CAT\n"));
            }
            parts = kr_plus(parts, kr_str("1"));
        } else {
            seg = kr_plus(seg, kr_idx(s, kr_atoi(i)));
            i = kr_plus(i, kr_str("1"));
        }
    }
    if (kr_truthy(kr_gt(kr_len(seg), kr_str("0")))) {
        code = kr_plus(kr_plus(kr_plus(code, kr_str("PUSH \"")), seg), kr_str("\"\n"));
        if (kr_truthy(kr_gt(parts, kr_str("0")))) {
            code = kr_plus(code, kr_str("CAT\n"));
        }
        parts = kr_plus(parts, kr_str("1"));
    }
    if (kr_truthy(kr_eq(parts, kr_str("0")))) {
        return kr_str("PUSH \"\"\n");
    }
    return code;
}

char* irListLiteralIR(char* tokens, char* pos, char* ntoks, char* lc) {
    char* p = kr_plus(pos, kr_str("1"));
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RBRACK")))) {
        return kr_plus(kr_str("PUSH \"\"\n,"), kr_plus(p, kr_str("1")));
    }
    char* code = kr_str("");
    char* ec = kr_str("0");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RBRACK")))) {
        if (kr_truthy(kr_gt(ec, kr_str("0")))) {
            p = kr_plus(p, kr_str("1"));
        }
        char* ep = ((char*(*)(char*,char*,char*,char*))irExpr)(tokens, p, ntoks, lc);
        char* ecode = ((char*(*)(char*))pairVal)(ep);
        p = ((char*(*)(char*))pairPos)(ep);
        if (kr_truthy(kr_gt(ec, kr_str("0")))) {
            code = kr_plus(kr_plus(code, ecode), kr_str("PUSH \",\"\nCAT\nCAT\n"));
        } else {
            code = ecode;
        }
        ec = kr_plus(ec, kr_str("1"));
    }
    return kr_plus(kr_plus(code, kr_str(",")), kr_plus(p, kr_str("1")));
}

char* irStructLiteralIR(char* tokens, char* pos, char* ntoks, char* lc) {
    char* name = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* p = kr_plus(pos, kr_str("2"));
    char* code = kr_str("STRUCTNEW\n");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RBRACE")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, p)), kr_str("ID")))) {
            char* fname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, p));
            p = kr_plus(p, kr_str("2"));
            char* ep = ((char*(*)(char*,char*,char*,char*))irExpr)(tokens, p, ntoks, lc);
            char* ecode = ((char*(*)(char*))pairVal)(ep);
            p = ((char*(*)(char*))pairPos)(ep);
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("COMMA")))) {
                p = kr_plus(p, kr_str("1"));
            }
            code = kr_plus(kr_plus(kr_plus(kr_plus(code, ecode), kr_str("SETFIELD ")), fname), kr_str("\n"));
        } else {
            p = kr_plus(p, kr_str("1"));
        }
    }
    return kr_plus(kr_plus(code, kr_str(",")), kr_plus(p, kr_str("1")));
}

char* irCall(char* tokens, char* pos, char* ntoks, char* lc) {
    char* fname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* p = kr_plus(pos, kr_str("2"));
    char* code = kr_str("");
    char* argc = kr_str("0");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RPAREN")))) {
        if (kr_truthy(kr_gt(argc, kr_str("0")))) {
            p = kr_plus(p, kr_str("1"));
        }
        char* ap = ((char*(*)(char*,char*,char*,char*))irExpr)(tokens, p, ntoks, lc);
        code = kr_plus(code, ((char*(*)(char*))pairVal)(ap));
        p = ((char*(*)(char*))pairPos)(ap);
        argc = kr_plus(argc, kr_str("1"));
    }
    char* builtins = kr_str("print,kp,printErr,readLine,input,readFile,writeFile,arg,argCount,len,substring,charAt,indexOf,contains,startsWith,endsWith,replace,trim,lstrip,rstrip,center,toLower,toUpper,repeat,padLeft,padRight,charCode,fromCharCode,splitBy,format,strReverse,isAlpha,isDigit,isSpace,toInt,parseInt,abs,min,max,pow,sqrt,sign,clamp,hex,bin,floor,ceil,round,split,length,first,last,head,tail,append,join,reverse,sort,unique,fill,zip,slice,listIndexOf,every,some,countOf,sumList,maxList,minList,range,words,lines,keys,values,hasKey,structNew,getField,setField,hasField,structFields,random,timestamp,environ,exit,assert,type,isTruthy,toStr,throw,mapGet,mapSet,mapDel,fadd,fsub,fmul,fdiv,fsqrt,ffloor,fceil,fround,fformat,flt,fgt,feq,sbNew,sbAppend,sbToString,bufNew,bufStr,bufGetDword,bufSetDword,bufGetWord,bufGetQword,bufGetDwordAt,bufGetQwordAt,bufSetByte,bufSetDwordAt,handleOut,handleGet,handleInt,toHandle,ptrDeref,ptrIndex,callPtr");
    if (kr_truthy(kr_contains(builtins, fname))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, kr_str("BUILTIN ")), fname), kr_str(" ")), argc), kr_str("\n,")), kr_plus(p, kr_str("1")));
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, kr_str("CALL ")), fname), kr_str(" ")), argc), kr_str("\n,")), kr_plus(p, kr_str("1")));
}

char* irStmt(char* tokens, char* pos, char* ntoks, char* lc, char* inFunc) {
    char* tok = ((char*(*)(char*,char*))tokAt)(tokens, pos);
    char* tt = ((char*(*)(char*))tokType)(tok);
    if (kr_truthy((kr_truthy(kr_eq(tok, kr_str("KW:let"))) || kr_truthy(kr_eq(tok, kr_str("KW:const"))) ? kr_str("1") : kr_str("0")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))irLetIR)(tokens, kr_plus(pos, kr_str("1")), ntoks, lc, inFunc);
    }
    if (kr_truthy((kr_truthy(kr_eq(tok, kr_str("KW:emit"))) || kr_truthy(kr_eq(tok, kr_str("KW:return"))) ? kr_str("1") : kr_str("0")))) {
        char* pair = ((char*(*)(char*,char*,char*,char*))irExpr)(tokens, kr_plus(pos, kr_str("1")), ntoks, lc);
        char* code = ((char*(*)(char*))pairVal)(pair);
        char* p = ((char*(*)(char*))pairPos)(pair);
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
            p = kr_plus(p, kr_str("1"));
        }
        return kr_plus(kr_plus(code, kr_str("RETURN\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:if")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))irIfIR)(tokens, kr_plus(pos, kr_str("1")), ntoks, lc, inFunc);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:while")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))irWhileIR)(tokens, kr_plus(pos, kr_str("1")), ntoks, lc, inFunc);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:for")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))irForIR)(tokens, kr_plus(pos, kr_str("1")), ntoks, lc, inFunc);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:match")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))irMatchIR)(tokens, kr_plus(pos, kr_str("1")), ntoks, lc, inFunc);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:break")))) {
        char* p = kr_plus(pos, kr_str("1"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
            p = kr_plus(p, kr_str("1"));
        }
        return kr_plus(kr_str("BREAK\n,"), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:continue")))) {
        char* p = kr_plus(pos, kr_str("1"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
            p = kr_plus(p, kr_str("1"));
        }
        return kr_plus(kr_str("CONTINUE\n,"), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:throw")))) {
        char* pair = ((char*(*)(char*,char*,char*,char*))irExpr)(tokens, kr_plus(pos, kr_str("1")), ntoks, lc);
        char* code = ((char*(*)(char*))pairVal)(pair);
        char* p = ((char*(*)(char*))pairPos)(pair);
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
            p = kr_plus(p, kr_str("1"));
        }
        return kr_plus(kr_plus(code, kr_str("THROW\n,")), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:try")))) {
        return ((char*(*)(char*,char*,char*,char*,char*))irTryIR)(tokens, kr_plus(pos, kr_str("1")), ntoks, lc, inFunc);
    }
    if (kr_truthy(kr_eq(tt, kr_str("ID")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("1"))), kr_str("DOT")))) {
            if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("2")))), kr_str("ID")))) {
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("3"))), kr_str("ASSIGN")))) {
                    char* objName = ((char*(*)(char*))tokVal)(tok);
                    char* field = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("2"))));
                    char* pair = ((char*(*)(char*,char*,char*,char*))irExpr)(tokens, kr_plus(pos, kr_str("4")), ntoks, lc);
                    char* code = ((char*(*)(char*))pairVal)(pair);
                    char* p = ((char*(*)(char*))pairPos)(pair);
                    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
                        p = kr_plus(p, kr_str("1"));
                    }
                    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("LOAD "), objName), kr_str("\n")), code), kr_str("SETFIELD ")), field), kr_str("\nSTORE ")), objName), kr_str("\n,")), p);
                }
            }
        }
    }
    if (kr_truthy(kr_eq(tt, kr_str("ID")))) {
        char* nt = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("1")));
        if (kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(nt, kr_str("PLUSEQ"))) || kr_truthy(kr_eq(nt, kr_str("MINUSEQ"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(nt, kr_str("STAREQ"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(nt, kr_str("SLASHEQ"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(nt, kr_str("MODEQ"))) ? kr_str("1") : kr_str("0")))) {
            char* name = ((char*(*)(char*))tokVal)(tok);
            char* pair = ((char*(*)(char*,char*,char*,char*))irExpr)(tokens, kr_plus(pos, kr_str("2")), ntoks, lc);
            char* rcode = ((char*(*)(char*))pairVal)(pair);
            char* p = ((char*(*)(char*))pairPos)(pair);
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
                p = kr_plus(p, kr_str("1"));
            }
            char* op = kr_str("ADD\n");
            if (kr_truthy(kr_eq(nt, kr_str("MINUSEQ")))) {
                op = kr_str("SUB\n");
            }
            if (kr_truthy(kr_eq(nt, kr_str("STAREQ")))) {
                op = kr_str("MUL\n");
            }
            if (kr_truthy(kr_eq(nt, kr_str("SLASHEQ")))) {
                op = kr_str("DIV\n");
            }
            if (kr_truthy(kr_eq(nt, kr_str("MODEQ")))) {
                op = kr_str("MOD\n");
            }
            return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("LOAD "), name), kr_str("\n")), rcode), op), kr_str("STORE ")), name), kr_str("\n,")), p);
        }
    }
    if (kr_truthy((kr_truthy(kr_eq(tt, kr_str("ID"))) && kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("1"))), kr_str("ASSIGN"))) ? kr_str("1") : kr_str("0")))) {
        char* name = ((char*(*)(char*))tokVal)(tok);
        char* pair = ((char*(*)(char*,char*,char*,char*))irExpr)(tokens, kr_plus(pos, kr_str("2")), ntoks, lc);
        char* code = ((char*(*)(char*))pairVal)(pair);
        char* p = ((char*(*)(char*))pairPos)(pair);
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
            p = kr_plus(p, kr_str("1"));
        }
        return kr_plus(kr_plus(kr_plus(kr_plus(code, kr_str("STORE ")), name), kr_str("\n,")), p);
    }
    char* pair = ((char*(*)(char*,char*,char*,char*))irExpr)(tokens, pos, ntoks, lc);
    char* code = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
        p = kr_plus(p, kr_str("1"));
    }
    return kr_plus(kr_plus(code, kr_str("POP\n,")), p);
}

char* irLetIR(char* tokens, char* pos, char* ntoks, char* lc, char* inFunc) {
    char* name = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* p = kr_plus(pos, kr_str("1"));
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("COLON")))) {
        p = kr_plus(p, kr_str("2"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("LBRACK")))) {
            p = kr_plus(p, kr_str("1"));
            while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RBRACK")))) {
                p = kr_plus(p, kr_str("1"));
            }
            p = kr_plus(p, kr_str("1"));
        }
    }
    p = kr_plus(p, kr_str("1"));
    char* pair = ((char*(*)(char*,char*,char*,char*))irExpr)(tokens, p, ntoks, lc);
    char* code = ((char*(*)(char*))pairVal)(pair);
    p = ((char*(*)(char*))pairPos)(pair);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("SEMI")))) {
        p = kr_plus(p, kr_str("1"));
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("LOCAL "), name), kr_str("\n")), code), kr_str("STORE ")), name), kr_str("\n,")), p);
}

char* irBlockIR(char* tokens, char* pos, char* ntoks, char* lc, char* inFunc) {
    char* p = kr_plus(pos, kr_str("1"));
    char* sbBlock = kr_sbnew();
    char* nlc = lc;
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RBRACE")))) {
        char* sp = ((char*(*)(char*,char*,char*,char*,char*))irStmt)(tokens, p, ntoks, nlc, inFunc);
        sbBlock = kr_sbappend(sbBlock, ((char*(*)(char*))pairVal)(sp));
        p = ((char*(*)(char*))pairPos)(sp);
        nlc = kr_plus(nlc, kr_str("1"));
    }
    return kr_plus(kr_plus(kr_sbtostring(sbBlock), kr_str(",")), kr_plus(p, kr_str("1")));
}

char* irIfIR(char* tokens, char* pos, char* ntoks, char* lc, char* inFunc) {
    char* pair = ((char*(*)(char*,char*,char*,char*))irExpr)(tokens, pos, ntoks, lc);
    char* condCode = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    char* elseLabel = ((char*(*)(char*,char*))irLabel)(kr_str("_else"), pos);
    char* endLabel = ((char*(*)(char*,char*))irLabel)(kr_str("_endif"), pos);
    char* nlc = kr_plus(lc, kr_str("1"));
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))irBlockIR)(tokens, p, ntoks, nlc, inFunc);
    char* bodyCode = ((char*(*)(char*))pairVal)(bp);
    p = ((char*(*)(char*))pairPos)(bp);
    nlc = kr_plus(nlc, kr_str("1"));
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("KW:else")))) {
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, kr_str("1"))), kr_str("KW:if")))) {
            char* ep = ((char*(*)(char*,char*,char*,char*,char*))irIfIR)(tokens, kr_plus(p, kr_str("2")), ntoks, nlc, inFunc);
            char* elseCode = ((char*(*)(char*))pairVal)(ep);
            p = ((char*(*)(char*))pairPos)(ep);
            return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(condCode, kr_str("JUMPIFNOT ")), elseLabel), kr_str("\n")), bodyCode), kr_str("JUMP ")), endLabel), kr_str("\n")), kr_str("LABEL ")), elseLabel), kr_str("\n")), elseCode), kr_str("LABEL ")), endLabel), kr_str("\n,")), p);
        } else {
            char* ep = ((char*(*)(char*,char*,char*,char*,char*))irBlockIR)(tokens, kr_plus(p, kr_str("1")), ntoks, nlc, inFunc);
            char* elseCode = ((char*(*)(char*))pairVal)(ep);
            p = ((char*(*)(char*))pairPos)(ep);
            return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(condCode, kr_str("JUMPIFNOT ")), elseLabel), kr_str("\n")), bodyCode), kr_str("JUMP ")), endLabel), kr_str("\n")), kr_str("LABEL ")), elseLabel), kr_str("\n")), elseCode), kr_str("LABEL ")), endLabel), kr_str("\n,")), p);
        }
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(condCode, kr_str("JUMPIFNOT ")), endLabel), kr_str("\n")), bodyCode), kr_str("LABEL ")), endLabel), kr_str("\n,")), p);
}

char* irWhileIR(char* tokens, char* pos, char* ntoks, char* lc, char* inFunc) {
    char* loopLabel = ((char*(*)(char*,char*))irLabel)(kr_str("_wloop"), pos);
    char* endLabel = ((char*(*)(char*,char*))irLabel)(kr_str("_wend"), pos);
    char* nlc = kr_plus(lc, kr_str("1"));
    char* pair = ((char*(*)(char*,char*,char*,char*))irExpr)(tokens, pos, ntoks, nlc);
    char* condCode = ((char*(*)(char*))pairVal)(pair);
    char* p = ((char*(*)(char*))pairPos)(pair);
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))irBlockIR)(tokens, p, ntoks, nlc, inFunc);
    char* bodyCode = ((char*(*)(char*))pairVal)(bp);
    p = ((char*(*)(char*))pairPos)(bp);
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("LABEL "), loopLabel), kr_str("\n")), condCode), kr_str("JUMPIFNOT ")), endLabel), kr_str("\n")), bodyCode), kr_str("JUMP ")), loopLabel), kr_str("\n")), kr_str("LABEL ")), endLabel), kr_str("\n,")), p);
}

char* irForIR(char* tokens, char* pos, char* ntoks, char* lc, char* inFunc) {
    char* varName = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, pos));
    char* p = kr_plus(pos, kr_str("2"));
    char* pair = ((char*(*)(char*,char*,char*,char*))irExpr)(tokens, p, ntoks, lc);
    char* collCode = ((char*(*)(char*))pairVal)(pair);
    p = ((char*(*)(char*))pairPos)(pair);
    char* loopLabel = ((char*(*)(char*,char*))irLabel)(kr_str("_floop"), pos);
    char* endLabel = ((char*(*)(char*,char*))irLabel)(kr_str("_fend"), pos);
    char* idxVar = kr_plus(kr_str("_for_i_"), pos);
    char* cntVar = kr_plus(kr_str("_for_cnt_"), pos);
    char* colVar = kr_plus(kr_str("_for_col_"), pos);
    char* nlc = kr_plus(lc, kr_str("1"));
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))irBlockIR)(tokens, p, ntoks, nlc, inFunc);
    char* bodyCode = ((char*(*)(char*))pairVal)(bp);
    p = ((char*(*)(char*))pairPos)(bp);
    char* code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(collCode, kr_str("LOCAL ")), colVar), kr_str("\n")), kr_str("STORE ")), colVar), kr_str("\n"));
    code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, kr_str("LOCAL ")), idxVar), kr_str("\n")), kr_str("PUSH 0\n")), kr_str("STORE ")), idxVar), kr_str("\n"));
    code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, kr_str("LOCAL ")), cntVar), kr_str("\n")), kr_str("LOAD ")), colVar), kr_str("\n")), kr_str("BUILTIN length 1\n")), kr_str("STORE ")), cntVar), kr_str("\n"));
    code = kr_plus(kr_plus(kr_plus(code, kr_str("LABEL ")), loopLabel), kr_str("\n"));
    code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, kr_str("LOAD ")), idxVar), kr_str("\n")), kr_str("LOAD ")), cntVar), kr_str("\n")), kr_str("LT\n"));
    code = kr_plus(kr_plus(kr_plus(code, kr_str("JUMPIFNOT ")), endLabel), kr_str("\n"));
    code = kr_plus(kr_plus(kr_plus(code, kr_str("LOCAL ")), varName), kr_str("\n"));
    code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, kr_str("LOAD ")), colVar), kr_str("\n")), kr_str("LOAD ")), idxVar), kr_str("\n")), kr_str("BUILTIN split 2\n")), kr_str("STORE ")), varName), kr_str("\n"));
    code = kr_plus(code, bodyCode);
    code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, kr_str("LOAD ")), idxVar), kr_str("\n")), kr_str("PUSH 1\n")), kr_str("ADD\n")), kr_str("STORE ")), idxVar), kr_str("\n"));
    code = kr_plus(kr_plus(kr_plus(code, kr_str("JUMP ")), loopLabel), kr_str("\n"));
    code = kr_plus(kr_plus(kr_plus(code, kr_str("LABEL ")), endLabel), kr_str("\n"));
    return kr_plus(kr_plus(code, kr_str(",")), p);
}

char* irMatchIR(char* tokens, char* pos, char* ntoks, char* lc, char* inFunc) {
    char* pair = ((char*(*)(char*,char*,char*,char*))irExpr)(tokens, pos, ntoks, lc);
    char* matchCode = ((char*(*)(char*))pairVal)(pair);
    char* p = kr_plus(((char*(*)(char*))pairPos)(pair), kr_str("1"));
    char* endLabel = ((char*(*)(char*,char*))irLabel)(kr_str("_mend"), pos);
    char* matchVar = kr_plus(kr_str("_match_"), pos);
    char* code = kr_plus(kr_plus(kr_plus(matchCode, kr_str("STORE ")), matchVar), kr_str("\n"));
    char* nlc = kr_plus(lc, kr_str("1"));
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RBRACE")))) {
        char* caseLabel = ((char*(*)(char*,char*))irLabel)(kr_str("_mcase"), p);
        char* nextLabel = ((char*(*)(char*,char*))irLabel)(kr_str("_mnext"), p);
        nlc = kr_plus(nlc, kr_str("1"));
        if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("KW:else")))) {
            p = kr_plus(p, kr_str("1"));
            char* bp = ((char*(*)(char*,char*,char*,char*,char*))irBlockIR)(tokens, p, ntoks, nlc, inFunc);
            code = kr_plus(code, ((char*(*)(char*))pairVal)(bp));
            p = ((char*(*)(char*))pairPos)(bp);
        } else {
            char* cp = ((char*(*)(char*,char*,char*,char*))irExpr)(tokens, p, ntoks, nlc);
            char* caseCode = ((char*(*)(char*))pairVal)(cp);
            p = ((char*(*)(char*))pairPos)(cp);
            char* bp = ((char*(*)(char*,char*,char*,char*,char*))irBlockIR)(tokens, p, ntoks, nlc, inFunc);
            char* bodyCode = ((char*(*)(char*))pairVal)(bp);
            p = ((char*(*)(char*))pairPos)(bp);
            code = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(code, kr_str("LOAD ")), matchVar), kr_str("\n")), caseCode), kr_str("EQ\n")), kr_str("JUMPIFNOT ")), nextLabel), kr_str("\n")), bodyCode), kr_str("JUMP ")), endLabel), kr_str("\n")), kr_str("LABEL ")), nextLabel), kr_str("\n"));
        }
        nlc = kr_plus(nlc, kr_str("1"));
    }
    p = kr_plus(p, kr_str("1"));
    return kr_plus(kr_plus(kr_plus(kr_plus(code, kr_str("LABEL ")), endLabel), kr_str("\n,")), p);
}

char* irTryIR(char* tokens, char* pos, char* ntoks, char* lc, char* inFunc) {
    char* catchLabel = ((char*(*)(char*,char*))irLabel)(kr_str("_catch"), pos);
    char* endLabel = ((char*(*)(char*,char*))irLabel)(kr_str("_tryend"), pos);
    char* nlc = kr_plus(lc, kr_str("1"));
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))irBlockIR)(tokens, pos, ntoks, nlc, inFunc);
    char* bodyCode = ((char*(*)(char*))pairVal)(bp);
    char* p = ((char*(*)(char*))pairPos)(bp);
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("KW:catch")))) {
        p = kr_plus(p, kr_str("1"));
        char* catchVar = kr_str("_err");
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, p)), kr_str("ID")))) {
            catchVar = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, p));
            p = kr_plus(p, kr_str("1"));
        }
        char* cp = ((char*(*)(char*,char*,char*,char*,char*))irBlockIR)(tokens, p, ntoks, nlc, inFunc);
        char* catchCode = ((char*(*)(char*))pairVal)(cp);
        p = ((char*(*)(char*))pairPos)(cp);
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("TRY "), catchLabel), kr_str("\n")), bodyCode), kr_str("ENDTRY\n")), kr_str("JUMP ")), endLabel), kr_str("\n")), kr_str("LABEL ")), catchLabel), kr_str("\n")), kr_str("LOCAL ")), catchVar), kr_str("\n")), kr_str("STORE ")), catchVar), kr_str("\n")), catchCode), kr_str("LABEL ")), endLabel), kr_str("\n,")), p);
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("TRY "), catchLabel), kr_str("\n")), bodyCode), kr_str("ENDTRY\n")), kr_str("LABEL ")), catchLabel), kr_str("\n")), kr_str("LABEL ")), endLabel), kr_str("\n,")), p);
}

char* irFuncIR(char* tokens, char* pos, char* ntoks) {
    char* fname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(pos, kr_str("1"))));
    char* p = kr_plus(pos, kr_str("3"));
    char* params = kr_str("");
    char* pc = kr_str("0");
    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RPAREN")))) {
        char* pt = ((char*(*)(char*,char*))tokAt)(tokens, p);
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(pt), kr_str("ID")))) {
            params = kr_plus(kr_plus(kr_plus(params, kr_str("PARAM ")), ((char*(*)(char*))tokVal)(pt)), kr_str("\n"));
            pc = kr_plus(pc, kr_str("1"));
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(p, kr_str("1"))), kr_str("COLON")))) {
                p = kr_plus(p, kr_str("3"));
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("LBRACK")))) {
                    p = kr_plus(p, kr_str("1"));
                    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("RBRACK")))) {
                        p = kr_plus(p, kr_str("1"));
                    }
                    p = kr_plus(p, kr_str("1"));
                }
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("COMMA")))) {
                    p = kr_plus(p, kr_str("1"));
                }
            } else {
                p = kr_plus(p, kr_str("1"));
            }
        } else {
            p = kr_plus(p, kr_str("1"));
        }
    }
    p = kr_plus(p, kr_str("1"));
    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, p), kr_str("ARROW")))) {
        p = kr_plus(p, kr_str("2"));
    }
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))irBlockIR)(tokens, p, ntoks, kr_str("0"), kr_str("1"));
    char* bodyCode = ((char*(*)(char*))pairVal)(bp);
    p = ((char*(*)(char*))pairPos)(bp);
    return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_str("FUNC "), fname), kr_str(" ")), pc), kr_str("\n")), params), bodyCode), kr_str("END\n\n,")), p);
}

char* findFreeVars(char* tokens, char* bodyStart, char* bodyEnd, char* params) {
    char* localDecls = params;
    char* i = kr_plus(bodyStart, kr_str("1"));
    while (kr_truthy(kr_lt(i, bodyEnd))) {
        char* tok = ((char*(*)(char*,char*))tokAt)(tokens, i);
        if (kr_truthy((kr_truthy(kr_eq(tok, kr_str("KW:let"))) || kr_truthy(kr_eq(tok, kr_str("KW:const"))) ? kr_str("1") : kr_str("0")))) {
            char* lname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, kr_str("1"))));
            if (kr_truthy(kr_not(kr_contains(localDecls, kr_plus(kr_plus(kr_str(","), lname), kr_str(",")))))) {
                localDecls = kr_plus(kr_plus(kr_plus(localDecls, kr_str(",")), lname), kr_str(","));
            }
        }
        i = kr_plus(i, kr_str("1"));
    }
    char* freeVars = kr_str("");
    i = kr_plus(bodyStart, kr_str("1"));
    while (kr_truthy(kr_lt(i, bodyEnd))) {
        char* tok = ((char*(*)(char*,char*))tokAt)(tokens, i);
        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(tok), kr_str("ID")))) {
            char* name = ((char*(*)(char*))tokVal)(tok);
            char* nextTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, kr_str("1")));
            if (kr_truthy(kr_neq(nextTok, kr_str("LPAREN")))) {
                if (kr_truthy(kr_not(kr_contains(kr_plus(kr_plus(kr_str(","), localDecls), kr_str(",")), kr_plus(kr_plus(kr_str(","), name), kr_str(",")))))) {
                    if (kr_truthy((kr_truthy(kr_gt(kr_len(name), kr_str("0"))) && kr_truthy(kr_not(kr_startswith(name, kr_str("kr_")))) ? kr_str("1") : kr_str("0")))) {
                        if (kr_truthy(kr_not(kr_contains(freeVars, kr_plus(kr_plus(kr_str(","), name), kr_str(",")))))) {
                            freeVars = kr_plus(kr_plus(kr_plus(freeVars, kr_str(",")), name), kr_str(","));
                        }
                    }
                }
            }
        }
        i = kr_plus(i, kr_str("1"));
    }
    if (kr_truthy(kr_gt(kr_len(freeVars), kr_str("2")))) {
        return kr_substr(freeVars, kr_str("1"), kr_sub(kr_len(freeVars), kr_str("1")));
    }
    return kr_str("");
}

int main(int argc, char** argv) {
    _argc = argc; _argv = argv;
    srand((unsigned)time(NULL));
    char* kccVer = kr_str("1.3.7");
    char* irMode = kr_str("0");
    char* headersDir = kr_str("");
    char* outFile = kr_str("");
    char* file = kr_arg(kr_str("0"));
    char* argIdx = kr_str("0");
    if (kr_truthy((kr_truthy(kr_eq(file, kr_str("--version"))) || kr_truthy(kr_eq(file, kr_str("-v"))) ? kr_str("1") : kr_str("0")))) {
        kr_printerr(kr_plus(kr_str("kcc version "), kccVer));
        return atoi(kr_str("0"));
    }
    if (kr_truthy(kr_eq(kr_argcount(), kr_str("0")))) {
        kr_printerr(kr_str("kcc: no input file"));
        kr_printerr(kr_str("usage: kcc [-o out.exe] [--headers dir] source.k"));
        return atoi(kr_str("1"));
    }
    while (kr_truthy((kr_truthy((kr_truthy(kr_eq(file, kr_str("--ir"))) || kr_truthy(kr_eq(file, kr_str("--headers"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(file, kr_str("-o"))) ? kr_str("1") : kr_str("0")))) {
        if (kr_truthy(kr_eq(file, kr_str("--ir")))) {
            irMode = kr_str("1");
            argIdx = kr_plus(argIdx, kr_str("1"));
        }
        if (kr_truthy(kr_eq(file, kr_str("--headers")))) {
            argIdx = kr_plus(argIdx, kr_str("1"));
            headersDir = kr_arg(kr_plus(argIdx, kr_str("")));
            argIdx = kr_plus(argIdx, kr_str("1"));
        }
        if (kr_truthy(kr_eq(file, kr_str("-o")))) {
            argIdx = kr_plus(argIdx, kr_str("1"));
            outFile = kr_arg(kr_plus(argIdx, kr_str("")));
            argIdx = kr_plus(argIdx, kr_str("1"));
        }
        file = kr_arg(kr_plus(argIdx, kr_str("")));
    }
    if (kr_truthy(kr_gt(kr_len(outFile), kr_str("0")))) {
        irMode = kr_str("1");
    }
    if (kr_truthy(kr_eq(headersDir, kr_str("")))) {
        headersDir = kr_str("C:\\krypton\\headers");
    }
    char* source = kr_readfile(file);
    if (kr_truthy(kr_eq(kr_len(source), kr_str("0")))) {
        kr_printerr(kr_plus(kr_str("kcc: cannot read file: "), file));
        return atoi(kr_str("1"));
    }
    char* tokens = ((char*(*)(char*))tokenize)(source);
    char* ntoks = kr_linecount(tokens);
    char* baseDir = kr_str("");
    char* lastSlash = kr_sub(kr_str("0"), kr_str("1"));
    char* fi = kr_str("0");
    while (kr_truthy(kr_lt(fi, kr_len(file)))) {
        if (kr_truthy((kr_truthy(kr_eq(kr_idx(file, kr_atoi(fi)), kr_str("/"))) || kr_truthy(kr_eq(kr_idx(file, kr_atoi(fi)), kr_str("\\"))) ? kr_str("1") : kr_str("0")))) {
            lastSlash = fi;
        }
        fi = kr_plus(fi, kr_str("1"));
    }
    if (kr_truthy(kr_gte(lastSlash, kr_str("0")))) {
        baseDir = kr_substr(file, kr_str("0"), kr_plus(lastSlash, kr_str("1")));
    }
    char* ftable = ((char*(*)(char*,char*))scanFunctions)(tokens, ntoks);
    char* sb = kr_sbnew();
    sb = kr_sbappend(sb, ((char*(*)(void))cRuntime)());
    char* imported = kr_str("");
    char* importFwdDecls = kr_str("");
    char* importBodies = kr_str("");
    char* importedIR = kr_str("");
    char* lambdaBank = kr_str("");
    char* lambdaFreeVars = kr_str("");
    char* structTable = kr_str("");
    char* lsi = kr_str("0");
    while (kr_truthy(kr_lt(lsi, ntoks))) {
        char* lsTok = ((char*(*)(char*,char*))tokAt)(tokens, lsi);
        if (kr_truthy((kr_truthy(kr_eq(lsTok, kr_str("KW:func"))) || kr_truthy(kr_eq(lsTok, kr_str("KW:fn"))) ? kr_str("1") : kr_str("0")))) {
            char* prevTok = kr_str("");
            if (kr_truthy(kr_gt(lsi, kr_str("0")))) {
                prevTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_sub(lsi, kr_str("1")));
            }
            char* nextTok2 = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(lsi, kr_str("1")));
            if (kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(prevTok, kr_str("ASSIGN"))) || kr_truthy(kr_eq(prevTok, kr_str("LPAREN"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(prevTok, kr_str("COMMA"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(prevTok, kr_str("KW:emit"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(prevTok, kr_str("KW:return"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(prevTok, kr_str("KW:in"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_eq(nextTok2, kr_str("LPAREN"))) ? kr_str("1") : kr_str("0")))) {
                char* lp2 = kr_plus(lsi, kr_str("2"));
                char* lparams2 = kr_str("");
                char* lpc2 = kr_str("0");
                while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, lp2), kr_str("RPAREN")))) {
                    if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, lp2)), kr_str("ID")))) {
                        if (kr_truthy(kr_gt(lpc2, kr_str("0")))) {
                            lparams2 = kr_plus(lparams2, kr_str(","));
                        }
                        lparams2 = kr_plus(lparams2, ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, lp2)));
                        lpc2 = kr_plus(lpc2, kr_str("1"));
                    }
                    lp2 = kr_plus(lp2, kr_str("1"));
                }
                lp2 = kr_plus(lp2, kr_str("1"));
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, lp2), kr_str("ARROW")))) {
                    lp2 = kr_plus(lp2, kr_str("2"));
                }
                char* lbp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, lp2, ntoks, kr_str("1"), kr_plus(kr_str("_krlam"), lsi));
                char* lbcode = ((char*(*)(char*))pairVal)(lbp);
                char* lsig = kr_plus(kr_plus(kr_str("char* _krlam"), lsi), kr_str("(void)"));
                if (kr_truthy(kr_gt(lpc2, kr_str("0")))) {
                    lsig = kr_plus(kr_plus(kr_plus(kr_str("char* _krlam"), lsi), kr_str("(char* ")), ((char*(*)(char*))cIdent)(((char*(*)(char*,char*))getNthParam)(lparams2, kr_str("0"))));
                    char* lpi2 = kr_str("1");
                    while (kr_truthy(kr_lt(lpi2, lpc2))) {
                        lsig = kr_plus(kr_plus(lsig, kr_str(", char* ")), ((char*(*)(char*))cIdent)(((char*(*)(char*,char*))getNthParam)(lparams2, lpi2)));
                        lpi2 = kr_plus(lpi2, kr_str("1"));
                    }
                    lsig = kr_plus(lsig, kr_str(")"));
                }
                char* lbodyEnd = ((char*(*)(char*,char*))skipBlock)(tokens, lp2);
                char* lfreeVars = ((char*(*)(char*,char*,char*,char*))findFreeVars)(tokens, lp2, lbodyEnd, lparams2);
                char* lfvc = kr_str("0");
                if (kr_truthy(kr_gt(kr_len(lfreeVars), kr_str("0")))) {
                    lfvc = kr_linecount(lfreeVars);
                }
                char* lcapDecls = kr_str("");
                char* lcapInits = kr_str("");
                char* lfvi2 = kr_str("0");
                while (kr_truthy(kr_lt(lfvi2, lfvc))) {
                    char* fvn2 = ((char*(*)(char*))cIdent)(kr_split(lfreeVars, lfvi2));
                    lcapDecls = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(lcapDecls, kr_str("static char* _krlam")), lsi), kr_str("_")), fvn2), kr_str(";\n"));
                    lcapInits = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(lcapInits, kr_str("    char* ")), fvn2), kr_str(" = _krlam")), lsi), kr_str("_")), fvn2), kr_str(";\n"));
                    lfvi2 = kr_plus(lfvi2, kr_str("1"));
                }
                lambdaBank = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(lambdaBank, lcapDecls), kr_str("static ")), lsig), kr_str(" {\n")), lbcode), kr_str("return _K_EMPTY;\n}\n\n"));
            }
        }
        lsi = kr_plus(lsi, kr_str("1"));
    }
    char* ii = kr_str("0");
    while (kr_truthy(kr_lt(ii, ntoks))) {
        char* itok = ((char*(*)(char*,char*))tokAt)(tokens, ii);
        if (kr_truthy(kr_eq(itok, kr_str("KW:import")))) {
            char* importPath = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(ii, kr_str("1"))));
            char* fullPath = importPath;
            if (kr_truthy(kr_gt(kr_len(baseDir), kr_str("0")))) {
                if (kr_truthy(kr_not(kr_startswith(importPath, kr_str("/"))))) {
                    if (kr_truthy(kr_not(kr_startswith(importPath, kr_str("C:"))))) {
                        char* relPath = kr_plus(baseDir, importPath);
                        char* testSrc = kr_readfile(relPath);
                        if (kr_truthy(kr_gt(kr_len(testSrc), kr_str("0")))) {
                            fullPath = relPath;
                        }
                    }
                }
            }
            if (kr_truthy(kr_gt(kr_len(headersDir), kr_str("0")))) {
                char* testSrc2 = kr_readfile(fullPath);
                if (kr_truthy(kr_eq(kr_len(testSrc2), kr_str("0")))) {
                    char* hdPath = kr_plus(kr_plus(headersDir, kr_str("/")), importPath);
                    char* testSrc3 = kr_readfile(hdPath);
                    if (kr_truthy(kr_gt(kr_len(testSrc3), kr_str("0")))) {
                        fullPath = hdPath;
                    }
                }
            }
            if (kr_truthy(kr_not(kr_contains(imported, kr_plus(fullPath, kr_str("|")))))) {
                imported = kr_plus(kr_plus(imported, fullPath), kr_str("|"));
                char* importSrc = kr_readfile(fullPath);
                if (kr_truthy(kr_gt(kr_len(importSrc), kr_str("0")))) {
                    char* iToks = ((char*(*)(char*))tokenize)(importSrc);
                    char* iNtoks = kr_linecount(iToks);
                    char* iFtable = ((char*(*)(char*,char*))scanFunctions)(iToks, iNtoks);
                    char* iDecls = kr_str("");
                    char* ij = kr_str("0");
                    while (kr_truthy(kr_lt(ij, iNtoks))) {
                        char* itk = ((char*(*)(char*,char*))tokAt)(iToks, ij);
                        if (kr_truthy(kr_eq(itk, kr_str("KW:jxt")))) {
                            char* ijxtPos = kr_plus(ij, kr_str("2"));
                            char* ijxtHasCHeader = kr_str("0");
                            while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(iToks, ijxtPos), kr_str("RBRACE")))) {
                                char* ijLang = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(iToks, ijxtPos));
                                if (kr_truthy((kr_truthy(kr_eq(ijLang, kr_str("c"))) || kr_truthy(kr_eq(ijLang, kr_str("t"))) ? kr_str("1") : kr_str("0")))) {
                                    char* ijPath = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(iToks, kr_plus(ijxtPos, kr_str("1"))));
                                    ijxtHasCHeader = kr_str("1");
                                    char* ijIncLine = kr_str("");
                                    if (kr_truthy((kr_truthy(kr_contains(ijPath, kr_str("/"))) || kr_truthy(kr_contains(ijPath, kr_str("\\"))) ? kr_str("1") : kr_str("0")))) {
                                        ijIncLine = kr_plus(kr_plus(kr_str("#include \""), ijPath), kr_str("\"\n"));
                                    } else {
                                        ijIncLine = kr_plus(kr_plus(kr_str("#include <"), ijPath), kr_str(">\n"));
                                    }
                                    if (kr_truthy(kr_eq(ijLang, kr_str("c")))) {
                                        iDecls = kr_plus(ijIncLine, iDecls);
                                    } else {
                                        iDecls = kr_plus(iDecls, ijIncLine);
                                    }
                                    ijxtPos = kr_plus(ijxtPos, kr_str("2"));
                                } else if (kr_truthy(kr_eq(ijLang, kr_str("struct")))) {
                                    char* isName = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(iToks, kr_plus(ijxtPos, kr_str("1"))));
                                    char* isfPos = kr_plus(ijxtPos, kr_str("3"));
                                    char* isEntry = kr_plus(isName, kr_str(":"));
                                    char* isFirst = kr_str("1");
                                    char* getBody = kr_str("");
                                    char* setBody = kr_str("");
                                    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(iToks, isfPos), kr_str("RBRACE")))) {
                                        if (kr_truthy(kr_eq(((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(iToks, isfPos)), kr_str("field")))) {
                                            char* isfName = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(iToks, kr_plus(isfPos, kr_str("1"))));
                                            char* isfType = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(iToks, kr_plus(isfPos, kr_str("2"))));
                                            char* isfCPath = isfName;
                                            if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(iToks, kr_plus(isfPos, kr_str("3")))), kr_str("STR")))) {
                                                isfCPath = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(iToks, kr_plus(isfPos, kr_str("3"))));
                                                isfPos = kr_plus(isfPos, kr_str("4"));
                                            } else {
                                                isfPos = kr_plus(isfPos, kr_str("3"));
                                            }
                                            if (kr_truthy(kr_eq(isFirst, kr_str("0")))) {
                                                isEntry = kr_plus(isEntry, kr_str(","));
                                            }
                                            isEntry = kr_plus(kr_plus(kr_plus(isEntry, isfName), kr_str(":")), isfType);
                                            isFirst = kr_str("0");
                                            char* getExpr = kr_plus(kr_plus(kr_str("kr_itoa(s->"), isfCPath), kr_str(")"));
                                            if (kr_truthy((kr_truthy((kr_truthy(kr_eq(isfType, kr_str("ULONGLONG"))) || kr_truthy(kr_eq(isfType, kr_str("SIZE_T"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(isfType, kr_str("ULONG_PTR"))) ? kr_str("1") : kr_str("0")))) {
                                                getExpr = kr_plus(kr_plus(kr_str("({ char _b[32]; snprintf(_b,32,\"%llu\",(unsigned long long)s->"), isfCPath), kr_str("); kr_str(_b); })"));
                                            }
                                            if (kr_truthy(kr_eq(isfType, kr_str("LONGLONG")))) {
                                                getExpr = kr_plus(kr_plus(kr_str("({ char _b[32]; snprintf(_b,32,\"%lld\",(long long)s->"), isfCPath), kr_str("); kr_str(_b); })"));
                                            }
                                            if (kr_truthy((kr_truthy(kr_eq(isfType, kr_str("HANDLE"))) || kr_truthy(kr_eq(isfType, kr_str("PVOID"))) ? kr_str("1") : kr_str("0")))) {
                                                getExpr = kr_plus(kr_plus(kr_str("((char*)s->"), isfCPath), kr_str(")"));
                                            }
                                            if (kr_truthy(kr_eq(isfType, kr_str("CHAR_ARRAY")))) {
                                                getExpr = kr_plus(kr_plus(kr_str("kr_str(s->"), isfCPath), kr_str(")"));
                                            }
                                            if (kr_truthy((kr_truthy((kr_truthy(kr_eq(isfType, kr_str("BYTE"))) || kr_truthy(kr_eq(isfType, kr_str("UCHAR"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(isfType, kr_str("BOOL"))) ? kr_str("1") : kr_str("0")))) {
                                                getExpr = kr_plus(kr_plus(kr_str("kr_itoa((int)(unsigned char)s->"), isfCPath), kr_str(")"));
                                            }
                                            getBody = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(getBody, kr_str("    if(strcmp(f,\"")), isfName), kr_str("\")==0) return ")), getExpr), kr_str(";\n"));
                                            char* setStmt = kr_plus(kr_plus(kr_str("s->"), isfCPath), kr_str("=(DWORD)atoi(v);"));
                                            if (kr_truthy((kr_truthy((kr_truthy(kr_eq(isfType, kr_str("ULONGLONG"))) || kr_truthy(kr_eq(isfType, kr_str("SIZE_T"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(isfType, kr_str("ULONG_PTR"))) ? kr_str("1") : kr_str("0")))) {
                                                setStmt = kr_plus(kr_plus(kr_str("s->"), isfCPath), kr_str("=(ULONGLONG)atoll(v);"));
                                            }
                                            if (kr_truthy(kr_eq(isfType, kr_str("LONGLONG")))) {
                                                setStmt = kr_plus(kr_plus(kr_str("s->"), isfCPath), kr_str("=(LONGLONG)atoll(v);"));
                                            }
                                            if (kr_truthy((kr_truthy(kr_eq(isfType, kr_str("WORD"))) || kr_truthy(kr_eq(isfType, kr_str("USHORT"))) ? kr_str("1") : kr_str("0")))) {
                                                setStmt = kr_plus(kr_plus(kr_str("s->"), isfCPath), kr_str("=(WORD)atoi(v);"));
                                            }
                                            if (kr_truthy((kr_truthy((kr_truthy(kr_eq(isfType, kr_str("BYTE"))) || kr_truthy(kr_eq(isfType, kr_str("UCHAR"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(isfType, kr_str("BOOL"))) ? kr_str("1") : kr_str("0")))) {
                                                setStmt = kr_plus(kr_plus(kr_str("s->"), isfCPath), kr_str("=(BYTE)atoi(v);"));
                                            }
                                            if (kr_truthy((kr_truthy(kr_eq(isfType, kr_str("HANDLE"))) || kr_truthy(kr_eq(isfType, kr_str("PVOID"))) ? kr_str("1") : kr_str("0")))) {
                                                setStmt = kr_plus(kr_plus(kr_str("s->"), isfCPath), kr_str("=(HANDLE)v;"));
                                            }
                                            if (kr_truthy(kr_eq(isfType, kr_str("CHAR_ARRAY")))) {
                                                setStmt = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("strncpy(s->"), isfCPath), kr_str(",v,sizeof(s->")), isfCPath), kr_str(")-1);"));
                                            }
                                            setBody = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(setBody, kr_str("    if(strcmp(f,\"")), isfName), kr_str("\")==0){")), setStmt), kr_str(" return _K_EMPTY;}\n"));
                                        } else {
                                            isfPos = kr_plus(isfPos, kr_str("1"));
                                        }
                                    }
                                    structTable = kr_plus(kr_plus(structTable, isEntry), kr_str("\n"));
                                    char* sAcc = kr_plus(kr_plus(kr_str("static char* structnew_"), isName), kr_str("(void){"));
                                    sAcc = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(sAcc, isName), kr_str("* s=(")), isName), kr_str("*)_alloc(sizeof(")), isName), kr_str("));"));
                                    sAcc = kr_plus(kr_plus(kr_plus(sAcc, kr_str("memset(s,0,sizeof(")), isName), kr_str(")); return (char*)s;}\n"));
                                    sAcc = kr_plus(kr_plus(kr_plus(sAcc, kr_str("static char* structget_")), isName), kr_str("(char* p,char* f){"));
                                    sAcc = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(sAcc, isName), kr_str("* s=(")), isName), kr_str("*)p;\n")), getBody);
                                    sAcc = kr_plus(sAcc, kr_str("    return _K_EMPTY;}\n"));
                                    sAcc = kr_plus(kr_plus(kr_plus(sAcc, kr_str("static char* structset_")), isName), kr_str("(char* p,char* f,char* v){"));
                                    sAcc = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(sAcc, isName), kr_str("* s=(")), isName), kr_str("*)p;\n")), setBody);
                                    sAcc = kr_plus(sAcc, kr_str("    return _K_EMPTY;}\n"));
                                    sAcc = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(sAcc, kr_str("static char* structsizeof_")), isName), kr_str("(void){return kr_itoa(sizeof(")), isName), kr_str("));}\n"));
                                    iDecls = kr_plus(iDecls, sAcc);
                                    ijxtPos = kr_plus(isfPos, kr_str("1"));
                                } else if (kr_truthy(kr_eq(ijLang, kr_str("func")))) {
                                    char* ijfName = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(iToks, kr_plus(ijxtPos, kr_str("1"))));
                                    char* ijfPos = kr_plus(ijxtPos, kr_str("3"));
                                    char* ijfPc = kr_str("0");
                                    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(iToks, ijfPos), kr_str("RPAREN")))) {
                                        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(iToks, ijfPos)), kr_str("ID")))) {
                                            ijfPc = kr_plus(ijfPc, kr_str("1"));
                                        }
                                        ijfPos = kr_plus(ijfPos, kr_str("1"));
                                    }
                                    if (kr_truthy(kr_eq(ijxtHasCHeader, kr_str("0")))) {
                                        char* ijfDecl = kr_plus(kr_plus(kr_str("char* "), ((char*(*)(char*))cIdent)(ijfName)), kr_str("(char*"));
                                        if (kr_truthy(kr_eq(ijfPc, kr_str("0")))) {
                                            ijfDecl = kr_plus(kr_plus(kr_str("char* "), ((char*(*)(char*))cIdent)(ijfName)), kr_str("("));
                                        }
                                        char* ijfPi = kr_str("1");
                                        while (kr_truthy(kr_lt(ijfPi, ijfPc))) {
                                            ijfDecl = kr_plus(ijfDecl, kr_str(", char*"));
                                            ijfPi = kr_plus(ijfPi, kr_str("1"));
                                        }
                                        ijfDecl = kr_plus(ijfDecl, kr_str(");\n"));
                                        iDecls = kr_plus(iDecls, ijfDecl);
                                    }
                                    char* ijfInfo = kr_plus(kr_plus(kr_plus(ijfName, kr_str(":")), ijfPc), kr_str(":0"));
                                    if (kr_truthy(kr_gt(kr_len(ftable), kr_str("0")))) {
                                        ftable = kr_plus(kr_plus(ftable, kr_str("\n")), ijfInfo);
                                    } else {
                                        ftable = ijfInfo;
                                    }
                                    ijfPos = kr_plus(ijfPos, kr_str("1"));
                                    char* ijfRetType = kr_str("");
                                    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(iToks, ijfPos), kr_str("ARROW")))) {
                                        ijfRetType = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(iToks, kr_plus(ijfPos, kr_str("1"))));
                                        ijfPos = kr_plus(ijfPos, kr_str("2"));
                                    }
                                    char* ijfCName = ((char*(*)(char*))cIdent)(ijfName);
                                    if (kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(ijfRetType, kr_str("INT"))) || kr_truthy(kr_eq(ijfRetType, kr_str("UINT"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(ijfRetType, kr_str("DWORD"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(ijfRetType, kr_str("LONG"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(ijfRetType, kr_str("BOOL"))) ? kr_str("1") : kr_str("0")))) {
                                        char* iwd = kr_plus(kr_plus(kr_str("static char* _krw_"), ijfCName), kr_str("("));
                                        char* iwpi = kr_str("0");
                                        while (kr_truthy(kr_lt(iwpi, ijfPc))) {
                                            if (kr_truthy(kr_gt(iwpi, kr_str("0")))) {
                                                iwd = kr_plus(iwd, kr_str(","));
                                            }
                                            iwd = kr_plus(kr_plus(iwd, kr_str("char* _a")), iwpi);
                                            iwpi = kr_plus(iwpi, kr_str("1"));
                                        }
                                        if (kr_truthy(kr_eq(ijfPc, kr_str("0")))) {
                                            iwd = kr_plus(iwd, kr_str("void"));
                                        }
                                        iwd = kr_plus(kr_plus(kr_plus(iwd, kr_str("){return kr_itoa((int)")), ijfCName), kr_str("("));
                                        iwpi = kr_str("0");
                                        while (kr_truthy(kr_lt(iwpi, ijfPc))) {
                                            if (kr_truthy(kr_gt(iwpi, kr_str("0")))) {
                                                iwd = kr_plus(iwd, kr_str(","));
                                            }
                                            iwd = kr_plus(kr_plus(iwd, kr_str("_a")), iwpi);
                                            iwpi = kr_plus(iwpi, kr_str("1"));
                                        }
                                        iwd = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(iwd, kr_str("));}\n#define ")), ijfCName), kr_str(" _krw_")), ijfCName), kr_str("\n"));
                                        iDecls = kr_plus(iDecls, iwd);
                                    }
                                    if (kr_truthy((kr_truthy(kr_eq(ijfRetType, kr_str("UINT64"))) || kr_truthy(kr_eq(ijfRetType, kr_str("ULONGLONG"))) ? kr_str("1") : kr_str("0")))) {
                                        char* iwd = kr_plus(kr_plus(kr_str("static char* _krw_"), ijfCName), kr_str("("));
                                        char* iwpi = kr_str("0");
                                        while (kr_truthy(kr_lt(iwpi, ijfPc))) {
                                            if (kr_truthy(kr_gt(iwpi, kr_str("0")))) {
                                                iwd = kr_plus(iwd, kr_str(","));
                                            }
                                            iwd = kr_plus(kr_plus(iwd, kr_str("char* _a")), iwpi);
                                            iwpi = kr_plus(iwpi, kr_str("1"));
                                        }
                                        if (kr_truthy(kr_eq(ijfPc, kr_str("0")))) {
                                            iwd = kr_plus(iwd, kr_str("void"));
                                        }
                                        iwd = kr_plus(kr_plus(kr_plus(iwd, kr_str("){char _b[32];snprintf(_b,32,\"%llu\",(unsigned long long)")), ijfCName), kr_str("("));
                                        iwpi = kr_str("0");
                                        while (kr_truthy(kr_lt(iwpi, ijfPc))) {
                                            if (kr_truthy(kr_gt(iwpi, kr_str("0")))) {
                                                iwd = kr_plus(iwd, kr_str(","));
                                            }
                                            iwd = kr_plus(kr_plus(iwd, kr_str("_a")), iwpi);
                                            iwpi = kr_plus(iwpi, kr_str("1"));
                                        }
                                        iwd = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(iwd, kr_str("));return kr_str(_b);}\n#define ")), ijfCName), kr_str(" _krw_")), ijfCName), kr_str("\n"));
                                        iDecls = kr_plus(iDecls, iwd);
                                    }
                                    if (kr_truthy(kr_eq(ijfRetType, kr_str("zero")))) {
                                        char* iwd = kr_plus(kr_plus(kr_str("static char* _krw_"), ijfCName), kr_str("("));
                                        char* iwpi = kr_str("0");
                                        while (kr_truthy(kr_lt(iwpi, ijfPc))) {
                                            if (kr_truthy(kr_gt(iwpi, kr_str("0")))) {
                                                iwd = kr_plus(iwd, kr_str(","));
                                            }
                                            iwd = kr_plus(kr_plus(iwd, kr_str("char* _a")), iwpi);
                                            iwpi = kr_plus(iwpi, kr_str("1"));
                                        }
                                        if (kr_truthy(kr_eq(ijfPc, kr_str("0")))) {
                                            iwd = kr_plus(iwd, kr_str("void"));
                                        }
                                        iwd = kr_plus(kr_plus(kr_plus(iwd, kr_str("){")), ijfCName), kr_str("("));
                                        iwpi = kr_str("0");
                                        while (kr_truthy(kr_lt(iwpi, ijfPc))) {
                                            if (kr_truthy(kr_gt(iwpi, kr_str("0")))) {
                                                iwd = kr_plus(iwd, kr_str(","));
                                            }
                                            iwd = kr_plus(kr_plus(iwd, kr_str("_a")), iwpi);
                                            iwpi = kr_plus(iwpi, kr_str("1"));
                                        }
                                        iwd = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(iwd, kr_str(");return _K_EMPTY;}\n#define ")), ijfCName), kr_str(" _krw_")), ijfCName), kr_str("\n"));
                                        iDecls = kr_plus(iDecls, iwd);
                                    }
                                    ijxtPos = ijfPos;
                                } else {
                                    ijxtPos = kr_plus(ijxtPos, kr_str("2"));
                                }
                            }
                            ij = ((char*(*)(char*,char*))skipBlock)(iToks, kr_plus(ij, kr_str("1")));
                        } else if (kr_truthy((kr_truthy(kr_eq(itk, kr_str("KW:func"))) || kr_truthy(kr_eq(itk, kr_str("KW:fn"))) ? kr_str("1") : kr_str("0")))) {
                            char* iname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(iToks, kr_plus(ij, kr_str("1"))));
                            if (kr_truthy(kr_gt(kr_len(iname), kr_str("0")))) {
                                char* iinfo = ((char*(*)(char*,char*))funcLookup)(iFtable, iname);
                                char* ipc = ((char*(*)(char*))funcParamCount)(iinfo);
                                char* idecl = kr_plus(kr_plus(kr_str("char* "), ((char*(*)(char*))cIdent)(iname)), kr_str("(char*"));
                                char* ipj = kr_str("1");
                                while (kr_truthy(kr_lt(kr_toint(ipj), kr_toint(ipc)))) {
                                    idecl = kr_plus(idecl, kr_str(", char*"));
                                    ipj = kr_plus(ipj, kr_str("1"));
                                }
                                if (kr_truthy(kr_eq(kr_toint(ipc), kr_str("0")))) {
                                    idecl = kr_plus(kr_plus(kr_str("char* "), ((char*(*)(char*))cIdent)(iname)), kr_str("("));
                                }
                                idecl = kr_plus(idecl, kr_str(");\n"));
                                iDecls = kr_plus(iDecls, idecl);
                            }
                        }
                        ij = kr_plus(ij, kr_str("1"));
                    }
                    importFwdDecls = kr_plus(kr_plus(kr_plus(importFwdDecls, kr_str("// --- imported: ")), fullPath), kr_str(" ---\n"));
                    importFwdDecls = kr_plus(importFwdDecls, iDecls);
                    char* iBodies = ((char*(*)(char*,char*,char*))compileImportedFunctions)(iToks, iNtoks, iFtable);
                    importBodies = kr_plus(importBodies, iBodies);
                    if (kr_truthy(kr_eq(irMode, kr_str("1")))) {
                        char* iIRi = kr_str("0");
                        char* iIRinJxt = kr_str("0");
                        while (kr_truthy(kr_lt(iIRi, iNtoks))) {
                            char* iIRtok = ((char*(*)(char*,char*))tokAt)(iToks, iIRi);
                            if (kr_truthy(kr_eq(iIRtok, kr_str("KW:jxt")))) {
                                iIRi = ((char*(*)(char*,char*))skipBlock)(iToks, kr_plus(iIRi, kr_str("1")));
                            } else if (kr_truthy((kr_truthy(kr_eq(iIRtok, kr_str("KW:func"))) || kr_truthy(kr_eq(iIRtok, kr_str("KW:fn"))) ? kr_str("1") : kr_str("0")))) {
                                char* iIRfp = ((char*(*)(char*,char*,char*))irFuncIR)(iToks, iIRi, iNtoks);
                                importedIR = kr_plus(importedIR, ((char*(*)(char*))pairVal)(iIRfp));
                                iIRi = ((char*(*)(char*))pairPos)(iIRfp);
                            } else {
                                iIRi = kr_plus(iIRi, kr_str("1"));
                            }
                        }
                    }
                    if (kr_truthy(kr_gt(kr_len(iFtable), kr_str("0")))) {
                        if (kr_truthy(kr_gt(kr_len(ftable), kr_str("0")))) {
                            ftable = kr_plus(kr_plus(ftable, kr_str("\n")), iFtable);
                        } else {
                            ftable = iFtable;
                        }
                    }
                } else {
                    kr_printerr(kr_plus(kr_str("kcc: import not found: "), fullPath));
                }
            }
            ii = kr_plus(ii, kr_str("2"));
        } else if (kr_truthy(kr_eq(itok, kr_str("KW:jxt")))) {
            char* jxtPos = kr_plus(ii, kr_str("2"));
            char* jxtHasCHeader = kr_str("0");
            while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, jxtPos), kr_str("RBRACE")))) {
                char* lang = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, jxtPos));
                char* jxtPath = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(jxtPos, kr_str("1"))));
                if (kr_truthy(kr_eq(lang, kr_str("k")))) {
                    char* jFullPath = jxtPath;
                    if (kr_truthy(kr_gt(kr_len(baseDir), kr_str("0")))) {
                        if (kr_truthy((kr_truthy(kr_not(kr_startswith(jxtPath, kr_str("/")))) && kr_truthy(kr_not(kr_startswith(jxtPath, kr_str("C:")))) ? kr_str("1") : kr_str("0")))) {
                            jFullPath = kr_plus(baseDir, jxtPath);
                        }
                    }
                    if (kr_truthy(kr_not(kr_contains(imported, kr_plus(jFullPath, kr_str("|")))))) {
                        imported = kr_plus(kr_plus(imported, jFullPath), kr_str("|"));
                        char* jSrc = kr_readfile(jFullPath);
                        if (kr_truthy(kr_gt(kr_len(jSrc), kr_str("0")))) {
                            char* jToks = ((char*(*)(char*))tokenize)(jSrc);
                            char* jNt = kr_linecount(jToks);
                            char* jFt = ((char*(*)(char*,char*))scanFunctions)(jToks, jNt);
                            importFwdDecls = kr_plus(kr_plus(kr_plus(importFwdDecls, kr_str("// --- jxt: ")), jFullPath), kr_str(" ---\n"));
                            importBodies = kr_plus(importBodies, ((char*(*)(char*,char*,char*))compileImportedFunctions)(jToks, jNt, jFt));
                            if (kr_truthy(kr_gt(kr_len(jFt), kr_str("0")))) {
                                if (kr_truthy(kr_gt(kr_len(ftable), kr_str("0")))) {
                                    ftable = kr_plus(kr_plus(ftable, kr_str("\n")), jFt);
                                } else {
                                    ftable = jFt;
                                }
                            }
                        } else {
                            kr_printerr(kr_plus(kr_str("kcc: jxt k not found: "), jFullPath));
                        }
                    }
                } else if (kr_truthy((kr_truthy(kr_eq(lang, kr_str("c"))) || kr_truthy(kr_eq(lang, kr_str("t"))) ? kr_str("1") : kr_str("0")))) {
                    jxtHasCHeader = kr_str("1");
                    char* jIncLine = kr_str("");
                    if (kr_truthy((kr_truthy(kr_contains(jxtPath, kr_str("/"))) || kr_truthy(kr_contains(jxtPath, kr_str("\\"))) ? kr_str("1") : kr_str("0")))) {
                        jIncLine = kr_plus(kr_plus(kr_str("#include \""), jxtPath), kr_str("\"\n"));
                    } else {
                        jIncLine = kr_plus(kr_plus(kr_str("#include <"), jxtPath), kr_str(">\n"));
                    }
                    if (kr_truthy(kr_eq(lang, kr_str("c")))) {
                        importFwdDecls = kr_plus(jIncLine, importFwdDecls);
                    } else {
                        importFwdDecls = kr_plus(importFwdDecls, jIncLine);
                    }
                    jxtPos = kr_plus(jxtPos, kr_str("2"));
                } else if (kr_truthy(kr_eq(lang, kr_str("struct")))) {
                    char* sName = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(jxtPos, kr_str("1"))));
                    char* sfPos = kr_plus(jxtPos, kr_str("3"));
                    char* sEntry = kr_plus(sName, kr_str(":"));
                    char* sfFirst = kr_str("1");
                    char* getBody = kr_str("");
                    char* setBody = kr_str("");
                    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, sfPos), kr_str("RBRACE")))) {
                        if (kr_truthy(kr_eq(((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, sfPos)), kr_str("field")))) {
                            char* sfName = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(sfPos, kr_str("1"))));
                            char* sfType = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(sfPos, kr_str("2"))));
                            char* sfCPath = sfName;
                            if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(sfPos, kr_str("3")))), kr_str("STR")))) {
                                sfCPath = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(sfPos, kr_str("3"))));
                                sfPos = kr_plus(sfPos, kr_str("4"));
                            } else {
                                sfPos = kr_plus(sfPos, kr_str("3"));
                            }
                            if (kr_truthy(kr_eq(sfFirst, kr_str("0")))) {
                                sEntry = kr_plus(sEntry, kr_str(","));
                            }
                            sEntry = kr_plus(kr_plus(kr_plus(sEntry, sfName), kr_str(":")), sfType);
                            sfFirst = kr_str("0");
                            char* getExpr = kr_plus(kr_plus(kr_str("kr_itoa(s->"), sfCPath), kr_str(")"));
                            if (kr_truthy((kr_truthy((kr_truthy(kr_eq(sfType, kr_str("ULONGLONG"))) || kr_truthy(kr_eq(sfType, kr_str("SIZE_T"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(sfType, kr_str("ULONG_PTR"))) ? kr_str("1") : kr_str("0")))) {
                                getExpr = kr_plus(kr_plus(kr_str("({ char _b[32]; snprintf(_b,32,\"%llu\",(unsigned long long)s->"), sfCPath), kr_str("); kr_str(_b); })"));
                            }
                            if (kr_truthy(kr_eq(sfType, kr_str("LONGLONG")))) {
                                getExpr = kr_plus(kr_plus(kr_str("({ char _b[32]; snprintf(_b,32,\"%lld\",(long long)s->"), sfCPath), kr_str("); kr_str(_b); })"));
                            }
                            if (kr_truthy((kr_truthy((kr_truthy(kr_eq(sfType, kr_str("HANDLE"))) || kr_truthy(kr_eq(sfType, kr_str("PVOID"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(sfType, kr_str("LPVOID"))) ? kr_str("1") : kr_str("0")))) {
                                getExpr = kr_plus(kr_plus(kr_str("((char*)s->"), sfCPath), kr_str(")"));
                            }
                            if (kr_truthy(kr_eq(sfType, kr_str("CHAR_ARRAY")))) {
                                getExpr = kr_plus(kr_plus(kr_str("kr_str(s->"), sfCPath), kr_str(")"));
                            }
                            if (kr_truthy((kr_truthy((kr_truthy(kr_eq(sfType, kr_str("BYTE"))) || kr_truthy(kr_eq(sfType, kr_str("UCHAR"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(sfType, kr_str("BOOL"))) ? kr_str("1") : kr_str("0")))) {
                                getExpr = kr_plus(kr_plus(kr_str("kr_itoa((int)(unsigned char)s->"), sfCPath), kr_str(")"));
                            }
                            getBody = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(getBody, kr_str("    if(strcmp(f,\"")), sfName), kr_str("\")==0) return ")), getExpr), kr_str(";\n"));
                            char* setStmt = kr_plus(kr_plus(kr_str("s->"), sfCPath), kr_str("=(DWORD)atoi(v);"));
                            if (kr_truthy((kr_truthy((kr_truthy(kr_eq(sfType, kr_str("ULONGLONG"))) || kr_truthy(kr_eq(sfType, kr_str("SIZE_T"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(sfType, kr_str("ULONG_PTR"))) ? kr_str("1") : kr_str("0")))) {
                                setStmt = kr_plus(kr_plus(kr_str("s->"), sfCPath), kr_str("=(ULONGLONG)atoll(v);"));
                            }
                            if (kr_truthy(kr_eq(sfType, kr_str("LONGLONG")))) {
                                setStmt = kr_plus(kr_plus(kr_str("s->"), sfCPath), kr_str("=(LONGLONG)atoll(v);"));
                            }
                            if (kr_truthy((kr_truthy(kr_eq(sfType, kr_str("WORD"))) || kr_truthy(kr_eq(sfType, kr_str("USHORT"))) ? kr_str("1") : kr_str("0")))) {
                                setStmt = kr_plus(kr_plus(kr_str("s->"), sfCPath), kr_str("=(WORD)atoi(v);"));
                            }
                            if (kr_truthy((kr_truthy((kr_truthy(kr_eq(sfType, kr_str("BYTE"))) || kr_truthy(kr_eq(sfType, kr_str("UCHAR"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(sfType, kr_str("BOOL"))) ? kr_str("1") : kr_str("0")))) {
                                setStmt = kr_plus(kr_plus(kr_str("s->"), sfCPath), kr_str("=(BYTE)atoi(v);"));
                            }
                            if (kr_truthy((kr_truthy(kr_eq(sfType, kr_str("HANDLE"))) || kr_truthy(kr_eq(sfType, kr_str("PVOID"))) ? kr_str("1") : kr_str("0")))) {
                                setStmt = kr_plus(kr_plus(kr_str("s->"), sfCPath), kr_str("=(HANDLE)v;"));
                            }
                            if (kr_truthy(kr_eq(sfType, kr_str("CHAR_ARRAY")))) {
                                setStmt = kr_plus(kr_plus(kr_plus(kr_plus(kr_str("strncpy(s->"), sfCPath), kr_str(",v,sizeof(s->")), sfCPath), kr_str(")-1);"));
                            }
                            setBody = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(setBody, kr_str("    if(strcmp(f,\"")), sfName), kr_str("\")==0){")), setStmt), kr_str(" return _K_EMPTY;}\n"));
                        } else {
                            sfPos = kr_plus(sfPos, kr_str("1"));
                        }
                    }
                    structTable = kr_plus(kr_plus(structTable, sEntry), kr_str("\n"));
                    char* sAccessors = kr_plus(kr_plus(kr_str("static char* structnew_"), sName), kr_str("(void){"));
                    sAccessors = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(sAccessors, sName), kr_str("* s=(")), sName), kr_str("*)_alloc(sizeof(")), sName), kr_str("));"));
                    sAccessors = kr_plus(kr_plus(kr_plus(sAccessors, kr_str("memset(s,0,sizeof(")), sName), kr_str(")); return (char*)s;}\n"));
                    sAccessors = kr_plus(kr_plus(kr_plus(sAccessors, kr_str("static char* structget_")), sName), kr_str("(char* p,char* f){"));
                    sAccessors = kr_plus(kr_plus(kr_plus(kr_plus(sAccessors, sName), kr_str("* s=(")), sName), kr_str("*)p;\n"));
                    sAccessors = kr_plus(sAccessors, getBody);
                    sAccessors = kr_plus(sAccessors, kr_str("    return _K_EMPTY;}\n"));
                    sAccessors = kr_plus(kr_plus(kr_plus(sAccessors, kr_str("static char* structset_")), sName), kr_str("(char* p,char* f,char* v){"));
                    sAccessors = kr_plus(kr_plus(kr_plus(kr_plus(sAccessors, sName), kr_str("* s=(")), sName), kr_str("*)p;\n"));
                    sAccessors = kr_plus(sAccessors, setBody);
                    sAccessors = kr_plus(sAccessors, kr_str("    return _K_EMPTY;}\n"));
                    sAccessors = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(sAccessors, kr_str("static char* structsizeof_")), sName), kr_str("(void){return kr_itoa(sizeof(")), sName), kr_str("));}\n"));
                    importFwdDecls = kr_plus(importFwdDecls, sAccessors);
                    jxtPos = kr_plus(sfPos, kr_str("1"));
                } else if (kr_truthy(kr_eq(lang, kr_str("func")))) {
                    char* jfName = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(jxtPos, kr_str("1"))));
                    char* jfCName = ((char*(*)(char*))cIdent)(jfName);
                    char* jfPos = kr_plus(jxtPos, kr_str("3"));
                    char* jfParams = kr_str("");
                    char* jfPc = kr_str("0");
                    while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, jfPos), kr_str("RPAREN")))) {
                        if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(((char*(*)(char*,char*))tokAt)(tokens, jfPos)), kr_str("ID")))) {
                            if (kr_truthy(kr_gt(jfPc, kr_str("0")))) {
                                jfParams = kr_plus(jfParams, kr_str(","));
                            }
                            jfParams = kr_plus(jfParams, ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, jfPos)));
                            jfPc = kr_plus(jfPc, kr_str("1"));
                        }
                        jfPos = kr_plus(jfPos, kr_str("1"));
                    }
                    if (kr_truthy(kr_eq(jxtHasCHeader, kr_str("0")))) {
                        char* jfDecl = kr_plus(kr_plus(kr_str("char* "), jfCName), kr_str("(char*"));
                        char* jfPi = kr_str("1");
                        while (kr_truthy(kr_lt(jfPi, jfPc))) {
                            jfDecl = kr_plus(jfDecl, kr_str(", char*"));
                            jfPi = kr_plus(jfPi, kr_str("1"));
                        }
                        if (kr_truthy(kr_eq(jfPc, kr_str("0")))) {
                            jfDecl = kr_plus(kr_plus(kr_str("char* "), jfCName), kr_str("("));
                        }
                        jfDecl = kr_plus(jfDecl, kr_str(");\n"));
                        importFwdDecls = kr_plus(importFwdDecls, jfDecl);
                    }
                    char* jfInfo = kr_plus(kr_plus(kr_plus(jfName, kr_str(":")), jfPc), kr_str(":0"));
                    if (kr_truthy(kr_gt(kr_len(ftable), kr_str("0")))) {
                        ftable = kr_plus(kr_plus(ftable, kr_str("\n")), jfInfo);
                    } else {
                        ftable = jfInfo;
                    }
                    jfPos = kr_plus(jfPos, kr_str("1"));
                    char* jfRetType = kr_str("");
                    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, jfPos), kr_str("ARROW")))) {
                        jfRetType = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(jfPos, kr_str("1"))));
                        jfPos = kr_plus(jfPos, kr_str("2"));
                    }
                    if (kr_truthy((kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(jfRetType, kr_str("INT"))) || kr_truthy(kr_eq(jfRetType, kr_str("UINT"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(jfRetType, kr_str("DWORD"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(jfRetType, kr_str("LONG"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(jfRetType, kr_str("BOOL"))) ? kr_str("1") : kr_str("0")))) {
                        char* wd = kr_plus(kr_plus(kr_str("static char* _krw_"), jfCName), kr_str("("));
                        char* wpi = kr_str("0");
                        while (kr_truthy(kr_lt(wpi, jfPc))) {
                            if (kr_truthy(kr_gt(wpi, kr_str("0")))) {
                                wd = kr_plus(wd, kr_str(","));
                            }
                            wd = kr_plus(kr_plus(wd, kr_str("char* _a")), wpi);
                            wpi = kr_plus(wpi, kr_str("1"));
                        }
                        if (kr_truthy(kr_eq(jfPc, kr_str("0")))) {
                            wd = kr_plus(wd, kr_str("void"));
                        }
                        wd = kr_plus(kr_plus(kr_plus(wd, kr_str("){return kr_itoa((int)")), jfCName), kr_str("("));
                        wpi = kr_str("0");
                        while (kr_truthy(kr_lt(wpi, jfPc))) {
                            if (kr_truthy(kr_gt(wpi, kr_str("0")))) {
                                wd = kr_plus(wd, kr_str(","));
                            }
                            wd = kr_plus(kr_plus(wd, kr_str("_a")), wpi);
                            wpi = kr_plus(wpi, kr_str("1"));
                        }
                        wd = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(wd, kr_str(");}\n#define ")), jfCName), kr_str(" _krw_")), jfCName), kr_str("\n"));
                        importFwdDecls = kr_plus(importFwdDecls, wd);
                    }
                    if (kr_truthy((kr_truthy(kr_eq(jfRetType, kr_str("UINT64"))) || kr_truthy(kr_eq(jfRetType, kr_str("ULONGLONG"))) ? kr_str("1") : kr_str("0")))) {
                        char* wd = kr_plus(kr_plus(kr_str("static char* _krw_"), jfCName), kr_str("("));
                        char* wpi = kr_str("0");
                        while (kr_truthy(kr_lt(wpi, jfPc))) {
                            if (kr_truthy(kr_gt(wpi, kr_str("0")))) {
                                wd = kr_plus(wd, kr_str(","));
                            }
                            wd = kr_plus(kr_plus(wd, kr_str("char* _a")), wpi);
                            wpi = kr_plus(wpi, kr_str("1"));
                        }
                        if (kr_truthy(kr_eq(jfPc, kr_str("0")))) {
                            wd = kr_plus(wd, kr_str("void"));
                        }
                        wd = kr_plus(kr_plus(kr_plus(wd, kr_str("){char _b[32];snprintf(_b,32,\"%llu\",(unsigned long long)")), jfCName), kr_str("("));
                        wpi = kr_str("0");
                        while (kr_truthy(kr_lt(wpi, jfPc))) {
                            if (kr_truthy(kr_gt(wpi, kr_str("0")))) {
                                wd = kr_plus(wd, kr_str(","));
                            }
                            wd = kr_plus(kr_plus(wd, kr_str("_a")), wpi);
                            wpi = kr_plus(wpi, kr_str("1"));
                        }
                        wd = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(wd, kr_str("));return kr_str(_b);}\n#define ")), jfCName), kr_str(" _krw_")), jfCName), kr_str("\n"));
                        importFwdDecls = kr_plus(importFwdDecls, wd);
                    }
                    if (kr_truthy(kr_eq(jfRetType, kr_str("zero")))) {
                        char* wd = kr_plus(kr_plus(kr_str("static char* _krw_"), jfCName), kr_str("("));
                        char* wpi = kr_str("0");
                        while (kr_truthy(kr_lt(wpi, jfPc))) {
                            if (kr_truthy(kr_gt(wpi, kr_str("0")))) {
                                wd = kr_plus(wd, kr_str(","));
                            }
                            wd = kr_plus(kr_plus(wd, kr_str("char* _a")), wpi);
                            wpi = kr_plus(wpi, kr_str("1"));
                        }
                        if (kr_truthy(kr_eq(jfPc, kr_str("0")))) {
                            wd = kr_plus(wd, kr_str("void"));
                        }
                        wd = kr_plus(kr_plus(kr_plus(wd, kr_str("){")), jfCName), kr_str("("));
                        wpi = kr_str("0");
                        while (kr_truthy(kr_lt(wpi, jfPc))) {
                            if (kr_truthy(kr_gt(wpi, kr_str("0")))) {
                                wd = kr_plus(wd, kr_str(","));
                            }
                            wd = kr_plus(kr_plus(wd, kr_str("_a")), wpi);
                            wpi = kr_plus(wpi, kr_str("1"));
                        }
                        wd = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(wd, kr_str(");return _K_EMPTY;}\n#define ")), jfCName), kr_str(" _krw_")), jfCName), kr_str("\n"));
                        importFwdDecls = kr_plus(importFwdDecls, wd);
                    }
                    jxtPos = jfPos;
                } else {
                    jxtPos = kr_plus(jxtPos, kr_str("2"));
                }
            }
            ii = kr_plus(jxtPos, kr_str("1"));
        } else {
            ii = kr_plus(ii, kr_str("1"));
        }
    }
    if (kr_truthy(kr_gt(kr_len(importFwdDecls), kr_str("0")))) {
        sb = kr_sbappend(sb, importFwdDecls);
        sb = kr_sbappend(sb, kr_str("\n"));
    }
    if (kr_truthy(kr_gt(kr_len(lambdaBank), kr_str("0")))) {
        sb = kr_sbappend(sb, kr_str("// --- lambda functions ---\n"));
        sb = kr_sbappend(sb, lambdaBank);
    }
    if (kr_truthy(kr_gt(kr_len(importBodies), kr_str("0")))) {
        sb = kr_sbappend(sb, importBodies);
    }
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* tok = ((char*(*)(char*,char*))tokAt)(tokens, i);
        if (kr_truthy((kr_truthy(kr_eq(tok, kr_str("KW:func"))) || kr_truthy(kr_eq(tok, kr_str("KW:fn"))) ? kr_str("1") : kr_str("0")))) {
            char* nameTok = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, kr_str("1")));
            if (kr_truthy(kr_eq(nameTok, kr_str("LPAREN")))) {
                char* lskip = kr_plus(i, kr_str("2"));
                while (kr_truthy((kr_truthy(kr_lt(lskip, ntoks)) && kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, lskip), kr_str("RPAREN"))) ? kr_str("1") : kr_str("0")))) {
                    lskip = kr_plus(lskip, kr_str("1"));
                }
                lskip = kr_plus(lskip, kr_str("1"));
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, lskip), kr_str("ARROW")))) {
                    lskip = kr_plus(lskip, kr_str("2"));
                }
                i = kr_sub(((char*(*)(char*,char*))skipBlock)(tokens, lskip), kr_str("1"));
            }
            char* fname = ((char*(*)(char*))tokVal)(nameTok);
            if (kr_truthy(kr_gt(kr_len(fname), kr_str("0")))) {
                char* info = ((char*(*)(char*,char*))funcLookup)(ftable, fname);
                char* pc = ((char*(*)(char*))funcParamCount)(info);
                char* decl = kr_plus(kr_plus(kr_str("char* "), ((char*(*)(char*))cIdent)(fname)), kr_str("(char*"));
                char* pi = kr_str("1");
                while (kr_truthy(kr_lt(kr_toint(pi), kr_toint(pc)))) {
                    decl = kr_plus(decl, kr_str(", char*"));
                    pi = kr_plus(pi, kr_str("1"));
                }
                if (kr_truthy(kr_eq(kr_toint(pc), kr_str("0")))) {
                    decl = kr_plus(kr_plus(kr_str("char* "), ((char*(*)(char*))cIdent)(fname)), kr_str("("));
                }
                decl = kr_plus(decl, kr_str(");\n"));
                sb = kr_sbappend(sb, decl);
            }
        } else if (kr_truthy(kr_eq(tok, kr_str("KW:callback")))) {
            char* cbSkip = kr_plus(i, kr_str("3"));
            while (kr_truthy((kr_truthy(kr_lt(cbSkip, ntoks)) && kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, cbSkip), kr_str("RPAREN"))) ? kr_str("1") : kr_str("0")))) {
                cbSkip = kr_plus(cbSkip, kr_str("1"));
            }
            cbSkip = kr_plus(cbSkip, kr_str("1"));
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, cbSkip), kr_str("ARROW")))) {
                cbSkip = kr_plus(cbSkip, kr_str("2"));
            }
            i = kr_sub(((char*(*)(char*,char*))skipBlock)(tokens, cbSkip), kr_str("1"));
        } else if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(tok), kr_str("CBLOCK")))) {
        } else if (kr_truthy(kr_eq(tok, kr_str("KW:let")))) {
            char* gfp = kr_plus(i, kr_str("2"));
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, gfp), kr_str("COLON")))) {
                gfp = kr_plus(gfp, kr_str("2"));
            }
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, gfp), kr_str("ASSIGN")))) {
                char* gfv = ((char*(*)(char*,char*,char*))compileExpr)(tokens, kr_plus(gfp, kr_str("1")), ntoks);
                i = kr_sub(((char*(*)(char*))pairPos)(gfv), kr_str("1"));
            } else {
                i = kr_sub(gfp, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(tok, kr_str("KW:jxt")))) {
            i = kr_sub(((char*(*)(char*,char*))skipBlock)(tokens, kr_plus(i, kr_str("1"))), kr_str("1"));
        } else if (kr_truthy(kr_eq(tok, kr_str("KW:export")))) {
        } else if (kr_truthy(kr_eq(tok, kr_str("KW:jxt")))) {
            i = ((char*(*)(char*,char*))skipBlock)(tokens, kr_plus(i, kr_str("1")));
        } else if (kr_truthy((kr_truthy((kr_truthy(kr_eq(tok, kr_str("KW:struct"))) || kr_truthy(kr_eq(tok, kr_str("KW:class"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(tok, kr_str("KW:type"))) ? kr_str("1") : kr_str("0")))) {
            char* sn = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, kr_str("1"))));
            if (kr_truthy(kr_gt(kr_len(sn), kr_str("0")))) {
                sb = kr_sbappend(sb, kr_plus(kr_plus(kr_str("static char* "), ((char*(*)(char*))cIdent)(sn)), kr_str("();\n")));
            }
            i = kr_sub(((char*(*)(char*,char*))skipBlock)(tokens, kr_plus(i, kr_str("2"))), kr_str("1"));
        }
        i = kr_plus(i, kr_str("1"));
    }
    sb = kr_sbappend(sb, kr_str("\n"));
    char* sbGlobals = kr_sbnew();
    char* glDepth = kr_str("0");
    i = kr_str("0");
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* tok = ((char*(*)(char*,char*))tokAt)(tokens, i);
        if (kr_truthy(kr_eq(tok, kr_str("LBRACE")))) {
            glDepth = kr_plus(glDepth, kr_str("1"));
        }
        if (kr_truthy(kr_eq(tok, kr_str("RBRACE")))) {
            glDepth = kr_sub(glDepth, kr_str("1"));
        }
        if (kr_truthy((kr_truthy(kr_eq(tok, kr_str("KW:let"))) && kr_truthy(kr_eq(glDepth, kr_str("0"))) ? kr_str("1") : kr_str("0")))) {
            char* gname = ((char*(*)(char*))cIdent)(((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, kr_str("1")))));
            char* gp = kr_plus(i, kr_str("2"));
            char* gtype = kr_str("str");
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, gp), kr_str("COLON")))) {
                gtype = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(gp, kr_str("1"))));
                gp = kr_plus(gp, kr_str("2"));
            }
            sb = kr_sbappend(sb, kr_plus(kr_plus(kr_str("static char* "), gname), kr_str(" = NULL;\n")));
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, gp), kr_str("ASSIGN")))) {
                gp = kr_plus(gp, kr_str("1"));
                char* gval = ((char*(*)(char*,char*,char*))compileExpr)(tokens, gp, ntoks);
                char* gvalCode = ((char*(*)(char*))pairVal)(gval);
                sbGlobals = kr_sbappend(sbGlobals, kr_plus(kr_plus(kr_plus(kr_plus(kr_str("    "), gname), kr_str(" = ")), gvalCode), kr_str(";\n")));
                i = ((char*(*)(char*))pairPos)(gval);
            } else {
                i = gp;
            }
        } else if (kr_truthy((kr_truthy(kr_eq(tok, kr_str("KW:func"))) || kr_truthy(kr_eq(tok, kr_str("KW:fn"))) ? kr_str("1") : kr_str("0")))) {
            if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, kr_str("1"))), kr_str("LPAREN")))) {
                char* lskip2 = kr_plus(i, kr_str("2"));
                while (kr_truthy((kr_truthy(kr_lt(lskip2, ntoks)) && kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, lskip2), kr_str("RPAREN"))) ? kr_str("1") : kr_str("0")))) {
                    lskip2 = kr_plus(lskip2, kr_str("1"));
                }
                lskip2 = kr_plus(lskip2, kr_str("1"));
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, lskip2), kr_str("ARROW")))) {
                    lskip2 = kr_plus(lskip2, kr_str("2"));
                }
                i = ((char*(*)(char*,char*))skipBlock)(tokens, lskip2);
            } else {
                char* fp = ((char*(*)(char*,char*,char*))compileFunc)(tokens, i, ntoks);
                char* fcode = ((char*(*)(char*))pairVal)(fp);
                sb = kr_sbappend(sb, fcode);
                i = ((char*(*)(char*))pairPos)(fp);
            }
        } else if (kr_truthy(kr_eq(tok, kr_str("KW:callback")))) {
            char* fp = ((char*(*)(char*,char*,char*))compileCallbackFunc)(tokens, kr_plus(i, kr_str("1")), ntoks);
            char* fcode = ((char*(*)(char*))pairVal)(fp);
            sb = kr_sbappend(sb, fcode);
            i = ((char*(*)(char*))pairPos)(fp);
        } else if (kr_truthy(kr_eq(((char*(*)(char*))tokType)(tok), kr_str("CBLOCK")))) {
            char* craw = kr_replace(((char*(*)(char*))tokVal)(tok), kr_str("\\x01"), kr_str("\n"));
            sb = kr_sbappend(sb, kr_plus(craw, kr_str("\n")));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(tok, kr_str("KW:jxt")))) {
            i = kr_sub(((char*(*)(char*,char*))skipBlock)(tokens, kr_plus(i, kr_str("1"))), kr_str("1"));
        } else if (kr_truthy(kr_eq(tok, kr_str("KW:export")))) {
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy((kr_truthy((kr_truthy(kr_eq(tok, kr_str("KW:struct"))) || kr_truthy(kr_eq(tok, kr_str("KW:class"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(tok, kr_str("KW:type"))) ? kr_str("1") : kr_str("0")))) {
            char* sname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(i, kr_str("1"))));
            char* scname = ((char*(*)(char*))cIdent)(sname);
            char* sp2 = kr_plus(i, kr_str("3"));
            char* sfields = kr_str("");
            char* sfc = kr_str("0");
            while (kr_truthy(kr_neq(((char*(*)(char*,char*))tokAt)(tokens, sp2), kr_str("RBRACE")))) {
                if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, sp2), kr_str("KW:let")))) {
                    char* sfname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(sp2, kr_str("1"))));
                    if (kr_truthy(kr_gt(sfc, kr_str("0")))) {
                        sfields = kr_plus(kr_plus(sfields, kr_str(",")), sfname);
                    } else {
                        sfields = sfname;
                    }
                    sfc = kr_plus(sfc, kr_str("1"));
                    sp2 = kr_plus(sp2, kr_str("2"));
                    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, sp2), kr_str("COLON")))) {
                        sp2 = kr_plus(sp2, kr_str("2"));
                    }
                    if (kr_truthy(kr_eq(((char*(*)(char*,char*))tokAt)(tokens, sp2), kr_str("ASSIGN")))) {
                        char* sep = ((char*(*)(char*,char*,char*))compileExpr)(tokens, kr_plus(sp2, kr_str("1")), ntoks);
                        sp2 = ((char*(*)(char*))pairPos)(sep);
                    }
                } else {
                    sp2 = kr_plus(sp2, kr_str("1"));
                }
            }
            char* sout = kr_plus(kr_plus(kr_str("typedef struct "), scname), kr_str("_s {\n"));
            char* si = kr_str("0");
            while (kr_truthy(kr_lt(si, sfc))) {
                char* sfn = ((char*(*)(char*,char*))getNthParam)(sfields, si);
                sout = kr_plus(kr_plus(kr_plus(sout, kr_str("    char* ")), ((char*(*)(char*))cIdent)(sfn)), kr_str(";\n"));
                si = kr_plus(si, kr_str("1"));
            }
            sout = kr_plus(kr_plus(kr_plus(sout, kr_str("} ")), scname), kr_str("_t;\n\n"));
            sout = kr_plus(kr_plus(kr_plus(sout, kr_str("static char* ")), scname), kr_str("() {\n"));
            sout = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(sout, kr_str("    ")), scname), kr_str("_t* _s = (")), scname), kr_str("_t*)_alloc(sizeof(")), scname), kr_str("_t));\n"));
            char* si2 = kr_str("0");
            while (kr_truthy(kr_lt(si2, sfc))) {
                char* sfn2 = ((char*(*)(char*,char*))getNthParam)(sfields, si2);
                sout = kr_plus(kr_plus(kr_plus(sout, kr_str("    _s->")), ((char*(*)(char*))cIdent)(sfn2)), kr_str(" = _K_EMPTY;\n"));
                si2 = kr_plus(si2, kr_str("1"));
            }
            sout = kr_plus(sout, kr_str("    return (char*)_s;\n}\n\n"));
            sb = kr_sbappend(sb, sout);
            i = sp2;
        } else {
            i = kr_plus(i, kr_str("1"));
        }
    }
    char* entry = ((char*(*)(char*,char*))findEntry)(tokens, ntoks);
    if (kr_truthy(kr_lt(entry, kr_str("0")))) {
        if (kr_truthy(irMode)) {
            char* sbIRlib = kr_sbnew();
            sbIRlib = kr_sbappend(sbIRlib, kr_plus(kr_plus(kr_str("; Krypton IR\n; Source: "), file), kr_str("\n\n")));
            sbIRlib = kr_sbappend(sbIRlib, importedIR);
            char* irlibI = kr_str("0");
            while (kr_truthy(kr_lt(irlibI, ntoks))) {
                char* irlibTok = ((char*(*)(char*,char*))tokAt)(tokens, irlibI);
                if (kr_truthy((kr_truthy(kr_eq(irlibTok, kr_str("KW:func"))) || kr_truthy(kr_eq(irlibTok, kr_str("KW:fn"))) ? kr_str("1") : kr_str("0")))) {
                    char* irlibFp = ((char*(*)(char*,char*,char*))irFuncIR)(tokens, irlibI, ntoks);
                    sbIRlib = kr_sbappend(sbIRlib, ((char*(*)(char*))pairVal)(irlibFp));
                    irlibI = ((char*(*)(char*))pairPos)(irlibFp);
                } else if (kr_truthy(kr_eq(irlibTok, kr_str("KW:export")))) {
                    char* irlibNext = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(irlibI, kr_str("1")));
                    if (kr_truthy((kr_truthy(kr_eq(irlibNext, kr_str("KW:func"))) || kr_truthy(kr_eq(irlibNext, kr_str("KW:fn"))) ? kr_str("1") : kr_str("0")))) {
                        char* irlibFname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(irlibI, kr_str("2"))));
                        char* irlibFp = ((char*(*)(char*,char*,char*))irFuncIR)(tokens, kr_plus(irlibI, kr_str("1")), ntoks);
                        sbIRlib = kr_sbappend(sbIRlib, kr_plus(kr_plus(kr_str("EXPORT "), irlibFname), kr_str("\n")));
                        sbIRlib = kr_sbappend(sbIRlib, ((char*(*)(char*))pairVal)(irlibFp));
                        irlibI = ((char*(*)(char*))pairPos)(irlibFp);
                    } else {
                        irlibI = kr_plus(irlibI, kr_str("1"));
                    }
                } else {
                    irlibI = kr_plus(irlibI, kr_str("1"));
                }
            }
            char* irLibText = kr_sbtostring(sbIRlib);
            if (kr_truthy(kr_gt(kr_len(outFile), kr_str("0")))) {
                char* kompilerDir = kr_replace(headersDir, kr_str("headers"), kr_str("bin"));
                char* tmpIR = kr_str("C:\\krypton\\tmp_kcc_build.ir");
                char* tmpOpt = kr_str("C:\\krypton\\tmp_kcc_build_opt.ir");
                kr_writefile(tmpIR, irLibText);
                char* optCmd2 = kr_plus(kr_plus(kr_plus(kr_plus(kompilerDir, kr_str("\\optimize_host.exe ")), tmpIR), kr_str(" > ")), tmpOpt);
                char* codeCmd2 = kr_plus(kr_plus(kr_plus(kr_plus(kompilerDir, kr_str("\\x64_host_new.exe ")), tmpOpt), kr_str(" ")), outFile);
                kr_shellrun(optCmd2);
                kr_shellrun(codeCmd2);
                kr_deletefile(tmpIR);
                kr_deletefile(tmpOpt);
                return atoi(kr_str("0"));
            }
            kr_print(irLibText);
            return atoi(kr_str("0"));
        }
        kr_print(kr_sbtostring(sb));
        return atoi(kr_str("0"));
    }
    sb = kr_sbappend(sb, kr_str("int main(int argc, char** argv) {\n"));
    sb = kr_sbappend(sb, kr_str("    _argc = argc; _argv = argv;\n"));
    sb = kr_sbappend(sb, kr_str("    srand((unsigned)time(NULL));\n"));
    char* globInitCode = kr_sbtostring(sbGlobals);
    if (kr_truthy(kr_gt(kr_len(globInitCode), kr_str("0")))) {
        sb = kr_sbappend(sb, globInitCode);
    }
    char* bp = ((char*(*)(char*,char*,char*,char*,char*))compileBlock)(tokens, entry, ntoks, kr_str("0"), kr_str("0"));
    char* bcode = ((char*(*)(char*))pairVal)(bp);
    sb = kr_sbappend(sb, bcode);
    sb = kr_sbappend(sb, kr_str("    return 0;\n"));
    sb = kr_sbappend(sb, kr_str("}\n"));
    if (kr_truthy(irMode)) {
        char* sbIR = kr_sbnew();
        sbIR = kr_sbappend(sbIR, kr_plus(kr_plus(kr_str("; Krypton IR\n; Source: "), file), kr_str("\n\n")));
        sbIR = kr_sbappend(sbIR, importedIR);
        char* iri = kr_str("0");
        while (kr_truthy(kr_lt(iri, ntoks))) {
            char* irtok = ((char*(*)(char*,char*))tokAt)(tokens, iri);
            if (kr_truthy((kr_truthy(kr_eq(irtok, kr_str("KW:func"))) || kr_truthy(kr_eq(irtok, kr_str("KW:fn"))) ? kr_str("1") : kr_str("0")))) {
                char* fp = ((char*(*)(char*,char*,char*))irFuncIR)(tokens, iri, ntoks);
                sbIR = kr_sbappend(sbIR, ((char*(*)(char*))pairVal)(fp));
                iri = ((char*(*)(char*))pairPos)(fp);
            } else if (kr_truthy(kr_eq(irtok, kr_str("KW:export")))) {
                char* expNext = ((char*(*)(char*,char*))tokAt)(tokens, kr_plus(iri, kr_str("1")));
                if (kr_truthy((kr_truthy(kr_eq(expNext, kr_str("KW:func"))) || kr_truthy(kr_eq(expNext, kr_str("KW:fn"))) ? kr_str("1") : kr_str("0")))) {
                    char* expFname = ((char*(*)(char*))tokVal)(((char*(*)(char*,char*))tokAt)(tokens, kr_plus(iri, kr_str("2"))));
                    char* efp = ((char*(*)(char*,char*,char*))irFuncIR)(tokens, kr_plus(iri, kr_str("1")), ntoks);
                    sbIR = kr_sbappend(sbIR, kr_plus(kr_plus(kr_str("EXPORT "), expFname), kr_str("\n")));
                    sbIR = kr_sbappend(sbIR, ((char*(*)(char*))pairVal)(efp));
                    iri = ((char*(*)(char*))pairPos)(efp);
                } else {
                    iri = kr_plus(iri, kr_str("1"));
                }
            } else {
                iri = kr_plus(iri, kr_str("1"));
            }
        }
        char* irEntry = ((char*(*)(char*,char*))findEntry)(tokens, ntoks);
        if (kr_truthy(kr_gte(irEntry, kr_str("0")))) {
            char* ep = ((char*(*)(char*,char*,char*,char*,char*))irBlockIR)(tokens, irEntry, ntoks, kr_str("0"), kr_str("0"));
            sbIR = kr_sbappend(sbIR, kr_plus(kr_plus(kr_str("FUNC __main__ 0\n"), ((char*(*)(char*))pairVal)(ep)), kr_str("END\n")));
        }
        char* irText = kr_sbtostring(sbIR);
        if (kr_truthy(kr_gt(kr_len(outFile), kr_str("0")))) {
            char* kompilerDir = kr_replace(headersDir, kr_str("headers"), kr_str("bin"));
            char* tmpIR = kr_str("C:\\krypton\\tmp_kcc_build.ir");
            char* tmpOpt = kr_str("C:\\krypton\\tmp_kcc_build_opt.ir");
            kr_writefile(tmpIR, irText);
            char* optCmd = kr_plus(kr_plus(kr_plus(kr_plus(kompilerDir, kr_str("\\optimize_host.exe ")), tmpIR), kr_str(" > ")), tmpOpt);
            char* codeCmd = kr_plus(kr_plus(kr_plus(kr_plus(kompilerDir, kr_str("\\x64_host_new.exe ")), tmpOpt), kr_str(" ")), outFile);
            kr_shellrun(optCmd);
            kr_shellrun(codeCmd);
            kr_deletefile(tmpIR);
            kr_deletefile(tmpOpt);
            return atoi(kr_str("0"));
        }
        kr_print(irText);
        return atoi(kr_str("0"));
    }
    kr_print(kr_sbtostring(sb));
    return 0;
}

