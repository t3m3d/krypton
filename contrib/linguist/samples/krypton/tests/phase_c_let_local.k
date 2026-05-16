// Phase C 1.8.9: `let local TYPE name` desugars to a typed-pointer
// heap allocation of sizeof(TYPE) bytes. Field reads/writes work as
// for any other typed *TYPE pointer.

struct Vec3 { let x: u32  let y: u32  let z: u32 }
struct Pixel { let r: u8  let g: u8  let b: u8  let a: u8 }

just run {
    let local Vec3 v
    v.x = 10
    v.y = 20
    v.z = 30
    print("v = (" + v.x + ", " + v.y + ", " + v.z + ")  expect (10, 20, 30)")

    let local Pixel pix
    pix.r = 200
    pix.g = 100
    pix.b = 50
    pix.a = 255
    print("pix = (" + pix.r + ", " + pix.g + ", " + pix.b + ", " + pix.a + ")  expect (200, 100, 50, 255)")
}
