// Bitwise operations for Krypton
// Simulated via arithmetic since Krypton lacks native bitwise ops

go bitwise {

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
}
