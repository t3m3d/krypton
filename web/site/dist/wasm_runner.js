// web/site/dist/wasm_runner.js — Krypton browser WASM loader.
//
// This file does TWO independent jobs:
//
//   1. Lesson playback (Agent B's original responsibility): wraps window.runK
//      so the lesson "Run" button serves the precompiled /learn/<slug>.wasm
//      when the code box is unedited, falling back to runner.js's JS bridge
//      otherwise.
//
//   2. Hero particle animation (NEW, 2.2): when the page has a
//      <canvas id="heroCanvas">, fetch /particles.wasm (compiled from the
//      user-visible source at /particles.ks) and call its exported _start()
//      every requestAnimationFrame. The .wasm module draws each frame via
//      the host canvas/random imports declared below.
//
// Host import surface (mirrors wasm_self.k's wasmImports section):
//
//   env.console_log(ptr, len)            — UTF-8 bytes from linear memory
//   env.console_log_int(v)               — decimal int
//   env.canvas_clear()                   — clearRect on the active canvas
//   env.canvas_circle(x, y, r)           — fill one solid disc
//   env.canvas_line(x1, y1, x2, y2)      — stroke one segment
//   env.canvas_set_fill(rgba)            — fillStyle = #RRGGBBAA
//   env.canvas_set_stroke(rgba)          — strokeStyle = same
//   env.canvas_width()  -> i32           — active canvas .width
//   env.canvas_height() -> i32           — active canvas .height
//   env.random_int(max) -> i32           — uniform integer in [0, max)
//
// "Active canvas" is set by setActiveCanvas(canvas) below. The hero loader
// switches it to <canvas id="heroCanvas"> before each RAF. Lesson playback
// never touches the canvas surface, so those imports are no-ops there.

(function () {
  'use strict';

  // ── Shared host state ───────────────────────────────────────────────
  var activeCtx = null;        // CanvasRenderingContext2D for the active canvas
  var activeCanvas = null;     // The <canvas> element backing activeCtx
  var lessonOut = [];          // Lesson stdout buffer (used by console_log*)
  var lessonInstance = null;   // Currently-running lesson WASM instance
  var dec = new TextDecoder('utf-8');

  // Hero multi-pass state. The hero renderer invokes _start() up to four
  // times per RAF, each time with a different (flipX, flipY, timeBias)
  // — so a single 44-particle module renders as a 176-particle tumbling
  // field with four opposing drift directions. The wasm only computes
  // positive +x/+y drifts, so JS-side mirroring is what produces the
  // visual sense of particles flowing in different directions.
  var passFlipX = 0;
  var passFlipY = 0;
  var passTimeBias = 0;
  var passSuppressClear = false;
  // Per-pass particle list: each canvas_circle call appends its DISPLAY
  // (post-flip, post-divide-by-64) coordinates so the frame loop can
  // walk all pairs after _start returns and stitch additional proximity
  // links beyond the by-index-neighbour ones the wasm draws on its own.
  var passParticles = null;

  function setActiveCanvas(c) {
    activeCanvas = c;
    activeCtx = c ? c.getContext('2d') : null;
    // Hairlines: the hero links between particles should be almost
    // gossamer-thin. Default 1.0 reads as "too solid"; 0.5 lands as a
    // sub-pixel antialiased line that matches the original JS impl.
    if (activeCtx) activeCtx.lineWidth = 0.5;
  }

  // Theme-aware RGB override: when the page sets `--particle-rgb` on :root
  // (e.g. via `@media (prefers-color-scheme: dark)`), use those R/G/B
  // values for the particle field instead of whatever's packed into the
  // KryptScript-side rgba. Alpha is always taken from the packed value so
  // the .ks-tuned ~99% fill / 26% stroke distinction is preserved.
  // Re-read every call so a runtime theme flip (system pref change)
  // reaches the next frame without a reload.
  function themedRGB(fallbackR, fallbackG, fallbackB) {
    try {
      var v = getComputedStyle(document.documentElement)
                .getPropertyValue('--particle-rgb').trim();
      if (v) {
        var p = v.split(',');
        if (p.length === 3) {
          return [
            parseInt(p[0], 10) | 0,
            parseInt(p[1], 10) | 0,
            parseInt(p[2], 10) | 0
          ];
        }
      }
    } catch (e) { /* ignore — fall through to defaults */ }
    return [fallbackR, fallbackG, fallbackB];
  }

  function rgbaToCss(packed) {
    // Colour encoding: 0xAARRGGBB, but Krypton's tagged-int model halves
    // the usable range (every i32 literal is silently `(N<<1)` so it has
    // to fit in 31 bits BEFORE the tag bit). That leaves us with 6 bits
    // for alpha — values 0x00..0x3F. We extrapolate to 0..252 in JS by
    // multiplying the masked byte by 4, so `0x3FFFFFFF` lands at ~99%
    // opacity and `0x05FFFFFF` at ~8%.
    //
    // RGB is overridden by the page-level `--particle-rgb` CSS variable
    // when set (theme-aware), falling back to whatever's in the packed
    // value. The alpha encoded in the WASM call is always honoured.
    var u = packed >>> 0;
    var a = (((u >>> 24) & 0x3f) * 4) / 255;
    var rgb = themedRGB((u >>> 16) & 0xff, (u >>> 8) & 0xff, u & 0xff);
    return 'rgba(' + rgb[0] + ',' + rgb[1] + ',' + rgb[2] + ',' + a.toFixed(3) + ')';
  }

  function rgbaToCssDim(packed, scale) {
    var u = packed >>> 0;
    var a = ((((u >>> 24) & 0x3f) * 4) / 255) * scale;
    var rgb = themedRGB((u >>> 16) & 0xff, (u >>> 8) & 0xff, u & 0xff);
    return 'rgba(' + rgb[0] + ',' + rgb[1] + ',' + rgb[2] + ',' + a.toFixed(3) + ')';
  }

  function makeImports(memLookup) {
    return { env: {
      // Lesson stdout
      console_log: function (ptr, len) {
        try {
          var mem = memLookup();
          lessonOut.push(dec.decode(mem.subarray(ptr, ptr + len)));
        } catch (e) { /* ignore — particles modules don't allocate strings */ }
      },
      console_log_int:   function (v) { lessonOut.push(String(v | 0)); },
      console_log_int64: function (hi, lo) {
        var v = (BigInt.asUintN(32, BigInt(hi)) << 32n) | BigInt.asUintN(32, BigInt(lo));
        lessonOut.push(v.toString());
      },
      console_log_f64:   function (v) { lessonOut.push(String(v)); },
      abort:             function (code) { throw new WebAssembly.RuntimeError('env.abort(' + code + ')'); },

      // Canvas surface (active canvas selected via setActiveCanvas).
      canvas_clear: function () {
        if (!activeCtx) return;
        // Skipped on every pass after the first so each pass layers onto
        // the previous, building up the multi-direction field instead of
        // erasing it on every _start invocation.
        if (passSuppressClear) return;
        activeCtx.clearRect(0, 0, activeCanvas.width, activeCanvas.height);
      },
      // Coordinates and radii arrive in fixed-point: KryptScript-side
      // working units are 1/64 of a CSS pixel, so the integer-only tagged
      // i32 ABI still produces sub-pixel-smooth motion when ctx.arc /
      // ctx.lineTo receive the divided floats below. The Canvas2D antialiaser
      // does the rest. The mirror flags fold a single +x/+y-drifting field
      // into 4 quadrants of opposing drift to fake a tumbling structure.
      canvas_circle: function (x, y, r) {
        if (!activeCtx) return;
        var wf = (activeCanvas.width | 0) * 64;
        var hf = (activeCanvas.height | 0) * 64;
        if (passFlipX) x = wf - x;
        if (passFlipY) y = hf - y;
        var px = x / 64, py = y / 64;
        // r/64 puts each dot at ~2.5 CSS px radius — the .ks-authored
        // default, which sits between the earlier r/80 (too small) and
        // r/40 (too big) revisions.
        activeCtx.beginPath();
        activeCtx.arc(px, py, r / 64, 0, 6.283185307179586);
        activeCtx.fill();
        if (passParticles) passParticles.push(px, py);
      },
      canvas_line: function (x1, y1, x2, y2) {
        // Wasm's by-index neighbour links (up to 5/particle) are
        // suppressed in hero mode — the post-pass proximity stitcher in
        // the frame loop owns line drawing, with a strict per-particle
        // degree cap. Without this no-op, the cap wouldn't be enforceable.
        if (!activeCtx || passParticles) return;
        var wf = (activeCanvas.width | 0) * 64;
        var hf = (activeCanvas.height | 0) * 64;
        if (passFlipX) { x1 = wf - x1; x2 = wf - x2; }
        if (passFlipY) { y1 = hf - y1; y2 = hf - y2; }
        activeCtx.beginPath();
        activeCtx.moveTo(x1 / 64, y1 / 64);
        activeCtx.lineTo(x2 / 64, y2 / 64);
        activeCtx.stroke();
      },
      canvas_set_fill:   function (rgba) { if (activeCtx) activeCtx.fillStyle   = rgbaToCss(rgba); },
      // Strokes get an additional alpha scale-down. The fill (dots) wants
      // ~100% so each particle reads as a solid pip; the stroke (links)
      // wants ~15% so the web feels like web, not wire. Doing it host-side
      // means we don't have to recompile particles.wasm to retune.
      canvas_set_stroke: function (rgba) { if (activeCtx) activeCtx.strokeStyle = rgbaToCssDim(rgba, 0.40); },
      canvas_width:      function () { return activeCanvas ? activeCanvas.width  | 0 : 0; },
      canvas_height:     function () { return activeCanvas ? activeCanvas.height | 0 : 0; },
      random_int:        function (max) { max = max | 0; return max > 0 ? (Math.random() * max) | 0 : 0; },
      // passTimeBias shifts each pass into a different phase so the four
      // mirrored fields don't sit on top of each other as perfect reflections.
      time_ms:           function () { return ((Date.now() + passTimeBias) & 0x3fffff) | 0; },
    }};
  }

  // ─────────────────────────────────────────────────────────────────────
  // 1. Hero particle animation (Krypton .ks → .wasm, drives <canvas>)
  // ─────────────────────────────────────────────────────────────────────

  function startHeroParticles() {
    var canvas = document.getElementById('heroCanvas');
    if (!canvas) return;

    // Keep the canvas's backing-buffer dimensions in sync with the
    // .hero parent. Called from inside the RAF loop too — at first paint
    // the parent's offsetWidth may still be 0 (no layout yet), which
    // would make the .ks code do `% 0` and trap. By re-checking each
    // frame we recover automatically once layout completes, and also
    // pick up window resizes without an event listener.
    function syncCanvasSize() {
      var parent = canvas.parentElement;
      if (!parent) return;
      var pw = parent.offsetWidth | 0;
      var ph = parent.offsetHeight | 0;
      if (canvas.width !== pw)  canvas.width  = pw;
      if (canvas.height !== ph) canvas.height = ph;
    }
    syncCanvasSize();

    fetch('/particles.wasm?v=17', { cache: 'no-cache' })
      .then(function (r) { return r.ok ? r.arrayBuffer() : null; })
      .catch(function () { return null; })
      .then(function (bytes) {
        if (!bytes) return;       // no module shipped → leave the canvas blank
        var instance = null;
        var imports = makeImports(function () {
          return new Uint8Array(instance.exports.memory.buffer);
        });
        WebAssembly.instantiate(bytes, imports).then(function (res) {
          instance = res.instance;
          if (typeof instance.exports._start !== 'function') return;

          // ── Krypton runtime visibility (the "JS"-equivalent inspector trail) ──
          // 1. Tag the canvas with data-* attributes so anyone using DevTools'
          //    Elements pane sees the .ks source path, .wasm path, runtime
          //    version, and current opcode count. JavaScript devs are used to
          //    "this widget is powered by X" being visible there — give the
          //    same affordance for Krypton-powered ones.
          try {
            canvas.setAttribute('data-krypton-runtime', '2.2.0');
            canvas.setAttribute('data-krypton-source', '/particles.ks');
            canvas.setAttribute('data-krypton-wasm',   '/particles.wasm');
            canvas.setAttribute('data-krypton-size',   String(bytes.byteLength | 0));
          } catch (e) { /* noop */ }

          // 2. Console banner — same pattern as a framework's startup log.
          try {
            var n = bytes.byteLength | 0;
            var banner = [
              '%c[Krypton 2.2]%c particles.wasm loaded (' + n + ' bytes) ' +
              '— view the KryptScript source at %c/particles.ks',
              'background:linear-gradient(135deg,#7722ff,#3a0ca3);color:#fff;padding:2px 6px;border-radius:4px;font-weight:600',
              'color:inherit',
              'color:#7722ff;font-weight:600',
            ];
            console.log.apply(console, banner);
          } catch (e) { /* noop */ }

          // RAF loop: each frame, point the host's "active canvas" at
          // the hero canvas and invoke _start() — particles.ks is the
          // body of _start, so each call is one full frame's worth of
          // drawing. We always reschedule the next frame even if this
          // one trapped (e.g. layout-not-ready → canvas.width = 0 →
          // wasm `% 0`); the next frame can recover once layout settles.
          // Four passes per frame. Each pass invokes the same wasm _start()
          // but with different (flipX, flipY, timeBias) host state, so a
          // 44-particle module yields a 176-particle tumbling field with
          // four opposing drift directions. Time biases are chosen far
          // enough apart that the four phases visually look like distinct
          // particles rather than mirrored ghosts of each other.
          var PASSES = [
            { fx: 0, fy: 0, bias: 0         },
            { fx: 1, fy: 0, bias: 5_000_000 },
            { fx: 0, fy: 1, bias: 9_000_000 },
            { fx: 1, fy: 1, bias: 13_000_000 },
          ];
          // Proximity-link threshold + per-particle degree cap. After all
          // four mirror passes capture their particles, walk every (i,j)
          // pair within LINK_DIST_PX, sort shortest-first, and greedily
          // keep the ones whose BOTH endpoints still have room under
          // MAX_LINKS_PER_PARTICLE. Result: free-drifting particles that
          // each have a bounded degree, with the surviving links being
          // the shortest available.
          var LINK_DIST_PX = 80;
          var LINK_DIST_SQ = LINK_DIST_PX * LINK_DIST_PX;
          var MAX_LINKS_PER_PARTICLE = 3;
          function drawExtraLinks(ps) {
            if (!activeCtx || !ps || ps.length < 4) return;
            var n = ps.length / 2;
            var pairs = [];
            for (var i = 0; i < ps.length; i += 2) {
              for (var j = i + 2; j < ps.length; j += 2) {
                var dx = ps[i] - ps[j], dy = ps[i+1] - ps[j+1];
                var d2 = dx*dx + dy*dy;
                if (d2 < LINK_DIST_SQ) pairs.push([i, j, d2]);
              }
            }
            pairs.sort(function (a, b) { return a[2] - b[2]; });
            var deg = new Int32Array(n);
            for (var k = 0; k < pairs.length; k++) {
              var a = pairs[k][0], b = pairs[k][1];
              var ai = a >> 1, bi = b >> 1;
              if (deg[ai] >= MAX_LINKS_PER_PARTICLE) continue;
              if (deg[bi] >= MAX_LINKS_PER_PARTICLE) continue;
              deg[ai]++; deg[bi]++;
              activeCtx.beginPath();
              activeCtx.moveTo(ps[a],   ps[a+1]);
              activeCtx.lineTo(ps[b],   ps[b+1]);
              activeCtx.stroke();
            }
          }

          function frame() {
            syncCanvasSize();
            if (canvas.width > 0 && canvas.height > 0) {
              setActiveCanvas(canvas);
              var allParticles = [];
              for (var p = 0; p < PASSES.length; p++) {
                passFlipX     = PASSES[p].fx;
                passFlipY     = PASSES[p].fy;
                passTimeBias  = PASSES[p].bias;
                passSuppressClear = p > 0;
                passParticles = [];
                try { instance.exports._start(); }
                catch (e) { /* recover next pass */ }
                for (var k = 0; k < passParticles.length; k++) allParticles.push(passParticles[k]);
              }
              passParticles = null;
              passSuppressClear = false;
              drawExtraLinks(allParticles);
              setActiveCanvas(null);
            }
            requestAnimationFrame(frame);
          }
          requestAnimationFrame(frame);
        }).catch(function (e) {
          console.error('[Krypton] particles.wasm instantiate failed:', e);
        });
      });
  }

  // ─────────────────────────────────────────────────────────────────────
  // 2. Lesson playback (the original wasm_runner responsibility)
  // ─────────────────────────────────────────────────────────────────────

  function lessonSlug() {
    var m = (location.pathname || '').match(/\/learn\/([^\/]+?)\.html?$/i);
    return m ? m[1] : null;
  }

  var wasmAvail = {}; // slug -> Promise<ArrayBuffer|null>
  function fetchWasm(slug) {
    if (wasmAvail[slug]) return wasmAvail[slug];
    var p = fetch('/learn/' + slug + '.wasm', { cache: 'force-cache' })
      .then(function (r) { return r.ok ? r.arrayBuffer() : null; })
      .catch(function () { return null; });
    wasmAvail[slug] = p;
    return p;
  }

  function makeLessonHost() {
    var imports = makeImports(function () {
      return new Uint8Array(lessonInstance.exports.memory.buffer);
    });
    return {
      run: function (bytes) {
        lessonOut = [];
        return WebAssembly.instantiate(bytes, imports).then(function (res) {
          lessonInstance = res.instance;
          if (typeof lessonInstance.exports._start !== 'function')
            throw new Error('module missing exported _start()');
          if (!(lessonInstance.exports.memory instanceof WebAssembly.Memory))
            throw new Error('module missing exported memory');
          lessonInstance.exports._start();
          return lessonOut.join('');
        });
      },
    };
  }

  var slug = lessonSlug();
  var jsBridge = window.runK;

  if (slug && typeof jsBridge === 'function') {
    document.addEventListener('DOMContentLoaded', function () {
      document.querySelectorAll('pre code.k').forEach(function (code) {
        code.dataset.korig = (code.innerText || code.textContent);
      });
    });

    window.runK = function (btn) {
      var wrap = btn.parentElement;
      var code = wrap.querySelector('pre code.k');
      var out = wrap.querySelector('.run-out');
      if (!code || !out) return jsBridge(btn);

      var cur = (code.innerText || code.textContent);
      var orig = code.dataset.korig;
      if (orig != null && cur !== orig) return jsBridge(btn);

      var label = btn.textContent;
      btn.disabled = true;
      btn.textContent = 'Running…';

      fetchWasm(slug).then(function (bytes) {
        if (!bytes) {
          btn.disabled = false; btn.textContent = label;
          return jsBridge(btn);
        }
        out.className = 'run-out';
        out.textContent = '';
        makeLessonHost().run(bytes).then(function (text) {
          out.textContent = text.length ? text : '(no output)';
          out.className = 'run-out ok';
          btn.disabled = false; btn.textContent = label;
        }, function () {
          btn.disabled = false; btn.textContent = label;
          jsBridge(btn);
        });
      });
    };
  }

  // Fire hero particles on every page that has a #heroCanvas.
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', startHeroParticles);
  } else {
    startHeroParticles();
  }
})();
