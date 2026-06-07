# Handoff L→M→W — Krypton 2.3.0 release input (Linux section) — 2026-06-06

**Routing: this doc flows L → M → W before the release ships.** I (agent **L**,
Linux x86-64 + aarch64) wrote the Linux section + release-notes material below.
**M:** read, confirm/expand the macOS section, append yours, pass to W. **W:**
same for Windows, then assemble the final release notes + cut tags.

---

## A. Release-notes material — Linux 2.3.0 highlights (ready to paste)

**Linux native backend reaches runtime/language parity** with macOS & Windows.
Five backend fixes this session (`compiler/linux_x86/elf.k`), all on `main`:

- **First-class functions / closures** — `FUNCPTR` + `callPtr` implemented, so
  lambdas and the `k:fp` pipeline (`fpMap`/`fpFilter`/`fpReduce`) run natively.
  (`84b8a574`)
- **Int-argument builtins** — `padLeft`/`padRight`/`sbAppend` now stringify an
  int arg instead of dereferencing it as a pointer (no more segfault).
  (`2cd167c9`, `ae7535ec`)
- **Library files + GC diagnostics** — a source file with no `just run` exits
  cleanly instead of SIGSEGV; `gcCollect`/`gcAllocCount`/… stubbed with correct
  stack effect. (`fd736817`)
- **Example suite: 77 → ~87 of 118 running** on native Linux. Remaining failures
  are platform-specific GUI (see §D) — not backend bugs.

**StringBuilder parity confirmed** (handoff `handoff_l2w_6626.md`): 50k-append
stress = `len=150000` in **3 ms (x86) / 10 ms (aarch64 via qemu)**; compile.k
self-host peak RSS **42 MB**. Both Linux backends already ship the doubling-
realloc SB — no port was needed.

**Naming standardized: Linux = `aarch64`** (matches `uname -m`, GNU triplet,
ELF `EM_AARCH64`, qemu); **macOS stays `arm64`** (Apple). New `--aarch64`
cross-compile flag with `--arm64` kept as an alias. (Branch — see §C.)

---

## B. Version bump status (2.2.0 → 2.3.0)

- **DONE on main by M** (`d28cba25`): source strings — `kcc.ks`,
  `compiler/compile.k` (`kccVer`), `tools/kr/run.k`, README badges (all 3
  platforms show 2.3.0).
- **macOS seeds regenerated** by M (`59379fa8`): `kcc_seed_macos_aarch64`,
  `kcc-arm64`, `kcc_driver_macos_aarch64` now report 2.3.0.
- **⚠️ LINUX SEEDS NOT YET REGENERATED** — `bootstrap/kcc_driver_linux_x86_64`,
  `kcc_seed_linux_x86_64`, `kcc_seed_linux_aarch64` on `main` are still built
  from pre-bump source, so they **still report 2.2.0**. **L owns this** — I will
  regenerate the Linux driver + FE seeds at 2.3.0 (and fold it into the branch in
  §C). Tracking item; do not cut the Linux release until `kcc --version` →
  `2.3.0` from the committed Linux seed.

---

## C. Branch to land: `linux-aarch64-rename` (pushed)

Contains the Linux `arm64 → aarch64` rename: `compiler/linux_arm64/` →
`compiler/linux_aarch64/` (incl. `elf.k`, `elf_host`, `kcc-linux-arm64` →
`kcc-linux-aarch64`); path refs updated in `kcc.ks` (5), `build.sh`,
`.gitignore`, `elf.k`; `--aarch64` flag + `--arm64` alias; driver recompiled.
**Verified:** `--aarch64`, `--arm64` alias, and x86 native all produce working
binaries (`len=150000`; aarch64 under `qemu-aarch64-static`).

- It also carries a now-**redundant** version-bump commit (`81aef423`) — main
  already has the source bump (§B). **L will rebase the branch onto current main**
  (drops the dup) **+ regenerate the Linux 2.3.0 seeds**, then it's a clean merge =
  rename + Linux seeds. macOS `arm64` and historical docs untouched.
- **M / W action:** nothing required for the rename itself (Linux-only paths),
  but be aware `--aarch64` is now the documented Linux flag if any cross-platform
  docs/CI reference `--arm64`.

---

## D. Known Linux limitations to reflect in the release notes (honest)

1. **No Linux GUI backend yet.** `gui_*` / `win_*` examples render via Win32
   (Windows) / Cocoa (macOS); Linux has only `stdlib/x11.k` at Phase A2 (socket
   handshake — no CreateWindow/event-loop/drawing). ~28 examples are therefore
   Windows/macOS-only for now. **Roadmap item**, scoped out of 2.3.0 by the owner.
   Suggested note wording: *"GUI apps are supported on Windows (Win32) and macOS
   (Cocoa); a native Linux GUI backend (X11) is in progress."*
2. **`splitBy` unreliable on the native backend** (`LINUX_RELEASE_TODO`) — blocks
   `import_demo` / `word_frequency` (the map/JSON stdlib layer). `split(s, idx)`
   works; the list-returning `splitBy` does not. Separate workstream.
3. **Driver rebuild quirk** (cosmetic): `kcc -e`/`-r` triggers a ~10-min
   elf_host self-host rebuild whenever `elf.k` is mtime-newer than the binary —
   and `git pull` restamps mtimes, so the first call after a sync looks like a
   hang. Suggested fix (content-sha stamp) noted in `handoff_l2w_6626.md`.

---

## E. Pre-release checklist (Linux portion)

- [ ] L: rebase `linux-aarch64-rename` onto main + regenerate Linux 2.3.0 seeds
      (driver + FE x86 + FE aarch64); confirm `kcc --version` → `2.3.0`.
- [ ] L: merge the branch (or hand the PR to whoever cuts).
- [ ] Verify on a fresh clone: `kcc hello.k -o h && ./h`, `kcc --aarch64 hello.k
      -o h2 && qemu-aarch64-static h2`, `kcc --version`.
- [ ] Cross-platform (M/W): README/extension already at 2.3.0 source; ensure the
      **VS Code .vsix** is rebuilt from `krypton-lang/package.json` 2.3.0.

---

## F. macOS section — M to fill
_(Mach-O self-host fix, SB status, seeds regenerated to 2.3.0, any macOS-specific
release notes. I observed `06f9999b` (self-host verified) + `59379fa8` (seeds) —
please confirm/expand.)_

## G. Windows section — W to fill
_(Native SB runtime `9515f8c6`, fresh-clone parity `4c7b941f`, kr.exe REPL,
kcc.ks `-e` fix, any Windows release notes. Also: the driver rebuild-trigger
sha-stamp idea from `handoff_l2w_6626.md` is yours if you want it.)_

— L (Linux x86-64 / aarch64)
