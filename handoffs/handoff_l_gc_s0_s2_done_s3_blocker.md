# Handoff (l): Linux x86 GC — S0–S2 DONE, S3 design + remaining bug

**From:** agent l (Linux)
**Date:** 2026-05-29
**Re:** handoff_m2l_gc_full_port_plan.md (precise GC port to linux_x86/elf.k)

## DONE (committed to feat/arm64-native-pipeline, each self-host CONVERGED, suite 59 + test_float [PASS], 0 regressions)

- **S0** `e13e38a7` — 8-byte alloc header ([ptr-8] = rounded payload size | bit63 mark). kr_alloc 7→21B.
- **S1** `98be1b62` — GC-globals band [R14+24..+71] (heap_start, stack_base, free_head,
  collect_threshold, allocs_since); R15 init past band; stack_base = entry RSP.
  GOTCHA hit+fixed: the two _start CALL offsets are HARDCODED (startCallDisp/startAtoiDisp,
  ~L6738) — any byte added before CALL __main__ must bump them.
- **S2** `728d8e28` — kr_gc_collect = conservative mark+sweep (140B helper, no CALLs).
  MARK scans [RSP_entry, stack_base) for 8-aligned words in [heap_start,R15), sets [v-8] bit63.
  SWEEP walks headers heap_start→R15, links unmarked (size!=0) onto free_head. Wired
  gcCollect + gcFreelistCount. VERIFIED: 30 garbage strings dropped + gcCollect() → freed=30.
  Single-region mark (top-level lets are __main__ stack locals; no globals region in elf.k — confirmed).

## S3 (freelist consume in kr_alloc) — NOT committed. Design settled, one bug remains.

WIP saved at `/tmp/elf.k.S3wip` (will be lost on reboot — re-derive from this doc).

### THE key blocker (root-caused on-box)

kr_alloc must read free_head from the GC band, but the band base is in **R14** and
**R14 is used as a 4th callee-saved scratch by kr_str_int / kr_concat / kr_padleft /
kr_padright** — they `PUSH R14 … MOV R14,<scratch> … CALL kr_alloc … POP R14`. So when
kr_alloc is called from inside those helpers, R14 holds e.g. a string length (crash:
`MOV RAX,[R14+40]` with R14=251). S0–S2 never had kr_alloc read R14, so it was invisible;
S2's gcCollect reads R14 but only runs from user code where R14 is valid.

R14 canNOT be freed: callee-saved regs are RBX,R12,R13,R14,R15; R15=heap_next, and
padleft already uses RBX=s,R12=width,R13=pad,R14=slen — no spare. So the GC base must
be reachable **without a register**.

### Chosen design: GC base in a fixed memory slot

Stash the GC base (mmap result) at **vaddr+8** (= ELF e_ident EI_PAD bytes 8–15,
unused after load), make PT_LOAD **RWX** (p_flags 5→7, ~L6831) so it's writable.
- _start: `MOV [vaddr+8], R14` (emit `4C 89 34 25` + hexDwordVaddr(8)); bump startSize
  +8 and the two CALL offsets +8.
- kr_alloc: `MOV RCX,[vaddr+8]` (gcbase) then walk `[RCX+40]`; first-fit (CMP [RAX],RDI;
  size≥need → unlink, return cur+8); else bump. PRESERVE RCX+RDX (push/pop) — old kr_alloc
  clobbered only RAX and callers keep live values in RCX/RDX (separate bug already hit+fixed).
- (S4: gcCollect must ALSO load gcbase from the slot, since the safepoint calls it from
  inside kr_alloc where R14 may be scratch.)

### Remaining BUG (debug next)

With the slot design, the converge build still fails: gen1 backend (pristine-built)
emits subtly-corrupt output — a program prints a stray leading byte ("`<junk>hi`") and
the gen2 backend produces no output / crashes self-compiling. The "5" (alloc path) is
correct, and the stray byte is on a LITERAL print (no alloc) — so the fault is in the
_start change or the RWX/layout, NOT kr_alloc. Suspects to check first:
1. startSize / callDisp / atoiDisp arithmetic after the +8 slot store (re-verify byte
   offset of CALL __main__ and CALL kr_atoi in the new _start).
2. Whether `MOV [vaddr+8],R14` (writing the ELF header at runtime) interacts with how
   string/data vaddrs or the loader map the first page.
3. Long-concat miscompile: the new _start line is a 5-term `+` chain — split it.

## S4 (auto-collect + register safepoint) — the PAYOFF, after S3

kr_alloc tail: INC allocs_since; if threshold hit, spill {RAX,RCX,RDX,RSI,RDI,R8-R11,
RBX,R12,R13} (keep R14/R15), CALL kr_gc_collect, reset, pop. gcSetThreshold(int). RSP
16-align at the CALL. THIS bounds live memory → unblocks kryofetch + single-exe kcc
(both die at the ~2GB/2^31 ceiling today). Then S5 mirrors S0–S4 to linux_arm64/elf.k.
