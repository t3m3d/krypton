// Find the largest prime factor of an integer.

func largestPrimeFactor(n) {
    let v = n
    let largest = 1
    let p = 2
    while v > 1 {
        if v % p == 0 {
            largest = p
            while v % p == 0 { v = v / p }
        }
        p += 1
        // p*p > v means v is itself prime
        if p * p > v {
            if v > 1 { largest = v }
            v = 1
        }
    }
    emit largest
}

just run {
    let nums = "2,3,12,15,28,100,600851475,13195"
    for s in nums {
        let n = toInt(s)
        kp(s + " → largest prime factor = " + largestPrimeFactor(n))
    }
}
