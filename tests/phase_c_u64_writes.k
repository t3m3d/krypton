// Phase C: typed *u64 writes via kr_bufsetqwordat machine-code stub.
// Both `p[i] = v` (indexed) and `s.field = v` (struct field).

struct Big { let a: u64  let b: u64  let c: u32 }

just run {
    // Indexed *u64 writes.
    let buf: *u64 = bufNew(24)
    buf[0] = 100
    buf[1] = 200000
    buf[2] = 999999
    print("buf[0] = " + buf[0] + " (expect 100)")
    print("buf[1] = " + buf[1] + " (expect 200000)")
    print("buf[2] = " + buf[2] + " (expect 999999)")

    // Struct *u64 fields.
    let local Big big
    big.a = 1234567
    big.b = 7654321
    big.c = 42
    print("big.a = " + big.a + " (expect 1234567)")
    print("big.b = " + big.b + " (expect 7654321)")
    print("big.c = " + big.c + " (expect 42)")
}
