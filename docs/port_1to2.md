# `kcc --port-1to2` — 1.x → 2.0 migration scanner

A diagnostic-only mode that scans a Krypton source file for patterns valid in 1.x but needing attention before 2.0 ships. Exits 0 either way; emits warnings to stderr.

## Usage

```
kcc --port-1to2 source.k
```

Output one warning per pattern, plus a final tally:

```
source.k: warning [port-1to2]: bufNew() — manual heap allocation. ...
source.k: warning [port-1to2]: cfunc { } block — C-language body. ...
source.k: port-1to2 done — 2 warning(s).
```

A clean file:

```
source.k: port-1to2 clean — no 2.0 migration concerns flagged.
```

## What it flags

| Pattern | Rationale | Suggested 2.0 form |
|---------|-----------|--------------------|
| `bufNew(N)` | Manual heap allocation; lifetime cliff under future GC | `let local TYPE name` (stack alloc) when 2.0 frame layout lands; or accept that GC will reclaim |
| `rawAlloc(N)` | Bypasses GC tracking entirely | Wrap in explicit `unsafe` block or pair with `rawFree` |
| `rawFree(p)` | Only needed for `rawAlloc`'d memory | Will be a no-op for GC-tracked allocs |
| `ptrAdd(p, n)` | Raw pointer arithmetic | Typed pointer indexing: `let p: *u8 = ...; p[n]` |
| `ptrToInt(p)` | Loses GC-tracking when pointer round-trips through int | Avoid; pass typed pointers directly |
| `rawReadByte`/`Word`/`Qword` | Unbounded memory read | Typed pointer indexing with bounds-aware `*u8`/`*u32`/`*u64` |
| `rawWriteWord`/`Qword` | Unbounded memory write | Typed pointer assignment |
| `cfunc { ... }` block | C-language body — won't survive native pipeline once Win32 ABI marshalling lands | Pure-Krypton implementation calling Win32 directly via `head:` imports |
| File-scope `let X = ...` followed by `X = ...` reassign | Mutable module globals are broken in the native pipeline (silently writes per-function local instead) | Confine state to function scope or pass explicitly through call chains |

## What it does NOT flag (yet)

- Implicit conversions (`toInt(stringFromInt)`)
- Lambdas with free vars (closures don't work natively yet — but this isn't 1.x → 2.0; it's a design constraint)
- DLL imports that depend on broken Win32 marshalling (e.g., direct `Sleep(500)` works only via cfunc wrapper)

## When to run it

- Before upgrading a 1.x codebase to a future 2.0 release
- During 2.0-alpha development as a smoke test for new code
- As a CI step to prevent regressions

## Sample

`tests/port_1to2_sample.k` deliberately includes one of each flagged pattern. Running:

```
kcc --port-1to2 tests/port_1to2_sample.k
```

Should emit exactly 8 warnings.
