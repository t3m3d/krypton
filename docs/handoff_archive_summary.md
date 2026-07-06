# Handoff Archive Summary

Compact facts preserved before deleting `handoffs/handoff_*.md`.

## Release State

- macOS `2.4.1` is live.
- GitHub release: `https://github.com/t3m3d/krypton/releases/tag/2.4.1`
- macOS assets uploaded:
  - `krypton-2.4.1-macos-arm64.tar.gz`
  - `krypton-2.4.1-macos-arm64.pkg`
- Homebrew tap is pushed for macOS `2.4.1`.
- Linux stays on `2.3.0` in the formula until matching Linux artifact is cut.

## kweb

- macOS package ships `web/kweb`, `web/kweb_gui.ks`, and `kweb_gui.app`.
- GUI deploy behavior:
  - empty remote folder means FTP account root
  - `test` means upload under `/test`
  - do not force `public_html`
- Historical bug: `web/kweb.htk` CLI deploy once forced `/public_html`.
  Keep current GUI/CLI behavior root-default: empty remote folder uploads to
  FTP account root, and `test` uploads under `/test`.

## Windows

- Windows release still needs parity work.
- Check installer/package includes current required pieces: `kcc`, runtime DLL, `kr`, `kweb`, `kls` if present, `headers`, `stdlib`, `bootstrap`, examples if already shipped.
- `print()` is now main newline print; `kp()` remains fallback. Windows still needs seed/release verification if not already done.
- Pending backend items:
  - `ws2_32` IAT host rebuild
  - GC phase-3 runtime verification
  - possible old FE/BE generation skew
- Avoid cross-FE artifacts unless FE/BE versions match.
- x64 host rebuild history:
  - Windows `x64_host` regeneration has been fragile and memory-heavy.
  - Broken rebuilds can produce valid-looking PE files that crash on startup or
    when processing real IR.
  - Current release work should prefer known-good backend binaries unless a new
    backend is rebuilt and smoke-tested end to end.
  - Cross-building Windows backend artifacts from macOS/Linux only works when
    frontend and backend `compile.k` generations match.
- Runtime/bootstrap gotcha:
  - `runtime/krypton_rt.k` is not always the executable body of
    `krypton_rt.dll`.
  - When output is `krypton_rt.dll`, bootstrap mode can emit helper bodies from
    `compiler/windows_x86/x64.k`; source-level changes in `runtime/krypton_rt.k`
    may only affect exported names/declarations.
  - Treat temp/copied DLLs as untrusted unless rebuilt from source or
    byte-identical to tracked `runtime/krypton_rt.dll`.
- GC stage notes:
  - Windows/macOS had staged GC work around freelist consumption and phase-3
    auto-collect, but older handoffs marked parts as source-landed before full
    Windows runtime validation.
  - Validate each GC stage with small runtime smokes before release; do not stack
    new GC work on unverified stage work.
- GUI warning:
  - `guiEnableModernChrome`, `guiApplyExplorerTheme`, and broader theme/color
    helpers were documented as modernization work but were not fully proven.
  - Current Windows testing showed those paths can crash after the window shows.
    Plain Win32 controls are the stable baseline until custom paint/theme
    support is rebuilt and verified.

## Linux

- Linux GC is not a phase-3 mirror. It needs a full ELF GC port, not a byte-copy of macOS/Windows phase 3.
- Current Linux backends are bump allocators with GC stubs.
- Known Linux runtime gaps:
  - `toStr(string)` can return raw heap pointer
  - tagged int/string print paths can misbehave in loops
  - `envGet -> toStr` can mis-print
- GC port should converge in small stages: object headers, GC globals, sweep, mark, collect, auto-collect safepoint.

## Roadmap

- Prefer Windows-first for major feature work, then mirror to macOS/Linux.
- Suggested order from roadmap:
  1. first-class file I/O
  2. floating point
  3. switch/enums/format
  4. fixed arrays/static locals/compound assignment
  5. defer/multi-return/slices/interfaces
- Python frontend prep exists, but future work depends on float/classes/exceptions decisions.

## Build Notes

- `build.sh` stays shell for bootstrap boundary.
- Post-kcc orchestration can be KryptScript (`.ks` run with `kcc -r`).
- `KRYPTON_ROOT` must be set/exported before invoking bootstrap drivers directly.
- Skip Win32-only fs/settings/dll tests on Linux/macOS.
