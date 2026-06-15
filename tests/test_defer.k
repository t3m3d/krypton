// B1 defer — runs deferred calls at function exit in LIFO order; covers early
// returns + fall-through. FE-lowered (relocated to exits in irFuncIR); no backend.
let order = ""
func track(s) { order = order + s }

func lifo() {
    defer track("1")
    defer track("2")
    defer track("3")
    track("b")
    // exit order: body then 3,2,1 -> "b321"
}
func early(x) {
    defer track("E")
    if x > 0 { return 1 }
    emit 0
}
just run {
    lifo()
    if order != "b321" { kp("[FAIL] LIFO order: " + order); exit("1") }
    order = ""
    let r1 = early(1)            // E runs before the early return
    if r1 != 1 { kp("[FAIL] early return value"); exit("1") }
    if order != "E" { kp("[FAIL] defer on early return: " + order); exit("1") }
    order = ""
    let r0 = early(0)            // E runs at fall-through
    if r0 != 0 { kp("[FAIL] fallthrough return value"); exit("1") }
    if order != "E" { kp("[FAIL] defer on fallthrough: " + order); exit("1") }
    kp("[PASS] defer (LIFO, early-return + fall-through, function-scope)")
}
