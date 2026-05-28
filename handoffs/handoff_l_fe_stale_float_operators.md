# Note (l): the committed Linux FE binary is STALE — blocks float operators + A4–A7

**From:** agent l (Linux)
**Date:** 2026-05-28
**Re:** full A1 parity (f64 operators); the broader FE-binary staleness on this branch

## Finding

On `feat/arm64-native-pipeline`, the committed Linux front-end binaries
(`compiler/linux_x86/kcc-x64`, `bootstrap/kcc_driver_linux_x86_64`, both git-tracked,
mtime 2026-05-28) are **stale** relative to `compiler/compile.k`. compile.k HAS the
A1–A7 work committed (e.g. `901e3071` A7 float compound-assign, `19c9fda0` A5 arrays,
`07aa9d10` A6 static locals, `9647c73f` A4 printf — all ancestors of HEAD), but the
built FE predates them.

Symptoms via the committed FE:
- `3.0 * 2.0` emits integer `MUL` (not `BUILTIN fmul`).
- static locals → `UNSUPPORTED`; arrays/printf likewise behind.

## What I verified (gen1 self-host)

Rebuilt the FE from current compile.k (stale kcc-x64 compiling compile.k → /tmp/new_kcc).
The fresh FE:
- `3.0 * 2.0` → **`BUILTIN fmul 2`** ✓ (literal float operators work).
- has A6 static-local handling (7 STATIC hits vs the stale binary's 1).

So float **literal** operators (and A4–A7) come alive simply by rebuilding the FE.

## Still broken even after rebuild (separate FE bug)

**Variable-typed** float operators still emit `MUL`/`ADD`:
`let a = 3.0; let b = 2.0; a * b` → `MUL`. The literal's `;f64` pair-type tag
(irPrimary, ~line 1229) is correct, and operator inference (irMultiplicative ~1072,
irAdditive ~1045) reads `pairType`, but the **let-binding type isn't tracked** so a
later `LOAD a` doesn't report f64. That's the remaining gap for `tests/test_float.k`'s
operator/compound-assign section. Needs `let a = <f64expr>` to record a's type in the
`types` table that irPrimary consults for identifiers.

## Why I didn't just commit a rebuilt FE

Swapping the FE binary is whole-toolchain blast radius (every feature, every backend).
It needs: gen2 self-host **convergence** (gen1==gen2 IR) + the **full test suite**
green on Linux (x86 + arm64) before trusting it — and FE work is Windows-first/shared
(see project-krypton-language-roadmap). I restored the pristine binaries; tracked tree
is clean. Backend side is DONE: all A1 explicit builtins + intToFloat/floatToInt land
on both Linux ELF backends (commits 7097a7ca, f7e73c46, f57dfefa, 2c01ba2f), so once
the FE is rebuilt + the let-type fix lands, operators light up with **no backend
change** (they lower to the fadd/fmul builtins already implemented).

## Action for whoever owns the FE (W/M or a focused session)

1. Fix let-binding f64 type tracking in compile.k (the `types` table for identifiers).
2. Rebuild kcc-x64 (+ driver) from compile.k; verify gen2 convergence.
3. Run the full suite on x86 + arm64 (a64_baseline.sh) — confirm no A4–A7 regressions.
4. Then remove the `tests/test_float.k` off-macOS skip in build.sh.
