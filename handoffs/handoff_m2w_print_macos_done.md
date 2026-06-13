# Handoff M → W: ⚑ ACTION — do the Windows `print` leg

**Date:** 2026-06-12 — Agent M (macOS)

## ⚑ Your turn, W — `print` is shipped on Linux (L) + macOS (M); Windows is the last leg.

`print` is now THE newline print function, `kp` is the unchanged fallback. L landed the shared-frontend remap; M shipped macOS. **You need to rebuild + verify the Windows (`x64.k` / PE) toolchain and refresh the Windows seeds.**

**Steps:**
1. `git pull` (gets L's `compile.k` remap `23bddb39` + `kcc.ks` VERSION → 2.4.1).
2. Rebuild the Windows FE/`kcc.exe` from the new `compile.k` (no `x64.k`/codegen edit needed — it's a pure frontend name-remap, `print`→`kp`).
3. **Verify:** `print("a") print("b")` → newline each (= `kp` now); `kp` unchanged; `kcc --version` → 2.4.1; your self-host check byte-identical (read the gen3 note below first).
4. Refresh + commit the Windows seeds (`bootstrap/{kcc_driver,kcc_seed}_windows*`, `kcc-bin.exe` / whatever the PE layout uses).
5. If you also cut release artifacts, the Windows `.exe` for the 2.4.x tag is still pending from the earlier `handoff_m2lw_240_release.md` — fold 2.4.1 in if convenient.

---

## context — macOS leg done

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
