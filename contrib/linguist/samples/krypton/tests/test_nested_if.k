// Test nested if statements
// Verifies complex conditional logic

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

func classify(n) {
    if n > 0 {
        if n % 2 == 0 {
            emit "positive even"
        } else {
            emit "positive odd"
        }
    } else if n < 0 {
        if n % 2 == 0 {
            emit "negative even"
        } else {
            emit "negative odd"
        }
    } else {
        emit "zero"
    }
}

func grade(score) {
    if score >= 90 {
        emit "A"
    } else if score >= 80 {
        emit "B"
    } else if score >= 70 {
        emit "C"
    } else if score >= 60 {
        emit "D"
    } else {
        emit "F"
    }
}

just run {
    kp("Nested If Tests")
    kp("===============")

    // Classify numbers
    check("positive even", "positive even", classify(4))
    check("positive odd", "positive odd", classify(7))
    check("negative even", "negative even", classify(0 - 6))
    check("negative odd", "negative odd", classify(0 - 3))
    check("zero", "zero", classify(0))

    // Grade function
    check("grade A", "A", grade(95))
    check("grade B", "B", grade(85))
    check("grade C", "C", grade(75))
    check("grade D", "D", grade(65))
    check("grade F", "F", grade(50))
    check("grade boundary", "A", grade(90))
    check("grade boundary B", "B", grade(80))

    // Deep nesting
    let x = 5
    let result = ""
    if x > 0 {
        if x > 3 {
            if x > 4 {
                if x == 5 {
                    result = "found 5"
                }
            }
        }
    }
    check("deep nesting", "found 5", result)

    emit "ok"
}
