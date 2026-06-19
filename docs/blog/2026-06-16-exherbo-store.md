# Exherbo Linux on the Microsoft Store

**2026-06-16**

Exherbo Linux is now a one-click install on the Microsoft Store as a
WSL2 distribution. Search "Exherbo Linux WSL" or grab it directly:
https://apps.microsoft.com/detail/<STORE-URL>

This is the first of four planned WSL distributions I'm shipping
to the Store. Exherbo went first because it's small, has a loyal
user base, and had no existing Store presence. Three more in the
pipeline behind it: Chimera Linux (musl + LLVM + dinit), Gentoo,
and a polished Fedora release that picks up where the existing
Fedora Remix leaves off.

## What's inside

The MSIX wraps Microsoft's official WSL-DistroLauncher template
(MIT licensed) with the upstream Exherbo `-current.tar.xz` stage
pulled from `stages.exherbo.org` and sha256-verified at build time
via the `.sha256sum` sibling URL. Nothing third-party in the rootfs.

The launcher does the standard WSL OOBE - creates a wheel-group
user, runs `passwd` interactively, drops you into bash. /etc/wsl.conf
ships hardened: `noexec` on /mnt/c (so a Windows .exe in /mnt/c can't
be accidentally executed from Linux), `appendWindowsPath=false` so
the Linux PATH stays clean.

After install, `cave sync` and you're running source-based Exherbo
on Windows.

## Build pipeline

Three scripts and a thin C++ launcher:

- `fetch-rootfs.ps1`: pulls the upstream stage, sha-verifies it.
- `build-msix.ps1`: auto-locates msbuild across all VS 2022 editions
  (BuildTools / Community / Professional / Enterprise), packs the
  MSIX via MakeAppx and signs via signtool. Doesn't need the UWP
  workload, so VS Build Tools alone is enough.
- `make-cert.ps1`: generates the self-signed dev cert for sideload
  testing.

The full source is at https://github.com/t3m3d/exherbo-wsl-store
(MIT). Same pattern's used for the three sibling distros — each
swaps the rootfs URL, the OOBE specifics (cave for Exherbo, emerge
for Gentoo, apk for Chimera, dnf for Fedora), and the launcher
identity.

## Privacy

No telemetry, no analytics, ever. https://krypton-lang.org/exherbo-privacy.html

## If you don't want a Store account

The same distro is also available via a PowerShell installer:
https://github.com/t3m3d/exherbo-wsl2-installer
