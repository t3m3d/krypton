// Reverse the order of words in a sentence.
// Strategy: walk the string right-to-left, collect words.

func reverseWords(s) {
    let n = len(s)
    let out = ""
    let cur = ""
    let i = n - 1
    while i >= 0 {
        let ch = s[i]
        if ch == " " {
            if len(cur) > 0 {
                if len(out) > 0 { out = out + " " }
                out = out + cur
                cur = ""
            }
        } else {
            cur = ch + cur
        }
        i = i - 1
    }
    if len(cur) > 0 {
        if len(out) > 0 { out = out + " " }
        out = out + cur
    }
    emit out
}

just run {
    let inputs = "the quick brown fox|hello world from krypton|one two three four five"
    // Split inputs by | to iterate (avoiding comma since words contain spaces)
    let n = len(inputs)
    let i = 0
    let cur = ""
    while i < n {
        let ch = inputs[i]
        if ch == "|" {
            kp("input:  " + cur)
            kp("output: " + reverseWords(cur))
            kp("")
            cur = ""
        } else {
            cur = cur + ch
        }
        i += 1
    }
    if len(cur) > 0 {
        kp("input:  " + cur)
        kp("output: " + reverseWords(cur))
    }
}
