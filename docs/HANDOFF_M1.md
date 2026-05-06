# Handoff — M1 MacBook Session

Quick "start here" doc when picking up Krypton work on the M1 MacBook
after a Windows session.

Last updated: 2026-05-06.

---

## State of the world (Windows, current)

Krypton **1.8.0** shipped (installer at `installer/Output/krypton-1.8.0-setup.exe`,
release notes in `releasenotes/RELEASE_NOTES_1.8.0.txt`).

**Post-1.8.0 work in repo (uncommitted at handoff time may include):**

- `lsp/` — Krypton Language Server (`kls.exe`, ~480 KB on Windows).
  Diagnostics + outline + completion working in VS Code Insiders. See
  [`lsp/README.md`](../lsp/README.md).
- `krypton-lang/extension.js` — VS Code LSP client (~300 LOC, no
  `vscode-languageclient` dep, hand-rolled framing). Latest version
  on Windows: 1.8.4.
- `extensions/krypton-language-1.8.x.vsix` — bundled extension +
  kls.exe for Windows.

Look at `git log --oneline -10` and `git status` to see what's actually
committed vs in-flight.

---

## What you can pick up on M1

Two well-scoped, mostly-independent tasks:

### A. macOS arm64 GC port — bring 1.7.5+ GC to Mach-O

Plan: [`docs/macos_gc_port_plan.md`](macos_gc_port_plan.md)

The macOS arm64 backend (`compiler/macos_arm64/macho_arm64_self.k`)
already has a bump allocator. Add the 1.7.5+ GC primitives:
`gcAllocated`, `gcLimit`, `gcSetLimit`, `gcReset`, `gcCollect`.

**Mostly: add 5 new global cells in `__DATA` zero-fill region + 5 new
builtins. No new section needed.**

Estimated: 1-2 sessions. Higher impact than B since it unblocks kls
and other long-running programs on macOS.

### B. macOS LSP port — get kls running on macOS

Plan: [`docs/macos_lsp_port_plan.md`](macos_lsp_port_plan.md)

Only one file needs porting (`lsp/jsonrpc.k`'s cfunc block —
`#ifdef _WIN32` around `_setmode`/`_strnicmp`). The diff is in the
plan doc, ready to apply.

Estimated: 1 session. Straightforward.

**Recommended order: A then B**, since kls benefits from GC on long
sessions. But B is fine to do first if you want a quick win.

---

## Existing macOS gotchas (memory)

From prior sessions:

- macOS does NOT use clang for self-host — `macho_arm64_self.k` writes
  Mach-O + ad-hoc signature directly. No clang/codesign external
  calls.
- Linux ELF self-host of `elf.k` produces a broken binary; re-seed
  needs Linux gcc on a Linux host (not relevant on M1 unless you also
  cross-compile).
- macOS kcc binary may be older than 1.8.0. If so, rebuild via
  `macho_arm64_self.k` before doing anything else, or some new
  builtins won't resolve.

---

## Quick orientation commands once on M1

```bash
git pull origin main
git status

# Confirm macOS kcc works at all
./kcc --version 2>/dev/null || echo "macOS kcc missing, build first"

# See what's in the macOS backend
wc -l compiler/macos_arm64/macho_arm64_self.k

# See the GC plan
cat docs/macos_gc_port_plan.md | head -80

# See the LSP plan
cat docs/macos_lsp_port_plan.md | head -80
```

---

## Don't forget when coming back to Windows

- The Windows `kls.exe` build chain assumes `gcc` (mingw-w64) on PATH.
  Bash on Windows works.
- The .vsix bundles a Windows kls.exe. If you change kls source,
  rebuild kls.exe first (`lsp/build.bat`), then rebuild .vsix
  (`scripts/build_vsix.sh`).
- Extension is currently 1.8.4 (1.8.4.vsix in `extensions/`).
  Extensions panel in VS Code Insiders will flag if older.
