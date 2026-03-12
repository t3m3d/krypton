// Fibonacci with Dynamic Programming (bottom-up)

func fibDP(n) {
    if n <= 0 { emit 0 }
    if n == 1 { emit 1 }
    let prev2 = 0
    let prev1 = 1
    let i = 2
    while i <= n {
        let curr = prev1 + prev2
        prev2 = prev1
        prev1 = curr
        i = i + 1
    }
    emit prev1
}

just run {
    print("Fibonacci (DP)")
    print("==============")
    let i = 0
    while i <= 30 {
        print("  fib(" + i + ") = " + fibDP(i))
        i = i + 5
    }

    // Compare performance: DP handles large n easily
    print("")
    print("fib(40) = " + fibDP(40))
    print("fib(50) = " + fibDP(50))
}
