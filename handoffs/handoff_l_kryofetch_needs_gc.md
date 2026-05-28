# Note (l): kryofetch distro-art is a concrete motivator for the Linux GC port

**From:** agent l (Linux)
**Date:** 2026-05-28
**Re:** handoff_m2l_gc_full_port_plan.md (GC port to Linux ELF)

Recording a real program that the linux_x86 ELF backend currently **cannot compile**,
as a test case / motivator for the staged GC port.

## The program

kryofetch `run_linux.k` (a large WIP: ~4791 lines of neofetch-derived distro ASCII
art, distroArt_0..22 + Tux). The FE handles it fine: 836 KB IR, ~88K instructions.
optimize_host barely shrinks it (88090 → 87785). But:

`compiler/linux_x86/elf_host <opt.ir> out` → **SIGSEGV** (no output binary).

## Failure mode (measured)

- Peak RSS at fault ≈ **1936 MB** with a **3.75 GB** heap available → NOT heap
  exhaustion. (Earlier with the stock 1.875 GB heap it faulted at the cap; I bumped
  the heap to 1.875→3.75 GB and the fault simply moved to ~1.9 GB — then reverted the
  bump as useless.)
- The fault is at the backend's fundamental **0x7F000000 / 2^31 int-range ceiling**:
  the bump allocator never frees, so the SUM of all transient string allocations over
  the compile (sbToString copies, concats, per-op builders) crosses ~2 GB and some
  internal size/offset/pointer computation overflows the int/pointer threshold.

## Why GC fixes it

With the conservative GC reclaiming transients, peak-LIVE stays in the MBs (it's a ~2 MB
output binary) instead of accumulating ~2 GB of dead allocations. Live memory never
approaches 2^31, so the overflow never triggers and kryofetch builds. This is the
clean fix — heap-size tuning is a dead end (capped by the 0x7F000000 int ceiling, and
the fault is below the cap anyway).

## Disposition

Per Brian (2026-05-28): **leave kryofetch run_linux.k as uncommitted WIP**; do NOT trim
the distro set or refactor the art storage. The GC port (your staged plan) is the agreed
next task; use kryofetch as the large-program acceptance test. No toolchain changes were
committed for this (heap-bump experiment reverted; backend left pristine).
