# macOS Objective-K 2.4.6 Release Candidate

Status: signed and notarized local candidate. Do not tag or publish until the
remaining manual gates pass. Published macOS release remains 2.4.5.

## Verified In This Checkout

- macOS arm64 frontend and driver report 2.4.6. Frontend self-host rebuild is
  byte-identical; compiler, seed, driver, kweb CLI, and kweb app are signed.
- Objective-K core and `--gui` checks pass, including native callbacks,
  protocol/ownership Focus app, declaration syntax, and rejection cases.
- OKUI builds both smoke app and kweb app. kweb app bundle has version 2.4.6,
  glass icon, valid plist, and valid whole-bundle ad-hoc signature.
- Tarball extracted to a clean temporary prefix: `kcc --version`, a `.k`
  Hello World, Objective-K declarations, and top-level `.ks` via `kr` pass.
- kweb CLI creates a project and builds a configured `dist/index.html`.
- `.pkg` expands and contains compiler, `kr`, runtime, and signed kweb app.
  Package installer and tarball installer scripts pass `bash -n`.
- Every shipped Mach-O has a hardened-runtime Developer ID Application
  signature. The installer has a Developer ID Installer signature and trusted
  timestamp. Apple accepted notarization submission
  `53daa137-5c37-45c0-b9e5-b7b457145d23`; the ticket is stapled and validates.
  Gatekeeper reports `source=Notarized Developer ID`. The tarball kweb app is
  covered by the same notarization and passes Gatekeeper.
- Final `.pkg` and tarball contain no AppleDouble `._*` files. Release builders
  exclude the tracked local Objective-K Focus binary.
- Native `ADD` keeps SHA-256's 32-bit wrap for nonnegative operands and uses
  signed addition when either operand is negative. Backend self-host output is
  byte-identical across generations; `codesign -v` passes. Full macOS suite is
  71 passed, 0 failed, 8 skipped, including negative-chain and wrap regressions.
- Tarball installer passed in a disposable `/tmp` prefix: installed `kcc`
  reports 2.4.6, compiles and runs negative-number checks, and installed
  kweb app passes `codesign -v` with the original CDHash. Tarball and `.pkg`
  installers preserve payload signatures instead of replacing them with ad-hoc
  signatures. Both payloads contain backend
  matching the tracked seed; neither contains local untracked example binary.
- `.pkg` postinstall uses Installer target volume for filesystem writes and
  creates boot-correct `/usr/local/krypton` symlinks there. Extracted postinstall
  passes `bash -n`, fails without its target argument, and succeeds against an
  offline `/tmp` target without writing live system paths.
- `pkgbuild` emits four `write: Permission denied` lines even for an empty
  package root, both inside and outside the sandbox. The release build emits
  five. `pkgutil --expand` and payload extraction succeed; this is a known
  host-tool warning, not a payload validation failure.

Current local artifact SHA-256:

- `krypton-2.4.6-macos-arm64.tar.gz`:
  `3c399881abbb5d2f8a05a47bba74cedf195bc91b5e920b4d054d7a861ca1802e`
- `krypton-2.4.6-macos-arm64.pkg`:
  `8ee34ed2492db90887e038286dc730f1abc5f0a19540c45b5f6ed43548fbbadc`

## Release Gates

1. Test `.pkg` through macOS Installer on a clean machine or disposable volume;
   payload expansion, offline postinstall, and tarball installation pass, but
   Installer requires an administrator password unavailable to this run. Test
   image was detached after this check.
2. Test real FTP deployment with a test account and remote folder; no
   credentials are stored or used by this release prep.
3. Rebuild final artifacts after any gate fix, record SHA-256, then publish
   GitHub assets. Update Homebrew only after release URLs work.

Objective-K remains experimental and macOS arm64 only in this candidate.
Current declarations require executable entry source, callback-backed methods,
and one declared protocol conformance per object. AppKit remains the GUI backend.
