// Sieve of Eratosthenes
// Find all primes up to N using the classic sieve algorithm

// We represent the sieve as a comma-separated list of "1" or "0"
func makeSieve(n) {
    let result = "0,0"  // 0 and 1 are not prime
    let i = 2
    while i <= n {
        result = result + ",1"
        i = i + 1
    }
    emit result
}

func sieveSet(sieve, idx, val) {
    let size = count(sieve)
    let sb = sbNew()
    let i = 0
    while i < size {
        if i > 0 {
            sb = sbAppend(sb, ",")
        }
        if i == idx {
            sb = sbAppend(sb, "" + val)
        } else {
            sb = sbAppend(sb, split(sieve, i))
        }
        i = i + 1
    }
    emit sbToString(sb)
}

just run {
    let n = 50
    kp("Sieve of Eratosthenes up to " + n)
    kp("================================")

    let sieve = makeSieve(n)

    // Sieve algorithm
    let p = 2
    while p * p <= n {
        if split(sieve, p) == "1" {
            // Mark multiples of p as composite
            let j = p * p
            while j <= n {
                sieve = sieveSet(sieve, j, 0)
                j = j + p
            }
        }
        p = p + 1
    }

    // Collect primes
    let primes = ""
    let primeCount = 0
    let i = 2
    while i <= n {
        if split(sieve, i) == "1" {
            if primes == "" {
                primes = "" + i
            } else {
                primes = primes + ", " + i
            }
            primeCount = primeCount + 1
        }
        i = i + 1
    }

    kp("Primes: " + primes)
    kp("Count: " + primeCount)
    emit "ok"
}
