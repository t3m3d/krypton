# Python compatibility matrix

**What the Python frontend will and will NOT support.**

The goal of the Python FE is **a Python-shaped surface over Krypton's
native runtime / GC / IR / backends** — not byte-for-byte CPython
compatibility. Several Python features are explicit non-goals because
they don't fit Krypton's model or because supporting them would harm
the language's properties (native compilation, no GIL, predictable
GC).

Sibling docs: `python_to_kir.md` (what we DO support, with IR
lowerings), `handoff_w2all_pyfrontend.md` (prep work coordination),
`handoff_w2all_overall.md` (the broader roadmap).

## At a glance

| Feature | Status | Reason |
|---|---|---|
| `print` / `input` / `len` / `range` / `enumerate` / `zip` / `map` / `filter` / `sorted` / `sum` / `abs` / `min` / `max` / `all` / `any` / `chr` / `ord` / `hex` / `bin` / `oct` / `id` / `hash` | shipped | `stdlib/builtins.k` |
| str methods | shipped | `stdlib/string_py.k` (37 funcs) |
| list methods + `x[i]` + `x[lo:hi]` + `x in xs` | shipped | `stdlib/list_py.k` (15 funcs) |
| dict methods + `d[k]` + `k in d` | shipped | `stdlib/dict_py.k` (16 funcs) |
| arithmetic + comparison + logical short-circuit | shipped | maps to Krypton IR |
| if / while / for-in | shipped | maps to Krypton IR |
| def + closures + lambda | shipped | reuses Krypton native pipeline |
| f-strings | partial | basic interpolation works; format specs blocked on A4 |
| float / `math.*` / `1.5e-3` | **blocked: A1 floating point** | no FP in runtime yet |
| `class` (single-inheritance, no metaclass) | **blocked: Tier B structural types** | needs class system |
| `try / except / raise / finally` | **blocked: exception design TBD** | no IR ops for unwind |
| `with` / context managers | **blocked: B1 defer** | needs scope-exit support |
| generators / `yield` / generator expressions | **blocked: B5 goroutines** | needs stackful coroutines |
| `async def` / `await` / `asyncio` | **blocked: B5 goroutines** | concurrency lives in `go` |
| `*args` / `**kwargs` | **blocked: A4 variadic** | parser + ABI work |
| keyword arguments | **blocked: A4 variadic** | same |
| tuple multi-return | **blocked: B2 multi-return** | ABI / parser work |
| compound assignment beyond `+=` | **blocked: A7** | parser work |

## Explicitly NOT supported (won't ship even when the blocker lifts)

These aren't blocked on a roadmap item — they're choices we're making
on purpose. They reflect Krypton's design (native, no GIL, predictable
GC, no runtime metaprogramming).

### `__dunder__` runtime hooks

No `__getattr__`, `__setattr__`, `__getitem__`, `__setitem__`,
`__call__`, `__iter__`, `__next__`, `__enter__`, `__exit__` as
runtime-overridable hooks. Krypton dispatches at compile time;
runtime dispatch through dunder methods is a performance + complexity
tax that hurts more than it helps for the kinds of programs Krypton
targets.

Counter-cases: `__init__` is supported as a constructor convention
once classes ship; `__str__` / `__repr__` may be supported as
compile-time hooks (FE emits `reprk` / `strk` for `repr()` /
`str()` calls).

### Metaclasses

`class C(metaclass=M):` is a parse error. Krypton's class model
(when it ships) is single-inheritance only; metaclasses don't fit.

### Multiple inheritance / MRO

`class C(A, B):` rejected. Diamond resolution and method-resolution-
order are Python-specific complexity that doesn't pay back. Use
composition or interfaces (Tier B4 once it ships) instead.

### `eval` / `exec` / `compile`

No runtime compilation entry points. Krypton compiles once at build
time; runtime eval would require shipping a full compiler in every
binary. Use config files + parsers (`stdlib/json.k`, `stdlib/ini.k`)
for dynamic data, or write the dynamic surface as Krypton code that
calls back into your program.

### Monkey-patching builtins

The `*k`-named polyfills in `stdlib/builtins.k` etc. are immutable
imports. You can't reassign `printk = my_printk` at the module level
and have it affect prior callers. Use ordinary function composition.

### `pickle` / `marshal`

No language-level serialization that captures arbitrary objects.
Krypton's value model (everything is a string at the runtime
boundary) makes JSON / explicit-serialize patterns more natural.

### C extension imports

`import numpy` (or any extension module compiled from C) won't work.
Krypton's FFI is `head:` headers + IAT bindings (Windows) / direct
syscalls (POSIX). If you need numpy-like capability, write it in
Krypton on top of typed pointers + the future float surface.

### `__import__` / dynamic module loading

`import` is compile-time only. No runtime `importlib`. Plugin
architectures should use callable values + explicit dispatch
tables, not runtime module loading.

### Descriptors / properties (as runtime hooks)

`@property` may be supported as a syntactic shortcut once classes
ship — the FE rewrites `@property def x(self):` into a method
`x_get(self)` and `obj.x` → `x_get(obj)`. But there's no runtime
descriptor protocol; you can't write your own `__get__` /
`__set__`.

### GIL semantics

Krypton goroutines (once B5 lands) are real concurrency — no GIL,
no shared-memory race-by-default. Programs that depend on the GIL
for implicit serialization (a lot of Python code, sadly) need
explicit synchronization. Use channels + atomics (B6).

### Negative-index assignment with bounds-error

Python raises `IndexError` on `xs[100] = v` for an out-of-range
write. Krypton's `listSetk` clamps to no-op on out-of-range.
**This is intentional** — no exception machinery yet, and silent
clamp matches the rest of the stdlib's "tolerant" stance. Explicit
bounds-checking decorator may ship later.

### Dynamic class modification

`C.new_method = lambda self: ...` doesn't work. Classes are
fixed at compile time. Use closures over data + free-form
function dispatch if you need that flexibility.

### `__slots__`

Not needed — Krypton structs are fixed-layout by default. No
dict-backed instance storage to opt out of.

### `nonlocal` chains across multiple scopes

`nonlocal` for the immediate enclosing scope works; reaching
through multiple closure scopes to a grandparent is undefined
behavior. The FE emits a warning.

### Implicit string concatenation of adjacent literals

```python
"foo" "bar"   # Python: "foobar"
```
Reject as parse error. Forces `"foo" + "bar"` (or f-string). Less
magic, fewer typos.

### Operator overloading via dunders

`a + b` does NOT call `a.__add__(b)`. The FE always emits the IR
`ADD` op. If both operands are int-strings, you get int addition;
if either is a non-digit string, you get string concat (Krypton's
existing kr_plus semantics).

## Edge cases worth calling out

### `print(*args, sep=" ", end="\n")`

Today `printk(x)` is one-positional. Variadic + kwargs blocked on
A4. Until then, the FE lowers `print(a, b)` to `printk(strk(a) + " " + strk(b))`.

### `range(start, stop, step)`

Two-arg today (`rangek(start, stop)`). Three-arg requires FE-level
argcount overload — fold a `step` parameter into the IR `RANGE` op
when it lands.

### `dict(a=1, b=2)` constructor with kwargs

Blocked on kwargs (A4). Until then, lower to:
```python
dictsetk(dictsetk("", "a", "1"), "b", "2")
```

### `True is True` / `None is None`

Lower as `EQ`. Krypton has no separate identity-vs-equality channel
(everything is strings); `is` semantics match `==` for singletons.

### Integer division `//` vs `/`

Both lower to Krypton `DIV` (integer). Once floats ship (A1), `/`
will lower to `FDIV` and `//` will stay `DIV`. Programs written
today expecting integer `/` continue to work post-A1; programs
expecting float `/` need a re-lowering pass when A1 ships.

### Truthiness

Python's truthiness rules (empty containers, zero, None all falsy)
match Krypton's `isTruthy` for strings + int-strings + the empty
string sentinel. No work needed.

### Iteration over strings

`for c in "hello":` lowers to a per-character loop. The FE detects
string receiver (vs list) and rewrites `INDEX` accordingly. Today
both happen to do the right thing because Krypton strings + lists
share the same runtime.

## What this means for porting Python code

- **Pure-Python algorithms** (sorts, parsers, state machines,
  numeric code that doesn't need floats) port cleanly.
- **Web frameworks** (Flask, Django) need substantial rewriting —
  Python's runtime metaprogramming is load-bearing in those.
- **Scientific stack** (numpy, pandas) needs to be re-written in
  Krypton on typed pointers + the future float surface; can't
  import as-is.
- **Async/concurrent code** (`asyncio`, `gevent`, `twisted`) needs
  re-architecting onto goroutines once B5 ships.
- **CLI tools / scripts** with stdlib-only deps port well today —
  string manipulation, file I/O, basic data shaping.

Treat the Python FE as a syntax-level convenience, not a runtime
compatibility shim. The Python you write looks like Python; what
it runs as is Krypton.
