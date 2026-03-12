// Anagram checker
// Determines if two strings are anagrams of each other

func sortString(s) {
    // Simple bubble sort on characters
    let arr = ""
    let i = 0
    while i < len(s) {
        if arr == "" {
            arr = s[i]
        } else {
            arr = arr + "," + s[i]
        }
        i = i + 1
    }

    let size = count(arr)
    let swapped = 1
    while swapped {
        swapped = 0
        i = 0
        while i < size - 1 {
            let a = split(arr, i)
            let b = split(arr, i + 1)
            if a > b {
                // Swap
                let sb = sbNew()
                let j = 0
                while j < size {
                    if j > 0 { sb = sbAppend(sb, ",") }
                    if j == i {
                        sb = sbAppend(sb, b)
                    } else if j == i + 1 {
                        sb = sbAppend(sb, a)
                    } else {
                        sb = sbAppend(sb, split(arr, j))
                    }
                    j = j + 1
                }
                arr = sbToString(sb)
                swapped = 1
            }
            i = i + 1
        }
    }

    // Join back
    let result = sbNew()
    i = 0
    while i < size {
        result = sbAppend(result, split(arr, i))
        i = i + 1
    }
    emit sbToString(result)
}

func toLower(s) {
    let sb = sbNew()
    let upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    let lower = "abcdefghijklmnopqrstuvwxyz"
    let i = 0
    while i < len(s) {
        let ch = s[i]
        let found = 0
        let j = 0
        while j < 26 {
            if ch == upper[j] {
                sb = sbAppend(sb, lower[j])
                found = 1
                break
            }
            j = j + 1
        }
        if found == 0 {
            if ch != " " {
                sb = sbAppend(sb, ch)
            }
        }
        i = i + 1
    }
    emit sbToString(sb)
}

func isAnagram(a, b) {
    let normA = toLower(a)
    let normB = toLower(b)
    if len(normA) != len(normB) {
        emit 0
    }
    let sortedA = sortString(normA)
    let sortedB = sortString(normB)
    if sortedA == sortedB {
        emit 1
    }
    emit 0
}

just run {
    kp("Anagram Checker")
    kp("===============")
    kp("")

    // Test pairs
    kp("listen / silent: " + isAnagram("listen", "silent"))
    kp("hello / world: " + isAnagram("hello", "world"))
    kp("race / care: " + isAnagram("race", "care"))
    kp("night / thing: " + isAnagram("night", "thing"))
    kp("rat / tar: " + isAnagram("rat", "tar"))
    kp("ab / abc: " + isAnagram("ab", "abc"))
    kp("evil / vile: " + isAnagram("evil", "vile"))
    kp("fluster / restful: " + isAnagram("fluster", "restful"))
    emit "ok"
}
