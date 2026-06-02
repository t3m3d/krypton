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
func toHex(n) {
    if n == 0 { emit "0" }
    let x = n
    let out = ""
    while x > 0 {
        let d = x % 16
        out = _hexDigit(d) + out
        x = x / 16
    }
    emit out
}

// toHexByte(n) -> exactly 2 hex digits (low byte of n).
func toHexByte(n) {
    let b = n % 256
    let hi = b / 16
    let lo = b % 16
    emit _hexDigit(hi) + _hexDigit(lo)
}

// toHexPad(n, width) -> hex left-padded with '0' to width digits.
func toHexPad(n, width) {
    let s = toHex(n)
    while len(s) < width { s = "0" + s }
    emit s
}

// strToHex(s) -> hex of every byte of the string ("AB" -> "4142").
func strToHex(s) {
    let out = ""
    let i = 0
    while i < len(s) {
        out = out + toHexByte(toInt(charCode(s[i])))
        i += 1
    }
    emit out
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
func hexToStr(s) {
    let out = ""
    let i = 0
    while i + 1 < len(s) {
        out = out + fromCharCode(_hexVal(s[i]) * 16 + _hexVal(s[i+1]))
        i += 2
    }
    emit out
}
