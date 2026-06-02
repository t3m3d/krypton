// compile.k — Krypton-to-C compiler written in Krypton
// Usage: kcc compiler/compile.k <source.k> > output.c
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
    let sb = sbNew()
    while i < len(text) && text[i] != "\"" {
        if text[i] == "\\" && i + 1 < len(text) {
            if i > start {
                sb = sbAppend(sb, substring(text, start, i))
            }
            sb = sbAppend(sb, substring(text, i, i + 2))
            i = i + 2
            start = i
        }
        else {
            i += 1
        }
    }
    if i > start {
        sb = sbAppend(sb, substring(text, start, i))
    }
    emit sbToString(sb) + "," + (i + 1)
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
    let sb = sbNew()
    while i < len(text) && text[i] != "`" {
        sb = sbAppend(sb, text[i])
        i += 1
    }
    emit sbToString(sb) + "," + (i + 1)
}

func tokenize(text) {
    let out = sbNew()
    let i = 0

    // Skip shebang line at start of file: `#!/usr/bin/env kcc` etc.
    // Lets `.k` files be `chmod +x`'d and run directly via a kcc -r shebang.
    if len(text) >= 2 && text[0] == "#" && text[1] == "!" {
        while i < len(text) && text[i] != "\n" { i += 1 }
        if i < len(text) { i += 1 }
    }

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
                if id == "jxt" {
                    // Bracketless jxt: jxt followed by anything other than `{`
                    // is sugar for the brace form. Each subsequent line:
                    //     inc "path"
                    // generates the same tokens as `k "path"` (or `c "path"`
                    // if the path ends in .h or .krh). Block ends at the
                    // first non-`inc` token (typically `func`, `let`, `just`).
                    let ji = skipWS(text, i)
                    let bracketless = 0
                    if ji < len(text) {
                        if text[ji] != "{" {
                            bracketless = 1
                        }
                    }
                    if bracketless == 1 {
                        out = sbAppend(out, "LBRACE\n")
                        let done = 0
                        while done == 0 {
                            let ji2 = skipWS(text, ji)
                            if ji2 >= len(text) {
                                done = 1
                            } else {
                                if charIsAlpha(text[ji2]) {
                                    let pp = readIdent(text, ji2)
                                    let nm = pairVal(pp)
                                    if nm == "inc" {
                                        let ji3 = pairPos(pp)
                                        ji3 = skipWS(text, ji3)
                                        let haveStr = 0
                                        if ji3 < len(text) {
                                            if text[ji3] == "\"" {
                                                haveStr = 1
                                            }
                                        }
                                        if haveStr == 1 {
                                            let sp = readString(text, ji3)
                                            let path = pairVal(sp)
                                            ji = pairPos(sp)
                                            let lang = "k"
                                            if endsWith(path, ".h") { lang = "c" }
                                            if endsWith(path, ".krh") { lang = "c" }
                                            out = sbAppend(out, "ID:" + lang + "\n")
                                            out = sbAppend(out, "STR:" + path + "\n")
                                        } else {
                                            done = 1
                                        }
                                    } else {
                                        done = 1
                                    }
                                } else {
                                    done = 1
                                }
                            }
                        }
                        out = sbAppend(out, "RBRACE\n")
                        i = ji
                    }
                }
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
    let sb = sbNew()
    let i = 0
    let start = 0
    while i < len(s) {
        let c = s[i]
        if c == "\\" || c == "\"" || c == "\n" || c == "\r" || c == "\t" {
            if i > start {
                sb = sbAppend(sb, substring(s, start, i))
            }
            if c == "\\" {
                sb = sbAppend(sb, "\\\\")
            } else if c == "\"" {
                sb = sbAppend(sb, "\\\"")
            } else if c == "\n" {
                sb = sbAppend(sb, "\\n")
            } else if c == "\r" {
                sb = sbAppend(sb, "\\r")
            } else if c == "\t" {
                sb = sbAppend(sb, "\\t")
            }
            start = i + 1
        }
        i += 1
    }
    if i > start {
        sb = sbAppend(sb, substring(s, start, i))
    }
    emit sbToString(sb)
}

// === Expand escape sequences in string tokens ===

func expandEscapes(s) {
    let sb = sbNew()
    let i = 0
    let start = 0
    while i < len(s) {
        if s[i] == "\\" {
            if i > start {
                sb = sbAppend(sb, substring(s, start, i))
            }
            i += 1
            if i < len(s) {
                let c = s[i]
                if c == "n" {
                    sb = sbAppend(sb, "\n")
                } else if c == "t" {
                    sb = sbAppend(sb, "\t")
                } else if c == "r" {
                    sb = sbAppend(sb, "\r")
                } else if c == "\\" {
                    sb = sbAppend(sb, "\\")
                } else if c == "\"" {
                    sb = sbAppend(sb, "\"")
                } else {
                    sb = sbAppend(sb, "\\")
                    sb = sbAppend(sb, c)
                }
            }
            start = i + 1
        }
        i += 1
    }
    if i > start {
        sb = sbAppend(sb, substring(s, start, i))
    }
    emit sbToString(sb)
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
    let sb = sbNew()
    let i = 0
    while i < depth {
        sb = sbAppend(sb, "    ")
        i += 1
    }
    emit sbToString(sb)
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
        // Krypton-2.1: emit C string literal directly (lives in .rodata,
        // no per-call kr_str allocation). The kr_* runtime helpers all
        // take read-only inputs so this is safe.
        emit "((char*)\"" + tv + "\")," + (pos + 1)
    }

    if tt == "STR" {
        let expanded = expandEscapes(tv)
        let escaped = cEscape(expanded)
        emit "((char*)\"" + escaped + "\")," + (pos + 1)
    }

    if tt == "KW" {
        if tv == "true" {
            emit "((char*)\"true\")," + (pos + 1)
        }
        if tv == "false" {
            emit "((char*)\"false\")," + (pos + 1)
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
        // 2.0-alpha-3: tightened — require uppercase ID + LBRACE +
        // `<ID>: ...` field syntax. Without the inner check, patterns
        // like `while i < N { ... }` would attempt struct-literal parse.
        if tokAt(tokens, pos + 1) == "LBRACE" {
            let firstChar = name[0]
            if firstChar >= "A" && firstChar <= "Z" {
                let inner1c = tokAt(tokens, pos + 2)
                let inner2c = tokAt(tokens, pos + 3)
                if startsWith(inner1c, "ID:") == "1" {
                    if inner2c == "COLON" {
                        emit compileStructLiteral(tokens, pos, ntoks)
                    }
                }
            }
        }
        emit cIdent(name) + "," + (pos + 1)
    }

    emit "((char*)\"\")," + (pos + 1)
}

// === Function/builtin call compiler ===

// Win32 int-arg marshalling for the C-emit path.  Mirrors the table in
// compiler/windows_x86/x64.k — when these names appear in user code that
// goes through `kcc → C → gcc`, the bare-string Krypton arg has to be
// atoi()'d to an int before being passed to the Win32 function (whose
// real signature expects a DWORD, etc.).  Returns CSV of arg indices
// (0-based), or "" if not marshalled.
func compileWin32IntArgs(name) {
    if name == "GetStdHandle"               { emit "0" }
    if name == "SetConsoleOutputCP"         { emit "0" }
    if name == "SetConsoleMode"             { emit "0,1" }
    if name == "GetConsoleMode"             { emit "0" }
    if name == "GetConsoleScreenBufferInfo" { emit "0" }
    if name == "Sleep"                      { emit "0" }
    if name == "GetTickCount"               { emit "" }
    if name == "GetTickCount64"             { emit "" }
    if name == "GetSystemMetrics"           { emit "0" }
    if name == "ExitProcess"                { emit "0" }
    if name == "WriteFile"                  { emit "0,2,4" }
    if name == "ReadFile"                   { emit "0,2,4" }
    if name == "CloseHandle"                { emit "0" }
    if name == "CreateToolhelp32Snapshot"   { emit "0,1" }
    if name == "Process32First"             { emit "0" }
    if name == "Process32Next"              { emit "0" }
    if name == "GetLogicalDrives"           { emit "" }
    if name == "GetFileAttributesA"         { emit "" }
    if name == "GetFileSizeEx"              { emit "0" }
    if name == "FreeLibrary"                { emit "0" }
    if name == "FindFirstFileA"             { emit "" }
    if name == "FindNextFileA"              { emit "0" }
    if name == "FindClose"                  { emit "0" }
    if name == "CreateDirectoryA"           { emit "" }
    if name == "DeleteFileA"                { emit "" }
    if name == "RemoveDirectoryA"           { emit "" }
    if name == "MoveFileA"                  { emit "" }
    if name == "CopyFileA"                  { emit "2" }   // bFailIfExists is BOOL
    if name == "GetCurrentDirectoryA"       { emit "0" }   // size = DWORD
    if name == "SetCurrentDirectoryA"       { emit "" }    // (string only)
    if name == "GetTempPathA"               { emit "0" }   // size = DWORD
    // Process / pipe management
    if name == "CreatePipe"                 { emit "3" }       // out, out, sa-ptr, size=DWORD
    if name == "CreateProcessA"             { emit "4,5" }     // app=str, cmd=str, pa,ta=ptr, inherit=BOOL, flags=DWORD, env=ptr, dir=str, si=ptr, pi=ptr
    if name == "PeekNamedPipe"              { emit "0,2" }     // handle, lpBuf=ptr, nBufSize=DWORD, lpRead=ptr, lpAvail=ptr, lpLeft=ptr
    if name == "GetExitCodeProcess"         { emit "0" }       // process, lpExitCode=ptr
    if name == "SetHandleInformation"       { emit "0,1,2" }   // handle, mask=DWORD, flags=DWORD
    if name == "RegOpenKeyExA"              { emit "0,2,3" }
    if name == "RegQueryValueExA"           { emit "0" }
    if name == "RegEnumKeyExA"              { emit "0,1" }
    if name == "RegCloseKey"                { emit "0" }
    if name == "GetUserNameA"               { emit "" }
    if name == "GlobalMemoryStatusEx"       { emit "" }
    if name == "GetSystemPowerStatus"       { emit "" }
    if name == "GetDiskFreeSpaceExA"        { emit "" }
    if name == "GetCurrentProcessId"        { emit "" }
    if name == "GetCurrentThreadId"         { emit "" }
    if name == "GetLastError"               { emit "" }
    if name == "SetLastError"               { emit "0" }
    if name == "WaitForSingleObject"        { emit "0,1" }
    if name == "TerminateProcess"           { emit "0,1" }
    if name == "OpenProcess"                { emit "0,1,2" }
    if name == "CreateFileA"                { emit "1,2,3,4,5,6" }
    if name == "VirtualAlloc"               { emit "0,1,2,3" }
    if name == "VirtualFree"                { emit "0,1,2" }
    if name == "HeapAlloc"                  { emit "0,1,2" }
    if name == "HeapReAlloc"                { emit "0,1,3" }
    if name == "HeapFree"                   { emit "0,1" }
    if name == "GetEnvironmentVariableA"    { emit "2" }
    if name == "CreateFileMappingA"         { emit "0,1,2,3,4,5" }
    if name == "MapViewOfFile"              { emit "0,1,2,3,4" }
    if name == "MessageBoxA"                { emit "0,3" }
    if name == "ShowWindow"                 { emit "0,1" }
    if name == "SetTimer"                   { emit "0,1,2" }
    if name == "KillTimer"                  { emit "0,1" }
    if name == "SetForegroundWindow"        { emit "0" }
    if name == "ShellExecuteA"              { emit "0,5" }
    emit ""
}

// "1" if return is full 64-bit (HANDLE/HMODULE/HINSTANCE) — use itoa64.
// Default for compileWin32IntReturn=="1" is BOOL/DWORD (32-bit).
func compileWin32Return64(name) {
    if name == "GetStdHandle"             { emit "1" }
    if name == "GetProcessHeap"           { emit "1" }
    if name == "CreateToolhelp32Snapshot" { emit "1" }
    if name == "CreateFileA"              { emit "1" }
    if name == "FindFirstFileA"           { emit "1" }
    if name == "CreateFileMappingA"       { emit "1" }
    if name == "MapViewOfFile"            { emit "1" }
    if name == "GetForegroundWindow"      { emit "1" }
    if name == "VirtualAlloc"             { emit "1" }
    if name == "HeapAlloc"                { emit "1" }
    if name == "HeapReAlloc"              { emit "1" }
    emit ""
}

// "1" if Win32 function returns an int that should be itoa'd into a
// Krypton string; "" otherwise.  By default 32-bit (BOOL/DWORD/LONG);
// see compileWin32Return64 for HANDLE-typed (64-bit) returns.
func compileWin32IntReturn(name) {
    if name == "GetStdHandle"               { emit "1" }
    if name == "GetTickCount"               { emit "1" }
    if name == "GetTickCount64"             { emit "1" }
    if name == "GetSystemMetrics"           { emit "1" }
    if name == "WriteFile"                  { emit "1" }
    if name == "ReadFile"                   { emit "1" }
    if name == "CloseHandle"                { emit "1" }
    if name == "CreateToolhelp32Snapshot"   { emit "1" }
    if name == "Process32First"             { emit "1" }
    if name == "Process32Next"              { emit "1" }
    if name == "GetLogicalDrives"           { emit "1" }
    if name == "GetFileAttributesA"         { emit "1" }
    if name == "GetFileSizeEx"              { emit "1" }
    if name == "FindFirstFileA"             { emit "1" }
    if name == "FindNextFileA"              { emit "1" }
    if name == "FindClose"                  { emit "1" }
    if name == "CreateDirectoryA"           { emit "1" }
    if name == "DeleteFileA"                { emit "1" }
    if name == "RemoveDirectoryA"           { emit "1" }
    if name == "MoveFileA"                  { emit "1" }
    if name == "CopyFileA"                  { emit "1" }
    if name == "GetCurrentDirectoryA"       { emit "1" }   // DWORD count returned
    if name == "SetCurrentDirectoryA"       { emit "1" }   // BOOL
    if name == "GetTempPathA"               { emit "1" }   // DWORD count returned
    if name == "CreateFileA"                { emit "1" }   // HANDLE
    if name == "CreatePipe"                 { emit "1" }   // BOOL
    if name == "CreateProcessA"             { emit "1" }   // BOOL
    if name == "PeekNamedPipe"              { emit "1" }   // BOOL
    if name == "GetExitCodeProcess"         { emit "1" }   // BOOL
    if name == "SetHandleInformation"       { emit "1" }   // BOOL
    if name == "RegOpenKeyExA"              { emit "1" }
    if name == "RegQueryValueExA"           { emit "1" }
    if name == "RegEnumKeyExA"              { emit "1" }
    if name == "RegCloseKey"                { emit "1" }
    if name == "GetUserNameA"               { emit "1" }
    if name == "GlobalMemoryStatusEx"       { emit "1" }
    if name == "GetSystemPowerStatus"       { emit "1" }
    if name == "GetDiskFreeSpaceExA"        { emit "1" }
    if name == "GetCurrentProcessId"        { emit "1" }
    if name == "GetCurrentThreadId"         { emit "1" }
    if name == "GetLastError"               { emit "1" }
    if name == "WaitForSingleObject"        { emit "1" }
    if name == "TerminateProcess"           { emit "1" }
    if name == "GetProcessHeap"             { emit "1" }
    if name == "SetConsoleMode"             { emit "1" }
    if name == "GetConsoleMode"             { emit "1" }
    if name == "SetConsoleOutputCP"         { emit "1" }
    if name == "GetConsoleScreenBufferInfo" { emit "1" }
    if name == "VirtualFree"                { emit "1" }
    if name == "HeapFree"                   { emit "1" }
    if name == "FreeLibrary"                { emit "1" }
    if name == "MessageBoxA"                { emit "1" }
    if name == "ShowWindow"                 { emit "1" }
    if name == "SetTimer"                   { emit "1" }
    if name == "KillTimer"                  { emit "1" }
    if name == "GetForegroundWindow"        { emit "1" }
    if name == "SetForegroundWindow"        { emit "1" }
    if name == "CreateFileMappingA"         { emit "1" }
    if name == "UnmapViewOfFile"            { emit "1" }
    if name == "ShellExecuteA"              { emit "1" }
    emit ""
}

// Check whether csv (e.g. "0,2,4") contains the integer idx.
func compileCsvHas(csv, idx) {
    if len(csv) == 0 { emit "0" }
    let target = "" + idx
    let i = 0
    let cur = ""
    while i <= len(csv) {
        let ch = ""
        if i < len(csv) { ch = substring(csv, i, i + 1) }
        if i == len(csv) || ch == "," {
            if cur == target { emit "1" }
            cur = ""
        } else {
            cur = cur + ch
        }
        i += 1
    }
    emit "0"
}

func compileCall(tokens, pos, ntoks) {
    let fname = tokVal(tokAt(tokens, pos))
    let p = pos + 2
    // collect compiled argument expressions
    let args = ""
    let argList = ""    // newline-separated, for Win32 marshalling rebuild
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
            argList = argList + "\n" + acode
        } else {
            args = acode
            argList = acode
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
    // Arena mark/reset — bump-allocator checkpoint for hot loops.
    if fname == "arenaMark"     { emit "_alloc_mark()," + p }
    if fname == "arenaReset"    { emit "_alloc_reset(" + args + ")," + p }
    if fname == "intSlotStore"  { emit "intSlotStore(" + args + ")," + p }
    if fname == "intSlotLoad"   { emit "intSlotLoad(" + args + ")," + p }
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
    if fname == "bufNew"      { emit "({int _bn=atoi("+args+");char* _bp=_alloc(_bn);memset(_bp,0,_bn);_bp;})," + p }
    if fname == "bufStr"      { emit "kr_str(" + args + ")," + p }
    if fname == "bufGetDword" { emit "kr_bufgetdword(" + args + ")," + p }
    if fname == "bufSetDword" { emit "kr_bufsetdword(" + args + ")," + p }
    if fname == "bufGetWord"  { emit "kr_bufgetword(" + args + ")," + p }
    if fname == "bufGetQword"   { emit "kr_bufgetqword(" + args + ")," + p }
    if fname == "bufGetDwordAt"  { emit "kr_bufgetdwordat(" + args + ")," + p }
    if fname == "bufGetQwordAt"  { emit "kr_bufgetqwordat(" + args + ")," + p }
    if fname == "bufSetQwordAt"  { emit "kr_bufsetqwordat(" + args + ")," + p }
    if fname == "bufGetWordAt"   { emit "kr_bufgetwordat(" + args + ")," + p }
    if fname == "bufSetWordAt"   { emit "kr_bufsetwordat(" + args + ")," + p }
    if fname == "bufSetByte"     { emit "kr_bufsetbyte(" + args + ")," + p }
    if fname == "bufGetByte"     { emit "kr_bufgetbyte(" + args + ")," + p }
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

    // Win32 marshalling: when fname is a marshalled Win32 function,
    // wrap atoi() around int args + kr_itoa() around int returns so the
    // C-emit path works the same as the native PE pipeline.
    let intArgsCsv = compileWin32IntArgs(fname)
    let intRet = compileWin32IntReturn(fname)
    if len(intArgsCsv) > 0 || intRet == "1" {
        // Build an arg-by-arg cast list (`int` for marshalled, `char*` for the rest).
        let mCast = ""
        let mArgs = ""
        let mi = 0
        while mi < argc {
            let acode = getLine(argList, mi)
            if compileCsvHas(intArgsCsv, mi) == "1" {
                if mi == 0 { mCast = "void*"  mArgs = "(void*)(intptr_t)atoll("+acode+")" }
                else       { mCast = mCast + ",void*"  mArgs = mArgs + ", (void*)(intptr_t)atoll("+acode+")" }
            } else {
                if mi == 0 { mCast = "char*"  mArgs = acode }
                else       { mCast = mCast + ",char*"  mArgs = mArgs + ", " + acode }
            }
            mi += 1
        }
        if argc == 0 { mCast = "void" }
        let retType = "char*"
        let mCall = "((" + retType + "(*)(" + mCast + "))" + cIdent(fname) + ")(" + mArgs + ")"
        if intRet == "1" {
            // 64-bit returns (HANDLE etc.) need full width; 32-bit returns
            // (BOOL/DWORD/LONG) need explicit truncation to avoid garbage
            // in the upper 32 bits of RAX.
            let is64 = compileWin32Return64(fname)
            if is64 == "1" {
                mCall = "kr_itoa64((long long)(intptr_t)(" + mCall + "))"
            } else {
                mCall = "kr_itoa((int)(intptr_t)(" + mCall + "))"
            }
        }
        emit mCall + "," + p
    }

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
    r = sbAppend(r, "static ABlock* _arena = 0;\n")

    // Krypton-2.1 mark+sweep collector for the C-emit runtime.
    //
    // Strategy: conservative stack-scan mark+sweep. Every _alloc prepends
    // a 16-byte header (linked-list pointer + size + mark flag) to the
    // returned chunk. Allocations are still bump-allocated within 64-MB
    // arena blocks, but we also keep a global linked list of all
    // outstanding allocations.
    //
    // When the total committed arena exceeds _gc_threshold bytes, the
    // next _alloc call triggers _gc_collect:
    //   1. setjmp() forces callee-save registers to a jmp_buf.
    //   2. Walk the C stack from (jmp_buf + locals) up to _stack_bottom,
    //      treating each 8-byte aligned word as a possible pointer.
    //   3. Mark any allocation whose user-data range contains a stack-word
    //      value. Strings have no internal pointers so recursion isn't
    //      needed.
    //   4. Sweep: unmarked allocations are removed from the linked list.
    //   5. If any 64-MB arena block ends up with all of its allocations
    //      unmarked, free() the whole block. This is the only memory
    //      that gets returned to the OS without a full copy.
    //
    // Limits:
    //   - Conservative scan retains some false-positives (integers that
    //     happen to look like arena pointers).
    //   - Bump allocator means individual chunks can't be reclaimed within
    //     a still-live block; only fully-dead blocks free.
    //   - In practice, this is sufficient to bound long compilations
    //     because most arena memory is per-iteration garbage that dies
    //     in waves.
    r = sbAppend(r, "typedef struct AllocHdr { struct AllocHdr* next; uint32_t size; uint32_t mark; } AllocHdr;\n")
    r = sbAppend(r, "static AllocHdr* _alloc_head = 0;\n")
    r = sbAppend(r, "static char* _stack_bottom = 0;\n")
    r = sbAppend(r, "static long _gc_arena_bytes = 0;\n")
    r = sbAppend(r, "static long _gc_threshold = 268435456L;\n")  // 256 MB default
    r = sbAppend(r, "static int _gc_enabled = -1;\n")  // lazy-init: -1 unknown, 0 off, 1 on
    r = sbAppend(r, "static void _gc_collect(void);\n")
    // Pointer-range hint used by mark phase for O(1) reject of non-arena
    // stack words. Updated on every _alloc and recomputed on _gc_collect.
    r = sbAppend(r, "static char* _arena_addr_lo = (char*)~(uintptr_t)0;\n")
    r = sbAppend(r, "static char* _arena_addr_hi = 0;\n")

    // noinline so a real call frame exists at GC trigger time — caller's
    // caller-save register values are spilled to the stack before the
    // call, making them visible to the conservative scan.
    r = sbAppend(r, "static char* _alloc(int n) __attribute__((noinline));\n")
    r = sbAppend(r, "static char* _alloc(int n) {\n")
    r = sbAppend(r, "    n = (n + 7) & ~7;\n")
    r = sbAppend(r, "    if (_gc_enabled < 0) {\n")
    r = sbAppend(r, "        const char* env = getenv(\"KR_NOGC\");\n")
    r = sbAppend(r, "        _gc_enabled = (env && *env) ? 0 : 1;\n")
    r = sbAppend(r, "    }\n")
    r = sbAppend(r, "    int total = sizeof(AllocHdr) + n;\n")
    r = sbAppend(r, "    if (!_arena || _arena->used + total > _arena->cap) {\n")
    r = sbAppend(r, "        if (_gc_enabled && _gc_arena_bytes > _gc_threshold) {\n")
    r = sbAppend(r, "            _gc_collect();\n")
    r = sbAppend(r, "            if (_arena && _arena->used + total <= _arena->cap) goto have_room;\n")
    r = sbAppend(r, "        }\n")
    r = sbAppend(r, "        int cap = 64*1024*1024;\n")
    r = sbAppend(r, "        if (total > cap) cap = total;\n")
    r = sbAppend(r, "        ABlock* b = (ABlock*)malloc(sizeof(ABlock) + cap);\n")
    r = sbAppend(r, "        if (!b) { fprintf(stderr, \"out of memory\\n\"); exit(1); }\n")
    r = sbAppend(r, "        b->cap = cap; b->used = 0; b->next = _arena; _arena = b;\n")
    r = sbAppend(r, "        _gc_arena_bytes += cap;\n")
    r = sbAppend(r, "    }\n")
    r = sbAppend(r, "    have_room:;\n")
    r = sbAppend(r, "    AllocHdr* h = (AllocHdr*)((char*)(_arena + 1) + _arena->used);\n")
    r = sbAppend(r, "    h->next = _alloc_head;\n")
    r = sbAppend(r, "    h->size = (uint32_t)n;\n")
    r = sbAppend(r, "    h->mark = 0;\n")
    r = sbAppend(r, "    _alloc_head = h;\n")
    r = sbAppend(r, "    _arena->used += total;\n")
    r = sbAppend(r, "    char* user = (char*)(h + 1);\n")
    r = sbAppend(r, "    if (user < _arena_addr_lo) _arena_addr_lo = user;\n")
    r = sbAppend(r, "    if (user + n > _arena_addr_hi) _arena_addr_hi = user + n;\n")
    r = sbAppend(r, "    return user;\n")
    r = sbAppend(r, "}\n\n")

    // Mark+sweep collector itself (defined after _alloc since it doesn't
    // call _alloc internally). Conservative stack-scan with setjmp() to
    // force callee-save register spills.
    r = sbAppend(r, "#include <setjmp.h>\n")
    r = sbAppend(r, "static int _gc_in_range(ABlock* b, char* p) {\n")
    r = sbAppend(r, "    char* base = (char*)(b + 1);\n")
    r = sbAppend(r, "    return p >= base && p < base + b->cap;\n")
    r = sbAppend(r, "}\n")
    // Sorted-array index built once per GC. Binary search lets mark phase
    // be O(log n) per stack word instead of O(n) — the difference between
    // a few seconds and tens of minutes on a 1M-alloc compile.
    r = sbAppend(r, "static AllocHdr** _gc_sorted = 0;\n")
    r = sbAppend(r, "static int _gc_sorted_cap = 0;\n")
    r = sbAppend(r, "static int _gc_sorted_n = 0;\n")
    r = sbAppend(r, "static int _gc_alloc_cmp(const void* a, const void* b) {\n")
    r = sbAppend(r, "    char* pa = (char*)*(AllocHdr* const*)a;\n")
    r = sbAppend(r, "    char* pb = (char*)*(AllocHdr* const*)b;\n")
    r = sbAppend(r, "    return pa < pb ? -1 : (pa > pb ? 1 : 0);\n")
    r = sbAppend(r, "}\n")
    r = sbAppend(r, "static void _gc_mark_word(void* word) {\n")
    r = sbAppend(r, "    char* p = (char*)word;\n")
    r = sbAppend(r, "    if (p < _arena_addr_lo || p >= _arena_addr_hi) return;\n")
    r = sbAppend(r, "    if (_gc_sorted_n == 0) return;\n")
    r = sbAppend(r, "    // Binary search for greatest alloc with start <= p.\n")
    r = sbAppend(r, "    int lo = 0, hi = _gc_sorted_n;\n")
    r = sbAppend(r, "    while (lo < hi) {\n")
    r = sbAppend(r, "        int mid = (lo + hi) / 2;\n")
    r = sbAppend(r, "        char* mid_start = (char*)_gc_sorted[mid];\n")
    r = sbAppend(r, "        if (mid_start <= p) lo = mid + 1; else hi = mid;\n")
    r = sbAppend(r, "    }\n")
    r = sbAppend(r, "    if (lo == 0) return;\n")
    r = sbAppend(r, "    AllocHdr* a = _gc_sorted[lo - 1];\n")
    r = sbAppend(r, "    char* user = (char*)(a + 1);\n")
    r = sbAppend(r, "    if (p >= user && p < user + a->size) a->mark = 1;\n")
    r = sbAppend(r, "}\n")
    r = sbAppend(r, "static void _gc_collect(void) {\n")
    r = sbAppend(r, "    // Clear all marks + count.\n")
    r = sbAppend(r, "    AllocHdr* a = _alloc_head;\n")
    r = sbAppend(r, "    long n_total = 0, n_live = 0;\n")
    r = sbAppend(r, "    while (a) { a->mark = 0; n_total++; a = a->next; }\n")
    r = sbAppend(r, "    // Build sorted-by-address index for binary-search mark phase.\n")
    r = sbAppend(r, "    if (n_total > _gc_sorted_cap) {\n")
    r = sbAppend(r, "        int newcap = _gc_sorted_cap ? _gc_sorted_cap : 1024;\n")
    r = sbAppend(r, "        while (newcap < n_total) newcap *= 2;\n")
    r = sbAppend(r, "        _gc_sorted = (AllocHdr**)realloc(_gc_sorted, newcap * sizeof(AllocHdr*));\n")
    r = sbAppend(r, "        _gc_sorted_cap = newcap;\n")
    r = sbAppend(r, "    }\n")
    r = sbAppend(r, "    int idx = 0;\n")
    r = sbAppend(r, "    for (a = _alloc_head; a; a = a->next) _gc_sorted[idx++] = a;\n")
    r = sbAppend(r, "    _gc_sorted_n = idx;\n")
    r = sbAppend(r, "    qsort(_gc_sorted, idx, sizeof(AllocHdr*), _gc_alloc_cmp);\n")
    r = sbAppend(r, "    // Mark roots: spill regs to jmp_buf, then scan stack.\n")
    r = sbAppend(r, "    jmp_buf regs;\n")
    r = sbAppend(r, "    setjmp(regs);\n")
    r = sbAppend(r, "    char* lo = (char*)&regs;\n")
    r = sbAppend(r, "    char* hi = _stack_bottom;\n")
    r = sbAppend(r, "    if (lo > hi) { char* t = lo; lo = hi; hi = t; }\n")
    r = sbAppend(r, "    char* p = (char*)(((uintptr_t)lo + 7) & ~(uintptr_t)7);\n")
    r = sbAppend(r, "    while (p < hi) {\n")
    r = sbAppend(r, "        _gc_mark_word(*(void**)p);\n")
    r = sbAppend(r, "        p += 8;\n")
    r = sbAppend(r, "    }\n")
    r = sbAppend(r, "    // Sweep: unlink unmarked from the global list.\n")
    r = sbAppend(r, "    AllocHdr** pp = &_alloc_head;\n")
    r = sbAppend(r, "    while (*pp) {\n")
    r = sbAppend(r, "        if ((*pp)->mark == 0) { *pp = (*pp)->next; }\n")
    r = sbAppend(r, "        else { n_live++; pp = &(*pp)->next; }\n")
    r = sbAppend(r, "    }\n")
    r = sbAppend(r, "    // Free any fully-dead arena blocks (no live allocs in their range).\n")
    r = sbAppend(r, "    ABlock** bpp = &_arena;\n")
    r = sbAppend(r, "    while (*bpp) {\n")
    r = sbAppend(r, "        int has_live = 0;\n")
    r = sbAppend(r, "        AllocHdr* la = _alloc_head;\n")
    r = sbAppend(r, "        while (la) { if (_gc_in_range(*bpp, (char*)la)) { has_live = 1; break; } la = la->next; }\n")
    r = sbAppend(r, "        if (!has_live && *bpp != _arena) {\n")
    r = sbAppend(r, "            ABlock* dead = *bpp;\n")
    r = sbAppend(r, "            *bpp = dead->next;\n")
    r = sbAppend(r, "            _gc_arena_bytes -= dead->cap;\n")
    r = sbAppend(r, "            free(dead);\n")
    r = sbAppend(r, "        } else {\n")
    r = sbAppend(r, "            bpp = &(*bpp)->next;\n")
    r = sbAppend(r, "        }\n")
    r = sbAppend(r, "    }\n")
    r = sbAppend(r, "    // Reset _gc_threshold to roughly 4x current live size, min 64 MB.\n")
    r = sbAppend(r, "    long live_bytes = 0;\n")
    r = sbAppend(r, "    a = _alloc_head; while (a) { live_bytes += a->size; a = a->next; }\n")
    r = sbAppend(r, "    _gc_threshold = live_bytes * 4;\n")
    r = sbAppend(r, "    if (_gc_threshold < 536870912L) _gc_threshold = 536870912L;\n")  // 512 MB floor — small live sets shouldn't cause thrashing GC cycles
    r = sbAppend(r, "    if (getenv(\"KR_GC_LOG\")) fprintf(stderr, \"[gc] swept %ld/%ld allocs, %ldMB live, threshold->%ldMB\\n\", n_total - n_live, n_total, live_bytes/1048576, _gc_threshold/1048576);\n")
    r = sbAppend(r, "}\n\n")

    // ── Arena mark/reset (Krypton 2.1 GC-for-C-emit) ──
    // Lets long-running compiler loops reclaim per-iteration garbage in O(1).
    // Caller MUST NOT hold pointers to memory allocated after the mark when
    // calling reset — the arena rewinds and those addresses become reusable.
    // Token is itself arena-allocated and is invalidated by the reset.
    r = sbAppend(r, "typedef struct { ABlock* block; int used; } _AllocMark;\n")
    r = sbAppend(r, "static char* _alloc_mark(void) {\n")
    r = sbAppend(r, "    _AllocMark m;\n")
    r = sbAppend(r, "    m.block = _arena;\n")
    r = sbAppend(r, "    m.used = _arena ? _arena->used : 0;\n")
    r = sbAppend(r, "    char* tok = _alloc(sizeof(_AllocMark));\n")
    r = sbAppend(r, "    memcpy(tok, &m, sizeof(_AllocMark));\n")
    r = sbAppend(r, "    return tok;\n")
    r = sbAppend(r, "}\n")
    // Forward-declare the itoa cache (defined alongside kr_itoa lower
    // down) so _alloc_reset can clear it.
    r = sbAppend(r, "static char* _kr_itoa_cache[1024];\n")
    r = sbAppend(r, "static char* _alloc_reset(const char* tok) {\n")
    r = sbAppend(r, "    _AllocMark m;\n")
    r = sbAppend(r, "    memcpy(&m, tok, sizeof(_AllocMark));\n")
    r = sbAppend(r, "    // Prune the global alloc list: anything in a block we're about\n")
    r = sbAppend(r, "    // to free (or above m.used within m.block) gets dropped first so\n")
    r = sbAppend(r, "    // the GC mark phase doesn't dereference freed memory.\n")
    r = sbAppend(r, "    AllocHdr** pp = &_alloc_head;\n")
    r = sbAppend(r, "    while (*pp) {\n")
    r = sbAppend(r, "        AllocHdr* h = *pp;\n")
    r = sbAppend(r, "        int dead = 0;\n")
    r = sbAppend(r, "        ABlock* b = _arena;\n")
    r = sbAppend(r, "        while (b && b != m.block) {\n")
    r = sbAppend(r, "            if (_gc_in_range(b, (char*)h)) { dead = 1; break; }\n")
    r = sbAppend(r, "            b = b->next;\n")
    r = sbAppend(r, "        }\n")
    r = sbAppend(r, "        if (!dead && m.block && _gc_in_range(m.block, (char*)h)\n")
    r = sbAppend(r, "             && (char*)h >= (char*)(m.block + 1) + m.used) dead = 1;\n")
    r = sbAppend(r, "        if (dead) *pp = h->next;\n")
    r = sbAppend(r, "        else pp = &h->next;\n")
    r = sbAppend(r, "    }\n")
    r = sbAppend(r, "    while (_arena && _arena != m.block) {\n")
    r = sbAppend(r, "        ABlock* deadb = _arena;\n")
    r = sbAppend(r, "        _arena = deadb->next;\n")
    r = sbAppend(r, "        _gc_arena_bytes -= deadb->cap;\n")
    r = sbAppend(r, "        free(deadb);\n")
    r = sbAppend(r, "    }\n")
    r = sbAppend(r, "    if (_arena) _arena->used = m.used;\n")
    r = sbAppend(r, "    // kr_itoa cached strings point into arena; reset invalidates them.\n")
    r = sbAppend(r, "    for (int i = 0; i < 1024; i++) _kr_itoa_cache[i] = 0;\n")
    r = sbAppend(r, "    return \"\";\n")
    r = sbAppend(r, "}\n\n")

    // Cross-reset int storage: 32 slots of static long memory. Lets a hot
    // loop save loop-carried ints (e.g., realTextSize, fi2) before
    // arenaReset() and restore them after. Slot index is a Krypton int
    // string ("0"-"31"). Value is parsed via atoi on store, formatted via
    // snprintf into a fresh kr_str on load.
    r = sbAppend(r, "static long _intSlots[32];\n")
    r = sbAppend(r, "static char* intSlotStore(const char* slot, const char* val) {\n")
    r = sbAppend(r, "    int s = atoi(slot);\n")
    r = sbAppend(r, "    if (s < 0 || s >= 32) return \"\";\n")
    r = sbAppend(r, "    _intSlots[s] = atol(val);\n")
    r = sbAppend(r, "    return \"\";\n")
    r = sbAppend(r, "}\n")
    r = sbAppend(r, "static char* kr_str(const char*);\n")
    r = sbAppend(r, "static char* intSlotLoad(const char* slot) {\n")
    r = sbAppend(r, "    int s = atoi(slot);\n")
    r = sbAppend(r, "    char buf[32];\n")
    r = sbAppend(r, "    if (s < 0 || s >= 32) { buf[0]='0'; buf[1]=0; return kr_str(buf); }\n")
    r = sbAppend(r, "    snprintf(buf, sizeof(buf), \"%ld\", _intSlots[s]);\n")
    r = sbAppend(r, "    return kr_str(buf);\n")
    r = sbAppend(r, "}\n\n")

    // Pre-allocated constant strings — eliminates billions of allocations
    r = sbAppend(r, "static char _K_EMPTY[] = \"\";\nstatic char _K_ZERO[] = \"0\";\nstatic char _K_ONE[] = \"1\";\n\n")

    r = sbAppend(r, "static char* kr_str(const char* s) {\nif (!s[0]) return _K_EMPTY;\n    if (s[0] == '0' && !s[1]) return _K_ZERO;\n    if (s[0] == '1' && !s[1]) return _K_ONE;\n    int n = (int)strlen(s) + 1;\n    char* p = _alloc(n);\n    memcpy(p, s, n);\n    return p;\n")
    r = sbAppend(r, "}\n\nstatic char* kr_cat(const char* a, const char* b) {\nint la = (int)strlen(a), lb = (int)strlen(b);\n    char* p = _alloc(la + lb + 1);\n    memcpy(p, a, la);\n    memcpy(p + la, b, lb + 1);\n    return p;\n}\n\n")
    r = sbAppend(r, "static int kr_isnum(const char* s) {\n    if (!*s) return 0;\n    const char* p = s;\n    if (*p == '-') p++;\n    if (!*p) return 0;\n    while (*p) { if (*p < '0' || *p > '9') return 0; p++; }\n    return 1;\n}\n\n")
    // Krypton-2.1: small-int cache for kr_itoa. Most ints used by the
    // compiler are positions, offsets, sizes — values in 0..1023 dominate
    // by a wide margin. Caching them eliminates ~80% of kr_itoa-induced
    // _alloc traffic. (Cache array forward-declared above _alloc_reset.)
    r = sbAppend(r, "static char* kr_itoa(int v) {\n")
    r = sbAppend(r, "    if (v == 0) return _K_ZERO;\n")
    r = sbAppend(r, "    if (v == 1) return _K_ONE;\n")
    r = sbAppend(r, "    if (v >= 0 && v < 1024) {\n")
    r = sbAppend(r, "        char* c = _kr_itoa_cache[v];\n")
    r = sbAppend(r, "        if (c) return c;\n")
    r = sbAppend(r, "        char buf[8];\n")
    r = sbAppend(r, "        snprintf(buf, sizeof(buf), \"%d\", v);\n")
    r = sbAppend(r, "        c = kr_str(buf);\n")
    r = sbAppend(r, "        _kr_itoa_cache[v] = c;\n")
    r = sbAppend(r, "        return c;\n")
    r = sbAppend(r, "    }\n")
    r = sbAppend(r, "    char buf[32];\n")
    r = sbAppend(r, "    snprintf(buf, sizeof(buf), \"%d\", v);\n")
    r = sbAppend(r, "    return kr_str(buf);\n")
    r = sbAppend(r, "}\n\nstatic int kr_atoi(const char* s) { return atoi(s); }\n\n")
    // 64-bit int → string. Used by C-emit Win32 marshalling for HANDLE
    // returns (which are 64-bit pointers — kr_itoa truncates).
    r = sbAppend(r, "static char* kr_itoa64(long long v) {\n    char buf[32];\n    snprintf(buf, sizeof(buf), \"%lld\", v);\n    return kr_str(buf);\n}\n\n")
    r = sbAppend(r, "static char* kr_plus(const char* a, const char* b) {\n    if (kr_isnum(a) && kr_isnum(b))\n        return kr_itoa(atoi(a) + atoi(b));\n    return kr_cat(a, b);\n}\n\nstatic char* kr_sub(const char* a, const char* b) { return kr_itoa(atoi(a) - atoi(b)); }\nstatic char* kr_mul(const char* a, const char* b) { return kr_itoa(atoi(a) * atoi(b)); }\nstatic char* kr_div(const char* a, const char* b) { return kr_itoa(atoi(a) / atoi(b)); }\n")
    r = sbAppend(r, "static char* kr_mod(const char* a, const char* b) { return kr_itoa(atoi(a) % atoi(b)); }\nstatic char* kr_neg(const char* a) { return kr_itoa(-atoi(a)); }\nstatic char* kr_not(const char* a) { return atoi(a) ? _K_ZERO : _K_ONE; }\n\nstatic char* kr_eq(const char* a, const char* b) {\n    return strcmp(a, b) == 0 ? _K_ONE : _K_ZERO;\n}\nstatic char* kr_neq(const char* a, const char* b) {\n    return strcmp(a, b) != 0 ? _K_ONE : _K_ZERO;\n")
    r = sbAppend(r, "}\nstatic char* kr_lt(const char* a, const char* b) {\n    if (kr_isnum(a) && kr_isnum(b)) return atoi(a) < atoi(b) ? _K_ONE : _K_ZERO;\n    return strcmp(a, b) < 0 ? _K_ONE : _K_ZERO;\n}\nstatic char* kr_gt(const char* a, const char* b) {\n    if (kr_isnum(a) && kr_isnum(b)) return atoi(a) > atoi(b) ? _K_ONE : _K_ZERO;\n    return strcmp(a, b) > 0 ? _K_ONE : _K_ZERO;\n")
    r = sbAppend(r, "}\nstatic char* kr_lte(const char* a, const char* b) {\n    return kr_gt(a, b) == _K_ZERO ? _K_ONE : _K_ZERO;\n}\nstatic char* kr_gte(const char* a, const char* b) {\n    return kr_lt(a, b) == _K_ZERO ? _K_ONE : _K_ZERO;\n}\n\nstatic int kr_truthy(const char* s) {\n")
    r = sbAppend(r, "    if (!s || !*s) return 0;\n    if (strcmp(s, \"0\") == 0) return 0;\n    if (strcmp(s, \"false\") == 0) return 0;\n    return 1;\n}\n\nstatic char* kr_print(const char* s) {\n")
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
    r = sbAppend(r, "    return kr_itoa(count);\n}\n\nstatic char* kr_count(const char* s) {\n    int n = 1;\n    if (s) { const char* p = s; while (*p) { if (*p == ',') n++; p++; } }\n    return kr_itoa(n);\n}\n\n")

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

    r = sbAppend(r, "static char* kr_fromcharcode(const char* ns) {\n    unsigned int v = (unsigned int)atoi(ns);\n    char buf[5] = {0};\n    if (v < 0x80) { buf[0] = (char)v; }\n    else if (v < 0x800) {\n        buf[0] = (char)(0xC0 | (v >> 6));\n        buf[1] = (char)(0x80 | (v & 0x3F));\n    } else if (v < 0x10000) {\n        buf[0] = (char)(0xE0 | (v >> 12));\n        buf[1] = (char)(0x80 | ((v >> 6) & 0x3F));\n        buf[2] = (char)(0x80 | (v & 0x3F));\n    } else {\n        buf[0] = (char)(0xF0 | (v >> 18));\n        buf[1] = (char)(0x80 | ((v >> 12) & 0x3F));\n        buf[2] = (char)(0x80 | ((v >> 6) & 0x3F));\n        buf[3] = (char)(0x80 | (v & 0x3F));\n    }\n    return kr_str(buf);\n}\n\n")

    r = sbAppend(r, "static char* kr_slice(const char* lst, const char* starts, const char* ends) {\n    int cnt = kr_listlen(lst);\n    int s = atoi(starts), e = atoi(ends);\n    if (s < 0) s = cnt + s;\n    if (e < 0) e = cnt + e;\n    if (s < 0) s = 0;\n    if (e > cnt) e = cnt;\n    if (s >= e) return _K_EMPTY;\n")
    r = sbAppend(r, "    char* out = kr_split(lst, kr_itoa(s));\n    for (int i = s + 1; i < e; i++)\n        out = kr_cat(kr_cat(out, \",\"), kr_split(lst, kr_itoa(i)));\n    return out;\n}\n\n")

    r = sbAppend(r, "static char* kr_length(const char* lst) {\n    return kr_itoa(kr_listlen(lst));\n}\n\n")

    r = sbAppend(r, "static char* kr_unique(const char* lst) {\n    if (!*lst) return _K_EMPTY;\n    int cnt = kr_listlen(lst);\n    char* out = _K_EMPTY; int oc = 0;\n    for (int i = 0; i < cnt; i++) {\n        char* item = kr_split(lst, kr_itoa(i));\n        int dup = 0;\n        for (int j = 0; j < oc; j++) {\n")
    r = sbAppend(r, "            if (strcmp(kr_split(out, kr_itoa(j)), item) == 0) { dup = 1; break; }\n        }\n        if (!dup) {\n            if (oc == 0) out = item; else out = kr_cat(kr_cat(out, \",\"), item);\n            oc++;\n        }\n    }\n    return out;\n")
    r = sbAppend(r, "}\n\n")

    r = sbAppend(r, "static char* kr_printerr(const char* s) {\n")
    r = sbAppend(r, "    fprintf(stderr, \"%s\\n\", s);\n")
    r = sbAppend(r, "    fflush(stderr);\n")
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
    r = sbAppend(r, "typedef struct { int cap; int len; } SBHdr;\n#define MAX_SBS 1048576\nstatic SBHdr* _sb_table[MAX_SBS];\nstatic int _sb_count = 0;\n\nstatic char* kr_sbnew() {\n    int initcap = 65536;\n    SBHdr* h = (SBHdr*)malloc(sizeof(SBHdr) + initcap);\n    h->cap = initcap;\n")
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
    r = sbAppend(r, "static char* kr_bufgetbyte(char* buf,const char* off){return kr_itoa((int)(unsigned char)buf[atoi(off)]);}\n")
    r = sbAppend(r, "static char* kr_bufsetdwordat(char* buf,const char* off,const char* val){*(unsigned int*)(buf+atoi(off))=(unsigned int)atoll(val);return _K_EMPTY;}\n")
    r = sbAppend(r, "static char* kr_bufsetqwordat(char* buf,const char* off,const char* val){*(unsigned long long*)(buf+atoi(off))=(unsigned long long)atoll(val);return _K_EMPTY;}\n")
    r = sbAppend(r, "static char* kr_bufgetwordat(char* buf,const char* off){unsigned short v=*(unsigned short*)(buf+atoi(off));return kr_itoa((int)v);}\n")
    r = sbAppend(r, "static char* kr_bufsetwordat(char* buf,const char* off,const char* val){*(unsigned short*)(buf+atoi(off))=(unsigned short)atoi(val);return _K_EMPTY;}\n")
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
func irExpr(tokens, pos, ntoks, lc, types) {
    emit irTernary(tokens, pos, ntoks, lc, types)
}

func irTernary(tokens, pos, ntoks, lc, types) {
    let pair = irOr(tokens, pos, ntoks, lc, types)
    let code = pairVal(pair)
    let p = pairPos(pair)
    let nlc = lc
    if tokAt(tokens, p) == "QUESTION" {
        let trueLabel = irLabel("_tern_t", p)
        let endLabel = irLabel("_tern_e", p)
        nlc = nlc + 1
        let tp = irExpr(tokens, p + 1, ntoks, nlc, types)
        let tcode = pairVal(tp)
        p = pairPos(tp)
        nlc = nlc + 1
        // skip COLON
        p = p + 1
        let fp = irExpr(tokens, p, ntoks, nlc, types)
        let fcode = pairVal(fp)
        p = pairPos(fp)
        nlc = nlc + 1
        let out = code + "JUMPIFNOT " + trueLabel + "\n" + tcode + "JUMP " + endLabel + "\n" + "LABEL " + trueLabel + "\n" + fcode + "LABEL " + endLabel + "\n"
        emit out + "," + p
    }
    emit code + "," + p
}

func irOr(tokens, pos, ntoks, lc, types) {
    let pair = irAnd(tokens, pos, ntoks, lc, types)
    let code = pairVal(pair)
    let p = pairPos(pair)
    let nlc = lc
    while tokAt(tokens, p) == "OR" {
        let shortLabel = irLabel("_or", p)
        let endLabel = irLabel("_orend", p)
        nlc = nlc + 1
        let rp = irAnd(tokens, p + 1, ntoks, nlc, types)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        // Stack-balanced short-circuit OR. JUMPIF pops left and jumps if
        // truthy. Truthy branch pushes 1 and skips right; falsy branch
        // evaluates right and uses its result. Both end with one value
        // on stack — required for native stack-machine backends (elf.k).
        code = code + "JUMPIF " + shortLabel + "\n"
                    + rcode + "JUMP " + endLabel + "\n"
                    + "LABEL " + shortLabel + "\n"
                    + "PUSH 1\n"
                    + "LABEL " + endLabel + "\n"
    }
    emit code + "," + p
}

func irAnd(tokens, pos, ntoks, lc, types) {
    let pair = irEquality(tokens, pos, ntoks, lc, types)
    let code = pairVal(pair)
    let p = pairPos(pair)
    let nlc = lc
    while tokAt(tokens, p) == "AND" {
        let shortLabel = irLabel("_and", p)
        let endLabel = irLabel("_andend", p)
        nlc = nlc + 1
        let rp = irEquality(tokens, p + 1, ntoks, nlc, types)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        // Stack-balanced short-circuit AND. Mirror of irOr.
        code = code + "JUMPIFNOT " + shortLabel + "\n"
                    + rcode + "JUMP " + endLabel + "\n"
                    + "LABEL " + shortLabel + "\n"
                    + "PUSH 0\n"
                    + "LABEL " + endLabel + "\n"
    }
    emit code + "," + p
}

func irEquality(tokens, pos, ntoks, lc, types) {
    let pair = irRelational(tokens, pos, ntoks, lc, types)
    let code = pairVal(pair)
    let p = pairPos(pair)
    while tokAt(tokens, p) == "EQ" || tokAt(tokens, p) == "NEQ" {
        let op = tokAt(tokens, p)
        let rp = irRelational(tokens, p + 1, ntoks, lc, types)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        if op == "EQ" { code = code + rcode + "EQ\n" }
        else { code = code + rcode + "NEQ\n" }
    }
    emit code + "," + p
}

func irRelational(tokens, pos, ntoks, lc, types) {
    let pair = irAdditive(tokens, pos, ntoks, lc, types)
    let code = pairVal(pair)
    let p = pairPos(pair)
    while tokAt(tokens, p) == "LT" || tokAt(tokens, p) == "GT" || tokAt(tokens, p) == "LTE" || tokAt(tokens, p) == "GTE" {
        let op = tokAt(tokens, p)
        let rp = irAdditive(tokens, p + 1, ntoks, lc, types)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        if op == "LT" { code = code + rcode + "LT\n" }
        if op == "GT" { code = code + rcode + "GT\n" }
        if op == "LTE" { code = code + rcode + "LTE\n" }
        if op == "GTE" { code = code + rcode + "GTE\n" }
    }
    emit code + "," + p
}

func irAdditive(tokens, pos, ntoks, lc, types) {
    let pair = irMultiplicative(tokens, pos, ntoks, lc, types)
    let code = pairVal(pair)
    let p = pairPos(pair)
    while tokAt(tokens, p) == "PLUS" || tokAt(tokens, p) == "MINUS" {
        let op = tokAt(tokens, p)
        let rp = irMultiplicative(tokens, p + 1, ntoks, lc, types)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        if op == "PLUS" { code = code + rcode + "ADD\n" }
        else { code = code + rcode + "SUB\n" }
    }
    emit code + "," + p
}

func irMultiplicative(tokens, pos, ntoks, lc, types) {
    let pair = irPow(tokens, pos, ntoks, lc, types)
    let code = pairVal(pair)
    let p = pairPos(pair)
    while tokAt(tokens, p) == "STAR" || tokAt(tokens, p) == "SLASH" || tokAt(tokens, p) == "MOD" {
        let op = tokAt(tokens, p)
        let rp = irPow(tokens, p + 1, ntoks, lc, types)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        if op == "STAR" { code = code + rcode + "MUL\n" }
        if op == "SLASH" { code = code + rcode + "DIV\n" }
        if op == "MOD" { code = code + rcode + "MOD\n" }
    }
    emit code + "," + p
}

// Right-associative ** — `a ** b ** c` is `a ** (b ** c)`.
func irPow(tokens, pos, ntoks, lc, types) {
    let pair = irUnary(tokens, pos, ntoks, lc, types)
    let code = pairVal(pair)
    let p = pairPos(pair)
    if tokAt(tokens, p) == "STARSTAR" {
        let rp = irPow(tokens, p + 1, ntoks, lc, types)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        code = code + rcode + "BUILTIN pow 2\n"
    }
    emit code + "," + p
}

func irUnary(tokens, pos, ntoks, lc, types) {
    let tok = tokAt(tokens, pos)
    if tok == "MINUS" {
        let pair = irUnary(tokens, pos + 1, ntoks, lc, types)
        let code = pairVal(pair)
        let p = pairPos(pair)
        emit code + "NEG\n," + p
    }
    if tok == "BANG" {
        let pair = irUnary(tokens, pos + 1, ntoks, lc, types)
        let code = pairVal(pair)
        let p = pairPos(pair)
        emit code + "NOT\n," + p
    }
    emit irPostfix(tokens, pos, ntoks, lc, types)
}

func irPostfix(tokens, pos, ntoks, lc, types) {
    let pair = irPrimary(tokens, pos, ntoks, lc, types)
    let code = pairVal(pair)
    let p = pairPos(pair)
    // 1.8.10: deferred-offset state for nested-struct chains.
    // When we walk `outer.inner.field`, the outer LOAD goes onto the
    // value stack once, then we accumulate (innerOff + fieldOff) into
    // `accumOff` without emitting any intermediate buf reads. Only the
    // final primitive field flushes a single buf read with the combined
    // offset. The current "deferred type" is tracked separately from
    // the IR-comment tag because the comment is inert — it never
    // reaches codegen — so we can drop/replace it without re-emitting
    // it during chain traversal.
    let accumOff = 0
    let deferredType = ""    // "*Vec3" etc. while building a chain
    // Seed deferredType from the trailing TYPE comment that irPrimary
    // may have emitted on the LOAD line.
    let nLines0 = lineCount(code)
    if nLines0 > 0 {
        let last0 = getLine(code, nLines0 - 1)
        if startsWith(last0, "; TYPE ") == "1" {
            deferredType = substring(last0, 7, len(last0))
        }
    }
    while tokAt(tokens, p) == "LBRACK" || tokAt(tokens, p) == "DOT" {
        if tokAt(tokens, p) == "LBRACK" {
            let idxp = irExpr(tokens, p + 1, ntoks, lc, types)
            let idxcode = pairVal(idxp)
            p = pairPos(idxp) + 1
            // If we have an accumulated nested offset waiting, fold it
            // into the index expression (idx*N + accumOff) before the
            // BUILTIN call.
            let addAcc = ""
            if accumOff != 0 { addAcc = "PUSH " + accumOff + "\nADD\n" }
            if deferredType == "*u8" {
                code = code + idxcode + addAcc + "BUILTIN bufGetByte 2\n"
            } else if deferredType == "*u16" || deferredType == "*i16" {
                code = code + idxcode + "PUSH 2\nMUL\n" + addAcc + "BUILTIN bufGetWordAt 2\n"
            } else if deferredType == "*u32" || deferredType == "*i32" {
                code = code + idxcode + "PUSH 4\nMUL\n" + addAcc + "BUILTIN bufGetDwordAt 2\n"
            } else if deferredType == "*u64" || deferredType == "*i64" {
                code = code + idxcode + "PUSH 8\nMUL\n" + addAcc + "BUILTIN bufGetQwordAt 2\n"
            } else {
                code = code + idxcode + "INDEX\n"
            }
            accumOff = 0
            deferredType = ""
        } else {
            let field = tokVal(tokAt(tokens, p + 1))
            p = p + 2
            let didTypedField = 0
            if startsWith(deferredType, "*") == "1" {
                let sname = substring(deferredType, 1, len(deferredType))
                let info = irTypeOf(types, sname + "." + field)
                if len(info) > 0 {
                    let pipe1 = indexOf(info, "|")
                    let offStr = substring(info, 0, pipe1)
                    let ftype  = substring(info, pipe1 + 1, len(info))
                    let fOff = toInt(offStr)
                    if startsWith(ftype, "*") == "1" {
                        // Nested struct field — defer further; just
                        // accumulate the offset and re-tag the type.
                        accumOff = accumOff + fOff
                        deferredType = ftype
                        didTypedField = 1
                    } else {
                        let fop = ""
                        if ftype == "u8"  || ftype == "i8"  { fop = "BUILTIN bufGetByte 2\n" }
                        if ftype == "u16" || ftype == "i16" { fop = "BUILTIN bufGetWordAt 2\n" }
                        if ftype == "u32" || ftype == "i32" { fop = "BUILTIN bufGetDwordAt 2\n" }
                        if ftype == "u64" || ftype == "i64" { fop = "BUILTIN bufGetQwordAt 2\n" }
                        if len(fop) > 0 {
                            code = code + "PUSH " + (accumOff + fOff) + "\n" + fop
                            didTypedField = 1
                            accumOff = 0
                            deferredType = ""
                        }
                    }
                }
            }
            if didTypedField == 0 {
                code = code + "GETFIELD " + field + "\n"
                deferredType = ""
                accumOff = 0
            }
        }
    }
    emit code + "," + p
}

func irPrimary(tokens, pos, ntoks, lc, types) {
    let tok = tokAt(tokens, pos)
    let tt = tokType(tok)
    let tv = tokVal(tok)

    // Integer/float literal
    if tt == "INT" {
        emit "PUSH " + tv + "\n," + (pos + 1)
    }

    // String literal
    if tt == "STR" {
        // tv carries escape sequences as literal 2-char pairs (e.g. "\n" =
        // 2 chars: backslash + n) — Krypton's tokenizer doesn't decode
        // them. parseQuoted in elf.k IS a proper decoder, so emit tv as-is
        // and let the backend's parseQuoted convert "\n" → newline byte
        // (matching what gcc would do for the C-emit path).
        // Don't double-escape — that produced "\\n" 3-char IR which
        // parseQuoted decoded as literal "\n" 2-char (broken on native).
        emit "PUSH \"" + tv + "\"\n," + (pos + 1)
    }

    // Backtick interpolation - emit as PUSH + CAT chain
    if tt == "INTERP" {
        emit irInterpToIR(tv, pos, lc, types) + "," + (pos + 1)
    }

    // Boolean literals — store as the strings "true"/"false" so kp(true)
    // prints "true" instead of "1". The truthiness rule already treats
    // "false" as falsy and any non-empty/non-"0"/non-"false" string as
    // truthy, so `if true` / `if false` still work as expected.
    // Comparison ops, isTruthy, hasField, etc. continue to return "1"/"0";
    // see stdlib/booleans.k for normalization helpers.
    if tok == "KW:true" {
        emit "PUSH \"true\"\n," + (pos + 1)
    }
    if tok == "KW:false" {
        emit "PUSH \"false\"\n," + (pos + 1)
    }

    // Grouped expression
    if tok == "LPAREN" {
        let pair = irExpr(tokens, pos + 1, ntoks, lc, types)
        let code = pairVal(pair)
        let p = pairPos(pair)
        emit code + "," + (p + 1)
    }

    // List literal [a, b, c]
    if tok == "LBRACK" {
        emit irListLiteralIR(tokens, pos, ntoks, lc, types)
    }

    // 2.0-alpha: lambda expression `func(params) { body }` — pre-scan
    // hoists the body to a top-level `FUNC _krlam<pos> N` ahead of
    // time. If the body has free vars (closure), emit env-construction
    // IR before the FUNCPTR so the result is a closure value (env head)
    // instead of a raw fp. irScanFuncTypes tags such locals as
    // `closure`; irCall dispatches them via env-extracting call.
    if (tok == "KW:func" || tok == "KW:fn") && tokAt(tokens, pos + 1) == "LPAREN" {
        let lp = pos + 2
        let lpc = ""    // user param csv
        while tokAt(tokens, lp) != "RPAREN" {
            let lpt = tokAt(tokens, lp)
            if tokType(lpt) == "ID" {
                if len(lpc) > 0 { lpc = lpc + "," }
                lpc = lpc + tokVal(lpt)
            }
            lp = lp + 1
        }
        lp += 1   // past RPAREN
        if tokAt(tokens, lp) == "ARROW" { lp = lp + 2 }
        let lpEnd = skipBlock(tokens, lp)

        // 2.0-alpha-3 unification: ALL lambdas wrapped as closures
        // (env-head with __fp__ + capture entries if any). Lambda
        // body always has __env as PARAM 0; capture-free bodies
        // just ignore it. Per benchmark, overhead is below noise.
        let lFree = findFreeVars(tokens, lp, lpEnd, lpc)
        let envCode = "BUILTIN envNew 0\n"
        if len(lFree) > 0 {
            let lfc = count(lFree)
            let lfi = 0
            while lfi < lfc {
                let lfname = split(lFree, lfi)
                envCode = envCode +
                    "PUSH \"" + lfname + "\"\n" +
                    "LOAD " + lfname + "\n" +
                    "BUILTIN envSet 3\n"
                lfi = lfi + 1
            }
        }
        envCode = envCode +
            "PUSH \"__fp__\"\n" +
            "FUNCPTR _krlam" + pos + "\n" +
            "BUILTIN envSet 3\n"
        emit envCode + "," + lpEnd
    }

    // Identifier - function call or variable
    if tt == "ID" {
        let nextTok = tokAt(tokens, pos + 1)
        if nextTok == "LPAREN" {
            emit irCall(tokens, pos, ntoks, lc, types)
        }
        // Struct literal: Name { field: val }
        // 2.0-alpha-3: tighten heuristic — also require the LBRACE
        // body to start with `<ID>: ...` (field-syntax). Without this,
        // patterns like `while i < N { ... }` would attempt struct-literal
        // parse on N (NOTE: bug still reproduces even with this fix —
        // crash is upstream, possibly in tokenization). Kept the
        // tightening anyway because it's more correct.
        let firstChar = tv[0]
        if nextTok == "LBRACE" {
            if firstChar >= "A" && firstChar <= "Z" {
                let inner1 = tokAt(tokens, pos + 2)
                let inner2 = tokAt(tokens, pos + 3)
                if startsWith(inner1, "ID:") == "1" {
                    if inner2 == "COLON" {
                        emit irStructLiteralIR(tokens, pos, ntoks, lc, types)
                    }
                }
            }
        }
        // Plain variable load. Phase C: if `tv` was declared with a
        // type annotation, emit a `; TYPE *u8` comment alongside so
        // irPostfix can specialize a following `[i]` into a typed
        // pointer read. Comment is stripped by x64.k's IR cleanup.
        let varType = irTypeOf(types, tv)
        if len(varType) > 0 {
            // 2.0-alpha-3: closure capture — `__cap__:<name>` type
            // means `tv` is a captured free var; rewrite the load as
            // `LOAD __env; PUSH "<name>"; envGet 2`. The lambda body
            // has __env as its first PARAM (added by irLambdaIR).
            if startsWith(varType, "__cap__:") == "1" {
                let capName = substring(varType, 8, len(varType))
                emit "LOAD __env\nPUSH \"" + capName + "\"\nBUILTIN envGet 2\n," + (pos + 1)
            }
            emit "LOAD " + tv + "\n; TYPE " + varType + "\n," + (pos + 1)
        }
        emit "LOAD " + tv + "\n," + (pos + 1)
    }

    emit "PUSH \"\"\n," + (pos + 1)
}

func irInterpToIR(s, pos, lc, types) {
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
            // Tokenize and compile the inner expression as proper IR
            // (was: bare "LOAD <text>" — broken for anything but a single identifier)
            let exprToks = tokenize(expr)
            let exprNtoks = lineCount(exprToks)
            if exprNtoks > 0 {
                let ep = irExpr(exprToks, 0, exprNtoks, lc, types)
                code = code + pairVal(ep)
            } else {
                code = code + "PUSH \"\"\n"
            }
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

func irListLiteralIR(tokens, pos, ntoks, lc, types) {
    let p = pos + 1
    if tokAt(tokens, p) == "RBRACK" {
        emit "PUSH \"\"\n," + (p + 1)
    }
    let code = ""
    let ec = 0
    while tokAt(tokens, p) != "RBRACK" {
        if ec > 0 { p = p + 1 }
        let ep = irExpr(tokens, p, ntoks, lc, types)
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

func irStructLiteralIR(tokens, pos, ntoks, lc, types) {
    let name = tokVal(tokAt(tokens, pos))
    let p = pos + 2
    let code = "STRUCTNEW\n"
    while tokAt(tokens, p) != "RBRACE" {
        if tokType(tokAt(tokens, p)) == "ID" {
            let fname = tokVal(tokAt(tokens, p))
            p = p + 2
            let ep = irExpr(tokens, p, ntoks, lc, types)
            let ecode = pairVal(ep)
            p = pairPos(ep)
            if tokAt(tokens, p) == "COMMA" { p += 1 }
            code = code + ecode + "SETFIELD " + fname + "\n"
        } else { p += 1 }
    }
    emit code + "," + (p + 1)
}

func irCall(tokens, pos, ntoks, lc, types) {
    let fname = tokVal(tokAt(tokens, pos))

    // Special case: funcptr(IDENT) — emit a FUNCPTR <name> opcode
    // that pushes the address of the named function onto the value
    // stack. The native backend turns this into
    //   lea rax, [rip + funcOffset(name)]
    //   mov [rsp + vstack_slot], rax
    // Without this, irCall would evaluate `IDENT` as a regular
    // expression — which emits LOAD <name>, treating the name as
    // a local variable. That works in the C-emit path (where
    // `(char*)IDENT` decays to a function pointer in C) but
    // crashes in native because there's no local of that name.
    // Argument must be a bare identifier; anything else falls
    // through to normal arg evaluation (and is broken anyway).
    if fname == "funcptr" {
        let argTok = tokAt(tokens, pos + 2)
        if tokType(argTok) == "ID" && tokAt(tokens, pos + 3) == "RPAREN" {
            let funcName = tokVal(argTok)
            emit "FUNCPTR " + funcName + "\n," + (pos + 4)
        }
    }

    let p = pos + 2
    let code = ""
    let argc = 0
    while tokAt(tokens, p) != "RPAREN" {
        if argc > 0 { p += 1 }
        let ap = irExpr(tokens, p, ntoks, lc, types)
        code = code + pairVal(ap)
        p = pairPos(ap)
        argc += 1
    }

    // 2.0-alpha: if fname is a local tagged "fp" (function-pointer
    // local — assigned a `func(...)` lambda or a `funcptr(IDENT)`),
    // route through `BUILTIN callPtr <argc+1>`. The fp gets pushed
    // first (LOAD fname), then args follow, mirroring how an explicit
    // `callPtr(fp, a, b)` would compile. x64.k's callPtr handler
    // already maps argc → kr_callptr1..4.
    if irTypeOf(types, fname) == "fp" {
        emit "LOAD " + fname + "\n" + code + "BUILTIN callPtr " + (argc + 1) + "\n," + (p + 1)
    }

    // 2.0-alpha-3: closure dispatch. The local is a closure value
    // (env head with "__fp__" key + capture entries). Extract fp
    // from env, then call fp(env, user_args...). callPtr's first
    // arg is fp itself; the rest are passed to fp; argc = 1(fp) +
    // 1(env) + N(user args).
    if irTypeOf(types, fname) == "closure" {
        let fpExtract = "LOAD " + fname + "\nPUSH \"__fp__\"\nBUILTIN envGet 2\n"
        let envPush = "LOAD " + fname + "\n"
        emit fpExtract + envPush + code + "BUILTIN callPtr " + (argc + 2) + "\n," + (p + 1)
    }

    // builtins vs user functions.
    //
    // ⚠ Token-bounded match (NOT substring). Wrapping both sides with commas
    // ensures `add` doesn't get matched by `fadd`, `pos` by `pairPos`, etc.
    // The previous substring-only check silently routed user functions named
    // add/sub/mul/div/pos/etc. through the BUILTIN path → backends emitted
    // UNSUPPORTED markers → stack corruption at runtime. Bug found 2026-05-03.
    let builtins = "print,kp,printErr,readLine,input,readFile,writeFile,arg,argCount,len,count,substring,charAt,indexOf,contains,startsWith,endsWith,replace,trim,lstrip,rstrip,center,toLower,toUpper,repeat,padLeft,padRight,charCode,fromCharCode,splitBy,format,strReverse,isAlpha,isDigit,isSpace,toInt,parseInt,abs,min,max,pow,sqrt,sign,clamp,hex,bin,floor,ceil,round,split,length,first,last,head,tail,append,join,reverse,sort,unique,fill,zip,slice,listIndexOf,every,some,countOf,sumList,maxList,minList,range,words,lines,keys,values,hasKey,structNew,getField,setField,hasField,structFields,random,timestamp,environ,exit,assert,type,isTruthy,toStr,throw,mapHas,mapGet,mapSet,mapDel,exec,shellRun,fadd,fsub,fmul,fdiv,fsqrt,ffloor,fceil,fround,fformat,flt,fgt,feq,sbNew,sbAppend,sbToString,bufNew,bufStr,bufGetDword,bufSetDword,bufGetWord,bufGetQword,bufGetDwordAt,bufGetQwordAt,bufSetByte,bufGetByte,bufSetDwordAt,bufSetQwordAt,bufGetWordAt,bufSetWordAt,bufGetWordAtBE,bufGetDwordAtBE,bufGetQwordAtBE,handleOut,handleGet,handleInt,toHandle,ptrDeref,ptrIndex,callPtr,getLine,lineCount,envNew,envSet,envGet,makeResult,getResultTag,getResultVal,getResultEnv,getResultPos,gcAllocated,gcAllocCount,gcShadowCount,gcShadowPop,gcShadowPush,gcWalkAllocs,gcMark,gcSweep,gcFreelistCount,rdtsc,pause,mfence,lfence,sfence,gcLimit,gcSetLimit,gcCollect,gcReset,gcCheckpoint,gcRestore,gcSlabCount,gcSlabBytes,sockMake,sockBind,sockListen,sockAccept,sockRecv,sockSend,sockClose,sockRecvStr"
    if contains("," + builtins + ",", "," + fname + ",") {
        emit code + "BUILTIN " + fname + " " + argc + "\n," + (p + 1)
    }
    emit code + "CALL " + fname + " " + argc + "\n," + (p + 1)
}

// IR statement emitter
func irStmt(tokens, pos, ntoks, lc, inFunc, types) {
    let tok = tokAt(tokens, pos)
    let tt = tokType(tok)

    // let/const declaration
    if tok == "KW:let" || tok == "KW:const" {
        emit irLetIR(tokens, pos + 1, ntoks, lc, inFunc, types)
    }

    // emit/return
    if tok == "KW:emit" || tok == "KW:return" {
        let pair = irExpr(tokens, pos + 1, ntoks, lc, types)
        let code = pairVal(pair)
        let p = pairPos(pair)
        if tokAt(tokens, p) == "SEMI" { p += 1 }
        // 2.0-alpha-3 stage 6: restore shadow_sp before early return.
        // The function-exit wrap (irFuncIR) adds the same restore at
        // the implicit fall-through end; explicit RETURN bypasses that
        // unless we re-emit it here. inFunc=="0" → top-level (__main__);
        // skip the restore there since __sh_save isn't always present
        // in IR-mode entry blocks. (Top-level early return = process
        // exit anyway.)
        let restoreCode = ""
        if inFunc == "1" {
            restoreCode = "BUILTIN gcShadowCount 0\nLOAD __sh_save\nSUB\nBUILTIN gcShadowPop 1\nPOP\n"
        }
        emit code + restoreCode + "RETURN\n," + p
    }

    // if statement
    if tok == "KW:if" {
        emit irIfIR(tokens, pos + 1, ntoks, lc, inFunc, types)
    }

    // while loop
    if tok == "KW:while" {
        emit irWhileIR(tokens, pos + 1, ntoks, lc, inFunc, types)
    }

    // for-in loop
    if tok == "KW:for" {
        emit irForIR(tokens, pos + 1, ntoks, lc, inFunc, types)
    }

    // match
    if tok == "KW:match" {
        emit irMatchIR(tokens, pos + 1, ntoks, lc, inFunc, types)
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
        let pair = irExpr(tokens, pos + 1, ntoks, lc, types)
        let code = pairVal(pair)
        let p = pairPos(pair)
        if tokAt(tokens, p) == "SEMI" { p += 1 }
        emit code + "THROW\n," + p
    }

    if tok == "KW:try" {
        emit irTryIR(tokens, pos + 1, ntoks, lc, inFunc, types)
    }

    // Nested func declaration inside a block (e.g. `func helper(...) {...}`
    // sitting inside a `just run` body). Krypton has no closures, so a nested
    // func is semantically identical to a top-level FUNC. The file-scope
    // walk hoists nested funcs as siblings; here we simply skip past the
    // tokens so no IR is emitted at the nested call site.
    //
    // Detect a true declaration (KW:func ID LPAREN ...) — KW:func LPAREN is
    // a lambda expression and falls through to irExpr below.
    if (tok == "KW:func" || tok == "KW:fn") && tokType(tokAt(tokens, pos + 1)) == "ID" {
        let p = pos + 2  // past KW:func and name
        // skip params: LPAREN ... RPAREN
        if tokAt(tokens, p) == "LPAREN" {
            let pdepth = 1
            p += 1
            while p < ntoks && pdepth > 0 {
                let tt2 = tokAt(tokens, p)
                if tt2 == "LPAREN" { pdepth += 1 }
                if tt2 == "RPAREN" { pdepth -= 1 }
                p += 1
            }
        }
        // skip body: LBRACE ... RBRACE
        while p < ntoks && tokAt(tokens, p) != "LBRACE" { p += 1 }
        if tokAt(tokens, p) == "LBRACE" {
            let bdepth = 1
            p += 1
            while p < ntoks && bdepth > 0 {
                let tt3 = tokAt(tokens, p)
                if tt3 == "LBRACE" { bdepth += 1 }
                if tt3 == "RBRACE" { bdepth -= 1 }
                p += 1
            }
        }
        emit "," + p
    }

    // field assignment: ID DOT ID (DOT ID)* ASSIGN
    // 1.8.10: nested struct LHS supported via the same deferred-offset
    // accumulation that irPostfix uses for reads. Walk the DOT chain,
    // accumulate nested struct offsets, then emit a single typed write
    // at the leaf primitive field.
    if tt == "ID" {
        if tokAt(tokens, pos + 1) == "DOT" {
            if tokType(tokAt(tokens, pos + 2)) == "ID" {
                // Walk the chain to find the ASSIGN.
                let chainEnd = pos + 2
                while tokAt(tokens, chainEnd + 1) == "DOT" && tokType(tokAt(tokens, chainEnd + 2)) == "ID" {
                    chainEnd = chainEnd + 2
                }
                if tokAt(tokens, chainEnd + 1) == "ASSIGN" {
                    let objName = tokVal(tok)
                    let objType = irTypeOf(types, objName)
                    let didTypedWrite = 0
                    if startsWith(objType, "*") == "1" && len(objType) > 1 {
                        // Walk fields, accumulate offset, find leaf type.
                        let curType = objType    // "*Outer"
                        let acc = 0
                        let fpos = pos + 2
                        let walkOK = 1
                        let leafType = ""
                        while fpos <= chainEnd && walkOK == 1 {
                            let fname = tokVal(tokAt(tokens, fpos))
                            let sname = substring(curType, 1, len(curType))
                            let info  = irTypeOf(types, sname + "." + fname)
                            if len(info) == 0 { walkOK = 0 }
                            if walkOK == 1 {
                                let pipe1 = indexOf(info, "|")
                                let off   = toInt(substring(info, 0, pipe1))
                                let ft    = substring(info, pipe1 + 1, len(info))
                                acc = acc + off
                                if fpos == chainEnd {
                                    leafType = ft
                                } else {
                                    if startsWith(ft, "*") == "1" {
                                        curType = ft
                                    } else {
                                        // Tried to chain through a primitive — bail.
                                        walkOK = 0
                                    }
                                }
                            }
                            fpos = fpos + 2
                        }
                        if walkOK == 1 {
                            let setOp = ""
                            if leafType == "u8"  || leafType == "i8"  { setOp = "BUILTIN bufSetByte 3\n" }
                            if leafType == "u16" || leafType == "i16" { setOp = "BUILTIN bufSetWordAt 3\n" }
                            if leafType == "u32" || leafType == "i32" { setOp = "BUILTIN bufSetDwordAt 3\n" }
                            if leafType == "u64" || leafType == "i64" { setOp = "BUILTIN bufSetQwordAt 3\n" }
                            if len(setOp) > 0 {
                                let valp = irExpr(tokens, chainEnd + 2, ntoks, lc, types)
                                let p2 = pairPos(valp)
                                if tokAt(tokens, p2) == "SEMI" { p2 += 1 }
                                emit "LOAD " + objName + "\nPUSH " + acc + "\n" +
                                     pairVal(valp) + setOp + "POP\n," + p2
                                didTypedWrite = 1
                            }
                        }
                    }
                    if didTypedWrite == 0 && tokAt(tokens, pos + 3) == "ASSIGN" {
                        // Fall back to the legacy single-level env-style write.
                        let field = tokVal(tokAt(tokens, pos + 2))
                        let pair = irExpr(tokens, pos + 4, ntoks, lc, types)
                        let code = pairVal(pair)
                        let p = pairPos(pair)
                        if tokAt(tokens, p) == "SEMI" { p += 1 }
                        emit "LOAD " + objName + "\n" + code + "SETFIELD " + field + "\nSTORE " + objName + "\n," + p
                    }
                }
            }
        }
    }

    // compound assignment
    if tt == "ID" {
        let nt = tokAt(tokens, pos + 1)
        if nt == "PLUSEQ" || nt == "MINUSEQ" || nt == "STAREQ" || nt == "SLASHEQ" || nt == "MODEQ" {
            let name = tokVal(tok)
            let pair = irExpr(tokens, pos + 2, ntoks, lc, types)
            let rcode = pairVal(pair)
            let p = pairPos(pair)
            if tokAt(tokens, p) == "SEMI" { p += 1 }
            let op = "ADD\n"
            if nt == "MINUSEQ" { op = "SUB\n" }
            if nt == "STAREQ"  { op = "MUL\n" }
            if nt == "SLASHEQ" { op = "DIV\n" }
            if nt == "MODEQ"   { op = "MOD\n" }
            emit "LOAD " + name + "\n" + rcode + op + "STORE " + name + "\nLOAD " + name + "\nBUILTIN gcShadowPush 1\nPOP\n," + p
        }
    }

    // post-increment / post-decrement statement: i++  i--
    if tt == "ID" {
        let nt = tokAt(tokens, pos + 1)
        if nt == "PLUSPLUS" || nt == "MINUSMINUS" {
            let name = tokVal(tok)
            let p = pos + 2
            if tokAt(tokens, p) == "SEMI" { p += 1 }
            let op = "ADD\n"
            if nt == "MINUSMINUS" { op = "SUB\n" }
            emit "LOAD " + name + "\nPUSH 1\n" + op + "STORE " + name + "\n," + p
        }
    }

    // pre-increment / pre-decrement statement: ++i  --i
    if tok == "PLUSPLUS" || tok == "MINUSMINUS" {
        let name = tokVal(tokAt(tokens, pos + 1))
        let p = pos + 2
        if tokAt(tokens, p) == "SEMI" { p += 1 }
        let op = "ADD\n"
        if tok == "MINUSMINUS" { op = "SUB\n" }
        emit "LOAD " + name + "\nPUSH 1\n" + op + "STORE " + name + "\n," + p
    }

    // Phase C 1.8.7: typed-pointer subscript assignment `p[i] = v`.
    // Lowers to BUILTIN bufSet*At with proper sizeof(T) byte-offset
    // scaling, mirroring the read-side specialization in irPostfix.
    // Only fires when `name` has a recognised typed-pointer annotation;
    // untyped `p[i] = v` falls through to whatever existing handler
    // catches it (today: nothing — that's a future enhancement).
    if tt == "ID" && tokAt(tokens, pos + 1) == "LBRACK" {
        let name = tokVal(tok)
        let varType = irTypeOf(types, name)
        if len(varType) > 0 {
            // Find the matching RBRACK and check for an ASSIGN after.
            let depth = 1
            let pB = pos + 2
            while pB < ntoks && depth > 0 {
                let tk = tokAt(tokens, pB)
                if tk == "LBRACK" { depth += 1 }
                if tk == "RBRACK" { depth -= 1 }
                if depth > 0 { pB += 1 }
            }
            if tokAt(tokens, pB) == "RBRACK" && tokAt(tokens, pB + 1) == "ASSIGN" {
                let setOp = ""
                let scaleOp = ""
                if varType == "*u8" {
                    setOp = "BUILTIN bufSetByte 3\n"
                } else if varType == "*u16" || varType == "*i16" {
                    setOp = "BUILTIN bufSetWordAt 3\n"
                    scaleOp = "PUSH 2\nMUL\n"
                } else if varType == "*u32" || varType == "*i32" {
                    setOp = "BUILTIN bufSetDwordAt 3\n"
                    scaleOp = "PUSH 4\nMUL\n"
                } else if varType == "*u64" || varType == "*i64" {
                    setOp = "BUILTIN bufSetQwordAt 3\n"
                    scaleOp = "PUSH 8\nMUL\n"
                }
                if len(setOp) > 0 {
                    let idxp = irExpr(tokens, pos + 2, ntoks, lc, types)
                    let valp = irExpr(tokens, pB + 2, ntoks, lc, types)
                    let p = pairPos(valp)
                    if tokAt(tokens, p) == "SEMI" { p += 1 }
                    emit "LOAD " + name + "\n" + pairVal(idxp) + scaleOp +
                         pairVal(valp) + setOp + "POP\n," + p
                }
            }
        }
    }

    // plain assignment
    if tt == "ID" && tokAt(tokens, pos + 1) == "ASSIGN" {
        let name = tokVal(tok)
        let pair = irExpr(tokens, pos + 2, ntoks, lc, types)
        let code = pairVal(pair)
        let p = pairPos(pair)
        if tokAt(tokens, p) == "SEMI" { p += 1 }
        // 2.0-alpha-3 stage 6 prep: re-root the new value on the shadow
        // stack. Without this, a sweep between the reassignment and the
        // next read could collect the new heap-allocated value.
        emit code + "STORE " + name + "\nLOAD " + name + "\nBUILTIN gcShadowPush 1\nPOP\n," + p
    }

    // expression statement (function call)
    let pair = irExpr(tokens, pos, ntoks, lc, types)
    let code = pairVal(pair)
    let p = pairPos(pair)
    if tokAt(tokens, p) == "SEMI" { p += 1 }
    emit code + "POP\n," + p
}

// Phase C: serialize a type-token range to a compact string so it
// can be stored in the per-function types table. `*u8` → "*u8",
// `[*Vec3]` → "[*Vec3]". Mirrors the grammar of irSkipTypeBody.
func irTypeStr(tokens, start, end) {
    let p = start
    let sb = sbNew()
    while p < end {
        let tk = tokAt(tokens, p)
        if tk == "STAR"   { sb = sbAppend(sb, "*") }
        if tk == "LBRACK" { sb = sbAppend(sb, "[") }
        if tk == "RBRACK" { sb = sbAppend(sb, "]") }
        if startsWith(tk, "ID:") == "1" { sb = sbAppend(sb, substring(tk, 3, len(tk))) }
        if startsWith(tk, "KW:") == "1" { sb = sbAppend(sb, substring(tk, 3, len(tk))) }
        p += 1
    }
    emit sbToString(sb)
}

// Look up a name's type in the per-function types table.
// Each line is "name|type". Returns "" if not found.
func irTypeOf(types, name) {
    let n = lineCount(types)
    let i = 0
    while i < n {
        let line = getLine(types, i)
        let pipePos = indexOf(line, "|")
        if pipePos > 0 {
            if substring(line, 0, pipePos) == name {
                emit substring(line, pipePos + 1, len(line))
            }
        }
        i += 1
    }
    emit ""
}

// Phase C 1.8.9: total size in bytes of a struct, derived from the
// pre-scanned `<sname>.<field>|<offset>|<type>` lines. Returns the
// byte offset of the highest field plus its width — i.e. the
// sequential-layout total size, no padding/alignment.
func irStructSizeOf(types, sname) {
    // Prefer the explicit padded total recorded as `__size__.<sname>`
    // — written at the end of irScanStructTypesOnce after natural
    // alignment is applied. Fall back to scanning fields for older
    // type tables that don't carry the sentinel.
    let sizeKey = "__size__." + sname
    let sizeRec = irTypeOf(types, sizeKey)
    if len(sizeRec) > 0 { emit toInt(sizeRec) }

    let n = lineCount(types)
    let i = 0
    let prefix = sname + "."
    let totalSize = 0
    while i < n {
        let line = getLine(types, i)
        if startsWith(line, prefix) == "1" {
            let pipe1 = indexOf(line, "|")
            let rest  = substring(line, pipe1 + 1, len(line))
            let pipe2 = indexOf(rest, "|")
            let off   = toInt(substring(rest, 0, pipe2))
            let ft    = substring(rest, pipe2 + 1, len(rest))
            let fsize = 4
            if ft == "u8"  || ft == "i8"  { fsize = 1 }
            if ft == "u16" || ft == "i16" { fsize = 2 }
            if ft == "u32" || ft == "i32" { fsize = 4 }
            if ft == "u64" || ft == "i64" { fsize = 8 }
            let endOff = off + fsize
            if endOff > totalSize { totalSize = endOff }
        }
        i += 1
    }
    emit totalSize
}

// Phase B: type-annotation parser. Eats `(*)* base` where base is
// either an IDENT/KW or a bracketed `[type]`. Recurses for nested
// `[*Vec3]`-style forms. Returns the position AFTER the type body
// (NOT the `:` itself — caller advances past `:` first).
func irSkipTypeBody(tokens, pos) {
    let p = pos
    while tokAt(tokens, p) == "STAR" { p += 1 }
    if tokAt(tokens, p) == "LBRACK" {
        p += 1
        p = irSkipTypeBody(tokens, p)
        if tokAt(tokens, p) == "RBRACK" { p += 1 }
        emit p
    }
    let tk = tokAt(tokens, p)
    if startsWith(tk, "ID:") == "1" || startsWith(tk, "KW:") == "1" { p += 1 }
    emit p
}

// Eat `: TYPE` if present. Returns position after the annotation
// (or the original position if none was present).
func irSkipTypeAnnotation(tokens, pos) {
    if tokAt(tokens, pos) != "COLON" { emit pos }
    emit irSkipTypeBody(tokens, pos + 1)
}

func irLetIR(tokens, pos, ntoks, lc, inFunc, types) {
    let name = tokVal(tokAt(tokens, pos))
    // Phase C 1.8.9: `let local TYPE name` — heap-allocate sizeof(TYPE)
    // bytes via bufNew and store the pointer in `name`. Same memory
    // model as a heap struct, but the syntax matches what true stack
    // allocation will look like once the x64.k frame layout supports
    // it. The pre-scan in irScanFuncTypes already recorded `name|*TYPE`
    // so reads/writes via `name.field` lower to typed buf calls.
    if name == "local" {
        let typeTk = tokAt(tokens, pos + 1)
        let varTk  = tokAt(tokens, pos + 2)
        if startsWith(typeTk, "ID:") == "1" && startsWith(varTk, "ID:") == "1" {
            let typeName = substring(typeTk, 3, len(typeTk))
            let varName  = substring(varTk, 3, len(varTk))
            let structSize = irStructSizeOf(types, typeName)
            if structSize > 0 {
                let p = pos + 3
                if tokAt(tokens, p) == "SEMI" { p += 1 }
                let baseCode = "LOCAL " + varName + "\nPUSH " + structSize +
                               "\nBUILTIN bufNew 1\nSTORE " + varName + "\n"
                // Emit default-value field initializers captured at
                // struct-scan time. Walk types table for
                // `__default__.<typeName>.<fname>|val` lines and emit
                // a typed write for each, using the field's offset/type
                // looked up in the same table.
                let initCode = ""
                let dpfx = "__default__." + typeName + "."
                let dn = lineCount(types)
                let di = 0
                while di < dn {
                    let dline = getLine(types, di)
                    if startsWith(dline, dpfx) == "1" {
                        let dpipe = indexOf(dline, "|")
                        let dfname = substring(dline, len(dpfx), dpipe)
                        let dval = substring(dline, dpipe + 1, len(dline))
                        let finfo = irTypeOf(types, typeName + "." + dfname)
                        if len(finfo) > 0 {
                            let fpipe = indexOf(finfo, "|")
                            let foff = substring(finfo, 0, fpipe)
                            let ft = substring(finfo, fpipe + 1, len(finfo))
                            let setOp = ""
                            if ft == "u8"  || ft == "i8"  { setOp = "BUILTIN bufSetByte 3\n" }
                            if ft == "u16" || ft == "i16" { setOp = "BUILTIN bufSetWordAt 3\n" }
                            if ft == "u32" || ft == "i32" { setOp = "BUILTIN bufSetDwordAt 3\n" }
                            if ft == "u64" || ft == "i64" { setOp = "BUILTIN bufSetQwordAt 3\n" }
                            if len(setOp) > 0 {
                                initCode = initCode + "LOAD " + varName +
                                           "\nPUSH " + foff +
                                           "\nPUSH " + dval +
                                           "\n" + setOp + "POP\n"
                            }
                        }
                    }
                    di += 1
                }
                emit baseCode + initCode + "," + p
            }
        }
    }
    let p = irSkipTypeAnnotation(tokens, pos + 1)
    // skip ASSIGN
    p += 1
    let pair = irExpr(tokens, p, ntoks, lc, types)
    let code = pairVal(pair)
    p = pairPos(pair)
    if tokAt(tokens, p) == "SEMI" { p += 1 }
    // 2.0-alpha-3 GC stage 3: push the just-stored value onto the shadow
    // stack so the mark walker (stages 4-5) sees it as a root. The push
    // is unconditional — if the value is a smart-int, the marker's
    // range-check filters it out at scan time (no false retention).
    // Lifetime is function-scoped (no per-block popping); the function
    // prologue/epilogue saves/restores shadow_sp.
    let pushCode = "LOAD " + name + "\nBUILTIN gcShadowPush 1\nPOP\n"
    emit "LOCAL " + name + "\n" + code + "STORE " + name + "\n" + pushCode + "," + p
}

func irBlockIR(tokens, pos, ntoks, lc, inFunc, types) {
    // pos is at LBRACE
    let p = pos + 1
    let sbBlock = sbNew()
    let nlc = lc
    while tokAt(tokens, p) != "RBRACE" {
        let sp = irStmt(tokens, p, ntoks, nlc, inFunc, types)
        sbBlock = sbAppend(sbBlock, pairVal(sp))
        p = pairPos(sp)
        nlc = nlc + 1
    }
    emit sbToString(sbBlock) + "," + (p + 1)
}

func irIfIR(tokens, pos, ntoks, lc, inFunc, types) {
    let pair = irExpr(tokens, pos, ntoks, lc, types)
    // Wrap the condition in BUILTIN isTruthy so JUMPIFNOT sees a 0/1
    // instead of testing raw pointer non-zero. Empty string ("") is a
    // valid string pointer (non-zero) but should be FALSY per Krypton's
    // truthiness rules — without this wrap, `if ""` takes the truthy
    // branch on native (matches what the C-emit path does via kr_truthy()).
    let condCode = pairVal(pair) + "BUILTIN isTruthy 1\n"
    let p = pairPos(pair)
    let elseLabel = irLabel("_else", pos)
    let endLabel = irLabel("_endif", pos)
    let nlc = lc + 1
    let bp = irBlockIR(tokens, p, ntoks, nlc, inFunc, types)
    let bodyCode = pairVal(bp)
    p = pairPos(bp)
    nlc = nlc + 1
    if tokAt(tokens, p) == "KW:else" {
        if tokAt(tokens, p + 1) == "KW:if" {
            let ep = irIfIR(tokens, p + 2, ntoks, nlc, inFunc, types)
            let elseCode = pairVal(ep)
            p = pairPos(ep)
            emit condCode + "JUMPIFNOT " + elseLabel + "\n" + bodyCode + "JUMP " + endLabel + "\n" + "LABEL " + elseLabel + "\n" + elseCode + "LABEL " + endLabel + "\n," + p
        } else {
            let ep = irBlockIR(tokens, p + 1, ntoks, nlc, inFunc, types)
            let elseCode = pairVal(ep)
            p = pairPos(ep)
            emit condCode + "JUMPIFNOT " + elseLabel + "\n" + bodyCode + "JUMP " + endLabel + "\n" + "LABEL " + elseLabel + "\n" + elseCode + "LABEL " + endLabel + "\n," + p
        }
    }
    emit condCode + "JUMPIFNOT " + endLabel + "\n" + bodyCode + "LABEL " + endLabel + "\n," + p
}

func irWhileIR(tokens, pos, ntoks, lc, inFunc, types) {
    let loopLabel = irLabel("_wloop", pos)
    let endLabel = irLabel("_wend", pos)
    let nlc = lc + 1
    let pair = irExpr(tokens, pos, ntoks, nlc, types)
    // Wrap condition in BUILTIN isTruthy — see irIfIR for rationale.
    let condCode = pairVal(pair) + "BUILTIN isTruthy 1\n"
    let p = pairPos(pair)
    let bp = irBlockIR(tokens, p, ntoks, nlc, inFunc, types)
    let bodyCode = pairVal(bp)
    p = pairPos(bp)
    // Resolve loose BREAKs in this loop's body to a JUMP to its end label.
    // Bottom-up processing: any nested loop will have already replaced its
    // own BREAKs with its own JUMP-to-its-end-label, so only this loop's
    // direct breaks remain as bare "BREAK\n" lines. Same idea for CONTINUE
    // → JUMP to this loop's top label (where the cond gets re-tested).
    bodyCode = replace(bodyCode, "BREAK\n", "JUMP " + endLabel + "\n")
    bodyCode = replace(bodyCode, "CONTINUE\n", "JUMP " + loopLabel + "\n")
    emit "LABEL " + loopLabel + "\n" + condCode + "JUMPIFNOT " + endLabel + "\n" + bodyCode + "JUMP " + loopLabel + "\n" + "LABEL " + endLabel + "\n," + p
}

func irForIR(tokens, pos, ntoks, lc, inFunc, types) {
    let varName = tokVal(tokAt(tokens, pos))
    let p = pos + 2
    let pair = irExpr(tokens, p, ntoks, lc, types)
    let collCode = pairVal(pair)
    p = pairPos(pair)
    let loopLabel = irLabel("_floop", pos)
    let endLabel = irLabel("_fend", pos)
    let idxVar = "_for_i_" + pos
    let cntVar = "_for_cnt_" + pos
    let colVar = "_for_col_" + pos
    let nlc = lc + 1
    let bp = irBlockIR(tokens, p, ntoks, nlc, inFunc, types)
    let bodyCode = pairVal(bp)
    p = pairPos(bp)
    // Same break-resolution as irWhileIR — see comment there. CONTINUE
    // jumps to a label placed RIGHT BEFORE the increment step, so the
    // for-loop's iteration variable still advances on continue.
    let contLabel = irLabel("_fcont", pos)
    bodyCode = replace(bodyCode, "BREAK\n", "JUMP " + endLabel + "\n")
    bodyCode = replace(bodyCode, "CONTINUE\n", "JUMP " + contLabel + "\n")
    let code = collCode + "LOCAL " + colVar + "\n" + "STORE " + colVar + "\n"
    code = code + "LOCAL " + idxVar + "\n" + "PUSH 0\n" + "STORE " + idxVar + "\n"
    code = code + "LOCAL " + cntVar + "\n" + "LOAD " + colVar + "\n" + "BUILTIN length 1\n" + "STORE " + cntVar + "\n"
    code = code + "LABEL " + loopLabel + "\n"
    code = code + "LOAD " + idxVar + "\n" + "LOAD " + cntVar + "\n" + "LT\n"
    code = code + "JUMPIFNOT " + endLabel + "\n"
    code = code + "LOCAL " + varName + "\n"
    code = code + "LOAD " + colVar + "\n" + "LOAD " + idxVar + "\n" + "BUILTIN split 2\n" + "STORE " + varName + "\n"
    code = code + bodyCode
    code = code + "LABEL " + contLabel + "\n"
    code = code + "LOAD " + idxVar + "\n" + "PUSH 1\n" + "ADD\n" + "STORE " + idxVar + "\n"
    code = code + "JUMP " + loopLabel + "\n"
    code = code + "LABEL " + endLabel + "\n"
    emit code + "," + p
}

func irMatchIR(tokens, pos, ntoks, lc, inFunc, types) {
    let pair = irExpr(tokens, pos, ntoks, lc, types)
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
            let bp = irBlockIR(tokens, p, ntoks, nlc, inFunc, types)
            code = code + pairVal(bp)
            p = pairPos(bp)
        } else {
            let cp = irExpr(tokens, p, ntoks, nlc, types)
            let caseCode = pairVal(cp)
            p = pairPos(cp)
            let bp = irBlockIR(tokens, p, ntoks, nlc, inFunc, types)
            let bodyCode = pairVal(bp)
            p = pairPos(bp)
            code = code + "LOAD " + matchVar + "\n" + caseCode + "EQ\n" + "JUMPIFNOT " + nextLabel + "\n" + bodyCode + "JUMP " + endLabel + "\n" + "LABEL " + nextLabel + "\n"
        }
        nlc = nlc + 1
    }
    p += 1
    emit code + "LABEL " + endLabel + "\n," + p
}

func irTryIR(tokens, pos, ntoks, lc, inFunc, types) {
    let catchLabel = irLabel("_catch", pos)
    let endLabel = irLabel("_tryend", pos)
    let nlc = lc + 1
    let bp = irBlockIR(tokens, pos, ntoks, nlc, inFunc, types)
    let bodyCode = pairVal(bp)
    let p = pairPos(bp)
    if tokAt(tokens, p) == "KW:catch" {
        p += 1
        let catchVar = "_err"
        if tokType(tokAt(tokens, p)) == "ID" {
            catchVar = tokVal(tokAt(tokens, p))
            p += 1
        }
        let cp = irBlockIR(tokens, p, ntoks, nlc, inFunc, types)
        let catchCode = pairVal(cp)
        p = pairPos(cp)
        emit "TRY " + catchLabel + "\n" + bodyCode + "ENDTRY\n" + "JUMP " + endLabel + "\n" + "LABEL " + catchLabel + "\n" + "LOCAL " + catchVar + "\n" + "STORE " + catchVar + "\n" + catchCode + "LABEL " + endLabel + "\n," + p
    }
    emit "TRY " + catchLabel + "\n" + bodyCode + "ENDTRY\n" + "LABEL " + catchLabel + "\n" + "LABEL " + endLabel + "\n," + p
}

// Phase C 1.8.8: pre-scan the entire token stream for struct definitions
// and emit field-offset entries the lookup table can find. Each struct
// produces lines of the form `StructName.field|byteOffset|fieldType`.
// Primitive widths (u8/i8/u16/i16/u32/i32/u64/i64) get exact sizes.
// 1.8.10: a nested struct field (type matches a struct already declared
// earlier in the file) gets sized from the previously-recorded fields,
// and is recorded as `*StructName` so later field-chain access (`a.b.c`)
// can resolve `a.b` to a typed pointer to the nested region.
// Multi-pass struct scan: each pass resolves one more level of nested
// struct sizing using the previous pass's output as size hints. Iterate
// until output stabilizes (or hard cap at 16 — that's 16 levels of
// struct nesting, plenty for any practical schema). Eliminates the
// lexical-ordering requirement; structs can reference each other in
// any declaration order.
func irScanStructTypes(tokens, ntoks) {
    let prev = ""
    let curr = irScanStructTypesOnce(tokens, ntoks, "")
    let iters = 0
    while curr != prev && iters < 16 {
        prev = curr
        curr = irScanStructTypesOnce(tokens, ntoks, curr)
        iters = iters + 1
    }
    emit curr
}

func irScanStructTypesOnce(tokens, ntoks, sizeHints) {
    let sb = sbNew()
    let i = 0
    while i < ntoks {
        let tk = tokAt(tokens, i)
        if tk == "KW:struct" || tk == "KW:class" || tk == "KW:type" {
            let snameTk = tokAt(tokens, i + 1)
            if startsWith(snameTk, "ID:") == "1" && tokAt(tokens, i + 2) == "LBRACE" {
                let sname = substring(snameTk, 3, len(snameTk))
                let p = i + 3
                let off = 0
                let maxAlign = 1
                while p < ntoks && tokAt(tokens, p) != "RBRACE" {
                    if tokAt(tokens, p) == "KW:let" {
                        let fnameTk = tokAt(tokens, p + 1)
                        if startsWith(fnameTk, "ID:") == "1" {
                            let fname = substring(fnameTk, 3, len(fnameTk))
                            let ftype = "u32"      // default if no annotation
                            let fsize = 4
                            let falign = 4
                            let q = p + 2
                            if tokAt(tokens, q) == "COLON" {
                                let typeStart = q + 1
                                let typeEnd = irSkipTypeBody(tokens, typeStart)
                                ftype = irTypeStr(tokens, typeStart, typeEnd)
                                if ftype == "u8"  || ftype == "i8"  { fsize = 1  falign = 1 }
                                if ftype == "u16" || ftype == "i16" { fsize = 2  falign = 2 }
                                if ftype == "u32" || ftype == "i32" { fsize = 4  falign = 4 }
                                if ftype == "u64" || ftype == "i64" { fsize = 8  falign = 8 }
                                // Nested struct: ftype names a struct.
                                // Look up size + alignment in pass-1
                                // hints. Empty on first pass → falls
                                // back to fsize=4, falign=4.
                                let nestedSize = irStructSizeOf(sizeHints, ftype)
                                if nestedSize > 0 {
                                    fsize = nestedSize
                                    let nalignRec = irTypeOf(sizeHints, "__align__." + ftype)
                                    if len(nalignRec) > 0 {
                                        falign = toInt(nalignRec)
                                    } else {
                                        falign = 4    // safe default
                                    }
                                    ftype = "*" + ftype
                                }
                                q = typeEnd
                            }
                            // Natural alignment: round off up to falign
                            // before placing this field.
                            if off % falign != 0 {
                                off = off + (falign - off % falign)
                            }
                            if falign > maxAlign { maxAlign = falign }
                            sb = sbAppend(sb, sname + "." + fname + "|" + off + "|" + ftype + "\n")
                            off = off + fsize
                            // Capture int-literal default if present
                            // (`field: u32 = 42`). Stored under the
                            // separate `__default__.` prefix so it
                            // doesn't pollute irTypeOf lookups.
                            if tokAt(tokens, q) == "ASSIGN" {
                                let dvTk = tokAt(tokens, q + 1)
                                if tokType(dvTk) == "INT" {
                                    sb = sbAppend(sb, "__default__." + sname + "." + fname + "|" + tokVal(dvTk) + "\n")
                                }
                                while q < ntoks && tokAt(tokens, q) != "SEMI" && tokAt(tokens, q) != "KW:let" && tokAt(tokens, q) != "RBRACE" {
                                    q += 1
                                }
                            }
                            p = q
                            continue
                        }
                    }
                    p += 1
                }
                // Pad struct total size up to maxAlign so arrays of
                // this struct stay properly aligned. Recorded under
                // `__size__.<sname>` so irStructSizeOf can prefer it.
                // `__align__.<sname>` exposes the chosen alignment so
                // outer structs that contain this one can place it
                // tightly instead of padding to a worst-case 8.
                let totalSize = off
                if totalSize % maxAlign != 0 {
                    totalSize = totalSize + (maxAlign - totalSize % maxAlign)
                }
                sb = sbAppend(sb, "__size__." + sname + "|" + totalSize + "\n")
                sb = sbAppend(sb, "__align__." + sname + "|" + maxAlign + "\n")
            }
        }
        i += 1
    }
    emit sbToString(sb)
}

// Phase C: pre-scan the function body for `let X: TYPE` patterns and
// build a `name|type\n...` table the IR generator can consult when
// emitting LOADs/INDEXes. Only LEXICAL scope is captured — names are
// added regardless of nesting (good enough for typed-pointer lowering;
// shadowing / scope-precise tracking is future work).
func irScanFuncTypes(tokens, bodyStart) {
    if tokAt(tokens, bodyStart) != "LBRACE" { emit "" }
    let p = bodyStart + 1
    let depth = 1
    let nTok = lineCount(tokens)
    let sb = sbNew()
    while p < nTok && depth > 0 {
        let tk = tokAt(tokens, p)
        if tk == "LBRACE" { depth += 1  p += 1  continue }
        if tk == "RBRACE" { depth -= 1  p += 1  continue }
        if tk == "KW:let" || tk == "KW:const" {
            let nameTk = tokAt(tokens, p + 1)
            if startsWith(nameTk, "ID:") == "1" {
                let nameStr = substring(nameTk, 3, len(nameTk))
                // Phase C 1.8.9: `let local TYPE name` — record name as `*TYPE`.
                if nameStr == "local" {
                    let typeTk = tokAt(tokens, p + 2)
                    let varTk  = tokAt(tokens, p + 3)
                    if startsWith(typeTk, "ID:") == "1" && startsWith(varTk, "ID:") == "1" {
                        let typeName = substring(typeTk, 3, len(typeTk))
                        let varName  = substring(varTk, 3, len(varTk))
                        sb = sbAppend(sb, varName + "|*" + typeName + "\n")
                        p = p + 4
                        continue
                    }
                }
                if tokAt(tokens, p + 2) == "COLON" {
                    let typeStart = p + 3
                    let typeEnd = irSkipTypeBody(tokens, typeStart)
                    sb = sbAppend(sb, nameStr + "|" + irTypeStr(tokens, typeStart, typeEnd) + "\n")
                    p = typeEnd
                    continue
                }
                // 2.0-alpha: detect function-pointer locals so plain
                // `f(args)` calls route through callPtr at irCall time.
                // 2.0-alpha-3 unification: ALL lambdas tagged `closure`
                // (env-wrapped uniformly, with __fp__ entry + capture
                // entries if any). funcptr() result stays `fp` (raw).
                // Per benchmark, closure-call overhead is ~0 (within
                // noise) so universal env-wrap is acceptable.
                if tokAt(tokens, p + 2) == "ASSIGN" {
                    let rhsTk = tokAt(tokens, p + 3)
                    let isLam = "0"
                    let isFuncPtr = "0"
                    if rhsTk == "KW:func" || rhsTk == "KW:fn" {
                        if tokAt(tokens, p + 4) == "LPAREN" { isLam = "1" }
                    }
                    if rhsTk == "ID:funcptr" {
                        if tokAt(tokens, p + 4) == "LPAREN" { isFuncPtr = "1" }
                    }
                    if isLam == "1" {
                        sb = sbAppend(sb, nameStr + "|closure\n")
                    } else {
                        if isFuncPtr == "1" {
                            sb = sbAppend(sb, nameStr + "|fp\n")
                        }
                    }
                }
            }
        }
        p += 1
    }
    emit sbToString(sb)
}

// 2.0-alpha: lambda lowering. KW:func at pos with LPAREN immediately
// after (no name). Emits a top-level FUNC <synthName> N IR with the
// lambda body so a sibling FUNCPTR <synthName> can take its address.
//
// 2.0-alpha-3: closure support via env passing. When the lambda body
// has free vars, prepend a hidden `__env` first param. Free vars in
// the body get tagged as `__cap__:<name>` so irPrimary's ID handler
// rewrites `LOAD <freeVar>` to `LOAD __env; PUSH "<name>"; envGet 2`.
// Lambda creation site builds the env (envSet for each capture +
// "__fp__" entry); irCall dispatches closure-typed locals through the
// env-extracting call sequence.
func irLambdaIR(tokens, pos, ntoks, lambdaName) {
    // pos is at KW:func; pos+1 is LPAREN.
    let p = pos + 2
    let userParams = ""
    let paramTypes = ""
    let pc = 0
    let paramCsv = ""
    while tokAt(tokens, p) != "RPAREN" {
        let pt = tokAt(tokens, p)
        if tokType(pt) == "ID" {
            let pname = tokVal(pt)
            userParams = userParams + "PARAM " + pname + "\n"
            if len(paramCsv) > 0 { paramCsv = paramCsv + "," }
            paramCsv = paramCsv + pname
            pc += 1
            if tokAt(tokens, p + 1) == "COLON" {
                let typeStart = p + 2
                let typeEnd = irSkipTypeBody(tokens, typeStart)
                let ptype = irTypeStr(tokens, typeStart, typeEnd)
                paramTypes = paramTypes + pname + "|" + ptype + "\n"
                p = typeEnd
                if tokAt(tokens, p) == "COMMA" { p += 1 }
            } else { p += 1 }
        } else { p += 1 }
    }
    p += 1   // past RPAREN
    if tokAt(tokens, p) == "ARROW" { p = p + 2 }

    // 2.0-alpha-3 unification: ALL lambdas get __env first PARAM so
    // closure dispatch is uniform. Capture-free lambdas just ignore
    // __env. Per benchmark, the overhead is below noise.
    let bodyEnd = skipBlock(tokens, p)
    let freeVars = findFreeVars(tokens, p, bodyEnd, paramCsv)
    let captureTypes = ""
    let allParams = "PARAM __env\n" + userParams
    pc = pc + 1
    if len(freeVars) > 0 {
        let fcount = count(freeVars)
        let fi = 0
        while fi < fcount {
            let fname = split(freeVars, fi)
            captureTypes = captureTypes + fname + "|__cap__:" + fname + "\n"
            fi = fi + 1
        }
    }

    let funcTypes = irScanStructTypes(tokens, ntoks) + irScanFuncTypes(tokens, p) + paramTypes + captureTypes
    let bp = irBlockIR(tokens, p, ntoks, 0, "1", funcTypes)
    let bodyCode = pairVal(bp)
    p = pairPos(bp)
    emit "FUNC " + lambdaName + " " + pc + "\n" + allParams + bodyCode + "RETURN\nEND\n\n," + p
}

func irFuncIR(tokens, pos, ntoks) {
    // pos is at KW:func
    let fname = tokVal(tokAt(tokens, pos + 1))
    let p = pos + 3
    let params = ""
    let paramTypes = ""
    let pc = 0
    while tokAt(tokens, p) != "RPAREN" {
        let pt = tokAt(tokens, p)
        if tokType(pt) == "ID" {
            let pname = tokVal(pt)
            params = params + "PARAM " + pname + "\n"
            pc += 1
            if tokAt(tokens, p + 1) == "COLON" {
                let typeStart = p + 2
                let typeEnd = irSkipTypeBody(tokens, typeStart)
                let ptype = irTypeStr(tokens, typeStart, typeEnd)
                paramTypes = paramTypes + pname + "|" + ptype + "\n"
                p = typeEnd
                if tokAt(tokens, p) == "COMMA" { p += 1 }
            } else { p += 1 }
        } else { p += 1 }
    }
    p += 1
    // skip -> return type
    if tokAt(tokens, p) == "ARROW" { p = p + 2 }
    // Phase C: pre-scan body for `let X: TYPE` so irPrimary can tag
    // LOADs with type hints and irPostfix can specialize INDEX into
    // typed-pointer reads. Also scan struct definitions across the
    // whole token stream so `*Vec3.field` lowers to a typed offset
    // read. paramTypes appended last so typed params (e.g. `cb: fp`)
    // route through callPtr in irCall.
    let funcTypes = irScanStructTypes(tokens, ntoks) + irScanFuncTypes(tokens, p) + paramTypes
    let bp = irBlockIR(tokens, p, ntoks, 0, "1", funcTypes)
    let bodyCode = pairVal(bp)
    p = pairPos(bp)
    // 1.7.9 — auto-emit gcCheckpoint/gcRestore around functions whose name
    // starts with "pure_". Wraps the body so all per-function allocations
    // get reclaimed on return. CAVEAT: the wrapping appends BEFORE the
    // implicit function-end RETURN only, so functions with explicit
    // emit/return statements don't reach the restore. pure_ functions
    // should be procedural (side-effects only, no return value).
    if startsWith(fname, "pure_") {
        bodyCode = "LOCAL _gc_ck\nBUILTIN gcCheckpoint 0\nSTORE _gc_ck\n" + bodyCode + "LOAD _gc_ck\nBUILTIN gcRestore 1\nPOP\n"
    }
    // 2.0-alpha-3 GC stage 3: wrap function body with shadow_sp save/restore.
    // Per-let pushes (in irLetIR) accumulate during function execution; this
    // resets shadow_sp to the entry value at function exit, popping every
    // pushed root at once. CAVEAT: explicit `return`/`emit` early-exits
    // bypass the restore (RETURN op jumps straight to the function
    // epilogue), causing shadow stack growth. Mitigation deferred until
    // stages 4-5 land — pre-collection the imbalance is harmless.
    // 2.0-alpha-3 stage 6: wrap EVERY function (including pure_) with
    // shadow-stack save/restore. pure_ functions also have gcCheckpoint
    // wrapping, but that doesn't conflict — the two operate on different
    // GC mechanisms (arena epoch vs. mark-sweep root tracking).
    // Push every PARAM onto the shadow stack at entry. Without this,
    // function-arg heap pointers wouldn't be roots — sweep could
    // collect them while the callee still uses them.
    let paramPushes = ""
    let plnCount = lineCount(params)
    let pli = 0
    while pli < plnCount {
        let pln = getLine(params, pli)
        if startsWith(pln, "PARAM ") == "1" {
            let pn = substring(pln, 6, len(pln))
            paramPushes = paramPushes + "LOAD " + pn + "\nBUILTIN gcShadowPush 1\nPOP\n"
        }
        pli += 1
    }
    bodyCode = "LOCAL __sh_save\nBUILTIN gcShadowCount 0\nSTORE __sh_save\n" + paramPushes + bodyCode +
               "BUILTIN gcShadowCount 0\nLOAD __sh_save\nSUB\nBUILTIN gcShadowPop 1\nPOP\n"
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


// 2.0-alpha-3: --port-1to2 migration scanner. Walks tokens, flags
// patterns that are valid in 1.x but need attention before 2.0 ships.
// Output goes to stderr; no code generated; caller exits 0.
func emitPortWarnings(tokens, ntoks, fname) {
    let warnings = 0
    let i = 0
    let topLevelLets = ""    // names declared at file scope

    // Pre-pass: collect file-scope `let X = ...` names
    let pp = 0
    let ppDepth = 0
    while pp < ntoks {
        let pt = tokAt(tokens, pp)
        if pt == "LBRACE" { ppDepth = ppDepth + 1 }
        if pt == "RBRACE" { ppDepth = ppDepth - 1 }
        if ppDepth == 0 && (pt == "KW:let" || pt == "KW:const") {
            let nameTk = tokAt(tokens, pp + 1)
            if startsWith(nameTk, "ID:") == "1" {
                let nm = substring(nameTk, 3, len(nameTk))
                if len(topLevelLets) > 0 { topLevelLets = topLevelLets + "," }
                topLevelLets = topLevelLets + nm
            }
        }
        pp = pp + 1
    }

    // Main pass
    while i < ntoks {
        let tok = tokAt(tokens, i)

        // bufNew / rawAlloc / rawFree — manual heap
        if tok == "ID:bufNew" && tokAt(tokens, i + 1) == "LPAREN" {
            printErr(fname + ": warning [port-1to2]: bufNew() — manual heap allocation. In 2.0, prefer typed `let local TYPE name` (stack alloc) or wait for GC reclamation.")
            warnings = warnings + 1
        }
        if tok == "ID:rawAlloc" && tokAt(tokens, i + 1) == "LPAREN" {
            printErr(fname + ": warning [port-1to2]: rawAlloc() — escapes GC; 2.0 will require explicit `unsafe` block or paired rawFree.")
            warnings = warnings + 1
        }
        if tok == "ID:rawFree" && tokAt(tokens, i + 1) == "LPAREN" {
            printErr(fname + ": warning [port-1to2]: rawFree() — only needed for rawAlloc'd memory under 2.0 GC.")
            warnings = warnings + 1
        }

        // Raw pointer arithmetic
        if tok == "ID:ptrAdd" && tokAt(tokens, i + 1) == "LPAREN" {
            printErr(fname + ": warning [port-1to2]: ptrAdd() — raw pointer arithmetic. Prefer typed `*u8 + n` syntax in 2.0.")
            warnings = warnings + 1
        }
        if tok == "ID:ptrToInt" && tokAt(tokens, i + 1) == "LPAREN" {
            printErr(fname + ": warning [port-1to2]: ptrToInt() — converts pointer to int. Loses GC-tracking under 2.0.")
            warnings = warnings + 1
        }

        // Raw memory access
        if tok == "ID:rawReadByte" || tok == "ID:rawReadWord" || tok == "ID:rawReadQword" {
            if tokAt(tokens, i + 1) == "LPAREN" {
                let fn = substring(tok, 3, len(tok))
                printErr(fname + ": warning [port-1to2]: " + fn + "() — raw memory read. Prefer typed pointer indexing (`p[i]` with `let p: *u8 = ...`) for 2.0 safety.")
                warnings = warnings + 1
            }
        }
        if tok == "ID:rawWriteWord" || tok == "ID:rawWriteQword" {
            if tokAt(tokens, i + 1) == "LPAREN" {
                let fn = substring(tok, 3, len(tok))
                printErr(fname + ": warning [port-1to2]: " + fn + "() — raw memory write. Prefer typed pointer assignment in 2.0.")
                warnings = warnings + 1
            }
        }

        // cfunc { } block — emitted as a single CBLOCK token by the
        // tokenizer (compile.k:219), not KW:cfunc.
        if tokType(tok) == "CBLOCK" {
            printErr(fname + ": warning [port-1to2]: `cfunc { }` block — C-language body. 2.0 prefers pure-Krypton implementations once Win32 ABI marshalling lands.")
            warnings = warnings + 1
        }

        // Mutable file-scope global: name from topLevelLets reassigned
        // outside its own let.
        if tokType(tok) == "ID" {
            let nm2 = tokVal(tok)
            if contains("," + topLevelLets + ",", "," + nm2 + ",") {
                let nextTok = tokAt(tokens, i + 1)
                if nextTok == "ASSIGN" {
                    let prev = ""
                    if i > 0 { prev = tokAt(tokens, i - 1) }
                    if prev != "KW:let" && prev != "KW:const" {
                        printErr(fname + ": warning [port-1to2]: file-scope `" + nm2 + "` reassigned — mutable module globals are broken in the native pipeline. Confine state to function scope or pass explicitly.")
                        warnings = warnings + 1
                    }
                }
            }
        }

        i = i + 1
    }

    if warnings == 0 {
        printErr(fname + ": port-1to2 clean — no 2.0 migration concerns flagged.")
    } else {
        printErr(fname + ": port-1to2 done — " + warnings + " warning(s).")
    }
}


just run {
    let kccVer = "2.2.0"

    // Parse flags: --version, --ir, -o OUTFILE, --port-1to2
    // 1.8.4: removed --headers. Install root is fixed at C:\krypton;
    // stdlib lives at <root>/stdlib and C bindings at <root>/headers.
    // The new `k:` / `c:` import prefixes resolve under those.
    // 2.0-alpha-3: --port-1to2 is a diagnostic-only mode that scans
    // source for patterns needing attention before a 2.0 upgrade.
    let irMode = 0
    let portMode = 0
    // Install root resolution order (2.1.1):
    //   1. $KRYPTON_ROOT env var (set by kcc.sh wrapper from $SCRIPT_DIR).
    //   2. POSIX default ($HOME present) → /usr/local/krypton.
    //   3. Windows fallback → C:\krypton.
    // kcc.sh on macOS/Linux sets KRYPTON_ROOT to its own libexec dir,
    // which is where Homebrew + tarball installs place stdlib/ + headers/.
    let installRoot = environ("KRYPTON_ROOT")
    if installRoot == "" {
        // Windows sets OS=Windows_NT regardless of shell (cmd, PowerShell,
        // Git Bash, MSYS). Check it FIRST — otherwise Git Bash's HOME var
        // misroutes Windows users to /usr/local/krypton.
        if environ("OS") == "Windows_NT" {
            installRoot = "C:\\krypton"
        } else if environ("HOME") != "" {
            installRoot = "/usr/local/krypton"
        } else {
            installRoot = "C:\\krypton"
        }
    }
    let headersDir  = installRoot + "/headers"   // legacy var, kept for bin-dir derivation
    let outFile = ""
    let file = arg("0")
    let argIdx = 0

    if file == "--version" || file == "-v" {
        printErr("kcc version " + kccVer + "\n")
        emit 0
    }

    if argCount() == 0 {
        printErr("kcc: no input file")
        printErr("usage: kcc [-o out.exe] [--port-1to2] source.k")
        emit 1
    }

    while file == "--ir" || file == "-o" || file == "--port-1to2" {
        if file == "--ir" {
            irMode = 1
            argIdx += 1
        }
        if file == "-o" {
            argIdx += 1
            outFile = arg(argIdx + "")
            argIdx += 1
        }
        if file == "--port-1to2" {
            portMode = 1
            argIdx += 1
        }
        file = arg(argIdx + "")
    }

    // When -o is given, force IR mode internally (pipeline handles the rest)
    if len(outFile) > 0 { irMode = 1 }

    let source = readFile(file)

    if len(source) == 0 {
        printErr("kcc: cannot read file: " + file)
        emit 1
    }
    let tokens = tokenize(source)
    let ntoks = lineCount(tokens)

    // 2.0-alpha-3: --port-1to2 diagnostic mode. Scans source for
    // patterns that need attention before a 2.0 upgrade and exits.
    // No code generation. Patterns flagged:
    //   - bufNew/rawAlloc/rawFree         — manual heap (lifetime cliff under future GC)
    //   - rawReadByte/Word/Qword          — raw memory access (boundary check absent)
    //   - rawWriteWord/Qword              — raw memory writes
    //   - ptrAdd/ptrToInt/ptrIndex/ptrDeref — raw pointer arithmetic
    //   - cfunc { }                       — C body (won't survive native pipeline; rewrite)
    //   - top-level `let X = ...` followed by `X = ...` — mutable module global (broken in native)
    if portMode == 1 {
        emitPortWarnings(tokens, ntoks, file)
        emit 0
    }

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
            let fullPath = importPath
            // 1.8.4: Odin-style `prefix:name` imports — extension implied
            // by the prefix. Resolves under <install root>:
            //   k:foo    / core:foo    → <root>/stdlib/foo.k
            //   head:foo / headers:foo → <root>/headers/foo.krh
            let colonAt = indexOf(importPath, ":")
            if colonAt > 0 && colonAt < 8 {
                let prefix = substring(importPath, 0, colonAt)
                let sub    = substring(importPath, colonAt + 1, len(importPath))
                if prefix == "k"       { fullPath = installRoot + "/stdlib/"  + sub + ".k"   }
                if prefix == "core"    { fullPath = installRoot + "/stdlib/"  + sub + ".k"   }
                if prefix == "head"    { fullPath = installRoot + "/headers/" + sub + ".krh" }
                if prefix == "headers" { fullPath = installRoot + "/headers/" + sub + ".krh" }
            }
            // Backwards compat: legacy "stdlib/foo.k" / "windows.krh" forms.
            // resolve relative path: source-relative, then cwd, then install.
            if len(baseDir) > 0 {
                if !startsWith(importPath, "/") {
                    if !startsWith(importPath, "C:") {
                        if !startsWith(fullPath, installRoot) {
                            let relPath = baseDir + importPath
                            let testSrc = readFile(relPath)
                            if len(testSrc) > 0 {
                                fullPath = relPath
                            }
                        }
                    }
                }
            }
            // Try install root for legacy unprefixed paths.
            let testSrc2 = readFile(fullPath)
            if len(testSrc2) == 0 {
                let hdPath = installRoot + "/headers/" + importPath
                let testSrc3 = readFile(hdPath)
                if len(testSrc3) > 0 {
                    fullPath = hdPath
                }
            }
            let testSrc4 = readFile(fullPath)
            if len(testSrc4) == 0 {
                let stdPath = installRoot + "/" + importPath
                let testSrc5 = readFile(stdPath)
                if len(testSrc5) > 0 {
                    fullPath = stdPath
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
                                    // Skip wrapper if the new Win32 marshalling table covers this name.
                                    let _iHasMarshal = "0"
                                    if len(compileWin32IntReturn(ijfCName)) > 0 { _iHasMarshal = "1" }
                                    if len(compileWin32IntArgs(ijfCName)) > 0 { _iHasMarshal = "1" }
                                    if (ijfRetType == "INT" || ijfRetType == "UINT" || ijfRetType == "DWORD" || ijfRetType == "LONG" || ijfRetType == "BOOL") && _iHasMarshal == "0" {
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
                                    if (ijfRetType == "UINT64" || ijfRetType == "ULONGLONG") && _iHasMarshal == "0" {
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
                                    if ijfRetType == "zero" && _iHasMarshal == "0" {
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
                            // skipBlock returns the position one past RBRACE;
                            // subtract 1 so the trailing `ij += 1` lands at the
                            // next sibling token (otherwise we'd skip it).
                            ij = skipBlock(iToks, ij + 1) - 1
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
                        } else if tokType(itk) == "CBLOCK" {
                            // Top-level cfunc { } in imported module: emit the raw
                            // C body verbatim into the import-decls block so any
                            // statics/globals/helpers it defines are reachable from
                            // jxt-declared functions in the same imported file.
                            let icraw = replace(tokVal(itk), "\x01", "\n")
                            iDecls = iDecls + icraw + "\n"
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
                    jxtPos += 2
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
                    // Skip the legacy wrapper if this function is in the new
                    // Win32 marshalling table — the inline marshalling at the
                    // call site (compileCall) does the right thing for both
                    // 32-bit and 64-bit returns and for atoi'd int args.
                    let _hasNewMarshal = compileWin32IntReturn(jfCName)
                    if len(_hasNewMarshal) > 0 || len(compileWin32IntArgs(jfCName)) > 0 {
                        // No wrapper needed — fall through.
                    }
                    // Generate static wrapper + #define for integer-returning APIs.
                    // Args passed as char* (no int cast) — C handles implicit conversion,
                    // which is safe for both pointer args and toHandle() integer args.
                    if (jfRetType == "INT" || jfRetType == "UINT" || jfRetType == "DWORD" || jfRetType == "LONG" || jfRetType == "BOOL") && len(_hasNewMarshal) == 0 && len(compileWin32IntArgs(jfCName)) == 0 {
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
                    if (jfRetType == "UINT64" || jfRetType == "ULONGLONG") && len(_hasNewMarshal) == 0 && len(compileWin32IntArgs(jfCName)) == 0 {
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
                    if jfRetType == "zero" && len(_hasNewMarshal) == 0 && len(compileWin32IntArgs(jfCName)) == 0 {
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
                let compilerDir = replace(headersDir, "headers", "bin")
                let tmpDir = "C:\\krypton"
                if environ("HOME") != "" {
                    tmpDir = environ("TMPDIR")
                    if tmpDir == "" { tmpDir = "/tmp" }
                }
                let tmpIR  = tmpDir + "/tmp_kcc_build.ir"
                let tmpOpt = tmpDir + "/tmp_kcc_build_opt.ir"
                writeFile(tmpIR, irLibText)
                let optCmd2  = compilerDir + "\\optimize_host.exe " + tmpIR + " > " + tmpOpt
                let codeCmd2 = compilerDir + "\\x64_host_new.exe " + tmpOpt + " " + outFile
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
    sb = sbAppend(sb, "    char _stack_anchor; _stack_bottom = &_stack_anchor;\n")
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

        // Collect top-level globals (let/const at file scope) so we can prepend
        // their init code to __main__ as locals — gives globals a working
        // home without a dedicated .bss region in the ELF backend.
        let sbGlobInit = sbNew()
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
            } else if irtok == "KW:just" || irtok == "KW:go" {
                // Skip the entry block — it's handled separately via findEntry below.
                // Without this skip, our top-level walk would treat `let` tokens
                // inside `just run { ... }` as globals.
                //
                // BUT first: walk the body looking for nested `func` declarations
                // and hoist each as a top-level FUNC. Krypton has no closures,
                // so a nested func is semantically a sibling. Without this, the
                // nested-func tokens fall through to irExpr and emit garbage.
                let bodyOpen = iri + 2
                while bodyOpen < ntoks && tokAt(tokens, bodyOpen) != "LBRACE" { bodyOpen += 1 }
                let scanP = bodyOpen + 1
                let scanDepth = 1
                while scanP < ntoks && scanDepth > 0 {
                    let st = tokAt(tokens, scanP)
                    if st == "LBRACE" { scanDepth += 1; scanP += 1 }
                    else if st == "RBRACE" { scanDepth -= 1; scanP += 1 }
                    else if (st == "KW:func" || st == "KW:fn") && tokType(tokAt(tokens, scanP + 1)) == "ID" {
                        let nfp = irFuncIR(tokens, scanP, ntoks)
                        sbIR = sbAppend(sbIR, pairVal(nfp))
                        scanP = pairPos(nfp)
                    } else {
                        scanP += 1
                    }
                }
                iri = scanP
            } else if irtok == "KW:struct" || irtok == "KW:class" || irtok == "KW:type" {
                // Skip struct/class/type body — `let`s inside are field decls,
                // not file-scope globals. Without this skip, we'd hoist them
                // as bogus locals into __main__'s prologue (LOCAL x; LOAD y; STORE x).
                //
                // Also synthesise a zero-arg constructor `FUNC <Name> 0` so
                // user code `let v = Vec()` (which compiles to CALL Vec 0)
                // resolves to a real function. Body is just STRUCTNEW + RETURN
                // — emits an empty struct (NULL sentinel; SETFIELD ops on it
                // build the linked-list of fields lazily).
                let structName = tokVal(tokAt(tokens, iri + 1))
                sbIR = sbAppend(sbIR, "FUNC " + structName + " 0\nSTRUCTNEW\nRETURN\nEND\n\n")
                let entryP = iri + 2
                while entryP < ntoks && tokAt(tokens, entryP) != "LBRACE" { entryP += 1 }
                let depth = 0
                while entryP < ntoks {
                    let bt = tokAt(tokens, entryP)
                    if bt == "LBRACE" { depth += 1 }
                    if bt == "RBRACE" {
                        depth -= 1
                        if depth == 0 { entryP += 1; break }
                    }
                    entryP += 1
                }
                iri = entryP
            } else if irtok == "KW:let" || irtok == "KW:const" {
                let glp = irLetIR(tokens, iri + 1, ntoks, 0, "0", "")
                sbGlobInit = sbAppend(sbGlobInit, pairVal(glp))
                iri = pairPos(glp)
            } else {
                iri += 1
            }
        }

        // 2.0-alpha: lambda hoisting. Walk the whole token stream, find
        // every `func(...)` / `fn(...)` expression (KW:func followed
        // immediately by LPAREN — no name), and emit a top-level FUNC
        // _krlam<pos> N for it. irPrimary's lambda branch later just
        // pushes FUNCPTR _krlam<pos>.
        let lamI = 0
        while lamI < ntoks {
            let lamTok = tokAt(tokens, lamI)
            if (lamTok == "KW:func" || lamTok == "KW:fn") && tokAt(tokens, lamI + 1) == "LPAREN" {
                let lampair = irLambdaIR(tokens, lamI, ntoks, "_krlam" + lamI)
                sbIR = sbAppend(sbIR, pairVal(lampair))
                lamI = pairPos(lampair)
            } else {
                lamI += 1
            }
        }

        let irEntry = findEntry(tokens, ntoks)
        if irEntry >= 0 {
            let mainTypes = irScanStructTypes(tokens, ntoks) + irScanFuncTypes(tokens, irEntry)
            let ep = irBlockIR(tokens, irEntry, ntoks, 0, "0", mainTypes)
            // 2.0-alpha-3 GC stage 3: same shadow-stack save/restore wrap
            // as irFuncIR applies to __main__'s body (and prepended global
            // inits). On normal exit, all per-let pushes get popped.
            let mainBody = sbToString(sbGlobInit) + pairVal(ep)
            mainBody = "LOCAL __sh_save\nBUILTIN gcShadowCount 0\nSTORE __sh_save\n" + mainBody +
                       "BUILTIN gcShadowCount 0\nLOAD __sh_save\nSUB\nBUILTIN gcShadowPop 1\nPOP\n"
            sbIR = sbAppend(sbIR, "FUNC __main__ 0\n" + mainBody + "END\n")
        }

        let irText = sbToString(sbIR)

        // -o mode: run full native pipeline internally
        if len(outFile) > 0 {
            let compilerDir = replace(headersDir, "headers", "bin")
            let tmpDir = "C:\\krypton"
            if environ("HOME") != "" {
                tmpDir = environ("TMPDIR")
                if tmpDir == "" { tmpDir = "/tmp" }
            }
            let tmpIR  = tmpDir + "/tmp_kcc_build.ir"
            let tmpOpt = tmpDir + "/tmp_kcc_build_opt.ir"
            writeFile(tmpIR, irText)
            let optCmd  = compilerDir + "\\optimize_host.exe " + tmpIR + " > " + tmpOpt
            let codeCmd = compilerDir + "\\x64_host_new.exe " + tmpOpt + " " + outFile
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
