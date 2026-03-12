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
    } else if (kr_truthy(kr_eq(word, kr_str("module")))) {
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
            out = kr_plus(out, kr_str("PLUS\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str("-")))) {
            if (kr_truthy((kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(text))) && kr_truthy(kr_eq(kr_idx(text, kr_atoi(kr_plus(i, kr_str("1")))), kr_str(">"))) ? kr_str("1") : kr_str("0")))) {
                out = kr_plus(out, kr_str("ARROW\n"));
                i = kr_plus(i, kr_str("2"));
            } else {
                out = kr_plus(out, kr_str("MINUS\n"));
                i = kr_plus(i, kr_str("1"));
            }
        } else if (kr_truthy(kr_eq(c, kr_str("*")))) {
            out = kr_plus(out, kr_str("STAR\n"));
            i = kr_plus(i, kr_str("1"));
        } else if (kr_truthy(kr_eq(c, kr_str("/")))) {
            out = kr_plus(out, kr_str("SLASH\n"));
            i = kr_plus(i, kr_str("1"));
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
            out = kr_plus(out, kr_str("MOD\n"));
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
    while (kr_truthy(kr_lt(i, kr_len(s)))) {
        char* c = kr_idx(s, kr_atoi(i));
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
        } else {
            out = kr_plus(out, c);
        }
        i = kr_plus(i, kr_str("1"));
    }
    return out;
}

char* expandEscapes(char* s) {
    char* out = kr_str("");
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, kr_len(s)))) {
        if (kr_truthy(kr_eq(kr_idx(s, kr_atoi(i)), kr_str("\\")))) {
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
        } else {
            out = kr_plus(out, kr_idx(s, kr_atoi(i)));
        }
        i = kr_plus(i, kr_str("1"));
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
    return compileOr(tokens, pos, ntoks);
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
    while (kr_truthy((kr_truthy((kr_truthy(kr_eq(tokAt(tokens, p), kr_str("STAR"))) || kr_truthy(kr_eq(tokAt(tokens, p), kr_str("SLASH"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(tokAt(tokens, p), kr_str("PERCENT"))) ? kr_str("1") : kr_str("0")))) {
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
    return kr_plus(kr_plus(kr_plus(kr_plus(cIdent(fname), kr_str("(")), args), kr_str("),")), p);
}

char* compileStmt(char* tokens, char* pos, char* ntoks, char* depth, char* inFunc) {
    char* tok = tokAt(tokens, pos);
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
    if (kr_truthy(kr_eq(tok, kr_str("KW:break")))) {
        char* p = kr_plus(pos, kr_str("1"));
        if (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("SEMI")))) {
            p = kr_plus(p, kr_str("1"));
        }
        return kr_plus(kr_plus(indent(depth), kr_str("break;\n,")), p);
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
        kr_print(kr_str("No entry point found"));
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
    return 0;
}

