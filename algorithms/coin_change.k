// Coin Change Problem (DP)
// Find minimum coins to make a given amount

func minCoins(coins, amount) {
    // dp[i] = min coins for amount i, using env
    let dp = ""
    dp = envSet(dp, "0", "0")

    let i = 1
    while i <= amount {
        let best = amount + 1  // infinity
        let j = 0
        let nc = count(coins)
        while j < nc {
            let coin = toInt(split(coins, j))
            if coin <= i {
                let prev = envGet(dp, "" + (i - coin))
                if len(prev) > 0 {
                    let val = toInt(prev) + 1
                    if val < best {
                        best = val
                    }
                }
            }
            j += 1
        }
        if best <= amount {
            dp = envSet(dp, "" + i, "" + best)
        }
        i += 1
    }

    let result = envGet(dp, "" + amount)
    if len(result) == 0 { emit 0 - 1 }
    emit toInt(result)
}

just run {
    let coins = "1,5,10,25"
    kp("Coins: " + coins)
    kp("=====================")

    let amounts = "1,5,11,15,30,41,63,99"
    let i = 0
    while i < count(amounts) {
        let amt = toInt(split(amounts, i))
        let result = minCoins(coins, amt)
        if result >= 0 {
            kp("  " + amt + " cents: " + result + " coins")
        } else {
            kp("  " + amt + " cents: impossible")
        }
        i += 1
    }
}
