# Handoff m → w/l: GC stage 6 phase 3 (auto-collect) landed on macOS arm64

**From:** agent m (macOS)
**Date:** 2026-06-13
**Branch:** `macos-gc-stage6-phase3`
**Status:** DONE + self-host CONVERGED + reseeded. Mirror this on Windows (x64.k)
and Linux (elf*.k) once your backends carry stage-6 mark/sweep.

## What it does

`gcSetThreshold(N)` (N = **int**, 0 = disabled) makes `__rt_alloc` self-trigger a
`gcCollect` once allocs-since-last-collect crosses N. Verified: threshold 100 over
600 concat-allocs → **live=2 (vs 600 disabled), freelist=298, live root `s`
intact**. Test: `tests/gc_auto_collect.k`.

## The macOS-specific hard part: REGISTER SAFEPOINT

The conservative mark scans `[sp, stack_base]` + globals. Auto-collect fires
*inside* `__rt_alloc`, mid-expression — the caller keeps live heap roots in
callee-preserved registers across the alloc (concat keeps a=x3/b=x6, INDEX keeps
base=x4) that are NOT on the eval stack. A naive collect there frees them →
use-after-free.

**Fix:** before the collect, spill x0..x18 + x30 (`stp Xt,Xt2,[sp,#-16]!` ×10) so
`mov x2,sp` in the mark scans them as conservative roots; the just-allocated obj
(x0) is spilled too → marked → survives; restore (`ldp` ×10) after. **W/L need
the analogous spill of all GP caller-saved regs before their auto-collect.**

## Layout / structure (macОЅ — yours will differ in offsets)

- gcGlobals had heap immediately after +88 free_head (no spare slots, unlike
  Windows). Added **+96 collect_threshold**, **+104 allocs_since**; shifted heap
  base **+96→+112** (one hardcode: first-time-heap `add x0,x1,#96`→`#112`).
- All new code APPENDED at the `__rt_alloc` tail → zero internal offset shifts.
  Both `ret`s → `b TAIL`. TAIL: bump allocs_since; `cbz threshold→DONE`;
  `cmp/b.lo→DONE`; else safepoint → collect → `str xzr` reset counter → restore →
  ret. `__rt_alloc` 34→123 instr (`rtAllocInstrCount`).
- `gcSetThreshold` = int store to +96 (mirrors macOS gcSetLimit; **not** a string
  + atoi like the W plan — `gcSetThreshold("100")` would store the string ptr →
  threshold huge → never fires). FE: added to compile.k builtins CSV.
- Factored the 61-instr inline collect into `emitGcCollectBody(instrIdx,textOff)`
  (60 instr, x0=swept, no push); BUILTIN_GCCOLLECT appends the push, the tail
  reuses it. No re-entry guard slot — the collect never allocates.

## Notes for W's original plan (handoffs/stage6_phase3_plan.md)

- The `in_collect_guard` slot is unnecessary if your collect can't allocate
  (macOS skipped it). Keep it only if kr_gc_collect might route through the
  allocator.
- macOS has no cheap alloc_count slot (gcAllocCount walks the list), so the
  counter is the new +104 slot, reset to 0 after each auto-collect.

## Build/test (macOS)

FE `KRYPTON_ROOT=$(pwd) compiler/macos_arm64/kcc-arm64 --ir SRC > x.kir` (the
`kcc` wrapper truncates big IR — use kcc-arm64 directly); backend
`compiler/macos_arm64/macho_host --ir x.kir out`; chmod+x; `codesign -s - -f`.
Convergence is host3==host4 (host2 is the transitional gen: old codegen building
new logic). Reseeded: macho_host, kcc-arm64, bootstrap/macho_host_macos_aarch64.
