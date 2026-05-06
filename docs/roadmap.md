# Krypton Roadmap

Current released version: **1.7.5** (2026-05-04). Internal builds beyond
1.7.5 (1.7.6 / 1.7.7 / 1.7.8) are kept under `versions/kcc_v17X.exe`
snapshots and ship features incrementally as the GC machinery is built
out toward 2.0 — they are not on the public download page.

The v1.0.0 goal — native compilation without an external C compiler — shipped in 1.0.0
(2026-03-23). Subsequent 1.x releases extended the native pipeline (Linux ELF, Windows
PE/COFF, macOS arm64 Mach-O), the language itself, and (in 1.7.x) the
GC infrastructure on the Windows native runtime.

For per-release detail, see `CHANGELOG.md` at the repo root.
For the 2.0 plan and the multi-tier GC sequencing, see `docs/v20_plan.md`.

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

## Shipped (1.5 — 1.7.5)

- **1.5.x** — compile.k import-walker fixes (CBLOCK propagation, skipBlock-after-jxt).
- **1.6.0** — Windows native pipeline restored. Pre-1.6.0, every `if`/`while`
  on the native path crashed silently (`isTruthy` was missing from
  `resolveBuiltin`). Native test suite went 0/38 → 38/38.
- **1.6.1** — late-cycle adds: 10 string/numeric builtins (`repeat`,
  `padLeft`, `padRight`, `reverse`, `abs`, `min`, `max`, `endsWith`,
  `bin`, `pow` + `**` operator), plus `stdlib/native_extras.k` with
  25 list/map helpers (`join`, `slice`, `splitBy`, `sort`, `keys`,
  `values`, `hasKey`, `mapGet`/`mapSet`, etc.). Examples climbed
  70/95 → 77/95 passing on the native pipeline.
- **1.7.0** — memory-plumbing release. Tier 1 of the GC plan: replaced
  `s = s + chunk` chains in `compiler/windows_x86/x64.k` and
  `compiler/compile.k` with `sbAppend` to cut the O(N²) allocation
  pattern that produced a 50 GB `kcc.exe` blowup on a malformed
  source file.
- **1.7.5** — GC API surface + first real allocation tracking. Bootstrap
  DLL got its first writable `.rdata` slot. New primitives:
  `gcAllocated()`, `gcLimit()`, `gcSetLimit(n)`, `gcCollect()` (placeholder).
  `gcSetLimit(n)` installs a circuit breaker that aborts cleanly with
  `ExitProcess(99)` if total allocation exceeds the cap — direct fix
  for the 1.6.1 50 GB scenario.

## Internal builds (post-1.7.5, snapshotted in `versions/`)

Released as `versions/kcc_v17X.exe` snapshots only — no installer, no
download page, no upload. Used to validate the GC machinery before the
next public release rolls them up.

- **1.7.6 (internal)** — `gcReset()` primitive. `__rt_alloc` redirected
  to `__rt_alloc_v2` which bump-allocates from a 64 MB slab; `gcReset()`
  zeroes `slab_off` for O(1) recycle. kryofetch `--watch` measurement
  showed memory bounded across renders (was leaking 110 KB/render
  pre-1.7.6).
- **1.7.7 (internal)** — multi-slab arena. When 64 MB slab fills,
  allocate a new slab via `HeapAlloc` and link it into a chain.
  `gcReset()` walks the chain and frees every slab except the first.
  No more per-call HeapAlloc fallback for total allocations under
  64 MB per slab.
- **1.7.8 (internal)** — checkpoint/restore primitives. `gcCheckpoint()`
  returns a token; `gcRestore(token)` rewinds the arena to that point,
  freeing slabs allocated since via `HeapFree`. Tighter scope than
  `gcReset` (which always rewinds to slab start). Token is single-use
  per `gcRestore` (it's allocated in the arena and gets reclaimed on
  restore).

For the full 2.0 plan including the C-style low-level memory layer,
lambdas in native, concurrency, ARM64 Linux backend, and LSP, see
[`docs/v20_plan.md`](v20_plan.md).

## Carried-over items (not on the GC track)

These are still open but lower priority than the GC machinery push:

- **Native module imports.** `import "stdlib/result.k"` should work via the native
  pipeline end-to-end (currently the IR walk inlines top-level `func`
  declarations from the file, but path resolution and de-duplication for nested
  imports needs work). Would unblock `examples/import_demo.k`.
- **Windows typed-struct expansion.** The Windows PE backend's V2 struct table
  supports five C structs today (`SYSTEM_INFO`, `MEMORYSTATUSEX`,
  `ULARGE_INTEGER`, `CONSOLE_SCREEN_BUFFER_INFO`, `SYSTEM_POWER_STATUS`).
  Add `PROCESSENTRY32` and `WIN32_FIND_DATAA` so programs like kryofetch can
  detect their parent shell and count installed packages without falling back
  to env vars or gcc.
- **Cross-platform parity for new ELF builtins.** `reverse`, struct/env runtime,
  and the trim/toUpper/toLower group landed on Linux first in 1.5;
  bring them to `compiler/macos_arm64/macho_arm64_self.k`. (Tracked
  alongside the macOS GC port — see `docs/macos_gc_port_plan.md`.)
- **`tokenize` as a runtime function.** Currently a compile.k internal; would let
  user programs do tokenization without depending on a compiler binary.
- **Auto-compute Windows runtime offsets.** Most of this was incidentally
  resolved by 1.6.0/1.6.1's non-cascading append pattern (helpers go
  at the end of the bootstrap block, retarget JMPs). The "six
  hardcoded offsets" warning still applies in the older middle of
  the block.
- **Smart-int boundary documentation + tooling.** Values ≥ `0x40000000` (1 GiB) are
  treated as string pointers; ints near that boundary collide. Add a runtime
  check + clearer error.
- **Drop the gcc bootstrap fallback.** `kcc.sh` still falls back to gcc for
  `elf_host` rebuild when `elf.k` self-host fails past ~67 funcs.
