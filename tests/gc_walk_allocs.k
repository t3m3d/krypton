// 2.0-alpha-3 stage 1.5: per-alloc 16B header + gcAllocsHead linked
// list. Each call to __rt_alloc_v2 prepends its allocation to the
// global list. gcWalkAllocs() walks the chain and returns the count.
//
// Foundation for stages 4 (mark walker) + 5 (sweep walker). The mark
// phase will iterate this same list, the sweep phase will unlink dead
// entries.
//
// Note: gcWalkAllocs itself allocates one string (the int->ascii
// return), so consecutive calls add to the count.

just run {
    print("at start:                " + gcWalkAllocs())

    let buf = bufNew(64)
    print("after bufNew(64):        " + gcWalkAllocs())

    let s = "x"
    let i = 0
    while i < 10 {
        s = s + "x"
        i = i + 1
    }
    print("after 10 string concats: " + gcWalkAllocs())

    let n_allocs = toInt(gcWalkAllocs())
    let n_count  = toInt(gcAllocCount())
    print("walk says " + n_allocs + " live, count says " + n_count + " ever (small delta from itoa allocs)")
    print("alloc_total = " + gcAllocated() + " bytes")
}
