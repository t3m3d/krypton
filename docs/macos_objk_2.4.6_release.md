# macOS Objective-K 2.4.6 Release Candidate

Status: signed, notarized, installed, and ready to publish. Published macOS
release remains 2.4.5 until the GitHub assets are uploaded.

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
  timestamp. Apple accepted final notarization submission
  `33fa8ea8-b627-48be-b563-02a5d36077e8`; the ticket is stapled and validates.
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
- Installer.app completed on the release host. The package receipt reports
  2.4.6 and installed `/usr/local/bin/kcc` reports `kcc version 2.4.6`. Existing
  Homebrew 2.4.5 was unlinked because `/opt/homebrew/bin` had PATH priority.
- The final kweb GUI deployed `index.html`, `about.html`, and `.htaccess` by FTP
  to `kweb-test`. `https://krypton-lang.org/kweb-test/` returns HTTP 200.
- `pkgbuild` emits four `write: Permission denied` lines even for an empty
  package root, both inside and outside the sandbox. The release build emits
  five. `pkgutil --expand` and payload extraction succeed; this is a known
  host-tool warning, not a payload validation failure.

Current local artifact SHA-256:

- `krypton-2.4.6-macos-arm64.tar.gz`:
  `b784108e70bace923a4c5c4de06aae560db399ee0cb1ccd294b0e4b066e2a06a`
- `krypton-2.4.6-macos-arm64.pkg`:
  `1f8e9ce84e38fed57dbdc46214adf92e5aa79b91ecfb107c28b9305f66b3468a`

## Release Gates

All local release gates passed. Publish GitHub assets, verify their URLs, then
update Homebrew with the final tarball SHA-256.

Objective-K remains experimental and macOS arm64 only in this candidate.
Current declarations require executable entry source, callback-backed methods,
and one declared protocol conformance per object. AppKit remains the GUI backend.
