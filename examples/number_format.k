// Number formatting utilities
// Format numbers in various ways

func formatWithCommas(n) {
    let s = "" + n
    let sLen = len(s)
    if sLen <= 3 {
        emit s
    }
    let sb = sbNew()
    let i = 0
    while i < sLen {
        let remaining = sLen - i
        if remaining % 3 == 0 {
            if i > 0 {
                sb = sbAppend(sb, ",")
            }
        }
        sb = sbAppend(sb, s[i])
        i = i + 1
    }
    emit sbToString(sb)
}

func toOrdinal(n) {
    let mod100 = n % 100
    if mod100 == 11 { emit "" + n + "th" }
    if mod100 == 12 { emit "" + n + "th" }
    if mod100 == 13 { emit "" + n + "th" }
    let mod10 = n % 10
    if mod10 == 1 { emit "" + n + "st" }
    if mod10 == 2 { emit "" + n + "nd" }
    if mod10 == 3 { emit "" + n + "rd" }
    emit "" + n + "th"
}

func numberToWords(n) {
    if n == 0 { emit "zero" }
    if n == 1 { emit "one" }
    if n == 2 { emit "two" }
    if n == 3 { emit "three" }
    if n == 4 { emit "four" }
    if n == 5 { emit "five" }
    if n == 6 { emit "six" }
    if n == 7 { emit "seven" }
    if n == 8 { emit "eight" }
    if n == 9 { emit "nine" }
    if n == 10 { emit "ten" }
    if n == 11 { emit "eleven" }
    if n == 12 { emit "twelve" }
    if n == 13 { emit "thirteen" }
    if n == 14 { emit "fourteen" }
    if n == 15 { emit "fifteen" }
    if n == 16 { emit "sixteen" }
    if n == 17 { emit "seventeen" }
    if n == 18 { emit "eighteen" }
    if n == 19 { emit "nineteen" }
    if n == 20 { emit "twenty" }
    emit "" + n
}

func formatBytes(bytes) {
    if bytes < 1024 {
        emit "" + bytes + " B"
    }
    let kb = bytes / 1024
    if kb < 1024 {
        emit "" + kb + " KB"
    }
    let mb = kb / 1024
    if mb < 1024 {
        emit "" + mb + " MB"
    }
    let gb = mb / 1024
    emit "" + gb + " GB"
}

just run {
    kp("Number Formatting")
    kp("=================")
    kp("")

    kp("Comma formatting:")
    let nums = "1,12,123,1234,12345,123456,1234567"
    let total = count(nums)
    let i = 0
    while i < total {
        let n = toInt(split(nums, i))
        kp("  " + n + " -> " + formatWithCommas(n))
        i = i + 1
    }
    kp("")

    kp("Ordinal numbers:")
    i = 1
    while i <= 25 {
        kp("  " + toOrdinal(i))
        i = i + 1
    }
    kp("")

    kp("Numbers to words:")
    i = 0
    while i <= 20 {
        kp("  " + i + " -> " + numberToWords(i))
        i = i + 1
    }
    kp("")

    kp("Byte formatting:")
    let sizes = "512,1024,4096,1048576,1073741824"
    total = count(sizes)
    i = 0
    while i < total {
        let n = toInt(split(sizes, i))
        kp("  " + n + " -> " + formatBytes(n))
        i = i + 1
    }
    emit "ok"
}
