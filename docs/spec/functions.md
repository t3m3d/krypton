# Krypton Built-in Functions Reference

**Version 1.8.0** — Reference for built-in functions.

All values in Krypton are strings. Functions that operate on numbers parse their
arguments and return numeric strings. Lists are comma-separated strings (`"a,b,c"`).
Maps are interleaved key-value lists (`"name,Alice,age,30"`).

## Pipeline support legend

Some functions exist in every pipeline; others are only available via the C-emitter
path (`kcc.sh --c` or default on macOS). Each entry below carries a tag:

- **(native)** — works in `kcc.sh --native` on Linux ELF (the leading native target)
  *and* in the C path. The Windows PE backend (`x64.k`) and macOS arm64 Mach-O
  backend (`macho_arm64_self.k`) carry most of these too; if a function works on
  Linux native it generally works everywhere unless noted otherwise.
- **(C path)** — only resolves through the C-emitter pipeline; calling it from
  `--native` will produce an `UNSUPPORTED` marker and crash at runtime. To use
  these today, compile with `kcc.sh --c` (emit C) and run the resulting binary
  through `gcc` / `clang`. Most of them will migrate to the native pipeline over
  the 1.5–2.0 line.

When in doubt, run `kcc.sh --native --ir foo.k` and look for `UNSUPPORTED` lines.

---

## I/O

### print(s) / kp(s) — (native)
Prints `s` followed by a newline to stdout. `kp` is a short alias.

### printErr(s) — (native)
Prints `s` followed by a newline to stderr.

### readFile(path) — (native)
Reads a file's contents. Returns `""` if the file does not exist.

### writeFile(path, data) — (native)
Writes `data` to a file. Returns `"1"` on success, `"0"` on failure.

### arg(n) — (native)
Returns command-line argument `n` (0-based, skipping the program name).

### argCount() — (native)
Returns the number of command-line arguments.

### exit(code) — (native)
Exits the program with the given exit code. Does not return.

### readLine(prompt) — (C path)
Prints `prompt` then reads a line from stdin (no trailing newline).

### input() — (C path)
Reads a line from stdin with no prompt.

### deleteFile(path) — (C path)
Removes a file. Returns `"1"` on success.

### shellRun(cmd) — (C path)
Runs `cmd` via the system shell; returns the captured stdout.

### environ(name) — (C path)
Returns the value of an environment variable, or `""` if not set.

---

## Strings

### len(s) — (native)
Returns the byte length of `s`. Smart-int aware: `len(0)` → `"1"`.

### substring(s, start, end) — (native)
Returns the substring from `start` to `end` (exclusive).

### s[i] — (native)
Indexing returns the single-byte character at position `i`.

### startsWith(s, prefix) — (native)
Returns `"1"` if `s` starts with `prefix`.

### endsWith(s, suffix) — (native)
Returns `"1"` if `s` ends with `suffix`.

### contains(s, sub) — (native)
Returns `"1"` if `s` contains `sub`.

### indexOf(s, sub) — (native)
Position of `sub` in `s`, or `"-1"` if not found.

### replace(s, old, new) — (native)
Replaces every occurrence of `old` with `new`.

### trim(s) — (native)
Strips leading and trailing whitespace.

### toUpper(s) / toLower(s) — (native)
Case conversion.

### reverse(s) — (native)
Byte-reverses a string.

### repeat(s, n) — (native)
Returns `s` repeated `n` times.

### charCode(s) — (native)
Returns the numeric code of the first byte of `s`.

### fromCharCode(n) — (native)
Returns a one-character string with code `n`.

### isDigit(s) — (native)
`"1"` if the first byte is a digit (`0`..`9`).

### isAlpha(s) — (native)
`"1"` if the first byte is a letter.

### lstrip(s) / rstrip(s) — (C path)
Strip only leading or only trailing whitespace.

### center(s, width, pad) — (C path)
Centers `s` within `width`, padding with `pad`.

### padLeft(s, width, pad) / padRight(s, width, pad) — (C path)
Left- or right-pad to `width`.

### splitBy(s, delim) — (C path)
Splits `s` on a multi-char `delim`; returns a comma-separated list.

### format(fmt, arg) — (C path)
Replaces the first `{}` in `fmt` with `arg`. Use backtick interpolation
(`` `Hello {name}` ``) instead — that's a language feature and works everywhere.

### eqIgnoreCase(a, b) — (C path)
Case-insensitive string equality.

### words(s) / lines(s) — (C path)
Split on whitespace / newlines into a comma-separated list.

### sprintf(fmt, ...) — (C path)
C-style formatted print to a string.

---

## Numbers

### toInt(s) / parseInt(s) — (native)
Parse a string to an integer string. Smart-int aware.

### abs(n) — (native)
Absolute value.

### pow(base, exp) — (native)
Integer power.

### range(start, end) — (native)
Comma-separated list of integers `[start, end)`.

### min(a, b) / max(a, b) — (C path)
Smaller / larger of two numeric strings.

### sqrt(n) — (C path)
Integer square root.

### sign(n) — (C path)
Returns `"-1"`, `"0"`, or `"1"`.

### clamp(val, lo, hi) — (C path)
Clamp `val` to `[lo, hi]`.

### hex(n) / bin(n) — (C path)
Hex / binary string representation.

### floor(n) / ceil(n) / round(n) — (C path)
For Krypton's integer-only number model these are identity functions on integer
strings; included for compatibility.

### random(n) — (C path)
Random integer in `[0, n)`.

### timestamp() — (C path)
Current Unix timestamp as a string.

### Bit ops: bitAnd / bitOr / bitXor / bitNot / bitShl / bitShr — (C path)
Bitwise operations on numeric strings.

### 64-bit ops: add64 / sub-via-add64 / mul64 / div64 / mod64 — (C path)
64-bit arithmetic helpers, used by code generators that need to sidestep the
1 GiB smart-int boundary.

### Floats: toFloat, fadd, fsub, fmul, fdiv, fformat, feq, flt, fgt, ffloor, fceil, fround, fsqrt — (C path)
Float/double helpers. Krypton's runtime model is still string-based; these
parse, compute, and re-format.

---

## Lists

Lists are comma-separated strings: `"a,b,c"`.

### split(lst, i) — (native)
Returns the item at index `i`.

### length(lst) / count(lst) — (native)
Returns the number of items.

### range(start, end) — (native)
See "Numbers".

### first(lst) / last(lst) / head(lst, n) / tail(lst, n) — (C path)
First/last item, first-`n` items, last-`n` items.

### append(lst, item) — (C path)
Append `item` to the end.

### slice(lst, start, end) — (C path)
Items from `start` to `end` (exclusive).

### removeAt(lst, i) / replaceAt(lst, i, val) / remove(lst, item) — (C path)
Index-based / value-based removal and replacement.

### sort(lst) — (C path)
Numeric-aware sort.

### unique(lst) — (C path)
Drops duplicates, preserving first-occurrence order.

### fill(n, val) — (C path)
List of `n` copies of `val`.

### zip(a, b) — (C path)
Element-by-element interleave.

### listIndexOf(lst, item) — (C path)
Position of `item`, or `"-1"`.

### every(lst, val) / some(lst, val) — (C path)
All-equal / any-equal predicates.

### countOf(lst, item) — (C path)
Number of occurrences.

### sumList(lst) / minList(lst) / maxList(lst) — (C path)
Numeric reductions.

### listMap(lst, prefix, suffix) / listFilter(lst, val) — (C path)
Wrap each item in `prefix`/`suffix` / keep items matching `val` (or `!val`).

---

## Maps

Maps are interleaved key-value comma-separated strings: `"name,Alice,age,30"`.

### mapGet(map, key) / mapSet(map, key, val) / mapDel(map, key) — (C path)
Map operations.

### keys(map) / values(map) / hasKey(map, key) — (C path)
Inspection.

---

## Structs

Static structs declared with `struct Name { let field; ... }` use a fast
slot-array representation in the C path and a linked-list of bindings in the
native pipeline. Both expose the same API.

### structNew() — (native)
Creates a new empty dynamic struct.

### setField(obj, name, val) — (native)
Sets a field. **Returns the updated struct** — assign back: `obj = setField(obj, ...)`.
The C runtime mutates in place, but the native runtime is functional, so always
re-assign for portability.

### getField(obj, name) — (native)
Returns the field value, or `""` if not set.

### hasField(obj, name) — (native)
`"1"` if the field exists.

### structFields(obj) — (native)
Comma-separated list of field names.

---

## Line Operations

### getLine(s, i) — (native)
Returns the `i`-th newline-separated line.

### lineCount(s) — (native)
Number of newline-separated lines.

---

## Pairs

Pairs are encoded as `"value,position"` strings, used pervasively by parser
helpers in the compiler.

### pairVal(p) / pairPos(p) / pairNew(val, pos) — (stdlib)
Defined in `stdlib/pair.k`. Until native module imports are wired, inline these
in programs that target the native pipeline (see `tests/test_pair_ops.k`).

---

## StringBuilder

Efficient string assembly without repeated concatenation.

### sbNew() — (native)
Creates a new StringBuilder.

### sbAppend(sb, s) — (native)
Appends `s`. Auto-stringifies a small-int second argument. Returns the handle.

### sbToString(sb) — (native)
Returns the accumulated string.

---

## Environment (Low-level)

A linked-list of `{name, value, prev}` bindings used internally by the
interpreter and as the storage backend for dynamic structs in the native runtime.

### envNew() — (native)
Empty environment (`null` sentinel).

### envSet(env, key, val) — (native)
Adds a binding; returns the new environment head.

### envGet(env, key) — (native)
Looks up `key`; returns `""` if not found.

---

## Result helpers

Used by the IR / interpreter for parser-style return values.

### makeResult(tag, val, env, pos) — (C path)
### getResultTag(r) / getResultVal(r) / getResultEnv(r) / getResultPos(r) — (C path)
Pack/unpack helpers.

---

## Type and Conversion

### toStr(s) — (native)
Identity. All values are already strings.

### isTruthy(s) — (native)
`"1"` if `s` is truthy by Krypton's rules (not `""`, `"0"`, or `"false"`).

### type(s) — (C path)
Returns `"number"` if `s` parses as a number, else `"string"`.

### assert(cond, msg) — (C path)
If `cond` is falsy, prints `msg` to stderr and exits with code 1.

### throw(msg) — (native via `throw` keyword)
Throws an exception. Use the keyword form `throw "message"`; the function form
exists only in the C path.

---

## Compiler-internal (advanced)

Used by code generators / AOT build steps. Almost all are C-path only because
they touch raw pointers and would need explicit wiring through the native
pipeline to be safe.

- `tokenize(s)`, `tokAt(toks, i)`, `tokVal(t)`, `tokType(t)` — Krypton tokenizer.
- `bufNew(n)`, `bufSetByte`, `bufSetDword`, `bufSetDwordAt`, `bufGetWord`,
  `bufGetDword`, `bufGetDwordAt`, `bufGetQword`, `bufGetQwordAt`, `bufStr` —
  byte-buffer manipulation for hand-emitting machine code.
- `writeBytes(path, hex)` — writes a binary file from a hex-encoded string.
- `funcptr(name)` — returns a Krypton-compiled function as a raw `char*`
  function pointer for callbacks.
- `callPtr(fp, ...)` — invokes a function pointer.
- `ptrDeref(p)` / `ptrIndex(p, i)` — raw memory access.
- `structAddr(obj)` / `toHandle(p)` / `handleInt(h)` / `handleGet(h)` /
  `handleOut(h)` / `handleValid(h)` — handle / pointer interop helpers.
- `sizeOf(typeName)` — C-type size lookup.
- `exec(cmd)` — execute and return exit code.

---

## Garbage collection (added 1.7.5+)

The Windows native runtime exposes allocation tracking and a soft
limit on the bump arena. Linux ELF and macOS arm64 backends do not yet
have these — they're scheduled to catch up before final 2.0.

### gcAllocated() — (native, Windows; 1.7.5+)
Total bytes allocated by `__rt_alloc` since process start (lifetime
cumulative). Returns int-string. Useful for diagnosing per-scope
allocation cost: read before and after a chunk of work, subtract.

### gcLimit() — (native, Windows; 1.7.5+)
Current soft allocation cap (int-string). `"0"` means unlimited.

### gcSetLimit(n) — (native, Windows; 1.7.5+)
Set the soft cap. If `gcAllocated()` ever exceeds `n`, the next
`__rt_alloc` call abort the process cleanly with `ExitProcess(99)`.
Use to bound pathological allocation patterns (the `kcc.exe` 50 GB
blowup that motivated this would have aborted at, say, `gcSetLimit(1<<30)`).

### gcCollect() — (native, Windows; 1.7.5+)
Placeholder. Returns `"0"`. Real mark-sweep semantics ship in 2.0.

### gcReset() — (native, Windows; 1.7.6 internal+)
Recycles the arena: zeros `slab_off` (so the next allocation starts at
the slab's beginning), zeros `alloc_total`, and frees every slab in
the chain except the first via `HeapFree`. Use at scope boundaries
where you know everything allocated since process start (or since the
last reset) is no longer needed. Returns `"0"`.

### gcCheckpoint() — (native, Windows; 1.7.8 internal+)
Returns an opaque token capturing the current arena state (`slab_curr`
+ `slab_off`). Pair with `gcRestore(token)` for scope-bound bulk free
without disturbing pre-checkpoint allocations.

### gcRestore(token) — (native, Windows; 1.7.8 internal+)
Rewind the arena to the state captured by `gcCheckpoint()`. Walks the
slab chain from `saved_slab_curr->next`, frees each subsequent slab
via `HeapFree`, restores `slab_curr`/`slab_off`. **The token is
single-use** — its memory falls in the rewound range and gets
overwritten by the next allocation. Take a fresh `gcCheckpoint()` for
each scope; never reuse a token across loop iterations.

Idiomatic per-iteration cleanup:
```krypton
while running == 1 {
    let ck = gcCheckpoint()
    doScopedWork()
    gcRestore(ck)
}
```

### gcSlabCount() — (native, Windows; 1.8.0 internal+)
Number of 64 MB slabs in the chain. Returns int-string. `"1"` when
only the first slab is allocated, `"2"`+ once multi-slab kicks in.
`"0"` if no allocation has ever happened.

### gcSlabBytes() — (native, Windows; 1.8.0 internal+)
Bytes used in the current (last) slab — the bump offset `slab_off`
including the 8-byte next-pointer header. Together with
`gcSlabCount()` you can estimate total current usage:

```krypton
let estCurrent = (toInt(gcSlabCount()) - 1) * 67108864 + toInt(gcSlabBytes())
```

### `pure_` function name prefix — (native, Windows; 1.7.9 internal+)
Functions whose name starts with `pure_` get auto-wrapped by the
compiler with `gcCheckpoint()` at entry and `gcRestore()` at exit.
Per-call slab allocations are reclaimed automatically. Caveat: the
wrap appends BEFORE the implicit RETURN, so `pure_` functions must
be **procedural** — no explicit `emit` / `return` of allocated values.

## Notes

- Numeric `+` semantics: when both operands are numeric strings, `+` performs
  integer addition — even via the toStr-via-concat idiom (`"" + 5 + "x"` is
  `5 + "x"` → `"5x"`, not `"5x"`). To force string concat of digit-only tokens,
  use `sbAppend`.
- The native runtime's smart-int convention reserves values ≥ `0x40000000`
  (1 GiB) for string pointers; integers at or above that boundary will be
  misinterpreted as pointers and likely crash. Use `add64` / `mul64` etc. when
  you need more headroom.
