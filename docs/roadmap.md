# Krypton Roadmap

---

## Completed

### v0.1.0
- Self-hosting compiler written in Krypton
- Core syntax: `let`, `func`/`fn`, `emit`/`return`, `if`/`else`, `while`, `break`
- Entry point: `just run { ... }`
- 15 built-in functions

### v0.2.0
- 15 new built-ins: string ops, I/O, math, system (30 total)

### v0.3.0
- `+=`, `-=`, `*=`, `/=`, `%=` compound assignment
- `for item in list { }` loop
- 12 new built-ins: list/map ops, repeat, format (42 total)

### v0.4.0
- `continue` statement
- `match` statement
- `do { } while cond` loop
- 15 new built-ins: math, strings, lists, I/O (57 total)

### v0.5.0
- Ternary operator: `cond ? a : b`
- `const` declarations
- 15 new built-ins: list ops, hex, bin (72 total)

### v0.6.0 (compiler fixes)
- Fixed 3 critical bugs in compile.k
- Build tooling established

### v0.7.0
- `try` / `catch` / `throw` via setjmp/longjmp
- 20 new built-ins: strings, lists, system (127 total)

### v0.7.1
- Structs: `struct Name { let field }`, dot access, field assignment
- Struct literals: `Name { field: val }`
- Dynamic structs: `structNew()`, `getField()`, `setField()`
- Nested for-in loop variable clash fixed

### v0.7.2 (current)
- **Critical fix:** `struct`, `try`, `catch`, `throw` now correctly tokenized as keywords
- String interpolation: `` `Hello {name}!` ``
- Tutorial lessons 21-25
- Test coverage for structs, try/catch, for-in, interpolation
- All docs updated to v0.7.2

---

## Near-term (v0.8.x)

### v0.8.0 — Module System
- `module name` declaration
- `import name` loads another `.k` file
- `export func` marks a function as public
- Compiler resolves imports at compile time

### v0.8.1 — String Enhancements
- Multi-line strings
- Raw strings (no escape processing)
- More string format specifiers in `format()`

### v0.8.2 — List Comprehensions
- `[expr for item in list]` syntax sugar
- Compiles to a for-in loop building a list

---

## Medium-term (v0.9.x)

### Float Support
- `float` literals: `3.14`, `2.5`
- Float arithmetic operators
- `toFloat()`, `fromFloat()` builtins
- `floor`, `ceil`, `round` return meaningful values for floats

### Typed Struct Fields
- `let x: int` field declarations
- Type checking at struct construction time
- More efficient C codegen (native struct members vs dynamic fields)

### Error Types
- Typed exceptions: `throw Error { code: "404", msg: "not found" }`
- `catch` with type matching

---

## Long-term

- **Lambdas / first-class functions**
- **Pattern matching with destructuring**
- **Concurrency / process model**
- **Optional static typing** — type annotations that the compiler can verify
- **Quantum blocks** — `quantum qpute { }`, `prepare`, `measure`
- **Package manager** — distributing Krypton libraries
