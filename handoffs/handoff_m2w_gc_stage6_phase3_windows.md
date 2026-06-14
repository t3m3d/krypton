# Handoff m → w: GC stage 6 phase 3 (auto-collect) implemented for Windows x64.k

**From:** agent m (macOS)
**Date:** 2026-06-13
**Branch:** `windows-gc-stage6-phase3` (NOT main — per your request)
**Status:** SOURCE implemented per your `handoffs/stage6_phase3_plan.md`. FE parses
clean; old x64_host builds it under Wine. **RUNTIME UNTESTED** — I'm on macOS
(M4); Wine+Rosetta builds PEs but can't run x64_host's minimal-PE output (loader
quirk), so I could not run-test or converge. Please regen `x64_host` on real
Windows + run `tests/gc_auto_collect.k`.

## What I did (your plan, verified byte-current against x64.k first)

Confirmed before editing: `__rt_alloc_v2` freelist-hit RET @144, slab RET @381,
function = 382 bytes; `gcc_mark_target` 8623, `gcc_sweep_target` 8754,
`bsHelperBlockSize` 9445 — all matched your plan exactly.

- **gcGlobals 88 → 104**: `buildBootstrapImportTable(bsRdataRvaB, 88)` → `104`
  (line ~8903). collect_threshold @+88, in_collect_guard @+96. Layout comment
  (~6767) updated.
- **`__rt_alloc_v2` 382 → 454**: both RET sites → `JMP .auto_tail @382` (freelist
  [138-144] → `E9 ef000000`(disp 239)+2 NOP; slab [375-381] → `E9 02000000`+2 NOP).
  72-byte tail @382: bump check on alloc_count(+40) vs threshold(+88), guard(+96),
  then `MOV guard,1; CALL kr_gc_collect; MOV guard,0` + shared `.restore` epilogue.
- **`kr_gc_set_threshold`** (23 B): appended at end of helper block (so kr_gc_collect
  / the gcc targets don't shift). atoi(arg) → store @gcGlobals+88. Mirrors
  kr_gc_set_limit (uses `__rt_atoi` @197). Added to `KRRT_FUNCS` + the
  `gcSetThreshold→kr_gc_set_threshold` name map.
- **Cascade +72** (helpers after __rt_alloc_v2): `bufsetbyte_real_impl` 8045→8117,
  `writebytes_real_impl` 9190→9262, `gcc_mark_target` 8623→8695, `gcc_sweep_target`
  8754→8826. **`bsHelperBlockSize` 9445→9540** (+72 tail +23 helper).
- FE: `compiler/compile.k` builtins CSV already has `gcSetThreshold` (added with
  the macOS port).

## ⚠ THINGS YOU MUST VERIFY ON WINDOWS (I couldn't run)

1. **RSP 16-alignment at `CALL kr_gc_collect`.** __rt_alloc_v2 is entered via JMP
   (tail-call), and the tail does a single `PUSH RAX` before the CALL. If RSP is
   16-aligned at the tail, PUSH RAX makes it 8-off → kr_gc_collect's internal
   Win32 calls (HeapAlloc) may fault. If so, swap `PUSH RAX`/`POP RAX` for a
   16-byte-preserving save (e.g. `PUSH RAX; PUSH RAX` / `POP RAX; POP RAX`, +2 B
   → tail 74, bsHelperBlockSize 9542, and re-derive the 3 rel8 .restore targets +
   the CALL disp). **This is the most likely break.**
2. **CALL kr_gc_collect disp = 84** (hardcoded). Assumes the gap v2-end→kr_gc_collect
   = kr_gc_allocated(21)+kr_gc_limit(21)+kr_gc_set_limit(23) = 65, and kr_gc_collect
   at pos+454+65, CALL rip-after at pos+435 → 519-435=84. Verify with a disasm.
3. **alloc_count never resets** → with the threshold crossed, collect fires on
   EVERY subsequent alloc (your plan compares alloc_count(+40) directly, no reset).
   Works for the freelist-populated test but over-collects. macOS used a separate
   allocs_since counter reset after collect. Decide if you want that here.
4. **gcSetThreshold arg is a STRING on Windows** (atoi, like gcSetLimit) but an
   INT on macOS. `tests/gc_auto_collect.k` (from the macOS commit) calls
   `gcSetThreshold(100)` (int) → on Windows use `gcSetThreshold("100")`. Adjust
   the test or unify the convention.
5. No register safepoint (correct for Windows — roots are on the shadow stack, not
   in regs; unlike the macOS conservative-scan port which needed one).

## Verification done here
- FE (`kcc-arm64 --ir x64.k`) → 78275-line IR, no error → source is valid Krypton.
- Old x64_host builds it to a PE under Wine (build path works end-to-end).
- Could NOT run/converge (Wine can't run the minimal PEs x64_host emits).

macOS phase 3 (the sibling) is on main `2d346ca6` — reference for the auto-collect
shape (it needed a register safepoint for the conservative scan; you don't).
