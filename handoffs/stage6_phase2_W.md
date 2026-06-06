# Handoff — Stage 6 phase 2 (freelist consumption) source-shipped, build pending

**Status: source on branch `stage6-phase2-freelist-consume` (eb844258). Binary
not rebuilt. Manual rebuild + test needed on a machine with ≥48 GB free RAM.**
— agent W, 2026-06-06 night

## What landed

A 69-byte freelist-consumption block inserted at offset 76 of `__rt_alloc_v2`
in `compiler/windows_x86/x64.k`. On entry RBX = inflated+aligned request size.
The block:
1. Loads `free_head` from `gcGlobals[72]`.
2. If non-NULL AND its size+flags (low 2 bits masked) ≥ RBX:
   - Unlinks from `free_head`.
   - Re-links into `gcAllocsHead` so the next mark walker still sees it.
   - Bumps `alloc_count`.
   - Returns `ptr+16` (user data, past the 16-byte header).
3. Otherwise falls through to the slab bump path unchanged.

This is the load-bearing change for stage 6: phase 1 (sweep → free_head)
already shipped; phase 2 (alloc ← free_head) closes the loop so `gcCollect`
actually recycles memory instead of just shuffling pointers.

## Why not on main

The native rebuild of `x64.k` OOM'd `kcc-bin.exe` at ~25 GB RAM and growing.
This is **pre-existing** O(n²) string-concat behaviour in compile.k's FE,
exposed by x64.k's current size (9700+ lines, ~150 KB on disk). The IR-only
pass (`--ir`) was at 22 GB RAM and accelerating when I killed it for system
safety. The currently-installed `x64_host_new.exe` (May 31) was presumably
built when x64.k was smaller. **Phase 2 source compiles fine in principle;
the build environment is the bottleneck.**

So phase 2 sits on its own branch. Anyone with the RAM headroom can:

```
git fetch && git checkout stage6-phase2-freelist-consume
kcc -o /tmp/x64_host_new.exe compiler/windows_x86/x64.k
cp /tmp/x64_host_new.exe /c/krypton/bin/x64_host_new.exe
kcc -o /tmp/krypton_rt.dll runtime/krypton_rt.k
cp /tmp/krypton_rt.dll /c/krypton/krypton_rt.dll
cp /tmp/krypton_rt.dll %TEMP%/krypton_rt.dll
kcc -r tests/gc_freelist_consume.k
# Expected: freelist count drops after the 3 new allocs.
```

If it works, fast-forward main and the branch retires.

## Cascade audit (high confidence — mechanical)

`__rt_alloc_v2` grows 313 → 382 bytes. Insertion at offset 76 means:
- Every offset ≥ 76 shifts +69.
- Internal JMPs within the original code keep their disps (both source and
  target shift the same +69, so deltas are invariant).
- Only the JA `.huge_alloc` disp32 changes (source at 70-75 doesn't shift,
  target does): **178 → 247**.

Constants updated:
| | old | new |
|---|---|---|
| `bsHelperBlockSize` | 9376 | 9445 |
| `bufsetbyte_real_impl` | 7976 | 8045 |
| `writebytes_real_impl` | 9121 | 9190 |
| `gcc_mark_target` | 8554 | 8623 |
| `gcc_sweep_target` | 8685 | 8754 |

All v2_* disp constants for offsets ≥ 76 bumped by their `+69` cascade.
The new `v2_fl_*` disp constants are derived fresh from RIP-after positions
within the inserted block (83, 110, 117, 127, 134).

Internal JZ/JB displacements in the freelist block are rel8 (`+57`, `+45`)
both targeting `.fl_skip` at byte 145. Both fit rel8 range.

## What's deferred

- **Phase 3 (auto-trigger)**: add a `gcSetThreshold(n)` builtin + a check in
  `__rt_alloc_v2` after `alloc_count++` that auto-calls `kr_gc_collect` when
  the threshold is crossed. ~25 bytes of additional helper code; cascade is
  the new .epilogue offset only. Easy add once phase 2 is verified.
- **The x64.k build-time RAM blowup**: pre-existing, worth its own
  investigation. The FE's sbAppend chains during IR emission scale O(n²)
  because `emit a + b` allocates a fresh concat per call and the shadow
  stack accumulates roots without collection mid-function. Tier-2 GC
  arena epochs (v20 plan) would fix this naturally; until then,
  rebuilding x64.k requires ≥48 GB free RAM headroom on this machine.

## Other open at end of session

- L's `arm64_codegen_drop.md` describes a layout-sensitive elf_host bug
  with a "grow guards" workaround. Likely wants the same deep-codegen
  bisection treatment the FE crash got. Coordinate with L tomorrow.

— W
