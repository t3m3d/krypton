// Line-based operations for Krypton
// Operates on newline-delimited text

module lines


// Filter out empty lines
func filterEmpty(text) {
    let sb = sbNew()
    let total = lineCount(text)
    let i = 0
    while i < total {
        let line = getLine(text, i)
        if len(line) > 0 {
            sb = sbAppend(sb, line)
            sb = sbAppend(sb, "\n")
        }
        i += 1
    }
    emit sbToString(sb)
}

// Remove duplicate lines
func unique(text) {
    let sb = sbNew()
    let seen = ""
    let total = lineCount(text)
    let i = 0
    while i < total {
        let line = getLine(text, i)
        let found = 0
        if seen != "" {
            let seenSize = count(seen)
            let j = 0
            while j < seenSize {
                if split(seen, j) == line {
                    found = 1
                    break
                }
                j += 1
            }
        }
        if found == 0 {
            sb = sbAppend(sb, line)
            sb = sbAppend(sb, "\n")
            if seen == "" {
                seen = line
            } else {
                seen = seen + "," + line
            }
        }
        i += 1
    }
    emit sbToString(sb)
}

// Reverse the order of lines
func reverseLines(text) {
    let sb = sbNew()
    let total = lineCount(text)
    let i = total - 1
    while i >= 0 {
        sb = sbAppend(sb, getLine(text, i))
        sb = sbAppend(sb, "\n")
        i -= 1
    }
    emit sbToString(sb)
}

// Take first n lines
func takeLines(text, n) {
    let sb = sbNew()
    let total = lineCount(text)
    let limit = n
    if limit > total {
        limit = total
    }
    let i = 0
    while i < limit {
        sb = sbAppend(sb, getLine(text, i))
        sb = sbAppend(sb, "\n")
        i += 1
    }
    emit sbToString(sb)
}

// Drop first n lines
func dropLines(text, n) {
    let sb = sbNew()
    let total = lineCount(text)
    let i = n
    while i < total {
        sb = sbAppend(sb, getLine(text, i))
        sb = sbAppend(sb, "\n")
        i += 1
    }
    emit sbToString(sb)
}

// Count lines matching a prefix
func countMatching(text, prefix) {
    let cnt = 0
    let total = lineCount(text)
    let i = 0
    while i < total {
        if startsWith(getLine(text, i), prefix) {
            cnt += 1
        }
        i += 1
    }
    emit cnt
}

// Join all lines into single string with separator
func joinLines(text, sep) {
    let sb = sbNew()
    let total = lineCount(text)
    let i = 0
    while i < total {
        if i > 0 {
            sb = sbAppend(sb, sep)
        }
        sb = sbAppend(sb, getLine(text, i))
        i += 1
    }
    emit sbToString(sb)
}

// Get line at index (safe, returns "" for out of bounds)
func safeGetLine(text, idx) {
    let total = lineCount(text)
    if idx < 0 {
        emit ""
    }
    if idx >= total {
        emit ""
    }
    emit getLine(text, idx)
}

// Find first line containing substring
func findLine(text, needle) {
    let total = lineCount(text)
    let nLen = len(needle)
    let i = 0
    while i < total {
        let line = getLine(text, i)
        let j = 0
        while j <= len(line) - nLen {
            if substring(line, j, j + nLen) == needle {
                emit i
            }
            j += 1
        }
        i += 1
    }
    emit 0 - 1
}
