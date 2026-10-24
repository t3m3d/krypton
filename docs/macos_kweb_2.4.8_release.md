# Krypton 2.4.8 - macOS arm64

This macOS patch release fixes kweb FTP deployment on servers that limit rapid
reconnections. The CLI and GUI upload files in batches of ten through reusable
curl connections, with connection timeouts and retries. Empty remote folder
still means the FTP account root; kweb never adds `public_html`.

The Learn lessons and published examples now use `print(...)`. The compiler
continues to accept `kp(...)` as a legacy alias. ThePeopleWire placements were
removed from the site.

## Editor extension

`krypton-language-2.4.8.vsix` adds highlighting and snippets for `.k`, `.ks`,
and `.htk`, plus `kls` diagnostics, outline, and completion. It includes a
macOS arm64 `kls` binary; Windows and Linux use an installed `kls`. Install
the VSIX directly in brain Code Editor, VS Code, or Google Antigravity.

## Verification

- Native compiler self-host fixpoint: byte-identical.
- macOS suite: 71 passed, 0 failed, 8 platform skips.
- Objective-K runtime and OKUI checks passed.
- All 34 tutorial sources compiled.
- Extension client tests: 11 passed, 1 skipped; VSIX archive validated.
- macOS package and tarball report `kcc version 2.4.8`.
- Apple accepted installer and kweb app notarization. Installer and tarball app
  carry stapled tickets and pass Gatekeeper as Notarized Developer ID software.

Linux x86_64 remains at 2.4.4 and Windows x86_64 at 2.3.0 until their matching
artifacts are built and tested.
