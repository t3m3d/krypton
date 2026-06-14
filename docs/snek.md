# snek — Python-ish frontend for Krypton

`compiler/snek.k` is a single-file source-to-source translator. It reads
`.kp` (a subset of Python syntax) and emits Krypton source you compile
with the regular pipeline:

```sh
kcc -o snek.exe compiler/snek.k
snek.exe my.kp > my.k          # snek emits Krypton source to stdout
snek.exe my.kp -o my.k         # ...or to a file
kcc -o my.exe my.k             # then compile the Krypton normally
my.exe                          # native PE, no runtime python dependency
```

No `py` or `python` anywhere in the toolchain. The name "snek" is the
project codename; `.kp` is the source extension. House rule per project memory.

## Supported syntax

### Literals and operators

| Python              | Lowered to                  |
|---------------------|-----------------------------|
| `42`                | `42`                        |
| `"hello"`           | `"hello"`                   |
| `True` / `False`    | `"1"` / `"0"`               |
| `None`              | `""`                        |
| `a + b`             | `(a + b)`                   |
| `a - b` `a*b` `a/b` `a%b` | same                  |
| `a ** b`            | `pow(toInt(a), toInt(b))`   |
| `a // b`            | `(a / b)` (already int)     |
| `a == b` etc.       | same                        |
| `a and b`           | `(a && b)`                  |
| `a or b`            | `(a \|\| b)`                |
| `not x`             | `(x == "0")`                |

### Strings

| Python                          | Lowered to                                       |
|---------------------------------|--------------------------------------------------|
| `"hello"`                       | `"hello"`                                        |
| `f"x={a+1}"`                    | `("x=" + toStr((a + 1)))`                        |
| `s[0:5]`                        | `substring(s, 0, 5)`                             |
| `s[i]`                          | `split(s, i)` (treated as comma-list element)    |

### Lists (faux — backed by comma-strings)

| Python              | Lowered to                                      |
|---------------------|-------------------------------------------------|
| `[1, 2, 3]`         | `(toStr(1) + "," + toStr(2) + "," + toStr(3))`  |
| `xs[i]`             | `split(xs, i)`                                  |
| `len(xs)`           | `count(xs)`                                     |

### Control flow

```python
if x > 0:
    print(x)
elif x == 0:
    print("zero")
else:
    print("neg")

while n > 0:
    print(n)
    n -= 1

for i in range(10):
    print(i)

if "needle" in haystack:
    print("found")

if x is None:
    pass
```

### Functions and lambdas

```python
def add(a, b):
    return a + b

def greet(name: str, age: int) -> str:
    return f"hi {name}, you are {age}"

double = lambda x: x * 2
```

Type hints are accepted and discarded — they don't constrain the emitted
Krypton (yet; a future pass will lower them to typed locals).

### Imports

```python
import math
import string
from os import getcwd
```

Lowered to `import "k:math"` / `import "k:string"` / `import "k:os"`.
Dotted calls (`math.sqrt(x)`) use the prefix-style lowering
`mathsqrtk(x)` for known prefix-using modules (`math`, `os`, `sys`).
Other dotted calls (`s.upper()`) use the method-call style with the LHS
as the first argument: `upperk(s)`.

`from X import Y` currently emits the bare `import "k:X"`; user must
still call the names as `X.Y(...)`. Aliasing is a phase-7 item.

### Augmented assignment

`x += 1`, `x -= 1`, `x *= 2`, `x /= 2`, `x %= 3` desugar to
`x = x <op> rhs`.

### Multi-arg print

`print(a, b, c)` lowers to a space-joined toStr concat:
`print(toStr(a) + " " + toStr(b) + " " + toStr(c))`.

### Raise

```python
raise ValueError("bad input")
```

Lowered to `printErr(toStr(...))` + `exit("1")`. No `try` / `except`
in MVP — exceptions terminate the program with the error written to
stderr.

## Phase status

| Phase | Features                                                | Status |
|-------|---------------------------------------------------------|--------|
| 1     | int/str literals, names, assignment, binary arithmetic  | ✓      |
| 2     | def/return/if/else/while + INDENT/DEDENT                | ✓      |
| 3     | for/elif/and/or/not + nested blocks                     | ✓      |
| 4     | import, dotted calls, type hints, f-strings             | ✓      |
| 5     | lists, indexing, slicing, aug-assign, in/not in/is, **  | ✓      |
| 6     | lambda, raise, `**` / `//`, tuple unpacking             | ✓      |
| 7     | list comprehensions, dict literals + access,            | ✓      |
|       | try/except (try body emitted, except ignored),          |        |
|       | break/continue, assert, str/int/repr/input aliases      |        |
| 8+    | class definitions, real exception catching, generators  | TODO   |

## Known limits

- **Runtime stdlib import gap.** `import "k:math"` + calling
  `mathisqrtk(...)` segfaults on the Windows native pipeline. The
  frontend lowering is correct; Krypton's import dispatch needs the fix.
  Workaround until then: paste stdlib funcs inline. See
  `feedback_stdlib_import_native_broken` memory.
- **No exception handling beyond `raise`.** `try/except/finally` aren't
  parsed. `raise` terminates the program; user catches via process exit
  code only.
- **No class definitions.** Snek targets script-style Python.
- **No list/dict comprehensions.** Each needs hoisted helper-function
  generation; the AST traversal isn't wired yet.
- **No tuple unpacking.** `a, b = 1, 2` parses as `a = (1, 2)`-ish (bad).
- **No `f"..."`-side mods** — `f"{x:.2f}"` format specs ignored.
- **String contents containing literal `__SNEK_*__` placeholders.**
  Snek uses these as internal markers; user-strings containing them
  will round-trip wrong. Unlikely in practice.

## Architecture

- **Lexer.** Emits tokens as `KIND\tVAL\tLINE` (tab-separated -- not
  comma, since comma is a valid operator value). INDENT/DEDENT tokens
  bracket Python-significant whitespace. FSTR tokens carry the raw
  f-string content for parser-time `{...}` expansion.
- **Parser.** Recursive descent. State `(toks, pos)` threaded
  explicitly through every function -- `guiStateSet/Get` segfaults on
  CLI-only PEs (no GUI subsystem init), see `feedback_guistate_cli_broken`.
- **AST.** Length-prefixed encoding for variable-length children
  (e.g. `BIN|<op>|<llen>|<left><right>`, `LIST|<n>|<len0>|<e0>...`).
  Avoids the nested-`|`-collision class of bugs that bit earlier MVP
  versions.
- **Emitter.** Walks the program-statement list, separates IMPORTs and
  DEFs (hoisted to module scope) from the rest (wrapped in `just run
  {}`). Declared-names threaded through to emit `let x = ...` on first
  assignment and `x = ...` thereafter.
