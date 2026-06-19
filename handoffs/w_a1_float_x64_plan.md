# Plan: A1 floating point on x64 (PE) — w-side implementation notes

**Date:** 2026-06-19. **Audience:** future agent w (me) or anyone wiring SSE2 into `compiler/windows_x86/x64.k`. Mirrors `handoff_m2wl_a1_float.md` (macho arm64 reference) and `compiler/macos_arm64/macho_arm64_self.k`.

## Why this isn't done yet

The kr_bufsetqwordat fix (today, raw-store mirror of macho) was needed before A1 — Tier-B regression is bigger blast radius. Doing A1 now would mean rebuilding x64.k twice; once is bad enough at 30+ min wall + ~37 GB RAM. Land A1 in one pass after Tier-A/B is green.

## SSE2 byte sequences (REX prefix + opcode + ModR/M)

All using xmm0/xmm1 for two-operand ops:

| op | bytes | mnemonic |
|----|-------|----------|
| addsd xmm0,xmm1 | `F2 0F 58 C1` | add |
| subsd xmm0,xmm1 | `F2 0F 5C C1` | sub |
| mulsd xmm0,xmm1 | `F2 0F 59 C1` | mul |
| divsd xmm0,xmm1 | `F2 0F 5E C1` | div |
| sqrtsd xmm0,xmm0 | `F2 0F 51 C0` | sqrt |
| ucomisd xmm0,xmm1 | `66 0F 2E C1` | compare (sets ZF/CF/PF) |
| cvtsi2sd xmm0,rax | `F2 48 0F 2A C0` | int64→f64 (REX.W) |
| cvttsd2si rax,xmm0 | `F2 48 0F 2C C0` | f64→int64 trunc (REX.W) |
| roundsd xmm0,xmm0,N | `66 0F 3A 0B C0 NN` | floor=0/ceil=1/trunc=3/nearest=0 (SSE4.1, all post-2008 CPUs) |
| movsd xmm0,[rax] | `F2 0F 10 00` | load box |
| movsd [rax],xmm0 | `F2 0F 11 00` | store box |
| xorpd xmm0,[sign_mask] | `66 0F 57 05 disp32` | fneg via xor with 0x8000_0000_0000_0000 |

Comparisons: ucomisd then setcc:
- `eq` = ZF=1 ∧ PF=0 → `setnp al; setz cl; and al,cl`
- `lt` = CF=1 ∧ PF=0 → `setnp al; setb cl; and al,cl`  (note: ucomisd's CF=1 means a<b)
- `gt` = CF=0 ∧ ZF=0 ∧ PF=0 → `setnp al; seta cl; and al,cl`

## __text helpers (appended after __rt_alloc, like macho's 4)

### `__f_load1` — RCX → xmm0
```
cmp rcx, 1<<32        ; B9 imm32 (for [boundary]?) Need 1<<32 = 0x100000000 which is 5-byte imm. Use mov r9,imm64.
mov r9, 0x100000000   ; 49 B9 00 00 00 00 01 00 00 00  (10 bytes)
cmp rcx, r9           ; 4C 39 C9                       (3)
jb int_path           ; 72 06                          (2)  — short jump +6 to int_path
movsd xmm0, [rcx]     ; F2 0F 10 01                    (4)  — deref box
ret                   ; C3                             (1)
int_path:
cvtsi2sd xmm0, rcx    ; F2 48 0F 2A C1                 (5)
ret                   ; C3                             (1)
```
Total ~26 bytes.

### `__f_load2` — RDX → xmm1 (same logic, target xmm1)
```
mov r9, 0x100000000
cmp rdx, r9
jb int_path
movsd xmm1, [rdx]     ; F2 0F 10 0A
ret
int_path:
cvtsi2sd xmm1, rdx    ; F2 48 0F 2A CA
ret
```

### `__f_box` — xmm0 → RAX (allocate 8B box, store)
```
push rbp; sub rsp,32  ; preserve frame + shadow space for kr_alloc
movsd [rsp+24], xmm0  ; spill xmm0 (kr_alloc may clobber)  (F2 0F 11 44 24 18)
mov rcx, 8            ; alloc size (rdx unused for kr_alloc)
call [kr_rawalloc IAT]
movsd xmm0, [rsp+24]  ; restore
movsd [rax], xmm0     ; store double in box
add rsp,32; pop rbp
ret
```
Total ~30 bytes. (NOTE: kr_rawalloc is the GC-friendly allocator — same path bufNew uses.)

### `__f_format` — RCX=val_ptr, RDX=prec_str → RAX=string
Big helper. Pattern (mirrors macho 59 instr):
1. cmp rcx,1<<32; load box xor scvtf
2. fcmp to 0.0; cset neg_flag
3. fabs xmm0
4. scale = 10^prec
5. xmm0 = round(xmm0 * scale)
6. digits = cvttsd2si xmm0
7. alloc 48B buffer, write right-to-left: digits → frac_chars → '.' → int_chars → optional '-'
8. return buffer

Defer this one — simpler kr_itoa-style str builder + integer manipulations.

## FE-emit handlers in x64.k

Add new branches in the IR dispatch loop (around line 2200-2500 where BUILTIN is handled):

```
if op == "BUILTIN" {
    if a1 == "fadd" || a1 == "fsub" || a1 == "fmul" || a1 == "fdiv" {
        // pop 2 args → call __f_load1 with arg0 in rcx, __f_load2 with arg1 in rdx
        // do the fop, call __f_box, push result
        movRcxFromRsp(vstBase + (vsp-2)*8)
        movRdxFromRsp(vstBase + (vsp-1)*8)
        callTextHelper(__f_load1)
        callTextHelper(__f_load2)
        emit fp_op_bytes        // 4 bytes
        callTextHelper(__f_box) // returns rax = box pointer
        movRspFromRax(vstBase + (vsp-2)*8)
        vsp -= 1
    }
    // ...
}
```

## PUSH_FLOAT lowering

FE emits `PUSH 3.14` for float literals (per `handoff_m2wl_a1_float.md` comment "FE lexes float literals → IR PUSH 3.14"). The x64 PUSH op currently does `LEA RAX, [rip+disp]` for ALL pushes — including string-pointer-to-"3.14". That's fine for fprint/concat. For fp arithmetic, __f_load1 will see a pointer > 1<<32, treat it as a box pointer, and `movsd xmm0, [box]` — but the box doesn't contain valid f64 bits; it contains the ASCII "3.14".

Two options:
(a) **macho-style runtime materialization** — FE emits a special PUSH_FLOAT opcode that lowers to: PUSH int M, PUSH int scale, BUILTIN intToFloat ×2, BUILTIN fdiv. Avoids backend compile-time IEEE754. Backend just runs the existing path. Most portable.
(b) **Compile-time IEEE754 in x64.k** — parse the "3.14" string, write 8 bytes of IEEE754 into rdata, emit LEA for box pointer. Faster runtime but backend gains a float-parser.

Recommend (a) — matches macho, minimal x64.k changes.

FE check: is `PUSH 3.14` already emitting `PUSH_FLOAT`? Per macho there's `BUILTIN_FLOAT` paths. Need to verify the IR shape compile.k uses for float literals on Windows; currently PUSH literal might just LEA a string ptr and fp builtins blow up.

## Polymorphic NEG

`-3.14` lowers to `PUSH "3.14"; NEG`. The current x64 NEG (`kr_neg` runtime func) is int-only (atoi+negate+itoa). Mirror macho's polymorphic shape:
```
NEG handler:
  cmp rcx, 1<<32
  jae fp_path
  ; existing int path
fp_path:
  movsd xmm0, [rcx]
  xorpd xmm0, [sign_mask_in_rdata]
  call __f_box
  ret
```

`sign_mask` is 16 bytes in rdata: `0x8000000000000000, 0x0000000000000000`.

## Estimated size

- 3 helpers (~80 bytes total) + __f_format (~200 bytes)
- ~12 builtin handlers (fadd/fsub/fmul/fdiv/fsqrt/ffloor/fceil/fround/flt/fgt/feq/intToFloat/floatToInt/fformat)
- NEG polymorphism
- sign_mask rdata constant

~400-500 lines added to x64.k.

## Test surface

`tests/test_float.k` — fully covers everything above + operator-form (a+b on f64-typed locals) + compound assign + int-promote. Add `windows` to the skip-removal in `build.sh` once this lands.

## What's MISSING for parity with macho

- transcendentals (sin/cos/log) — not in FE surface, deferred
- f32 / single-precision — not in FE, deferred
- NaN/Inf semantics in fformat — currently macho probably doesn't either; check at impl time
