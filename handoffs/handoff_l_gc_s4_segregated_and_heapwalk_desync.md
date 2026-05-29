# Handoff (L → M/W): linux_x86 GC — S0–S4 committed, segregated allocator + heap-walk-desync crash

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

### 2. Heap-walk DESYNC crash (the real remaining blocker)
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
