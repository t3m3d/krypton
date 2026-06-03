// tests/test_buffer.k — byte-buffer builtins on the Linux native backend.
//
// These (bufNew/bufSetByte/bufGetByte/bufGet*At) let pure-Krypton code hold
// and parse BINARY data with embedded NUL bytes — which Krypton C-strings
// cannot (len() is strlen, concat truncates at NUL, fromCharCode(0)==""). They
// unblock stdlib/x11.k Phase A2+ (parsing X11 wire replies). Ported to elf.k as
// inline x86-64 codegen (C-free), mirroring x64.k's Phase C buffer machinery.

func check(name, expected, actual) {
    if expected == actual { kp("[PASS] " + name) } else { kp("[FAIL] " + name + " exp=" + expected + " got=" + actual) }
}

just run {
    kp("Buffer Builtin Tests")
    kp("====================")
    let b = bufNew(16)
    bufSetByte(b, 0, 72)    // 'H'
    bufSetByte(b, 1, 105)   // 'i'
    bufSetByte(b, 2, 0)     // embedded NUL — the X11 wire-data problem
    bufSetByte(b, 3, 88)    // 'X'
    check("getByte 0",          "72",    "" + bufGetByte(b, 0))
    check("getByte 1",          "105",   "" + bufGetByte(b, 1))
    check("embedded NUL byte",  "0",     "" + bufGetByte(b, 2))
    check("byte after NUL",     "88",    "" + bufGetByte(b, 3))
    check("wordAt 0 (LE u16)",  "26952", "" + bufGetWordAt(b, 0))   // 72 + 105*256
    bufSetByte(b, 4, 1)  bufSetByte(b, 5, 2)  bufSetByte(b, 6, 0)  bufSetByte(b, 7, 0)
    check("dwordAt 4 (LE u32)", "513",   "" + bufGetDwordAt(b, 4))  // 1 + 2*256
}
