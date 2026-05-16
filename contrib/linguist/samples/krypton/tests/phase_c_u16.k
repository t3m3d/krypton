// Phase C 1.8.7: *u16 read + write via p[i] / p[i] = v.

just run {
    let buf = bufNew(32)
    let p16: *u16 = buf

    p16[0] = 0xABCD
    p16[1] = 0x1234
    p16[5] = 0xFFFF

    print("p16[0] = " + p16[0] + " (expect 43981)")
    print("p16[1] = " + p16[1] + " (expect 4660)")
    print("p16[5] = " + p16[5] + " (expect 65535)")

    // Cross-check: read same bytes via *u8 to verify byte ordering.
    let p8: *u8 = buf
    print("p8[0] = " + p8[0] + " (expect 205, 0xCD low byte little-endian)")
    print("p8[1] = " + p8[1] + " (expect 171, 0xAB high byte)")
    print("p8[2] = " + p8[2] + " (expect 52, 0x34 low byte of 0x1234)")
    print("p8[3] = " + p8[3] + " (expect 18, 0x12 high byte)")
}
