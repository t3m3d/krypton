// Longest Increasing Subsequence (length only)
// O(n^2) DP. dp[i] = length of LIS ending at index i.

func _lis_get(t, i) { emit toInt(split(t, i)) }

func _lis_set(t, i, v) {
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

func _lis_ones(n) {
    if n <= 0 { emit "" }
    let sb = sbNew()
    let i = 0
    while i < n {
        if i > 0 { sb = sbAppend(sb, ",") }
        sb = sbAppend(sb, "1")
        i += 1
    }
    emit sbToString(sb)
}

func lisLength(arr) {
    let n = count(arr)
    if n == 0 { emit 0 }
    if n == 1 { emit 1 }
    let dp = _lis_ones(n)
    let i = 1
    while i < n {
        let ai = toInt(split(arr, i))
        let j = 0
        while j < i {
            let aj = toInt(split(arr, j))
            if aj < ai {
                let cand = _lis_get(dp, j) + 1
                if cand > _lis_get(dp, i) {
                    dp = _lis_set(dp, i, cand)
                }
            }
            j += 1
        }
        i += 1
    }
    // max of dp
    let best = 0
    let k = 0
    while k < n {
        let v = _lis_get(dp, k)
        if v > best { best = v }
        k += 1
    }
    emit best
}

just run {
    kp("Longest Increasing Subsequence (length)")
    kp("=======================================")

    let a1 = "10,9,2,5,3,7,101,18"
    kp("  " + a1 + "  -> " + lisLength(a1))   // 4: 2,3,7,101 (or 2,3,7,18)

    let a2 = "0,1,0,3,2,3"
    kp("  " + a2 + "  -> " + lisLength(a2))   // 4

    let a3 = "7,7,7,7"
    kp("  " + a3 + "  -> " + lisLength(a3))   // 1

    let a4 = "1,2,3,4,5"
    kp("  " + a4 + "  -> " + lisLength(a4))   // 5

    let a5 = "5"
    kp("  " + a5 + "  -> " + lisLength(a5))   // 1
}
