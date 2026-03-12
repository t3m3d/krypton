// Input validation utilities for Krypton
// Functions to validate strings and values

go validate {

    // Check if string is a valid integer
    func isValidInt(s) {
        if len(s) == 0 {
            emit 0
        }
        let start = 0
        if s[0] == "-" {
            if len(s) == 1 {
                emit 0
            }
            start = 1
        }
        let i = start
        while i < len(s) {
            let ch = s[i]
            if ch < "0" {
                emit 0
            }
            if ch > "9" {
                emit 0
            }
            i = i + 1
        }
        emit 1
    }

    // Check if string is non-empty
    func isNonEmpty(s) {
        if len(s) > 0 {
            emit 1
        }
        emit 0
    }

    // Check if string contains only whitespace
    func isBlank(s) {
        let i = 0
        while i < len(s) {
            let ch = s[i]
            if ch != " " {
                if ch != "\t" {
                    if ch != "\n" {
                        if ch != "\r" {
                            emit 0
                        }
                    }
                }
            }
            i = i + 1
        }
        emit 1
    }

    // Check if string is a valid identifier (letter/underscore start, alphanumeric)
    func isValidIdent(s) {
        if len(s) == 0 {
            emit 0
        }
        let first = s[0]
        if first != "_" {
            if first < "A" { emit 0 }
            if first > "z" { emit 0 }
            if first > "Z" {
                if first < "a" {
                    emit 0
                }
            }
        }
        let i = 1
        while i < len(s) {
            let ch = s[i]
            if ch == "_" {
                i = i + 1
            } else if ch >= "0" {
                if ch <= "9" {
                    i = i + 1
                } else if ch >= "A" {
                    if ch <= "z" {
                        i = i + 1
                    } else {
                        emit 0
                    }
                } else {
                    emit 0
                }
            } else if ch >= "A" {
                if ch <= "z" {
                    i = i + 1
                } else {
                    emit 0
                }
            } else {
                emit 0
            }
        }
        emit 1
    }

    // Check if string length is within bounds
    func isLengthBetween(s, minLen, maxLen) {
        let sLen = len(s)
        if sLen >= minLen {
            if sLen <= maxLen {
                emit 1
            }
        }
        emit 0
    }

    // Check if a number is in range [lo, hi]
    func isInRange(n, lo, hi) {
        if n >= lo {
            if n <= hi {
                emit 1
            }
        }
        emit 0
    }

    // Check if a string looks like a file path
    func isFilePath(s) {
        if len(s) == 0 {
            emit 0
        }
        // Check for common path patterns
        let i = 0
        let hasDot = 0
        let hasSlash = 0
        while i < len(s) {
            if s[i] == "." {
                hasDot = 1
            }
            if s[i] == "/" {
                hasSlash = 1
            }
            if s[i] == "\\" {
                hasSlash = 1
            }
            i = i + 1
        }
        if hasDot {
            emit 1
        }
        if hasSlash {
            emit 1
        }
        emit 0
    }

    // Validate that all characters are printable ASCII
    func isPrintableAscii(s) {
        let i = 0
        while i < len(s) {
            let ch = s[i]
            if ch < " " {
                if ch != "\t" {
                    if ch != "\n" {
                        emit 0
                    }
                }
            }
            i = i + 1
        }
        emit 1
    }
}
