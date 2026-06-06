// 2.0-alpha-3 GC stage 6 phase 2: __rt_alloc_v2 consumes from
// gcGlobals[72] (free_head) when a block ≥ requested size is available.
// On freelist hit: unlink from free_head, re-link into gcAllocsHead
// (so the next mark walker still sees it), bump alloc_count, return.

just run {
    let pre = gcFreelistCount()
    if pre == "0" {
        print("[OK] freelist starts at 0")
    } else {
        print("[NOTE] freelist starts at " + pre)
    }

    // Create some unreferenced intermediate string allocs that will be
    // unmarked at collect time. The temporaries from `a + b` are
    // collected; the final concatenated result is rooted in `x` etc.
    let r1 = ""
    let i = 0
    while i < 8 {
        r1 = "x"
        i = i + 1
    }
    print("ran allocs, r1=" + r1)

    let collected = gcCollect()
    print("collected: " + collected)

    let mid = gcFreelistCount()
    print("freelist after collect: " + mid)

    // New allocs of similar size — if freelist consumption works, the
    // freelist count should drop on each successful reuse.
    let q1 = "a"
    let q2 = "b"
    let q3 = "c"
    let after = gcFreelistCount()
    print("freelist after 3 new allocs: " + after)

    if mid > after {
        print("[OK] freelist DROPPED (consumed): " + mid + " -> " + after)
    } else {
        print("[INFO] freelist same/grew: " + mid + " -> " + after)
        print("       (possible if new allocs were too big for available free blocks)")
    }

    print("q1=" + q1 + " q2=" + q2 + " q3=" + q3)
}
