// Permutations generator
// Generates all permutations of a string

func permute(prefix, remaining) {
    if len(remaining) == 0 {
        kp(prefix)
    } else {
        let i = 0
        while i < len(remaining) {
            let ch = remaining[i]
            let rest = substring(remaining, 0, i) + substring(remaining, i + 1, len(remaining))
            permute(prefix + ch, rest)
            i += 1
        }
    }
}

just run {
    let s = "ABC"
    kp("Permutations of '" + s + "':")
    permute("", s)

    kp("")
    let s2 = "1234"
    kp("Permutations of '" + s2 + "':")
    permute("", s2)
}
