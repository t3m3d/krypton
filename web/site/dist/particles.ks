#!/usr/bin/env kr
// particles.ks — Krypton-side hero particle field, cluster-tumble edition.
//
// Compiled to particles.wasm by wasm_self.k (the Krypton WASM backend) and
// loaded into the browser by web/site/dist/wasm_runner.js. The colors come
// from the host shim's themedRGB() (reads the --particle-rgb CSS var, so
// dark mode auto-themes); only the MOTION is defined here.
//
// Layout: 9 small clusters of 5 dots each (= 45 dots, ~current 44).
//   - Each cluster has a CENTER that drifts linearly across the canvas
//     at its own (vx, vy), giving each group an independent trajectory.
//   - Within a cluster, the 5 dots tumble around the center via two
//     phase-offset triangle waves (90° apart for x vs y → roughly circular
//     orbit). Per-cluster periods vary so the groups desync over time
//     (organic, not synchronized).
//
// Lines between dots are drawn by the JS proximity stitcher in
// wasm_runner.js (canvasLine here is a no-op in hero mode). With
// LINK_DIST_PX=80 and an orbit radius of ~25px, dots within the same
// cluster auto-link; clusters stay visually distinct unless their centers
// pass close to each other (rare, looks like a "reaction" when it happens).
//
// Working unit is 1/64 of a CSS pixel — sub-pixel-accurate integer math
// that the host shim divides before handing to ctx.arc.

func tri(t, period, amp) {
    // Triangle wave: t in [0, period), returns value in [0, 2*amp].
    // Ramps 0 → 2*amp over the first half, 2*amp → 0 over the second.
    let half = period / 2
    if t < half { emit (t * 2 * amp) / half }
    emit (2 * amp) - ((t - half) * 2 * amp) / half
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

    let nClusters = 9
    let perCluster = 5

    // Orbit radius in fine units. 25 display-px * 64 = 1600.
    // Small enough that intra-cluster dots all sit within LINK_DIST_PX=80
    // of each other, so the proximity stitcher links them all.
    let orbitR = 1600

    let c = 0
    while c < nClusters {
        // Cluster center: linear drift with cluster-specific velocity.
        // Prime multipliers (7, 11, 173, 211) spread starting positions
        // and velocities so the 9 clusters look unrelated, not gridded.
        let cvx = ((c * 7) % 5) + 1
        let cvy = ((c * 11) % 5) + 1
        let cx0f = ((c * 173) % w) * 64
        let cy0f = ((c * 211) % h) * 64
        let xcf = (cx0f + cvx * t) % wf
        let ycf = (cy0f + cvy * t) % hf

        // Tumble period varies per cluster (3000..5400 ms) so the groups
        // desync over time — no two clusters complete an orbit in lockstep.
        let period = 3000 + (c % 5) * 600
        let quarter = period / 4

        let p = 0
        while p < perCluster {
            // Each dot in the cluster gets an evenly-spaced phase offset
            // (0°, 72°, 144°, 216°, 288° around the orbit).
            let phaseShift = (p * period) / perCluster
            let tp = (t + phaseShift) % period
            let ty = (tp + quarter) % period

            // Triangle waves for x and y offset, 90° (quarter-period) apart.
            // Subtracting orbitR centres the [0, 2*orbitR] range onto the
            // cluster centre. Adding wf/hf before mod keeps the result
            // non-negative through the wrap.
            let dx = tri(tp, period, orbitR) - orbitR
            let dy = tri(ty, period, orbitR) - orbitR

            let xf = (xcf + dx + wf) % wf
            let yf = (ycf + dy + hf) % hf

            // 2.5 px diameter (160 / 64).
            canvasCircle(xf, yf, 160)
            p = p + 1
        }
        c = c + 1
    }
}
