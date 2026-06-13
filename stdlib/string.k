// stdlib/string.k -- Krypton string functions shaped to match the
// semantics the upcoming Python frontend will lower method-call syntax to.
//
// Names use the `*k` suffix convention so they don't shadow Krypton's
// own `replace` / `trim` / `startsWith` / etc. builtins and so user-side
// Krypton code never sees "Python" leaking through identifiers.  The FE
// rewrites at lowering time:
//
//   s.upper()                   -> upperk(s)
//   s.split(",")                -> splitk(s, ",")
//   s.replace("a", "b")         -> replacek(s, "a", "b")
//   s.strip()                   -> stripk(s)
//
// Most of these are thin wrappers over existing Krypton builtins; only
// the genuinely-new shapes (split-by-separator, capitalize, title,
// partition, classification predicates) carry real polyfill code.

module string


// ── Case ──────────────────────────────────────────────────────────────

func upperk(s) {
    emit toUpper(s)
}

func lowerk(s) {
    emit toLower(s)
}

func capitalizek(s) {
    if len(s) == 0 { emit "" }
    let first = toUpper(substring(s, 0, 1))
    let rest = toLower(substring(s, 1, len(s)))
    emit first + rest
}

func titlek(s) {
    let out = sbNew()
    let i = 0
    let upNext = "1"
    while i < len(s) {
        let c = s[i]
        if c == " " || c == "\t" || c == "\n" {
            out = sbAppend(out, c)
            upNext = "1"
        } else {
            if upNext == "1" {
                out = sbAppend(out, toUpper(c))
                upNext = "0"
            } else {
                out = sbAppend(out, toLower(c))
            }
        }
        i += 1
    }
    emit sbToString(out)
}

func swapcasek(s) {
    let out = sbNew()
    let i = 0
    while i < len(s) {
        let c = s[i]
        let code = charCode(c)
        if code >= 65 && code <= 90       { out = sbAppend(out, toLower(c)) }
        else if code >= 97 && code <= 122 { out = sbAppend(out, toUpper(c)) }
        else                              { out = sbAppend(out, c) }
        i += 1
    }
    emit sbToString(out)
}


// ── Trimming ──────────────────────────────────────────────────────────

// Match Python: strip whitespace (space, tab, newline, carriage return).
func stripk(s) {
    let lo = 0
    let hi = len(s)
    while lo < hi {
        let c = charCode(s[lo])
        if c == 32 || c == 9 || c == 10 || c == 13 { lo += 1 } else { break }
    }
    while hi > lo {
        let c = charCode(s[hi - 1])
        if c == 32 || c == 9 || c == 10 || c == 13 { hi -= 1 } else { break }
    }
    emit substring(s, lo, hi)
}

func lstripk(s) {
    let lo = 0
    let hi = len(s)
    while lo < hi {
        let c = charCode(s[lo])
        if c == 32 || c == 9 || c == 10 || c == 13 { lo += 1 } else { break }
    }
    emit substring(s, lo, hi)
}

func rstripk(s) {
    let lo = 0
    let hi = len(s)
    while hi > lo {
        let c = charCode(s[hi - 1])
        if c == 32 || c == 9 || c == 10 || c == 13 { hi -= 1 } else { break }
    }
    emit substring(s, lo, hi)
}


// ── Splitting / joining ───────────────────────────────────────────────

// splitk(s, sep) -- split a string by `sep` into a comma-list.
// Krypton's `split(list, i)` is the get-Nth-item builtin; this is the
// Python-shape splitter.  Empty `sep` is undefined behavior (Python
// raises; we return the original string as a one-element list).
func splitk(s, sep) {
    if sep == "" { emit s }
    let n = len(s)
    let m = len(sep)
    let out = sbNew()
    let first = "1"
    let i = 0
    let lo = 0
    while i + m <= n {
        if substring(s, i, i + m) == sep {
            if first == "0" { out = sbAppend(out, ",") }
            out = sbAppend(out, substring(s, lo, i))
            first = "0"
            i = i + m
            lo = i
        } else {
            i += 1
        }
    }
    if first == "0" { out = sbAppend(out, ",") }
    out = sbAppend(out, substring(s, lo, n))
    emit sbToString(out)
}

// rsplitk -- behaves like splitk for the no-maxsplit case (Python differs
// only when maxsplit is provided, which we don't accept yet).
func rsplitk(s, sep) {
    emit splitk(s, sep)
}

// splitlinesk -- split on \n and \r\n.  Result excludes the line endings.
func splitlinesk(s) {
    let out = sbNew()
    let first = "1"
    let n = len(s)
    let i = 0
    let lo = 0
    while i < n {
        let c = s[i]
        if c == "\n" {
            if first == "0" { out = sbAppend(out, ",") }
            let hi = i
            if i > 0 && s[i - 1] == "\r" { hi = i - 1 }
            out = sbAppend(out, substring(s, lo, hi))
            first = "0"
            lo = i + 1
        }
        i += 1
    }
    if lo < n {
        if first == "0" { out = sbAppend(out, ",") }
        out = sbAppend(out, substring(s, lo, n))
    }
    emit sbToString(out)
}

// partitionk(s, sep) -> "before,sep,after" -- empty sep returns
// "s,,".  If `sep` not found, returns "s,,".
func partitionk(s, sep) {
    let idx = indexOf(s, sep)
    if idx < 0 { emit s + ",," }
    let before = substring(s, 0, idx)
    let after = substring(s, idx + len(sep), len(s))
    emit before + "," + sep + "," + after
}

// rpartitionk(s, sep) -- same shape but searches from the right.
func rpartitionk(s, sep) {
    // No native rindexOf; walk backwards.
    let m = len(sep)
    let i = len(s) - m
    while i >= 0 {
        if substring(s, i, i + m) == sep {
            let before = substring(s, 0, i)
            let after = substring(s, i + m, len(s))
            emit before + "," + sep + "," + after
        }
        i -= 1
    }
    emit ",," + s
}

// joink(sep, items) -- Krypton-style arg order (sep first, list second).
// Python's `sep.join(items)` lowering is mechanical: receiver becomes
// the first arg.
func joink(sep, items) {
    let n = count(items)
    if n == 0 { emit "" }
    let out = sbNew()
    out = sbAppend(out, split(items, 0))
    let i = 1
    while i < n {
        out = sbAppend(out, sep)
        out = sbAppend(out, split(items, i))
        i += 1
    }
    emit sbToString(out)
}


// ── Search ────────────────────────────────────────────────────────────

func findk(s, sub) {
    emit indexOf(s, sub)
}

func rfindk(s, sub) {
    let m = len(sub)
    let i = len(s) - m
    while i >= 0 {
        if substring(s, i, i + m) == sub { emit i }
        i -= 1
    }
    emit -1
}

func startswithk(s, prefix) {
    emit startsWith(s, prefix)
}

func endswithk(s, suffix) {
    emit endsWith(s, suffix)
}

func containsk(s, sub) {
    if indexOf(s, sub) >= 0 { emit "1" }
    emit "0"
}

// countk(s, sub) -- number of non-overlapping occurrences.
func countk(s, sub) {
    if sub == "" { emit 0 }
    let n = len(s)
    let m = len(sub)
    let i = 0
    let c = 0
    while i + m <= n {
        if substring(s, i, i + m) == sub {
            c += 1
            i = i + m
        } else {
            i += 1
        }
    }
    emit c
}


// ── Modification ──────────────────────────────────────────────────────

func replacek(s, old, new) {
    emit replace(s, old, new)
}

func removeprefixk(s, prefix) {
    if startsWith(s, prefix) { emit substring(s, len(prefix), len(s)) }
    emit s
}

func removesuffixk(s, suffix) {
    if endsWith(s, suffix) { emit substring(s, 0, len(s) - len(suffix)) }
    emit s
}


// ── Padding ───────────────────────────────────────────────────────────

func ljustk(s, width) {
    emit padRight(s, width, " ")
}

func rjustk(s, width) {
    emit padLeft(s, width, " ")
}

// centerk(s, width) -- pad with spaces equally on both sides.
func centerk(s, width) {
    let w = toInt(width)
    let n = len(s)
    if n >= w { emit s }
    let total = w - n
    let leftPad = total / 2
    let rightPad = total - leftPad
    let out = sbNew()
    let i = 0
    while i < leftPad { out = sbAppend(out, " ")  i += 1 }
    out = sbAppend(out, s)
    i = 0
    while i < rightPad { out = sbAppend(out, " ")  i += 1 }
    emit sbToString(out)
}

// zfillk(s, width) -- left-pad with "0" up to width; preserves a
// leading "+"/"-" sign as the leftmost char.
func zfillk(s, width) {
    let w = toInt(width)
    let n = len(s)
    if n >= w { emit s }
    let pad = w - n
    let sign = ""
    let body = s
    if n > 0 && (s[0] == "+" || s[0] == "-") {
        sign = s[0]
        body = substring(s, 1, n)
    }
    let out = sbNew()
    out = sbAppend(out, sign)
    let i = 0
    while i < pad { out = sbAppend(out, "0")  i += 1 }
    out = sbAppend(out, body)
    emit sbToString(out)
}


// ── Classification predicates ─────────────────────────────────────────
// Each returns "1" / "0" (int family).  Empty string returns "0" for
// every classifier (matches Python).

func isalphak(s) {
    if len(s) == 0 { emit 0 }
    let i = 0
    while i < len(s) {
        let c = charCode(s[i])
        if !((c >= 65 && c <= 90) || (c >= 97 && c <= 122)) { emit 0 }
        i += 1
    }
    emit 1
}

func isdigitk(s) {
    if len(s) == 0 { emit 0 }
    let i = 0
    while i < len(s) {
        if !isDigit(s[i]) { emit 0 }
        i += 1
    }
    emit 1
}

func isalnumk(s) {
    if len(s) == 0 { emit 0 }
    let i = 0
    while i < len(s) {
        let c = charCode(s[i])
        if !((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57)) { emit 0 }
        i += 1
    }
    emit 1
}

func isspacek(s) {
    if len(s) == 0 { emit 0 }
    let i = 0
    while i < len(s) {
        let c = charCode(s[i])
        if !(c == 32 || c == 9 || c == 10 || c == 13 || c == 11 || c == 12) { emit 0 }
        i += 1
    }
    emit 1
}

func isupperk(s) {
    if len(s) == 0 { emit 0 }
    let saw = "0"
    let i = 0
    while i < len(s) {
        let c = charCode(s[i])
        if c >= 97 && c <= 122 { emit 0 }
        if c >= 65 && c <= 90  { saw = "1" }
        i += 1
    }
    emit saw
}

func islowerk(s) {
    if len(s) == 0 { emit 0 }
    let saw = "0"
    let i = 0
    while i < len(s) {
        let c = charCode(s[i])
        if c >= 65 && c <= 90  { emit 0 }
        if c >= 97 && c <= 122 { saw = "1" }
        i += 1
    }
    emit saw
}

func isasciik(s) {
    let i = 0
    while i < len(s) {
        if charCode(s[i]) > 127 { emit 0 }
        i += 1
    }
    emit 1
}


// ── Misc ──────────────────────────────────────────────────────────────

// expandtabsk(s, tabsize) -- replace \t with enough spaces to reach
// next multiple of `tabsize`.  Default Python tabsize is 8.
func expandtabsk(s, tabsize) {
    let ts = toInt(tabsize)
    if ts <= 0 { ts = 8 }
    let out = sbNew()
    let col = 0
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == "\t" {
            let pad = ts - (col % ts)
            let j = 0
            while j < pad { out = sbAppend(out, " ")  j += 1 }
            col = col + pad
        } else if c == "\n" {
            out = sbAppend(out, c)
            col = 0
        } else {
            out = sbAppend(out, c)
            col += 1
        }
        i += 1
    }
    emit sbToString(out)
}

// Coverage notes
// --------------
// Shipped (37 funcs):
//   upperk lowerk capitalizek titlek swapcasek
//   stripk lstripk rstripk
//   splitk rsplitk splitlinesk partitionk rpartitionk joink
//   findk rfindk startswithk endswithk containsk countk
//   replacek removeprefixk removesuffixk
//   ljustk rjustk centerk zfillk
//   isalphak isdigitk isalnumk isspacek isupperk islowerk isasciik
//   expandtabsk
//
// Blocked on roadmap:
//   formatk / format_mapk  -- variadic + dict (A4)
//   encodek / decodek      -- needs bytes type (TBD)
//   maketransk / translatek -- character-table polyfill, not blocked
//                              but deferred until any caller needs it
//   istitlek              -- predicate, easy add; deferred for symmetry
//                              with the open isspacek-variants
//   casefoldk             -- Unicode-aware lower; needs Unicode tables
