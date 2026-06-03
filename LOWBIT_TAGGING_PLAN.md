# Low-bit integer tagging for the macOS arm64 backend — design + staged plan

Goal: replace the **magnitude-based** int/ptr discrimination (a value ≥
`0x100000000` is a pointer) with **low-bit tagging**, so integers can hold the
full range needed by ALL programs — including the backend's own vaddr math
(`0x100000000`+) — and the native toolchain can self-host the backend (the last
clang use). Magnitude-tagging fundamentally can't work: the backend's vaddr ints
live in the same numeric range as real pointers (TEXT/DATA at `0x1000xxxxx`).

## Representation

- **Integer** value v is stored as `(v << 1) | 1` (low bit = 1). Range: 63-bit
  signed. Untag = arithmetic shift right 1 (`asr x, x, #1`).
- **Pointer** (heap/string/struct/buf) stays a raw address. All allocations are
  ≥ 8-byte aligned, so the low 3 bits are 0 → low bit = 0.
- **Discriminator**: `(value & 1)` → 1 = int, 0 = pointer. (Replaces the 11
  `cmp x, 0x100000000` magnitude checks.)

This is the OCaml/standard scheme. Pointers unchanged; only ints gain a tag.

## Tagged arithmetic (operands a,b already tagged)

- ADD: `a + b - 1`   (since (2a+1)+(2b+1) = 2(a+b)+2; −1 → 2(a+b)+1) ✓
- SUB: `a - b + 1`
- NEG: `2 - a`        (−(2a+1)+... → 2(−a)+1 = 2−2a−1+... ; compute as `(xzr - a) + 2`)
- MUL: untag both (`asr`), `mul`, retag (`(r<<1)|1`)
- DIV/MOD: untag both, op, retag
- Comparisons (LT/GT/LE/GE): tagged ints compare with the SAME ordering as
  untagged (the tag is the LSB and identical on both), so `cmp a,b; cset` still
  works for the int path — NO untag needed. The string path (both ptr, low bit 0)
  uses the existing strcmp. EQ/NE already polymorphic — switch its discriminator
  to low-bit.

## Site inventory (macOS arm64 backend, ~94 op branches)

PRODUCE an int (must TAG the result):
- `PUSH_INT` (tag the literal at emit: emit `(v<<1)|1`)
- arithmetic ADD/SUB/MUL/DIV/MOD/NEG
- builtins returning ints: `len`, `count`, `charCode`, `toInt`/`parseInt`,
  `indexOf`, `lineCount`, `length`, `listIndexOf`, `countOf`, `abs/min/max/...`,
  `argCount`, `bufGet*`, comparison results, `isTruthy`, boolean literals.

CONSUME an int (must UNTAG the arg):
- `fromCharCode`, `substring` (lo/hi), `INDEX`/`s[i]`, `repeat` count,
  `padLeft/padRight` width, `getLine` idx, `bufGet/SetByte` offset, `exit` code,
  socket args, etc.

DISCRIMINATOR (magnitude → low-bit), 11 sites:
- EQ/NE, the print/`toStr` int-vs-ptr branch, `isTruthy`, any `cmp x,0x100000000`.

OPAQUE (no change — move values without interpreting): LOAD/STORE_SLOT,
LOAD/STORE_GLOBAL, DUP, POP, PUSH_STR, JUMP/JUMPIFNOT (JUMPIFNOT tests truthiness
→ untag/compare-to-tagged-0=`1`), CALL/RETURN, sb*/buf handles (pointers).

## Booleans / truthiness
- `false`/0 → tagged `1` (0<<1|1). `true`/1 → tagged `3`.
- JUMPIFNOT / NOT / isTruthy: "is it falsy?" = value == tagged-0 (`1`) OR empty
  string. Update the truthiness check accordingly.

## Cross-backend / IR note
The IR is representation-agnostic (ops, not value encodings). Only THIS backend's
runtime changes. The C backend (compile.k → C) and the frontend are untouched.
So the IR a tagged-backend program emits is identical; only how THIS backend's
emitted code represents values at runtime changes.

## Staged execution (each stage: build host in /tmp, full regression, NEVER
touch committed seeds until the whole thing self-hosts + regresses clean)

1. PUSH_INT tag + ADD/SUB/NEG tagged + the int/ptr discriminator → low-bit.
   Test: `kp(toStr(2+3))`, comparisons, big ints (`0x100000000`).
2. MUL/DIV/MOD untag/retag. Test arithmetic suite.
3. Int-producing builtins tag results (len/charCode/toInt/indexOf/lineCount/...).
4. Int-consuming builtins untag args (fromCharCode/substring/INDEX/repeat/...).
5. Truthiness (JUMPIFNOT/NOT/isTruthy) + booleans.
6. toStr/print int branch via low-bit.
7. Full regression (all stdlib + examples), then the self-host fixpoint, then
   backend self-host (native frontend compiles macho_arm64_self.k — the literal
   `0x100000000` must now work).
8. Only then: refresh + commit seeds.

## Risk
This rewrites the native value representation. A single missed tag/untag =
silent wrong results (not a crash). Mitigation: stage + test each builtin in
isolation; keep the magnitude-based committed seeds as the safety net until the
tagged backend passes the full suite AND self-hosts twice (stable).
