// Knuth-Morris-Pratt String Matching
// Builds the longest-proper-prefix-also-suffix (LPS) table for the pattern,
// then scans the text in O(n + m) without backtracking.

func _kmp_get(t, i) { emit toInt(split(t, i)) }

func _kmp_set(t, i, v) {
    let n = count(t)
    let sb = sbNew()
    let k = 0
    while k < n {
        if k > 0 { sb = sbAppend(sb, ",") }
        if k == i { sb = sbAppend(sb, v) } else { sb = sbAppend(sb, split(t, k)) }
        k += 1
    }
    emit sbToString(sb)
}

func _kmp_zeros(n) {
    if n <= 0 { emit "" }
    let sb = sbNew()
    let i = 0
    while i < n {
        if i > 0 { sb = sbAppend(sb, ",") }
        sb = sbAppend(sb, "0")
        i += 1
    }
    emit sbToString(sb)
}

func _kmp_buildLps(pattern) {
    let m = len(pattern)
    let lps = _kmp_zeros(m)
    let i = 1
    let j = 0
    while i < m {
        if pattern[i] == pattern[j] {
            j += 1
            lps = _kmp_set(lps, i, j)
            i += 1
        } else {
            if j > 0 {
                j = _kmp_get(lps, j - 1)
            } else {
                lps = _kmp_set(lps, i, 0)
                i += 1
            }
        }
    }
    emit lps
}

func kmpSearch(text, pattern) {
    let n = len(text)
    let m = len(pattern)
    if m == 0 { emit "" }
    let lps = _kmp_buildLps(pattern)
    let positions = ""
    let firstP = 1
    let i = 0
    let j = 0
    while i < n {
        if text[i] == pattern[j] {
            i += 1
            j += 1
            if j == m {
                if firstP { firstP = 0 } else {
                    let p1 = sbNew()
                    p1 = sbAppend(p1, positions)
                    p1 = sbAppend(p1, ",")
                    positions = sbToString(p1)
                }
                let p2 = sbNew()
                p2 = sbAppend(p2, positions)
                p2 = sbAppend(p2, "" + (i - j))
                positions = sbToString(p2)
                j = _kmp_get(lps, j - 1)
            }
        } else {
            if j > 0 {
                j = _kmp_get(lps, j - 1)
            } else {
                i += 1
            }
        }
    }
    emit positions
}

just run {
    kp("KMP String Matching")
    kp("===================")
    let text = "AABAACAADAABAABA"
    let pat  = "AABA"
    kp("  text: " + text)
    kp("  pat:  " + pat)
    let pos = kmpSearch(text, pat)
    kp("  positions: " + pos)

    let text2 = "abcxabcdabxabcdabcdabcy"
    let pat2  = "abcdabcy"
    kp("  text: " + text2)
    kp("  pat:  " + pat2)
    kp("  positions: " + kmpSearch(text2, pat2))

    kp("  no match: '" + kmpSearch("hello world", "xyz") + "'")
}
