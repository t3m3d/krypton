// GCD and LCM algorithms

func gcd(a, b) {
    while b != 0 {
        let t = b
        b = a % b
        a = t
    }
    emit a
}

func lcm(a, b) {
    emit (a * b) / gcd(a, b)
}

// Extended GCD: returns "gcd,x,y" where a*x + b*y = gcd
func extGcd(a, b) {
    if b == 0 {
        emit "" + a + ",1,0"
    }
    let result = extGcd(b, a % b)
    let g = toInt(split(result, 0))
    let x = toInt(split(result, 1))
    let y = toInt(split(result, 2))
    let newX = y
    let newY = x - (a / b) * y
    emit "" + g + "," + newX + "," + newY
}

just run {
    print("GCD and LCM")
    print("============")

    let pairs = "12,8,54,24,17,13,100,75,48,36"
    let i = 0
    while i < 5 {
        let a = toInt(split(pairs, i * 2))
        let b = toInt(split(pairs, i * 2 + 1))
        print("  gcd(" + a + ", " + b + ") = " + gcd(a, b))
        print("  lcm(" + a + ", " + b + ") = " + lcm(a, b))
        i += 1
    }

    print("")
    print("Extended GCD:")
    let eg = extGcd(35, 15)
    let g = split(eg, 0)
    let x = split(eg, 1)
    let y = split(eg, 2)
    print("  extGcd(35, 15) = gcd=" + g + " x=" + x + " y=" + y)
    print("  Verify: 35*" + x + " + 15*" + y + " = " + (35 * toInt(x) + 15 * toInt(y)))
}
