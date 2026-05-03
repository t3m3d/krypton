// 0/1 Knapsack
// Bottom-up DP. Each item is taken at most once.
// Weights and values are parallel comma-lists.

// 1-D DP table stored as a comma-list of length (capacity+1).
// dp[w] = max value achievable using items[0..i] with capacity w.

func _ks_get(table, i) { emit toInt(split(table, i)) }

func _ks_set(table, i, v) {
    let n = count(table)
    let sb = sbNew()
    let k = 0
    while k < n {
        if k > 0 { sb = sbAppend(sb, ",") }
        if k == i { sb = sbAppend(sb, v) } else { sb = sbAppend(sb, split(table, k)) }
        k += 1
    }
    emit sbToString(sb)
}

func _ks_max(a, b) {
    if a > b { emit a }
    emit b
}

func _ks_zeros(n) {
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

func knapsack01(weights, values, capacity) {
    let n = count(weights)
    let dp = _ks_zeros(capacity + 1)
    let i = 0
    while i < n {
        let wi = toInt(split(weights, i))
        let vi = toInt(split(values, i))
        // Iterate w from capacity down to wi so each item is used at most once.
        let w = capacity
        while w >= wi {
            let take = vi + _ks_get(dp, w - wi)
            let skip = _ks_get(dp, w)
            dp = _ks_set(dp, w, _ks_max(take, skip))
            w -= 1
        }
        i += 1
    }
    emit _ks_get(dp, capacity)
}

just run {
    kp("0/1 Knapsack")
    kp("============")

    // Classic example: 3 items, capacity 50
    let w1 = "10,20,30"
    let v1 = "60,100,120"
    kp("  weights: " + w1)
    kp("  values:  " + v1)
    kp("  cap=50  -> max value = " + knapsack01(w1, v1, 50))   // 220

    // Capacity 0
    kp("  cap=0   -> " + knapsack01(w1, v1, 0))                 // 0

    // Capacity smaller than smallest item
    kp("  cap=5   -> " + knapsack01(w1, v1, 5))                 // 0

    // Single item that fits exactly
    kp("  cap=10  -> " + knapsack01("10", "60", 10))            // 60
}
