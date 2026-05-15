// Factorial using recursion and iteration

func factRecursive(n) {
    if n <= 1 { emit 1 }
    emit n * factRecursive(n - 1)
}

func factIterative(n) {
    let result = 1
    let i = 2
    while i <= n {
        result *= i
        i += 1
    }
    emit result
}

just run {
    for n in range(0, 13) {
        let ni = toInt(n)
        kp(`{n}! = ` + factRecursive(ni))
    }
}
