# Handoff — M1 MacBook Setup & Workflow

Setup, build, and daily-driver instructions for picking up Krypton work on
an Apple Silicon Mac.

Last updated: 2026-05-11 (Krypton 2.0).

---

## State of the world

Krypton **2.0** is shipped on Windows (installer at
`installer/Output/krypton-2.0-setup.exe`, release notes in
`releasenotes/RELEASE_NOTES_2.0.txt`).

Recent 2.0 work that landed on the Windows side:
- All C companion DLLs (`ckrypton_gui/fs/proc`) eliminated. Stdlib + runtime
  are pure Krypton. Only intentional C left is `bootstrap/kcc_seed.c`.
- Mark-sweep GC complete with shadow-stack rooting and freelist reuse.
- WindowProc trampoline + full Win32 GUI surface in pure Krypton.
- Platform binaries moved from repo root into `compiler/<arch>/`:
  - `compiler/linux_x86/kcc-x64`
  - `compiler/linux_arm64/kcc-linux-arm64`
  - `compiler/macos_arm64/kcc-arm64` ← **your binary**
  - `kcc.exe` (Windows, root only)
- Odin-style import prefixes: `import "k:gui"`, `import "head:windows"`.

**What's currently working on macOS arm64:**
- Native Mach-O codegen (`compiler/macos_arm64/macho_arm64_self.k`).
- Bump-allocator memory.
- Ad-hoc code signature (no `codesign` external call).
- Last known seed binary: `bootstrap/kcc_seed_macos_aarch64`.

**What's NOT yet ported to macOS arm64 (vs. Windows 2.0):**
- Mark-sweep GC primitives (`gcMark`, `gcSweep`, `gcCollect`, `gcFreelistCount`,
  per-allocation 16-byte headers, shadow-stack rooting). The macOS backend
  still ships the 1.x bump allocator only.
- LSP server (`kls`). The Mach-O `kls` binary in `compiler/macos_arm64/kls`
  is a 1.8.x build; needs rebuild against current `lsp/*.k`. The
  `lsp/jsonrpc.k` `cfunc` block needs the `#ifdef _WIN32` split (plan in
  `docs/macos_lsp_port_plan.md`).
- 2.0 typed-pointer codegen for arm64 (`*u8`/`*u16`/`*u32` indexing).
- WindowProc trampoline equivalent (macOS uses Cocoa target-action; no
  current GUI surface on macOS — Win32-only feature).

---

## First-time setup

### Prerequisites
```bash
xcode-select --install     # CLI tools: clang, make, git
```
That's the entire dependency list. No Homebrew packages required for
Krypton itself (no clang invocation at user-compile time; the bootstrap
seed is the only C path).

### Clone + first build
```bash
cd ~/dev
git clone https://github.com/t3m3d/krypton.git
cd krypton
./build.sh
```

`build.sh` detects macOS arm64 and:
1. Either copies `bootstrap/kcc_seed_macos_aarch64` → `compiler/macos_arm64/kcc-arm64`
   (no clang needed), OR
2. Compiles `bootstrap/kcc_seed.c` via clang → `compiler/macos_arm64/kcc-arm64`,
   then self-rebuilds via `compiler/compile.k`.

End state: `compiler/macos_arm64/kcc-arm64` exists and `./kcc --version`
reports the current version.

### Make `kcc` available system-wide (optional)
```bash
sudo ln -s "$(pwd)/kcc" /usr/local/bin/kcc
kcc --version
```

The `kcc` root-level script is a shell dispatcher that picks
`compiler/macos_arm64/kcc-arm64` on Darwin/arm64.

---

## Daily-driver commands

```bash
# Compile + run a .k file (native Mach-O, no clang)
./kcc hello.k -o hello && ./hello

# Self-rebuild kcc after editing compile.k or macho_arm64_self.k
./build.sh

# Run regression suite
./build.sh test

# Bump bootstrap seed (after major compile.k changes)
./kcc --c compiler/compile.k > bootstrap/kcc_seed.c
# (Commit the regenerated seed. Linux x86 seed regen needs a Linux host.)
```

---

## Where things live (post 2026-05-11 cleanup)

```
krypton/
  kcc                          shell dispatcher (picks platform binary)
  kcc.sh                       driver script (--ir / --c / --llvm / --native)
  build.sh                     bootstrap + self-rebuild
  install.sh                   /usr/local symlink helper
  bootstrap/
    kcc_seed.c                 cold-start C source (cross-platform)
    kcc_seed_macos_aarch64     prebuilt Mach-O seed (skip clang on fresh checkout)
  compiler/
    compile.k                  shared frontend
    optimize.k                 shared optimizer
    macos_arm64/
      macho.k                  Mach-O codegen helpers
      macho_arm64_self.k       arm64 native backend (~3000 lines)
      macho_host               compiled optimizer for the macOS pipeline
      kcc-arm64                ← your kcc binary
      kls                      ← LSP server (needs rebuild for 2.0)
    linux_x86/                 (don't touch from M1)
    linux_arm64/               (don't touch from M1)
    windows_x86/               (don't touch from M1)
  runtime/
    krypton_rt.k               Krypton source for the rt symbol DLL (Windows-only relevance)
  stdlib/                      .k modules — `k:` prefix imports
  headers/                     .krh bindings — `head:` prefix imports
  lsp/                         language server (cross-platform; needs jsonrpc.k split)
  examples/                    .k programs
  tests/                       regression suite
  docs/                        plans + reference (this file lives here)
```

---

## Pending macOS arm64 work (priority order)

### A. Mark-sweep GC port — bring 2.0 GC to Mach-O
Plan: [`docs/macos_gc_port_plan.md`](macos_gc_port_plan.md) (written
when the design was Tier 2 / 1.7.5). Update needed for 2.0 mark+sweep:

- Per-allocation 16-byte header (next-link + size+flags) in `__rt_alloc`.
- `gcAllocsHead` global cell linked list.
- Shadow-stack region (lazy `mmap`'d 64 KB on macOS instead of Windows
  `HeapAlloc`).
- `kr_gc_mark` + `kr_gc_sweep` + freelist primitives in
  `macho_arm64_self.k` bootstrap helpers (current Windows machine code
  in `compiler/windows_x86/x64.k` at lines ~7050+ is the reference impl).
- `compile.k` already emits `gcShadowPush`/`gcShadowPop` ops — these
  need to map to arm64 instruction sequences in `macho_arm64_self.k`.

Estimated: 4-6 focused sessions.

### B. LSP port — kls on macOS
Plan: [`docs/macos_lsp_port_plan.md`](macos_lsp_port_plan.md).

Only `lsp/jsonrpc.k` needs work — wrap its `cfunc` block with
`#ifdef _WIN32` and add the POSIX path (`fcntl` instead of `_setmode`,
`strncasecmp` instead of `_strnicmp`). The rest of `lsp/*.k` is portable.

After porting: rebuild `compiler/macos_arm64/kls` via:
```bash
./kcc lsp/kls.k -o compiler/macos_arm64/kls
```

Estimated: 1 session.

### C. Typed pointers on arm64
Currently Windows-only (x64.k emits `bufGetByte`/etc. for `*u8` indexing).
Mirror in `macho_arm64_self.k`. Pattern: detect `; TYPE *u8` IR comment
on LOAD, route INDEX through direct buf read instead of generic `kr_idx`.

---

## Cross-platform sync rules

**Do** on M1:
- Build + test macOS arm64 binaries.
- Edit `compiler/compile.k`, `compiler/optimize.k`, stdlib, headers.
- Edit `compiler/macos_arm64/macho*.k` (your backend).
- Edit `lsp/*.k` (cross-platform LSP).
- Edit `bootstrap/kcc_seed.c` if you regenerate it; commit the result.

**Don't** touch from M1:
- `compiler/windows_x86/*.k` or any `.exe` artifacts.
- `compiler/linux_x86/*` or `compiler/linux_arm64/*`.
- `installer/*.iss` (Windows-only Inno Setup).
- `*.dll` files (Windows-only).
- `.vsix` extension bundles unless you're on a Mac with VS Code.

**Always** when crossing platforms:
- `git pull origin main` before starting.
- Regenerate `bootstrap/kcc_seed.c` only when compile.k changes are
  truly cross-platform — otherwise leave the seed alone and let the
  prebuilt platform seeds handle bootstrap.
- The macOS seed (`bootstrap/kcc_seed_macos_aarch64`) gets bumped
  whenever you do a major compile.k change AND want fresh-checkout
  bootstrap to skip clang on macOS.

---

## Quick orientation when picking up a session

```bash
git pull origin main
git status

# Confirm kcc works
./kcc --version

# See what's in the macOS backend
wc -l compiler/macos_arm64/macho_arm64_self.k

# Run a sanity build
./kcc examples/fibonacci.k -o /tmp/fib && /tmp/fib

# See current state of macOS-specific plans
cat docs/macos_gc_port_plan.md   | head -60
cat docs/macos_lsp_port_plan.md  | head -60

# See what changed since you last left
git log --oneline -20
```

---

## Known gotchas (from prior sessions)

- **macOS does NOT use clang for self-host.** `macho_arm64_self.k`
  writes Mach-O directly + adds the ad-hoc signature inline. No
  `clang` or `codesign` invocations at user-compile time.
- **Linux ELF self-host of `elf.k` produces a broken binary** —
  re-seeding `kcc_seed_linux_x86_64` needs a real Linux gcc on a Linux
  host, not relevant unless you're cross-compiling.
- **The macOS bootstrap seed may lag behind compile.k.** If `./kcc`
  rejects new builtins after `git pull`, run `./build.sh` to
  self-rebuild from compile.k via the seed → fresh kcc-arm64.
- **`lsp/jsonrpc.k`** has a Windows-only `cfunc` block. Until it's
  ported, `lsp/kls.k` won't compile on macOS — the `compiler/macos_arm64/kls`
  in the tree is from an older 1.8.x build that pre-dates that issue.
- **GUI features are Windows-only.** `stdlib/gui.k` uses Win32 IAT
  imports. macOS would need a Cocoa or AppKit backend (~not started~).
  Don't try to run GUI examples on macOS yet.

---

## When you come back to Windows

- Push your work; pull on the Windows side before doing anything.
- If you regenerated `bootstrap/kcc_seed.c`, the Windows side will pick
  it up automatically on next `build_v140.bat` or `bootstrap.bat` run.
- The Windows installer (`installer/krypton-installer.iss`) is the
  shipping artifact. macOS doesn't currently have an installer — the
  `releases/krypton-1.8.0-macos-arm64.pkg` is stale (1.8.x era).
  When the macOS arm64 GC port lands, the next release will need a
  matching `.pkg` (Apple's `pkgbuild` tool — no Inno Setup equivalent).
