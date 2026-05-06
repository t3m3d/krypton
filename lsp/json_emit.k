// lsp/json_emit.k — Compose JSON for LSP responses.
//
// stdlib/json.k is too flat for nested LSP shapes (its jsonObject only
// handles string→string maps). This builder emits *fragments* you can
// nest freely:
//
//     let pos     = jeObj("line", jeNum(0), "character", jeNum(0))
//     let range   = jeObj("start", pos, "end", pos)
//     let diag    = jeObj("range", range, "severity", jeNum(1),
//                         "message", jeStr("oops"))
//     let result  = jeObj("uri", jeStr(uri), "diagnostics", jeArr1(diag))
//
// All builders return ready-to-paste JSON text. They do NOT add
// surrounding whitespace.

module json_emit

func jeStr(s) {
    let sb = sbNew()
    sb = sbAppend(sb, "\"")
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == "\\" { sb = sbAppend(sb, "\\\\") }
        else if c == "\"" { sb = sbAppend(sb, "\\\"") }
        else if c == "\n" { sb = sbAppend(sb, "\\n") }
        else if c == "\r" { sb = sbAppend(sb, "\\r") }
        else if c == "\t" { sb = sbAppend(sb, "\\t") }
        else if c == "\b" { sb = sbAppend(sb, "\\b") }
        else if c == "\f" { sb = sbAppend(sb, "\\f") }
        else if charCode(c) < 32 {
            // Control char — emit \u00XX.
            let v = charCode(c)
            sb = sbAppend(sb, "\\u00")
            sb = sbAppend(sb, hex(v / 16))
            sb = sbAppend(sb, hex(v % 16))
        }
        else { sb = sbAppend(sb, c) }
        i += 1
    }
    sb = sbAppend(sb, "\"")
    emit sbToString(sb)
}

func jeNum(n) { emit n + "" }
func jeBool(b) { if b == 0 { emit "false" }  emit "true" }
func jeNull() { emit "null" }
func jeRaw(s) { emit s }

// === Object builders ===
// Keys are bare identifiers; values are pre-encoded fragments.
func jeObj0() { emit "{}" }

func jeObj(k1, v1) {
    emit "{" + jeStr(k1) + ":" + v1 + "}"
}

func jeObj2(k1, v1, k2, v2) {
    emit "{" + jeStr(k1) + ":" + v1 + "," + jeStr(k2) + ":" + v2 + "}"
}

func jeObj3(k1, v1, k2, v2, k3, v3) {
    emit "{" + jeStr(k1) + ":" + v1 + "," + jeStr(k2) + ":" + v2 + "," + jeStr(k3) + ":" + v3 + "}"
}

func jeObj4(k1, v1, k2, v2, k3, v3, k4, v4) {
    let sb = sbNew()
    sb = sbAppend(sb, "{")
    sb = sbAppend(sb, jeStr(k1) + ":" + v1 + ",")
    sb = sbAppend(sb, jeStr(k2) + ":" + v2 + ",")
    sb = sbAppend(sb, jeStr(k3) + ":" + v3 + ",")
    sb = sbAppend(sb, jeStr(k4) + ":" + v4)
    sb = sbAppend(sb, "}")
    emit sbToString(sb)
}

// === Array builders ===
func jeArr0() { emit "[]" }
func jeArr1(a) { emit "[" + a + "]" }
func jeArr2(a, b) { emit "[" + a + "," + b + "]" }

// Build an array from a TAB-separated list of pre-encoded fragments.
// Empty input → "[]". Uses a manual walk because each fragment is JSON
// that may contain commas — splitBy would produce a comma-joined list
// that re-splits ambiguously.
func jeArrFrom(tabList) {
    if tabList == "" { emit "[]" }
    let sb = sbNew()
    sb = sbAppend(sb, "[")
    let n = len(tabList)
    let i = 0
    let start = 0
    let first = 1
    while i < n {
        if tabList[i] == "\t" {
            if first == 0 { sb = sbAppend(sb, ",") }
            sb = sbAppend(sb, substring(tabList, start, i))
            first = 0
            start = i + 1
        }
        i += 1
    }
    if first == 0 { sb = sbAppend(sb, ",") }
    sb = sbAppend(sb, substring(tabList, start, n))
    sb = sbAppend(sb, "]")
    emit sbToString(sb)
}

// === LSP convenience: Position and Range ===
func jePos(line, col) {
    emit jeObj2("line", jeNum(line), "character", jeNum(col))
}

func jeRange(sl, sc, el, ec) {
    emit jeObj2("start", jePos(sl, sc), "end", jePos(el, ec))
}

// === LSP convenience: Diagnostic ===
func jeDiagnostic(sl, sc, el, ec, severity, message) {
    emit jeObj3("range", jeRange(sl, sc, el, ec),
                "severity", jeNum(severity),
                "message", jeStr(message))
}
