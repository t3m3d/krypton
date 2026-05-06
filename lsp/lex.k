// lsp/lex.k — Position-aware tokenizer for Krypton LSP
//
// Decoupled from compiler/compile.k. Tokens carry line/col so the LSP
// can map every token back to a source range for hover, definition,
// completion, and diagnostics.
//
// Token format (one per line, TAB-separated):
//     TYPE\tLINE\tCOL\tVAL\n
//
// LINE and COL are 0-based (LSP convention). VAL extends to end of
// the line; string literals do not contain literal newlines because
// escapes are preserved as the original \n bytes.
//
// Diagnostic format (one per line, TAB-separated):
//     SEVERITY\tLINE\tCOL\tENDLINE\tENDCOL\tMESSAGE\n
//
// SEVERITY: 1=error, 2=warning, 3=info, 4=hint.

module lex

// Krypton string escapes don't include \xNN. Build the separator
// between the tokens block and the diagnostics block at runtime.
func lxSep() { emit fromCharCode(1) }

func lxIsDigit(c) {
    emit c >= "0" && c <= "9"
}

func lxIsAlpha(c) {
    emit (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_"
}

func lxIsAlphaNum(c) {
    emit lxIsAlpha(c) || lxIsDigit(c)
}

func lxIsHex(c) {
    emit lxIsDigit(c) || (c >= "a" && c <= "f") || (c >= "A" && c <= "F")
}

func lxIsKW(w) {
    if w == "func" { emit 1 }
    if w == "fn" { emit 1 }
    if w == "let" { emit 1 }
    if w == "const" { emit 1 }
    if w == "if" { emit 1 }
    if w == "else" { emit 1 }
    if w == "while" { emit 1 }
    if w == "for" { emit 1 }
    if w == "in" { emit 1 }
    if w == "do" { emit 1 }
    if w == "loop" { emit 1 }
    if w == "until" { emit 1 }
    if w == "break" { emit 1 }
    if w == "continue" { emit 1 }
    if w == "match" { emit 1 }
    if w == "emit" { emit 1 }
    if w == "return" { emit 1 }
    if w == "try" { emit 1 }
    if w == "catch" { emit 1 }
    if w == "throw" { emit 1 }
    if w == "module" { emit 1 }
    if w == "import" { emit 1 }
    if w == "export" { emit 1 }
    if w == "struct" { emit 1 }
    if w == "class" { emit 1 }
    if w == "type" { emit 1 }
    if w == "callback" { emit 1 }
    if w == "jxt" { emit 1 }
    if w == "just" { emit 1 }
    if w == "go" { emit 1 }
    if w == "true" { emit 1 }
    if w == "false" { emit 1 }
    if w == "null" { emit 1 }
    if w == "quantum" { emit 1 }
    if w == "qpute" { emit 1 }
    if w == "process" { emit 1 }
    if w == "measure" { emit 1 }
    if w == "prepare" { emit 1 }
    emit 0
}

// === Token row builder ===
// Returns "TYPE\tLINE\tCOL\tVAL\n"
func lxRow(typ, line, col, val) {
    emit typ + "\t" + line + "\t" + col + "\t" + val + "\n"
}

// === Diagnostic row builder ===
func dxRow(sev, line, col, endLine, endCol, msg) {
    emit sev + "\t" + line + "\t" + col + "\t" + endLine + "\t" + endCol + "\t" + msg + "\n"
}

// === Main tokenizer ===
// Returns "tokens\x01diagnostics" — split on \x01 to separate.
func lspTokenize(text) {
    let toks = sbNew()
    let diags = sbNew()
    let i = 0
    let line = 0
    let col = 0
    let n = len(text)

    while i < n {
        let c = text[i]

        // whitespace / newline tracking
        if c == "\n" { line += 1  col = 0  i += 1  continue }
        if c == "\r" { i += 1  continue }
        if c == " " || c == "\t" { col += 1  i += 1  continue }

        // line comment
        if c == "/" && i + 1 < n && text[i + 1] == "/" {
            while i < n && text[i] != "\n" { i += 1  col += 1 }
            continue
        }

        // block comment
        if c == "/" && i + 1 < n && text[i + 1] == "*" {
            let startLine = line
            let startCol = col
            i += 2  col += 2
            let closed = 0
            while i + 1 < n {
                if text[i] == "*" && text[i + 1] == "/" {
                    i += 2  col += 2
                    closed = 1
                    break
                }
                if text[i] == "\n" { line += 1  col = 0 } else { col += 1 }
                i += 1
            }
            if closed == 0 {
                diags = sbAppend(diags, dxRow("1", startLine, startCol, line, col, "unterminated block comment"))
                break
            }
            continue
        }

        // numbers
        if lxIsDigit(c) {
            let startCol = col
            let startI = i
            // hex
            if c == "0" && i + 1 < n && (text[i + 1] == "x" || text[i + 1] == "X") {
                i += 2  col += 2
                let hexStart = i
                while i < n && lxIsHex(text[i]) { i += 1  col += 1 }
                if i == hexStart {
                    diags = sbAppend(diags, dxRow("1", line, startCol, line, col, "hex literal needs digits"))
                }
                toks = sbAppend(toks, lxRow("INT", line, startCol, substring(text, startI, i)))
                continue
            }
            while i < n && lxIsDigit(text[i]) { i += 1  col += 1 }
            // float fragment
            if i < n && text[i] == "." && i + 1 < n && lxIsDigit(text[i + 1]) {
                i += 1  col += 1
                while i < n && lxIsDigit(text[i]) { i += 1  col += 1 }
                toks = sbAppend(toks, lxRow("FLT", line, startCol, substring(text, startI, i)))
                continue
            }
            toks = sbAppend(toks, lxRow("INT", line, startCol, substring(text, startI, i)))
            continue
        }

        // strings
        if c == "\"" {
            let startLine = line
            let startCol = col
            i += 1  col += 1
            let sb = sbNew()
            let closed = 0
            while i < n {
                let sc = text[i]
                if sc == "\\" && i + 1 < n {
                    sb = sbAppend(sb, sc)
                    sb = sbAppend(sb, text[i + 1])
                    i += 2  col += 2
                    continue
                }
                if sc == "\"" { i += 1  col += 1  closed = 1  break }
                if sc == "\n" {
                    diags = sbAppend(diags, dxRow("1", startLine, startCol, line, col, "unterminated string literal"))
                    closed = 1
                    break
                }
                sb = sbAppend(sb, sc)
                i += 1  col += 1
            }
            if closed == 0 {
                diags = sbAppend(diags, dxRow("1", startLine, startCol, line, col, "unterminated string literal"))
            }
            toks = sbAppend(toks, lxRow("STR", startLine, startCol, sbToString(sb)))
            continue
        }

        // backtick interpolated strings
        if c == "`" {
            let startLine = line
            let startCol = col
            i += 1  col += 1
            let sb = sbNew()
            let closed = 0
            while i < n {
                let sc = text[i]
                if sc == "`" { i += 1  col += 1  closed = 1  break }
                if sc == "\n" { line += 1  col = 0 } else { col += 1 }
                sb = sbAppend(sb, sc)
                i += 1
            }
            if closed == 0 {
                diags = sbAppend(diags, dxRow("1", startLine, startCol, line, col, "unterminated backtick string"))
            }
            toks = sbAppend(toks, lxRow("ISTR", startLine, startCol, sbToString(sb)))
            continue
        }

        // identifiers / keywords
        if lxIsAlpha(c) {
            let startCol = col
            let startI = i
            while i < n && lxIsAlphaNum(text[i]) { i += 1  col += 1 }
            let word = substring(text, startI, i)
            if lxIsKW(word) == 1 {
                toks = sbAppend(toks, lxRow("KW", line, startCol, word))
            } else {
                toks = sbAppend(toks, lxRow("ID", line, startCol, word))
            }
            continue
        }

        // multi-char operators
        if i + 1 < n {
            let two = substring(text, i, i + 2)
            if two == "==" || two == "!=" || two == "<=" || two == ">=" ||
               two == "&&" || two == "||" || two == "+=" || two == "-=" ||
               two == "*=" || two == "/=" || two == "%=" || two == "++" ||
               two == "--" || two == "->" {
                toks = sbAppend(toks, lxRow("OP", line, col, two))
                i += 2  col += 2
                continue
            }
        }

        // single-char punct/op
        let ch = c
        let kind = "OP"
        if ch == "{" { kind = "LBRACE" }
        if ch == "}" { kind = "RBRACE" }
        if ch == "(" { kind = "LPAREN" }
        if ch == ")" { kind = "RPAREN" }
        if ch == "[" { kind = "LBRACK" }
        if ch == "]" { kind = "RBRACK" }
        if ch == "," { kind = "COMMA" }
        if ch == ";" { kind = "SEMI" }
        if ch == ":" { kind = "COLON" }
        if ch == "." { kind = "DOT" }
        toks = sbAppend(toks, lxRow(kind, line, col, ch))
        i += 1  col += 1
    }

    emit sbToString(toks) + lxSep() + sbToString(diags)
}

// === Token field accessors (operate on a single TAB-delimited line) ===
//
// Manual walk — avoids splitBy because token VALUE may contain commas
// (string literals) and Krypton lists use comma as separator.

func lxField(row, idx) {
    let n = len(row)
    let i = 0
    let cur = 0
    let start = 0
    while i < n {
        if row[i] == "\t" {
            if cur == idx { emit substring(row, start, i) }
            cur += 1
            start = i + 1
        }
        i += 1
    }
    if cur == idx { emit substring(row, start, n) }
    emit ""
}

func lxType(row) { emit lxField(row, 0) }
func lxLine(row) { emit toInt(lxField(row, 1)) }
func lxCol(row)  { emit toInt(lxField(row, 2)) }
func lxVal(row)  { emit lxField(row, 3) }
