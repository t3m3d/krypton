// Run-Length Encoding

func encode(s) {
    if len(s) == 0 { emit "" }
    let sb = sbNew()
    let i = 0
    while i < len(s) {
        let ch = s[i]
        let cnt = 1
        while i + cnt < len(s) && s[i + cnt] == ch {
            cnt = cnt + 1
        }
        if cnt > 1 {
            sb = sbAppend(sb, "" + cnt)
        }
        sb = sbAppend(sb, ch)
        i = i + cnt
    }
    emit sbToString(sb)
}

func decode(s) {
    let sb = sbNew()
    let i = 0
    while i < len(s) {
        // Check if current char is a digit
        let num = 0
        let hasNum = 0
        while i < len(s) && s[i] >= "0" && s[i] <= "9" {
            num = num * 10 + toInt(s[i])
            hasNum = 1
            i = i + 1
        }
        if i < len(s) {
            if !hasNum { num = 1 }
            let j = 0
            while j < num {
                sb = sbAppend(sb, s[i])
                j = j + 1
            }
            i = i + 1
        }
    }
    emit sbToString(sb)
}

just run {
    let tests = "AAABBBCCCA,ABCD,AABBCC,AAAAAAAA,A"
    let i = 0
    while i < count(tests) {
        let s = split(tests, i)
        let enc = encode(s)
        let dec = decode(enc)
        print("'" + s + "' -> '" + enc + "' -> '" + dec + "'")
        if s == dec {
            print("  [OK] Round-trip matches")
        } else {
            print("  [FAIL] Mismatch!")
        }
        i = i + 1
    }
}
