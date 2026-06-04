#!/usr/bin/env kr
// particles.ks — Krypton-side hero particle field.
//
// Matches the original constellation-style JS animation that used to
// live inline in every page. Each particle drifts independently in its
// own random-ish direction (including backward), wrapping at the canvas
// edges. The 4-pass mirror trick in wasm_runner.js renders this 15-
// particle source as ~60 visible dots; the proximity stitcher in the
// same shim draws lines between any pair within LINK_DIST_PX with a
// distance-faded alpha — the constellation look.
//
// Working unit is 1/64 of a CSS pixel for sub-pixel-smooth integer
// motion: x = (x0 + vx * t) mod canvas_width_fine.
//
// NO clusters, NO orbits, NO z-axis depth — those were experiments
// that all felt over-designed compared to the original. The honest
// constellation drift is what reads as "Krypton" on the hero.

func posMod(x, m) {
    // Modulo that always returns [0, m) even if x is negative.
    // Krypton's `%` is C-style: (-3) % 10 == -3, not 7.
    let r = x % m
    if r < 0 { emit r + m }
    emit r
}

just run {
    let w = canvasWidth()
    let h = canvasHeight()
    let t = timeMs()

    canvasClear()
    canvasSetFill(1073741823)        // 0x3FFFFFFF — ~99% alpha
    canvasSetStroke(721420287)       // 0x2AFFFFFF — ~26% alpha (lines)

    let wf = w * 64
    let hf = h * 64

    // 15 source particles -> 60 visible via 4-pass mirror in wasm_runner.js.
    let n = 15

    let i = 0
    while i < n {
        // Per-particle velocity in [-5, +5] fine units / ms. With t
        // advancing ~16 ms/frame, display motion is up to ~1.25 px/frame —
        // matches the original JS Math.random()*0.6 drift speed. The two
        // odd primes (31, 73) give x and y independent distributions; the
        // +7/+13 phase shifts ensure no particle is perfectly stationary.
        let vx = ((i * 31 + 7)  % 11) - 5
        let vy = ((i * 73 + 13) % 11) - 5

        // Spread initial positions with primes that don't share factors
        // with the velocity primes — avoids aliasing into visible bands.
        let x0f = ((i * 197 + 41) % w) * 64
        let y0f = ((i * 149 + 23) % h) * 64

        // Linear motion with proper wrap on both signs (posMod).
        let xf = posMod(x0f + vx * t, wf)
        let yf = posMod(y0f + vy * t, hf)

        // Radius 1.5..2.5 px — original was Math.random()*2+1 (1..3 px),
        // but the 4-pass mirror multiplies the visible density, so a
        // tighter range here keeps the field from looking cluttered.
        let r = 96 + ((i * 17) % 64)

        canvasCircle(xf, yf, r)
        i = i + 1
    }
}
