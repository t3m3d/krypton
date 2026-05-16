// Test nested while loops

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("Nested While Tests")
    kp("==================")

    // Basic nested
    let total = 0
    let i = 0
    while i < 3 {
        let j = 0
        while j < 4 {
            total = total + 1
            j = j + 1
        }
        i = i + 1
    }
    check("3x4 iterations", "12", "" + total)

    // Triple nested
    total = 0
    i = 0
    while i < 2 {
        let j = 0
        while j < 3 {
            let k = 0
            while k < 4 {
                total = total + 1
                k = k + 1
            }
            j = j + 1
        }
        i = i + 1
    }
    check("2x3x4 iterations", "24", "" + total)

    // Inner break doesn't affect outer
    let outerRuns = 0
    i = 0
    while i < 5 {
        let j = 0
        while j < 100 {
            if j == 2 {
                break
            }
            j = j + 1
        }
        outerRuns = outerRuns + 1
        i = i + 1
    }
    check("outer runs all 5", "5", "" + outerRuns)

    // Dependent loops (inner depends on outer)
    total = 0
    i = 0
    while i < 5 {
        let j = 0
        while j <= i {
            total = total + 1
            j = j + 1
        }
        i = i + 1
    }
    check("triangular 1+2+3+4+5", "15", "" + total)

    emit "ok"
}
