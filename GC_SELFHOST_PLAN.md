# Native self-host via conservative GC — implementation plan (macOS arm64)

Goal: a `macho_host` built by the **native** pipeline (no clang) can compile the
big sources (compile.k = 42729 IR lines, macho_arm64_self.k itself) without
exhausting memory. That unblocks regenerating the bootstrap seeds with Krypton
itself → **clang leaves the lineage entirely** (today users are clang-free via
seeds, but seed regen still needs clang once).

Status when this plan was written (2026-06-02): user path is clang-free via
seeds. Native self-host SEGVs ~3 min into compiling compile.k. Root cause below.

UPDATE (283825a1): the **memory wall is SOLVED** without GC — `__main__` now
mmaps an 8 GB heap (commit msg there), so a native host compiles compile.k to
COMPLETION (~190s, no SEGV). **GC is therefore no longer REQUIRED for
self-host** — it remains a memory-efficiency win (the host uses ~GBs of leaked
intermediates) but is optional. The plan below stays valid for that efficiency
work. THE REMAINING self-host blocker is now a **native-codegen correctness
bug**: a native-built frontend (compile.k compiled by the native backend) emits
only the IR header then stops — tokenize/parse miscompiled. Present on clean git
HEAD too (not caused by the mmap or layout changes). That bug — not memory — is
what must be fixed next to self-host. Chase: diff native-frontend vs clang-
frontend IR on a small input; the native one dies right after the header, so the
miscompiled construct is hit early in compile.k's read/tokenize/main path.

---

## Why it dies — and why "more heap" can't fix it

- The bump allocator **never frees** (`macho_arm64_self.k` ~L3646: "the bump
  allocator never calls collect"). Compiling compile.k churns >1.75 GB of
  intermediate strings with zero reclamation.
- Heap lives in the __DATA zero-fill segment, `DATA_VADDR (0x100008000) ..
  +DATA_VMSIZE`. `DATA_VMSIZE()` = `0x70000000` (L224). It **cannot grow**: the
  next region up is the **dyld shared cache** (~`0x180000000` on arm64 macOS).
  `0x100008000 + 0x70000000 = 0x170008000`, just under it. (The old
  `g_LINKEDIT_VADDR = DATA+0x40000000` bug — fixed 29b09e56 — had LINKEDIT
  overlapping the heap at 1 GB; now LINKEDIT = DATA + DATA_VMSIZE so the full
  1.75 GB is usable. Still not enough without freeing.)

⇒ Self-host **requires memory reclamation**. No way around it.

---

## Why a TRACING GC is the wrong choice here

Precise tracing needs roots. The root machinery is stubbed:
- `gcShadowPush(v)` is **count-only** — it bumps `gcShadowCount` (bump_cell+40)
  but does NOT store `v` (L3644). So `gcMark` (L3685) walks a shadow array that
  was never written → marks nothing real.
- The codegen does **not** emit shadow push/pop around locals holding heap
  pointers. Adding that is a massive, invasive change across all of codegen.

⇒ Use **conservative GC**: at collect time, scan the machine stack + registers
for values that look like heap pointers, mark those allocations (and their
interiors), sweep the rest to a freelist. No codegen cooperation needed.

Conservative-GC safety rule: **over-marking is safe** (keeps garbage),
**under-marking is fatal** (frees live → corruption). So we must scan EVERY
place a live pointer can hide: all registers + the entire used stack + (for
compound values) the interiors of marked blocks.

---

## What already exists (reuse it)

- Per-alloc header (emitAllocVar/N): `[next:8B][size_flags:8B]` then user bytes;
  user_ptr = header+16. `next` links every alloc into `gcAllocsHead`
  (bump_cell+48). `size_flags` low bits = size; **bit 63 = mark bit**.
- `gcMark` sets bit63 of `(v-8)` for in-range `v` (range filter
  `[bump_cell+80, bump_top)`). Reuse the mark-bit convention; replace its SOURCE
  (shadow array → stack/reg scan).
- `gcSweep` walks `gcAllocsHead`, unlinks unmarked, clears marks on kept.
  Extend it to push unmarked blocks onto a **freelist** instead of just
  unlinking.
- System area (bump_cell offsets): +0 bump, +8 argc, +16 argv, +24 alloc_total,
  +32 alloc_limit, +40 gcShadowCount, +48 gcAllocsHead, **+56 reserved (free)**.

---

## Krypton value representation (determines interior scanning)

- **Strings**: flat NUL-terminated byte buffers. NO internal heap pointers →
  conservative scan need NOT recurse into string bytes. (Big simplification —
  the dominant allocation during compile is strings.)
- **String builders (sb)**: a handle (8B) holding a pointer to a buffer. Handle
  IS a heap pointer to a block whose first 8 bytes point to the buffer →
  interiors of marked blocks MUST be scanned (8-byte aligned words) so the
  buffer survives.
- **Lists/structs/maps**: comma-joined strings (flat) per the list model, OR
  pointer-bearing blocks (structNew). Audit `structNew`/`mapNew` layout; if they
  hold pointers, interior scan covers them.
⇒ v1 must do **transitive interior scan of marked blocks** (scan each marked
block's user bytes, 8-aligned, for further heap pointers; mark+enqueue). Strings
are flat so most scans find nothing — cheap.

---

## Stages (implement + TEST one at a time; never commit an unverified stage)

### Stage 1 — capture the stack base (safe, additive, no behavior change)
In the `__main__` prologue (where argc/argv save to bump_cell+8/+16, ~L2026),
also store the initial SP to **bump_cell+56**. At `__main__` entry SP is the
outermost frame = the high boundary for a downward stack scan.
- `mov x_tmp, sp ; str x_tmp, [x_cell, #7]` (offset 56 = #7 in 8-byte-scaled str).
- Update that op's instruction COUNT in the count table (+N) — 3-edit discipline.
- TEST: full sample suite still builds+runs; `gcCheckpoint`/reset unaffected.

### Stage 2 — conservative mark (replace gcMark's source)
New `gcCollect` (or rewrite BUILTIN_GCMARK) that:
1. Spills x0–x30 to the stack (so register-held pointers are in the scanned
   range), e.g. `stp` pairs into a reserved scratch frame.
2. Reads `lo = current SP`, `hi = [cell+56]` (stack base), `heap_min =
   cell+80`, `heap_top = [cell+0]`.
3. For each 8-aligned word `w` in `[lo, hi)`: if `heap_min <= w < heap_top`,
   set bit63 of `(w-8)` and enqueue the block for interior scan.
4. Interior scan (worklist): for each marked block, walk its user bytes
   (size from size_flags low bits, 8-aligned) applying the same test; mark+enqueue
   newly found blocks. Use the mark bit to avoid re-enqueue.
5. Restore registers.
- TEST in isolation BEFORE wiring sweep: a program that allocs N blocks, keeps
  a few in locals, calls collect-mark, then `gcWalkAllocs`/count marked — verify
  the kept ones are marked and dropped ones aren't. (Add a debug builtin if
  needed.)

### Stage 3 — sweep to a freelist
Extend `gcSweep`: unmarked block → push onto a freelist (head at a NEW system
slot; extend system area, e.g. bump_cell+64 and shift heap start, OR carve a
slot — pick one and update emitAllocVar's `heap_min`/offsets consistently).
Freelist threads through the block's `next` field. Keep marked, clear bit63.
- Decide freelist policy: simplest correct = single freelist, first-fit by
  stored size; coalescing NOT required for v1.
- TEST: alloc+drop in a loop with collect; `gcFreelistCount` grows; memory
  (RSS) stays bounded across iterations.

### Stage 4 — freelist reuse + auto-trigger
- `emitAllocVar`/`emitAllocN`: before bumping, search the freelist for a block
  with `size >= needed`; if found, unlink + reuse (return user_ptr). Else bump.
- Auto-trigger: when `alloc_total - last_collect_total > THRESHOLD` (e.g.
  256 MB) inside alloc, run collect first. Store `last_collect_total` in a
  system slot.
- TEST: the native-built host compiles compile.k to completion under 1.75 GB,
  and the produced frontend is byte-identical (or functionally identical) to the
  clang-built one. Then self-compile macho_arm64_self.k → host gen2 → fixed point.

---

## Hard correctness checklist (conservative GC)
- [ ] ALL registers spilled before scan (a live pointer only in a reg = freed).
- [ ] FULL used stack scanned `[sp, base)` — base captured in Stage 1.
- [ ] Interior scan of marked blocks (sb handles / structs hold pointers).
- [ ] Mark bit cleared on every kept block each cycle (no stale marks).
- [ ] Freelist size stored/honored; never hand back a too-small block.
- [ ] Collect only at alloc points (a safe point — no half-built values in
      flight beyond what's in regs/stack, which we scan).
- [ ] Over-mark OK, under-mark fatal — when unsure, mark.

## Test gates (run before EACH commit)
1. Sample suite (stdlib programs, examples/ks/*) build + run unchanged.
2. `bash tests/.../RUN.sh` if present.
3. Native-built host compiles a 6k-line program (old SEGV threshold) — passes.
4. Stage 4 only: native host compiles compile.k fully; frontend works
   (compiles + runs a program with sockConnect/imports).
5. Keep the change OFF by default (env `KR_GC=1` or a compile flag) until gate 4
   passes, so a regression can't brick the committed seeds.

## Risk
This is the compiler compiling itself. A wrong free corrupts every subsequent
binary — including the seeds users depend on. Implement incrementally, test each
stage in isolation, and do NOT refresh the committed seeds from a GC-enabled host
until gate 4 is green twice. The clang seed path stays as the safety net.

Mirrors the Linux elf.k self-host effort — same conservative approach applies
there (scan stack, same header/mark conventions in elf.k).
