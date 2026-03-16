// Counter/frequency utilities for Krypton
// Count occurrences of items in lists

go counter {

    // Count character frequencies in a string
    // Returns newline-delimited "char=count" pairs
    func charFrequency(s) {
        let result = ""
        let counted = ""
        let i = 0
        while i < len(s) {
            let ch = s[i]
            // Check if already counted
            let already = 0
            let j = 0
            while j < len(counted) {
                if counted[j] == ch {
                    already = 1
                    break
                }
                j += 1
            }
            if already == 0 {
                // Count this character
                let cnt = 0
                let k = 0
                while k < len(s) {
                    if s[k] == ch {
                        cnt += 1
                    }
                    k += 1
                }
                result = result + ch + "=" + cnt + "\n"
                counted = counted + ch
            }
            i += 1
        }
        emit result
    }

    // Count word frequencies in text (words separated by spaces)
    func wordFrequency(text) {
        // Split into words by spaces
        let words = ""
        let sb = sbNew()
        let i = 0
        while i < len(text) {
            let ch = text[i]
            if ch == " " {
                let word = sbToString(sb)
                if len(word) > 0 {
                    if words == "" {
                        words = word
                    } else {
                        words = words + "," + word
                    }
                }
                sb = sbNew()
            } else {
                sb = sbAppend(sb, ch)
            }
            i += 1
        }
        let lastWord = sbToString(sb)
        if len(lastWord) > 0 {
            if words == "" {
                words = lastWord
            } else {
                words = words + "," + lastWord
            }
        }

        // Count each unique word
        let result = ""
        let seen = ""
        let total = count(words)
        i = 0
        while i < total {
            let w = split(words, i)
            let already = 0
            if seen != "" {
                let sSize = count(seen)
                let j = 0
                while j < sSize {
                    if split(seen, j) == w {
                        already = 1
                        break
                    }
                    j += 1
                }
            }
            if already == 0 {
                let cnt = 0
                let k = 0
                while k < total {
                    if split(words, k) == w {
                        cnt += 1
                    }
                    k += 1
                }
                result = result + w + "=" + cnt + "\n"
                if seen == "" {
                    seen = w
                } else {
                    seen = seen + "," + w
                }
            }
            i += 1
        }
        emit result
    }

    // Count items in a comma-separated list
    func listFrequency(list) {
        let size = count(list)
        let result = ""
        let seen = ""
        let i = 0
        while i < size {
            let item = split(list, i)
            let already = 0
            if seen != "" {
                let sSize = count(seen)
                let j = 0
                while j < sSize {
                    if split(seen, j) == item {
                        already = 1
                        break
                    }
                    j += 1
                }
            }
            if already == 0 {
                let cnt = 0
                let k = 0
                while k < size {
                    if split(list, k) == item {
                        cnt += 1
                    }
                    k += 1
                }
                result = result + item + "=" + cnt + "\n"
                if seen == "" {
                    seen = item
                } else {
                    seen = seen + "," + item
                }
            }
            i += 1
        }
        emit result
    }
}
