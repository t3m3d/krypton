// Binary number converter
// Convert between decimal and binary representations

func toBinary(n) {
    if n == 0 {
        emit "0"
    }
    // Build digits MSB-first into an sb. Per spec, `+` on two numeric
    // strings adds — so naive "" + bit + result silently does arithmetic
    // once result is digit-only. sbAppend / sbPrepend would be ideal;
    // until sbPrepend exists, accumulate LSB-first into an sb and reverse.
    let lsb = sbNew()
    let num = n
    while num > 0 {
        let bit = num % 2
        // sbAppend (kr_concat) auto-stringifies a small-int second arg.
        // Don't pre-stringify via "" + bit — that takes the numeric path.
        lsb = sbAppend(lsb, bit)
        num = num / 2
    }
    emit reverse(sbToString(lsb))
}

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

func padBinary(bin, width) {
    // Naive `result = "0" + result` does numeric add per spec
    // (both args look numeric), so build via sb.
    let need = width - len(bin)
    if need <= 0 { emit bin }
    let sb = sbNew()
    let i = 0
    while i < need {
        sb = sbAppend(sb, "0")
        i += 1
    }
    sb = sbAppend(sb, bin)
    emit sbToString(sb)
}

just run {
    kp("Binary Number Converter")
    kp("=======================")
    kp("")

    kp("Decimal to Binary:")
    let nums = "0,1,2,7,8,15,16,42,100,255,256,1000"
    let total = count(nums)
    let i = 0
    while i < total {
        let n = toInt(split(nums, i))
        let bin = toBinary(n)
        kp("  " + n + " => " + padBinary(bin, 12))
        i += 1
    }

    kp("")
    kp("Binary to Decimal:")
    let bins = "0,1,10,111,1000,1111,10000,101010,1100100,11111111"
    total = count(bins)
    i = 0
    while i < total {
        let b = split(bins, i)
        let dec = fromBinary(b)
        kp("  " + padBinary(b, 12) + " => " + dec)
        i += 1
    }

    // Powers of 2 in binary
    kp("")
    kp("Powers of 2:")
    let p = 1
    let exp = 0
    while exp <= 10 {
        kp("  2^" + exp + " = " + p + " = " + padBinary(toBinary(p), 12))
        p = p * 2
        exp = exp + 1
    }
    emit "ok"
}
