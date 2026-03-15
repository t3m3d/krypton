// Fibonacci sequence generator

func fib(n) {
    if n <= 0 { emit 0 }
    if n == 1 { emit 1 }
    let a = 0
    let b = 1
    let i = 2
    while i <= n {
        let temp = a + b
        a = b
        b = temp
        i += 1
    }
    emit b
}

just run {
    let n = 20
    kp(`First {n} Fibonacci numbers:`)
    for i in range(0, n) {
        kp(`  fib({i}) = ` + fib(toInt(i)))
    }
}
