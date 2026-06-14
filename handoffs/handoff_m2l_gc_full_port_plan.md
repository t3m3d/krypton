# Handoff m → l: GC full port to Linux ELF — staged implementation plan

**From:** agent m (macOS, M4)
**Date:** 2026-06-14
**Decision:** Brian chose **(a) full port** (bring precise GC to the ELF backends).
**Status:** PLAN ONLY — no code committed. I'm on macOS and cannot build/run/converge
ELF binaries on this box (no native x86-64/arm64 Linux loader; qemu/docker would be
blind anyway). Whole-GC machine code emitted blind would be offset-bug-ridden and
would corrupt the working bump backend — exactly the class of thing that needs a box
that can run the output. So this is the offset-level plan (the same kind W's
`stage6_phase3_plan.md` was for me), mapped to elf.k's real structures. **You
implement + converge on the Linux box.**

Primary target: `compiler/linux_x86/elf.k` (x86-64 SysV). `linux_arm64/elf.k` is a
second pass (same design, AArch64 encodings — do x86 first, mirror after it converges).

---

## 0. Why this is NOT a phase-3 mirror

macОЅ/Windows already had stages 1–6 (freelist alloc + conservative mark/sweep +
`kr_gc_collect`); phase 3 was a small tail-append. **Linux has none of it.** Both
ELF backends are bump allocators with every GC builtin stubbed:
- `linux_x86/elf.k` ~L3922-3933: `gcCollect`/`gcLiveCount`/`gcAllocCount`/
  `gcFreelistCount`/`gcWalkAllocs`/`gcShadowCount` → `PUSH_INT 0`; `gcShadowPush/Pop`
  → `POP; PUSH_INT 0`.
- `linux_arm64/elf.k` ~L796, ~L1080: `gcCollect` → no-op push 0.

So you build the whole stack. Good news below makes it tractable.

## 1. THE GOOD NEWS — elf.k's layout is data-driven (no manual offset cascade)

Unlike macho_arm64_self.k and x64.k (hardcoded byte offsets that cascade on every
edit), elf.k computes every runtime-helper vaddr as a running sum (see ~L6179-6260):

```
let krAllocVAddr  = krStrIntVAddr + krSiSz
let krStrlenVAddr = krAllocVAddr + krAlSz   // krAlSz = krAllocSize()
let krConcatVAddr = krStrlenVAddr + krSlSz
... ~70 helpers, each: prevVAddr + prevSize ...
let stringsBase   = krPadrightVAddr + krPrtSz
```

Each `emit*CodeFinal(thisVAddr, ..., targetVAddr)` computes its CALL disps from
**absolute vaddrs** (`dAlloc = allocVAddr - (thisVAddr + N)`). Consequences:

- **Growing a helper** (e.g. kr_alloc 7→30 B): bump its `krXxSize()` return value.
  Every downstream `*VAddr` and every CALL disp into/after it recomputes
  automatically. **Zero manual offset edits.**
- **Inserting a new helper** (kr_gc_collect, kr_gc_set_threshold): add (a) the
  `emitKrXxxCode()` + `krXxxSize()` pair, (b) a `let krXxxVAddr = krPrevVAddr +
  krPrevSz` line in the chain, (c) `let krXxSz = krXxxSize()` in the size block
  (~L6046), (d) emit its code into the helper-emit pass, (e) thread its VAddr to
  any caller's `emit*CodeFinal(...)` signature.
- The ONLY manual offsets are rel disps *within* one emit fn (from `thisVAddr + literal`).
  Self-contained — internal to each helper.

This means the port is additive and mostly mechanical once the design is fixed.

## 2. THE HARD BLOCKER — objects have no header

`kr_alloc` (L353-368) is 7 bytes: `MOV RAX,R15; ADD R15,RDI; RET`. Returns the raw
bump pointer. **There is no per-object metadata word.** macОЅ mark sets bit63 of
`[ptr-8]`; sweep walks the heap by reading each object's size from `[ptr-8]`. Linux
objects have no such word — mark/sweep have nowhere to store the bit or read sizes.

**Stage 0 (foundational): add an 8-byte header to every allocation.**

New `kr_alloc` (size in RDI → ptr in RAX):
```
; round RDI up to 8 (so headers stay aligned): ADD RDI,15; AND RDI,-8  (one of the
;   +8 is the header, +7 rounds the payload — pick your rounding, keep 8-aligned)
MOV  [R15], RDI        ; header = payload size (mark bit63 = 0, clear from mmap)
LEA  RAX, [R15+8]      ; object ptr = past header
LEA  R15, [R15+RDI+8]  ; bump past header+payload
RET
```
Header layout: bits[0..62] = payload byte count, bit63 = mark. Matches macho so the
mental model transfers. **This is the only change with semantic ripple** — but note
the callers don't care: they still receive a clean payload pointer and never touch
[ptr-8]. The ~25 `CALL kr_alloc` sites are unaffected (vaddr math auto-cascades; see §1).

⚠ Verify two things on-box after this stage alone (before any GC logic):
- Self-host still CONVERGES with the header in place (header math correct, no
  off-by-8 in any helper that does pointer arithmetic on alloc results — grep the
  `emitKr*CodeFinal` fns for `[RAX+...]` writes right after a `CALL kr_alloc`; they
  assume RAX is the payload start, which still holds).
- 8-alignment preserved across the whole `__text`+heap (mmap base is page-aligned;
  keep every bump a multiple of 8).

## 3. GC-globals band

Current globals (emitStartCode L3348): `[R14+0]=argc, [R14+8]=argv, [R14+16]=envp`,
then `LEA R15,[RAX+24]` (heap_next starts at +24). Carve a GC band and push R15 init:

| off | slot | set by |
|-----|------|--------|
| +0  | argc | _start (existing) |
| +8  | argv | _start (existing) |
| +16 | envp | _start (existing) |
| +24 | `heap_start` | _start: `MOV [R14+24], R15-after-init` (sweep walk lower bound + mark filter lo) |
| +32 | `stack_base` | _start: capture RSP **at entry** (= highest stack addr; argc sits at [RSP] on entry) → `MOV [R14+32], <saved RSP>` |
| +40 | `free_head` | gcReset/sweep |
| +48 | `collect_threshold` | gcSetThreshold (0 = disabled) |
| +56 | `allocs_since` | kr_alloc tail / reset after collect |
| +64 | (spare / heap_next mirror if you want gcAllocCount cheap) | |

Then `LEA R15,[RAX+24]` → `LEA R15,[RAX+72]` (or +80; keep 8-aligned, leave a spare).
Set `heap_start` = that same post-band value so sweep/mark filter use a tight lower
bound. **Capture stack_base in _start BEFORE consuming args** — at `_start` entry RSP
points at argc, the highest address the program stack reaches; save it first thing.

## 4. Stages (implement + converge each before the next)

Order matters — converge after every stage so a regression is bisectable.

**S0. Header** (§2) — alloc returns payload past an 8-byte size/mark header. Converge.

**S1. GC-globals band + stack_base capture** (§3). No behavior change yet; converge
to prove the band + R15 bump didn't break alloc.

**S2. kr_gc_collect helper = MARK + SWEEP** (new helper, insert per §1):
- **Mark** (single region — elf has no globals region, top-level lets are __main__
  stack locals; confirm via §6 Q1): scan `[RSP_at_collect_entry, [R14+32]]` word by
  word. For each word `v`: if `[R14+24] <= v < R15` and `v` 8-aligned → set bit63 of
  `[v-8]`. (Conservative; false-retain is fine.)
- **Sweep**: walk `p = [R14+24]` while `p < R15`; `sz = [p] & ~bit63`; if bit63 set →
  clear it; else → push `p` onto `free_head` (store old `[R14+40]` into `[p+8]` as the
  freelist next-link — payload ≥8 always, since header rounds up) and `[R14+40] = p`.
  Advance `p += (sz & ~bit63) + 8`.
- Wire `gcCollect` builtin (L3922) from `PUSH_INT 0` to `CALL kr_gc_collect; PUSH 0`
  (keep the net +1 eval-stack push — collect returns no value, the FE expects one).
- Wire `gcLiveCount` / `gcFreelistCount` / `gcAllocCount` from stub-0 to real walks
  (count marked objects / freelist length / heap-walk count). These make the test
  assertions meaningful.
- Test: a program that drops references then `gcCollect()` → live count drops,
  freelist grows. Converge.

**S3. Freelist CONSUME in kr_alloc**: before bumping, check `free_head` for a block
whose header size ≥ rounded RDI (macho used exact-size; first-fit is simpler and
fine). If hit: unlink (`[R14+40] = [block+8]`), return `block` (payload), don't bump.
Else bump as S0. Test: alloc after a collect reuses freed nodes (freelist count
drops, heap_next doesn't advance). Converge.

**S4. PHASE 3 — auto-collect + REGISTER SAFEPOINT** (the macho-equivalent hard part):
- `gcSetThreshold(N)` builtin: N is an **int** (match macОЅ — NOT a string+atoi like
  the Windows convention; `gcSetThreshold("100")` would store a pointer → never fires).
  Store to `[R14+48]`. Add to compile.k builtins CSV (already there from the macОЅ
  port — verify) + elf.k bname dispatch + opSize + emit.
- kr_alloc TAIL (after the alloc, before RET): `INC qword [R14+56]` (allocs_since);
  if `[R14+48]==0` → RET; if `[R14+56] < [R14+48]` → RET; else **SAFEPOINT**:
  - Spill the GP registers that may hold live heap roots across the alloc. SysV
    caller-saved = RAX,RCX,RDX,RSI,RDI,R8,R9,R10,R11. **But also the callee-saved
    R12–R15/RBX** because helpers like kr_concat keep `a` in R12, `b` in R13 live
    across `CALL kr_alloc` — those are in registers, NOT on the machine stack, so the
    conservative scan won't see them → use-after-free. Spill RBX,R12,R13,R14,R15? No —
    R14/R15 are the GC base/heap_next, keep them. Spill {RAX,RCX,RDX,RSI,RDI,R8,R9,
    R10,R11,RBX,R12,R13} (push all 12) so `MOV <scanlo>,RSP` in the collect sees them
    as conservative roots; the just-alloc'd RAX is spilled too → marked → survives.
  - `CALL kr_gc_collect` → `MOV qword [R14+56], 0` (reset) → pop the 12 → RET.
  - kr_alloc has no internal CALLs today, so the tail is pure append; size grows,
    vaddr chain auto-cascades (§1).
- ⚠ **RSP 16-alignment at `CALL kr_gc_collect`** — same bug W hit on Windows. At the
  CALL, RSP must be 16-aligned (SysV ABI; kr_gc_collect itself makes no external
  calls, but keep the discipline and if you add any syscall inside collect it
  matters). 12 pushes = 96 B = 16-aligned delta; verify the entry alignment and pad
  with one dummy push if odd.
- Test: `tests/gc_auto_collect.k` (exists from the macОЅ commit; uses `gcSetThreshold(100)`
  int form) → over N allocs, live stays bounded, root survives. Converge (host3==host4).

**S5. arm64 mirror**: repeat S0–S4 in `linux_arm64/elf.k` (AArch64 encodings; its
alloc + globals model differs — re-derive, same design). Converge on arm64.

## 5. Build / test / converge loop (your box)

(Fill in your actual ELF host names — analogues of the macОЅ loop.)
- FE: `KRYPTON_ROOT=$(pwd) compiler/linux_x86/kcc-linux-x86 --ir compiler/linux_x86/elf.k > x.kir`
  (use kcc directly, not a wrapper that truncates big IR).
- Backend: `compiler/linux_x86/elf_host --ir x.kir newhost` (or your host's CLI — check
  whether it takes `--ir`; the arm64 dir has `elf_host` + `kcc-linux-arm64`).
- `chmod +x`; run tests. **Convergence = host3==host4** byte-identical in the code
  region (host2 is the transitional gen: old codegen building the new logic). Reseed
  the bootstrap host + kcc once green.
- Branch, don't touch main until a stage converges. (W's model: ship to a branch,
  run-test on the native box, merge when green.)

## 6. Open questions to resolve ON-BOX before coding

1. **Where do __main__ top-level `let`s live in elf.k?** I found no `LOAD_GLOBAL`/
   `STORE_GLOBAL` in elf.k (macho has them); STORE_LOCAL/LOAD_LOCAL are RBP-relative
   (L3442). Strongly implies top-level lets are __main__ stack-frame locals → the
   single `[RSP, stack_base]` scan covers them. **CONFIRM** by tracing how a top-level
   `let s = ...` used in __main__ is emitted. If any global data region exists, mark
   must scan it too (then it's the macho two-region story).
2. **Which regs does the elf evaluator keep live across a `CALL kr_alloc`?** It's a
   stack machine (PUSH/POP RAX), so most temporaries spill to the machine stack
   (covered by the scan). The exceptions are inside the hand-written helpers
   (kr_concat R12/R13, kr_range R14-buf, kr_index, etc.). Audit each `emit*CodeFinal`
   that brackets a `CALL kr_alloc`: any value held in a register across that call is a
   root the auto-collect safepoint must spill. List them; size the safepoint to cover
   the union. (This is why S4 spills callee-saved R12/R13 too.)
3. **Heap size vs collect cadence.** Heap is 0x70000000 (~1.875 GB) lazy mmap
   (L3361). With real GC you can lower it, but not required — leave it; GC just
   reclaims within it.

## 7. References
- macОЅ design (the stack you're mirroring): commits `ea577322` (conservative mark),
  `2d346ca6` (phase 3 + register safepoint). Handoffs:
  `handoff_m2wl_gc_stage6_phase3_macho.md` (safepoint rationale),
  `handoff_m2l_gc_conservative_mark_macho.md` (two-region mark — yours is one-region),
  `handoff_m2l_gc_stage6_macho.md` (the three macОЅ alloc gotchas — analogues here).
- Windows phase 3 (string-vs-int threshold, RSP-align bug): `handoff_m2w_gc_stage6_phase3_windows.md`.
- Status handoff that triggered this: `handoff_m2l_gc_stage6_status.md`.

Ping Brian / me (m) if Q1 turns up a globals region — that changes the mark in S2.
