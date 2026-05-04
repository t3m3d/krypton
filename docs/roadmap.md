# Krypton Roadmap

Current released version: **1.5.1** (2026-05-04).

The v1.0.0 goal — native compilation without an external C compiler — shipped in 1.0.0
(2026-03-23). Subsequent 1.x releases extended the native pipeline (Linux ELF, Windows
PE/COFF, macOS arm64 Mach-O) and the language itself.

For per-release detail, see `CHANGELOG.md` at the repo root.

---

## Shipped (1.0 — 1.4)

- **Native pipeline.** Krypton source → IR → optimizer → target backend → executable.
  No external C compiler required at user-invocation time on Linux x86_64, Windows
  x86_64, or macOS arm64.
- **Three backends, all written in Krypton:**
  `compiler/linux_x86/elf.k` — hand-emitted ELF64 with direct syscalls, no libc.
  `compiler/windows_x86/x64.k` — PE/COFF + thin `krypton_rt.dll`.
  `compiler/macos_arm64/macho_arm64_self.k` — Mach-O + ad-hoc SHA-256 codesign,
  no clang/ld/codesign needed.
- **Self-hosting.** `kcc-x64` (compiled from `compile.k`) compiles itself byte-for-byte
  on Linux. Bootstrap seeds shipped in `bootstrap/` for clone-and-run on every
  supported platform.
- **Language features delivered.** for-in, match, try/catch/throw, do-while, structs
  with dot access, struct literals (`Vec { x: 10, y: 20 }`), backtick interpolation
  (`` `Hello {name}` ``), list literals, compound assignment, post-/pre-inc,
  module system (`module`, `import`, `export`), `jxt` blocks for header inclusion,
  callbacks (raw C function pointers), DLL exports.
- **Stdlib.** ~30 modules under `stdlib/`: result, option, json, struct_utils,
  math_utils, string_utils, list_utils, map, etc.
- **Native runtime builtins** (Linux ELF, currently leading the platforms):
  `kp`, `printErr`, `print`, `len`, `length` (a.k.a. `count`), `substring`,
  `toInt`, `toStr`, `parseInt`, `split`, `range`, `startsWith`, `endsWith`,
  `contains`, `indexOf`, `replace`, `trim`, `toUpper`, `toLower`, `reverse`,
  `repeat`, `pow`, `abs`, `charCode`, `fromCharCode`, `isDigit`, `isAlpha`,
  `isTruthy`, `getLine`, `lineCount`, `readFile`, `writeFile`, `arg`,
  `argCount`, `exit`, `sbNew`/`sbAppend`/`sbToString`, `envNew`/`envSet`/`envGet`,
  `structNew`/`setField`/`getField`/`hasField`/`structFields`, plus `s[i]` indexing.

Test status: 37/37 native tests pass on Linux x86_64; ~79/84 examples pass.
The remaining example failures are largely `import_demo` (native module import
isn't yet wired), `runtokcount` / `test_tokenize` (would need `tokenize` as a
runtime helper, not a compiler internal), `run_committed` (a giant
single-file bootstrap compiler), and `struct_utils` (a library with no `main` —
expected).

---

## Near-term: 1.6

Goal: close the remaining native-runtime gaps and make the standard library
reachable from native programs.

- **Native module imports.** `import "stdlib/result.k"` should work via the native
  pipeline, not just the C path. Currently the IR walk inlines top-level `func`
  declarations from the file, but path resolution and de-duplication for nested
  imports needs work. Would unblock `examples/import_demo.k` and remove the
  inline-pair-helpers workaround scattered through tests/examples.
- **Windows typed-struct expansion.** The Windows PE backend's V2 struct table
  supports five C structs today (`SYSTEM_INFO`, `MEMORYSTATUSEX`,
  `ULARGE_INTEGER`, `CONSOLE_SCREEN_BUFFER_INFO`, `SYSTEM_POWER_STATUS`).
  Add `PROCESSENTRY32` (parent-process walks) and `WIN32_FIND_DATAA` (directory
  enumeration) so programs like kryofetch can detect their parent shell and
  count installed packages without falling back to env vars or gcc.
- **Cross-platform parity for new ELF builtins.** `reverse`, struct/env runtime,
  and the trim/toUpper/toLower group landed on Linux first in 1.5;
  bring them to `compiler/macos_arm64/macho_arm64_self.k`.
- **`tokenize` as a runtime function.** Currently a compile.k internal; would let
  user programs do tokenization without depending on a compiler binary. Would
  unblock `examples/runtokcount.k` and `examples/test_tokenize.k`.
- **Auto-compute Windows runtime offsets.** `compiler/windows_x86/x64.k` has
  six hardcoded byte-offset values that all shift together when any builtin
  changes size. Refactor to compute them automatically (the Linux ELF backend
  already does this via `funcVAddrs`). Would make adding Win32 builtins ~10x
  cheaper.
- **Smart-int boundary documentation + tooling.** Values ≥ `0x40000000` (1 GiB) are
  treated as string pointers; ints near that boundary collide. Add a runtime
  check, a clearer error, and document the limit prominently.
- **Drop the gcc bootstrap fallback.** `kcc.sh` still falls back to gcc for
  `elf_host` rebuild when `elf.k` self-host fails past ~67 funcs — fix that
  self-host bug, then remove the gcc path entirely.

---

## 2.0 candidates

Larger items that probably merit a major version bump.

- **ARM64 native backend for Linux.** Today only macOS arm64 has a native backend.
- **Lambdas as first-class values** in the native pipeline. The C path supports
  them via lifted helpers; native pipeline does not.
- **Garbage collection.** Replace the bump-only arena with a real GC. Today the
  arena grows monotonically until process exit; for long-running programs
  (servers, agents) this isn't viable.
- **Concurrency primitives.** Goroutine-style `go` blocks (the keyword is already
  reserved), with channels.
- **Package manager.** `kpm install foo` or similar — fetch and pin Krypton
  modules from a registry.
- **LSP server.** Editor support for diagnostics, jump-to-definition, autocomplete.
- **Quantum backend.** The original vision; reserved keywords (`quantum`, `qpute`,
  `process`, `measure`, `prepare`) are already in the tokenizer for it.
