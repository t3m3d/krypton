// Edit Distance (Levenshtein Distance)

func editDistance(a, b) {
    let m = len(a)
    let n = len(b)
    let dp = ""

    // Initialize base cases
    let i = 0
    while i <= m {
        dp = envSet(dp, "" + i + "_0", "" + i)
        i += 1
    }
    let j = 0
    while j <= n {
        dp = envSet(dp, "0_" + j, "" + j)
        j += 1
    }

    // Fill DP table
    i = 1
    while i <= m {
        j = 1
        while j <= n {
            let key = "" + i + "_" + j
            if a[i - 1] == b[j - 1] {
                let diag = toInt(envGet(dp, "" + (i - 1) + "_" + (j - 1)))
                dp = envSet(dp, key, "" + diag)
            } else {
                let ins = toInt(envGet(dp, "" + i + "_" + (j - 1))) + 1
                let del = toInt(envGet(dp, "" + (i - 1) + "_" + j)) + 1
                let rep = toInt(envGet(dp, "" + (i - 1) + "_" + (j - 1))) + 1
                let best = ins
                if del < best { best = del }
                if rep < best { best = rep }
                dp = envSet(dp, key, "" + best)
            }
            j += 1
        }
        i += 1
    }

    emit toInt(envGet(dp, "" + m + "_" + n))
}

just run {
    print("Edit Distance Calculator")
    print("========================")

    let pairs = "kitten,sitting,saturday,sunday,hello,hallo,abc,abc,intention,execution"
    let i = 0
    while i < 5 {
        let a = split(pairs, i * 2)
        let b = split(pairs, i * 2 + 1)
        print("  d('" + a + "', '" + b + "') = " + editDistance(a, b))
        i += 1
    }
}
