# macOS kweb 2.4.7 Release

Status: signed, notarized, installed, and ready to publish.

## Fix

- Fixed the macOS kweb GUI Deploy action crashing before FTP started.
- Added the missing Krypton path-separator helper used by remote-folder
  normalization.
- Rebuilt the macOS arm64 compiler, native driver, kweb CLI, and kweb app as
  version 2.4.7.

## Verification

- Compiler self-host fixpoint is byte-identical.
- Full macOS suite: 71 passed, 0 failed, 8 platform skips.
- Objective-K runtime and OKUI checks pass.
- Package and tarball contain compiler and kweb app version 2.4.7.
- Package and tarball kweb apps pass strict code-signature verification.
- Package and tarball contain no AppleDouble files.
- Apple notarization accepted submission
  `46e21a85-356b-4f65-966c-159a679395cf`.
- Stapled installer and tarball kweb app pass Gatekeeper as Notarized
  Developer ID software.

## Final SHA-256

- `krypton-2.4.7-macos-arm64.pkg`:
  `9c706ec9535e19c7afa82bab6c9cb1877a634d07445261c8e7bf0126c4dc5d38`
- `krypton-2.4.7-macos-arm64.tar.gz`:
  `404fc4c659f68f5b3dce65466d84ffa7988b936a0d34bc19795053a562faa124`

## Installation Test

- Installer receipt reports 2.4.7.
- `/usr/local/bin/kcc --version` reports 2.4.7.
- Installed kweb app reports 2.4.7 and passes Gatekeeper.
- Installed kweb Deploy reached FTP handling, reported a local connection
  failure cleanly, and remained running instead of crashing.
