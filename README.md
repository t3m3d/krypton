# Krypton

**A self-hosting programming language that emits native machine code without a C compiler in the loop.**

> Version 1.4.0

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
![Version](https://img.shields.io/badge/version-1.4.0-brightgreen)

Krypton is a dynamically typed language with clean syntax, 147 built-in functions, and a compiler written in itself. The **default** compilation pipeline produces a native executable on every supported platform — no gcc, no clang, no external toolchain at user-invocation time:

| Platform | Backend | Output |
|----------|---------|--------|
| **Linux x86_64** | `compiler/linux_x86/elf.k` | Static ELF, direct syscalls, no libc |
| **Windows x86_64** | `compiler/windows_x86/x64.k` | PE/COFF, kernel32-only via `runtime/krypton_rt.dll` |
| **macOS arm64** | `compiler/macos_arm64/macho_arm64_self.k` | Mach-O with in-Krypton SHA-256 ad-hoc code signing |

C output (`--c`) and gcc-rebuild (`--gcc`, deprecated) remain as escape hatches but are not part of the normal flow.

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

**Nothing for end users.** All three supported platforms ship prebuilt seed binaries in `bootstrap/`. `git clone` and go.

| Platform | Files in `bootstrap/` | Compiler at install time |
|----------|----------------------|--------------------------|
| Linux x86_64 | `kcc_seed_linux_x86_64`, `elf_host_linux_x86_64`, `optimize_host_linux_x86_64` | none (pure copy) |
| Windows x86_64 | `kcc_seed_windows_x86_64.exe`, `x64_host_windows_x86_64.exe`, `optimize_host_windows_x86_64.exe` | none (pure copy) |
| macOS arm64 | `kcc_seed_macos_aarch64` | none (pure copy) |

**Optional, for development only:**
- **gcc** — one-time bootstrap if you edit `compiler/linux_x86/elf.k` or `compiler/windows_x86/x64.k` and need to rebuild a seed binary. End users never need it.
- **LLVM/clang** — only for the optional `--llvm` backend.
- **macOS Xcode CLT** — provides `xcrun` for the macOS arm64 self-build path. (Note: the macho_arm64_self.k pipeline emits Mach-O directly with in-Krypton SHA-256 ad-hoc signing — no clang or codesign invocation.)

---

### Linux / WSL

```bash
git clone https://github.com/t3m3d/krypton && cd krypton && ./install.sh
```

(or `./build.sh` for a non-installing build).

`./build.sh` copies `bootstrap/kcc_seed_linux_x86_64` directly as `./kcc-x64`. No compiler invoked. Smoke test runs `examples/fibonacci.k` through the native ELF pipeline:

```bash
kcc.sh hello.k                          # default native pipeline (no gcc)
./hello                                  # static ELF, direct syscalls, no libc
```

The pipeline is `compile.k → .kir → optimize.k → compiler/linux_x86/elf.k → ELF binary`.

### Windows x86_64

```
git clone https://github.com/t3m3d/krypton
cd krypton
bootstrap.bat
```

`bootstrap.bat` copies `kcc_seed_windows_x86_64.exe`, `x64_host_windows_x86_64.exe`, and `optimize_host_windows_x86_64.exe` from `bootstrap/` into place. No compiler required.

```
kcc.sh hello.k                          # default native pipeline (no gcc)
hello.exe                                # PE/COFF, kernel32-only
```

The pipeline is `compile.k → .kir → optimize.k → compiler/windows_x86/x64.k → PE/COFF`. Output exes import only `kernel32.dll` via the bundled `runtime/krypton_rt.dll`.

For a from-source rebuild of the seed binaries, `build_v141.bat` uses [TDM-GCC](https://jmeubank.github.io/tdm-gcc/) or MSYS2 mingw-w64. End users don't need it.

### macOS arm64

```bash
git clone https://github.com/t3m3d/krypton && cd krypton && ./build.sh
```

The macOS pipeline is `compile.k → .kir → compiler/macos_arm64/macho_arm64_self.k → Mach-O`. The Krypton-side emitter writes the entire Mach-O — load commands, `__TEXT`/`__DATA`/`__LINKEDIT`, chained fixups — and the SHA-256 ad-hoc code signature, all in Krypton. **No clang, no `as`, no `ld`, no external `codesign` invocation.**

```bash
kcc.sh hello.k -o hello                  # default: native arm64 Mach-O
./hello
```

`./verify_macho_self.sh` runs the end-to-end self-emitted Mach-O smoke tests.

Why this differs in implementation from Linux/Windows: macOS Tahoe+ AMFI rejects unsigned and improperly-formatted Mach-Os, so the emitter has to produce a properly chained-fixups dyld-linked binary AND embed a valid code signature. Both happen in pure Krypton.

---

### Write a program

```
// hello.k
just run {
    kp("Hello from Krypton!")
}
```

### Compile to a native binary (default)

```bash
kcc.sh hello.k                # produces ./hello (Linux/macOS) or ./hello.exe (Windows)
./hello
```

Per-platform pipeline (chosen automatically):

- **Linux** — emits ELF64 directly via [compiler/elf.k](compiler/elf.k). Static binary, direct syscalls, no libc, no dynamic linker.
- **Windows** — emits PE/COFF directly via [compiler/x64.k](compiler/x64.k). Imports only `kernel32.dll` (via `runtime/krypton_rt.dll`).
- **macOS** — emits assembly via [compiler/macho.k](compiler/macho.k); `clang` assembles + links + signs into a Mach-O. (Tahoe AMFI rejects hand-rolled static binaries — clang produces a properly dyld-linked binary the kernel will accept.)

### Other compilation modes (opt-in)

```bash
kcc.sh --c hello.k                       # emit C source to stdout (debug/porting aid)
kcc.sh --c hello.k -o hello.c            # emit C source to a file
kcc.sh --llvm hello.k -o hello.ll        # emit LLVM IR; pair with `clang hello.ll -o hello`
kcc.sh --ir hello.k                      # emit Krypton IR (.kir) to stdout

# DEPRECATED — emits a deprecation warning. Removed once each platform's
# native rebuild fully replaces gcc in the lazy-rebuild fallback.
kcc.sh --gcc hello.k                     # route through C+gcc internally
```

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
```

Annotations are parsed and discarded — they document intent for humans and future tooling.

### Functions

```
func greet(name) {
    emit "Hello, " + name + "!"
}

just run {
    kp(greet("World"))
}
```

`emit` (or `return`) returns a value. `just run` is the program entry point.

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

### Floats

```
let result = fadd("3.14", "2.72")
kp(fformat(result, "2"))   // "5.86"
```

Float builtins: `fadd`, `fsub`, `fmul`, `fdiv`, `fsqrt`, `ffloor`, `fceil`, `fround`, `fformat`, `flt`, `fgt`, `feq`

---

## Compilation Pipeline

The default `kcc.sh source.k` invocation produces a native binary using a Krypton-only emitter. No C compiler or linker is invoked at user-call time on any of the three supported platforms:

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
    ├─ --c:                       source.k → C source (stdout or -o file)
    │                             Debug aid / porting only. Pair with
    │                             `gcc out.c -o out -lm` to build manually.
    │
    ├─ --llvm:                    source.k → .kir → optimize.k →
    │                              compiler/llvm.k → .ll
    │                              Pair with `clang hello.ll -o hello`.
    │
    └─ --gcc (DEPRECATED):        source.k → C source → gcc → native binary
                                  Emits a deprecation warning. Will be removed.
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

35 modules in `stdlib/`:

| Module | Contents |
|--------|----------|
| `math_utils.k` | gcd, lcm, isPrime, fibonacci, factorial, sqrt, abs, power |
| `result.k` | ok/err/isOk/isErr/unwrap/unwrapErr/unwrapOr |
| `option.k` | optSome/optNone/isSome/isNone/optUnwrap |
| `json.k` | jsonStr/jsonBool/jsonArray/jsonObject/jsonNull |
| `float_utils.k` | floatAdd/floatMul/floatSqrt/floatFormat/pi() |
| `string_utils.k` | String manipulation helpers |
| `list_utils.k` | List processing functions |
| ... | 29 more modules |

---

## Project Structure

```
krypton/
├── compiler/
│   ├── compile.k                  # Self-hosting frontend
│   ├── optimize.k                 # IR optimizer
│   ├── llvm.k                     # LLVM IR backend (optional)
│   ├── run.k                      # Interpreter
│   ├── linux_x86/elf.k            # Linux x86_64 ELF emitter
│   ├── windows_x86/x64.k          # Windows x86_64 PE/COFF emitter
│   └── macos_arm64/macho_arm64_self.k  # macOS arm64 Mach-O emitter (with signing)
├── runtime/
│   ├── krypton_rt.k       # Krypton runtime (Phase 2 — self-hosted)
│   └── krypton_rt.dll     # Windows bootstrap runtime (kernel32-only, hand-emitted by x64.k)
├── bootstrap/                                # Prebuilt seeds — pure-copy install, no compiler
│   ├── kcc_seed.c                            # Pre-generated C source of compile.k (development fallback)
│   ├── kcc_seed_linux_x86_64                 # Linux kcc ELF
│   ├── elf_host_linux_x86_64                 # Linux ELF emitter
│   ├── optimize_host_linux_x86_64            # Linux IR optimizer
│   ├── kcc_seed_windows_x86_64.exe           # Windows kcc PE
│   ├── x64_host_windows_x86_64.exe           # Windows PE/COFF emitter
│   ├── optimize_host_windows_x86_64.exe      # Windows IR optimizer
│   ├── kcc_seed_macos_aarch64                # macOS arm64 kcc Mach-O
│   ├── REBUILD_SEED.md                       # How/when to rebuild seeds
│   └── sanitize_ir.py                        # IR pre-processor used during seed bootstrap
├── stdlib/                # Standard library modules
├── examples/              # Example programs
├── headers/               # .krh module headers
├── tests/                 # Test suite
├── assets/                # Windows icon resource (krypton_rc.o)
├── versions/              # Historical bootstrap binaries
├── build.sh               # Linux/macOS/WSL build (uses prebuilt seed when available)
├── bootstrap.bat          # Windows install (copies prebuilt binaries from bootstrap/)
├── build_v141.bat         # Windows from-source rebuild (requires TDM-GCC, dev only)
├── install.sh             # Linux install (build + symlink to /usr/local/bin)
├── kcc.sh                 # Compiler driver (dispatches to per-platform native emitter)
├── Makefile               # Cross-platform make wrapper around build scripts
├── CHANGELOG.md           # Full version history
├── RELEASE_NOTES_*.md     # Per-release notes
├── Spec.md                # Language specification
└── LICENSE                # Apache 2.0
```

---

## Bootstrap

Krypton solves the self-hosting chicken-and-egg problem by shipping prebuilt seed binaries in `bootstrap/` for every supported platform. A fresh clone needs **no compiler** to install.

**End-user install (no compiler on any platform):**

| Platform | Install command | What it does |
|----------|-----------------|--------------|
| Linux x86_64 | `./build.sh` | `cp bootstrap/kcc_seed_linux_x86_64 ./kcc-x64`, copies elf_host + optimize_host into place, smoke-tests fibonacci |
| Windows x86_64 | `bootstrap.bat` | copies `kcc_seed_*.exe`, `x64_host_*.exe`, `optimize_host_*.exe` |
| macOS arm64 | `./build.sh` | `cp bootstrap/kcc_seed_macos_aarch64 ./kcc-arm64` (M1/M2/M3) |

Pure `cp` — no compiler invoked at install. After that, `kcc.sh source.k` runs the platform's native emitter end-to-end with no C tools.

**Re-seeding (developer-only, one-time gcc bootstrap):**

If you edit `compiler/<platform>/<emitter>.k` you may need to rebuild the seed. The exact steps live in [bootstrap/REBUILD_SEED.md](bootstrap/REBUILD_SEED.md). Linux currently still needs gcc once for this; the path to dropping it entirely (a pure-Krypton self-bootstrap of `elf.k`) is documented there.

The compiler has been self-hosting since the v0.1 series. Historical bootstrap binaries live in `versions/`.

---

## Native Headers (.krh)

Seven headers ship in `headers/`:

| Header | Contents |
|--------|----------|
| `windows.krh` | Win32 system info, registry, console |
| `stdio.krh` | C stdio — printf, fopen, fread |
| `math.krh` | libm — sin, cos, sqrt, pow |
| `string.krh` | C strings — strlen, strcpy, strstr |
| `winsock.krh` | TCP/UDP networking (Winsock2) |
| `process.krh` | Process and thread management |
| `fileio.krh` | Windows file I/O — CreateFile, ReadFile |

Usage: `import "headers/windows.krh"` then call functions directly.

---

## Built-in Functions (147)

I/O, strings, math, lists, maps, structs, floats, exceptions, line operations, system, type utilities, StringBuilder — see [Spec.md](Spec.md) for the full reference.

---

**Krypton** — Copyright 2026 [t3m3d](https://github.com/t3m3d) — Apache 2.0
