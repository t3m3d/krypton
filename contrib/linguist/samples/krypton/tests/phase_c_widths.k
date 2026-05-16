// Phase C: typed-pointer indexing across widths.
//   *u8  → bufGetByte
//   *u32 → bufGetDwordAt
//   *u64 → bufGetQwordAt

just run {
    let buf = bufNew(64)
    bufSetByte(buf, 0, 65)        // 'A'
    bufSetByte(buf, 1, 66)        // 'B'
    bufSetDwordAt(buf, 4, 305419896)   // 0x12345678
    bufSetDwordAt(buf, 8, 4276993775)  // 0xFEDCBAEF
    bufSetDwordAt(buf, 16, 1)
    bufSetDwordAt(buf, 20, 0)     // upper 4 bytes of qword at 16

    let p8:  *u8  = buf
    let p32: *u32 = buf
    let p64: *u64 = buf

    print("p8[0] = " + p8[0] + " (expect 65)")
    print("p8[1] = " + p8[1] + " (expect 66)")
    print("p32[1] = " + p32[1] + " (expect 305419896)")
    print("p32[2] = " + p32[2] + " (expect 4276993775)")
    print("p64[2] = " + p64[2] + " (expect 1)")
}
