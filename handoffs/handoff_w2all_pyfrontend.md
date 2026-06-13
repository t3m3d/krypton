# w → all : Python frontend prep + coordination

**From:** agent w (Windows)
**To:** all (m, l, future-w, and Brian's external Copilot run)
**Date:** 2026-06-13
**Status:** prep work in flight; FE scaffolding will be done externally
via Microsoft Copilot.

## Context

Brian is going to use Microsoft Copilot to scaffold a Python-style
frontend for Krypton in ~4 prompts (lexer / parser / AST / lowering
skeleton). The new FE will sit alongside the existing Krypton FE in
`compile.k` — same IR target, same backends. The goal isn't to clone
Python — it's a Python-shaped surface over the Krypton IR / runtime /
GC / native backends.

Until that scaffolding lands, the rest of us can knock out the
non-FE prep work so the new FE has a real stdlib + spec to plug
into instead of inventing semantics in parallel.

**Public-facing surfaces should NOT promise "Python-style frontend" yet.**
The README / CHANGELOG / krypton-lang.org keep their current framing
until the Copilot-scaffolded FE actually parses Python. Internal
roadmap docs (this one, `handoff_w2all_overall.md`) can use the
"Python-style FE + C++-grade capability" framing as a north star.

## The prep work split

Four categories, all conflict-free with whatever the Copilot output
looks like:

### 1. Python-named stdlib polyfills *(w is taking — IN FLIGHT)*

`stdlib/builtins.k` mapping every Python builtin we can today onto
existing `kr_*` builtins / fp.k / etc. Plus `stdlib/list.k`,
`stdlib/dict.k`, `stdlib/string.k`, `stdlib/io_py.k` exposing
method-call shapes Python users expect (`x.append(v)`,
`s.split(",")`, `s.startswith("p")`, etc.).

Doable today because:
- Krypton's data model already covers strings + comma-list +
  newline-list. Python `list` / `dict` map cleanly with thin
  wrappers.
- `kr_*` builtins already do ~70% of Python's builtin coverage
  (`len`, `range`, `enumerate`, `zip`, `map`, `filter`, `abs`,
  `min`, `max`, `all`, `any`, `chr`, `ord`, `hex`, `bin`, `id`,
  `input`).

Things that BLOCK on roadmap items in
`handoff_w2all_overall.md`:
- `float(x)` / `1.5e-3` / `math.sin` → blocked on **A1 floating
  point**.
- `class C: ...` → blocked on a structural type / dispatch design
  (Tier B-ish).
- Real `try / except` → blocked on the exception design (TBD).
- `decorator` syntax → needs FE work, can simulate via
  higher-order functions for now.

For each Python builtin the polyfill will be one of:
- **alias** — same shape, just renamed (`print`, `len`, `range`,
  `abs`, `min`, `max`, `hex`, `bin`, `chr`, `ord`).
- **shim** — re-exposes existing builtin with Python-friendly
  defaults / arg order (`enumerate`, `zip`, `sorted`).
- **polyfill** — full Krypton implementation on top of primitives
  (`sum`, `reversed`, `repr`).
- **stub** — explicit "not yet" with a clear error message
  (`type`, `isinstance`, `class`-related).

### 2. Python → Krypton IR lowering spec

A `docs/python_to_kir.md` mapping each Python construct to the IR
op sequence the new FE should emit. Catches gaps before Copilot
hits them. **Open for any agent to pick up — m or l could do this
while w handles #1.**

Sections to cover:
- assignments (simple, augmented, tuple-unpacking)
- if / elif / else
- while / for-in
- def / lambda / closures (capture semantics)
- class — what subset we support (single inheritance, no
  metaclass, no `__dunder__` runtime hooks)
- dict / list / set / tuple literals + comprehensions
- f-strings → existing string concat / format
- try / except / finally → maps to ??? (open question)
- with-statement → maps to `defer` once that lands
- decorators → higher-order function rewrite
- generators / yield → coroutine on top of B5 goroutines (defer
  until B5 lands)

### 3. Python feature compat matrix

Short `docs/python_compat.md` listing **what we explicitly will NOT
support** so Copilot doesn't waste prompts on rabbit-holes:

- No GIL semantics — Krypton concurrency is goroutine-based once
  B5 lands.
- No `__dunder__` runtime hooks (no `__getattr__`, no `__setattr__`,
  no metaclasses).
- No `eval` / `exec` / `compile` runtime entry.
- No monkey-patching builtins (the polyfills above are immutable
  imports).
- No multiple inheritance — at most one base class.
- No descriptors, properties via builtin syntax (decorator-based
  `@property` is the maximum).
- No async / await as Python sugar — `go func()` + channels is
  the concurrency model.
- No `pickle` / `marshal` — use a stdlib JSON / explicit serialise.
- No `import` of arbitrary C extensions — Krypton FFI is `head:`
  bindings.

### 4. Skeleton `compiler/python_frontend/` directory layout

A placeholder directory + file headers so Copilot has somewhere to
write each piece. Skeleton only — no implementations. **Defer until
Copilot's first output lands; let Copilot pick the layout if it
prefers something else.**

## Order of operations

1. **(in flight)** w writes `stdlib/builtins.k` + the matching
   list / dict / string modules. Shipped under
   `import "k:builtins"` etc. — does NOT enable Python syntax,
   just makes Python-named functions callable from existing
   Krypton code.
2. **(open)** m or l writes `docs/python_to_kir.md`. Whoever picks
   it up, post a one-line ack in handoffs/ so the other doesn't
   double up.
3. **(open, Brian or any agent)** Brian's Copilot run scaffolds
   the FE. Output goes into `compiler/python_frontend/` (or
   wherever Copilot decides).
4. **(post-scaffold)** docs/python_compat.md gets reconciled with
   what Copilot actually emitted vs the planned list.
5. **(later, blocked on roadmap items)** Floating-point support
   unblocks `float`, `math.*`. Class system unblocks `class`.
   Goroutines unblock `async` mapping. Each is a separate work
   stream from `handoff_w2all_overall.md`.

## Cross-platform note

The Python FE produces the same Krypton IR every backend already
consumes. **w / m / l backends need ZERO changes** for the FE to
work — that's the whole point of going through IR. Backend-side
work only kicks in for the roadmap items that the FE depends on
(floats, classes, goroutines).

## Naming

The new file extension for Python-frontend Krypton is **TBD** —
options:
- `.pyk` — clear lineage, signals "Krypton with Python flavor"
- `.kpy` — "Krypton, Python frontend"
- `.kp`  — short, ambiguous (collides with the `kp` print alias)
- reuse `.k` and detect Python syntax automatically (cute but
  fragile; the lexers diverge enough that auto-detection has
  edge cases)

w's vote: `.pyk` for clarity. Brian / Copilot decision.

— w

[[handoff_w2all_overall]] [[project_ks_unification]]
