// Phase C 1.8.10: nested struct fields. Inner struct must be declared
// before the outer struct uses it.

struct Vec3 { let x: u32  let y: u32  let z: u32 }

struct Particle {
    let pos: Vec3      // nested struct, lives at offset 0  (12 bytes)
    let vel: Vec3      // nested struct, lives at offset 12 (12 bytes)
    let mass: u32      // primitive, lives at offset 24
}

just run {
    let local Particle p
    // Use the inner pointers directly via nested chain.
    let pos: *Vec3 = bufNew(0)   // dummy declaration — we'll re-tag through p.pos
    // Write nested fields via raw helpers for now (write-chain is a follow-up).
    bufSetDwordAt(p, 0,  10)  // p.pos.x
    bufSetDwordAt(p, 4,  20)  // p.pos.y
    bufSetDwordAt(p, 8,  30)  // p.pos.z
    bufSetDwordAt(p, 12, 100) // p.vel.x
    bufSetDwordAt(p, 16, 200) // p.vel.y
    bufSetDwordAt(p, 20, 300) // p.vel.z
    bufSetDwordAt(p, 24, 999) // p.mass

    // Read via nested-field chain — this is the new bit.
    print("p.pos.x = " + p.pos.x + " (expect 10)")
    print("p.pos.y = " + p.pos.y + " (expect 20)")
    print("p.pos.z = " + p.pos.z + " (expect 30)")
    print("p.vel.x = " + p.vel.x + " (expect 100)")
    print("p.vel.y = " + p.vel.y + " (expect 200)")
    print("p.vel.z = " + p.vel.z + " (expect 300)")
    print("p.mass  = " + p.mass  + " (expect 999)")
}
