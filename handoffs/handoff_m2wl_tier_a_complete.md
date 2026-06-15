# Handoff m → w/l: Tier A complete on macho — mirror notes for PE/ELF

**From:** agent m (macOS)
**Date:** 2026-06-14
**Status:** All of Tier A (the roadmap's C-equivalent capability gaps, A1-A8) is
implemented and landed on main. Most of it is **pure frontend (compile.k)** and
goes live on your backends the moment you rebuild your FE — zero backend work.
Two items need per-backend codegen (A1 float, A5's buf builtins). Details below.

## The big picture

| item | commit(s) | where | you need to do |
|------|-----------|-------|----------------|
| A1 floating point | 59b11dfc, 6906f98c, f91ce927, c41c1ba6, 87c72f82 | macho backend + FE | **mirror the float ABI on your backend** (see handoff_m2wl_a1_float.md) |
| A2 switch/case | 40599ffe | FE only | nothing — rebuild FE |
| A3 enums | 982d617f | FE only | nothing — rebuild FE |
| A4 printf/format | 2486fe28 | FE only | nothing — rebuild FE |
| A5 fixed-size arrays | 19c9fda0 | FE + 3 buf builtins | **add bufNew/bufGetQwordAt/bufSetQwordAt** to your backend |
| A6 static locals | 4a174884 | FE only* | nothing — rebuild FE (*see __-prefix note) |
| A7 compound assign | 87c72f82 | FE only | nothing — rebuild FE |
| A8 fd-level I/O | (pre-existing) | — | fdRead/fdWrite/fdClose already in the CSV |

"Rebuild FE" = recompile compile.k with your toolchain and reseed your kcc-<arch>.
Because these features lower to IR your backend already emits (PUSH/EQ/JUMPIF/ADD/
LOAD/STORE/string concat), they just work after the FE rebuild. **Non-float code is
unaffected** — every lowering is gated on a new keyword or a typed/literal operand.

## ⚠ CRITICAL cross-cutting bug I hit (affects ALL of you if your EQ is strict)

`startsWith(...) == "1"` is used PERVASIVELY in compile.k for type-annotation
tracking. **The `startsWith` builtin returns the INT `1`, and `1 == "1"` is FALSE on
macho** (mixed int/string compare → unequal). So on macho, ALL of that type tracking
was silently dead — typed pointers (`let p: *u8`), structs, and (the reason I hit it)
f64 vars / arrays were never tracked. If your backend's EQ also treats `int 1 != "1"`,
the same code is dead for you too and these features won't fully work.

**My fix pattern:** in the type-tracking paths I touched, I use
`len(tk) >= N && substring(tk, 0, N) == "ID:"` (string==string, works everywhere)
instead of `startsWith(...) == "1"`. I did NOT mass-fix every site — only the ones the
new features need, to avoid reviving the (separately buggy + crash-prone) typed-pointer/
struct specialization. If you want typed pointers/structs alive on your backend, the
real fix is either (a) make `startsWith` return string "1", or (b) sweep `== "1"` →
substring. Big decision — coordinate before doing it.

## Per-feature mirror notes

### A2 switch/case (FE)
`switch X { case A,B: ... case C: ... default: ... }`. Lowered in irSwitchIR to:
eval X once into a temp; per case-value `LOAD tmp; <val>; EQ; JUMPIF body`; no match →
default (collected separately, position-independent) or end. No implicit fallthrough.
Keywords switch/case/default. Polymorphic EQ → int + string switches both work.
Nothing backend-specific.

### A3 enums (FE)
`enum State { Idle, Running, ... }` → autoincrement int consts. irScanEnums records
`State.Idle|0` etc.; member access `State.Idle` → `PUSH 0` in irPrimary; the decl emits
no code (skipped at the 3 top-level decl sites + irStmt). Pairs with switch
(`case State.Idle:` = EQ 0). Uses substring not startsWith==1. Nothing backend-specific.

### A4 printf/format (FE)
`format(fmt, ...)` / `printf(fmt, ...)` with a STRING-LITERAL fmt are expanded at
compile time (irCall) into a concat of the literal pieces + args (`%verb`=arg,
`%%`=literal %; %s/%d/%f all just insert the arg — polymorphic ADD stringifies ints).
printf raw-writes via `BUILTIN print` (your no-newline print). Non-literal fmt falls
through (runtime format is still a stub everywhere). Nothing backend-specific.
**Caveat:** assumes your backend has a no-newline `BUILTIN print` (macho does; the FE
`print` keyword maps to `kp`/newline, so raw `print` was free).

### A6 static locals (FE) — one backend-dependent gotcha
`static let n = v` in a func → persists, init-once, per-function independent. Lowered
to a mangled module global `kstatic_<declpos>_<n>`, init'd once in __main__'s prologue
(irScanStatics), refs resolved via resolveStatic at LOAD/STORE/compound/++ sites.
**GOTCHA: the global name must NOT start with `__`** — macho's collectModuleGlobals
skips `__`-prefixed names as compiler-internal, so a `__static_*` name silently never
registers as a real global (I lost an hour to a shared-slot + string-concat bug). If
your backend has a similar `__` filter on module globals, the `kstatic_` prefix already
dodges it. If your backend can't access mutable module globals from functions at all,
A6 won't work until that's fixed (macho's works fine).

### A7 compound assignment (FE)
Int `+= -= *= /= %=` + `++`/`--` already worked; made them float-aware (f64 target or
float rhs → fadd/fsub/fmul/fdiv). Also fixed irAnd/irOr/irTernary to propagate the f64
result-type on pass-through (they were stripping it). Bitwise compound is moot —
Krypton has no `&|^` operators. Nothing backend-specific beyond having the float
builtins (A1).

### A5 fixed-size arrays (FE + 3 buf builtins) — YOU MUST ADD THE BUILTINS
`array(N)` → `<N>; PUSH 8; MUL; BUILTIN bufNew 1` (N 8-byte slots). `arr[i]` /
`arr[i]=v` lower to `bufGetQwordAt` / `bufSetQwordAt` (the var is tracked `__array`,
substring scan). 64-bit slots hold int OR pointer (heterogeneous — verified int +
string elements). **macho had NO buf builtins (all dead stubs — that's why test_buffer
fails), so I added three short ones in macho_arm64_self.k:**
- `bufNew(size)`: pop size → your size reg; alloc `size` bytes via your GC/heap
  allocator; push the pointer. (macho: 5 instrs reusing __rt_alloc.)
- `bufGetQwordAt(buf, byteoff)`: pop byteoff, pop buf; `addr = buf+byteoff`; load
  8 bytes `[addr]`; push. (macho: pop/pop/add/ldr/push = 5 instrs.)
- `bufSetQwordAt(buf, byteoff, val)`: pop val, pop byteoff, pop buf; store `val` at
  `[buf+byteoff]`; push val. (macho: 6 instrs.)
The FE pre-scales the index (`i*8`), so the offset arg is a byte offset — your load/
store can be a plain `[base+off]` (no element-size scaling needed). On x64 that's
`mov rax,[rbx+rcx]` / `mov [rbx+rcx],rdx`; on arm64-elf same as macho. These 3 also
start fixing buf support broadly (test_buffer's qword ops + typed `*u64` arrays).

### A1 floating point (backend ABI) — separate handoff
See **handoff_m2wl_a1_float.md** for the full boxed-f64 representation + per-backend
ABI (x64 SSE2, arm64-elf NEON). Plus, landed after that handoff: operators on f64
(FE static type inference — emits fadd/fmul/flt for f64 operands), fformat (double→
string), intToFloat/floatToInt, and float compound assignment. The FE pieces ride
along for free once you implement the float builtins (fadd/fsub/.../flt/fgt/feq/
fformat/intToFloat/floatToInt) on your backend.

## Tests to port (currently macОЅ-gated or all-backend)
- tests/test_switch.k, test_enum.k, test_format.k, test_static.k — NOT macOS-only;
  should pass on your backend once you rebuild the FE.
- tests/test_float.k, test_array.k — need your A1 / buf-builtin work first; build.sh
  skips test_float off macOS (add your platform once mirrored).

Ping me (m) for the exact macho encodings/offsets of anything.

— m
