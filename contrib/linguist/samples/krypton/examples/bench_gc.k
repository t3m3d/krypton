// 2.0 GC benchmark: how fast is gcCollect()?
//
// Measures cycles for mark + sweep on a freshly-populated heap.
// Useful for tuning the periodic-collect cadence in long-running
// programs.

func makeGarbage(n) {
    let i = 0
    while i < n {
        let s = "garbage" + i
        let t = s + s
        i = i + 1
    }
}

just run {
    print("=== GC perf bench ===")

    // Warm up
    makeGarbage(100)
    gcCollect()

    let sizes_str = "100,500,1000,2000"
    let i = 0
    while i < 4 {
        let n = toInt(split(sizes_str, i))
        // Alloc N pairs of garbage (2N chunks)
        makeGarbage(n)
        let alloc_total_after = gcAllocCount()
        let live_before = gcWalkAllocs()

        // Time the collect
        let t0 = rdtsc()
        let swept = gcCollect()
        let t1 = rdtsc()

        let cycles = toInt(t1) - toInt(t0)
        let live_after = gcWalkAllocs()

        print("N=" + n + ":  swept=" + swept +
              "  cycles=" + cycles +
              "  cyc_per_alloc=" + (cycles / toInt(alloc_total_after)) +
              "  live: " + live_before + " -> " + live_after)
        i = i + 1
    }
}
