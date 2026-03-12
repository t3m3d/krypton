// String utility functions for Krypton
// Provides common string manipulation operations

go string_utils {

    // Repeat a string n times
    func repeat(s, n) {
        let result = ""
        let i = 0
        while i < n {
            result = result + s
            i = i + 1
        }
        emit result
    }

    // Pad a string on the left to reach target length
    func padLeft(s, targetLen, padChar) {
        let result = s
        while len(result) < targetLen {
            result = padChar + result
        }
        emit result
    }

    // Pad a string on the right to reach target length
    func padRight(s, targetLen, padChar) {
        let result = s
        while len(result) < targetLen {
            result = result + padChar
        }
        emit result
    }

    // Check if a string contains a substring
    func contains(haystack, needle) {
        let hLen = len(haystack)
        let nLen = len(needle)
        if nLen > hLen {
            emit 0
        }
        let i = 0
        while i <= hLen - nLen {
            if substring(haystack, i, i + nLen) == needle {
                emit 1
            }
            i = i + 1
        }
        emit 0
    }

    // Check if a string ends with a suffix
    func endsWith(s, suffix) {
        let sLen = len(s)
        let sufLen = len(suffix)
        if sufLen > sLen {
            emit 0
        }
        if substring(s, sLen - sufLen, sLen) == suffix {
            emit 1
        }
        emit 0
    }

    // Convert a string to uppercase (ASCII only)
    func toUpper(s) {
        let sb = sbNew()
        let i = 0
        while i < len(s) {
            let ch = s[i]
            if ch >= "a" {
                if ch <= "z" {
                    // Convert lowercase to uppercase
                    let code = toInt(ch) - 32
                    sb = sbAppend(sb, substring("ABCDEFGHIJKLMNOPQRSTUVWXYZ", code - 65, code - 64))
                } else {
                    sb = sbAppend(sb, ch)
                }
            } else {
                sb = sbAppend(sb, ch)
            }
            i = i + 1
        }
        emit sbToString(sb)
    }

    // Trim leading whitespace
    func trimLeft(s) {
        let i = 0
        while i < len(s) {
            let ch = s[i]
            if ch != " " {
                if ch != "\t" {
                    if ch != "\n" {
                        if ch != "\r" {
                            emit substring(s, i, len(s))
                        }
                    }
                }
            }
            i = i + 1
        }
        emit ""
    }

    // Trim trailing whitespace
    func trimRight(s) {
        let i = len(s) - 1
        while i >= 0 {
            let ch = s[i]
            if ch != " " {
                if ch != "\t" {
                    if ch != "\n" {
                        if ch != "\r" {
                            emit substring(s, 0, i + 1)
                        }
                    }
                }
            }
            i = i - 1
        }
        emit ""
    }

    // Trim whitespace from both ends
    func trim(s) {
        emit trimRight(trimLeft(s))
    }

    // Replace all occurrences of old with new in s
    func replaceAll(s, old, new) {
        let sb = sbNew()
        let sLen = len(s)
        let oldLen = len(old)
        let i = 0
        while i < sLen {
            if i + oldLen <= sLen {
                if substring(s, i, i + oldLen) == old {
                    sb = sbAppend(sb, new)
                    i = i + oldLen
                } else {
                    sb = sbAppend(sb, s[i])
                    i = i + 1
                }
            } else {
                sb = sbAppend(sb, s[i])
                i = i + 1
            }
        }
        emit sbToString(sb)
    }

    // Count occurrences of a substring
    func countOccurrences(s, sub) {
        let cnt = 0
        let sLen = len(s)
        let subLen = len(sub)
        let i = 0
        while i <= sLen - subLen {
            if substring(s, i, i + subLen) == sub {
                cnt = cnt + 1
                i = i + subLen
            } else {
                i = i + 1
            }
        }
        emit cnt
    }

    // Reverse a string
    func reverse(s) {
        let sb = sbNew()
        let i = len(s) - 1
        while i >= 0 {
            sb = sbAppend(sb, s[i])
            i = i - 1
        }
        emit sbToString(sb)
    }

    // Join a comma-separated list with a delimiter
    func join(list, delim) {
        let sb = sbNew()
        let total = count(list)
        let i = 0
        while i < total {
            if i > 0 {
                sb = sbAppend(sb, delim)
            }
            sb = sbAppend(sb, split(list, i))
            i = i + 1
        }
        emit sbToString(sb)
    }
}
