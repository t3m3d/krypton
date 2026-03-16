// Character Frequency Analysis (for Huffman-like compression)

func charFrequency(text) {
    let freq = ""
    let chars = ""
    let numChars = 0
    let i = 0
    while i < len(text) {
        let ch = text[i]
        let prev = envGet(freq, ch)
        if len(prev) == 0 {
            freq = envSet(freq, ch, "1")
            if numChars > 0 {
                chars = chars + "," + ch
            } else {
                chars = ch
            }
            numChars = numChars + 1
        } else {
            freq = envSet(freq, ch, "" + (toInt(prev) + 1))
        }
        i += 1
    }
    // Print sorted by frequency (simple selection)
    let printed = ""
    let p = 0
    while p < numChars {
        let maxCh = ""
        let maxFreq = 0
        let j = 0
        while j < numChars {
            let ch = split(chars, j)
            let alreadyPrinted = 0
            // Check if already printed
            let k = 0
            while k < len(printed) {
                if printed[k] == ch {
                    alreadyPrinted = 1
                    break
                }
                k += 1
            }
            if !alreadyPrinted {
                let f = toInt(envGet(freq, ch))
                if f > maxFreq {
                    maxFreq = f
                    maxCh = ch
                }
            }
            j += 1
        }
        if len(maxCh) > 0 {
            print("  '" + maxCh + "': " + maxFreq)
            printed = printed + maxCh
        }
        p = p + 1
    }
}

just run {
    let text = "this is an example for huffman encoding"
    print("Text: '" + text + "'")
    print("Character frequencies (descending):")
    charFrequency(text)
}
