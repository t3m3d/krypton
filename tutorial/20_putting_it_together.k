// Tutorial 20: Putting It All Together
// A mini project: word frequency counter

func buildFreqMap(text) {
    // Count word frequencies using env as a map
    let env = ""
    let word = ""
    let i = 0
    while i < len(text) {
        let ch = text[i]
        if ch == " " || ch == "\n" || ch == "\t" {
            if len(word) > 0 {
                let prev = envGet(env, word)
                if len(prev) == 0 {
                    env = envSet(env, word, "1")
                } else {
                    env = envSet(env, word, "" + (toInt(prev) + 1))
                }
                word = ""
            }
        } else {
            word = word + ch
        }
        i = i + 1
    }
    // Handle last word
    if len(word) > 0 {
        let prev = envGet(env, word)
        if len(prev) == 0 {
            env = envSet(env, word, "1")
        } else {
            env = envSet(env, word, "" + (toInt(prev) + 1))
        }
    }
    emit env
}

just run {
    let text = "the cat sat on the mat the cat ate the rat"
    print("Text: " + text)
    print("")

    let freq = buildFreqMap(text)

    // Check specific words
    let words = "the,cat,sat,on,mat,ate,rat"
    let i = 0
    let n = count(words)
    while i < n {
        let w = split(words, i)
        let c = envGet(freq, w)
        if len(c) > 0 {
            print("  '" + w + "' appears " + c + " time(s)")
        }
        i = i + 1
    }

    print("")
    print("Tutorial complete! You now know the key features of Krypton.")
}
