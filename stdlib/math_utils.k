// Math utility functions for Krypton.
// Builtins to use directly (don't reimplement; the dispatcher routes calls
// of these names to native machine code regardless of any user definition):
//   abs(n)   pow(base, exp)
// This module ships the rest: min, max, factorial, gcd, lcm, isPrime,
// fibonacci, digitSum, digitCount, clamp, isqrt, sign, sumTo.

module math_utils


// Maximum of two values
func max(a, b) {
    if a > b {
        emit a
    }
    emit b
}

// Minimum of two values
func min(a, b) {
    if a < b {
        emit a
    }
    emit b
}

// Power function (base^exp for non-negative exp)
func power(base, exp) {
    let result = 1
    let i = 0
    while i < exp {
        result *= base
        i += 1
    }
    emit result
}

// Factorial
func factorial(n) {
    if n <= 1 {
        emit 1
    }
    emit n * factorial(n - 1)
}

// Greatest common divisor (Euclidean algorithm)
func gcd(a, b) {
    let x = abs(a)
    let y = abs(b)
    while y != 0 {
        let temp = y
        y = x % temp
        x = temp
    }
    emit x
}

// Least common multiple
func lcm(a, b) {
    if a == 0 {
        emit 0
    }
    if b == 0 {
        emit 0
    }
    emit abs(a * b) / gcd(a, b)
}

// Check if a number is prime
func isPrime(n) {
    if n < 2 {
        emit 0
    }
    if n == 2 {
        emit 1
    }
    if n % 2 == 0 {
        emit 0
    }
    let i = 3
    while i * i <= n {
        if n % i == 0 {
            emit 0
        }
        i = i + 2
    }
    emit 1
}

// Fibonacci number at position n
func fibonacci(n) {
    if n <= 0 {
        emit 0
    }
    if n == 1 {
        emit 1
    }
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

// Sum of digits
func digitSum(n) {
    let num = abs(n)
    let sum = 0
    while num > 0 {
        sum = sum + num % 10
        num = num / 10
    }
    emit sum
}

// Count digits in a number
func digitCount(n) {
    if n == 0 {
        emit 1
    }
    let num = abs(n)
    let cnt = 0
    while num > 0 {
        cnt += 1
        num = num / 10
    }
    emit cnt
}

// Clamp a value between min and max
func clamp(val, lo, hi) {
    if val < lo {
        emit lo
    }
    if val > hi {
        emit hi
    }
    emit val
}

// Integer square root (floor)
func isqrt(n) {
    if n < 0 {
        emit 0
    }
    if n == 0 {
        emit 0
    }
    let x = n
    let y = (x + 1) / 2
    while y < x {
        x = y
        y = (x + n / x) / 2
    }
    emit x
}

// Sign function: returns -1, 0, or 1
func sign(n) {
    if n < 0 {
        emit 0 - 1
    }
    if n > 0 {
        emit 1
    }
    emit 0
}

// Sum of integers from 1 to n
func sumTo(n) {
    emit n * (n + 1) / 2
}

// ── Modular arithmetic + extended GCD ────────────────────────────────

// Modular exponentiation: (base ^ exp) mod m. exp is non-negative.
func modPow(base, exp, m) {
    if m == 1 { emit 0 }
    let result = 1
    let b = base % m
    let e = exp
    while e > 0 {
        if e % 2 == 1 { result = (result * b) % m }
        e = e / 2
        b = (b * b) % m
    }
    emit result
}

// Modular inverse via extended Euclidean. Returns -1 if gcd(a, m) > 1.
func modInverse(a, m) {
    let g = a
    let x = 1
    let y = 0
    let g2 = m
    let x2 = 0
    let y2 = 1
    while g2 != 0 {
        let q = g / g2
        let tg = g - q * g2
        let tx = x - q * x2
        let ty = y - q * y2
        g = g2  x = x2  y = y2
        g2 = tg  x2 = tx  y2 = ty
    }
    if g != 1 { emit 0 - 1 }
    let r = x % m
    if r < 0 { r = r + m }
    emit r
}

// Binomial coefficient C(n, k). Iterative, integer-only.
func choose(n, k) {
    if k < 0 || k > n { emit 0 }
    let kk = k
    if kk > n - kk { kk = n - kk }
    let result = 1
    let i = 0
    while i < kk {
        result = result * (n - i)
        result = result / (i + 1)
        i = i + 1
    }
    emit result
}

// Greatest common divisor returning the larger of two when both are 0.
func ceilDiv(a, b) {
    if b == 0 { emit 0 }
    emit (a + b - 1) / b
}

// Integer logarithm: largest k such that base^k <= n. Returns -1 for
// n <= 0 or base <= 1.
func ilog(n, base) {
    if n <= 0 { emit 0 - 1 }
    if base <= 1 { emit 0 - 1 }
    let k = 0
    let v = 1
    while v * base <= n {
        v = v * base
        k = k + 1
    }
    emit k
}

// Integer power: base^exp. Negative exp returns 0 (no fractions).
func ipow(base, exp) {
    if exp < 0 { emit 0 }
    let result = 1
    let b = base
    let e = exp
    while e > 0 {
        if e % 2 == 1 { result = result * b }
        e = e / 2
        b = b * b
    }
    emit result
}

// True iff n is even.
func isEven(n) {
    if n % 2 == 0 { emit 1 }
    emit 0
}

// True iff n is odd.
func isOdd(n) {
    if n % 2 == 0 { emit 0 }
    emit 1
}
