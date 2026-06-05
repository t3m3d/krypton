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
