// 2.0-alpha demo — composes everything shipped this release:
//   - native lambdas with typed `cb: fp` params
//   - functional pipeline via stdlib/fp.k
//   - typed struct fields with natural alignment + defaults
//   - nested struct read+write chains
//   - for-in over comma-separated lists (newly fixed)
//   - GC diagnostics: alloc count + shadow stack count
//
// Models a tiny "physics step" over a list of particles.

import "k:fp"

struct Vec3 {
    let x: u32 = 0
    let y: u32 = 0
    let z: u32 = 0
}

struct Particle {
    let pos:  Vec3
    let vel:  Vec3
    let mass: u32 = 1
}


// Apply a delta to a particle in place. Returns the same particle for
// chaining (Krypton convention: emit value).
func step(p: *Particle, dx, dy, dz) {
    p.pos.x = p.pos.x + dx
    p.pos.y = p.pos.y + dy
    p.pos.z = p.pos.z + dz
}


// "Hash" a particle's position to a single number — useful for
// comparing simulation states cheaply.
func posHash(p: *Particle) {
    emit p.pos.x * 73 + p.pos.y * 41 + p.pos.z * 17
}


just run {
    let allocsBefore = toInt(gcAllocCount())
    print("=== 2.0-alpha demo ===")
    print("allocs at start: " + allocsBefore)
    print("")

    let local Particle p
    p.pos.x = 100  p.pos.y = 200  p.pos.z = 300
    p.vel.x = 1    p.vel.y = 2    p.vel.z = 3
    print("start pos = (" + p.pos.x + ", " + p.pos.y + ", " + p.pos.z + ")")
    print("hash(start) = " + posHash(p))

    // Step 5 frames using the velocity. Each frame mutates pos in place.
    print("")
    print("--- 5 simulation steps ---")
    let frame = 0
    while frame < 5 {
        step(p, p.vel.x, p.vel.y, p.vel.z)
        print("after step " + (frame + 1) + ": pos=(" + p.pos.x + "," + p.pos.y + "," + p.pos.z + ")  hash=" + posHash(p))
        frame = frame + 1
    }

    // Functional pipeline. Native lambdas DON'T have closure capture
    // yet (1.x semantic — captures are 2.1 work per docs/v20_plan.md),
    // so the bodies use only their params and global builtins.
    print("")
    print("--- functional pipeline ---")
    let nums = fpRange(1, 11)
    let doubled = fpMap(nums, func(v) { emit toInt(v) * 2 })
    let evens   = fpFilter(doubled, func(v) { emit toInt(v) % 4 == 0 })
    let sum     = fpReduce(evens, "0", func(a, v) { emit toInt(a) + toInt(v) })
    print("nums    = " + nums)
    print("doubled = " + doubled)
    print("evens   = " + evens)
    print("sum(evens) = " + sum + "  (expect 60 = 4+8+12+16+20)")

    // for-in iterates a comma-list — newly fixed in this release.
    let total = 0
    for v in evens {
        total = total + toInt(v)
    }
    print("for-in sum = " + total + "  (expect 60)")

    print("")
    print("--- diagnostics ---")
    let allocsAfter = toInt(gcAllocCount())
    print("allocs at end     : " + allocsAfter)
    print("delta             : " + (allocsAfter - allocsBefore))
    print("shadow-stack roots: " + gcShadowCount() + " (expect 0; compiler doesn't emit pushes yet)")
}
