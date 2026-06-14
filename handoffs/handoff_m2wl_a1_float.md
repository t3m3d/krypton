# Handoff m → w/l: A1 floating point — macho-first, mirror to PE/ELF

**From:** agent m (macOS)
**Date:** 2026-06-14
**Status:** A1 CORE DONE on macho arm64 (commits `59b11dfc` F1, `6906f98c` F2,
on main, self-host converged). W was down so macOS led this one — reverse of the
usual Windows-first flow. Here's the IR shape + ABI so you can mirror on x64.k / elf.k.

## FE surface (already in compile.k, shared — no FE change needed)

The FE lexes float literals (`3.14` → IR `PUSH 3.14`) and emits these as
`BUILTIN <name> <argc>`: `fadd fsub fmul fdiv fsqrt ffloor fceil fround fformat
flt fgt feq`. **All map to hardware FP instrs — no libm, no transcendentals**
(the FE surface has no sin/cos/etc.). `ffloor/fceil/fround` = round-to-{-inf,+inf,
nearest-even}. `flt/fgt/feq` return a bool int (1/0). `fformat(value, prec)` →
decimal string.

**Critical FE gotcha:** a negative literal `-3.14` is lowered to `PUSH 3.14` +
`NEG` (unary-minus op), NOT a negative float literal. So your `NEG` op must be
made float-aware (see below) or negatives corrupt the value. Binary operators on
floats (`x * 2.0`) still emit integer `MUL` — out of scope (needs FE type-tracking
to pick fadd-vs-add); users call fadd/fmul explicitly for now.

## Representation (my choice — recommend you match for cross-backend test parity)

**Boxed f64, no runtime type tag.**
- A float value = a pointer to 8 raw f64 bytes. On macho it's >4GB (heap), which
  the existing smart-int test (`val < 1<<32` = int, else pointer) already
  distinguishes from ints. Use your backend's int/ptr boundary.
- **Literals:** materialize at runtime as `M / scale` (M = all digits as int,
  scale = 10^fracdigits) via `int→double; int→double; fdiv` — **avoids
  compile-time IEEE754 conversion** (our backends are int-only). ~15 sig digits.
- **Results:** box via an 8-byte heap alloc (GC leaf object; conservative mark
  handles it — the f64 bits are never traced as pointers).
- **No type tag:** fp builtins know their operands are floats statically (the op
  is `fadd` etc.), so they just deref the box. They **auto-promote int operands**
  (if value < boundary → int→double convert), so `fadd(5, 2.5)` works.
- Generic `print`/concat only ever see a float *after* `fformat` → string, so they
  never need to decode a box.

## macho implementation shape (translate per your ABI)

- 3 small `__text` helpers appended after the allocator (like our `__rt_alloc`):
  `__f_load1` (operand→fp-reg, int-promote-or-deref), `__f_load2` (2nd operand),
  `__f_box` (fp-reg→8-byte boxed ptr). Each fp builtin is then a short fixed-count
  sequence: pop operands, `bl __f_load1/2`, the hardware FP op, `bl __f_box`, push.
- `fformat` = a bigger helper: `scale=10^prec`; `digits = round(|v|*scale)` as one
  integer (round-to-nearest then float→int); write digits right-to-left into a
  ~48B buffer — lowest `prec` digits are the fraction, then `.`, then the integer
  part, then `-`. Handles rounding, leading-zero fractions, zero, prec=0 (no dot),
  negatives.
- **`NEG` made polymorphic:** pointer operand → deref + fp-negate + re-box; int
  operand → integer negate. (On macho this grew NEG 3→10 instrs.)

## Test

`tests/test_float.k` (macОЅ-only; build.sh skips on linux/windows until you mirror).
Validates arith + compares via `feq`/`flt` and fformat via string equality
(3.14, 3.1416 rounded, 0.05, 0.00, 10, -3.14, 0.333333). Add your platform to the
skip-removal once A1 lands on your backend.

## Per-backend ABI notes

- **x64 (w):** SSE2 — `addsd/subsd/mulsd/divsd/sqrtsd`, `cvtsi2sd` (int→double),
  `cvttsd2si` (double→int trunc), `roundsd` (floor/ceil/nearest via imm), `ucomisd`
  + setcc for flt/fgt/feq, `xorpd` with sign-mask for fneg, `andpd` for fabs. Box
  in your heap; reuse your IAT-free alloc.
- **arm64 elf (l):** identical instructions to macho (fadd/fsub/fmul/fdiv/fsqrt/
  frintm/p/n/fcmp/fcvtzs/scvtf/fneg/fabs/udiv/msub) — but elf has **no precise GC /
  no object header** (see handoff_m2l_gc_full_port_plan.md), so a boxed f64 needs
  somewhere to live; simplest interim = bump-alloc 8 bytes (no reclaim) until the
  GC port lands. x86 elf = SSE2 like Windows.

Ping me (m) for the exact macho encodings/offsets if useful.
