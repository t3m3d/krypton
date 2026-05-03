// Run-length encode a string: "aaabb" → "a3b2"

func encode(s) {
    if len(s) == 0 { emit "" }
    let out = sbNew()
    let i = 0
    let n = len(s)
    while i < n {
        let ch = s[i]
        let count = 1
        while i + 1 < n && s[i + 1] == ch {
            count += 1
            i += 1
        }
        out = sbAppend(out, ch)
        out = sbAppend(out, "" + count)
        i += 1
    }
    emit sbToString(out)
}

just run {
    let inputs = "aaabb,wwwwwggh,abcdef,zzz,a"
    for w in inputs {
        kp(w + " → " + encode(w))
    }
}
