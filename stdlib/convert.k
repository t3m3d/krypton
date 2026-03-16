// Type conversion utilities for Krypton
// Convert between different representations

go convert {

    // Convert integer to binary string
    func toBinary(n) {
        if n == 0 {
            emit "0"
        }
        let result = ""
        let num = n
        while num > 0 {
            let bit = num % 2
            result = "" + bit + result
            num = num / 2
        }
        emit result
    }

    // Convert binary string to integer
    func fromBinary(s) {
        let result = 0
        let i = 0
        while i < len(s) {
            result = result * 2
            if s[i] == "1" {
                result = result + 1
            }
            i += 1
        }
        emit result
    }

    // Convert integer to hexadecimal string
    func toHex(n) {
        if n == 0 {
            emit "0"
        }
        let hexChars = "0123456789abcdef"
        let result = ""
        let num = n
        while num > 0 {
            let digit = num % 16
            result = hexChars[digit] + result
            num = num / 16
        }
        emit result
    }

    // Convert hexadecimal string to integer
    func fromHex(s) {
        let result = 0
        let i = 0
        while i < len(s) {
            result = result * 16
            let ch = s[i]
            if ch >= "0" {
                if ch <= "9" {
                    result = result + toInt(ch) - toInt("0")
                }
            }
            if ch >= "a" {
                if ch <= "f" {
                    result = result + toInt(ch) - toInt("a") + 10
                }
            }
            if ch >= "A" {
                if ch <= "F" {
                    result = result + toInt(ch) - toInt("A") + 10
                }
            }
            i += 1
        }
        emit result
    }

    // Convert integer to octal string
    func toOctal(n) {
        if n == 0 {
            emit "0"
        }
        let result = ""
        let num = n
        while num > 0 {
            let digit = num % 8
            result = "" + digit + result
            num = num / 8
        }
        emit result
    }

    // Convert a character to its string representation
    func charToStr(ch) {
        emit "" + ch
    }

    // Convert boolean-like value to string
    func boolToStr(val) {
        if val {
            emit "true"
        }
        emit "false"
    }

    // Convert string to all-lowercase representation
    // (simple version for ASCII a-z)
    func toLowerStr(s) {
        let sb = sbNew()
        let upperAlpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let lowerAlpha = "abcdefghijklmnopqrstuvwxyz"
        let i = 0
        while i < len(s) {
            let ch = s[i]
            let found = 0
            let j = 0
            while j < 26 {
                if ch == upperAlpha[j] {
                    sb = sbAppend(sb, lowerAlpha[j])
                    found = 1
                    break
                }
                j += 1
            }
            if found == 0 {
                sb = sbAppend(sb, ch)
            }
            i += 1
        }
        emit sbToString(sb)
    }

    // Convert number to string with sign prefix
    func toSignedStr(n) {
        if n > 0 {
            emit "+" + n
        }
        emit "" + n
    }
}
