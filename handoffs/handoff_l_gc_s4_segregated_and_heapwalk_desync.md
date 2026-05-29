# Handoff (L → M/W): linux_x86 GC — ✅ SOLVED & committed (segregated alloc + transitive mark)

## ✅ RESOLVED 2026-05-29 (commit 6cbffc1c, pushed)
GC now works at scale. Two stacked bugs fixed:
1. **Missing transitive mark** (the UAF) → added a fixpoint transitive pass to
   kr_gc_collect (now 301B: stack-mark → transitive fixpoint → sweep).
2. **A 1-byte REX bug in the new code**: `LEA R11,[RSI+RDX+8]` was emitted `0x4E`
   (REX.WRX); REX.X=1 promoted the SIB index from RDX→R10, so R11=2·RSI+16 garbage →
   the scan ran off into unmapped memory. Fix: `0x4E`→`0x4C` (REX.WR).
Result: self-host **CONVERGED h2==h3** byte-identical (643173B); GC-on self-compile
74s, heap plateau ~26MB (was SIGSEGV ~13s). Suite 60 pass / 4 skip; the 2 fails
(test_array, test_static) are **pre-existing** (identical on the GC-off pre-S0 backend).
GC auto-collect left **ON** (gcSetThreshold 1M at backend entry) so big compiles cap
memory. Segregated exact-size free lists (committed too) keep alloc O(1).

NEXT: S6 mirror to linux_arm64/elf.k. Optional: swap the fixpoint for a worklist
mark-stack (fixpoint is O(heap·passes)/collect; fine here, matters for huge inputs).

---
## (historical) original handoff below
# linux_x86 GC — S0–S4 committed, segregated allocator + heap-walk-desync crash

## State
- **S0–S4 GC engine** committed + pushed on `feat/arm64-native-pipeline`
  (commits e13e38a7 / 98be1b62 / 728d8e28 / 867d5f05 / f0579143). Suite green,
  self-host CONVERGED h2==h3, **GC default-OFF** (threshold 0 ⇒ never auto-collects),
  so the committed tree is safe for normal compiles.
- Working tree reverted to clean S4. No uncommitted GC code on the branch.

## Two problems found past S4 (both only bite when GC is ON for big programs)

### 1. Single first-fit freelist is O(n²)  → SOLVED (code saved, not committed)
First-fit walk of one global free list = O(heap) per alloc ⇒ O(n²) over a compile.
Self-host with GC-on took ~22 min.
**Fix: segregated (exact-size) free lists.** Layout:
- gcbase band at `[R14+24..]`; **buckets at gcbase+72+size** (exact-size bucket, O(1) pop).
- kr_alloc: round RDI; `CMP RDI,2048 / JA .bump`; `MOV RCX,[vaddr+8]` (gcbase);
  `LEA RDX,[RCX+RDI+72]` bucket head; pop head (no walk); **REP STOSB-zero** the
  recycled block (kr_concat relies on zeroed mem); `.tail` INC allocs_since +
  threshold check + 12-reg safepoint `CALL kr_gc_collect`.
- sweep: walk heap, unmarked `size<=2048` → link to `[gcbase+72+size]`,
  `size>2048` dropped, marked → clear bit63.
- This made it **FAST** (h3 build reached 16s vs 22min). Code preserved at
  `/tmp/elf.k.segregated_wip` on L's box (copy into handoff if box wiped — see below).

### 2. DEFINITIVE ROOT CAUSE — missing transitive (heap→heap) marking
**(supersedes the "mark corrupts a header" theory below, now DISPROVEN)**

The crash is a **use-after-free**, not a mark-side header corruption:
- Mark's only write is `OR [RAX-8],bit63` (set mark). It touches **only bit63**; the
  size lives in bits 0..62. Sweep masks bit63 off before advancing (`AND RAX,~bit63`).
  ⇒ mark **cannot** corrupt a size field ⇒ cannot cause a heap-walk desync.
- kr_concat allocs `la+lb+1`, writes `la+lb` (NUL slot stays in-block, zeroed by the
  bucket-pop REP STOSB). No payload overflow. kr_alloc bucket-pop zeroes exactly the
  payload (header untouched). All audited alloc/write paths are size-correct.

**The actual bug:** `kr_gc_collect` MARK scans ONLY the stack
(`[RSP_entry, stack_base)`). It does NOT scan the interiors of marked objects. So a
live object A reachable **only** through another heap object B (heap→heap pointer) is
never marked. Sweep frees A (links it into a bucket, writes a free-link into A's
payload[0]), alloc later hands A out and zeroes it — while B still points to A. When
the program follows B→A it reads freelist-link / zeroed / reused bytes and eventually
**dereferences string content as a pointer** (RAX=0x6309707369447374 = ASCII). That is
the SIGSEGV. Small tests pass because their live sets are stack-rooted (no heap→heap
chains deep enough to matter); elf.k's compile state has heap→heap structure ⇒ it bites.

**FIX = add transitive marking** between the stack-scan and the sweep:
- Simplest, no extra memory — **fixpoint over the heap**: repeat { walk blocks p; for
  each MARKED p, scan its payload qwords w; if `heap_start<=w<R15 && w&7==0` and
  `[w-8]` not yet marked, set its mark + set `changed` } until `!changed`. O(heap·passes)
  — correct but can be slow with frequent collects.
- Better — **worklist/mark-stack**: push stack-root-marked blocks; pop, scan payload,
  push+mark newly found; O(heap) per collect. Needs a scratch buffer (carve another GC
  band slot for a mark-stack region, or reuse the top of the heap).
- Recommend: land fixpoint first for correctness (verify kryofetch builds), then swap to
  worklist for speed.

Either way the conservative scan inside an object is the SAME predicate already used for
the stack scan (in-range, 8-aligned) — reuse it.

### (OLD/DISPROVEN) Heap-walk DESYNC theory — kept for history
With segregated GC on, self-compiling `elf.k` SIGSEGVs at ~16s.
gdb: crash in cv_h2 code at `+0x9988a`; **RAX=0x6309707369447374** — that is
**ASCII string bytes** ("tsDispt\tc" byte-reversed) being used as a header/pointer.
RDX=0x7f445fe00110 (valid heap), RSI=0x7f09a708, R8=1.

**Diagnosis:** the sweep heap-walk read **string payload as a block header**, got a
bogus huge size, advanced RSI by garbage, then deref'd unmapped → SIGSEGV. The walk
**desynced** — `p` landed mid-object instead of on a header.

Small tests PASS (string-concat+collect, sb+collect), so it is scale/pattern-specific,
not a basic mark gap. Most likely cause: **conservative mark imprecision** — a stack
word that looks like an 8-aligned heap pointer but points into the MIDDLE of a large
object; `OR [v-8],bit63` then corrupts a mid-object word. If that word later sits where
the sweep expects a size, the size is wrong → walk desyncs. (Alt: a footprint/header
mismatch on some alloc path, or transitive marking never added so a live child is swept
then its slot reused and walked.)

### What to try next (in order)
1. Make the sweep walk **defensive**: sanity-check each header `size` (must be
   8-aligned, `8 <= size <= heap_used`); on a bad header, the walk is already corrupt —
   better: stop relying on raw walk.
2. **Don't OR bit63 on false-positive pointers mid-object.** Mark should verify `v-8`
   is a real header start (e.g. maintain a separate mark bitmap keyed off heap base, or
   only mark when `[v-8]` size is sane AND `v` is exactly a payload start). A mark
   bitmap (1 bit / 8-byte word, indexed `(v-heap_base)/8`) sidesteps in-band corruption
   entirely — recommended.
3. Add **transitive marking** if not present (mark children of marked objects) before
   trusting sweep — but bitmap + sane-header gate is the higher-value fix.

## Wiring note
The unblock needs `gcSetThreshold(N)` at elf.k `just run` entry. Do NOT commit that
until #2 is fixed — with current mark it corrupts big compiles. 1M plateaus heap ~123MB
(safe but many collects); tune after correctness.

## Net
GC engine is in + safe-off. The 2^31 ceiling (kryofetch / single-exe kcc) stays blocked
until the heap-walk-desync (#2) is fixed — a mark-bitmap is the clean path. Allocator
speed already solved (segregated). This is a multi-session correctness task; M's
original plan warned of exactly this conservative-on-untyped-heap hazard.
