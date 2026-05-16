// String utility functions for Krypton
// Provides string operations that *aren't* covered by built-in functions.
//
// Builtins to use directly (don't reimplement; they shadow user funcs of
// the same name in the IR dispatch and would silently win):
//   repeat(s, n)       endsWith(s, suf)   reverse(s)
//   contains(s, sub)   trim(s)            replace(s, old, new)
//   toUpper(s)         toLower(s)         indexOf(s, sub)
//   substring(s, lo, hi)                  startsWith(s, pfx)

module string_utils


// Pad a string on the left to reach target length.
// Native builtin equivalent: none.
func padLeft(s, targetLen, padChar) {
    let result = s
    while len(result) < targetLen {
        let sb = sbNew()
        sb = sbAppend(sb, padChar)
        sb = sbAppend(sb, result)
        result = sbToString(sb)
    }
    emit result
}

// Pad a string on the right to reach target length.
func padRight(s, targetLen, padChar) {
    let result = s
    while len(result) < targetLen {
        let sb = sbNew()
        sb = sbAppend(sb, result)
        sb = sbAppend(sb, padChar)
        result = sbToString(sb)
    }
    emit result
}

// Trim leading whitespace only.
// Native builtin trim(s) does both ends; use this when you need just one.
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
        i += 1
    }
    emit ""
}

// Trim trailing whitespace only.
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
        i -= 1
    }
    emit ""
}

// Count occurrences of a substring in a string.
// Native builtin equivalent: none.
func countOccurrences(s, sub) {
    let cnt = 0
    let sLen = len(s)
    let subLen = len(sub)
    if subLen == 0 { emit 0 }
    let i = 0
    while i <= sLen - subLen {
        if substring(s, i, i + subLen) == sub {
            cnt += 1
            i = i + subLen
        } else {
            i += 1
        }
    }
    emit cnt
}

// Join a comma-separated list with a delimiter.
// Native builtin equivalent: none.
func join(list, delim) {
    let sb = sbNew()
    let total = count(list)
    let i = 0
    while i < total {
        if i > 0 { sb = sbAppend(sb, delim) }
        sb = sbAppend(sb, split(list, i))
        i += 1
    }
    emit sbToString(sb)
}
