// 2.0-alpha: lambdas in the native pipeline. Pre-scan hoists each
// lambda to a sibling top-level FUNC; the lambda expression itself
// pushes a function pointer (FUNCPTR _krlam<pos>). Invocation is via
// callPtr(fp, args...) — no closures, captures must be passed.

just run {
    let f = func(x) { emit x * 2 }
    let g = func(a, b) { emit a + b * 10 }

    // Direct invocation — irScanFuncTypes tags `f`/`g` as `fp`, irCall
    // routes through callPtr automatically.
    print("f(7)     = " + f(7)     + "  (expect 14)")
    print("g(3, 4)  = " + g(3, 4)  + "  (expect 43)")

    // Explicit callPtr still works (for higher-order funcs that take
    // an fp parameter — we don't yet propagate fp through params).
    print("via cp   = " + callPtr(f, 9) + "  (expect 18)")

    // Direct lambda value via callPtr.
    print("inline   = " + callPtr(func(n) { emit n * n }, 6) + "  (expect 36)")

    // funcptr(named) also tags as fp.
    let h = funcptr(double)
    print("h(11)    = " + h(11) + "  (expect 22)")
}

func double(x) { emit x * 2 }
