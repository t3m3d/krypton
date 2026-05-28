# Handoff l → m: A1 floating point mirrored onto linux_arm64 ELF

**From:** agent l (Linux)
**Date:** 2026-05-28
**Re:** handoff_m2wl_a1_float.md (your F1 `59b11dfc` + F2 `6906f98c` on macho)
**Status:** A1 CORE DONE on linux_arm64 ELF. Commit `7097a7ca` on
`feat/arm64-native-pipeline`. Self-host reseeded, verified under qemu, no regressions.

## What landed

The full F1+F2 surface from your handoff, mirrored onto `compiler/linux_arm64/elf.k`:
- **Representation matches yours** for cross-backend parity: a float = a pointer to
  an 8-byte f64 box. Only difference: the int/ptr boundary is **VBASE = 0x7F000000**
  (this backend's existing smart-int threshold, `e_movzHi(9, 32512)`), not your
  `1<<32`. Literals materialize as M/scale via `scvtf`+`fdiv`; results box via the
  bump allocator.
- **No precise GC here** (per handoff_m2l_gc_full_port_plan.md) — boxes are
  bump-alloc'd, no reclaim. Fine for the test surface; revisit when the GC port lands.
- **No runtime type tag**; int operands auto-promote (`value < VBASE -> scvtf`).
- 17 scalar-double encoders (`e_scvtf/fcvtzs/fadd/fsub/fmul/fdiv/fsqrt/fneg/fabs/
  frintm/p/n/fcmp/fcmpz/ldrd/strd`), derived from your hex anchors, hi/lo-split for
  this backend's `wordHL(hi16,lo16)`.
- 4 helpers after `kr_readproc`: `__f_load1`/`__f_load2`/`__f_box`/`__f_format`
  (the 232-byte formatter is a 1:1 port of your `__f_format`; lr saved in x26 since
  ELF has no `stp fp,lr` helper, and the buffer alloc uses `kr_alloc` with size in
  x0).
- PUSH float detection, `BUILTIN fadd…feq + fformat`, float-aware `NEG`.
- **`cset` gotcha:** this backend's `e_cset(rd, cc)` takes the **inverted** condition
  (it feeds cc straight into CSINC, whose result is `invert(cc)`). So flt→`cset 10`
  (GE), fgt→`cset 13` (LE), feq→`cset 1` (NE), and the neg-flag in __f_format is
  `cset 5` (PL→MI). Cost me a careful read; flagging in case W hits the same on PE.

## Verified (qemu-aarch64)

arith (fadd/fsub/fmul/fdiv), compares (flt/fgt/feq), fsqrt/ffloor/fceil/fround,
int-promote (`fadd(5,2.5)`), float-NEG (`-3.14`), and **all** your fformat cases
(3.14, 3.1416 rounded, 0.05, 0.00, 10, -3.14, 0.333333). a64 baseline: **57 pass,
0 compile-fail, zero regressions** (the 5 non-passing — array/objc_smoke/enum/
format/static — are byte-identical pre vs post my change; pre-existing).

## NOT done (out of scope on this branch)

The FE in `compiler/compile.k` on `feat/arm64-native-pipeline` only emits the
**explicit** float builtins. It does **not** yet do:
- f64-typed **operators**: `a * b` with `let a: f64` still emits integer `MUL`
  (verified in the FE IR), not `fmul`.
- `intToFloat` / `floatToInt`: arrive as generic `CALL`, not BUILTIN.

So `tests/test_float.k` (which uses operators, conversions, and compound assign)
**cannot pass on arm64 yet** and stays build.sh-skipped off macOS. If your later
macho work added the FE operator/conversion type-inference, that compile.k change
needs to land on this branch — then I'll wire `intToFloat`/`floatToInt` codegen +
operator lowering on the ELF side and remove the skip. Ping me (l) when the FE
piece is on this branch.

## x86 ELF (linux_x86/elf.k) — F1 + float-NEG DONE (commit f7e73c46); fformat next

The x86 leg now has the F1 surface + float-aware NEG (SSE2: cvtsi2sd/divsd/addsd/
subsd/mulsd/sqrtsd/roundsd/ucomisd+setcc/xorpd-fneg), all INLINE via the existing
kr_alloc vaddr — no emitFuncCode 70-param threading. Verified natively
(1 0 1 1 1 1 1 1 1 1 1), no regressions. int/ptr boundary here is 0x400000 (this
backend's smart-int threshold), not arm64's VBASE. (elf_host is gitignored; driver
rebuilds from elf.k — only elf.k committed.)

x86 fformat now DONE too (commit f57dfefa): kr_fformat helper (219B), threaded
through the vaddr layout + emitFuncCode + segment, BUILTIN_FFORMAT stub. Verified
natively (3.14/3.1416/0.05/0.00/10/-3.14/0.333333/4.00).

**PARITY REACHED on A1 explicit-builtin codegen across all three backends**
(macho arm64, linux arm64 ELF, linux x86 ELF). The only gap to full macOS A1 is
the FE-level f64 operator/conversion/compound-assign work, which is on `main`, NOT
on feat/arm64-native-pipeline (verified: this branch's FE emits integer MUL for
a*b and generic CALL for intToFloat). When that FE work lands here, operators lower
to the fadd/fmul builtins all backends already have; only intToFloat/floatToInt
(generic CALLs) need a small per-backend codegen add. test_float.k stays
macOS-skipped until then.
