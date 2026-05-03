// Print a hex dump of a string, 16 bytes per row.
//
// Note: uses sbAppend rather than `+` to concatenate single hex digits.
// Reason: `+` between two numeric-looking strings does addition, so
// `"4" + "8"` would give 12 instead of "48". sbAppend is always concat.

func toHex2(n) {
    let digits = "0123456789ABCDEF"
    let hi = n / 16
    let lo = n % 16
    let sb = sbNew()
    sb = sbAppend(sb, digits[hi])
    sb = sbAppend(sb, digits[lo])
    emit sbToString(sb)
}

func toHex6(n) {
    let digits = "0123456789ABCDEF"
    let v = n
    let buf = ""
    let i = 0
    while i < 6 {
        let sb = sbNew()
        sb = sbAppend(sb, digits[v % 16])
        sb = sbAppend(sb, buf)
        buf = sbToString(sb)
        v = v / 16
        i += 1
    }
    emit buf
}

just run {
    let data = "Hello, Krypton! This is a hex dump test.|Line 2 here.|Final."
    let n = len(data)
    let off = 0
    while off < n {
        let line = sbNew()
        line = sbAppend(line, toHex6(off))
        line = sbAppend(line, "  ")
        let ascii = ""
        let i = 0
        while i < 16 {
            if off + i < n {
                let ch = data[off + i]
                let code = charCode(ch)
                line = sbAppend(line, toHex2(code))
                line = sbAppend(line, " ")
                if code >= 32 {
                    if code <= 126 { ascii = ascii + ch }
                    else { ascii = ascii + "." }
                } else {
                    ascii = ascii + "."
                }
            } else {
                line = sbAppend(line, "   ")
                ascii = ascii + " "
            }
            i += 1
        }
        line = sbAppend(line, " |")
        line = sbAppend(line, ascii)
        line = sbAppend(line, "|")
        kp(sbToString(line))
        off += 16
    }
}
