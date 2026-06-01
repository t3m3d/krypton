#!/usr/bin/env kr
// particles.ks — Krypton-side hero particle field.
//
// Compiled to particles.wasm by wasm_self.k (the Krypton WASM backend) and
// loaded into the browser by web/site/dist/wasm_runner.js. This replaces
// the inline JavaScript particle animation that used to run in every
// page's <script> tag.
//
// Each particle has a deterministic position computed from its index `i`
// and the current time `t` — no per-frame randomness, so the motion is
// smooth instead of flickering. Wraps at canvas edges via integer modulo.
// Lines are drawn between particles whose Manhattan distance is below a
// threshold, giving the familiar "connecting tendrils" look.
//
// Host imports (declared in wasm_self.k's wasmImports section, supplied
// by wasm_runner.js):
//   canvas_clear()                — clear the registered hero canvas
//   canvas_circle(x, y, r)        — fill one solid disc
//   canvas_line(x1,y1,x2,y2)      — stroke one segment
//   canvas_set_fill(rgba)         — fillStyle =  0xAARRGGBB (6-bit alpha,
//                                                JS extrapolates by *4)
//   canvas_set_stroke(rgba)       — strokeStyle = same encoding
//   canvas_width()  -> i32        — canvas .width in CSS pixels
//   canvas_height() -> i32        — same, .height
//   random_int(max) -> i32        — uniform integer in [0, max)
//   time_ms()       -> i32        — 22-bit monotonic counter from host

just run {
    let w = canvasWidth()
    let h = canvasHeight()
    let t = timeMs()

    canvasClear()

    // Per-particle position is deterministic: each particle gets a unique
    // initial offset (x0, y0) and a drift speed (vx, vy), then current
    // position = (x0 + vx * (t / DAMP)) mod w/h. Slower DAMP = faster
    // visible motion. 0x3FFFFFFF fill alpha lands near 100% display after
    // the host shim's *4 alpha extrapolation.
    canvasSetFill(1073741823)
    canvasSetStroke(704643071)

    // Precompute the time scale once. Dividing inside the loop would
    // recompute per particle; pulling it out trims ~32 IR ops per frame.
    let tx = t / 90
    let ty = t / 110

    let i = 0
    while i < 28 {
        // Initial offsets — spread particles across the canvas using
        // small primes so positions don't collapse onto a grid.
        let x0 = (i * 137) % w
        let y0 = (i * 89) % h
        // Velocity — small positive integers; using `i % 3 + 1` keeps
        // x always positive (modulo on negatives is undefined in
        // tagged-int land).
        let vx = (i % 4) + 1
        let vy = (i % 3) + 1
        let xi = (x0 + vx * tx) % w
        let yi = (y0 + vy * ty) % h

        canvasCircle(xi, yi, 3)

        // Connect this particle to its 3 nearest index neighbours.
        // O(N*K) lines per frame with K=3 = 84 distance checks total,
        // and only nearby pairs actually emit a canvasLine call.
        let k = 1
        while k <= 4 {
            let j = (i + k) % 28
            let xj0 = (j * 137) % w
            let yj0 = (j * 89) % h
            let vxj = (j % 4) + 1
            let vyj = (j % 3) + 1
            let xj = (xj0 + vxj * tx) % w
            let yj = (yj0 + vyj * ty) % h

            // Manhattan distance — avoids sqrt and stays inside i32.
            let dx = xi - xj
            let dy = yi - yj
            if dx < 0 { dx = 0 - dx }
            if dy < 0 { dy = 0 - dy }
            if dx + dy < 180 {
                canvasLine(xi, yi, xj, yj)
            }
            k = k + 1
        }

        i = i + 1
    }
}
