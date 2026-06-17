// Struct env runtime (macho) — STRUCTNEW/SETFIELD/GETFIELD now back a struct
// with a faithful (keyPtr, value) buffer instead of crashing. Values keep their
// real type (int OR string/pointer), survive multi-field, update-in-place, and
// cross-function passing. (Struct literals `T { ... }` are a separate FE issue;
// not exercised here.)
struct Wallet { cents name }
func balance(w)      { return w.cents }
func deposit(w, amt) { w.cents = w.cents + amt  return w.cents }
func rename(w, nm)   { w.name = nm  return w }

struct Point { x y }
func dist2(p) { return p.x * p.x + p.y * p.y }

just run {
    let w = Wallet()
    w.cents = 100              // int field
    w.name = "alice"           // string field
    if balance(w) != 100 { kp("[FAIL] int field cross-function"); exit("1") }
    if w.cents != 100 { kp("[FAIL] int field readback"); exit("1") }
    if w.name != "alice" { kp("[FAIL] string field"); exit("1") }

    w.cents = w.cents + 50     // update int in place
    if w.cents != 150 { kp("[FAIL] int update"); exit("1") }
    let after = deposit(w, 25) // mutate via function
    if after != 175 { kp("[FAIL] deposit return"); exit("1") }

    let p = Point()
    p.x = 3  p.y = 4
    if dist2(p) != 25 { kp("[FAIL] int arithmetic on fields"); exit("1") }
    p.x = 6
    if dist2(p) != 52 { kp("[FAIL] field update affects compute"); exit("1") }

    kp("[PASS] struct env (faithful int/string fields, update, cross-function)")
}
