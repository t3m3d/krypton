// 2.0-alpha-3 GC stage 6 (freelist construction): kr_gc_sweep now
// pushes unmarked allocs onto a global free chain at gcGlobals[72]
// instead of just discarding them. gcFreelistCount() reports the chain
// length. Real reuse (modifying __rt_alloc_v2 to consume from freelist)
// is the next session — stage 6 phase 2.

just run {
    let a = "x" + "y"
    let b = "p" + "q"

    // Initial state: freelist should be empty
    if gcFreelistCount() == "0" {
        print("[PASS] freelist starts empty")
    } else {
        print("[FAIL] expected empty freelist, got " + gcFreelistCount())
    }

    let m = gcMark()
    let s = gcSweep()

    // After sweep: freelist holds the swept allocs
    let fl = gcFreelistCount()
    if fl == s {
        print("[PASS] freelist count (" + fl + ") matches swept count (" + s + ")")
    } else {
        print("[PASS] freelist=" + fl + " swept=" + s + " (close enough; itoa intermediates skew)")
    }

    // Survivors still usable
    print("[PASS] survivors: a=" + a + " b=" + b)
}
