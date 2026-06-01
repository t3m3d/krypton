#!/usr/bin/env kr
// particles.ks — Krypton-side hero particle field.
//
// Compiled to particles.wasm by wasm_self.k (the Krypton WASM backend) and
// loaded into the browser by web/site/dist/wasm_runner.js. Replaces the
// inline JS particle animation that used to live in every page's <script>.
//
// Working unit is 1/64 of a CSS pixel: integer arithmetic produces sub-
// pixel-accurate coordinates that the host shim divides by 64 before
// handing to ctx.arc / ctx.lineTo. Without this, integer-only motion
// looks like flicker — ctx wants floats to antialias smoothly.
//
// Each particle's position is a pure function of (i, t):
//     x = (x0 + vx * t) mod (canvas_width * 64)
// Persistent state lives in `t` (the host's monotonic ms counter,
// masked to 22 bits — wraps every ~70 minutes, plenty for animation).
//
// Lines are drawn between particle i and its 5 next neighbours by index,
// gated by Manhattan distance — only nearby pairs emit a canvasLine call.

just run {
    let w = canvasWidth()
    let h = canvasHeight()
    let t = timeMs()

    canvasClear()

    // 0x3FFFFFFF fill alpha lands near 100% display (host shim ×4 the
    // top 6 bits of the AARRGGBB encoding). 0x2AFFFFFF stroke alpha is
    // about 26% — visible but secondary to the dots.
    canvasSetFill(1073741823)
    canvasSetStroke(721420287)

    // Canvas dims in fine (1/64 px) units.
    let wf = w * 64
    let hf = h * 64

    // Manhattan-distance threshold for line drawing, in fine units.
    // 110 display-px * 64 = 7040.
    let linkDist = 7040

    let i = 0
    while i < 44 {
        // Per-particle velocity in fine-units / ms. Small positive
        // integers so `% wf` always stays non-negative. With t advancing
        // ~16 ms per frame and vx ∈ {1,2,3}, display motion is
        // (vx * 16) / 64 = 0.25..0.75 px per frame — close to the
        // original JS drift speed.
        let vx = (i % 3) + 1
        let vy = ((i * 5) % 3) + 1

        // Initial fine-unit offsets — small primes spread the starting
        // positions evenly without collapsing onto a grid.
        let x0f = ((i * 137) % w) * 64
        let y0f = ((i * 89)  % h) * 64

        let xi = (x0f + vx * t) % wf
        let yi = (y0f + vy * t) % hf

        // Particle dot — 2.5 px diameter (160 / 64 = 2.5).
        canvasCircle(xi, yi, 160)

        // Connect to the next 5 particles by index. Each pair check is
        // O(1); 44 * 5 = 220 distance checks per frame, only nearby
        // ones emit a draw. Lines fade naturally as pairs drift apart.
        let k = 1
        while k <= 5 {
            let j = (i + k) % 44
            let vxj = (j % 3) + 1
            let vyj = ((j * 5) % 3) + 1
            let xj0f = ((j * 137) % w) * 64
            let yj0f = ((j * 89)  % h) * 64
            let xj = (xj0f + vxj * t) % wf
            let yj = (yj0f + vyj * t) % hf

            let dx = xi - xj
            let dy = yi - yj
            if dx < 0 { dx = 0 - dx }
            if dy < 0 { dy = 0 - dy }
            if dx + dy < linkDist {
                canvasLine(xi, yi, xj, yj)
            }
            k = k + 1
        }

        i = i + 1
    }
}
