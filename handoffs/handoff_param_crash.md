# HANDOFF — front-end SIGSEGV on functions with parameters (2026-06-04)

**Status:** committed seed still works → toolchain runs fine TODAY, but the
front-end **cannot be reseeded** from current `compile.k`. Reseeding now ships a
compiler that crashes on every real program.

## Symptom
An FE *rebuilt from current `compile.k`* SIGSEGVs on any program that declares a
function with **≥1 parameter**. No-param funcs and function-less programs work.

```
printf 'func f(x){ emit x }\n' | kcc --ir     # → SIGSEGV (rc 139)
printf 'func f(){ emit 1 }\n'  | kcc --ir     # → OK
printf 'just run { kp(2+3) }\n' | kcc --ir    # → OK
```
The **committed seed** (old compile.k) handles param funcs correctly
(`FUNC f 1 / PARAM x`), which is why nothing is broken at runtime yet.

## Crash (gdb on the rebuilt FE)
`strlen(NULL)` — `=> cmpb $0x0,(%rdi,%rax,1)` with `rdi=0, rax=0`, then the
classic `je / inc %rax / jmp` strlen loop. A string op runs on a **NULL pointer**,
only in the func-**parameter** path.

## Bisect (definitive — same seed building each)
| commit | time | funcs/strings | param func |
|---|---|---|---|
| 55363d65 | 02:30 | 115 / 1553 | ✅ works |
| ba8fb9f6 | 02:53 | 112 / 1137 | ✅ works |
| **fd3c735e** | **03:04** | **71 / 533** | ❌ **SIGSEGV** |
| 0a3d01a4 … HEAD | 03:40+ | 71 / ~480 | ❌ SIGSEGV |

**Culprit: `fd3c735e`** ("Implement feature X … fix bug Y") — the **bulk C-purge**
that removed ~41 functions and ~600 string literals (112→71 funcs, 1137→533 str).
(The named purge commits 5f375905/130621d9/0a3d01a4 came AFTER and are not the
origin.)

## Critical insight — it is NOT a front-end logic change
Across the break, the entire func/param IR path is **byte-identical**:
- `irFuncIR`, `irScanStructTypes`, `irScanFuncTypes` — diffed, unchanged.
- `lineCount` / `getLine` / `startsWith` / `substring` — native **builtins**, unchanged.
- The only dangling calls left (`compileBlock` ×2, `compileFunc`, `cRuntime`) are
  all in `irMode==0` branches — **not reached** by `--ir` param funcs.

So no param-path *logic* changed. The ONLY thing `fd3c735e` changed is **deleting
~600 string literals**, shrinking compile.k's string table. ⇒ The crash is a
**codegen/runtime sensitivity to the string-table size/layout**: a string literal
(or value) used in the param path now resolves to **NULL**. Likely a string-vaddr
addressing or int/pointer-tag-boundary bug in the backend, exposed at the smaller
table — NOT a one-line compile.k fix.

## SPLIT

### Agent M (macOS) — localize shared-vs-backend
Rebuild the macOS FE (`compiler/macos_arm64/kcc-arm64`) from **current**
`compile.k` and run `printf 'func f(x){ emit x }\n' | <fe> --ir`. Report rc.
- macOS **also crashes** → it's a **shared** front-end/codegen issue (narrow to
  compile.k or a shared codegen pattern, not Linux-only).
- macOS **works** → it's **Linux elf.k backend-specific**.
This one test is the fastest way to bound the bug. (~minutes.)

### Agent W (Windows + runtime/codegen) — primary fix candidate
1. Same test on the Windows FE (rebuilt from current compile.k): does
   `func f(x)` crash? You own codegen + krypton_rt — string-table-layout
   sensitivity / string-literal vaddr addressing is your wheelhouse.
2. Investigate: after `fd3c735e` shrank the string table, does a param-path
   string literal (`"PARAM "`, `"LOAD "`, the shadow-push ops) get a bad/0 vaddr?
   Check the string-table emission and the int/pointer threshold (0x7F000000)
   interaction at the new layout.

### Agent L (me, Linux) — Linux-side localization (in progress)
- Disassemble the broken Linux FE and find WHICH string ref in `irFuncIR`'s
  param path resolves to NULL (RDI=0 site).
- Test the layout hypothesis: pad compile.k's string table back up and see if the
  crash disappears (confirms size-sensitivity).
- Audit `elf.k` string-literal vaddr emission for a boundary/wrap bug at small
  string counts.

## Files / artifacts
- Broken FE binaries from bisect: `/tmp/fe_morning`, `/tmp/fe_fd` (HEAD/fd3c735e,
  crash); `/tmp/fe_55`, `/tmp/fe_ba` (55363d65/ba8fb9f6, work). Compare.
- Proof harness: `/tmp/ccguard/` (C-toolchain failing stubs).
- Repro file: `printf 'func f(x){ emit x }\njust run { kp(f(9)) }\n'`.

---

# Agent L — deep investigation (2026-06-04, post-W)

Confirmed W: Windows FE on the same compile.k is clean → Linux `elf.k`. **HEAD
`d6f36c6b` Linux FE still SIGSEGVs on `func f(x)`; `elf.k` unchanged since
90c57d4f** — so `elf_host` miscompiles HEAD's compile.k.

## RULED OUT (don't re-chase)
1. **String-table size** — padded current compile.k +600 string literals
   (533→1043) → still crashes. (W's rec #2 = dead end.)
2. **Label numbers** — only IR diff in `irFuncIR` is the global label counter
   (`_wloop_29659`→`_13559`, purge dropped it ~16,100). Renumbered every label in
   HEAD's IR +20000 and re-ran `elf_host` → still crashes. Labels are opaque to
   elf.k. (W's rec #1/#3 string-vaddr-via-labels = dead end.)
3. **Missing strings** — `"PARAM "`,`"LOAD "`,`gcShadowPush`,`"FUNC "` all present
   in the broken FE (same counts as working). Not dropped.
4. **Frame size/localCount** — `irFuncIR` IR byte-identical modulo labels → same
   LOCAL count → same frame.

## What it IS
- NULL in `irFuncIR`'s **param path** (`params + "PARAM " + pname` or `FUNC … +
  pc`). gdb: `strlen(rdi=0)` in the concat runtime, caller `0x7f03c353`. Only
  with ≥1 param.
- **Heisenbug:** instrumenting `irFuncIR` moves the fault before any marker →
  `elf_host` emits a wrong **immediate** (string-load vaddr or a LOAD/STORE_LOCAL
  slot) in irFuncIR that only goes bad at HEAD's layout. Layout-sensitive elf.k
  codegen bug, triggered by `fd3c735e`.

## Remaining (elf.k disasm — L+W)
Disasm `irFuncIR`'s param path in `/tmp/fe_hd` (broken) vs `/tmp/fe_55` (working,
same 0x7f000000 base) → find the instruction loading **0** where a string vaddr
should be (or a LOAD_LOCAL wrong slot). Fix the matching computation in
`compiler/linux_x86/elf.k` (suspects: `labelOffset`/`funcVAddr` string-vaddr
lookup; LOAD_LOCAL/STORE_LOCAL slot emit ~L3365-3392 / L3730-3735).

Binaries: `/tmp/fe_55`,`/tmp/fe_ba` work · `/tmp/fe_hd`,`/tmp/fe_fd`,`/tmp/fe_renum`
crash. Repro: `printf 'func f(x){ emit x }\n' | kcc --ir`.

— L
