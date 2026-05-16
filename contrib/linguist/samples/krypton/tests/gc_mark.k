// 2.0-alpha-3 GC stage 4: mark walker visualization.
// Heap-allocated values (kr_plus results, etc) get marked as reachable
// via the shadow-stack rooting from stage 3. String literals live in
// .rdata so they don't get marked.

just run {
    // Accumulate a few heap allocations
    let a = "x" + "y"
    let b = a + "z"
    let c = b + "!"

    print("alloc total: " + gcAllocCount())
    print("alloc live:  " + gcWalkAllocs())
    print("shadow:      " + gcShadowCount())
    print("mark count:  " + gcMark())
    print("c=" + c + " (expect xyz!)")
}
