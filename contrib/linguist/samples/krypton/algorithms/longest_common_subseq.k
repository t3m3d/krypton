// Longest Common Subsequence

func lcsLength(a, b) {
    let m = len(a)
    let n = len(b)

    // Build DP table as flat array (m+1)*(n+1)
    // Using env as a 2D map
    let dp = ""
    let i = 0
    while i <= m {
        let j = 0
        while j <= n {
            let key = "" + i + "_" + j
            if i == 0 || j == 0 {
                dp = envSet(dp, key, "0")
            } else if a[i - 1] == b[j - 1] {
                let prev = toInt(envGet(dp, "" + (i - 1) + "_" + (j - 1)))
                dp = envSet(dp, key, "" + (prev + 1))
            } else {
                let up = toInt(envGet(dp, "" + (i - 1) + "_" + j))
                let left = toInt(envGet(dp, "" + i + "_" + (j - 1)))
                if up > left {
                    dp = envSet(dp, key, "" + up)
                } else {
                    dp = envSet(dp, key, "" + left)
                }
            }
            j += 1
        }
        i += 1
    }

    emit toInt(envGet(dp, "" + m + "_" + n))
}

just run {
    let a = "ABCBDAB"
    let b = "BDCAB"
    kp("String A: " + a)
    kp("String B: " + b)
    kp("LCS length: " + lcsLength(a, b))

    let c = "AGGTAB"
    let d = "GXTXAYB"
    kp("")
    kp("String C: " + c)
    kp("String D: " + d)
    kp("LCS length: " + lcsLength(c, d))
}
