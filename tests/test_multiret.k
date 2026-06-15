// B2 multi-return — return a,b packs into an array; let x,y = f() destructures.
// FE-lowered over the A5 array buf builtins. No backend change beyond A5.
func divmod(a, b) { return a / b, a % b }
func minmax(x, y) { if x < y { return x, y }  return y, x }
func three()      { return 1, 2, 3 }
func nameAge()    { return "bob", 30 }

just run {
    let q, r = divmod(17, 5)
    if q != 3 || r != 2 { kp("[FAIL] divmod"); exit("1") }
    let lo, hi = minmax(8, 3)
    if lo != 3 || hi != 8 { kp("[FAIL] minmax (multi-return in branch)"); exit("1") }
    let a, b, c = three()
    if a != 1 || b != 2 || c != 3 { kp("[FAIL] three"); exit("1") }
    let nm, age = nameAge()
    if nm != "bob" || age != 30 { kp("[FAIL] mixed string/int"); exit("1") }
    kp("[PASS] multi-return (2/3 values, in-branch, mixed string/int)")
}
