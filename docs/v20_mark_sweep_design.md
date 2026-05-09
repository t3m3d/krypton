# Krypton 2.0 — Mark-Sweep GC Design (Tier 3)

Status: **draft for review.** Builds on Tier 1 (sbAppend refactor, shipped 1.7.0) and Tier 2 (arena slabs + epoch reset + checkpoint/restore + `pure_` auto-wrap, shipped 1.7.6→1.7.9). Tier 3 is the centerpiece of 2.0 per `docs/v20_plan.md`.

## Goal

Move from "everything lives until process exit (or scope reset)" to "unreachable allocations get reclaimed automatically." Specifically: long-running programs (LSP, servers, agents) stay flat in memory without manual `gcReset()` calls.

## Non-goals (out of scope, deferred to 2.1+)

- Generational collection
- Concurrent / incremental marking (stop-the-world is fine for 2.0)
- Compaction (allocations stay where they are)
- Weak references / finalizers

## Current state (1.8.10)

Allocator: 64 MB arena slabs, bump-allocated. `__rt_alloc_v2`:
- Tracks `alloc_total` (bytes ever allocated) in `gcGlobals[0]`.
- Soft limit at `gcGlobals[8]` — calls `ExitProcess(99)` if exceeded.
- Slab chain rooted at `gcGlobals[16]` (slab_first); current slab in `gcGlobals[24]`; offset within current at `gcGlobals[32]`.
- Each slab: `[0..7]` = next-pointer, `[8..]` = payload.
- `gcReset()` walks chain, frees all but first slab via `HeapFree`, resets offsets.
- `gcCheckpoint()` returns 16-byte token capturing (slab_curr, slab_off); `gcRestore(token)` rewinds.

**No per-allocation tracking.** Pointer-to-allocation is just an offset within a slab; we don't know its size or whether anything still references it.

## Tier 3 = mark-sweep with shadow-stack roots

### Why shadow stack (not conservative scan)

Per v20 plan: Krypton's smart-int convention puts the pointer/int boundary at `0x40000000`. A user int like `0x40001234` is indistinguishable from a heap pointer to a conservative scanner. Shadow stack is precise — the compiler emits explicit push/pop of every Krypton-typed local at scope entry/exit, and roots are exactly that stack.

Cost: ~2 instructions per local at function entry/exit. Worth it for precision.

### Why allocator-handoff (not caller-pinning)

DLL exports still return `char*`. After 2.0, callers can't assume the returned pointer lives forever. Two options:
- **Caller-pinned**: callers must `kr_pin(ptr)` to retain across GC points. Forgetting = use-after-free. Maximally efficient, maximally unsafe.
- **Allocator-handoff** (chosen): every `kr_*` that returns a pointer pushes that pointer onto the current shadow-stack frame before returning. Caller pops on scope exit. Compiler emits this automatically; user code never sees it. Cost: one extra qword push per return.

Allocator-handoff keeps user code feeling manual-free.

## Allocation header layout

To track liveness per allocation, every `__rt_alloc` result needs a header. Two options:

### Option A: Inline header (16 bytes per alloc)
```
[ptr - 16]  next   (qword)  — link in global allocation list
[ptr - 8]   size + flags    (qword) — size in low 56 bits, mark bit in bit 0
[ptr]       payload (size bytes)
```

Pros: O(1) lookup of header given payload pointer (just subtract 16). Cache-friendly (header next to payload).
Cons: 16-byte overhead per alloc. For Krypton's typical pattern (lots of short strings), this is ~50%+ memory overhead.

### Option B: Sideband table
```
gcAllocs = [{ptr: 0x..., size: N, marked: false}, ...]   // grows on each alloc
```

Pros: Zero per-alloc overhead. Headers don't pollute payload region.
Cons: O(log N) lookup of metadata given pointer (binary search on sorted ptrs); sweep walks N entries even if 99% are dead.

### Option C: Bitmap per slab
```
slab[0..63]  = mark bitmap (1 bit per 8 bytes of payload)
slab[64..]   = payload
```

Pros: O(1) mark via bit set; no per-alloc header. Sweep iterates bitmap (fast).
Cons: Doesn't track allocation boundaries — sweep can't distinguish "16-byte alloc with mark on first word" from "two 8-byte allocs". Need a separate boundary table.

**Recommended: Option A (inline header).** Simplest. Memory overhead is acceptable when traded against the savings from actual reclamation. Tier 2 slabs are already the bulk allocator; per-alloc overhead is a one-time tax.

If overhead bites, fallback: only allocations from `kr_gc_alloc_tracked` get headers; bump-only `__rt_alloc_fast` for short-lived strings stays untracked. Compiler picks per call site based on lifetime analysis.

## Shadow stack mechanics

Per-thread global pointer `gcShadowSp` points at top of shadow stack. Stack itself is a 64 KB region allocated at process start (grows by reserve+commit if it overflows — same trick as Win32 fiber stacks).

### Compiler emits

At function entry (after prologue): nothing yet — locals don't exist as Krypton-typed values until they're STOREd.

At each STORE of a heap-pointer value to a local:
```
MOV [gcShadowSp], RAX
ADD gcShadowSp, 8
```

At each function exit (before epilogue):
```
SUB gcShadowSp, <N * 8>     ; N = number of pointer-typed locals
```

Where `<N>` is computed at compile time. The compiler tracks which locals hold Krypton pointers (currently: anything not a smart-int or known-primitive return).

### Mark phase

Walk the shadow stack from base to `gcShadowSp`. For each entry:
1. Check if it's a heap pointer (range check against arena slab list — if it falls inside any slab, it's a heap ptr).
2. Subtract 16 to get the header.
3. Set the mark bit in `size + flags`.
4. If the payload contains pointers (e.g., a struct with field pointers), recurse. **Open question**: how does the collector know which words inside an allocation are pointers? See "Type tags" below.

### Sweep phase

Walk the global allocation linked list (rooted at `gcAllocs`). For each header:
- If mark bit is set → clear it, leave allocation alive.
- If mark bit is clear → unlink from list, return memory to slab's freelist (or just mark the slab range as reusable).

Returning memory to a bump-allocated slab is awkward. Two options:
- **Compact**: walk all live allocations, copy down to fill gaps left by dead ones. Updates all live pointers. Expensive but reclaims fully.
- **Free list per slab**: each slab maintains a list of free chunks. New allocations check the free list first, fall back to bumping. Doesn't compact; fragmentation grows.

**Recommended for first cut: free list per slab.** Compaction is complex and can be a 2.1 follow-up.

## Type tags (the hard problem)

When the marker walks an allocation's payload, it needs to know which 8-byte words inside it are pointers. Three options:

### Option A: Type info per allocation
Header grows to 24 bytes; one word stores a pointer to a type descriptor. Type descriptor encodes "word at offset 0 is a pointer, offset 8 is an int, offset 16 is a string-ptr, ..." Generated by the compiler for each struct type.

Cost: 24 bytes per alloc. Compiler complexity: must emit type descriptors for every struct type and pass them to the allocator.

### Option B: Conservative scan within payload
For each 8-byte word inside the payload, check if it falls inside a slab. If so, treat as a pointer.

Same hazard as conservative root scanning: a Krypton int that happens to look like a pointer triggers false retention. But the hazard is bounded: the *only* false positives are integers in the `0x40000000`+ range that coincidentally point to slab memory. Not impossible but rare.

Cost: zero memory overhead, simple code.

### Option C: Two-class object model
Heap allocations are either "leaf" (no embedded pointers — strings, byte buffers) or "composite" (struct/array with declared pointer fields). Header has a 1-bit flag. Composite allocations carry a small bitmap of which words are pointers (8 bytes for up to 64 words = 512-byte structs).

Cost: 8 bytes extra for composites; flag bit stolen from header.

**Recommended: start with Option B (conservative within payload).** Lowest implementation cost, hazard is rare. Move to Option A or C in 2.1 if false-retention bites.

## Staging — concrete sessions

| # | Stage | Lines changed | Risk | Behavior change |
|---|-------|---------------|------|-----------------|
| 1 | Inline header on every alloc; alloc-count slot in gcGlobals; `gcAllocCount()` builtin | x64.k __rt_alloc_v2 +30 lines, 1 new helper | Low | None visible (just header overhead) |
| 2 | Shadow-stack region allocated at process start; `gcShadowSp` slot in gcGlobals; `gcShadowPush(ptr)` / `gcShadowPop(n)` builtins | x64.k +2 helpers, ~80 lines | Low | None — only used if compiler emits |
| 3 | Compile.k emits gcShadowPush after STOREs of pointer-typed locals; gcShadowPop at function exits | compile.k irLetIR + irBlockIR + irFuncIR | High | Every Krypton function changes; binary size grows ~5% |
| 4 | Mark walker: walks shadow stack, sets mark bits in headers; conservative within-payload scan | x64.k 1 new helper, ~150 lines | Medium | None — invoked only by gcCollect (existing builtin, currently no-op) |
| 5 | Sweep walker: walks alloc list, frees unmarked, builds per-slab free list | x64.k 1 new helper, ~200 lines | High | First real free; bugs corrupt heap |
| 6 | `__rt_alloc_v2` checks free list first; triggers gcCollect on threshold (e.g., 2× live size) | x64.k __rt_alloc_v2 +50 lines | High | Memory now actually reclaims; allocator perf may regress 5-15% |

Total: ~6 sessions (matches plan estimate).

**Stages 1-2 are independent** and can ship as 1.9.x diagnostic builds without enabling collection. Stages 3-6 are the actual ABI break.

## ABI versioning

- 1.x DLLs: no headers, no shadow stack. Untrusted callers.
- 2.0 DLLs: 16-byte headers, allocator-handoff. Callers must be compiled by 2.0 kcc to push/pop shadow stack correctly.
- 2.0 binaries cannot link against 1.x runtime, vice versa. Hard break.
- Migration: `kcc --port-1to2 source.k` flag flags any pattern that needs adjustment (mostly: raw `bufNew` + `rawAlloc` patterns that escape the GC heap need explicit `untracked` annotation).

## Open questions for review

1. **Inline header cost vs. simplicity** — is 16 bytes/alloc tolerable for Krypton's typical workload? If not, drop to Option B (sideband) and pay O(log N) lookup.
2. **Type tags Option B vs. A** — accept rare false retention from conservative-within-payload scanning, or pay 24 bytes/alloc for precise type descriptors?
3. **Free list vs. compaction** — fragmentation hazard is real for long-running processes. Worth the implementation cost of compaction in first cut?
4. **Shadow stack overflow** — when 64 KB shadow stack fills, do we (a) extend by another 64 KB via VirtualAlloc, (b) trigger a forced collection, or (c) assert and exit?
5. **Collection triggers** — only at allocation threshold (e.g., 2× live), or also on explicit user request, or also on shadow-stack high-water mark?
6. **Closures + GC interaction** — native lambdas don't capture today (2.1 problem). When closures land, captured environments need GC roots too. Design for it now or defer?
7. **DLL export ABI** — do we ALSO change `kr_*` export signatures (e.g., add a hidden GC token param), or keep `(char*) → char*` and rely on shadow-stack handoff exclusively?

## What ships in 2.0

Stages 1-6, with conservative-within-payload type scanning, free-list-per-slab reclamation, 16-byte inline headers, ExceptionFilter-based shadow-stack overflow handling. Triggered on allocation threshold (2× live) plus user-explicit `gcCollect()`.

Targets: bounded memory in long-running LSP/server programs without `pure_` annotations or manual `gcReset()`.

Does NOT ship in 2.0: generational, concurrent, compacting, finalizers, weak refs.
