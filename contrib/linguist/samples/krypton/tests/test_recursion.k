// Test recursion
// Verifies function self-calling

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

func factorial(n) {
    if n <= 1 { emit 1 }
    emit n * factorial(n - 1)
}

func fib(n) {
    if n <= 0 { emit 0 }
    if n == 1 { emit 1 }
    emit fib(n - 1) + fib(n - 2)
}

func sumDigits(n) {
    if n < 10 { emit n }
    emit n % 10 + sumDigits(n / 10)
}

func power(b, e) {
    if e == 0 { emit 1 }
    emit b * power(b, e - 1)
}

func gcd(a, b) {
    if b == 0 { emit a }
    emit gcd(b, a % b)
}

func countDown(n) {
    if n <= 0 { emit "done" }
    emit countDown(n - 1)
}

just run {
    kp("Recursion Tests")
    kp("===============")

    // Factorial
    check("fact 0", "1", "" + factorial(0))
    check("fact 1", "1", "" + factorial(1))
    check("fact 5", "120", "" + factorial(5))
    check("fact 10", "3628800", "" + factorial(10))

    // Fibonacci
    check("fib 0", "0", "" + fib(0))
    check("fib 1", "1", "" + fib(1))
    check("fib 5", "5", "" + fib(5))
    check("fib 10", "55", "" + fib(10))

    // Sum digits
    check("digsum 123", "6", "" + sumDigits(123))
    check("digsum 999", "27", "" + sumDigits(999))
    check("digsum 5", "5", "" + sumDigits(5))

    // Power
    check("pow 2^10", "1024", "" + power(2, 10))
    check("pow 3^4", "81", "" + power(3, 4))
    check("pow 5^0", "1", "" + power(5, 0))

    // GCD
    check("gcd 12,8", "4", "" + gcd(12, 8))
    check("gcd 54,24", "6", "" + gcd(54, 24))
    check("gcd 17,13", "1", "" + gcd(17, 13))

    // Deep recursion
    check("countdown", "done", countDown(50))

    emit "ok"
}
