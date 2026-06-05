// Hex encoding/decoding for Krypton

module hex


// Encode a number as hex string with 0x prefix.
//
// Krypton bug: digit-only hex (e.g. dec 50 → "32") built via `+` on
// two single-digit strings would int-coalesce ("3" + "2" → 5). Build
// the digits in reverse into an sb, then reverse the sb contents.
func encodeHex(n) {
    let hexChars = "0123456789abcdef"
    if n == 0 { emit "0x0" }
    let buf = sbNew()
    let num = n
    while num > 0 {
        buf = sbAppend(buf, hexChars[num % 16])
        num = num / 16
    }
    let s = sbToString(buf)
    let out = sbNew()
    out = sbAppend(out, "0x")
    let i = len(s) - 1
    while i >= 0 {
        out = sbAppend(out, s[i])
        i = i - 1
    }
    emit sbToString(out)
}

// Decode a hex string (with or without 0x prefix)
func decodeHex(s) {
    let start = 0
    if len(s) > 2 {
        if s[0] == "0" {
            if s[1] == "x" {
                start = 2
            }
        }
    }
    let result = 0
    let i = start
    while i < len(s) {
        result = result * 16
        let ch = s[i]
        if ch >= "0" {
            if ch <= "9" {
                result = result + toInt(ch) - 48
            }
        }
        if ch >= "a" {
            if ch <= "f" {
                result = result + toInt(ch) - 87
            }
        }
        if ch >= "A" {
            if ch <= "F" {
                result = result + toInt(ch) - 55
            }
        }
        i += 1
    }
    emit result
}

// Convert a byte value to two-digit hex
func byteToHex(b) {
    let hexChars = "0123456789abcdef"
    let hi = b / 16
    let lo = b % 16
    emit hexChars[hi] + hexChars[lo]
}

// Convert a buffer (raw bytes via bufGetByte) to a hex string of
// length 2*n. Lowercase, no spaces or 0x prefix.
//   bytesToHex(buf, 4) → "deadbeef"
func bytesToHex(buf, n) {
    let out = sbNew()
    let i = 0
    while i < n {
        let b = toInt(bufGetByte(buf, i))
        out = sbAppend(out, byteToHex(b))
        i = i + 1
    }
    emit sbToString(out)
}

// Pretty-print a hex dump in the classic `hexdump -C` style.
//   offset (8 digit hex) | 16 bytes (space sep) | "ascii"
func hexDump(buf, n) {
    let out = sbNew()
    let row = 0
    while row * 16 < n {
        // offset
        let off = row * 16
        let offHex = encodeHex(off)
        out = sbAppend(out, offHex)
        out = sbAppend(out, "  ")
        // bytes
        let i = 0
        while i < 16 {
            let pos = off + i
            if pos < n {
                let b = toInt(bufGetByte(buf, pos))
                out = sbAppend(out, byteToHex(b))
                out = sbAppend(out, " ")
            } else {
                out = sbAppend(out, "   ")
            }
            if i == 7 { out = sbAppend(out, " ") }
            i = i + 1
        }
        // ascii
        out = sbAppend(out, " |")
        i = 0
        while i < 16 {
            let pos = off + i
            if pos < n {
                let b = toInt(bufGetByte(buf, pos))
                if b >= 32 && b < 127 { out = sbAppend(out, fromCharCode(b)) }
                else                  { out = sbAppend(out, ".") }
            } else {
                out = sbAppend(out, " ")
            }
            i = i + 1
        }
        out = sbAppend(out, "|\n")
        row = row + 1
    }
    emit sbToString(out)
}

// Check if string is a valid hex number
func isHexString(s) {
    let start = 0
    if len(s) > 2 {
        if s[0] == "0" {
            if s[1] == "x" {
                start = 2
            }
        }
    }
    if start >= len(s) {
        emit 0
    }
    let i = start
    while i < len(s) {
        let ch = s[i]
        let valid = 0
        if ch >= "0" {
            if ch <= "9" {
                valid = 1
            }
        }
        if ch >= "a" {
            if ch <= "f" {
                valid = 1
            }
        }
        if ch >= "A" {
            if ch <= "F" {
                valid = 1
            }
        }
        if valid == 0 {
            emit 0
        }
        i += 1
    }
    emit 1
}
