// wc - Word count tool
// Counts lines, words, and characters in a file

func countWords(text) {
    let wc = 0
    let inWord = 0
    let i = 0
    while i < len(text) {
        let ch = text[i]
        if ch == " " || ch == "\n" || ch == "\t" {
            if inWord {
                wc = wc + 1
                inWord = 0
            }
        } else {
            inWord = 1
        }
        i = i + 1
    }
    if inWord { wc = wc + 1 }
    emit wc
}

just run {
    if argCount() < 1 {
        print("Usage: wc <file>")
    } else {
        let filename = arg(0)
        let content = readFile(filename)
        let lines = lineCount(content)
        let words = countWords(content)
        let chars = len(content)
        print("  " + lines + "  " + words + "  " + chars + "  " + filename)
    }
}
