// Bracket balance checker
// Verifies that brackets/parentheses are properly matched

func isOpen(ch) {
    if ch == "(" { emit 1 }
    if ch == "[" { emit 1 }
    if ch == "{" { emit 1 }
    emit 0
}

func isClose(ch) {
    if ch == ")" { emit 1 }
    if ch == "]" { emit 1 }
    if ch == "}" { emit 1 }
    emit 0
}

func matches(open, close) {
    if open == "(" { if close == ")" { emit 1 } }
    if open == "[" { if close == "]" { emit 1 } }
    if open == "{" { if close == "}" { emit 1 } }
    emit 0
}

func checkBrackets(s) {
    // Use a string as a stack
    let stack = ""
    let stackSize = 0
    let i = 0
    while i < len(s) {
        let ch = s[i]
        if isOpen(ch) {
            stack = stack + ch
            stackSize = stackSize + 1
        } else if isClose(ch) {
            if stackSize == 0 {
                emit "Unmatched closing '" + ch + "' at position " + i
            }
            let top = stack[stackSize - 1]
            if matches(top, ch) == 0 {
                emit "Mismatch: '" + top + "' at top vs '" + ch + "' at position " + i
            }
            stack = substring(stack, 0, stackSize - 1)
            stackSize = stackSize - 1
        }
        i = i + 1
    }
    if stackSize > 0 {
        emit "Unclosed brackets: " + stackSize + " remaining"
    }
    emit "Balanced"
}

just run {
    kp("Bracket Balance Checker")
    kp("=======================")
    kp("")

    let tests = "(),([]),{[()]},((()),([)],((,)(,{[}],func test() { if (x) { emit y } },let a = (1 + (2 * 3))"
    let total = count(tests)
    let i = 0
    while i < total {
        let expr = split(tests, i)
        let result = checkBrackets(expr)
        let label = expr
        while len(label) < 40 {
            label = label + " "
        }
        kp("  " + label + " => " + result)
        i = i + 1
    }
    emit "ok"
}
