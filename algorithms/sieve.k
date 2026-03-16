// Sieve of Eratosthenes

func sieve(limit) {
    // Use env as boolean array
    let isPrime = ""
    let i = 2
    while i <= limit {
        isPrime = envSet(isPrime, "" + i, "1")
        i += 1
    }

    i = 2
    while i * i <= limit {
        if toInt(envGet(isPrime, "" + i)) == 1 {
            let j = i * i
            while j <= limit {
                isPrime = envSet(isPrime, "" + j, "0")
                j = j + i
            }
        }
        i += 1
    }

    // Collect primes
    let primes = ""
    let count = 0
    i = 2
    while i <= limit {
        if toInt(envGet(isPrime, "" + i)) == 1 {
            if count > 0 {
                primes = primes + ","
            }
            primes = primes + "" + i
            count += 1
        }
        i += 1
    }
    print("Found " + count + " primes up to " + limit)
    emit primes
}

just run {
    let primes = sieve(50)
    print("Primes: " + primes)
}
