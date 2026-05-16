// v1.2.4 feature test

// -> bool return type
func isPositive(n) -> bool {
    emit toInt(n) > 0
}

// loop { } until condition
func countDown(start) -> zero {
    let n = toInt(start)
    loop {
        printErr("n = " + n)
        n -= 1
    } until n == 0
}

just run {
    // Test -> bool
    let pos = isPositive("5")
    let neg = isPositive("-3")
    printErr("isPositive(5) = " + pos)
    printErr("isPositive(-3) = " + neg)

    // Test loop..until
    countDown("3")

    // Test emit exit code (0 = success)
    emit 0
}
