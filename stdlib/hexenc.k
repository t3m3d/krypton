// stdlib/hexenc.k — hex string encode/decode in PURE KRYPTON. No C.
//
// The native `hex()` builtin returns a DECIMAL string (e.g. hex(255) -> "255"),
// so it can't be used for real hex. This module does proper base-16.
//
//   toHex(110)        -> "6e"      (lowercase, no padding)
//   toHexByte(15)     -> "0f"      (always 2 digits)
//   strToHex("AB")    -> "4142"    (each byte of a string)
//   fromHex("6e")     -> 110       (parse hex -> int)
//   hexToStr("4142")  -> "AB"      (hex pairs -> string)

module hexenc

func _hexDigit(v) {
    if v < 10 { emit fromCharCode(48 + v) }       // 0-9
    emit fromCharCode(87 + v)                       // a-f  (97-10)
}

// toHex(n) -> lowercase hex of a non-negative int, no leading zeros.
//
// Built via sb + reverse because `digit + out` int-coalesces when both
// are digit chars ("3" + "2" → 5, not "32"). Same fix pattern as the
// other format helpers.
func toHex(n) {
    if n == 0 { emit "0" }
    let x = n
    let buf = sbNew()
    while x > 0 {
        buf = sbAppend(buf, _hexDigit(x % 16))
        x = x / 16
    }
    let raw = sbToString(buf)
    let out = sbNew()
    let j = len(raw) - 1
    while j >= 0 {
        out = sbAppend(out, raw[j])
        j = j - 1
    }
    emit sbToString(out)
}

// toHexByte(n) -> exactly 2 hex digits (low byte of n).
//
// Builds the two-digit pair via sbAppend because `_hexDigit(hi) +
// _hexDigit(lo)` int-coalesces when both digits are 0-9 (e.g. 0x32
// would render as 5).
func toHexByte(n) {
    let b = n % 256
    let hi = b / 16
    let lo = b % 16
    let out = sbNew()
    out = sbAppend(out, _hexDigit(hi))
    out = sbAppend(out, _hexDigit(lo))
    emit sbToString(out)
}

// toHexPad(n, width) -> hex left-padded with '0' to width digits.
// `"0" + s` int-coalesces single-digit input — use sbAppend.
func toHexPad(n, width) {
    let s = toHex(n)
    while len(s) < width {
        let b = sbNew()
        b = sbAppend(b, "0")
        b = sbAppend(b, s)
        s = sbToString(b)
    }
    emit s
}

// strToHex(s) -> hex of every byte of the string ("AB" -> "4142").
// Built via sbAppend — two 2-digit pairs concatenated via `+` also
// int-coalesce when the resulting strings are pure digits.
func strToHex(s) {
    let out = sbNew()
    let i = 0
    while i < len(s) {
        out = sbAppend(out, toHexByte(toInt(charCode(s[i]))))
        i += 1
    }
    emit sbToString(out)
}

func _hexVal(c) {
    let v = toInt(charCode(c))
    if v >= 48 && v <= 57 { emit v - 48 }     // 0-9
    if v >= 97 && v <= 102 { emit v - 87 }    // a-f
    if v >= 65 && v <= 70  { emit v - 55 }    // A-F
    emit 0
}

// fromHex(s) -> integer value of a hex string (any length).
func fromHex(s) {
    let v = 0
    let i = 0
    while i < len(s) {
        v = v * 16 + _hexVal(s[i])
        i += 1
    }
    emit v
}

// hexToStr(s) -> decode hex pairs back into a string ("4142" -> "AB").
// Built via sbAppend (output chars may be digits).
func hexToStr(s) {
    let out = sbNew()
    let i = 0
    while i + 1 < len(s) {
        out = sbAppend(out, fromCharCode(_hexVal(s[i]) * 16 + _hexVal(s[i+1])))
        i += 2
    }
    emit sbToString(out)
}
