# Linux kcc → Windows parity (builtin gap) — agent L, 2026-06-04

Goal: bring Linux `elf.k` builtin coverage up to Windows `x64.k`. Windows links a
runtime DLL (`krypton_rt.dll`) so it gets every `kr_*` for free; Linux **inlines**
its runtime in `elf.k`, so each builtin must be implemented as native x86-64.

## The gap (verified: present in x64.k, missing in elf.k)

### A. Backend-only — front-end ALREADY emits `BUILTIN <name>`; just add to elf.k
- `min`, `max`           (2-arg int → int; can be **inline**, no helper)
- `hex`, `bin`           (int → string; needs a format helper)
- `padLeft`, `padRight`  (string,int[,pad] → string; helper)
- `bufGetDword/SetDword` + word/qword variants (buffer ops; helpers)

### B. CALL-resolved — front-end emits a generic `CALL <name>`; Windows maps the
name to a DLL symbol (x64.k:1443). Linux needs EITHER front-end recognition
(emit `BUILTIN`) + elf.k impl, OR an elf.k call-name → inline-helper resolver.
- bitwise: `bitAnd bitOr bitXor bitNot shl shr`  (high value, simple int asm)
- `structGet structSet`
- pointer/FFI: `ptrAdd ptrDeref ptrIndex ptrToInt intToPtr rawAlloc rawFree
  rawRealloc rawRead* rawWrite* sizeof callPtr1..4`  (unsafe; lower priority)

### C. Windows-ONLY — NOT real parity gaps (skip on Linux)
`set_wndproc wndproc_addr handleOut/Get/Valid/Int toHandle` (Win32 GUI/handles),
`rdtsc pause mfence/lfence/sfence` (x86 fence intrinsics, niche). GC API
(`gc_*`) is mostly Windows-debug surface — confirm need before porting.

### Already in elf.k (done): reverse, repeat, abs, pow, sockets, exec, shellRun,
byte-buffers (bufNew/bufSetByte/bufGet*At), environ, unixConnect.

## Priority
1. **bitwise** (bitAnd/Or/Xor/Not/shl/shr) — most-requested, simplest asm. CALL-
   type, so needs FE recognition too (mirror x64.k:1443 mapping the other way:
   make compile.k emit `BUILTIN bitAnd`, or resolve in elf.k's CALL path).
2. **min/max** — inline, trivial, backend-only.
3. **hex/bin/padLeft/padRight** — string-format helpers, backend-only.
4. struct get/set, then ptr/raw (FFI, advanced).

## elf.k builtin-add recipe (helper-based, e.g. mirror `abs`)
1. `func emitKr<Name>Code(thisVAddr, ...)` — the native asm helper (~L1583 abs).
2. size const `kr<Nm>Sz = hexBytesLen(...)` and `kr<Name>VAddr = <prev>VAddr +
   <prevSz>` in the vaddr chain (~L5440).
3. Thread `kr<Name>VAddr` through the **giant `emitFuncCode` param list**
   (def ~L3697 AND call ~L5510) — easy to miss; both sites.
4. `opByteSize`: `if op == "BUILTIN_<NAME>" { emit N }` (~L3171) — MUST equal the
   emit byte count exactly (verify with the awk sum: hexByte=1, hexDword=4).
5. name→op: `} else if bname == "<name>" { opSb=sbAppend(opSb,"BUILTIN_<NAME>") }`
   (~L3492).
6. emit block in emitFuncCode: `} else if op == "BUILTIN_<NAME>" { ... CALL
   kr<Name>VAddr ... }` with disp = `kr<Name>VAddr - (funcStartVAddr + off + N)`
   (~L4656).
7. Append `kr<Name>Code` to the binary's code section (with the other kr*Code).
**Inline builtins (min/max)** skip 1-3/7 — just opByteSize + name→op + an inline
emit block (no helper, no vaddr).

## Build/validate loop
Edit elf.k → rebuild elf_host (native self-host now works: `kcc.sh --native`
seeds it, no gcc) → test `printf 'just run { kp(min(3,7)) }' | kcc --native -o t`.
opByteSize mismatch → SIGILL/SIGSEGV at runtime, so verify byte counts.

— L (gap mapped; starting on bitwise + min/max)

## CRITICAL impl detail — int representation (found inspecting kr_abs)
Krypton ints are tagged: a value can be a **small int stored directly** OR a
**string pointer** (>= 0x7F000000 threshold), and negatives are normalized via
`kr_atoi`, NOT raw 2's-complement. So an int builtin must `kr_atoi` each arg to a
raw register int FIRST, operate, then return the raw int. A naive `CMP`/`AND` on
the tagged stack values is WRONG (breaks on strings-as-numbers and negatives).
`kr_abs` (L1583) is the template: `CALL kr_atoi` (RDI→RAX), then operate, `RET`.

### min/max sketch (2-arg, mirror `pow`'s emit shape: POP RSI; POP RDI; CALL; PUSH RAX = 8 bytes)
Helper `kr_min(a=RDI, b=RSI)`:
```
push rsi            ; 56  save b
call kr_atoi        ; E8 d32   RDI(a) -> RAX
mov  rbx, rax       ; 48 89 C3 a_raw -> RBX   (NB: verify kr_atoi preserves RBX;
pop  rdi            ; 5F       b                 if not, push/pop RBX around call 2)
call kr_atoi        ; E8 d32   RDI(b) -> RAX
cmp  rbx, rax       ; 48 39 C3
cmovg rbx, rax      ; 48 0F 4F D8   min -> RBX  (cmovl for max)
mov  rax, rbx       ; 48 89 D8
ret                 ; C3
```
**Must verify kr_atoi's clobber set before trusting RBX across call #2** — if it
clobbers RBX, save it. Test with negatives and string-number args.

## STATUS
- [x] **min/max** — DONE (625783b7). Inline-ish helpers, validated incl. negatives.
- [x] **bitwise** bitAnd/Or/Xor/Not/shl/shr — DONE (4031a0b1). CALL-resolved in the
      op-rewriting pass; each kr_atoi's args first. Validated 2/7/5/-7/16/64; 58/0.
      Gotcha hit & fixed: a size-var NAME collision (krShlSz vs strlen's krSlSz)
      corrupted the vaddr chain → SIGILL on every helper. **Grep existing size-var
      names before adding to the ~L5475 block.**
- [x] **hex/bin** — DONE (ba07ced6). kr_hex(107B base-16 a-f, 24B buf),
      kr_bin(99B base-2, 72B buf); both fold kr_atoi + call kr_alloc, sign+magnitude.
      Category A (FE emits BUILTIN) → name→op entry + helper, no interceptor.
      Validated hex(255)=ff hex(4096)=1000; bin(255)=11111111; 58/0.
- [x] **padLeft/padRight** — DONE (this commit). 3-arg (s, width, padStr)→string;
      kr_padleft(119B)/kr_padright(122B), SysV port of x64.k. Args saved in
      callee-saved regs (RBX/R12/R13/R14) across atoi/strlen/alloc; width<=len
      returns s directly (no strdup). FE pops 3 args POP RDX/RSI/RDI →
      RDI=s,RSI=width,RDX=pad. Validated 00007 / ...hi / 70000 / hi... / passthru;
      concat after pad confirms nul-term; 58/0.
- [ ] **NEXT: struct get/set** (structGet/structSet), then ptr/raw FFI (advanced).
      Or buffer dword/word/qword ops (bufGet/SetDword etc.) — also category gaps.

All int+string scalar builtins now at parity (min/max/bitwise/hex/bin/pad*).

## aarch64 (cross-compile from x86) — 2026-06-05
The `--arm64` path cross-compiles via the x86 front-end IR + an x86 host that
EMITS aarch64 (`compiler/linux_arm64/elf_host`), run under qemu-aarch64-static.
- [x] **min/max + bitwise** ported to `compiler/linux_arm64/elf.k`:
      min/max (CSEL, cond LT/GT), bitAnd/Or/Xor (AND/ORR/EOR), shl/shr (LSLV/LSRV),
      bitNot (MVN). Added e_and/e_orr/e_eor/e_orn/e_lslv/e_lsrv/e_csel encoders.
      min/max arrive as BUILTIN; bitwise arrive as CALL → intercepted in the CALL
      branch (opBytes + emit). Validated under qemu: min/max=3/7/0/99, bitwise
      AND/OR/XOR/shl/shr=2/7/5/16/64, nested+vars OK.
- **LIMITATION**: the arm64 backend does NOT support negative numbers yet — a
      negative value's high bit exceeds the 0x7F000000 int/string tag, so kp
      derefs it as a pointer → SIGSEGV. This is pre-existing (`kp(2-9)` also
      crashes), not from these builtins. So bitNot (always negative) and min/max
      with negative args are blocked until the backend gains negative support.
      The builtin asm is correct + forward-compatible (works once negatives land).
- aarch64 still lacks hex/bin/pad and most other builtins (young backend: it had
      only kp/len before this). Native aarch64-HOST (driver+host running ON arm64)
      is unbuilt — cross-from-x86 is the supported path.

Recipe lesson learned: the consistency check must include a **name-collision grep**,
not just an occurrence count — a reused `let krXxSz` silently shadows another size.
