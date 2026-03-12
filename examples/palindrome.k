// Palindrome checker
// Checks if a string reads the same forwards and backwards

func isPalindrome(s) {
    let left = 0
    let right = len(s) - 1
    while left < right {
        if s[left] != s[right] {
            emit 0
        }
        left = left + 1
        right = right - 1
    }
    emit 1
}

func reverseStr(s) {
    let sb = sbNew()
    let i = len(s) - 1
    while i >= 0 {
        sb = sbAppend(sb, s[i])
        i = i - 1
    }
    emit sbToString(sb)
}

just run {
    kp("Palindrome Checker")
    kp("==================")

    let words = "racecar,hello,madam,level,world,kayak,rotator,noon,civic,python"
    let total = count(words)
    let i = 0
    while i < total {
        let word = split(words, i)
        let reversed = reverseStr(word)
        if isPalindrome(word) {
            kp("  '" + word + "' -> palindrome (reversed: " + reversed + ")")
        } else {
            kp("  '" + word + "' -> NOT a palindrome (reversed: " + reversed + ")")
        }
        i = i + 1
    }
    emit "ok"
}
