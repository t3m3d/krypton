# m → l : real conservative GC mark (stack + globals scan) on Mach-O

**From:** agent m (macOS) — **Date:** 2026-06-13
**Status:** DONE + self-host-converged. Follows handoff_m2l_gc_stage6_macho.md.

The macOS `gcMark`/`gcCollect` now do a **real conservative scan** instead of
the stubbed shadow stack. This makes mark-sweep actually safe (live data
survives a collect) and is the prerequisite for stage 6 phase 3 (auto-collect).
Mirror to ELF when you wire a live GC pass.

## Why the shadow stack was replaced

The old root model (shipped, then stubbed): `compile.k` emits `gcShadowPush`
on every STORE of a heap value, popped at *function* exit. Two fatal flaws:
1. **Leak** — a loop that reassigns a local pushes a root per iteration,
   popped only at function return → unbounded shadow growth (it was stubbed to
   count-only to stop the bleed, so mark found nothing).
2. **Mis-rooting** — reassigning an *outer* variable inside a loop pushes the
   new value but the variable's lifetime is the outer scope; push/pop can't
   model that. (This is the "scope-precise tracking is future work" comment.)

Conservative stack+globals scanning sidesteps both: roots are wherever live
values actually sit, no separate bookkeeping.

## What it does now

`gcMark` (43 instr) and `gcCollect`'s inline mark (61 instr w/ sweep) scan TWO
regions, feeding one heap-range filter (`v in [heap_min, bump)` → set bit 63 of
`[v-8]`):
1. **Machine stack** `[sp, stack_base)` — function frame locals + eval-stack
   temporaries. `stack_base` = `__main__`'s fp, captured at `[bump_cell +
   0x50000000] + 0`.
2. **Globals region** `[globals_base, +nGlobals*8)` — `__main__`'s module
   "locals" live here (`LOAD_GLOBAL`, at `g_TEXT_VMSIZE + 0x6F004000`), NOT on
   the stack. **This was the bug**: a stack-only scan marked 0 roots because
   every top-level `let` is a global. `g_NGLOBALS` (set in `parseFullIR`) is
   embedded as the count; `globals_base` via `adrp` like `LOAD_GLOBAL`.

`__main__` prologue now also captures `heap_min` (real heap base = mmap base, or
`bump_cell+96` fallback) at `[bump_cell+0x50000000] + 8`. heap_min MUST be the
tight real base: marking *writes* to `[v-8]`, so a loose lower bound would let
stack/text words pass and SIGBUS on read-only `__TEXT` or corrupt data.

## Verified

- `marked=2` on a live test (globals roots found; was 0).
- `gcCollect` keeps live data: collected 19 dead temporaries, `live` survived.
- ph2 freelist consume still 29→24; gc_alloc_count, fibonacci=4181 clean.
- **Self-host CONVERGED**: gen2==gen3 byte-identical except code signature.

## Known tradeoffs (acceptable; document for ELF too)

- Conservative: a non-pointer word coincidentally in `[heap_min, bump)` and
  8-aligned causes a false mark — over-retention only (safe). False mark writes
  bit 63 of `[v-8]` inside the anon heap; sweep only reads real headers so it's
  not confused, worst case one data qword's high bit flips (rare; Krypton value
  tagging keeps ints out of the heap range).
- A root held ONLY in a callee-saved register across a collect would be missed,
  but Krypton spills locals to frame slots / eval stack, so at a `gcCollect()`
  statement boundary all roots are stack- or globals-resident. **Phase 3
  (auto-collect mid-alloc in `__rt_alloc`) still needs a safepoint** (spill
  x0–x18 or only trigger at statement boundaries) before it's safe.

Seed re-rolled: `bootstrap/macho_host_macos_aarch64`. — m
