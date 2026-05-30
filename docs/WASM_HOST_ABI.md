# WASM Host ABI (Phase 1)

**This is a contract.** Both the Krypton-side emitter
(`compiler/wasm32/wasm_self.k`) and any host-side loader
(`scripts/run_wasm.js`, `web/site/dist/wasm_runner.js`, future WASI
wrapper) must match it byte-for-byte. Changes go through PR with both
agents reviewing.

## Module shape

Every Krypton-emitted module exports:

- `memory` — linear memory, initial 1 page (64 KiB), max unbounded.
- `_start: () -> ()` — entry point. Mirrors the body of
  `just run { ... }` in the source. Host calls this once after
  instantiation.

## Imports the host must provide

All under module name `env`.

```
console_log(ptr: i32, len: i32) -> ()
  Write [memory[ptr .. ptr+len)] to host stdout, interpreted as UTF-8.
  No automatic newline. Krypton's kp() emits its own "\n".

console_log_int(v: i32) -> ()
  Print decimal representation of v to host stdout, no newline.

console_log_int64(hi: i32, lo: i32) -> ()
  Print decimal representation of (i64) ((hi as u32) << 32 | (lo as u32))
  to host stdout, no newline. Used when Krypton emits 64-bit values
  (not in Phase 1.2; reserved).

console_log_f64(v: f64) -> ()
  Print decimal representation of v to host stdout, no newline.
  Reserved for Phase 1.6.

abort(code: i32) -> ()
  Reserved. Host should print a fatal-error message and stop calling.
  Phase 1.2 does not emit this; Phase 1.5 will.
```

If a host adds capabilities (fetch, fs, etc.) they go under a
different module name (`net`, `fs`, …) — never overload `env`.

## String representation

In linear memory: **pointer + length, no null terminator, UTF-8 bytes**.
The function signature `(ptr: i32, len: i32)` is the only string ABI in
Phase 1.

String literals from the source go in the Data section at offsets
computed by the emitter at build time. Pointer values are the offset
into linear memory (Data segment loads to offset 0 in Phase 1; future
phases may reserve a header region).

## Numeric representation

Phase 1 uses `i32` for every Krypton runtime value (small ints, pointer
offsets). No tagged pointers yet. No floats yet. Lessons that need
floats (none in 1-7) gate.

## Function table

Phase 1 emits direct calls only — no funcptr table. `BUILTIN <name> N`
in IR lowers to either an import (for `kp`) or a `call $<func>` direct
call (for user funcs).

`callPtr` and funcptr-style dispatch are deferred to Phase 1.5+; the
Element + Table sections will appear then.

## Versioning

If this file changes incompatibly, bump the doc version below.
Hosts that can't promise the new ABI should refuse to load modules
emitted under the new version.

**Current version: 1.0** (2026-05-30, Phase 1.0 skeleton).

## See also

- `docs/wasm_backend_design.md` — long-arc design
- `docs/WASM_PHASE_1_SPLIT.md` — Agent A / Agent B work split
- WebAssembly Core Spec § 4 (binary format)
- WASI snapshot preview1 (future Phase 1.5 alternative host)
