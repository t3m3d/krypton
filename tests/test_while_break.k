// Test while loop with break
// Verifies loop control flow including break statements

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("While/Break Tests")
    kp("=================")

    // Basic while
    let sum = 0
    let i = 1
    while i <= 10 {
        sum = sum + i
        i = i + 1
    }
    check("sum 1-10", "55", "" + sum)

    // While with break
    let found = 0
    i = 0
    while i < 100 {
        if i == 42 {
            found = i
            break
        }
        i = i + 1
    }
    check("break at 42", "42", "" + found)

    // Nested while
    let count = 0
    i = 0
    while i < 5 {
        let j = 0
        while j < 5 {
            count = count + 1
            j = j + 1
        }
        i = i + 1
    }
    check("nested 5x5", "25", "" + count)

    // While false (should not execute)
    let executed = 0
    while 0 {
        executed = 1
    }
    check("while false", "0", "" + executed)

    // Single iteration
    let once = 0
    i = 0
    while i < 1 {
        once = once + 1
        i = i + 1
    }
    check("single iter", "1", "" + once)

    // Break in nested (inner only)
    let outerCount = 0
    let innerTotal = 0
    i = 0
    while i < 5 {
        let j = 0
        while j < 10 {
            if j == 3 {
                break
            }
            innerTotal = innerTotal + 1
            j = j + 1
        }
        outerCount = outerCount + 1
        i = i + 1
    }
    check("outer continues", "5", "" + outerCount)
    check("inner breaks at 3", "15", "" + innerTotal)

    emit "ok"
}
