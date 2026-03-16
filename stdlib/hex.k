// Hex encoding/decoding for Krypton

go hex {

    // Encode a number as hex string with 0x prefix
    func encodeHex(n) {
        let hexChars = "0123456789abcdef"
        if n == 0 {
            emit "0x0"
        }
        let result = ""
        let num = n
        while num > 0 {
            let digit = num % 16
            result = hexChars[digit] + result
            num = num / 16
        }
        emit "0x" + result
    }

    // Decode a hex string (with or without 0x prefix)
    func decodeHex(s) {
        let start = 0
        if len(s) > 2 {
            if s[0] == "0" {
                if s[1] == "x" {
                    start = 2
                }
            }
        }
        let result = 0
        let i = start
        while i < len(s) {
            result = result * 16
            let ch = s[i]
            if ch >= "0" {
                if ch <= "9" {
                    result = result + toInt(ch) - 48
                }
            }
            if ch >= "a" {
                if ch <= "f" {
                    result = result + toInt(ch) - 87
                }
            }
            if ch >= "A" {
                if ch <= "F" {
                    result = result + toInt(ch) - 55
                }
            }
            i += 1
        }
        emit result
    }

    // Convert a byte value to two-digit hex
    func byteToHex(b) {
        let hexChars = "0123456789abcdef"
        let hi = b / 16
        let lo = b % 16
        emit hexChars[hi] + hexChars[lo]
    }

    // Check if string is a valid hex number
    func isHexString(s) {
        let start = 0
        if len(s) > 2 {
            if s[0] == "0" {
                if s[1] == "x" {
                    start = 2
                }
            }
        }
        if start >= len(s) {
            emit 0
        }
        let i = start
        while i < len(s) {
            let ch = s[i]
            let valid = 0
            if ch >= "0" {
                if ch <= "9" {
                    valid = 1
                }
            }
            if ch >= "a" {
                if ch <= "f" {
                    valid = 1
                }
            }
            if ch >= "A" {
                if ch <= "F" {
                    valid = 1
                }
            }
            if valid == 0 {
                emit 0
            }
            i += 1
        }
        emit 1
    }
}
