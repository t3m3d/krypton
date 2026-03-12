// GCD and LCM calculator
// Greatest Common Divisor and Least Common Multiple

func gcd(a, b) {
    let x = a
    let y = b
    if x < 0 { x = 0 - x }
    if y < 0 { y = 0 - y }
    while y != 0 {
        let temp = y
        y = x % temp
        x = temp
    }
    emit x
}

func lcm(a, b) {
    if a == 0 { emit 0 }
    if b == 0 { emit 0 }
    let g = gcd(a, b)
    let absA = a
    let absB = b
    if absA < 0 { absA = 0 - absA }
    if absB < 0 { absB = 0 - absB }
    emit (absA / g) * absB
}

func extendedGcd(a, b) {
    // Returns gcd,x,y where a*x + b*y = gcd
    if b == 0 {
        emit "" + a + ",1,0"
    }
    let result = extendedGcd(b, a % b)
    let g = split(result, 0)
    let x1 = toInt(split(result, 1))
    let y1 = toInt(split(result, 2))
    let x = y1
    let y = x1 - (a / b) * y1
    emit g + "," + x + "," + y
}

just run {
    kp("GCD and LCM Calculator")
    kp("======================")
    kp("")

    // Test pairs
    kp("GCD examples:")
    kp("  gcd(12, 8) = " + gcd(12, 8))
    kp("  gcd(54, 24) = " + gcd(54, 24))
    kp("  gcd(100, 75) = " + gcd(100, 75))
    kp("  gcd(17, 13) = " + gcd(17, 13))
    kp("  gcd(0, 5) = " + gcd(0, 5))
    kp("")

    kp("LCM examples:")
    kp("  lcm(4, 6) = " + lcm(4, 6))
    kp("  lcm(12, 18) = " + lcm(12, 18))
    kp("  lcm(7, 5) = " + lcm(7, 5))
    kp("  lcm(15, 20) = " + lcm(15, 20))
    kp("")

    // GCD table
    kp("GCD table (rows and columns 1-8):")
    let sb = sbNew()
    sb = sbAppend(sb, "     ")
    let c = 1
    while c <= 8 {
        let label = "" + c
        while len(label) < 4 {
            label = " " + label
        }
        sb = sbAppend(sb, label)
        c = c + 1
    }
    kp(sbToString(sb))

    let r = 1
    while r <= 8 {
        sb = sbNew()
        let rLabel = "" + r
        while len(rLabel) < 3 {
            rLabel = " " + rLabel
        }
        sb = sbAppend(sb, rLabel + "  ")
        c = 1
        while c <= 8 {
            let g = gcd(r, c)
            let gLabel = "" + g
            while len(gLabel) < 4 {
                gLabel = " " + gLabel
            }
            sb = sbAppend(sb, gLabel)
            c = c + 1
        }
        kp(sbToString(sb))
        r = r + 1
    }
    emit "ok"
}
