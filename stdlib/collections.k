// Collection utilities for Krypton
// Higher-order-style operations on comma-separated lists

module collections


// Apply operation to each element and build new list
// (Since Krypton doesn't have first-class functions,
//  these are specialized for common operations)

// Double every numeric element
func mapDouble(list) {
    let size = count(list)
    let result = ""
    let i = 0
    while i < size {
        let val = toInt(split(list, i)) * 2
        if result == "" {
            result = "" + val
        } else {
            result = result + "," + val
        }
        i += 1
    }
    emit result
}

// Square every numeric element
func mapSquare(list) {
    let size = count(list)
    let result = ""
    let i = 0
    while i < size {
        let val = toInt(split(list, i))
        let sq = val * val
        if result == "" {
            result = "" + sq
        } else {
            result = result + "," + sq
        }
        i += 1
    }
    emit result
}

// Negate every numeric element
func mapNegate(list) {
    let size = count(list)
    let result = ""
    let i = 0
    while i < size {
        let val = 0 - toInt(split(list, i))
        if result == "" {
            result = "" + val
        } else {
            result = result + "," + val
        }
        i += 1
    }
    emit result
}

// Filter: keep only positive numbers
func filterPositive(list) {
    let size = count(list)
    let result = ""
    let i = 0
    while i < size {
        let val = toInt(split(list, i))
        if val > 0 {
            if result == "" {
                result = "" + val
            } else {
                result = result + "," + val
            }
        }
        i += 1
    }
    emit result
}

// Filter: keep only even numbers
func filterEven(list) {
    let size = count(list)
    let result = ""
    let i = 0
    while i < size {
        let val = toInt(split(list, i))
        if val % 2 == 0 {
            if result == "" {
                result = "" + val
            } else {
                result = result + "," + val
            }
        }
        i += 1
    }
    emit result
}

// Filter: keep only odd numbers
func filterOdd(list) {
    let size = count(list)
    let result = ""
    let i = 0
    while i < size {
        let val = toInt(split(list, i))
        if val % 2 != 0 {
            if result == "" {
                result = "" + val
            } else {
                result = result + "," + val
            }
        }
        i += 1
    }
    emit result
}

// Reduce: sum all elements
func reduceSum(list) {
    let size = count(list)
    let total = 0
    let i = 0
    while i < size {
        total = total + toInt(split(list, i))
        i += 1
    }
    emit total
}

// Reduce: product of all elements
func reduceProduct(list) {
    let size = count(list)
    let product = 1
    let i = 0
    while i < size {
        product = product * toInt(split(list, i))
        i += 1
    }
    emit product
}

// Check if all elements satisfy a condition (all positive)
func allPositive(list) {
    let size = count(list)
    let i = 0
    while i < size {
        if toInt(split(list, i)) <= 0 {
            emit 0
        }
        i += 1
    }
    emit 1
}

// Check if any element satisfies a condition (any zero)
func anyZero(list) {
    let size = count(list)
    let i = 0
    while i < size {
        if toInt(split(list, i)) == 0 {
            emit 1
        }
        i += 1
    }
    emit 0
}

// Zip two lists into pairs
func zip(a, b) {
    let aSize = count(a)
    let bSize = count(b)
    let size = aSize
    if bSize < size {
        size = bSize
    }
    let result = ""
    let i = 0
    while i < size {
        let pair = split(a, i) + ":" + split(b, i)
        if result == "" {
            result = pair
        } else {
            result = result + "," + pair
        }
        i += 1
    }
    emit result
}

// ── Slicing / chunking ───────────────────────────────────────────────

// listSlice(list, lo, hi) — return items at indices [lo, hi). Half-open.
func listSlice(list, lo, hi) {
    let n = count(list)
    if lo < 0 { lo = 0 }
    if hi > n { hi = n }
    if lo >= hi { emit "" }
    let out = ""
    let i = lo
    while i < hi {
        if out == "" { out = split(list, i) }
        else         { out = out + "," + split(list, i) }
        i = i + 1
    }
    emit out
}

// listChunk(list, n) — return a list of chunks, each as a `;`-joined
// sub-list, the chunks themselves comma-joined. (Krypton has no real
// nested lists, so we encode by delimiter level.)
//
//   listChunk("1,2,3,4,5", 2) → "1;2,3;4,5"
func listChunk(list, n) {
    if n <= 0 { emit "" }
    let total = count(list)
    let out = sbNew()
    let i = 0
    let chunkFirst = 1
    let any = 0
    while i < total {
        let inner = sbNew()
        let added = 0
        while added < n && i < total {
            if added > 0 { inner = sbAppend(inner, ";") }
            inner = sbAppend(inner, split(list, i))
            added = added + 1
            i = i + 1
        }
        if any == 1 { out = sbAppend(out, ",") }
        out = sbAppend(out, sbToString(inner))
        any = 1
    }
    emit sbToString(out)
}

// ── Set operations on lists ──────────────────────────────────────────

// True ("1") iff `list` contains the exact string `item`. Linear scan.
func _co_has(list, item) {
    let n = count(list)
    let i = 0
    while i < n {
        if split(list, i) == item { emit "1" }
        i = i + 1
    }
    emit "0"
}

// Items present in BOTH a and b, in a's order, with a-side duplicates kept.
func listIntersect(a, b) {
    let out = ""
    let n = count(a)
    let i = 0
    while i < n {
        let it = split(a, i)
        if _co_has(b, it) == "1" {
            if out == "" { out = it }
            else         { out = out + "," + it }
        }
        i = i + 1
    }
    emit out
}

// Items in a followed by items in b that aren't already present
// (preserves order, drops duplicates).
func listUnion(a, b) {
    let out = a
    let n = count(b)
    let i = 0
    while i < n {
        let it = split(b, i)
        if _co_has(out, it) == "0" {
            if out == "" { out = it }
            else         { out = out + "," + it }
        }
        i = i + 1
    }
    emit out
}

// Items in a that are NOT in b, in a's order.
func listDifference(a, b) {
    let out = ""
    let n = count(a)
    let i = 0
    while i < n {
        let it = split(a, i)
        if _co_has(b, it) == "0" {
            if out == "" { out = it }
            else         { out = out + "," + it }
        }
        i = i + 1
    }
    emit out
}

// ── Statistics ───────────────────────────────────────────────────────

// Integer mean (floored). Returns 0 on empty list.
func listMean(list) {
    let n = count(list)
    if n == 0 { emit 0 }
    let sum = 0
    let i = 0
    while i < n {
        sum = sum + toInt(split(list, i))
        i = i + 1
    }
    emit sum / n
}

// Median of an integer list (assumes list is already sorted). For
// even-length lists returns the lower of the two middle elements
// (integer floor — no floats in Krypton).
func listMedian(list) {
    let n = count(list)
    if n == 0 { emit 0 }
    let mid = n / 2
    if (n % 2) == 1 { emit toInt(split(list, mid)) }
    // even: average the two middles (floored)
    let a = toInt(split(list, mid - 1))
    let b = toInt(split(list, mid))
    emit (a + b) / 2
}

// Most common item in a list (string equality). Ties broken by first-seen.
func listMode(list) {
    let n = count(list)
    if n == 0 { emit "" }
    let bestItem = ""
    let bestCnt = 0
    let i = 0
    while i < n {
        let it = split(list, i)
        let cnt = 0
        let j = 0
        while j < n {
            if split(list, j) == it { cnt = cnt + 1 }
            j = j + 1
        }
        if cnt > bestCnt { bestCnt = cnt  bestItem = it }
        i = i + 1
    }
    emit bestItem
}

// Count occurrences of `item` (string equality).
func listFrequency(list, item) {
    let n = count(list)
    let cnt = 0
    let i = 0
    while i < n {
        if split(list, i) == item { cnt = cnt + 1 }
        i = i + 1
    }
    emit cnt
}
