# snek status — 2026-06-13 (agent w)

## Where it is

`compiler/snek.k` is a single-file Python-ish frontend that lexes a small Python
subset and emits Krypton source. Driver + lex + parser skeleton + emit are
written (~700 lines). Test input `examples/hello.kp`.

## Blocker hit tonight

The parser was designed around `guiStateSet` / `guiStateGet` as a stash for
`(tokens, pos)`. That doesn't work on the CLI native pipeline:

```
snek-dbg: pre-init guiState from main
Segmentation fault (rc=139)
```

`guiStateSet` segfaults on a tiny constant key+value when called from the
top-level `just run {}` block — i.e. it isn't a "called from inside a func"
issue. It looks like guiState needs the GUI subsystem initialized first
(HINSTANCE, etc.) before its backing store exists, and a CLI-only PE never
hits that init path.

## Module-level `let` is also broken

Earlier in the same debug session, I confirmed
`feedback_module_mutable_globals.md` has a wider footprint than mutation:
**reads** of module-level `let CONST = "..."` from inside a function also fail
(returns the parameter value or GC-reused garbage). Workaround in the same
file: wrap every module constant in a one-line emit func.

Done in snek already: `snekKeywords()`, `snekTokKey()`, `snekPosKey()`,
`snekDeclKey()`. Refactor is clean.

## Plan to unblock

Two paths, take the cheaper one:

### Path A — fix guiState in the native runtime
Find where `guiStateSet` is lowered and check whether the dict-buf is
lazy-allocated. If yes, force-init at runtime entry regardless of GUI use.
Estimated: a few hours of x64.k spelunking, single-byte fix likely.

### Path B — refactor snek to thread state
Pass `tokens` as first arg to every parser func, return `"node\nnewPos"`
strings, caller splits via `getLine`. ~20 funcs to touch in snek.k. No
runtime change needed. Estimated: one focused session.

**Recommend B** for snek — keeps snek self-contained and forward-compatible
with future kcc generations. A is the right fix to file separately, but I
shouldn't make snek depend on it.

## What's solid

- Lex pass works end-to-end (produces 70 tokens for hello.kp).
- File I/O works (`readFile` on relative + absolute paths).
- `kcc -o snek.exe` builds cleanly; only the parser stage faults.
- Driver / arg parsing / `-o` flag works.

## Next session

1. Path B refactor (parserInit removed; tokens threaded).
2. Re-test end-to-end: `snek.exe examples/hello.kp` should emit Krypton
   source to stdout that, when piped through `kcc -o`, produces a working
   PE that prints "hello, world".
3. If time: add INDENT/DEDENT pass for `def`/`if`/`while`.

— w
