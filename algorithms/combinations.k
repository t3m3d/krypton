// Combinations generator
// Generate all k-combinations from a string of characters

func combine(prefix, chars, start, k) {
    if len(prefix) == k {
        print(prefix)
    } else {
        let i = start
        while i < len(chars) {
            combine(prefix + chars[i], chars, i + 1, k)
            i = i + 1
        }
    }
}

just run {
    let chars = "ABCDE"

    print("Choose 2 from " + chars + ":")
    combine("", chars, 0, 2)

    print("")
    print("Choose 3 from " + chars + ":")
    combine("", chars, 0, 3)
}
