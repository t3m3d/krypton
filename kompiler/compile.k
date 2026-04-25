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
        i -= 1
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

// === Lexer helpers ===

func isDigit(c) {
    emit c >= "0" && c <= "9"
}

func charIsAlpha(c) {
    emit (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_"
}

func charIsAlphaNum(c) {
    emit charIsAlpha(c) || (c >= "0" && c <= "9")
}

func hexDigitVal(c) {
    if c >= "0" && c <= "9" { emit charCode(c) - charCode("0") }
    if c >= "a" && c <= "f" { emit charCode(c) - charCode("a") + 10 }
    if c >= "A" && c <= "F" { emit charCode(c) - charCode("A") + 10 }
    emit -1
}

func readNumber(text, i) {
    let start = i
    // hex literal: 0x... or 0X...
    if text[i] == "0" && i + 1 < len(text) && (text[i + 1] == "x" || text[i + 1] == "X") {
        i = i + 2
        let hexVal = 0
        while i < len(text) && hexDigitVal(text[i]) >= 0 {
            hexVal = hexVal * 16 + hexDigitVal(text[i])
            i += 1
        }
        emit hexVal + "," + i
    }
    while i < len(text) && isDigit(text[i]) {
        i += 1
    }
    // check for float: digits followed by . followed by digits
    if i < len(text) && text[i] == "." {
        if i + 1 < len(text) && isDigit(text[i + 1]) {
            i += 1
            while i < len(text) && isDigit(text[i]) {
                i += 1
            }
        }
    }
    emit substring(text, start, i) + "," + i
}

func readIdent(text, i) {
    let start = i
    while i < len(text) && charIsAlphaNum(text[i]) {
        i += 1
    }
    emit substring(text, start, i) + "," + i
}

func readString(text, i) {
    i += 1
    let start = i
    let s = ""
    while i < len(text) && text[i] != "\"" {
        if text[i] == "\\" && i + 1 < len(text) {
            if i > start {
                s = s + substring(text, start, i)
            }
            s = s + substring(text, i, i + 2)
            i = i + 2
            start = i
        }
        else {
            i += 1
        }
    }
    if i > start {
        s = s + substring(text, start, i)
    }
    emit s + "," + (i + 1)
}

func skipWS(text, i) {
    while i < len(text) && (text[i] == " " || text[i] == "\n" || text[i] == "\t" || text[i] == "\r") {
        i += 1
    }
    emit i
}

func skipComment(text, i) {
    if i + 1 < len(text) && text[i] == "/" && text[i + 1] == "/" {
        while i < len(text) && text[i] != "\n" {
            i += 1
        }
        emit i
    }
    else if i + 1 < len(text) && text[i] == "/" && text[i + 1] == "*" {
        i = i + 2
        while i + 1 < len(text) && (text[i] != "*" || text[i + 1] != "/") {
            i += 1
        }
        emit i + 2
    }
    emit i
}

func isKW(word) {
    if word == "just" { emit 1 }
    else if word == "go" { emit 1 }
    else if word == "func" { emit 1 }
    else if word == "fn" { emit 1 }
    else if word == "let" { emit 1 }
    else if word == "emit" { emit 1 }
    else if word == "return" { emit 1 }
    else if word == "if" { emit 1 }
    else if word == "else" { emit 1 }
    else if word == "while" { emit 1 }
    else if word == "break" { emit 1 }
    else if word == "continue" { emit 1 }
    else if word == "for" { emit 1 }
    else if word == "in" { emit 1 }
    else if word == "match" { emit 1 }
    else if word == "do" { emit 1 }
    else if word == "const" { emit 1 }
    else if word == "module" { emit 1 }
    else if word == "import" { emit 1 }
    else if word == "export" { emit 1 }
    else if word == "struct" { emit 1 }
    else if word == "class" { emit 1 }
    else if word == "type" { emit 1 }
    else if word == "try" { emit 1 }
    else if word == "catch" { emit 1 }
    else if word == "throw" { emit 1 }
    else if word == "quantum" { emit 1 }
    else if word == "qpute" { emit 1 }
    else if word == "process" { emit 1 }
    else if word == "true" { emit 1 }
    else if word == "false" { emit 1 }
    else if word == "null" { emit 1 }
    else if word == "measure" { emit 1 }
    else if word == "prepare" { emit 1 }
    else if word == "jxt" { emit 1 }
    else if word == "callback" { emit 1 }
    else if word == "loop" { emit 1 }
    else if word == "until" { emit 1 }
    else { emit 0 }
}

func readBacktickString(text, i) {
    // read from ` to next ` preserving {expr} markers
    i += 1
    let s = ""
    while i < len(text) && text[i] != "`" {
        s = s + text[i]
        i += 1
    }
    emit s + "," + (i + 1)
}

func tokenize(text) {
    let out = sbNew()
    let i = 0

    while i < len(text) {
        i = skipWS(text, i)

        if i >= len(text) {
            break
        }

        let c = text[i]

        if c == "/" && i + 1 < len(text) && (text[i + 1] == "/" || text[i + 1] == "*") {
            i = skipComment(text, i)
        }
        else if isDigit(c) {
            let pair = readNumber(text, i)
            let num = pairVal(pair)
            i = pairPos(pair)
            out = sbAppend(out, "INT:" + num + "\n")
        }
        else if c == "\"" {
            let pair = readString(text, i)
            let str = pairVal(pair)
            i = pairPos(pair)
            out = sbAppend(out, "STR:" + str + "\n")
        }
        else if charIsAlpha(c) {
            let pair = readIdent(text, i)
            let id = pairVal(pair)
            i = pairPos(pair)
            // cfunc { } — read raw C block, emit CBLOCK token
            if id == "cfunc" {
                let ci2 = skipWS(text, i)
                if ci2 < len(text) && text[ci2] == "{" {
                    ci2 += 1
                    let ctext = ""
                    let cdepth = 1
                    let inStr = 0
                    while ci2 < len(text) && cdepth > 0 {
                        let ch = text[ci2]
                        if inStr == 1 {
                            if ch == "\\" && ci2 + 1 < len(text) {
                                ctext = ctext + ch + text[ci2 + 1]
                                ci2 += 2
                            } else {
                                if ch == "\"" { inStr = 0 }
                                if ch == "\n" { ctext = ctext + "\x01" }
                                else { ctext = ctext + ch }
                                ci2 += 1
                            }
                        } else {
                            if ch == "\"" { inStr = 1  ctext = ctext + ch  ci2 += 1 }
                            else if ch == "{" { cdepth += 1  ctext = ctext + ch  ci2 += 1 }
                            else if ch == "}" {
                                cdepth -= 1
                                if cdepth > 0 { ctext = ctext + ch }
                                ci2 += 1
                            }
                            else if ch == "\n" { ctext = ctext + "\x01"  ci2 += 1 }
                            else if ch == "\r" { ci2 += 1 }
                            else { ctext = ctext + ch  ci2 += 1 }
                        }
                    }
                    i = ci2
                    out = sbAppend(out, "CBLOCK:" + ctext + "\n")
                }
            } else if isKW(id) {
                out = sbAppend(out, "KW:" + id + "\n")
            }
            else {
                out = sbAppend(out, "ID:" + id + "\n")
            }
        }
        else if c == "+" {
            if i + 1 < len(text) && text[i + 1] == "+" {
                out = sbAppend(out, "PLUSPLUS\n")
                i = i + 2
            } else if i + 1 < len(text) && text[i + 1] == "=" {
                out = sbAppend(out, "PLUSEQ\n")
                i = i + 2
            } else {
                out = sbAppend(out, "PLUS\n")
                i += 1
            }
        }
        else if c == "-" {
            if i + 1 < len(text) && text[i + 1] == ">" {
                out = sbAppend(out, "ARROW\n")
                i = i + 2
            }
            else if i + 1 < len(text) && text[i + 1] == "-" {
                out = sbAppend(out, "MINUSMINUS\n")
                i = i + 2
            }
            else if i + 1 < len(text) && text[i + 1] == "=" {
                out = sbAppend(out, "MINUSEQ\n")
                i = i + 2
            }
            else {
                out = sbAppend(out, "MINUS\n")
                i += 1
            }
        }
        else if c == "*" {
            if i + 1 < len(text) && text[i + 1] == "*" {
                out = sbAppend(out, "STARSTAR\n")
                i = i + 2
            } else if i + 1 < len(text) && text[i + 1] == "=" {
                out = sbAppend(out, "STAREQ\n")
                i = i + 2
            } else {
                out = sbAppend(out, "STAR\n")
                i += 1
            }
        }
        else if c == "/" {
            if i + 1 < len(text) && text[i + 1] == "=" {
                out = sbAppend(out, "SLASHEQ\n")
                i = i + 2
            } else {
                out = sbAppend(out, "SLASH\n")
                i += 1
            }
        }
        else if c == "(" {
            out = sbAppend(out, "LPAREN\n")
            i += 1
        }
        else if c == ")" {
            out = sbAppend(out, "RPAREN\n")
            i += 1
        }
        else if c == "{" {
            out = sbAppend(out, "LBRACE\n")
            i += 1
        }
        else if c == "}" {
            out = sbAppend(out, "RBRACE\n")
            i += 1
        }
        else if c == "[" {
            out = sbAppend(out, "LBRACK\n")
            i += 1
        }
        else if c == "]" {
            out = sbAppend(out, "RBRACK\n")
            i += 1
        }
        else if c == ":" {
            out = sbAppend(out, "COLON\n")
            i += 1
        }
        else if c == ";" {
            out = sbAppend(out, "SEMI\n")
            i += 1
        }
        else if c == "," {
            out = sbAppend(out, "COMMA\n")
            i += 1
        }
        else if c == "=" {
            if i + 1 < len(text) && text[i + 1] == "=" {
                out = sbAppend(out, "EQ\n")
                i = i + 2
            }
            else {
                out = sbAppend(out, "ASSIGN\n")
                i += 1
            }
        }
        else if c == "!" {
            if i + 1 < len(text) && text[i + 1] == "=" {
                out = sbAppend(out, "NEQ\n")
                i = i + 2
            }
            else {
                out = sbAppend(out, "BANG\n")
                i += 1
            }
        }
        else if c == "<" {
            if i + 1 < len(text) && text[i + 1] == "=" {
                out = sbAppend(out, "LTE\n")
                i = i + 2
            }
            else {
                out = sbAppend(out, "LT\n")
                i += 1
            }
        }
        else if c == ">" {
            if i + 1 < len(text) && text[i + 1] == "=" {
                out = sbAppend(out, "GTE\n")
                i = i + 2
            }
            else {
                out = sbAppend(out, "GT\n")
                i += 1
            }
        }
        else if c == "&" {
            if i + 1 < len(text) && text[i + 1] == "&" {
                out = sbAppend(out, "AND\n")
                i = i + 2
            }
            else {
                i += 1
            }
        }
        else if c == "|" {
            if i + 1 < len(text) && text[i + 1] == "|" {
                out = sbAppend(out, "OR\n")
                i = i + 2
            }
            else {
                i += 1
            }
        }
        else if c == "%" {
            if i + 1 < len(text) && text[i + 1] == "=" {
                out = sbAppend(out, "MODEQ\n")
                i = i + 2
            } else {
                out = sbAppend(out, "MOD\n")
                i += 1
            }
        }
        else if c == "?" {
            out = sbAppend(out, "QUESTION\n")
            i += 1
        }
        else if c == "." {
            out = sbAppend(out, "DOT\n")
            i += 1
        }
        else if c == "`" {
            // backtick string: `text {expr} text`
            let pair = readBacktickString(text, i)
            let str = pairVal(pair)
            i = pairPos(pair)
            out = sbAppend(out, "INTERP:" + str + "\n")
        }
        else {
            i += 1
        }
    }

    emit sbToString(out)
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
        i += 1
    }
    emit tok
}

func tokVal(tok) {
    let i = 0
    while i < len(tok) {
        if tok[i] == ":" {
            emit substring(tok, i + 1, len(tok))
        }
        i += 1
    }
    emit ""
}

// === C string escaping ===

func cEscape(s) {
    let out = ""
    let i = 0
    let start = 0
    while i < len(s) {
        let c = s[i]
        if c == "\\" || c == "\"" || c == "\n" || c == "\r" || c == "\t" {
            if i > start {
                out = out + substring(s, start, i)
            }
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
            }
            start = i + 1
        }
        i += 1
    }
    if i > start {
        out = out + substring(s, start, i)
    }
    emit out
}

// === Expand escape sequences in string tokens ===

func expandEscapes(s) {
    let out = ""
    let i = 0
    let start = 0
    while i < len(s) {
        if s[i] == "\\" {
            if i > start {
                out = out + substring(s, start, i)
            }
            i += 1
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
            start = i + 1
        }
        i += 1
    }
    if i > start {
        out = out + substring(s, start, i)
    }
    emit out
}

// === Function table helpers ===

func scanFunctions(tokens, ntoks) {
    let table = sbNew()
    let i = 0
    while i < ntoks {
        let tok = tokAt(tokens, i)
        if tok == "KW:jxt" {
            i = skipBlock(tokens, i + 1)
        } else if tok == "KW:func" {
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
                    pc += 1
                    // skip optional type annotation: param: type
                    if tokAt(tokens, j + 1) == "COLON" {
                        j = j + 3
                        // skip compound type: list[int]
                        if tokAt(tokens, j) == "LBRACK" {
                            let std = 1
                            j += 1
                            while std > 0 {
                                if tokAt(tokens, j) == "LBRACK" { std += 1 }
                                if tokAt(tokens, j) == "RBRACK" { std -= 1 }
                                j += 1
                            }
                        }
                        if tokAt(tokens, j) == "COMMA" { j += 1 }
                    } else {
                        j += 1
                    }
                } else {
                    j += 1
                }
            }
            // j is at RPAREN, j+1 is LBRACE
            let bodyStart = j + 1
            table = sbAppend(table, fname + "~" + pc + "~" + params + "~" + bodyStart + "\n")
        }
        i += 1
    }
    emit sbToString(table)
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
            nl += 1
        }
        let line = substring(table, i, nl)
        // find first ~
        let t1 = 0
        while t1 < len(line) {
            if line[t1] == "~" {
                break
            }
            t1 += 1
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
        i += 1
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
                j += 1
            }
            emit rest
        }
        i += 1
    }
    emit ""
}

func funcStart(info) {
    let i = len(info) - 1
    while i >= 0 {
        if info[i] == "~" {
            emit toInt(substring(info, i + 1, len(info)))
        }
        i -= 1
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
            count += 1
            start = i + 1
        }
        i += 1
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
        i += 1
    }
    emit 0 - 1
}

func skipBlock(tokens, pos) {
    let depth = 1
    let p = pos + 1
    while depth > 0 {
        let t = tokAt(tokens, p)
        if t == "LBRACE" {
            depth += 1
        }
        if t == "RBRACE" {
            depth -= 1
        }
        p += 1
    }
    emit p
}

// === Indentation helper ===

func indent(depth) {
    let out = ""
    let i = 0
    while i < depth {
        out = out + "    "
        i += 1
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
    // Avoid clashes with C stdlib functions and C type keywords
    if name == "abs" || name == "exit" || name == "rand" || name == "free" || name == "malloc" || name == "printf" || name == "strlen" || name == "strcmp" || name == "strcpy" || name == "time" {
        emit "k_" + name
    }
    if name == "double" || name == "float" || name == "int" || name == "bool" || name == "string" || name == "list" || name == "map" || name == "any" || name == "void" || name == "num" {
        emit "k_" + name
    }
    emit name
}

// =============================================
// Expression Compiler
// Each returns pair: "cExprCode,pos"
// =============================================

func compileExpr(tokens, pos, ntoks) {
    emit compileTernary(tokens, pos, ntoks)
}

func compileTernary(tokens, pos, ntoks) {
    let pair = compileOr(tokens, pos, ntoks)
    let code = pairVal(pair)
    let p = pairPos(pair)
    if tokAt(tokens, p) == "QUESTION" {
        let tp = compileExpr(tokens, p + 1, ntoks)
        let tcode = pairVal(tp)
        p = pairPos(tp)
        // expect COLON
        p += 1
        let fp = compileExpr(tokens, p, ntoks)
        let fcode = pairVal(fp)
        p = pairPos(fp)
        code = "(kr_truthy(" + code + ") ? " + tcode + " : " + fcode + ")"
    }
    emit code + "," + p
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
    let pair = compilePow(tokens, pos, ntoks)
    let code = pairVal(pair)
    let p = pairPos(pair)
    while tokAt(tokens, p) == "STAR" || tokAt(tokens, p) == "SLASH" || tokAt(tokens, p) == "MOD" {
        let op = tokAt(tokens, p)
        let rp = compilePow(tokens, p + 1, ntoks)
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

// ** exponentiation operator — right-associative, higher precedence than * / %
func compilePow(tokens, pos, ntoks) {
    let pair = compileUnary(tokens, pos, ntoks)
    let code = pairVal(pair)
    let p = pairPos(pair)
    if tokAt(tokens, p) == "STARSTAR" {
        // right-associative: recurse into compilePow for right side
        let rp = compilePow(tokens, p + 1, ntoks)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        code = "kr_pow(" + code + ", " + rcode + ")"
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
    // Pre-increment / pre-decrement: ++x, --x
    if tok == "PLUSPLUS" {
        let rp = compilePostfix(tokens, pos + 1, ntoks)
        let rcode = pairVal(rp)
        let p = pairPos(rp)
        emit "(" + rcode + " = kr_plus(" + rcode + ", kr_str(\"1\")))," + p
    }
    if tok == "MINUSMINUS" {
        let rp = compilePostfix(tokens, pos + 1, ntoks)
        let rcode = pairVal(rp)
        let p = pairPos(rp)
        emit "(" + rcode + " = kr_sub(" + rcode + ", kr_str(\"1\")))," + p
    }
    emit compilePostfix(tokens, pos, ntoks)
}

func compilePostfix(tokens, pos, ntoks) {
    let pair = compilePrimary(tokens, pos, ntoks)
    let code = pairVal(pair)
    let p = pairPos(pair)
    while tokAt(tokens, p) == "LBRACK" || tokAt(tokens, p) == "DOT" {
        if tokAt(tokens, p) == "LBRACK" {
            let ip = compileExpr(tokens, p + 1, ntoks)
            let icode = pairVal(ip)
            p = pairPos(ip)
            // expect RBRACK
            p += 1
            code = "kr_idx(" + code + ", kr_atoi(" + icode + "))"
        } else {
            // DOT field access: expr.field -> kr_getfield(expr, "field")
            let field = tokVal(tokAt(tokens, p + 1))
            p = p + 2
            code = "kr_getfield(" + code + ", \"" + field + "\")"
        }
    }
    emit code + "," + p
}

func compilePrimary(tokens, pos, ntoks) {
    let tok = tokAt(tokens, pos)
    let tt = tokType(tok)
    let tv = tokVal(tok)

    // Backtick string interpolation: `Hello {name}!`
    if tt == "INTERP" {
        emit compileInterp(tv) + "," + (pos + 1)
    }

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
        if tv == "null" {
            emit "((char*)0)," + (pos + 1)
        }
    }

    if tok == "LPAREN" {
        let ep = compileExpr(tokens, pos + 1, ntoks)
        let ecode = pairVal(ep)
        let p = pairPos(ep)
        // expect RPAREN
        emit ecode + "," + (p + 1)
    }

    // List literal: [expr, expr, ...] -> comma-separated string
    if tok == "LBRACK" {
        emit compileListLiteral(tokens, pos, ntoks)
    }

    // Lambda: func(params) { body } or fn(params) { body }
    // Only treat as lambda if next token is LPAREN (otherwise it's a variable reference)
    if tok == "KW:func" || tok == "KW:fn" {
        if tokAt(tokens, pos + 1) == "LPAREN" {
            emit compileLambda(tokens, pos, ntoks)
        }
        // Not followed by '(' — treat as variable reference (e.g. let fn = ...; cIdent(fn))
        emit cIdent(tv) + "," + (pos + 1)
    }


    if tt == "ID" {
        let name = tv
        // check for function call
        if tokAt(tokens, pos + 1) == "LPAREN" {
            emit compileCall(tokens, pos, ntoks)
        }
        // check for struct literal: Name { field: val, ... }
        // Only trigger if name starts with uppercase (struct convention)
        if tokAt(tokens, pos + 1) == "LBRACE" {
            let firstChar = name[0]
            if firstChar >= "A" && firstChar <= "Z" {
                emit compileStructLiteral(tokens, pos, ntoks)
            }
        }
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
            p += 1
        }
        let ap = compileExpr(tokens, p, ntoks)
        let acode = pairVal(ap)
        p = pairPos(ap)
        if argc > 0 {
            args = args + ", " + acode
        } else {
            args = acode
        }
        argc += 1
    }
    p += 1

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
    if fname == "exec" {
        emit "kr_exec(" + args + ")," + p
    }
    if fname == "shellRun"   { emit "kr_shellrun(" + args + ")," + p }
    if fname == "deleteFile" { emit "kr_deletefile(" + args + ")," + p }
    if fname == "structNew" {
        // structNew("STRUCTNAME") -> structnew_STRUCTNAME()
        // First arg is a string literal with the struct name
        let snArg = tokAt(tokens, pos + 2)
        if tokType(snArg) == "STR" {
            emit "structnew_" + tokVal(snArg) + "()," + p
        } else {
            emit "structnew_unknown()," + p
        }
    }
    if fname == "structGet" {
        // structGet(ptr, "STRUCTNAME", "fieldname") -> structget_STRUCTNAME(ptr, "fieldname")
        let sgType = tokAt(tokens, pos + 4)
        let sgField = tokAt(tokens, pos + 6)
        if tokType(sgType) == "STR" {
            let sgPtr = split(args, 0)
            emit "structget_" + tokVal(sgType) + "(" + sgPtr + ", kr_str(\"" + tokVal(sgField) + "\"))," + p
        } else {
            emit "kr_str(\"\")," + p
        }
    }
    if fname == "structSet" {
        // structSet(ptr, "STRUCTNAME", "fieldname", val) -> structset_STRUCTNAME(ptr, "fieldname", val)
        let ssType = tokAt(tokens, pos + 4)
        let ssField = tokAt(tokens, pos + 6)
        if tokType(ssType) == "STR" {
            let ssPtr = split(args, 0)
            let ssVal = split(args, 3)
            emit "structset_" + tokVal(ssType) + "(" + ssPtr + ", kr_str(\"" + tokVal(ssField) + "\"), " + ssVal + ")," + p
        } else {
            emit "_K_EMPTY," + p
        }
    }
    if fname == "sizeOf" {
        // sizeOf("STRUCTNAME") -> structsizeof_STRUCTNAME()
        let soArg = tokAt(tokens, pos + 2)
        if tokType(soArg) == "STR" {
            emit "structsizeof_" + tokVal(soArg) + "()," + p
        } else {
            emit "kr_str(\"0\")," + p
        }
    }
    if fname == "structAddr" {
        // structAddr(ptr) -> pass as void* to API functions
        emit "((char*)(" + args + "))," + p
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

    // v0.2.0 builtins
    if fname == "writeFile" {
        emit "kr_writefile(" + args + ")," + p
    }
    // writeBytes(path, hexstr) — write raw binary from hex-encoded string
    // e.g. writeBytes("out.exe", "4D5A9000...") writes those raw bytes
    if fname == "writeBytes" {
        emit "kr_writebytes(" + args + ")," + p
    }
    if fname == "input" {
        emit "kr_input()," + p
    }
    if fname == "indexOf" {
        emit "kr_indexof(" + args + ")," + p
    }
    if fname == "replace" {
        emit "kr_replace(" + args + ")," + p
    }
    if fname == "charAt" {
        emit "kr_charat(" + args + ")," + p
    }
    if fname == "trim" {
        emit "kr_trim(" + args + ")," + p
    }
    if fname == "toLower" {
        emit "kr_tolower(" + args + ")," + p
    }
    if fname == "toUpper" {
        emit "kr_toupper(" + args + ")," + p
    }
    if fname == "contains" {
        emit "kr_contains(" + args + ")," + p
    }
    if fname == "endsWith" {
        emit "kr_endswith(" + args + ")," + p
    }
    if fname == "abs" {
        emit "kr_abs(" + args + ")," + p
    }
    if fname == "min" {
        emit "kr_min(" + args + ")," + p
    }
    if fname == "max" {
        emit "kr_max(" + args + ")," + p
    }
    if fname == "exit" {
        emit "kr_exit(" + args + ")," + p
    }
    if fname == "type" {
        emit "kr_type(" + args + ")," + p
    }

    // v0.3.0 builtins
    if fname == "append" {
        emit "kr_append(" + args + ")," + p
    }
    if fname == "join" {
        emit "kr_join(" + args + ")," + p
    }
    if fname == "reverse" {
        emit "kr_reverse(" + args + ")," + p
    }
    if fname == "sort" {
        emit "kr_sort(" + args + ")," + p
    }
    if fname == "keys" {
        emit "kr_keys(" + args + ")," + p
    }
    if fname == "values" {
        emit "kr_values(" + args + ")," + p
    }
    if fname == "hasKey" {
        emit "kr_haskey(" + args + ")," + p
    }
    if fname == "remove" {
        emit "kr_remove(" + args + ")," + p
    }
    if fname == "repeat" {
        emit "kr_repeat(" + args + ")," + p
    }
    if fname == "format" {
        emit "kr_format(" + args + ")," + p
    }
    if fname == "parseInt" {
        emit "kr_parseint(" + args + ")," + p
    }
    if fname == "toStr" {
        emit "kr_tostr(" + args + ")," + p
    }

    // v0.4.0 builtins
    if fname == "range" {
        emit "kr_range(" + args + ")," + p
    }
    if fname == "pow" {
        emit "kr_pow(" + args + ")," + p
    }
    if fname == "sqrt" {
        emit "kr_sqrt(" + args + ")," + p
    }
    if fname == "sign" {
        emit "kr_sign(" + args + ")," + p
    }
    if fname == "clamp" {
        emit "kr_clamp(" + args + ")," + p
    }
    if fname == "padLeft" {
        emit "kr_padleft(" + args + ")," + p
    }
    if fname == "padRight" {
        emit "kr_padright(" + args + ")," + p
    }
    if fname == "charCode" {
        emit "kr_charcode(" + args + ")," + p
    }
    if fname == "fromCharCode" {
        emit "kr_fromcharcode(" + args + ")," + p
    }
    if fname == "slice" {
        emit "kr_slice(" + args + ")," + p
    }
    if fname == "length" {
        emit "kr_length(" + args + ")," + p
    }
    if fname == "unique" {
        emit "kr_unique(" + args + ")," + p
    }
    if fname == "printErr" {
        emit "kr_printerr(" + args + ")," + p
    }
    if fname == "readLine" {
        emit "kr_readline(" + args + ")," + p
    }
    if fname == "assert" {
        emit "kr_assert(" + args + ", \"assertion failed\")," + p
    }

    // v0.5.0 builtins
    if fname == "splitBy" {
        emit "kr_splitby(" + args + ")," + p
    }
    if fname == "listIndexOf" {
        emit "kr_listindexof(" + args + ")," + p
    }
    if fname == "insertAt" {
        emit "kr_insertat(" + args + ")," + p
    }
    if fname == "removeAt" {
        emit "kr_removeat(" + args + ")," + p
    }
    if fname == "replaceAt" {
        emit "kr_replaceat(" + args + ")," + p
    }
    if fname == "fill" {
        emit "kr_fill(" + args + ")," + p
    }
    if fname == "zip" {
        emit "kr_zip(" + args + ")," + p
    }
    if fname == "every" {
        emit "kr_every(" + args + ")," + p
    }
    if fname == "some" {
        emit "kr_some(" + args + ")," + p
    }
    if fname == "countOf" {
        emit "kr_countof(" + args + ")," + p
    }
    if fname == "sumList" {
        emit "kr_sumlist(" + args + ")," + p
    }
    if fname == "maxList" {
        emit "kr_maxlist(" + args + ")," + p
    }
    if fname == "minList" {
        emit "kr_minlist(" + args + ")," + p
    }
    if fname == "hex" {
        emit "kr_hex(" + args + ")," + p
    }
    if fname == "bin" {
        emit "kr_bin(" + args + ")," + p
    }

    // v0.7.0 builtins
    if fname == "strReverse" {
        emit "kr_strreverse(" + args + ")," + p
    }
    if fname == "words" {
        emit "kr_words(" + args + ")," + p
    }
    if fname == "lines" {
        emit "kr_lines(" + args + ")," + p
    }
    if fname == "first" {
        emit "kr_first(" + args + ")," + p
    }
    if fname == "last" {
        emit "kr_last(" + args + ")," + p
    }
    if fname == "head" {
        emit "kr_head(" + args + ")," + p
    }
    if fname == "tail" {
        emit "kr_tail(" + args + ")," + p
    }
    if fname == "lstrip" {
        emit "kr_lstrip(" + args + ")," + p
    }
    if fname == "rstrip" {
        emit "kr_rstrip(" + args + ")," + p
    }
    if fname == "center" {
        emit "kr_center(" + args + ")," + p
    }
    if fname == "isAlpha" {
        emit "kr_isalpha(" + args + ")," + p
    }
    if fname == "isDigit" {
        emit "kr_isdigit(" + args + ")," + p
    }
    if fname == "isSpace" {
        emit "kr_isspace(" + args + ")," + p
    }
    if fname == "random" {
        emit "kr_random(" + args + ")," + p
    }
    if fname == "timestamp" {
        emit "kr_timestamp()," + p
    }
    if fname == "environ" {
        emit "kr_environ(" + args + ")," + p
    }
    if fname == "floor" {
        emit "kr_floor(" + args + ")," + p
    }
    if fname == "ceil" {
        emit "kr_ceil(" + args + ")," + p
    }
    if fname == "round" {
        emit "kr_round(" + args + ")," + p
    }
    if fname == "throw" {
        emit "kr_throw(" + args + ")," + p
    }

    // v0.8.6 float builtins
    if fname == "fadd" { emit "kr_fadd(" + args + ")," + p }
    if fname == "fsub" { emit "kr_fsub(" + args + ")," + p }
    if fname == "fmul" { emit "kr_fmul(" + args + ")," + p }
    if fname == "fdiv" { emit "kr_fdiv(" + args + ")," + p }
    if fname == "flt"  { emit "kr_flt(" + args + ")," + p }
    if fname == "fgt"  { emit "kr_fgt(" + args + ")," + p }
    if fname == "feq"  { emit "kr_feq(" + args + ")," + p }
    if fname == "fsqrt"  { emit "kr_fsqrt(" + args + ")," + p }
    if fname == "ffloor" { emit "kr_ffloor(" + args + ")," + p }
    if fname == "fceil"  { emit "kr_fceil(" + args + ")," + p }
    if fname == "fround" { emit "kr_fround(" + args + ")," + p }
    if fname == "fformat"{ emit "kr_fformat(" + args + ")," + p }
    if fname == "toFloat"{ emit args + "," + p }

    // bitwise builtins
    if fname == "bitAnd"  { emit "kr_bitand(" + args + ")," + p }
    if fname == "bitOr"   { emit "kr_bitor(" + args + ")," + p }
    if fname == "bitXor"  { emit "kr_bitxor(" + args + ")," + p }
    if fname == "bitNot"  { emit "kr_bitnot(" + args + ")," + p }
    if fname == "bitShl"  { emit "kr_bitshl(" + args + ")," + p }
    if fname == "bitShr"  { emit "kr_bitshr(" + args + ")," + p }

    // 64-bit integer builtins
    if fname == "toLong"  { emit "kr_tolong(" + args + ")," + p }
    if fname == "div64"   { emit "kr_div64(" + args + ")," + p }
    if fname == "mod64"   { emit "kr_mod64(" + args + ")," + p }
    if fname == "mul64"   { emit "kr_mul64(" + args + ")," + p }
    if fname == "add64"   { emit "kr_add64(" + args + ")," + p }
    if fname == "eqIgnoreCase" { emit "kr_eqignorecase(" + args + ")," + p }
    if fname == "handleValid"  { emit "kr_handlevalid(" + args + ")," + p }

    // v1.1.3 buffer / handle builtins for native Windows API calls
    if fname == "bufNew"      { emit "_alloc(atoi(" + args + "))," + p }
    if fname == "bufStr"      { emit "kr_str(" + args + ")," + p }
    if fname == "bufGetDword" { emit "kr_bufgetdword(" + args + ")," + p }
    if fname == "bufSetDword" { emit "kr_bufsetdword(" + args + ")," + p }
    if fname == "bufGetWord"  { emit "kr_bufgetword(" + args + ")," + p }
    if fname == "bufGetQword"   { emit "kr_bufgetqword(" + args + ")," + p }
    if fname == "bufGetDwordAt"  { emit "kr_bufgetdwordat(" + args + ")," + p }
    if fname == "bufGetQwordAt"  { emit "kr_bufgetqwordat(" + args + ")," + p }
    if fname == "bufSetByte"     { emit "kr_bufsetbyte(" + args + ")," + p }
    if fname == "bufSetDwordAt"  { emit "kr_bufsetdwordat(" + args + ")," + p }
    if fname == "handleOut"      { emit "((char*)_alloc(sizeof(void*)))," + p }
    if fname == "handleGet"      { emit "kr_handleget(" + args + ")," + p }
    if fname == "handleInt"      { emit "kr_handleint(" + args + ")," + p }
    if fname == "toHandle"       { emit "((char*)(intptr_t)atoll(" + args + "))," + p }
    if fname == "ptrDeref"       { emit "kr_ptrderef(" + args + ")," + p }
    if fname == "ptrIndex"       { emit "kr_ptrindex(" + args + ")," + p }
    if fname == "callPtr" {
        if argc == 2 { emit "kr_callptr1(" + args + ")," + p }
        if argc == 3 { emit "kr_callptr2(" + args + ")," + p }
        if argc == 4 { emit "kr_callptr3(" + args + ")," + p }
        if argc == 5 { emit "kr_callptr4(" + args + ")," + p }
    }

    // v0.7.5 builtins
    if fname == "mapGet" {
        emit "kr_mapget(" + args + ")," + p
    }
    if fname == "mapSet" {
        emit "kr_mapset(" + args + ")," + p
    }
    if fname == "mapDel" {
        emit "kr_mapdel(" + args + ")," + p
    }
    if fname == "sprintf" {
        emit "kr_sprintf(" + args + ")," + p
    }
    if fname == "listMap" {
        emit "kr_listmap(" + args + ")," + p
    }
    if fname == "listFilter" {
        emit "kr_listfilter(" + args + ")," + p
    }
    if fname == "strSplit" {
        emit "kr_strsplit(" + args + ")," + p
    }

    // v0.7.1 struct builtins
    if fname == "structNew" {
        emit "kr_structnew()," + p
    }
    if fname == "getField" {
        emit "kr_getfield(" + args + ")," + p
    }
    if fname == "setField" {
        emit "kr_setfield(" + args + ")," + p
    }
    if fname == "hasField" {
        emit "kr_hasfield(" + args + ")," + p
    }
    if fname == "structFields" {
        emit "kr_structfields(" + args + ")," + p
    }

    // funcptr(name) — returns a Krypton callback function as a char* pointer
    // so it can be passed to C APIs expecting a function pointer
    if fname == "funcptr" {
        emit "((char*)" + cIdent(args) + ")," + p
    }

    // User-defined function call
    // Try indirect call for lambda variables (function pointers)
    // Build arg list with types for cast
    let castArgs = "char*"
    let ci = 1
    while ci < argc { castArgs = castArgs + ",char*"  ci += 1 }
    if argc == 0 { castArgs = "void" }
    emit "((char*(*)("+castArgs+"))"+cIdent(fname)+")("+args+")," + p
}

// =============================================
// Statement Compiler
// Each returns pair: "cCode,pos"
// =============================================


func compileStmt(tokens, pos, ntoks, depth, inFunc) {
    let tok = tokAt(tokens, pos)
    // 'tok' must be declared before any use below for valid C codegen
    if tok == "KW:struct" || tok == "KW:class" || tok == "KW:type" {
        emit compileStructDecl(tokens, pos + 1, ntoks, depth)
    }
    if tok == "KW:try" {
        // try { ... } catch { ... } using setjmp/longjmp
        let bp = compileBlock(tokens, pos + 1, ntoks, depth, inFunc)
        let bcode = pairVal(bp)
        let p = pairPos(bp)
        if tokAt(tokens, p) == "KW:catch" {
            p += 1
            // check for optional catch variable: catch e { }
            let catchVar = "__err"
            if tokType(tokAt(tokens, p)) == "ID" {
                catchVar = tokVal(tokAt(tokens, p))
                p += 1
            }
            let cbp = compileBlock(tokens, p, ntoks, depth, inFunc)
            let cbcode = pairVal(cbp)
            p = pairPos(cbp)
            let ind = indent(depth)
            let ind1 = indent(depth + 1)
            let out = ind + "{\n"
            out = out + ind1 + "if (setjmp(*_kr_pushtry()) == 0) {\n"
            out = out + bcode
            out = out + ind1 + "_kr_poptry();\n"
            out = out + ind1 + "} else {\n"
            out = out + ind1 + "    char* " + catchVar + " = _kr_poptry();\n"
            out = out + cbcode
            out = out + ind1 + "}\n"
            out = out + ind + "}\n"
            emit out + "," + p
        } else {
            let ind = indent(depth)
            let ind1 = indent(depth + 1)
            let out = ind + "{\n"
            out = out + ind1 + "if (setjmp(*_kr_pushtry()) == 0) {\n"
            out = out + bcode
            out = out + ind1 + "_kr_poptry();\n"
            out = out + ind1 + "}\n"
            out = out + ind + "}\n"
            emit out + "," + p
        }
    }
    if tok == "KW:throw" {
        let ep = compileExpr(tokens, pos + 1, ntoks)
        let ecode = pairVal(ep)
        let p = pairPos(ep)
        if tokAt(tokens, p) == "SEMI" {
            p += 1
        }
        emit indent(depth) + "_kr_throw(" + ecode + ");\n," + p
    }

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

    if tok == "KW:for" {
        emit compileFor(tokens, pos + 1, ntoks, depth, inFunc)
    }

    if tok == "KW:break" {
        let p = pos + 1
        if tokAt(tokens, p) == "SEMI" {
            p += 1
        }
        emit indent(depth) + "break;\n," + p
    }

    if tok == "KW:continue" {
        let p = pos + 1
        if tokAt(tokens, p) == "SEMI" {
            p += 1
        }
        emit indent(depth) + "continue;\n," + p
    }

    if tok == "KW:match" {
        emit compileMatch(tokens, pos + 1, ntoks, depth, inFunc)
    }

    if tok == "KW:do" {
        emit compileDoWhile(tokens, pos + 1, ntoks, depth, inFunc)
    }

    if tok == "KW:loop" {
        emit compileLoop(tokens, pos + 1, ntoks, depth, inFunc)
    }

    if tok == "KW:const" {
        emit compileLet(tokens, pos + 1, ntoks, depth)
    }

    // --- Module/import/export: emit comment stubs ---
    if tok == "KW:module" {
        // module name -- emit comment, advance past name
        let mname = tokVal(tokAt(tokens, pos + 1))
        let p = pos + 2
        emit "// module: " + mname + "\n," + p
    }
    if tok == "KW:import" {
        // import "file.k" - load and inline compile the file
        let importPath = tokVal(tokAt(tokens, pos + 1))
        let p = pos + 2
        // importPath comes as a STR token value (no quotes)
        let importSrc = readFile(importPath)
        if len(importSrc) > 0 {
            // emit a comment marker and the file contents will be compiled
            // by the main compilation loop when we return the import token
            emit indent(depth) + "// imported: " + importPath + "\n," + p
        } else {
            emit indent(depth) + "// import not found: " + importPath + "\n," + p
        }
    }
    if tok == "KW:export" {
        // export func name(...) or export struct Name
        // Just skip the export keyword and compile what follows
        let nextTok = tokAt(tokens, pos + 1)
        if nextTok == "KW:func" || nextTok == "KW:fn" {
            // compile the func declaration
            let fp = compileFunc(tokens, pos + 1, ntoks)
            emit pairVal(fp) + "," + pairPos(fp)
        }
        if nextTok == "KW:struct" || nextTok == "KW:class" || nextTok == "KW:type" {
            emit compileStructDecl(tokens, pos + 2, ntoks, depth)
        }
        // bare export name -- just skip
        let p = pos + 2
        emit indent(depth) + "// export\n," + p
    }

    // cfunc { } inline C block — emit verbatim inside function body
    if tokType(tok) == "CBLOCK" {
        let craw = replace(tokVal(tok), "\x01", "\n")
        emit indent(depth) + craw + "\n," + (pos + 1)
    }

    // Check for post-increment/decrement: i++  i--
    if tokType(tok) == "ID" {
        let nextTok = tokAt(tokens, pos + 1)
        if nextTok == "PLUSPLUS" {
            let vname = cIdent(tokVal(tok))
            let p = pos + 2
            if tokAt(tokens, p) == "SEMI" { p += 1 }
            emit indent(depth) + vname + " = kr_plus(" + vname + ", kr_str(\"1\"));\n," + p
        }
        if nextTok == "MINUSMINUS" {
            let vname = cIdent(tokVal(tok))
            let p = pos + 2
            if tokAt(tokens, p) == "SEMI" { p += 1 }
            emit indent(depth) + vname + " = kr_sub(" + vname + ", kr_str(\"1\"));\n," + p
        }
    }
    // Check for pre-increment/decrement: ++i  --i
    if tok == "PLUSPLUS" {
        let vname = cIdent(tokVal(tokAt(tokens, pos + 1)))
        let p = pos + 2
        if tokAt(tokens, p) == "SEMI" { p += 1 }
        emit indent(depth) + vname + " = kr_plus(" + vname + ", kr_str(\"1\"));\n," + p
    }
    if tok == "MINUSMINUS" {
        let vname = cIdent(tokVal(tokAt(tokens, pos + 1)))
        let p = pos + 2
        if tokAt(tokens, p) == "SEMI" { p += 1 }
        emit indent(depth) + vname + " = kr_sub(" + vname + ", kr_str(\"1\"));\n," + p
    }

    // Check for compound assignment: ID PLUSEQ/MINUSEQ/STAREQ/SLASHEQ/MODEQ
    if tokType(tok) == "ID" {
        let nextTok = tokAt(tokens, pos + 1)
        if nextTok == "PLUSEQ" || nextTok == "MINUSEQ" || nextTok == "STAREQ" || nextTok == "SLASHEQ" || nextTok == "MODEQ" {
            emit compileCompoundAssign(tokens, pos, ntoks, depth)
        }
    }

    // Check for field assignment: ID DOT ID ASSIGN
    if tokType(tok) == "ID" {
        if tokAt(tokens, pos + 1) == "DOT" {
            if tokType(tokAt(tokens, pos + 2)) == "ID" {
                if tokAt(tokens, pos + 3) == "ASSIGN" {
                    emit compileFieldAssign(tokens, pos, ntoks, depth)
                }
            }
        }
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
    let p = pos + 1
    // optional type annotation: let name: type = expr
    if tokAt(tokens, p) == "COLON" {
        // skip COLON and type name (may be ID or KW like int/string)
        p = p + 2
        // handle compound types: list[int], map[string, int]
        if tokAt(tokens, p) == "LBRACK" {
            let depth2 = 1
            p += 1
            while depth2 > 0 {
                if tokAt(tokens, p) == "LBRACK" { depth2 += 1 }
                if tokAt(tokens, p) == "RBRACK" { depth2 -= 1 }
                p += 1
            }
        }
    }
    // skip ASSIGN
    p += 1
    let ep = compileExpr(tokens, p, ntoks)
    let ecode = pairVal(ep)
    p = pairPos(ep)
    if tokAt(tokens, p) == "SEMI" {
        p += 1
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
        p += 1
    }
    emit indent(depth) + cIdent(name) + " = " + ecode + ";\n," + p
}

func compileEmit(tokens, pos, ntoks, depth, inFunc) {
    let ep = compileExpr(tokens, pos, ntoks)
    let ecode = pairVal(ep)
    let p = pairPos(ep)
    if tokAt(tokens, p) == "SEMI" {
        p += 1
    }
    if inFunc == "0" {
        // In main entry block: emit value as process exit code
        emit indent(depth) + "return atoi(" + ecode + ");\n," + p
    }
    if inFunc == "int" {
        // In an int-returning function: wrap with atoi so char* expr becomes int
        emit indent(depth) + "return atoi(" + ecode + ");\n," + p
    }
    if inFunc == "zero" {
        // In a void function: evaluate for side effects, no return value
        emit indent(depth) + ecode + ";\n," + p
    }
    // In a function or lambda: return the expression value as char*
    emit indent(depth) + "return " + ecode + ";\n," + p
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
        p += 1
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

// compileListLiteral: [expr, expr, ...] -> kr_cat chain producing "a,b,c"

func compileLambda(tokens, pos, ntoks) {
    // Lambda was pre-compiled in the pre-scan pass.
    // Collect params, then return function pointer + set captures.
    let lname = "_krlam" + pos
    let p = pos + 2
    // collect params for free var analysis
    let lparams = ""
    let lpc = 0
    while tokAt(tokens, p) != "RPAREN" {
        if tokType(tokAt(tokens, p)) == "ID" {
            if lpc > 0 { lparams = lparams + "," }
            lparams = lparams + tokVal(tokAt(tokens, p))
            lpc += 1
        }
        p += 1
    }
    p += 1  // past RPAREN
    if tokAt(tokens, p) == "ARROW" { p += 2 }
    // skip past body block
    let bp = skipBlock(tokens, p)
    // Detect free variables and set static captures at creation site
    let lfv2 = findFreeVars(tokens, p - 1, bp, lparams)
    let lfvc2 = 0
    if len(lfv2) > 0 { lfvc2 = lineCount(lfv2) }
    let captureCode = ""
    let lfvi3 = 0
    while lfvi3 < lfvc2 {
        let fvn3 = cIdent(split(lfv2, lfvi3))
        captureCode = captureCode + "_krlam" + pos + "_" + cIdent(fvn3) + " = " + cIdent(fvn3) + "; "
        lfvi3 += 1
    }
    // Use C comma operator to chain capture assignments with pointer return
    if len(captureCode) > 0 {
        // Remove trailing "; " and wrap in comma expression
        let cc = trim(captureCode)
        // Replace "; " between assignments with ", " for comma operator
        let ccExpr = trim(replace(cc, ";", ""))
        emit "(" + ccExpr + ", (char*)&" + lname + ")," + bp
    } else {
        emit "(char*)&" + lname + "," + bp
    }

}


func compileListLiteral(tokens, pos, ntoks) {
    // pos is at LBRACK
    let p = pos + 1
    if tokAt(tokens, p) == "RBRACK" {
        // empty list
        emit "kr_str(\"\")" + "," + (p + 1)
    }
    // collect elements
    let elems = ""
    let ec = 0
    while tokAt(tokens, p) != "RBRACK" {
        if ec > 0 {
            // skip COMMA
            p = p + 1
        }
        let ep = compileExpr(tokens, p, ntoks)
        let ecode = pairVal(ep)
        p = pairPos(ep)
        if ec > 0 {
            elems = elems + "\n" + ecode
        } else {
            elems = ecode
        }
        ec += 1
    }
    // skip RBRACK
    p = p + 1
    if ec == 1 {
        emit elems + "," + p
    }
    // build kr_cat chain with commas between elements
    let result = getLine(elems, 0)
    let ei = 1
    while ei < ec {
        let elem = getLine(elems, ei)
        result = "kr_cat(kr_cat(" + result + ", kr_str(\",\")), " + elem + ")"
        ei += 1
    }
    emit result + "," + p
}

// compileInterp: compile a backtick interpolation string
// Input: raw string like "Hello {name}, you are {age} years old"
// Output: C expression like kr_cat(kr_cat(kr_str("Hello "), name), ...)
func compileInterp(s) {
    let parts = ""
    let pc = 0
    let i = 0
    let seg = ""
    while i < len(s) {
        if s[i] == "{" {
            // flush literal segment
            if len(seg) > 0 {
                let escaped = cEscape(seg)
                if pc > 0 {
                    parts = parts + "\n" + "L:" + escaped
                } else {
                    parts = "L:" + escaped
                }
                pc += 1
                seg = ""
            }
            // read expression until }
            i += 1
            let expr = ""
            while i < len(s) && s[i] != "}" {
                expr = expr + s[i]
                i += 1
            }
            i += 1
            if pc > 0 {
                parts = parts + "\n" + "E:" + expr
            } else {
                parts = "E:" + expr
            }
            pc += 1
        } else {
            seg = seg + s[i]
            i += 1
        }
    }
    // flush final segment
    if len(seg) > 0 {
        let escaped = cEscape(seg)
        if pc > 0 {
            parts = parts + "\n" + "L:" + escaped
        } else {
            parts = "L:" + escaped
        }
        pc += 1
    }
    if pc == 0 {
        emit "kr_str(\"\")"
    }
    // build kr_cat chain from parts
    let result = ""
    let j = 0
    while j < pc {
        let part = getLine(parts, j)
        let ptype = substring(part, 0, 2)
        let pval = substring(part, 2, len(part))
        let cpart = ""
        if ptype == "L:" {
            cpart = "kr_str(\"" + pval + "\")"
        } else {
            // Tokenize and compile the expression inside {}
            let exprToks = tokenize(pval)
            let exprNtoks = lineCount(exprToks)
            if exprNtoks > 0 {
                let ep = compileExpr(exprToks, 0, exprNtoks)
                cpart = pairVal(ep)
            } else {
                cpart = "kr_str(\"\")"
            }
        }
        if j == 0 {
            result = cpart
        } else {
            result = "kr_cat(" + result + ", " + cpart + ")"
        }
        j += 1
    }
    emit result
}

// === Struct compiler helpers ===

// compileStructDecl: struct Name { let field1 let field2 ... }
// Emits: typedef struct { char* field1; char* field2; } Name_t;
//        + constructor: char* Name(char* field1, char* field2) { ... }
func compileStructDecl(tokens, pos, ntoks, depth) {
    let name = tokVal(tokAt(tokens, pos))
    let p = pos + 1
    // skip LBRACE
    p += 1
    // collect field names from let declarations
    let fields = ""
    let fc = 0
    while tokAt(tokens, p) != "RBRACE" {
        if tokAt(tokens, p) == "KW:let" {
            let fname = tokVal(tokAt(tokens, p + 1))
            if fc > 0 {
                fields = fields + "," + fname
            } else {
                fields = fname
            }
            fc += 1
            // skip let name
            p = p + 2
            // skip optional type annotation: let name: type
            if tokAt(tokens, p) == "COLON" {
                p = p + 2
                if tokAt(tokens, p) == "LBRACK" {
                    let sfd = 1
                    p += 1
                    while sfd > 0 {
                        if tokAt(tokens, p) == "LBRACK" { sfd += 1 }
                        if tokAt(tokens, p) == "RBRACK" { sfd -= 1 }
                        p += 1
                    }
                }
            }
            // skip optional = value
            if tokAt(tokens, p) == "ASSIGN" {
                // skip default value expression
                let ep = compileExpr(tokens, p + 1, ntoks)
                p = pairPos(ep)
            }
        } else {
            p += 1
        }
    }
    p += 1
    let cname = cIdent(name)
    let out = "typedef struct " + cname + "_s {\n"
    let i = 0
    while i < fc {
        let fld = getNthParam(fields, i)
        out = out + "    char* " + cIdent(fld) + ";\n"
        i += 1
    }
    out = out + "} " + cname + "_t;\n\n"
    // emit constructor function: Name() returns a new empty struct
    out = out + "static char* " + cname + "() {\n"
    out = out + "    " + cname + "_t* _s = (" + cname + "_t*)_alloc(sizeof(" + cname + "_t));\n"
    let i2 = 0
    while i2 < fc {
        let fld2 = getNthParam(fields, i2)
        out = out + "    _s->" + cIdent(fld2) + " = _K_EMPTY;\n"
        i2 += 1
    }
    out = out + "    return (char*)_s;\n"
    out = out + "}\n\n"
    emit out + "," + p
}

// compileFieldAssign: obj.field = expr
// Emits: kr_setfield(obj, "field", expr);
func compileFieldAssign(tokens, pos, ntoks, depth) {
    let objName = tokVal(tokAt(tokens, pos))
    let field = tokVal(tokAt(tokens, pos + 2))
    let p = pos + 4
    let ep = compileExpr(tokens, p, ntoks)
    let ecode = pairVal(ep)
    p = pairPos(ep)
    if tokAt(tokens, p) == "SEMI" {
        p += 1
    }
    emit indent(depth) + "kr_setfield(" + cIdent(objName) + ", \"" + field + "\", " + ecode + ");\n," + p
}

// compileStructLiteral: Name { field: expr, field2: expr2 }
// Emits: a stack block that creates and populates the struct
func compileStructLiteral(tokens, pos, ntoks) {
    let name = tokVal(tokAt(tokens, pos))
    let cname = cIdent(name)
    let p = pos + 2
    // parse field: value pairs
    let fields = ""
    let vals = ""
    let fc = 0
    while tokAt(tokens, p) != "RBRACE" {
        if tokType(tokAt(tokens, p)) == "ID" {
            let fname = tokVal(tokAt(tokens, p))
            // skip field name and COLON
            p = p + 2
            let ep = compileExpr(tokens, p, ntoks)
            let ecode = pairVal(ep)
            p = pairPos(ep)
            if tokAt(tokens, p) == "COMMA" {
                p += 1
            }
            if fc > 0 {
                fields = fields + "," + fname
                vals = vals + ecode + "\n"
            } else {
                fields = fname
                vals = ecode + "\n"
            }
            fc += 1
        } else {
            p += 1
        }
    }
    // skip RBRACE
    p += 1
    // Emit a GNU statement-expression block: ({ Type* _s = ...; set fields; _s; })
    // This works as an expression in both GCC and clang (C99 extension)
    let out = "({ char* _sl = kr_structnew();"
    let i3 = 0
    while i3 < fc {
        let fn3 = getNthParam(fields, i3)
        let fv3 = getLine(vals, i3)
        out = out + " kr_setfield(_sl, \"" + fn3 + "\", " + fv3 + ");"
        i3 += 1
    }
    out = out + " _sl; })"
    emit out + "," + p
}

func compileCompoundAssign(tokens, pos, ntoks, depth) {
    let name = tokVal(tokAt(tokens, pos))
    let op = tokAt(tokens, pos + 1)
    let p = pos + 2
    let ep = compileExpr(tokens, p, ntoks)
    let ecode = pairVal(ep)
    p = pairPos(ep)
    if tokAt(tokens, p) == "SEMI" {
        p += 1
    }
    let cname = cIdent(name)
    if op == "PLUSEQ" {
        emit indent(depth) + cname + " = kr_plus(" + cname + ", " + ecode + ");\n," + p
    }
    if op == "MINUSEQ" {
        emit indent(depth) + cname + " = kr_sub(" + cname + ", " + ecode + ");\n," + p
    }
    if op == "STAREQ" {
        emit indent(depth) + cname + " = kr_mul(" + cname + ", " + ecode + ");\n," + p
    }
    if op == "SLASHEQ" {
        emit indent(depth) + cname + " = kr_div(" + cname + ", " + ecode + ");\n," + p
    }
    if op == "MODEQ" {
        emit indent(depth) + cname + " = kr_mod(" + cname + ", " + ecode + ");\n," + p
    }
    emit indent(depth) + cname + " = " + ecode + ";\n," + p
}

func compileFor(tokens, pos, ntoks, depth, inFunc) {
    // for <var> in <expr> { ... }
    let varName = tokVal(tokAt(tokens, pos))
    // skip var, KW:in
    let p = pos + 2
    let ep = compileExpr(tokens, p, ntoks)
    let collection = pairVal(ep)
    p = pairPos(ep)

    let bp = compileBlock(tokens, p, ntoks, depth, inFunc)
    let bcode = pairVal(bp)
    p = pairPos(bp)

    let cvar = cIdent(varName)
    // Use depth-unique names to allow nested for-in loops
    let dstr = depth + ""
    let colVar = "_for_col_" + dstr
    let cntVar = "_for_cnt_" + dstr
    let idxVar = "_for_i_" + dstr
    let out = indent(depth) + "{\n"
    out = out + indent(depth + 1) + "char* " + colVar + " = " + collection + ";\n"
    out = out + indent(depth + 1) + "int " + cntVar + " = kr_listlen(" + colVar + ");\n"
    out = out + indent(depth + 1) + "for (int " + idxVar + " = 0; " + idxVar + " < " + cntVar + "; " + idxVar + "++) {\n"
    out = out + indent(depth + 2) + "char* " + cvar + " = kr_split(" + colVar + ", kr_itoa(" + idxVar + "));\n"
    out = out + bcode
    out = out + indent(depth + 1) + "}\n"
    out = out + indent(depth) + "}\n"
    emit out + "," + p
}

func compileMatch(tokens, pos, ntoks, depth, inFunc) {
    // match <expr> { <STR|INT|KW:true|KW:false> { body } ... KW:else { body } }
    let ep = compileExpr(tokens, pos, ntoks)
    let mexpr = pairVal(ep)
    let p = pairPos(ep)
    // skip LBRACE
    p += 1

    let out = indent(depth) + "{\n"
    out = out + indent(depth + 1) + "char* _match_val = " + mexpr + ";\n"
    let first = "1"
    while tokAt(tokens, p) != "RBRACE" {
        let ct = tokAt(tokens, p)
        if ct == "KW:else" {
            p += 1
            let bp = compileBlock(tokens, p, ntoks, depth + 1, inFunc)
            let bcode = pairVal(bp)
            p = pairPos(bp)
            if first == "1" {
                out = out + indent(depth + 1) + "{\n" + bcode + indent(depth + 1) + "}\n"
            } else {
                out = out + " else {\n" + bcode + indent(depth + 1) + "}\n"
            }
        } else {
            // compile the match value as an expression
            let vp = compileExpr(tokens, p, ntoks)
            let vcode = pairVal(vp)
            p = pairPos(vp)
            let bp = compileBlock(tokens, p, ntoks, depth + 1, inFunc)
            let bcode = pairVal(bp)
            p = pairPos(bp)
            if first == "1" {
                out = out + indent(depth + 1) + "if (strcmp(_match_val, " + vcode + ") == 0) {\n" + bcode + indent(depth + 1) + "}"
                first = "0"
            } else {
                out = out + " else if (strcmp(_match_val, " + vcode + ") == 0) {\n" + bcode + indent(depth + 1) + "}"
            }
        }
    }
    // skip RBRACE
    p += 1
    out = out + "\n" + indent(depth) + "}\n"
    emit out + "," + p
}

func compileDoWhile(tokens, pos, ntoks, depth, inFunc) {
    // do { body } while <expr>
    let bp = compileBlock(tokens, pos, ntoks, depth, inFunc)
    let bcode = pairVal(bp)
    let p = pairPos(bp)
    // skip KW:while
    p += 1
    let cp = compileExpr(tokens, p, ntoks)
    let cond = pairVal(cp)
    p = pairPos(cp)
    if tokAt(tokens, p) == "SEMI" {
        p += 1
    }
    let out = indent(depth) + "do {\n" + bcode + indent(depth) + "} while (kr_truthy(" + cond + "));\n"
    emit out + "," + p
}

func compileLoop(tokens, pos, ntoks, depth, inFunc) {
    // loop { body } until <expr>
    // Compiles to: do { body } while (!kr_truthy(expr))
    let bp = compileBlock(tokens, pos, ntoks, depth, inFunc)
    let bcode = pairVal(bp)
    let p = pairPos(bp)
    // skip KW:until
    p += 1
    let cp = compileExpr(tokens, p, ntoks)
    let cond = pairVal(cp)
    p = pairPos(cp)
    if tokAt(tokens, p) == "SEMI" {
        p += 1
    }
    let out = indent(depth) + "do {\n" + bcode + indent(depth) + "} while (!kr_truthy(" + cond + "));\n"
    emit out + "," + p
}

func compileExprStmt(tokens, pos, ntoks, depth) {
    let ep = compileExpr(tokens, pos, ntoks)
    let ecode = pairVal(ep)
    let p = pairPos(ep)
    if tokAt(tokens, p) == "SEMI" {
        p += 1
    }
    emit indent(depth) + ecode + ";\n," + p
}

// === Block compiler ===

func compileBlock(tokens, pos, ntoks, depth, inFunc) {
    // pos should be at LBRACE
    let p = pos + 1
    let code = sbNew()
    while tokAt(tokens, p) != "RBRACE" {
        // skip stray semicolons
        if tokAt(tokens, p) == "SEMI" {
            p += 1
        } else {
            let sp = compileStmt(tokens, p, ntoks, depth + 1, inFunc)
            let sCode = pairVal(sp)
            p = pairPos(sp)
            code = sbAppend(code, sCode)
        }
    }
    // skip RBRACE
    p += 1
    emit sbToString(code) + "," + p
}

// === Function compiler ===

func hoistLambdas(code) {
    // Extract /*LS*/body/*LE*/ markers from code, return "hoisted\ncleanCode"
    let hoisted = sbNew()
    let clean = sbNew()
    let i = 0
    let clen = len(code)
    while i < clen {
        if i + 6 <= clen && substring(code, i, i + 6) == "/*LS*/" {
            let le = indexOf(substring(code, i + 6, clen), "/*LE*/")
            if toInt(le) >= 0 {
                let bodyStart = i + 6
                let bodyEnd = bodyStart + toInt(le)
                let leEnd = bodyEnd + 6
                hoisted = sbAppend(hoisted, substring(code, bodyStart, bodyEnd) + "\n")
                i = leEnd
            } else {
                clean = sbAppend(clean, code[i])
                i += 1
            }
        } else {
            clean = sbAppend(clean, code[i])
            i += 1
        }
    }
    emit sbToString(hoisted) + "/*SPLIT*/" + sbToString(clean)
}


func compileFunc(tokens, pos, ntoks) {
    // pos is at KW:func
    let nameTok = tokAt(tokens, pos + 1)
    let fname = tokVal(nameTok)
    // skip name, LPAREN
    let p = pos + 3
    let params = ""
    let pnames = ""
    let pc = 0
    while tokAt(tokens, p) != "RPAREN" {
        let pt = tokAt(tokens, p)
        if tokType(pt) == "ID" {
            let pname = cIdent(tokVal(pt))
            if pc > 0 {
                params = params + ", char* " + pname
                pnames = pnames + "," + pname
            } else {
                params = "char* " + pname
                pnames = pname
            }
            pc += 1
            // optional type annotation: param: type
            if tokAt(tokens, p + 1) == "COLON" {
                p = p + 3
                // handle compound types: list[int] etc
                if tokAt(tokens, p) == "LBRACK" {
                    let td = 1
                    p += 1
                    while td > 0 {
                        if tokAt(tokens, p) == "LBRACK" { td += 1 }
                        if tokAt(tokens, p) == "RBRACK" { td -= 1 }
                        p += 1
                    }
                }
                // skip optional comma
                if tokAt(tokens, p) == "COMMA" { p += 1 }
            } else {
                p += 1
            }
        } else {
            p += 1
        }
    }
    // skip RPAREN
    p += 1
    // optional return type annotation: -> type
    let fnRetType = ""
    if tokAt(tokens, p) == "ARROW" {
        fnRetType = tokVal(tokAt(tokens, p + 1))
        p = p + 2
        // handle compound return types
        if tokAt(tokens, p) == "LBRACK" {
            let rd = 1
            p += 1
            while rd > 0 {
                if tokAt(tokens, p) == "LBRACK" { rd += 1 }
                if tokAt(tokens, p) == "RBRACK" { rd -= 1 }
                p += 1
            }
        }
    }

    // compile body block — pass return type so emit knows how to return
    let fnInFunc = "1"
    if fnRetType == "int"  { fnInFunc = "int" }
    if fnRetType == "bool" { fnInFunc = "int" }
    if fnRetType == "zero" { fnInFunc = "zero" }
    let bp = compileBlock(tokens, p, ntoks, 0, fnInFunc)
    let bcode = pairVal(bp)
    p = pairPos(bp)

    // Generate appropriate C output based on return type.
    // For void and int, emit an inner function + a char* wrapper so
    // the rest of Krypton can call it normally without type casts.
    // Wrappers use char* (not static char*) to match the forward declaration.
    let wrapParams = params
    if pc == 0 { wrapParams = "void" }
    let out = ""
    if fnRetType == "zero" {
        // void inner + char* wrapper
        let vbody = replace(bcode, "return _K_EMPTY;\n", "")
        vbody = replace(vbody, "return _K_ZERO;\n", "")
        vbody = replace(vbody, "return _K_ONE;\n", "")
        let innerName = "_krv_" + cIdent(fname)
        out = "static void " + innerName + "(" + wrapParams + ") {\n" + vbody + "}\n"
        out = out + "char* " + cIdent(fname) + "(" + wrapParams + ") { " + innerName + "(" + pnames + "); return _K_EMPTY; }\n\n"
    } else if fnRetType == "int" {
        // int inner + char* wrapper
        let innerName = "_kri_" + cIdent(fname)
        out = "static int " + innerName + "(" + wrapParams + ") {\n" + bcode + "}\n"
        out = out + "char* " + cIdent(fname) + "(" + wrapParams + ") { return kr_itoa(" + innerName + "(" + pnames + ")); }\n\n"
    } else if fnRetType == "bool" {
        // bool inner (returns int 0/1) + char* wrapper
        let innerName = "_krb_" + cIdent(fname)
        out = "static int " + innerName + "(" + wrapParams + ") {\n" + bcode + "}\n"
        out = out + "char* " + cIdent(fname) + "(" + wrapParams + ") { return " + innerName + "(" + pnames + ") ? _K_ONE : _K_ZERO; }\n\n"
    } else {
        out = "char* " + cIdent(fname) + "(" + params + ") {\n" + bcode + "}\n\n"
    }

    emit out + "," + p
}

// compileCallbackFunc — like compileFunc but generates a void C function
// suitable for use as a C callback via funcptr()
// Usage: callback func name(params) { body }
func compileCallbackFunc(tokens, pos, ntoks) {
    // pos is at KW:func (the callback keyword was already consumed)
    let nameTok = tokAt(tokens, pos + 1)
    let fname = tokVal(nameTok)
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
            pc += 1
            p += 1
        } else {
            p += 1
        }
    }
    p += 1
    // skip optional -> annotation (ignored for callbacks — always void)
    if tokAt(tokens, p) == "ARROW" {
        p = p + 2
    }
    // compile body — any emit/return statements are dropped (void return)
    let bp = compileBlock(tokens, p, ntoks, 0, "1")
    let bcode = pairVal(bp)
    p = pairPos(bp)
    // strip any "return ...;" lines — void function can't return a value
    let bodyStripped = replace(bcode, "return _K_EMPTY;\n", "")
    bodyStripped = replace(bodyStripped, "return _K_ZERO;\n", "")
    bodyStripped = replace(bodyStripped, "return _K_ONE;\n", "")
    let out = "void " + cIdent(fname) + "(" + params + ") {\n" + bodyStripped + "}\n\n"
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
    r = sbAppend(r, "#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <time.h>\n#include <ctype.h>\n#include <stdarg.h>\n#include <stdint.h>\n#if defined(_WIN32) || defined(_WIN64)\n#include <string.h>\n#else\n#include <strings.h>\n#define _stricmp strcasecmp\n#endif\n\nstatic int _argc; static char** _argv;\n\ntypedef struct ABlock { struct ABlock* next; int cap; int used; } ABlock;\n")
    r = sbAppend(r, "static ABlock* _arena = 0;\nstatic char* _alloc(int n) {\n    n = (n + 7) & ~7;\n    if (!_arena || _arena->used + n > _arena->cap) {\n        int cap = 64*1024*1024;\n        if (n > cap) cap = n;\n        ABlock* b = (ABlock*)malloc(sizeof(ABlock) + cap);\n")
    r = sbAppend(r, "        if (!b) { fprintf(stderr, \"out of memory\\n\"); exit(1); }\n")
    r = sbAppend(r, "        b->cap = cap; b->used = 0; b->next = _arena; _arena = b;\n    }\n    char* p = (char*)(_arena + 1) + _arena->used;\n    _arena->used += n;\n    return p;\n}\n\n")

    // Pre-allocated constant strings — eliminates billions of allocations
    r = sbAppend(r, "static char _K_EMPTY[] = \"\";\nstatic char _K_ZERO[] = \"0\";\nstatic char _K_ONE[] = \"1\";\n\n")

    r = sbAppend(r, "static char* kr_str(const char* s) {\n    if (!s[0]) return _K_EMPTY;\n    if (s[0] == '0' && !s[1]) return _K_ZERO;\n    if (s[0] == '1' && !s[1]) return _K_ONE;\n    int n = (int)strlen(s) + 1;\n    char* p = _alloc(n);\n    memcpy(p, s, n);\n    return p;\n")
    r = sbAppend(r, "}\n\nstatic char* kr_cat(const char* a, const char* b) {\n    int la = (int)strlen(a), lb = (int)strlen(b);\n    char* p = _alloc(la + lb + 1);\n    memcpy(p, a, la);\n    memcpy(p + la, b, lb + 1);\n    return p;\n}\n\n")
    r = sbAppend(r, "static int kr_isnum(const char* s) {\n    if (!*s) return 0;\n    const char* p = s;\n    if (*p == '-') p++;\n    if (!*p) return 0;\n    while (*p) { if (*p < '0' || *p > '9') return 0; p++; }\n    return 1;\n}\n\n")
    r = sbAppend(r, "static char* kr_itoa(int v) {\n    if (v == 0) return _K_ZERO;\n    if (v == 1) return _K_ONE;\n    char buf[32];\n    snprintf(buf, sizeof(buf), \"%d\", v);\n    return kr_str(buf);\n}\n\nstatic int kr_atoi(const char* s) { return atoi(s); }\n\n")
    r = sbAppend(r, "static char* kr_plus(const char* a, const char* b) {\n    if (kr_isnum(a) && kr_isnum(b))\n        return kr_itoa(atoi(a) + atoi(b));\n    return kr_cat(a, b);\n}\n\nstatic char* kr_sub(const char* a, const char* b) { return kr_itoa(atoi(a) - atoi(b)); }\nstatic char* kr_mul(const char* a, const char* b) { return kr_itoa(atoi(a) * atoi(b)); }\nstatic char* kr_div(const char* a, const char* b) { return kr_itoa(atoi(a) / atoi(b)); }\n")
    r = sbAppend(r, "static char* kr_mod(const char* a, const char* b) { return kr_itoa(atoi(a) % atoi(b)); }\nstatic char* kr_neg(const char* a) { return kr_itoa(-atoi(a)); }\nstatic char* kr_not(const char* a) { return atoi(a) ? _K_ZERO : _K_ONE; }\n\nstatic char* kr_eq(const char* a, const char* b) {\n    return strcmp(a, b) == 0 ? _K_ONE : _K_ZERO;\n}\nstatic char* kr_neq(const char* a, const char* b) {\n    return strcmp(a, b) != 0 ? _K_ONE : _K_ZERO;\n")
    r = sbAppend(r, "}\nstatic char* kr_lt(const char* a, const char* b) {\n    if (kr_isnum(a) && kr_isnum(b)) return atoi(a) < atoi(b) ? _K_ONE : _K_ZERO;\n    return strcmp(a, b) < 0 ? _K_ONE : _K_ZERO;\n}\nstatic char* kr_gt(const char* a, const char* b) {\n    if (kr_isnum(a) && kr_isnum(b)) return atoi(a) > atoi(b) ? _K_ONE : _K_ZERO;\n    return strcmp(a, b) > 0 ? _K_ONE : _K_ZERO;\n")
    r = sbAppend(r, "}\nstatic char* kr_lte(const char* a, const char* b) {\n    return kr_gt(a, b) == _K_ZERO ? _K_ONE : _K_ZERO;\n}\nstatic char* kr_gte(const char* a, const char* b) {\n    return kr_lt(a, b) == _K_ZERO ? _K_ONE : _K_ZERO;\n}\n\nstatic int kr_truthy(const char* s) {\n")
    r = sbAppend(r, "    if (!s || !*s) return 0;\n    if (strcmp(s, \"0\") == 0) return 0;\n    return 1;\n}\n\nstatic char* kr_print(const char* s) {\n")
    r = sbAppend(r, "    printf(\"%s\\n\", s);\n")
    r = sbAppend(r, "    return _K_EMPTY;\n}\n\nstatic char* kr_len(const char* s) { return kr_itoa((int)strlen(s)); }\n\nstatic char* kr_idx(const char* s, int i) {\n    char buf[2] = {s[i], 0};\n    return kr_str(buf);\n}\n\nstatic char* kr_split(const char* s, const char* idxs) {\n")
    r = sbAppend(r, "    int idx = atoi(idxs);\n    int count = 0;\n    const char* start = s;\n    const char* p = s;\n    while (*p) {\n        if (*p == ',') {\n            if (count == idx) {\n                int len = (int)(p - start);\n")
    r = sbAppend(r, "                char* r = _alloc(len + 1);\n                memcpy(r, start, len);\n                r[len] = 0;\n                return r;\n            }\n            count++;\n            start = p + 1;\n        }\n")
    r = sbAppend(r, "        p++;\n    }\n    if (count == idx) return kr_str(start);\n    return kr_str(\"\");\n}\n\nstatic char* kr_startswith(const char* s, const char* prefix) {\n    return strncmp(s, prefix, strlen(prefix)) == 0 ? _K_ONE : _K_ZERO;\n}\n\n")
    r = sbAppend(r, "static char* kr_substr(const char* s, const char* starts, const char* ends) {\n    int st = atoi(starts), en = atoi(ends);\n    int slen = (int)strlen(s);\n    if (st >= slen) return kr_str(\"\");\n    if (en > slen) en = slen;\n    int n = en - st;\n    if (n <= 0) return kr_str(\"\");\n    char* r = _alloc(n + 1);\n")
    r = sbAppend(r, "    memcpy(r, s + st, n);\n    r[n] = 0;\n    return r;\n}\n\nstatic char* kr_toint(const char* s) { return kr_itoa(atoi(s)); }\n\nstatic char* kr_exec(const char* cmd) {\n    char* buf=_alloc(8192); buf[0]=0;\n#ifdef _WIN32\n    FILE* p=_popen(cmd,\"r\");\n#else\n    FILE* p=popen(cmd,\"r\");\n#endif\n    if(!p) return buf;\n    int pos=0,ch;\n    while(pos<8191&&(ch=fgetc(p))!=EOF) buf[pos++]=(char)ch;\n    buf[pos]=0;\n#ifdef _WIN32\n    _pclose(p);\n#else\n    pclose(p);\n#endif\n    while(pos>0&&(buf[pos-1]==13||buf[pos-1]==10||buf[pos-1]==32)) buf[--pos]=0;\n    return buf;\n}\n\n\n\nstatic char* kr_readfile(const char* path) {\n    FILE* f = fopen(path, \"rb\");\n    if (!f) return kr_str(\"\");\n")
    r = sbAppend(r, "    fseek(f, 0, SEEK_END);\n    long sz = ftell(f);\n    fseek(f, 0, SEEK_SET);\n    char* buf = _alloc((int)sz + 1);\n    fread(buf, 1, sz, f);\n    buf[sz] = 0;\n    fclose(f);\n    return buf;\n")
    r = sbAppend(r, "}\n\nstatic char* kr_arg(const char* idxs) {\n    int idx = atoi(idxs) + 1;\n    if (idx < _argc) return kr_str(_argv[idx]);\n    return kr_str(\"\");\n}\n\nstatic char* kr_argcount() {\n    return kr_itoa(_argc - 1);\n")
    r = sbAppend(r, "}\n\nstatic char* kr_getline(const char* s, const char* idxs) {\n")
    r = sbAppend(r, "    int idx = atoi(idxs);\n    static const char* _gl_s = 0;\n    static int _gl_idx = 0;\n    static const char* _gl_start = 0;\n")
    r = sbAppend(r, "    const char* start; int cur;\n    if (s == _gl_s && _gl_start && idx >= _gl_idx) {\n        start = _gl_start; cur = _gl_idx;\n    } else {\n        start = s; cur = 0; _gl_s = s; _gl_start = s; _gl_idx = 0;\n    }\n")
    r = sbAppend(r, "    const char* p = start;\n    while (*p) {\n        if (*p == '\\n') {\n            if (cur == idx) {\n                int len = (int)(p - start);\n                char* r = _alloc(len + 1);\n                memcpy(r, start, len); r[len] = 0;\n")
    r = sbAppend(r, "                _gl_s = s; _gl_idx = idx; _gl_start = start;\n                return r;\n            }\n            cur++; start = p + 1;\n        }\n        p++;\n    }\n    if (cur == idx) { _gl_s = s; _gl_idx = idx; _gl_start = start; return kr_str(start); }\n    return kr_str(\"\");\n}\n\nstatic char* kr_linecount(const char* s) {\n")
    r = sbAppend(r, "    if (!*s) return kr_str(\"0\");\n    int count = 1;\n    const char* p = s;\n")
    r = sbAppend(r, "    while (*p) { if (*p == '\\n') count++; p++; }\n")
    r = sbAppend(r, "    if (*(p - 1) == '\\n') count--;\n")
    r = sbAppend(r, "    return kr_itoa(count);\n}\n\nstatic char* kr_count(const char* s) {\n    return kr_linecount(s);\n}\n\n")

    // v0.2.0 builtins
    r = sbAppend(r, "static char* kr_writefile(const char* path, const char* data) {\n    FILE* f = fopen(path, \"wb\");\n    if (!f) return _K_ZERO;\n    fwrite(data, 1, strlen(data), f);\n    fclose(f);\n    return _K_ONE;\n}\n\n")
    r = sbAppend(r, "static int _krhex(char c){if(c>='0'&&c<='9')return c-'0';if(c>='a'&&c<='f')return c-'a'+10;if(c>='A'&&c<='F')return c-'A'+10;return -1;}\n")
    r = sbAppend(r, "static char* kr_writebytes(const char* path, const char* hexstr) {\n    FILE* f = fopen(path, \"wb\");\n    if (!f) return _K_ZERO;\n    const char* p = hexstr;\n    while (*p) {\n        if (*p == 'x' && p[1] && p[2]) {\n            int hi = _krhex(p[1]), lo = _krhex(p[2]);\n            if (hi >= 0 && lo >= 0) { unsigned char b = (unsigned char)(hi*16+lo); fwrite(&b,1,1,f); }\n            p += 3;\n        } else { p++; }\n    }\n    fclose(f);\n    return _K_ONE;\n}\n\n")
    r = sbAppend(r, "static char* kr_shellrun(const char* cmd){int r=system(cmd);return kr_itoa(r);}\n")
    r = sbAppend(r, "static char* kr_deletefile(const char* path){remove(path);return _K_EMPTY;}\n")
    // Bootstrap aliases: older bootstrap compilers (kcc_v103) emit bare function names
    // instead of kr_* for builtins they don't recognize. Define plain aliases so they resolve.
    r = sbAppend(r, "static char* exec(const char* cmd){return kr_exec(cmd);}\n")
    r = sbAppend(r, "static char* shellRun(const char* cmd){return kr_shellrun(cmd);}\n")
    r = sbAppend(r, "static char* deleteFile(const char* path){return kr_deletefile(path);}\n\n")

    r = sbAppend(r, "static char* kr_input() {\n    char buf[4096];\n    if (!fgets(buf, sizeof(buf), stdin)) return _K_EMPTY;\n    int len = (int)strlen(buf);\n")
    r = sbAppend(r, "    if (len > 0 && buf[len-1] == '\\n') buf[--len] = 0;\n")
    r = sbAppend(r, "    if (len > 0 && buf[len-1] == '\\r') buf[--len] = 0;\n")
    r = sbAppend(r, "    return kr_str(buf);\n}\n\n")

    r = sbAppend(r, "static char* kr_indexof(const char* s, const char* sub) {\n    const char* p = strstr(s, sub);\n    if (!p) return kr_itoa(-1);\n    return kr_itoa((int)(p - s));\n}\n\n")

    r = sbAppend(r, "static char* kr_replace(const char* s, const char* old, const char* rep) {\n    int slen = (int)strlen(s), olen = (int)strlen(old), rlen = (int)strlen(rep);\n    if (olen == 0) return kr_str(s);\n    int count = 0;\n    const char* p = s;\n    while ((p = strstr(p, old)) != 0) { count++; p += olen; }\n    int nlen = slen + count * (rlen - olen);\n    char* out = _alloc(nlen + 1);\n")
    r = sbAppend(r, "    char* dst = out;\n    p = s;\n    while (*p) {\n        if (strncmp(p, old, olen) == 0) {\n            memcpy(dst, rep, rlen); dst += rlen; p += olen;\n        } else { *dst++ = *p++; }\n    }\n    *dst = 0;\n")
    r = sbAppend(r, "    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_charat(const char* s, const char* idxs) {\n    int i = atoi(idxs);\n    int slen = (int)strlen(s);\n    if (i < 0 || i >= slen) return _K_EMPTY;\n    char buf[2] = {s[i], 0};\n    return kr_str(buf);\n}\n\n")

    r = sbAppend(r, "static char* kr_trim(const char* s) {\n")
    r = sbAppend(r, "    while (*s == ' ' || *s == '\\t' || *s == '\\n' || *s == '\\r') s++;\n")
    r = sbAppend(r, "    int len = (int)strlen(s);\n")
    r = sbAppend(r, "    while (len > 0 && (s[len-1]==' '||s[len-1]=='\\t'||s[len-1]=='\\n'||s[len-1]=='\\r')) len--;\n")
    r = sbAppend(r, "    char* r = _alloc(len + 1);\n    memcpy(r, s, len);\n    r[len] = 0;\n    return r;\n}\n\n")

    r = sbAppend(r, "static char* kr_tolower(const char* s) {\n    int len = (int)strlen(s);\n    char* out = _alloc(len + 1);\n    for (int i = 0; i <= len; i++)\n        out[i] = (s[i] >= 'A' && s[i] <= 'Z') ? s[i] + 32 : s[i];\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_toupper(const char* s) {\n    int len = (int)strlen(s);\n    char* out = _alloc(len + 1);\n    for (int i = 0; i <= len; i++)\n        out[i] = (s[i] >= 'a' && s[i] <= 'z') ? s[i] - 32 : s[i];\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_contains(const char* s, const char* sub) {\n    return strstr(s, sub) ? _K_ONE : _K_ZERO;\n}\n\n")

    r = sbAppend(r, "static char* kr_endswith(const char* s, const char* suffix) {\n    int slen = (int)strlen(s), suflen = (int)strlen(suffix);\n    if (suflen > slen) return _K_ZERO;\n    return strcmp(s + slen - suflen, suffix) == 0 ? _K_ONE : _K_ZERO;\n}\n\n")

    r = sbAppend(r, "static char* kr_abs(const char* a) { int v = atoi(a); return kr_itoa(v < 0 ? -v : v); }\nstatic char* kr_min(const char* a, const char* b) { return atoi(a) <= atoi(b) ? kr_str(a) : kr_str(b); }\nstatic char* kr_max(const char* a, const char* b) { return atoi(a) >= atoi(b) ? kr_str(a) : kr_str(b); }\n\n")

    r = sbAppend(r, "static char* kr_exit(const char* code) { exit(atoi(code)); return _K_EMPTY; }\n\n")

    r = sbAppend(r, "static char* kr_type(const char* s) {\n    if (kr_isnum(s)) return kr_str(\"number\");\n    return kr_str(\"string\");\n}\n\n")

    // v0.3.0 builtins: list/map ops, repeat, format, parseInt, toStr
    r = sbAppend(r, "static char* kr_append(const char* lst, const char* item) {\n    if (!*lst) return kr_str(item);\n    return kr_cat(kr_cat(lst, \",\"), item);\n}\n\n")

    r = sbAppend(r, "static char* kr_join(const char* lst, const char* sep) {\n    int llen = (int)strlen(lst), slen = (int)strlen(sep);\n    int rlen = 0;\n    for (int i = 0; i < llen; i++) {\n        if (lst[i] == ',') rlen += slen; else rlen++;\n    }\n    char* out = _alloc(rlen + 1);\n    int j = 0;\n")
    r = sbAppend(r, "    for (int i = 0; i < llen; i++) {\n        if (lst[i] == ',') { memcpy(out+j, sep, slen); j += slen; }\n        else { out[j++] = lst[i]; }\n    }\n    out[j] = 0;\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_reverse(const char* lst) {\n    int cnt = 0;\n    const char* p = lst;\n    while (*p) { if (*p == ',') cnt++; p++; }\n    cnt++;\n    char* out = _K_EMPTY;\n    for (int i = cnt - 1; i >= 0; i--) {\n        char* item = kr_split(lst, kr_itoa(i));\n")
    r = sbAppend(r, "        if (i == cnt - 1) out = item;\n        else out = kr_cat(kr_cat(out, \",\"), item);\n    }\n    return out;\n}\n\n")

    r = sbAppend(r, "static int _kr_cmp(const void* a, const void* b) {\n    const char* sa = *(const char**)a;\n    const char* sb = *(const char**)b;\n    if (kr_isnum(sa) && kr_isnum(sb)) return atoi(sa) - atoi(sb);\n    return strcmp(sa, sb);\n}\nstatic char* kr_sort(const char* lst) {\n    if (!*lst) return _K_EMPTY;\n")
    r = sbAppend(r, "    int cnt = 1;\n    const char* p = lst;\n    while (*p) { if (*p == ',') cnt++; p++; }\n    char** arr = (char**)_alloc(cnt * sizeof(char*));\n    for (int i = 0; i < cnt; i++) arr[i] = kr_split(lst, kr_itoa(i));\n    qsort(arr, cnt, sizeof(char*), _kr_cmp);\n    char* out = arr[0];\n    for (int i = 1; i < cnt; i++) out = kr_cat(kr_cat(out, \",\"), arr[i]);\n")
    r = sbAppend(r, "    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_keys(const char* map) {\n    if (!*map) return _K_EMPTY;\n    int cnt = 1;\n    const char* p = map;\n    while (*p) { if (*p == ',') cnt++; p++; }\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i += 2) {\n        char* k = kr_split(map, kr_itoa(i));\n")
    r = sbAppend(r, "        if (first) { out = k; first = 0; }\n        else out = kr_cat(kr_cat(out, \",\"), k);\n    }\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_values(const char* map) {\n    if (!*map) return _K_EMPTY;\n    int cnt = 1;\n    const char* p = map;\n    while (*p) { if (*p == ',') cnt++; p++; }\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 1; i < cnt; i += 2) {\n        char* v = kr_split(map, kr_itoa(i));\n")
    r = sbAppend(r, "        if (first) { out = v; first = 0; }\n        else out = kr_cat(kr_cat(out, \",\"), v);\n    }\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_haskey(const char* map, const char* key) {\n    if (!*map) return _K_ZERO;\n    int cnt = 1;\n    const char* p = map;\n    while (*p) { if (*p == ',') cnt++; p++; }\n    for (int i = 0; i < cnt; i += 2) {\n        if (strcmp(kr_split(map, kr_itoa(i)), key) == 0) return _K_ONE;\n    }\n")
    r = sbAppend(r, "    return _K_ZERO;\n}\n\n")

    r = sbAppend(r, "static char* kr_remove(const char* lst, const char* item) {\n    if (!*lst) return _K_EMPTY;\n    int cnt = 1;\n    const char* p = lst;\n    while (*p) { if (*p == ',') cnt++; p++; }\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i++) {\n        char* el = kr_split(lst, kr_itoa(i));\n")
    r = sbAppend(r, "        if (strcmp(el, item) != 0) {\n            if (first) { out = el; first = 0; }\n            else out = kr_cat(kr_cat(out, \",\"), el);\n        }\n    }\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_repeat(const char* s, const char* ns) {\n    int n = atoi(ns);\n    if (n <= 0) return _K_EMPTY;\n    int slen = (int)strlen(s);\n    char* out = _alloc(slen * n + 1);\n    for (int i = 0; i < n; i++) memcpy(out + i * slen, s, slen);\n    out[slen * n] = 0;\n    return out;\n")
    r = sbAppend(r, "}\n\n")

    r = sbAppend(r, "static char* kr_format(const char* fmt, const char* arg) {\n    char buf[4096];\n    const char* p = strstr(fmt, \"{}\");\n    if (!p) return kr_str(fmt);\n    int pre = (int)(p - fmt);\n    int alen = (int)strlen(arg);\n    int postlen = (int)strlen(p + 2);\n    if (pre + alen + postlen >= 4096) return kr_str(fmt);\n")
    r = sbAppend(r, "    memcpy(buf, fmt, pre);\n    memcpy(buf + pre, arg, alen);\n    memcpy(buf + pre + alen, p + 2, postlen + 1);\n    return kr_str(buf);\n}\n\n")

    r = sbAppend(r, "static char* kr_parseint(const char* s) {\n    const char* p = s;\n")
    r = sbAppend(r, "    while (*p == ' ' || *p == '\\t') p++;\n")
    r = sbAppend(r, "    if (!*p) return _K_ZERO;\n    return kr_itoa(atoi(p));\n}\n\n")

    r = sbAppend(r, "static char* kr_tostr(const char* s) { return kr_str(s); }\n\n")

    r = sbAppend(r, "static int kr_listlen(const char* s) {\n    if (!*s) return 0;\n    int cnt = 1;\n    while (*s) { if (*s == ',') cnt++; s++; }\n    return cnt;\n}\n\n")

    // v0.4.0 builtins
    r = sbAppend(r, "static char* kr_range(const char* starts, const char* ends) {\n    int s = atoi(starts), e = atoi(ends);\n    if (s >= e) return _K_EMPTY;\n    char* out = kr_itoa(s);\n    for (int i = s + 1; i < e; i++) out = kr_cat(kr_cat(out, \",\"), kr_itoa(i));\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_pow(const char* bs, const char* es) {\n    int b = atoi(bs), e = atoi(es), r = 1;\n    for (int i = 0; i < e; i++) r *= b;\n    return kr_itoa(r);\n}\n\n")

    r = sbAppend(r, "static char* kr_sqrt(const char* s) {\n    int v = atoi(s);\n    if (v <= 0) return _K_ZERO;\n    int r = 0;\n    while ((r + 1) * (r + 1) <= v) r++;\n    return kr_itoa(r);\n}\n\n")

    r = sbAppend(r, "static char* kr_sign(const char* s) {\n    int v = atoi(s);\n    if (v > 0) return _K_ONE;\n    if (v < 0) return kr_str(\"-1\");\n    return _K_ZERO;\n}\n\n")

    r = sbAppend(r, "static char* kr_clamp(const char* vs, const char* los, const char* his) {\n    int v = atoi(vs), lo = atoi(los), hi = atoi(his);\n    if (v < lo) return kr_str(los);\n    if (v > hi) return kr_str(his);\n    return kr_str(vs);\n}\n\n")

    r = sbAppend(r, "static char* kr_padleft(const char* s, const char* ws, const char* pad) {\n    int w = atoi(ws), slen = (int)strlen(s), plen = (int)strlen(pad);\n    if (slen >= w || plen == 0) return kr_str(s);\n    int need = w - slen;\n    char* out = _alloc(w + 1);\n    for (int i = 0; i < need; i++) out[i] = pad[i % plen];\n    memcpy(out + need, s, slen + 1);\n    return out;\n")
    r = sbAppend(r, "}\n\n")

    r = sbAppend(r, "static char* kr_padright(const char* s, const char* ws, const char* pad) {\n    int w = atoi(ws), slen = (int)strlen(s), plen = (int)strlen(pad);\n    if (slen >= w || plen == 0) return kr_str(s);\n    int need = w - slen;\n    char* out = _alloc(w + 1);\n    memcpy(out, s, slen);\n    for (int i = 0; i < need; i++) out[slen + i] = pad[i % plen];\n    out[w] = 0;\n")
    r = sbAppend(r, "    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_charcode(const char* s) {\n    if (!*s) return _K_ZERO;\n    return kr_itoa((unsigned char)s[0]);\n}\n\n")

    r = sbAppend(r, "static char* kr_fromcharcode(const char* ns) {\n    char buf[2] = {(char)atoi(ns), 0};\n    return kr_str(buf);\n}\n\n")

    r = sbAppend(r, "static char* kr_slice(const char* lst, const char* starts, const char* ends) {\n    int cnt = kr_listlen(lst);\n    int s = atoi(starts), e = atoi(ends);\n    if (s < 0) s = cnt + s;\n    if (e < 0) e = cnt + e;\n    if (s < 0) s = 0;\n    if (e > cnt) e = cnt;\n    if (s >= e) return _K_EMPTY;\n")
    r = sbAppend(r, "    char* out = kr_split(lst, kr_itoa(s));\n    for (int i = s + 1; i < e; i++)\n        out = kr_cat(kr_cat(out, \",\"), kr_split(lst, kr_itoa(i)));\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_length(const char* lst) {\n    return kr_itoa(kr_listlen(lst));\n}\n\n")

    r = sbAppend(r, "static char* kr_unique(const char* lst) {\n    if (!*lst) return _K_EMPTY;\n    int cnt = kr_listlen(lst);\n    char* out = _K_EMPTY; int oc = 0;\n    for (int i = 0; i < cnt; i++) {\n        char* item = kr_split(lst, kr_itoa(i));\n        int dup = 0;\n        for (int j = 0; j < oc; j++) {\n")
    r = sbAppend(r, "            if (strcmp(kr_split(out, kr_itoa(j)), item) == 0) { dup = 1; break; }\n        }\n        if (!dup) {\n            if (oc == 0) out = item; else out = kr_cat(kr_cat(out, \",\"), item);\n            oc++;\n        }\n    }\n    return out;\n")
    r = sbAppend(r, "}\n\n")

    r = sbAppend(r, "static char* kr_printerr(const char* s) {\n")
    r = sbAppend(r, "    fprintf(stderr, \"%s\\n\", s);\n")
    r = sbAppend(r, "    return _K_EMPTY;\n}\n\n")

    r = sbAppend(r, "static char* kr_readline(const char* prompt) {\n    if (*prompt) printf(\"%s\", prompt);\n    fflush(stdout);\n    char buf[4096];\n    if (!fgets(buf, sizeof(buf), stdin)) return _K_EMPTY;\n    int len = (int)strlen(buf);\n")
    r = sbAppend(r, "    if (len > 0 && buf[len-1] == '\\n') buf[--len] = 0;\n")
    r = sbAppend(r, "    if (len > 0 && buf[len-1] == '\\r') buf[--len] = 0;\n")
    r = sbAppend(r, "    return kr_str(buf);\n}\n\n")

    r = sbAppend(r, "static char* kr_assert(const char* cond, const char* msg) {\n    if (!kr_truthy(cond)) {\n")
    r = sbAppend(r, "        fprintf(stderr, \"ASSERTION FAILED: %s\\n\", msg);\n")
    r = sbAppend(r, "        exit(1);\n    }\n    return _K_ONE;\n}\n\n")

    // v0.5.0 builtins: list operations, data, conversion
    r = sbAppend(r, "static char* kr_splitby(const char* s, const char* delim) {\n    int slen = (int)strlen(s), dlen = (int)strlen(delim);\n    if (dlen == 0 || slen == 0) return kr_str(s);\n    char* out = _K_EMPTY; int first = 1;\n    const char* p = s;\n    while (*p) {\n        const char* f = strstr(p, delim);\n        if (!f) { \n")
    r = sbAppend(r, "            if (first) out = kr_str(p); else out = kr_cat(kr_cat(out, \",\"), kr_str(p));\n            break;\n        }\n        int n = (int)(f - p);\n        char* chunk = _alloc(n + 1);\n        memcpy(chunk, p, n); chunk[n] = 0;\n        if (first) { out = chunk; first = 0; }\n        else out = kr_cat(kr_cat(out, \",\"), chunk);\n")
    r = sbAppend(r, "        p = f + dlen;\n        if (!*p) { out = kr_cat(kr_cat(out, \",\"), _K_EMPTY); break; }\n    }\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_listindexof(const char* lst, const char* item) {\n    if (!*lst) return kr_itoa(-1);\n    int cnt = kr_listlen(lst);\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(kr_split(lst, kr_itoa(i)), item) == 0) return kr_itoa(i);\n    }\n    return kr_itoa(-1);\n}\n\n")

    r = sbAppend(r, "static char* kr_insertat(const char* lst, const char* idxs, const char* item) {\n    int idx = atoi(idxs);\n    int cnt = kr_listlen(lst);\n    if (!*lst && idx == 0) return kr_str(item);\n    if (idx < 0) idx = 0;\n    if (idx >= cnt) return kr_cat(kr_cat(lst, \",\"), item);\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i++) {\n")
    r = sbAppend(r, "        if (i == idx) {\n            if (first) { out = kr_str(item); first = 0; }\n            else out = kr_cat(kr_cat(out, \",\"), item);\n        }\n        char* el = kr_split(lst, kr_itoa(i));\n        if (first) { out = el; first = 0; }\n        else out = kr_cat(kr_cat(out, \",\"), el);\n    }\n")
    r = sbAppend(r, "    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_removeat(const char* lst, const char* idxs) {\n    int idx = atoi(idxs);\n    int cnt = kr_listlen(lst);\n    if (idx < 0 || idx >= cnt) return kr_str(lst);\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i++) {\n        if (i == idx) continue;\n        char* el = kr_split(lst, kr_itoa(i));\n")
    r = sbAppend(r, "        if (first) { out = el; first = 0; }\n        else out = kr_cat(kr_cat(out, \",\"), el);\n    }\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_replaceat(const char* lst, const char* idxs, const char* val) {\n    int idx = atoi(idxs);\n    int cnt = kr_listlen(lst);\n    if (idx < 0 || idx >= cnt) return kr_str(lst);\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i++) {\n        char* el = (i == idx) ? (char*)val : kr_split(lst, kr_itoa(i));\n        if (first) { out = el; first = 0; }\n")
    r = sbAppend(r, "        else out = kr_cat(kr_cat(out, \",\"), el);\n    }\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_fill(const char* ns, const char* val) {\n    int n = atoi(ns);\n    if (n <= 0) return _K_EMPTY;\n    char* out = kr_str(val);\n    for (int i = 1; i < n; i++) out = kr_cat(kr_cat(out, \",\"), val);\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_zip(const char* a, const char* b) {\n    int ac = kr_listlen(a), bc = kr_listlen(b);\n    int mc = ac < bc ? ac : bc;\n    if (!*a || !*b) return _K_EMPTY;\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < mc; i++) {\n        char* ai = kr_split(a, kr_itoa(i));\n        char* bi = kr_split(b, kr_itoa(i));\n")
    r = sbAppend(r, "        if (first) { out = kr_cat(kr_cat(ai, \",\"), bi); first = 0; }\n        else { out = kr_cat(kr_cat(out, \",\"), kr_cat(kr_cat(ai, \",\"), bi)); }\n    }\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_every(const char* lst, const char* val) {\n    if (!*lst) return _K_ONE;\n    int cnt = kr_listlen(lst);\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(kr_split(lst, kr_itoa(i)), val) != 0) return _K_ZERO;\n    }\n    return _K_ONE;\n}\n\n")

    r = sbAppend(r, "static char* kr_some(const char* lst, const char* val) {\n    if (!*lst) return _K_ZERO;\n    int cnt = kr_listlen(lst);\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(kr_split(lst, kr_itoa(i)), val) == 0) return _K_ONE;\n    }\n    return _K_ZERO;\n}\n\n")

    r = sbAppend(r, "static char* kr_countof(const char* lst, const char* item) {\n    if (!*lst) return _K_ZERO;\n    int cnt = kr_listlen(lst), c = 0;\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(kr_split(lst, kr_itoa(i)), item) == 0) c++;\n    }\n    return kr_itoa(c);\n}\n\n")

    r = sbAppend(r, "static char* kr_sumlist(const char* lst) {\n    if (!*lst) return _K_ZERO;\n    int cnt = kr_listlen(lst), s = 0;\n    for (int i = 0; i < cnt; i++) s += atoi(kr_split(lst, kr_itoa(i)));\n    return kr_itoa(s);\n}\n\n")

    r = sbAppend(r, "static char* kr_maxlist(const char* lst) {\n    if (!*lst) return _K_ZERO;\n    int cnt = kr_listlen(lst);\n    int m = atoi(kr_split(lst, _K_ZERO));\n    for (int i = 1; i < cnt; i++) {\n        int v = atoi(kr_split(lst, kr_itoa(i)));\n        if (v > m) m = v;\n    }\n")
    r = sbAppend(r, "    return kr_itoa(m);\n}\n\n")

    r = sbAppend(r, "static char* kr_minlist(const char* lst) {\n    if (!*lst) return _K_ZERO;\n    int cnt = kr_listlen(lst);\n    int m = atoi(kr_split(lst, _K_ZERO));\n    for (int i = 1; i < cnt; i++) {\n        int v = atoi(kr_split(lst, kr_itoa(i)));\n        if (v < m) m = v;\n    }\n")
    r = sbAppend(r, "    return kr_itoa(m);\n}\n\n")

    r = sbAppend(r, "static char* kr_hex(const char* s) {\n    int v = atoi(s);\n    char buf[32];\n    snprintf(buf, sizeof(buf), \"%x\", v < 0 ? -v : v);\n    if (v < 0) return kr_cat(\"-\", kr_str(buf));\n    return kr_str(buf);\n}\n\n")

    r = sbAppend(r, "static char* kr_bin(const char* s) {\n    int v = atoi(s);\n    if (v == 0) return _K_ZERO;\n    int neg = v < 0; if (neg) v = -v;\n    char buf[64]; int i = 63; buf[i] = 0;\n    while (v > 0) { buf[--i] = '0' + (v & 1); v >>= 1; }\n    if (neg) return kr_cat(\"-\", kr_str(&buf[i]));\n    return kr_str(&buf[i]);\n")
    r = sbAppend(r, "}\n\n")

    // Native env (linked-list of entries, cast to char*)
    r = sbAppend(r, "typedef struct EnvEntry { char* name; char* value; struct EnvEntry* prev; } EnvEntry;\n\n")

    r = sbAppend(r, "static char* kr_envnew() { return (char*)0; }\n\n")

    r = sbAppend(r, "static char* kr_envset(char* envp, const char* name, const char* val) {\n    EnvEntry* e = (EnvEntry*)_alloc(sizeof(EnvEntry));\n    e->name = (char*)name;\n    e->value = (char*)val;\n    e->prev = (EnvEntry*)envp;\n    return (char*)e;\n}\n\n")

    r = sbAppend(r, "static char* kr_envget(char* envp, const char* name) {\n    EnvEntry* e = (EnvEntry*)envp;\n    while (e) {\n        if (strcmp(e->name, name) == 0) return e->value;\n        e = e->prev;\n    }\n    if (strcmp(name, \"__argOffset\") != 0)\n")
    r = sbAppend(r, "        fprintf(stderr, \"ERROR: undefined variable: %s\\n\", name);\n")
    r = sbAppend(r, "    return kr_str(\"\");\n}\n\n")

    // Native result (struct with tag, val, env, pos)
    r = sbAppend(r, "typedef struct ResultStruct { char tag; char* val; char* env; int pos; } ResultStruct;\n\n")

    r = sbAppend(r, "static char* kr_makeresult(const char* tag, const char* val, const char* env, const char* pos) {\n    ResultStruct* r = (ResultStruct*)_alloc(sizeof(ResultStruct));\n    r->tag = tag[0];\n    r->val = (char*)val;\n    r->env = (char*)env;\n    r->pos = atoi(pos);\n    return (char*)r;\n}\n\n")

    r = sbAppend(r, "static char* kr_getresulttag(const char* r) {\n    char buf[2] = {((ResultStruct*)r)->tag, 0};\n    return kr_str(buf);\n}\n\n")

    r = sbAppend(r, "static char* kr_getresultval(const char* r) {\n    return ((ResultStruct*)r)->val;\n}\n\n")

    r = sbAppend(r, "static char* kr_getresultenv(const char* r) {\n    return ((ResultStruct*)r)->env;\n}\n\n")

    r = sbAppend(r, "static char* kr_getresultpos(const char* r) {\n    return kr_itoa(((ResultStruct*)r)->pos);\n}\n\n")

    r = sbAppend(r, "static char* kr_istruthy(const char* s) {\n    if (!s || !*s || strcmp(s, \"0\") == 0 || strcmp(s, \"false\") == 0)\n        return _K_ZERO;\n    return _K_ONE;\n}\n\n")

    // StringBuilder: handle-based, mutable buffer with capacity doubling
    r = sbAppend(r, "typedef struct { int cap; int len; } SBHdr;\n#define MAX_SBS 4096\nstatic SBHdr* _sb_table[MAX_SBS];\nstatic int _sb_count = 0;\n\nstatic char* kr_sbnew() {\n    int initcap = 65536;\n    SBHdr* h = (SBHdr*)malloc(sizeof(SBHdr) + initcap);\n    h->cap = initcap;\n")
    r = sbAppend(r, "    h->len = 0;\n    ((char*)(h + 1))[0] = 0;\n    _sb_table[_sb_count] = h;\n    return kr_itoa(_sb_count++);\n}\n\nstatic char* kr_sbappend(const char* handle, const char* s) {\n    int idx = atoi(handle);\n    SBHdr* h = _sb_table[idx];\n")
    r = sbAppend(r, "    int slen = (int)strlen(s);\n    while (h->len + slen + 1 > h->cap) {\n        int newcap = h->cap * 2;\n        h = (SBHdr*)realloc(h, sizeof(SBHdr) + newcap);\n        h->cap = newcap;\n    }\n    memcpy((char*)(h + 1) + h->len, s, slen);\n    h->len += slen;\n")
    r = sbAppend(r, "    ((char*)(h + 1))[h->len] = 0;\n    _sb_table[idx] = h;\n    return kr_str(handle);\n}\n\nstatic char* kr_sbtostring(const char* handle) {\n    int idx = atoi(handle);\n    SBHdr* h = _sb_table[idx];\n    return (char*)(h + 1);\n")
    r = sbAppend(r, "}\n\n")


    // v0.7.0: setjmp/longjmp exception support
    r = sbAppend(r, "#include <setjmp.h>\n#define _KR_TRY_MAX 256\nstatic jmp_buf _kr_try_stack[_KR_TRY_MAX];\nstatic char*   _kr_err_stack[_KR_TRY_MAX];\nstatic int     _kr_try_depth = 0;\n\nstatic jmp_buf* _kr_pushtry() {\n    _kr_err_stack[_kr_try_depth] = _K_EMPTY;\n    return &_kr_try_stack[_kr_try_depth++];\n")
    r = sbAppend(r, "}\n\nstatic char* _kr_poptry() {\n    if (_kr_try_depth > 0) _kr_try_depth--;\n    return _kr_err_stack[_kr_try_depth];\n}\n\nstatic char* _kr_throw(const char* msg) {\n    if (_kr_try_depth > 0) {\n        _kr_err_stack[_kr_try_depth - 1] = (char*)msg;\n")
    r = sbAppend(r, "        longjmp(_kr_try_stack[_kr_try_depth - 1], 1);\n    }\n")
    r = sbAppend(r, "    fprintf(stderr, \"Uncaught exception: %s\\n\", msg);\n")
    r = sbAppend(r, "    exit(1);\n    return _K_EMPTY;\n}\n\n")

    // v0.7.0 builtins
    r = sbAppend(r, "static char* kr_strreverse(const char* s) {\n    int n = (int)strlen(s);\n    char* out = _alloc(n + 1);\n    for (int i = 0; i < n; i++) out[i] = s[n - 1 - i];\n    out[n] = 0;\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_words(const char* s) {\n    if (!*s) return _K_EMPTY;\n    char* out = _K_EMPTY; int first = 1;\n    const char* p = s;\n")
    r = sbAppend(r, "    while (*p == ' ' || *p == '\\t') p++;\n")
    r = sbAppend(r, "    const char* start = p;\n    while (1) {\n")
    r = sbAppend(r, "        if (*p == ' ' || *p == '\\t' || *p == 0) {\n")
    r = sbAppend(r, "            if (p > start) {\n                int n = (int)(p - start);\n                char* w = _alloc(n + 1);\n                memcpy(w, start, n); w[n] = 0;\n                if (first) { out = w; first = 0; }\n                else out = kr_cat(kr_cat(out, \",\"), w);\n            }\n            if (!*p) break;\n")
    r = sbAppend(r, "            while (*p == ' ' || *p == '\\t') p++;\n")
    r = sbAppend(r, "            start = p;\n        } else { p++; }\n    }\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_lines(const char* s) {\n    if (!*s) return _K_EMPTY;\n    char* out = _K_EMPTY; int first = 1;\n    const char* p = s, *start = s;\n    while (1) {\n")
    r = sbAppend(r, "        if (*p == '\\n' || *p == 0) {\n")
    r = sbAppend(r, "            int n = (int)(p - start);\n")
    r = sbAppend(r, "            if (n > 0 && start[n-1] == '\\r') n--;\n")
    r = sbAppend(r, "            char* ln = _alloc(n + 1);\n            memcpy(ln, start, n); ln[n] = 0;\n            if (first) { out = ln; first = 0; }\n            else out = kr_cat(kr_cat(out, \",\"), ln);\n            if (!*p) break;\n            start = p + 1;\n        }\n        p++;\n")
    r = sbAppend(r, "    }\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_first(const char* lst) { return kr_split(lst, _K_ZERO); }\n\n")

    r = sbAppend(r, "static char* kr_last(const char* lst) {\n    int cnt = kr_listlen(lst);\n    if (cnt == 0) return _K_EMPTY;\n    return kr_split(lst, kr_itoa(cnt - 1));\n}\n\n")

    r = sbAppend(r, "static char* kr_head(const char* lst, const char* ns) {\n    int n = atoi(ns), cnt = kr_listlen(lst);\n    if (n <= 0 || !*lst) return _K_EMPTY;\n    if (n >= cnt) return kr_str(lst);\n    char* out = kr_split(lst, _K_ZERO);\n    for (int i = 1; i < n; i++) out = kr_cat(kr_cat(out, \",\"), kr_split(lst, kr_itoa(i)));\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_tail(const char* lst, const char* ns) {\n    int n = atoi(ns), cnt = kr_listlen(lst);\n    if (n <= 0 || !*lst) return _K_EMPTY;\n    if (n >= cnt) return kr_str(lst);\n    int start = cnt - n;\n    char* out = kr_split(lst, kr_itoa(start));\n    for (int i = start + 1; i < cnt; i++) out = kr_cat(kr_cat(out, \",\"), kr_split(lst, kr_itoa(i)));\n    return out;\n")
    r = sbAppend(r, "}\n\n")

    r = sbAppend(r, "static char* kr_lstrip(const char* s) {\n")
    r = sbAppend(r, "    while (*s == ' ' || *s == '\\t' || *s == '\\n' || *s == '\\r') s++;\n")
    r = sbAppend(r, "    return kr_str(s);\n}\n\n")

    r = sbAppend(r, "static char* kr_rstrip(const char* s) {\n    int len = (int)strlen(s);\n")
    r = sbAppend(r, "    while (len > 0 && (s[len-1]==' '||s[len-1]=='\\t'||s[len-1]=='\\n'||s[len-1]=='\\r')) len--;\n")
    r = sbAppend(r, "    char* r = _alloc(len + 1);\n    memcpy(r, s, len); r[len] = 0;\n    return r;\n}\n\n")

    r = sbAppend(r, "static char* kr_center(const char* s, const char* ws, const char* pad) {\n    int w = atoi(ws), slen = (int)strlen(s), plen = (int)strlen(pad);\n    if (slen >= w || plen == 0) return kr_str(s);\n    int total = w - slen;\n    int left = total / 2, right = total - left;\n    char* out = _alloc(w + 1);\n    for (int i = 0; i < left; i++) out[i] = pad[i % plen];\n    memcpy(out + left, s, slen);\n")
    r = sbAppend(r, "    for (int i = 0; i < right; i++) out[left + slen + i] = pad[i % plen];\n    out[w] = 0;\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_isalpha(const char* s) {\n    if (!*s) return _K_ZERO;\n    for (const char* p = s; *p; p++) if (!isalpha((unsigned char)*p)) return _K_ZERO;\n    return _K_ONE;\n}\n\n")

    r = sbAppend(r, "static char* kr_isdigit(const char* s) {\n    if (!*s) return _K_ZERO;\n    for (const char* p = s; *p; p++) if (!isdigit((unsigned char)*p)) return _K_ZERO;\n    return _K_ONE;\n}\n\n")

    r = sbAppend(r, "static char* kr_isspace(const char* s) {\n    if (!*s) return _K_ZERO;\n    for (const char* p = s; *p; p++) if (!isspace((unsigned char)*p)) return _K_ZERO;\n    return _K_ONE;\n}\n\n")

    r = sbAppend(r, "static char* kr_random(const char* ns) {\n    int n = atoi(ns);\n    if (n <= 0) return _K_ZERO;\n    return kr_itoa(rand() % n);\n}\n\n")

    r = sbAppend(r, "static char* kr_timestamp() {\n    return kr_itoa((int)time(NULL));\n}\n\n")

    r = sbAppend(r, "static char* kr_environ(const char* name) {\n    const char* v = getenv(name);\n    if (!v) return _K_EMPTY;\n    return kr_str(v);\n}\n\n")

    r = sbAppend(r, "static char* kr_floor(const char* s) { return kr_itoa((int)atoi(s)); }\nstatic char* kr_ceil(const char* s)  { return kr_itoa((int)atoi(s)); }\nstatic char* kr_round(const char* s) { return kr_itoa((int)atoi(s)); }\n\n")

    r = sbAppend(r, "static char* kr_throw(const char* msg) { return _kr_throw(msg); }\n\n")


    // v0.7.1: struct field access via tagged field array
    // Structs are stored as: count|name1|val1|name2|val2|...
    // All in arena memory, cast to char*
    r = sbAppend(r, "static char* kr_structnew() {\n    // 2 slots for count + up to 32 fields (name+val pairs)\n    char** s = (char**)_alloc(66 * sizeof(char*));\n    s[0] = _K_ZERO; // field count\n    return (char*)s;\n}\n\nstatic char* kr_setfield(char* obj, const char* name, const char* val) {\n    char** s = (char**)obj;\n")
    r = sbAppend(r, "    int cnt = atoi(s[0]);\n    // search for existing field\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(s[1 + i*2], name) == 0) {\n            s[2 + i*2] = (char*)val;\n            return obj;\n        }\n    }\n")
    r = sbAppend(r, "    // add new field\n    s[1 + cnt*2] = (char*)name;\n    s[2 + cnt*2] = (char*)val;\n    s[0] = kr_itoa(cnt + 1);\n    return obj;\n}\n\nstatic char* kr_getfield(char* obj, const char* name) {\n    if (!obj) return _K_EMPTY;\n")
    r = sbAppend(r, "    char** s = (char**)obj;\n    int cnt = atoi(s[0]);\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(s[1 + i*2], name) == 0) return s[2 + i*2];\n    }\n    return _K_EMPTY;\n}\n\nstatic char* kr_hasfield(char* obj, const char* name) {\n")
    r = sbAppend(r, "    if (!obj) return _K_ZERO;\n    char** s = (char**)obj;\n    int cnt = atoi(s[0]);\n    for (int i = 0; i < cnt; i++) {\n        if (strcmp(s[1 + i*2], name) == 0) return _K_ONE;\n    }\n    return _K_ZERO;\n}\n\n")
    r = sbAppend(r, "static char* kr_structfields(char* obj) {\n    if (!obj) return _K_EMPTY;\n    char** s = (char**)obj;\n    int cnt = atoi(s[0]);\n    if (cnt == 0) return _K_EMPTY;\n    char* out = s[1];\n    for (int i = 1; i < cnt; i++) out = kr_cat(kr_cat(out, \",\"), s[1 + i*2]);\n    return out;\n")
    r = sbAppend(r, "}\n\n")


    // v0.7.5 builtins
    r = sbAppend(r, "static char* kr_mapget(const char* map, const char* key) {\n    if (!*map) return _K_EMPTY;\n    int cnt = kr_listlen(map);\n    for (int i = 0; i < cnt - 1; i += 2) {\n        if (strcmp(kr_split(map, kr_itoa(i)), key) == 0)\n            return kr_split(map, kr_itoa(i + 1));\n    }\n    return _K_EMPTY;\n")
    r = sbAppend(r, "}\n\n")

    r = sbAppend(r, "static char* kr_mapset(const char* map, const char* key, const char* val) {\n    if (!*map) return kr_cat(kr_cat(kr_str(key), \",\"), val);\n    int cnt = kr_listlen(map);\n    char* out = _K_EMPTY; int first = 1; int found = 0;\n    for (int i = 0; i < cnt - 1; i += 2) {\n        char* k = kr_split(map, kr_itoa(i));\n        char* v = (strcmp(k, key) == 0) ? (char*)val : kr_split(map, kr_itoa(i+1));\n        if (strcmp(k, key) == 0) found = 1;\n")
    r = sbAppend(r, "        if (first) { out = kr_cat(k, kr_cat(\",\", v)); first = 0; }\n        else out = kr_cat(out, kr_cat(\",\", kr_cat(k, kr_cat(\",\", v))));\n    }\n    if (!found) {\n        if (first) out = kr_cat(kr_str(key), kr_cat(\",\", val));\n        else out = kr_cat(out, kr_cat(\",\", kr_cat(kr_str(key), kr_cat(\",\", val))));\n    }\n    return out;\n")
    r = sbAppend(r, "}\n\n")

    r = sbAppend(r, "static char* kr_mapdel(const char* map, const char* key) {\n    if (!*map) return _K_EMPTY;\n    int cnt = kr_listlen(map);\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt - 1; i += 2) {\n        char* k = kr_split(map, kr_itoa(i));\n        if (strcmp(k, key) != 0) {\n            char* v = kr_split(map, kr_itoa(i+1));\n")
    r = sbAppend(r, "            if (first) { out = kr_cat(k, kr_cat(\",\", v)); first = 0; }\n            else out = kr_cat(out, kr_cat(\",\", kr_cat(k, kr_cat(\",\", v))));\n        }\n    }\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_sprintf(const char* fmt, ...) {\n    char buf[4096];\n    va_list args;\n    va_start(args, fmt);\n    vsnprintf(buf, sizeof(buf), fmt, args);\n    va_end(args);\n    return kr_str(buf);\n}\n\n")

    r = sbAppend(r, "static char* kr_strsplit(const char* s, const char* delim) {\n    return kr_splitby(s, delim);\n}\n\n")

    r = sbAppend(r, "static char* kr_listmap(const char* lst, const char* prefix, const char* suffix) {\n    if (!*lst) return _K_EMPTY;\n    int cnt = kr_listlen(lst);\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i++) {\n        char* item = kr_split(lst, kr_itoa(i));\n        char* mapped = kr_cat(kr_cat(kr_str(prefix), item), suffix);\n        if (first) { out = mapped; first = 0; }\n")
    r = sbAppend(r, "        else out = kr_cat(out, kr_cat(\",\", mapped));\n    }\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_listfilter(const char* lst, const char* val) {\n    if (!*lst) return _K_EMPTY;\n    int cnt = kr_listlen(lst), negate = 0;\n    const char* match = val;\n    if (val[0] == '!') { negate = 1; match = val + 1; }\n    char* out = _K_EMPTY; int first = 1;\n    for (int i = 0; i < cnt; i++) {\n        char* item = kr_split(lst, kr_itoa(i));\n")
    r = sbAppend(r, "        int eq = (strcmp(item, match) == 0);\n        int keep = negate ? !eq : eq;\n        if (keep) {\n            if (first) { out = item; first = 0; }\n            else out = kr_cat(out, kr_cat(\",\", item));\n        }\n    }\n    return out;\n")
    r = sbAppend(r, "}\n\n")


    // v0.8.6 float support
    r = sbAppend(r, "#include <math.h>\nstatic char* kr_tofloat(const char* s) {\n    return s;\n}\n\nstatic char* kr_fadd(const char* a,const char* b){char buf[64];snprintf(buf,64,\"%g\",atof(a)+atof(b));return kr_str(buf);}\nstatic char* kr_fsub(const char* a,const char* b){char buf[64];snprintf(buf,64,\"%g\",atof(a)-atof(b));return kr_str(buf);}\nstatic char* kr_fmul(const char* a,const char* b){char buf[64];snprintf(buf,64,\"%g\",atof(a)*atof(b));return kr_str(buf);}\nstatic char* kr_fdiv(const char* a,const char* b){char buf[64];if(atof(b)==0.0)return kr_str(\"0\");snprintf(buf,64,\"%g\",atof(a)/atof(b));return kr_str(buf);}\n")
    r = sbAppend(r, "static char* kr_flt(const char* a,const char* b){return atof(a)<atof(b)?_K_ONE:_K_ZERO;}\nstatic char* kr_fgt(const char* a,const char* b){return atof(a)>atof(b)?_K_ONE:_K_ZERO;}\nstatic char* kr_feq(const char* a,const char* b){return atof(a)==atof(b)?_K_ONE:_K_ZERO;}\nstatic char* kr_fsqrt(const char* a) {\n    char buf[64]; snprintf(buf,64,\"%g\",sqrt(atof(a)));\n    return kr_str(buf);\n}\n\nstatic char* kr_ffloor(const char* a) {\n")
    r = sbAppend(r, "    char buf[64]; snprintf(buf,64,\"%.0f\",floor(atof(a)));\n    return kr_str(buf);\n}\n\nstatic char* kr_fceil(const char* a) {\n    char buf[64]; snprintf(buf,64,\"%.0f\",ceil(atof(a)));\n    return kr_str(buf);\n}\n\nstatic char* kr_fround(const char* a) {\n")
    r = sbAppend(r, "    char buf[64]; snprintf(buf,64,\"%.0f\",round(atof(a)));\n    return kr_str(buf);\n}\n\nstatic char* kr_fformat(const char* a,const char* prec){char fmt[32],buf[64];snprintf(fmt,32,\"%%.%sf\",prec);snprintf(buf,64,fmt,atof(a));return kr_str(buf);}\n")

    // bitwise and 64-bit builtins
    r = sbAppend(r, "static char* kr_bitand(const char* a,const char* b){return kr_itoa((int)((unsigned int)atoi(a)&(unsigned int)atoi(b)));}\n")
    r = sbAppend(r, "static char* kr_bitor(const char* a,const char* b){return kr_itoa((int)((unsigned int)atoi(a)|(unsigned int)atoi(b)));}\n")
    r = sbAppend(r, "static char* kr_bitxor(const char* a,const char* b){return kr_itoa((int)((unsigned int)atoi(a)^(unsigned int)atoi(b)));}\n")
    r = sbAppend(r, "static char* kr_bitnot(const char* a){return kr_itoa((int)(~(unsigned int)atoi(a)));}\n")
    r = sbAppend(r, "static char* kr_bitshl(const char* a,const char* b){return kr_itoa((int)((unsigned int)atoi(a)<<atoi(b)));}\n")
    r = sbAppend(r, "static char* kr_bitshr(const char* a,const char* b){return kr_itoa((int)((unsigned int)atoi(a)>>atoi(b)));}\n")
    r = sbAppend(r, "static char* kr_tolong(const char* s){char buf[32];snprintf(buf,32,\"%lld\",(long long)atoll(s));return kr_str(buf);}\n")
    r = sbAppend(r, "static char* kr_div64(const char* a,const char* b){if(atoll(b)==0)return kr_str(\"0\");char buf[32];snprintf(buf,32,\"%lld\",atoll(a)/atoll(b));return kr_str(buf);}\n")
    r = sbAppend(r, "static char* kr_mod64(const char* a,const char* b){if(atoll(b)==0)return kr_str(\"0\");char buf[32];long long r2=atoll(a)%atoll(b);snprintf(buf,32,\"%lld\",r2);return kr_str(buf);}\n")
    r = sbAppend(r, "static char* kr_mul64(const char* a,const char* b){char buf[32];snprintf(buf,32,\"%lld\",atoll(a)*atoll(b));return kr_str(buf);}\n")
    r = sbAppend(r, "static char* kr_add64(const char* a,const char* b){char buf[32];snprintf(buf,32,\"%lld\",atoll(a)+atoll(b));return kr_str(buf);}\n")
    r = sbAppend(r, "static char* kr_eqignorecase(const char* a,const char* b){return _stricmp(a,b)==0?kr_str(\"1\"):kr_str(\"0\");}\n")
    r = sbAppend(r, "static char* kr_handlevalid(const char* h){return (h!=NULL&&h!=(char*)(intptr_t)-1)?kr_str(\"1\"):kr_str(\"0\");}\n")

    // v1.1.3 buffer / handle builtins
    r = sbAppend(r, "static char* kr_bufgetdword(char* buf){unsigned int v=*(unsigned int*)buf;return kr_itoa((int)v);}\n")
    r = sbAppend(r, "static char* kr_bufsetdword(char* buf,const char* vs){*(unsigned int*)buf=(unsigned int)atoi(vs);return _K_EMPTY;}\n")
    r = sbAppend(r, "static char* kr_bufgetword(char* buf){return kr_itoa((int)(*(unsigned short*)buf));}\n")
    r = sbAppend(r, "static char* kr_bufgetqword(char* buf){unsigned long long v=*(unsigned long long*)buf;char s[32];snprintf(s,32,\"%llu\",v);return kr_str(s);}\n")
    r = sbAppend(r, "static char* kr_bufgetdwordat(char* buf,const char* off){unsigned int v=*(unsigned int*)(buf+atoi(off));return kr_itoa((int)v);}\n")
    r = sbAppend(r, "static char* kr_bufgetqwordat(char* buf,const char* off){unsigned long long v=*(unsigned long long*)(buf+atoi(off));char s[32];snprintf(s,32,\"%llu\",v);return kr_str(s);}\n")
    r = sbAppend(r, "static char* kr_bufsetbyte(char* buf,const char* off,const char* val){buf[atoi(off)]=(unsigned char)atoi(val);return _K_EMPTY;}\n")
    r = sbAppend(r, "static char* kr_bufsetdwordat(char* buf,const char* off,const char* val){*(unsigned int*)(buf+atoi(off))=(unsigned int)atoll(val);return _K_EMPTY;}\n")
    r = sbAppend(r, "static char* kr_handleget(char* buf){return *(char**)buf;}\n")
    r = sbAppend(r, "static char* kr_handleint(char* ptr){char s[32];snprintf(s,32,\"%d\",(int)(intptr_t)ptr);return kr_str(s);}\n")
    r = sbAppend(r, "static char* kr_ptrderef(char* ptr){return *(char**)ptr;}\n")
    r = sbAppend(r, "static char* kr_ptrindex(char* ptr,const char* n){return ((char**)ptr)[atoi(n)];}\n")
    r = sbAppend(r, "static char* kr_callptr1(char* fn,char* a0){return ((char*(*)(char*))(fn))(a0);}\n")
    r = sbAppend(r, "static char* kr_callptr2(char* fn,char* a0,char* a1){return ((char*(*)(char*,char*))(fn))(a0,a1);}\n")
    r = sbAppend(r, "static char* kr_callptr3(char* fn,char* a0,char* a1,char* a2){return ((char*(*)(char*,char*,char*))(fn))(a0,a1,a2);}\n")
    r = sbAppend(r, "static char* kr_callptr4(char* fn,char* a0,char* a1,char* a2,char* a3){return ((char*(*)(char*,char*,char*,char*))(fn))(a0,a1,a2,a3);}\n")

    // Closure support
    r = sbAppend(r, "static char* kr_mkclosure(const char* fn,const char* env){")
    r = sbAppend(r, "int fl=strlen(fn),el=strlen(env);char* p=_alloc(fl+el+2);")
    r = sbAppend(r, "memcpy(p,fn,fl);p[fl]='|';memcpy(p+fl+1,env,el+1);return p;}\n")
    r = sbAppend(r, "static char* kr_closure_fn(const char* c){")
    r = sbAppend(r, "const char* p=strchr(c,'|');if(!p)return(char*)c;")
    r = sbAppend(r, "int n=p-c;char* r2=_alloc(n+1);memcpy(r2,c,n);r2[n]=0;return r2;}\n")
    r = sbAppend(r, "static char* kr_closure_env(const char* c){")
    r = sbAppend(r, "const char* p=strchr(c,'|');return p?(char*)(p+1):(char*)_K_EMPTY;}\n")
    emit sbToString(r)
}

// =============================================
// Main: compile a .k file to C
// =============================================


// ── Module System ─────────────────────────────────────────────

// scanFunctionsInTokens: like scanFunctions but handles "go name { func... }"
// Returns same ftable format
func scanModuleFunctions(tokens, ntoks) {
    // First check if there's a "go name {" wrapper
    // If so, find the LBRACE and scan functions inside it
    let i = 0
    let bodyStart = 0
    let hasWrapper = 0
    while i < ntoks {
        let tok = tokAt(tokens, i)
        if tok == "KW:go" {
            // go name { -- check if next two are ID and LBRACE
            if i + 2 < ntoks {
                if tokType(tokAt(tokens, i + 1)) == "ID" {
                    if tokAt(tokens, i + 2) == "LBRACE" {
                        bodyStart = i + 2
                        hasWrapper = 1
                    }
                }
            }
        }
        i += 1
    }
    // Scan functions from bodyStart (works whether wrapper or not)
    emit scanFunctions(tokens, ntoks)
}

// compileImportedFunctions: compile all func bodies from a token stream
// Handles both flat files and "go name { func... }" wrapped files
// Returns C code string
func compileImportedFunctions(tokens, ntoks, ftable) {
    let sb = sbNew()
    let i = 0
    // Detect "go name {" wrapper - if found, skip into body
    let inWrapper = 0
    let depth = 0
    while i < ntoks {
        let tok = tokAt(tokens, i)
        if tok == "KW:go" {
            if i + 2 < ntoks {
                if tokType(tokAt(tokens, i + 1)) == "ID" {
                    if tokAt(tokens, i + 2) == "LBRACE" {
                        // skip: go, name, LBRACE
                        i = i + 3
                        inWrapper = 1
                    }
                }
            }
        }
        // compile func declarations (skip jxt blocks)
        if tok == "KW:jxt" {
            // skip entire jxt block - headers handle their own declarations
            i = skipBlock(tokens, i + 1)
        } else if tok == "KW:func" || tok == "KW:fn" {
            let fp = compileFunc(tokens, i, ntoks)
            sb = sbAppend(sb, pairVal(fp))
            i = pairPos(fp)
        } else if tok == "KW:callback" {
            // callback func name(params) { body } — compiles to void C function
            let fp = compileCallbackFunc(tokens, i + 1, ntoks)
            sb = sbAppend(sb, pairVal(fp))
            i = pairPos(fp)
        } else if tok == "KW:export" {
            // export func ... -- skip the export keyword, compile the func
            i += 1
        } else {
            i += 1
        }
    }
    emit sbToString(sb)
}

// compileImportedForwardDecls: emit forward declarations from imported file
func compileImportedForwardDecls(tokens, ntoks, ftable) {
    let sb = sbNew()
    let i = 0
    while i < ntoks {
        let tok = tokAt(tokens, i)
        if tok == "KW:func" || tok == "KW:fn" {
            let nameTok = tokAt(tokens, i + 1)
            let fname = tokVal(nameTok)
            let info = funcLookup(ftable, fname)
            let pc = funcParamCount(info)
            let decl = "char* " + cIdent(fname) + "("
            let pi = 0
            while pi < pc {
                if pi > 0 { decl = decl + ", " }
                decl = decl + "char*"
                pi += 1
            }
            decl = decl + ");\n"
            sb = sbAppend(sb, decl)
            // skip to end of function
            let fp = skipBlock(tokens, i + 3 + pc * 2)
            i = fp
        } else if tok == "KW:export" {
            i += 1
        } else {
            i += 1
        }
    }
    emit sbToString(sb)
}


// ── Krypton IR Emitter ──────────────────────────────────────────
// Emits .kir (Krypton Intermediate Representation) instead of C.
// One instruction per line. Stack-based virtual machine model.
//
// Usage: kcc --ir source.k > source.kir
//
// Instruction set:
//   FUNC name argc     - define function
//   PARAM name         - declare parameter (in order)
//   LOCAL name         - declare local variable
//   CONST name value   - string constant
//   LOAD name          - push variable value onto stack
//   STORE name         - pop stack, store in variable
//   CALL name argc     - call user function
//   BUILTIN name argc  - call builtin function
//   PUSH value         - push literal string value
//   ADD SUB MUL DIV MOD NEG NOT - arithmetic/logic
//   EQ NEQ LT GT LTE GTE AND OR - comparison
//   CAT                - string concatenation
//   JUMP label         - unconditional branch
//   JUMPIF label       - branch if stack top truthy
//   JUMPIFNOT label    - branch if stack top falsy
//   LABEL name         - branch target
//   RETURN             - return top of stack
//   END                - end function
//   GETFIELD name      - get struct field by name
//   SETFIELD name      - set struct field by name
//   STRUCTNEW          - create new dynamic struct
//   INDEX              - string/list index

// IR label counter for unique labels
func irLabel(prefix, n) {
    emit prefix + "_" + n
}

// IR emitter for expressions - returns IR text + new label counter
func irExpr(tokens, pos, ntoks, lc) {
    emit irTernary(tokens, pos, ntoks, lc)
}

func irTernary(tokens, pos, ntoks, lc) {
    let pair = irOr(tokens, pos, ntoks, lc)
    let code = pairVal(pair)
    let p = pairPos(pair)
    let nlc = lc
    if tokAt(tokens, p) == "QUESTION" {
        let trueLabel = irLabel("_tern_t", p)
        let endLabel = irLabel("_tern_e", p)
        nlc = nlc + 1
        let tp = irExpr(tokens, p + 1, ntoks, nlc)
        let tcode = pairVal(tp)
        p = pairPos(tp)
        nlc = nlc + 1
        // skip COLON
        p = p + 1
        let fp = irExpr(tokens, p, ntoks, nlc)
        let fcode = pairVal(fp)
        p = pairPos(fp)
        nlc = nlc + 1
        let out = code + "JUMPIFNOT " + trueLabel + "\n" + tcode + "JUMP " + endLabel + "\n" + "LABEL " + trueLabel + "\n" + fcode + "LABEL " + endLabel + "\n"
        emit out + "," + p
    }
    emit code + "," + p
}

func irOr(tokens, pos, ntoks, lc) {
    let pair = irAnd(tokens, pos, ntoks, lc)
    let code = pairVal(pair)
    let p = pairPos(pair)
    let nlc = lc
    while tokAt(tokens, p) == "OR" {
        let shortLabel = irLabel("_or", p)
        nlc = nlc + 1
        let rp = irAnd(tokens, p + 1, ntoks, nlc)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        code = code + "JUMPIF " + shortLabel + "\n" + rcode + "LABEL " + shortLabel + "\n"
    }
    emit code + "," + p
}

func irAnd(tokens, pos, ntoks, lc) {
    let pair = irEquality(tokens, pos, ntoks, lc)
    let code = pairVal(pair)
    let p = pairPos(pair)
    let nlc = lc
    while tokAt(tokens, p) == "AND" {
        let shortLabel = irLabel("_and", p)
        nlc = nlc + 1
        let rp = irEquality(tokens, p + 1, ntoks, nlc)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        code = code + "JUMPIFNOT " + shortLabel + "\n" + rcode + "LABEL " + shortLabel + "\n"
    }
    emit code + "," + p
}

func irEquality(tokens, pos, ntoks, lc) {
    let pair = irRelational(tokens, pos, ntoks, lc)
    let code = pairVal(pair)
    let p = pairPos(pair)
    while tokAt(tokens, p) == "EQ" || tokAt(tokens, p) == "NEQ" {
        let op = tokAt(tokens, p)
        let rp = irRelational(tokens, p + 1, ntoks, lc)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        if op == "EQ" { code = code + rcode + "EQ\n" }
        else { code = code + rcode + "NEQ\n" }
    }
    emit code + "," + p
}

func irRelational(tokens, pos, ntoks, lc) {
    let pair = irAdditive(tokens, pos, ntoks, lc)
    let code = pairVal(pair)
    let p = pairPos(pair)
    while tokAt(tokens, p) == "LT" || tokAt(tokens, p) == "GT" || tokAt(tokens, p) == "LTE" || tokAt(tokens, p) == "GTE" {
        let op = tokAt(tokens, p)
        let rp = irAdditive(tokens, p + 1, ntoks, lc)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        if op == "LT" { code = code + rcode + "LT\n" }
        if op == "GT" { code = code + rcode + "GT\n" }
        if op == "LTE" { code = code + rcode + "LTE\n" }
        if op == "GTE" { code = code + rcode + "GTE\n" }
    }
    emit code + "," + p
}

func irAdditive(tokens, pos, ntoks, lc) {
    let pair = irMultiplicative(tokens, pos, ntoks, lc)
    let code = pairVal(pair)
    let p = pairPos(pair)
    while tokAt(tokens, p) == "PLUS" || tokAt(tokens, p) == "MINUS" {
        let op = tokAt(tokens, p)
        let rp = irMultiplicative(tokens, p + 1, ntoks, lc)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        if op == "PLUS" { code = code + rcode + "ADD\n" }
        else { code = code + rcode + "SUB\n" }
    }
    emit code + "," + p
}

func irMultiplicative(tokens, pos, ntoks, lc) {
    let pair = irUnary(tokens, pos, ntoks, lc)
    let code = pairVal(pair)
    let p = pairPos(pair)
    while tokAt(tokens, p) == "STAR" || tokAt(tokens, p) == "SLASH" || tokAt(tokens, p) == "MOD" {
        let op = tokAt(tokens, p)
        let rp = irUnary(tokens, p + 1, ntoks, lc)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        if op == "STAR" { code = code + rcode + "MUL\n" }
        if op == "SLASH" { code = code + rcode + "DIV\n" }
        if op == "MOD" { code = code + rcode + "MOD\n" }
    }
    emit code + "," + p
}

func irUnary(tokens, pos, ntoks, lc) {
    let tok = tokAt(tokens, pos)
    if tok == "MINUS" {
        let pair = irUnary(tokens, pos + 1, ntoks, lc)
        let code = pairVal(pair)
        let p = pairPos(pair)
        emit code + "NEG\n," + p
    }
    if tok == "BANG" {
        let pair = irUnary(tokens, pos + 1, ntoks, lc)
        let code = pairVal(pair)
        let p = pairPos(pair)
        emit code + "NOT\n," + p
    }
    emit irPostfix(tokens, pos, ntoks, lc)
}

func irPostfix(tokens, pos, ntoks, lc) {
    let pair = irPrimary(tokens, pos, ntoks, lc)
    let code = pairVal(pair)
    let p = pairPos(pair)
    while tokAt(tokens, p) == "LBRACK" || tokAt(tokens, p) == "DOT" {
        if tokAt(tokens, p) == "LBRACK" {
            let idxp = irExpr(tokens, p + 1, ntoks, lc)
            let idxcode = pairVal(idxp)
            p = pairPos(idxp) + 1
            code = code + idxcode + "INDEX\n"
        } else {
            let field = tokVal(tokAt(tokens, p + 1))
            p = p + 2
            code = code + "GETFIELD " + field + "\n"
        }
    }
    emit code + "," + p
}

func irPrimary(tokens, pos, ntoks, lc) {
    let tok = tokAt(tokens, pos)
    let tt = tokType(tok)
    let tv = tokVal(tok)

    // Integer/float literal
    if tt == "INT" {
        emit "PUSH " + tv + "\n," + (pos + 1)
    }

    // String literal
    if tt == "STR" {
        // escape newlines in the IR for safe storage
        let escaped = replace(replace(tv, "\\n", "\\\\n"), "\\t", "\\\\t")
        emit "PUSH \"" + escaped + "\"\n," + (pos + 1)
    }

    // Backtick interpolation - emit as PUSH + CAT chain
    if tt == "INTERP" {
        emit irInterpToIR(tv, pos) + "," + (pos + 1)
    }

    // Boolean
    if tok == "KW:true" {
        emit "PUSH 1\n," + (pos + 1)
    }
    if tok == "KW:false" {
        emit "PUSH 0\n," + (pos + 1)
    }

    // Grouped expression
    if tok == "LPAREN" {
        let pair = irExpr(tokens, pos + 1, ntoks, lc)
        let code = pairVal(pair)
        let p = pairPos(pair)
        emit code + "," + (p + 1)
    }

    // List literal [a, b, c]
    if tok == "LBRACK" {
        emit irListLiteralIR(tokens, pos, ntoks, lc)
    }

    // Identifier - function call or variable
    if tt == "ID" {
        let nextTok = tokAt(tokens, pos + 1)
        if nextTok == "LPAREN" {
            emit irCall(tokens, pos, ntoks, lc)
        }
        // Struct literal: Name { field: val }
        let firstChar = tv[0]
        if nextTok == "LBRACE" {
            if firstChar >= "A" && firstChar <= "Z" {
                emit irStructLiteralIR(tokens, pos, ntoks, lc)
            }
        }
        // Plain variable load
        emit "LOAD " + tv + "\n," + (pos + 1)
    }

    emit "PUSH \"\"\n," + (pos + 1)
}

func irInterpToIR(s, pos) {
    let code = ""
    let i = 0
    let seg = ""
    let parts = 0
    while i < len(s) {
        if s[i] == "{" {
            if len(seg) > 0 {
                code = code + "PUSH \"" + seg + "\"\n"
                if parts > 0 { code = code + "CAT\n" }
                parts += 1
                seg = ""
            }
            i += 1
            let expr = ""
            while i < len(s) && s[i] != "}" {
                expr = expr + s[i]
                i += 1
            }
            i += 1
            code = code + "LOAD " + expr + "\n"
            if parts > 0 { code = code + "CAT\n" }
            parts += 1
        } else {
            seg = seg + s[i]
            i += 1
        }
    }
    if len(seg) > 0 {
        code = code + "PUSH \"" + seg + "\"\n"
        if parts > 0 { code = code + "CAT\n" }
        parts += 1
    }
    if parts == 0 { emit "PUSH \"\"\n" }
    emit code
}

func irListLiteralIR(tokens, pos, ntoks, lc) {
    let p = pos + 1
    if tokAt(tokens, p) == "RBRACK" {
        emit "PUSH \"\"\n," + (p + 1)
    }
    let code = ""
    let ec = 0
    while tokAt(tokens, p) != "RBRACK" {
        if ec > 0 { p = p + 1 }
        let ep = irExpr(tokens, p, ntoks, lc)
        let ecode = pairVal(ep)
        p = pairPos(ep)
        if ec > 0 {
            code = code + ecode + "PUSH \",\"\nCAT\nCAT\n"
        } else {
            code = ecode
        }
        ec += 1
    }
    emit code + "," + (p + 1)
}

func irStructLiteralIR(tokens, pos, ntoks, lc) {
    let name = tokVal(tokAt(tokens, pos))
    let p = pos + 2
    let code = "STRUCTNEW\n"
    while tokAt(tokens, p) != "RBRACE" {
        if tokType(tokAt(tokens, p)) == "ID" {
            let fname = tokVal(tokAt(tokens, p))
            p = p + 2
            let ep = irExpr(tokens, p, ntoks, lc)
            let ecode = pairVal(ep)
            p = pairPos(ep)
            if tokAt(tokens, p) == "COMMA" { p += 1 }
            code = code + ecode + "SETFIELD " + fname + "\n"
        } else { p += 1 }
    }
    emit code + "," + (p + 1)
}

func irCall(tokens, pos, ntoks, lc) {
    let fname = tokVal(tokAt(tokens, pos))
    let p = pos + 2
    let code = ""
    let argc = 0
    while tokAt(tokens, p) != "RPAREN" {
        if argc > 0 { p += 1 }
        let ap = irExpr(tokens, p, ntoks, lc)
        code = code + pairVal(ap)
        p = pairPos(ap)
        argc += 1
    }
    // builtins vs user functions
    let builtins = "print,kp,printErr,readLine,input,readFile,writeFile,arg,argCount,len,substring,charAt,indexOf,contains,startsWith,endsWith,replace,trim,lstrip,rstrip,center,toLower,toUpper,repeat,padLeft,padRight,charCode,fromCharCode,splitBy,format,strReverse,isAlpha,isDigit,isSpace,toInt,parseInt,abs,min,max,pow,sqrt,sign,clamp,hex,bin,floor,ceil,round,split,length,first,last,head,tail,append,join,reverse,sort,unique,fill,zip,slice,listIndexOf,every,some,countOf,sumList,maxList,minList,range,words,lines,keys,values,hasKey,structNew,getField,setField,hasField,structFields,random,timestamp,environ,exit,assert,type,isTruthy,toStr,throw,mapGet,mapSet,mapDel,fadd,fsub,fmul,fdiv,fsqrt,ffloor,fceil,fround,fformat,flt,fgt,feq,sbNew,sbAppend,sbToString,bufNew,bufStr,bufGetDword,bufSetDword,bufGetWord,bufGetQword,bufGetDwordAt,bufGetQwordAt,bufSetByte,bufSetDwordAt,handleOut,handleGet,handleInt,toHandle,ptrDeref,ptrIndex,callPtr"
    if contains(builtins, fname) {
        emit code + "BUILTIN " + fname + " " + argc + "\n," + (p + 1)
    }
    emit code + "CALL " + fname + " " + argc + "\n," + (p + 1)
}

// IR statement emitter
func irStmt(tokens, pos, ntoks, lc, inFunc) {
    let tok = tokAt(tokens, pos)
    let tt = tokType(tok)

    // let/const declaration
    if tok == "KW:let" || tok == "KW:const" {
        emit irLetIR(tokens, pos + 1, ntoks, lc, inFunc)
    }

    // emit/return
    if tok == "KW:emit" || tok == "KW:return" {
        let pair = irExpr(tokens, pos + 1, ntoks, lc)
        let code = pairVal(pair)
        let p = pairPos(pair)
        if tokAt(tokens, p) == "SEMI" { p += 1 }
        emit code + "RETURN\n," + p
    }

    // if statement
    if tok == "KW:if" {
        emit irIfIR(tokens, pos + 1, ntoks, lc, inFunc)
    }

    // while loop
    if tok == "KW:while" {
        emit irWhileIR(tokens, pos + 1, ntoks, lc, inFunc)
    }

    // for-in loop
    if tok == "KW:for" {
        emit irForIR(tokens, pos + 1, ntoks, lc, inFunc)
    }

    // match
    if tok == "KW:match" {
        emit irMatchIR(tokens, pos + 1, ntoks, lc, inFunc)
    }

    // break
    if tok == "KW:break" {
        let p = pos + 1
        if tokAt(tokens, p) == "SEMI" { p += 1 }
        emit "BREAK\n," + p
    }

    // continue
    if tok == "KW:continue" {
        let p = pos + 1
        if tokAt(tokens, p) == "SEMI" { p += 1 }
        emit "CONTINUE\n," + p
    }

    // try/catch/throw
    if tok == "KW:throw" {
        let pair = irExpr(tokens, pos + 1, ntoks, lc)
        let code = pairVal(pair)
        let p = pairPos(pair)
        if tokAt(tokens, p) == "SEMI" { p += 1 }
        emit code + "THROW\n," + p
    }

    if tok == "KW:try" {
        emit irTryIR(tokens, pos + 1, ntoks, lc, inFunc)
    }

    // field assignment: ID DOT ID ASSIGN
    if tt == "ID" {
        if tokAt(tokens, pos + 1) == "DOT" {
            if tokType(tokAt(tokens, pos + 2)) == "ID" {
                if tokAt(tokens, pos + 3) == "ASSIGN" {
                    let objName = tokVal(tok)
                    let field = tokVal(tokAt(tokens, pos + 2))
                    let pair = irExpr(tokens, pos + 4, ntoks, lc)
                    let code = pairVal(pair)
                    let p = pairPos(pair)
                    if tokAt(tokens, p) == "SEMI" { p += 1 }
                    emit "LOAD " + objName + "\n" + code + "SETFIELD " + field + "\nSTORE " + objName + "\n," + p
                }
            }
        }
    }

    // compound assignment
    if tt == "ID" {
        let nt = tokAt(tokens, pos + 1)
        if nt == "PLUSEQ" || nt == "MINUSEQ" || nt == "STAREQ" || nt == "SLASHEQ" || nt == "MODEQ" {
            let name = tokVal(tok)
            let pair = irExpr(tokens, pos + 2, ntoks, lc)
            let rcode = pairVal(pair)
            let p = pairPos(pair)
            if tokAt(tokens, p) == "SEMI" { p += 1 }
            let op = "ADD\n"
            if nt == "MINUSEQ" { op = "SUB\n" }
            if nt == "STAREQ"  { op = "MUL\n" }
            if nt == "SLASHEQ" { op = "DIV\n" }
            if nt == "MODEQ"   { op = "MOD\n" }
            emit "LOAD " + name + "\n" + rcode + op + "STORE " + name + "\n," + p
        }
    }

    // plain assignment
    if tt == "ID" && tokAt(tokens, pos + 1) == "ASSIGN" {
        let name = tokVal(tok)
        let pair = irExpr(tokens, pos + 2, ntoks, lc)
        let code = pairVal(pair)
        let p = pairPos(pair)
        if tokAt(tokens, p) == "SEMI" { p += 1 }
        emit code + "STORE " + name + "\n," + p
    }

    // expression statement (function call)
    let pair = irExpr(tokens, pos, ntoks, lc)
    let code = pairVal(pair)
    let p = pairPos(pair)
    if tokAt(tokens, p) == "SEMI" { p += 1 }
    emit code + "POP\n," + p
}

func irLetIR(tokens, pos, ntoks, lc, inFunc) {
    let name = tokVal(tokAt(tokens, pos))
    let p = pos + 1
    // skip optional type annotation
    if tokAt(tokens, p) == "COLON" {
        p = p + 2
        if tokAt(tokens, p) == "LBRACK" {
            p += 1
            while tokAt(tokens, p) != "RBRACK" { p += 1 }
            p += 1
        }
    }
    // skip ASSIGN
    p += 1
    let pair = irExpr(tokens, p, ntoks, lc)
    let code = pairVal(pair)
    p = pairPos(pair)
    if tokAt(tokens, p) == "SEMI" { p += 1 }
    emit "LOCAL " + name + "\n" + code + "STORE " + name + "\n," + p
}

func irBlockIR(tokens, pos, ntoks, lc, inFunc) {
    // pos is at LBRACE
    let p = pos + 1
    let sbBlock = sbNew()
    let nlc = lc
    while tokAt(tokens, p) != "RBRACE" {
        let sp = irStmt(tokens, p, ntoks, nlc, inFunc)
        sbBlock = sbAppend(sbBlock, pairVal(sp))
        p = pairPos(sp)
        nlc = nlc + 1
    }
    emit sbToString(sbBlock) + "," + (p + 1)
}

func irIfIR(tokens, pos, ntoks, lc, inFunc) {
    let pair = irExpr(tokens, pos, ntoks, lc)
    let condCode = pairVal(pair)
    let p = pairPos(pair)
    let elseLabel = irLabel("_else", pos)
    let endLabel = irLabel("_endif", pos)
    let nlc = lc + 1
    let bp = irBlockIR(tokens, p, ntoks, nlc, inFunc)
    let bodyCode = pairVal(bp)
    p = pairPos(bp)
    nlc = nlc + 1
    if tokAt(tokens, p) == "KW:else" {
        if tokAt(tokens, p + 1) == "KW:if" {
            let ep = irIfIR(tokens, p + 2, ntoks, nlc, inFunc)
            let elseCode = pairVal(ep)
            p = pairPos(ep)
            emit condCode + "JUMPIFNOT " + elseLabel + "\n" + bodyCode + "JUMP " + endLabel + "\n" + "LABEL " + elseLabel + "\n" + elseCode + "LABEL " + endLabel + "\n," + p
        } else {
            let ep = irBlockIR(tokens, p + 1, ntoks, nlc, inFunc)
            let elseCode = pairVal(ep)
            p = pairPos(ep)
            emit condCode + "JUMPIFNOT " + elseLabel + "\n" + bodyCode + "JUMP " + endLabel + "\n" + "LABEL " + elseLabel + "\n" + elseCode + "LABEL " + endLabel + "\n," + p
        }
    }
    emit condCode + "JUMPIFNOT " + endLabel + "\n" + bodyCode + "LABEL " + endLabel + "\n," + p
}

func irWhileIR(tokens, pos, ntoks, lc, inFunc) {
    let loopLabel = irLabel("_wloop", pos)
    let endLabel = irLabel("_wend", pos)
    let nlc = lc + 1
    let pair = irExpr(tokens, pos, ntoks, nlc)
    let condCode = pairVal(pair)
    let p = pairPos(pair)
    let bp = irBlockIR(tokens, p, ntoks, nlc, inFunc)
    let bodyCode = pairVal(bp)
    p = pairPos(bp)
    emit "LABEL " + loopLabel + "\n" + condCode + "JUMPIFNOT " + endLabel + "\n" + bodyCode + "JUMP " + loopLabel + "\n" + "LABEL " + endLabel + "\n," + p
}

func irForIR(tokens, pos, ntoks, lc, inFunc) {
    let varName = tokVal(tokAt(tokens, pos))
    let p = pos + 2
    let pair = irExpr(tokens, p, ntoks, lc)
    let collCode = pairVal(pair)
    p = pairPos(pair)
    let loopLabel = irLabel("_floop", pos)
    let endLabel = irLabel("_fend", pos)
    let idxVar = "_for_i_" + pos
    let cntVar = "_for_cnt_" + pos
    let colVar = "_for_col_" + pos
    let nlc = lc + 1
    let bp = irBlockIR(tokens, p, ntoks, nlc, inFunc)
    let bodyCode = pairVal(bp)
    p = pairPos(bp)
    let code = collCode + "LOCAL " + colVar + "\n" + "STORE " + colVar + "\n"
    code = code + "LOCAL " + idxVar + "\n" + "PUSH 0\n" + "STORE " + idxVar + "\n"
    code = code + "LOCAL " + cntVar + "\n" + "LOAD " + colVar + "\n" + "BUILTIN length 1\n" + "STORE " + cntVar + "\n"
    code = code + "LABEL " + loopLabel + "\n"
    code = code + "LOAD " + idxVar + "\n" + "LOAD " + cntVar + "\n" + "LT\n"
    code = code + "JUMPIFNOT " + endLabel + "\n"
    code = code + "LOCAL " + varName + "\n"
    code = code + "LOAD " + colVar + "\n" + "LOAD " + idxVar + "\n" + "BUILTIN split 2\n" + "STORE " + varName + "\n"
    code = code + bodyCode
    code = code + "LOAD " + idxVar + "\n" + "PUSH 1\n" + "ADD\n" + "STORE " + idxVar + "\n"
    code = code + "JUMP " + loopLabel + "\n"
    code = code + "LABEL " + endLabel + "\n"
    emit code + "," + p
}

func irMatchIR(tokens, pos, ntoks, lc, inFunc) {
    let pair = irExpr(tokens, pos, ntoks, lc)
    let matchCode = pairVal(pair)
    let p = pairPos(pair) + 1
    let endLabel = irLabel("_mend", pos)
    let matchVar = "_match_" + pos
    let code = matchCode + "STORE " + matchVar + "\n"
    let nlc = lc + 1
    while tokAt(tokens, p) != "RBRACE" {
        let caseLabel = irLabel("_mcase", p)
        let nextLabel = irLabel("_mnext", p)
        nlc = nlc + 1
        if tokAt(tokens, p) == "KW:else" {
            p += 1
            let bp = irBlockIR(tokens, p, ntoks, nlc, inFunc)
            code = code + pairVal(bp)
            p = pairPos(bp)
        } else {
            let cp = irExpr(tokens, p, ntoks, nlc)
            let caseCode = pairVal(cp)
            p = pairPos(cp)
            let bp = irBlockIR(tokens, p, ntoks, nlc, inFunc)
            let bodyCode = pairVal(bp)
            p = pairPos(bp)
            code = code + "LOAD " + matchVar + "\n" + caseCode + "EQ\n" + "JUMPIFNOT " + nextLabel + "\n" + bodyCode + "JUMP " + endLabel + "\n" + "LABEL " + nextLabel + "\n"
        }
        nlc = nlc + 1
    }
    p += 1
    emit code + "LABEL " + endLabel + "\n," + p
}

func irTryIR(tokens, pos, ntoks, lc, inFunc) {
    let catchLabel = irLabel("_catch", pos)
    let endLabel = irLabel("_tryend", pos)
    let nlc = lc + 1
    let bp = irBlockIR(tokens, pos, ntoks, nlc, inFunc)
    let bodyCode = pairVal(bp)
    let p = pairPos(bp)
    if tokAt(tokens, p) == "KW:catch" {
        p += 1
        let catchVar = "_err"
        if tokType(tokAt(tokens, p)) == "ID" {
            catchVar = tokVal(tokAt(tokens, p))
            p += 1
        }
        let cp = irBlockIR(tokens, p, ntoks, nlc, inFunc)
        let catchCode = pairVal(cp)
        p = pairPos(cp)
        emit "TRY " + catchLabel + "\n" + bodyCode + "ENDTRY\n" + "JUMP " + endLabel + "\n" + "LABEL " + catchLabel + "\n" + "LOCAL " + catchVar + "\n" + "STORE " + catchVar + "\n" + catchCode + "LABEL " + endLabel + "\n," + p
    }
    emit "TRY " + catchLabel + "\n" + bodyCode + "ENDTRY\n" + "LABEL " + catchLabel + "\n" + "LABEL " + endLabel + "\n," + p
}

func irFuncIR(tokens, pos, ntoks) {
    // pos is at KW:func
    let fname = tokVal(tokAt(tokens, pos + 1))
    let p = pos + 3
    let params = ""
    let pc = 0
    while tokAt(tokens, p) != "RPAREN" {
        let pt = tokAt(tokens, p)
        if tokType(pt) == "ID" {
            params = params + "PARAM " + tokVal(pt) + "\n"
            pc += 1
            if tokAt(tokens, p + 1) == "COLON" {
                p = p + 3
                if tokAt(tokens, p) == "LBRACK" {
                    p += 1
                    while tokAt(tokens, p) != "RBRACK" { p += 1 }
                    p += 1
                }
                if tokAt(tokens, p) == "COMMA" { p += 1 }
            } else { p += 1 }
        } else { p += 1 }
    }
    p += 1
    // skip -> return type
    if tokAt(tokens, p) == "ARROW" { p = p + 2 }
    let bp = irBlockIR(tokens, p, ntoks, 0, "1")
    let bodyCode = pairVal(bp)
    p = pairPos(bp)
    emit "FUNC " + fname + " " + pc + "\n" + params + bodyCode + "END\n\n," + p
}

func findFreeVars(tokens, bodyStart, bodyEnd, params) {
    // Find free variables: referenced before any local let declaration
    // First pass: collect all let-declared names in body
    let localDecls = params
    let i = bodyStart + 1
    while i < bodyEnd {
        let tok = tokAt(tokens, i)
        if tok == "KW:let" || tok == "KW:const" {
            let lname = tokVal(tokAt(tokens, i + 1))
            if !contains(localDecls, "," + lname + ",") {
                localDecls = localDecls + "," + lname + ","
            }
        }
        i += 1
    }
    // Second pass: find IDs not in localDecls at all
    let freeVars = ""
    i = bodyStart + 1
    while i < bodyEnd {
        let tok = tokAt(tokens, i)
        if tokType(tok) == "ID" {
            let name = tokVal(tok)
            let nextTok = tokAt(tokens, i + 1)
            if nextTok != "LPAREN" {
                if !contains("," + localDecls + ",", "," + name + ",") {
                    if len(name) > 0 && !startsWith(name, "kr_") {
                        if !contains(freeVars, "," + name + ",") {
                            freeVars = freeVars + "," + name + ","
                        }
                    }
                }
            }
        }
        i += 1
    }
    if len(freeVars) > 2 { emit substring(freeVars, 1, len(freeVars) - 1) }
    emit ""
}


just run {
    let kccVer = "1.3.7"

    // Parse flags: --version, --ir, --headers PATH, -o OUTFILE
    let irMode = 0
    let headersDir = ""
    let outFile = ""
    let file = arg("0")
    let argIdx = 0

    if file == "--version" || file == "-v" {
        printErr("kcc version " + kccVer)
        emit 0
    }

    if argCount() == 0 {
        printErr("kcc: no input file")
        printErr("usage: kcc [-o out.exe] [--headers dir] source.k")
        emit 1
    }

    while file == "--ir" || file == "--headers" || file == "-o" {
        if file == "--ir" {
            irMode = 1
            argIdx += 1
        }
        if file == "--headers" {
            argIdx += 1
            headersDir = arg(argIdx + "")
            argIdx += 1
        }
        if file == "-o" {
            argIdx += 1
            outFile = arg(argIdx + "")
            argIdx += 1
        }
        file = arg(argIdx + "")
    }

    // When -o is given, force IR mode internally (pipeline handles the rest)
    if len(outFile) > 0 { irMode = 1 }

    // Default to system headers if --headers not specified
    if headersDir == "" { headersDir = "C:\\krypton\\headers" }

    let source = readFile(file)

    if len(source) == 0 {
        printErr("kcc: cannot read file: " + file)
        emit 1
    }
    let tokens = tokenize(source)
    let ntoks = lineCount(tokens)

    // Resolve base directory for relative imports
    let baseDir = ""
    let lastSlash = 0 - 1
    let fi = 0
    while fi < len(file) {
        if file[fi] == "/" || file[fi] == "\\" {
            lastSlash = fi
        }
        fi += 1
    }
    if lastSlash >= 0 {
        baseDir = substring(file, 0, lastSlash + 1)
    }
    // Scan functions in main file
    let ftable = scanFunctions(tokens, ntoks)

    // Output the C runtime
    let sb = sbNew()
    sb = sbAppend(sb, cRuntime())

    // === IMPORT PROCESSING ===
    // Walk tokens looking for import statements
    // Track imported files to avoid duplicates
    let imported = ""
    let importFwdDecls = ""
    let importBodies = ""
    let importedIR = ""  // accumulated IR from imported files (--ir mode)
    let lambdaBank = ""  // pre-compiled lambda C functions
    let lambdaFreeVars = ""  // lambda pos -> free vars mapping
    let structTable = ""  // extern struct definitions: "NAME:field1:TYPE1,field2:TYPE2\n"

    // Pre-scan: find all lambda expressions and compile them to C
    // Only run if source contains lambda patterns (func( without a name)
    let lsi = 0
    while lsi < ntoks {
        let lsTok = tokAt(tokens, lsi)
        if lsTok == "KW:func" || lsTok == "KW:fn" {
            let prevTok = ""
            if lsi > 0 { prevTok = tokAt(tokens, lsi - 1) }
            let nextTok2 = tokAt(tokens, lsi + 1)
            if (prevTok == "ASSIGN" || prevTok == "LPAREN" || prevTok == "COMMA" || prevTok == "KW:emit" || prevTok == "KW:return" || prevTok == "KW:in") && nextTok2 == "LPAREN" {
                // This is a lambda expression - pre-compile it
                let lp2 = lsi + 2  // past func and LPAREN
                let lparams2 = ""
                let lpc2 = 0
                while tokAt(tokens, lp2) != "RPAREN" {
                    if tokType(tokAt(tokens, lp2)) == "ID" {
                        if lpc2 > 0 { lparams2 = lparams2 + "," }
                        lparams2 = lparams2 + tokVal(tokAt(tokens, lp2))
                        lpc2 += 1
                    }
                    lp2 += 1
                }
                lp2 += 1  // past RPAREN
                if tokAt(tokens, lp2) == "ARROW" { lp2 += 2 }
                // Compile lambda body
                let lbp = compileBlock(tokens, lp2, ntoks, 1, "_krlam" + lsi)
                let lbcode = pairVal(lbp)
                // Build signature with explicit params only
                let lsig = "char* _krlam" + lsi + "(void)"
                if lpc2 > 0 {
                    lsig = "char* _krlam" + lsi + "(char* " + cIdent(getNthParam(lparams2, 0))
                    let lpi2 = 1
                    while lpi2 < lpc2 {
                        lsig = lsig + ", char* " + cIdent(getNthParam(lparams2, lpi2))
                        lpi2 += 1
                    }
                    lsig = lsig + ")"
                }
                // Detect free variables (for static capture)
                let lbodyEnd = skipBlock(tokens, lp2)
                let lfreeVars = findFreeVars(tokens, lp2, lbodyEnd, lparams2)
                let lfvc = 0
                if len(lfreeVars) > 0 { lfvc = lineCount(lfreeVars) }
                let lcapDecls = ""
                let lcapInits = ""
                let lfvi2 = 0
                while lfvi2 < lfvc {
                    let fvn2 = cIdent(split(lfreeVars, lfvi2))
                    lcapDecls = lcapDecls + "static char* _krlam" + lsi + "_" + fvn2 + ";\n"
                    lcapInits = lcapInits + "    char* " + fvn2 + " = _krlam" + lsi + "_" + fvn2 + ";\n"
                    lfvi2 += 1
                }
                lambdaBank = lambdaBank + lcapDecls + "static " + lsig + " {\n" + lbcode + "return _K_EMPTY;\n}\n\n"
            }
        }
        lsi += 1
    }

    let ii = 0
    while ii < ntoks {
        let itok = tokAt(tokens, ii)
        if itok == "KW:import" {
            let importPath = tokVal(tokAt(tokens, ii + 1))
            // resolve relative path
            // Try 1: relative to source file directory
            // Try 2: as-is (relative to working directory)
            let fullPath = importPath
            if len(baseDir) > 0 {
                if !startsWith(importPath, "/") {
                    if !startsWith(importPath, "C:") {
                        let relPath = baseDir + importPath
                        let testSrc = readFile(relPath)
                        if len(testSrc) > 0 {
                            fullPath = relPath
                        }
                        // else: fall back to importPath as-is (cwd-relative)
                    }
                }
            }
            // Try headersDir if still not found
            if len(headersDir) > 0 {
                let testSrc2 = readFile(fullPath)
                if len(testSrc2) == 0 {
                    let hdPath = headersDir + "/" + importPath
                    let testSrc3 = readFile(hdPath)
                    if len(testSrc3) > 0 {
                        fullPath = hdPath
                    }
                }
            }
            // check cache - skip if already imported
            if !contains(imported, fullPath + "|") {
                imported = imported + fullPath + "|"
                let importSrc = readFile(fullPath)
                if len(importSrc) > 0 {
                    let iToks = tokenize(importSrc)
                    let iNtoks = lineCount(iToks)
                    let iFtable = scanFunctions(iToks, iNtoks)
                    // forward declarations
                    let iDecls = ""
                                        let ij = 0
                    while ij < iNtoks {
                        let itk = tokAt(iToks, ij)
                        if itk == "KW:jxt" {
                            // Process jxt block from imported file
                            let ijxtPos = ij + 2
                            let ijxtHasCHeader = 0
                            while tokAt(iToks, ijxtPos) != "RBRACE" {
                                let ijLang = tokVal(tokAt(iToks, ijxtPos))
                                if ijLang == "c" || ijLang == "t" {
                                    let ijPath = tokVal(tokAt(iToks, ijxtPos + 1))
                                    ijxtHasCHeader = 1
                                    let ijIncLine = ""
                                    if contains(ijPath, "/") || contains(ijPath, "\\") {
                                        ijIncLine = "#include \"" + ijPath + "\"\n"
                                    } else {
                                        ijIncLine = "#include <" + ijPath + ">\n"
                                    }
                                    // c: prepend (foundation headers first), t: append (depends on c headers)
                                    if ijLang == "c" {
                                        iDecls = ijIncLine + iDecls
                                    } else {
                                        iDecls = iDecls + ijIncLine
                                    }
                                    ijxtPos += 2
                                } else if ijLang == "struct" {
                                    // Process struct declaration
                                    let isName = tokVal(tokAt(iToks, ijxtPos + 1))
                                    let isfPos = ijxtPos + 3
                                    let isEntry = isName + ":"
                                    let isFirst = 1
                                    let getBody = ""
                                    let setBody = ""
                                    while tokAt(iToks, isfPos) != "RBRACE" {
                                        if tokVal(tokAt(iToks, isfPos)) == "field" {
                                            let isfName = tokVal(tokAt(iToks, isfPos + 1))
                                            let isfType = tokVal(tokAt(iToks, isfPos + 2))
                                            // optional C access path (string literal): field name TYPE "c.path"
                                            let isfCPath = isfName
                                            if tokType(tokAt(iToks, isfPos + 3)) == "STR" {
                                                isfCPath = tokVal(tokAt(iToks, isfPos + 3))
                                                isfPos = isfPos + 4
                                            } else {
                                                isfPos = isfPos + 3
                                            }
                                            if isFirst == 0 { isEntry = isEntry + "," }
                                            isEntry = isEntry + isfName + ":" + isfType
                                            isFirst = 0
                                            let getExpr = "kr_itoa(s->" + isfCPath + ")"
                                            if isfType == "ULONGLONG" || isfType == "SIZE_T" || isfType == "ULONG_PTR" {
                                                getExpr = "({ char _b[32]; snprintf(_b,32,\"%llu\",(unsigned long long)s->" + isfCPath + "); kr_str(_b); })"
                                            }
                                            if isfType == "LONGLONG" {
                                                getExpr = "({ char _b[32]; snprintf(_b,32,\"%lld\",(long long)s->" + isfCPath + "); kr_str(_b); })"
                                            }
                                            if isfType == "HANDLE" || isfType == "PVOID" {
                                                getExpr = "((char*)s->" + isfCPath + ")"
                                            }
                                            if isfType == "CHAR_ARRAY" {
                                                getExpr = "kr_str(s->" + isfCPath + ")"
                                            }
                                            if isfType == "BYTE" || isfType == "UCHAR" || isfType == "BOOL" {
                                                getExpr = "kr_itoa((int)(unsigned char)s->" + isfCPath + ")"
                                            }
                                            getBody = getBody + "    if(strcmp(f,\"" + isfName + "\")==0) return " + getExpr + ";\n"
                                            let setStmt = "s->" + isfCPath + "=(DWORD)atoi(v);"
                                            if isfType == "ULONGLONG" || isfType == "SIZE_T" || isfType == "ULONG_PTR" {
                                                setStmt = "s->" + isfCPath + "=(ULONGLONG)atoll(v);"
                                            }
                                            if isfType == "LONGLONG" {
                                                setStmt = "s->" + isfCPath + "=(LONGLONG)atoll(v);"
                                            }
                                            if isfType == "WORD" || isfType == "USHORT" {
                                                setStmt = "s->" + isfCPath + "=(WORD)atoi(v);"
                                            }
                                            if isfType == "BYTE" || isfType == "UCHAR" || isfType == "BOOL" {
                                                setStmt = "s->" + isfCPath + "=(BYTE)atoi(v);"
                                            }
                                            if isfType == "HANDLE" || isfType == "PVOID" {
                                                setStmt = "s->" + isfCPath + "=(HANDLE)v;"
                                            }
                                            if isfType == "CHAR_ARRAY" {
                                                setStmt = "strncpy(s->" + isfCPath + ",v,sizeof(s->" + isfCPath + ")-1);"
                                            }
                                            setBody = setBody + "    if(strcmp(f,\"" + isfName + "\")==0){" + setStmt + " return _K_EMPTY;}\n"
                                        } else {
                                            isfPos += 1
                                        }
                                    }
                                    structTable = structTable + isEntry + "\n"
                                    let sAcc = "static char* structnew_" + isName + "(void){"
                                    sAcc = sAcc + isName + "* s=(" + isName + "*)_alloc(sizeof(" + isName + "));"
                                    sAcc = sAcc + "memset(s,0,sizeof(" + isName + ")); return (char*)s;}\n"
                                    sAcc = sAcc + "static char* structget_" + isName + "(char* p,char* f){"
                                    sAcc = sAcc + isName + "* s=(" + isName + "*)p;\n" + getBody
                                    sAcc = sAcc + "    return _K_EMPTY;}\n"
                                    sAcc = sAcc + "static char* structset_" + isName + "(char* p,char* f,char* v){"
                                    sAcc = sAcc + isName + "* s=(" + isName + "*)p;\n" + setBody
                                    sAcc = sAcc + "    return _K_EMPTY;}\n"
                                    sAcc = sAcc + "static char* structsizeof_" + isName + "(void){return kr_itoa(sizeof(" + isName + "));}\n"
                                    iDecls = iDecls + sAcc
                                    ijxtPos = isfPos + 1
                                } else if ijLang == "func" {
                                    let ijfName = tokVal(tokAt(iToks, ijxtPos + 1))
                                    let ijfPos = ijxtPos + 3
                                    let ijfPc = 0
                                    while tokAt(iToks, ijfPos) != "RPAREN" {
                                        if tokType(tokAt(iToks, ijfPos)) == "ID" { ijfPc += 1 }
                                        ijfPos += 1
                                    }
                                    // only emit char* forward declaration if no C header (avoids conflicts)
                                    if ijxtHasCHeader == 0 {
                                        let ijfDecl = "char* " + cIdent(ijfName) + "(char*"
                                        if ijfPc == 0 { ijfDecl = "char* " + cIdent(ijfName) + "(" }
                                        let ijfPi = 1
                                        while ijfPi < ijfPc { ijfDecl = ijfDecl + ", char*"  ijfPi += 1 }
                                        ijfDecl = ijfDecl + ");\n"
                                        iDecls = iDecls + ijfDecl
                                    }
                                    // Add to ftable
                                    let ijfInfo = ijfName + ":" + ijfPc + ":0"
                                    if len(ftable) > 0 { ftable = ftable + "\n" + ijfInfo }
                                    else { ftable = ijfInfo }
                                    ijfPos += 1
                                    // Check for -> ReturnType and generate wrapper
                                    let ijfRetType = ""
                                    if tokAt(iToks, ijfPos) == "ARROW" {
                                        ijfRetType = tokVal(tokAt(iToks, ijfPos + 1))
                                        ijfPos += 2
                                    }
                                    let ijfCName = cIdent(ijfName)
                                    if ijfRetType == "INT" || ijfRetType == "UINT" || ijfRetType == "DWORD" || ijfRetType == "LONG" || ijfRetType == "BOOL" {
                                        let iwd = "static char* _krw_" + ijfCName + "("
                                        let iwpi = 0
                                        while iwpi < ijfPc {
                                            if iwpi > 0 { iwd = iwd + "," }
                                            iwd = iwd + "char* _a" + iwpi
                                            iwpi += 1
                                        }
                                        if ijfPc == 0 { iwd = iwd + "void" }
                                        iwd = iwd + "){return kr_itoa((int)" + ijfCName + "("
                                        iwpi = 0
                                        while iwpi < ijfPc {
                                            if iwpi > 0 { iwd = iwd + "," }
                                            iwd = iwd + "_a" + iwpi
                                            iwpi += 1
                                        }
                                        iwd = iwd + "));}\n#define " + ijfCName + " _krw_" + ijfCName + "\n"
                                        iDecls = iDecls + iwd
                                    }
                                    if ijfRetType == "UINT64" || ijfRetType == "ULONGLONG" {
                                        let iwd = "static char* _krw_" + ijfCName + "("
                                        let iwpi = 0
                                        while iwpi < ijfPc {
                                            if iwpi > 0 { iwd = iwd + "," }
                                            iwd = iwd + "char* _a" + iwpi
                                            iwpi += 1
                                        }
                                        if ijfPc == 0 { iwd = iwd + "void" }
                                        iwd = iwd + "){char _b[32];snprintf(_b,32,\"%llu\",(unsigned long long)" + ijfCName + "("
                                        iwpi = 0
                                        while iwpi < ijfPc {
                                            if iwpi > 0 { iwd = iwd + "," }
                                            iwd = iwd + "_a" + iwpi
                                            iwpi += 1
                                        }
                                        iwd = iwd + "));return kr_str(_b);}\n#define " + ijfCName + " _krw_" + ijfCName + "\n"
                                        iDecls = iDecls + iwd
                                    }
                                    if ijfRetType == "zero" {
                                        let iwd = "static char* _krw_" + ijfCName + "("
                                        let iwpi = 0
                                        while iwpi < ijfPc {
                                            if iwpi > 0 { iwd = iwd + "," }
                                            iwd = iwd + "char* _a" + iwpi
                                            iwpi += 1
                                        }
                                        if ijfPc == 0 { iwd = iwd + "void" }
                                        iwd = iwd + "){"  + ijfCName + "("
                                        iwpi = 0
                                        while iwpi < ijfPc {
                                            if iwpi > 0 { iwd = iwd + "," }
                                            iwd = iwd + "_a" + iwpi
                                            iwpi += 1
                                        }
                                        iwd = iwd + ");return _K_EMPTY;}\n#define " + ijfCName + " _krw_" + ijfCName + "\n"
                                        iDecls = iDecls + iwd
                                    }
                                    ijxtPos = ijfPos
                                } else {
                                    ijxtPos += 2
                                }
                            }
                            ij = skipBlock(iToks, ij + 1)
                        } else if itk == "KW:func" || itk == "KW:fn" {
                            let iname = tokVal(tokAt(iToks, ij + 1))
                            if len(iname) > 0 {
                                let iinfo = funcLookup(iFtable, iname)
                                let ipc = funcParamCount(iinfo)
                                let idecl = "char* " + cIdent(iname) + "(char*"
                                let ipj = 1
                                while toInt(ipj) < toInt(ipc) {
                                    idecl = idecl + ", char*"
                                    ipj += 1
                                }
                                if toInt(ipc) == 0 {
                                    idecl = "char* " + cIdent(iname) + "("
                                }
                                idecl = idecl + ");\n"
                                iDecls = iDecls + idecl
                            }
                        }
                        ij += 1
                    }
                    importFwdDecls = importFwdDecls + "// --- imported: " + fullPath + " ---\n"
                    importFwdDecls = importFwdDecls + iDecls
                    // function bodies
                    let iBodies = compileImportedFunctions(iToks, iNtoks, iFtable)
                    importBodies = importBodies + iBodies
                    // in --ir mode, also collect IR for imported functions (skip jxt blocks)
                    if irMode == 1 {
                        let iIRi = 0
                        let iIRinJxt = 0
                        while iIRi < iNtoks {
                            let iIRtok = tokAt(iToks, iIRi)
                            if iIRtok == "KW:jxt" {
                                // skip entire jxt block
                                iIRi = skipBlock(iToks, iIRi + 1)
                            } else if (iIRtok == "KW:func" || iIRtok == "KW:fn") {
                                let iIRfp = irFuncIR(iToks, iIRi, iNtoks)
                                importedIR = importedIR + pairVal(iIRfp)
                                iIRi = pairPos(iIRfp)
                            } else {
                                iIRi += 1
                            }
                        }
                    }
                    // merge function table
                    if len(iFtable) > 0 {
                        if len(ftable) > 0 {
                            ftable = ftable + "\n" + iFtable
                        } else {
                            ftable = iFtable
                        }
                    }
                } else {
                    printErr("kcc: import not found: " + fullPath)
                }
            }
            ii += 2
        } else if itok == "KW:jxt" {
            // jxt { c "header.h"  k "module.k"  t "other.h" }
            let jxtPos = ii + 2
            let jxtHasCHeader = 0
            while tokAt(tokens, jxtPos) != "RBRACE" {
                let lang = tokVal(tokAt(tokens, jxtPos))
                let jxtPath = tokVal(tokAt(tokens, jxtPos + 1))
                if lang == "k" {
                    // Krypton module - process same as KW:import
                    let jFullPath = jxtPath
                    if len(baseDir) > 0 {
                        if !startsWith(jxtPath, "/") && !startsWith(jxtPath, "C:") {
                            jFullPath = baseDir + jxtPath
                        }
                    }
                    if !contains(imported, jFullPath + "|") {
                        imported = imported + jFullPath + "|"
                        let jSrc = readFile(jFullPath)
                        if len(jSrc) > 0 {
                            let jToks = tokenize(jSrc)
                            let jNt = lineCount(jToks)
                            let jFt = scanFunctions(jToks, jNt)
                            importFwdDecls = importFwdDecls + "// --- jxt: " + jFullPath + " ---\n"
                            importBodies = importBodies + compileImportedFunctions(jToks, jNt, jFt)
                            if len(jFt) > 0 {
                                if len(ftable) > 0 { ftable = ftable + "\n" + jFt }
                                else { ftable = jFt }
                            }
                        } else {
                            printErr("kcc: jxt k not found: " + jFullPath)
                        }
                    }
                } else if lang == "c" || lang == "t" {
                    // C header: c = prepend (foundation), t = append (depends on c headers)
                    jxtHasCHeader = 1
                    let jIncLine = ""
                    if contains(jxtPath, "/") || contains(jxtPath, "\\") {
                        jIncLine = "#include \"" + jxtPath + "\"\n"
                    } else {
                        jIncLine = "#include <" + jxtPath + ">\n"
                    }
                    if lang == "c" {
                        importFwdDecls = jIncLine + importFwdDecls
                    } else {
                        importFwdDecls = importFwdDecls + jIncLine
                    }
                    jxtPos += 2
                } else if lang == "struct" {
                    // jxt extern struct: struct NAME { field fname TYPE ... }
                    let sName = tokVal(tokAt(tokens, jxtPos + 1))
                    let sfPos = jxtPos + 3
                    let sEntry = sName + ":"
                    let sfFirst = 1
                    // Build C accessor functions
                    let getBody = ""
                    let setBody = ""
                    while tokAt(tokens, sfPos) != "RBRACE" {
                        if tokVal(tokAt(tokens, sfPos)) == "field" {
                            let sfName = tokVal(tokAt(tokens, sfPos + 1))
                            let sfType = tokVal(tokAt(tokens, sfPos + 2))
                            // optional C access path (string literal): field name TYPE "c.path"
                            let sfCPath = sfName
                            if tokType(tokAt(tokens, sfPos + 3)) == "STR" {
                                sfCPath = tokVal(tokAt(tokens, sfPos + 3))
                                sfPos = sfPos + 4
                            } else {
                                sfPos = sfPos + 3
                            }
                            if sfFirst == 0 { sEntry = sEntry + "," }
                            sEntry = sEntry + sfName + ":" + sfType
                            sfFirst = 0
                            // Generate get accessor for this field
                            let getExpr = "kr_itoa(s->" + sfCPath + ")"
                            if sfType == "ULONGLONG" || sfType == "SIZE_T" || sfType == "ULONG_PTR" {
                                getExpr = "({ char _b[32]; snprintf(_b,32,\"%llu\",(unsigned long long)s->" + sfCPath + "); kr_str(_b); })"
                            }
                            if sfType == "LONGLONG" {
                                getExpr = "({ char _b[32]; snprintf(_b,32,\"%lld\",(long long)s->" + sfCPath + "); kr_str(_b); })"
                            }
                            if sfType == "HANDLE" || sfType == "PVOID" || sfType == "LPVOID" {
                                getExpr = "((char*)s->" + sfCPath + ")"
                            }
                            if sfType == "CHAR_ARRAY" {
                                getExpr = "kr_str(s->" + sfCPath + ")"
                            }
                            if sfType == "BYTE" || sfType == "UCHAR" || sfType == "BOOL" {
                                getExpr = "kr_itoa((int)(unsigned char)s->" + sfCPath + ")"
                            }
                            getBody = getBody + "    if(strcmp(f,\"" + sfName + "\")==0) return " + getExpr + ";\n"
                            // Generate set accessor for this field
                            let setStmt = "s->" + sfCPath + "=(DWORD)atoi(v);"
                            if sfType == "ULONGLONG" || sfType == "SIZE_T" || sfType == "ULONG_PTR" {
                                setStmt = "s->" + sfCPath + "=(ULONGLONG)atoll(v);"
                            }
                            if sfType == "LONGLONG" {
                                setStmt = "s->" + sfCPath + "=(LONGLONG)atoll(v);"
                            }
                            if sfType == "WORD" || sfType == "USHORT" {
                                setStmt = "s->" + sfCPath + "=(WORD)atoi(v);"
                            }
                            if sfType == "BYTE" || sfType == "UCHAR" || sfType == "BOOL" {
                                setStmt = "s->" + sfCPath + "=(BYTE)atoi(v);"
                            }
                            if sfType == "HANDLE" || sfType == "PVOID" {
                                setStmt = "s->" + sfCPath + "=(HANDLE)v;"
                            }
                            if sfType == "CHAR_ARRAY" {
                                setStmt = "strncpy(s->" + sfCPath + ",v,sizeof(s->" + sfCPath + ")-1);"
                            }
                            setBody = setBody + "    if(strcmp(f,\"" + sfName + "\")==0){" + setStmt + " return _K_EMPTY;}\n"
                        } else {
                            sfPos += 1
                        }
                    }
                    structTable = structTable + sEntry + "\n"
                    // Emit C accessor functions
                    let sAccessors = "static char* structnew_" + sName + "(void){"
                    sAccessors = sAccessors + sName + "* s=(" + sName + "*)_alloc(sizeof(" + sName + "));"
                    sAccessors = sAccessors + "memset(s,0,sizeof(" + sName + ")); return (char*)s;}\n"
                    sAccessors = sAccessors + "static char* structget_" + sName + "(char* p,char* f){"
                    sAccessors = sAccessors + sName + "* s=(" + sName + "*)p;\n"
                    sAccessors = sAccessors + getBody
                    sAccessors = sAccessors + "    return _K_EMPTY;}\n"
                    sAccessors = sAccessors + "static char* structset_" + sName + "(char* p,char* f,char* v){"
                    sAccessors = sAccessors + sName + "* s=(" + sName + "*)p;\n"
                    sAccessors = sAccessors + setBody
                    sAccessors = sAccessors + "    return _K_EMPTY;}\n"
                    sAccessors = sAccessors + "static char* structsizeof_" + sName + "(void){return kr_itoa(sizeof(" + sName + "));}\n"
                    importFwdDecls = importFwdDecls + sAccessors
                    jxtPos = sfPos + 1
                } else if lang == "func" {
                    // jxt func declaration: func name(p1, p2) -> type
                    // jxtPos is at ID:func, jxtPos+1 is ID:name
                    let jfName = tokVal(tokAt(tokens, jxtPos + 1))
                    let jfCName = cIdent(jfName)
                    // collect params: scan from LPAREN to RPAREN
                    let jfPos = jxtPos + 3
                    let jfParams = ""
                    let jfPc = 0
                    while tokAt(tokens, jfPos) != "RPAREN" {
                        if tokType(tokAt(tokens, jfPos)) == "ID" {
                            if jfPc > 0 { jfParams = jfParams + "," }
                            jfParams = jfParams + tokVal(tokAt(tokens, jfPos))
                            jfPc += 1
                        }
                        jfPos += 1
                    }
                    // only emit char* forward declaration if no C header (avoids conflicts)
                    if jxtHasCHeader == 0 {
                        let jfDecl = "char* " + jfCName + "(char*"
                        let jfPi = 1
                        while jfPi < jfPc { jfDecl = jfDecl + ", char*"  jfPi += 1 }
                        if jfPc == 0 { jfDecl = "char* " + jfCName + "(" }
                        jfDecl = jfDecl + ");\n"
                        importFwdDecls = importFwdDecls + jfDecl
                    }
                    // add to function table
                    let jfInfo = jfName + ":" + jfPc + ":0"
                    if len(ftable) > 0 { ftable = ftable + "\n" + jfInfo }
                    else { ftable = jfInfo }
                    // advance past RPAREN and check for -> ReturnType annotation
                    jfPos += 1
                    let jfRetType = ""
                    if tokAt(tokens, jfPos) == "ARROW" {
                        jfRetType = tokVal(tokAt(tokens, jfPos + 1))
                        jfPos += 2
                    }
                    // Generate static wrapper + #define for integer-returning APIs.
                    // Args passed as char* (no int cast) — C handles implicit conversion,
                    // which is safe for both pointer args and toHandle() integer args.
                    if jfRetType == "INT" || jfRetType == "UINT" || jfRetType == "DWORD" || jfRetType == "LONG" || jfRetType == "BOOL" {
                        let wd = "static char* _krw_" + jfCName + "("
                        let wpi = 0
                        while wpi < jfPc {
                            if wpi > 0 { wd = wd + "," }
                            wd = wd + "char* _a" + wpi
                            wpi += 1
                        }
                        if jfPc == 0 { wd = wd + "void" }
                        wd = wd + "){return kr_itoa((int)" + jfCName + "("
                        wpi = 0
                        while wpi < jfPc {
                            if wpi > 0 { wd = wd + "," }
                            wd = wd + "_a" + wpi
                            wpi += 1
                        }
                        wd = wd + ");}\n#define " + jfCName + " _krw_" + jfCName + "\n"
                        importFwdDecls = importFwdDecls + wd
                    }
                    if jfRetType == "UINT64" || jfRetType == "ULONGLONG" {
                        let wd = "static char* _krw_" + jfCName + "("
                        let wpi = 0
                        while wpi < jfPc {
                            if wpi > 0 { wd = wd + "," }
                            wd = wd + "char* _a" + wpi
                            wpi += 1
                        }
                        if jfPc == 0 { wd = wd + "void" }
                        wd = wd + "){char _b[32];snprintf(_b,32,\"%llu\",(unsigned long long)" + jfCName + "("
                        wpi = 0
                        while wpi < jfPc {
                            if wpi > 0 { wd = wd + "," }
                            wd = wd + "_a" + wpi
                            wpi += 1
                        }
                        wd = wd + "));return kr_str(_b);}\n#define " + jfCName + " _krw_" + jfCName + "\n"
                        importFwdDecls = importFwdDecls + wd
                    }
                    if jfRetType == "zero" {
                        let wd = "static char* _krw_" + jfCName + "("
                        let wpi = 0
                        while wpi < jfPc {
                            if wpi > 0 { wd = wd + "," }
                            wd = wd + "char* _a" + wpi
                            wpi += 1
                        }
                        if jfPc == 0 { wd = wd + "void" }
                        wd = wd + "){" + jfCName + "("
                        wpi = 0
                        while wpi < jfPc {
                            if wpi > 0 { wd = wd + "," }
                            wd = wd + "_a" + wpi
                            wpi += 1
                        }
                        wd = wd + ");return _K_EMPTY;}\n#define " + jfCName + " _krw_" + jfCName + "\n"
                        importFwdDecls = importFwdDecls + wd
                    }
                    jxtPos = jfPos
                } else {
                    jxtPos += 2
                }
            }
            ii = jxtPos + 1
        } else {
            ii += 1
        }
    }

    // Emit import forward declarations
    if len(importFwdDecls) > 0 {
        sb = sbAppend(sb, importFwdDecls)
        sb = sbAppend(sb, "\n")
    }

    // Emit import function bodies
    if len(lambdaBank) > 0 {
        sb = sbAppend(sb, "// --- lambda functions ---\n")
        sb = sbAppend(sb, lambdaBank)
    }
    if len(importBodies) > 0 {
        sb = sbAppend(sb, importBodies)
    }

    // === MAIN FILE FUNCTIONS ===
    // First pass: forward declarations
    let i = 0
    while i < ntoks {
        let tok = tokAt(tokens, i)
        if tok == "KW:func" || tok == "KW:fn" {
            // Skip if this is a lambda (next token is LPAREN, not a name)
            let nameTok = tokAt(tokens, i + 1)
            if nameTok == "LPAREN" {
                // lambda expression - skip past body
                let lskip = i + 2
                while lskip < ntoks && tokAt(tokens, lskip) != "RPAREN" { lskip += 1 }
                lskip += 1  // past RPAREN
                if tokAt(tokens, lskip) == "ARROW" { lskip += 2 }
                i = skipBlock(tokens, lskip) - 1
            }
            let fname = tokVal(nameTok)
            if len(fname) > 0 {
            let info = funcLookup(ftable, fname)
            let pc = funcParamCount(info)
            // Forward decl always uses char* — void/int funcs have char* wrappers
            let decl = "char* " + cIdent(fname) + "(char*"
            let pi = 1
            while toInt(pi) < toInt(pc) {
                decl = decl + ", char*"
                pi += 1
            }
            if toInt(pc) == 0 {
                decl = "char* " + cIdent(fname) + "("
            }
            decl = decl + ");\n"
            sb = sbAppend(sb, decl)
            }
        } else if tok == "KW:callback" {
            // callback func — skip the func keyword, name, params, body
            // void forward decl emitted by body pass; no char* decl needed here
            let cbSkip = i + 3
            while cbSkip < ntoks && tokAt(tokens, cbSkip) != "RPAREN" { cbSkip += 1 }
            cbSkip += 1
            if tokAt(tokens, cbSkip) == "ARROW" { cbSkip += 2 }
            i = skipBlock(tokens, cbSkip) - 1
        } else if tokType(tok) == "CBLOCK" {
            // cfunc { } — skip in forward-decl pass, emitted in body pass
        } else if tok == "KW:let" {
            // top-level global let — skip in forward-decl pass, handled in body pass
            let gfp = i + 2
            if tokAt(tokens, gfp) == "COLON" { gfp += 2 }
            if tokAt(tokens, gfp) == "ASSIGN" {
                let gfv = compileExpr(tokens, gfp + 1, ntoks)
                i = pairPos(gfv) - 1
            } else {
                i = gfp - 1
            }
        } else if tok == "KW:jxt" {
            // skip jxt block - already processed
            i = skipBlock(tokens, i + 1) - 1
        } else if tok == "KW:export" {
            // export: just advance past it, KW:func follows on next iteration
        } else if tok == "KW:jxt" {
            // skip jxt block entirely - already processed in import loop
            i = skipBlock(tokens, i + 1)
        } else if tok == "KW:struct" || tok == "KW:class" || tok == "KW:type" {
            // emit forward decl for struct constructor
            let sn = tokVal(tokAt(tokens, i + 1))
            if len(sn) > 0 {
                sb = sbAppend(sb, "static char* " + cIdent(sn) + "();\n")
            }
            // skip struct body - skipBlock returns pos after RBRACE
            // subtract 1 because outer loop does i += 1
            i = skipBlock(tokens, i + 2) - 1
        }
        i += 1
    }
    sb = sbAppend(sb, "\n")

    // Second pass: compile function bodies + collect global let inits
    let sbGlobals = sbNew()
    let glDepth = 0
    i = 0
    while i < ntoks {
        let tok = tokAt(tokens, i)
        if tok == "LBRACE" { glDepth += 1 }
        if tok == "RBRACE" { glDepth -= 1 }
        if tok == "KW:let" && glDepth == 0 {
            // Top-level global variable declaration
            let gname = cIdent(tokVal(tokAt(tokens, i + 1)))
            let gp = i + 2
            // skip optional type annotation
            let gtype = "str"
            if tokAt(tokens, gp) == "COLON" {
                gtype = tokVal(tokAt(tokens, gp + 1))
                gp += 2
            }
            // global variables are always char* to stay in the Krypton string world
            sb = sbAppend(sb, "static char* " + gname + " = NULL;\n")
            // compile initializer
            if tokAt(tokens, gp) == "ASSIGN" {
                gp += 1
                let gval = compileExpr(tokens, gp, ntoks)
                let gvalCode = pairVal(gval)
                sbGlobals = sbAppend(sbGlobals, "    " + gname + " = " + gvalCode + ";\n")
                i = pairPos(gval)
            } else {
                i = gp
            }
        } else if tok == "KW:func" || tok == "KW:fn" {
            // Skip if this is a lambda (next token is LPAREN, not a name)
            if tokAt(tokens, i + 1) == "LPAREN" {
                let lskip2 = i + 2
                while lskip2 < ntoks && tokAt(tokens, lskip2) != "RPAREN" { lskip2 += 1 }
                lskip2 += 1
                if tokAt(tokens, lskip2) == "ARROW" { lskip2 += 2 }
                i = skipBlock(tokens, lskip2)
            } else {
            let fp = compileFunc(tokens, i, ntoks)
            let fcode = pairVal(fp)
            sb = sbAppend(sb, fcode)
            i = pairPos(fp)
            }
        } else if tok == "KW:callback" {
            // callback func — compile as void C function
            let fp = compileCallbackFunc(tokens, i + 1, ntoks)
            let fcode = pairVal(fp)
            sb = sbAppend(sb, fcode)
            i = pairPos(fp)
        } else if tokType(tok) == "CBLOCK" {
            // cfunc { } — decode SOH placeholders back to newlines and emit verbatim
            let craw = replace(tokVal(tok), "\x01", "\n")
            sb = sbAppend(sb, craw + "\n")
            i += 1
        } else if tok == "KW:jxt" {
            i = skipBlock(tokens, i + 1) - 1
        } else if tok == "KW:export" {
            // skip export keyword, compile func on next pass
            i += 1
        } else if tok == "KW:struct" || tok == "KW:class" || tok == "KW:type" {
            // Inline struct compilation to avoid pairPos issues
            let sname = tokVal(tokAt(tokens, i + 1))
            let scname = cIdent(sname)
            let sp2 = i + 3
            // collect fields
            let sfields = ""
            let sfc = 0
            while tokAt(tokens, sp2) != "RBRACE" {
                if tokAt(tokens, sp2) == "KW:let" {
                    let sfname = tokVal(tokAt(tokens, sp2 + 1))
                    if sfc > 0 { sfields = sfields + "," + sfname }
                    else { sfields = sfname }
                    sfc += 1
                    sp2 = sp2 + 2
                    // skip optional type annotation
                    if tokAt(tokens, sp2) == "COLON" { sp2 = sp2 + 2 }
                    // skip optional default value
                    if tokAt(tokens, sp2) == "ASSIGN" {
                        let sep = compileExpr(tokens, sp2 + 1, ntoks)
                        sp2 = pairPos(sep)
                    }
                } else { sp2 += 1 }
            }
            // emit typedef
            let sout = "typedef struct " + scname + "_s {\n"
            let si = 0
            while si < sfc {
                let sfn = getNthParam(sfields, si)
                sout = sout + "    char* " + cIdent(sfn) + ";\n"
                si += 1
            }
            sout = sout + "} " + scname + "_t;\n\n"
            sout = sout + "static char* " + scname + "() {\n"
            sout = sout + "    " + scname + "_t* _s = (" + scname + "_t*)_alloc(sizeof(" + scname + "_t));\n"
            let si2 = 0
            while si2 < sfc {
                let sfn2 = getNthParam(sfields, si2)
                sout = sout + "    _s->" + cIdent(sfn2) + " = _K_EMPTY;\n"
                si2 += 1
            }
            sout = sout + "    return (char*)_s;\n}\n\n"
            sb = sbAppend(sb, sout)
            // advance past struct body
            i = sp2
        } else {
            i += 1
        }
    }

    // Find and compile the entry block
    let entry = findEntry(tokens, ntoks)
    if entry < 0 {
        if irMode {
            // DLL/library IR mode: emit IR for export funcs, no entry point
            let sbIRlib = sbNew()
            sbIRlib = sbAppend(sbIRlib, "; Krypton IR\n; Source: " + file + "\n\n")
            sbIRlib = sbAppend(sbIRlib, importedIR)
            let irlibI = 0
            while irlibI < ntoks {
                let irlibTok = tokAt(tokens, irlibI)
                if irlibTok == "KW:func" || irlibTok == "KW:fn" {
                    let irlibFp = irFuncIR(tokens, irlibI, ntoks)
                    sbIRlib = sbAppend(sbIRlib, pairVal(irlibFp))
                    irlibI = pairPos(irlibFp)
                } else if irlibTok == "KW:export" {
                    let irlibNext = tokAt(tokens, irlibI + 1)
                    if irlibNext == "KW:func" || irlibNext == "KW:fn" {
                        let irlibFname = tokVal(tokAt(tokens, irlibI + 2))
                        let irlibFp = irFuncIR(tokens, irlibI + 1, ntoks)
                        sbIRlib = sbAppend(sbIRlib, "EXPORT " + irlibFname + "\n")
                        sbIRlib = sbAppend(sbIRlib, pairVal(irlibFp))
                        irlibI = pairPos(irlibFp)
                    } else { irlibI += 1 }
                } else { irlibI += 1 }
            }
            let irLibText = sbToString(sbIRlib)
            if len(outFile) > 0 {
                let kompilerDir = replace(headersDir, "headers", "bin")
                let tmpIR  = "C:\\krypton\\tmp_kcc_build.ir"
                let tmpOpt = "C:\\krypton\\tmp_kcc_build_opt.ir"
                writeFile(tmpIR, irLibText)
                let optCmd2  = kompilerDir + "\\optimize_host.exe " + tmpIR + " > " + tmpOpt
                let codeCmd2 = kompilerDir + "\\x64_host_new.exe " + tmpOpt + " " + outFile
                shellRun(optCmd2)
                shellRun(codeCmd2)
                deleteFile(tmpIR)
                deleteFile(tmpOpt)
                emit 0
            }
            print(irLibText)
            emit 0
        }
        // library file with no entry point — emit C
        print(sbToString(sb))
        emit 0
    }

    sb = sbAppend(sb, "int main(int argc, char** argv) {\n")
    sb = sbAppend(sb, "    _argc = argc; _argv = argv;\n")
    sb = sbAppend(sb, "    srand((unsigned)time(NULL));\n")
    // initialize global variables declared at file scope
    let globInitCode = sbToString(sbGlobals)
    if len(globInitCode) > 0 {
        sb = sbAppend(sb, globInitCode)
    }

    let bp = compileBlock(tokens, entry, ntoks, 0, "0")
    let bcode = pairVal(bp)
    sb = sbAppend(sb, bcode)
    sb = sbAppend(sb, "    return 0;\n")
    sb = sbAppend(sb, "}\n")

    // If --ir mode, emit IR instead of C
    if irMode {
        let sbIR = sbNew()
        sbIR = sbAppend(sbIR, "; Krypton IR\n; Source: " + file + "\n\n")
        sbIR = sbAppend(sbIR, importedIR)

        let iri = 0
        while iri < ntoks {
            let irtok = tokAt(tokens, iri)
            if irtok == "KW:func" || irtok == "KW:fn" {
                let fp = irFuncIR(tokens, iri, ntoks)
                sbIR = sbAppend(sbIR, pairVal(fp))
                iri = pairPos(fp)
            } else if irtok == "KW:export" {
                let expNext = tokAt(tokens, iri + 1)
                if expNext == "KW:func" || expNext == "KW:fn" {
                    let expFname = tokVal(tokAt(tokens, iri + 2))
                    let efp = irFuncIR(tokens, iri + 1, ntoks)
                    sbIR = sbAppend(sbIR, "EXPORT " + expFname + "\n")
                    sbIR = sbAppend(sbIR, pairVal(efp))
                    iri = pairPos(efp)
                } else {
                    iri += 1
                }
            } else {
                iri += 1
            }
        }

        let irEntry = findEntry(tokens, ntoks)
        if irEntry >= 0 {
            let ep = irBlockIR(tokens, irEntry, ntoks, 0, "0")
            sbIR = sbAppend(sbIR, "FUNC __main__ 0\n" + pairVal(ep) + "END\n")
        }

        let irText = sbToString(sbIR)

        // -o mode: run full native pipeline internally
        if len(outFile) > 0 {
            let kompilerDir = replace(headersDir, "headers", "bin")
            let tmpIR  = "C:\\krypton\\tmp_kcc_build.ir"
            let tmpOpt = "C:\\krypton\\tmp_kcc_build_opt.ir"
            writeFile(tmpIR, irText)
            let optCmd  = kompilerDir + "\\optimize_host.exe " + tmpIR + " > " + tmpOpt
            let codeCmd = kompilerDir + "\\x64_host_new.exe " + tmpOpt + " " + outFile
            shellRun(optCmd)
            shellRun(codeCmd)
            deleteFile(tmpIR)
            deleteFile(tmpOpt)
            emit 0
        }

        print(irText)
        emit 0
    }

    print(sbToString(sb))
}
