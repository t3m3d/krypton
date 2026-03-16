// Roman numeral converter
// Convert between decimal and Roman numeral representations

func toRoman(n) {
    let result = ""
    let num = n

    while num >= 1000 {
        result = result + "M"
        num = num - 1000
    }
    while num >= 900 {
        result = result + "CM"
        num = num - 900
    }
    while num >= 500 {
        result = result + "D"
        num = num - 500
    }
    while num >= 400 {
        result = result + "CD"
        num = num - 400
    }
    while num >= 100 {
        result = result + "C"
        num = num - 100
    }
    while num >= 90 {
        result = result + "XC"
        num = num - 90
    }
    while num >= 50 {
        result = result + "L"
        num = num - 50
    }
    while num >= 40 {
        result = result + "XL"
        num = num - 40
    }
    while num >= 10 {
        result = result + "X"
        num = num - 10
    }
    while num >= 9 {
        result = result + "IX"
        num = num - 9
    }
    while num >= 5 {
        result = result + "V"
        num = num - 5
    }
    while num >= 4 {
        result = result + "IV"
        num = num - 4
    }
    while num >= 1 {
        result = result + "I"
        num = num - 1
    }

    emit result
}

func romanCharValue(ch) {
    if ch == "I" { emit 1 }
    if ch == "V" { emit 5 }
    if ch == "X" { emit 10 }
    if ch == "L" { emit 50 }
    if ch == "C" { emit 100 }
    if ch == "D" { emit 500 }
    if ch == "M" { emit 1000 }
    emit 0
}

func fromRoman(s) {
    let result = 0
    let i = 0
    while i < len(s) {
        let current = romanCharValue(s[i])
        if i + 1 < len(s) {
            let next = romanCharValue(s[i + 1])
            if current < next {
                result = result + next - current
                i = i + 2
            } else {
                result = result + current
                i += 1
            }
        } else {
            result = result + current
            i += 1
        }
    }
    emit result
}

just run {
    kp("Roman Numeral Converter")
    kp("=======================")
    kp("")

    let nums = "1,4,9,14,42,99,100,399,500,1000,1999,2024,3999"
    let total = count(nums)
    let i = 0
    while i < total {
        let n = toInt(split(nums, i))
        let roman = toRoman(n)
        let back = fromRoman(roman)
        let label = "" + n
        while len(label) < 6 {
            label = " " + label
        }
        kp("  " + label + " = " + roman + " (back to: " + back + ")")
        i += 1
    }
    emit "ok"
}
