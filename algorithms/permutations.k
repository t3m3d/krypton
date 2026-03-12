// Permutations generator
// Generates all permutations of a string

func permute(prefix, remaining) {
    if len(remaining) == 0 {
        print(prefix)
    } else {
        let i = 0
        while i < len(remaining) {
            let ch = remaining[i]
            let rest = substring(remaining, 0, i) + substring(remaining, i + 1, len(remaining))
            permute(prefix + ch, rest)
            i = i + 1
        }
    }
}

just run {
    let s = "ABC"
    print("Permutations of '" + s + "':")
    permute("", s)

    print("")
    let s2 = "1234"
    print("Permutations of '" + s2 + "':")
    permute("", s2)
}
