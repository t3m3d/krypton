// Prime number checker and generator
// Demonstrates control flow and mathematical operations

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

func nextPrime(n) {
    let candidate = n + 1
    while isPrime(candidate) == 0 {
        candidate = candidate + 1
    }
    emit candidate
}

just run {
    kp("Prime Numbers up to 100:")
    kp("========================")
    let primeCount = 0
    let sb = sbNew()
    let i = 2
    while i <= 100 {
        if isPrime(i) {
            if primeCount > 0 {
                sb = sbAppend(sb, ", ")
            }
            sb = sbAppend(sb, "" + i)
            primeCount = primeCount + 1
        }
        i = i + 1
    }
    kp(sbToString(sb))
    kp("")
    kp("Total primes found: " + primeCount)

    kp("")
    kp("Prime gaps (consecutive primes and their differences):")
    let prev = 2
    let current = 3
    let gapCount = 0
    while current <= 100 {
        if isPrime(current) {
            let gap = current - prev
            if gap > 2 {
                kp("  Gap of " + gap + " between " + prev + " and " + current)
                gapCount = gapCount + 1
            }
            prev = current
        }
        current = current + 1
    }
    kp("Gaps > 2 found: " + gapCount)
    emit "ok"
}
