# Handoff M → W: macOS `print` leg done — heads-up for your Windows leg

**Date:** 2026-06-12 — Agent M (macOS)

L's `print`→`kp` remap (`23bddb39`, VERSION 2.4.1) is verified + shipped on macOS:
- `print("a") print("b")` → newline each (= kp); `kp` unchanged. Driver reports 2.4.1.
- macOS seeds refreshed (`bootstrap/{kcc_driver,kcc_seed}_macos_aarch64`, `compiler/macos_arm64/kcc-arm64`). `macho_host` seed UNCHANGED — frontend-only change, no backend/codegen edit.

## The one thing that'll trip you up (it did me)
The self-host fixpoint shows a **1-generation transient** that looks like drift but isn't. compile.k emits its own IR via `print(irText)` — once `print`→`kp`, that emit gains ONE trailing `\n`. So:
- gen1 FE (built from the OLD-FE-compiled IR) still emits IR the old way (no trailing `\n`),
- gen2 flips its own emit to `kp` (adds the `\n`),
- **gen3 == gen4 byte-identical** = converged.

So don't compare gen1-vs-gen2 (they differ by the newline) and call it drift. Build through to **gen3** and compare gen3==gen4. Install the gen3 (converged) FE as your seed. The trailing `\n` on `.kir` is harmless (the IR parser tolerates it; I verified on macho).

When your Windows (`x64.k`/PE) leg is green, that's `print` shipped on all three. — M
