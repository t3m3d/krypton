// B4 interfaces (slab 1) — UFCS method dispatch. `obj.method(args)` lowers to
// `method(obj, args)`: any free function whose first param is the receiver acts
// as a method, duck-typed and structural — works on ANY value, not just structs.
// The `interface` block is compile-time signature documentation (skipped at
// codegen). FE only, no vtable. (Dynamic dispatch over a heterogeneous
// []Interface and per-type overloading of one method name are the future vtable
// slab.) NB: value receivers used here on purpose — heap structs have a separate
// pre-existing macho codegen bug (test_structs), unrelated to dispatch.
interface Doubler {
    func double()
    func plus(m)
}

func double(n)    { return n * 2 }
func plus(n, m)   { return n + m }
func describe(n)  { return "n=" + n }
func shout(s)     { return s + "!" }

just run {
    let x = 21
    if x.double() != 42 { kp("[FAIL] method no-arg on int"); exit("1") }
    if x.plus(9) != 30 { kp("[FAIL] method with arg"); exit("1") }
    if x.describe() != "n=21" { kp("[FAIL] method returning string"); exit("1") }

    let s = "hi"
    if s.shout() != "hi!" { kp("[FAIL] method on string receiver"); exit("1") }

    let y = x.double()          // 42
    if y.plus(x) != 63 { kp("[FAIL] method result reused as receiver"); exit("1") }

    kp("[PASS] interfaces (UFCS dispatch on value receivers + interface decl)")
}
