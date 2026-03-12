// Tutorial 19: Pattern Matching with startsWith
// Using startsWith for simple pattern matching

func classify(line) {
    if startsWith(line, "//") {
        emit "comment"
    } else if startsWith(line, "func ") || startsWith(line, "fn ") {
        emit "function"
    } else if startsWith(line, "let ") {
        emit "variable"
    } else if startsWith(line, "if ") {
        emit "conditional"
    } else if startsWith(line, "while ") {
        emit "loop"
    } else if startsWith(line, "print(") || startsWith(line, "kp(") {
        emit "output"
    } else {
        emit "other"
    }
}

just run {
    let code = "// A sample\nfunc add(a, b) {\nlet x = 5\nif x > 3 {\nprint(x)\nwhile x > 0 {\n}\n"
    let lc = lineCount(code)
    let i = 0
    while i < lc {
        let line = getLine(code, i)
        let kind = classify(line)
        print("[" + kind + "] " + line)
        i = i + 1
    }
}
