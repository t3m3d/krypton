// File processing utilities for Krypton
// Higher-level file operations

go file_utils {

    // Count words in file content
    func countWords(content) {
        let cnt = 0
        let inWord = 0
        let i = 0
        while i < len(content) {
            let ch = content[i]
            if ch == " " {
                if inWord {
                    cnt += 1
                    inWord = 0
                }
            } else if ch == "\n" {
                if inWord {
                    cnt += 1
                    inWord = 0
                }
            } else if ch == "\t" {
                if inWord {
                    cnt += 1
                    inWord = 0
                }
            } else {
                inWord = 1
            }
            i += 1
        }
        if inWord {
            cnt += 1
        }
        emit cnt
    }

    // Count characters in file content (excluding newlines)
    func countChars(content) {
        let cnt = 0
        let i = 0
        while i < len(content) {
            if content[i] != "\n" {
                if content[i] != "\r" {
                    cnt += 1
                }
            }
            i += 1
        }
        emit cnt
    }

    // Get file extension from a filename
    func getExtension(filename) {
        let i = len(filename) - 1
        while i >= 0 {
            if filename[i] == "." {
                emit substring(filename, i + 1, len(filename))
            }
            i -= 1
        }
        emit ""
    }

    // Get basename from a file path
    func getBasename(path) {
        let i = len(path) - 1
        while i >= 0 {
            if path[i] == "/" {
                emit substring(path, i + 1, len(path))
            }
            if path[i] == "\\" {
                emit substring(path, i + 1, len(path))
            }
            i -= 1
        }
        emit path
    }

    // Get directory from a file path
    func getDirectory(path) {
        let i = len(path) - 1
        while i >= 0 {
            if path[i] == "/" {
                emit substring(path, 0, i)
            }
            if path[i] == "\\" {
                emit substring(path, 0, i)
            }
            i -= 1
        }
        emit "."
    }

    // Process file line by line and count non-empty lines
    func countNonEmptyLines(content) {
        let cnt = 0
        let lines = lineCount(content)
        let i = 0
        while i < lines {
            let line = getLine(content, i)
            if len(line) > 0 {
                cnt += 1
            }
            i += 1
        }
        emit cnt
    }

    // Get longest line length
    func longestLineLength(content) {
        let maxLen = 0
        let lines = lineCount(content)
        let i = 0
        while i < lines {
            let line = getLine(content, i)
            if len(line) > maxLen {
                maxLen = len(line)
            }
            i += 1
        }
        emit maxLen
    }

    // Extract first N lines from content
    func headLines(content, n) {
        let sb = sbNew()
        let lines = lineCount(content)
        let limit = n
        if limit > lines {
            limit = lines
        }
        let i = 0
        while i < limit {
            sb = sbAppend(sb, getLine(content, i))
            sb = sbAppend(sb, "\n")
            i += 1
        }
        emit sbToString(sb)
    }

    // Extract last N lines from content
    func tailLines(content, n) {
        let sb = sbNew()
        let lines = lineCount(content)
        let start = lines - n
        if start < 0 {
            start = 0
        }
        let i = start
        while i < lines {
            sb = sbAppend(sb, getLine(content, i))
            sb = sbAppend(sb, "\n")
            i += 1
        }
        emit sbToString(sb)
    }
}
