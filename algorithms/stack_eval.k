// Stack-based expression evaluator
// Evaluates simple postfix (RPN) expressions

func stackNew() { emit "" }

func stackPush(stack, val) {
    if len(stack) == 0 { emit val }
    emit stack + "," + val
}

func stackPop(stack) {
    // Returns "value|rest"
    let n = count(stack)
    let top = split(stack, n - 1)
    let sb = sbNew()
    let i = 0
    while i < n - 1 {
        if i > 0 { sb = sbAppend(sb, ",") }
        sb = sbAppend(sb, split(stack, i))
        i += 1
    }
    emit top + "|" + sbToString(sb)
}

func getVal(popResult) {
    let i = 0
    while i < len(popResult) {
        if popResult[i] == "|" {
            emit substring(popResult, 0, i)
        }
        i += 1
    }
    emit popResult
}

func getRest(popResult) {
    let i = 0
    while i < len(popResult) {
        if popResult[i] == "|" {
            emit substring(popResult, i + 1, len(popResult))
        }
        i += 1
    }
    emit ""
}

func evalRPN(tokens) {
    let stack = stackNew()
    let n = count(tokens)
    let i = 0
    while i < n {
        let tok = split(tokens, i)
        if tok == "+" || tok == "-" || tok == "*" || tok == "/" {
            let r1 = stackPop(stack)
            let b = toInt(getVal(r1))
            stack = getRest(r1)
            let r2 = stackPop(stack)
            let a = toInt(getVal(r2))
            stack = getRest(r2)
            if tok == "+" { stack = stackPush(stack, "" + (a + b)) }
            if tok == "-" { stack = stackPush(stack, "" + (a - b)) }
            if tok == "*" { stack = stackPush(stack, "" + (a * b)) }
            if tok == "/" { stack = stackPush(stack, "" + (a / b)) }
        } else {
            stack = stackPush(stack, tok)
        }
        i += 1
    }
    let final = stackPop(stack)
    emit getVal(final)
}

just run {
    // "3 4 + 2 *" = (3+4)*2 = 14
    let expr1 = "3,4,+,2,*"
    print(expr1 + " = " + evalRPN(expr1))

    // "5 1 2 + 4 * + 3 -" = 5+((1+2)*4)-3 = 14
    let expr2 = "5,1,2,+,4,*,+,3,-"
    print(expr2 + " = " + evalRPN(expr2))

    // "2 3 * 4 5 * +" = 6+20 = 26
    let expr3 = "2,3,*,4,5,*,+"
    print(expr3 + " = " + evalRPN(expr3))
}
