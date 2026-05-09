// Higher-order: pass a lambda to a function that calls it.
// 2.0-alpha-3 unification: ALL lambdas are closures (env-wrapped),
// so receivers tag params as `cb: closure` and direct `cb(x)`
// dispatches via env extraction.

func apply(cb: closure, x) {
    emit cb(x)
}

func twice(cb: closure, x) {
    let once = cb(x)
    emit cb(once)
}

just run {
    let sq = func(n) { emit n * n }
    print("apply(sq, 5)  = " + apply(sq, 5)  + "  (expect 25)")
    print("twice(sq, 3)  = " + twice(sq, 3)  + "  (expect 81)")

    let inc = func(n) { emit n + 1 }
    print("apply(inc, 9) = " + apply(inc, 9) + "  (expect 10)")
}
