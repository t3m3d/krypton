// Phase C: declaration-order independence via multi-pass struct scan.
// Particle declared BEFORE Vec3 — used to require Vec3 first.

struct Particle {
    let pos: Vec3      // forward reference: Vec3 not yet declared
    let vel: Vec3
    let mass: u32
}

struct Vec3 { let x: u32  let y: u32  let z: u32 }

just run {
    let local Particle p
    p.pos.x = 11
    p.pos.y = 22
    p.pos.z = 33
    p.vel.x = 44
    p.vel.y = 55
    p.vel.z = 66
    p.mass  = 77

    print("p.pos.x = " + p.pos.x + " (expect 11)")
    print("p.pos.y = " + p.pos.y + " (expect 22)")
    print("p.pos.z = " + p.pos.z + " (expect 33)")
    print("p.vel.x = " + p.vel.x + " (expect 44)")
    print("p.vel.y = " + p.vel.y + " (expect 55)")
    print("p.vel.z = " + p.vel.z + " (expect 66)")
    print("p.mass  = " + p.mass  + " (expect 77)")
}
