
func zero() { emit 42 }
func one(a) { emit a + 1 }
func two(a, b) { emit a * 10 + b }
func three(a, b, c) { emit a + b + c }
func four(a, b, c, d) { emit a + b + c + d }
func five(a, b, c, d, e) { emit a + b + c + d + e }
func six(a, b, c, d, e, f) { emit a + b + c + d + e + f }
func seven(a, b, c, d, e, f, g) { emit a + b + c + d + e + f + g }
func eight(a, b, c, d, e, f, g, h) { emit a + b + c + d + e + f + g + h }
func text(s) { emit s + "!" }
func nested(fp, a) { emit callPtr(fp, a) + callPtr(funcptr(zero)) }

func check(name, expected, actual) {
    if expected != actual { kp("[FAIL] " + name); exit("1") }
    kp("[PASS] " + name)
}

just run {
    check("zero args", 42, callPtr(funcptr(zero)))
    check("one arg", 8, callPtr(funcptr(one), 7))
    check("arg order", 23, callPtr(funcptr(two), 2, 3))
    check("three args", 6, callPtr(funcptr(three), 1, 2, 3))
    check("four args", 10, callPtr(funcptr(four), 1, 2, 3, 4))
    check("five args", 15, callPtr(funcptr(five), 1, 2, 3, 4, 5))
    check("six args", 21, callPtr(funcptr(six), 1, 2, 3, 4, 5, 6))
    check("seven args", 28, callPtr(funcptr(seven), 1, 2, 3, 4, 5, 6, 7))
    check("eight args", 36, callPtr(funcptr(eight), 1, 2, 3, 4, 5, 6, 7, 8))
    check("string value", "K!", callPtr(funcptr(text), "K"))
    check("nested calls", 50, callPtr(funcptr(nested), funcptr(one), 7))
    let storage = bufNew(8)
    bufSetQwordAt(storage, 0, funcptr(two))
    check("stored pointer", 91, callPtr(bufGetQwordAt(storage, 0), 9, 1))
    let i = 0
    while i < 50 {
        if callPtr(funcptr(one), i) != i + 1 { kp("[FAIL] loop labels"); exit("1") }
        i += 1
    }
    kp("[PASS] loop labels")
}
