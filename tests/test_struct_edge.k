// Struct env runtime edge cases (macho). Nested structs, structs in collections,
// structs returned from functions, repeated same-key updates (no false grow), and
// many distinct fields with runtime-built keys (env EQ compares key CONTENT, so
// computed keys like "f"+k match — not just interned pointers).
struct Inner { v }
struct Outer { tag inner }
struct P { x }
struct C { n }

func mk(n) { let p = P()  p.x = n  return p }

just run {
    // nested: a struct field holding another struct (faithful pointer value)
    let i = Inner()
    i.v = 42
    let o = Outer()
    o.tag = "x"
    o.inner = i
    if o.inner.v != 42 { kp("[FAIL] nested struct field"); exit("1") }
    if o.tag != "x" { kp("[FAIL] nested sibling field"); exit("1") }

    // struct in an array + struct returned from a function
    let a = array(3)
    a[0] = mk(10)  a[1] = mk(20)  a[2] = mk(30)
    if a[1].x != 20 { kp("[FAIL] struct stored in array"); exit("1") }
    if mk(99).x != 99 { kp("[FAIL] struct returned from func"); exit("1") }

    // repeated same-key update must NOT grow the field set
    let c = C { n: 5 }
    let k = 0
    while k < 100 { c.n = k  k = k + 1 }
    if c.n != 99 { kp("[FAIL] repeated same-key update"); exit("1") }

    // many distinct fields with runtime-built keys (content-compared)
    let m = structNew()
    let j = 0
    while j < 24 { m = setField(m, "f" + j, j * 2)  j = j + 1 }
    if getField(m, "f0") != 0 { kp("[FAIL] computed-key f0"); exit("1") }
    if getField(m, "f10") != 20 { kp("[FAIL] computed-key f10"); exit("1") }
    if getField(m, "f23") != 46 { kp("[FAIL] computed-key f23"); exit("1") }

    kp("[PASS] struct edge: nested, in-array, returned, repeat-update, 24 keys")
}
