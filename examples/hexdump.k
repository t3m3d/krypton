// Print a hex dump of a string, 16 bytes per row.

func toHex2(n) {
    let digits = "0123456789ABCDEF"
    let hi = n / 16
    let lo = n % 16
    emit digits[hi] + digits[lo]
}

func toHex6(n) {
    let digits = "0123456789ABCDEF"
    let v = n
    let out = ""
    let i = 0
    while i < 6 {
        out = digits[v % 16] + out
        v = v / 16
        i += 1
    }
    emit out
}

just run {
    let data = "Hello, Krypton! This is a hex dump test.|Line 2 here.|Final."
    let n = len(data)
    let off = 0
    while off < n {
        let line = toHex6(off) + "  "
        let ascii = ""
        let i = 0
        while i < 16 {
            if off + i < n {
                let ch = data[off + i]
                let code = charCode(ch)
                line = line + toHex2(code) + " "
                if code >= 32 {
                    if code <= 126 { ascii = ascii + ch }
                    else { ascii = ascii + "." }
                } else {
                    ascii = ascii + "."
                }
            } else {
                line = line + "   "
                ascii = ascii + " "
            }
            i += 1
        }
        kp(line + " |" + ascii + "|")
        off += 16
    }
}
