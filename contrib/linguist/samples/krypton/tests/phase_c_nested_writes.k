// Phase C 1.8.10: nested struct field writes via deferred-offset
// accumulation on the LHS. Same chain-walk as the read path.

struct Vec3 { let x: u32  let y: u32  let z: u32 }

struct Particle {
    let pos: Vec3      // offset 0  (12 bytes)
    let vel: Vec3      // offset 12 (12 bytes)
    let mass: u32      // offset 24
}

just run {
    let local Particle p

    // All writes through nested chain — no raw bufSetDwordAt this time.
    p.pos.x = 10
    p.pos.y = 20
    p.pos.z = 30
    p.vel.x = 100
    p.vel.y = 200
    p.vel.z = 300
    p.mass  = 999

    // Read back via nested chain (already verified in phase_c_nested.k).
    print("p.pos.x = " + p.pos.x + " (expect 10)")
    print("p.pos.y = " + p.pos.y + " (expect 20)")
    print("p.pos.z = " + p.pos.z + " (expect 30)")
    print("p.vel.x = " + p.vel.x + " (expect 100)")
    print("p.vel.y = " + p.vel.y + " (expect 200)")
    print("p.vel.z = " + p.vel.z + " (expect 300)")
    print("p.mass  = " + p.mass  + " (expect 999)")
}
