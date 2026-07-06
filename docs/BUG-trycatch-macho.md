# BUG: try/catch/throw unimplemented in native backends (macOS SIGILL/SIGSEGV)

**Found:** 2026-06-20 (macOS backend, macOS arm64). **Test:** `tests/test_try_catch.k`
fails — `FAIL basic throw` then crash (signal 4 SIGILL in the suite, 139 SIGSEGV
standalone).

## Root cause (definitive)
`compiler/compile.k` emits IR opcodes **`TRY <label>` / `THROW` / `ENDTRY`** for
try/catch/throw (compile.k:1896, 2654-2656). The **native backend
`compiler/macos_arm64/macho_arm64_self.k` has no handler for any of them** — its
opcode dispatch (~lines 1809-2551: FUNC/LOCAL/LOAD/STORE/CALL/RETURN/PUSH/arith/
LABEL/JUMP/JUMPIF*/BUILTIN/POP/END…) simply lacks TRY/THROW/ENDTRY/CATCH cases, so
they're **silently skipped**.

Effect, for `try { throw "X" } catch e { caught = e }`:
- `TRY`/`ENDTRY` → skipped (no handler set up).
- `THROW` → skipped, so the value pushed by `PUSH "X"` is **never consumed** →
  value-stack imbalance.
- control falls through `JUMP _tryend` → **the catch block is jumped over** →
  `caught` keeps its old value ("no"); then the leftover stack entry corrupts the
  function epilogue / gcShadow math → **SIGILL/SIGSEGV**.

No backend implements it: `-r` (native run) gives the same wrong `no`; there's no
interpreter/C reference to port from. Broken on **all** native targets, not just
macho.

## Fix plan (it's a feature impl, ~hours, self-hosting → test carefully)
Implement setjmp/longjmp-style exceptions in the arm64 backend. Three sites in
`macho_arm64_self.k`:
1. **Pre-pass** (1809-2551): translate `TRY label` / `THROW` / `ENDTRY` into curOps
   tokens.
2. **Size pass** (~2764, `if opTok == ... { emit <words> }`): give each new token its
   instruction-word count for label resolution.
3. **Byte-emission pass**: emit the arm64 for:
   - `TRY label`: push a catch record {catch-label addr, value-stack ptr, FP, LR} onto
     a global **catch stack**.
   - `ENDTRY`: pop the catch stack (normal, no-throw exit).
   - `THROW`: pop the thrown value; pop the top catch record; restore VSP/FP/SP/LR
     (this is the cross-function unwind — the SIGILL case where `throw` is inside a
     called fn, e.g. `mayThrow`); push the value; `br` to the catch-label addr. The
     catch label's IR already does `STORE e` to bind it.

Same-frame throw (test "basic throw") only needs VSP restore + branch; cross-function
("throw from func") needs the full SP/FP/LR restore (longjmp).

## Scope note
This is the hardest of the 7 macOS test fails. The other 6 (assertions in booleans/
buffer/env_ops/negative_nums/unixconnect, + line_ops SIGTRAP) are likely smaller and
better release wins to do first. Track try/catch as a focused codegen task.
