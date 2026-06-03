// Test large-integer support on the native ELF backend.
//
// Regression for the int/pointer tag ceiling. The Linux backend tags values
// below the ELF load base as ints and values at/above it as pointers. That
// base was 0x40000000 (2^30), so any int >= ~1.07e9 — e.g. Unix epoch seconds
// (~1.78e9) — was dereferenced as a pointer and SIGSEGV'd. The base/threshold
// was raised to 0x7F000000, lifting the usable int ceiling to 0x7EFFFFFF
// (~2.13e9, covering epoch through ~2037). See compiler/linux_x86/elf.k
// (hexDwordVaddr). This test must keep passing or that ceiling regressed.

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("Large Integer Tests")
    kp("===================")

    // Values that used to crash at the old 2^30 boundary.
    check("old 2^30 boundary",   "1073741824", "" + 1073741824)
    check("unix epoch magnitude", "1779000017", "" + 1779000017)
    check("max usable int",      "2130706431", "" + 2130706431)   // 0x7EFFFFFF

    // TOTP-style epoch math (the yubiKrypt path that motivated the fix).
    check("epoch / 30",          "59300000",   "" + (1779000017 / 30))
    check("epoch % 30",          "17",         "" + (1779000017 % 30))
    check("window reconstruct",  "17",         "" + (1779000017 - (1779000017 / 30) * 30))

    // Large product that stays under the ceiling.
    check("mul -> 2e9",          "2000000000", "" + (40000 * 50000))

    // Pointers must still be tagged as pointers (discrimination intact).
    check("string still pointer", "1",         "" + contains("yubikey", "key"))
}
