// Stage 6 phase 3: auto-trigger gcCollect on alloc-count threshold.
// gcSetThreshold(N) (N int or numeric string; 0 disables) makes __rt_alloc
// self-collect once allocs-since-collect >= N. The threshold arg is parsed via
// int-passthrough + atoi so "100" and 100 both work — unified with the Windows
// ABI so this one test runs on both backends (handoff_w2m_phase3_review.md item 4).
// The collect runs behind a register safepoint, so
// live roots the caller keeps in registers across an alloc (e.g. `s` here)
// survive. Without auto-collect the 600 dead temps accumulate (live ~600);
// with it the live alloc-list stays tiny and dead temps land on the freelist.
just run {
    gcSetThreshold("100")
    let s = ""
    let i = 0
    while i < 600 {
        s = "x" + i
        i = i + 1
    }
    let live = gcAllocCount()
    kp("live=" + live)
    kp("s=" + s)
    // s must be intact (safepoint preserved the live root across collects).
    if s != "x599" {
        kp("[FAIL] live root corrupted by auto-collect: " + s)
        exit("1")
    }
    // With a 100-alloc threshold over 600 allocs the live set must stay small —
    // far below the ~600 we'd see with auto-collect disabled.
    if toInt(live) > 50 {
        kp("[FAIL] auto-collect did not bound the live set: " + live)
        exit("1")
    }
    kp("[OK] auto-collect fired; live root preserved")
}
