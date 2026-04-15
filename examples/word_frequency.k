// Word frequency analyzer
// Demonstrates: for-in, compound assignment (+=), keys, values, hasKey,
//               splitBy, sort, const, ternary

func countWords(text) {
    // Split text into words by spaces
    const words = splitBy(text, " ")
    // Build frequency map: word,count,word,count,...
    let map = ""
    for word in words {
        const w = toLower(word)
        if w == "" { continue }
        if hasKey(map, w) {
            // Increment: rebuild map with updated count
            let newMap = ""
            const k = keys(map)
            for key in k {
                const oldVal = split(values(map), listIndexOf(k, key))
                if key == w {
                    if newMap == "" {
                        newMap = key + "," + (oldVal + 1)
                    } else {
                        newMap = newMap + "," + key + "," + (oldVal + 1)
                    }
                } else {
                    if newMap == "" {
                        newMap = key + "," + oldVal
                    } else {
                        newMap = newMap + "," + key + "," + oldVal
                    }
                }
            }
            map = newMap
        } else {
            if map == "" {
                map = w + ",1"
            } else {
                map = map + "," + w + ",1"
            }
        }
    }
    emit map
}

just run {
    const title = "Word Frequency Analyzer"
    kp(title)
    kp(repeat("=", len(title)))

    const text = "the cat sat on the mat the cat ate the rat on the mat"
    kp("Text: \"" + text + "\"")
    kp("")

    const freq = countWords(text)
    const wordKeys = keys(freq)
    const wordVals = values(freq)

    kp("Word frequencies:")
    let maxCount = 0
    for i in range(0, length(wordKeys)) {
        const word = split(wordKeys, i)
        const count = split(wordVals, i)
        const bar = repeat("#", count)
        kp("  " + padRight(word, 8, " ") + padLeft(count, 2, " ") + " " + bar)
        if count > maxCount {
            maxCount = count
        }
    }

    kp("")
    kp("Total unique words: " + length(wordKeys))
    kp("Most frequent count: " + maxCount)
    emit "ok"
}
