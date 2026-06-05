// Character classification utilities for Krypton.
// Builtins to use directly (don't reimplement; the dispatcher routes calls
// of these names to native machine code regardless of any user definition):
//   isDigit(ch)   isAlpha(ch)
// This module ships the rest: case checks, alpha-num, whitespace, punct,
// operator, hex-digit, plus whole-string variants.

module char_utils


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

// ── Additional per-character predicates ──────────────────────────────

// ASCII printable: space (32) through tilde (126).
func isPrintable(ch) {
    if len(ch) == 0 { emit 0 }
    let c = toInt(charCode(ch))
    if c >= 32 && c <= 126 { emit 1 }
    emit 0
}

// ASCII control: 0..31 or 127 (DEL).
func isControl(ch) {
    if len(ch) == 0 { emit 0 }
    let c = toInt(charCode(ch))
    if c < 32 { emit 1 }
    if c == 127 { emit 1 }
    emit 0
}

// 7-bit ASCII (0..127).
func isAscii(ch) {
    if len(ch) == 0 { emit 0 }
    let c = toInt(charCode(ch))
    if c >= 0 && c <= 127 { emit 1 }
    emit 0
}

// English vowel (a, e, i, o, u — case-insensitive).
func isVowel(ch) {
    if len(ch) != 1 { emit 0 }
    let c = ch
    if c == "a" || c == "e" || c == "i" || c == "o" || c == "u" { emit 1 }
    if c == "A" || c == "E" || c == "I" || c == "O" || c == "U" { emit 1 }
    emit 0
}

// English consonant (alpha and not a vowel).
func isConsonant(ch) {
    if isAlpha(ch) == 0 { emit 0 }
    if isVowel(ch) == 1 { emit 0 }
    emit 1
}

// True iff ASCII digit OR underscore (typical identifier-cont char).
func isIdentCont(ch) {
    if len(ch) != 1 { emit 0 }
    if isAlphaNum(ch) == 1 { emit 1 }
    if ch == "_" { emit 1 }
    emit 0
}

// True iff char is a single-quote, double-quote, or backtick.
func isQuote(ch) {
    if len(ch) != 1 { emit 0 }
    if ch == "\"" || ch == "'" { emit 1 }
    if toInt(charCode(ch)) == 96 { emit 1 }   // backtick
    emit 0
}

// True iff char is a bracket: ( ) [ ] { }
func isBracket(ch) {
    if len(ch) != 1 { emit 0 }
    if ch == "(" || ch == ")" { emit 1 }
    if ch == "[" || ch == "]" { emit 1 }
    if ch == "{" || ch == "}" { emit 1 }
    emit 0
}
