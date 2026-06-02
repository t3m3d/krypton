// stdlib/crc32.k — CRC-32 (IEEE 802.3) checksum in PURE KRYPTON. No C.
//
// Native ints wrap at 2^32 (unsigned), which is exactly what CRC-32 wants.
// Uses the reflected polynomial 0xEDB88320, bit-at-a-time (no 256-table, to
// stay small and avoid large-list init across the import boundary).
//
//   crc32("123456789")  -> 3421780262   (0xCBF43926, the standard check value)
//   crc32Hex("...")     -> 8-digit lowercase hex
//
// Pairs with k:hexenc for the hex form.

module crc32

// 32-bit XOR via binary decomposition (Krypton has no native bitwise xor).
func _xor32(a, b) {
    let result = 0
    let bit = 1
    let x = a
    let y = b
    let i = 0
    while i < 32 {
        let xb = x % 2
        let yb = y % 2
        if xb != yb { result = result + bit }
        x = x / 2
        y = y / 2
        bit = bit * 2
        i += 1
    }
    emit result
}

// crc32(s) -> CRC-32 as an unsigned 32-bit integer.
func crc32(s) {
    let crc = 4294967295            // 0xFFFFFFFF
    let poly = 3988292384           // 0xEDB88320 (reflected)
    let n = len(s)
    let i = 0
    while i < n {
        let byte = toInt(charCode(s[i]))
        crc = _xor32(crc, byte)
        let k = 0
        while k < 8 {
            if crc % 2 == 1 {
                crc = _xor32(crc / 2, poly)
            } else {
                crc = crc / 2
            }
            k += 1
        }
        i += 1
    }
    emit _xor32(crc, 4294967295)    // final XOR 0xFFFFFFFF
}

func _hd(v) {
    if v < 10 { emit fromCharCode(48 + v) }
    emit fromCharCode(87 + v)
}

// crc32Hex(s) -> 8-digit lowercase hex string of the checksum.
func crc32Hex(s) {
    let v = crc32(s)
    let out = ""
    let i = 0
    while i < 8 {
        out = _hd(v % 16) + out
        v = v / 16
        i += 1
    }
    emit out
}
