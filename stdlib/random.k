// Pseudo-random number generation for Krypton
// Uses a linear congruential generator

go random {

    // Generate next random number from seed
    // LCG: next = (a * seed + c) % m
    func nextRandom(seed) {
        // Using parameters similar to MINSTD
        let a = 16807
        let c = 0
        let m = 2147483647
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
            i = i + 1
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
                k = k + 1
            }
            arr = sbToString(sb)
            i = i - 1
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
            i = i + 1
        }
        emit sbToString(sb)
    }
}
