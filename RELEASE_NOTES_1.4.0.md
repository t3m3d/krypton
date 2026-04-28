# Krypton 1.4.0 — Release Notes

**Released:** 2026-04-27

## Headline

**Native binaries everywhere. C is no longer the default on any platform.**

`kcc.sh hello.k` now produces a native executable directly — ELF on Linux, PE on Windows, Mach-O on macOS. No intermediate C step in the user-visible pipeline. C output is opt-in via `--c`.

---

## Highlights

- **macOS native pipeline** — new `kompiler/macho.k` backend lands a working Mach-O backend on macOS Tahoe (26.x).
- **`kcc.sh` default flipped from C → native** — `kcc.sh foo.k` now produces a binary, not a `.c` file.
- **Bracketless `jxt` syntax** — cleaner imports.
- **8 new ELF builtins** — `printErr`, `charCode`, `fromCharCode`, `exit`, `isDigit`, `isAlpha`, `abs`, `startsWith`.
- **Bug fix** — `jxt { k "..." }` no longer hangs the compiler.

---

## macOS — Native Mach-O Pipeline

### What works

```bash
./kcc.sh hello.k                # produces ./hello, runs natively on macOS
./hello
```

The pipeline: `.k → kcc --ir → kompiler/macho.k → .s → clang → Mach-O`.

`clang` is invoked as the assembler+linker (not as a C compiler) — `macho.k` emits AT&T-syntax assembly, clang handles dyld scaffolding, libSystem linkage, and code signing in one step.

### Why through clang on macOS but not Linux/Windows

macOS Tahoe (26.x)+ AMFI silently SIGKILLs hand-rolled static binaries even when properly code-signed. We exhausted the cheap fixes (LINKEDIT segment, valid CODE_SIGNATURE, MH_PIE, RIP-relative addressing — codesign succeeded each time, kernel still rejected). Apple effectively requires `dyld`-linked Mach-Os, which clang+ld64 produce automatically. The pragmatic call is to let clang handle the complexity it owns.

`kompiler/elf.k` (Linux) and `kompiler/x64.k` (Windows) continue to emit final binaries directly, no external linker — those kernels accept hand-rolled static binaries.

### IR coverage in macho.k

| IR op | Status |
|---|---|
| `FUNC __main__` / `FUNC <name>` | ✓ x86_64 + arm64 |
| `PARAM` / `LOCAL` / `STORE` / `LOAD` | ✓ x86_64 + arm64 (LOAD param via positive RBP offset, LOAD local via negative) |
| `PUSH "string"` | ✓ x86_64 + arm64 (string interned to `__cstring` section) |
| `PUSH <int>` | ✓ x86_64 + arm64 |
| `ADD` / `SUB` / `MUL` / `DIV` / `MOD` | ✓ x86_64 + arm64 (numeric only — string-concat dispatch is future work) |
| `EQ` / `NEQ` / `LT` / `GT` / `LTE` / `GTE` | ✓ x86_64 + arm64 |
| `LABEL` / `JUMP` / `JUMPIFNOT` | ✓ x86_64 + arm64 |
| `BUILTIN kp 1` | ✓ x86_64 + arm64 (uses libSystem `_puts`) |
| `CALL <name> <argc>` | ✓ x86_64 (with stack-alignment padding for odd argc); arm64 stubbed (TODO) |
| `RETURN` / `END` / `POP` | ✓ x86_64 + arm64 |

### Building on macOS — first time

Requires Xcode Command Line Tools:

```bash
xcode-select --install                                  # one-time setup; provides clang, as, ld, codesign, git
git clone https://github.com/t3m3d/krypton && cd krypton
./build.sh                                              # compiles kcc from kcc_seed.c via clang (~30s)
./kcc --version                                         # kcc version 1.4.0
```

Then any of:

```bash
./kcc.sh hello.k                                        # default: native Mach-O at ./hello
./hello

./kcc.sh hello.k -o myapp                               # explicit output name
./myapp

./verify_macho.sh                                       # runs both hardcoded + IR-driven smoke tests
```

### Optional: install globally

```bash
./install.sh                                            # symlinks ./kcc → /usr/local/bin/kcc
kcc --version                                           # works from anywhere
```

### Optional: ship as a prebuilt seed

After a successful `./build.sh`, you can ship the resulting binary so future macOS users skip the source-compile step:

```bash
cp ./kcc bootstrap/kcc_seed_macos_x86_64                # Intel Mac
# or
cp ./kcc bootstrap/kcc_seed_macos_aarch64               # Apple Silicon
git add bootstrap/kcc_seed_macos_*
git commit -m "bootstrap: ship prebuilt macOS kcc seed"
git push
```

After that, fresh clones on the same arch will detect the prebuilt and `cp` it directly — no clang compile needed for the seed.

### What's NOT yet supported on macOS

- ARM64 `CALL` (multi-function programs on Apple Silicon need register-based arg marshalling — currently stubbed with a TODO)
- String concatenation via `ADD` (numeric `ADD` works; string `+` doesn't)
- Most non-`kp` builtins (`toStr`, `toInt`, `substring`, etc.) — would each need a libSystem helper mapping
- macOS prebuilt seed in `bootstrap/` — must be built and shipped from a Mac

---

## `kcc.sh` Default Flipped: C → Native

### New behavior

```bash
kcc.sh foo.k                    # native binary at ./foo (was: C source to stdout)
kcc.sh foo.k -o bar             # native binary at ./bar (unchanged)
kcc.sh --c foo.k                # C source to stdout (legacy mode, opt-in)
kcc.sh --c foo.k -o foo.c       # C source to file
kcc.sh --gcc foo.k              # native binary, but routed through C+gcc internally
kcc.sh --llvm foo.k -o foo.ll   # LLVM IR
kcc.sh --ir foo.k               # Krypton IR (.kir) to stdout
```

### Breaking change

If you have scripts that relied on `kcc.sh foo.k` printing C source to stdout, add `--c`:

```bash
# Old (broken now):
./kcc.sh hello.k > hello.c

# New (explicit C):
./kcc.sh --c hello.k > hello.c
# or:
./kcc.sh --c hello.k -o hello.c
```

---

## New Syntax: Bracketless `jxt`

Imports without braces. Each line is `inc "path"`; extension routes the include (`.k` → Krypton module, `.h` / `.krh` → C header).

```
jxt
inc "stdlib/result.k"
inc "stdlib/math_utils.k"

just run {
    kp(isPrime("17"))
}
```

The block ends at the first non-`inc` token (typically `func`, `let`, or `just run`). Old brace form is fully backwards-compatible.

---

## ELF Backend — 8 New Builtins

Hand-emitted machine code, available on the Linux native pipeline:

| Builtin | Bytes | Notes |
|---|---|---|
| `printErr(s)` | 37 | Like `kp` but writes to stderr (fd 2) |
| `charCode(s)` | 4 | First byte as integer |
| `fromCharCode(n)` | 23 | 1-char string from byte value |
| `exit(n)` | 16 | `SYS_exit(atoi(n))`, does not return |
| `isDigit(s)` | 16 | 1 if first byte is `'0'`..`'9'`, else 0 |
| `isAlpha(s)` | 19 | 1 if first byte is A-Z or a-z |
| `abs(n)` | 14 | `\|n\|` via atoi + neg |
| `startsWith(s, prefix)` | 27 | 1 if `s` begins with `prefix` |

### All ELF builtins as of 1.4.0

`kp`, `printErr`, `toStr`, `toInt`, `length`, `len`, `split`, `range`, `arg`, `argCount`, `substring`, `sbNew`, `sbAppend`, `sbToString`, `readFile`, `writeFile`, `charCode`, `fromCharCode`, `isDigit`, `isAlpha`, `abs`, `exit`, `startsWith`, plus `s[i]` indexing.

---

## Bug Fix: `jxt { k "..." }` Infinite Loop

The `k` branch of [`kompiler/compile.k`](kompiler/compile.k)'s jxt-block parser was missing a `jxtPos += 2` advance that the `c` and `t` branches had. Any program using `jxt { k "..." }` would hang `kcc` forever — affecting `--ir`, the C backend, and `--native`.

Discovered while testing the new bracketless syntax. Fixed.

---

## Verification

- All 23 ELF regression programs still pass on Linux
- `verify_macho.sh` (both hardcoded + IR-driven phases) PASSES on macOS Tahoe 26.3 / Darwin 25.3.0 x86_64
- Self-host clean: `./kcc kompiler/compile.k` produces byte-identical C output between old and new compilers
- Tested IR-driven examples on Mac: `kp("...")`, `let x = ...`, `if x > y { ... }`, `func square(n) { emit n * n }; emit square(7)` — all produce correct Mach-O binaries that run

---

## Upgrading

```bash
git pull
./build.sh         # Linux/macOS/WSL
bootstrap.bat      # Windows
```

If you have scripts that piped `kcc.sh foo.k > foo.c`, update them to `kcc.sh --c foo.k > foo.c`.

---

## What's Next

- ARM64 `CALL` support in `macho.k` (register-based arg marshalling)
- String concat / smart-int dispatch in macho.k's `ADD`
- More macho.k builtins (`toStr`, `toInt`, `substring`, etc. via libSystem helpers)
- Prebuilt macOS seeds for `bootstrap/` (built on a Mac, shipped to repo)
- Eventually retire `compile.k`'s C emission + `bootstrap/kcc_seed.c` once macOS prebuilts cover all common archs

---

**Krypton 1.4.0** — [t3m3d/krypton](https://github.com/t3m3d/krypton) — Apache 2.0
