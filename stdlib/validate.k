// Input validation utilities for Krypton
// Functions to validate strings and values

module validate


// Check if string is a valid integer
func isValidInt(s) {
    if len(s) == 0 {
        emit 0
    }
    let start = 0
    if s[0] == "-" {
        if len(s) == 1 {
            emit 0
        }
        start = 1
    }
    let i = start
    while i < len(s) {
        let ch = s[i]
        if ch < "0" {
            emit 0
        }
        if ch > "9" {
            emit 0
        }
        i += 1
    }
    emit 1
}

// Check if string is non-empty
func isNonEmpty(s) {
    if len(s) > 0 {
        emit 1
    }
    emit 0
}

// Check if string contains only whitespace
func isBlank(s) {
    let i = 0
    while i < len(s) {
        let ch = s[i]
        if ch != " " {
            if ch != "\t" {
                if ch != "\n" {
                    if ch != "\r" {
                        emit 0
                    }
                }
            }
        }
        i += 1
    }
    emit 1
}

// Check if string is a valid identifier (letter/underscore start, alphanumeric)
func isValidIdent(s) {
    if len(s) == 0 {
        emit 0
    }
    let first = s[0]
    if first != "_" {
        if first < "A" { emit 0 }
        if first > "z" { emit 0 }
        if first > "Z" {
            if first < "a" {
                emit 0
            }
        }
    }
    let i = 1
    while i < len(s) {
        let ch = s[i]
        if ch == "_" {
            i += 1
        } else if ch >= "0" {
            if ch <= "9" {
                i += 1
            } else if ch >= "A" {
                if ch <= "z" {
                    i += 1
                } else {
                    emit 0
                }
            } else {
                emit 0
            }
        } else if ch >= "A" {
            if ch <= "z" {
                i += 1
            } else {
                emit 0
            }
        } else {
            emit 0
        }
    }
    emit 1
}

// Check if string length is within bounds
func isLengthBetween(s, minLen, maxLen) {
    let sLen = len(s)
    if sLen >= minLen {
        if sLen <= maxLen {
            emit 1
        }
    }
    emit 0
}

// Check if a number is in range [lo, hi]
func isInRange(n, lo, hi) {
    if n >= lo {
        if n <= hi {
            emit 1
        }
    }
    emit 0
}

// Check if a string looks like a file path
func isFilePath(s) {
    if len(s) == 0 {
        emit 0
    }
    // Check for common path patterns
    let i = 0
    let hasDot = 0
    let hasSlash = 0
    while i < len(s) {
        if s[i] == "." {
            hasDot = 1
        }
        if s[i] == "/" {
            hasSlash = 1
        }
        if s[i] == "\\" {
            hasSlash = 1
        }
        i += 1
    }
    if hasDot {
        emit 1
    }
    if hasSlash {
        emit 1
    }
    emit 0
}

// Validate that all characters are printable ASCII
func isPrintableAscii(s) {
    let i = 0
    while i < len(s) {
        let ch = s[i]
        if ch < " " {
            if ch != "\t" {
                if ch != "\n" {
                    emit 0
                }
            }
        }
        i += 1
    }
    emit 1
}

// ── Character-class predicates (single char in, "1"/"0" out) ─────────

func isAsciiLetter(c) {
    if len(c) != 1 { emit "0" }
    if c >= "a" && c <= "z" { emit "1" }
    if c >= "A" && c <= "Z" { emit "1" }
    emit "0"
}

func isAsciiDigit(c) {
    if len(c) != 1 { emit "0" }
    if c >= "0" && c <= "9" { emit "1" }
    emit "0"
}

func isAsciiAlnum(c) {
    if isAsciiLetter(c) == "1" { emit "1" }
    if isAsciiDigit(c)  == "1" { emit "1" }
    emit "0"
}

func isHexDigit(c) {
    if isAsciiDigit(c) == "1" { emit "1" }
    if c >= "a" && c <= "f" { emit "1" }
    if c >= "A" && c <= "F" { emit "1" }
    emit "0"
}

// ── Whole-string validators ──────────────────────────────────────────

// True iff every char is ASCII letter or digit (and string non-empty).
func isAlnum(s) {
    if len(s) == 0 { emit 0 }
    let i = 0
    while i < len(s) {
        if isAsciiAlnum(s[i]) == "0" { emit 0 }
        i = i + 1
    }
    emit 1
}

// True iff every char is ASCII letter (and string non-empty).
func isAlpha(s) {
    if len(s) == 0 { emit 0 }
    let i = 0
    while i < len(s) {
        if isAsciiLetter(s[i]) == "0" { emit 0 }
        i = i + 1
    }
    emit 1
}

// True iff every char is 0-9 (and string non-empty).
func isNumeric(s) {
    if len(s) == 0 { emit 0 }
    let i = 0
    while i < len(s) {
        if isAsciiDigit(s[i]) == "0" { emit 0 }
        i = i + 1
    }
    emit 1
}

// True iff every char is a hex digit (0-9 a-f A-F). String non-empty.
// Accepts an optional leading "0x" or "0X".
func isHex(s) {
    if len(s) == 0 { emit 0 }
    let start = 0
    if len(s) >= 2 && s[0] == "0" {
        if s[1] == "x" || s[1] == "X" { start = 2 }
    }
    if start >= len(s) { emit 0 }
    let i = start
    while i < len(s) {
        if isHexDigit(s[i]) == "0" { emit 0 }
        i = i + 1
    }
    emit 1
}

// Lightweight email validator. Accepts "<local>@<domain>" where:
//   - local is 1+ chars of [A-Za-z0-9._%+-]
//   - domain has at least one "." and TLD-side is 2+ letters
// Not RFC-5322 — that needs a real parser. Catches the everyday bad
// shapes (missing @, no domain, no dot, bare TLD).
func isEmail(s) {
    if len(s) < 3 { emit 0 }
    let at = indexOf(s, "@")
    if at <= 0 { emit 0 }
    if at >= len(s) - 1 { emit 0 }
    // local-part chars
    let i = 0
    while i < at {
        let c = s[i]
        let ok = 0
        if isAsciiAlnum(c) == "1" { ok = 1 }
        if c == "." || c == "_" || c == "%" || c == "+" || c == "-" { ok = 1 }
        if ok == 0 { emit 0 }
        i = i + 1
    }
    // domain-part: must contain at least one '.', TLD 2+ letters
    let dom = substring(s, at + 1, len(s))
    let dot = -1
    let j = len(dom) - 1
    while j >= 0 {
        if dom[j] == "." { dot = j  j = -1 }
        else { j = j - 1 }
    }
    if dot < 0 { emit 0 }
    if (len(dom) - dot - 1) < 2 { emit 0 }
    let k = dot + 1
    while k < len(dom) {
        if isAsciiLetter(dom[k]) == "0" { emit 0 }
        k = k + 1
    }
    // disallow consecutive or leading/trailing dots in domain
    if dom[0] == "." { emit 0 }
    if dom[len(dom) - 1] == "." { emit 0 }
    let m = 1
    while m < len(dom) {
        if dom[m] == "." && dom[m - 1] == "." { emit 0 }
        m = m + 1
    }
    emit 1
}

// IPv4 dotted-quad validator. Each octet 0-255, no leading zeros
// (except the digit "0" itself).
func isIPv4(s) {
    if len(s) == 0 { emit 0 }
    let dots = 0
    let i = 0
    while i < len(s) {
        if s[i] == "." { dots = dots + 1 }
        i = i + 1
    }
    if dots != 3 { emit 0 }
    // walk 4 octets
    let oct = 0
    let lo = 0
    let n = len(s)
    while oct < 4 {
        let hi = lo
        while hi < n && s[hi] != "." { hi = hi + 1 }
        let part = substring(s, lo, hi)
        if len(part) == 0 { emit 0 }
        if len(part) > 3 { emit 0 }
        if len(part) > 1 && part[0] == "0" { emit 0 }
        let p = 0
        while p < len(part) {
            if isAsciiDigit(part[p]) == "0" { emit 0 }
            p = p + 1
        }
        let v = toInt(part)
        if v > 255 { emit 0 }
        lo = hi + 1
        oct = oct + 1
    }
    emit 1
}

// URL shape check (http/https only, with host). Not a full parser.
//   isURL("https://example.com/path?q=1") → "1"
func isURL(s) {
    if len(s) < 10 { emit 0 }
    let scheme = ""
    if startsWith(s, "https://") == "1" { scheme = "https" }
    if startsWith(s, "http://")  == "1" { scheme = "http"  }
    if scheme == "" { emit 0 }
    let rest = substring(s, len(scheme) + 3, len(s))
    if len(rest) == 0 { emit 0 }
    // host = up to first '/', '?', '#'
    let endHost = len(rest)
    let h = 0
    while h < len(rest) {
        let c = rest[h]
        if c == "/" || c == "?" || c == "#" { endHost = h  h = len(rest) }
        else { h = h + 1 }
    }
    let host = substring(rest, 0, endHost)
    if len(host) == 0 { emit 0 }
    // host must contain at least one ".", "-", or alnum
    let okHost = 0
    let i = 0
    while i < len(host) {
        let c = host[i]
        if isAsciiAlnum(c) == "1" { okHost = 1 }
        else if c == "." || c == "-" || c == ":" { }
        else { emit 0 }
        i = i + 1
    }
    if okHost == 0 { emit 0 }
    emit 1
}

// UUID v1-v5 shape: 8-4-4-4-12 hex chars (case-insensitive), with hyphens.
//   "550e8400-e29b-41d4-a716-446655440000"
func isUUID(s) {
    if len(s) != 36 { emit 0 }
    let i = 0
    while i < 36 {
        let c = s[i]
        if i == 8 || i == 13 || i == 18 || i == 23 {
            if c != "-" { emit 0 }
        } else {
            if isHexDigit(c) == "0" { emit 0 }
        }
        i = i + 1
    }
    emit 1
}

// True iff s contains only chars from a given allow-list set.
func charsIn(s, allowed) {
    if len(s) == 0 { emit 0 }
    let i = 0
    while i < len(s) {
        if indexOf(allowed, s[i]) < 0 { emit 0 }
        i = i + 1
    }
    emit 1
}
