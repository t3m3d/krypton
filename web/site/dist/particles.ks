#!/usr/bin/env kr
// particles.ks — Krypton-side hero particle field.
//
// Compiled to particles.wasm by wasm_self.k (the Krypton WASM backend) and
// loaded into the browser by web/site/dist/wasm_runner.js. Replaces the
// inline JavaScript particle animation that used to run in every page's
// <script> tag.
//
// Host imports (declared in wasm_self.k's wasmImports section, supplied by
// wasm_runner.js):
//   canvas_clear()            — clear the registered hero canvas
//   canvas_circle(x, y, r)    — fill one circle at (x, y) radius r
//   canvas_line(x1,y1,x2,y2)  — stroke one line segment
//   canvas_set_fill(rgba)     — fillStyle =  rgba packed as 0xRRGGBBAA
//   canvas_set_stroke(rgba)   — strokeStyle = same encoding
//   canvas_width()  -> i32    — canvas .width in CSS pixels
//   canvas_height() -> i32    — same, .height
//   random_int(max) -> i32    — uniform integer in [0, max)
//
// Visual: each tick, paint ~32 white dots at pseudo-random positions, plus
// a handful of connecting lines. Repeated calls from the host's
// requestAnimationFrame loop give a shimmering / drifting field that looks
// like the original JS particle effect.

just run {
    let w = canvasWidth()
    let h = canvasHeight()

    canvasClear()

    // Dots: white near-opaque. Color encoded as 0xAARRGGBB where alpha is
    // a 6-bit value in [0, 0x3F]; the host shim multiplies by 4 to extend
    // to the 0-252 display range. 0x3FFFFFFF = white at ~99% effective
    // alpha (alpha byte 0x3F = 63, *4 = 252/255).
    canvasSetFill(1073741823)
    let i = 0
    while i < 32 {
        let x = randomInt(w)
        let y = randomInt(h)
        canvasCircle(x, y, 2)
        i = i + 1
    }

    // Lines: faint white tendrils between random pairs. ~10 segments per
    // frame, each ~120px max length so they look local rather than wild.
    // 0x05FFFFFF: alpha byte 0x05 = 5, *4 = 20/255 ≈ 8% effective alpha.
    canvasSetStroke(100663295)
    let j = 0
    while j < 10 {
        let x1 = randomInt(w)
        let y1 = randomInt(h)
        let x2 = x1 + randomInt(240) - 120
        let y2 = y1 + randomInt(240) - 120
        canvasLine(x1, y1, x2, y2)
        j = j + 1
    }
}
