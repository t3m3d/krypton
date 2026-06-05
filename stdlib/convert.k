// Type conversion utilities for Krypton
// Convert between different representations

module convert


// Convert integer to binary string.
//
// Builds digits via sbAppend then reverses, because Krypton's `+` on
// two single-digit strings int-coalesces ("1" + "0" → 1, not "10").
func toBinary(n) {
    if n == 0 { emit "0" }
    let buf = sbNew()
    let num = n
    while num > 0 {
        let bit = num % 2
        if bit == 1 { buf = sbAppend(buf, "1") }
        else        { buf = sbAppend(buf, "0") }
        num = num / 2
    }
    let s = sbToString(buf)
    let out = sbNew()
    let i = len(s) - 1
    while i >= 0 {
        out = sbAppend(out, s[i])
        i = i - 1
    }
    emit sbToString(out)
}

// Convert binary string to integer
func fromBinary(s) {
    let result = 0
    let i = 0
    while i < len(s) {
        result = result * 2
        if s[i] == "1" {
            result = result + 1
        }
        i += 1
    }
    emit result
}

// Convert integer to hexadecimal string. Same int-coalesce workaround
// as toBinary — build via sb then reverse.
func toHex(n) {
    if n == 0 { emit "0" }
    let hexChars = "0123456789abcdef"
    let buf = sbNew()
    let num = n
    while num > 0 {
        buf = sbAppend(buf, hexChars[num % 16])
        num = num / 16
    }
    let s = sbToString(buf)
    let out = sbNew()
    let i = len(s) - 1
    while i >= 0 {
        out = sbAppend(out, s[i])
        i = i - 1
    }
    emit sbToString(out)
}

// Convert hexadecimal string to integer.
//
// Original used toInt(ch) for letters — but toInt("a") = 0 (atoi fail),
// so every hex letter b-f / B-F mapped to value 10. Use charCode for
// letters; toInt is fine for digits since toInt("5")=5 by spec.
func fromHex(s) {
    let result = 0
    let i = 0
    while i < len(s) {
        result = result * 16
        let ch = s[i]
        if ch >= "0" && ch <= "9" {
            result = result + toInt(ch)
        } else if ch >= "a" && ch <= "f" {
            result = result + (toInt(charCode(ch)) - 97) + 10
        } else if ch >= "A" && ch <= "F" {
            result = result + (toInt(charCode(ch)) - 65) + 10
        }
        i += 1
    }
    emit result
}

// Convert integer to octal string. Same int-coalesce workaround
// as toBinary / toHex — build via sb then reverse.
func toOctal(n) {
    if n == 0 { emit "0" }
    let digits = "01234567"
    let buf = sbNew()
    let num = n
    while num > 0 {
        buf = sbAppend(buf, digits[num % 8])
        num = num / 8
    }
    let s = sbToString(buf)
    let out = sbNew()
    let i = len(s) - 1
    while i >= 0 {
        out = sbAppend(out, s[i])
        i = i - 1
    }
    emit sbToString(out)
}

// Convert a character to its string representation
func charToStr(ch) {
    emit "" + ch
}

// Convert boolean-like value to string
func boolToStr(val) {
    if val {
        emit "true"
    }
    emit "false"
}

// Convert string to all-lowercase representation
// (simple version for ASCII a-z)
func toLowerStr(s) {
    let sb = sbNew()
    let upperAlpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    let lowerAlpha = "abcdefghijklmnopqrstuvwxyz"
    let i = 0
    while i < len(s) {
        let ch = s[i]
        let found = 0
        let j = 0
        while j < 26 {
            if ch == upperAlpha[j] {
                sb = sbAppend(sb, lowerAlpha[j])
                found = 1
                break
            }
            j += 1
        }
        if found == 0 {
            sb = sbAppend(sb, ch)
        }
        i += 1
    }
    emit sbToString(sb)
}

// Convert number to string with sign prefix. "+" + n would int-coalesce
// (atoi("+")=0, so "+" + 5 = 5), so build via sb.
func toSignedStr(n) {
    if n > 0 {
        let b = sbNew()
        b = sbAppend(b, "+")
        b = sbAppend(b, n + "")
        emit sbToString(b)
    }
    emit "" + n
}

// ── Arbitrary base conversion (2..36) ────────────────────────────────

// toBase(n, base) — convert integer n to a string in base 2..36.
// Uses 0-9 then a-z for digits. Returns "0" for n=0.
func toBase(n, base) {
    if n == 0 { emit "0" }
    if base < 2 || base > 36 { emit "" }
    let alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
    let buf = sbNew()
    let num = n
    let neg = 0
    if num < 0 { neg = 1  num = 0 - num }
    while num > 0 {
        buf = sbAppend(buf, alphabet[num % base])
        num = num / base
    }
    let s = sbToString(buf)
    let out = sbNew()
    if neg == 1 { out = sbAppend(out, "-") }
    let i = len(s) - 1
    while i >= 0 {
        out = sbAppend(out, s[i])
        i = i - 1
    }
    emit sbToString(out)
}

// fromBase(s, base) — parse a base-2..36 string into an integer.
// Returns 0 on bad input. Accepts an optional leading "-".
//
// Uses charCode for digit values: Krypton's toInt("5") = 5 (the digit
// value), but toInt("f") = 0 (atoi fail), so we go via charCode for
// every char to get a uniform numeric mapping.
func fromBase(s, base) {
    if base < 2 || base > 36 { emit 0 }
    if len(s) == 0 { emit 0 }
    let start = 0
    let neg = 0
    if s[0] == "-" { neg = 1  start = 1 }
    let total = 0
    let i = start
    while i < len(s) {
        let cc = toInt(charCode(s[i]))
        let v = 0 - 1
        if cc >= 48 && cc <= 57 { v = cc - 48 }              // 0-9
        if cc >= 97 && cc <= 122 { v = (cc - 97) + 10 }      // a-z
        if cc >= 65 && cc <= 90  { v = (cc - 65) + 10 }      // A-Z
        if v < 0 || v >= base { emit 0 }
        total = total * base + v
        i = i + 1
    }
    if neg == 1 { emit 0 - total }
    emit total
}
