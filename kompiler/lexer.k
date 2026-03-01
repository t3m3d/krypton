go lexer {

    func isDigit(c) {
        emit c >= "0" && c <= "9";
    }

    func isAlpha(c) {
        emit (c >= "a" && c <= "z") || (c >= "A" && c <= "Z");
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
        while i < len(text) && isAlpha(text[i]) {
            n = n + text[i];
            i = i + 1;
        }
        emit n + "," + i;
    }

    func tokenize(text) {
        let out = "";
        let i = 0;

        while i < len(text) {
            let c = text[i];

            if c == " " {
                i = i + 1;
            }
            else if isDigit(c) {
                let pair = readNumber(text, i);
                let num = split(pair, 0);
                let ni = split(pair, 1);
                out = out + "INT:" + num + "\n";
                i = toInt(ni);
            }
            else if isAlpha(c) {
                let pair = readIdent(text, i);
                let id = split(pair, 0);
                let ni = split(pair, 1);
                out = out + "IDENT:" + id + "\n";
                i = toInt(ni);
            }
            else if c == "+" {
                out = out + "PLUS\n";
                i = i + 1;
            }
            else if c == "-" {
                out = out + "MINUS\n";
                i = i + 1;
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
            else {
                print("Unknown character: " + c);
                i = i + 1;
            }
        }

        emit out;
    }
}