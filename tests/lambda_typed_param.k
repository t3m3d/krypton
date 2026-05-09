// 2.0-alpha: typed `cb: fp` param enables direct `cb(args)` invocation
// inside the receiver — irScanFuncTypes captures param types and irCall
// routes fp-tagged calls through callPtr automatically.

func apply(cb: fp, x) {
    emit cb(x)            // direct invocation, no explicit callPtr
}

func compose(f: fp, g: fp, x) {
    emit f(g(x))          // chained direct calls
}

just run {
    let sq  = func(n) { emit n * n }
    let inc = func(n) { emit n + 1 }

    print("apply(sq, 6)         = " + apply(sq, 6) + "  (expect 36)")
    print("compose(sq, inc, 4)  = " + compose(sq, inc, 4) + "  (expect 25)")
    print("compose(inc, sq, 4)  = " + compose(inc, sq, 4) + "  (expect 17)")
}
