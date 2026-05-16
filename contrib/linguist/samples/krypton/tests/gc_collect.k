// 2.0-final GC: gcCollect() does mark + sweep in one call.
// Returns the count of allocs moved to the freelist (sweep count).

just run {
    let i = 0
    while i < 30 {
        let s = "iter" + i
        i = i + 1
    }

    let live_before = gcWalkAllocs()
    let n = gcCollect()
    let live_after = gcWalkAllocs()
    let free_after = gcFreelistCount()

    if toInt(n) > "0" {
        print("[PASS] gcCollect swept some: " + n)
    } else {
        print("[FAIL] gcCollect swept 0 (expected positive)")
    }

    print("[PASS] live_before=" + live_before + " live_after=" + live_after + " free=" + free_after)
}
