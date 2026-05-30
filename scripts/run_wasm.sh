#!/usr/bin/env bash
# scripts/run_wasm.sh — portable wrapper around the Krypton WASM host loader.
#
# Usage: run_wasm.sh path/to/module.wasm
#
# Prefers Node (scripts/run_wasm.js — the canonical, fully-tested loader).
# Falls back to macOS JavaScriptCore (osascript -l JavaScript) ONLY when Node
# isn't installed — for Node-less Macs, per WASM_PHASE_1_SPLIT.md B.2.
#
# Both paths implement the exact same env imports from docs/WASM_HOST_ABI.md.
# Output is byte-for-byte stdout, no added newlines.
#
# NOTE: the osascript fallback is macOS-only and cannot be exercised on the
# Windows dev box — it needs a smoke test on the Mac (Agent A territory to
# verify). The Node path is the one used everywhere Node exists.

set -u
DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WASM="${1:-}"

if [[ -z "$WASM" ]]; then
  echo "usage: run_wasm.sh <module.wasm>" >&2
  exit 1
fi

# Preferred path: Node.
if command -v node >/dev/null 2>&1; then
  exec node "$DIR/run_wasm.js" "$WASM"
fi

# Fallback: macOS JavaScriptCore via osascript. Reads the file through the
# Foundation bridge, mirrors run_wasm.js's env imports, runs _start.
if command -v osascript >/dev/null 2>&1; then
  osascript -l JavaScript - "$WASM" <<'JXA'
function run(argv) {
  ObjC.import('Foundation');
  const path = argv[0];
  const data = $.NSData.dataWithContentsOfFile(path);
  if (!data || data.length === 0) { throw new Error('cannot read ' + path); }
  const buf = new ArrayBuffer(data.length);
  data.getBytesLength($(buf), data.length);
  const out = [];
  const dec = new TextDecoder('utf-8');
  let instance = null;
  const mem = () => new Uint8Array(instance.exports.memory.buffer);
  const imports = { env: {
    console_log: (p, l) => { out.push(dec.decode(mem().subarray(p, p + l))); },
    console_log_int: (v) => { out.push(String(v | 0)); },
    console_log_int64: (h, l) => {
      const v = (BigInt.asUintN(32, BigInt(h)) << 32n) | BigInt.asUintN(32, BigInt(l));
      out.push(v.toString());
    },
    console_log_f64: (v) => { out.push(String(v)); },
    abort: (c) => { throw new Error('module called env.abort(' + c + ')'); },
  }};
  const mod = new WebAssembly.Module(new Uint8Array(buf));
  instance = new WebAssembly.Instance(mod, imports);
  instance.exports._start();
  return out.join('');
}
JXA
  exit $?
fi

echo "run_wasm.sh: need either 'node' or macOS 'osascript' to run WASM" >&2
exit 1
