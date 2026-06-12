# Handoff M → L (Linux) + W (Windows): finish the krypton 2.4.0 release

**Date:** 2026-06-12
**From:** Agent M (macOS)
**Release:** https://github.com/t3m3d/krypton/releases/tag/2.4.0 (published, macOS assets only)

## What's done (macOS)

- `kcc.ks` VERSION → **2.4.0** (commit on `main`).
- macOS bootstrap seeds refreshed from the objk toolchain: `bootstrap/{kcc_driver,kcc_seed,macho_host}_macos_aarch64`.
- Built + verified `krypton-2.4.0-macos-arm64.tar.gz` (sha256 `70fd3f97e7e4b1f41bde915853ea336ab6990a3fddd75c75451b9a3a5189f4a3`) and `.pkg`, uploaded to the 2.4.0 tag. Verified the released `kcc` builds an **objk** app C-free (`examples/objk/term_grid.ks` → Mach-O, links only libobjc/Foundation/AppKit).

2.4.0 = objk (Objective-C FFI: `objc_msgSend*` + `class_addMethod`/`allocateClassPair` in macho backend + `stdlib/cocoa.k`) + native fixes (`exit(int)`, `splitBy`/`repeat`/`hex` unshadowed) + C-free self-host.

## What I need from you

### L (Linux)
1. `git pull` (gets the 2.4.0 version bump). Refresh the Linux seeds if your build needs it.
2. `bash scripts/build_tarball_linux.sh` → `releases/krypton-2.4.0-linux-x86_64.tar.gz`.
3. Upload to the tag: `gh release upload 2.4.0 releases/krypton-2.4.0-linux-x86_64.tar.gz --repo t3m3d/krypton`.
4. Note its sha256.

### W (Windows)
1. `git pull`. Build the Windows release artifact (the `.exe` installer, as in 2.3.0).
2. `gh release upload 2.4.0 krypton-2.4.0-windows-x86_64.exe --repo t3m3d/krypton`.

### Then (either of you) — bump the Homebrew formula
`homebrew-krypton/Formula/krypton.rb` is shared-version with per-OS urls. **I deliberately did NOT bump it** — bumping `version "2.3.0"` → `"2.4.0"` makes the `on_linux` url point at a 2.4.0 file, so it 404s until the Linux tarball exists. Once the Linux tarball is uploaded:
- `version "2.4.0"`
- `on_macos` url → `.../2.4.0/krypton-2.4.0-macos-arm64.tar.gz`, sha256 `70fd3f97e7e4b1f41bde915853ea336ab6990a3fddd75c75451b9a3a5189f4a3`
- `on_linux` url → `.../2.4.0/krypton-2.4.0-linux-x86_64.tar.gz`, sha256 `<from step L.4>`
- test assert `2.3.0` → `2.4.0`

## ⚑ ACTION — bump the formula AFTER your tarballs (ping)

This is the one open item gating a clean 2.4.0. **Sequence, do not reorder:**
1. L uploads `krypton-2.4.0-linux-x86_64.tar.gz` to the tag (step L above).
2. W uploads the Windows asset.
3. **THEN** whoever's last bumps `homebrew-krypton/Formula/krypton.rb` to 2.4.0 (the 4 edits above).

Do **not** bump the formula before the Linux tarball exists — `version "2.4.0"` makes the `on_linux` url resolve to a 2.4.0 file; if it isn't uploaded yet, every `brew install/upgrade krypton` on Linux 404s. macOS is unaffected either way (its 2.4.0 tarball is already on the tag), so there's no rush on the macOS side — the gate is purely the Linux asset.

## Why this matters / downstream
objk is what lets the **stem** terminal ship with **no Obj-C source** (pure-Krypton Cocoa GUI). The released 2.4.0 kcc builds objk apps from source.

The stem cask already ships the prebuilt objk `stem.app` (verified C-free). I also added `build_dmg.ks` to the stem repo — a reproducible cask-DMG builder that uses the **released** kcc. It runs **config-free only once Homebrew `krypton` is ≥ 2.4.0 on PATH** (the brew wrapper then exports an objk-carrying `KRYPTON_ROOT`); until this formula bump lands, stem DMG builds must pass `KRYPTON_ROOT=/path/to/krypton-2.4.0`. So your formula bump is what makes stem's release pipeline fully turnkey.
