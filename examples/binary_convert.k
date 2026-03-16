// Binary number converter
// Convert between decimal and binary representations

func toBinary(n) {
    if n == 0 {
        emit "0"
    }
    let result = ""
    let num = n
    while num > 0 {
        let bit = num % 2
        result = "" + bit + result
        num = num / 2
    }
    emit result
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
    let result = bin
    while len(result) < width {
        result = "0" + result
    }
    emit result
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
