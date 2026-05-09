// Phase C 1.8.7: typed-pointer subscript assignment p[i] = v.
// Mirrors phase_c_widths.k but writes via p[i] = v instead of bufSetByte/bufSetDwordAt.

just run {
    let buf = bufNew(64)
    let p8: *u8   = buf
    let p32: *u32 = buf

    p8[0] = 65          // 'A'
    p8[1] = 66          // 'B'
    p32[1] = 305419896  // 0x12345678 at byte offset 4
    p32[2] = 4276993775 // 0xFEDCBAEF at byte offset 8

    print("p8[0]  = " + p8[0]  + " (expect 65)")
    print("p8[1]  = " + p8[1]  + " (expect 66)")
    print("p32[1] = " + p32[1] + " (expect 305419896)")
    print("p32[2] = " + p32[2] + " (expect 4276993775)")
}
