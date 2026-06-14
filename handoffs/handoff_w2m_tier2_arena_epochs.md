# w → m: Tier-2 arena epochs (stretch task)

**From:** agent w (Windows-native)
**To:** agent m (macOS arm64, Mach-O backend + GC stages 1-6 phase 3 owner)
**Date:** 2026-06-13
**Status:** assignment — pick this up after the explicit-header sb draft work hands off to me

---

## Why you

You shipped GC stages 1-6 phase 3 on Mach-O including self-host convergence. You
caught the int-store vs string-atoi distinction on `gcSetThreshold` that I missed
in `stage6_phase3_plan.md`, and you added the register safepoint requirement that
my plan didn't have. You're now the highest-context person on the GC subsystem
of either backend.

Brian asked me to pick a kinda-complicated next step for you to stretch on.
**This is it.** Tier-2 in `docs/v20_plan.md` — arena epochs.

## What Tier 2 is

Today (stages 1-6): every allocation is a permanent member of the global GC chain
until mark-sweep decides it's unreachable. Conservative-scan + register-safepoint
gets us correctness, but every short-lived allocation (think the `sbAppend` calls
inside a hot loop) pays the mark+sweep tax.

Tier 2 says: most allocations live for a *known scope* — a loop iteration, a
function call, a parser-token-walk. If we can declare that scope, we can free
its whole arena in O(1) at scope exit with no mark phase.

Two surface designs to pick between (your call after prototyping):

### Design A — implicit per-frame arena

Every function gets a hidden arena. All allocs from inside the function go
into it. At RETURN, the arena either:
- frees wholesale if no allocation escaped, OR
- promotes escaping allocations to the global Tier-3 chain and then frees the
  rest.

Pro: zero user-facing change, every program benefits.
Con: escape analysis is required. Static-only escape is hard in our untyped FE;
dynamic via write barriers is doable but adds per-store cost.

### Design B — explicit `arena { ... }` block

```krypton
arena {
    let buf = sbNew()
    let i = 0
    while i < 1000000 { buf = sbAppend(buf, toStr(i) + ","); i = i + 1 }
    // buf freed here, nothing escapes
}
```

Pro: zero analysis. Compiler emits arena_push at `{`, arena_pop at `}`.
Pro: explicit lets users tune hot paths surgically.
Con: needs FE syntax + opt-in. Programs without `arena {}` see no benefit.

**My lean: ship B first** (1-2 weeks of work), then layer A on top of B as a
follow-up using B's primitives. B gives users immediate wins on the hot inner
loops we know matter (snek's lex+parse, kcc's compile.k, anything string-heavy)
without the escape-analysis rabbit hole.

## Suggested staging (~5 stages, ship each)

1. **Arena alloc primitive.** New helper `kr_arena_alloc(size, arena_id)` and
   `kr_arena_reset(arena_id)`. Lazy-init each arena as a 64 KB block, grow by
   doubling, single bump-pointer per arena. Don't link arena-allocated chunks
   into the GC global chain yet. Builtins: `arenaNew()` → id, `arenaReset(id)`,
   `arenaInArena(arena_id)` for the parser to query.

2. **Arena-aware `__rt_alloc_v2`.** Read an `active_arena_id` slot in
   `gcGlobals` (new field). If nonzero, route the alloc to that arena instead
   of the global pool. Push/pop sets/clears the slot. Stage 6 freelist consume
   only runs on the global path.

3. **FE syntax: `arena { body }` block.** Pre-scan in `compile.k`. Emits
   `BUILTIN arenaPush` before body, `BUILTIN arenaPop` after. Variables
   declared inside leak naturally (let them — they're freed at pop). Variables
   that *escape* (assigned to outer-scope names) — Brian's first cut can just
   *not optimize that case* (warn, leak the escapee permanently). Real escape
   handling can wait for stage 5.

4. **GC mark walks arena chains too.** Mark phase must scan arena-allocated
   chunks if a root points into one — otherwise live arena-data gets falsely
   collected mid-arena. Probably means linking arena chunks into a shadow
   chain that mark walks but sweep skips.

5. **Escape detection + promotion.** Now we can do A on top of B's primitives.
   A write barrier (`kr_arena_store`) that checks if an outer-scope-targeted
   store is depositing an arena pointer; if yes, promote the pointee to the
   global pool before the store completes. This is the hard one — defer until
   1-4 are stable in production.

## What I want back from you

- A `handoff_m2w_tier2_arena_design.md` with your design choice (A/B/hybrid)
  and any deviations from my staging.
- Stage 1 shipped on Mach-O with a `tests/arena_alloc.k` smoke (alloc 100 KB
  in arena, reset, alloc again, verify the second alloc reuses the first
  arena's bytes — confirms reset works).
- Don't ship to Windows. I'll port stage 1 to x64.k after I see your design,
  using the same Mach-O→Win64 translation we did for stage 6.

## Constraints

- No new C code (`feedback_no_c_for_dlls.md`). Arena primitives are pure
  machine-code helpers like the GC stages.
- Reuse the 16B alloc header layout from stage 1.5 where possible (next-link +
  size+flags); arena chunks may need a different flag bit (`IS_ARENA = 1<<1`?).
- Don't touch the global GC stages 1-6 paths during stages 1-3 of this work.
  Arenas are a parallel allocation system; integration happens at stage 4.

## Why this is "kinda complicated"

It's not the bytes — you've shipped harder bytes already. It's that this
intersects three subsystems (allocator, FE syntax, GC mark) and you have to
commit to a design choice (A/B/hybrid) without being able to A/B-test both
in production. Brian sees this as a "let's see how m does on something with
design surface" — not just impl surface.

Take your time. Ship stage 1 in a session, design doc separately, stages 2-4
across whatever cadence makes sense.

— w
