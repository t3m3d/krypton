// Factorial calculator
// Computes n! using both iterative and recursive approaches

func factorialIterative(n) {
    let result = 1
    let i = 2
    while i <= n {
        result = result * i
        i = i + 1
    }
    emit result
}

func factorialRecursive(n) {
    if n <= 1 {
        emit 1
    }
    emit n * factorialRecursive(n - 1)
}

just run {
    kp("Factorial Calculator")
    kp("====================")
    let i = 0
    while i <= 12 {
        let iter = factorialIterative(i)
        let recur = factorialRecursive(i)
        kp(i + "! = " + iter + " (recursive: " + recur + ")")
        i = i + 1
    }
    emit "ok"
}
