// Collatz conjecture (3n+1 problem)
// For any positive integer: if even divide by 2, if odd multiply by 3 and add 1
// Conjecture: all sequences eventually reach 1

func collatzStep(n) {
    if n % 2 == 0 {
        emit n / 2
    }
    emit 3 * n + 1
}

func collatzLength(n) {
    let steps = 0
    let current = n
    while current != 1 {
        current = collatzStep(current)
        steps = steps + 1
    }
    emit steps
}

func collatzMax(n) {
    let maxVal = n
    let current = n
    while current != 1 {
        if current > maxVal {
            maxVal = current
        }
        current = collatzStep(current)
    }
    emit maxVal
}

just run {
    kp("Collatz Conjecture (3n+1)")
    kp("=========================")
    kp("")

    // Show sequence for a specific number
    let start = 27
    kp("Sequence for " + start + ":")
    let sb = sbNew()
    let current = start
    let steps = 0
    while current != 1 {
        sb = sbAppend(sb, "" + current + " -> ")
        current = collatzStep(current)
        steps = steps + 1
    }
    sb = sbAppend(sb, "1")
    kp(sbToString(sb))
    kp("Steps: " + steps)
    kp("")

    // Find number with longest sequence in range
    kp("Collatz lengths for 1-30:")
    let longestN = 1
    let longestLen = 0
    let n = 1
    while n <= 30 {
        let cLen = collatzLength(n)
        let maxReached = collatzMax(n)
        let label = "" + n
        while len(label) < 4 {
            label = " " + label
        }
        kp("  n=" + label + "  steps=" + cLen + "  max=" + maxReached)
        if cLen > longestLen {
            longestLen = cLen
            longestN = n
        }
        n = n + 1
    }
    kp("")
    kp("Longest sequence: n=" + longestN + " with " + longestLen + " steps")
    emit "ok"
}
