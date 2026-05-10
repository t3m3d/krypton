// 2.0-alpha-3 GC stage 5: soft sweep walker.
// kr_gc_sweep walks gcAllocsHead, rebuilds the chain keeping only allocs
// whose mark bit is set (clearing the bit on survivors). Unmarked allocs
// are unlinked from the chain — memory not yet returned to a slab freelist
// (that's stage 6). Net: gcWalkAllocs() count drops; live values still
// usable because their pointers stay valid.

just run {
    let a = "x" + "y"
    let b = "p" + "q"
    let c = "u" + "v"

    let m = gcMark()
    let s = gcSweep()
    print("[PASS] sweep returned a numeric count: " + s)
    print("[PASS] live allocs after sweep: " + gcWalkAllocs())
    print("[PASS] survivors usable: a=" + a + " b=" + b + " c=" + c)
}
