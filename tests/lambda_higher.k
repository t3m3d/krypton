// Higher-order: pass a lambda to a function that calls it via callPtr.
// Direct `fp(args)` syntax inside the receiving function only works
// if `fp` is tagged in irScanFuncTypes — params aren't tracked yet,
// so receivers must use explicit `callPtr(fp, args...)`.

func apply(fp, x) {
    emit callPtr(fp, x)
}

func twice(fp, x) {
    let once = callPtr(fp, x)
    emit callPtr(fp, once)
}

just run {
    let sq = func(n) { emit n * n }
    print("apply(sq, 5)  = " + apply(sq, 5)  + "  (expect 25)")
    print("twice(sq, 3)  = " + twice(sq, 3)  + "  (expect 81)")

    // Lambda stored, passed by name.
    let inc = func(n) { emit n + 1 }
    print("apply(inc, 9) = " + apply(inc, 9) + "  (expect 10)")
}
