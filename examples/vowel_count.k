// Vowel and consonant counter
// Analyzes text for letter categories

func isVowel(ch) {
    if ch == "a" { emit 1 }
    if ch == "e" { emit 1 }
    if ch == "i" { emit 1 }
    if ch == "o" { emit 1 }
    if ch == "u" { emit 1 }
    if ch == "A" { emit 1 }
    if ch == "E" { emit 1 }
    if ch == "I" { emit 1 }
    if ch == "O" { emit 1 }
    if ch == "U" { emit 1 }
    emit 0
}

func isLetter(ch) {
    if ch >= "a" { if ch <= "z" { emit 1 } }
    if ch >= "A" { if ch <= "Z" { emit 1 } }
    emit 0
}

func analyzeText(text) {
    let vowels = 0
    let consonants = 0
    let digits = 0
    let spaces = 0
    let punct = 0
    let i = 0
    while i < len(text) {
        let ch = text[i]
        if isVowel(ch) {
            vowels = vowels + 1
        } else if isLetter(ch) {
            consonants = consonants + 1
        } else if ch >= "0" {
            if ch <= "9" {
                digits = digits + 1
            } else {
                punct = punct + 1
            }
        } else if ch == " " {
            spaces = spaces + 1
        } else {
            punct = punct + 1
        }
        i = i + 1
    }
    kp("  Vowels:     " + vowels)
    kp("  Consonants: " + consonants)
    kp("  Digits:     " + digits)
    kp("  Spaces:     " + spaces)
    kp("  Other:      " + punct)
    kp("  Total:      " + len(text))
}

func vowelPositions(text) {
    let sb = sbNew()
    let i = 0
    while i < len(text) {
        if isVowel(text[i]) {
            sb = sbAppend(sb, "" + i + ":" + text[i] + " ")
        }
        i = i + 1
    }
    emit sbToString(sb)
}

just run {
    kp("Text Analysis")
    kp("=============")
    kp("")

    let texts = "Hello World,The quick brown fox jumps over the lazy dog,Krypton Programming Language 2024"
    let total = count(texts)
    let i = 0
    while i < total {
        let text = split(texts, i)
        kp("Text: \"" + text + "\"")
        analyzeText(text)
        kp("  Vowel positions: " + vowelPositions(text))
        kp("")
        i = i + 1
    }
    emit "ok"
}
