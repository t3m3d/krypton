# Krypton

**A self-hosting programming language with a native compilation pipeline.**

> Version 1.4.0

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
![Version](https://img.shields.io/badge/version-1.4.0-brightgreen)

Krypton is a dynamically typed language with clean syntax, 147 built-in functions, and a compiler written in itself. It compiles to C for broad compatibility, and to native machine code via the **`--native`** backend (ELF on Linux, PE on Windows) — no external compiler in the critical path.

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

**Nothing.** Both Linux and Windows ship prebuilt seed binaries in `bootstrap/`. `git clone` and run.

Optional:
- **GCC** — only if you want the C backend (`./kcc x.k > x.c && gcc x.c -o x -lm`) or to rebuild from source on a platform without a prebuilt seed.
- **clang / LLVM** — only for the `--llvm` backend.
- **TDM-GCC / MSYS2 mingw-w64** — only if you want a Windows from-source rebuild via `build_v141.bat`.

---

### Linux / WSL

One-line install (clones, builds, symlinks `kcc` into `/usr/local/bin`):

```bash
git clone https://github.com/t3m3d/krypton && cd krypton && ./install.sh
```

`./build.sh` picks one of two paths:

- **Prebuilt seed (no gcc required)**: if `bootstrap/kcc_seed_<os>_<arch>` exists for your platform (currently `linux_x86_64` ships in the repo), it's copied directly as `./kcc`. Pure `cp` — no compiler involved.
- **Source seed (gcc required)**: otherwise compiles `bootstrap/kcc_seed.c` (pre-generated C source of the self-hosting compiler) with gcc, then self-rebuilds via `compile.k`.

After install, native ELF compilation is **fully gcc-free** via the `--native` flag:

```bash
kcc.sh --native examples/hello.k -o hello
./hello                                 # static Linux ELF, no libc, no gcc
```

This pipeline (`compile.k → IR → kompiler/elf.k → x86-64 ELF`) emits direct Linux syscalls, no library dependencies.

**Builtins supported by the ELF backend:** `kp`, `printErr`, `toStr`, `toInt`, `length`, `len`, `split`, `range`, `arg`, `argCount`, `substring`, `sbNew`, `sbAppend`, `sbToString`, `readFile`, `writeFile`, `charCode`, `fromCharCode`, `isDigit`, `isAlpha`, `abs`, `exit`, `startsWith`, plus `s[i]` indexing. Tested with 23+ programs including `examples/fibonacci.k`. More builtins ship as the runtime grows.

The traditional C path still works as a fallback if you have gcc (`./kcc source.k > out.c && gcc out.c -o prog -lm`).

### macOS

```bash
git clone https://github.com/t3m3d/krypton && cd krypton && ./build.sh
```

`./build.sh` falls through to the source-seed path (no prebuilt macOS binary ships yet) and compiles `bootstrap/kcc_seed.c` with whatever C compiler is installed — gcc, or clang if gcc isn't available. Either works.

**Compile-and-run:**

```bash
./kcc.sh hello.k -o hello       # uses clang/gcc — produces a Mach-O binary
./hello
```

**`--native` falls back to clang on macOS for now.** A standalone Mach-O backend ([kompiler/macho.k](kompiler/macho.k)) is in early skeleton form — emits a hello-world binary for both `x86_64` and `arm64` (Apple Silicon), but doesn't yet parse user IR. To validate the format works on your Mac:

```bash
./verify_macho.sh             # auto-detects host arch; runs codesign + executes
./verify_macho.sh --both      # try both x86_64 and arm64
```

Until the Mach-O backend handles full IR, `kcc.sh --native` on macOS prints a warning and routes through the C path.

**Requirements on macOS:** Xcode Command Line Tools (`xcode-select --install`) provide `clang` and `codesign`. That's all you need.

---

### Windows

```
git clone https://github.com/t3m3d/krypton
cd krypton
bootstrap.bat
```

`bootstrap.bat` copies the prebuilt binaries (`kcc.exe`, `optimize_host.exe`, `x64_host.exe`) from `bootstrap/` into place. **No C compiler required.**

For a from-source rebuild (with new icon, version bump, etc.), use `build_v141.bat` instead — that requires [TDM-GCC](https://jmeubank.github.io/tdm-gcc/) (or MSYS2 mingw-w64).

Native PE compilation (no gcc):
```
kcc.sh --native hello.k -o hello.exe
```

LLVM IR backend (optional):
```
winget install LLVM.LLVM
kcc.sh --llvm hello.k -o hello.ll
clang hello.ll -o hello.exe
```

---

### Write a program

```
// hello.k
just run {
    kp("Hello from Krypton!")
}
```

### Compile to a native binary (recommended — no gcc)

**Linux:**
```bash
kcc.sh --native hello.k -o hello
./hello                            # static ELF, direct syscalls, no libc
```

Emits ELF64 directly via [kompiler/elf.k](kompiler/elf.k). Static binary, calls Linux syscalls (`SYS_write`, `SYS_mmap`, `SYS_exit`) directly, no libc, no dynamic linker.

**Windows:**
```
kcc.sh --native hello.k -o hello.exe
```

Emits PE/COFF directly via [kompiler/x64.k](kompiler/x64.k). The `.exe` imports only `kernel32.dll` (via `runtime/krypton_rt.dll`).

### Compile to C (fallback — requires gcc)

**Linux / macOS:**
```bash
./kcc hello.k > hello.c
gcc hello.c -o hello -lm
./hello
```

**Windows:**
```
kcc.exe hello.k > hello.c
gcc hello.c -o hello.exe -lm
hello.exe
```

### Compile via LLVM IR (optional — requires clang)

```
kcc.sh --llvm hello.k -o hello.ll
clang hello.ll -o hello       # or hello.exe on Windows
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

```
source.k
    │
    ├─ Native ELF backend (Linux, no gcc, no libc):
    │      kcc.sh --native source.k -o source
    │
    │      source.k → .kir → .kir (opt) → x86-64 ELF → source
    │      (direct syscalls, static binary)
    │
    ├─ Native PE backend (Windows, no gcc):
    │      kcc.sh --native source.k -o source.exe
    │
    │      source.k → .kir → .kir (opt) → x64 PE → source.exe
    │      (uses runtime/krypton_rt.dll, kernel32-only)
    │
    ├─ C backend (fallback, requires gcc):
    │      kcc source.k > source.c
    │      gcc source.c -o source -lm
    │
    └─ LLVM IR backend (optional, requires clang):
           kcc.sh --llvm source.k -o source.ll
           clang source.ll -o source

           source.k → .kir → .kir (opt) → .ll → object → binary
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
├── kompiler/
│   ├── compile.k          # Self-hosting compiler (4,735 lines)
│   ├── optimize.k         # IR optimizer (335 lines)
│   ├── x64.k              # Native PE/COFF backend, Windows (5,274 lines)
│   ├── elf.k              # Native ELF64 backend, Linux (2,207 lines)
│   ├── llvm.k             # LLVM IR backend (441 lines)
│   └── run.k              # Interpreter (2,084 lines)
├── runtime/
│   ├── krypton_rt.k       # Krypton runtime (Phase 2 — self-hosted)
│   └── krypton_rt.dll     # Windows bootstrap runtime (kernel32-only, hand-emitted by x64.k)
├── bootstrap/                              # Cold-start prebuilts — no compiler needed to install
│   ├── kcc_seed.c                          # Pre-generated C source of compile.k (fallback)
│   ├── kcc_seed_linux_x86_64               # Prebuilt Linux kcc ELF
│   ├── elf_host_linux_x86_64               # Prebuilt Linux ELF emitter
│   ├── kcc_seed_windows_x86_64.exe         # Prebuilt Windows kcc PE
│   ├── x64_host_windows_x86_64.exe         # Prebuilt Windows PE emitter
│   └── optimize_host_windows_x86_64.exe    # Prebuilt IR optimizer
├── stdlib/                # Standard library modules
├── examples/              # Example programs
├── headers/               # .krh module headers
├── tests/                 # Test suite
├── assets/                # Windows icon resource (krypton_rc.o)
├── versions/              # Historical bootstrap binaries
├── build.sh               # Linux/macOS/WSL build (uses prebuilt seed when available)
├── bootstrap.bat          # Windows install (copies prebuilt binaries from bootstrap/)
├── build_v141.bat         # Windows from-source rebuild (requires TDM-GCC)
├── install.sh             # Linux install (build + symlink to /usr/local/bin)
├── Makefile               # Cross-platform make wrapper around build scripts
├── CHANGELOG.md           # Full version history
├── RELEASE_NOTES_*.md     # Per-release notes
├── Spec.md                # Language specification
└── LICENSE                # Apache 2.0
```

---

## Bootstrap

Krypton solves the self-hosting chicken-and-egg problem by shipping prebuilt seed binaries in `bootstrap/`. A fresh clone needs **no compiler** to install on either Linux or Windows.

**Linux / WSL:** `build.sh` copies `bootstrap/kcc_seed_linux_x86_64` directly as `./kcc` — pure `cp`, no gcc invoked. Falls back to compiling `bootstrap/kcc_seed.c` with gcc only if the prebuilt is missing for the host platform (e.g., aarch64). After that, `kcc.sh --native` uses `bootstrap/elf_host_linux_x86_64` (the prebuilt ELF emitter), so the entire `--native` pipeline is gcc-free too.

**Windows:** `bootstrap.bat` copies `kcc_seed_windows_x86_64.exe`, `x64_host_windows_x86_64.exe`, and `optimize_host_windows_x86_64.exe` into place. `kcc.sh --native` uses those prebuilts directly. From-source rebuild (icon updates, version bumps) lives in `build_v141.bat` and requires TDM-GCC.

**macOS:** falls through to source-seed mode (no prebuilt yet). Requires gcc/clang.

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
