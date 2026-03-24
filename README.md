# Krypton

**A self-hosting programming language with a native compilation pipeline.**

> Version 1.0.0 — The language is complete. The compiler is self-hosting. Native compilation via LLVM is working.

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
![Version](https://img.shields.io/badge/version-1.0.0-brightgreen)

Krypton is a dynamically typed language with clean syntax, 147 built-in functions, and a compiler written in itself. It compiles to C for broad compatibility, and to native machine code via LLVM for maximum performance — no GCC in the critical path.

```
jxt {
    k "stdlib/math_utils.k"
}

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

- **GCC** (or any C99 compiler) — for all platforms
- **LLVM / clang** (optional) — for native compilation via `build_llvm.bat` / `make native`

---

### Linux / macOS

```bash
git clone https://github.com/t3m3d/krypton
cd krypton
chmod +x build.sh
./build.sh
```

This bootstraps a native `kcc` binary from source in four steps:
1. Compiles the C interpreter (`archive/c/run.c`) with GCC
2. Uses that interpreter to compile the self-hosting compiler (`kompiler/compile.k`) to C
3. Compiles the resulting C to a fast native `kcc` binary
4. Builds the IR optimizer and LLVM backend

Or use `make`:

```bash
make              # build everything
make run F=hello.k   # compile + run a file
make test         # run the test suite
```

---

### Windows

```
git clone https://github.com/t3m3d/krypton
cd krypton
build_v100.bat
```

Requires [TDM-GCC](https://jmeubank.github.io/tdm-gcc/). For native LLVM compilation:

```
winget install LLVM.LLVM
build_llvm.bat hello.k
```

---

### Write a program

```
// hello.k
just run {
    kp("Hello from Krypton!")
}
```

### Compile to C (all platforms)

**Linux / macOS:**
```bash
./kcc hello.k > hello.c
gcc hello.c -o hello -lm
./hello
```

**Windows:**
```
kcc_v100.exe hello.k > hello.c
gcc hello.c -o hello.exe -lm
hello.exe
```

### Compile to native via LLVM

**Linux / macOS:**
```bash
make native F=hello.k
```

**Windows:**
```
.\build_llvm.bat hello.k
hello_llvm.exe
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

```
jxt {
    k "stdlib/result.k"
    k "stdlib/math_utils.k"
    c "windows.h"
}
```

- `k` — Krypton module (full source inlined at compile time)
- `c` — C header (emits `#include` in generated C)
- `t` — alias for `c` (family initial)

The legacy `import` keyword still works.

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
    ├─ C backend (default):
    │      kcc source.k > source.c
    │      gcc source.c -o source.exe -lm
    │
    └─ LLVM native backend:
           .\build_llvm.bat source.k
           
           source.k → .kir → .kir (opt) → .ll → .o → source_llvm.exe
```

### Krypton IR

```
kcc_v098.exe --ir source.k > source.kir
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
│   ├── compile.k          # Self-hosting compiler (3,567 lines)
│   ├── optimize.k         # IR optimizer (348 lines)
│   ├── llvm.k             # LLVM IR backend (437 lines)
│   └── run.k              # Interpreter (2,092 lines)
├── runtime/
│   └── krypton_runtime.c  # C runtime for LLVM-compiled programs
├── stdlib/                # 35 standard library modules
├── examples/              # Example programs
├── algorithms/            # Classic algorithm implementations
├── tutorial/              # Progressive tutorial
├── tests/                 # Test suite
├── assets/                # Icon and Windows resource
├── versions/              # Bootstrap chain binaries
├── Spec.md                # Language specification
├── CHANGELOG.md           # Full version history
└── LICENSE                # Apache 2.0
```

---

## Bootstrap Chain

```
kcc (C++) → v010 → v020 → v030 → v040 → v050 → v060
          → v070 → v071 → v072 → v075 → v077 → v080
          → v085 → v086 → v090 → v095 → v097 → v098
```

Each version compiled by the previous. The compiler has been self-hosting since v0.1.0.

---

## Built-in Functions (147)

I/O, strings, math, lists, maps, structs, floats, exceptions, line operations, system, type utilities, StringBuilder — see [Spec.md](Spec.md) for the full reference.

---

**Krypton** — Copyright 2026 [t3m3d](https://github.com/t3m3d) — Apache 2.0
