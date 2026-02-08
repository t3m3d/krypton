# Krypton Type System

Krypton uses a simple, explicit, statically‑checked type system. All values have
a known type at compile time, and no implicit conversions occur.

## Primitive Types

| Type   | Description                     |
|--------|---------------------------------|
| int    | 64‑bit signed integer           |
| float  | 64‑bit floating‑point number    |
| bool   | Boolean (`true` or `false`)     |
| string | UTF‑8 encoded string            |

## Quantum Types

| Type  | Description                   |
|-------|-------------------------------|
| qubit | A single quantum bit          |
| qreg  | A fixed‑size quantum register |

Quantum types may only be manipulated inside quantum contexts such as
`quantum qpute` blocks or quantum intrinsics (`prepare`, `measure`).

## Function Types

Functions declare parameter types and a return type:

fn add(a: int, b: int) -> int

The returned value is produced using `emit`.

## Process Types

Processes declared with `go` do not specify a return type:

go run {
    emit 42;
}

If a process uses `emit`, the emitted value becomes the process result.

## Type Rules

- All variables must be declared using `let`.
- Types must match exactly; no implicit conversions occur.
- Quantum values cannot be copied or cloned.
- Function parameters and return types must be explicitly typed.
- Expressions must resolve to a well‑defined type at compile time.
