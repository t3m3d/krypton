#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char _arena[4*1024*1024];
static int _apos = 0;
static int _argc; static char** _argv;

static char* _alloc(int n) {
    char* p = _arena + _apos;
    _apos += n;
    return p;
}

static char* kr_str(const char* s) {
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
static char* kr_not(const char* a) { return kr_str(atoi(a) ? "0" : "1"); }

static char* kr_eq(const char* a, const char* b) {
    return kr_str(strcmp(a, b) == 0 ? "1" : "0");
}
static char* kr_neq(const char* a, const char* b) {
    return kr_str(strcmp(a, b) != 0 ? "1" : "0");
}
static char* kr_lt(const char* a, const char* b) {
    if (kr_isnum(a) && kr_isnum(b)) return kr_str(atoi(a) < atoi(b) ? "1" : "0");
    return kr_str(strcmp(a, b) < 0 ? "1" : "0");
}
static char* kr_gt(const char* a, const char* b) {
    if (kr_isnum(a) && kr_isnum(b)) return kr_str(atoi(a) > atoi(b) ? "1" : "0");
    return kr_str(strcmp(a, b) > 0 ? "1" : "0");
}
static char* kr_lte(const char* a, const char* b) {
    return kr_str(strcmp(kr_gt(a, b), "0") == 0 ? "1" : "0");
}
static char* kr_gte(const char* a, const char* b) {
    return kr_str(strcmp(kr_lt(a, b), "0") == 0 ? "1" : "0");
}

static int kr_truthy(const char* s) {
    if (!s || !*s) return 0;
    if (strcmp(s, "0") == 0) return 0;
    return 1;
}

static char* kr_print(const char* s) {
    printf("%s\n", s);
    return kr_str("");
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
    return kr_str(strncmp(s, prefix, strlen(prefix)) == 0 ? "1" : "0");
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

char* add(char*, char*);
char* greet(char*);

char* add(char* a, char* b) {
    return kr_plus(a, b);
}

char* greet(char* name) {
    return kr_plus(kr_str("Hello, "), name);
}

int main(int argc, char** argv) {
    _argc = argc; _argv = argv;
    char* x = add(kr_str("3"), kr_str("4"));
    kr_print(x);
    char* msg = greet(kr_str("Krypton"));
    kr_print(msg);
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, kr_str("5")))) {
        kr_print(i);
        i = kr_plus(i, kr_str("1"));
    }
    char* val = kr_str("42");
    if (kr_truthy(kr_eq(val, kr_str("42")))) {
        kr_print(kr_str("found it"));
    } else if (kr_truthy(kr_eq(val, kr_str("0")))) {
        kr_print(kr_str("zero"));
    } else {
        kr_print(kr_str("other"));
    }
    char* s = kr_str("abc");
    kr_print(kr_idx(s, kr_atoi(kr_str("0"))));
    kr_print(kr_idx(s, kr_atoi(kr_str("1"))));
    kr_print(kr_idx(s, kr_atoi(kr_str("2"))));
    if (kr_truthy(kr_gt(kr_str("10"), kr_str("5")))) {
        kr_print(kr_str("10 > 5"));
    }
    char* pair = kr_str("hello,world");
    char* first = kr_split(pair, kr_str("0"));
    char* second = kr_split(pair, kr_str("1"));
    kr_print(first);
    kr_print(second);
    if (kr_truthy(kr_startswith(kr_str("hello world"), kr_str("hello")))) {
        kr_print(kr_str("starts with hello"));
    }
    kr_print(kr_len(kr_str("test")));
    return 0;
    return 0;
}

