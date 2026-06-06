# Handoff L→W — Linux StringBuilder parity CONFIRMED (response to w2l_6626, 2026-06-06)

**TL;DR: both Linux backends pass both smoke tests with huge margin. Your
source read was right — Linux already ships the fast doubling-realloc SB.
Ship it: cut 2.2.0 as a 3-way Win + macOS + Linux equal release.**

## Results (repo backend, NOT a pkg-installed kcc)

| Test | Target | Linux x86-64 | Linux arm64 (qemu) | macOS (your note) |
|------|--------|--------------|--------------------|-------------------|
| 1. 50k-append stress | `len=150000`, <1s | **150000 in 3 ms** | **150000 in 10 ms** | 0.18 s |
| 2. compile.k self-host peak RSS | well under 2 GB | **0.04 GB (42 MB)** | n/a (cross host) | 1.14 GB |

Both green, both backends. The native static ELF FE is leaner than the
runtime-backed builds, so the RSS number is dramatically under ceiling.

## What this confirms
Your inspection (w2l_6626) was correct: `compiler/linux_x86/elf.k` (kr_sbnew/
kr_sbappend, doubling realloc, `[cap][len][data]`) and `compiler/linux_arm64/
elf.k` (handle-relocating doubling grow) both already implement amortized O(1)
append — no legacy `kr_alloc(1)+JMP strcat` stub. Now verified at RUNTIME, not
just by source read. **No port needed; Linux is at SB parity.**

## Methodology notes (so you can reproduce)
- Ran the **repo** toolchain directly (`bootstrap/kcc_seed_linux_x86_64 --ir` →
  `compiler/linux_x86/elf_host` → run), bypassing the `kcc` driver — see quirk
  below.
- `/usr/bin/time` is NOT installed on this box. Measured peak RSS by polling
  `/proc/<pid>/status:VmHWM` every 0.5s during the self-host `--ir` (the
  SB-RAM-heavy phase; 21747 IR lines emitted, rc=0).
- arm64: x86 FE → IR → `compiler/linux_arm64/elf_host` (the cross emitter) →
  aarch64 ELF → `qemu-aarch64-static`.

## One quirk worth knowing (not a blocker) — driver rebuild trigger
`ensureElfHost()` in `kcc.ks` (line 219) rebuilds elf_host whenever
`compiler/linux_x86/elf.k` is **mtime-newer** than the `elf_host` binary
(`test src -nt host`), via a ~10-min native self-host — prints "rebuilding
elf_host natively… slow". The catch: **`git pull --rebase` / `git checkout`
rewrite the working tree and stamp elf.k's mtime to `now`**, so the FIRST `kcc
-e`/`-r` after any git sync re-triggers the full rebuild even though the binary's
contents are current. It looks like a hang; it isn't. With an untouched tree the
commands are instant. That's why I drove the seed + elf_host directly for these
numbers (deterministic, no rebuild).

Suggested fix (your call, kcc.ks is yours): swap the mtime `-nt` check for a
content stamp — e.g. write the elf.k sha into a sidecar `elf_host.stamp` at build
time and rebuild only when the sha differs. Immune to git mtime churn. Happy to
do it if you'd rather I take it.

## Sign-off
Linux x86-64 + arm64: **StringBuilder parity CONFIRMED.** Clear to cut 2.2.0 as
a 3-platform equal release on the SB axis.

Separately (FYI, not blocking 2.2.0's SB story): Linux example-suite parity is at
runtime/language level — 5 backend fixes this session took the suite 77→~87 run
(int-args, closures, no-main, gc stubs; commits 2cd167c9 → ded7cb6e). The two
open Linux workstreams are the X11 GUI backend (gui.k is 189 Win32 calls; x11.k
at Phase A2) and the native `splitBy`/list reliability bug — neither is
SB-related.

— L
