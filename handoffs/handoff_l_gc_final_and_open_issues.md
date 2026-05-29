# Handoff (L): linux_x86 GC done; kryofetch + 3 open backend issues

## DONE & committed/pushed (branch feat/arm64-native-pipeline)
- **Transitive-mark GC works** (`6cbffc1c`): segregated O(1) alloc + stack-mark →
  transitive fixpoint → sweep. Self-host CONVERGES h2==h3 byte-identical; suite
  60 pass / 4 skip (2 fails test_array/test_static are PRE-EXISTING — identical on
  the pre-S0 bump backend). GC-on self-compile completes (~74s, heap plateau ~26MB).
  The 1-byte REX bug (`LEA R11` 0x4E→0x4C) is fixed.
- **O(n) hexStr** (`94e3e08d`): was O(n^2) per char; now sbAppend.
- Repo tip `94e3e08d`. Installed elf_host matches.

## REVERTED (don't redo blindly)
- `7ecbdfe9` large-block reclaim (first-fit large free list) + 8GB heap, and
  `3810e68a` driver-loop O(n) — reverted in `94e3e08d`. The large-reclaim did NOT
  fix kryofetch (see below) and added complexity. **8GB heap re-add is trivial &
  worthwhile** if you want headroom: in emitStartCode replace `MOV ESI,0x70000000`
  with `MOV ESI,0x40000000` + `SHL RSI,3` (48 C1 E6 03), startSize 109→113,
  startCallDisp 91→95, startAtoiDisp 99→103. (Krypton tags int literals ≥0x7F000000
  as pointers, so you can't write a bigger size literal directly — shift instead.)

## OPEN ISSUE 1 — kryofetch native build (the original task)
- FE+opt of run_linux.k now succeed (836KB IR → 832KB opt). elf_host codegen runs
  but its heap grows ~120MB/min with NO plateau on this input → exhausts (crashed at
  the 1.875GB ceiling; with 8GB it reached ~5GB still climbing).
- RSS = bump high-water (Linux doesn't return freed pages). Growth is a
  growing-transient pattern: large allocations that exceed every freed block, so a
  free list can't reuse them. hexStr O(n) did NOT fix it; large-reclaim did NOT cap
  it. Root source NOT isolated (candidates: conservative false-retention via stale
  stack slots holding old large-buffer pointers; or an O(n²)/non-reclaimable alloc
  in codegen specific to run_linux.k's 270 large ASCII-art literals).
- run_linux.k source is committed (kryofetch repo `a20faf8`).

## ✅ FIXED 2026-05-29 (commit 3dc3c73b) — Issue 2 front-end accumulation
The FE now emits the existing CAT opcode (always kr_concat) for `+` when an operand is
statically a string literal (string literals carry a new `;str` type tag, propagated
through the precedence levels in compile.k). CAT result left untyped so `"" + 10 + 4`
stays numeric (14). Rebuilt + committed compiler/linux_x86/kcc-x64. Verified:
`a + "0123456789"` ×300 → 3000; "" +10+4 → 14; 5+3 → 8; suite 60/2/4; FE self-converges
(kcc3==kcc4); backend self-hosts (h2==h3). Applies to all backends (all have CAT).

## (was OPEN) ISSUE 2 — PRE-EXISTING front-end bug: `x = x + literal` accumulation (NOT GC)
**Proven NOT a backend/GC bug:** the segregated-GC backend AND the pre-S0 bump backend
produce the IDENTICAL wrong result, so the fault is in the SHARED front-end (kcc-x64)
or optimizer / IR — my GC backend faithfully executes the same IR. It is narrow:
elf.k self-host uses **sbAppend**, not `x = x + literal`, so convergence + suite are
unaffected; that's why it went unnoticed.

Repro: `let a="" let k=0 while k<10 { a = a + "0123456789" k=k+1 } kp(a)` prints
**"1234567890"** (10 chars — NOT accumulated; content is the literal rotated left by 1
with a premature NUL) instead of the 100-char string. `kp(len(a)+"")` → "10". At k≥18
it SIGSEGVs (the corrupted/short string later derefs bad). str_int itself is fine
(100/150/12345 → correct). Tiny/letter cases work (`a=a+"XY"` ×5 → correct).
⇒ Bug is in how the FE lowers `var = var + <string-literal>` inside a loop (looks like
a source/dest off-by-one + early NUL, data/size dependent). Fix belongs in the
front-end (compiler/compile.k or the optimizer), NOT in linux_x86/elf.k.

## (was Issue 2, reclassified above) large-string-concat crash
- Repro: a program that accumulates a >2048-byte string via concat crashes (SIGSEGV).
  `let big="" ; while k<300 { big = big + "0123456789" } ; while i<20000 { let t = big + "x" }`
  → core dump. **GC is OFF** in this repro (no gcSetThreshold) so it's NOT the
  collector. Small-string accumulation (`big` stays <2048) is FINE.
- Works on the pre-S0 bump backend (runs, just slow), crashes since the **segregated
  allocator** landed. The suite never builds >2048-byte strings so it's untested.
- **Minimal repro / bisect (CLEAN, GC off):** `let a="" let k=0 while k<N { a = a + "0123456789" k=k+1 } kp(len(a)+"")`
  - N=10 (→ should be len 100): prints **"10"** (WRONG), no crash
  - N=15 (→150): prints **"10"** (WRONG), no crash
  - N=18..25: **CRASH** (SIGSEGV)
  - But tiny accumulation is CORRECT: `while k<5 { a=a+"XY" }` → "XYXYXYXYXY" len 10 ✓;
    `a="AA"; a=a+"BB"` → "AABB" ✓; len("hello")→5 ✓; inline concat ✓.
  So something breaks as a single string accumulates past ~100 bytes via 10-byte
  concats: first `len` returns wrong (looks like the result loses NUL-termination so
  len scans wrong), then by ~180 bytes it derefs into bad memory → SIGSEGV. Crash is
  early (R15 ≈ heap_start+24) and lands in str_int/atoi-shaped code with
  RDI = string-content-as-pointer.
  Hypothesis: the segregated kr_alloc returns a block that isn't NUL-terminated for
  these sizes (zeroing count off, or bucket/bump boundary), OR kr_concat's copy/size
  for the growing result is off-by-something at a size class. self-host's 643KB output
  is built with **sbAppend** (different path) so it's unaffected — that's why
  convergence + suite pass while this breaks.
  NEXT: dump kr_concat's result bytes for N=10 (is [100]==0? what's len scanning?);
  check segregated kr_alloc zeroing (REP STOSB count = rounded size vs requested) and
  the small-bucket size rounding around 64/128 byte classes.
- gdb: wild control flow into the ELF header; faults in str_int/atoi-shaped code
  (cmpb '-' / digit scan) with RDI = string-content-as-pointer. Possible: kr_concat
  mis-treats the large result/operand as a small int and calls kr_str_int on garbage,
  or copies past the block. Start by diffing kr_concat's size/alloc/copy for la+lb+1
  when la+lb+1 > 2048. (kr_concat is unchanged since pre-S0 where it worked, so the
  trigger is the segregated kr_alloc's behavior for >2048 sizes.)
- NOTE: this box has **ptrace-attach disabled** (gdb -p fails) and **no /usr/bin/time**;
  gdb *launch* (run) works. Use `gdb -batch -ex run` and read `*(long*)0x7f000008`
  (gcbase slot) for heap state.

## OPEN ISSUE 3 — repeat() broken on linux_x86 (separate, pre-existing)
- `repeat("x",N)` compiles but the emitted CALL targets the image base (krRepeatVAddr
  resolves to SEG_BASE / a builtin-dispatch or FE mismatch in the bundled kcc-x64).
  Not in the suite. Unrelated to GC.

## Suggested next steps
1. Fix Issue 2 first (it's the likely cause of Issue 1 — kryofetch builds big strings).
   Minimal repro is fast; bisect segregated kr_alloc small/bump path vs kr_concat.
2. Re-add 8GB heap.
3. Re-attempt kryofetch; if heap still grows, instrument allocs (emit a write() of a
   counter in kr_gc_collect) since ptrace-attach is unavailable.
See [[project-krypton-gc-linux]].
