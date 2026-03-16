// Power function examples
// Various exponentiation algorithms

func powerSimple(base, exp) {
    let result = 1
    let i = 0
    while i < exp {
        result = result * base
        i += 1
    }
    emit result
}

// Fast exponentiation using binary method (exponentiation by squaring)
func powerFast(base, exp) {
    let result = 1
    let b = base
    let e = exp
    while e > 0 {
        if e % 2 == 1 {
            result = result * b
        }
        b = b * b
        e = e / 2
    }
    emit result
}

// Modular exponentiation: (base^exp) % mod
func powerMod(base, exp, mod) {
    let result = 1
    let b = base % mod
    let e = exp
    while e > 0 {
        if e % 2 == 1 {
            result = (result * b) % mod
        }
        b = (b * b) % mod
        e = e / 2
    }
    emit result
}

just run {
    kp("Power Function Examples")
    kp("=======================")
    kp("")

    // Basic powers
    kp("Powers of 2:")
    let i = 0
    while i <= 15 {
        kp("  2^" + i + " = " + powerFast(2, i))
        i += 1
    }
    kp("")

    kp("Powers of 3:")
    i = 0
    while i <= 10 {
        kp("  3^" + i + " = " + powerFast(3, i))
        i += 1
    }
    kp("")

    // Verify both methods give same results
    kp("Verification (simple vs fast):")
    let base = 5
    let exp = 0
    while exp <= 8 {
        let s = powerSimple(base, exp)
        let f = powerFast(base, exp)
        let match = "MATCH"
        if s != f {
            match = "MISMATCH"
        }
        kp("  " + base + "^" + exp + " = " + s + " / " + f + " [" + match + "]")
        exp = exp + 1
    }
    kp("")

    // Modular exponentiation
    kp("Modular exponentiation (base^exp mod 97):")
    kp("  2^10 mod 97 = " + powerMod(2, 10, 97))
    kp("  3^20 mod 97 = " + powerMod(3, 20, 97))
    kp("  5^15 mod 97 = " + powerMod(5, 15, 97))
    emit "ok"
}
