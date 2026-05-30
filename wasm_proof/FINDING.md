# WASM Phase 0 — Resolved: writeBytes + hex-encoded byte string

**Date:** 2026-05-30.
**Status:** ✅ working. `hello.wasm` emitted from pure Krypton, loaded and
executed by WebAssembly, prints "Hello".

## What works

`wasm_proof/hello_wasm.htk` builds a valid 95-byte WebAssembly module that:

- Imports `env.console_log(i32, i32)` from the host.
- Allocates one page of linear memory (64KB).
- Exports `memory` and `_start`.
- `_start` calls `console_log(0, 5)`, which the host wires to read "Hello"
  from linear memory offset 0.
- Data section places "Hello" at offset 0.

Hex dump:

```
00000000: 0061 736d 0100 0000 0109 0260 027f 7f00  .asm.......`....
00000010: 6000 0002 1301 0365 6e76 0b63 6f6e 736f  `......env.conso
00000020: 6c65 5f6c 6f67 0000 0302 0101 0503 0100  le_log..........
00000030: 0107 1302 066d 656d 6f72 7902 0006 5f73  .....memory..._s
00000040: 7461 7274 0001 0a0a 0108 0041 0041 0510  tart.......A.A..
00000050: 000b 0b0b 0100 4100 0b05 4865 6c6c 6f    ......A...Hello
```

Run-through via JavaScriptCore (osascript -l JavaScript):

```
bytes=95
Module instantiated OK
OUTPUT: Hello
```

## The two issues that were resolved

### 1. `\0` bytes drop with `fromCharCode(0) + ...` concat

**Cause.** Krypton strings are C-style null-terminated, so concatenating
`fromCharCode(0)` either drops the byte or truncates the string.

**Fix.** Use the `writeBytes(path, hexString)` pattern that elf.k and
macho_arm64_self.k already use. Encode each byte as `"x" + HH` (e.g.
`"x00"` for `\0`); `writeBytes` decodes the hex pairs into raw bytes and
writes them. The relevant builtin definitions live in elf.k:28 (`hexByte`,
`hexWord`, `hexDword`).

### 2. `s[i]` on a Krypton string returns a 1-char string, not an int

**Cause.** `toInt(s[i])` parses the character as a number; "e" isn't a
valid integer, so it becomes 0.

**Fix.** Use the `charCode` builtin: `toInt(charCode(s[i]))` returns
the codepoint. Used by stdlib/url.k:35 for hex parsing — same pattern.

## What this confirms

The full design in `docs/wasm_backend_design.md` is mechanically
implementable in Krypton today, on the current 2.0.0 / 2.1 toolchain,
without any new runtime primitives. Phase 1 (IR → WASM lowering) can
start whenever.

The proof binary is 95 bytes, matching the section-by-section sizes
predicted in the design doc.

## Files

- `hello_wasm.htk`  — the proof script
- `/tmp/hello.wasm` — the output binary (validated)

## Next step

Phase 1: build a minimal IR-to-WASM lowering. Take a 3-line Krypton
program through `kcc --ir` and emit a `.wasm` that produces the same
output. Pick `tutorial/01_hello_world.k` as the first end-to-end test.

The proof script's helpers (`hexByte`, `b`, `leb`, `bstr`,
`wasmSection`) are direct fits for the v1 backend — lift them into
`compiler/wasm32/wasm_self.k` with the same signatures.

## See also

- `docs/wasm_backend_design.md` — full design context
- `compiler/linux_x86/elf.k`   — hexByte/hexWord helper source
- `compiler/macos_arm64/macho_arm64_self.k` — same pattern for Mach-O
- stdlib/url.k — charCode usage example
