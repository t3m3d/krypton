// Phase C 1.8.8: typed struct field access via *Struct pointers.
// `let v: *Vec3 = ...` plus `v.x = 5; let y = v.y` lowers to direct
// typed buf reads/writes at the field's byte offset.

struct Vec3 {
    let x: u32
    let y: u32
    let z: u32
}

struct Pixel {
    let r: u8
    let g: u8
    let b: u8
    let a: u8
}

just run {
    let buf = bufNew(64)
    let v: *Vec3 = buf
    v.x = 100
    v.y = 200
    v.z = 305419896  // 0x12345678

    print("v.x = " + v.x + " (expect 100)")
    print("v.y = " + v.y + " (expect 200)")
    print("v.z = " + v.z + " (expect 305419896)")

    let pix: *Pixel = buf      // Aliased view of same buffer.
    pix.r = 255
    pix.g = 128
    pix.b = 64
    pix.a = 16
    print("pix.r = " + pix.r + " (expect 255)")
    print("pix.g = " + pix.g + " (expect 128)")
    print("pix.b = " + pix.b + " (expect 64)")
    print("pix.a = " + pix.a + " (expect 16)")
}
