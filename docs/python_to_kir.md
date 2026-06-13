# Python → Krypton IR lowering spec

**Audience:** the Python frontend author (Brian's Copilot scaffolding
+ whoever maintains it after).
**Sibling docs:** `handoff_w2all_pyfrontend.md`, `handoff_w2all_overall.md`.
**Status:** living doc; fill in as constructs land. Mark as
**(shipped)** / **(planned)** / **(blocked: <roadmap-item>)** as they
move through.

## Pipeline

```
.pyk source  ──FE──>  Krypton IR  ──existing BE──>  PE / Mach-O / ELF
                          ↑
                  (same as .k source)
```

The new FE produces **the exact same IR** the existing Krypton FE
produces. That's the entire portability play: backends don't change,
runtime doesn't change, GC doesn't change. Only the syntax in front
gets a second skin.

## IR primer

A Krypton IR line is one of:

```
FUNC <name> <argcount>
PARAM <name>
LET <name>
LOAD <name>
PUSH <literal>
CALL <name>
CALLPTR <argcount>
ADD / SUB / MUL / DIV / MOD / NEG
EQ / NEQ / LT / LE / GT / GE
JZ <label> / JNZ <label> / JUMP <label>
LABEL <name>
RETURN
EMIT
INDEX
SETINDEX
BUILTIN <name> <argcount>
EXPORT <name>
GC_SHADOW_PUSH / GC_SHADOW_POP <n>
; TYPE <type>     ; comment-tags for the typed-pointer path
```

Stack-based — every IR op consumes / produces values on a per-function
op stack. Locals live in named slots (`LET <name>`, `LOAD <name>`).

This doc maps every Python construct to a sequence of these ops.

---

## Expressions

### Literals

| Python | IR sequence |
|---|---|
| `42` | `PUSH "42"` |
| `0xFF` | `PUSH "255"` |
| `0b1010` | `PUSH "10"` |
| `"hello"` | `PUSH "hello"` |
| `'hello'` | `PUSH "hello"` |
| `True` | `PUSH "1"` |
| `False` | `PUSH "0"` |
| `None` | `PUSH ""` |
| `3.14` | **blocked: A1 floating point** |
| `1.5e-3` | **blocked: A1** |

Notes:
- Krypton ints are smart-int strings. `42` and `"42"` are the same
  value at the IR level.
- `True` / `False` map to `"1"` / `"0"` — matches the existing
  `isTruthy` family.
- `None` is `""` (empty string sentinel).

### Names

```python
x
```
→
```
LOAD x
```

Names reserved by Krypton's runtime / FE today (`emit`, `func`, `let`,
`module`, `import`, `just`, `run`, `jxt`, `if`, `else`, `while`, `for`,
`in`, `return`, `closure`, `fp`) are rejected at FE pre-parse — the
Python FE rewrites them to a safe synonym (`emit` → `emit_`, etc.) or
errors with a clear message.

### Binary operators

| Python | IR |
|---|---|
| `a + b` | `LOAD a; LOAD b; ADD` |
| `a - b` | `LOAD a; LOAD b; SUB` |
| `a * b` | `LOAD a; LOAD b; MUL` |
| `a / b` | `LOAD a; LOAD b; DIV` *(integer div today — float / blocked on A1)* |
| `a // b` | `LOAD a; LOAD b; DIV` *(Krypton DIV is integer)* |
| `a % b` | `LOAD a; LOAD b; MOD` |
| `a ** b` | `LOAD a; LOAD b; BUILTIN kr_pow 2` |
| `a << b` | `LOAD a; LOAD b; BUILTIN kr_shl 2` |
| `a >> b` | `LOAD a; LOAD b; BUILTIN kr_shr 2` |
| `a & b` | `LOAD a; LOAD b; BUILTIN kr_bitand 2` |
| `a \| b` | `LOAD a; LOAD b; BUILTIN kr_bitor 2` |
| `a ^ b` | `LOAD a; LOAD b; BUILTIN kr_bitxor 2` |
| `~a` | `LOAD a; BUILTIN kr_bitnot 1` |

### Comparison

| Python | IR |
|---|---|
| `a == b` | `LOAD a; LOAD b; EQ` |
| `a != b` | `LOAD a; LOAD b; NEQ` |
| `a < b` | `LOAD a; LOAD b; LT` |
| `a <= b` | `LOAD a; LOAD b; LE` |
| `a > b` | `LOAD a; LOAD b; GT` |
| `a >= b` | `LOAD a; LOAD b; GE` |
| `a is b` | `LOAD a; LOAD b; EQ` *(string identity == value in Krypton)* |
| `a in xs` | `LOAD a; LOAD xs; CALL inlistk 2` *(list.k)* |
| `a in d` | `LOAD a; LOAD d; CALL indictk 2` *(dict.k; FE picks based on receiver type)* |
| `a in s` | `LOAD a; LOAD s; CALL containsk 2` *(string.k)* |
| `a not in xs` | `inlistk; NEG_BOOL` *(or `JZ` inverted)* |

Chained comparisons (`a < b < c`) lower to `LOAD a; LOAD b; LT; ...; LOAD b; LOAD c; LT; ... AND`. The middle expression `b` is evaluated **once**, cached in a temp local.

### Logical short-circuit

```python
a and b
```
→
```
LOAD a
JZ .skip            ; falsy: leave a on stack and skip b
POP                 ; (Krypton stack doesn't track but conceptually)
LOAD b
.skip:
```

```python
a or b
```
→
```
LOAD a
JNZ .skip           ; truthy: leave a on stack and skip b
POP
LOAD b
.skip:
```

```python
not a
```
→
```
LOAD a
BUILTIN kr_not 1
```

### Ternary

```python
x if cond else y
```
→
```
LOAD cond
JZ .else
LOAD x
JUMP .end
.else:
LOAD y
.end:
```

### Unary

| Python | IR |
|---|---|
| `-x` | `LOAD x; NEG` |
| `+x` | `LOAD x` |
| `~x` | `LOAD x; BUILTIN kr_bitnot 1` |
| `not x` | `LOAD x; BUILTIN kr_not 1` |

### Function call

```python
f(a, b, c)
```
→
```
LOAD a
LOAD b
LOAD c
CALL f
```

For functions where the FE knows the callee at compile time (top-level
`def`, imports), emit `CALL <name>`. For callable values (lambdas,
function-typed locals), emit `CALLPTR <argcount>`.

### Method call

```python
obj.method(a)
```
→ FE rewrites to the matching stdlib polyfill based on the inferred /
declared receiver type:

| Receiver kind | Lowering rule |
|---|---|
| `str` | `obj.method(a)` → `methodk(obj, a)` *(string.k)* |
| `list` | `obj.method(a)` → `methodk(obj, a)` *(list.k)* — disambiguated names: `listIndexk`, `listCountk` |
| `dict` | `obj.method(a)` → `dict<method>k(obj, a)` *(dict.k, `dict`-prefixed)* |
| struct | `obj.method(a)` → `<typename>_<method>(obj, a)` — once Tier-B classes ship |

Today: without type inference, the FE picks string-method names by
default; user can disambiguate with explicit calls if Python's runtime
dispatch is needed. Type inference (Tier B) cleans this up.

### Attribute access

```python
obj.attr
```
→ for structs: `BUILTIN getField 2` with `"attr"` pushed. For dicts
(when ambiguity exists): `dictgetk(obj, "attr", "")`. Same
disambiguation rules as method call.

### Subscript

```python
x[i]
```
→
```
LOAD x
LOAD i
INDEX
```

`INDEX` calls `kr_idx(s, i)` at runtime — handles both string-index and
list-index uniformly because Krypton's data model unifies them. For
typed pointers (`p[i]` on `*u8` etc.), the typed-pointer fast path
fires automatically (see `project_v183_phase_c.md`).

```python
x[i] = v
```
→
```
LOAD x
LOAD i
LOAD v
SETINDEX
```

```python
x[lo:hi]
```
→
```
LOAD x
LOAD lo
LOAD hi
CALL slicek    ; from list.k
```

### Comprehensions

```python
[expr for x in xs]
```
→ FE rewrites to a synthesized helper lambda + `mapk`:

```python
# rewritten internally as:
mapk(lambda x: expr, xs)
```

```python
[expr for x in xs if pred]
```
→
```python
mapk(lambda x: expr, filterk(lambda x: pred, xs))
```

```python
{k: v for x in xs}
```
→ similar reduce-style build with `dictsetk` accumulation. Pending.

Generator expressions (`(x for x in xs)`) — **blocked on B5 goroutines**
for proper lazy semantics. Today: lower to a list comprehension that
materializes eagerly with a warning.

### Lambda

```python
lambda x: x + 1
```
→
```
FUNC __lam<id> 1
PARAM x
LOAD x
PUSH "1"
ADD
EMIT
```

The FE hoists each lambda to a sibling `FUNC` with a unique name
(`__lam<position>` — same pattern as the existing native pipeline does
for `func(...) { ... }` literals).

Closures: free vars detected at FE scan time; lambda body gets a
hidden `__env` first PARAM; references to free vars rewrite to
`envGet` lookups. See `project_v20_alpha3` for the existing closure
machinery — the Python FE plugs into it unchanged.

### f-strings

```python
f"hello {name}, you are {age}"
```
→
```
PUSH "hello "
LOAD name
ADD
PUSH ", you are "
ADD
LOAD age
ADD
```

Format specs (`{x:5.2f}`, `{x:>10}`) — **blocked on A4 variadic /
formatk**. Today: lower to `strk(x)` and ignore the spec with a
warning.

### Walrus

```python
(x := expr)
```
→
```
<eval expr>
LET x
LOAD x        ; leave value on stack for the surrounding expression
```

---

## Statements

### Assignment

```python
x = expr
```
→
```
<eval expr>
LET x
```

Tuple-unpacking:

```python
x, y = a, b
```
→ FE rewrites as a sequence of LET statements with index-based
extraction from a temp:

```
<eval RHS>      ; produces a list "a,b"
LET __unp0
LOAD __unp0
PUSH "0"
INDEX
LET x
LOAD __unp0
PUSH "1"
INDEX
LET y
```

For known-size tuples the FE can skip the temp and emit direct LET
sequences.

Augmented:

```python
x += y
```
→
```
LOAD x
LOAD y
ADD
LET x
```

Same shape for `-=`, `*=`, `/=`, etc. **Blocked on A7 compound
assignment in the FE parser** — already on the roadmap.

### if / elif / else

```python
if cond:
    body
elif cond2:
    body2
else:
    body3
```
→
```
LOAD cond
JZ .elif1
<body>
JUMP .end
.elif1:
LOAD cond2
JZ .else
<body2>
JUMP .end
.else:
<body3>
.end:
```

### while / break / continue

```python
while cond:
    body
```
→
```
.loop:
LOAD cond
JZ .end
<body>
JUMP .loop
.end:
```

`break` → `JUMP .end`.
`continue` → `JUMP .loop`.

Each `while` pushes its `(.loop, .end)` pair on the FE's loop stack so
nested `break` / `continue` jump to the innermost. Standard FE
plumbing.

### for-in

```python
for x in xs:
    body
```
→
```
LOAD xs
LET __it
PUSH "0"
LET __i
LOAD __it
BUILTIN count 1
LET __n
.loop:
LOAD __i
LOAD __n
GE
JNZ .end
LOAD __it
LOAD __i
INDEX
LET x
<body>
LOAD __i
PUSH "1"
ADD
LET __i
JUMP .loop
.end:
```

The existing Krypton `for x in <list>` uses this exact shape — the
Python FE plugs into the same lowering helper in `compile.k`.

For dict iteration (`for k in d:`, `for k, v in d.items():`), use
`dictkeysk` / `dictitemsk` then loop as above with tuple-unpacking on
each iteration.

### def

```python
def f(a, b) -> int:
    return a + b
```
→
```
FUNC f 2
PARAM a
PARAM b
LOAD a
LOAD b
ADD
EMIT
RETURN
```

Return-type annotation is ignored at IR level (Krypton has no FE-level
type checker yet; types are runtime). Optional argument annotations
similarly ignored.

Default args: `def f(a, b=10):` → FE inserts a check at the start of
the body:

```
FUNC f 2
PARAM a
PARAM b
LOAD b
PUSH ""
EQ
JZ .skip
PUSH "10"
LET b
.skip:
<body>
```

`*args` / `**kwargs` — **blocked on A4 variadic + structural types**.

### class

```python
class C:
    def method(self, x):
        ...
```
→ **blocked on Tier B structural types / classes**.

Stop-gap for the FE: when a `class` appears, lower the body as a
struct of fields + sibling functions named `<C>_<method>` taking
`self` as first arg. The FE rewrites `obj.method(x)` →
`C_method(obj, x)` when receiver type is known.

Single inheritance: only the immediate base class is supported; no
MRO / multiple inheritance.

### return

```python
return expr
```
→
```
<eval expr>
EMIT
RETURN
```

Bare `return` → `PUSH ""` (None) then EMIT + RETURN.

### try / except / finally

**Blocked on the exception design (TBD).** Krypton has no exception
machinery today — `printErr` + `exit` are the runtime equivalent.

Stop-gap for the FE:
- `try:` body always runs.
- `except <Type> as e:` ignored (no exception object to bind); body
  never runs.
- `except:` body ignored.
- `finally:` body emitted inline after the try body.
- `raise X` lowers to `printErr(repr(X)); exit("1")`.

This is a placeholder; real try/except is a multi-session feature
that needs IR ops for `THROW` + `CATCH` + stack unwinding.

### with

```python
with open("f") as fd:
    body
```
→ **blocked on B1 defer** (the natural lowering).

Stop-gap: lower with-statement to its `__enter__` + body + `__exit__`
sequence inline.

### pass

```python
pass
```
→ no IR (empty statement).

### import

```python
import foo
from foo import bar
```
→ FE rewrites Python `import` to Krypton `import "k:foo"` at the
compile.k import-resolver layer. Selective import (`from foo import
bar`) brings just the named function into scope; FE tracks the
bindings.

`import foo as f` → bind `f` as the module alias for symbol-resolution
inside the function.

### global / nonlocal

`global x` → FE binds reads/writes of `x` to a module-level slot.
`nonlocal x` → FE binds reads/writes to the enclosing function's
slot (closure capture).

### del

```python
del x
```
→ for local vars: emit `PUSH ""; LET x` (NULL out). For dict items
(`del d[k]`): `dictdelk(d, k)` + LET back.

### yield / generator

**Blocked on B5 goroutines.** Generators are stackful coroutines;
without goroutines, simulate by materializing into a list — slow but
correct.

### async / await

**Blocked on B5 goroutines.** `async def` → ordinary `def`. `await`
→ direct call (synchronous). All concurrency lives in `go f()` once
B5 lands.

---

## Cross-references

- Function name pool: `stdlib/builtins.k` + `stdlib/string.k`
  + `stdlib/list.k` + `stdlib/dict.k` define the `*k`-suffixed
  surface this spec lowers to.
- IR op definitions: `compiler/windows_x86/x64.k` (search the
  emitter funcs for each op).
- Closure machinery: `project_v20_alpha3_closure_unification.md`.
- Typed pointers: `project_v183_phase_c.md` and follow-ons.
- Roadmap items referenced as "blocked on Aₙ / Bₙ":
  `handoff_w2all_overall.md`.

## Open questions for the FE author

1. **File extension.** `.pyk` is w's vote in
   `handoff_w2all_pyfrontend.md`. Brian / Copilot decision.
2. **Type inference depth.** Do we infer enough to disambiguate
   `obj.method()` between string / list / dict surfaces, or
   require explicit calls? Today: string default + warn on
   ambiguous.
3. **Indentation vs braces.** Python is indentation-significant;
   Krypton uses braces. Does `.pyk` enforce indentation, or accept
   braces too? Indentation-only is cleaner for "this IS Python";
   accepting braces lets users mix in Krypton snippets without
   reformatting.
4. **Strict mode.** Should the FE reject Python features it can't
   lower yet (raise compile error) or silently degrade (warn +
   stub)? Currently this doc assumes "warn + stub" for blocked items.

When Copilot's scaffolding lands, reconcile this doc with what
actually got built. Sections that turn out to be different from
plan can be marked **(shipped, differs)** rather than rewritten.
