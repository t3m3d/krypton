// String Matching (Naive Pattern Matching)

func findPattern(text, pattern) {
    let results = ""
    let count = 0
    let i = 0
    let tLen = len(text)
    let pLen = len(pattern)
    while i <= tLen - pLen {
        let match = 1
        let j = 0
        while j < pLen {
            if text[i + j] != pattern[j] {
                match = 0
                break
            }
            j += 1
        }
        if match {
            if count > 0 {
                results = results + ","
            }
            results = results + "" + i
            count += 1
        }
        i += 1
    }
    emit results
}

just run {
    let text = "AABAACAADAABAABA"
    let pattern = "AABA"
    print("Text: " + text)
    print("Pattern: " + pattern)

    let positions = findPattern(text, pattern)
    if len(positions) > 0 {
        print("Found at positions: " + positions)
        let n = count(positions)
        let i = 0
        while i < n {
            let pos = toInt(split(positions, i))
            print("  Position " + pos + ": " + substring(text, pos, pos + len(pattern)))
            i += 1
        }
    } else {
        print("Pattern not found")
    }
}
