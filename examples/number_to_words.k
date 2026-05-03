// Convert an integer 0-999 to English words.

func ones(n) {
    if n == 0 { emit "" }
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
    emit ""
}

func tens(n) {
    if n == 2 { emit "twenty" }
    if n == 3 { emit "thirty" }
    if n == 4 { emit "forty" }
    if n == 5 { emit "fifty" }
    if n == 6 { emit "sixty" }
    if n == 7 { emit "seventy" }
    if n == 8 { emit "eighty" }
    if n == 9 { emit "ninety" }
    emit ""
}

func words(n) {
    if n == 0 { emit "zero" }
    let out = ""
    let h = n / 100
    let rem = n % 100
    if h > 0 {
        out = ones(h) + " hundred"
        if rem > 0 { out = out + " " }
    }
    if rem >= 20 {
        out = out + tens(rem / 10)
        if rem % 10 > 0 { out = out + "-" + ones(rem % 10) }
    } else if rem > 0 {
        out = out + ones(rem)
    }
    emit out
}

just run {
    let nums = "0,1,7,12,19,20,42,99,100,101,250,777,999"
    for s in nums {
        let n = toInt(s)
        kp(s + " = " + words(n))
    }
}
