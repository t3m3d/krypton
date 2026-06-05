// Pseudo-random number generation for Krypton
// Uses a linear congruential generator

module random


// Generate next random number from seed
// LCG: next = (a * seed + c) % m
func nextRandom(seed) {
    // Using parameters similar to MINSTD. The modulus 2^31-1 (2147483647)
    // exceeds the smart-int literal ceiling (0x7F000000), so build via
    // toInt of a string literal.
    let a = 16807
    let c = 0
    let m = toInt("2147483647")
    let next = (a * seed + c) % m
    if next < 0 {
        next = 0 - next
    }
    emit next
}

// Get random number in range [0, max)
func randomInRange(seed, maxVal) {
    let r = nextRandom(seed)
    emit r % maxVal
}

// Generate n random numbers as comma-separated list
func randomList(seed, n, maxVal) {
    let result = ""
    let current = seed
    let i = 0
    while i < n {
        current = nextRandom(current)
        let val = current % maxVal
        if result == "" {
            result = "" + val
        } else {
            result = result + "," + val
        }
        i += 1
    }
    emit result
}

// Shuffle a comma-separated list (Fisher-Yates with LCG)
func shuffle(list, seed) {
    let size = count(list)
    // Copy list to mutable array representation
    let arr = list
    let current = seed
    let i = size - 1
    while i > 0 {
        current = nextRandom(current)
        let j = current % (i + 1)
        // Swap arr[i] and arr[j]
        let valI = split(arr, i)
        let valJ = split(arr, j)
        let sb = sbNew()
        let k = 0
        while k < size {
            if k > 0 {
                sb = sbAppend(sb, ",")
            }
            if k == i {
                sb = sbAppend(sb, valJ)
            } else if k == j {
                sb = sbAppend(sb, valI)
            } else {
                sb = sbAppend(sb, split(arr, k))
            }
            k += 1
        }
        arr = sbToString(sb)
        i -= 1
    }
    emit arr
}

// Pick a random element from a list
func randomChoice(list, seed) {
    let size = count(list)
    let r = nextRandom(seed)
    let idx = r % size
    emit split(list, idx)
}

// Generate a random string of given length
func randomString(seed, length) {
    let chars = "abcdefghijklmnopqrstuvwxyz"
    let sb = sbNew()
    let current = seed
    let i = 0
    while i < length {
        current = nextRandom(current)
        let idx = current % 26
        sb = sbAppend(sb, chars[idx])
        i += 1
    }
    emit sbToString(sb)
}

// Random boolean ("1" or "0") from a seed.
func randomBool(seed) {
    let r = nextRandom(seed)
    emit r % 2
}

// Random int in [lo, hi). lo inclusive, hi exclusive.
//   randomRange(seed, 10, 20) → 10..19
func randomRange(seed, lo, hi) {
    let span = hi - lo
    if span <= 0 { emit lo }
    let r = nextRandom(seed)
    emit lo + (r % span)
}

// Roll `count` dice of `sides` each; return CSV of results.
//   diceRoll(seed, 6, 3) → "4,2,6"
func diceRoll(seed, sides, count) {
    let out = ""
    let current = seed
    let i = 0
    while i < count {
        current = nextRandom(current)
        let r = (current % sides) + 1
        if out == "" { out = "" + r }
        else         { out = out + "," + r }
        i += 1
    }
    emit out
}

// Sample k unique items from a list without replacement. If k >= len(list),
// returns a shuffled copy of the whole list.
func randomSample(list, k, seed) {
    let n = count(list)
    let take = k
    if take > n { take = n }
    let shuffled = shuffle(list, seed)
    if take == n { emit shuffled }
    let out = ""
    let i = 0
    while i < take {
        if out == "" { out = split(shuffled, i) }
        else         { out = out + "," + split(shuffled, i) }
        i += 1
    }
    emit out
}
