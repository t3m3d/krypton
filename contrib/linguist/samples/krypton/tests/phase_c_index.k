// Phase C: typed pointer p[i] should compile to BUILTIN bufGetByte 2
// instead of INDEX → kr_idx. Untyped s[i] still uses kr_idx.

just run {
    let s: string = "ABCD"
    let p: *u8 = s
    print("typed p[0]=" + p[0] + " p[1]=" + p[1])
    print("untyped s[0]=" + s[0])
}
