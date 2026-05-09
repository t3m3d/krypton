// 2.0-alpha-3 benchmark: closure call overhead vs raw fp call.
// Uses the new rdtsc() builtin to measure cycles.
//
// Krypton gotcha (pre-existing): upper-case variable names in
// while/if/for conditions misparse as struct literals when followed
// by `{`. Use lowercase. (See feedback_uppercase_var_brace.md.)

func plain(x) {
    emit toInt(x) * 2
}

just run {
    let n = 10000
    print("=== closure vs raw fp (n=" + n + " calls) ===")

    // Warm up
    let warm_i = 0
    while warm_i < 100 { warm_i = warm_i + 1 }

    // Raw fp via funcptr + explicit callPtr
    let f_raw = funcptr(plain)
    let r_start = rdtsc()
    let i1 = 0
    let acc1 = 0
    while i1 < n {
        acc1 = toInt(callPtr(f_raw, i1))
        i1 = i1 + 1
    }
    let r_end = rdtsc()
    let r_cycles = toInt(r_end) - toInt(r_start)
    print("raw fp:       " + r_cycles + " cycles total, ~" + (r_cycles / n) + " per call")

    // Lambda without captures (tagged fp): direct call
    let f_lam = func(x) { emit toInt(x) * 2 }
    let l_start = rdtsc()
    let i2 = 0
    let acc2 = 0
    while i2 < n {
        acc2 = f_lam(i2)
        i2 = i2 + 1
    }
    let l_end = rdtsc()
    let l_cycles = toInt(l_end) - toInt(l_start)
    print("fp lambda:    " + l_cycles + " cycles total, ~" + (l_cycles / n) + " per call")

    // Closure (lambda with capture): closure dispatch
    let factor = 2
    let f_clos = func(x) { emit toInt(x) * factor }
    let c_start = rdtsc()
    let i3 = 0
    let acc3 = 0
    while i3 < n {
        acc3 = f_clos(i3)
        i3 = i3 + 1
    }
    let c_end = rdtsc()
    let c_cycles = toInt(c_end) - toInt(c_start)
    print("closure:      " + c_cycles + " cycles total, ~" + (c_cycles / n) + " per call")

    print("")
    print("delta closure vs fp lambda: " + (c_cycles - l_cycles) + " cycles ("
        + ((c_cycles - l_cycles) / n) + " per call) — envGet overhead")
}
