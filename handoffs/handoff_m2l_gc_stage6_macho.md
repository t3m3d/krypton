# m → l : GC stage 6 (freelist) landed on Mach-O — mirror to ELF

**From:** agent m (macOS) — **Date:** 2026-06-13
**Status:** DONE + self-host-converged on `compiler/macos_arm64/macho_arm64_self.k`.

macOS now matches the Windows stage 6 merge (ph1 + ph2). Mirror to `compiler/linux_*/elf*.k` when ready. Phase 3 (auto-trigger gcCollect on threshold, see `stage6_phase3_plan.md`) still deferred everywhere.

## What landed

**Phase 1 — freelist construction.** `gcSweep` (standalone) AND `gcCollect`'s
inline sweep now push each unmarked node onto a freelist head instead of
dropping it. `gcReset` zeroes the head. `gcFreelistCount` is a real walk
(was a stub→0).

**Phase 2 — consumption.** Allocation now recycles freelist nodes. Because
the macOS backend INLINES allocation at ~25 sites (no callable allocator like
Windows' `__rt_alloc_v2`), I refactored alloc into a single callable helper:
- New `__rt_alloc` helper appended to `__text` after all user functions
  (`emitRtAllocHelper`, 34 instrs). Input x4=size, returns x0=ptr.
- `emitAllocN`/`emitAllocVar` became 21-instruction **trampolines** into it.
  Kept at EXACTLY 21 instrs so none of the ~25 call sites' offsets change.
- Helper does: alloc_total update + limit check → freelist-fit check
  (size_flags >= request; no masking — swept nodes have mark bit clear and
  sizes are 8-aligned) → else bump. Relinks reused node into gcAllocsHead.
- `g_RT_ALLOC_INSTR` = total user-func instrs, set in `emitTextFromIR`;
  `computeTextSize` += helper size.

## Three gotchas that cost me (you WILL hit the analogues on ELF)

1. **free_head slot collision.** First put free_head at gcGlobals **+56** —
   which is the **getLine cache** (+56/64/72) + envp save (+80). The compiler
   uses getLine constantly → it overwrote free_head → freelist deref crashed
   with x0 pointing into a string ("C Krypton"). Moved free_head to **+88**
   (only free slot before heap @ +96). Pick a slot ELF's runtime genuinely
   leaves free.

2. **Trampoline return register.** Tried `adr x16; b __rt_alloc` (x16 return) —
   broke self-host: the backend keeps live values in x16 across allocs. Tried
   `bl` (x30) bare — fine for the link reg itself, but…

3. **x4 (size) clobber.** `INDEX` (`s[i]`) keeps the **string base in x4**
   across the alloc; the old inline `emitAllocN` never touched x4 so it worked.
   The new trampoline's `movz x4,size` destroyed it → `ldrb [x4,x3]` crash.
   Fix: `emitAllocN` brackets its `bl` with `stp x4,x30 / ldp x4,x30` to
   preserve BOTH the caller's x4 and the link reg. Net helper clobber set =
   {x0,x1,x2,x9,x11} (+x30 saved) = intersection of the old emitAllocVar /
   emitAllocN contracts, so no call site breaks.

## Verified

- ph1: `gcSweep`→freelist 3==swept 3; `gcCollect` parks 30 → `gcFreelistCount`=30.
- ph2: `tests/gc_freelist_consume`-style — 30 → 25 after 5 reuse allocs.
- `s[i]`, replace, concat, gc_alloc_count: all clean.
- **Self-host CONVERGED**: gen2==gen3 byte-identical except the ad-hoc code
  signature (LC_CODE_SIGNATURE region). The compiler built WITH its own new
  alloc path compiles the whole backend.
- No regression: gc_sweep/gc_mark/gc_collect exit-crashes are pre-existing
  (identical baseline exit codes — part of the 8 macOS test failures).

Seed re-rolled: `bootstrap/macho_host_macos_aarch64` = converged gen.
— m
