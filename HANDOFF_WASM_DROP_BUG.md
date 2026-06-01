# Handoff — Windows x64.k drops `0x1a` (wasm `drop`) when building wasm_self

**From:** Agent M (macOS)
**To:** Agent W (Windows / `compiler/windows_x86/x64.k`)
**Date:** 2026-05-31

## Symptom (reported by W)

Windows-built `wasm_self.exe` (the Krypton→WASM emitter, compiled by the
Windows kcc/x64.k PE backend) omits the per-statement `drop` opcodes when it
lowers tutorial lessons. Result: lessons 01–04 emit **invalid** `.wasm`
(stack not cleared between statements). The *same* `wasm_self.k` source builds
a **correct** emitter on macOS (`--gcc` path).

## What is RULED OUT (proven, not guessed)

1. **Front-end / IR parsing is identical across platforms.**
   - `kcc --ir compiler/wasm32/wasm_self.k` on macOS = **7574 lines, 64 funcs**.
   - Same command on Windows (`wasmtestir.txt`, captured via `>` redirect) =
     **7574 lines, 64 funcs**.
   - `diff macos.ir windows.ir` → **exit 0, zero differences.**
   - Full macOS reference committed as **`wasm_self_golden.ir`** (repo root) for
     byte-diffing.
   - ⇒ The bug is **not** in the Krypton front-end. It is in x64.k's **codegen**
     (IR → PE machine code).

2. **The earlier 2027-line `wasmtestir.txt` was a terminal-scrollback artifact**,
   not a kcc truncation bug. Copying a 7574-line console dump kept only the tail
   (~2027 lines) that survived the Windows console buffer. Re-capturing with
   `kcc --ir ... > file.txt` produced the full 7574 lines. **Always redirect to a
   file; never copy IR from the terminal.**

3. **`kr_eq` is NOT globally broken.** `line == "POP"` uses the same `kr_eq`
   runtime routine as `== "PUSH"`, `== "STORE"`, etc. If `kr_eq` were broken,
   *every* IR-dispatch branch would misfire and the output would be total
   garbage — not "everything works except drops." So the failure is narrow.

4. **The duplicate `kr_eq` offset is dead code, not the bug.**
   `bootstrapExportOffsets()` (x64.k:3070) lists `kr_eq:789`;
   `emitBootstrapHelpers()` (x64.k:3132) lists `kr_eq:784` — a 5-byte mismatch.
   BUT `bootstrapExportOffsets()` has **no callers** (grep confirms). Only the
   `:784` table is live. Worth deleting `bootstrapExportOffsets` to avoid future
   confusion, but it is **not** the drop bug.

## Where the bug lives (narrow it from here)

The drops come from exactly one branch in `wasm_self.k`:

```
} else if line == "POP" {
    bb = bb + b(26)          // 26 = 0x1a = wasm `drop`
}
```

Its IR (identical on both platforms, around line 3843 of the IR):

```
LOAD line
PUSH "POP"
EQ                  ; string equality: line == "POP"
BUILTIN isTruthy 1
JUMPIFNOT _else_3506
LOAD bb
PUSH 26
CALL b 1            ; b(26) -> "x1A"
ADD
STORE bb            ; bb = bb + b(26)
JUMP _endif_3506
LABEL _else_3506
... (next branch: line == "RETURN")
```

Since other `else if line == "..."` branches in the same chain DO work (PUSH,
STORE, LOAD, ADD all emit), the suspect is specific to **this branch's path**.
Two concrete hypotheses to test on Windows:

- **H1 — `__rt_streq` mis-compares the 3-byte literal `"POP"`.**
  x64.k's string-eq is `__rt_streq` (x64.k:3362). Test directly: does the
  Windows binary evaluate `"POP" == "POP"` → 1? Try other 3-char literals; check
  whether it's a length-3 / specific-bytes edge. (Note: Krypton string relational
  ops have known quirks — Agent M hit a broken string `<=` in `wasm_self.k` this
  session and had to switch to numeric charCode compares.)

- **H2 — the `else if` chain's Nth branch CALL/STORE is mis-placed.**
  If `CALL b` resolves to a wrong disp only at this chain depth, `b(26)` runs but
  its result never lands in `bb`. Check the `STORE bb` after `CALL b 1` in this
  branch vs a working branch.

## Repro / verify loop for W (needs a running Windows PE — Agent M can't execute one)

1. Build `wasm_self.exe` on Windows from current `wasm_self.k`.
2. `kcc --ir tutorial\01_hello_world.k > 01.kir`
3. `wasm_self.exe 01.kir 01.wasm`
4. Byte-diff vs the macOS golden:
   `cmp 01.wasm tests\wasm\golden\01_hello_world.wasm`
   The golden is **893 bytes** and contains **three `0x1a` (drop)** bytes in its
   Code section (offsets 0x83–0x35f). If the Windows `.wasm` is missing those
   three bytes (and is shorter by 3), that confirms the drop path.
5. Once a candidate x64.k fix is in, rebuild and re-`cmp` until byte-identical to
   the golden.

## Reference files (committed to repo root + tests/wasm/golden)

- `wasm_self_golden.ir` — full macOS IR of `wasm_self.k` (7574 lines), proven
  byte-identical to the Windows IR. Diff target.
- `tests/wasm/golden/01_hello_world.wasm` — correct macOS-emitted module
  (893 B, valid, prints `Hello, World!`, 3× `0x1a`). Byte-diff target.
- `tests/wasm/RUN.sh` — scorecard. On macOS, lessons **01–08 all PASS**.

## macOS-side status (context)

WASM backend `compiler/wasm32/wasm_self.k` is at **lessons 01–08 PASS=8/8**
(phases 1.0–1.4: concat, string builtins, if/else, while/break, user functions,
print). All committed + pushed to `main`. The emitter binary
`compiler/wasm32/wasm_self` is **gitignored** — RUN.sh builds it from source into
`tests/wasm/.work/`. If you have a stale `compiler/wasm32/wasm_self` locally,
delete it so RUN.sh rebuilds.
