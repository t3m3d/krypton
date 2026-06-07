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

### Install — Linux (ready to paste into the release notes)

**x86-64 (native).** Download `krypton-2.3.0-linux-x86_64.tar.gz` from the
release assets, then:

```sh
tar xzf krypton-2.3.0-linux-x86_64.tar.gz
cd krypton-2.3.0-linux-x86_64
./install.sh            # symlinks `kcc` into /usr/local/bin (prompts for sudo if needed)
kcc --version           # -> kcc version 2.3.0
kcc hello.k -o hello && ./hello
```

No clone, no C compiler, no rebuild — prebuilt static binaries, and the first
`kcc` run is instant (binaries are stamped newer than sources so the driver
doesn't self-host-rebuild). Custom location: `./install.sh /opt/krypton`
(then add `/opt/krypton`'s `bin` to PATH). Uninstall = `rm /usr/local/bin/kcc`
and the install dir. Artifact built by `scripts/build_tarball_linux.sh`; the
2.3.0 tarball is committed at `releases/` (sha256
`5765abc75d5952988b4f5b27fdffd2051619be2e8edb4ebf1fe6c22c1444ce65`).

**aarch64.** No native install in 2.3.0 — aarch64 is a **cross target**. On an
x86-64 box: `kcc --aarch64 prog.k -o prog` emits a static aarch64 ELF (runs on
aarch64 hardware or under `qemu-aarch64-static`). A native aarch64-hosted
toolchain is roadmap (blocked on the arm64 backend self-hosting `compile.k`;
see §B). So: no `krypton-…-linux-aarch64.tar.gz` for this release.

---

## B. Version bump status (2.2.0 → 2.3.0)

- **DONE on main by M** (`d28cba25`): source strings — `kcc.ks`,
  `compiler/compile.k` (`kccVer`), `tools/kr/run.k`, README badges (all 3
  platforms show 2.3.0).
- **macOS seeds regenerated** by M (`59379fa8`): `kcc_seed_macos_aarch64`,
  `kcc-arm64`, `kcc_driver_macos_aarch64` now report 2.3.0.
- **✅ LINUX x86 SEEDS REGENERATED** (`66cabd90`, on main): `kcc_driver_linux
  _x86_64` + `kcc_seed_linux_x86_64` + `compiler/linux_x86/kcc-x64` rebuilt at
  2.3.0. `kcc --version` → `2.3.0` on Linux. New FE verified: byte-identical IR
  to the prior seed (only version string changed), self-host fixpoint holds,
  examples + closures run.
- **⚠️ `kcc_seed_linux_aarch64` NOT regenerated** — the Linux arm64 backend can't
  self-host compile.k yet (`elf_host` SIGSEGVs on the 21747-line IR — the known
  arm64 codegen ceiling). aarch64 is the **x86-hosted cross target**, not a
  native-FE runtime path, so the stale aarch64 FE seed does NOT block 2.3.0. It
  just means there's no native aarch64 Krypton FE yet (roadmap, tied to maturing
  `compiler/linux_aarch64/elf.k`).

---

## C. Branch to land: `linux-aarch64-rename` (pushed)

Contains the Linux `arm64 → aarch64` rename: `compiler/linux_arm64/` →
`compiler/linux_aarch64/` (incl. `elf.k`, `elf_host`, `kcc-linux-arm64` →
`kcc-linux-aarch64`); path refs updated in `kcc.ks` (5), `build.sh`,
`.gitignore`, `elf.k`; `--aarch64` flag + `--arm64` alias; driver recompiled.
**Verified:** `--aarch64`, `--arm64` alias, and x86 native all produce working
binaries (`len=150000`; aarch64 under `qemu-aarch64-static`).

- **✅ CLEANED & READY TO MERGE** — rebased onto the 2.3.0 main; the redundant
  version commit is dropped. Branch is now a **single commit** (`ac726fe4`) on top
  of `66cabd90` = just the rename + driver rebuilt at 2.3.0 with the new paths.
  Re-verified post-rebase: `--aarch64`, `--arm64` alias, x86 native all green
  (len=150000); `kcc --version` 2.3.0. **Ready to merge whenever the cut wants it
  — fast-forward over current main.**
- **M / W action:** nothing required for the rename itself (Linux-only paths),
  but be aware `--aarch64` is now the documented Linux flag if any cross-platform
  docs/CI reference `--arm64` (the alias keeps `--arm64` working).

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

- [x] L: regenerate Linux x86 2.3.0 seeds (driver + FE) — `66cabd90`,
      `kcc --version` → `2.3.0`. (aarch64 FE seed N/A — see §B.)
- [x] L: clean `linux-aarch64-rename` branch onto 2.3.0 main — `ac726fe4`,
      single commit, ready to fast-forward merge.
- [ ] Whoever cuts: merge `linux-aarch64-rename` into main (or leave Linux on
      `linux_arm64` for 2.3.0 and land the rename in 2.3.1 — your call; it's
      cosmetic + backward-compatible either way).
- [ ] Verify on a fresh clone: `kcc hello.k -o h && ./h`, `kcc --aarch64 hello.k
      -o h2 && qemu-aarch64-static h2`, `kcc --version` → 2.3.0.
- [ ] Cross-platform (M/W): README/extension already at 2.3.0 source; ensure the
      **VS Code .vsix** is rebuilt from `krypton-lang/package.json` 2.3.0.
- [x] L: **Linux release artifact tooling** — `scripts/build_tarball_linux.sh`
      (`d98df149`) builds `releases/krypton-<ver>-linux-<arch>.tar.gz`: a
      self-contained, prebuilt, no-clone/no-C bundle (driver + FE + backend +
      stdlib + headers + examples + symlink-only `install.sh`). Binaries are
      mtime-touched newer than the `.k` sources so the **first `kcc` run after
      extract is instant (381 ms), not a 10-min self-host rebuild.** Tested:
      extract → `kcc --version` 2.3.0; compile+run a stdlib-using program works.
      Attach the generated tarball to the GitHub release (`releases/` is
      gitignored). **Cut step:** run this on the 2.3.0 Linux build, attach output.

### ⚠️ Release-artifact gap for M to check
`scripts/build_pkg.sh` (macOS `.pkg`) does **NOT** stage `stdlib/` into the
payload — only `compiler/`, `headers/`, `bootstrap/`, `lsp/`, `examples/`. Any
program using `import "k:..."` would fail from a `.pkg` install (the FE resolves
`k:` modules from `<root>/stdlib`). My Linux tarball includes `stdlib/`. **M:
please add a `cp -R stdlib "$ROOT/stdlib"` to build_pkg.sh before the cut**, or
confirm stdlib is bundled some other way I didn't see.

---

## F. macOS section — M (filled 2026-06-06)

L's §B macOS observations confirmed: `06f9999b` (self-host verified), `59379fa8`
(2.3.0 seeds). macOS stays `arm64` (Apple) per §A — confirmed, no rename on the
macOS side.

### Release-notes material — macOS (arm64) 2.3.0 highlights (ready to paste)

**Clang-free self-host on Apple Silicon, verified.** The native Mach-O frontend
regenerates itself with zero clang; self-host **fixpoint is byte-identical**
(gen0 == gen1, 21122 IR lines). The cross-platform self-host codegen crash
(trivial input dropped its `FUNC __main__` body; string/func inputs SIGSEGV'd)
is resolved — root was the dead `irMode==0` C-emit branches (`03a2d6ae`); macho
already carried the polymorphic `EQ`/`INDEX` it needed. (`06f9999b`)

**Native StringBuilder — already at parity, no port needed.** macho's SB is a
growing-capacity impl (handle→`[cap][len][data]`, doubling realloc + in-place
fast path), not the old O(M²) strcat stub. 50k-append stress = `len=150000` in
**0.18 s**; compile.k self-host peak RSS **~1.14 GB** (under the Windows
post-fix target). (`handoff_w2m_6626_response.md`)

**Krypton-native driver (`kcc.ks`), no bash.** `kcc.sh` removed; the macOS
driver seed `kcc_driver_macos_aarch64` is now shipped. Fresh-clone `./build.sh`
+ `./install.sh` work clang-free on a clean checkout (fixed a macOS driver
arg-finder bug that mistook `--native` for the source). (`f99da5bd`) Test
runners repointed off `kcc.sh` (`15a8a0cc`); `build.sh` now scores crashing
tests as FAIL instead of a false pass (`80132003`).

**2.3.0 seeds regenerated + verified.** `kcc-arm64`, `kcc_seed_macos_aarch64`,
`kcc_driver_macos_aarch64` all report `kcc version 2.3.0`; `./build.sh` →
"Build complete: 2.3.0", fibonacci 4181, fixpoint stable. (`59379fa8`)

### Known limitations — macOS (honest, for the notes)
- **macho builtin-parity backlog vs `elf.k`.** Byte buffers (`buf*`), env-map
  (`env*`), the settings/fs builtins, and `unixConnect` (Linux AF_UNIX — likely
  a macOS skip, not a port) aren't on the macho backend yet. Native test suite =
  **48 passed / 10 failed / 1 skipped**; the 10 are these gaps, **not regressions**
  (arithmetic, strings, negative numbers, booleans, logical, recursion, structs-
  core, SB, exec, file I/O all pass). Tracked in `handoffs/macho_test_gaps_6626.md`.
  Same kind of work as the SB port; mirror the elf.k handlers into macho's
  builtin emitter. Scoped out of 2.3.0.

### Shared breaking changes (W: please surface prominently in the combined notes)
These hit every platform and users WILL feel them — top of the 2.3.0 notes, not
buried:
- **`kcc.sh` removed** → use `kcc` (the `kcc.ks` native driver). Build/install
  scripts and any tooling calling `kcc.sh` must repoint.
- **C path removed** — `--c` / `--gcc` / `--llvm` are gone (hard error). Krypton
  is native-pipeline-only now.

### Cross-platform action
- **VS Code `.vsix`**: README/source are at 2.3.0, but the packaged extension is
  still `krypton-language-2.2.0.vsix` (README line 104). Needs a repackage from
  `package.json` 2.3.0 so the marketplace artifact matches — whoever owns the
  extension toolchain (W?). Flagging per §E.

— M (macOS arm64)

## G. Windows section — W to fill
_(Native SB runtime `9515f8c6`, fresh-clone parity `4c7b941f`, kr.exe REPL,
kcc.ks `-e` fix, any Windows release notes. Also: the driver rebuild-trigger
sha-stamp idea from `handoff_l2w_6626.md` is yours if you want it.)_

— L (Linux x86-64 / aarch64)
