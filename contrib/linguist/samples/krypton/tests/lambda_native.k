// 2.0-alpha-3 unification: lambdas are ALWAYS closures (env-wrapped).
// Direct invocation `f(args)` dispatches via env extraction. Raw fp's
// (from funcptr(named_func)) stay as `fp` and use callPtr explicitly.

just run {
    let f = func(x) { emit x * 2 }
    let g = func(a, b) { emit a + b * 10 }

    // Direct invocation — irScanFuncTypes tags `f`/`g` as `closure`,
    // irCall closure-dispatches.
    print("f(7)     = " + f(7)     + "  (expect 14)")
    print("g(3, 4)  = " + g(3, 4)  + "  (expect 43)")

    // funcptr(named) returns raw fp — use callPtr explicitly.
    let h = funcptr(double)
    print("h(11) via callPtr = " + callPtr(h, 11) + "  (expect 22)")

    // Direct invocation of fp-typed local also works (irCall sees `fp`
    // tag and routes through raw callPtr dispatch).
    print("h(15) direct      = " + h(15) + "  (expect 30)")
}

func double(x) { emit x * 2 }
