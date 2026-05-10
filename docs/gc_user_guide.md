# Krypton 2.0 GC — user guide

Krypton 2.0 ships a **mark-sweep garbage collector** with shadow-stack
rooting and per-allocation freelist reuse. This document covers what
users need to know.

## TL;DR

- Krypton allocates from 64 MB arena slabs. Without GC, slabs grow
  forever — every string concat, every `kr_str` call leaks.
- 2.0 adds explicit `gcCollect()` (mark + sweep). Freed allocations
  go onto a global freelist; subsequent `__rt_alloc` calls reuse them
  before bumping new slab memory.
- For long-running programs (LSPs, servers, monitors, IDEs):
  call `gcCollect()` between events / requests / loop ticks.
- For short-running programs (one-shot scripts, kryofetch-style
  fetchers): GC is inert — just exit, the OS reclaims the slabs.

## How rooting works

Krypton uses a **shadow stack** — a separate stack of "roots" that
the marker walks. The compiler emits explicit `gcShadowPush(value)`
after every:

- `let x = expr` (initial binding)
- `x = expr` (reassignment / compound assign / `++`)
- function entry (one push per `PARAM`)

…and a `gcShadowPop` diff before every:

- function exit (implicit fall-through end)
- explicit `emit` / `return` (early exit)

This means **the heap pointers visible from any live Krypton local
are always rooted**. Sweep can't accidentally collect a value that's
still in scope.

### What's NOT rooted

- **Vstack intermediates**: during expression evaluation (`a + b + c`),
  intermediate results live on the value-stack but are not pushed to
  the shadow stack until they're stored. **Don't trigger GC mid-expression**
  — call `gcCollect()` only between statements.
- **Struct fields holding heap pointers**: storing a heap value into
  a struct field doesn't root it via the shadow stack. The struct
  itself is rooted (so range-check finds the chunk), but the field
  contents are reached via "conservative within-payload scan" — bytes
  inside the struct that look like heap pointers are followed.

## Triggering collection

Krypton 2.0 does not auto-trigger GC inside `__rt_alloc` (deferred
to 2.1 — needs safe-point design). You call it explicitly:

```krypton
gcCollect()    // returns sweep count as a string
```

**Patterns:**

### Per-event server loop

```krypton
while running == "1" {
    handleOneRequest()
    gcCollect()    // between events — request's intermediates
                   // are unreachable now, freelist them
}
```

### Periodic timer in GUI app

```krypton
let TICK_BUDGET = 50          // every 50 ticks ≈ 5s at 100ms/tick
let tickCount = 0
func onTimer() {
    pumpLsp()
    pumpBackend()
    tickCount = tickCount + 1
    if tickCount >= TICK_BUDGET {
        gcCollect()
        tickCount = 0
    }
    emit 0
}
```

### After bulk work in a function

```krypton
func processLargeFile(path) {
    let lines = readFileLines(path)
    foreach line ... { ... }   // lots of allocs
    let result = computeSummary(lines)
    gcCollect()                // bulk-free everything except `result`
    emit result
}
```

## Diagnostic builtins

| Builtin | Returns |
|---------|---------|
| `gcAllocCount()` | Monotonic counter — total allocs ever (including reuses) |
| `gcWalkAllocs()` | Live alloc count (chain length) |
| `gcFreelistCount()` | Free chunks waiting for reuse |
| `gcMark()` | Run mark phase only; returns marks-set count. **See safety note below.** |
| `gcSweep()` | Run sweep phase only; returns sweep count. **See safety note below.** |
| `gcCollect()` | Mark + sweep; returns sweep count |
| `gcShadowCount()` | Current shadow-stack depth (mostly diagnostic) |
| `gcAllocated()` | Total bytes ever allocated |
| `gcLimit()` / `gcSetLimit(n)` | Soft byte limit (ExitProcess(99) on overrun) |

**Safety note: don't separate `gcMark()` and `gcSweep()`.** Any
allocation between them creates a chunk that hasn't been marked, so
the subsequent sweep will move it to the freelist — including, e.g.,
the int-string returned by `gcMark()` itself. If your code stores
that result (`let m = gcMark()`), `m`'s underlying chunk gets swept,
and subsequent allocations may reuse it and overwrite the bytes.

**Always use `gcCollect()`** (mark + sweep atomically, with no
allocations between phases). The standalone `gcMark` and `gcSweep`
are exposed for unit testing the GC machinery, not for production.

## Performance characteristics

Per `gcCollect()`:

- Mark walk: O(R × A) where R = roots in shadow stack, A = live allocs.
  For typical 1000 alloc / 100 root program: ~1ms.
- Sweep walk: O(A). For 1000 allocs: ~50µs.

Per allocation:

- Trampoline freelist check (always runs): ~50ns
- On freelist hit: O(F) walk where F = freelist length, plus 6 stores
- On freelist miss: fall-through to bump path (O(1))

Memory:

- Per-allocation overhead: 16-byte header (next-link + size+flags)
- Slabs are not returned to OS until process exit — peak working set
  is bounded by the largest concurrent live set, not the cumulative
  alloc total.

## Known 2.0 limitations

1. **No auto-trigger.** Programs must call `gcCollect()` explicitly.
   Auto-trigger requires safe-point design; deferred to 2.1.
2. **No slab compaction.** When a slab is mostly free, we can't
   release it back to the OS. Freelist reuse keeps memory bounded
   but not minimum.
3. **Reassignment leaves duplicate roots.** `x = expr` pushes a new
   shadow entry but doesn't pop the old. Heavy-reassignment functions
   accumulate shadow entries until the function exits. Workaround:
   put per-iteration work in a helper function (function exit pops
   all entries at once).
4. **Conservative within-payload scan** for struct fields. False-retention
   possible if a Krypton int happens to fall in a slab address range.
   Rare in practice (boundary at 0x40000000); not yet observed.

## Migration from 1.x

The 16-byte allocation header is a **hard ABI break**. 1.x-built DLLs
cannot be linked against 2.0 user binaries (and vice versa).

To migrate Krypton-side code:

```
kcc --port-1to2 source.k
```

This scans for patterns that need attention before a 2.0 upgrade:

- `bufNew` / `rawAlloc` / `rawFree` — manual heap
- `rawReadByte` / etc. — raw memory access
- `cfunc { }` — C body that won't survive native pipeline
- top-level `let X = ...` followed by `X = ...` — mutable module
  global (broken in native pipeline)

For typical user code (no `cfunc`, no raw heap), 2.0 just works.
