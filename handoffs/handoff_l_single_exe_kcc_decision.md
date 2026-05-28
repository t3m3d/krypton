# Decision (l): shipping kcc as a single executable on Linux

**From:** agent l (Linux)
**Date:** 2026-05-28
**Question:** what's needed for `kcc` to install + run as one self-contained executable.

## Current state

`kcc` today is NOT single-file. It is the driver (`bootstrap/kcc_driver_linux_x86_64`)
PLUS:
- sidecar host binaries it **shells out** to at compile time (`compile.k:3779` →
  `optimize_host`, `elf_host`) via **temp files** (`/tmp/tmp_kcc_build.ir`);
- **`KRYPTON_ROOT`** (`compile.k:2967`) to locate the `bin/` hosts, `headers/`, and
  to resolve `import` statements (`3147` reads stdlib `.k` from disk).

(Compiled Krypton *programs* are already single static C-free ELFs — `cp` and run.
This is only about the compiler itself.)

## Two architectures

**A) True monolith** — unify FE + optimize + ELF codegen into ONE Krypton source,
pipe IR in memory (no shellRun, no temp files), self-locate (drop KRYPTON_ROOT),
embed stdlib for `import`. Compile → one static ELF `kcc`. Cleanest end state.

**B) Self-extracting single file** — keep the existing (working) host binaries +
stdlib, bundle them as a payload APPENDED to a tiny pure-Krypton launcher; on run,
the launcher reads /proc/self/exe, extracts the payload to a cache dir, points the
driver at it, `shellRun`s it. One file; works without recompiling anything.

## The blocker for A (measured)

The unified source is **580 KB** (compile.k 160 + optimize.k 11 + elf.k 409) →
~830 KB+ IR. The backend (no GC, bump allocator) dies at ~1.9 GB / the 0x7F000000
(2^31) int-range ceiling once total compile-time allocation crosses it. Reference:
kryofetch's 413 KB source / 836 KB IR ALREADY fails there (handoff_l_kryofetch_needs_gc.md).
A 580 KB unified source is bigger → **A cannot self-compile until the GC port lands.**

So A and kryofetch share ONE root blocker: the Linux GC port
(handoff_m2l_gc_full_port_plan.md). GC reclaims transients → peak-live stays in the
MBs → the ceiling is never hit → both A and kryofetch build.

## DECISION

**Primary: GC port → then A (true monolith).** Rationale: the GC port is already the
planned next task and is independently needed for kryofetch and any large program;
it's the single root fix; A is the correct long-term artifact. One investment clears
the whole class (kryofetch + single-exe kcc + large Krypton programs).

Post-GC plan for A:
1. Concatenate FE + optimize + elf into one source (resolve fn-name collisions; one
   entry; IR flows in memory). [the native backend can't link transitive module
   imports, so concatenate rather than `import`.]
2. Self-locate via /proc/self/exe; remove the KRYPTON_ROOT requirement.
3. Embed the `import`-able stdlib `.k` as baked-in strings (offline imports).
4. `kcc --native` the unified source → one static ELF; wire `kcc -r` to compile +
   run in-process.

**Fallback if a single-file kcc is wanted BEFORE the GC port: B (self-extracting).**
Pure-Krypton launcher (payload appended post-compile) keeps the no-bash/no-C ethos.
Works today; the cost is extract-to-cache on first run + a self-reading-binary stub.

## Recommendation

Do the GC port next (unblocks kryofetch AND single-exe kcc), then ship A. Use B only
if a single-file kcc is needed immediately.
