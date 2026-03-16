// Simple calculator - evaluates basic arithmetic expressions
// Supports +, -, *, / on integer operands

func isDigit(ch) {
    if ch >= "0" {
        if ch <= "9" {
            emit 1
        }
    }
    emit 0
}

func readNumber(expr, pos) {
    let start = pos
    while pos < len(expr) {
        if isDigit(expr[pos]) == 0 {
            break
        }
        pos += 1
    }
    emit substring(expr, start, pos) + "," + pos
}

func skipSpaces(expr, pos) {
    while pos < len(expr) {
        if expr[pos] != " " {
            break
        }
        pos += 1
    }
    emit pos
}

func evaluate(expr) {
    // Simple left-to-right evaluation: num op num op num ...
    let pos = 0
    pos = skipSpaces(expr, pos)

    let pair = readNumber(expr, pos)
    let result = toInt(pairVal(pair))
    pos = pairPos(pair)

    while pos < len(expr) {
        pos = skipSpaces(expr, pos)
        if pos >= len(expr) {
            break
        }
        let op = expr[pos]
        pos += 1
        pos = skipSpaces(expr, pos)

        let pair2 = readNumber(expr, pos)
        let operand = toInt(pairVal(pair2))
        pos = pairPos(pair2)

        if op == "+" {
            result = result + operand
        } else if op == "-" {
            result = result - operand
        } else if op == "*" {
            result = result * operand
        } else if op == "/" {
            if operand != 0 {
                result = result / operand
            } else {
                kp("Error: division by zero")
                emit "error"
            }
        }
    }
    emit result
}

just run {
    kp("Simple Calculator")
    kp("=================")

    let expressions = "2 + 3,10 - 4,6 * 7,100 / 5,15 + 20 - 3,2 * 3 + 4"
    let total = count(expressions)
    let i = 0
    while i < total {
        let expr = split(expressions, i)
        let result = evaluate(expr)
        kp("  " + expr + " = " + result)
        i += 1
    }
    emit "ok"
}
