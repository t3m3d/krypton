// 2.0-alpha: big-endian byte-slice readers via kr_bufget*atbe machine
// stubs. Useful for protocol parsers (DNS, PNG, network headers).

just run {
    let buf: *u8 = bufNew(16)

    // Write a known LE pattern via existing bufSet*; read back as BE
    // to confirm byte order is reversed.
    bufSetWordAt(buf, 0, 0x1234)         // bytes: 34 12  (LE storage)
    bufSetDwordAt(buf, 4, 0x12345678)    // bytes: 78 56 34 12
    bufSetQwordAt(buf, 8, 0x123456789ABCDEF0) // bytes: F0 DE BC 9A 78 56 34 12

    // LE reads return what was written.
    print("LE word  = " + bufGetWordAt(buf, 0)  + "  (expect 4660 = 0x1234)")
    print("LE dword = " + bufGetDwordAt(buf, 4) + "  (expect 305419896 = 0x12345678)")

    // BE reads byte-swap → 0x1234 stored as 34 12 → BE-reads as 0x3412.
    print("BE word  = " + bufGetWordAtBE(buf, 0)  + "  (expect 13330 = 0x3412)")
    print("BE dword = " + bufGetDwordAtBE(buf, 4) + "  (expect 2018915346 = 0x78563412)")

    // Round-trip: write BE then read LE confirms swap.
    // (Use the standard set since we don't have set*BE yet.)
    bufSetDwordAt(buf, 0, 0x44332211)   // LE: 11 22 33 44
    print("BE dword = " + bufGetDwordAtBE(buf, 0) + "  (expect 287454020 = 0x11223344)")
}
