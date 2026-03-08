go lexer {

    func isDigit(c) {
        emit c >= "0" && c <= "9";
    }

    func isAlpha(c) {
        emit (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_";
    }

    func isAlphaNum(c) {
        emit isAlpha(c) || isDigit(c);
    }

    func isKeyword(word) {
        if word == "just" emit 1;
        else if word == "run" emit 1;
        else if word == "fn" emit 1;
        else if word == "let" emit 1;
        else if word == "emit" emit 1;
        else if word == "return" emit 1;
        else if word == "if" emit 1;
        else if word == "else" emit 1;
        else if word == "while" emit 1;
        else if word == "module" emit 1;
        else if word == "quantum" emit 1;
        else if word == "qpute" emit 1;
        else if word == "process" emit 1;
        else if word == "true" emit 1;
        else if word == "false" emit 1;
        else if word == "measure" emit 1;
        else if word == "prepare" emit 1;
        else if word == "int" emit 1;
        else if word == "float" emit 1;
        else if word == "bool" emit 1;
        else if word == "string" emit 1;
        else if word == "qbit" emit 1;
        else if word == "print" emit 1;
        else if word == "kp" emit 1;
        else emit 0;
    }

    func readNumber(text, i) {
        let n = "";
        while i < len(text) && isDigit(text[i]) {
            n = n + text[i];
            i = i + 1;
        }
        emit n + "," + i;
    }

    func readIdent(text, i) {
        let n = "";
        while i < len(text) && isAlphaNum(text[i]) {
            n = n + text[i];
            i = i + 1;
        }
        emit n + "," + i;
    }

    func readString(text, i) {
        let s = "";
        i = i + 1;
        while i < len(text) && text[i] != "\"" {
            s = s + text[i];
            i = i + 1;
        }
        emit s + "," + (i + 1);
    }

    func skipWhitespace(text, i) {
        while i < len(text) && (text[i] == " " || text[i] == "\n" || text[i] == "\t" || text[i] == "\r") {
            i = i + 1;
        }
        emit i;
    }
    func skipComment(text, i) {
        if i + 1 < len(text) && text[i] == "/" && text[i + 1] == "/" {
            while i < len(text) && text[i] != "\n" {
                i = i + 1;
            }
            emit i;
        }
        else if i + 1 < len(text) && text[i] == "/" && text[i + 1] == "*" {
            i = i + 2;
            while i + 1 < len(text) && (text[i] != "*" || text[i + 1] != "/") {
                i = i + 1;
            }
            emit i + 2;
        }
        else {
            emit i;
        }
    }

    func tokenize(text) {
        let out = "";
        let i = 0;

        while i < len(text) {
            let ci = skipWhitespace(text, i);
            i = ci;

            if i >= len(text) {
                break;
            }

            let c = text[i];

            if text[i] == "/" && i + 1 < len(text) && (text[i + 1] == "/" || text[i + 1] == "*") {
                let ci2 = skipComment(text, i);
                i = ci2;
            }
            else if isDigit(c) {
                let pair = readNumber(text, i);
                let num = split(pair, 0);
                let ni = split(pair, 1);
                out = out + "INT:" + num + "\n";
                i = toInt(ni);
            }
            else if c == "\"" {
                let pair = readString(text, i);
                let str = split(pair, 0);
                let ni = split(pair, 1);
                out = out + "STRING:" + str + "\n";
                i = toInt(ni);
            }
            else if isAlpha(c) {
                let pair = readIdent(text, i);
                let id = split(pair, 0);
                let ni = split(pair, 1);
                if isKeyword(id) {
                    out = out + "KW:" + id + "\n";
                }
                else {
                    out = out + "IDENT:" + id + "\n";
                }
                i = toInt(ni);
            }
            else if c == "+" {
                out = out + "PLUS\n";
                i = i + 1;
            }
            else if c == "-" {
                if i + 1 < len(text) && text[i + 1] == ">" {
                    out = out + "ARROW\n";
                    i = i + 2;
                }
                else {
                    out = out + "MINUS\n";
                    i = i + 1;
                }
            }
            else if c == "*" {
                out = out + "STAR\n";
                i = i + 1;
            }
            else if c == "/" {
                out = out + "SLASH\n";
                i = i + 1;
            }
            else if c == "(" {
                out = out + "LPAREN\n";
                i = i + 1;
            }
            else if c == ")" {
                out = out + "RPAREN\n";
                i = i + 1;
            }
            else if c == "{" {
                out = out + "LBRACE\n";
                i = i + 1;
            }
            else if c == "}" {
                out = out + "RBRACE\n";
                i = i + 1;
            }
            else if c == "[" {
                out = out + "LBRACK\n";
                i = i + 1;
            }
            else if c == "]" {
                out = out + "RBRACK\n";
                i = i + 1;
            }
            else if c == ":" {
                out = out + "COLON\n";
                i = i + 1;
            }
            else if c == ";" {
                out = out + "SEMI\n";
                i = i + 1;
            }
            else if c == "," {
                out = out + "COMMA\n";
                i = i + 1;
            }
            else if c == "=" {
                if i + 1 < len(text) && text[i + 1] == "=" {
                    out = out + "EQ\n";
                    i = i + 2;
                }
                else {
                    out = out + "ASSIGN\n";
                    i = i + 1;
                }
            }
            else if c == "!" {
                if i + 1 < len(text) && text[i + 1] == "=" {
                    out = out + "NEQ\n";
                    i = i + 2;
                }
                else {
                    out = out + "BANG\n";
                    i = i + 1;
                }
            }
            else if c == "<" {
                if i + 1 < len(text) && text[i + 1] == "=" {
                    out = out + "LTE\n";
                    i = i + 2;
                }
                else {
                    out = out + "LT\n";
                    i = i + 1;
                }
            }
            else if c == ">" {
                if i + 1 < len(text) && text[i + 1] == "=" {
                    out = out + "GTE\n";
                    i = i + 2;
                }
                else {
                    out = out + "GT\n";
                    i = i + 1;
                }
            }
            else if c == "&" {
                if i + 1 < len(text) && text[i + 1] == "&" {
                    out = out + "AND\n";
                    i = i + 2;
                }
                else {
                    i = i + 1;
                }
            }
            else if c == "|" {
                if i + 1 < len(text) && text[i + 1] == "|" {
                    out = out + "OR\n";
                    i = i + 2;
                }
                else {
                    i = i + 1;
                }
            }
            else {
                print("Unknown character: " + c);
                i = i + 1;
            }
        }

        emit out;
    }
}