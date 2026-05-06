// lsp/validate.k — Token-stream structural validator.
//
// Catches problems the tokenizer can't:
//   - unmatched braces/parens/brackets
//   - func declared without a name or without parens
//   - let declared without an identifier
//   - duplicate top-level function names (warning)
//
// Operates on the token rows produced by lex.k (TYPE\tLINE\tCOL\tVAL\n).
// Returns diagnostic rows in the same format as lex.k:
//   SEVERITY\tLINE\tCOL\tENDLINE\tENDCOL\tMESSAGE\n

module validate

func vRow(sev, line, col, endLine, endCol, msg) {
    emit sev + "\t" + line + "\t" + col + "\t" + endLine + "\t" + endCol + "\t" + msg + "\n"
}

// === bracket-balance pass ===
//
// Stack format: each entry is "TYPE,LINE,COL\n" — when we see a closer
// we pop and verify it matches; if not, error. At end any leftover
// opener is unterminated.

func vPushOpen(stack, kind, line, col) {
    emit stack + kind + "," + line + "," + col + "\n"
}

func vTopKind(stack) {
    let n = lineCount(stack)
    if n == 0 { emit "" }
    let row = getLine(stack, n - 1)
    let i = 0
    while i < len(row) {
        if row[i] == "," { emit substring(row, 0, i) }
        i += 1
    }
    emit ""
}

func vTopField(stack, fieldIdx) {
    let n = lineCount(stack)
    if n == 0 { emit "0" }
    let row = getLine(stack, n - 1)
    let cur = 0
    let start = 0
    let i = 0
    while i < len(row) {
        if row[i] == "," {
            if cur == fieldIdx { emit substring(row, start, i) }
            cur += 1
            start = i + 1
        }
        i += 1
    }
    if cur == fieldIdx { emit substring(row, start, len(row)) }
    emit "0"
}

func vTopLine(stack) { emit toInt(vTopField(stack, 1)) }
func vTopCol(stack)  { emit toInt(vTopField(stack, 2)) }

func vPop(stack) {
    let n = lineCount(stack)
    if n <= 1 { emit "" }
    let sb = sbNew()
    let i = 0
    while i < n - 1 {
        let row = getLine(stack, i)
        if len(row) > 0 { sb = sbAppend(sb, row + "\n") }
        i += 1
    }
    emit sbToString(sb)
}

func vMatchingOpen(closeKind) {
    if closeKind == "RBRACE" { emit "LBRACE" }
    if closeKind == "RPAREN" { emit "LPAREN" }
    if closeKind == "RBRACK" { emit "LBRACK" }
    emit ""
}

func vKindGlyph(kind) {
    if kind == "LBRACE" { emit "{" }
    if kind == "RBRACE" { emit "}" }
    if kind == "LPAREN" { emit "(" }
    if kind == "RPAREN" { emit ")" }
    if kind == "LBRACK" { emit "[" }
    if kind == "RBRACK" { emit "]" }
    emit kind
}

// === main validator entry ===
//
// Walk the token rows, push openers, pop on closers, check shape rules.
// Returns concatenated diagnostic rows (or "").

func validateTokens(toks) {
    let diags = sbNew()
    let stack = ""           // line-separated "kind,line,col"
    let nLines = lineCount(toks)
    let i = 0
    let lastFuncLine = -1
    let funcsSeen = ""       // pipe-delimited "|name|name|" for dup detection

    while i < nLines {
        let row = getLine(toks, i)
        if len(row) == 0 { i += 1  continue }

        let typ = lxType(row)
        let ln  = lxLine(row)
        let col = lxCol(row)
        let val = lxVal(row)

        // bracket balance
        if typ == "LBRACE" || typ == "LPAREN" || typ == "LBRACK" {
            stack = vPushOpen(stack, typ, ln, col)
        }
        if typ == "RBRACE" || typ == "RPAREN" || typ == "RBRACK" {
            let want = vMatchingOpen(typ)
            let top  = vTopKind(stack)
            if top == "" {
                diags = sbAppend(diags, vRow("1", ln, col, ln, col + 1,
                    "stray '" + vKindGlyph(typ) + "' with no matching opener"))
            } else if top != want {
                diags = sbAppend(diags, vRow("1", ln, col, ln, col + 1,
                    "mismatched '" + vKindGlyph(typ) + "' — expected '" +
                    vKindGlyph(vMatchingOpen(top) + "")
                    + "' to close '" + vKindGlyph(top) + "' at line " +
                    (vTopLine(stack) + 1)))
                stack = vPop(stack)
            } else {
                stack = vPop(stack)
            }
        }

        // func / fn declarations
        if typ == "KW" && (val == "func" || val == "fn") {
            // Next token must be ID (function name)
            let nxt = ""
            if i + 1 < nLines { nxt = getLine(toks, i + 1) }
            let nxtType = ""
            if len(nxt) > 0 { nxtType = lxType(nxt) }
            if nxtType != "ID" {
                diags = sbAppend(diags, vRow("1", ln, col, ln, col + len(val),
                    "'" + val + "' must be followed by a function name"))
            } else {
                let fname = lxVal(nxt)
                // Check duplicate at top-level (heuristic: only when stack is empty
                // before this `func` keyword — i.e. not nested in another scope).
                if stack == "" {
                    if contains(funcsSeen, "|" + fname + "|") {
                        let nLn = lxLine(nxt)
                        let nCol = lxCol(nxt)
                        diags = sbAppend(diags, vRow("2", nLn, nCol, nLn, nCol + len(fname),
                            "duplicate function name '" + fname + "'"))
                    } else {
                        funcsSeen = funcsSeen + "|" + fname + "|"
                    }
                }
                // Then we want LPAREN after the name
                let after = ""
                if i + 2 < nLines { after = getLine(toks, i + 2) }
                let afterType = ""
                if len(after) > 0 { afterType = lxType(after) }
                if afterType != "LPAREN" {
                    let nLn = lxLine(nxt)
                    let nCol = lxCol(nxt)
                    diags = sbAppend(diags, vRow("1", nLn, nCol, nLn, nCol + len(fname),
                        "function '" + fname + "' missing '(' for parameter list"))
                }
                lastFuncLine = ln
            }
        }

        // let declarations need an identifier
        if typ == "KW" && val == "let" {
            let nxt = ""
            if i + 1 < nLines { nxt = getLine(toks, i + 1) }
            let nxtType = ""
            if len(nxt) > 0 { nxtType = lxType(nxt) }
            if nxtType != "ID" {
                diags = sbAppend(diags, vRow("1", ln, col, ln, col + 3,
                    "'let' must be followed by a variable name"))
            }
        }

        i += 1
    }

    // Anything still on the stack is an unterminated opener.
    let leftover = lineCount(stack)
    let s = 0
    while s < leftover {
        let row = getLine(stack, s)
        if len(row) > 0 {
            let kind = ""
            let j = 0
            while j < len(row) {
                if row[j] == "," { kind = substring(row, 0, j)  break }
                j += 1
            }
            // Pull line/col directly from this stack row
            let parts2 = 0
            let cur = 0
            let start = 0
            let oLine = 0
            let oCol = 0
            let k = 0
            while k < len(row) {
                if row[k] == "," {
                    if cur == 1 { oLine = toInt(substring(row, start, k)) }
                    cur += 1
                    start = k + 1
                }
                k += 1
            }
            if cur == 2 { oCol = toInt(substring(row, start, len(row))) }
            diags = sbAppend(diags, vRow("1", oLine, oCol, oLine, oCol + 1,
                "unterminated '" + vKindGlyph(kind) + "' (no matching closer)"))
        }
        s += 1
    }

    emit sbToString(diags)
}
