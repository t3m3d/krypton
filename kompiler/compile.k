// compile.k — Krypton-to-C compiler written in Krypton
// Usage: kcc kompiler/compile.k <source.k> > output.c
//   then: gcc -o program output.c

// === Pair helpers (value,pos) ===

func findLastComma(s) {
    let i = len(s) - 1
    while i >= 0 {
        if s[i] == "," {
            emit i
        }
        i = i - 1
    }
    emit -1
}

func pairVal(pair) {
    let c = findLastComma(pair)
    if c < 0 {
        emit pair
    }
    emit substring(pair, 0, c)
}

func pairPos(pair) {
    let c = findLastComma(pair)
    emit toInt(substring(pair, c + 1, len(pair)))
}

// === Token access ===

func tokAt(tokens, idx) {
    emit getLine(tokens, idx)
}

func tokType(tok) {
    let i = 0
    while i < len(tok) {
        if tok[i] == ":" {
            emit substring(tok, 0, i)
        }
        i = i + 1
    }
    emit tok
}

func tokVal(tok) {
    let i = 0
    while i < len(tok) {
        if tok[i] == ":" {
            emit substring(tok, i + 1, len(tok))
        }
        i = i + 1
    }
    emit ""
}

// === C string escaping ===

func cEscape(s) {
    let out = ""
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == "\\" {
            out = out + "\\\\"
        } else if c == "\"" {
            out = out + "\\\""
        } else if c == "\n" {
            out = out + "\\n"
        } else if c == "\r" {
            out = out + "\\r"
        } else if c == "\t" {
            out = out + "\\t"
        } else {
            out = out + c
        }
        i = i + 1
    }
    emit out
}

// === Expand escape sequences in string tokens ===

func expandEscapes(s) {
    let out = ""
    let i = 0
    while i < len(s) {
        if s[i] == "\\" {
            i = i + 1
            if i < len(s) {
                let c = s[i]
                if c == "n" {
                    out = out + "\n"
                } else if c == "t" {
                    out = out + "\t"
                } else if c == "r" {
                    out = out + "\r"
                } else if c == "\\" {
                    out = out + "\\"
                } else if c == "\"" {
                    out = out + "\""
                } else {
                    out = out + "\\" + c
                }
            }
        } else {
            out = out + s[i]
        }
        i = i + 1
    }
    emit out
}

// === Function table helpers ===

func scanFunctions(tokens, ntoks) {
    let table = ""
    let i = 0
    while i < ntoks {
        let tok = tokAt(tokens, i)
        if tok == "KW:func" {
            let nameTok = tokAt(tokens, i + 1)
            let fname = tokVal(nameTok)
            // skip name, LPAREN
            let j = i + 3
            let params = ""
            let pc = 0
            while tokAt(tokens, j) != "RPAREN" {
                let pt = tokAt(tokens, j)
                if tokType(pt) == "ID" {
                    if pc > 0 {
                        params = params + "," + tokVal(pt)
                    } else {
                        params = tokVal(pt)
                    }
                    pc = pc + 1
                }
                j = j + 1
            }
            // j is at RPAREN, j+1 is LBRACE
            let bodyStart = j + 1
            table = table + fname + "~" + pc + "~" + params + "~" + bodyStart + "\n"
        }
        i = i + 1
    }
    emit table
}

func funcLookup(table, name) {
    let i = 0
    let tlen = len(table)
    while i < tlen {
        // find end of line
        let nl = i
        while nl < tlen {
            if table[nl] == "\n" {
                break
            }
            nl = nl + 1
        }
        let line = substring(table, i, nl)
        // find first ~
        let t1 = 0
        while t1 < len(line) {
            if line[t1] == "~" {
                break
            }
            t1 = t1 + 1
        }
        let fnom = substring(line, 0, t1)
        if fnom == name {
            emit substring(line, t1 + 1, len(line))
        }
        i = nl + 1
    }
    emit ""
}

func funcParamCount(info) {
    let i = 0
    while i < len(info) {
        if info[i] == "~" {
            emit toInt(substring(info, 0, i))
        }
        i = i + 1
    }
    emit 0
}

func funcParams(info) {
    let i = 0
    while i < len(info) {
        if info[i] == "~" {
            let rest = substring(info, i + 1, len(info))
            let j = 0
            while j < len(rest) {
                if rest[j] == "~" {
                    emit substring(rest, 0, j)
                }
                j = j + 1
            }
            emit rest
        }
        i = i + 1
    }
    emit ""
}

func funcStart(info) {
    let i = len(info) - 1
    while i >= 0 {
        if info[i] == "~" {
            emit toInt(substring(info, i + 1, len(info)))
        }
        i = i - 1
    }
    emit 0
}

func getNthParam(params, idx) {
    let count = 0
    let start = 0
    let i = 0
    while i < len(params) {
        if params[i] == "," {
            if count == idx {
                emit substring(params, start, i)
            }
            count = count + 1
            start = i + 1
        }
        i = i + 1
    }
    if count == idx {
        emit substring(params, start, len(params))
    }
    emit ""
}

func findEntry(tokens, ntoks) {
    let i = 0
    while i < ntoks {
        let tok = tokAt(tokens, i)
        if tok == "KW:just" || tok == "KW:go" {
            if i + 2 < ntoks {
                let next = tokAt(tokens, i + 1)
                if next == "ID:run" {
                    if tokAt(tokens, i + 2) == "LBRACE" {
                        emit i + 2
                    }
                }
            }
        }
        i = i + 1
    }
    emit 0 - 1
}

func skipBlock(tokens, pos) {
    let depth = 1
    let p = pos + 1
    while depth > 0 {
        let t = tokAt(tokens, p)
        if t == "LBRACE" {
            depth = depth + 1
        }
        if t == "RBRACE" {
            depth = depth - 1
        }
        p = p + 1
    }
    emit p
}

// === Indentation helper ===

func indent(depth) {
    let out = ""
    let i = 0
    while i < depth {
        out = out + "    "
        i = i + 1
    }
    emit out
}

// === C identifier sanitizer ===

func cIdent(name) {
    // Krypton identifiers are valid C identifiers
    // but avoid C keyword collisions by prefixing
    if name == "int" || name == "char" || name == "void" || name == "return" || name == "if" || name == "else" || name == "while" || name == "break" || name == "for" || name == "do" || name == "switch" || name == "case" || name == "default" || name == "struct" || name == "const" || name == "static" || name == "long" || name == "short" || name == "double" || name == "float" || name == "auto" || name == "register" || name == "extern" || name == "typedef" || name == "union" || name == "enum" || name == "sizeof" || name == "goto" || name == "volatile" || name == "signed" || name == "unsigned" {
        emit "k_" + name
    }
    emit name
}

// =============================================
// Expression Compiler
// Each returns pair: "cExprCode,pos"
// =============================================

func compileExpr(tokens, pos, ntoks) {
    emit compileOr(tokens, pos, ntoks)
}

func compileOr(tokens, pos, ntoks) {
    let pair = compileAnd(tokens, pos, ntoks)
    let code = pairVal(pair)
    let p = pairPos(pair)
    while tokAt(tokens, p) == "OR" {
        let rp = compileAnd(tokens, p + 1, ntoks)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        code = "(kr_truthy(" + code + ") || kr_truthy(" + rcode + ") ? kr_str(\"1\") : kr_str(\"0\"))"
    }
    emit code + "," + p
}

func compileAnd(tokens, pos, ntoks) {
    let pair = compileEquality(tokens, pos, ntoks)
    let code = pairVal(pair)
    let p = pairPos(pair)
    while tokAt(tokens, p) == "AND" {
        let rp = compileEquality(tokens, p + 1, ntoks)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        code = "(kr_truthy(" + code + ") && kr_truthy(" + rcode + ") ? kr_str(\"1\") : kr_str(\"0\"))"
    }
    emit code + "," + p
}

func compileEquality(tokens, pos, ntoks) {
    let pair = compileRelational(tokens, pos, ntoks)
    let code = pairVal(pair)
    let p = pairPos(pair)
    while tokAt(tokens, p) == "EQ" || tokAt(tokens, p) == "NEQ" {
        let op = tokAt(tokens, p)
        let rp = compileRelational(tokens, p + 1, ntoks)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        if op == "EQ" {
            code = "kr_eq(" + code + ", " + rcode + ")"
        } else {
            code = "kr_neq(" + code + ", " + rcode + ")"
        }
    }
    emit code + "," + p
}

func compileRelational(tokens, pos, ntoks) {
    let pair = compileAdditive(tokens, pos, ntoks)
    let code = pairVal(pair)
    let p = pairPos(pair)
    while tokAt(tokens, p) == "LT" || tokAt(tokens, p) == "GT" || tokAt(tokens, p) == "LTE" || tokAt(tokens, p) == "GTE" {
        let op = tokAt(tokens, p)
        let rp = compileAdditive(tokens, p + 1, ntoks)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        if op == "LT" {
            code = "kr_lt(" + code + ", " + rcode + ")"
        } else if op == "GT" {
            code = "kr_gt(" + code + ", " + rcode + ")"
        } else if op == "LTE" {
            code = "kr_lte(" + code + ", " + rcode + ")"
        } else {
            code = "kr_gte(" + code + ", " + rcode + ")"
        }
    }
    emit code + "," + p
}

func compileAdditive(tokens, pos, ntoks) {
    let pair = compileMult(tokens, pos, ntoks)
    let code = pairVal(pair)
    let p = pairPos(pair)
    while tokAt(tokens, p) == "PLUS" || tokAt(tokens, p) == "MINUS" {
        let op = tokAt(tokens, p)
        let rp = compileMult(tokens, p + 1, ntoks)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        if op == "PLUS" {
            code = "kr_plus(" + code + ", " + rcode + ")"
        } else {
            code = "kr_sub(" + code + ", " + rcode + ")"
        }
    }
    emit code + "," + p
}

func compileMult(tokens, pos, ntoks) {
    let pair = compileUnary(tokens, pos, ntoks)
    let code = pairVal(pair)
    let p = pairPos(pair)
    while tokAt(tokens, p) == "STAR" || tokAt(tokens, p) == "SLASH" || tokAt(tokens, p) == "PERCENT" {
        let op = tokAt(tokens, p)
        let rp = compileUnary(tokens, p + 1, ntoks)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        if op == "STAR" {
            code = "kr_mul(" + code + ", " + rcode + ")"
        } else if op == "SLASH" {
            code = "kr_div(" + code + ", " + rcode + ")"
        } else {
            code = "kr_mod(" + code + ", " + rcode + ")"
        }
    }
    emit code + "," + p
}

func compileUnary(tokens, pos, ntoks) {
    let tok = tokAt(tokens, pos)
    if tok == "MINUS" {
        let rp = compileUnary(tokens, pos + 1, ntoks)
        let rcode = pairVal(rp)
        let p = pairPos(rp)
        emit "kr_neg(" + rcode + ")," + p
    }
    if tok == "BANG" {
        let rp = compileUnary(tokens, pos + 1, ntoks)
        let rcode = pairVal(rp)
        let p = pairPos(rp)
        emit "kr_not(" + rcode + ")," + p
    }
    emit compilePostfix(tokens, pos, ntoks)
}

func compilePostfix(tokens, pos, ntoks) {
    let pair = compilePrimary(tokens, pos, ntoks)
    let code = pairVal(pair)
    let p = pairPos(pair)
    while tokAt(tokens, p) == "LBRACK" {
        let ip = compileExpr(tokens, p + 1, ntoks)
        let icode = pairVal(ip)
        p = pairPos(ip)
        // expect RBRACK
        p = p + 1
        code = "kr_idx(" + code + ", kr_atoi(" + icode + "))"
    }
    emit code + "," + p
}

func compilePrimary(tokens, pos, ntoks) {
    let tok = tokAt(tokens, pos)
    let tt = tokType(tok)
    let tv = tokVal(tok)

    if tt == "INT" {
        emit "kr_str(\"" + tv + "\")," + (pos + 1)
    }

    if tt == "STR" {
        let expanded = expandEscapes(tv)
        let escaped = cEscape(expanded)
        emit "kr_str(\"" + escaped + "\")," + (pos + 1)
    }

    if tt == "KW" {
        if tv == "true" {
            emit "kr_str(\"1\")," + (pos + 1)
        }
        if tv == "false" {
            emit "kr_str(\"0\")," + (pos + 1)
        }
    }

    if tok == "LPAREN" {
        let ep = compileExpr(tokens, pos + 1, ntoks)
        let ecode = pairVal(ep)
        let p = pairPos(ep)
        // expect RPAREN
        emit ecode + "," + (p + 1)
    }

    if tt == "ID" {
        let name = tv
        // check for function call
        if tokAt(tokens, pos + 1) == "LPAREN" {
            emit compileCall(tokens, pos, ntoks)
        }
        // bare variable reference
        emit cIdent(name) + "," + (pos + 1)
    }

    emit "kr_str(\"\")," + (pos + 1)
}

// === Function/builtin call compiler ===

func compileCall(tokens, pos, ntoks) {
    let fname = tokVal(tokAt(tokens, pos))
    let p = pos + 2
    // collect compiled argument expressions
    let args = ""
    let argc = 0
    while tokAt(tokens, p) != "RPAREN" {
        if argc > 0 {
            // skip COMMA
            p = p + 1
        }
        let ap = compileExpr(tokens, p, ntoks)
        let acode = pairVal(ap)
        p = pairPos(ap)
        if argc > 0 {
            args = args + ", " + acode
        } else {
            args = acode
        }
        argc = argc + 1
    }
    p = p + 1

    // Map builtins to C runtime calls
    if fname == "kp" || fname == "print" {
        emit "kr_print(" + args + ")," + p
    }
    if fname == "len" {
        emit "kr_len(" + args + ")," + p
    }
    if fname == "substring" {
        emit "kr_substr(" + args + ")," + p
    }
    if fname == "toInt" {
        emit "kr_toint(" + args + ")," + p
    }
    if fname == "split" {
        emit "kr_split(" + args + ")," + p
    }
    if fname == "startsWith" {
        emit "kr_startswith(" + args + ")," + p
    }
    if fname == "readFile" {
        emit "kr_readfile(" + args + ")," + p
    }
    if fname == "arg" {
        emit "kr_arg(" + args + ")," + p
    }
    if fname == "argCount" {
        emit "kr_argcount()," + p
    }
    if fname == "getLine" {
        emit "kr_getline(" + args + ")," + p
    }
    if fname == "lineCount" {
        emit "kr_linecount(" + args + ")," + p
    }
    if fname == "count" {
        emit "kr_count(" + args + ")," + p
    }

    // Native env/result builtins
    if fname == "envNew" {
        emit "kr_envnew()," + p
    }
    if fname == "envSet" {
        emit "kr_envset(" + args + ")," + p
    }
    if fname == "envGet" {
        emit "kr_envget(" + args + ")," + p
    }
    if fname == "makeResult" {
        emit "kr_makeresult(" + args + ")," + p
    }
    if fname == "getResultTag" {
        emit "kr_getresulttag(" + args + ")," + p
    }
    if fname == "getResultVal" {
        emit "kr_getresultval(" + args + ")," + p
    }
    if fname == "getResultEnv" {
        emit "kr_getresultenv(" + args + ")," + p
    }
    if fname == "getResultPos" {
        emit "kr_getresultpos(" + args + ")," + p
    }
    if fname == "isTruthy" {
        emit "kr_istruthy(" + args + ")," + p
    }
    if fname == "sbNew" {
        emit "kr_sbnew()," + p
    }
    if fname == "sbAppend" {
        emit "kr_sbappend(" + args + ")," + p
    }
    if fname == "sbToString" {
        emit "kr_sbtostring(" + args + ")," + p
    }

    // User-defined function call
    emit cIdent(fname) + "(" + args + ")," + p
}

// =============================================
// Statement Compiler
// Each returns pair: "cCode,pos"
// =============================================

func compileStmt(tokens, pos, ntoks, depth, inFunc) {
    let tok = tokAt(tokens, pos)

    if tok == "KW:let" {
        emit compileLet(tokens, pos + 1, ntoks, depth)
    }

    if tok == "KW:emit" || tok == "KW:return" {
        emit compileEmit(tokens, pos + 1, ntoks, depth, inFunc)
    }

    if tok == "KW:if" {
        emit compileIf(tokens, pos + 1, ntoks, depth, inFunc)
    }

    if tok == "KW:while" {
        emit compileWhile(tokens, pos + 1, ntoks, depth, inFunc)
    }

    if tok == "KW:break" {
        let p = pos + 1
        if tokAt(tokens, p) == "SEMI" {
            p = p + 1
        }
        emit indent(depth) + "break;\n," + p
    }

    // Check for assignment: ID ASSIGN
    if tokType(tok) == "ID" {
        if tokAt(tokens, pos + 1) == "ASSIGN" {
            emit compileAssign(tokens, pos, ntoks, depth)
        }
    }

    // Expression statement (e.g. bare function call)
    emit compileExprStmt(tokens, pos, ntoks, depth)
}

func compileLet(tokens, pos, ntoks, depth) {
    let name = tokVal(tokAt(tokens, pos))
    // skip name, ASSIGN
    let p = pos + 2
    let ep = compileExpr(tokens, p, ntoks)
    let ecode = pairVal(ep)
    p = pairPos(ep)
    if tokAt(tokens, p) == "SEMI" {
        p = p + 1
    }
    emit indent(depth) + "char* " + cIdent(name) + " = " + ecode + ";\n," + p
}

func compileAssign(tokens, pos, ntoks, depth) {
    let name = tokVal(tokAt(tokens, pos))
    // skip name, ASSIGN
    let p = pos + 2
    let ep = compileExpr(tokens, p, ntoks)
    let ecode = pairVal(ep)
    p = pairPos(ep)
    if tokAt(tokens, p) == "SEMI" {
        p = p + 1
    }
    emit indent(depth) + cIdent(name) + " = " + ecode + ";\n," + p
}

func compileEmit(tokens, pos, ntoks, depth, inFunc) {
    let ep = compileExpr(tokens, pos, ntoks)
    let ecode = pairVal(ep)
    let p = pairPos(ep)
    if tokAt(tokens, p) == "SEMI" {
        p = p + 1
    }
    if inFunc == "1" {
        emit indent(depth) + "return " + ecode + ";\n," + p
    }
    // In main: just return 0
    emit indent(depth) + "return 0;\n," + p
}

func compileIf(tokens, pos, ntoks, depth, inFunc) {
    // pos is right after KW:if
    let cp = compileExpr(tokens, pos, ntoks)
    let cond = pairVal(cp)
    let p = pairPos(cp)

    // compile then-block
    let bp = compileBlock(tokens, p, ntoks, depth, inFunc)
    let bcode = pairVal(bp)
    p = pairPos(bp)

    let out = indent(depth) + "if (kr_truthy(" + cond + ")) {\n" + bcode + indent(depth) + "}"

    // check for else
    if tokAt(tokens, p) == "KW:else" {
        p = p + 1
        if tokAt(tokens, p) == "KW:if" {
            // else if — compile the rest as an if statement
            let eip = compileIf(tokens, p + 1, ntoks, depth, inFunc)
            let eicode = pairVal(eip)
            p = pairPos(eip)
            // eicode starts with indent + "if (..."
            // we want " else if (..."
            // strip the leading indent from eicode
            let stripped = substring(eicode, len(indent(depth)), len(eicode))
            out = out + " else " + stripped
            emit out + "," + p
        } else {
            // else block
            let ebp = compileBlock(tokens, p, ntoks, depth, inFunc)
            let ebcode = pairVal(ebp)
            p = pairPos(ebp)
            out = out + " else {\n" + ebcode + indent(depth) + "}\n"
            emit out + "," + p
        }
    }

    out = out + "\n"
    emit out + "," + p
}

func compileWhile(tokens, pos, ntoks, depth, inFunc) {
    let cp = compileExpr(tokens, pos, ntoks)
    let cond = pairVal(cp)
    let p = pairPos(cp)

    let bp = compileBlock(tokens, p, ntoks, depth, inFunc)
    let bcode = pairVal(bp)
    p = pairPos(bp)

    let out = indent(depth) + "while (kr_truthy(" + cond + ")) {\n" + bcode + indent(depth) + "}\n"
    emit out + "," + p
}

func compileExprStmt(tokens, pos, ntoks, depth) {
    let ep = compileExpr(tokens, pos, ntoks)
    let ecode = pairVal(ep)
    let p = pairPos(ep)
    if tokAt(tokens, p) == "SEMI" {
        p = p + 1
    }
    emit indent(depth) + ecode + ";\n," + p
}

// === Block compiler ===

func compileBlock(tokens, pos, ntoks, depth, inFunc) {
    // pos should be at LBRACE
    let p = pos + 1
    let code = ""
    while tokAt(tokens, p) != "RBRACE" {
        // skip stray semicolons
        if tokAt(tokens, p) == "SEMI" {
            p = p + 1
        } else {
            let sp = compileStmt(tokens, p, ntoks, depth + 1, inFunc)
            let sCode = pairVal(sp)
            p = pairPos(sp)
            code = code + sCode
        }
    }
    // skip RBRACE
    p = p + 1
    emit code + "," + p
}

// === Function compiler ===

func compileFunc(tokens, pos, ntoks) {
    // pos is at KW:func
    let nameTok = tokAt(tokens, pos + 1)
    let fname = tokVal(nameTok)
    // skip name, LPAREN
    let p = pos + 3
    let params = ""
    let pc = 0
    while tokAt(tokens, p) != "RPAREN" {
        let pt = tokAt(tokens, p)
        if tokType(pt) == "ID" {
            if pc > 0 {
                params = params + ", char* " + cIdent(tokVal(pt))
            } else {
                params = "char* " + cIdent(tokVal(pt))
            }
            pc = pc + 1
        }
        p = p + 1
    }
    // skip RPAREN
    p = p + 1

    // compile body block
    let bp = compileBlock(tokens, p, ntoks, 0, "1")
    let bcode = pairVal(bp)
    p = pairPos(bp)

    let out = "char* " + cIdent(fname) + "(" + params + ") {\n" + bcode + "}\n\n"
    emit out + "," + p
}

// StringBuilder (Krypton-level: just concat; the C builtins in cRuntime are the fast path)
func sbNew() {
    emit ""
}

func sbAppend(sb, s) {
    emit sb + s
}

func sbToString(sb) {
    emit sb
}

// === C Runtime (embedded in output) ===

func cRuntime() {
    let r = sbNew()
    r = sbAppend(r, "#include <stdio.h>\n")
    r = sbAppend(r, "#include <stdlib.h>\n")
    r = sbAppend(r, "#include <string.h>\n\n")
    r = sbAppend(r, "static int _argc; static char** _argv;\n\n")
    r = sbAppend(r, "typedef struct ABlock { struct ABlock* next; int cap; int used; } ABlock;\n")
    r = sbAppend(r, "static ABlock* _arena = 0;\n")
    r = sbAppend(r, "static char* _alloc(int n) {\n")
    r = sbAppend(r, "    n = (n + 7) & ~7;\n")
    r = sbAppend(r, "    if (!_arena || _arena->used + n > _arena->cap) {\n")
    r = sbAppend(r, "        int cap = 256*1024*1024;\n")
    r = sbAppend(r, "        if (n > cap) cap = n;\n")
    r = sbAppend(r, "        ABlock* b = (ABlock*)malloc(sizeof(ABlock) + cap);\n")
    r = sbAppend(r, "        if (!b) { fprintf(stderr, \"out of memory\\n\"); exit(1); }\n")
    r = sbAppend(r, "        b->cap = cap; b->used = 0; b->next = _arena; _arena = b;\n")
    r = sbAppend(r, "    }\n")
    r = sbAppend(r, "    char* p = (char*)(_arena + 1) + _arena->used;\n")
    r = sbAppend(r, "    _arena->used += n;\n")
    r = sbAppend(r, "    return p;\n")
    r = sbAppend(r, "}\n\n")
    r = sbAppend(r, "static char* kr_str(const char* s) {\n")
    r = sbAppend(r, "    int n = (int)strlen(s) + 1;\n")
    r = sbAppend(r, "    char* p = _alloc(n);\n")
    r = sbAppend(r, "    memcpy(p, s, n);\n")
    r = sbAppend(r, "    return p;\n")
    r = sbAppend(r, "}\n\n")
    r = sbAppend(r, "static char* kr_cat(const char* a, const char* b) {\n")
    r = sbAppend(r, "    int la = (int)strlen(a), lb = (int)strlen(b);\n")
    r = sbAppend(r, "    char* p = _alloc(la + lb + 1);\n")
    r = sbAppend(r, "    memcpy(p, a, la);\n")
    r = sbAppend(r, "    memcpy(p + la, b, lb + 1);\n")
    r = sbAppend(r, "    return p;\n")
    r = sbAppend(r, "}\n\n")
    r = sbAppend(r, "static int kr_isnum(const char* s) {\n")
    r = sbAppend(r, "    if (!*s) return 0;\n")
    r = sbAppend(r, "    const char* p = s;\n")
    r = sbAppend(r, "    if (*p == '-') p++;\n")
    r = sbAppend(r, "    if (!*p) return 0;\n")
    r = sbAppend(r, "    while (*p) { if (*p < '0' || *p > '9') return 0; p++; }\n")
    r = sbAppend(r, "    return 1;\n")
    r = sbAppend(r, "}\n\n")
    r = sbAppend(r, "static char* kr_itoa(int v) {\n")
    r = sbAppend(r, "    char buf[32];\n")
    r = sbAppend(r, "    snprintf(buf, sizeof(buf), \"%d\", v);\n")
    r = sbAppend(r, "    return kr_str(buf);\n")
    r = sbAppend(r, "}\n\n")
    r = sbAppend(r, "static int kr_atoi(const char* s) { return atoi(s); }\n\n")
    r = sbAppend(r, "static char* kr_plus(const char* a, const char* b) {\n")
    r = sbAppend(r, "    if (kr_isnum(a) && kr_isnum(b))\n")
    r = sbAppend(r, "        return kr_itoa(atoi(a) + atoi(b));\n")
    r = sbAppend(r, "    return kr_cat(a, b);\n")
    r = sbAppend(r, "}\n\n")
    r = sbAppend(r, "static char* kr_sub(const char* a, const char* b) { return kr_itoa(atoi(a) - atoi(b)); }\n")
    r = sbAppend(r, "static char* kr_mul(const char* a, const char* b) { return kr_itoa(atoi(a) * atoi(b)); }\n")
    r = sbAppend(r, "static char* kr_div(const char* a, const char* b) { return kr_itoa(atoi(a) / atoi(b)); }\n")
    r = sbAppend(r, "static char* kr_mod(const char* a, const char* b) { return kr_itoa(atoi(a) % atoi(b)); }\n")
    r = sbAppend(r, "static char* kr_neg(const char* a) { return kr_itoa(-atoi(a)); }\n")
    r = sbAppend(r, "static char* kr_not(const char* a) { return kr_str(atoi(a) ? \"0\" : \"1\"); }\n\n")
    r = sbAppend(r, "static char* kr_eq(const char* a, const char* b) {\n")
    r = sbAppend(r, "    return kr_str(strcmp(a, b) == 0 ? \"1\" : \"0\");\n")
    r = sbAppend(r, "}\n")
    r = sbAppend(r, "static char* kr_neq(const char* a, const char* b) {\n")
    r = sbAppend(r, "    return kr_str(strcmp(a, b) != 0 ? \"1\" : \"0\");\n")
    r = sbAppend(r, "}\n")
    r = sbAppend(r, "static char* kr_lt(const char* a, const char* b) {\n")
    r = sbAppend(r, "    if (kr_isnum(a) && kr_isnum(b)) return kr_str(atoi(a) < atoi(b) ? \"1\" : \"0\");\n")
    r = sbAppend(r, "    return kr_str(strcmp(a, b) < 0 ? \"1\" : \"0\");\n")
    r = sbAppend(r, "}\n")
    r = sbAppend(r, "static char* kr_gt(const char* a, const char* b) {\n")
    r = sbAppend(r, "    if (kr_isnum(a) && kr_isnum(b)) return kr_str(atoi(a) > atoi(b) ? \"1\" : \"0\");\n")
    r = sbAppend(r, "    return kr_str(strcmp(a, b) > 0 ? \"1\" : \"0\");\n")
    r = sbAppend(r, "}\n")
    r = sbAppend(r, "static char* kr_lte(const char* a, const char* b) {\n")
    r = sbAppend(r, "    return kr_str(strcmp(kr_gt(a, b), \"0\") == 0 ? \"1\" : \"0\");\n")
    r = sbAppend(r, "}\n")
    r = sbAppend(r, "static char* kr_gte(const char* a, const char* b) {\n")
    r = sbAppend(r, "    return kr_str(strcmp(kr_lt(a, b), \"0\") == 0 ? \"1\" : \"0\");\n")
    r = sbAppend(r, "}\n\n")
    r = sbAppend(r, "static int kr_truthy(const char* s) {\n")
    r = sbAppend(r, "    if (!s || !*s) return 0;\n")
    r = sbAppend(r, "    if (strcmp(s, \"0\") == 0) return 0;\n")
    r = sbAppend(r, "    return 1;\n")
    r = sbAppend(r, "}\n\n")
    r = sbAppend(r, "static char* kr_print(const char* s) {\n")
    r = sbAppend(r, "    printf(\"%s\\n\", s);\n")
    r = sbAppend(r, "    return kr_str(\"\");\n")
    r = sbAppend(r, "}\n\n")
    r = sbAppend(r, "static char* kr_len(const char* s) { return kr_itoa((int)strlen(s)); }\n\n")
    r = sbAppend(r, "static char* kr_idx(const char* s, int i) {\n")
    r = sbAppend(r, "    char buf[2] = {s[i], 0};\n")
    r = sbAppend(r, "    return kr_str(buf);\n")
    r = sbAppend(r, "}\n\n")
    r = sbAppend(r, "static char* kr_split(const char* s, const char* idxs) {\n")
    r = sbAppend(r, "    int idx = atoi(idxs);\n")
    r = sbAppend(r, "    int count = 0;\n")
    r = sbAppend(r, "    const char* start = s;\n")
    r = sbAppend(r, "    const char* p = s;\n")
    r = sbAppend(r, "    while (*p) {\n")
    r = sbAppend(r, "        if (*p == ',') {\n")
    r = sbAppend(r, "            if (count == idx) {\n")
    r = sbAppend(r, "                int len = (int)(p - start);\n")
    r = sbAppend(r, "                char* r = _alloc(len + 1);\n")
    r = sbAppend(r, "                memcpy(r, start, len);\n")
    r = sbAppend(r, "                r[len] = 0;\n")
    r = sbAppend(r, "                return r;\n")
    r = sbAppend(r, "            }\n")
    r = sbAppend(r, "            count++;\n")
    r = sbAppend(r, "            start = p + 1;\n")
    r = sbAppend(r, "        }\n")
    r = sbAppend(r, "        p++;\n")
    r = sbAppend(r, "    }\n")
    r = sbAppend(r, "    if (count == idx) return kr_str(start);\n")
    r = sbAppend(r, "    return kr_str(\"\");\n")
    r = sbAppend(r, "}\n\n")
    r = sbAppend(r, "static char* kr_startswith(const char* s, const char* prefix) {\n")
    r = sbAppend(r, "    return kr_str(strncmp(s, prefix, strlen(prefix)) == 0 ? \"1\" : \"0\");\n")
    r = sbAppend(r, "}\n\n")
    r = sbAppend(r, "static char* kr_substr(const char* s, const char* starts, const char* ends) {\n")
    r = sbAppend(r, "    int st = atoi(starts), en = atoi(ends);\n")
    r = sbAppend(r, "    int slen = (int)strlen(s);\n")
    r = sbAppend(r, "    if (st >= slen) return kr_str(\"\");\n")
    r = sbAppend(r, "    if (en > slen) en = slen;\n")
    r = sbAppend(r, "    int n = en - st;\n")
    r = sbAppend(r, "    if (n <= 0) return kr_str(\"\");\n")
    r = sbAppend(r, "    char* r = _alloc(n + 1);\n")
    r = sbAppend(r, "    memcpy(r, s + st, n);\n")
    r = sbAppend(r, "    r[n] = 0;\n")
    r = sbAppend(r, "    return r;\n")
    r = sbAppend(r, "}\n\n")
    r = sbAppend(r, "static char* kr_toint(const char* s) { return kr_itoa(atoi(s)); }\n\n")
    r = sbAppend(r, "static char* kr_readfile(const char* path) {\n")
    r = sbAppend(r, "    FILE* f = fopen(path, \"rb\");\n")
    r = sbAppend(r, "    if (!f) return kr_str(\"\");\n")
    r = sbAppend(r, "    fseek(f, 0, SEEK_END);\n")
    r = sbAppend(r, "    long sz = ftell(f);\n")
    r = sbAppend(r, "    fseek(f, 0, SEEK_SET);\n")
    r = sbAppend(r, "    char* buf = _alloc((int)sz + 1);\n")
    r = sbAppend(r, "    fread(buf, 1, sz, f);\n")
    r = sbAppend(r, "    buf[sz] = 0;\n")
    r = sbAppend(r, "    fclose(f);\n")
    r = sbAppend(r, "    return buf;\n")
    r = sbAppend(r, "}\n\n")
    r = sbAppend(r, "static char* kr_arg(const char* idxs) {\n")
    r = sbAppend(r, "    int idx = atoi(idxs) + 1;\n")
    r = sbAppend(r, "    if (idx < _argc) return kr_str(_argv[idx]);\n")
    r = sbAppend(r, "    return kr_str(\"\");\n")
    r = sbAppend(r, "}\n\n")
    r = sbAppend(r, "static char* kr_argcount() {\n")
    r = sbAppend(r, "    return kr_itoa(_argc - 1);\n")
    r = sbAppend(r, "}\n\n")
    r = sbAppend(r, "static char* kr_getline(const char* s, const char* idxs) {\n")
    r = sbAppend(r, "    int idx = atoi(idxs);\n")
    r = sbAppend(r, "    int cur = 0;\n")
    r = sbAppend(r, "    const char* start = s;\n")
    r = sbAppend(r, "    const char* p = s;\n")
    r = sbAppend(r, "    while (*p) {\n")
    r = sbAppend(r, "        if (*p == '\\n') {\n")
    r = sbAppend(r, "            if (cur == idx) {\n")
    r = sbAppend(r, "                int len = (int)(p - start);\n")
    r = sbAppend(r, "                char* r = _alloc(len + 1);\n")
    r = sbAppend(r, "                memcpy(r, start, len);\n")
    r = sbAppend(r, "                r[len] = 0;\n")
    r = sbAppend(r, "                return r;\n")
    r = sbAppend(r, "            }\n")
    r = sbAppend(r, "            cur++;\n")
    r = sbAppend(r, "            start = p + 1;\n")
    r = sbAppend(r, "        }\n")
    r = sbAppend(r, "        p++;\n")
    r = sbAppend(r, "    }\n")
    r = sbAppend(r, "    if (cur == idx) return kr_str(start);\n")
    r = sbAppend(r, "    return kr_str(\"\");\n")
    r = sbAppend(r, "}\n\n")
    r = sbAppend(r, "static char* kr_linecount(const char* s) {\n")
    r = sbAppend(r, "    if (!*s) return kr_str(\"0\");\n")
    r = sbAppend(r, "    int count = 1;\n")
    r = sbAppend(r, "    const char* p = s;\n")
    r = sbAppend(r, "    while (*p) { if (*p == '\\n') count++; p++; }\n")
    r = sbAppend(r, "    if (*(p - 1) == '\\n') count--;\n")
    r = sbAppend(r, "    return kr_itoa(count);\n")
    r = sbAppend(r, "}\n\n")
    r = sbAppend(r, "static char* kr_count(const char* s) {\n")
    r = sbAppend(r, "    return kr_linecount(s);\n")
    r = sbAppend(r, "}\n\n")

    // Native env (linked-list of entries, cast to char*)
    r = sbAppend(r, "typedef struct EnvEntry { char* name; char* value; struct EnvEntry* prev; } EnvEntry;\n\n")

    r = sbAppend(r, "static char* kr_envnew() { return (char*)0; }\n\n")

    r = sbAppend(r, "static char* kr_envset(char* envp, const char* name, const char* val) {\n")
    r = sbAppend(r, "    EnvEntry* e = (EnvEntry*)_alloc(sizeof(EnvEntry));\n")
    r = sbAppend(r, "    e->name = (char*)name;\n")
    r = sbAppend(r, "    e->value = (char*)val;\n")
    r = sbAppend(r, "    e->prev = (EnvEntry*)envp;\n")
    r = sbAppend(r, "    return (char*)e;\n")
    r = sbAppend(r, "}\n\n")

    r = sbAppend(r, "static char* kr_envget(char* envp, const char* name) {\n")
    r = sbAppend(r, "    EnvEntry* e = (EnvEntry*)envp;\n")
    r = sbAppend(r, "    while (e) {\n")
    r = sbAppend(r, "        if (strcmp(e->name, name) == 0) return e->value;\n")
    r = sbAppend(r, "        e = e->prev;\n")
    r = sbAppend(r, "    }\n")
    r = sbAppend(r, "    if (strcmp(name, \"__argOffset\") != 0)\n")
    r = sbAppend(r, "        fprintf(stderr, \"ERROR: undefined variable: %s\\n\", name);\n")
    r = sbAppend(r, "    return kr_str(\"\");\n")
    r = sbAppend(r, "}\n\n")

    // Native result (struct with tag, val, env, pos)
    r = sbAppend(r, "typedef struct ResultStruct { char tag; char* val; char* env; int pos; } ResultStruct;\n\n")

    r = sbAppend(r, "static char* kr_makeresult(const char* tag, const char* val, const char* env, const char* pos) {\n")
    r = sbAppend(r, "    ResultStruct* r = (ResultStruct*)_alloc(sizeof(ResultStruct));\n")
    r = sbAppend(r, "    r->tag = tag[0];\n")
    r = sbAppend(r, "    r->val = (char*)val;\n")
    r = sbAppend(r, "    r->env = (char*)env;\n")
    r = sbAppend(r, "    r->pos = atoi(pos);\n")
    r = sbAppend(r, "    return (char*)r;\n")
    r = sbAppend(r, "}\n\n")

    r = sbAppend(r, "static char* kr_getresulttag(const char* r) {\n")
    r = sbAppend(r, "    char buf[2] = {((ResultStruct*)r)->tag, 0};\n")
    r = sbAppend(r, "    return kr_str(buf);\n")
    r = sbAppend(r, "}\n\n")

    r = sbAppend(r, "static char* kr_getresultval(const char* r) {\n")
    r = sbAppend(r, "    return ((ResultStruct*)r)->val;\n")
    r = sbAppend(r, "}\n\n")

    r = sbAppend(r, "static char* kr_getresultenv(const char* r) {\n")
    r = sbAppend(r, "    return ((ResultStruct*)r)->env;\n")
    r = sbAppend(r, "}\n\n")

    r = sbAppend(r, "static char* kr_getresultpos(const char* r) {\n")
    r = sbAppend(r, "    return kr_itoa(((ResultStruct*)r)->pos);\n")
    r = sbAppend(r, "}\n\n")

    r = sbAppend(r, "static char* kr_istruthy(const char* s) {\n")
    r = sbAppend(r, "    if (!s || !*s || strcmp(s, \"0\") == 0 || strcmp(s, \"false\") == 0)\n")
    r = sbAppend(r, "        return kr_str(\"0\");\n")
    r = sbAppend(r, "    return kr_str(\"1\");\n")
    r = sbAppend(r, "}\n\n")

    // StringBuilder: handle-based, mutable buffer with capacity doubling
    r = sbAppend(r, "typedef struct { int cap; int len; } SBHdr;\n")
    r = sbAppend(r, "#define MAX_SBS 4096\n")
    r = sbAppend(r, "static SBHdr* _sb_table[MAX_SBS];\n")
    r = sbAppend(r, "static int _sb_count = 0;\n\n")
    r = sbAppend(r, "static char* kr_sbnew() {\n")
    r = sbAppend(r, "    int initcap = 65536;\n")
    r = sbAppend(r, "    SBHdr* h = (SBHdr*)malloc(sizeof(SBHdr) + initcap);\n")
    r = sbAppend(r, "    h->cap = initcap;\n")
    r = sbAppend(r, "    h->len = 0;\n")
    r = sbAppend(r, "    ((char*)(h + 1))[0] = 0;\n")
    r = sbAppend(r, "    _sb_table[_sb_count] = h;\n")
    r = sbAppend(r, "    return kr_itoa(_sb_count++);\n")
    r = sbAppend(r, "}\n\n")
    r = sbAppend(r, "static char* kr_sbappend(const char* handle, const char* s) {\n")
    r = sbAppend(r, "    int idx = atoi(handle);\n")
    r = sbAppend(r, "    SBHdr* h = _sb_table[idx];\n")
    r = sbAppend(r, "    int slen = (int)strlen(s);\n")
    r = sbAppend(r, "    while (h->len + slen + 1 > h->cap) {\n")
    r = sbAppend(r, "        int newcap = h->cap * 2;\n")
    r = sbAppend(r, "        h = (SBHdr*)realloc(h, sizeof(SBHdr) + newcap);\n")
    r = sbAppend(r, "        h->cap = newcap;\n")
    r = sbAppend(r, "    }\n")
    r = sbAppend(r, "    memcpy((char*)(h + 1) + h->len, s, slen);\n")
    r = sbAppend(r, "    h->len += slen;\n")
    r = sbAppend(r, "    ((char*)(h + 1))[h->len] = 0;\n")
    r = sbAppend(r, "    _sb_table[idx] = h;\n")
    r = sbAppend(r, "    return kr_str(handle);\n")
    r = sbAppend(r, "}\n\n")
    r = sbAppend(r, "static char* kr_sbtostring(const char* handle) {\n")
    r = sbAppend(r, "    int idx = atoi(handle);\n")
    r = sbAppend(r, "    SBHdr* h = _sb_table[idx];\n")
    r = sbAppend(r, "    return (char*)(h + 1);\n")
    r = sbAppend(r, "}\n\n")

    emit sbToString(r)
}

// =============================================
// Main: compile a .k file to C
// =============================================

just run {
    let file = arg(0)
    let source = readFile(file)

    let tokens = tokenize(source)
    let ntoks = lineCount(tokens)

    let ftable = scanFunctions(tokens, ntoks)

    // Output the C runtime
    let sb = sbNew()
    sb = sbAppend(sb, cRuntime())

    // Compile all func declarations (forward declare then define)
    // First pass: emit forward declarations
    let i = 0
    while i < ntoks {
        let tok = tokAt(tokens, i)
        if tok == "KW:func" {
            let nameTok = tokAt(tokens, i + 1)
            let fname = tokVal(nameTok)
            let info = funcLookup(ftable, fname)
            let pc = funcParamCount(info)
            let paramStr = funcParams(info)
            let decl = "char* " + cIdent(fname) + "("
            let pi = 0
            while pi < pc {
                if pi > 0 {
                    decl = decl + ", "
                }
                decl = decl + "char*"
                pi = pi + 1
            }
            decl = decl + ");\n"
            sb = sbAppend(sb, decl)
        }
        i = i + 1
    }
    sb = sbAppend(sb, "\n")

    // Second pass: compile function bodies
    i = 0
    while i < ntoks {
        let tok = tokAt(tokens, i)
        if tok == "KW:func" {
            let fp = compileFunc(tokens, i, ntoks)
            let fcode = pairVal(fp)
            sb = sbAppend(sb, fcode)
            // skip past the function in token stream
            i = pairPos(fp)
        } else {
            i = i + 1
        }
    }

    // Find and compile the entry block
    let entry = findEntry(tokens, ntoks)
    if entry < 0 {
        print("No entry point found")
        emit 1
    }

    sb = sbAppend(sb, "int main(int argc, char** argv) {\n")
    sb = sbAppend(sb, "    _argc = argc; _argv = argv;\n")

    let bp = compileBlock(tokens, entry, ntoks, 0, "0")
    let bcode = pairVal(bp)
    sb = sbAppend(sb, bcode)
    sb = sbAppend(sb, "    return 0;\n")
    sb = sbAppend(sb, "}\n")

    print(sbToString(sb))
    emit "ok"
}
