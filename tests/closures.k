// 2.0-alpha-3 closures: free vars captured at creation site, snapshot
// semantics. Limitation: closures CANNOT be passed to functions that
// declare params typed `cb: fp` (e.g., stdlib/fp.k receivers) — those
// expect raw function pointers and will crash when given an env-wrapped
// closure value. Direct invocation `f(args)` works.

just run {
    // Single int capture
    let n = 5
    let f = func(x) { emit x + n }
    print("f(7)  = " + f(7)  + " (expect 12)")
    print("f(10) = " + f(10) + " (expect 15)")

    // Multi-int capture
    let a = 10
    let b = 20
    let c = 30
    let g = func(x) { emit x + a + b + c }
    print("g(1)  = " + g(1)  + " (expect 61)")

    // Pointer (string) capture — round-trips via envSet/envGet
    let prefix = ">> "
    let suffix = " <<"
    let wrap = func(s) { emit prefix + s + suffix }
    print(wrap("hello"))

    // Snapshot semantics — capture takes the value at creation time,
    // not at call time.
    let m = 5
    let h1 = func(x) { emit x + m }
    print("h1(0) with m=5  = " + h1(0) + " (expect 5)")
    m = 100
    print("h1(0) after m=100 = " + h1(0) + " (still 5; snapshot at creation)")
    let h2 = func(x) { emit x + m }
    print("h2(0) with m=100  = " + h2(0) + " (expect 100)")

    print("done")
}
