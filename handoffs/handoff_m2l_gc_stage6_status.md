# Handoff m → l: GC stage 6 — Linux is NOT a phase-3 mirror (no precise GC yet)

**From:** agent m (macOS)
**Date:** 2026-06-14
**Re:** "Linux mirror of GC stage 6 phase 3" — stop, read this first.

## TL;DR

Do **not** try to mirror phase 3 (auto-collect / `gcSetThreshold`) on the ELF
backends. Both `compiler/linux_x86/elf.k` and `compiler/linux_arm64/elf.k` are
**bump allocators with NO precise GC**. Every GC builtin is a stub:

- `elf.k` (x86) lines ~3922-3933: `gcCollect`/`gcLiveCount`/`gcAllocCount`/
  `gcFreelistCount`/`gcWalkAllocs`/`gcShadowCount` → `PUSH_INT 0`;
  `gcShadowPush/Pop` → `POP; PUSH_INT 0`. Comment says so verbatim:
  *"This backend uses a bump arena (no precise GC), so stub them."*
- `linux_arm64/elf.k` lines ~796, ~1080: `gcCollect` → `no-op (bump allocator):
  push 0`.

There is no freelist, no `free_head`, no conservative mark, no `kr_gc_collect`,
no gcGlobals GC slots on ELF. Phase 3 sits on top of stages 1–6 (freelist alloc +
mark/sweep + `gcCollect`). None of that exists on Linux, so a phase-3 byte-port
has nothing to attach to.

## What macOS actually shipped (the reference stack)

macОЅ arm64 carries the full chain; mirror order if you do this:

1. Freelist allocator (`__rt_alloc` freelist-hit path + slab).
2. Conservative mark (scan `[sp..stack_base]` + globals) + sweep → freelist.
3. `kr_gc_collect` runtime + `gcGlobals` slots (`free_head`, counters).
4. **Phase 3** (the easy part, last): `gcSetThreshold(N)` int store; `__rt_alloc`
   tail bumps `allocs_since`, compares vs `collect_threshold`, fires collect
   behind a **register safepoint** (spill all GP caller-saved regs so the
   conservative scan sees roots held in callee-preserved regs mid-alloc), resets
   counter. See `handoffs/handoff_m2wl_gc_stage6_phase3_macho.md` for the safepoint
   rationale and `handoffs/stage6_phase3_plan.md` for W's offset-level plan.

Commits: macOS `2d346ca6`, Windows `3c728376`+`20b6ce22` (w-confirmed). Both are
real backends with mark/sweep; that's why phase 3 was a small tail-append for them.

## Decision for you (L) / Brian

**(a) Full port** — bring stages 1–6 to elf.k first (big lift, ~the whole macho
GC stack re-expressed for SysV/ELF: different gcGlobals model — elf uses
R14=heap base, R15=heap_next; SysV caller-saved set rax/rcx/rdx/rsi/rdi/r8-r11 for
the safepoint), then phase 3 on top. Weeks, not a mirror.

**(b) Defer Linux GC** — leave the bump-arena stubs (correct + safe; programs just
never free until exit). Update the memory index so "L mirror pending" no longer
implies a quick phase-3 task. Recommended unless Linux long-running daemons need
heap reclaim now.

No code changed in this handoff — status correction only. Ping Brian to pick (a)/(b).
