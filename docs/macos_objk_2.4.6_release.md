# macOS Objective-K 2.4.6 Release Candidate

Status: local candidate only. Do not tag or publish yet. Published macOS release
remains 2.4.5.

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

## Release Gates

1. Fix or explicitly waive `test_negative_nums.k`: full macOS suite is 70
   passed, 1 failed, 8 skipped. `(0 - 10) + 3` currently prints `4294967289`
   instead of `-7`; wrapped result also has wrong comparison behavior. Backend
   32-bit ADD protects the self-host signer, so string-only formatting is not
   a complete fix.
2. Investigate five `write: Permission denied` lines from `build_pkg.ks`.
   Expanded payload checks pass, but package creation should be warning-free.
3. Test installer on a clean macOS arm64 machine or disposable volume; current
   checks used extracted payloads, not system installation.
4. Test real FTP deployment with a test account and remote folder; no
   credentials are stored or used by this release prep.
5. Obtain Developer ID signing identity and notarize public app/package, or
   explicitly publish an unsigned/ad-hoc-signed build with macOS Gatekeeper
   limitations stated. `security find-identity` currently finds no valid
   signing identity; the local `.pkg` has no distribution signature.
6. Rebuild final artifacts after any gate fix, record SHA-256, then publish
   GitHub assets. Update Homebrew only after release URLs work.

Objective-K remains experimental and macOS arm64 only in this candidate.
Current declarations require executable entry source, callback-backed methods,
and one declared protocol conformance per object. AppKit remains the GUI backend.
