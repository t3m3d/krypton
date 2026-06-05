// Bitwise operations for Krypton
// Simulated via arithmetic since Krypton lacks native bitwise ops

module bitwise


// Bitwise AND using binary decomposition
func bitAnd(a, b) {
    let result = 0
    let bit = 1
    let x = a
    let y = b
    while x > 0 {
        if y <= 0 {
            break
        }
        let xBit = x % 2
        let yBit = y % 2
        if xBit == 1 {
            if yBit == 1 {
                result = result + bit
            }
        }
        x = x / 2
        y = y / 2
        bit = bit * 2
    }
    emit result
}

// Bitwise OR
func bitOr(a, b) {
    let result = 0
    let bit = 1
    let x = a
    let y = b
    while x > 0 {
        let xBit = x % 2
        let yBit = y % 2
        if xBit == 1 {
            result = result + bit
        } else if yBit == 1 {
            result = result + bit
        }
        x = x / 2
        y = y / 2
        bit = bit * 2
    }
    // Handle remaining bits of y
    while y > 0 {
        let yBit = y % 2
        if yBit == 1 {
            result = result + bit
        }
        y = y / 2
        bit = bit * 2
    }
    emit result
}

// Bitwise XOR
func bitXor(a, b) {
    let result = 0
    let bit = 1
    let x = a
    let y = b
    while x > 0 {
        let xBit = x % 2
        let yBit = y % 2
        if xBit != yBit {
            result = result + bit
        }
        x = x / 2
        y = y / 2
        bit = bit * 2
    }
    while y > 0 {
        let yBit = y % 2
        if yBit == 1 {
            result = result + bit
        }
        y = y / 2
        bit = bit * 2
    }
    emit result
}

// Left shift by n positions
func shiftLeft(val, n) {
    let result = val
    let i = 0
    while i < n {
        result = result * 2
        i += 1
    }
    emit result
}

// Right shift by n positions
func shiftRight(val, n) {
    let result = val
    let i = 0
    while i < n {
        result = result / 2
        i += 1
    }
    emit result
}

// Count set bits (popcount)
func popcount(n) {
    let cnt = 0
    let x = n
    while x > 0 {
        if x % 2 == 1 {
            cnt += 1
        }
        x = x / 2
    }
    emit cnt
}

// Check if n is a power of 2
func isPowerOf2(n) {
    if n <= 0 {
        emit 0
    }
    if popcount(n) == 1 {
        emit 1
    }
    emit 0
}

// Get the highest set bit position
func highBit(n) {
    let pos = 0
    let x = n
    while x > 1 {
        x = x / 2
        pos += 1
    }
    emit pos
}

// Get the lowest set bit position (0-indexed). Returns -1 for n=0.
func lowBit(n) {
    if n == 0 { emit 0 - 1 }
    let pos = 0
    let x = n
    while x % 2 == 0 {
        x = x / 2
        pos = pos + 1
    }
    emit pos
}

// Test whether bit at `pos` is set in `n` (returns 0 or 1).
func bitTest(n, pos) {
    let x = n
    let i = 0
    while i < pos {
        x = x / 2
        i = i + 1
    }
    emit x % 2
}

// Set bit at `pos` in `n` (returns new value).
func bitSet(n, pos) {
    let mask = 1
    let i = 0
    while i < pos {
        mask = mask * 2
        i = i + 1
    }
    if (n / mask) % 2 == 1 { emit n }
    emit n + mask
}

// Clear bit at `pos` in `n` (returns new value).
func bitClear(n, pos) {
    let mask = 1
    let i = 0
    while i < pos {
        mask = mask * 2
        i = i + 1
    }
    if (n / mask) % 2 == 1 { emit n - mask }
    emit n
}

// Toggle bit at `pos`.
func bitToggle(n, pos) {
    if bitTest(n, pos) == 1 { emit bitClear(n, pos) }
    emit bitSet(n, pos)
}

// Number of bits required to represent n (1 for n=0..1, 2 for n=2..3, ...).
func bitWidth(n) {
    if n <= 0 { emit 1 }
    let pos = 0
    let x = n
    while x > 0 {
        x = x / 2
        pos = pos + 1
    }
    emit pos
}

// Round up to the next power of 2 (>= n). nextPow2(0)=1, nextPow2(1)=1.
func nextPow2(n) {
    if n <= 1 { emit 1 }
    let p = 1
    while p < n { p = p * 2 }
    emit p
}
