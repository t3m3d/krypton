# Krypton Built‑In Functions and Keywords

This document defines the built‑in operations, keywords, and intrinsic behaviors
available in the Krypton language. All syntax listed here is guaranteed by the
core language and must be implemented by the compiler/runtime.

---

## kp(expr)

Prints the value of an expression.

Example:

kp("Hello");

---

## emit expr

Returns a value from a function or process.  
In functions, the emitted value becomes the function's return value.  
In processes, the emitted value becomes the process result.

Example:

emit 42;

---

## prepare ident

Initializes a qubit or quantum register into a known state.  
Only valid inside quantum contexts.

Example:

prepare q;

---

## measure ident

Measures a qubit or quantum register and returns classical data.

Example:

let r = measure q;

---

## Function Declaration

Functions declare parameters and a return type.  
The returned value must be produced using `emit`.

Example:

fn add(a: int, b: int) -> int {
    emit a + b;
}

---

## Process Declaration

Processes are lightweight execution blocks that do not declare a return type.  
They may still produce a value using `emit`.

Example:

go worker {
    emit 10;
}

---

## Main Entry Point

The program entry point is always:

go run {
    ...
}

Example:

go run {
    kp("Hello Krypton");
    emit 0;
}

---

## Keywords Summary

| Keyword   | Purpose                                 |
|-----------|-----------------------------------------|
| fn        | Define a function                       |
| go        | Define a process                        |
| run       | Program entry point                     |
| emit      | Return a value                          |
| kp        | Print to output                         |
| prepare   | Initialize quantum data                 |
| measure   | Measure quantum data                    |
| let       | Bind a variable                         |
| if / else | Conditional execution                   |

---

## Notes

- All built‑ins must be implemented before Krypton 0.1.0.
- `emit` is the only return mechanism.
- `kp` is the only built‑in output function.
- Quantum intrinsics (`prepare`, `measure`) must be available even if backed by a simulator.
