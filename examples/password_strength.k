// Password strength analyzer
// Checks various criteria for password complexity

func hasUppercase(s) {
    let i = 0
    while i < len(s) {
        let ch = s[i]
        if ch >= "A" {
            if ch <= "Z" {
                emit 1
            }
        }
        i = i + 1
    }
    emit 0
}

func hasLowercase(s) {
    let i = 0
    while i < len(s) {
        let ch = s[i]
        if ch >= "a" {
            if ch <= "z" {
                emit 1
            }
        }
        i = i + 1
    }
    emit 0
}

func hasDigit(s) {
    let i = 0
    while i < len(s) {
        let ch = s[i]
        if ch >= "0" {
            if ch <= "9" {
                emit 1
            }
        }
        i = i + 1
    }
    emit 0
}

func hasSpecial(s) {
    let specials = "!@#$%^&*()_+-=[]{}|;:'"
    let i = 0
    while i < len(s) {
        let ch = s[i]
        let j = 0
        while j < len(specials) {
            if ch == specials[j] {
                emit 1
            }
            j = j + 1
        }
        i = i + 1
    }
    emit 0
}

func hasRepeat(s) {
    let i = 0
    while i < len(s) - 2 {
        if s[i] == s[i + 1] {
            if s[i + 1] == s[i + 2] {
                emit 1
            }
        }
        i = i + 1
    }
    emit 0
}

func analyzePassword(pwd) {
    let score = 0
    let details = ""

    // Length check
    if len(pwd) >= 8 {
        score = score + 1
        details = details + "  [+] Length >= 8\n"
    } else {
        details = details + "  [-] Length < 8\n"
    }

    if len(pwd) >= 12 {
        score = score + 1
        details = details + "  [+] Length >= 12\n"
    }

    // Character variety
    if hasUppercase(pwd) {
        score = score + 1
        details = details + "  [+] Has uppercase\n"
    } else {
        details = details + "  [-] No uppercase\n"
    }

    if hasLowercase(pwd) {
        score = score + 1
        details = details + "  [+] Has lowercase\n"
    } else {
        details = details + "  [-] No lowercase\n"
    }

    if hasDigit(pwd) {
        score = score + 1
        details = details + "  [+] Has digit\n"
    } else {
        details = details + "  [-] No digit\n"
    }

    if hasSpecial(pwd) {
        score = score + 1
        details = details + "  [+] Has special char\n"
    } else {
        details = details + "  [-] No special char\n"
    }

    // Penalty for repetition
    if hasRepeat(pwd) {
        score = score - 1
        details = details + "  [-] Has repeated chars (3+)\n"
    }

    // Rating
    let rating = "Weak"
    if score >= 3 { rating = "Fair" }
    if score >= 5 { rating = "Strong" }
    if score >= 6 { rating = "Very Strong" }

    kp("Password: " + pwd)
    kp("Score: " + score + "/7 - " + rating)
    kp(details)
}

just run {
    kp("Password Strength Analyzer")
    kp("==========================")
    kp("")

    analyzePassword("abc")
    analyzePassword("password")
    analyzePassword("Hello123")
    analyzePassword("Str0ng!Pass")
    analyzePassword("MyP@ssw0rd!2024")
    analyzePassword("aaaaabbb")
    emit "ok"
}
