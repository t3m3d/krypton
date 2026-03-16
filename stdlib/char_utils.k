// Character classification utilities for Krypton
// Functions to test character types

go char_utils {

    // Check if character is a digit (0-9)
    func isDigit(ch) {
        if ch >= "0" {
            if ch <= "9" {
                emit 1
            }
        }
        emit 0
    }

    // Check if character is a lowercase letter
    func isLower(ch) {
        if ch >= "a" {
            if ch <= "z" {
                emit 1
            }
        }
        emit 0
    }

    // Check if character is an uppercase letter
    func isUpper(ch) {
        if ch >= "A" {
            if ch <= "Z" {
                emit 1
            }
        }
        emit 0
    }

    // Check if character is a letter (a-z or A-Z)
    func isAlpha(ch) {
        if isLower(ch) {
            emit 1
        }
        if isUpper(ch) {
            emit 1
        }
        emit 0
    }

    // Check if character is alphanumeric
    func isAlphaNum(ch) {
        if isAlpha(ch) {
            emit 1
        }
        if isDigit(ch) {
            emit 1
        }
        emit 0
    }

    // Check if character is whitespace
    func isWhitespace(ch) {
        if ch == " " {
            emit 1
        }
        if ch == "\t" {
            emit 1
        }
        if ch == "\n" {
            emit 1
        }
        if ch == "\r" {
            emit 1
        }
        emit 0
    }

    // Check if character is a punctuation mark
    func isPunct(ch) {
        if ch == "." { emit 1 }
        if ch == "," { emit 1 }
        if ch == "!" { emit 1 }
        if ch == "?" { emit 1 }
        if ch == ";" { emit 1 }
        if ch == ":" { emit 1 }
        if ch == "'" { emit 1 }
        if ch == "-" { emit 1 }
        if ch == "(" { emit 1 }
        if ch == ")" { emit 1 }
        if ch == "[" { emit 1 }
        if ch == "]" { emit 1 }
        if ch == "{" { emit 1 }
        if ch == "}" { emit 1 }
        emit 0
    }

    // Check if character is a hex digit
    func isHexDigit(ch) {
        if isDigit(ch) {
            emit 1
        }
        if ch >= "a" {
            if ch <= "f" {
                emit 1
            }
        }
        if ch >= "A" {
            if ch <= "F" {
                emit 1
            }
        }
        emit 0
    }

    // Check if character is an operator symbol
    func isOperator(ch) {
        if ch == "+" { emit 1 }
        if ch == "-" { emit 1 }
        if ch == "*" { emit 1 }
        if ch == "/" { emit 1 }
        if ch == "%" { emit 1 }
        if ch == "=" { emit 1 }
        if ch == "<" { emit 1 }
        if ch == ">" { emit 1 }
        if ch == "!" { emit 1 }
        if ch == "&" { emit 1 }
        if ch == "|" { emit 1 }
        emit 0
    }

    // Check if an entire string contains only digits
    func isNumeric(s) {
        if len(s) == 0 {
            emit 0
        }
        let i = 0
        while i < len(s) {
            if isDigit(s[i]) == 0 {
                emit 0
            }
            i += 1
        }
        emit 1
    }

    // Check if an entire string is alphabetic
    func isAlphabetic(s) {
        if len(s) == 0 {
            emit 0
        }
        let i = 0
        while i < len(s) {
            if isAlpha(s[i]) == 0 {
                emit 0
            }
            i += 1
        }
        emit 1
    }
}
