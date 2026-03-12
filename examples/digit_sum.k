// Digit sum calculator
// Sum the digits of numbers and explore properties

func digitSum(n) {
    let num = n
    if num < 0 { num = 0 - num }
    let sum = 0
    while num > 0 {
        sum = sum + num % 10
        num = num / 10
    }
    emit sum
}

func digitalRoot(n) {
    let num = n
    while num >= 10 {
        num = digitSum(num)
    }
    emit num
}

func digitProduct(n) {
    let num = n
    if num < 0 { num = 0 - num }
    if num == 0 { emit 0 }
    let product = 1
    while num > 0 {
        product = product * (num % 10)
        num = num / 10
    }
    emit product
}

func countDigits(n) {
    if n == 0 { emit 1 }
    let num = n
    if num < 0 { num = 0 - num }
    let cnt = 0
    while num > 0 {
        cnt = cnt + 1
        num = num / 10
    }
    emit cnt
}

func reverseNumber(n) {
    let num = n
    let reversed = 0
    while num > 0 {
        reversed = reversed * 10 + num % 10
        num = num / 10
    }
    emit reversed
}

just run {
    kp("Digit Operations")
    kp("================")
    kp("")

    kp("Digit sums:")
    let nums = "123,456,789,999,1234,9999,12345"
    let total = count(nums)
    let i = 0
    while i < total {
        let n = toInt(split(nums, i))
        kp("  " + n + " -> digit sum: " + digitSum(n) + ", digital root: " + digitalRoot(n))
        i = i + 1
    }
    kp("")

    kp("Digit products:")
    i = 0
    while i < total {
        let n = toInt(split(nums, i))
        kp("  " + n + " -> digit product: " + digitProduct(n))
        i = i + 1
    }
    kp("")

    kp("Number reversal:")
    let revNums = "1234,5678,12321,10000,9876"
    total = count(revNums)
    i = 0
    while i < total {
        let n = toInt(split(revNums, i))
        let rev = reverseNumber(n)
        let isPalin = "no"
        if n == rev {
            isPalin = "yes"
        }
        kp("  " + n + " -> " + rev + " (palindrome: " + isPalin + ")")
        i = i + 1
    }
    kp("")

    // Find all numbers 1-100 where digit sum is 10
    kp("Numbers 1-100 with digit sum = 10:")
    let sb = sbNew()
    let n = 1
    while n <= 100 {
        if digitSum(n) == 10 {
            sb = sbAppend(sb, "" + n + " ")
        }
        n = n + 1
    }
    kp("  " + sbToString(sb))
    emit "ok"
}
