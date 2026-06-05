// String utility functions for Krypton
// Provides string operations that *aren't* covered by built-in functions.
//
// Builtins to use directly (don't reimplement; they shadow user funcs of
// the same name in the IR dispatch and would silently win):
//   repeat(s, n)       endsWith(s, suf)   reverse(s)
//   contains(s, sub)   trim(s)            replace(s, old, new)
//   toUpper(s)         toLower(s)         indexOf(s, sub)
//   substring(s, lo, hi)                  startsWith(s, pfx)

module string_utils


// Pad a string on the left to reach target length.
// Native builtin equivalent: none.
func padLeft(s, targetLen, padChar) {
    let result = s
    while len(result) < targetLen {
        let sb = sbNew()
        sb = sbAppend(sb, padChar)
        sb = sbAppend(sb, result)
        result = sbToString(sb)
    }
    emit result
}

// Pad a string on the right to reach target length.
func padRight(s, targetLen, padChar) {
    let result = s
    while len(result) < targetLen {
        let sb = sbNew()
        sb = sbAppend(sb, result)
        sb = sbAppend(sb, padChar)
        result = sbToString(sb)
    }
    emit result
}

// Trim leading whitespace only.
// Native builtin trim(s) does both ends; use this when you need just one.
func trimLeft(s) {
    let i = 0
    while i < len(s) {
        let ch = s[i]
        if ch != " " {
            if ch != "\t" {
                if ch != "\n" {
                    if ch != "\r" {
                        emit substring(s, i, len(s))
                    }
                }
            }
        }
        i += 1
    }
    emit ""
}

// Trim trailing whitespace only.
func trimRight(s) {
    let i = len(s) - 1
    while i >= 0 {
        let ch = s[i]
        if ch != " " {
            if ch != "\t" {
                if ch != "\n" {
                    if ch != "\r" {
                        emit substring(s, 0, i + 1)
                    }
                }
            }
        }
        i -= 1
    }
    emit ""
}

// Count occurrences of a substring in a string.
// Native builtin equivalent: none.
func countOccurrences(s, sub) {
    let cnt = 0
    let sLen = len(s)
    let subLen = len(sub)
    if subLen == 0 { emit 0 }
    let i = 0
    while i <= sLen - subLen {
        if substring(s, i, i + subLen) == sub {
            cnt += 1
            i = i + subLen
        } else {
            i += 1
        }
    }
    emit cnt
}

// Join a comma-separated list with a delimiter.
// Native builtin equivalent: none.
func join(list, delim) {
    let sb = sbNew()
    let total = count(list)
    let i = 0
    while i < total {
        if i > 0 { sb = sbAppend(sb, delim) }
        sb = sbAppend(sb, split(list, i))
        i += 1
    }
    emit sbToString(sb)
}

// ── Case conversion ──────────────────────────────────────────────────

// Capitalize the first character only ("hello world" → "Hello world").
func capitalize(s) {
    if len(s) == 0 { emit "" }
    let sb = sbNew()
    sb = sbAppend(sb, toUpper(substring(s, 0, 1)))
    if len(s) > 1 { sb = sbAppend(sb, substring(s, 1, len(s))) }
    emit sbToString(sb)
}

// Title-case every word (split on whitespace + "-" + "_").
//   "hello world"   → "Hello World"
//   "the-quick_fox" → "The-Quick_Fox"
func titleCase(s) {
    let out = sbNew()
    let i = 0
    let atStart = 1
    while i < len(s) {
        let c = s[i]
        if c == " " || c == "\t" || c == "\n" || c == "-" || c == "_" {
            out = sbAppend(out, c)
            atStart = 1
        } else {
            if atStart == 1 { out = sbAppend(out, toUpper(c)) }
            else            { out = sbAppend(out, toLower(c)) }
            atStart = 0
        }
        i = i + 1
    }
    emit sbToString(out)
}

// Swap upper ↔ lower for every letter.
func swapCase(s) {
    let out = sbNew()
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c >= "a" && c <= "z" { out = sbAppend(out, toUpper(c)) }
        else if c >= "A" && c <= "Z" { out = sbAppend(out, toLower(c)) }
        else { out = sbAppend(out, c) }
        i = i + 1
    }
    emit sbToString(out)
}

// camelCase / snake_case / kebab-case converters. Input may be any of the
// three; we normalise to space-separated words then re-stitch.
func _su_words(s) {
    // Yields words separated by "\x01" (chosen because Krypton never
    // produces \x01 from user text). Splits on whitespace, hyphen,
    // underscore, AND camel-hump (lower→upper boundary).
    let out = sbNew()
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == " " || c == "\t" || c == "-" || c == "_" {
            out = sbAppend(out, fromCharCode(1))
        } else if c >= "A" && c <= "Z" && i > 0 {
            let p = s[i - 1]
            if p >= "a" && p <= "z" { out = sbAppend(out, fromCharCode(1)) }
            out = sbAppend(out, c)
        } else {
            out = sbAppend(out, c)
        }
        i = i + 1
    }
    emit sbToString(out)
}

func camelCase(s) {
    let words = _su_words(s)
    let out = sbNew()
    let i = 0
    let first = 1
    let atStart = 1
    while i < len(words) {
        let c = words[i]
        if c == fromCharCode(1) { atStart = 1 }
        else {
            if atStart == 1 {
                if first == 1 { out = sbAppend(out, toLower(c))  first = 0 }
                else          { out = sbAppend(out, toUpper(c)) }
                atStart = 0
            } else {
                out = sbAppend(out, toLower(c))
            }
        }
        i = i + 1
    }
    emit sbToString(out)
}

func snakeCase(s) {
    let words = _su_words(s)
    let out = sbNew()
    let i = 0
    let atStart = 1
    let any = 0
    while i < len(words) {
        let c = words[i]
        if c == fromCharCode(1) { atStart = 1 }
        else {
            if atStart == 1 && any == 1 { out = sbAppend(out, "_") }
            out = sbAppend(out, toLower(c))
            atStart = 0
            any = 1
        }
        i = i + 1
    }
    emit sbToString(out)
}

func kebabCase(s) {
    emit replace(snakeCase(s), "_", "-")
}

// ── Escapes ──────────────────────────────────────────────────────────

// HTML-escape: & < > " '
func escapeHtml(s) {
    let out = sbNew()
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == "&"      { out = sbAppend(out, "&amp;") }
        else if c == "<" { out = sbAppend(out, "&lt;") }
        else if c == ">" { out = sbAppend(out, "&gt;") }
        else if c == "\"" { out = sbAppend(out, "&quot;") }
        else if c == "'" { out = sbAppend(out, "&#39;") }
        else { out = sbAppend(out, c) }
        i = i + 1
    }
    emit sbToString(out)
}

// JSON-string-escape: backslash, quote, control chars. Returns the
// inner string content (no surrounding quotes).
//
// Implementation note: Krypton's lexer collapses `"\\n"` to an actual
// newline byte, not a backslash-then-n. So we build escape sequences
// out of `fromCharCode(92)` (the explicit backslash byte) joined with
// plain ASCII suffixes. Same for `\"`.
func escapeJson(s) {
    let BS = fromCharCode(92)   // literal '\'
    let DQ = fromCharCode(34)   // literal '"'
    let out = sbNew()
    let i = 0
    while i < len(s) {
        let c = s[i]
        let cc = charCode(c)
        if c == BS       { out = sbAppend(out, BS)  out = sbAppend(out, BS) }
        else if c == DQ  { out = sbAppend(out, BS)  out = sbAppend(out, DQ) }
        else if cc == 8  { out = sbAppend(out, BS)  out = sbAppend(out, "b") }
        else if cc == 9  { out = sbAppend(out, BS)  out = sbAppend(out, "t") }
        else if cc == 10 { out = sbAppend(out, BS)  out = sbAppend(out, "n") }
        else if cc == 12 { out = sbAppend(out, BS)  out = sbAppend(out, "f") }
        else if cc == 13 { out = sbAppend(out, BS)  out = sbAppend(out, "r") }
        else if cc < 32 {
            out = sbAppend(out, BS)
            out = sbAppend(out, "u00")
            let hi = cc / 16
            let lo = cc % 16
            let hex = "0123456789abcdef"
            out = sbAppend(out, substring(hex, hi, hi + 1))
            out = sbAppend(out, substring(hex, lo, lo + 1))
        } else {
            out = sbAppend(out, c)
        }
        i = i + 1
    }
    emit sbToString(out)
}

// Quote + escape for Windows cmd.exe argument passing. Wraps in
// double-quotes and escapes embedded `"` per CommandLineToArgv rules.
func escapeShellWin(s) {
    let BS = fromCharCode(92)
    let DQ = fromCharCode(34)
    let out = sbNew()
    out = sbAppend(out, DQ)
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == DQ { out = sbAppend(out, BS)  out = sbAppend(out, DQ) }
        else       { out = sbAppend(out, c) }
        i = i + 1
    }
    out = sbAppend(out, DQ)
    emit sbToString(out)
}

// ── Layout helpers ───────────────────────────────────────────────────

// Truncate to width, appending ellipsis if cut. If width <= len(ellip)
// returns the first `width` chars of `ellip`.
func truncate(s, width, ellip) {
    if len(s) <= width { emit s }
    if width <= len(ellip) { emit substring(ellip, 0, width) }
    let out = sbNew()
    out = sbAppend(out, substring(s, 0, width - len(ellip)))
    out = sbAppend(out, ellip)
    emit sbToString(out)
}

// Indent every line by `n` copies of `pad`. Lines are split on "\n".
func indent(s, n, pad) {
    let prefix = sbNew()
    let k = 0
    while k < n { prefix = sbAppend(prefix, pad)  k = k + 1 }
    let pfx = sbToString(prefix)
    let out = sbNew()
    let i = 0
    let lineStart = 1
    while i < len(s) {
        if lineStart == 1 { out = sbAppend(out, pfx)  lineStart = 0 }
        let c = s[i]
        out = sbAppend(out, c)
        if c == "\n" { lineStart = 1 }
        i = i + 1
    }
    emit sbToString(out)
}

// Remove a common leading-whitespace prefix from every line ("textwrap.dedent").
func dedent(s) {
    // First pass: find smallest leading-space count across non-blank lines.
    let i = 0
    let minLead = -1
    let lineStart = 1
    let lead = 0
    let blank = 1
    while i <= len(s) {
        if i == len(s) || s[i] == "\n" {
            if blank == 0 {
                if minLead < 0 || lead < minLead { minLead = lead }
            }
            lineStart = 1
            lead = 0
            blank = 1
        } else {
            if lineStart == 1 {
                if s[i] == " " || s[i] == "\t" { lead = lead + 1 }
                else { lineStart = 0  blank = 0 }
            } else {
                if s[i] != " " && s[i] != "\t" { blank = 0 }
            }
        }
        i = i + 1
    }
    if minLead <= 0 { emit s }
    // Second pass: strip that many leading chars from each line.
    let out = sbNew()
    let j = 0
    let trim2 = 0
    let inHead = 1
    while j < len(s) {
        let c = s[j]
        if inHead == 1 && trim2 < minLead && (c == " " || c == "\t") {
            trim2 = trim2 + 1
        } else {
            out = sbAppend(out, c)
            inHead = 0
        }
        if c == "\n" { inHead = 1  trim2 = 0 }
        j = j + 1
    }
    emit sbToString(out)
}

// Repeat a string n times.
//   strRepeat("ab", 3) → "ababab"
// Krypton has a `repeat` builtin already; this is a friendly alias.
func strRepeat(s, n) {
    emit repeat(s, n)
}

// ── String distance / similarity ─────────────────────────────────────

// Length of the longest common prefix of two strings.
func longestCommonPrefix(a, b) {
    let n = len(a)
    if len(b) < n { n = len(b) }
    let i = 0
    while i < n {
        if a[i] != b[i] { emit i }
        i = i + 1
    }
    emit n
}

// Length of the longest common suffix.
func longestCommonSuffix(a, b) {
    let la = len(a)
    let lb = len(b)
    let n = la
    if lb < n { n = lb }
    let i = 0
    while i < n {
        if a[la - 1 - i] != b[lb - 1 - i] { emit i }
        i = i + 1
    }
    emit n
}

// Levenshtein edit distance (insert / delete / substitute, cost 1 each).
// O(len(a) * len(b)) time + O(len(b)) space. Buffer-backed.
func levenshtein(a, b) {
    let la = len(a)
    let lb = len(b)
    if la == 0 { emit lb }
    if lb == 0 { emit la }
    // prev[j] = distance using first j chars of b
    let prev = bufNew((lb + 1) * 4)
    let cur  = bufNew((lb + 1) * 4)
    let j = 0
    while j <= lb {
        bufSetDwordAt(prev, j * 4, j + "")
        j = j + 1
    }
    let i = 1
    while i <= la {
        bufSetDwordAt(cur, 0, i + "")
        let jj = 1
        while jj <= lb {
            let cost = 1
            if a[i - 1] == b[jj - 1] { cost = 0 }
            let delV = toInt(bufGetDwordAt(prev, jj * 4)) + 1
            let insV = toInt(bufGetDwordAt(cur, (jj - 1) * 4)) + 1
            let subV = toInt(bufGetDwordAt(prev, (jj - 1) * 4)) + cost
            let best = delV
            if insV < best { best = insV }
            if subV < best { best = subV }
            bufSetDwordAt(cur, jj * 4, best + "")
            jj = jj + 1
        }
        // swap prev <-> cur (copy cur into prev for next iteration)
        let k = 0
        while k <= lb {
            bufSetDwordAt(prev, k * 4, bufGetDwordAt(cur, k * 4))
            k = k + 1
        }
        i = i + 1
    }
    emit toInt(bufGetDwordAt(prev, lb * 4)) + ""
}
