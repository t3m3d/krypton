# Changelog

All notable changes to the Krypton language and compiler.

## [1.4.0] - 2026-04-27

### macOS support — first-class baseline via the C path

`build.sh`, `kcc.sh`, and the README now treat macOS as a first-class target. Until a native Mach-O backend exists, macOS goes through the C path automatically with the right defaults.

- **`kcc.sh --native`** on macOS prints a warning and falls back to the C/clang path instead of silently producing non-runnable Linux ELF binaries.
- **`kcc.sh -o foo`** (default behaviour) routes through the C path on macOS, `--native` on Linux/Windows.
- **C compiler discovery**: `$CC` env var → `gcc` → `clang` → MinGW paths. macOS users with only Xcode Command Line Tools (`clang`) work out of the box.
- **`build.sh`** banner says "Linux / macOS / WSL"; success message recommends the right command per platform.
- README has a dedicated macOS section noting the C-path requirement.

Generated C is verified portable to clang (only standard headers; no Linux-only includes).

### New `jxt` syntax — bracketless

Imports can now be written without braces. Each line is `inc "path"`, and the file extension determines the include type (`.k` → Krypton module, `.h` / `.krh` → C header). The block ends at the first non-`inc` token.

**New (recommended):**

```
jxt
inc "stdlib/result.k"
inc "stdlib/math_utils.k"

just run { ... }
```

**Old (still supported):**

```
jxt {
    k "stdlib/result.k"
    k "stdlib/math_utils.k"
}
```

Implemented in [kompiler/compile.k](kompiler/compile.k)'s tokenizer — when `jxt` is followed by anything other than `{`, the tokenizer synthesizes the equivalent brace-form token stream (`LBRACE`, `ID:k|c`, `STR:path`..., `RBRACE`). Downstream parsing is unchanged.

### ELF Backend — 8 new builtins

Eight new hand-emitted machine-code routines extend the Linux native pipeline (and become available on macOS once Mach-O lands):

- **`printErr(s)`** — 37 B. Like `kp` but writes to fd 2 (stderr) via `SYS_write`.
- **`charCode(s)`** — 4 B. `MOVZX EAX, byte [RDI]; RET`. Returns the first byte as an integer.
- **`fromCharCode(n)`** — 23 B. Allocates 2 bytes, writes the byte + NUL, returns the pointer.
- **`exit(n)`** — 16 B. `SYS_exit(atoi(n))`. Does not return.
- **`isDigit(s)`** — 16 B. Returns 1 if first byte is `'0'`..`'9'`, else 0. Smart-int convention.
- **`isAlpha(s)`** — 19 B. `OR 0x20` + range check `'a'`..`'z'` (handles both cases).
- **`abs(n)`** — 14 B. `kr_atoi` + `TEST` + `JNS` + `NEG`.
- **`startsWith(s, prefix)`** — 27 B. Byte loop comparing prefix against s; returns 1/0.

### Builtins now supported by the ELF backend

`kp`, `printErr`, `toStr`, `toInt`, `length`, `len`, `split`, `range`, `arg`, `argCount`, `substring`, `sbNew`, `sbAppend`, `sbToString`, `readFile`, `writeFile`, `charCode`, `fromCharCode`, `isDigit`, `isAlpha`, `abs`, `exit`, `startsWith`, plus `s[i]` indexing.

### Bug fix — `jxt { k "..." }` was infinite-looping

The `k` branch of compile.k's jxt-block parser ([kompiler/compile.k:4184](kompiler/compile.k#L4184)) was missing the `jxtPos += 2` advance that the `c` and `t` branches had. Any program using `jxt { k "..." }` would hang in kcc forever. Discovered while testing the new bracketless syntax. The `--ir`, default C, and `--native` paths were all affected. Fixed.

### Verification

All 23 ELF regression programs still pass. New test groups: 4 jxt syntax tests, 4 batch-1 builtin tests (printErr, charCode, fromCharCode, exit), 4 batch-2 builtin tests (isDigit, isAlpha, abs, startsWith). macOS C-path verified end-to-end via simulated `uname -s = Darwin` in WSL. Self-host clean: byte-identical C output between old and new kcc.

## [1.3.9] - 2026-04-26

### Linux Native ELF Backend — Complete

A full standalone ELF emitter (`kompiler/elf.k`, ~2100 lines) ships native Linux x86-64 binaries with **no gcc, no libc, no external runtime**. Direct `syscall` instructions for `SYS_write`, `SYS_mmap`, `SYS_exit`. Static `PT_LOAD` segment with hand-emitted ELF64 header.

```
kcc.sh --native examples/hello.k -o hello
./hello                                 # static Linux ELF, no libc, no gcc
```

**Runtime functions (all hand-emitted machine code):**
- `kr_print` (37 B), `kr_alloc` (7 B), `kr_strlen` (14 B)
- `kr_str_int` (91 B itoa), `kr_atoi` (73 B with smart-int passthrough)
- `kr_concat` (118 B with int→string preamble)
- `kr_length` (28 B), `kr_split` (113 B), `kr_range` (135 B)
- `kr_index` (36 B) — string indexing `s[i]`
- `kr_argcount` (7 B), `kr_arg` (17 B) — command-line args via `argCount()` / `arg(i)`

**Smart value dispatch:** values < `0x400000` are integers, ≥ `0x400000` are string pointers. ADD, kp, and concat all check at runtime and route accordingly.

**`_start` (81 bytes):** captures argc/argv from the stack, mmaps a 64KB heap, stashes argc/argv as globals at heap[0..15], sets `R14`=globals base / `R15`=bump pointer, calls `__main__`, runs `kr_atoi` on the return value, then `SYS_exit`.

**23/23 regression programs verified** via `kcc.sh --native` on Linux: hello, math, combo, mul, cond, loop, divtest, userfn, recursion, fib, tostr, print_calc, fib_print, edge, concat, toint, indextest, argtest + 5 examples (hello, functions, test_basic, test_loop, fibonacci).

`examples/fibonacci.k` produces a 1693-byte static ELF that prints the first 20 Fibonacci numbers.

### Both Platforms — gcc-Free Bootstrap

The `bootstrap/` directory now ships prebuilt host binaries for both Linux and Windows. No C compiler is required for clone-build-run on either platform.

| File | OS | Purpose |
|---|---|---|
| `kcc_seed_linux_x86_64` | Linux | the kcc compiler ELF (280K) |
| `elf_host_linux_x86_64` | Linux | --native ELF emitter (146K) |
| `kcc_seed_windows_x86_64.exe` | Windows | the kcc compiler PE (820K) |
| `x64_host_windows_x86_64.exe` | Windows | --native PE emitter (672K) |
| `optimize_host_windows_x86_64.exe` | Windows | IR optimizer (388K) |

**Linux** — `./build.sh` copies `bootstrap/kcc_seed_linux_x86_64` directly when present. Falls back to compiling `bootstrap/kcc_seed.c` with gcc only when the prebuilt is missing for the host platform. Verified gcc-free with `PATH=/usr/bin:/bin CC=nonexistent ./build.sh`.

**Windows** — new `bootstrap.bat` copies all three Windows prebuilts into place. `kcc.sh`'s `--native` Windows path also auto-restores `x64_host.exe` and `optimize_host.exe` from prebuilts when missing, eliminating gcc from the runtime path.

**Updates:**
- `.gitignore` — added `!bootstrap/*.exe` exception so Windows prebuilts are tracked
- `kcc.sh` — Linux + Windows `--native` paths both check for prebuilt seeds before invoking gcc
- `bootstrap.bat` — new file, Windows analog of `build.sh`'s prebuilt-install path
- `README.md` — Windows install section now points at `bootstrap.bat` (no compiler needed)

## [1.2.0] - 2026-04-22

### Native Pipeline — Memory Leak Fix

Eliminated two classes of memory leak that caused RAM exhaustion when compiling large programs with the native x64 backend (`kcc --native`).

**Fix A — StringBuilders in x64.k (O(N²) → O(N)):**

Replaced all string accumulation loops in the x64 code generator with `sbNew`/`sbAppend`/`sbToString` calls:
- IR cleanup loop (`clean` string built from all IR lines)
- Export name collection (`exportNames`)
- Function offset table (`allFuncOffsets`)
- Bootstrap export offset tracking (`bsOffsets`, `bsExportNames`)
- PE header builder functions (`emitDosHeader`, `emitPEHeader`, `emitSectionHeader`, `emitEntryPoint`)

Each of these previously did `s = s + chunk` in a loop — allocating a new copy of the entire string on every iteration and leaking the old one. For a large program with N IR instructions, this produced O(N²) allocations.

**Fix B — Arena allocator in native_rt.c:**

Replaced per-string `HeapAlloc` calls with a 64MB slab arena. All `kr_plus`, `kr_str`, `kr_substring`, and other string-returning functions now allocate from bump-pointer slabs instead of calling `HeapAlloc` per result. StringBuilder internal buffers (which need `HeapReAlloc`) are the only remaining `HeapAlloc` users.

Result: compiling large Krypton programs no longer exhausts RAM. Memory usage is bounded by the arena slab size (64MB) rather than growing with the square of program size.

## [1.1.9] - 2026-04-04

### Compiler — System Header Search Path (`--headers`)

The compiler now accepts a `--headers PATH` flag that adds a fallback directory for resolving `import` statements. When an import is not found relative to the source file, the compiler searches the headers directory before failing.

```
kcc.exe --headers C:/krypton/headers source.k
```

`kcc.sh` passes `--headers` automatically pointing to the `headers/` directory next to the compiler, so projects no longer need to bundle their own copy of the standard headers.

### kcc Driver — Automatic Header Discovery

`kcc.sh` now detects the `headers/` directory alongside the compiler and passes it automatically:

```bash
# Before: project needed its own headers/ folder
import "headers/windows.krh"

# After: just use the name — compiler finds it from install
import "windows.krh"
```

### headers — Synced and Updated

All standard headers updated to match the latest kryofetch definitions:

| Header | Changes |
|--------|---------|
| `windows.krh` | Added `SYSTEM_POWER_STATUS` struct; `-> UINT64/INT/DWORD/UINT/LONG/BOOL` return annotations on `GetTickCount64`, `GetSystemMetrics`, `GetLogicalDrives`, `GetCurrentProcessId`, `RegEnumKeyExA`, `Process32First/Next`; added `GetLogicalProcessorInformationEx` |
| `fileio.krh` | Added `WIN32_FIND_DATAA` struct; `GetFileAttributesA -> DWORD`; `FindNextFileA -> BOOL` |

---

## [1.1.7] - 2026-04-04

### Compiler — New Builtins (2)

| Builtin | Description |
|---------|-------------|
| `shellRun(cmd)` | Run a shell command, returns exit code as string |
| `deleteFile(path)` | Delete a file at `path`, returns empty string |

### Compiler — Bootstrap Aliases in Runtime

`cRuntime()` now emits `exec()`, `shellRun()`, and `deleteFile()` as non-prefixed alias functions alongside their `kr_` implementations. This ensures compatibility with older bootstrap compilers (e.g. `kcc_v103`) that emit bare function-pointer calls without the `kr_` prefix.

### kcc Driver — Single-Step Compilation (`kcc.sh`)

New bash driver `kcc.sh` wraps `kcc.exe` + `gcc` into a single command:

```
bash kcc.sh source.k -o output.exe [-lFOO ...]
```

- Without `-o`: passes through to `kcc.exe` (C to stdout, same as before)
- With `-o`: compiles Krypton → C → native `.exe` in one step
- Accepts `-l*`, `-L*`, `-W*` flags forwarded to `gcc`
- Accepts `--ir` flag forwarded to `kcc.exe`
- Automatically locates `gcc` from PATH or common Windows install locations (TDM-GCC, MinGW64, MSYS2)

---

## [1.1.6] - 2026-04-01

### Compiler — Offset Buffer Builtins (2 new)

New builtins for reading values at a byte offset inside a buffer — required for
iterating packed struct arrays returned by Win32 APIs like `PdhGetFormattedCounterArrayA`:

| Builtin | Description |
|---------|-------------|
| `bufGetDwordAt(buf, offset)` | Read `uint32` at byte offset, returns string |
| `bufGetQwordAt(buf, offset)` | Read `uint64` at byte offset, returns string |

Offsets are numeric strings and support full Krypton arithmetic expressions:
```
let off = toInt(i) * 24
let status = bufGetDwordAt(items, off + 8)
let val    = bufGetQwordAt(items, off + 16)
```

### Compiler — bufGetQword Builtin

New builtin `bufGetQword(buf)` reads a full 8-byte `uint64` from the start of a
buffer as a numeric string. Complements `bufGetDword` for 64-bit registry values
(`REG_QWORD`) and other 64-bit out-parameters.

### headers/windows.krh — PDH Support

`windows.krh` now includes `<pdh.h>` and declares the Performance Data Helper
APIs used for querying GPU and other hardware counters:

```
func PdhOpenQueryA(source, userdata, out) -> LONG
func PdhAddEnglishCounterA(query, path, userdata, out) -> LONG
func PdhCollectQueryData(query)
func PdhGetFormattedCounterArrayA(counter, format, bufSize, itemCount, items)
func PdhCloseQuery(query)
```

`PdhOpenQueryA` and `PdhAddEnglishCounterA` use `-> LONG` return annotations so
error codes are returned as numeric strings and can be checked with `toInt()`.

### headers/windows.krh — regHklmQword

New utility function `regHklmQword(path, name)` reads a `REG_QWORD` (64-bit)
value from `HKEY_LOCAL_MACHINE`. Uses `bufNew("8")` + `bufGetQword` internally.
Follows the same pattern as `regHklmDword` / `regHkcuDword`.

---

## [1.1.3] - 2026-03-31

### Compiler — Native Windows API Integer Returns

jxt function declarations now support a `-> TYPE` return annotation that
auto-generates a static C wrapper and `#define` redirect so integer-returning
Windows APIs can be called directly from Krypton without any C shim files.

```
jxt {
    c "windows.h"
    func GetTickCount64() -> UINT64
    func GetLogicalDrives() -> DWORD
    func GetSystemMetrics(index) -> INT
    func Process32First(snap, entry) -> BOOL
    func RegEnumKeyExA(key, idx, name, sz, r, cls, clsSz, lw) -> LONG
}
```

Supported return types: `INT`, `UINT`, `DWORD`, `LONG`, `BOOL`, `UINT64`, `ULONGLONG`

For integer types the compiler emits:
```c
static char* _krw_Func(char* _a0, ...) { return kr_itoa((int)Func(_a0, ...)); }
#define Func _krw_Func
```
For 64-bit types:
```c
static char* _krw_Func(void) { char _b[32]; snprintf(_b,32,"%llu",(unsigned long long)Func()); return kr_str(_b); }
#define Func _krw_Func
```

Args are passed as `char*` without truncating casts — 64-bit pointer safety preserved.
Works in both main-file and imported `.krh` jxt blocks.

### Compiler — Buffer & Handle Builtins (8 new)

New builtins for working with Windows out-parameter APIs directly from Krypton:

| Builtin | Description |
|---------|-------------|
| `bufNew(n)` | Allocate n-byte zeroed buffer, returns `char*` |
| `bufStr(buf)` | Read buffer as null-terminated string |
| `bufGetDword(buf)` | Read `uint32` from buffer, returns string |
| `bufSetDword(buf, val)` | Write `uint32` to buffer |
| `bufGetWord(buf)` | Read `uint16` from buffer, returns string |
| `handleOut()` | Allocate pointer-sized buffer for HANDLE out-params |
| `handleGet(buf)` | Dereference pointer buffer → HANDLE |
| `toHandle(n)` | Convert integer string to `(char*)(intptr_t)n` |

### Compiler — BYTE/UCHAR/BOOL Struct Fields

jxt struct declarations can now use `BYTE`, `UCHAR`, and `BOOL` field types.
Generated accessors read with `(unsigned char)` cast and write with `(BYTE)` cast.

```
struct SYSTEM_POWER_STATUS {
    field ACLineStatus       BYTE
    field BatteryLifePercent BYTE
    field BatteryLifeTime    DWORD
}
```

### kryofetch — Pure Krypton (zero exec/powershell)

All kryofetch modules now use native Windows API calls instead of `exec()`
or PowerShell subprocesses:

- **os.k** — `osver` via registry, `uptime` via `GetTickCount64`, `kfresolution`
  via `GetSystemMetrics`, `kftheme` via HKCU registry, `kfbattery` via
  `SYSTEM_POWER_STATUS`, `sysuser/syshost` via `GetUserNameA/GetComputerNameA`,
  `sysarch` via `SYSTEM_INFO`
- **cpu.k** — `cpubrand` via registry `ProcessorNameString`, `cpucores` via
  `SYSTEM_INFO.dwNumberOfProcessors`
- **disk.k** — `driveinfo` via `GetLogicalDrives() -> DWORD`
- **gpu.k** — `gpunames` via `RegEnumKeyExA` + registry `DriverDesc` keys
- **utils.k** — `regHklmStr`, `regHkcuStr`, `regHklmDword`, `regHkcuDword`
  pure Krypton registry helpers using `handleOut/handleGet/bufNew/bufSetDword/bufStr`
- **run.k** — `kfconsize` via `GetConsoleScreenBufferInfo`, `kfshell` via
  process tree walk with `CreateToolhelp32Snapshot` + `Process32First/Next`

### headers/windows.krh — Updated

- Added `SYSTEM_POWER_STATUS` struct (BYTE + DWORD fields)
- Added `-> TYPE` annotations on `GetTickCount64`, `GetSystemMetrics`,
  `GetLogicalDrives`, `GetCurrentProcessId`, `Process32First`, `Process32Next`,
  `RegEnumKeyExA`
- Added `GetSystemPowerStatus`, `GetConsoleMode`, `SetConsoleMode`,
  `CreateToolhelp32Snapshot`, `CloseHandle`

---

## [0.6.0] - 2026-03-14

### Language
- `for item in list { ... }` — for-in loop over comma-separated lists
- `do { ... } while cond` — do-while loop
- `match expr { val { } ... else { } }` — pattern matching
- `continue` statement in loops
- Compound assignment: `+=`, `-=`, `*=`, `/=`, `%=`
- `const` declarations: `const x = value`
- Ternary operator: `cond ? trueExpr : falseExpr` (nestable)

### Built-in Functions (30 new, 72 total)
- **Math:** `range`, `pow`, `sqrt`, `sign`, `clamp`
- **Strings:** `padLeft`, `padRight`, `charCode`, `fromCharCode`, `trim`, `toLower`, `toUpper`, `contains`, `endsWith`, `indexOf`, `replace`, `charAt`, `repeat`, `format`
- **Lists:** `append`, `join`, `reverse`, `sort`, `slice`, `length`, `unique`, `splitBy`, `listIndexOf`, `insertAt`, `removeAt`, `replaceAt`, `fill`, `zip`, `every`, `some`, `countOf`, `sumList`, `maxList`, `minList`
- **Conversion:** `hex`, `bin`, `parseInt`, `toStr`
- **I/O:** `printErr`, `readLine`, `writeFile`, `input`, `exit`

### Compiler
- Fixed `isKW` — `struct/class/type/try/catch/throw` were orphaned before keyword chain
- Fixed duplicate dead code block outside `compileStmt` (85 stray lines)
- Removed `defined()`/`not defined()` fake syntax from module scaffolding
- Clean module/import/export comment stubs
- Self-host verified

---

## [1.0.1] - 2026-03-25

### Compiler

- Fixed `\x` hex escape sequences not being handled in `expandEscapes()`.
  Previously `\x1b` (and any `\xNN`) would fall through to the `else` branch,
  emitting a literal backslash + `x` instead of the actual character. This
  caused any program using ANSI escape codes (e.g. `"\x1b[34m"`) to produce
  corrupted or empty output from the compiler.
- Bootstrap chain extended: ... -> v100 -> v101

---

## [1.1.0] - 2026-03-28

### Closures / Lambdas

Anonymous functions can now be assigned to variables and passed as arguments.

```
// Assign a lambda to a variable
let double = func(x) { emit toInt(x) * 2 + "" }
let add = func(a, b) { emit toInt(a) + toInt(b) + "" }

// Call it
kp(double("5"))      // 10
kp(add("3", "4"))    // 7

// Pass to higher-order functions
func applyTwice(f, x) { emit f(f(x)) }
let inc = func(x) { emit toInt(x) + 1 + "" }
kp(applyTwice(inc, "5"))   // 7
```

Implementation: lambdas compile to named static C functions (`_krlam_N`
where N is the token position) hoisted before the calling scope. The
variable holds a function pointer cast to `char*`. Calls are emitted as
indirect casts: `((char*(*)(char*,char*))fn)(args)`.

### New .krh Headers

Three new native headers ship with v1.1.0:

**`headers/winsock.krh`** — Windows networking (Winsock2)
- socket, bind, listen, accept, connect, send, recv
- getaddrinfo, WSAStartup/Cleanup, htons/ntohs
- Link with: `-lws2_32`

**`headers/process.krh`** — Process and thread management
- CreateProcess, WaitForSingleObject, CreateThread
- Sleep, GetCurrentProcessId, ShellExecuteA

**`headers/fileio.krh`** — Windows file I/O
- CreateFile, ReadFile, WriteFile, FindFirstFile/FindNextFile
- CreateDirectory, GetCurrentDirectory, GetTempPath

---

## [1.1.0] - 2026-03-28

### Closures / Lambdas

Anonymous functions are now first-class values.

```
let double = func(x) { emit toInt(x) * 2 + "" }
let add = func(a, b) { emit toInt(a) + toInt(b) + "" }

kp(double("5"))          // 10
kp(add("3", "4"))        // 7

func applyTwice(f, x) { emit f(f(x)) }
kp(applyTwice(double, "3"))   // 12
```

True closures capture outer variables:

```
func makeAdder(n) {
    emit func(x) { emit toInt(x) + toInt(n) + "" }
}

let add5 = makeAdder("5")
kp(add5("3"))    // 8
kp(add5("10"))   // 15
```

Implementation: a pre-scan pass walks all tokens before compilation
and compiles any `func`/`fn` that appears after `=`, `(`, `,`, `emit`,
or `return` into a named static C function (`_krlam_N`). These are
emitted at file scope before all user functions. The lambda expression
compiles to a function pointer `(char*)&_krlam_N`. Both the first and
second compilation passes skip lambda tokens, treating them as
expressions rather than declarations.

### New .krh Headers

**`headers/winsock.krh`** — Winsock2 TCP/UDP networking
- socket, bind, listen, accept, connect, send, recv
- getaddrinfo, WSAStartup/Cleanup, htons/ntohs
- Link: `-lws2_32`

**`headers/process.krh`** — Process and thread management
- CreateProcess, WaitForSingleObject, CreateThread
- Sleep, GetCurrentProcessId, ShellExecuteA

**`headers/fileio.krh`** — Windows file I/O
- CreateFile, ReadFile, WriteFile, FindFirstFile/FindNextFile
- CreateDirectory, GetCurrentDirectory, GetTempPath

---

## [1.0.3] - 2026-03-28

### Bug Fix — Struct + jxt hang resolved

The long-standing bug where a file containing both a `struct` declaration
and a `jxt` block caused the compiler to hang is now fixed.

**Root cause:** `scanFunctions` — which builds the function table before
compilation begins — was not skipping `jxt` blocks. When it encountered
`func` declarations inside a `jxt` block (as used in `.krh` header files),
it recorded them with a bogus `bodyStart` position pointing into the middle
of the jxt block. This corrupted the function table and caused the struct
compiler to enter an infinite loop when resolving field positions.

**Fix:** Added a `jxt` block skip to `scanFunctions` so it treats `jxt`
blocks the same way the first and second passes do — skip the entire block
and move on.

**Verified:** `test_struct_jxt.k` (struct + jxt + field access) now
compiles and runs correctly, printing `10`.

---

## [1.0.2] - 2026-03-27

### Native .krh Header System

Krypton programs can now declare and call external C functions directly
using `jxt { func ... }` syntax inside `.krh` header files — no C shim
files required.

```
import "headers/windows.krh"

just run {
    let ticks = GetTickCount64()
    kp("Uptime ms: " + ticks)
}
```

Four built-in headers ship with v1.0.2: `windows.krh`, `stdio.krh`,
`math.krh`, and `string.krh`.

### Bug Fixes

- **jxt import hang** — `compileImportedFunctions` was attempting to
  compile `func` declarations inside imported jxt blocks as Krypton
  function bodies, producing invalid C. Fixed with `else if` branching.
- **debug printErr** — removed leftover `printErr("DEBUG struct: ...")`
  from the second-pass struct compiler.

---

## [1.0.0] - 2026-03-23

### Krypton 1.0.0

The language is complete. The compiler is self-hosting. Native compilation
via LLVM is working. This is the first stable release.

**What ships in 1.0.0:**

Language features:
- Variables, constants, functions, structs, modules
- Optional type annotations on all declarations
- String interpolation with backtick syntax
- All control flow: if/else, while, for-in, do-while, match, break, continue
- Try/catch/throw with setjmp/longjmp
- Ternary operator, compound assignment, list literals
- Float arithmetic (fadd/fsub/fmul/fdiv/fsqrt/fformat)
- Float literals (3.14 tokenizes correctly)
- jxt { } block for unified imports and C headers

Compiler:
- Self-hosting: the compiler is written in Krypton and compiles itself
- C backend: kcc source.k > source.c && gcc source.c -o source.exe
- IR backend: kcc --ir source.k > source.kir
- LLVM backend: build_llvm.bat source.k -> native binary
- 91 compiler functions, 147 kr_ builtins, 3,539 lines

Standard library: 35 modules including result, option, json,
math_utils, float_utils, string_utils, list_utils

IR optimizer: 6 passes (dead code, constant folding, strength
reduction, store/load elimination, empty jump removal, unused locals)

LLVM backend: alloca-based stack, opaque pointer mode, per-function
string constants, implicit fallthrough br, builtin name mapping

Bootstrap chain:
kcc (C++) -> v010 -> v020 -> v030 -> v040 -> v050 -> v060
          -> v070 -> v071 -> v072 -> v075 -> v077 -> v080
          -> v085 -> v086 -> v090 -> v095 -> v097 -> v098 -> v100

**Known issues in 1.0.0:**
- Struct + jxt in the same file causes a hang during compilation.
  Workaround: use `import` instead of `jxt k` when the file also has structs.
  Fix planned for v1.0.1.

---

## [0.9.8] - 2026-03-23

### LLVM Backend

Krypton now compiles to native machine code via LLVM IR.

**New file: `kompiler/llvm.k`** — 437-line Krypton program that reads
`.kir` files and emits LLVM IR (`.ll`). Key design decisions:

- **Opaque pointer mode** — uses `ptr` throughout, compatible with LLVM 15+
- **Alloca-based virtual stack** — 32 pre-allocated `alloca ptr` slots per
  function, avoiding all SSA value lifetime issues across basic blocks
- **Per-function string globals** — string constants named `@kp_funcname_N`
  to avoid cross-function naming conflicts
- **Implicit fallthrough** — `lastWasTerm` flag ensures every basic block
  ends with a terminator before the next label
- **Builtin name mapping** — `kp` → `kr_kp`, `toInt` → `kr_toInt` etc.

**New file: `runtime/krypton_runtime.c`** — standalone C runtime for
LLVM-compiled programs. Provides all `kr_` functions without the embedded
cRuntime string. Compile once with gcc, link against any Krypton binary.

**New file: `build_llvm.bat`** — full native compilation pipeline:

    .uild_llvm.bat source.k
    -> source.kir -> source_opt.kir -> source.ll -> source_llvm.exe

**Verified output for `test_ir.k`:**
```
7
120
loop: 0
loop: 1
loop: 2
```

---

## [0.9.7] - 2026-03-22

### Language — jxt Block

New header/import declaration block using family initials j, x, t:

    jxt {
        c "stdio.h"
        c "math.h"
        k "stdlib/result.k"
        k "stdlib/math_utils.k"
        t "windows.h"
    }

Language tags:
- `k` — Krypton module (same as existing `import` keyword)
- `c` — C system header, emits `#include <name>` in generated C
- `t` — alias for `c` (family initial, same behavior)
- Future: `cpp`, `asm`, `llvm` for other backends

The `jxt` block is processed before function compilation. The old
`import` keyword still works for backward compatibility.

### Compiler
- `jxt` added to `isKW`
- Import loop handles `KW:jxt` blocks, processing each entry by language tag
- Both passes skip `jxt` blocks cleanly via `skipBlock`
- `k` entries use full path resolution (relative to source + cwd fallback)
- `c`/`t` entries with path separators use `"name"`, others use `<name>`
- Self-host verified with kcc_v095.exe

---

## [0.9.5] - 2026-03-22

### IR Optimizer

New program: `kompiler/optimize.k` — reads .kir files, applies six
optimization passes, writes optimized .kir to stdout.

Pipeline: `kcc --ir file.k > file.kir && kcc kompiler/optimize.k file.kir > opt.kir`

Passes:
- Dead code elimination — removes instructions after RETURN/JUMP
- Constant folding — PUSH 3 / PUSH 4 / ADD -> PUSH 7
- Strength reduction — removes x+0, x*1, x-0
- STORE/LOAD elimination — STORE x / LOAD x -> STORE x
- Empty jump removal — JUMP x / LABEL x -> LABEL x
- Unused local removal — drops unreferenced LOCAL declarations

Stats printed to stderr: `; optimizer: 87 -> 61 instructions (26 removed)`

---

## [0.9.0] - 2026-03-22

### Krypton IR

New mode: `kcc --ir file.k > file.kir`

Emits .kir (Krypton Intermediate Representation) — a stack-based
text instruction set, one instruction per line, human-readable.

Instruction set: PUSH LOAD STORE LOCAL POP FUNC PARAM CALL BUILTIN
RETURN END ADD SUB MUL DIV MOD NEG NOT CAT EQ NEQ LT GT LTE GTE
JUMP JUMPIF JUMPIFNOT LABEL STRUCTNEW GETFIELD SETFIELD INDEX
TRY ENDTRY THROW BREAK CONTINUE

All language features produce correct IR: if/else, while, for-in,
match, do-while, try/catch/throw, structs, interpolation, list literals.

25 new functions added to compile.k for IR emission.
compile.k: 91 functions, 3492 lines.

---

## [0.8.6] - 2026-03-17

### Bug Fix — Struct + Import
Top-level struct declarations in files that also use `import` now compile
correctly. The second pass was using `pairPos` on the struct compiler's output
to advance past the struct body — but `pairPos` finds the last comma in the
entire output string, which is unreliable when the generated C code contains
commas. Fixed by using `skipBlock` to advance past the struct body directly
from the token stream, bypassing the C code output entirely. The first pass
now also emits a forward declaration for the struct's constructor function.

### Float Support

Floating-point literals now tokenize correctly:

    let pi = 3.14159
    let e = 2.71828

Float arithmetic functions (all take and return float strings):

| Function | Description |
|----------|-------------|
| `fadd(a, b)` | Float addition |
| `fsub(a, b)` | Float subtraction |
| `fmul(a, b)` | Float multiplication |
| `fdiv(a, b)` | Float division |
| `fsqrt(a)` | Square root |
| `ffloor(a)` | Floor |
| `fceil(a)` | Ceiling |
| `fround(a)` | Round |
| `fformat(a, decimals)` | Format to N decimal places |
| `flt(a, b)` | Float less-than comparison |
| `fgt(a, b)` | Float greater-than comparison |
| `feq(a, b)` | Float equality comparison |
| `toFloat(s)` | Convert string to float (identity) |

Generated C uses `atof`, `snprintf`, and `math.h`. Link with `-lm`.

### New Stdlib Module
- `stdlib/float_utils.k` — float arithmetic wrappers: `floatAdd`, `floatSub`,
  `floatMul`, `floatDiv`, `floatSqrt`, `floatFloor`, `floatCeil`, `floatRound`,
  `floatFormat`, `floatLt`, `floatGt`, `floatEq`, `floatAbs`, `pi()`

### Compiler
- `readNumber` — now handles float literals (digits `.` digits)
- `cRuntime` — 12 new `kr_f*` functions, `#include <math.h>` added
- kr_ builtins: 134 → 147
- Self-host verified with kcc_v085.exe

---

## [0.8.5] - 2026-03-17

### Language — Optional Type Annotations

Type annotations are now supported everywhere a declaration occurs. They are
optional, non-enforced, and produce no change in the generated C — the compiler
parses and discards them. All values remain `char*` at runtime.

**Variable declarations:**
```
let x: int = 42
let name: string = "Krypton"
let items: list[int] = "1,2,3"
```

**Function parameters and return types:**
```
func add(a: int, b: int) -> int {
    emit toInt(a) + toInt(b) + ""
}
```

**Struct fields:**
```
struct Point {
    let x: float
    let y: float
}
```

**Supported type names:** `int`, `float`, `bool`, `string`, `list`, `map`, `any`, `void`, `num`

**Compound types:** `list[int]`, `map[string, int]` — brackets parsed and skipped.

### Compiler (compile.k)
- `compileLet` — skips optional `: type` and compound `list[int]` annotations
- `compileFunc` — skips `: type` on each parameter; skips `-> type` return annotation
- `compileStructDecl` — skips `: type` on struct field declarations
- `scanFunctions` — skips type annotations when counting parameters (so param counts stay correct)
- `isKW` — type keywords `int`, `float`, `bool`, `string`, `list`, `map`, `any`, `void`, `num` added as keywords
- `cIdent` — added `abs`, `exit`, `rand`, `free`, `malloc`, `printf`, `strlen`, `strcmp`, `strcpy`, `time` to reserved C name list

### Interpreter (run.k)
- `execLet` — skips optional `: type` annotation on variable declarations

### Docs
- `Spec.md` — updated to v0.8.5, new section 3.5 for type annotations

---

## [0.8.0] - 2026-03-13

### Language
 - Module/import/export support
 - Error handling: try, catch, throw
 - Struct/class/type declarations
 - Foundation for advanced features (lambdas, pattern matching, concurrency)

### Compiler
 - Updated kompiler/compile.k with new keywords and statement support
 - Ready for full release testing

---

## [0.5.0] - 2026-03-12

### Language
- Ternary operator: `cond ? trueExpr : falseExpr` (nestable)
- `const` declarations: `const x = "value"`

### Built-in Functions (15 new, 72 total)
- **List ops:** `splitBy`, `listIndexOf`, `insertAt`, `removeAt`, `replaceAt`, `fill`, `zip`, `every`, `some`, `countOf`
- **Aggregation:** `sumList`, `maxList`, `minList`
- **Conversion:** `hex`, `bin`

### Compiler
- Added `?` token to lexer
- Added `const` keyword
- Ternary expression parsing with correct precedence
- Self-host verified (485 KB with icon)

---

## [0.4.0] - 2026-03-12

### Language
- `continue` statement in loops
- `match` statement with pattern values and `else` fallback
- `do-while` loop: `do { ... } while cond`

### Built-in Functions (15 new, 57 total)
- **Math:** `range`, `pow`, `sqrt`, `sign`, `clamp`
- **Strings:** `padLeft`, `padRight`, `charCode`, `fromCharCode`
- **Lists:** `slice`, `length`, `unique`
- **I/O:** `printErr`, `readLine`
- **Debug:** `assert`

### Bugfix
- Fixed `%` modulo operator in expressions — lexer emitted `MOD` token but parser checked for `PERCENT` (broken since v0.1.0, only `%=` worked since v0.3.0)

### Compiler
- Self-host verified (470 KB with icon)

---

## [0.3.0] - 2026-03-12

### Language
- Compound assignment operators: `+=`, `-=`, `*=`, `/=`, `%=`
- `for-in` loop: `for item in list { ... }`

### Built-in Functions (12 new, 42 total)
- **Lists:** `append`, `join`, `reverse`, `sort`
- **Maps:** `keys`, `values`, `hasKey`, `remove`
- **Strings:** `repeat`, `format`
- **Conversion:** `parseInt`, `toStr`

### Compiler
- Added compound assignment tokens (PLUSEQ, MINUSEQ, STAREQ, SLASHEQ, MODEQ)
- Added `kr_listlen` for comma-based list length (fixes for-in iteration)
- First version with embedded icon via Windows resource compiler
- Self-host verified (455 KB with icon)

---

## [0.2.0] - 2026-03-11

### Built-in Functions (15 new, 30 total)
- **Strings:** `indexOf`, `contains`, `replace`, `charAt`, `trim`, `toLower`, `toUpper`, `endsWith`
- **I/O:** `writeFile`, `input`
- **Math:** `abs`, `min`, `max`
- **System:** `exit`, `type`

### Compiler
- Self-host verified (230 KB)

---

## [0.1.0] - 2026-03-10

### Initial Release
- Krypton-to-C transpiler written in Krypton (self-hosting)
- Core syntax: `let`, `func`/`fn`, `emit`/`return`, `if`/`else`, `while`, `break`
- Entry point: `just run { ... }`
- String-based value model (all values are strings, numeric-aware arithmetic)
- Arena allocator with 256 MB blocks
- Handle-based StringBuilder

### Built-in Functions (15)
- **I/O:** `print`/`kp`, `readFile`, `arg`, `argCount`
- **Strings:** `len`, `substring`, `split`, `startsWith`, `getLine`, `lineCount`, `count`
- **Conversion:** `toInt`
- **Low-level:** `envNew`, `envSet`, `envGet`, `makeResult`, `getResultTag`, `getResultVal`, `getResultEnv`, `getResultPos`, `isTruthy`, `sbNew`, `sbAppend`, `sbToString`

### Compiler
- C++ bootstrap → self-hosted fixed-point achieved
- Bootstrap chain preserved in `build/versions/`## [0.8.0] - 2026-03-16

### Module System

`import`, `export`, and `module` are now fully implemented.

**import** — load another Krypton file and inline its functions:

    import "stdlib/result.k"
    import "stdlib/math_utils.k"

    just run {
        let r = ok("hello")
        kp(unwrap(r))
        kp(gcd(48, 18))
    }

Import features:
- Path resolution relative to the source file's directory
- Import caching — duplicate imports silently skipped
- Works with both flat files and legacy `go name { }` wrapped files
- Error reporting when imported file is not found
- Merged function tables — imported functions visible to the compiler

**export** — mark a function as part of a module's public API:

    export func add(a, b) {
        emit toInt(a) + toInt(b) + ""
    }

**module** — declare the current file's module name:

    module math_utils

### Stdlib — Fully Importable

All 34 stdlib modules have been converted to the flat function format.
The `go name { }` wrapper has been removed from all of them.
A `module name` declaration has been added to each file.

Modules ready to import:
    stdlib/assert.k         stdlib/bitwise.k        stdlib/builder.k
    stdlib/char_utils.k     stdlib/collections.k    stdlib/convert.k
    stdlib/counter.k        stdlib/csv.k             stdlib/debug.k
    stdlib/file_utils.k     stdlib/format.k          stdlib/hex.k
    stdlib/io_utils.k       stdlib/json.k            stdlib/lines.k
    stdlib/list_utils.k     stdlib/map.k             stdlib/math_utils.k
    stdlib/option.k         stdlib/pair.k            stdlib/path.k
    stdlib/queue.k          stdlib/random.k          stdlib/range.k
    stdlib/result.k         stdlib/search.k          stdlib/set.k
    stdlib/sort.k           stdlib/stack.k           stdlib/string_utils.k
    stdlib/struct_utils.k   stdlib/test_framework.k  stdlib/text.k
    stdlib/validate.k

### Compiler (compile.k)
- Real import processing: loads file, tokenizes, scans functions, emits forward
  decls and bodies before the main file's functions
- Base directory resolution for relative import paths
- Import cache prevents duplicate compilation
- `export func` now actually compiles the following function
- `module name` emits a C comment marker
- Error message when source file cannot be read
- Top-level struct declarations now compiled in the second pass
- `fn` keyword accepted alongside `func` in all positions

### Interpreter (run.k)
- `import "file.k"` loads file and merges function table at runtime
- `module` and `export` keywords handled (skip gracefully)

### New Examples
- `examples/import_demo.k` — uses result.k, math_utils.k, json.k together
- `examples/hello_modules.k` — minimal import example

### Compiler stats
- compile.k: 66 functions, 134 builtins, 3433 lines
- Self-host verified with kcc_v077.exe

---

## [0.7.7] - 2026-03-16

### Language
- List literals: `[1, 2, 3]` compiles to comma-separated string `"1,2,3"`
- Empty list literal: `[]` produces `""`

### Interpreter (run.k) — Full Language Parity
- Added 86 missing builtins — now handles 113 total (up from 27)
- Added: `for-in`, `match`, `do-while`, `continue`, `try/catch/throw`
- Added: compound assignment (`+=`, `-=`, `*=`, `/=`, `%=`)
- Added: DOT field access (`obj.field`) and field assignment (`obj.field = val`)
- Added: `struct` declaration handling (skip at runtime)
- The interpreter now matches the compiler in language feature support

### Built-in Functions Added to Interpreter
All v0.2.0–v0.7.5 builtins including: string ops (toLower, toUpper, trim,
lstrip, rstrip, replace, indexOf, contains, splitBy, strReverse, isAlpha,
isDigit, center, padLeft, padRight, repeat, format), list ops (append, join,
sort, reverse, unique, range, first, last, head, tail, every, some, countOf,
sumList, maxList, minList, insertAt, removeAt, replaceAt, fill, zip, slice,
listIndexOf), math (pow, sqrt, hex, bin, sign, clamp, abs, min, max, floor,
ceil, round), struct ops (structNew, getField, setField, hasField, structFields),
map ops (mapGet, mapSet, mapDel), system (random, timestamp, environ, exit),
and more.

### New Stdlib Modules
- `stdlib/result.k` — Result type: `ok(val)`, `err(msg)`, `isOk`, `unwrap`, `unwrapOr`
- `stdlib/option.k` — Option type: `some(val)`, `none()`, `isSome`, `optUnwrap`, `optUnwrapOr`
- `stdlib/json.k` — JSON builder: `jsonStr`, `jsonObject`, `jsonArray`, `jsonBool`, `jsonNull`

### Docs
- `docs/roadmap.md` — Full roadmap to v1.0.0 native compilation documented

### Compiler
- Import statement improved: attempts to read file, reports whether found
- compile.k: 63 functions, 134 builtins, 3211 lines
- Self-host verified with kcc_v075.exe

---

## [0.7.5] - 2026-03-16

### Language
- String interpolation upgraded to full expressions: `` `{a + b}`, `{len(s)}`, `{func(x)}` ``
  Previously only simple identifiers worked. Expressions inside `{}` are now tokenized
  and compiled as full Krypton expressions.

### Built-in Functions (7 new, 134 total)
- **Maps:** `mapGet(map, key)`, `mapSet(map, key, val)`, `mapDel(map, key)` — key-value map operations that complement the existing `keys()`/`values()`/`hasKey()`
- **Lists:** `listMap(lst, prefix, suffix)` — wrap each item, `listFilter(lst, val)` — keep matching items (`"!val"` to exclude)
- **Strings:** `strSplit(s, delim)` — alias for `splitBy` with clearer name
- **System:** `sprintf(fmt, ...)` — C-style format strings via `vsnprintf`

### Stdlib
- All 27 stdlib modules modernized: `i = i + 1` → `i += 1`, `i = i - 1` → `i -= 1`
- New module: `stdlib/struct_utils.k` — `structToString`, `structCopy`, `structFromMap`, `structToMap`, `structEqual`

### Algorithms
- All 23 algorithm files modernized to use compound assignment operators

### Examples
- All 33 remaining examples modernized to current syntax
- New: `examples/task_manager.k` — showcase using structs, try/catch, interpolation, match

### Interpreter
- `run.k` updated to support string interpolation (backtick strings with `{expr}`)

### Compiler
- `#include <stdarg.h>` added to generated runtime for `sprintf`
- Self-host verified with kcc_v072.exe

---

## [0.7.2] - 2026-03-15

### Critical Fix
- `struct`, `class`, `type`, `try`, `catch`, `throw` were missing from `isKW()` — the tokenizer was producing `ID:struct` instead of `KW:struct`, meaning structs and try/catch were silently broken in any real program. Fixed.

### Language
- String interpolation: `` `Hello {name}, version {ver}!` `` — backtick strings with `{identifier}` placeholders compile to `kr_cat()` chains

### Docs
- `docs/spec/functions.md` — fully updated to v0.7.2 with all 127 functions
- `docs/spec/grammar.md` — updated with structs, try/catch, interpolation, DOT token
- `docs/spec/types.md` — completely rewritten to accurately describe Krypton's string-based type model (old version described a fictional static type system)
- `docs/roadmap.md` — updated with accurate history and near-term plans

### Tutorials
- `21_structs.k` — struct declaration, literals, dot access, dynamic structs
- `22_try_catch.k` — try/catch/throw with nesting and rethrow
- `23_for_in.k` — for-in with nesting, counters, range
- `24_string_interpolation.k` — backtick strings with expressions
- `25_match.k` — match statement pattern matching

### Tests
- `tests/test_structs.k` — full struct coverage
- `tests/test_try_catch.k` — exception handling coverage
- `tests/test_interpolation.k` — string interpolation coverage
- `tests/test_for_in.k` — for-in loop coverage including triple nesting

### Examples Updated
- `fibonacci.k`, `fizzbuzz.k`, `hello.k`, `factorial.k` modernized to use `+=`, `for-in`, string interpolation

### Compiler
- Self-host verified with kcc_v071.exe

---


