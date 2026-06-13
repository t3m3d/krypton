# Stage 6 phase 3 — auto-trigger gcCollect on threshold crossing

**Author:** agent w (Windows)
**Date:** 2026-06-13
**Status:** PLANNED, awaiting (a) successful regen of `x64_host_windows_x86_64.exe`,
(b) `tests/gc_freelist_consume.k` pass on the regen'd host.
**Cross-platform note:** mark and sweep aren't on macOS / Linux yet. This phase
lands on Windows first; agent m / agent l adopt the same shape once their backends
reach stage 5.

## Goal

Make GC fully automatic. Today `gcCollect()` only runs when user code calls it
explicitly. Phase 3 adds a threshold so the allocator self-triggers when
`alloc_count` crosses `collect_threshold`. With a sensible default threshold,
Krypton programs reclaim memory continuously with no user opt-in.

## What the user sees

```krypton
gcSetThreshold("10000")        // collect every 10k allocs
// ... normal Krypton code ...
// __rt_alloc_v2 auto-runs gcCollect() when alloc_count crosses 10k
```

Threshold 0 = disabled (existing programs see no behavior change — backward
compatible). Default in `kr_init_args`: TBD; sensible starting point is `8192`
which matches one slab page of bumped allocations.

## Design

### Two new gcGlobals slots

Layout extension (was 88 bytes, becomes 104):

```
+0   alloc_total
+8   alloc_limit
+16  slab_first
+24  slab_curr
+32  slab_off
+40  alloc_count
+48  shadow_base
+56  shadow_sp
+64  allocs_head
+72  free_head
+80  wndproc_funcptr
+88  collect_threshold      ← NEW (phase 3)
+96  in_collect_guard       ← NEW (phase 3)
```

`collect_threshold` = 0 → disabled. Nonzero → fire `kr_gc_collect` on each
`__rt_alloc_v2` exit where `alloc_count >= collect_threshold`.

`in_collect_guard` = 0 → not in collection. Set to 1 just before CALL
kr_gc_collect, reset to 0 after. Prevents re-entry if `kr_gc_collect` (or any
helper it calls) ever ends up routing through `__rt_alloc_v2` and re-checking
the threshold — would infinite-loop without the guard.

### Where the check fires

At the **tail** of `__rt_alloc_v2`, just before `RET`. Reason: the function has
two exits (freelist-hit at byte 144, slab path at byte 381). Putting the check
at the start would shift every internal offset by ~70 bytes — repeats the
phase-2 cascade audit. Putting it at the tail and redirecting both RET sites to
a shared check epilogue means:

- The 2 existing 7-byte epilogue sequences (`ADD RSP,0x28; POP RSI; POP RBX; RET`)
  get replaced in-place with 5-byte `JMP rel32` + 2 NOPs (same total bytes, no
  shift).
- The new ~72-byte tail block is **appended** at offset 382 (current end of
  `__rt_alloc_v2`). Function grows 382 → 454.
- No internal offset rewrites needed inside `__rt_alloc_v2`.

### Auto-check tail (offset 382 → 453, 72 bytes)

On entry: `RAX` = user pointer to return. Stack still has `PUSH RBX; PUSH RSI;
SUB RSP, 0x28`. Caller convention preserved.

```
;; Read threshold; if 0, skip check.
MOV  RDX, [RIP+collect_threshold]      ; 48 8B 15 dd dd dd dd  (7 bytes)
TEST RDX, RDX                          ; 48 85 D2              (3)
JZ   .restore (rel8 +N)                ; 74 NN                  (2)

;; Check the re-entry guard; if already collecting, skip.
MOV  RCX, [RIP+in_collect_guard]       ; 48 8B 0D dd dd dd dd  (7)
TEST RCX, RCX                          ; 48 85 C9              (3)
JNZ  .restore (rel8 +N)                ; 75 NN                  (2)

;; Compare alloc_count vs threshold.
MOV  RCX, [RIP+alloc_count]            ; 48 8B 0D dd dd dd dd  (7)
CMP  RCX, RDX                          ; 48 39 D1              (3)
JB   .restore (rel8 +N)                ; 72 NN                  (2)

;; --- trigger collection ---
PUSH RAX                               ; 50                     (1)  preserve return ptr
MOV  QWORD [RIP+in_collect_guard], 1   ; 48 C7 05 dd dd dd dd 01 00 00 00  (11)
CALL kr_gc_collect (rel32)             ; E8 dd dd dd dd        (5)
MOV  QWORD [RIP+in_collect_guard], 0   ; 48 C7 05 dd dd dd dd 00 00 00 00  (11)
POP  RAX                               ; 58                     (1)

.restore:
ADD  RSP, 0x28                         ; 48 83 C4 28           (4)
POP  RSI                               ; 5E                     (1)
POP  RBX                               ; 5B                     (1)
RET                                    ; C3                     (1)
```

Total: **72 bytes**. (7+3+2 + 7+3+2 + 7+3+2 + 1+11+5+11+1 + 4+1+1+1 = 72.)

Three rel8 JZ/JNZ/JB targets all point to `.restore` at offset 65 within the tail
(= absolute offset 382+65 = 447).

- JZ at tail[12] (RIP-after = 14): disp8 = 65 - 14 = 51
- JNZ at tail[24] (RIP-after = 26): disp8 = 65 - 26 = 39
- JB at tail[36] (RIP-after = 38): disp8 = 65 - 38 = 27

All within rel8 range (-128..127). Good.

`CALL kr_gc_collect` is rel32 — resolved at emit time the same way other CALLs
into the helper block are (compute `kr_gc_collect_offset - (textRva + pos + 5)`).
`kr_gc_collect` lives at a fixed position in the helper block (find via the
offsets table).

### Redirect both existing RET sites

**Freelist-hit exit** currently at offset 138–144 (7 bytes):
```
[138-141] ADD RSP, 0x28
[142]     POP RSI
[143]     POP RBX
[144]     RET
```

Replace with:
```
[138-142] JMP .auto_check_tail (rel32)   ; E9 dd dd dd dd  (5)
[143-144] NOP NOP                        ; 90 90           (2)
```

JMP rel32 displacement: target = 382, RIP-after = 143. disp = 382 - 143 = 239.

**Slab path epilogue** currently at offset 375–381 (7 bytes): same pattern.

Replace with:
```
[375-379] JMP .auto_check_tail (rel32)   ; E9 dd dd dd dd  (5)
[380-381] NOP NOP                        ; 90 90           (2)
```

JMP rel32: disp = 382 - 380 = 2.

### New builtin `gcSetThreshold(n)` → `kr_gc_set_threshold`

Mirror `kr_gc_set_limit` shape (23 bytes). Appended at end of helper block.

```
;; RCX = Krypton-side value (smart-int / string). atoi it.
PUSH RCX                          ; 51                     (1)
SUB  RSP, 0x28                    ; 48 83 EC 28            (4)
CALL __user_rt_atoi (rel32)       ; E8 dd dd dd dd         (5)  → RAX = parsed int
ADD  RSP, 0x28                    ; 48 83 C4 28            (4)
POP  RCX                          ; 59                     (1)
MOV  [RIP+collect_threshold], RAX ; 48 89 05 dd dd dd dd   (7)
RET                               ; C3                     (1)
```

Total: 23 bytes.

`collect_threshold` lives at `gcGlobalsRva + 88`.

Note: `__user_rt_atoi` is a fixed-position helper at the start of user .text on
non-bootstrap binaries. In the bootstrap (krypton_rt.dll) build, this builtin is
exported and resolved differently — check phase 2's `kr_gc_set_limit` for the
exact callsite pattern.

### Wiring changes elsewhere in x64.k

1. **`KRRT_FUNCS` CSV** — append `,kr_gc_set_threshold` at end.

2. **`compile.k` builtin name mapping** — add `if name == "gcSetThreshold" { emit
   "kr_gc_set_threshold" }` next to `gcSetLimit` (line 1560).

3. **`bsRdataRvaB` import-table offset** — `buildBootstrapImportTable(bsRdataRvaB,
   88)` becomes `... 104` (and the other `88 +` sites — search for `88`
   adjacent to `bsImpSz`, `bsExpHex`, etc., update each).

4. **`bsHelperBlockSize`** bumped: current 9445 → 9445 + 72 (tail) + 23
   (new helper) = **9540**.

5. **Helpers after `__rt_alloc_v2` shift +72** (auto-check tail). Per the phase-2
   audit:
   - `bufsetbyte_real_impl`: 8045 → 8117
   - `writebytes_real_impl`: 9190 → 9262
   - `gcc_mark_target`: 8623 → 8695
   - `gcc_sweep_target`: 8754 → 8826

   Verify these are all the constants that point to post-`__rt_alloc_v2`
   helpers. Last phase-2 audit caught all of them.

6. **gcSetThreshold helper offset** — append at end. Position = 9540 - 23 = 9517
   (in helper-block-relative offset). Add `kr_gc_set_threshold:9517` to the
   offsets table.

### Default threshold

`kr_init_args` is where the GC globals get initialized post-load. Set
`collect_threshold` to either:

- **0** — opt-in only (safest default; matches phase-2 behavior). User must
  call `gcSetThreshold("N")` to enable.
- **8192** — a reasonable starting threshold (~ one slab's worth of small
  allocations before collection). Programs benefit immediately.

**Recommendation:** ship as 0 in phase 3 itself, ship a separate one-line follow-up
that bumps the default to 8192 after a few days of validation. Keeps the
moving-parts count low per commit.

## Test plan

New file `tests/gc_auto_collect.k`:

```krypton
just run {
    gcSetThreshold("100")
    let preCount = gcAllocCount()
    print("pre alloc_count: " + preCount)

    // Force lots of temp allocs (each `+` makes one). 200 iterations
    // should cross the 100 threshold, triggering at least one auto-collect.
    let s = ""
    let i = 0
    while i < 200 {
        s = "x" + i
        i = i + 1
    }

    let postCount = gcAllocCount()
    print("post alloc_count: " + postCount)
    print("freelist: " + gcFreelistCount())

    // If auto-trigger fired, freelist should be non-empty (sweep deposited
    // unmarked temps) AND alloc_count growth should not be 200 (some
    // reuse via freelist consume).
    if gcFreelistCount() == "0" {
        print("[FAIL] freelist empty — auto-trigger never fired")
        exit("1")
    }
    print("[OK] auto-trigger fired and freelist populated")
}
```

Expected after rebuild: `[OK] auto-trigger fired and freelist populated`.

## Commit plan

One commit, same untested gating as phase 2:

```
x64.k: stage 6 phase 3 auto-trigger gcCollect on alloc_count threshold

⚠️ SOURCE-ONLY pending x64_host regen.

Adds gcSetThreshold(n) builtin + auto-check tail at __rt_alloc_v2 exit.
When alloc_count >= collect_threshold (and not already collecting),
fires kr_gc_collect via tail-call.  Threshold 0 = disabled (default).

gcGlobals 88 → 104 bytes (collect_threshold @+88, in_collect_guard @+96).
__rt_alloc_v2 grows 382 → 454 (72-byte appended tail; both existing RET
sites become JMP rel32 + 2 NOPs, no internal shift).
New kr_gc_set_threshold helper at end of helper block (23 bytes).
Helpers after __rt_alloc_v2 shift +72; offset constants updated.
bsHelperBlockSize 9445 → 9540.

New tests/gc_auto_collect.k regression test.

Co-Authored-By: ...
```

## Risk register

- **gcGlobals expansion** — only 16 bytes more, but every `88` literal adjacent
  to `bsImpData` / `bsImpSz` / `bsExpHex` / `bsRdataSz` must move to `104`.
  grep for `88 +`, `, 88`, `RvaB.*88`. Phase 2 didn't touch this; this is the
  first phase 3 surface bug risk.
- **JMP rel32 from offset 380 with disp=2** is valid (just jumps past the 2 NOPs
  into the tail). Visually weird but correct.
- **`__user_rt_atoi` availability** — in the bootstrap (krypton_rt.dll) build,
  this helper isn't present. `kr_gc_set_limit` handles this somehow; copy its
  exact approach for `kr_gc_set_threshold`. Risk: cargo-cult wrong; verify the
  pattern works for set_limit before assuming it generalises.
- **kr_gc_collect re-entrancy** — current `kr_gc_collect` body shouldn't allocate
  (just walks chain + marks + sweeps + freelist deposits). But if any future
  change makes it allocate, the `in_collect_guard` is the safety net. **Keep the
  guard even after this lands** — it's cheap insurance.
- **Cascade arithmetic** — 4 helper-offset constants must all move +72. Phase 2
  caught them all; same audit list applies. Pre-merge: grep for each constant and
  verify post-edit numbers.

## Why this can be source-only first

The phase-3 surface is small (3 code blocks) and entirely additive at the user
level. If validation finds a bug after regen, the revert is single-commit. Same
gating posture as phase 2.

## Cross-references

- Phase 2 cherry-pick: commit `5185d50e` (the freelist-consume code phase 3 builds
  on).
- Phase 2 memory: [[project_stage6_phase2]].
- The stage-6 design doc: `docs/v20_mark_sweep_design.md` (if extended to include
  phase 3 wording, add an entry here too).
- Allocator entry: `compiler/windows_x86/x64.k` near line 6758
  (`__rt_alloc_v2`).
- `gcGlobals` layout block: line ~8838.
