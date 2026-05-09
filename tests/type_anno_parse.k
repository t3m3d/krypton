// Phase B: type annotations on locals — parser-only.
// All these should compile (types are accepted, value semantics unchanged).

just run {
    let a: int = 5
    let b: string = "hello"
    let c: bool = 1
    let p: *u8 = rawAlloc(16)
    let q: *Vec3 = rawAlloc(24)
    let arr: [int] = "1,2,3"
    let nested: [*u8] = "x"
    print("a=" + a + " b=" + b + " c=" + c)
    rawFree(p)
    rawFree(q)
}
