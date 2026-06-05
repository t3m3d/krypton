// Text processing utilities for Krypton
// Advanced string/text manipulation

module text


// Split text into words (by whitespace)
func words(text) {
    let result = ""
    let sb = sbNew()
    let i = 0
    while i < len(text) {
        let ch = text[i]
        if ch == " " {
            let word = sbToString(sb)
            if len(word) > 0 {
                if result == "" {
                    result = word
                } else {
                    result = result + "," + word
                }
            }
            sb = sbNew()
        } else if ch == "\n" {
            let word = sbToString(sb)
            if len(word) > 0 {
                if result == "" {
                    result = word
                } else {
                    result = result + "," + word
                }
            }
            sb = sbNew()
        } else if ch == "\t" {
            let word = sbToString(sb)
            if len(word) > 0 {
                if result == "" {
                    result = word
                } else {
                    result = result + "," + word
                }
            }
            sb = sbNew()
        } else {
            sb = sbAppend(sb, ch)
        }
        i += 1
    }
    let last = sbToString(sb)
    if len(last) > 0 {
        if result == "" {
            result = last
        } else {
            result = result + "," + last
        }
    }
    emit result
}

// Count words in text
func wordCount(text) {
    let w = words(text)
    if w == "" {
        emit 0
    }
    emit count(w)
}

// Wrap text at specified width
func wordWrap(text, width) {
    let sb = sbNew()
    let lineLen = 0
    let i = 0
    while i < len(text) {
        let ch = text[i]
        if ch == "\n" {
            sb = sbAppend(sb, "\n")
            lineLen = 0
        } else if lineLen >= width {
            if ch == " " {
                sb = sbAppend(sb, "\n")
                lineLen = 0
            } else {
                sb = sbAppend(sb, ch)
                lineLen = lineLen + 1
            }
        } else {
            sb = sbAppend(sb, ch)
            lineLen = lineLen + 1
        }
        i += 1
    }
    emit sbToString(sb)
}

// Indent every line by n spaces
func indent(text, n) {
    let prefix = ""
    let i = 0
    while i < n {
        prefix = prefix + " "
        i += 1
    }
    let sb = sbNew()
    let lines = lineCount(text)
    i = 0
    while i < lines {
        sb = sbAppend(sb, prefix)
        sb = sbAppend(sb, getLine(text, i))
        sb = sbAppend(sb, "\n")
        i += 1
    }
    emit sbToString(sb)
}

// Remove leading whitespace from each line
func dedent(text) {
    let sb = sbNew()
    let lines = lineCount(text)
    let i = 0
    while i < lines {
        let line = getLine(text, i)
        let j = 0
        while j < len(line) {
            if line[j] != " " {
                if line[j] != "\t" {
                    break
                }
            }
            j += 1
        }
        sb = sbAppend(sb, substring(line, j, len(line)))
        sb = sbAppend(sb, "\n")
        i += 1
    }
    emit sbToString(sb)
}

// Number each line
func numberLines(text) {
    let sb = sbNew()
    let lines = lineCount(text)
    let i = 0
    while i < lines {
        let num = i + 1
        let prefix = "" + num
        while len(prefix) < 4 {
            prefix = " " + prefix
        }
        sb = sbAppend(sb, prefix + " | ")
        sb = sbAppend(sb, getLine(text, i))
        sb = sbAppend(sb, "\n")
        i += 1
    }
    emit sbToString(sb)
}

// Extract lines matching a pattern prefix
func grepPrefix(text, prefix) {
    let sb = sbNew()
    let lines = lineCount(text)
    let i = 0
    while i < lines {
        let line = getLine(text, i)
        if startsWith(line, prefix) {
            sb = sbAppend(sb, line)
            sb = sbAppend(sb, "\n")
        }
        i += 1
    }
    emit sbToString(sb)
}

// Split into paragraphs — separated by one or more blank lines.
// Returns "\x01"-joined paragraphs (Krypton has no nested lists);
// callers can split on chr(1) to iterate.
func paragraphs(text) {
    let out = sbNew()
    let lines = lineCount(text)
    let current = sbNew()
    let any = 0
    let inPara = 0
    let i = 0
    while i < lines {
        let line = getLine(text, i)
        if len(trim(line)) == 0 {
            if inPara == 1 {
                if any == 1 { out = sbAppend(out, fromCharCode(1)) }
                out = sbAppend(out, sbToString(current))
                any = 1
                current = sbNew()
                inPara = 0
            }
        } else {
            if inPara == 1 { current = sbAppend(current, "\n") }
            current = sbAppend(current, line)
            inPara = 1
        }
        i = i + 1
    }
    if inPara == 1 {
        if any == 1 { out = sbAppend(out, fromCharCode(1)) }
        out = sbAppend(out, sbToString(current))
    }
    emit sbToString(out)
}

// Number of paragraphs in `text` (treats blank lines as separators).
func paragraphCount(text) {
    let ps = paragraphs(text)
    if len(ps) == 0 { emit 0 }
    let n = 1
    let i = 0
    while i < len(ps) {
        if toInt(charCode(ps[i])) == 1 { n = n + 1 }
        i = i + 1
    }
    emit n
}

// Reverse word order in a sentence (delim = single space).
//   reverseWords("the quick brown fox") → "fox brown quick the"
func reverseWords(text) {
    let ws = words(text)
    let n = count(ws)
    let out = sbNew()
    let i = n - 1
    let any = 0
    while i >= 0 {
        if any == 1 { out = sbAppend(out, " ") }
        out = sbAppend(out, split(ws, i))
        any = 1
        i = i - 1
    }
    emit sbToString(out)
}

// Count characters that are letters (ASCII a-z + A-Z).
func letterCount(text) {
    let n = len(text)
    let i = 0
    let cnt = 0
    while i < n {
        let c = text[i]
        if (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") {
            cnt = cnt + 1
        }
        i = i + 1
    }
    emit cnt
}
