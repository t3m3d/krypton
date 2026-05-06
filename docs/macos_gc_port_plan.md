# macOS arm64 — GC Port Plan (1.7.5 + 1.7.6 features)

Target: bring the macOS arm64 backend (`compiler/macos_arm64/macho_arm64_self.k`)
to functional parity with the Windows native backend on the GC primitives
shipped in 1.7.5 and 1.7.6.

Status: this doc was written from a Windows host; **execute on the M1
MacBook**. The Windows code is the source of truth for the algorithm;
this doc maps it to Mach-O / arm64 specifics.

---

## What you're starting with (good news)

The macOS backend already has a **bump allocator**. See
`compiler/macos_arm64/macho_arm64_self.k:797` (`emitAllocN`). It:

- Lives in the zero-fill portion of `__DATA` (`bump cell @ DATA_VADDR + 0x4000`)
- Loads the current bump pointer, stores back the advanced pointer
- Handles first-time init via the `cbnz` dance (loaded ptr == 0 → use
  cell address + 64 as initial heap)

So macOS arm64 is *already at Tier 2 architecture*, just without:
- Allocation tracking (`alloc_total`)
- Soft limit / circuit breaker (`alloc_limit` + `ExitProcess`-equivalent)
- API surface (`gcAllocated`, `gcLimit`, `gcSetLimit`, `gcReset`, `gcCollect`)

**The port is mostly: add 5 new global cells and 5 new builtins. No new
section, no PE-equivalent layout surgery.**

---

## Layout — extend the `__DATA` zero-fill region

Current `__DATA` zero-fill cells (per `emitAllocN`):
```
bump cell  @ DATA_VADDR + 0x4000  (8 bytes)
heap       @ DATA_VADDR + 0x4000 + 64 .. DATA_VADDR + DATA_VMSIZE
```

The "system area at +8..+63" comment in `emitAllocN` already reserves
56 bytes after the bump cell. We can use those for GC globals without
expanding `DATA_VMSIZE` at all.

Proposed layout:
```
DATA_VADDR + 0x4000 + 0    : bump_cell      (8 B) — current free pointer (existing)
DATA_VADDR + 0x4000 + 8    : alloc_total    (8 B) — total bytes allocated (NEW)
DATA_VADDR + 0x4000 + 16   : alloc_limit    (8 B) — soft cap (NEW)
DATA_VADDR + 0x4000 + 24   : reserved       (8 B)
DATA_VADDR + 0x4000 + 32   : reserved       (8 B)
DATA_VADDR + 0x4000 + 40   : reserved       (8 B)
DATA_VADDR + 0x4000 + 48   : reserved       (8 B)
DATA_VADDR + 0x4000 + 56   : reserved       (8 B)
DATA_VADDR + 0x4000 + 64   : heap starts here (existing)
```

Note: 64 KB total `__DATA` heap is *much* smaller than Windows' 64 MB
slab. kryofetch on Windows uses ~110 KB per render (1.7.6 measurement)
and would blow past 64 KB on macOS. Consider bumping `DATA_VMSIZE`
from `0x10000` (64 KB) to `0x4000000` (64 MB) to match Windows. Check
that the Mach-O loader is OK with that — should be (it's just zero-fill).

---

## Modify `emitAllocN` — add tracking + limit check

Current 7-instruction sequence (~28 bytes):
```
adrp x1, bump_cell@PAGE
add  x1, x1, bump_cell@PAGEOFF
ldr  x0, [x1]              ; current free
cbnz x0, +2                ; skip init
add  x0, x1, #64           ; first-time: heap = cell + 64
add  x2, x0, #nAligned     ; new free
str  x2, [x1]              ; advance bump
```

New sequence (~12-14 instructions, depending on how you encode the limit
check):
```
adrp x1, bump_cell@PAGE        ; same as before
add  x1, x1, bump_cell@PAGEOFF
                                ; --- NEW: tracking ---
ldr  x3, [x1, #8]              ; alloc_total
add  x3, x3, #nAligned         ; total += size
str  x3, [x1, #8]
                                ; --- NEW: limit check ---
ldr  x4, [x1, #16]             ; alloc_limit
cbz  x4, .skip_check           ; if limit == 0, skip
cmp  x3, x4
b.ls .skip_check               ; if total <= limit, ok
                                ; LIMIT EXCEEDED — call exit(99)
                                ; arm64 calling: x0 = 99, syscall via libsystem
                                ; OR: brk #0 / immediate trap
                                ; (see note below)
.skip_check:
                                ; --- existing bump ---
ldr  x0, [x1]
cbnz x0, +2
add  x0, x1, #64
add  x2, x0, #nAligned
str  x2, [x1]
```

**Limit-exceeded path on macOS arm64**: the simplest bail is `brk #99`
(software trap with immediate). That kills the process with SIGTRAP.
Cleaner option: call `_exit(99)` via libsystem — but that needs a
chained-fixup entry which is more setup. Recommend `brk #99` for the
first cut; user sees a "Trace/BPT trap" error with code 99. Match
Windows' `ExitProcess(99)` semantics later.

---

## Five new helper functions

Each lives at a known label in `__TEXT,__text`. The compiler emits them
just like existing `emit*` helpers in `macho_arm64_self.k`.

### `kr_gc_allocated() → x0 = pointer to itoa(alloc_total)`
```
adrp x1, bump_cell@PAGE
add  x1, x1, bump_cell@PAGEOFF
ldr  x0, [x1, #8]              ; alloc_total
b    __rt_itoa                 ; tail-call, returns ptr in x0
```

### `kr_gc_limit() → x0 = pointer to itoa(alloc_limit)`
Same shape, ldr from `[x1, #16]` instead of `[x1, #8]`.

### `kr_gc_set_limit(x0 = n_str) → x0 = n_str (echo)`
```
mov  x19, x0                   ; save input ptr (callee-saved on arm64)
bl   __rt_atoi                 ; x0 = int
adrp x1, bump_cell@PAGE
add  x1, x1, bump_cell@PAGEOFF
str  x0, [x1, #16]             ; alloc_limit = atoi result
mov  x0, x19                   ; restore input ptr
ret
```

Note: x19-x28 are callee-saved on arm64; x0-x18 are caller-saved. So
we need to push x19 + x30 (link register) onto the stack at function
entry and pop at exit. Standard arm64 prologue/epilogue:
```
stp  x29, x30, [sp, #-32]!     ; save FP/LR, alloc 32 bytes stack
str  x19, [sp, #16]
... function body ...
ldr  x19, [sp, #16]
ldp  x29, x30, [sp], #32
ret
```

### `kr_gc_collect() → x0 = pointer to "0"`
Allocate 2 bytes, write '0' and 0, return ptr. Or tail-call a helper
that does that — same as the Windows version's placeholder.

### `kr_arena_reset() → x0 = pointer to "0"`
```
adrp x1, bump_cell@PAGE
add  x1, x1, bump_cell@PAGEOFF
str  xzr, [x1]                 ; bump_cell = 0  (forces re-init via cbnz dance)
str  xzr, [x1, #8]             ; alloc_total = 0
b    kr_gc_collect             ; tail-call returns "0"
```

This is even simpler than Windows because the existing `cbnz`-and-init
dance handles "zero means re-init from cell+64" — so writing 0 to
`bump_cell` automatically re-uses the slab from the start on the next
allocation.

---

## Compiler bindings (mirror Windows)

In whatever the macOS-side equivalent of `resolveBuiltin` is (likely a
similar function in `macho_arm64_self.k`):
```
if name == "gcAllocated"   { emit "kr_gc_allocated" }
if name == "gcLimit"       { emit "kr_gc_limit" }
if name == "gcSetLimit"    { emit "kr_gc_set_limit" }
if name == "gcCollect"     { emit "kr_gc_collect" }
if name == "gcReset"       { emit "kr_arena_reset" }
```

`compile.k`'s builtins list **already has these names** (added in
1.7.5/1.7.6). No changes to compile.k needed.

---

## arm64 instruction encoding cheat sheet

Reuse the existing `arm64_*` helper functions in `macho_arm64_self.k`
(adrp, add_imm, ldr_imm, str_imm, cbnz, etc.). For the new ones:

| Instruction | Helper | Notes |
|---|---|---|
| `cbz xN, +imm` | `arm64_cbz(reg, off)` | Likely needs adding; mirror `cbnz` with bit 24 cleared |
| `cmp xN, xM` | `arm64_cmp(rN, rM)` | SUBS xzr, xN, xM under the hood |
| `b.ls label` | `arm64_b_cond(0x09, off)` | LS = unsigned lower-or-same |
| `bl label` | `arm64_bl(off)` | BL with 26-bit signed offset |
| `b label` | `arm64_b(off)` | Same as BL but without link |
| `ret` | `arm64_ret()` | RET x30 |
| `brk #N` | `arm64_brk(imm16)` | Software breakpoint |
| `mov xD, xS` | `arm64_mov_reg(rD, rS)` | ORR xD, xzr, xS |
| `stp / ldp` | likely needs adding | Pair store/load for prologue |

If any of these helpers are missing from `macho_arm64_self.k`, write
them following the pattern of existing helpers (compute the encoding
by hand from the ARM ARM, return as `hexDword(...)`).

---

## Smoke test plan (run on M1)

After each port milestone, smoke-test on M1 before moving on:

1. **After tracking + limit + 5 helpers compile**: build kcc, then build
   a tiny test program:
   ```krypton
   just run {
       kp("alloc=" + gcAllocated())
       let s = "hello" + " world"
       kp("alloc=" + gcAllocated())
   }
   ```
   Expected: second number > first, both small (< 100 bytes).

2. **After `gcSetLimit` works**: run the limit test from
   `c:/tmp/test_gc_limit.k` (allocate in a loop after setting limit
   to 100 bytes). Expected: process aborts (SIGTRAP if you used
   `brk #99`, exit code 99 if you wired libsystem `_exit`).

3. **After `gcReset` works**: run the multi-render kryofetch comparison.
   Expected: with reset between renders, alloc count stays bounded
   instead of growing linearly.

4. **Regression**: build `examples/fibonacci.k`. Expected: same Mach-O
   output as before the port + clean run + valid ad-hoc signature.

---

## Things I'm unsure about (verify on M1)

- **Whether `DATA_VMSIZE = 0x10000` (64 KB) is enough.** kryofetch on
  Windows hits 110 KB per render. If you don't bump it to 64 MB, you'll
  hit the cap fast. Test bumping to `0x4000000` and verify the Mach-O
  still loads.
- **Whether the existing `bump cell` location collides with my proposed
  GC global slots.** The comment says "system area at +8..+63" — read
  the macho code to confirm nothing else writes to those bytes.
- **Whether the ad-hoc SHA-256 codesign covers `__DATA` zero-fill.**
  If it does and you write to it at runtime, codesign verification might
  reject. Windows had the analogous concern (made `.rdata` writable);
  on macOS, anonymous zero-fill pages should be exempt from codesign,
  but verify.
- **Whether arm64 `b.ls` (unsigned lower-or-same) needs a different
  condition code than I wrote.** Cross-check with ARM ARM section C2.

---

## Sequencing on the M1

1. Pull latest from main (1.7.5 + 1.7.6 changes are committed)
2. Read `compiler/macos_arm64/macho_arm64_self.k:797-828` (`emitAllocN`)
   to confirm current bump-allocator state matches this doc
3. Bump `DATA_VMSIZE` if needed; rebuild kcc on M1; smoke-test fibonacci
   to confirm the bigger heap doesn't break anything
4. Add the 5 GC global slots' load/store in `emitAllocN` (tracking +
   limit check)
5. Add the 5 helper functions (`kr_gc_allocated`, etc.)
6. Wire `resolveBuiltin` mappings
7. Smoke-test in order (1 → 4 from above)
8. Cut a `1.7.5-mac-port` snapshot to `versions/kcc_v175_mac.exe`-equivalent
   (or wherever macOS snapshots live)
9. Report results back so we can decide whether to roll into 1.7.7 / 1.8

No rush, no kcc invocations on Windows from this port — entirely
M1-side work. Windows side stays untouched.

---

## Reference files

- Windows source of truth for the algorithm:
  `compiler/windows_x86/x64.k` lines ~5470 (`__rt_alloc_v2`) and
  the `emitBootstrapHelpers` function generally
- macOS bump allocator: `compiler/macos_arm64/macho_arm64_self.k:797`
  (`emitAllocN`)
- 2.0 plan: `docs/v20_plan.md`
- Latest CHANGELOG entries: `[1.7.5]` and `[1.7.6]` for the Windows-side
  features being ported
