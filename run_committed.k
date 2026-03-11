// ============================================================
// Krypton Bootstrap Compiler/Interpreter
// Written in Krypton, runs on kcc (the C++ reference compiler)
// Usage: kcc kompiler/run.k <file.k>
// ============================================================

// ── String Utilities ──────────────────────────────────────

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
    if c < 0 {
        emit 0
    }
    emit toInt(substring(pair, c + 1, len(pair)))
}

// getLine and lineCount are native builtins

// ── Token Helpers ─────────────────────────────────────────

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

// ── Tokenizer ─────────────────────────────────────────────

func expandEscapes(s) {
    let r = ""
    let i = 0
    let start = 0
    while i < len(s) {
        if s[i] == "\\" && i + 1 < len(s) {
            if i > start {
                r = r + substring(s, start, i)
            }
            let nc = s[i + 1]
            if nc == "n" {
                r = r + "\n"
            }
            else if nc == "t" {
                r = r + "\t"
            }
            else if nc == "\\" {
                r = r + "\\"
            }
            else if nc == "\"" {
                r = r + "\""
            }
            else {
                r = r + substring(s, i, i + 1)
            }
            i = i + 2
            start = i
        }
        else {
            i = i + 1
        }
    }
    if i > start {
        r = r + substring(s, start, i)
    }
    emit r
}

func isDigit(c) {
    emit c >= "0" && c <= "9"
}

func isAlpha(c) {
    emit (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_"
}

func isAlphaNum(c) {
    emit isAlpha(c) || isDigit(c)
}

func readNumber(text, i) {
    let start = i
    while i < len(text) && isDigit(text[i]) {
        i = i + 1
    }
    emit substring(text, start, i) + "," + i
}

func readIdent(text, i) {
    let start = i
    while i < len(text) && isAlphaNum(text[i]) {
        i = i + 1
    }
    emit substring(text, start, i) + "," + i
}

func readString(text, i) {
    i = i + 1
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
            i = i + 1
        }
    }
    if i > start {
        s = s + substring(text, start, i)
    }
    emit s + "," + (i + 1)
}

func skipWS(text, i) {
    while i < len(text) && (text[i] == " " || text[i] == "\n" || text[i] == "\t" || text[i] == "\r") {
        i = i + 1
    }
    emit i
}

func skipComment(text, i) {
    if i + 1 < len(text) && text[i] == "/" && text[i + 1] == "/" {
        while i < len(text) && text[i] != "\n" {
            i = i + 1
        }
        emit i
    }
    else if i + 1 < len(text) && text[i] == "/" && text[i + 1] == "*" {
        i = i + 2
        while i + 1 < len(text) && (text[i] != "*" || text[i + 1] != "/") {
            i = i + 1
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
    else if word == "module" { emit 1 }
    else if word == "quantum" { emit 1 }
    else if word == "qpute" { emit 1 }
    else if word == "process" { emit 1 }
    else if word == "true" { emit 1 }
    else if word == "false" { emit 1 }
    else if word == "measure" { emit 1 }
    else if word == "prepare" { emit 1 }
    else { emit 0 }
}

func tokenize(text) {
    let out = ""
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
            out = out + "INT:" + num + "\n"
        }
        else if c == "\"" {
            let pair = readString(text, i)
            let str = pairVal(pair)
            i = pairPos(pair)
            out = out + "STR:" + str + "\n"
        }
        else if isAlpha(c) {
            let pair = readIdent(text, i)
            let id = pairVal(pair)
            i = pairPos(pair)
            if isKW(id) {
                out = out + "KW:" + id + "\n"
            }
            else {
                out = out + "ID:" + id + "\n"
            }
        }
        else if c == "+" {
            out = out + "PLUS\n"
            i = i + 1
        }
        else if c == "-" {
            if i + 1 < len(text) && text[i + 1] == ">" {
                out = out + "ARROW\n"
                i = i + 2
            }
            else {
                out = out + "MINUS\n"
                i = i + 1
            }
        }
        else if c == "*" {
            out = out + "STAR\n"
            i = i + 1
        }
        else if c == "/" {
            out = out + "SLASH\n"
            i = i + 1
        }
        else if c == "(" {
            out = out + "LPAREN\n"
            i = i + 1
        }
        else if c == ")" {
            out = out + "RPAREN\n"
            i = i + 1
        }
        else if c == "{" {
            out = out + "LBRACE\n"
            i = i + 1
        }
        else if c == "}" {
            out = out + "RBRACE\n"
            i = i + 1
        }
        else if c == "[" {
            out = out + "LBRACK\n"
            i = i + 1
        }
        else if c == "]" {
            out = out + "RBRACK\n"
            i = i + 1
        }
        else if c == ":" {
            out = out + "COLON\n"
            i = i + 1
        }
        else if c == ";" {
            out = out + "SEMI\n"
            i = i + 1
        }
        else if c == "," {
            out = out + "COMMA\n"
            i = i + 1
        }
        else if c == "=" {
            if i + 1 < len(text) && text[i + 1] == "=" {
                out = out + "EQ\n"
                i = i + 2
            }
            else {
                out = out + "ASSIGN\n"
                i = i + 1
            }
        }
        else if c == "!" {
            if i + 1 < len(text) && text[i + 1] == "=" {
                out = out + "NEQ\n"
                i = i + 2
            }
            else {
                out = out + "BANG\n"
                i = i + 1
            }
        }
        else if c == "<" {
            if i + 1 < len(text) && text[i + 1] == "=" {
                out = out + "LTE\n"
                i = i + 2
            }
            else {
                out = out + "LT\n"
                i = i + 1
            }
        }
        else if c == ">" {
            if i + 1 < len(text) && text[i + 1] == "=" {
                out = out + "GTE\n"
                i = i + 2
            }
            else {
                out = out + "GT\n"
                i = i + 1
            }
        }
        else if c == "&" {
            if i + 1 < len(text) && text[i + 1] == "&" {
                out = out + "AND\n"
                i = i + 2
            }
            else {
                i = i + 1
            }
        }
        else if c == "|" {
            if i + 1 < len(text) && text[i + 1] == "|" {
                out = out + "OR\n"
                i = i + 2
            }
            else {
                i = i + 1
            }
        }
        else {
            i = i + 1
        }
    }

    emit out
}

// ── Environment ───────────────────────────────────────────
// env is a string: "name=value\nname2=value2\n..."
// last-match semantics for shadowing

func envNew() {
    emit ""
}

func envGet(env, name) {
    // env format: name=LEN:value\n (length-prefixed, no escaping)
    let result = ""
    let found = 0
    let i = 0
    while i < len(env) {
        // find = for this entry
        let eqPos = i
        while eqPos < len(env) && env[eqPos] != "=" {
            eqPos = eqPos + 1
        }
        let entryName = substring(env, i, eqPos)
        // find : to get length
        let colonPos = eqPos + 1
        while colonPos < len(env) && env[colonPos] != ":" {
            colonPos = colonPos + 1
        }
        let vlen = toInt(substring(env, eqPos + 1, colonPos))
        let valStart = colonPos + 1
        if entryName == name {
            result = substring(env, valStart, valStart + vlen)
            found = 1
        }
        // skip past value + trailing newline
        i = valStart + vlen + 1
    }
    if found == 0 {
        if name != "__argOffset" {
            print("ERROR: undefined variable: " + name)
        }
    }
    emit result
}

func envSet(env, name, val) {
    // Length-prefixed with dedup: replace existing entry if found
    let newEntry = name + "=" + len(val) + ":" + val + "\n"
    let lastStart = -1
    let lastEnd = -1
    let i = 0
    while i < len(env) {
        let entryStart = i
        let eqPos = i
        while eqPos < len(env) && env[eqPos] != "=" {
            eqPos = eqPos + 1
        }
        let entryName = substring(env, i, eqPos)
        let colonPos = eqPos + 1
        while colonPos < len(env) && env[colonPos] != ":" {
            colonPos = colonPos + 1
        }
        let vlen = toInt(substring(env, eqPos + 1, colonPos))
        let entryEnd = colonPos + 1 + vlen + 1
        if entryName == name {
            lastStart = entryStart
            lastEnd = entryEnd
        }
        i = entryEnd
    }
    if lastStart >= 0 {
        emit substring(env, 0, lastStart) + substring(env, lastEnd, len(env)) + newEntry
    }
    emit env + newEntry
}

// ── Function Table ────────────────────────────────────────
// Format: "name\tparamCount\tp1,p2,...\tstartTokIdx\n..."
// startTokIdx points to the LBRACE of the function body

func scanFunctions(tokens, ntoks) {
    let table = ""
    let i = 0
    while i < ntoks {
        let tok = tokAt(tokens, i)
        if tok == "KW:func" || tok == "KW:fn" {
            let nameTok = tokAt(tokens, i + 1)
            let fname = tokVal(nameTok)
            // skip name, LPAREN
            let pi = i + 3
            let params = ""
            let pc = 0
            while tokAt(tokens, pi) != "RPAREN" {
                if tokType(tokAt(tokens, pi)) == "ID" {
                    if pc > 0 {
                        params = params + "," + tokVal(tokAt(tokens, pi))
                    }
                    else {
                        params = tokVal(tokAt(tokens, pi))
                    }
                    pc = pc + 1
                }
                pi = pi + 1
            }
            // pi is at RPAREN, next should be LBRACE (possibly after arrow+type)
            pi = pi + 1
            while tokAt(tokens, pi) != "LBRACE" {
                pi = pi + 1
            }
            table = table + fname + "~" + pc + "~" + params + "~" + pi + "\n"
            // skip past the function body
            i = pi
            let depth = 0
            while i < ntoks {
                let t = tokAt(tokens, i)
                if t == "LBRACE" {
                    depth = depth + 1
                }
                else if t == "RBRACE" {
                    depth = depth - 1
                    if depth == 0 {
                        i = i + 1
                        break
                    }
                }
                i = i + 1
            }
        }
        else {
            i = i + 1
        }
    }
    emit table
}

func funcLookup(table, name) {
    // returns "paramCount~p1,p2,...~startTokIdx" or "" if not found
    let i = 0
    let lineStart = 0
    while i <= len(table) {
        if i == len(table) || table[i] == "\n" {
            let line = substring(table, lineStart, i)
            // find first tilde
            let t1 = -1
            let j = 0
            while j < len(line) {
                if line[j] == "~" && t1 == -1 {
                    t1 = j
                }
                j = j + 1
            }
            if t1 > 0 {
                let fName = substring(line, 0, t1)
                if fName == name {
                    emit substring(line, t1 + 1, len(line))
                }
            }
            lineStart = i + 1
        }
        i = i + 1
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
    // between first and second tilde
    let t1 = -1
    let t2 = -1
    let i = 0
    while i < len(info) {
        if info[i] == "~" {
            if t1 == -1 {
                t1 = i
            }
            else if t2 == -1 {
                t2 = i
            }
        }
        i = i + 1
    }
    if t1 >= 0 && t2 >= 0 {
        emit substring(info, t1 + 1, t2)
    }
    emit ""
}

func funcStart(info) {
    // after last tilde
    let last = -1
    let i = 0
    while i < len(info) {
        if info[i] == "~" {
            last = i
        }
        i = i + 1
    }
    if last >= 0 {
        emit toInt(substring(info, last + 1, len(info)))
    }
    emit 0
}

func getNthParam(params, idx) {
    // comma-separated param names
    let n = 0
    let start = 0
    let i = 0
    while i <= len(params) {
        if i == len(params) || params[i] == "," {
            if n == idx {
                emit substring(params, start, i)
            }
            n = n + 1
            start = i + 1
        }
        i = i + 1
    }
    emit ""
}

// ── Find entry point ──────────────────────────────────────

func findEntry(tokens, ntoks) {
    // Look for: KW:go ID:run LBRACE  OR  KW:just ID:run LBRACE
    let i = 0
    while i + 2 < ntoks {
        let t0 = tokAt(tokens, i)
        let t1 = tokAt(tokens, i + 1)
        let t2 = tokAt(tokens, i + 2)
        if (t0 == "KW:go" || t0 == "KW:just") && t1 == "ID:run" && t2 == "LBRACE" {
            emit i + 2
        }
        i = i + 1
    }
    print("ERROR: no 'go run' or 'just run' block found")
    emit -1
}

// ── Skip Block ────────────────────────────────────────────

func skipBlock(tokens, pos) {
    // pos should point to LBRACE, returns position after matching RBRACE
    let depth = 0
    let i = pos
    let ntoks = lineCount(tokens)
    while i < ntoks {
        let t = tokAt(tokens, i)
        if t == "LBRACE" {
            depth = depth + 1
        }
        else if t == "RBRACE" {
            depth = depth - 1
            if depth == 0 {
                emit i + 1
            }
        }
        i = i + 1
    }
    emit i
}

// ── Expression Evaluator ──────────────────────────────────
// All eval functions return "value,pos" (use pairVal/pairPos)
// Precedence: or < and < eq/neq < rel < add/sub < mul/div < unary < postfix < primary

func evalExpr(tokens, pos, env, ftable) {
    emit evalOr(tokens, pos, env, ftable)
}

func evalOr(tokens, pos, env, ftable) {
    let pair = evalAnd(tokens, pos, env, ftable)
    let left = pairVal(pair)
    let p = pairPos(pair)

    while tokAt(tokens, p) == "OR" {
        let pair2 = evalAnd(tokens, p + 1, env, ftable)
        let right = pairVal(pair2)
        p = pairPos(pair2)
        if left != "0" && left != "" && left != "false" {
            left = "1"
        }
        else if right != "0" && right != "" && right != "false" {
            left = "1"
        }
        else {
            left = "0"
        }
    }

    emit left + "," + p
}

func evalAnd(tokens, pos, env, ftable) {
    let pair = evalEquality(tokens, pos, env, ftable)
    let left = pairVal(pair)
    let p = pairPos(pair)

    while tokAt(tokens, p) == "AND" {
        let pair2 = evalEquality(tokens, p + 1, env, ftable)
        let right = pairVal(pair2)
        p = pairPos(pair2)
        if (left == "0" || left == "" || left == "false") {
            left = "0"
        }
        else if (right == "0" || right == "" || right == "false") {
            left = "0"
        }
        else {
            left = "1"
        }
    }

    emit left + "," + p
}

func evalEquality(tokens, pos, env, ftable) {
    let pair = evalRelational(tokens, pos, env, ftable)
    let left = pairVal(pair)
    let p = pairPos(pair)

    while tokAt(tokens, p) == "EQ" || tokAt(tokens, p) == "NEQ" {
        let op = tokAt(tokens, p)
        let pair2 = evalRelational(tokens, p + 1, env, ftable)
        let right = pairVal(pair2)
        p = pairPos(pair2)
        if op == "EQ" {
            if left == right {
                left = "1"
            }
            else {
                left = "0"
            }
        }
        else {
            if left != right {
                left = "1"
            }
            else {
                left = "0"
            }
        }
    }

    emit left + "," + p
}

func evalRelational(tokens, pos, env, ftable) {
    let pair = evalAdditive(tokens, pos, env, ftable)
    let left = pairVal(pair)
    let p = pairPos(pair)

    while tokAt(tokens, p) == "LT" || tokAt(tokens, p) == "GT" || tokAt(tokens, p) == "LTE" || tokAt(tokens, p) == "GTE" {
        let op = tokAt(tokens, p)
        let pair2 = evalAdditive(tokens, p + 1, env, ftable)
        let right = pairVal(pair2)
        p = pairPos(pair2)
        let li = toInt(left)
        let ri = toInt(right)
        let numL = li + "" == left
        let numR = ri + "" == right
        if numL && numR {
            if op == "LT" {
                if li < ri { left = "1" } else { left = "0" }
            }
            else if op == "GT" {
                if li > ri { left = "1" } else { left = "0" }
            }
            else if op == "LTE" {
                if li <= ri { left = "1" } else { left = "0" }
            }
            else {
                if li >= ri { left = "1" } else { left = "0" }
            }
        }
        else {
            if op == "LT" {
                if left < right { left = "1" } else { left = "0" }
            }
            else if op == "GT" {
                if left > right { left = "1" } else { left = "0" }
            }
            else if op == "LTE" {
                if left <= right { left = "1" } else { left = "0" }
            }
            else {
                if left >= right { left = "1" } else { left = "0" }
            }
        }
    }

    emit left + "," + p
}

func evalAdditive(tokens, pos, env, ftable) {
    let pair = evalMult(tokens, pos, env, ftable)
    let left = pairVal(pair)
    let p = pairPos(pair)

    while tokAt(tokens, p) == "PLUS" || tokAt(tokens, p) == "MINUS" {
        let op = tokAt(tokens, p)
        let pair2 = evalMult(tokens, p + 1, env, ftable)
        let right = pairVal(pair2)
        p = pairPos(pair2)
        // try numeric, else string concat for +
        let li = toInt(left)
        let ri = toInt(right)
        if op == "PLUS" {
            // if both look numeric
            if li + "" == left && ri + "" == right {
                left = li + ri + ""
            }
            else {
                left = left + right
            }
        }
        else {
            left = (li - ri) + ""
        }
    }

    emit left + "," + p
}

func evalMult(tokens, pos, env, ftable) {
    let pair = evalUnary(tokens, pos, env, ftable)
    let left = pairVal(pair)
    let p = pairPos(pair)

    while tokAt(tokens, p) == "STAR" || tokAt(tokens, p) == "SLASH" {
        let op = tokAt(tokens, p)
        let pair2 = evalUnary(tokens, p + 1, env, ftable)
        let right = pairVal(pair2)
        p = pairPos(pair2)
        let li = toInt(left)
        let ri = toInt(right)
        if op == "STAR" {
            left = (li * ri) + ""
        }
        else {
            left = (li / ri) + ""
        }
    }

    emit left + "," + p
}

func evalUnary(tokens, pos, env, ftable) {
    let tok = tokAt(tokens, pos)
    if tok == "MINUS" {
        let pair = evalUnary(tokens, pos + 1, env, ftable)
        let val = pairVal(pair)
        let p = pairPos(pair)
        let n = toInt(val)
        emit (0 - n) + "," + p
    }
    if tok == "BANG" {
        let pair = evalUnary(tokens, pos + 1, env, ftable)
        let val = pairVal(pair)
        let p = pairPos(pair)
        if val == "0" || val == "" || val == "false" {
            emit "1," + p
        }
        else {
            emit "0," + p
        }
    }
    emit evalPostfix(tokens, pos, env, ftable)
}

func evalPostfix(tokens, pos, env, ftable) {
    let pair = evalPrimary(tokens, pos, env, ftable)
    let val = pairVal(pair)
    let p = pairPos(pair)

    while tokAt(tokens, p) == "LBRACK" {
        let pair2 = evalExpr(tokens, p + 1, env, ftable)
        let idx = pairVal(pair2)
        let p2 = pairPos(pair2)
        // expect RBRACK
        p = p2 + 1
        let ii = toInt(idx)
        if ii >= 0 && ii < len(val) {
            val = val[ii]
        }
        else {
            val = ""
        }
    }

    emit val + "," + p
}

func evalPrimary(tokens, pos, env, ftable) {
    let tok = tokAt(tokens, pos)
    let tt = tokType(tok)
    let tv = tokVal(tok)

    // integer literal
    if tt == "INT" {
        emit tv + "," + (pos + 1)
    }

    // string literal — expand escape sequences at evaluation time
    if tt == "STR" {
        emit expandEscapes(tv) + "," + (pos + 1)
    }

    // boolean
    if tok == "KW:true" {
        emit "1," + (pos + 1)
    }
    if tok == "KW:false" {
        emit "0," + (pos + 1)
    }

    // grouping
    if tok == "LPAREN" {
        let pair = evalExpr(tokens, pos + 1, env, ftable)
        let val = pairVal(pair)
        let p = pairPos(pair)
        // expect RPAREN
        emit val + "," + (p + 1)
    }

    // identifier or function call
    if tt == "ID" {
        let next = tokAt(tokens, pos + 1)
        if next == "LPAREN" {
            // function call
            emit evalCall(tokens, pos, env, ftable)
        }
        else {
            // variable lookup
            let val = envGet(env, tv)
            emit val + "," + (pos + 1)
        }
    }

    // fallback
    emit "," + (pos + 1)
}

// ── Function Call Evaluator ───────────────────────────────

func evalCall(tokens, pos, env, ftable) {
    let fname = tokVal(tokAt(tokens, pos))
    let p = pos + 2  // skip name + LPAREN

    // collect arguments
    let args = ""
    let argc = 0
    if tokAt(tokens, p) != "RPAREN" {
        let pair = evalExpr(tokens, p, env, ftable)
        args = pairVal(pair)
        p = pairPos(pair)
        argc = 1

        while tokAt(tokens, p) == "COMMA" {
            let pair2 = evalExpr(tokens, p + 1, env, ftable)
            args = args + "\t" + pairVal(pair2)
            p = pairPos(pair2)
            argc = argc + 1
        }
    }
    // skip RPAREN
    p = p + 1

    // ── Built-in functions ──
    if fname == "print" || fname == "kp" {
        if argc > 0 {
            print(getArg(args, 0))
        }
        emit "," + p
    }

    if fname == "len" {
        let s = getArg(args, 0)
        emit len(s) + "," + p
    }

    if fname == "substring" {
        let s = getArg(args, 0)
        let start = toInt(getArg(args, 1))
        let end = toInt(getArg(args, 2))
        emit substring(s, start, end) + "," + p
    }

    if fname == "toInt" {
        let s = getArg(args, 0)
        emit toInt(s) + "," + p
    }

    if fname == "split" {
        let s = getArg(args, 0)
        let idx = toInt(getArg(args, 1))
        emit split(s, idx) + "," + p
    }

    if fname == "startsWith" {
        let s = getArg(args, 0)
        let prefix = getArg(args, 1)
        emit startsWith(s, prefix) + "," + p
    }

    if fname == "count" {
        let s = getArg(args, 0)
        emit count(s) + "," + p
    }

    if fname == "readFile" {
        let path = getArg(args, 0)
        emit readFile(path) + "," + p
    }

    if fname == "arg" {
        let idx = toInt(getArg(args, 0))
        let offset = toInt(envGet(env, "__argOffset"))
        emit arg(idx + offset) + "," + p
    }

    if fname == "argCount" {
        let offset = toInt(envGet(env, "__argOffset"))
        emit (argCount() - offset) + "," + p
    }

    if fname == "getLine" {
        let s = getArg(args, 0)
        let idx = toInt(getArg(args, 1))
        emit getLine(s, idx) + "," + p
    }

    if fname == "tokAt" {
        let s = getArg(args, 0)
        let idx = toInt(getArg(args, 1))
        emit tokAt(s, idx) + "," + p
    }

    if fname == "lineCount" {
        let s = getArg(args, 0)
        emit lineCount(s) + "," + p
    }

    if fname == "envGet" {
        let e = getArg(args, 0)
        let n = getArg(args, 1)
        emit envGet(e, n) + "," + p
    }

    if fname == "envSet" {
        let e = getArg(args, 0)
        let n = getArg(args, 1)
        let v = getArg(args, 2)
        emit envSet(e, n, v) + "," + p
    }

    if fname == "pairVal" {
        let s = getArg(args, 0)
        emit pairVal(s) + "," + p
    }

    if fname == "pairPos" {
        let s = getArg(args, 0)
        emit pairPos(s) + "," + p
    }

    if fname == "tokType" {
        let s = getArg(args, 0)
        emit tokType(s) + "," + p
    }

    if fname == "tokVal" {
        let s = getArg(args, 0)
        emit tokVal(s) + "," + p
    }

    if fname == "findLastComma" {
        let s = getArg(args, 0)
        emit findLastComma(s) + "," + p
    }

    if fname == "tokenize" {
        let s = getArg(args, 0)
        emit tokenize(s) + "," + p
    }

    if fname == "scanFunctions" {
        let s = getArg(args, 0)
        let n = toInt(getArg(args, 1))
        emit scanFunctions(s, n) + "," + p
    }

    if fname == "findEntry" {
        let s = getArg(args, 0)
        let n = toInt(getArg(args, 1))
        emit findEntry(s, n) + "," + p
    }

    // ── User-defined functions ──
    let info = funcLookup(ftable, fname)
    if info != "" {
        let pc = funcParamCount(info)
        let paramStr = funcParams(info)
        let bodyStart = funcStart(info)

        // bind params
        let fenv = env
        let a = 0
        while a < pc {
            let pname = getNthParam(paramStr, a)
            let aval = getArg(args, a)
            fenv = envSet(fenv, pname, aval)
            a = a + 1
        }

        // execute function body (bodyStart points to LBRACE)
        let result = execBlock(tokens, bodyStart, fenv, ftable)
        let tag = getResultTag(result)
        let rval = getResultVal(result)
        // R means return/emit
        if tag == "R" {
            emit rval + "," + p
        }
        emit "," + p
    }

    // unknown function
    print("ERROR: unknown function: " + fname)
    emit "," + p
}

func getArg(args, idx) {
    // tab-separated
    let n = 0
    let start = 0
    let i = 0
    while i <= len(args) {
        if i == len(args) || args[i] == "\t" {
            if n == idx {
                emit substring(args, start, i)
            }
            n = n + 1
            start = i + 1
        }
        i = i + 1
    }
    emit ""
}

// ── Statement Executor ────────────────────────────────────
// Returns "C\tenv\tpos" (continue), "R\tvalue\tpos" (return/emit), "B\tenv\tpos" (break)

func makeResult(tag, val, env, pos) {
    // Length-prefixed: tag|pos|vlen|elen|val_bytes_env_bytes
    emit tag + "|" + pos + "|" + len(val) + "|" + len(env) + "|" + val + env
}

func getResultTag(r) {
    emit r[0]
}

func getResultVal(r) {
    // tag|pos|vlen|elen|data...
    // skip past tag| (index 2), find pos end
    let i = 2
    while i < len(r) && r[i] != "|" {
        i = i + 1
    }
    // i is at pipe after pos, skip to vlen
    let vlenStart = i + 1
    i = vlenStart
    while i < len(r) && r[i] != "|" {
        i = i + 1
    }
    let vlen = toInt(substring(r, vlenStart, i))
    // skip past elen
    let elenStart = i + 1
    i = elenStart
    while i < len(r) && r[i] != "|" {
        i = i + 1
    }
    let dataStart = i + 1
    emit substring(r, dataStart, dataStart + vlen)
}

func getResultEnv(r) {
    // tag|pos|vlen|elen|data...
    let i = 2
    while i < len(r) && r[i] != "|" {
        i = i + 1
    }
    let vlenStart = i + 1
    i = vlenStart
    while i < len(r) && r[i] != "|" {
        i = i + 1
    }
    let vlen = toInt(substring(r, vlenStart, i))
    let elenStart = i + 1
    i = elenStart
    while i < len(r) && r[i] != "|" {
        i = i + 1
    }
    let elen = toInt(substring(r, elenStart, i))
    let dataStart = i + 1
    emit substring(r, dataStart + vlen, dataStart + vlen + elen)
}

func getResultPos(r) {
    // tag|pos|...
    let i = 2
    let posEnd = i
    while posEnd < len(r) && r[posEnd] != "|" {
        posEnd = posEnd + 1
    }
    emit toInt(substring(r, 2, posEnd))
}

func isTruthy(val) {
    if val == "0" || val == "" || val == "false" {
        emit 0
    }
    emit 1
}

func execBlock(tokens, pos, env, ftable) {
    // pos points to LBRACE
    let p = pos + 1
    let curEnv = env

    while tokAt(tokens, p) != "RBRACE" && p < lineCount(tokens) {
        let tok = tokAt(tokens, p)

        // skip semicolons
        if tok == "SEMI" {
            p = p + 1
        }
        else {
            let result = execStmt(tokens, p, curEnv, ftable)
            let tag = getResultTag(result)
            if tag == "R" || tag == "B" {
                // propagate return/break up
                emit result
            }
            curEnv = getResultEnv(result)
            p = getResultPos(result)
        }
    }

    // skip RBRACE
    emit makeResult("C", "", curEnv, p + 1)
}

func execStmt(tokens, pos, env, ftable) {
    let tok = tokAt(tokens, pos)

    if tok == "KW:let" {
        emit execLet(tokens, pos + 1, env, ftable)
    }

    if tok == "KW:emit" || tok == "KW:return" {
        emit execEmit(tokens, pos + 1, env, ftable)
    }

    if tok == "KW:if" {
        emit execIf(tokens, pos + 1, env, ftable)
    }

    if tok == "KW:while" {
        emit execWhile(tokens, pos + 1, env, ftable)
    }

    if tok == "KW:break" {
        let p = pos + 1
        if tokAt(tokens, p) == "SEMI" {
            p = p + 1
        }
        emit makeResult("B", "", env, p)
    }

    // assignment: ID ASSIGN expr
    if tokType(tok) == "ID" && tokAt(tokens, pos + 1) == "ASSIGN" {
        emit execAssign(tokens, pos, env, ftable)
    }

    // expression statement (function call etc)
    emit execExprStmt(tokens, pos, env, ftable)
}

func execLet(tokens, pos, env, ftable) {
    // pos is at the identifier after 'let'
    let name = tokVal(tokAt(tokens, pos))
    // skip name, ASSIGN
    let p = pos + 2
    let pair = evalExpr(tokens, p, env, ftable)
    let val = pairVal(pair)
    p = pairPos(pair)
    if tokAt(tokens, p) == "SEMI" {
        p = p + 1
    }
    let newEnv = envSet(env, name, val)
    emit makeResult("C", "", newEnv, p)
}

func execAssign(tokens, pos, env, ftable) {
    let name = tokVal(tokAt(tokens, pos))
    // skip name, ASSIGN
    let p = pos + 2
    let pair = evalExpr(tokens, p, env, ftable)
    let val = pairVal(pair)
    p = pairPos(pair)
    if tokAt(tokens, p) == "SEMI" {
        p = p + 1
    }
    let newEnv = envSet(env, name, val)
    emit makeResult("C", "", newEnv, p)
}

func execEmit(tokens, pos, env, ftable) {
    let pair = evalExpr(tokens, pos, env, ftable)
    let val = pairVal(pair)
    let p = pairPos(pair)
    if tokAt(tokens, p) == "SEMI" {
        p = p + 1
    }
    emit makeResult("R", val, env, p)
}

func execIf(tokens, pos, env, ftable) {
    // pos is right after 'if'
    let condPair = evalExpr(tokens, pos, env, ftable)
    let condVal = pairVal(condPair)
    let p = pairPos(condPair)

    if isTruthy(condVal) {
        // execute then block
        let result = execBlock(tokens, p, env, ftable)
        let tag = getResultTag(result)
        let renv = getResultEnv(result)
        let rpos = getResultPos(result)
        // check for else
        if tokAt(tokens, rpos) == "KW:else" {
            if tokAt(tokens, rpos + 1) == "KW:if" {
                // skip the else-if chain
                let skipPos = rpos + 2
                // skip condition
                let dummyPair = evalExpr(tokens, skipPos, env, ftable)
                skipPos = pairPos(dummyPair)
                // skip block
                skipPos = skipBlock(tokens, skipPos)
                // continue skipping else-if / else
                while tokAt(tokens, skipPos) == "KW:else" {
                    if tokAt(tokens, skipPos + 1) == "KW:if" {
                        skipPos = skipPos + 2
                        let dp2 = evalExpr(tokens, skipPos, env, ftable)
                        skipPos = pairPos(dp2)
                        skipPos = skipBlock(tokens, skipPos)
                    }
                    else {
                        skipPos = skipPos + 1
                        skipPos = skipBlock(tokens, skipPos)
                    }
                }
                if tag == "R" || tag == "B" {
                    emit makeResult(tag, getResultVal(result), renv, skipPos)
                }
                emit makeResult("C", "", renv, skipPos)
            }
            else {
                // plain else, skip it
                let skipPos = rpos + 1
                skipPos = skipBlock(tokens, skipPos)
                if tag == "R" || tag == "B" {
                    emit makeResult(tag, getResultVal(result), renv, skipPos)
                }
                emit makeResult("C", "", renv, skipPos)
            }
        }
        // no else
        if tag == "R" || tag == "B" {
            emit result
        }
        emit makeResult("C", "", renv, rpos)
    }
    else {
        // skip then block
        let skipPos = skipBlock(tokens, p)
        // check for else
        if tokAt(tokens, skipPos) == "KW:else" {
            if tokAt(tokens, skipPos + 1) == "KW:if" {
                // else if
                emit execIf(tokens, skipPos + 2, env, ftable)
            }
            else {
                // else block
                emit execBlock(tokens, skipPos + 1, env, ftable)
            }
        }
        emit makeResult("C", "", env, skipPos)
    }
}

func execWhile(tokens, pos, env, ftable) {
    let condStart = pos
    let curEnv = env

    while 1 {
        let condPair = evalExpr(tokens, condStart, curEnv, ftable)
        let condVal = pairVal(condPair)
        let bodyStart = pairPos(condPair)

        if !isTruthy(condVal) {
            // skip block
            let endPos = skipBlock(tokens, bodyStart)
            emit makeResult("C", "", curEnv, endPos)
        }

        let result = execBlock(tokens, bodyStart, curEnv, ftable)
        let tag = getResultTag(result)
        curEnv = getResultEnv(result)

        if tag == "R" {
            emit result
        }
        if tag == "B" {
            let endPos = skipBlock(tokens, bodyStart)
            emit makeResult("C", "", curEnv, endPos)
        }
    }

    emit makeResult("C", "", curEnv, condStart)
}

func execExprStmt(tokens, pos, env, ftable) {
    let pair = evalExpr(tokens, pos, env, ftable)
    let p = pairPos(pair)
    if tokAt(tokens, p) == "SEMI" {
        p = p + 1
    }
    emit makeResult("C", "", env, p)
}

// ── Entry Point ───────────────────────────────────────────

just run {
    let file = arg(0)
    let source = readFile(file)

    let tokens = tokenize(source)
    let ntoks = lineCount(tokens)

    let ftable = scanFunctions(tokens, ntoks)

    let entry = findEntry(tokens, ntoks)
    if entry < 0 {
        print("No entry point found")
        emit 1
    }

    // Set up initial env with arg offset so inner arg() calls skip our file arg
    let initEnv = envSet(envNew(), "__argOffset", "1")

    let result = execBlock(tokens, entry, initEnv, ftable)
    let tag = getResultTag(result)
    if tag == "R" {
        let val = getResultVal(result)
        if val != "" {
            emit toInt(val)
        }
    }
    emit 0
}
