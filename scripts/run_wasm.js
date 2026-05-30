#!/usr/bin/env node
// scripts/run_wasm.js — Krypton WASM host loader / test runner (Agent B).
//
// Loads a Krypton-emitted .wasm module, provides the host imports defined in
// docs/WASM_HOST_ABI.md (v1.0), runs `_start`, and writes whatever the module
// printed to stdout — byte-for-byte, no added newlines (kp() emits its own).
//
// Usage:
//   node scripts/run_wasm.js path/to/module.wasm
//
// Exit codes (for tests/wasm/RUN.sh):
//   0  ran, _start returned normally
//   1  usage / file error
//   2  instantiation failed (bad module / missing import)
//   3  trap or host abort() during _start
//
// Contract: docs/WASM_HOST_ABI.md. All imports live under module "env".
// If the ABI gains capabilities they go under new module names (net, fs, …) —
// this loader must be updated in lockstep via the shared-contract PR.

'use strict';

const fs = require('fs');

function die(code, msg) {
  process.stderr.write('run_wasm: ' + msg + '\n');
  process.exit(code);
}

const wasmPath = process.argv[2];
if (!wasmPath) die(1, 'usage: node run_wasm.js <module.wasm>');

let wasmBytes;
try {
  wasmBytes = fs.readFileSync(wasmPath);
} catch (e) {
  die(1, 'cannot read ' + wasmPath + ': ' + e.message);
}

// Captured stdout fragments — joined and written once at the end so partial
// output on a trap is still observable but ordering is deterministic.
const out = [];
const dec = new TextDecoder('utf-8');

let instance = null;
let aborted = false;

// Re-read the memory view on every call: linear memory can grow, which
// detaches any previously-held ArrayBuffer.
function mem() {
  return new Uint8Array(instance.exports.memory.buffer);
}

const imports = {
  env: {
    // console_log(ptr,len): write [ptr..ptr+len) as UTF-8, no auto newline.
    console_log(ptr, len) {
      out.push(dec.decode(mem().subarray(ptr, ptr + len)));
    },
    // console_log_int(v): decimal int, no newline.
    console_log_int(v) {
      out.push(String(v | 0));
    },
    // console_log_int64(hi,lo): (u32 hi)<<32 | (u32 lo), decimal, no newline.
    console_log_int64(hi, lo) {
      const v = (BigInt.asUintN(32, BigInt(hi)) << 32n) |
                BigInt.asUintN(32, BigInt(lo));
      out.push(v.toString());
    },
    // console_log_f64(v): decimal float, no newline. (Reserved, Phase 1.6.)
    console_log_f64(v) {
      out.push(String(v));
    },
    // abort(code): fatal host error; stop running. (Reserved, Phase 1.5.)
    abort(code) {
      aborted = true;
      throw new WebAssembly.RuntimeError('module called env.abort(' + code + ')');
    },
  },
};

function flush() {
  if (out.length) process.stdout.write(out.join(''));
}

(async () => {
  let res;
  try {
    res = await WebAssembly.instantiate(wasmBytes, imports);
  } catch (e) {
    die(2, 'instantiate failed: ' + e.message);
  }
  instance = res.instance;

  if (typeof instance.exports._start !== 'function') {
    die(2, "module has no exported _start() — see WASM_HOST_ABI.md");
  }
  if (!(instance.exports.memory instanceof WebAssembly.Memory)) {
    die(2, "module does not export 'memory' — see WASM_HOST_ABI.md");
  }

  try {
    instance.exports._start();
  } catch (e) {
    flush();
    if (aborted) die(3, e.message);
    die(3, 'trap during _start: ' + e.message);
  }

  flush();
  process.exit(0);
})();
