// Tokenizer from compile.k (extracted for testing)

func readNumber(src, pos) {
    let start = pos
    while pos < len(src) && src[pos] >= "0" && src[pos] <= "9" {
        pos += 1
    }
    emit substring(src, start, pos) + "," + pos
}

func readString(src, pos) {
    let result = ""
    pos += 1
    while pos < len(src) && src[pos] != "\"" {
        if src[pos] == "\\" && pos + 1 < len(src) {
            result = result + src[pos] + src[pos + 1]
            pos = pos + 2
        } else {
            result = result + src[pos]
            pos += 1
        }
    }
    if pos < len(src) {
        pos += 1
    }
    emit result + "," + pos
}

func readIdent(src, pos) {
    let start = pos
    while pos < len(src) {
        let ch = src[pos]
        if (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || (ch >= "0" && ch <= "9") || ch == "_" {
            pos += 1
        } else {
            emit substring(src, start, pos) + "," + pos
        }
    }
    emit substring(src, start, pos) + "," + pos
}

func findLastComma(s) {
    let i = len(s) - 1
    while i >= 0 {
        if s[i] == "," {
            emit i
        }
        i -= 1
    }
    emit -1
}

func pairVal(pair) {
    let c = findLastComma(pair)
    if c < 0 {
        emit pair
    }
    emit substring(pair, 0, c)
}

func pairPos(pair) {
    let c = findLastComma(pair)
    emit toInt(substring(pair, c + 1, len(pair)))
}

func tokenize(src) {
    let tokens = ""
    let pos = 0
    let srcLen = len(src)
    while pos < srcLen {
        let ch = src[pos]
        // skip whitespace
        if ch == " " || ch == "\t" || ch == "\r" || ch == "\n" {
            pos += 1
        } else if ch == "/" && pos + 1 < srcLen && src[pos + 1] == "/" {
            while pos < srcLen && src[pos] != "\n" {
                pos += 1
            }
        } else if ch >= "0" && ch <= "9" {
            let np = readNumber(src, pos)
            tokens = tokens + "NUM:" + pairVal(np) + "\n"
            pos = pairPos(np)
        } else if ch == "\"" {
            let sp = readString(src, pos)
            tokens = tokens + "STR:" + pairVal(sp) + "\n"
            pos = pairPos(sp)
        } else if (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || ch == "_" {
            let ip = readIdent(src, pos)
            let word = pairVal(ip)
            if word == "let" || word == "if" || word == "else" || word == "while" || word == "func" || word == "emit" || word == "just" || word == "run" || word == "fn" {
                tokens = tokens + "KW:" + word + "\n"
            } else {
                tokens = tokens + "ID:" + word + "\n"
            }
            pos = pairPos(ip)
        } else if ch == "=" && pos + 1 < srcLen && src[pos + 1] == "=" {
            tokens = tokens + "OP:==\n"
            pos = pos + 2
        } else if ch == "!" && pos + 1 < srcLen && src[pos + 1] == "=" {
            tokens = tokens + "OP:!=\n"
            pos = pos + 2
        } else if ch == "<" && pos + 1 < srcLen && src[pos + 1] == "=" {
            tokens = tokens + "OP:<=\n"
            pos = pos + 2
        } else if ch == ">" && pos + 1 < srcLen && src[pos + 1] == "=" {
            tokens = tokens + "OP:>=\n"
            pos = pos + 2
        } else if ch == "&" && pos + 1 < srcLen && src[pos + 1] == "&" {
            tokens = tokens + "OP:&&\n"
            pos = pos + 2
        } else if ch == "|" && pos + 1 < srcLen && src[pos + 1] == "|" {
            tokens = tokens + "OP:||\n"
            pos = pos + 2
        } else if ch == "+" {
            tokens = tokens + "OP:+\n"
            pos += 1
        } else if ch == "-" {
            tokens = tokens + "OP:-\n"
            pos += 1
        } else if ch == "*" {
            tokens = tokens + "OP:*\n"
            pos += 1
        } else if ch == "/" {
            tokens = tokens + "OP:/\n"
            pos += 1
        } else if ch == "%" {
            tokens = tokens + "OP:%\n"
            pos += 1
        } else if ch == "<" {
            tokens = tokens + "OP:<\n"
            pos += 1
        } else if ch == ">" {
            tokens = tokens + "OP:>\n"
            pos += 1
        } else if ch == "=" {
            tokens = tokens + "OP:=\n"
            pos += 1
        } else if ch == "(" {
            tokens = tokens + "LPAREN\n"
            pos += 1
        } else if ch == ")" {
            tokens = tokens + "RPAREN\n"
            pos += 1
        } else if ch == "{" {
            tokens = tokens + "LBRACE\n"
            pos += 1
        } else if ch == "}" {
            tokens = tokens + "RBRACE\n"
            pos += 1
        } else if ch == "," {
            tokens = tokens + "COMMA\n"
            pos += 1
        } else if ch == "[" {
            tokens = tokens + "LBRACK\n"
            pos += 1
        } else if ch == "]" {
            tokens = tokens + "RBRACK\n"
            pos += 1
        } else if ch == ";" {
            pos += 1
        } else {
            pos += 1
        }
    }
    emit tokens
}

just run {
    let file = arg(0)
    kp("File: " + file)
    let source = readFile(file)
    kp("Source length: " + len(source))
    let tokens = tokenize(source)
    let ntoks = lineCount(tokens)
    kp("Token count: " + ntoks)
    emit "ok"
}
