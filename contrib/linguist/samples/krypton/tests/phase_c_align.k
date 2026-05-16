// Phase C: natural field alignment + struct trailing pad.
// Without padding, b would be at offset 1 (misaligned u32). With it,
// b is at offset 4 (3 bytes of pad after a). c at offset 8 (8 = 4+4).
// Total struct size pads up to 8 (max align = 4).

struct Mixed {
    let a: u8       // offset 0, size 1
    let b: u32      // offset 4 (was 1), size 4
    let c: u8       // offset 8, size 1
}                   // total 12 (8+4 rounded up to 4-align)

just run {
    let local Mixed m
    m.a = 11
    m.b = 4444
    m.c = 22
    print("m.a = " + m.a + " (expect 11)")
    print("m.b = " + m.b + " (expect 4444)")
    print("m.c = " + m.c + " (expect 22)")
}
