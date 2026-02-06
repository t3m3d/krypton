# Krypton Roadmap (Short-Term, Functionality First)

This roadmap focuses only on what is required to get the Krypton language
**fully functional**, stable, and capable of running real programs.

---

## 1. Finalize Core Language Files
These define the surface of the language and must be locked before deeper work.

- [*] grammar.md (syntax rules)
- [ ] types.md (type system rules)
- [ ] functions.md (built-in functions + keywords)

Once these three are stable, the compiler has a fixed target.

---

## 2. Implement Missing Syntax Features
Ensure the parser fully supports all constructs defined in grammar.md.

- [ ] `emit` statement
- [*] `kp` print statement
- [ ] `prepare` and `measure`
- [ ] function calls
- [ ] process declarations (`go name {}`)
- [ ] main entry (`go run {}`)

The parser must build correct AST nodes for every rule.

---

## 3. Complete AST Definitions
Every syntax element must have a matching AST node.

- [ ] Emit node
- [ ] Process node
- [ ] Quantum intrinsic nodes
- [ ] Function call node
- [ ] If / block / let nodes
- [ ] Expression nodes (binary, unary, literal, identifier)

No AST gaps allowed.

---

## 4. Implement Interpreter / Codegen Behavior
Make the language actually *run*.

### Emit
- [ ] `emit` must return a value from functions
- [ ] `emit` must return a value from processes
- [ ] `emit` inside `run` must end the program

### Processes
- [ ] Running a process executes its block
- [ ] The emitted value becomes the process result
- [ ] `run` is the only required process

### Functions
- [ ] Evaluate parameters
- [ ] Execute body
- [ ] Return via `emit`

### Quantum Ops
- [ ] `prepare` initializes a qubit/qreg
- [ ] `measure` returns classical data

---

## 5. Build Minimal Standard Library
Just enough to run real programs.

- [*] `kp()` — print
- [ ] quantum intrinsics
- [ ] basic math ops (already in grammar)

No extra features until the core works.

---

## 6. Create a Small Test Suite
Tests ensure nothing breaks as the language grows.

- [ ] let-binding test
- [ ] arithmetic test
- [ ] function call test
- [ ] emit test (functions)
- [ ] emit test (processes)
- [ ] run block test
- [ ] quantum prepare/measure test

Keep tests tiny and focused.

---

## 7. First Working Release
When all above items are complete:

- Krypton can parse programs
- Krypton can execute programs
- `emit` works everywhere
- `go run` works as the entry point
- quantum ops function at a basic level

This marks **Krypton 0.1.0**.
