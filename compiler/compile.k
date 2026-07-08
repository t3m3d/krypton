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

// A1 float: expression result-type channel. Pairs are "code,pos" or, for
// float-typed results, "code,pos;f64". pairVal/pairPos are unaffected (toInt
// stops at ';'). pairType returns the type after ';' (or "" = untyped/int).
// Lets operators (irAdditive/Multiplicative/Relational/Equality) emit the
// fadd/fmul/flt/... builtins when an operand is f64 instead of integer ADD/MUL.
func pairType(pair) {
    let c = findLastComma(pair)
    if c < 0 { emit "" }
    let rest = substring(pair, c + 1, len(pair))
    let s = 0
    while s < len(rest) && rest[s] != ";" { s += 1 }
    if s >= len(rest) { emit "" }
    emit substring(rest, s + 1, len(rest))
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

// Compare two leading-zero-stripped decimal strings; "1" if a >= b.
func decGE(a, b) {
    if len(a) > len(b) { emit "1" }
    if len(a) < len(b) { emit "0" }
    let j = 0
    while j < len(a) {
        if a[j] > b[j] { emit "1" }
        if a[j] < b[j] { emit "0" }
        j += 1
    }
    emit "1"
}

func readNumber(text, i) {
    let start = i
    // hex literal: 0x... or 0X...
    if text[i] == "0" && i + 1 < len(text) && (text[i + 1] == "x" || text[i + 1] == "X") {
        i = i + 2
        let hstart = i
        while i < len(text) && hexDigitVal(text[i]) >= 0 {
            i += 1
        }
        // Magnitude guard: the native runtime tags any value >= 0x7F000000 as a
        // pointer, so building such an int segfaults. Decide on the digit STRING
        // (before any int math) and fail cleanly instead of crashing.
        let z = hstart
        while z < i - 1 && text[z] == "0" { z += 1 }   // strip leading zeros
        let sig = i - z                                // significant hex digits
        let over = "0"
        if sig > 8 { over = "1" }
        if sig == 8 {
            let d0 = hexDigitVal(text[z])
            if d0 > 7 { over = "1" }
            if d0 == 7 && hexDigitVal(text[z + 1]) == 15 { over = "1" }
        }
        if over == "1" {
            printErr("kcc: integer literal 0x" + substring(text, hstart, i) + " exceeds the native runtime limit (max 0x7EFFFFFF) — represent it as a string or split it.\n")
            exit(1)
        }
        let hexVal = 0
        let k = hstart
        while k < i {
            hexVal = hexVal * 16 + hexDigitVal(text[k])
            k += 1
        }
        emit hexVal + "," + i
    }
    let dstart = i
    while i < len(text) && isDigit(text[i]) {
        i += 1
    }
    let isFloat = "0"
    // check for float: digits followed by . followed by digits
    if i < len(text) && text[i] == "." {
        if i + 1 < len(text) && isDigit(text[i + 1]) {
            isFloat = "1"
            i += 1
            while i < len(text) && isDigit(text[i]) {
                i += 1
            }
        }
    }
    // Same magnitude guard for decimal integers (ceiling 0x7F000000 = 2130706432).
    if isFloat == "0" && i > dstart {
        let z2 = dstart
        while z2 < i - 1 && text[z2] == "0" { z2 += 1 }
        if decGE(substring(text, z2, i), "2130706432") == "1" {
            printErr("kcc: integer literal " + substring(text, dstart, i) + " exceeds the native runtime limit (max 2130706431) — represent it as a string or split it.\n")
            exit(1)
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
    else if word == "defer" { emit 1 }
    else if word == "static" { emit 1 }
    else if word == "const" { emit 1 }
    else if word == "module" { emit 1 }
    else if word == "import" { emit 1 }
    else if word == "export" { emit 1 }
    else if word == "struct" { emit 1 }
    else if word == "class" { emit 1 }
    else if word == "type" { emit 1 }
    else if word == "enum" { emit 1 }
    else if word == "interface" { emit 1 }
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
    else if word == "switch" { emit 1 }
    else if word == "case" { emit 1 }
    else if word == "default" { emit 1 }
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
        } else if tok == "KW:interface" {
            // B4: interface bodies are signature docs, not real functions —
            // skip the whole block so the `func double()` declarations inside
            // don't leak into the global function table as 0-arg stubs that
            // shadow the real `func double(n)`. (skipBlock returns past `}`,
            // we want to land AT `}` so the outer i+=1 advances past it.)
            i = skipBlock(tokens, i + 2) - 1
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
            // j is at RPAREN. Plain-scan optional `-> TYPE`, then body.
            j = j + 1
            j = irSkipReturnType(tokens, j)
            let bodyStart = j
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
    let ty = pairType(pair)   // A7: propagate f64 on pass-through (no ?:)
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
    if ty == "f64" { emit code + "," + p + ";f64" }
    emit code + "," + p
}

func irOr(tokens, pos, ntoks, lc, types) {
    let pair = irAnd(tokens, pos, ntoks, lc, types)
    let code = pairVal(pair)
    let p = pairPos(pair)
    let ty = pairType(pair)   // A7: propagate f64 on pass-through
    let nlc = lc
    while tokAt(tokens, p) == "OR" {
        ty = ""
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
    if ty == "f64" { emit code + "," + p + ";f64" }
    emit code + "," + p
}

func irAnd(tokens, pos, ntoks, lc, types) {
    let pair = irEquality(tokens, pos, ntoks, lc, types)
    let code = pairVal(pair)
    let p = pairPos(pair)
    let ty = pairType(pair)   // A7: propagate f64 on pass-through
    let nlc = lc
    while tokAt(tokens, p) == "AND" {
        ty = ""
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
    if ty == "f64" { emit code + "," + p + ";f64" }
    emit code + "," + p
}

func irEquality(tokens, pos, ntoks, lc, types) {
    let pair = irRelational(tokens, pos, ntoks, lc, types)
    let code = pairVal(pair)
    let p = pairPos(pair)
    let ety = pairType(pair)
    while tokAt(tokens, p) == "EQ" || tokAt(tokens, p) == "NEQ" {
        let op = tokAt(tokens, p)
        let rp = irRelational(tokens, p + 1, ntoks, lc, types)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        // A1: float == via feq; != as !(a==b). bit-equality on the f64 bits.
        let isFloat = ety == "f64" || pairType(rp) == "f64"
        if isFloat {
            if op == "EQ" { code = code + rcode + "BUILTIN feq 2\n" }
            else          { code = code + rcode + "BUILTIN feq 2\nPUSH 0\nEQ\n" }
        } else {
            if op == "EQ" { code = code + rcode + "EQ\n" }
            else { code = code + rcode + "NEQ\n" }
        }
        ety = ""
    }
    if ety == "f64" { emit code + "," + p + ";f64" }
    emit code + "," + p
}

func irRelational(tokens, pos, ntoks, lc, types) {
    let pair = irAdditive(tokens, pos, ntoks, lc, types)
    let code = pairVal(pair)
    let p = pairPos(pair)
    let lty = pairType(pair)
    while tokAt(tokens, p) == "LT" || tokAt(tokens, p) == "GT" || tokAt(tokens, p) == "LTE" || tokAt(tokens, p) == "GTE" {
        let op = tokAt(tokens, p)
        let rp = irAdditive(tokens, p + 1, ntoks, lc, types)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        // A1: float compares. Only flt/fgt/feq exist as builtins, so synthesize
        // <= as !(a>b) and >= as !(a<b). Result is a bool int (not f64).
        let isFloat = lty == "f64" || pairType(rp) == "f64"
        if isFloat {
            if op == "LT"  { code = code + rcode + "BUILTIN flt 2\n" }
            if op == "GT"  { code = code + rcode + "BUILTIN fgt 2\n" }
            if op == "LTE" { code = code + rcode + "BUILTIN fgt 2\nPUSH 0\nEQ\n" }
            if op == "GTE" { code = code + rcode + "BUILTIN flt 2\nPUSH 0\nEQ\n" }
        } else {
            if op == "LT" { code = code + rcode + "LT\n" }
            if op == "GT" { code = code + rcode + "GT\n" }
            if op == "LTE" { code = code + rcode + "LTE\n" }
            if op == "GTE" { code = code + rcode + "GTE\n" }
        }
        lty = ""
    }
    // propagate float-ness on pass-through (no relational op consumed) so an
    // enclosing != / == sees an f64 operand.
    if lty == "f64" { emit code + "," + p + ";f64" }
    emit code + "," + p
}

func irAdditive(tokens, pos, ntoks, lc, types) {
    let pair = irMultiplicative(tokens, pos, ntoks, lc, types)
    let code = pairVal(pair)
    let p = pairPos(pair)
    let ty = pairType(pair)
    while tokAt(tokens, p) == "PLUS" || tokAt(tokens, p) == "MINUS" {
        let op = tokAt(tokens, p)
        let rp = irMultiplicative(tokens, p + 1, ntoks, lc, types)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        // A1: float if either operand is f64 → fadd/fsub (auto-promote int operand).
        // NOTE: `+` on a string stays integer-ADD here (ADD is polymorphic at
        // runtime: it only float-ifies when a STATIC f64 is involved; string
        // concat is unaffected because neither operand is f64-typed).
        let isFloat = ty == "f64" || pairType(rp) == "f64"
        if op == "PLUS" {
            if isFloat { code = code + rcode + "BUILTIN fadd 2\n"  ty = "f64" }
            else       { code = code + rcode + "ADD\n" }
        } else {
            if isFloat { code = code + rcode + "BUILTIN fsub 2\n"  ty = "f64" }
            else       { code = code + rcode + "SUB\n" }
        }
    }
    if ty == "f64" { emit code + "," + p + ";f64" }
    emit code + "," + p
}

func irMultiplicative(tokens, pos, ntoks, lc, types) {
    let pair = irPow(tokens, pos, ntoks, lc, types)
    let code = pairVal(pair)
    let p = pairPos(pair)
    let ty = pairType(pair)
    while tokAt(tokens, p) == "STAR" || tokAt(tokens, p) == "SLASH" || tokAt(tokens, p) == "MOD" {
        let op = tokAt(tokens, p)
        let rp = irPow(tokens, p + 1, ntoks, lc, types)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        // A1: float if either operand is f64. STAR/SLASH → fmul/fdiv (auto-promote
        // an int operand). MOD has no float form → stays integer.
        let isFloat = ty == "f64" || pairType(rp) == "f64"
        if op == "STAR" {
            if isFloat { code = code + rcode + "BUILTIN fmul 2\n"  ty = "f64" }
            else       { code = code + rcode + "MUL\n" }
        }
        if op == "SLASH" {
            if isFloat { code = code + rcode + "BUILTIN fdiv 2\n"  ty = "f64" }
            else       { code = code + rcode + "DIV\n" }
        }
        if op == "MOD" { code = code + rcode + "MOD\n"  ty = "" }
    }
    if ty == "f64" { emit code + "," + p + ";f64" }
    emit code + "," + p
}

// Right-associative ** — `a ** b ** c` is `a ** (b ** c)`.
func irPow(tokens, pos, ntoks, lc, types) {
    let pair = irUnary(tokens, pos, ntoks, lc, types)
    let code = pairVal(pair)
    let p = pairPos(pair)
    let ty = pairType(pair)
    if tokAt(tokens, p) == "STARSTAR" {
        let rp = irPow(tokens, p + 1, ntoks, lc, types)
        let rcode = pairVal(rp)
        p = pairPos(rp)
        code = code + rcode + "BUILTIN pow 2\n"
        ty = ""   // ** is integer-only (no fpow); result is not float
    }
    if ty == "f64" { emit code + "," + p + ";f64" }
    emit code + "," + p
}

func irUnary(tokens, pos, ntoks, lc, types) {
    let tok = tokAt(tokens, pos)
    if tok == "MINUS" {
        let pair = irUnary(tokens, pos + 1, ntoks, lc, types)
        let code = pairVal(pair)
        let p = pairPos(pair)
        // A1: -float stays float (backend NEG is float-aware).
        if pairType(pair) == "f64" { emit code + "NEG\n," + p + ";f64" }
        emit code + "NEG\n," + p
    }
    if tok == "BANG" {
        let pair = irUnary(tokens, pos + 1, ntoks, lc, types)
        let code = pairVal(pair)
        let p = pairPos(pair)
        // `false`/`true` are stored as the STRINGS "false"/"true", so the bare
        // backend NOT (`cmp x0,0`) treats `!false` as NOT-of-a-heap-pointer = 0
        // ("no"). Funnel the operand through isTruthy first (string-truthiness:
        // "false"/"0"/"" → 0, else 1), exactly like if/while wrap their
        // conditions, so NOT flips a clean 0/1 int. (Safe to grow code here now
        // that top-level emit/return exits cleanly — see line_ops fix.)
        emit code + "BUILTIN isTruthy 1\nNOT\n," + p
    }
    emit irPostfix(tokens, pos, ntoks, lc, types)
}

func irPostfix(tokens, pos, ntoks, lc, types) {
    let pair = irPrimary(tokens, pos, ntoks, lc, types)
    let code = pairVal(pair)
    let p = pairPos(pair)
    // A1: propagate the primary's float-ness when no postfix (.field/[i]) is
    // applied. Postfix results (field reads, indexing) aren't float-typed yet.
    let primaryType = pairType(pair)
    let primaryEnd = p
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
        if len(last0) >= 7 && substring(last0, 0, 7) == "; TYPE " {
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
                // Phase C typed *u64/*i64: ints only — bufGetQwordAt's atoi/itoa is fine.
                code = code + idxcode + "PUSH 8\nMUL\n" + addAcc + "BUILTIN bufGetQwordAt 2\n"
            } else if deferredType == "__array" {
                // A5 array: polymorphic 8-byte slot. bufGetQwordAt-then-intToPtr
                // recovers stored ptrs (Bug #1 workaround), but intToPtr("0") = 0
                // (NULL) crashes downstream kr_eq derefs — happens on uninit
                // slots OR an explicit `arr[i] = 0`. Inline branch: if the
                // readback string is "0", push the literal "0" ptr; else
                // intToPtr-unwrap. Single temp local per call site.
                // 2026-06-19 (w): FE-only Bug #1 workaround with zero-guard.
                let arTmp = "_ar" + pos
                let arZL  = "_arz" + pos
                let arDL  = "_ard" + pos
                code = code + idxcode + "PUSH 8\nMUL\n" + addAcc + "BUILTIN bufGetQwordAt 2\n" +
                       "LOCAL " + arTmp + "\nSTORE " + arTmp + "\n" +
                       "LOAD " + arTmp + "\nPUSH \"0\"\nEQ\nJUMPIF " + arZL + "\n" +
                       "LOAD " + arTmp + "\nBUILTIN intToPtr 1\nJUMP " + arDL + "\n" +
                       "LABEL " + arZL + "\nPUSH \"0\"\nLABEL " + arDL + "\n"
            } else if deferredType == "__slice" {
                // B3 slice read s[i]: same zero-guarded unwrap.
                let slvn = substring(tokAt(tokens, pos), 3, len(tokAt(tokens, pos)))
                let slTmp = "_sl" + pos
                let slZL  = "_slz" + pos
                let slDL  = "_sld" + pos
                code = "LOAD " + slvn + "\nPUSH 0\nBUILTIN bufGetQwordAt 2\nBUILTIN intToPtr 1\n" +
                       "LOAD " + slvn + "\nPUSH 8\nBUILTIN bufGetQwordAt 2\n" + idxcode + "PUSH 8\nMUL\nADD\n" + addAcc + "BUILTIN bufGetQwordAt 2\n" +
                       "LOCAL " + slTmp + "\nSTORE " + slTmp + "\n" +
                       "LOAD " + slTmp + "\nPUSH \"0\"\nEQ\nJUMPIF " + slZL + "\n" +
                       "LOAD " + slTmp + "\nBUILTIN intToPtr 1\nJUMP " + slDL + "\n" +
                       "LABEL " + slZL + "\nPUSH \"0\"\nLABEL " + slDL + "\n"
            } else {
                code = code + idxcode + "INDEX\n"
            }
            accumOff = 0
            deferredType = ""
        } else {
            let field = tokVal(tokAt(tokens, p + 1))
            p = p + 2
            let didTypedField = 0
            // B4 interfaces — UFCS method dispatch: obj.method(args) lowers to
            // method(obj, args). The receiver is already on the stack (in
            // `code`); push the user args after it and CALL the free function.
            // Duck-typed and structural: any `method(obj, ...)` satisfies it,
            // no vtable, no explicit `satisfies` decl. `interface` blocks are
            // compile-time signature docs (skipped at codegen). A field that
            // holds a callable is not reachable this way — `.name(` always
            // means a method call. (Dynamic dispatch over a heterogeneous
            // []Interface is the future vtable slab.)
            if tokAt(tokens, p) == "LPAREN" {
                let margc = 1                       // receiver is arg 0
                let mp = p + 1
                let mcode = ""
                while tokAt(tokens, mp) != "RPAREN" && mp < ntoks {
                    if margc > 1 { mp += 1 }        // skip the comma
                    let mex = irExpr(tokens, mp, ntoks, lc, types)
                    mcode = mcode + pairVal(mex)
                    mp = pairPos(mex)
                    margc += 1
                }
                mp += 1                             // past RPAREN
                code = code + mcode + "CALL " + field + " " + margc + "\n"
                p = mp
                deferredType = ""
                accumOff = 0
                didTypedField = 1
            }
            // B3 slice: s.len / s.cap read slots 16 / 24 of the quad.
            if deferredType == "__slice" {
                if field == "len" { code = code + "PUSH 16\nBUILTIN bufGetQwordAt 2\n"  didTypedField = 1 }
                if field == "cap" { code = code + "PUSH 24\nBUILTIN bufGetQwordAt 2\n"  didTypedField = 1 }
                deferredType = ""
                accumOff = 0
            }
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
    if p == primaryEnd && primaryType == "f64" { emit code + "," + p + ";f64" }
    emit code + "," + p
}

func irPrimary(tokens, pos, ntoks, lc, types) {
    let tok = tokAt(tokens, pos)
    let tt = tokType(tok)
    let tv = tokVal(tok)

    // Integer/float literal
    if tt == "INT" {
        // A1: a decimal point makes it a float literal → tag the pair f64 so
        // enclosing operators emit fadd/fmul/etc.
        let hasDot = "0"
        let di = 0
        while di < len(tv) { if tv[di] == "." { hasDot = "1" }  di += 1 }
        if hasDot == "1" {
            emit "PUSH " + tv + "\n," + (pos + 1) + ";f64"
        }
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
        lp = irSkipReturnType(tokens, lp)
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
        // A3 enum member access: EnumName.Member -> int constant (compile-time).
        if nextTok == "DOT" {
            let memTk = tokAt(tokens, pos + 2)
            if len(memTk) >= 3 && substring(memTk, 0, 3) == "ID:" {
                let ev = irTypeOf(types, tv + "." + substring(memTk, 3, len(memTk)))
                if len(ev) > 0 { emit "PUSH " + ev + "\n," + (pos + 3) }
            }
        }
        if nextTok == "LPAREN" {
            emit irCall(tokens, pos, ntoks, lc, types)
        }
        // Struct literal: Name { field: val }
        // 2.0-alpha-3: tighten heuristic — also require the LBRACE
        // body to start with `<ID>: ...` (field-syntax). Without this,
        // patterns like `while i < N { ... }` would attempt struct-literal
        // parse on N.
        //
        // The inner-ID check MUST use substring, not `startsWith(..)=="1"`:
        // on the macho-built compiler startsWith returns the int 1 and
        // `1 == "1"` is false, so the whole struct-literal path was dead —
        // `V { x: .. }` fell through to a bare var load and the `{ .. }` body
        // desynced the parser, silently dropping the rest of the block. (The
        // old comment here misblamed tokenization.)
        let firstChar = tv[0]
        if nextTok == "LBRACE" {
            if firstChar >= "A" && firstChar <= "Z" {
                let inner1 = tokAt(tokens, pos + 2)
                let inner2 = tokAt(tokens, pos + 3)
                if len(inner1) >= 3 && substring(inner1, 0, 3) == "ID:" {
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
            // A6: static local — load from its persistent module global.
            if len(varType) >= 12 && substring(varType, 0, 12) == "__staticref:" {
                emit "LOAD " + substring(varType, 12, len(varType)) + "\n," + (pos + 1)
            }
            // 2.0-alpha-3: closure capture — `__cap__:<name>` type
            // means `tv` is a captured free var; rewrite the load as
            // `LOAD __env; PUSH "<name>"; envGet 2`. The lambda body
            // has __env as its first PARAM (added by irLambdaIR).
            if startsWith(varType, "__cap__:") == "1" {
                let capName = substring(varType, 8, len(varType))
                emit "LOAD __env\nPUSH \"" + capName + "\"\nBUILTIN envGet 2\n," + (pos + 1)
            }
            // A1: an f64-annotated local loads a float box — tag the pair so
            // operators float-ify. No inert TYPE comment (it's not a pointer type).
            if varType == "f64" {
                emit "LOAD " + tv + "\n," + (pos + 1) + ";f64"
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

    // A5 fixed-size arrays: array(N) allocates an N-element array (N 8-byte slots,
    // zero-initialised) as a GC buffer. Indexing arr[i] / arr[i]=v lowers to
    // bufGetQwordAt/bufSetQwordAt (the var is tracked as __array). Pure FE over the
    // existing buf builtins — no backend change. Elements are 64-bit (int/pointer).
    if fname == "array" {
        let np = irExpr(tokens, pos + 2, ntoks, lc, types)
        let p = pairPos(np)
        if tokAt(tokens, p) == "RPAREN" { p += 1 }
        emit pairVal(np) + "PUSH 8\nMUL\nBUILTIN bufNew 1\n," + p
    }

    // B3 slice append: `append(s, v)` where s is a __slice. Cap-aware — if
    // len < cap, write v in place into the shared backing at byteOff+len*8
    // (Go-style aliasing) and return a new (base, byteOff, len+1, cap) quad;
    // otherwise grow: bufNew a cap*2 (>=1) buffer, copy the len elements, append
    // v, and return a quad over the fresh buffer. The base HANDLE is never
    // pointer-arithmetic'd (tagged — see slice creation). Returns the new slice
    // (an expression value). Only fires when arg0 is a bare __slice id; any
    // other append (lists) falls through to the runtime builtin. No backend
    // work — labels/jumps + buf builtins only. NB: temps holding heap refs
    // (_ap_s/_ap_v/_ap_nb) are gcShadowPush'd so the final bufNew(32) can't
    // collect them.
    if fname == "append" {
        let a0 = tokAt(tokens, pos + 2)
        if len(a0) >= 3 && substring(a0, 0, 3) == "ID:" && irTypeOf(types, substring(a0, 3, len(a0))) == "__slice" {
            let aS = irExpr(tokens, pos + 2, ntoks, lc, types)
            let sCode = pairVal(aS)
            let cp = pairPos(aS)
            if tokAt(tokens, cp) == "COMMA" { cp += 1 }
            let aV = irExpr(tokens, cp, ntoks, lc, types)
            let vCode = pairVal(aV)
            let rp = pairPos(aV)
            if tokAt(tokens, rp) == "RPAREN" { rp += 1 }
            // unique temps/labels per call site
            let S = "_ap_s_" + pos
            let V = "_ap_v_" + pos
            let NL = "_ap_nl_" + pos
            let NB = "_ap_nb_" + pos
            let NO = "_ap_no_" + pos
            let NC = "_ap_nc_" + pos
            let II = "_ap_i_" + pos
            let R = "_ap_r_" + pos
            let Lgrow = "_apgrow_" + pos
            let Lcapok = "_apcapok_" + pos
            let Lcloop = "_apcloop_" + pos
            let Lcend = "_apcend_" + pos
            let Ldone = "_apdone_" + pos
            // eval args once; root the heap-holding ones.
            let o = "LOCAL " + S + "\n" + sCode + "STORE " + S + "\n"
            o = o + "LOCAL " + V + "\n" + vCode + "STORE " + V + "\n"
            o = o + "LOCAL " + NL + "\nLOCAL " + NB + "\nLOCAL " + NO + "\nLOCAL " + NC + "\n"
            // newlen = oldlen + 1
            o = o + "LOAD " + S + "\nPUSH 16\nBUILTIN bufGetQwordAt 2\nPUSH 1\nADD\nSTORE " + NL + "\n"
            // if oldlen < oldcap -> in place, else grow
            o = o + "LOAD " + S + "\nPUSH 16\nBUILTIN bufGetQwordAt 2\nLOAD " + S + "\nPUSH 24\nBUILTIN bufGetQwordAt 2\nLT\nJUMPIFNOT " + Lgrow + "\n"
            // in place: bufSetQwordAt(base_intToPtr, byteOff + oldlen*8, ptrToInt(v))
            // 2026-06-19 (w): same wrap as slice element accesses.
            o = o + "LOAD " + S + "\nPUSH 0\nBUILTIN bufGetQwordAt 2\nBUILTIN intToPtr 1\n"
            o = o + "LOAD " + S + "\nPUSH 8\nBUILTIN bufGetQwordAt 2\nLOAD " + S + "\nPUSH 16\nBUILTIN bufGetQwordAt 2\nPUSH 8\nMUL\nADD\n"
            o = o + "LOAD " + V + "\nBUILTIN ptrToInt 1\nBUILTIN bufSetQwordAt 3\nPOP\n"
            o = o + "LOAD " + S + "\nPUSH 0\nBUILTIN bufGetQwordAt 2\nBUILTIN intToPtr 1\nSTORE " + NB + "\n"
            o = o + "LOAD " + S + "\nPUSH 8\nBUILTIN bufGetQwordAt 2\nSTORE " + NO + "\n"
            o = o + "LOAD " + S + "\nPUSH 24\nBUILTIN bufGetQwordAt 2\nSTORE " + NC + "\n"
            o = o + "JUMP " + Ldone + "\n"
            // grow: newcap = oldcap*2 (>=1)
            o = o + "LABEL " + Lgrow + "\n"
            o = o + "LOAD " + S + "\nPUSH 24\nBUILTIN bufGetQwordAt 2\nPUSH 2\nMUL\nSTORE " + NC + "\n"
            o = o + "LOAD " + NC + "\nPUSH 0\nEQ\nJUMPIFNOT " + Lcapok + "\nPUSH 1\nSTORE " + NC + "\nLABEL " + Lcapok + "\n"
            o = o + "LOAD " + NC + "\nPUSH 8\nMUL\nBUILTIN bufNew 1\nSTORE " + NB + "\n"
            o = o + "PUSH 0\nSTORE " + NO + "\n"
            // copy loop: i=0; while i<oldlen { nb[i*8] = base[byteOff + i*8] }
            o = o + "LOCAL " + II + "\nPUSH 0\nSTORE " + II + "\n"
            o = o + "LABEL " + Lcloop + "\n"
            o = o + "LOAD " + II + "\nLOAD " + S + "\nPUSH 16\nBUILTIN bufGetQwordAt 2\nLT\nJUMPIFNOT " + Lcend + "\n"
            // copy loop element: read with intToPtr from old base; write with ptrToInt to new base.
            // NB is a fresh bufNew pointer (already a real ptr — wrap on store only).
            o = o + "LOAD " + NB + "\nLOAD " + II + "\nPUSH 8\nMUL\n"
            o = o + "LOAD " + S + "\nPUSH 0\nBUILTIN bufGetQwordAt 2\nBUILTIN intToPtr 1\n"
            o = o + "LOAD " + S + "\nPUSH 8\nBUILTIN bufGetQwordAt 2\nLOAD " + II + "\nPUSH 8\nMUL\nADD\nBUILTIN bufGetQwordAt 2\nBUILTIN intToPtr 1\n"
            o = o + "BUILTIN ptrToInt 1\nBUILTIN bufSetQwordAt 3\nPOP\n"
            o = o + "LOAD " + II + "\nPUSH 1\nADD\nSTORE " + II + "\nJUMP " + Lcloop + "\nLABEL " + Lcend + "\n"
            // append v at oldlen, byteOff 0
            o = o + "LOAD " + NB + "\nLOAD " + S + "\nPUSH 16\nBUILTIN bufGetQwordAt 2\nPUSH 8\nMUL\nLOAD " + V + "\nBUILTIN ptrToInt 1\nBUILTIN bufSetQwordAt 3\nPOP\n"
            o = o + "LABEL " + Ldone + "\n"
            // build result quad — slot 0 = base ptr (ptrToInt wrapped store).
            o = o + "LOCAL " + R + "\nPUSH 32\nBUILTIN bufNew 1\nSTORE " + R + "\n"
            o = o + "LOAD " + R + "\nPUSH 0\nLOAD " + NB + "\nBUILTIN ptrToInt 1\nBUILTIN bufSetQwordAt 3\nPOP\n"
            o = o + "LOAD " + R + "\nPUSH 8\nLOAD " + NO + "\nBUILTIN bufSetQwordAt 3\nPOP\n"
            o = o + "LOAD " + R + "\nPUSH 16\nLOAD " + NL + "\nBUILTIN bufSetQwordAt 3\nPOP\n"
            o = o + "LOAD " + R + "\nPUSH 24\nLOAD " + NC + "\nBUILTIN bufSetQwordAt 3\nPOP\n"
            o = o + "LOAD " + R + "\n"
            emit o + "," + rp
        }
    }

    // A4 (variadic, printf-style): format(fmt, ...) / printf(fmt, ...) with a
    // STRING-LITERAL format are expanded at compile time into a concat of the
    // literal pieces interleaved with the args (each %verb consumes one arg;
    // %% = literal %). %s/%d/%f all just insert the arg (ADD auto-stringifies an
    // int). printf raw-writes the result (no extra newline — the \n is in fmt).
    // A non-literal fmt isn't expandable here and falls through (runtime format
    // is a dead stub — unchanged). Pure FE, reuses string concat; no backend work.
    if fname == "format" || fname == "printf" {
        let fmtTok = tokAt(tokens, pos + 2)
        if tokType(fmtTok) == "STR" {
            let fmt = tokVal(fmtTok)
            let out = "PUSH \"\"\n"
            let piece = ""
            let fp = pos + 3
            let fi = 0
            while fi < len(fmt) {
                let ch = fmt[fi]
                if ch == "%" && fi + 1 < len(fmt) {
                    let v = fmt[fi + 1]
                    if v == "%" {
                        piece = piece + "%"
                        fi = fi + 2
                    } else {
                        out = out + "PUSH \"" + piece + "\"\nADD\n"
                        piece = ""
                        if tokAt(tokens, fp) == "COMMA" { fp = fp + 1 }
                        if tokAt(tokens, fp) != "RPAREN" {
                            let ap = irExpr(tokens, fp, ntoks, lc, types)
                            out = out + pairVal(ap) + "ADD\n"
                            fp = pairPos(ap)
                        } else {
                            out = out + "PUSH \"\"\nADD\n"
                        }
                        fi = fi + 2
                    }
                } else {
                    piece = piece + ch
                    fi = fi + 1
                }
            }
            out = out + "PUSH \"" + piece + "\"\nADD\n"
            while fp < ntoks && tokAt(tokens, fp) != "RPAREN" { fp = fp + 1 }
            fp = fp + 1
            if fname == "printf" {
                emit out + "BUILTIN print 1\n," + fp
            }
            emit out + "," + fp
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
    let builtins = "print,kp,printErr,readLine,input,readFile,writeFile,arg,argCount,len,count,substring,charAt,indexOf,contains,startsWith,endsWith,replace,trim,lstrip,rstrip,center,toLower,toUpper,padLeft,padRight,charCode,fromCharCode,format,strReverse,isAlpha,isDigit,isSpace,toInt,parseInt,abs,min,max,pow,sqrt,sign,clamp,bin,floor,ceil,round,split,length,first,last,head,tail,append,join,reverse,sort,unique,fill,zip,slice,listIndexOf,every,some,countOf,sumList,maxList,minList,range,words,lines,keys,values,hasKey,structNew,getField,setField,hasField,structFields,random,timestamp,environ,exit,assert,type,isTruthy,toStr,throw,mapDel,exec,shellRun,fadd,fsub,fmul,fdiv,fsqrt,ffloor,fceil,fround,fformat,flt,fgt,feq,intToFloat,floatToInt,sbNew,sbAppend,sbToString,bufNew,bufStr,bufGetDword,bufSetDword,bufGetWord,bufGetQword,bufGetDwordAt,bufGetQwordAt,bufSetByte,bufGetByte,bufSetDwordAt,bufSetQwordAt,bufGetWordAt,bufSetWordAt,bufGetWordAtBE,bufGetDwordAtBE,bufGetQwordAtBE,handleOut,handleGet,handleInt,toHandle,ptrDeref,ptrIndex,callPtr,getLine,lineCount,envNew,envSet,envGet,makeResult,getResultTag,getResultVal,getResultEnv,getResultPos,gcAllocated,gcAllocCount,gcShadowCount,gcShadowPop,gcShadowPush,gcWalkAllocs,gcMark,gcSweep,gcFreelistCount,rdtsc,pause,mfence,lfence,sfence,gcLimit,gcSetLimit,gcSetThreshold,gcCollect,gcReset,gcCheckpoint,gcRestore,gcSlabCount,gcSlabBytes,sockMake,sockBind,sockListen,sockAccept,sockRecv,sockSend,sockClose,sockRecvStr,sockConnect,fdRead,fdWrite,fdClose,fdSetNonblock,sleepUs,ptyMaster,ptySlaveName,ptyForkExec,ptySetSize,procAlive,waitChild,unixConnect,memfdCreate,mmapShared,sockSendFd,readProc"
    if contains("," + builtins + ",", "," + fname + ",") {
        // `print` becomes THE newline print (Brian's ask). Route it to kp's
        // proven newline op (BUILTIN_KP) right here in the shared frontend, so
        // it lands on every backend with zero codegen edits. `kp` is unchanged
        // and stays as the fallback alias so already-built programs keep working.
        let bname = fname
        if bname == "print" { bname = "kp" }
        if bname == "gcSetThreshold" { bname = "gcSetLimit" }
        emit code + "BUILTIN " + bname + " " + argc + "\n," + (p + 1)
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
        // B2 multi-return: `return a, b, c` packs the values into an array(N)
        // (8-byte slots) and returns it; `let x, y = f()` destructures it.
        if tokAt(tokens, p) == "COMMA" {
            // B2: pack return values via ptrToInt-wrapped bufSetQwordAt so
            // polymorphic vals (string returns, struct returns) survive the
            // qword store's atoi. 2026-06-19 (w) Bug #1 FE workaround.
            let mr = "_mret_" + pos
            let sets = "LOAD " + mr + "\nPUSH 0\n" + code + "BUILTIN ptrToInt 1\nBUILTIN bufSetQwordAt 3\nPOP\n"
            let nv = 1
            while tokAt(tokens, p) == "COMMA" {
                let vp = irExpr(tokens, p + 1, ntoks, lc, types)
                sets = sets + "LOAD " + mr + "\nPUSH " + (nv * 8) + "\n" + pairVal(vp) + "BUILTIN ptrToInt 1\nBUILTIN bufSetQwordAt 3\nPOP\n"
                p = pairPos(vp)
                nv = nv + 1
            }
            if tokAt(tokens, p) == "SEMI" { p += 1 }
            let rst = ""
            if inFunc == "1" { rst = "" }
            emit "LOCAL " + mr + "\nPUSH " + (nv * 8) + "\nBUILTIN bufNew 1\nSTORE " + mr + "\n" + sets + "LOAD " + mr + "\n" + rst + "RETURN\n," + p
        }
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
            restoreCode = ""
            emit code + restoreCode + "RETURN\n," + p
        }
        // Top-level `return`/`emit <v>` = process exit. A plain RETURN here would
        // `ret` the raw value as the exit code; a string value is a heap pointer,
        // so dyld exit()s on garbage → SIGTRAP/SIGSEGV (test_line_ops `emit "ok"`).
        // Route through BUILTIN exit, which atoi-or-0's the value (string → 0,
        // numeric string/int → its value) and does a clean exit syscall.
        emit code + "BUILTIN exit 1\n," + p
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

    // switch / case / default (A2). No implicit fallthrough (Go-style).
    if tok == "KW:switch" {
        emit irSwitchIR(tokens, pos + 1, ntoks, lc, inFunc, types)
    }

    // static local decl (A6): its persistent global is initialised once at module
    // load (collected by the global-init scan). The decl itself emits no per-call
    // code; references to the name resolve to the global via resolveStatic.
    if tok == "KW:static" {
        let sp = pos + 1
        while sp < ntoks && tokAt(tokens, sp) != "ASSIGN" && tokAt(tokens, sp) != "SEMI" { sp += 1 }
        if tokAt(tokens, sp) == "ASSIGN" {
            let vp = irExpr(tokens, sp + 1, ntoks, lc, types)
            sp = pairPos(vp)
        }
        if tokAt(tokens, sp) == "SEMI" { sp += 1 }
        emit "," + sp
    }

    // B1 defer: `defer expr` runs expr at function exit (LIFO). Emit the expr's
    // code wrapped in KDEFER markers; irFuncIR's applyDefers pass relocates it to
    // before every RETURN + the fall-through end (and strips the markers).
    if tok == "KW:defer" {
        let dp = irExpr(tokens, pos + 1, ntoks, lc, types)
        let p = pairPos(dp)
        if tokAt(tokens, p) == "SEMI" { p += 1 }
        emit "KDEFER_START\n" + pairVal(dp) + "POP\nKDEFER_END\n," + p
    }

    // enum decl (A3): compile-time only (scanned by irScanEnums) — emit no code.
    if tok == "KW:enum" {
        let ep = pos + 1
        while ep < ntoks && tokAt(tokens, ep) != "LBRACE" { ep += 1 }
        emit "," + skipBlock(tokens, ep)
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
            let name = resolveStatic(types, tokVal(tok))   // A6: static -> its global
            let pair = irExpr(tokens, pos + 2, ntoks, lc, types)
            let rcode = pairVal(pair)
            let p = pairPos(pair)
            if tokAt(tokens, p) == "SEMI" { p += 1 }
            // A7: float-aware compound assignment — if the target is an f64 var or
            // the rhs is a float, use fadd/fsub/fmul/fdiv (MOD has no float form).
            let isFloat = irTypeOf(types, name) == "f64" || pairType(pair) == "f64"
            let op = "ADD\n"
            if isFloat { op = "BUILTIN fadd 2\n" }
            if nt == "MINUSEQ" { op = "SUB\n"  if isFloat { op = "BUILTIN fsub 2\n" } }
            if nt == "STAREQ"  { op = "MUL\n"  if isFloat { op = "BUILTIN fmul 2\n" } }
            if nt == "SLASHEQ" { op = "DIV\n"  if isFloat { op = "BUILTIN fdiv 2\n" } }
            if nt == "MODEQ"   { op = "MOD\n" }
            emit "LOAD " + name + "\n" + rcode + op + "STORE " + name + "\n," + p
        }
    }

    // post-increment / post-decrement statement: i++  i--
    if tt == "ID" {
        let nt = tokAt(tokens, pos + 1)
        if nt == "PLUSPLUS" || nt == "MINUSMINUS" {
            let name = resolveStatic(types, tokVal(tok))   // A6: static -> its global
            let p = pos + 2
            if tokAt(tokens, p) == "SEMI" { p += 1 }
            // A7: f64 ++/-- uses fadd/fsub (the int 1 auto-promotes).
            let isFloat = irTypeOf(types, name) == "f64"
            let op = "ADD\n"
            if isFloat { op = "BUILTIN fadd 2\n" }
            if nt == "MINUSMINUS" { op = "SUB\n"  if isFloat { op = "BUILTIN fsub 2\n" } }
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
                let baseExtra = ""
                if varType == "*u8" {
                    setOp = "BUILTIN bufSetByte 3\n"
                } else if varType == "*u16" || varType == "*i16" {
                    setOp = "BUILTIN bufSetWordAt 3\n"
                    scaleOp = "PUSH 2\nMUL\n"
                } else if varType == "*u32" || varType == "*i32" {
                    setOp = "BUILTIN bufSetDwordAt 3\n"
                    scaleOp = "PUSH 4\nMUL\n"
                } else if varType == "*u64" || varType == "*i64" {
                    // Phase C typed: bare atoi/itoa is correct (ints only).
                    setOp = "BUILTIN bufSetQwordAt 3\n"
                    scaleOp = "PUSH 8\nMUL\n"
                } else if varType == "__array" {
                    // A5 polymorphic: wrap value in ptrToInt so atoi inside
                    // bufSetQwordAt sees a numeric string and stores the raw
                    // 64-bit pointer value. Reader intToPtr's it back.
                    // 2026-06-19 (w): FE-only Bug #1 workaround.
                    setOp = "BUILTIN ptrToInt 1\nBUILTIN bufSetQwordAt 3\n"
                    scaleOp = "PUSH 8\nMUL\n"
                } else if varType == "__slice" {
                    setOp = "BUILTIN ptrToInt 1\nBUILTIN bufSetQwordAt 3\n"
                    scaleOp = "PUSH 8\nMUL\n"
                }
                if varType == "__slice" {
                    // B3 slice write s[i] = v: bufSetQwordAt(base, byteOff + i*8, ptrToInt(v)).
                    // base (slot 0) intToPtr'd back from its stored decimal addr.
                    let idxp = irExpr(tokens, pos + 2, ntoks, lc, types)
                    let valp = irExpr(tokens, pB + 2, ntoks, lc, types)
                    let p = pairPos(valp)
                    if tokAt(tokens, p) == "SEMI" { p += 1 }
                    emit "LOAD " + name + "\nPUSH 0\nBUILTIN bufGetQwordAt 2\nBUILTIN intToPtr 1\n" +
                         "LOAD " + name + "\nPUSH 8\nBUILTIN bufGetQwordAt 2\n" + pairVal(idxp) + "PUSH 8\nMUL\nADD\n" +
                         pairVal(valp) + "BUILTIN ptrToInt 1\nBUILTIN bufSetQwordAt 3\nPOP\n," + p
                }
                if len(setOp) > 0 {
                    let idxp = irExpr(tokens, pos + 2, ntoks, lc, types)
                    let valp = irExpr(tokens, pB + 2, ntoks, lc, types)
                    let p = pairPos(valp)
                    if tokAt(tokens, p) == "SEMI" { p += 1 }
                    emit "LOAD " + name + "\n" + baseExtra + pairVal(idxp) + scaleOp +
                         pairVal(valp) + setOp + "POP\n," + p
                }
            }
        }
    }

    // plain assignment
    if tt == "ID" && tokAt(tokens, pos + 1) == "ASSIGN" {
        let name = resolveStatic(types, tokVal(tok))   // A6: static -> its global
        let pair = irExpr(tokens, pos + 2, ntoks, lc, types)
        let code = pairVal(pair)
        let p = pairPos(pair)
        if tokAt(tokens, p) == "SEMI" { p += 1 }
        // 2.0-alpha-3 stage 6 prep: re-root the new value on the shadow
        // stack. Without this, a sweep between the reassignment and the
        // next read could collect the new heap-allocated value.
        emit code + "STORE " + name + "\n," + p
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

func irSkipReturnType(tokens, pos) {
    if tokAt(tokens, pos) != "ARROW" { emit pos }
    let p = pos + 1
    let nt = lineCount(tokens)
    while p < nt && tokAt(tokens, p) != "LBRACE" {
        let tk = tokAt(tokens, p)
        if tk == "ID:void" {
            printErr("kcc: use `do` for no-return functions; `void` is not Krypton.")
            exit(1)
        }
        p += 1
    }
    emit p
}

// Look up a name's type in the per-function types table.
// Each line is "name|type". Returns "" if not found.
func irTypeOf(types, name) {
    // Single linear pass: O(len). The old getLine(types,i) per index rescanned
    // from the start each time → O(count^2); irTypeOf is called per expression
    // during IR gen → O(n^2) that stalled native self-host on big functions.
    let n = len(types)
    let needle = name + "|"
    let nlen = len(needle)
    let start = 0
    while start < n {
        let e = start
        while e < n && types[e] != "\n" { e += 1 }
        if e - start > nlen {
            if substring(types, start, start + nlen) == needle {
                emit substring(types, start + nlen, e)
            }
        }
        start = e + 1
    }
    emit ""
}

// A6: if `name` is a static local (alias `__staticref:<global>` in types),
// return the mangled global name; otherwise return `name` unchanged. Used at
// every LOAD/STORE site so references to a static hit its persistent global.
func resolveStatic(types, name) {
    let t = irTypeOf(types, name)
    if len(t) >= 12 && substring(t, 0, 12) == "__staticref:" {
        emit substring(t, 12, len(t))
    }
    emit name
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
    // B2 multi-return destructuring: `let a, b, ... = expr` — expr must yield a
    // multi-return array (8-byte slots); bind each name to a slot.
    if tokAt(tokens, pos + 1) == "COMMA" {
        let nms = name
        let nc = 1
        let np = pos + 1
        while tokAt(tokens, np) == "COMMA" {
            np = np + 1
            nms = nms + "," + tokVal(tokAt(tokens, np))
            np = np + 1
            nc = nc + 1
        }
        if tokAt(tokens, np) == "ASSIGN" { np = np + 1 }
        let rp = irExpr(tokens, np, ntoks, lc, types)
        let p = pairPos(rp)
        if tokAt(tokens, p) == "SEMI" { p += 1 }
        // 2026-06-19 (w): intToPtr-unwrap each slot (mirrors the pack-time
        // ptrToInt wrap) so string/struct returns are recovered as pointers.
        let rt = "_mdes_" + pos
        let out = "LOCAL " + rt + "\n" + pairVal(rp) + "STORE " + rt + "\n"
        let k = 0
        while k < nc {
            let nm = getNthParam(nms, k)
            out = out + "LOCAL " + nm + "\nLOAD " + rt + "\nPUSH " + (k * 8) + "\nBUILTIN bufGetQwordAt 2\nBUILTIN intToPtr 1\nSTORE " + nm + "\n"
            k = k + 1
        }
        emit out + "," + p
    }
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
    // Skip an optional `: TYPE` annotation by scanning to the ASSIGN. The
    // type-body skip (irSkipTypeBody) mis-handles some bare primitive type
    // names (i32/f64/...), landing before `=` → the initializer was dropped and
    // the local default-inited to "". Scanning to ASSIGN is robust for
    // `let NAME [: TYPE] = EXPR`; `=` (ASSIGN) never appears inside a type or
    // an initializer expression (which uses EQ/NEQ, not ASSIGN).
    let p = pos + 1
    while p < ntoks && tokAt(tokens, p) != "ASSIGN" && tokAt(tokens, p) != "SEMI" { p += 1 }
    if tokAt(tokens, p) != "ASSIGN" {
        // declaration without initializer — default to empty string.
        emit "LOCAL " + name + "\nPUSH \"\"\nSTORE " + name +
             "\n," + p
    }
    p += 1   // skip ASSIGN
    // B3 slices: `let s = SRC[lo:hi]` builds a (base, byteOff, len, cap) quad in
    // a 32-byte GC buffer (slots 0/8/16/24). SRC is an __array (base = SRC
    // handle) or __slice (base = SRC slot 0). The base buffer HANDLE is kept
    // pristine — never pointer-arithmetic'd — because GC handles are tagged and
    // raw ADD corrupts them; the start position is carried in the byteOff slot
    // instead, and index reads do bufGetQwordAt(base, byteOff + i*8). byteOff =
    // (array) lo*8 OR (reslice) SRC.byteOff + lo*8; len = hi-lo; cap = (array)
    // len OR (reslice) SRC.cap - lo. The let var holds the quad ptr and is
    // tracked __slice by the pre-pass. Pure FE over the A5 buf builtins (8-byte
    // slots, int/pointer). append: TODO — pairs with the GC freelist work.
    let s3src = tokAt(tokens, p)
    if len(s3src) >= 3 && substring(s3src, 0, 3) == "ID:" && tokAt(tokens, p + 1) == "LBRACK" {
        let s3name = substring(s3src, 3, len(s3src))
        let s3ty = irTypeOf(types, s3name)
        if s3ty == "__array" || s3ty == "__slice" {
            let s3lo = irExpr(tokens, p + 2, ntoks, lc, types)
            let s3loCode = pairVal(s3lo)
            let s3q = pairPos(s3lo)
            if tokAt(tokens, s3q) == "COLON" {
                let s3hi = irExpr(tokens, s3q + 1, ntoks, lc, types)
                let s3hiCode = pairVal(s3hi)
                let s3r = pairPos(s3hi)
                if tokAt(tokens, s3r) == "RBRACK" { s3r += 1 }
                if tokAt(tokens, s3r) == "SEMI" { s3r += 1 }
                // base handle, byte offset, and cap source differ array vs reslice.
                let s3base = "LOAD " + s3name + "\n"
                let s3off = s3loCode + "PUSH 8\nMUL\n"
                let s3cap = s3hiCode + s3loCode + "SUB\n"
                if s3ty == "__slice" {
                    // reslicing: pull base ptr via intToPtr (matches store path).
                    s3base = "LOAD " + s3name + "\nPUSH 0\nBUILTIN bufGetQwordAt 2\nBUILTIN intToPtr 1\n"
                    s3off = "LOAD " + s3name + "\nPUSH 8\nBUILTIN bufGetQwordAt 2\n" + s3loCode + "PUSH 8\nMUL\nADD\n"
                    s3cap = "LOAD " + s3name + "\nPUSH 24\nBUILTIN bufGetQwordAt 2\n" + s3loCode + "SUB\n"
                }
                // 2026-06-19 (w): slot 0 = base ptr, wrap in ptrToInt so the
                // bufSetQwordAt atoi stores the full 64-bit address. Slots
                // 8/16/24 are ints and bypass the wrap.
                let s3out = "LOCAL " + name + "\nPUSH 32\nBUILTIN bufNew 1\nSTORE " + name + "\n"
                s3out = s3out + "LOAD " + name + "\nPUSH 0\n" + s3base + "BUILTIN ptrToInt 1\nBUILTIN bufSetQwordAt 3\nPOP\n"
                s3out = s3out + "LOAD " + name + "\nPUSH 8\n" + s3off + "BUILTIN bufSetQwordAt 3\nPOP\n"
                s3out = s3out + "LOAD " + name + "\nPUSH 16\n" + s3hiCode + s3loCode + "SUB\nBUILTIN bufSetQwordAt 3\nPOP\n"
                s3out = s3out + "LOAD " + name + "\nPUSH 24\n" + s3cap + "BUILTIN bufSetQwordAt 3\nPOP\n"
                s3out = s3out + ""
                emit s3out + "," + s3r
            }
        }
    }
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
    let pushCode = ""
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

// A2 switch/case. Lowered entirely to existing IR (temp + EQ + JUMPIF/JUMP/LABEL),
// so no backend change. The switch value is evaluated ONCE into a temp; each case
// value emits `LOAD tmp; <val>; EQ; JUMPIF body` (multi-value = several JUMPIFs);
// no match falls through to default (or end). No implicit fallthrough.
//
//   switch X { case A, B: S1   case C: S2   default: S3 }
//
// -> LOCAL t; <X>; STORE t
//    LOAD t;A;EQ;JUMPIF b0  LOAD t;B;EQ;JUMPIF b0  LOAD t;C;EQ;JUMPIF b1
//    JUMP def
//    LABEL b0; S1; JUMP end   LABEL b1; S2; JUMP end
//    LABEL def; S3; JUMP end   LABEL end
func irSwitchIR(tokens, pos, ntoks, lc, inFunc, types) {
    let ep = irExpr(tokens, pos, ntoks, lc, types)
    let exprCode = pairVal(ep)
    let p = pairPos(ep)
    let swId = "__sw_" + pos
    let endLabel = "_swend_" + pos
    let defLabel = "_swdef_" + pos
    if tokAt(tokens, p) == "LBRACE" { p += 1 }
    let checks = sbNew()
    let bodies = sbNew()
    let defBody = ""
    let hasDef = "0"
    let caseN = 0
    while tokAt(tokens, p) != "RBRACE" && p < ntoks {
        if tokAt(tokens, p) == "KW:case" {
            p += 1
            let bodyLabel = "_swc_" + pos + "_" + caseN
            let more = "1"
            while more == "1" {
                let vp = irExpr(tokens, p, ntoks, lc, types)
                checks = sbAppend(checks, "LOAD " + swId + "\n" + pairVal(vp) + "EQ\nJUMPIF " + bodyLabel + "\n")
                p = pairPos(vp)
                if tokAt(tokens, p) == "COMMA" { p += 1 } else { more = "0" }
            }
            if tokAt(tokens, p) == "COLON" { p += 1 }
            let bodySb = sbNew()
            while tokAt(tokens, p) != "KW:case" && tokAt(tokens, p) != "KW:default" && tokAt(tokens, p) != "RBRACE" && p < ntoks {
                let sp = irStmt(tokens, p, ntoks, lc, inFunc, types)
                bodySb = sbAppend(bodySb, pairVal(sp))
                p = pairPos(sp)
            }
            bodies = sbAppend(bodies, "LABEL " + bodyLabel + "\n" + sbToString(bodySb) + "JUMP " + endLabel + "\n")
            caseN = caseN + 1
        } else if tokAt(tokens, p) == "KW:default" {
            p += 1
            if tokAt(tokens, p) == "COLON" { p += 1 }
            let dSb = sbNew()
            while tokAt(tokens, p) != "KW:case" && tokAt(tokens, p) != "KW:default" && tokAt(tokens, p) != "RBRACE" && p < ntoks {
                let sp = irStmt(tokens, p, ntoks, lc, inFunc, types)
                dSb = sbAppend(dSb, pairVal(sp))
                p = pairPos(sp)
            }
            defBody = sbToString(dSb)
            hasDef = "1"
        } else {
            p += 1
        }
    }
    if tokAt(tokens, p) == "RBRACE" { p += 1 }
    let out = "LOCAL " + swId + "\n" + exprCode + "STORE " + swId + "\n" + sbToString(checks)
    if hasDef == "1" {
        out = out + "JUMP " + defLabel + "\n" + sbToString(bodies) + "LABEL " + defLabel + "\n" + defBody + "JUMP " + endLabel + "\nLABEL " + endLabel + "\n"
    } else {
        out = out + "JUMP " + endLabel + "\n" + sbToString(bodies) + "LABEL " + endLabel + "\n"
    }
    emit out + "," + p
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
// A3 enums. Scan `enum Name { A, B, C }` and record each member as a compile-time
// int constant `Name.Member|<i>` (autoincrement from 0) in the types table. Member
// access (Name.Member) resolves to PUSH <i> in irPrimary; the decl emits no code.
// Uses substring (string==) not startsWith==\"1\" (the latter is dead on macho).
func irScanEnums(tokens, ntoks) {
    let sb = sbNew()
    let i = 0
    while i < ntoks {
        if tokAt(tokens, i) == "KW:enum" {
            let nameTk = tokAt(tokens, i + 1)
            if len(nameTk) >= 3 && substring(nameTk, 0, 3) == "ID:" && tokAt(tokens, i + 2) == "LBRACE" {
                let ename = substring(nameTk, 3, len(nameTk))
                let p = i + 3
                let val = 0
                while p < ntoks && tokAt(tokens, p) != "RBRACE" {
                    let mTk = tokAt(tokens, p)
                    if len(mTk) >= 3 && substring(mTk, 0, 3) == "ID:" {
                        sb = sbAppend(sb, ename + "." + substring(mTk, 3, len(mTk)) + "|" + val + "\n")
                        val = val + 1
                    }
                    p = p + 1
                }
            }
        }
        i = i + 1
    }
    emit sbToString(sb)
}

// A6: collect every `static let n = v` (in any function) and emit its init as a
// module global __static_<declpos>_<n> (mangled by the `static` token index — must
// match irScanFuncTypes). Prepended to __main__ so each static is initialised ONCE
// at module load; references in the owning function resolve to this global.
func irScanStatics(tokens, ntoks, types) {
    let sb = sbNew()
    let i = 0
    while i < ntoks {
        if tokAt(tokens, i) == "KW:static" && tokAt(tokens, i + 1) == "KW:let" {
            let snTk = tokAt(tokens, i + 2)
            if len(snTk) >= 3 && substring(snTk, 0, 3) == "ID:" {
                let snm = substring(snTk, 3, len(snTk))
                let mangled = "kstatic_" + i + "_" + snm   // non-__ so it registers as a global
                let ap = i + 3
                while ap < ntoks && tokAt(tokens, ap) != "ASSIGN" && tokAt(tokens, ap) != "SEMI" { ap += 1 }
                let vcode = "PUSH 0\n"
                if tokAt(tokens, ap) == "ASSIGN" {
                    let vp = irExpr(tokens, ap + 1, ntoks, 0, types)
                    vcode = pairVal(vp)
                }
                sb = sbAppend(sb, "LOCAL " + mangled + "\n" + vcode + "STORE " + mangled + "\n")
            }
        }
        i = i + 1
    }
    emit sbToString(sb)
}

func kccStructTypes(tokens, ntoks) {
    if environ("KCC_NO_TYPE_SCAN") == "1" { emit "" }
    emit irScanStructTypes(tokens, ntoks)
}

func kccFuncTypes(tokens, bodyStart, ntoks) {
    if environ("KCC_NO_TYPE_SCAN") == "1" { emit "" }
    emit irScanFuncTypes(tokens, bodyStart, ntoks)
}

func kccEnums(tokens, ntoks) {
    if environ("KCC_NO_TYPE_SCAN") == "1" { emit "" }
    emit irScanEnums(tokens, ntoks)
}

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
func irScanFuncTypes(tokens, bodyStart, ntoks) {
    if tokAt(tokens, bodyStart) != "LBRACE" { emit "" }
    let p = bodyStart + 1
    let depth = 1
    // ntoks passed in (was lineCount(tokens) — an O(ntoks) rescan per function).
    let nTok = ntoks
    let sb = sbNew()
    while p < nTok && depth > 0 {
        let tk = tokAt(tokens, p)
        if tk == "LBRACE" { depth += 1  p += 1  continue }
        if tk == "RBRACE" { depth -= 1  p += 1  continue }
        // A6 static locals: `static let n = v` — record n as an alias to a
        // unique module global __static_<declpos>_<n> (mangled by the `static`
        // token position, so two functions' statics never collide). References
        // to n in this function resolve to that global (resolveStatic).
        if tk == "KW:static" && tokAt(tokens, p + 1) == "KW:let" {
            let snTk = tokAt(tokens, p + 2)
            if len(snTk) >= 3 && substring(snTk, 0, 3) == "ID:" {
                let snm = substring(snTk, 3, len(snTk))
                // NB: the global name must NOT start with __ — the macho backend's
                // collectModuleGlobals skips __-prefixed names as compiler-internal,
                // so a __static_* name would never register as a real global.
                sb = sbAppend(sb, snm + "|__staticref:kstatic_" + p + "_" + snm + "\n")
            }
        }
        // A5: `let arr = array(N)` — track arr as __array so arr[i] / arr[i]=v lower
        // to bufGetQwordAt/bufSetQwordAt (8-byte slots). substring, not startsWith==1.
        if tk == "KW:let" {
            let anTk = tokAt(tokens, p + 1)
            if len(anTk) >= 3 && substring(anTk, 0, 3) == "ID:" && tokAt(tokens, p + 2) == "ASSIGN" && tokAt(tokens, p + 3) == "ID:array" && tokAt(tokens, p + 4) == "LPAREN" {
                sb = sbAppend(sb, substring(anTk, 3, len(anTk)) + "|__array\n")
            }
        }
        // B3: `let s = SRC[lo:hi]` — track s as __slice so s[i] double-indirects
        // through the base ptr and s.len/s.cap read the triple. Detect a COLON at
        // bracket depth 1. substring, not startsWith==1 (dead on macho).
        if tk == "KW:let" {
            let slNm = tokAt(tokens, p + 1)
            if len(slNm) >= 3 && substring(slNm, 0, 3) == "ID:" && tokAt(tokens, p + 2) == "ASSIGN" {
                let slSrc = tokAt(tokens, p + 3)
                if len(slSrc) >= 3 && substring(slSrc, 0, 3) == "ID:" && tokAt(tokens, p + 4) == "LBRACK" {
                    let slP = p + 5
                    let slD = 1
                    let slIs = 0
                    while slP < nTok && slD > 0 {
                        let slT = tokAt(tokens, slP)
                        if slT == "LBRACK" { slD += 1 }
                        if slT == "RBRACK" { slD -= 1 }
                        if slT == "COLON" && slD == 1 { slIs = 1 }
                        slP += 1
                    }
                    if slIs == 1 { sb = sbAppend(sb, substring(slNm, 3, len(slNm)) + "|__slice\n") }
                }
            }
        }
        // B3: `let s2 = append(SRC, v)` where SRC is already a tracked __slice
        // -> s2 is also a __slice. Check the in-progress table (contains used
        // bare, not == "1" which is dead on macho). \n-anchored to avoid a
        // suffix false-match (e.g. "s" vs "xs").
        if tk == "KW:let" {
            let apNm = tokAt(tokens, p + 1)
            if len(apNm) >= 3 && substring(apNm, 0, 3) == "ID:" && tokAt(tokens, p + 2) == "ASSIGN" && tokAt(tokens, p + 3) == "ID:append" && tokAt(tokens, p + 4) == "LPAREN" {
                let apSrc = tokAt(tokens, p + 5)
                if len(apSrc) >= 3 && substring(apSrc, 0, 3) == "ID:" {
                    let apS = substring(apSrc, 3, len(apSrc))
                    if contains("\n" + sbToString(sb), "\n" + apS + "|__slice\n") {
                        sb = sbAppend(sb, substring(apNm, 3, len(apNm)) + "|__slice\n")
                    }
                }
            }
        }
        if tk == "KW:let" || tk == "KW:const" {
            // A1: narrow f64/f32 tracking for float-operator inference. Done
            // here with substring (string==) because `startsWith(...) == "1"`
            // is dead on macho (startsWith returns int 1; 1 == "1" is false).
            // We deliberately record ONLY float scalar types — the general
            // type-annotation tracking below stays gated by the (dormant)
            // startsWith check so we don't activate the buggy pointer/struct/
            // closure specialization paths that programs currently work around.
            let f64Tk = tokAt(tokens, p + 1)
            if len(f64Tk) >= 3 && substring(f64Tk, 0, 3) == "ID:" {
                if tokAt(tokens, p + 2) == "COLON" {
                    let tTk = tokAt(tokens, p + 3)
                    if tTk == "ID:f64" || tTk == "ID:f32" {
                        sb = sbAppend(sb, substring(f64Tk, 3, len(f64Tk)) + "|" + substring(tTk, 3, len(tTk)) + "\n")
                    }
                }
            }
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
    p = irSkipReturnType(tokens, p)

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

    let funcTypes = kccStructTypes(tokens, ntoks) + kccFuncTypes(tokens, p, ntoks) + paramTypes + captureTypes + kccEnums(tokens, ntoks)
    let bp = irBlockIR(tokens, p, ntoks, 0, "1", funcTypes)
    let bodyCode = pairVal(bp)
    p = pairPos(bp)
    emit "FUNC " + lambdaName + " " + pc + "\n" + allParams + bodyCode + "RETURN\nEND\n\n," + p
}

// B1 defer: relocate KDEFER_START..KDEFER_END blocks (emitted inline at the defer
// site by irStmt) to run at function exit. Forward pass: accumulate each deferred
// block LIFO (prepend), strip it from its inline position, and inject the
// accumulated-so-far before every RETURN and at the fall-through end. Lexical
// scope: a return only runs defers declared textually before it.
func applyDefers(body) {
    if indexOf(body, "KDEFER_START") < 0 { emit body }
    let out = sbNew()
    let deferAccum = ""
    let nl = lineCount(body)
    let i = 0
    while i < nl {
        let line = getLine(body, i)
        if line == "KDEFER_START" {
            let blk = ""
            i = i + 1
            while i < nl && getLine(body, i) != "KDEFER_END" {
                blk = blk + getLine(body, i) + "\n"
                i = i + 1
            }
            deferAccum = blk + deferAccum
        } else if line == "RETURN" {
            out = sbAppend(out, deferAccum + "RETURN\n")
        } else {
            out = sbAppend(out, line + "\n")
        }
        i = i + 1
    }
    out = sbAppend(out, deferAccum)
    emit sbToString(out)
}

func irFuncIR(tokens, pos, ntoks, structTypes) {
    // pos is at KW:func
    // structTypes: whole-stream struct-type scan, precomputed ONCE by the
    // caller and threaded in. Previously irFuncIR called
    // irScanStructTypes(tokens, ntoks) itself — a 16-iteration fixpoint over
    // the ENTIRE token stream — once per function, making IR emission
    // O(ntoks * nfuncs) (elf.k: ~16 min). Hoisting it out makes that term
    // O(ntoks) total.
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
    p = irSkipReturnType(tokens, p)
    // Phase C: pre-scan body for `let X: TYPE` so irPrimary can tag
    // LOADs with type hints and irPostfix can specialize INDEX into
    // typed-pointer reads. Also scan struct definitions across the
    // whole token stream so `*Vec3.field` lowers to a typed offset
    // read. paramTypes appended last so typed params (e.g. `cb: fp`)
    // route through callPtr in irCall.
    // structTypes is precomputed once by the caller (was an O(n*nfuncs)
    // whole-stream rescan per function here).
    let funcTypes = structTypes + kccFuncTypes(tokens, p, ntoks) + paramTypes
    let bp = irBlockIR(tokens, p, ntoks, 0, "1", funcTypes)
    let bodyCode = applyDefers(pairVal(bp))   // B1: relocate defers to exits
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
            paramPushes = paramPushes + ""
        }
        pli += 1
    }
    bodyCode = "" + paramPushes + bodyCode +
               ""
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
    let kccVer = "2.4.5"

    // Parse flags: --version, --ir, -o OUTFILE, --port-1to2
    // 1.8.4: removed --headers. Install root is fixed at C:\krypton;
    // stdlib lives at <root>/stdlib and C bindings at <root>/headers.
    // The new `k:` / `c:` import prefixes resolve under those.
    // 2.0-alpha-3: --port-1to2 is a diagnostic-only mode that scans
    // source for patterns needing attention before a 2.0 upgrade.
    // Default to IR mode — Krypton is now native-pipeline-only. The C-emit
    // path was removed 2026-06-04; the `irMode = 0` branches that still
    // exist in this file are dead code waiting on a final pass. Programs
    // invoked as `kcc foo.k` (no flags) should still emit IR, not nothing.
    let irMode = 1
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

    // Hard-reject deprecated C-emit / external-toolchain flags.
    let _aRej = 0
    while _aRej < argCount() {
        let _aFlag = arg(_aRej + "")
        if _aFlag == "--c"    { printErr("kcc: --c was removed (Krypton is C-free; native pipeline only).")    emit 1 }
        if _aFlag == "--gcc"  { printErr("kcc: --gcc was removed (Krypton is C-free; native pipeline only).")  emit 1 }
        if _aFlag == "--llvm" { printErr("kcc: --llvm was removed (Krypton is C-free; native pipeline only).") emit 1 }
        _aRej += 1
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

    // cRuntime() deleted entirely 2026-06-04 — Krypton's native pipeline
    // doesn't need C source. The 650-line C-emit function is gone from
    // this file. sb stays around as a buffer for whatever the legacy
    // dead-code paths used to write to (they're being deleted next).
    let sb = sbNew()

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

    // (Legacy C-mode lambda pre-scan removed 2026-06-05. Lambdas re-emit
    // through `irLambdaIR` later — IR has no need for lambdaBank.)
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
                if (prefix == "k" || prefix == "core") && sub == "objk" {
                    if environ("OS") == "Windows_NT" { fullPath = installRoot + "/stdlib/objkwin.k" }
                }
                if prefix == "k" && sub == "okui" {
                    if environ("OS") == "Windows_NT" { fullPath = installRoot + "/stdlib/okui_win.k" }
                }
                if prefix == "head"    { fullPath = installRoot + "/headers/" + sub + ".krh" }
                if prefix == "headers" { fullPath = installRoot + "/headers/" + sub + ".krh" }
                // .ks fallback: objk + KryptScript stdlib modules are tagged
                // .ks. If the .k form isn't present, retry the .ks form. (Not
                // everything moves to .ks — .k stays the default; this only
                // catches modules that were renamed.)
                if prefix == "k" || prefix == "core" {
                    if len(readFile(fullPath)) == 0 {
                        fullPath = installRoot + "/stdlib/" + sub + ".ks"
                    }
                }
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
	                    // Pull direct imports of imported modules too. This lets facade
	                    // modules (for example k:objk) hide their lower layers without
	                    // forcing app code to import k:cocoa/k:objc/head:* by hand.
	                    let depScan = 0
	                    while depScan < iNtoks {
	                        let depTok = tokAt(iToks, depScan)
	                        if depTok == "KW:import" {
	                            let depPath = tokVal(tokAt(iToks, depScan + 1))
	                            let depFull = depPath
	                            let depColon = indexOf(depPath, ":")
	                            if depColon > 0 && depColon < 8 {
	                                let depPrefix = substring(depPath, 0, depColon)
	                                let depSub = substring(depPath, depColon + 1, len(depPath))
	                                if depPrefix == "k"       { depFull = installRoot + "/stdlib/"  + depSub + ".k"   }
	                                if depPrefix == "core"    { depFull = installRoot + "/stdlib/"  + depSub + ".k"   }
	                                if (depPrefix == "k" || depPrefix == "core") && depSub == "objk" {
	                                    if environ("OS") == "Windows_NT" { depFull = installRoot + "/stdlib/objkwin.k" }
	                                }
	                                if depPrefix == "head"    { depFull = installRoot + "/headers/" + depSub + ".krh" }
	                                if depPrefix == "headers" { depFull = installRoot + "/headers/" + depSub + ".krh" }
	                                if depPrefix == "k" || depPrefix == "core" {
	                                    if len(readFile(depFull)) == 0 { depFull = installRoot + "/stdlib/" + depSub + ".ks" }
	                                }
	                            } else {
	                                let depBase = ""
	                                let depLastSlash = 0 - 1
	                                let depFi = 0
	                                while depFi < len(fullPath) {
	                                    if fullPath[depFi] == "/" || fullPath[depFi] == "\\" { depLastSlash = depFi }
	                                    depFi += 1
	                                }
	                                if depLastSlash >= 0 { depBase = substring(fullPath, 0, depLastSlash + 1) }
	                                if len(depBase) > 0 {
	                                    if !startsWith(depPath, "/") {
	                                        if !startsWith(depPath, "C:") { depFull = depBase + depPath }
	                                    }
	                                }
	                            }
	                            if !contains(imported, depFull + "|") {
	                                imported = imported + depFull + "|"
	                                let depSrc = readFile(depFull)
	                                if len(depSrc) > 0 {
	                                    let depToks = tokenize(depSrc)
	                                    let depNtoks = lineCount(depToks)
	                                    let depFtable = scanFunctions(depToks, depNtoks)
	                                    let depJ = 0
	                                    while depJ < depNtoks {
	                                        let depJTok = tokAt(depToks, depJ)
	                                        if depJTok == "KW:jxt" {
	                                            let depJxtPos = depJ + 2
	                                            while tokAt(depToks, depJxtPos) != "RBRACE" {
	                                                let depLang = tokVal(tokAt(depToks, depJxtPos))
	                                                if depLang == "c" || depLang == "t" {
	                                                    depJxtPos += 2
	                                                } else if depLang == "struct" {
	                                                    let depSName = tokVal(tokAt(depToks, depJxtPos + 1))
	                                                    let depSfPos = depJxtPos + 3
	                                                    let depSEntry = depSName + ":"
	                                                    let depSFirst = 1
	                                                    while tokAt(depToks, depSfPos) != "RBRACE" {
	                                                        if tokVal(tokAt(depToks, depSfPos)) == "field" {
	                                                            let depSfName = tokVal(tokAt(depToks, depSfPos + 1))
	                                                            let depSfType = tokVal(tokAt(depToks, depSfPos + 2))
	                                                            if tokType(tokAt(depToks, depSfPos + 3)) == "STR" { depSfPos = depSfPos + 4 }
	                                                            else { depSfPos = depSfPos + 3 }
	                                                            if depSFirst == 0 { depSEntry = depSEntry + "," }
	                                                            depSEntry = depSEntry + depSfName + ":" + depSfType
	                                                            depSFirst = 0
	                                                        } else {
	                                                            depSfPos += 1
	                                                        }
	                                                    }
	                                                    structTable = structTable + depSEntry + "\n"
	                                                    depJxtPos = depSfPos + 1
	                                                } else if depLang == "func" {
	                                                    let depFName = tokVal(tokAt(depToks, depJxtPos + 1))
	                                                    let depFPos = depJxtPos + 3
	                                                    let depFPc = 0
	                                                    while tokAt(depToks, depFPos) != "RPAREN" {
	                                                        if tokType(tokAt(depToks, depFPos)) == "ID" { depFPc += 1 }
	                                                        depFPos += 1
	                                                    }
	                                                    let depFInfo = depFName + ":" + depFPc + ":0"
	                                                    if len(ftable) > 0 { ftable = ftable + "\n" + depFInfo }
	                                                    else { ftable = depFInfo }
	                                                    depFPos += 1
	                                                    depFPos = irSkipReturnType(depToks, depFPos)
	                                                    depJxtPos = depFPos
	                                                } else {
	                                                    depJxtPos += 2
	                                                }
	                                            }
	                                            depJ = skipBlock(depToks, depJ + 1) - 1
	                                        }
	                                        depJ += 1
	                                    }
	                                    if irMode == 1 {
	                                        let depIRi = 0
	                                        let depStructTypes = irScanStructTypes(depToks, depNtoks)
	                                        while depIRi < depNtoks {
	                                            let depIRtok = tokAt(depToks, depIRi)
	                                            if depIRtok == "KW:jxt" {
	                                                depIRi = skipBlock(depToks, depIRi + 1)
	                                            } else if (depIRtok == "KW:func" || depIRtok == "KW:fn") {
	                                                let depIRfp = irFuncIR(depToks, depIRi, depNtoks, depStructTypes)
	                                                importedIR = importedIR + pairVal(depIRfp)
	                                                depIRi = pairPos(depIRfp)
	                                            } else {
	                                                depIRi += 1
	                                            }
	                                        }
	                                    }
	                                    if len(depFtable) > 0 {
	                                        if len(ftable) > 0 { ftable = ftable + "\n" + depFtable }
	                                        else { ftable = depFtable }
	                                    }
	                                } else {
	                                    printErr("kcc: import not found: " + depFull)
	                                }
	                            }
	                            depScan += 2
	                        } else {
	                            depScan += 1
	                        }
	                    }
	                    // forward declarations
	                    let iDecls = ""
                                        let ij = 0
                    while ij < iNtoks {
                        let itk = tokAt(iToks, ij)
                        if itk == "KW:jxt" {
                            // Process jxt block from imported file (IR-only)
                            let ijxtPos = ij + 2
                            while tokAt(iToks, ijxtPos) != "RBRACE" {
                                let ijLang = tokVal(tokAt(iToks, ijxtPos))
                                if ijLang == "c" || ijLang == "t" {
                                    ijxtPos += 2
                                } else if ijLang == "struct" {
                                    let isName = tokVal(tokAt(iToks, ijxtPos + 1))
                                    let isfPos = ijxtPos + 3
                                    let isEntry = isName + ":"
                                    let isFirst = 1
                                    while tokAt(iToks, isfPos) != "RBRACE" {
                                        if tokVal(tokAt(iToks, isfPos)) == "field" {
                                            let isfName = tokVal(tokAt(iToks, isfPos + 1))
                                            let isfType = tokVal(tokAt(iToks, isfPos + 2))
                                            if tokType(tokAt(iToks, isfPos + 3)) == "STR" {
                                                isfPos = isfPos + 4
                                            } else {
                                                isfPos = isfPos + 3
                                            }
                                            if isFirst == 0 { isEntry = isEntry + "," }
                                            isEntry = isEntry + isfName + ":" + isfType
                                            isFirst = 0
                                        } else {
                                            isfPos += 1
                                        }
                                    }
                                    structTable = structTable + isEntry + "\n"
                                    ijxtPos = isfPos + 1
                                } else if ijLang == "func" {
                                    let ijfName = tokVal(tokAt(iToks, ijxtPos + 1))
                                    let ijfPos = ijxtPos + 3
                                    let ijfPc = 0
                                    while tokAt(iToks, ijfPos) != "RPAREN" {
                                        if tokType(tokAt(iToks, ijfPos)) == "ID" { ijfPc += 1 }
                                        ijfPos += 1
                                    }
                                    let ijfInfo = ijfName + ":" + ijfPc + ":0"
                                    if len(ftable) > 0 { ftable = ftable + "\n" + ijfInfo }
                                    else { ftable = ijfInfo }
                                    ijfPos += 1
                                    ijfPos = irSkipReturnType(iToks, ijfPos)
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
                        } else if tokType(itk) == "CBLOCK" {
                        }
                        ij += 1
                    }
                    // (legacy --c path's compileImportedFunctions removed —
                    // IR-mode below handles function-body import via irFuncIR)
                    if irMode == 1 {
                        let iIRi = 0
                        let iIRinJxt = 0
                        let iStructTypes = kccStructTypes(iToks, iNtoks)
                        while iIRi < iNtoks {
                            let iIRtok = tokAt(iToks, iIRi)
                            if iIRtok == "KW:jxt" {
                                // skip entire jxt block
                                iIRi = skipBlock(iToks, iIRi + 1)
                            } else if (iIRtok == "KW:func" || iIRtok == "KW:fn") {
                                let iIRfp = irFuncIR(iToks, iIRi, iNtoks, iStructTypes)
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
            // jxt { k "module.k"  struct ...  func ... }   (IR-only)
            let jxtPos = ii + 2
            while tokAt(tokens, jxtPos) != "RBRACE" {
                let lang = tokVal(tokAt(tokens, jxtPos))
                let jxtPath = tokVal(tokAt(tokens, jxtPos + 1))
                if lang == "k" {
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
                    jxtPos += 2
                } else if lang == "struct" {
                    let sName = tokVal(tokAt(tokens, jxtPos + 1))
                    let sfPos = jxtPos + 3
                    let sEntry = sName + ":"
                    let sfFirst = 1
                    while tokAt(tokens, sfPos) != "RBRACE" {
                        if tokVal(tokAt(tokens, sfPos)) == "field" {
                            let sfName = tokVal(tokAt(tokens, sfPos + 1))
                            let sfType = tokVal(tokAt(tokens, sfPos + 2))
                            if tokType(tokAt(tokens, sfPos + 3)) == "STR" {
                                sfPos = sfPos + 4
                            } else {
                                sfPos = sfPos + 3
                            }
                            if sfFirst == 0 { sEntry = sEntry + "," }
                            sEntry = sEntry + sfName + ":" + sfType
                            sfFirst = 0
                        } else {
                            sfPos += 1
                        }
                    }
                    structTable = structTable + sEntry + "\n"
                    jxtPos = sfPos + 1
                } else if lang == "func" {
                    let jfName = tokVal(tokAt(tokens, jxtPos + 1))
                    let jfPos = jxtPos + 3
                    let jfPc = 0
                    while tokAt(tokens, jfPos) != "RPAREN" {
                        if tokType(tokAt(tokens, jfPos)) == "ID" { jfPc += 1 }
                        jfPos += 1
                    }
                    let jfInfo = jfName + ":" + jfPc + ":0"
                    if len(ftable) > 0 { ftable = ftable + "\n" + jfInfo }
                    else { ftable = jfInfo }
                    jfPos += 1
                    jfPos = irSkipReturnType(tokens, jfPos)
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
                lskip = irSkipReturnType(tokens, lskip)
                i = skipBlock(tokens, lskip) - 1
            }
            let fname = tokVal(nameTok)
            if len(fname) > 0 {
            let info = funcLookup(ftable, fname)
            let pc = funcParamCount(info)
            // Forward decl always uses char*. decl MUST be initialized
            // unconditionally — the old `if pc==0` left it NULL for funcs WITH
            // params, and sbAppend(sb, NULL) below strlen-crashes the FE (the
            // param-func SIGSEGV). (this builds the discarded
            // C-output sb, but the concat runs before sb is dropped in --ir mode.)
            let decl = "char* " + fname + "("
            sb = sbAppend(sb, decl)
            }
        } else if tok == "KW:callback" {
            // callback func — skip the func keyword, name, params, body
            // do/no-value forward decl emitted by body pass; no char* decl needed here
            let cbSkip = i + 3
            while cbSkip < ntoks && tokAt(tokens, cbSkip) != "RPAREN" { cbSkip += 1 }
            cbSkip += 1
            cbSkip = irSkipReturnType(tokens, cbSkip)
            i = skipBlock(tokens, cbSkip) - 1
        } else if tokType(tok) == "CBLOCK" {
            // cfunc { } — skip in forward-decl pass, emitted in body pass
        } else if tok == "KW:let" {
            // top-level global let — skip the rest of the line. compileExpr
            // was deleted with the C-emit code; for the forward-decl pass we
            // just need to advance past the expression, not evaluate it.
            // Tokenizer emits one expression per logical line, so scan to the
            // next KW-level token.
            let gfp = i + 2
            if tokAt(tokens, gfp) == "COLON" { gfp += 2 }
            if tokAt(tokens, gfp) == "ASSIGN" {
                let gscan = gfp + 1
                let gdepth = 0
                while gscan < ntoks {
                    let gstk = tokAt(tokens, gscan)
                    if gdepth == 0 {
                        if gstk == "KW:let" || gstk == "KW:func" || gstk == "KW:fn" || gstk == "KW:import" || gstk == "KW:struct" || gstk == "KW:type" || gstk == "KW:enum" || gstk == "KW:jxt" || gstk == "KW:export" { gscan = gscan - 1  break }
                        if gstk == "RBRACE" { gscan = gscan - 1  break }   // exiting outer block
                    }
                    if gstk == "LPAREN" || gstk == "LBRACE" || gstk == "LBRACK" { gdepth += 1 }
                    else if gstk == "RPAREN" || gstk == "RBRACK" || gstk == "RBRACE" { gdepth -= 1 }
                    gscan += 1
                }
                i = gscan
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
        } else if tok == "KW:enum" {
            // A3: enum decl is compile-time only (scanned by irScanEnums) — skip body.
            i = skipBlock(tokens, i + 2) - 1
        } else if tok == "KW:interface" {
            // B4: interface decl is compile-time signature docs only — skip body.
            i = skipBlock(tokens, i + 2) - 1
        } else if tok == "KW:struct" || tok == "KW:class" || tok == "KW:type" {
            // emit forward decl for struct constructor
            let sn = tokVal(tokAt(tokens, i + 1))
            if len(sn) > 0 {
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
            let gname = tokVal(tokAt(tokens, i + 1))
            let gp = i + 2
            // skip optional type annotation
            let gtype = "str"
            if tokAt(tokens, gp) == "COLON" {
                gtype = tokVal(tokAt(tokens, gp + 1))
                gp += 2
            }
            // Body-pass global initializer — compileExpr was deleted with the
            // C-emit code; sbGlobals feeds the legacy C main(), which is also
            // guarded out in --ir mode. Just advance past the expression.
            if tokAt(tokens, gp) == "ASSIGN" {
                gp += 1
                let gscan2 = gp
                let gdepth2 = 0
                while gscan2 < ntoks {
                    let gstk2 = tokAt(tokens, gscan2)
                    if gdepth2 == 0 {
                        if gstk2 == "KW:let" || gstk2 == "KW:func" || gstk2 == "KW:fn" || gstk2 == "KW:import" || gstk2 == "KW:struct" || gstk2 == "KW:type" || gstk2 == "KW:enum" || gstk2 == "KW:jxt" || gstk2 == "KW:export" { break }
                        if gstk2 == "RBRACE" { break }
                    }
                    if gstk2 == "LPAREN" || gstk2 == "LBRACE" || gstk2 == "LBRACK" { gdepth2 += 1 }
                    else if gstk2 == "RPAREN" || gstk2 == "RBRACK" || gstk2 == "RBRACE" { gdepth2 -= 1 }
                    gscan2 += 1
                }
                i = gscan2
            } else {
                i = gp
            }
        } else if tok == "KW:func" || tok == "KW:fn" {
            // Walk past the func — IR is generated separately by irFuncIR.
            // Handles both lambdas (no name) and named funcs.
            let sk = i + 2
            if tokAt(tokens, i + 1) != "LPAREN" { sk = i + 3 }   // skip name + LPAREN for named funcs
            while sk < ntoks && tokAt(tokens, sk) != "RPAREN" { sk += 1 }
            sk += 1
            sk = irSkipReturnType(tokens, sk)
            i = skipBlock(tokens, sk)
        } else if tok == "KW:callback" {
            let cbSk = i + 3
            while cbSk < ntoks && tokAt(tokens, cbSk) != "RPAREN" { cbSk += 1 }
            cbSk += 1
            cbSk = irSkipReturnType(tokens, cbSk)
            i = skipBlock(tokens, cbSk)
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
        } else if tok == "KW:enum" {
            // A3: enum decl — compile-time only; skip its body.
            i = skipBlock(tokens, i + 2) - 1
        } else if tok == "KW:interface" {
            // B4: interface decl — compile-time signature docs only; skip body.
            i = skipBlock(tokens, i + 2) - 1
        } else if tok == "KW:struct" || tok == "KW:class" || tok == "KW:type" {
            // Inline struct compilation to avoid pairPos issues
            let sname = tokVal(tokAt(tokens, i + 1))
            let scname = sname
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
                    // skip optional default value (walk past expr to next statement)
                    if tokAt(tokens, sp2) == "ASSIGN" {
                        sp2 = sp2 + 1
                        let sedepth = 0
                        while sp2 < ntoks {
                            let setk = tokAt(tokens, sp2)
                            if sedepth == 0 {
                                if setk == "KW:let" { break }
                                if setk == "RBRACE" { break }
                            }
                            if setk == "LPAREN" || setk == "LBRACE" || setk == "LBRACK" { sedepth += 1 }
                            else if setk == "RPAREN" || setk == "RBRACK" { sedepth -= 1 }
                            else if setk == "RBRACE" { sedepth -= 1 }
                            sp2 += 1
                        }
                    }
                } else { sp2 += 1 }
            }
            // emit typedef
            let sout = "typedef struct " + scname + "_s {\n"
            let si = 0
            while si < sfc {
                let sfn = getNthParam(sfields, si)
                si += 1
            }
            let si2 = 0
            while si2 < sfc {
                let sfn2 = getNthParam(sfields, si2)
                si2 += 1
            }
            sb = sbAppend(sb, sout)
            // advance past struct body
            i = sp2
        } else {
            i += 1
        }
    }

    // Find and compile the entry block
    let entry = findEntry(tokens, ntoks)

    // 2.3 deprecation warning: when a file with `just run { ... }` is part
    // of a multi-file project (signalled by an explicit `module` decl),
    // the entry-point file should be named `run.k`. Single-file scripts
    // are exempt. This is a WARNING in 2.3 and becomes an ERROR in 2.4
    // — give users one full release to rename.
    //
    // Detection:
    //   - entry >= 0 (this file owns the `just run` body)
    //   - the file basename is NOT "run.k" / "run.ks"
    //   - the token stream contains `module <ident>` (multi-file project)
    //
    // We don't gate on import presence because a project entry might
    // import nothing today but still be part of a multi-file layout.
    if entry >= 0 {
        let runkBase = substring(file, lastSlash + 1, len(file))
        if runkBase != "run.k" && runkBase != "run.ks" {
            let hasModule = 0
            let modI = 0
            while modI < ntoks && hasModule == 0 {
                if tokAt(tokens, modI) == "KW:module" { hasModule = 1 }
                modI += 1
            }
            if hasModule == 1 {
                printErr("kcc: warning: entry-point file should be named `run.k` (got `")
                printErr(runkBase + "`)\n")
                printErr("  Multi-file projects (those with `module <name>`) must place\n")
                printErr("  their `just run { ... }` body in `run.k`. This is a warning in\n")
                printErr("  2.3 and becomes an error in 2.4 — rename now to stay forward-compatible.\n")
            }
        }
    }

    if entry < 0 {
        if irMode {
            // DLL/library IR mode: emit IR for export funcs, no entry point
            let sbIRlib = sbNew()
            sbIRlib = sbAppend(sbIRlib, "; Krypton IR\n; Source: " + file + "\n\n")
            sbIRlib = sbAppend(sbIRlib, importedIR)
            let irlibI = 0
            let libStructTypes = kccStructTypes(tokens, ntoks)
            while irlibI < ntoks {
                let irlibTok = tokAt(tokens, irlibI)
                if irlibTok == "KW:func" || irlibTok == "KW:fn" {
                    let irlibFp = irFuncIR(tokens, irlibI, ntoks, libStructTypes)
                    sbIRlib = sbAppend(sbIRlib, pairVal(irlibFp))
                    irlibI = pairPos(irlibFp)
                } else if irlibTok == "KW:export" {
                    let irlibNext = tokAt(tokens, irlibI + 1)
                    if irlibNext == "KW:func" || irlibNext == "KW:fn" {
                        let irlibFname = tokVal(tokAt(tokens, irlibI + 2))
                        let irlibFp = irFuncIR(tokens, irlibI + 1, ntoks, libStructTypes)
                        sbIRlib = sbAppend(sbIRlib, "EXPORT " + irlibFname + "\n")
                        sbIRlib = sbAppend(sbIRlib, pairVal(irlibFp))
                        irlibI = pairPos(irlibFp)
                    } else { irlibI += 1 }
                } else { irlibI += 1 }
            }
            let irLibText = sbToString(sbIRlib)
            if len(outFile) > 0 {
                let compilerDir = replace(headersDir, "headers", "bin")
                let tmpDir = environ("TEMP")
                if tmpDir == "" { tmpDir = environ("TMP") }
                if tmpDir == "" { tmpDir = environ("TMPDIR") }
                if tmpDir == "" {
                    if environ("OS") == "Windows_NT" { tmpDir = "C:\\Windows\\Temp" }
                    else { tmpDir = "/tmp" }
                }
                let tmpBase = replace(replace(replace(outFile, "\\", "_"), "/", "_"), ":", "_")
                let tmpIR  = tmpDir + "/tmp_kcc_build_" + tmpBase + ".ir"
                let tmpOpt = tmpDir + "/tmp_kcc_build_" + tmpBase + "_opt.ir"
                writeFile(tmpIR, irLibText)
                let optCmd2  = compilerDir + "\\optimize_host.exe " + tmpIR + " > " + tmpOpt
                let codeCmd2 = compilerDir + "\\x64_host_new.exe " + tmpOpt + " " + outFile
                shellRun(optCmd2)
                shellRun(codeCmd2)
                DeleteFileA(tmpIR)
                DeleteFileA(tmpOpt)
                emit 0
            }
            print(irLibText)
            emit 0
        }
        // library file with no entry point — emit C
        print(sbToString(sb))
        emit 0
    }

    // (Legacy C `int main(...)` emission removed 2026-06-05. Krypton is
    // native-pipeline only now; the IR block below is the only output.)

    if irMode {
        let sbIR = sbNew()
        sbIR = sbAppend(sbIR, "; Krypton IR\n; Source: " + file + "\n\n")
        sbIR = sbAppend(sbIR, importedIR)

        // Collect top-level globals (let/const at file scope) so we can prepend
        // their init code to __main__ as locals — gives globals a working
        // home without a dedicated .bss region in the ELF backend.
        let sbGlobInit = sbNew()
        let iri = 0
        let mainStructTypes = kccStructTypes(tokens, ntoks)
        while iri < ntoks {
            let irtok = tokAt(tokens, iri)
            if irtok == "KW:func" || irtok == "KW:fn" {
                let fp = irFuncIR(tokens, iri, ntoks, mainStructTypes)
                sbIR = sbAppend(sbIR, pairVal(fp))
                iri = pairPos(fp)
            } else if irtok == "KW:export" {
                let expNext = tokAt(tokens, iri + 1)
                if expNext == "KW:func" || expNext == "KW:fn" {
                    let expFname = tokVal(tokAt(tokens, iri + 2))
                    let efp = irFuncIR(tokens, iri + 1, ntoks, mainStructTypes)
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
                        let nfp = irFuncIR(tokens, scanP, ntoks, mainStructTypes)
                        sbIR = sbAppend(sbIR, pairVal(nfp))
                        scanP = pairPos(nfp)
                    } else {
                        scanP += 1
                    }
                }
                iri = scanP
            } else if irtok == "KW:enum" {
                // A3: enum decl — compile-time only (scanned by irScanEnums). Skip
                // body; no constructor (unlike struct).
                let eP = iri + 2
                while eP < ntoks && tokAt(tokens, eP) != "LBRACE" { eP += 1 }
                iri = skipBlock(tokens, eP)
            } else if irtok == "KW:interface" {
                // B4: interface decl — compile-time signature docs only. Skip the
                // whole block so its bodyless `func m(...)` method signatures are
                // NOT compiled as real functions (no constructor, like enum).
                let ifP = iri + 2
                while ifP < ntoks && tokAt(tokens, ifP) != "LBRACE" { ifP += 1 }
                iri = skipBlock(tokens, ifP)
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
            let mainTypes = kccStructTypes(tokens, ntoks) + kccFuncTypes(tokens, irEntry, ntoks) + kccEnums(tokens, ntoks)
            let ep = irBlockIR(tokens, irEntry, ntoks, 0, "0", mainTypes)
            // 2.0-alpha-3 GC stage 3: same shadow-stack save/restore wrap
            // as irFuncIR applies to __main__'s body (and prepended global
            // inits). On normal exit, all per-let pushes get popped.
            let mainBody = irScanStatics(tokens, ntoks, mainTypes) + sbToString(sbGlobInit) + pairVal(ep)
            mainBody = "" + mainBody +
                       ""
            sbIR = sbAppend(sbIR, "FUNC __main__ 0\n" + mainBody + "END\n")
        }

        let irText = sbToString(sbIR)

        // -o mode: run full native pipeline internally
        if len(outFile) > 0 {
            let compilerDir = replace(headersDir, "headers", "bin")
            let tmpDir = environ("TEMP")
            if tmpDir == "" { tmpDir = environ("TMP") }
            if tmpDir == "" { tmpDir = environ("TMPDIR") }
            if tmpDir == "" {
                if environ("OS") == "Windows_NT" { tmpDir = "C:\\Windows\\Temp" }
                else { tmpDir = "/tmp" }
            }
            let tmpBase = replace(replace(replace(outFile, "\\", "_"), "/", "_"), ":", "_")
            let tmpIR  = tmpDir + "/tmp_kcc_build_" + tmpBase + ".ir"
            let tmpOpt = tmpDir + "/tmp_kcc_build_" + tmpBase + "_opt.ir"
            writeFile(tmpIR, irText)
            let optCmd  = compilerDir + "\\optimize_host.exe " + tmpIR + " > " + tmpOpt
            let codeCmd = compilerDir + "\\x64_host_new.exe " + tmpOpt + " " + outFile
            shellRun(optCmd)
            shellRun(codeCmd)
            DeleteFileA(tmpIR)
            DeleteFileA(tmpOpt)
            emit 0
        }

        print(irText)
        emit 0
    }

    print(sbToString(sb))
}
