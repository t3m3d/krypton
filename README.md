# Krypton

**A self-hosting programming language that emits native machine code without a C compiler in the loop.**

> **Current macOS version: 2.4.5** — refreshed kweb CLI/GUI deploy release.
> See [`CHANGELOG.md`](CHANGELOG.md) for the full history.

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
![Version](https://img.shields.io/badge/version-2.4.5-brightgreen)
![macOS](https://img.shields.io/badge/macOS-arm64%202.4.5-success)
![Linux](https://img.shields.io/badge/Linux-x86__64%202.4.4-yellow)
![Windows](https://img.shields.io/badge/Windows-x86__64%202.3.0-orange)

## File extensions

Krypton recognises two sibling source extensions. **Same compiler, same
syntax** — the split is purely a naming convention.

- **`.k`** — library or compiled program. `module foo`, exports, no shebang.
- **`.ks`** — KryptScript (new in 2.2). A script meant to run directly.
  Write it **top-to-bottom with no boilerplate** — `kr` auto-wraps the body
  in `just run { }` when there's no explicit one, so `import`s, `func`s, and
  statements just go at the top of the file (Swift-style). An explicit
  `just run { }` still works if you want it. Add `#!/usr/bin/env kr` and
  `chmod +x` to make it executable on POSIX. On Windows the installer
  associates `.ks` with `kr.exe` so double-click + `myscript.ks foo bar`
  from any shell Just Works — the Windows-native equivalent of a `.bat`.
  Use `.ks` for one-off tools and build glue you'd otherwise reach for bash
  or Python for. Read more at
  [`krypton-lang.org/kryptscript`](https://krypton-lang.org/kryptscript.html).

  ```bash
  # hello.ks — no `just run` wrapper needed
  import "k:ansi"
  func greet(w) { emit "Hello, " + w + "!" }
  kp(bold(cyan(greet("world"))))

  kr hello.ks            # run it
  kr                     # start the interactive REPL
  ```

```bash
kcc -r examples/hello.ks             # POSIX: compile + run + clean up
chmod +x examples/hello.ks && ./examples/hello.ks   # POSIX shebang path
```

```bat
:: Windows (after the installer's "Associate .k/.ks files" task)
myscript.ks foo bar                  :: double-click works too
```

The web framework adds a third extension for templates:

- **`.htk`** — htmk + ks template source built by `kweb`. Same Krypton syntax;
  the convention signals "this file is meant to render HTML."

## What's new in 2.4.5

- **kweb deploy refresh** — rebuilt macOS release with the FTP root/default-folder fix and current `kweb.app`.

## What's new in 2.4.4

- **macOS GUI app name fixed** — the app is now `kweb.app`, not `kweb_gui.app`.
- **Choc replaces Cocoa as the public Objective-K UI layer** — macOS kweb now builds through `k:choc_macos`; Cocoa stays as compatibility/backend code.
- **`do` no-return syntax** — `-> do` is accepted and `-> void` now errors.

## What's new in 2.4.3

- **kweb GUI icon** — app bundle now ships a dedicated `kweb_gui.icns`.
- **Homebrew macOS release** — patch release for `brew upgrade krypton`.

## What's new in 2.4.2

- **Homebrew macOS refresh** — patch release so `brew upgrade krypton` sees a newer version number after the kweb GUI release.

## What's new in 2.4.1

- **macOS kweb GUI** — native Objective-K/KryptScript app for build and FTP deploy.
- **macOS packages include kweb** — `/usr/local/bin/kweb` is linked on install.
- **Remote deploy folder control** — empty means FTP account root; `test` uploads under `/test`.
- **kweb build binary refreshed** — fixes stale temp-path failure in the old `web/kweb`.

## What's new in 2.3

**The compiler stopped needing C.** 2.3.0 is fully clang/gcc-free across build,
run, imports, and self-host on macOS (arm64), Linux (x86-64), and Windows
(x86-64) — and the toolchain hosts itself on all three.

> ⚠️ **Breaking changes**
> - **`kcc.sh` removed.** `kcc` is now the Krypton-native driver (compiled from
>   `kcc.ks`, no bash dependency). Repoint any scripts/tooling that called `kcc.sh`.
> - **C path removed.** `--c` / `--gcc` / `--llvm` are gone (hard error). The
>   native code generators are the only path now.

- **Clang/gcc-free self-host** on all three platforms — fixpoint byte-stable.
- **Native StringBuilder** (growing-capacity, doubling realloc) — amortized O(1)
  append; append-heavy code goes from minutes to seconds, self-host RAM drops sharply.
- **Krypton-native `kcc.ks` driver** replaces the bash `kcc.sh`.
- **Linux backend parity** — first-class functions/closures (`FUNCPTR`/`callPtr`,
  `k:fp`), int-arg builtins, library-file + GC-diagnostic fixes, `--aarch64`
  cross-compile (`--arm64` alias kept).
- **Windows** — `kcc.exe`/`kcc-bin.exe` driver/backend split, native
  `krypton_rt.dll` StringBuilder, `kr.exe` Swift-like auto-wrap + REPL.
- **macOS** — Mach-O self-host crash fixed; fresh-clone build/install fixed.

## What's new in 2.2

- **KryptScript** — `.ks` everywhere the toolchain accepts `.k`. Installer +
  VS Code extension associate both. `kcc` derives output basenames
  correctly for either extension.
- **WASM playground** — every tutorial lesson compiles to `.wasm` via the
  Krypton-side emitter (`compiler/wasm32/wasm_self.k`) and ships into
  `web/site/dist/learn/`. The lesson "Run" button picks up the precompiled
  module via `wasm_runner.js` and falls back to the JS bridge when the code
  box is edited. **16 lessons (01–15, 18, 19)** match `kcc -r` output
  byte-for-byte through the Node loader; the others fall back transparently.
- **New WASM helpers `$lineCount` / `$getLine`** — newline-separator
  counterparts to `$count` / `$split`. Hand-emitted at function indices
  20 and 21; `lineCount("a\nb\n")` returns `2` (matches native
  trailing-`\n` discount). Unlocked lessons 18 + 19 with zero regressions.
- **Krypton in the browser** — host-side ABI hooks let `.ks` modules drive
  the DOM canvas directly (`canvas_clear`, `canvas_circle`, `canvas_line`,
  `canvas_set_fill`, `canvas_set_stroke`, `canvas_width`, `canvas_height`,
  `random_int`, `time_ms`). The site's hero particle animation is now a
  Krypton-emitted `.wasm` module rather than inline JavaScript — view its
  source at [`krypton-lang.org/particles.ks`](https://krypton-lang.org/particles.ks).
- **kweb** — single-binary web framework CLI. Bundled in the Windows
  installer; build from source on macOS / Linux. `krypton-lang.org` itself
  is rendered by kweb.
- **Choc / Objective-K native UI** *(in progress)* — `stdlib/objk.k`,
  `stdlib/choc_macos.k`, and the Windows Choc layer form the native UI
  facade for pure Krypton apps. Cocoa remains available as compatibility
  code behind the macOS backend.
- **Zero-C HTTP server on macOS** *(macOS backend)* — `stdlib/server_native.k`
  is a complete HTTP server in pure Krypton on top of new BSD-socket
  builtins (`sockMake/Bind/Listen/Accept/Recv/RecvStr/Send/Close`) that
  the macho backend emits as direct `svc` syscalls. No libc, no clang,
  no `cfunc`. Verified end-to-end on macOS Tahoe arm64 with URL-decoded
  query params and HTML/JSON responses. The legacy `k:server` (with
  Winsock + POSIX `cfunc`) is still around for the Windows / `--gcc`
  path; new macOS code should `import "k:server_native"`.

**Platform release status (2026-07-05):**

| Platform | Shipped version | Notes |
|----------|-----------------|-------|
| macOS arm64 | **2.4.5** | `.pkg`, tarball, or Homebrew. Includes `kweb`, `/usr/local/bin/kweb`, and `/Applications/Krypton/kweb.app`. |
| Linux x86_64 | **2.4.4** | Prebuilt tarball -> `./install.sh`, or build from source. No C compiler. Self-hosting. Includes rebuilt `kcc` seed, driver, kweb, and aarch64 via `kcc --aarch64` cross-compile. |
| Windows x86_64 | **2.3.0** | Inno Setup installer: `kcc.exe`/`kcc-bin.exe` driver/backend split, native `krypton_rt.dll`, `kr.exe` REPL, kweb, WASM, .k/.ks associations. |
| **VS Code / Antigravity ext.** | **2.3.0** | `extensions/krypton-language-2.3.0.vsix`. Adds `.ks` (KryptScript) alongside `.k`, bundles the `kls` language server for Windows + macOS, ships `KryptScript` as a language-picker alias. |

macOS is on [`2.4.5`](https://github.com/t3m3d/krypton/releases/tag/2.4.5).
Linux is on [`2.4.4`](https://github.com/t3m3d/krypton/releases/tag/2.4.4).
Windows and the editor extension stay on [`2.3.0`](https://github.com/t3m3d/krypton/releases/tag/2.3.0)
until their matching artifacts are cut.

**Bundled CLIs (one package, four commands):**

- `kcc` / `krypton` — compiler.
- `kr` (POSIX) / `kr.exe` (Windows) — KryptScript runner. POSIX is a
  shebang-friendly bash shim over `kcc -r` that also (a) **auto-wraps**
  top-level code in `just run { }` so `.ks` files need no boilerplate, and
  (b) starts an **interactive REPL** when run with no arguments (`kr` →
  `ks>` prompt; remembers `import`/`func`/`let`, multi-line blocks, `:help`
  / `:list` / `:reset` / `:q`). Windows is a tiny native PE
  (`tools/kr/run.k` → `kr.exe`, ~16 KB) that compiles a `.k`/`.ks` script
  to a temp file, runs it inheriting stdio, propagates the script's exit
  code, then cleans up. The installer associates `.ks` with `kr.exe` so
  Explorer double-click + cmd.exe `myscript.ks args` both Just Work — the
  Windows-native equivalent of a `.bat` file. _(As of 2.3.0, Windows `kr.exe`
  has the same top-level auto-wrap + REPL as the POSIX `kr`.)_
- `kweb` — web framework CLI (`kweb init <name>`, `kweb build`, `kweb serve`,
  `kweb deploy <host> <user>`). macOS 2.4.5 also ships `kweb.app` for build
  and FTP deploy.

Krypton is a dynamically typed language with clean syntax, ~150 built-in functions, and a compiler written in itself.

**2.0 highlights** (see [`CHANGELOG.md`](CHANGELOG.md) for the full list):

- **Mark-sweep GC** with shadow-stack rooting and freelist reuse —
  long-running programs (LSP, servers, monitors) now stay flat in
  memory after `gcCollect()`.
- **Lambdas + closures** as first-class values (`stdlib/fp.k`).
- **Typed pointers** (`*u8`, `*Vec3`) and `let local TYPE name` for
  zero-overhead struct field access.
- **Win32 ABI marshalling** at ~30 call sites — `Sleep(500)` and
  `let t = GetTickCount()` work directly, no cfunc wrappers.
- **Memory-mapped files** (`mmapFile` in `stdlib/mmap.k`) for
  zero-copy file scanning.
- **Inline asm primitives**: `pause()`, `mfence()`, `lfence()`,
  `sfence()`, `rdtsc()`.

The **default** compilation pipeline produces a native executable on every supported platform — no gcc, no clang, no external toolchain at user-invocation time:

| Platform | Backend | Output |
|----------|---------|--------|
| **Linux x86_64** | `compiler/linux_x86/elf.k` | Static ELF, direct syscalls, no libc |
| **FreeBSD x86_64** | `compiler/freebsd_x86/elf.k` | Static ELF scaffold, direct syscalls, no libc; seed pass pending |
| **Windows x86_64** | `compiler/windows_x86/x64.k` | PE/COFF, kernel32-only via `runtime/krypton_rt.dll` |
| **macOS arm64** | `compiler/macos_arm64/macho_arm64_self.k` | Mach-O with in-Krypton SHA-256 ad-hoc code signing |

The native code generators are the only path. The old C escape hatches
(`--c` / `--gcc` / `--llvm`) were **removed in 2.3.0** — they now hard-error.

```
jxt
inc "stdlib/math_utils.k"

func fibonacci(n) {
    if n <= 1 { emit n }
    emit toInt(fibonacci(n - 1)) + toInt(fibonacci(n - 2)) + ""
}

just run {
    kp(fibonacci("10"))
    kp(isPrime("17"))
}
```

---

## Quick Start

### Requirements

**Nothing for end users.** Released supported platforms ship prebuilt seed binaries in `bootstrap/`. `git clone` and go. FreeBSD x86_64 is scaffolded and waits on its first seed pass.

| Platform | Files in `bootstrap/` | Compiler at install time |
|----------|----------------------|--------------------------|
| Linux x86_64 | `kcc_seed_linux_x86_64`, `elf_host_linux_x86_64`, `optimize_host_linux_x86_64` | none (pure copy) |
| FreeBSD x86_64 | `kcc_seed_freebsd_x86_64`, `kcc_driver_freebsd_x86_64`, `elf_host_freebsd_x86_64`, `optimize_host_freebsd_x86_64` | pending first seed; no C fallback wired |
| Windows x86_64 | `kcc_seed_windows_x86_64.exe`, `x64_host_windows_x86_64.exe`, `optimize_host_windows_x86_64.exe` | none (pure copy) |
| macOS arm64 | `kcc_seed_macos_aarch64` | none (pure copy); macho_host built on first `--native` call via clang |
| Linux ARM64 | `kcc_seed_linux_aarch64` | none (pure copy); **C path only** — no native ELF aarch64 backend yet, `kcc --native` falls back to gcc/clang |

**Optional, for development only (end users never need a C compiler):**
- **gcc / clang** — one-time backend bootstrap *only* if you edit a backend
  emitter (`compiler/linux_x86/elf.k`, `compiler/freebsd_x86/elf.k`,
  `compiler/windows_x86/x64.k`, or `compiler/macos_arm64/macho_arm64_self.k`)
  and need to rebuild its host seed.
  Building and running normal programs never touches a C compiler.
- **macOS**: the `macho_arm64_self.k` pipeline emits Mach-O directly with
  in-Krypton SHA-256 ad-hoc signing — no clang or `codesign` invocation at
  user-compile time.

---

### Linux / WSL

**Install via Homebrew (recommended):**

```bash
brew tap t3m3d/krypton
brew install krypton
```

Installs `kcc` (or `krypton`) and `kweb` on PATH — prebuilt static ELF binaries,
no C compiler. x86_64 only.

**Or the prebuilt tarball / source:**

```bash
git clone https://github.com/t3m3d/krypton && cd krypton && ./install.sh
```

(or `./build.sh` for a non-installing build).

`./build.sh` copies `bootstrap/kcc_seed_linux_x86_64` directly as `./kcc-x64`. No compiler invoked. Smoke test runs `examples/fibonacci.k` through the native ELF pipeline:

```bash
kcc hello.k                          # default native pipeline (no gcc)
./hello                                  # static ELF, direct syscalls, no libc
```

The pipeline is `compile.k → .kir → optimize.k → compiler/linux_x86/elf.k → ELF binary`.

### Windows x86_64

**Install via Chocolatey (recommended):**

```
choco install krypton
```

Then use `krypton` (or `kcc`) from any terminal.

**Or build from source:**

```
git clone https://github.com/t3m3d/krypton
cd krypton
bootstrap.bat
```

`bootstrap.bat` copies `kcc_seed_windows_x86_64.exe`, `x64_host_windows_x86_64.exe`, and `optimize_host_windows_x86_64.exe` from `bootstrap/` into place. No compiler required.

```
kcc hello.k                          # default native pipeline (no gcc)
hello.exe                                # PE/COFF, kernel32-only
```

The pipeline is `compile.k → .kir → optimize.k → compiler/windows_x86/x64.k → PE/COFF`. Output exes import only `kernel32.dll` via the bundled `runtime/krypton_rt.dll`.

For a from-source rebuild of the seed binaries, `build_v141.bat` uses [TDM-GCC](https://jmeubank.github.io/tdm-gcc/) or MSYS2 mingw-w64. End users don't need it.

### macOS arm64

**Install via Homebrew (recommended):**

```bash
brew tap t3m3d/krypton
brew install krypton
```

Then use `kcc` (or `krypton`) from any terminal.

**Or build from source:**

```bash
git clone https://github.com/t3m3d/krypton && cd krypton && ./build.sh
```

The macOS pipeline is `compile.k → .kir → compiler/macos_arm64/macho_arm64_self.k → Mach-O`. The Krypton-side emitter writes the entire Mach-O — load commands, `__TEXT`/`__DATA`/`__LINKEDIT`, chained fixups — and the SHA-256 ad-hoc code signature, all in Krypton. **No clang, no `as`, no `ld`, no external `codesign` invocation.**

```bash
kcc hello.k -o hello                  # default: native arm64 Mach-O
./hello
```

`./scripts/verify_macho_self.sh` runs the end-to-end self-emitted Mach-O smoke tests.

Why this differs in implementation from Linux/Windows: macOS Tahoe+ AMFI rejects unsigned and improperly-formatted Mach-Os, so the emitter has to produce a properly chained-fixups dyld-linked binary AND embed a valid code signature. Both happen in pure Krypton.

---

### Write a program

```
// hello.k
just run {
    kp("Hello from Krypton!")
}
```

For multi-file projects (anything with a `module <name>` decl on at
least one file), put the `just run { ... }` body in a file literally
named `run.k`. The compiler emits a warning today when it isn't, and
will hard-error in the next major. Single-file scripts (no `module`
decl) are exempt — `myscript.ks` keeps working from anywhere.

```
myproject/
  run.k        # `just run { ... }` lives here
  parser.k     # library code: `module myproject`, `func`, `struct`, ...
  render.k     # library code
```

### Compile to a native binary (default)

```bash
kcc hello.k                # produces ./hello (Linux/macOS) or ./hello.exe (Windows)
./hello
```

Per-platform pipeline (chosen automatically):

- **Linux** — emits ELF64 directly via [compiler/elf.k](compiler/elf.k). Static binary, direct syscalls, no libc, no dynamic linker.
- **Windows** — emits PE/COFF directly via [compiler/x64.k](compiler/x64.k). Imports only `kernel32.dll` (via `runtime/krypton_rt.dll`).
- **macOS** — emits assembly via [compiler/macho.k](compiler/macho.k); `clang` assembles + links + signs into a Mach-O. (Tahoe AMFI rejects hand-rolled static binaries — clang produces a properly dyld-linked binary the kernel will accept.)

### Other compilation modes (opt-in)

```bash
kcc --ir hello.k                      # emit Krypton IR (.kir) to stdout
kcc --aarch64 hello.k -o hello        # Linux: cross-compile to a static aarch64 ELF
```

> The C escape hatches `--c` / `--gcc` / `--llvm` were **removed in 2.3.0**
> (they now hard-error). Native code generation is the only path.

---

## Language

### Variables

```
let x = "42"
let name = "Krypton"
const pi = "3.14159"
```

All values are strings at runtime. Arithmetic auto-detects numeric strings.

### Type Annotations (optional)

```
let x: int = "42"
let name: string = "Krypton"

func add(a: int, b: int) -> int {
    emit toInt(a) + toInt(b) + ""
}

func log(message: string) -> do {
    print(message)
}
```

`do` is Krypton's action-only / no-result return contract. Use `emit` when a function produces a value; use `-> do` when the function only performs work. Annotations document intent for humans and tooling; selected annotations already guide typed pointers, closures, and backend contracts.

### Functions

```
func greet(name) {
    emit "Hello, " + name + "!"
}

just run {
    kp(greet("World"))
}
```

`emit` (or `return`) sends a value out of a function. Action-only functions can use `-> do` and fall through. `just run` is the program entry point.
`scan(prompt)` is the standard line-input word. `get()` and `getEcho()` are the standard single-key contracts; native backends should lower them to no-Enter key reads.

### Imports — jxt block

**Bracketless form (recommended):**

```
jxt
inc "stdlib/result.k"
inc "stdlib/math_utils.k"
inc "windows.h"

just run { ... }
```

The block ends at the first non-`inc` line. Each `inc` is dispatched by the file extension:
- `.k` → Krypton module (full source inlined at compile time)
- `.h` / `.krh` → C header (emits `#include` in generated C)

**Brace form (still supported):**

```
jxt {
    k "stdlib/result.k"
    k "stdlib/math_utils.k"
    c "windows.h"
}
```

- `k` — Krypton module
- `c` — C header
- `t` — alias for `c` (family initial)

The legacy `import` keyword still works.

### Closures / Lambdas

```
// Assign anonymous functions to variables
let double = func(x) { emit toInt(x) * 2 + "" }
let add = func(a, b) { emit toInt(a) + toInt(b) + "" }

kp(double("5"))      // 10
kp(add("3", "4"))    // 7

// Pass as arguments to higher-order functions
func applyTwice(f, x) { emit f(f(x)) }
kp(applyTwice(double, "3"))   // 12
```

### Structs

```
struct Point {
    let x
    let y
}

let p = Point { x: "10", y: "20" }
kp(p.x)
p.x = "42"
```

### String Interpolation

```
let name = "Krypton"
kp(`Hello, {name}!`)
kp(`1 + 1 = {1 + 1}`)
```

### Control Flow

```
// if / else if / else
if x > 10 { kp("big") } else if x > 5 { kp("medium") } else { kp("small") }

// while
while i < 10 { i += 1 }

// for-in (comma-separated lists)
for item in "a,b,c" { kp(item) }

// match
match color {
    "red"  { kp("warm") }
    "blue" { kp("cool") }
    else   { kp("other") }
}

// try / catch / throw
try {
    throw "something went wrong"
} catch e {
    kp("caught: " + e)
}
```

### Booleans

```
kp(true)               // "true"
kp(false)              // "false"

let flag = true
if flag       { kp("yes") }
if !false     { kp("yes") }
if "0"        { kp("never") }     // "0" is falsy
if "false"    { kp("never") }     // "false" is falsy
if ""         { kp("never") }     // empty is falsy
if "anything" { kp("yes") }       // any other non-empty is truthy
```

`true` and `false` are language keywords — they evaluate to the strings
`"true"` and `"false"`. There's no distinct boolean runtime type; the
truthiness rule (`""` / `"0"` / `"false"` / `0` are falsy, everything else
truthy) carries the semantics through `if`, `while`, `!`, and `isTruthy`.

Comparison and logical ops (`==`, `<`, `&&`, etc.) and builtins like
`hasField` / `isDigit` return `"1"` / `"0"` for backward compatibility. So
`true == (5 > 3)` is *false* (`"true"` ≠ `"1"`) — both are truthy, but
they're different value forms. Use `stdlib/booleans.k`'s
`bool(v)` / `boolEq(a, b)` / `kpBool(v)` helpers when you want to normalize.

### Floats

```
let result = fadd("3.14", "2.72")
kp(fformat(result, "2"))   // "5.86"
```

Float builtins: `fadd`, `fsub`, `fmul`, `fdiv`, `fsqrt`, `ffloor`, `fceil`, `fround`, `fformat`, `flt`, `fgt`, `feq`

---

## Compilation Pipeline

The default `kcc source.k` invocation produces a native binary using a Krypton-only emitter. No C compiler or linker is invoked at user-call time on any of the three supported platforms:

```
source.k
    │
    ├─ Linux x86_64   (default):  source.k → .kir → optimize.k →
    │                              compiler/linux_x86/elf.k → ELF binary
    │                              (direct syscalls, no libc, no linker)
    │
    ├─ Windows x86_64 (default):  source.k → .kir → optimize.k →
    │                              compiler/windows_x86/x64.k → PE/COFF
    │                              (kernel32-only via runtime/krypton_rt.dll)
    │
    ├─ macOS arm64    (default):  source.k → .kir →
    │                              compiler/macos_arm64/macho_arm64_self.k →
    │                              Mach-O (in-Krypton SHA-256 ad-hoc signing)
    │
    ├─ --aarch64      (Linux):    source.k → .kir →
    │                              compiler/linux_aarch64/elf.k → static aarch64 ELF
    │
    └─ --ir:                      source.k → Krypton IR (.kir) to stdout

  (The --c / --gcc / --llvm C escape hatches were removed in 2.3.0.)
```

### Krypton IR

```
kcc --ir source.k > source.kir
```

Emits `.kir` — a stack-based intermediate representation, one instruction per line:

```
FUNC add 2
PARAM a
PARAM b
LOCAL result
LOAD a
BUILTIN toInt 1
LOAD b
BUILTIN toInt 1
ADD
PUSH ""
ADD
RETURN
END
```

### IR Optimizer

```
optimize.exe source.kir > source_opt.kir
```

Six passes: dead code elimination, constant folding, strength reduction,
STORE/LOAD elimination, empty jump removal, unused local removal.

---

## Standard Library

77+ modules in `stdlib/`. Highlights:

| Module | Contents |
|--------|----------|
| `math_utils.k` | gcd, lcm, isPrime, fibonacci, factorial, sqrt, abs, power |
| `result.k` | ok/err/isOk/isErr/unwrap/unwrapErr/unwrapOr |
| `option.k` | optSome/optNone/isSome/isNone/optUnwrap |
| `json.k` | jsonStr/jsonBool/jsonArray/jsonObject/jsonNull |
| `float_utils.k` | floatAdd/floatMul/floatSqrt/floatFormat/pi() |
| `arch.k` | Host CPU detection — `arch()`, `isArm()`, `isX86()`, `is64Bit()` |
| `x11.k` | X11 wire-protocol client (handshake + server-info parse; Linux GUI flagship) |
| `server_native.k` | Pure-Krypton HTTP server on the macOS native socket builtins |
| `color.k` | Hex/RGB/HSL conversion + lighten/darken/mix |
| `mime.k` | MIME type lookup by extension or path |
| `cookie.k` | HTTP cookie parse + build (`Set-Cookie:` attrs) |
| `base64.k` / `hex.k` | RFC 4648 + standard hex encode/decode |
| `csv.k` / `url.k` | RFC 4180 CSV + RFC 3986 URL parse / build |
| ... | 65 more modules in `stdlib/` — see `ls stdlib/*.k` |

---

## Ecosystem

Sibling repos under the same GitHub org. Each is its own program/repo,
built against this Krypton checkout via `KRYPTON_ROOT/kcc`.

| Repo | Language | Platforms | What it is |
|---|---|---|---|
| [kryofetch](https://github.com/t3m3d/kryofetch) | Krypton | Windows 10/11, Linux x86_64 | System-info CLI (neofetch-class). Talks to Win32 / `/proc` / `/sys` directly — no WMI, no PowerShell, no Python. |
| [yubikrypt](https://github.com/t3m3d/yubikrypt) | KryptScript | macOS arm64, Linux x86_64 | YubiKey detector + OATH/TOTP authenticator. Single self-contained `.ks`. |
| [kryoterm](https://github.com/t3m3d/kryoterm) | Krypton + KryptScript | Linux x86_64 (phase 0) | Krypton-native terminal emulator. Targets `stdlib/x11.k` for windowing once Phase B/C ship — no Qt, no GTK, no libX11. |
| [terk](https://github.com/t3m3d/terk) | C++ / Qt6 | Windows, macOS, Linux | Pre-existing Qt6 terminal. Slated to retire once `kryoterm` reaches feature parity. |
| [kmon](https://github.com/t3m3d/kmon) | Krypton | Windows 10/11 (requires Npcap) | Real-time network monitor — captures live packets, parses Ethernet + IPv4 + TCP/UDP/ICMP, streams to a browser dashboard via SSE. |

Each app's repo ships its own `build_linux.sh` + `PKGBUILD` (where applicable).
Arch users: `git clone <repo> && cd <repo> && makepkg -si`.

> Linux aarch64 support for the Krypton-language apps lands once the aarch64
> backend reaches Milestone 4 (string concat). See [`LINUX_RELEASE_TODO.md`](LINUX_RELEASE_TODO.md).

---

## Project Structure

```
krypton/
├── compiler/
│   ├── compile.k                       # Self-hosting frontend
│   ├── optimize.k                      # IR optimizer
│   ├── llvm.k                          # LLVM IR backend (optional)
│   ├── run.k                           # Interpreter
│   ├── linux_x86/elf.k                 # Linux x86_64 ELF emitter
│   ├── freebsd_x86/elf.k               # FreeBSD x86_64 ELF emitter scaffold
│   ├── windows_x86/x64.k               # Windows x86_64 PE/COFF emitter
│   └── macos_arm64/macho_arm64_self.k  # macOS arm64 Mach-O emitter (with signing)
├── runtime/
│   ├── krypton_rt.k       # Krypton runtime (Phase 2 — self-hosted)
│   └── krypton_rt.dll     # Windows bootstrap runtime (kernel32-only, hand-emitted by x64.k)
├── bootstrap/                                # Prebuilt seeds — pure-copy install, no compiler
│   ├── kcc_driver_<os>_<arch>                # kcc.ks-built driver (the `kcc` command), per platform
│   ├── kcc_seed_linux_x86_64                 # Linux x86_64 kcc ELF
│   ├── elf_host_linux_x86_64                 # Linux x86_64 ELF emitter
│   ├── optimize_host_linux_x86_64            # Linux x86_64 IR optimizer
│   ├── kcc_seed_freebsd_x86_64               # FreeBSD x86_64 kcc ELF (pending seed)
│   ├── elf_host_freebsd_x86_64               # FreeBSD x86_64 ELF emitter (pending seed)
│   ├── optimize_host_freebsd_x86_64          # FreeBSD x86_64 IR optimizer (pending seed)
│   ├── kcc_seed_linux_aarch64                # Linux ARM64 kcc ELF (C path only — no ARM64 ELF emitter yet)
│   ├── kcc_seed_windows_x86_64.exe           # Windows kcc PE
│   ├── x64_host_windows_x86_64.exe           # Windows PE/COFF emitter
│   ├── optimize_host_windows_x86_64.exe      # Windows IR optimizer
│   ├── kcc_seed_macos_aarch64                # macOS arm64 kcc Mach-O
│   └── REBUILD_SEED.md                       # How/when to rebuild seeds (covers all platforms)
├── stdlib/                # Standard library modules (~30 files: result, option, json, math_utils, …)
├── examples/              # Showcase programs (84 files: hello, fibonacci, calculator, hex_dump, …)
├── algorithms/            # Textbook algorithm reference impls (35 files: sorts, DP, graph, KMP, …)
├── tutorial/              # Step-by-step language intro (25 numbered lessons)
├── tools/                 # Single-file CLI utilities written in Krypton (cat, grep, head, fmt, …)
├── headers/               # .krh module headers (Win32, libc bindings)
├── tests/                 # Test suite (38 tests, run via ./build.sh test)
├── docs/                  # Roadmap + EBNF/types/functions specs
├── grammar/               # Single-source EBNF (krypton.ebnf)
├── extensions/            # Prebuilt VS Code extension (.vsix)
├── krypton-lang/          # Source for the VS Code extension; syntaxes/ is a git submodule
│                          # pinned to https://github.com/t3m3d/krypton-tmLanguage
├── assets/                # Windows icon resource (krypton_rc.o)
├── installer/             # Windows installer build artifacts
├── scripts/               # Dev helpers — sweep_examples.sh, sweep_algorithms.sh, build_vsix.sh, …
├── versions/              # Historical bootstrap binaries
├── build.sh               # Linux/macOS/WSL build (uses prebuilt seed when available)
├── bootstrap.bat          # Windows install (copies prebuilt binaries from bootstrap/)
├── build_v141.bat         # Windows from-source rebuild (requires TDM-GCC, dev only)
├── install.sh             # Linux install (build + symlink to /usr/local/bin)
├── kcc                 # Compiler driver (dispatches to per-platform native emitter)
├── Makefile               # Cross-platform make wrapper around build scripts
├── CHANGELOG.md           # Full version history
└── LICENSE                # Apache 2.0
```

---

## Bootstrap

Krypton solves the self-hosting chicken-and-egg problem by shipping prebuilt seed binaries in `bootstrap/` for every supported platform. A fresh clone needs **no compiler** to install.

**End-user install (no compiler on any platform):**

| Platform | Install command | What it does |
|----------|-----------------|--------------|
| Linux x86_64 | `./build.sh` | `cp bootstrap/kcc_seed_linux_x86_64 ./kcc-x64`, copies elf_host + optimize_host into place, smoke-tests fibonacci |
| FreeBSD x86_64 | `./build.sh` | pending first seed; expects `bootstrap/kcc_seed_freebsd_x86_64`, `bootstrap/kcc_driver_freebsd_x86_64`, and `bootstrap/elf_host_freebsd_x86_64` |
| Windows x86_64 | `bootstrap.bat` | copies `kcc_seed_*.exe`, `x64_host_*.exe`, `optimize_host_*.exe` |
| macOS arm64 | `./build.sh` | `cp bootstrap/kcc_seed_macos_aarch64 ./kcc-arm64` (M1/M2/M3) |

Pure `cp` — no compiler invoked at install. After that, `kcc source.k` runs the platform's native emitter end-to-end with no C tools.

**Re-seeding (developer-only):**

If you edit `compiler/<platform>/<emitter>.k` you may need to rebuild the seed. As of 2.3.0 the native toolchain regenerates its own seeds with **no C compiler** (the frontend self-hosts and the backend host is rebuilt by the native pipeline); the exact steps live in [bootstrap/REBUILD_SEED.md](bootstrap/REBUILD_SEED.md). (macOS still uses clang for the one-time `macho_host` rebuild if you edit `macho_arm64_self.k` and no prebuilt host is present.)

The compiler has been self-hosting since the v0.1 series. Historical bootstrap binaries live in `versions/`.

---

## Native Headers (.krh)

Headers in `headers/` declare external (C library / OS API) functions so
Krypton programs can call them via FFI through the C-emitter pipeline.

### C standard library

| Header | Contents |
|--------|----------|
| `stdio.krh` | C stdio — printf, fopen, fread, fwrite, fgets |
| `stdlib.krh` | malloc, free, atoi, atof, exit, system, getenv, qsort, rand |
| `string.krh` | strlen, strcpy, strcat, strcmp, strstr, memcpy, memset |
| `math.krh` | libm — sin, cos, sqrt, pow, log, exp, floor, ceil |
| `time.krh` | time, ctime, strftime, clock, clock_gettime, nanosleep |
| `ctype.krh` | isalpha, isdigit, isspace, tolower, toupper, etc. |
| `errno.krh` | strerror, perror |
| `assert.krh` | __assert_fail (Krypton's `assert` builtin is preferred) |
| `signal.krh` | signal, raise, kill, sigaction |
| `setjmp.krh` | setjmp, longjmp (Krypton's `try`/`catch` is preferred) |

### POSIX (Linux / macOS)

| Header | Contents |
|--------|----------|
| `unistd.krh` | read, write, close, fork, exec*, getpid, sleep, chdir |
| `sys_stat.krh` | stat, fstat, mkdir, chmod, umask |
| `fcntl.krh` | open, fcntl, posix_fadvise |
| `dirent.krh` | opendir, readdir, closedir |
| `sys_socket.krh` | POSIX sockets — socket, bind, listen, accept, send, recv |
| `netinet_in.krh` | sockaddr_in, in6_addr, htons/htonl/ntohs/ntohl |
| `arpa_inet.krh` | inet_pton, inet_ntop, inet_addr |
| `netdb.krh` | getaddrinfo, gethostbyname, gai_strerror |
| `sys_mman.krh` | mmap, munmap, mprotect, msync, shm_open |
| `dlfcn.krh` | dlopen, dlsym, dlclose (link with `-ldl` on Linux) |
| `pthread.krh` | pthread_create/join, mutex, cond, rwlock, once |

### Windows

| Header | Contents |
|--------|----------|
| `windows.krh` | Win32 system info, registry, console, PDH, toolhelp + GUI structs (RECT, POINT, MSG, WNDCLASSEXA, PAINTSTRUCT) |
| `user32.krh` | Window classes, message pump, paint, dialogs, input — link with `-luser32` |
| `gdi32.krh` | Text drawing, pens / brushes / fonts, shapes, bitmaps — link with `-lgdi32` |
| `fileio.krh` | Windows file I/O — CreateFile, ReadFile, FindFirstFile |
| `process.krh` | CreateProcess, WaitForSingleObject, CreateThread, Sleep |
| `winsock.krh` | TCP/UDP networking (Winsock2) — IAT-resolved via `ws2_32.dll` in native-PE mode (no link flag); `-lws2_32` only applies to the legacy `--gcc` path |
| `shell32.krh` | Default-handler launch + folder picker + known folders (ShellExecuteA, SHBrowseForFolderA, SHGetFolderPathA) — IAT-resolved via `shell32.dll` in native-PE mode; pair with `stdlib/shell.k` |
| `psapi.krh` | Process introspection — EnumProcesses, EnumProcessModules, GetModuleBaseNameA, GetModuleFileNameExA, GetProcessMemoryInfo — IAT-resolved via `psapi.dll` in native-PE mode; pair with `stdlib/proc_ex.k` |
| `iphlpapi.krh` | Windows IP Helper API — GetAdaptersAddresses, GetAdaptersInfo, GetIfTable, GetTcpTable, IcmpCreateFile / IcmpSendEcho / IcmpCloseHandle — IAT-resolved via `iphlpapi.dll` in native-PE mode; pair with `stdlib/iphlp.k` |
| `bcrypt.krh` | Modern crypto (CNG) — SHA-256 / HMAC / AES / system RNG (BCryptOpenAlgorithmProvider, BCryptHash, BCryptGenRandom, BCryptEncrypt, BCryptDecrypt, ...) — IAT-resolved via `bcrypt.dll` in native-PE mode; pair with `stdlib/crypto.k` |
| `wininet.krh` | In-process HTTP / HTTPS client — InternetOpenA, InternetOpenUrlA, InternetReadFile, HttpQueryInfoA, InternetConnectA, HttpOpenRequestA, HttpSendRequestA — IAT-resolved via `wininet.dll` in native-PE mode; pair with `stdlib/httpc.k` (`httpGetUrl`, `httpGetUrlStatus`) for HTTPS without curl-spawn |
| `conio.krh` | _kbhit, _getch (Windows console) |

### Third-party / project-specific

| Header | Contents |
|--------|----------|
| `pcap.krh` | libpcap packet capture (Linux: `-lpcap`, Win: `-lwpcap`) |
| `fetcher.krh` | Internal — kryofetch C backend (`kfetch_api.h`) |

Usage: `import "headers/stdio.krh"` then call `printf("hello\n")` directly.
The C-emitter pipeline picks up the corresponding `#include` and emits a
matching FFI call. The native pipeline doesn't yet wire FFI — these headers
are C-path-only today.

---

## Built-in Functions (~150)

I/O, strings, math, lists, maps, structs, floats, exceptions, line operations, system, type utilities, StringBuilder, plus the env / boolean / reverse runtime added in 1.5.0 — see [docs/spec/functions.md](docs/spec/functions.md) for the full reference, with each entry tagged native / C-path.

---

**Krypton** — Copyright 2026 [t3m3d](https://github.com/t3m3d) — Apache 2.0
