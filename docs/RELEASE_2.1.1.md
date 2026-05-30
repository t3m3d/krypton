# Release 2.1.1 — what to ship on each platform

**Status:** macOS arm64 = shipped + Homebrew. Linux / Windows = source ready,
binary not yet built. This doc is the recipe for cutting the remaining
platform binaries + bumping the package managers.

The 2.1.1 source contains four cross-platform bug fixes (Bugs 1, 1b, 2,
7) plus the 2.1.1-pre macOS self-host work. All fixes are in
`compiler/compile.k` and are platform-agnostic; each platform just needs
its own `kcc-<arch>` binary rebuilt from this source.

---

## What's bundled in every 2.1.1 release

All platforms ship the same tarball/installer layout:

```
<root>/
├── kcc.sh                       # wrapper; exports KRYPTON_ROOT
├── kcc                          # dispatcher; routes to compiler/<arch>/kcc-<arch>
├── compiler/
│   └── macos_arm64/kcc-arm64    # platform binary (or linux_x86, etc.)
│   └── macos_arm64/macho_host   # backend binary (Mac only)
├── headers/                     # *.krh C-binding headers
├── stdlib/                      # 57 Krypton modules (htmk, kcss, server, fp, …)
├── bootstrap/                   # one-time bootstrap C seeds
├── web/
│   └── kweb                     # web framework CLI (2.1.1 new; symlink to bin/kweb)
└── (platform install adds bin/ symlinks for kcc, krypton, kweb)
```

Three CLIs land in `bin/` on every platform: `kcc`, `krypton`, `kweb`.

---

## macOS arm64 — DONE

Shipped via Homebrew tap: `t3m3d/krypton`.

- Formula: `homebrew-krypton/Formula/krypton.rb` (now `version "2.1.1"`).
- Tarball URL: `https://github.com/t3m3d/krypton/releases/download/2.1.1/krypton-2.1.1-macos-arm64.tar.gz`.
- SHA256: **still placeholder `REPLACE_WITH_REAL_SHA_AFTER_TARBALL_BUILD`** — fill in after
  building the tarball. Compute with `shasum -a 256 krypton-2.1.1-macos-arm64.tar.gz`.

### Build the macOS tarball

```bash
cd /Users/.../GitHub/krypton

# 1. Rebuild kcc-arm64 from current source (uses the existing 2.0.0
#    bootstrap to compile compile.k).
kcc --c compiler/compile.k > /tmp/kcc_new.c
clang /tmp/kcc_new.c -o compiler/macos_arm64/kcc-arm64 -w
codesign -s - -f compiler/macos_arm64/kcc-arm64   # AMFI ad-hoc signature

# 2. Rebuild kweb from web/kweb.htk (using newly-built kcc).
KRYPTON_ROOT="$(pwd)" ./compiler/macos_arm64/kcc-arm64 web/kweb.htk > /tmp/kweb.c
clang /tmp/kweb.c -o web/kweb -w
codesign -s - -f web/kweb

# 3. Stage the tarball.
mkdir -p /tmp/krypton-2.1.1
cp -r kcc.sh kcc compiler headers stdlib bootstrap web /tmp/krypton-2.1.1/
# (only ship the macos_arm64 subdir under compiler/ — the linux + windows
# subdirs stay out of the macOS tarball)
rm -rf /tmp/krypton-2.1.1/compiler/linux_x86 /tmp/krypton-2.1.1/compiler/linux_arm64
# kweb is the only thing we actually need from web/; everything else is
# example .htk source for the user.
( cd /tmp && tar czf krypton-2.1.1-macos-arm64.tar.gz krypton-2.1.1/ )

# 4. Compute SHA + bump formula.
shasum -a 256 /tmp/krypton-2.1.1-macos-arm64.tar.gz
# → paste into homebrew-krypton/Formula/krypton.rb
```

### Cut the GitHub release

```bash
gh release create 2.1.1 \
    /tmp/krypton-2.1.1-macos-arm64.tar.gz \
    --title "Krypton 2.1.1 — portability bug-fix series + kweb" \
    --notes-file CHANGELOG-2.1.1-excerpt.md
```

Then push the Homebrew formula bump:

```bash
cd /Users/.../GitHub/homebrew-krypton
git add Formula/krypton.rb
git commit -m "krypton 2.1.1"
git push
```

Users update with `brew upgrade krypton`.

---

## Linux x86_64 — pending

The Linux backend (`compile/linux_x86/elf.k`) was at 1.5.0 parity per
`docs/HANDOFF_LINUX_SELFHOST.md`. Per that doc, the macOS `kcc-arm64`
(now 2.1.1) emits portable C that compiles cleanly with `gcc` on Linux
→ build a 2.1.1 Linux binary by cross-compilation through the C emit
path:

```bash
# On the Mac:
KRYPTON_ROOT=/Users/.../GitHub/krypton ./compiler/macos_arm64/kcc-arm64 \
    compiler/compile.k > /tmp/kcc_portable.c

# Copy /tmp/kcc_portable.c into a Linux env (Docker, lima, QEMU, real box):
gcc /tmp/kcc_portable.c -o kcc-x64 -O2 -lm -w
```

Linux release artifact: `krypton-2.1.1-linux-x86_64.tar.gz` with the
same layout as macOS, but `compiler/linux_x86/kcc-x64` instead of
`compiler/macos_arm64/kcc-arm64`. No code signing needed.

Homebrew on Linux (`linuxbrew`): the same formula extended with
`on_linux do url ... sha256 ...`. Or ship via `.deb`/`.rpm` —
out of scope for 2.1.1.

---

## Windows x86_64 — pending

The Windows installer is **Inno Setup** based:
`installer/krypton-installer.iss` (Windows only file). Bug fixes apply
identically — same `compile.k` source.

### Build kcc.exe

```cmd
:: From the Krypton repo on Windows (or via MinGW on Mac through QEMU)
kcc.exe --c compiler\compile.k > kcc_new.c
gcc kcc_new.c -o kcc.exe -O2 -lm -w
```

(Pre-2.1.1 build path uses the bundled `krypton_rt.dll` for Win32 API
calls — that DLL stays unchanged.)

### Build kweb.exe

```cmd
kcc.exe --c web\kweb.htk > kweb.c
gcc kweb.c -o kweb.exe -lws2_32 -lpsapi -lpdh -w
```

### Bump installer + ship

1. Edit `installer/krypton-installer.iss` — bump `MyAppVersion` to
   `2.1.1`. The .iss file lists which files to include in the installer
   (kcc.exe + kweb.exe + krypton_rt.dll + headers\ + stdlib\ + bootstrap\).
2. Run Inno Setup compiler: `iscc installer/krypton-installer.iss`.
3. Upload the resulting `KryptonSetup-2.1.1.exe` to the GitHub release.
4. (Optional) Update Chocolatey package: bump `krypton.nuspec` version
   + push.

### Cross-verify on Windows

The same bug-fix test cases should pass:

- `kcc --version` → `kcc version 2.1.1`
- `import "k:htmk"` → resolves from the install dir (no `C:\krypton`
  workaround needed — but Windows users actually use that path, so the
  fallback in compile.k preserves it).
- `fromCharCode(8593)` → emits proper UTF-8 (`E2 86 91`).

---

## CHANGELOG cross-reference

The full bug-fix list is in `CHANGELOG.md` under `## [2.1.1] - 2026-05-30`.
The Windows release notes should reference the same bug numbers (1, 1b,
2, 7 fixed; 3, 4, 5, 6 deferred).

---

## Open questions

- **Single tarball for all OSes vs. per-OS tarballs?** Currently per-OS.
  Bundling Linux + Mac + Windows binaries into one tarball would simplify
  release ops but ~triples download size for end users.
- **kweb in 2.1.1 vs 2.1.2?** Currently bundled in 2.1.1 because it's
  ready and shipping `kweb` alongside `kcc` is the framework story. If
  Windows can't get kweb compiled in time, ship Mac+Linux with kweb
  and Windows with `kcc` only as 2.1.1-win-partial; bundle kweb in 2.1.2.
- **Code signing on Mac.** Ad-hoc (`codesign -s -`) works for AMFI but
  Gatekeeper still warns. Apple Developer ID signing is paid + manual;
  defer to 2.2 unless someone reports a workflow blocker.

---

## See also

- `CHANGELOG.md` 2.1.1 section — full bug-fix list
- `compiler/compile.k` — source of the fixes
- `homebrew-krypton/Formula/krypton.rb` — Mac formula
- `installer/krypton-installer.iss` — Windows installer script
- `docs/HANDOFF_LINUX_SELFHOST.md` — Linux backend status pre-2.1.1
