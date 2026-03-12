// Word counter - counts words, lines, and characters in a file

func countWords(text) {
    let cnt = 0
    let inWord = 0
    let i = 0
    while i < len(text) {
        let ch = text[i]
        if ch == " " {
            if inWord { cnt = cnt + 1; inWord = 0 }
        } else if ch == "\n" {
            if inWord { cnt = cnt + 1; inWord = 0 }
        } else if ch == "\t" {
            if inWord { cnt = cnt + 1; inWord = 0 }
        } else {
            inWord = 1
        }
        i = i + 1
    }
    if inWord {
        cnt = cnt + 1
    }
    emit cnt
}

func countLines(text) {
    let cnt = 0
    let i = 0
    while i < len(text) {
        if text[i] == "\n" {
            cnt = cnt + 1
        }
        i = i + 1
    }
    emit cnt
}

just run {
    if argCount() < 1 {
        kp("Usage: kcc word_count.k <filename>")
        emit "error"
    }
    let filename = arg(0)
    let content = readFile(filename)

    let chars = len(content)
    let words = countWords(content)
    let lines = countLines(content)

    kp("File: " + filename)
    kp("  Lines:      " + lines)
    kp("  Words:      " + words)
    kp("  Characters: " + chars)
    emit "ok"
}
