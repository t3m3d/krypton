#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int _argc; static char** _argv;

static char* _alloc(int n) {
    char* p = (char*)malloc(n);
    if (!p) { fprintf(stderr, "out of memory\n"); exit(1); }
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

char* findLastComma(char*);
char* pairVal(char*);
char* pairPos(char*);
char* tokAt(char*, char*);
char* tokType(char*);
char* tokVal(char*);
char* expandEscapes(char*);
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
char* envGet(char*, char*);
char* envSet(char*, char*, char*);
char* scanFunctions(char*, char*);
char* funcLookup(char*, char*);
char* funcParamCount(char*);
char* funcParams(char*);
char* funcStart(char*);
char* getNthParam(char*, char*);
char* findEntry(char*, char*);
char* skipBlock(char*, char*);
char* evalExpr(char*, char*, char*, char*);
char* evalOr(char*, char*, char*, char*);
char* evalAnd(char*, char*, char*, char*);
char* evalEquality(char*, char*, char*, char*);
char* evalRelational(char*, char*, char*, char*);
char* evalAdditive(char*, char*, char*, char*);
char* evalMult(char*, char*, char*, char*);
char* evalUnary(char*, char*, char*, char*);
char* evalPostfix(char*, char*, char*, char*);
char* evalPrimary(char*, char*, char*, char*);
char* evalCall(char*, char*, char*, char*);
char* getArg(char*, char*);
char* makeResult(char*, char*, char*, char*);
char* getResultTag(char*);
char* getResultVal(char*);
char* getResultEnv(char*);
char* getResultPos(char*);
char* isTruthy(char*);
char* execBlock(char*, char*, char*, char*);
char* execStmt(char*, char*, char*, char*);
char* execLet(char*, char*, char*, char*);
char* execAssign(char*, char*, char*, char*);
char* execEmit(char*, char*, char*, char*);
char* execIf(char*, char*, char*, char*);
char* execWhile(char*, char*, char*, char*);
char* execExprStmt(char*, char*, char*, char*);

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
    if (kr_truthy(kr_lt(c, kr_str("0")))) {
        return kr_str("0");
    }
    return kr_toint(kr_substr(pair, kr_plus(c, kr_str("1")), kr_len(pair)));
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

char* expandEscapes(char* s) {
    char* r = kr_str("");
    char* i = kr_str("0");
    char* start = kr_str("0");
    while (kr_truthy(kr_lt(i, kr_len(s)))) {
        if (kr_truthy((kr_truthy(kr_eq(kr_idx(s, kr_atoi(i)), kr_str("\\"))) && kr_truthy(kr_lt(kr_plus(i, kr_str("1")), kr_len(s))) ? kr_str("1") : kr_str("0")))) {
            if (kr_truthy(kr_gt(i, start))) {
                r = kr_plus(r, kr_substr(s, start, i));
            }
            char* nc = kr_idx(s, kr_atoi(kr_plus(i, kr_str("1"))));
            if (kr_truthy(kr_eq(nc, kr_str("n")))) {
                r = kr_plus(r, kr_str("\n"));
            } else if (kr_truthy(kr_eq(nc, kr_str("t")))) {
                r = kr_plus(r, kr_str("\t"));
            } else if (kr_truthy(kr_eq(nc, kr_str("\\")))) {
                r = kr_plus(r, kr_str("\\"));
            } else if (kr_truthy(kr_eq(nc, kr_str("\"")))) {
                r = kr_plus(r, kr_str("\""));
            } else {
                r = kr_plus(r, kr_substr(s, i, kr_plus(i, kr_str("1"))));
            }
            i = kr_plus(i, kr_str("2"));
            start = i;
        } else {
            i = kr_plus(i, kr_str("1"));
        }
    }
    if (kr_truthy(kr_gt(i, start))) {
        r = kr_plus(r, kr_substr(s, start, i));
    }
    return r;
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
        } else {
            i = kr_plus(i, kr_str("1"));
        }
    }
    return out;
}

char* envGet(char* env, char* name) {
    char* result = kr_str("");
    char* found = kr_str("0");
    char* i = kr_str("0");
    char* lineStart = kr_str("0");
    while (kr_truthy(kr_lte(i, kr_len(env)))) {
        if (kr_truthy((kr_truthy(kr_eq(i, kr_len(env))) || kr_truthy(kr_eq(kr_idx(env, kr_atoi(i)), kr_str("\n"))) ? kr_str("1") : kr_str("0")))) {
            char* line = kr_substr(env, lineStart, i);
            char* eqPos = kr_neg(kr_str("1"));
            char* j = kr_str("0");
            while (kr_truthy(kr_lt(j, kr_len(line)))) {
                if (kr_truthy((kr_truthy(kr_eq(kr_idx(line, kr_atoi(j)), kr_str("="))) && kr_truthy(kr_eq(eqPos, kr_neg(kr_str("1")))) ? kr_str("1") : kr_str("0")))) {
                    eqPos = j;
                }
                j = kr_plus(j, kr_str("1"));
            }
            if (kr_truthy(kr_gt(eqPos, kr_str("0")))) {
                char* k = kr_substr(line, kr_str("0"), eqPos);
                if (kr_truthy(kr_eq(k, name))) {
                    result = kr_substr(line, kr_plus(eqPos, kr_str("1")), kr_len(line));
                    found = kr_str("1");
                }
            }
            lineStart = kr_plus(i, kr_str("1"));
        }
        i = kr_plus(i, kr_str("1"));
    }
    if (kr_truthy(kr_eq(found, kr_str("0")))) {
        if (kr_truthy(kr_neq(name, kr_str("__argOffset")))) {
            kr_print(kr_plus(kr_str("ERROR: undefined variable: "), name));
        }
    }
    char* unescaped = kr_str("");
    char* ui = kr_str("0");
    char* ustart = kr_str("0");
    while (kr_truthy(kr_lt(ui, kr_len(result)))) {
        if (kr_truthy((kr_truthy(kr_eq(kr_idx(result, kr_atoi(ui)), kr_str("\\"))) && kr_truthy(kr_lt(kr_plus(ui, kr_str("1")), kr_len(result))) ? kr_str("1") : kr_str("0")))) {
            if (kr_truthy(kr_gt(ui, ustart))) {
                unescaped = kr_plus(unescaped, kr_substr(result, ustart, ui));
            }
            if (kr_truthy(kr_eq(kr_idx(result, kr_atoi(kr_plus(ui, kr_str("1")))), kr_str("n")))) {
                unescaped = kr_plus(unescaped, kr_str("\n"));
            } else if (kr_truthy(kr_eq(kr_idx(result, kr_atoi(kr_plus(ui, kr_str("1")))), kr_str("\\")))) {
                unescaped = kr_plus(unescaped, kr_str("\\"));
            } else {
                unescaped = kr_plus(unescaped, kr_substr(result, ui, kr_plus(ui, kr_str("1"))));
            }
            ui = kr_plus(ui, kr_str("2"));
            ustart = ui;
        } else {
            ui = kr_plus(ui, kr_str("1"));
        }
    }
    if (kr_truthy(kr_gt(ui, ustart))) {
        unescaped = kr_plus(unescaped, kr_substr(result, ustart, ui));
    }
    return unescaped;
}

char* envSet(char* env, char* name, char* val) {
    char* escaped = kr_str("");
    char* ei = kr_str("0");
    char* estart = kr_str("0");
    while (kr_truthy(kr_lt(ei, kr_len(val)))) {
        if (kr_truthy(kr_eq(kr_idx(val, kr_atoi(ei)), kr_str("\\")))) {
            if (kr_truthy(kr_gt(ei, estart))) {
                escaped = kr_plus(escaped, kr_substr(val, estart, ei));
            }
            escaped = kr_plus(escaped, kr_str("\\\\"));
            ei = kr_plus(ei, kr_str("1"));
            estart = ei;
        } else if (kr_truthy(kr_eq(kr_idx(val, kr_atoi(ei)), kr_str("\n")))) {
            if (kr_truthy(kr_gt(ei, estart))) {
                escaped = kr_plus(escaped, kr_substr(val, estart, ei));
            }
            escaped = kr_plus(escaped, kr_str("\\n"));
            ei = kr_plus(ei, kr_str("1"));
            estart = ei;
        } else {
            ei = kr_plus(ei, kr_str("1"));
        }
    }
    if (kr_truthy(kr_gt(ei, estart))) {
        escaped = kr_plus(escaped, kr_substr(val, estart, ei));
    }
    return kr_plus(kr_plus(kr_plus(kr_plus(env, name), kr_str("=")), escaped), kr_str("\n"));
}

char* scanFunctions(char* tokens, char* ntoks) {
    char* table = kr_str("");
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* tok = tokAt(tokens, i);
        if (kr_truthy((kr_truthy(kr_eq(tok, kr_str("KW:func"))) || kr_truthy(kr_eq(tok, kr_str("KW:fn"))) ? kr_str("1") : kr_str("0")))) {
            char* nameTok = tokAt(tokens, kr_plus(i, kr_str("1")));
            char* fname = tokVal(nameTok);
            char* pi = kr_plus(i, kr_str("3"));
            char* params = kr_str("");
            char* pc = kr_str("0");
            while (kr_truthy(kr_neq(tokAt(tokens, pi), kr_str("RPAREN")))) {
                if (kr_truthy(kr_eq(tokType(tokAt(tokens, pi)), kr_str("ID")))) {
                    if (kr_truthy(kr_gt(pc, kr_str("0")))) {
                        params = kr_plus(kr_plus(params, kr_str(",")), tokVal(tokAt(tokens, pi)));
                    } else {
                        params = tokVal(tokAt(tokens, pi));
                    }
                    pc = kr_plus(pc, kr_str("1"));
                }
                pi = kr_plus(pi, kr_str("1"));
            }
            pi = kr_plus(pi, kr_str("1"));
            while (kr_truthy(kr_neq(tokAt(tokens, pi), kr_str("LBRACE")))) {
                pi = kr_plus(pi, kr_str("1"));
            }
            table = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(table, fname), kr_str("~")), pc), kr_str("~")), params), kr_str("~")), pi), kr_str("\n"));
            i = pi;
            char* depth = kr_str("0");
            while (kr_truthy(kr_lt(i, ntoks))) {
                char* t = tokAt(tokens, i);
                if (kr_truthy(kr_eq(t, kr_str("LBRACE")))) {
                    depth = kr_plus(depth, kr_str("1"));
                } else if (kr_truthy(kr_eq(t, kr_str("RBRACE")))) {
                    depth = kr_sub(depth, kr_str("1"));
                    if (kr_truthy(kr_eq(depth, kr_str("0")))) {
                        i = kr_plus(i, kr_str("1"));
                        break;
                    }
                }
                i = kr_plus(i, kr_str("1"));
            }
        } else {
            i = kr_plus(i, kr_str("1"));
        }
    }
    return table;
}

char* funcLookup(char* table, char* name) {
    char* i = kr_str("0");
    char* lineStart = kr_str("0");
    while (kr_truthy(kr_lte(i, kr_len(table)))) {
        if (kr_truthy((kr_truthy(kr_eq(i, kr_len(table))) || kr_truthy(kr_eq(kr_idx(table, kr_atoi(i)), kr_str("\n"))) ? kr_str("1") : kr_str("0")))) {
            char* line = kr_substr(table, lineStart, i);
            char* t1 = kr_neg(kr_str("1"));
            char* j = kr_str("0");
            while (kr_truthy(kr_lt(j, kr_len(line)))) {
                if (kr_truthy((kr_truthy(kr_eq(kr_idx(line, kr_atoi(j)), kr_str("~"))) && kr_truthy(kr_eq(t1, kr_neg(kr_str("1")))) ? kr_str("1") : kr_str("0")))) {
                    t1 = j;
                }
                j = kr_plus(j, kr_str("1"));
            }
            if (kr_truthy(kr_gt(t1, kr_str("0")))) {
                char* fName = kr_substr(line, kr_str("0"), t1);
                if (kr_truthy(kr_eq(fName, name))) {
                    return kr_substr(line, kr_plus(t1, kr_str("1")), kr_len(line));
                }
            }
            lineStart = kr_plus(i, kr_str("1"));
        }
        i = kr_plus(i, kr_str("1"));
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
    char* t1 = kr_neg(kr_str("1"));
    char* t2 = kr_neg(kr_str("1"));
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, kr_len(info)))) {
        if (kr_truthy(kr_eq(kr_idx(info, kr_atoi(i)), kr_str("~")))) {
            if (kr_truthy(kr_eq(t1, kr_neg(kr_str("1"))))) {
                t1 = i;
            } else if (kr_truthy(kr_eq(t2, kr_neg(kr_str("1"))))) {
                t2 = i;
            }
        }
        i = kr_plus(i, kr_str("1"));
    }
    if (kr_truthy((kr_truthy(kr_gte(t1, kr_str("0"))) && kr_truthy(kr_gte(t2, kr_str("0"))) ? kr_str("1") : kr_str("0")))) {
        return kr_substr(info, kr_plus(t1, kr_str("1")), t2);
    }
    return kr_str("");
}

char* funcStart(char* info) {
    char* last = kr_neg(kr_str("1"));
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, kr_len(info)))) {
        if (kr_truthy(kr_eq(kr_idx(info, kr_atoi(i)), kr_str("~")))) {
            last = i;
        }
        i = kr_plus(i, kr_str("1"));
    }
    if (kr_truthy(kr_gte(last, kr_str("0")))) {
        return kr_toint(kr_substr(info, kr_plus(last, kr_str("1")), kr_len(info)));
    }
    return kr_str("0");
}

char* getNthParam(char* params, char* idx) {
    char* n = kr_str("0");
    char* start = kr_str("0");
    char* i = kr_str("0");
    while (kr_truthy(kr_lte(i, kr_len(params)))) {
        if (kr_truthy((kr_truthy(kr_eq(i, kr_len(params))) || kr_truthy(kr_eq(kr_idx(params, kr_atoi(i)), kr_str(","))) ? kr_str("1") : kr_str("0")))) {
            if (kr_truthy(kr_eq(n, idx))) {
                return kr_substr(params, start, i);
            }
            n = kr_plus(n, kr_str("1"));
            start = kr_plus(i, kr_str("1"));
        }
        i = kr_plus(i, kr_str("1"));
    }
    return kr_str("");
}

char* findEntry(char* tokens, char* ntoks) {
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(kr_plus(i, kr_str("2")), ntoks))) {
        char* t0 = tokAt(tokens, i);
        char* t1 = tokAt(tokens, kr_plus(i, kr_str("1")));
        char* t2 = tokAt(tokens, kr_plus(i, kr_str("2")));
        if (kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(t0, kr_str("KW:go"))) || kr_truthy(kr_eq(t0, kr_str("KW:just"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_eq(t1, kr_str("ID:run"))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_eq(t2, kr_str("LBRACE"))) ? kr_str("1") : kr_str("0")))) {
            return kr_plus(i, kr_str("2"));
        }
        i = kr_plus(i, kr_str("1"));
    }
    kr_print(kr_str("ERROR: no 'go run' or 'just run' block found"));
    return kr_neg(kr_str("1"));
}

char* skipBlock(char* tokens, char* pos) {
    char* depth = kr_str("0");
    char* i = pos;
    char* ntoks = kr_linecount(tokens);
    while (kr_truthy(kr_lt(i, ntoks))) {
        char* t = tokAt(tokens, i);
        if (kr_truthy(kr_eq(t, kr_str("LBRACE")))) {
            depth = kr_plus(depth, kr_str("1"));
        } else if (kr_truthy(kr_eq(t, kr_str("RBRACE")))) {
            depth = kr_sub(depth, kr_str("1"));
            if (kr_truthy(kr_eq(depth, kr_str("0")))) {
                return kr_plus(i, kr_str("1"));
            }
        }
        i = kr_plus(i, kr_str("1"));
    }
    return i;
}

char* evalExpr(char* tokens, char* pos, char* env, char* ftable) {
    return evalOr(tokens, pos, env, ftable);
}

char* evalOr(char* tokens, char* pos, char* env, char* ftable) {
    char* pair = evalAnd(tokens, pos, env, ftable);
    char* left = pairVal(pair);
    char* p = pairPos(pair);
    while (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("OR")))) {
        char* pair2 = evalAnd(tokens, kr_plus(p, kr_str("1")), env, ftable);
        char* right = pairVal(pair2);
        p = pairPos(pair2);
        if (kr_truthy((kr_truthy((kr_truthy(kr_neq(left, kr_str("0"))) && kr_truthy(kr_neq(left, kr_str(""))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_neq(left, kr_str("false"))) ? kr_str("1") : kr_str("0")))) {
            left = kr_str("1");
        } else if (kr_truthy((kr_truthy((kr_truthy(kr_neq(right, kr_str("0"))) && kr_truthy(kr_neq(right, kr_str(""))) ? kr_str("1") : kr_str("0"))) && kr_truthy(kr_neq(right, kr_str("false"))) ? kr_str("1") : kr_str("0")))) {
            left = kr_str("1");
        } else {
            left = kr_str("0");
        }
    }
    return kr_plus(kr_plus(left, kr_str(",")), p);
}

char* evalAnd(char* tokens, char* pos, char* env, char* ftable) {
    char* pair = evalEquality(tokens, pos, env, ftable);
    char* left = pairVal(pair);
    char* p = pairPos(pair);
    while (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("AND")))) {
        char* pair2 = evalEquality(tokens, kr_plus(p, kr_str("1")), env, ftable);
        char* right = pairVal(pair2);
        p = pairPos(pair2);
        if (kr_truthy((kr_truthy((kr_truthy(kr_eq(left, kr_str("0"))) || kr_truthy(kr_eq(left, kr_str(""))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(left, kr_str("false"))) ? kr_str("1") : kr_str("0")))) {
            left = kr_str("0");
        } else if (kr_truthy((kr_truthy((kr_truthy(kr_eq(right, kr_str("0"))) || kr_truthy(kr_eq(right, kr_str(""))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(right, kr_str("false"))) ? kr_str("1") : kr_str("0")))) {
            left = kr_str("0");
        } else {
            left = kr_str("1");
        }
    }
    return kr_plus(kr_plus(left, kr_str(",")), p);
}

char* evalEquality(char* tokens, char* pos, char* env, char* ftable) {
    char* pair = evalRelational(tokens, pos, env, ftable);
    char* left = pairVal(pair);
    char* p = pairPos(pair);
    while (kr_truthy((kr_truthy(kr_eq(tokAt(tokens, p), kr_str("EQ"))) || kr_truthy(kr_eq(tokAt(tokens, p), kr_str("NEQ"))) ? kr_str("1") : kr_str("0")))) {
        char* op = tokAt(tokens, p);
        char* pair2 = evalRelational(tokens, kr_plus(p, kr_str("1")), env, ftable);
        char* right = pairVal(pair2);
        p = pairPos(pair2);
        if (kr_truthy(kr_eq(op, kr_str("EQ")))) {
            if (kr_truthy(kr_eq(left, right))) {
                left = kr_str("1");
            } else {
                left = kr_str("0");
            }
        } else {
            if (kr_truthy(kr_neq(left, right))) {
                left = kr_str("1");
            } else {
                left = kr_str("0");
            }
        }
    }
    return kr_plus(kr_plus(left, kr_str(",")), p);
}

char* evalRelational(char* tokens, char* pos, char* env, char* ftable) {
    char* pair = evalAdditive(tokens, pos, env, ftable);
    char* left = pairVal(pair);
    char* p = pairPos(pair);
    while (kr_truthy((kr_truthy((kr_truthy((kr_truthy(kr_eq(tokAt(tokens, p), kr_str("LT"))) || kr_truthy(kr_eq(tokAt(tokens, p), kr_str("GT"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(tokAt(tokens, p), kr_str("LTE"))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(tokAt(tokens, p), kr_str("GTE"))) ? kr_str("1") : kr_str("0")))) {
        char* op = tokAt(tokens, p);
        char* pair2 = evalAdditive(tokens, kr_plus(p, kr_str("1")), env, ftable);
        char* right = pairVal(pair2);
        p = pairPos(pair2);
        char* li = kr_toint(left);
        char* ri = kr_toint(right);
        char* numL = kr_eq(kr_plus(li, kr_str("")), left);
        char* numR = kr_eq(kr_plus(ri, kr_str("")), right);
        if (kr_truthy((kr_truthy(numL) && kr_truthy(numR) ? kr_str("1") : kr_str("0")))) {
            if (kr_truthy(kr_eq(op, kr_str("LT")))) {
                if (kr_truthy(kr_lt(li, ri))) {
                    left = kr_str("1");
                } else {
                    left = kr_str("0");
                }
            } else if (kr_truthy(kr_eq(op, kr_str("GT")))) {
                if (kr_truthy(kr_gt(li, ri))) {
                    left = kr_str("1");
                } else {
                    left = kr_str("0");
                }
            } else if (kr_truthy(kr_eq(op, kr_str("LTE")))) {
                if (kr_truthy(kr_lte(li, ri))) {
                    left = kr_str("1");
                } else {
                    left = kr_str("0");
                }
            } else {
                if (kr_truthy(kr_gte(li, ri))) {
                    left = kr_str("1");
                } else {
                    left = kr_str("0");
                }
            }
        } else {
            if (kr_truthy(kr_eq(op, kr_str("LT")))) {
                if (kr_truthy(kr_lt(left, right))) {
                    left = kr_str("1");
                } else {
                    left = kr_str("0");
                }
            } else if (kr_truthy(kr_eq(op, kr_str("GT")))) {
                if (kr_truthy(kr_gt(left, right))) {
                    left = kr_str("1");
                } else {
                    left = kr_str("0");
                }
            } else if (kr_truthy(kr_eq(op, kr_str("LTE")))) {
                if (kr_truthy(kr_lte(left, right))) {
                    left = kr_str("1");
                } else {
                    left = kr_str("0");
                }
            } else {
                if (kr_truthy(kr_gte(left, right))) {
                    left = kr_str("1");
                } else {
                    left = kr_str("0");
                }
            }
        }
    }
    return kr_plus(kr_plus(left, kr_str(",")), p);
}

char* evalAdditive(char* tokens, char* pos, char* env, char* ftable) {
    char* pair = evalMult(tokens, pos, env, ftable);
    char* left = pairVal(pair);
    char* p = pairPos(pair);
    while (kr_truthy((kr_truthy(kr_eq(tokAt(tokens, p), kr_str("PLUS"))) || kr_truthy(kr_eq(tokAt(tokens, p), kr_str("MINUS"))) ? kr_str("1") : kr_str("0")))) {
        char* op = tokAt(tokens, p);
        char* pair2 = evalMult(tokens, kr_plus(p, kr_str("1")), env, ftable);
        char* right = pairVal(pair2);
        p = pairPos(pair2);
        char* li = kr_toint(left);
        char* ri = kr_toint(right);
        if (kr_truthy(kr_eq(op, kr_str("PLUS")))) {
            if (kr_truthy((kr_truthy(kr_eq(kr_plus(li, kr_str("")), left)) && kr_truthy(kr_eq(kr_plus(ri, kr_str("")), right)) ? kr_str("1") : kr_str("0")))) {
                left = kr_plus(kr_plus(li, ri), kr_str(""));
            } else {
                left = kr_plus(left, right);
            }
        } else {
            left = kr_plus(kr_sub(li, ri), kr_str(""));
        }
    }
    return kr_plus(kr_plus(left, kr_str(",")), p);
}

char* evalMult(char* tokens, char* pos, char* env, char* ftable) {
    char* pair = evalUnary(tokens, pos, env, ftable);
    char* left = pairVal(pair);
    char* p = pairPos(pair);
    while (kr_truthy((kr_truthy(kr_eq(tokAt(tokens, p), kr_str("STAR"))) || kr_truthy(kr_eq(tokAt(tokens, p), kr_str("SLASH"))) ? kr_str("1") : kr_str("0")))) {
        char* op = tokAt(tokens, p);
        char* pair2 = evalUnary(tokens, kr_plus(p, kr_str("1")), env, ftable);
        char* right = pairVal(pair2);
        p = pairPos(pair2);
        char* li = kr_toint(left);
        char* ri = kr_toint(right);
        if (kr_truthy(kr_eq(op, kr_str("STAR")))) {
            left = kr_plus(kr_mul(li, ri), kr_str(""));
        } else {
            left = kr_plus(kr_div(li, ri), kr_str(""));
        }
    }
    return kr_plus(kr_plus(left, kr_str(",")), p);
}

char* evalUnary(char* tokens, char* pos, char* env, char* ftable) {
    char* tok = tokAt(tokens, pos);
    if (kr_truthy(kr_eq(tok, kr_str("MINUS")))) {
        char* pair = evalUnary(tokens, kr_plus(pos, kr_str("1")), env, ftable);
        char* val = pairVal(pair);
        char* p = pairPos(pair);
        char* n = kr_toint(val);
        return kr_plus(kr_plus(kr_sub(kr_str("0"), n), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(tok, kr_str("BANG")))) {
        char* pair = evalUnary(tokens, kr_plus(pos, kr_str("1")), env, ftable);
        char* val = pairVal(pair);
        char* p = pairPos(pair);
        if (kr_truthy((kr_truthy((kr_truthy(kr_eq(val, kr_str("0"))) || kr_truthy(kr_eq(val, kr_str(""))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(val, kr_str("false"))) ? kr_str("1") : kr_str("0")))) {
            return kr_plus(kr_str("1,"), p);
        } else {
            return kr_plus(kr_str("0,"), p);
        }
    }
    return evalPostfix(tokens, pos, env, ftable);
}

char* evalPostfix(char* tokens, char* pos, char* env, char* ftable) {
    char* pair = evalPrimary(tokens, pos, env, ftable);
    char* val = pairVal(pair);
    char* p = pairPos(pair);
    while (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("LBRACK")))) {
        char* pair2 = evalExpr(tokens, kr_plus(p, kr_str("1")), env, ftable);
        char* idx = pairVal(pair2);
        char* p2 = pairPos(pair2);
        p = kr_plus(p2, kr_str("1"));
        char* ii = kr_toint(idx);
        if (kr_truthy((kr_truthy(kr_gte(ii, kr_str("0"))) && kr_truthy(kr_lt(ii, kr_len(val))) ? kr_str("1") : kr_str("0")))) {
            val = kr_idx(val, kr_atoi(ii));
        } else {
            val = kr_str("");
        }
    }
    return kr_plus(kr_plus(val, kr_str(",")), p);
}

char* evalPrimary(char* tokens, char* pos, char* env, char* ftable) {
    char* tok = tokAt(tokens, pos);
    char* tt = tokType(tok);
    char* tv = tokVal(tok);
    if (kr_truthy(kr_eq(tt, kr_str("INT")))) {
        return kr_plus(kr_plus(tv, kr_str(",")), kr_plus(pos, kr_str("1")));
    }
    if (kr_truthy(kr_eq(tt, kr_str("STR")))) {
        return kr_plus(kr_plus(expandEscapes(tv), kr_str(",")), kr_plus(pos, kr_str("1")));
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:true")))) {
        return kr_plus(kr_str("1,"), kr_plus(pos, kr_str("1")));
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:false")))) {
        return kr_plus(kr_str("0,"), kr_plus(pos, kr_str("1")));
    }
    if (kr_truthy(kr_eq(tok, kr_str("LPAREN")))) {
        char* pair = evalExpr(tokens, kr_plus(pos, kr_str("1")), env, ftable);
        char* val = pairVal(pair);
        char* p = pairPos(pair);
        return kr_plus(kr_plus(val, kr_str(",")), kr_plus(p, kr_str("1")));
    }
    if (kr_truthy(kr_eq(tt, kr_str("ID")))) {
        char* next = tokAt(tokens, kr_plus(pos, kr_str("1")));
        if (kr_truthy(kr_eq(next, kr_str("LPAREN")))) {
            return evalCall(tokens, pos, env, ftable);
        } else {
            char* val = envGet(env, tv);
            return kr_plus(kr_plus(val, kr_str(",")), kr_plus(pos, kr_str("1")));
        }
    }
    return kr_plus(kr_str(","), kr_plus(pos, kr_str("1")));
}

char* evalCall(char* tokens, char* pos, char* env, char* ftable) {
    char* fname = tokVal(tokAt(tokens, pos));
    char* p = kr_plus(pos, kr_str("2"));
    char* args = kr_str("");
    char* argc = kr_str("0");
    if (kr_truthy(kr_neq(tokAt(tokens, p), kr_str("RPAREN")))) {
        char* pair = evalExpr(tokens, p, env, ftable);
        args = pairVal(pair);
        p = pairPos(pair);
        argc = kr_str("1");
        while (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("COMMA")))) {
            char* pair2 = evalExpr(tokens, kr_plus(p, kr_str("1")), env, ftable);
            args = kr_plus(kr_plus(args, kr_str("\t")), pairVal(pair2));
            p = pairPos(pair2);
            argc = kr_plus(argc, kr_str("1"));
        }
    }
    p = kr_plus(p, kr_str("1"));
    if (kr_truthy((kr_truthy(kr_eq(fname, kr_str("print"))) || kr_truthy(kr_eq(fname, kr_str("kp"))) ? kr_str("1") : kr_str("0")))) {
        if (kr_truthy(kr_gt(argc, kr_str("0")))) {
            kr_print(getArg(args, kr_str("0")));
        }
        return kr_plus(kr_str(","), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("len")))) {
        char* s = getArg(args, kr_str("0"));
        return kr_plus(kr_plus(kr_len(s), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("substring")))) {
        char* s = getArg(args, kr_str("0"));
        char* start = kr_toint(getArg(args, kr_str("1")));
        char* end = kr_toint(getArg(args, kr_str("2")));
        return kr_plus(kr_plus(kr_substr(s, start, end), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("toInt")))) {
        char* s = getArg(args, kr_str("0"));
        return kr_plus(kr_plus(kr_toint(s), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("split")))) {
        char* s = getArg(args, kr_str("0"));
        char* idx = kr_toint(getArg(args, kr_str("1")));
        return kr_plus(kr_plus(kr_split(s, idx), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("startsWith")))) {
        char* s = getArg(args, kr_str("0"));
        char* prefix = getArg(args, kr_str("1"));
        return kr_plus(kr_plus(kr_startswith(s, prefix), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("count")))) {
        char* s = getArg(args, kr_str("0"));
        return kr_plus(kr_plus(kr_count(s), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("readFile")))) {
        char* path = getArg(args, kr_str("0"));
        return kr_plus(kr_plus(kr_readfile(path), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("arg")))) {
        char* idx = kr_toint(getArg(args, kr_str("0")));
        char* offset = kr_toint(envGet(env, kr_str("__argOffset")));
        return kr_plus(kr_plus(kr_arg(kr_plus(idx, offset)), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("argCount")))) {
        char* offset = kr_toint(envGet(env, kr_str("__argOffset")));
        return kr_plus(kr_plus(kr_sub(kr_argcount(), offset), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("getLine")))) {
        char* s = getArg(args, kr_str("0"));
        char* idx = kr_toint(getArg(args, kr_str("1")));
        return kr_plus(kr_plus(kr_getline(s, idx), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("tokAt")))) {
        char* s = getArg(args, kr_str("0"));
        char* idx = kr_toint(getArg(args, kr_str("1")));
        return kr_plus(kr_plus(tokAt(s, idx), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("lineCount")))) {
        char* s = getArg(args, kr_str("0"));
        return kr_plus(kr_plus(kr_linecount(s), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("envGet")))) {
        char* e = getArg(args, kr_str("0"));
        char* n = getArg(args, kr_str("1"));
        return kr_plus(kr_plus(envGet(e, n), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("envSet")))) {
        char* e = getArg(args, kr_str("0"));
        char* n = getArg(args, kr_str("1"));
        char* v = getArg(args, kr_str("2"));
        return kr_plus(kr_plus(envSet(e, n, v), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("pairVal")))) {
        char* s = getArg(args, kr_str("0"));
        return kr_plus(kr_plus(pairVal(s), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("pairPos")))) {
        char* s = getArg(args, kr_str("0"));
        return kr_plus(kr_plus(pairPos(s), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("tokType")))) {
        char* s = getArg(args, kr_str("0"));
        return kr_plus(kr_plus(tokType(s), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("tokVal")))) {
        char* s = getArg(args, kr_str("0"));
        return kr_plus(kr_plus(tokVal(s), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("findLastComma")))) {
        char* s = getArg(args, kr_str("0"));
        return kr_plus(kr_plus(findLastComma(s), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("tokenize")))) {
        char* s = getArg(args, kr_str("0"));
        return kr_plus(kr_plus(tokenize(s), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("scanFunctions")))) {
        char* s = getArg(args, kr_str("0"));
        char* n = kr_toint(getArg(args, kr_str("1")));
        return kr_plus(kr_plus(scanFunctions(s, n), kr_str(",")), p);
    }
    if (kr_truthy(kr_eq(fname, kr_str("findEntry")))) {
        char* s = getArg(args, kr_str("0"));
        char* n = kr_toint(getArg(args, kr_str("1")));
        return kr_plus(kr_plus(findEntry(s, n), kr_str(",")), p);
    }
    char* info = funcLookup(ftable, fname);
    if (kr_truthy(kr_neq(info, kr_str("")))) {
        char* pc = funcParamCount(info);
        char* paramStr = funcParams(info);
        char* bodyStart = funcStart(info);
        char* fenv = env;
        char* a = kr_str("0");
        while (kr_truthy(kr_lt(a, pc))) {
            char* pname = getNthParam(paramStr, a);
            char* aval = getArg(args, a);
            fenv = envSet(fenv, pname, aval);
            a = kr_plus(a, kr_str("1"));
        }
        char* result = execBlock(tokens, bodyStart, fenv, ftable);
        char* tag = kr_idx(result, kr_atoi(kr_str("0")));
        char* rval = getResultVal(result);
        if (kr_truthy(kr_eq(tag, kr_str("R")))) {
            return kr_plus(kr_plus(rval, kr_str(",")), p);
        }
        return kr_plus(kr_str(","), p);
    }
    kr_print(kr_plus(kr_str("ERROR: unknown function: "), fname));
    return kr_plus(kr_str(","), p);
}

char* getArg(char* args, char* idx) {
    char* n = kr_str("0");
    char* start = kr_str("0");
    char* i = kr_str("0");
    while (kr_truthy(kr_lte(i, kr_len(args)))) {
        if (kr_truthy((kr_truthy(kr_eq(i, kr_len(args))) || kr_truthy(kr_eq(kr_idx(args, kr_atoi(i)), kr_str("\t"))) ? kr_str("1") : kr_str("0")))) {
            if (kr_truthy(kr_eq(n, idx))) {
                return kr_substr(args, start, i);
            }
            n = kr_plus(n, kr_str("1"));
            start = kr_plus(i, kr_str("1"));
        }
        i = kr_plus(i, kr_str("1"));
    }
    return kr_str("");
}

char* makeResult(char* tag, char* val, char* env, char* pos) {
    char* r = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(tag, kr_str("|")), val), kr_str("|")), env), kr_str("|")), pos);
    return r;
}

char* getResultTag(char* r) {
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, kr_len(r)))) {
        if (kr_truthy(kr_eq(kr_idx(r, kr_atoi(i)), kr_str("|")))) {
            return kr_substr(r, kr_str("0"), i);
        }
        i = kr_plus(i, kr_str("1"));
    }
    return r;
}

char* getResultVal(char* r) {
    char* first = kr_neg(kr_str("1"));
    char* last = kr_neg(kr_str("1"));
    char* secondLast = kr_neg(kr_str("1"));
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, kr_len(r)))) {
        if (kr_truthy(kr_eq(kr_idx(r, kr_atoi(i)), kr_str("|")))) {
            if (kr_truthy(kr_eq(first, kr_neg(kr_str("1"))))) {
                first = i;
            }
            secondLast = last;
            last = i;
        }
        i = kr_plus(i, kr_str("1"));
    }
    if (kr_truthy((kr_truthy(kr_gte(first, kr_str("0"))) && kr_truthy(kr_gte(secondLast, kr_str("0"))) ? kr_str("1") : kr_str("0")))) {
        return kr_substr(r, kr_plus(first, kr_str("1")), secondLast);
    }
    return kr_str("");
}

char* getResultEnv(char* r) {
    char* last = kr_neg(kr_str("1"));
    char* secondLast = kr_neg(kr_str("1"));
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, kr_len(r)))) {
        if (kr_truthy(kr_eq(kr_idx(r, kr_atoi(i)), kr_str("|")))) {
            secondLast = last;
            last = i;
        }
        i = kr_plus(i, kr_str("1"));
    }
    if (kr_truthy((kr_truthy(kr_gte(secondLast, kr_str("0"))) && kr_truthy(kr_gte(last, kr_str("0"))) ? kr_str("1") : kr_str("0")))) {
        return kr_substr(r, kr_plus(secondLast, kr_str("1")), last);
    }
    return kr_str("");
}

char* getResultPos(char* r) {
    char* last = kr_neg(kr_str("1"));
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(i, kr_len(r)))) {
        if (kr_truthy(kr_eq(kr_idx(r, kr_atoi(i)), kr_str("|")))) {
            last = i;
        }
        i = kr_plus(i, kr_str("1"));
    }
    if (kr_truthy(kr_gte(last, kr_str("0")))) {
        return kr_toint(kr_substr(r, kr_plus(last, kr_str("1")), kr_len(r)));
    }
    return kr_str("0");
}

char* isTruthy(char* val) {
    if (kr_truthy((kr_truthy((kr_truthy(kr_eq(val, kr_str("0"))) || kr_truthy(kr_eq(val, kr_str(""))) ? kr_str("1") : kr_str("0"))) || kr_truthy(kr_eq(val, kr_str("false"))) ? kr_str("1") : kr_str("0")))) {
        return kr_str("0");
    }
    return kr_str("1");
}

char* execBlock(char* tokens, char* pos, char* env, char* ftable) {
    char* p = kr_plus(pos, kr_str("1"));
    char* curEnv = env;
    while (kr_truthy((kr_truthy(kr_neq(tokAt(tokens, p), kr_str("RBRACE"))) && kr_truthy(kr_lt(p, kr_linecount(tokens))) ? kr_str("1") : kr_str("0")))) {
        char* tok = tokAt(tokens, p);
        if (kr_truthy(kr_eq(tok, kr_str("SEMI")))) {
            p = kr_plus(p, kr_str("1"));
        } else {
            char* result = execStmt(tokens, p, curEnv, ftable);
            char* tag = getResultTag(result);
            if (kr_truthy((kr_truthy(kr_eq(tag, kr_str("R"))) || kr_truthy(kr_eq(tag, kr_str("B"))) ? kr_str("1") : kr_str("0")))) {
                return result;
            }
            curEnv = getResultEnv(result);
            p = getResultPos(result);
        }
    }
    return makeResult(kr_str("C"), kr_str(""), curEnv, kr_plus(p, kr_str("1")));
}

char* execStmt(char* tokens, char* pos, char* env, char* ftable) {
    char* tok = tokAt(tokens, pos);
    if (kr_truthy(kr_eq(tok, kr_str("KW:let")))) {
        return execLet(tokens, kr_plus(pos, kr_str("1")), env, ftable);
    }
    if (kr_truthy((kr_truthy(kr_eq(tok, kr_str("KW:emit"))) || kr_truthy(kr_eq(tok, kr_str("KW:return"))) ? kr_str("1") : kr_str("0")))) {
        return execEmit(tokens, kr_plus(pos, kr_str("1")), env, ftable);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:if")))) {
        return execIf(tokens, kr_plus(pos, kr_str("1")), env, ftable);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:while")))) {
        return execWhile(tokens, kr_plus(pos, kr_str("1")), env, ftable);
    }
    if (kr_truthy(kr_eq(tok, kr_str("KW:break")))) {
        char* p = kr_plus(pos, kr_str("1"));
        if (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("SEMI")))) {
            p = kr_plus(p, kr_str("1"));
        }
        return makeResult(kr_str("B"), kr_str(""), env, p);
    }
    if (kr_truthy((kr_truthy(kr_eq(tokType(tok), kr_str("ID"))) && kr_truthy(kr_eq(tokAt(tokens, kr_plus(pos, kr_str("1"))), kr_str("ASSIGN"))) ? kr_str("1") : kr_str("0")))) {
        return execAssign(tokens, pos, env, ftable);
    }
    return execExprStmt(tokens, pos, env, ftable);
}

char* execLet(char* tokens, char* pos, char* env, char* ftable) {
    char* name = tokVal(tokAt(tokens, pos));
    char* p = kr_plus(pos, kr_str("2"));
    char* pair = evalExpr(tokens, p, env, ftable);
    char* val = pairVal(pair);
    p = pairPos(pair);
    if (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("SEMI")))) {
        p = kr_plus(p, kr_str("1"));
    }
    char* newEnv = envSet(env, name, val);
    return makeResult(kr_str("C"), kr_str(""), newEnv, p);
}

char* execAssign(char* tokens, char* pos, char* env, char* ftable) {
    char* name = tokVal(tokAt(tokens, pos));
    char* p = kr_plus(pos, kr_str("2"));
    char* pair = evalExpr(tokens, p, env, ftable);
    char* val = pairVal(pair);
    p = pairPos(pair);
    if (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("SEMI")))) {
        p = kr_plus(p, kr_str("1"));
    }
    char* newEnv = envSet(env, name, val);
    return makeResult(kr_str("C"), kr_str(""), newEnv, p);
}

char* execEmit(char* tokens, char* pos, char* env, char* ftable) {
    char* pair = evalExpr(tokens, pos, env, ftable);
    char* val = pairVal(pair);
    char* p = pairPos(pair);
    if (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("SEMI")))) {
        p = kr_plus(p, kr_str("1"));
    }
    return makeResult(kr_str("R"), val, env, p);
}

char* execIf(char* tokens, char* pos, char* env, char* ftable) {
    char* condPair = evalExpr(tokens, pos, env, ftable);
    char* condVal = pairVal(condPair);
    char* p = pairPos(condPair);
    if (kr_truthy(isTruthy(condVal))) {
        char* result = execBlock(tokens, p, env, ftable);
        char* tag = getResultTag(result);
        char* renv = getResultEnv(result);
        char* rpos = getResultPos(result);
        if (kr_truthy(kr_eq(tokAt(tokens, rpos), kr_str("KW:else")))) {
            if (kr_truthy(kr_eq(tokAt(tokens, kr_plus(rpos, kr_str("1"))), kr_str("KW:if")))) {
                char* skipPos = kr_plus(rpos, kr_str("2"));
                char* dummyPair = evalExpr(tokens, skipPos, env, ftable);
                skipPos = pairPos(dummyPair);
                skipPos = skipBlock(tokens, skipPos);
                while (kr_truthy(kr_eq(tokAt(tokens, skipPos), kr_str("KW:else")))) {
                    if (kr_truthy(kr_eq(tokAt(tokens, kr_plus(skipPos, kr_str("1"))), kr_str("KW:if")))) {
                        skipPos = kr_plus(skipPos, kr_str("2"));
                        char* dp2 = evalExpr(tokens, skipPos, env, ftable);
                        skipPos = pairPos(dp2);
                        skipPos = skipBlock(tokens, skipPos);
                    } else {
                        skipPos = kr_plus(skipPos, kr_str("1"));
                        skipPos = skipBlock(tokens, skipPos);
                    }
                }
                if (kr_truthy((kr_truthy(kr_eq(tag, kr_str("R"))) || kr_truthy(kr_eq(tag, kr_str("B"))) ? kr_str("1") : kr_str("0")))) {
                    return makeResult(tag, getResultVal(result), renv, skipPos);
                }
                return makeResult(kr_str("C"), kr_str(""), renv, skipPos);
            } else {
                char* skipPos = kr_plus(rpos, kr_str("1"));
                skipPos = skipBlock(tokens, skipPos);
                if (kr_truthy((kr_truthy(kr_eq(tag, kr_str("R"))) || kr_truthy(kr_eq(tag, kr_str("B"))) ? kr_str("1") : kr_str("0")))) {
                    return makeResult(tag, getResultVal(result), renv, skipPos);
                }
                return makeResult(kr_str("C"), kr_str(""), renv, skipPos);
            }
        }
        if (kr_truthy((kr_truthy(kr_eq(tag, kr_str("R"))) || kr_truthy(kr_eq(tag, kr_str("B"))) ? kr_str("1") : kr_str("0")))) {
            return result;
        }
        return makeResult(kr_str("C"), kr_str(""), renv, rpos);
    } else {
        char* skipPos = skipBlock(tokens, p);
        if (kr_truthy(kr_eq(tokAt(tokens, skipPos), kr_str("KW:else")))) {
            if (kr_truthy(kr_eq(tokAt(tokens, kr_plus(skipPos, kr_str("1"))), kr_str("KW:if")))) {
                return execIf(tokens, kr_plus(skipPos, kr_str("2")), env, ftable);
            } else {
                return execBlock(tokens, kr_plus(skipPos, kr_str("1")), env, ftable);
            }
        }
        return makeResult(kr_str("C"), kr_str(""), env, skipPos);
    }
}

char* execWhile(char* tokens, char* pos, char* env, char* ftable) {
    char* condStart = pos;
    char* curEnv = env;
    while (kr_truthy(kr_str("1"))) {
        char* condPair = evalExpr(tokens, condStart, curEnv, ftable);
        char* condVal = pairVal(condPair);
        char* bodyStart = pairPos(condPair);
        if (kr_truthy(kr_not(isTruthy(condVal)))) {
            char* endPos = skipBlock(tokens, bodyStart);
            return makeResult(kr_str("C"), kr_str(""), curEnv, endPos);
        }
        char* result = execBlock(tokens, bodyStart, curEnv, ftable);
        char* tag = getResultTag(result);
        curEnv = getResultEnv(result);
        if (kr_truthy(kr_eq(tag, kr_str("R")))) {
            return result;
        }
        if (kr_truthy(kr_eq(tag, kr_str("B")))) {
            char* endPos = skipBlock(tokens, bodyStart);
            return makeResult(kr_str("C"), kr_str(""), curEnv, endPos);
        }
    }
    return makeResult(kr_str("C"), kr_str(""), curEnv, condStart);
}

char* execExprStmt(char* tokens, char* pos, char* env, char* ftable) {
    char* pair = evalExpr(tokens, pos, env, ftable);
    char* p = pairPos(pair);
    if (kr_truthy(kr_eq(tokAt(tokens, p), kr_str("SEMI")))) {
        p = kr_plus(p, kr_str("1"));
    }
    return makeResult(kr_str("C"), kr_str(""), env, p);
}

int main(int argc, char** argv) {
    _argc = argc; _argv = argv;
    char* file = kr_arg(kr_str("0"));
    char* source = kr_readfile(file);
    char* tokens = tokenize(source);
    char* ntoks = kr_linecount(tokens);
    char* ftable = scanFunctions(tokens, ntoks);
    char* entry = findEntry(tokens, ntoks);
    if (kr_truthy(kr_lt(entry, kr_str("0")))) {
        kr_print(kr_str("No entry point found"));
        return 0;
    }
    char* initEnv = envSet(kr_str(""), kr_str("__argOffset"), kr_str("1"));
    char* result = execBlock(tokens, entry, initEnv, ftable);
    char* tag = getResultTag(result);
    if (kr_truthy(kr_eq(tag, kr_str("R")))) {
        char* val = getResultVal(result);
        if (kr_truthy(kr_neq(val, kr_str("")))) {
            return 0;
        }
    }
    return 0;
    return 0;
}

