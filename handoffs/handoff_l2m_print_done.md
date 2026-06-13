# Handoff L → M: `print`-as-newline-print DONE on Linux — your macOS seed leg is next

**Date:** 2026-06-13
**From:** Agent L (Linux, Arch/Hyprland box)
**To:** Agent M (macOS)
**Re:** your `handoff_m2l_print_alias.md` (remap `print` → `BUILTIN_KP`)

## Done exactly as you specced — one frontend edit
`compiler/compile.k` (the builtin-call IR emitter, ~line 1426): when the source
calls `print`, the frontend now emits `BUILTIN kp <argc>` instead of
`BUILTIN print <argc>`. So `print` routes to the proven newline op on every
backend with **zero codegen edits**; `kp` is untouched and stays the fallback.

```
let bname = fname
if bname == "print" { bname = "kp" }
emit code + "BUILTIN " + bname + " " + argc + "\n," + (p + 1)
```

(I first wrongly did a per-backend `linux_arm64/elf.k` edit — backed it out via
`git reset --hard` before it ever hit origin. The frontend remap is the only
change.)

## Verified on Linux x86 (all green)
- **IR remap:** `print("P")` → `BUILTIN kp 1`; `kp("K")` → `BUILTIN kp 1`. No
  `BUILTIN print` left in emitted IR.
- **Self-host fixpoint:** rebuilt the FE from the new `compile.k` (gen1), rebuilt
  again with gen1 (gen2). `gen1.kir == gen2.kir` **byte-identical**, and the gen1
  vs gen2 **binaries are identical**. Your trailing-`\n` analysis holds — the 4
  `print(...)` IR-emit sites in `compile.k` (now newline) are harmless; fixpoint
  stays exact.
- **`build.sh test`:** 56 passed / 0 failed / 3 skipped (with the new seed).
- **print/kp runtime:** `print("P"); kp("K")` → `P\nK\n`. Both newline. ✓
- No-newline reliance check: only real `print()` users off the compiler are
  `result.k`/`option.k` error messages — a trailing newline there is harmless.

## Linux seeds refreshed + committed (this push)
- `bootstrap/kcc_seed_linux_x86_64` + `compiler/linux_x86/kcc-x64` — rebuilt FE
  carrying the remap (the validated gen1; fixpoint-stable).
- `bootstrap/kcc_driver_linux_x86_64` — rebuilt from `kcc.ks`, now reports
  **`kcc version 2.4.1`** (smoke-tested: `--version`, `--native`, `-r`).
- `elf_host`/`optimize_host` unchanged (their sources didn't change).

## Version: 2.4.1 (Brian's call — keep it consistent)
`kcc.ks VERSION() -> "kcc version 2.4.1"`. Please bump the macOS driver to match
when you refresh the macОS seeds.

## ⚑ FYI — a stale version string I did NOT touch (your call)
`compiler/compile.k:2555` has its **own** `kccVer = "2.3.0"` (used by the FE's
`--version`, which `build.sh`'s final "Build complete" line reads). You left this
at 2.3.0 through the whole 2.4.0 release, so I treated it as vestigial and did
**not** bump it (avoids a second FE rebuild). The canonical `kcc --version`
(driver) correctly says 2.4.1. If you want the FE string maintained too, bump
`kccVer` → 2.4.1 and re-seed — but that's a deliberate choice, not done here.

## Your leg (macOS) + W (Windows)
- **M:** rebuild the macOS toolchain (`kcc-arm64` FE picks up the remap;
  `macho_host` unchanged), refresh `bootstrap/{kcc_seed,macho_host,kcc_driver}_macos_aarch64`,
  verify `print` newlines + `kp` + fixpoint, driver `--version` → 2.4.1, commit
  the macOS seeds.
- **W:** Windows FE re-seed (`x64.k` already maps `print`→`kr_print`; the remap
  makes the IR emit `kp`, which Windows also maps to `kr_print` — so no codegen
  change, just a FE reseed + version).

Pushed to `main`. Ping me if the macOS fixpoint diverges. — L
