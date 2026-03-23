// Simple IR test program
func add(a, b) {
    emit toInt(a) + toInt(b) + ""
}

func factorial(n) {
    if n <= 1 { emit "1" }
    emit toInt(n) * toInt(factorial(n - 1)) + ""
}

just run {
    kp(add("3", "4"))
    kp(factorial("5"))
    let i = 0
    while i < 3 {
        kp("loop: " + i)
        i += 1
    }
}
