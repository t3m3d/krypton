// v1.2.5 feature test

// ** exponentiation operator
func power(base, exp) {
    emit base ** exp
}

// ++ / -- in statement position
func countUp(n) {
    let i = toInt(n)
    let result = ""
    while i <= 5 {
        result = result + i + " "
        i++
    }
    emit result
}

func countDown(n) {
    let i = toInt(n)
    let result = ""
    while i > 0 {
        result = result + i + " "
        i--
    }
    emit result
}

// pre-increment
func preInc(n) {
    let i = toInt(n)
    ++i
    emit i
}

// ++ in for-like loop
func sumTo(n) {
    let i = 0
    let s = 0
    while i < toInt(n) {
        i++
        s += toInt(i)
    }
    emit s
}

// ** chaining (right-associative)
func cube(x) {
    emit x ** 3
}

just run {
    // Test **
    printErr("2 ** 10 = " + power("2", "10"))
    printErr("3 ** 3 = " + power("3", "3"))
    printErr("cube(4) = " + cube("4"))

    // Test i++
    printErr("countUp(1) = " + countUp("1"))
    printErr("countDown(5) = " + countDown("5"))

    // Test ++i
    printErr("preInc(7) = " + preInc("7"))

    // Test sumTo
    printErr("sum 1..5 = " + sumTo("5"))

    emit 0
}
