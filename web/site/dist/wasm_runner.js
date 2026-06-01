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

  function setActiveCanvas(c) {
    activeCanvas = c;
    activeCtx = c ? c.getContext('2d') : null;
  }

  function rgbaToCss(packed) {
    // Colour encoding: 0xAARRGGBB, but Krypton's tagged-int model halves
    // the usable range (every i32 literal is silently `(N<<1)` so it has
    // to fit in 31 bits BEFORE the tag bit). That leaves us with 6 bits
    // for alpha — values 0x00..0x3F. We extrapolate to 0..252 in JS by
    // multiplying the masked byte by 4, so `0x3FFFFFFF` lands at ~99%
    // opacity and `0x05FFFFFF` at ~8%.
    var u = packed >>> 0;
    var a = (((u >>> 24) & 0x3f) * 4) / 255;
    var r = (u >>> 16) & 0xff;
    var g = (u >>> 8)  & 0xff;
    var b = u & 0xff;
    return 'rgba(' + r + ',' + g + ',' + b + ',' + a.toFixed(3) + ')';
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
        activeCtx.clearRect(0, 0, activeCanvas.width, activeCanvas.height);
      },
      // Coordinates and radii arrive in fixed-point: KryptScript-side
      // working units are 1/64 of a CSS pixel, so the integer-only tagged
      // i32 ABI still produces sub-pixel-smooth motion when ctx.arc /
      // ctx.lineTo receive the divided floats below. The Canvas2D antialiaser
      // does the rest.
      canvas_circle: function (x, y, r) {
        if (!activeCtx) return;
        activeCtx.beginPath();
        activeCtx.arc(x / 64, y / 64, r / 64, 0, 6.283185307179586);
        activeCtx.fill();
      },
      canvas_line: function (x1, y1, x2, y2) {
        if (!activeCtx) return;
        activeCtx.beginPath();
        activeCtx.moveTo(x1 / 64, y1 / 64);
        activeCtx.lineTo(x2 / 64, y2 / 64);
        activeCtx.stroke();
      },
      canvas_set_fill:   function (rgba) { if (activeCtx) activeCtx.fillStyle   = rgbaToCss(rgba); },
      canvas_set_stroke: function (rgba) { if (activeCtx) activeCtx.strokeStyle = rgbaToCss(rgba); },
      canvas_width:      function () { return activeCanvas ? activeCanvas.width  | 0 : 0; },
      canvas_height:     function () { return activeCanvas ? activeCanvas.height | 0 : 0; },
      random_int:        function (max) { max = max | 0; return max > 0 ? (Math.random() * max) | 0 : 0; },
      time_ms:           function () { return (Date.now() & 0x3fffff) | 0; },
    }};
  }

  // ─────────────────────────────────────────────────────────────────────
  // 1. Hero particle animation (Krypton .ks → .wasm, drives <canvas>)
  // ─────────────────────────────────────────────────────────────────────

  function startHeroParticles() {
    var canvas = document.getElementById('heroCanvas');
    if (!canvas) return;

    // Size the canvas to its parent (the .hero div).
    function resize() {
      var parent = canvas.parentElement;
      if (!parent) return;
      canvas.width  = parent.offsetWidth;
      canvas.height = parent.offsetHeight;
    }
    resize();
    window.addEventListener('resize', resize);

    fetch('/particles.wasm', { cache: 'force-cache' })
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

          // RAF loop: each frame, point the host's "active canvas" at the
          // hero canvas and invoke _start() — particles.ks is the body of
          // _start, so each call is one full frame's worth of drawing.
          function frame() {
            setActiveCanvas(canvas);
            try { instance.exports._start(); }
            catch (e) { console.error('[Krypton] particles frame trap:', e); return; }
            setActiveCanvas(null);
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
