// web/site/dist/wasm_runner.js — Krypton browser WASM loader (Agent B, Phase B.4).
//
// Drop-in enhancement for the lesson "Run" button. Loads AFTER runner.js and
// wraps window.runK so that:
//
//   • if the lesson code box is UNMODIFIED and a precompiled
//     /learn/<slug>.wasm exists  → run the real Krypton-emitted WASM
//     (host imports per docs/WASM_HOST_ABI.md v1.0), output → .run-out;
//   • otherwise (edited code, no .wasm, fetch/instantiate/trap error)
//     → fall back to runner.js's JS-bridge (the original window.runK).
//
// This keeps the "edit the box, hit Run" UX working (JS bridge transpiles the
// live edit) while shipping genuine compiled WASM for the as-authored lesson.
//
// ── Wiring (Agent B owns this hook; spec'd here, applied in export.htk later) ──
//   1. export.htk's build loop runs the emitter per lesson:
//        wasm_self  dist/learn/<slug>.kir  dist/learn/<slug>.wasm
//      (only for lessons the emitter can lower; skip the rest — a missing
//       .wasm simply falls back to the JS bridge, no page change needed).
//   2. Each lesson page adds, AFTER the runner.js include:
//        <script src="/wasm_runner.js?v=1"></script>
//   No other page edits. Pages with no .wasm behave exactly as today.
//
// Contract: ABI changes go through the shared WASM_HOST_ABI.md PR (rule #3).

(function () {
  'use strict';

  // Derive the lesson slug from /learn/<slug>.html
  function lessonSlug() {
    var m = (location.pathname || '').match(/\/learn\/([^\/]+?)\.html?$/i);
    return m ? m[1] : null;
  }

  // Host imports — identical surface to scripts/run_wasm.js. No added newlines;
  // kp() emits its own. Returns { run(bytes) -> Promise<string> }.
  function makeHost() {
    var out = [];
    var dec = new TextDecoder('utf-8');
    var instance = null;
    function mem() { return new Uint8Array(instance.exports.memory.buffer); }
    var imports = { env: {
      console_log: function (ptr, len) { out.push(dec.decode(mem().subarray(ptr, ptr + len))); },
      console_log_int: function (v) { out.push(String(v | 0)); },
      console_log_int64: function (hi, lo) {
        var v = (BigInt.asUintN(32, BigInt(hi)) << 32n) | BigInt.asUintN(32, BigInt(lo));
        out.push(v.toString());
      },
      console_log_f64: function (v) { out.push(String(v)); },
      abort: function (code) { throw new WebAssembly.RuntimeError('env.abort(' + code + ')'); },
    }};
    return {
      run: function (bytes) {
        return WebAssembly.instantiate(bytes, imports).then(function (res) {
          instance = res.instance;
          if (typeof instance.exports._start !== 'function')
            throw new Error("module missing exported _start()");
          if (!(instance.exports.memory instanceof WebAssembly.Memory))
            throw new Error("module missing exported memory");
          instance.exports._start();
          return out.join('');
        });
      },
    };
  }

  // Per-slug cache of "does a .wasm exist?" so we only probe the network once.
  var wasmAvail = {}; // slug -> Promise<ArrayBuffer|null>
  function fetchWasm(slug) {
    if (wasmAvail[slug]) return wasmAvail[slug];
    var p = fetch('/learn/' + slug + '.wasm', { cache: 'force-cache' })
      .then(function (r) { return r.ok ? r.arrayBuffer() : null; })
      .catch(function () { return null; });
    wasmAvail[slug] = p;
    return p;
  }

  var slug = lessonSlug();
  var jsBridge = window.runK; // the runner.js implementation (may be undefined)

  // If there's no slug or no JS bridge to fall back to, leave runK untouched.
  if (!slug || typeof jsBridge !== 'function') return;

  // Record each code box's as-shipped source so we can tell if the user edited.
  document.addEventListener('DOMContentLoaded', function () {
    document.querySelectorAll('pre code.k').forEach(function (code) {
      code.dataset.korig = (code.innerText || code.textContent);
    });
  });

  window.runK = function (btn) {
    var wrap = btn.parentElement;
    var code = wrap.querySelector('pre code.k');
    var out = wrap.querySelector('.run-out');
    if (!code || !out) return (jsBridge ? jsBridge(btn) : undefined);

    var cur = (code.innerText || code.textContent);
    var orig = code.dataset.korig;
    var edited = (orig != null && cur !== orig);

    // Edited code → only the JS bridge reflects the live source.
    if (edited) return jsBridge(btn);

    var label = btn.textContent;
    btn.disabled = true;
    btn.textContent = 'Running…';

    fetchWasm(slug).then(function (bytes) {
      if (!bytes) {                 // no precompiled wasm → JS bridge
        btn.disabled = false; btn.textContent = label;
        return jsBridge(btn);
      }
      out.className = 'run-out';
      out.textContent = '';
      makeHost().run(bytes).then(function (text) {
        out.textContent = text.length ? text : '(no output)';
        out.className = 'run-out ok';
        btn.disabled = false; btn.textContent = label;
      }, function () {              // trap / bad module → JS bridge
        btn.disabled = false; btn.textContent = label;
        jsBridge(btn);
      });
    });
  };
})();
