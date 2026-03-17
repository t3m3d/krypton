# Krypton Roadmap — Toward 1.0.0

The goal of v1.0.0 is a Krypton compiler that compiles Krypton source directly
to native machine code without requiring an external C compiler.

---

## Completed

### v0.1.0 — v0.7.7
See CHANGELOG.md for full history.

Current state (v0.7.7):
- Self-hosting compiler: compile.k compiles itself
- 134 built-in functions
- Structs with dot access, try/catch/throw, string interpolation
- run.k interpreter: handles all language features including structs, for-in, match, try/catch
- List literals [1, 2, 3]
- Stdlib: 32 modules including result.k, option.k, json.k, struct_utils.k

---

## v0.8.0 — Module System

The module system is the last major piece before the stdlib is usable in compiled programs.

- `import "stdlib/math_utils.k"` — load and inline compile another file
- `export func name` — mark a function as exported
- `module name` — declare a module namespace
- Circular import detection
- Import caching (don't compile same file twice)
- stdlib files converted to use `just run` or made importable

---

## v0.8.5 — Type Annotations (Optional)

- `let x: int = 42` — optional type hints
- `func add(a: int, b: int) -> int` — typed function signatures
- No enforcement at first — purely for documentation and future tooling
- Compiler emits typed C declarations when annotations present

---

## v0.9.0 — Krypton IR

Design and implement an intermediate representation written in Krypton.

The IR is a simplified instruction set:
- `LOAD name` / `STORE name` — variable access
- `CONST value` — push constant
- `ADD`, `SUB`, `MUL`, `DIV` — arithmetic
- `CALL name argc` — function call
- `JUMP label` / `JUMPIF label` — control flow
- `LABEL name` — branch target
- `RETURN` — return from function

The compiler gains a new mode: `kcc --ir file.k > file.kir`

---

## v0.9.5 — IR Optimizer

- Constant folding
- Dead code elimination
- Common subexpression elimination
- Inline small functions

All passes written in Krypton, operating on the IR text format.

---

## v0.9.8 — x86-64 Code Emitter

A Krypton program that reads `.kir` and emits x86-64 assembly:

- Map Krypton string values to memory regions
- Implement the string runtime in assembly
- Emit ELF (Linux) or PE (Windows) object files
- Link with system libraries for I/O

---

## v1.0.0 — Native Compilation

`kcc file.k` produces a native executable with no external tools required.

- Krypton source → Krypton IR → x86-64 assembly → native binary
- Windows and Linux targets
- Full standard library importable
- Self-hosting: kcc_v100 can compile itself to produce an identical kcc_v100
- Performance within 2x of equivalent C code

---

## Post-1.0.0

- ARM64 target
- Lambdas and first-class functions
- Garbage collection (replace arena allocator)
- Concurrency primitives
- Package manager
- Language server protocol (LSP) for editor support
- Quantum computing backend (the original vision)
