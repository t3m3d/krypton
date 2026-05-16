// 2.0-alpha-2 stage 1: gcAllocCount() returns the running count of
// __rt_alloc invocations since process start. Monotonic — not reset by
// gcReset()/gcRestore() (matches gcAllocated semantics).

just run {
    let n0 = toInt(gcAllocCount())
    let b0 = toInt(gcAllocated())
    print("at start: " + n0 + " allocs, " + b0 + " bytes")

    // Force some allocations: each `+` on strings does at least one alloc.
    let s = "hello"
    let i = 0
    while i < 5 {
        s = s + " world"
        i += 1
    }
    let n1 = toInt(gcAllocCount())
    let b1 = toInt(gcAllocated())
    print("after 5 concats: " + n1 + " allocs (delta " + (n1 - n0) + "), " + b1 + " bytes (delta " + (b1 - b0) + ")")

    // Bigger run — confirm the count keeps moving.
    let j = 0
    while j < 100 {
        s = s + "x"
        j += 1
    }
    let n2 = toInt(gcAllocCount())
    print("after +100: " + n2 + " allocs (delta = " + (n2 - n1) + ")")

    print("bytes total: " + gcAllocated())
}
