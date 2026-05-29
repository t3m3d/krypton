# Handoff — Linux x86-64 self-hosting (drop gcc from the ELF path)

Date: 2026-05-28

---

## UPDATE — 2026-05-28 VM session (macOS host + Lima x86-64 VM)

Ran this on an M4 Mac via a Lima x86-64 Ubuntu VM (qemu full-system emulation).
Concrete, verified findings — read these before the older speculative sections:

### Toolchain reality
- **The shipped Linux binaries are v1.5.0** (`bootstrap/kcc_seed_linux_x86_64`
  AND `compiler/linux_x86/kcc-x64` both print `kcc version 1.5.0`). The Linux
  toolchain is far behind macOS (2.1.1).
- **The 1.5.0 `kcc` seed is unusable here**: compiling even hello.k it grows to
  ~all available RAM and OOMs (3.6 GB in a 3.8 GB VM, 9.75 GB in a 10 GB VM —
  an unbounded runaway, not a fixed arena). `--headers <repo>/headers` does not
  help. Do NOT try to bootstrap through the 1.5.0 seed.
- **Bypass that works:** the macOS `kcc-arm64` (2.1.1) emits *portable* C and
  KIR. Use it to generate everything, then just `gcc` in the VM:
  ```sh
  # on the Mac:
  compiler/macos_arm64/kcc-arm64 compiler/linux_x86/elf.k > elf.c      # portable C
  compiler/macos_arm64/kcc-arm64 --ir compiler/linux_x86/elf.k > elf.kir
  compiler/macos_arm64/kcc-arm64 --ir hello.k > hello.kir
  # in the VM:
  gcc elf.c -o elf_host -O2 -lm -w     # g0 = current 2.1.1 ELF backend (memory-sane: 2.8 MB for hello)
  ./elf_host elf.kir es                # g0 builds g1 (native ELF, ~328 KB) — exit 0
  ```

### ⚠ Lima mount caching WILL waste your time
Files written on the Mac under the Lima-mounted home are served to the VM from a
**stale cache** — the VM saw a 318 KB / different-md5 `elf.c` while the Mac had
330 KB. Every rebuild silently used old code until caught. **Workaround: pipe
fresh files into the VM's LOCAL disk over SSH stdin, and build from there:**
```sh
cat elf.c    | limactl shell krypton -- bash -c 'cat > /tmp/k/elf.c'
cat elf.kir  | limactl shell krypton -- bash -c 'cat > /tmp/k/elf.kir'
# verify in-VM: grep -c <a-marker> /tmp/k/elf.c   # must match Mac
```
On a native Linux box (WSL) this whole problem disappears.

### The self-host bug — precisely localized
- `g0` (gcc-built) works. `g0` builds `g1` (`es`) fine, **but `g1` SIGSEGVs**
  immediately when run (even `g1 hello.kir out`). Reproduced with fresh code.
- It is **NOT** a size/displacement bug: added self-checks proved function
  layout (no `SIZEDRIFT`) and every runtime helper's declared `krXxxSize()` vs
  actual emitted bytes (`HELPERSIZE all OK`) are correct.
- `g1` reads the KIR, parses fine through `FUNC`/`LOCAL`, then dies in the
  **`BUILTIN` handler of `parseFullIR`** (first builtin: `gcShadowCount`).
- A line/var trace in `g1` (its `printErr` works) showed: `rest=[gcShadowCount 0]`
  and `bj=13` are correct, but `bname = substring(rest,0,bj)` yields the **wrong
  pointer** — `g1` printed `bname=[  bname=[]`, i.e. `bname` held the address of a
  *nearby string literal* (my own format string), not `"gcShadowCount"`. Without
  the probe it's NULL → the SIGSEGV.
- Conclusion: **`bname`'s STORE and LOAD don't agree** — a local-slot /
  eval-stack codegen bug in elf.k that surfaces deep in the large `parseFullIR`
  function. It is **layout-sensitive** (adding `printErr`s changes which wrong
  value `bname` gets). This is the Linux analog of the macOS native-emitter bugs.

### ROOT CAUSE FOUND + FIRST FIX LANDED (2.x front-end vs 1.5.0 backend mismatch)
The real bug is a **version mismatch**: the 2.1.1 front-end (`kcc-arm64`) inserts
GC root-shadow builtins — `gcShadowCount` / `gcShadowPush` / `gcShadowPop` — into
*every* function, but the 1.5.0-era `elf.k` backend doesn't recognize them, so
its `BUILTIN` handler fell to the `UNSUPPORTED` branch (**emits nothing**).
`gcShadowCount` is supposed to **push** a value (0 args, 1 result); emitting
nothing left the following `STORE` popping a never-pushed value → **eval-stack
underflow → drift → later locals (e.g. `bname`) read garbage → SIGSEGV.** Ruled
out via self-checks: function layout, helper sizes, frame size, per-op
`opByteSize`-vs-actual, and `hexDword` negative encoding are ALL correct — it was
never a size/displacement bug.

**Fix applied (committed in elf.k, BUILTIN handler):**
- `gcShadowCount` → `PUSH_INT 0` (push a dummy count; correct +1 stack effect).
- `gcShadowPush` / `gcShadowPop` → `POP` + `PUSH_INT 0` (consume the 1 arg, push
  a dummy result; net 0, keeps the surrounding `LOAD…POP` balanced).

This **advanced g1 from crashing at KIR line 5 (`gcShadowCount`) to line 7**
(`PUSH "hi-linux\n"`), and g0 still compiles hello correctly. Verified by a
per-line trace in g1.

### SECOND FIX LANDED — `kr_linecount` off-by-one
The `lineCount(interned)` crash was NOT a garbage return — `internStr` returns a
valid string (verified: `ret len=12`, and the caller receives `interned len=12`).
The bug was in `emitKrLinecountCode`'s trailing-`\n` check: the `JNE → .ret`
that skips `DEC EAX` had disp **`0x01`**, but `.ret` is **+2** away — `0x01`
lands in the *middle* of `DEC EAX` (`FF C8`), executing `0xC8`/ENTER → corruption
→ RIP=0. Fixed to `0x02`. **Crucial property:** it only fires when the scanned
string does NOT end in `\n`. `lineCount(ir)` worked because hello.kir ends in a
newline; `interned` = `"hi-linux\\n\n0"` ends in `'0'`, so it tripped the bug.
This is the exact bug-class to watch in every hand-rolled scan helper.

### Next step — the chain continues (3rd bug)
With kr_linecount fixed the RIP=0 crash moved forward. g1 now SIGSEGVs in
`kr_cmpi` (the EQ/NEQ comparison helper) with a **NULL operand** (`RSI=0`,
`RDI="hi-linux\\n"`) during the line-7 `PUSH` handler. The eval stack is full of
zeros (~21 KB) → an **eval-stack runaway** (a net-pushing loop somewhere in
line-7 handling); the kr_cmpi null is a *downstream* symptom (reading a 0 off the
polluted stack). Not yet root-caused. NOTE all gcShadow patterns are balanced and
there is NO function-size drift (a `/2` size self-check shows a phantom 1.5×
because `hexByte` emits 3 chars/byte — divide emitted-hex len by **3**).

Debug method that works: capture g0 stderr (`2>g.txt`); `printErr`-dump
`funcVAddrs` and the helper vaddrs to map a faulting address (helpers live AFTER
the last user fn `emitFuncCode`); `gdb -batch -ex run -ex "x/Ni $pc"` for the
fault. This is a chain of 1.5.0↔2.1.1 mismatches — expect a few more. The clean
way to end the chain is to bring `elf.k` up to 2.1.1 parity (as for
`macho_arm64_self.k`).

### Reliable build+test loop (copy-paste)
```sh
# Mac: regen + pipe fresh into VM-local /tmp/k
compiler/macos_arm64/kcc-arm64 compiler/linux_x86/elf.k > /tmp/elf.c
compiler/macos_arm64/kcc-arm64 --ir compiler/linux_x86/elf.k > /tmp/elf.kir
cat /tmp/elf.c   | limactl shell krypton -- bash -c 'cat > /tmp/k/elf.c'
cat /tmp/elf.kir | limactl shell krypton -- bash -c 'cat > /tmp/k/elf.kir'
# VM: build g0, build g1, test g1  (g0->g1 takes ~3 min under emulation)
limactl shell krypton -- bash -lc 'cd /tmp/k && gcc elf.c -o elf_host -O2 -lm -w && \
  timeout 300 ./elf_host elf.kir es && chmod +x es && ./es hello.kir h2 && ./h2'
```
VM: `limactl start --arch=x86_64 krypton` (needs `lima-additional-guestagents`;
give it ~10 GiB RAM — `memory:` in `~/.lima/krypton/lima.yaml`). gdb is available
(`sudo apt-get install -y gdb`).

---

For: the machine that can **execute Linux x86-64 ELF** (WSL2, a Linux VM, a
container, or `qemu-x86_64` user-mode emulation). The dev work was done on
macOS arm64, which **cannot run ELF** (different binary format + syscall ABI +
ISA), so the self-host fixpoint must be verified where ELF actually runs.

---

## TL;DR

- **macOS arm64 now fully self-hosts** (2.1.1): `macho_arm64_self.k` compiles its
  own KIR into a byte-for-byte identical native Mach-O across generations, no
  clang/codesign in the loop. See CHANGELOG 2.1.1 and
  `memory`/`project_macos_selfhost.md` for the gotchas.
- **Linux does NOT self-host yet.** `compiler/linux_x86/elf.k` is **134 funcs**
  but trips its own documented **"self-host bug at >66 funcs"** (`kcc.sh:215`),
  so the Linux backend still falls back to a **one-time gcc bootstrap**.
- **Goal of this handoff:** fix that bug so `elf_host` can be rebuilt *from
  `elf.k` by the native ELF pipeline* (gcc-free), verified by a byte-identical
  multi-generation fixpoint — exactly like macOS. Then (secondary) compile the
  front-end `compile.k` natively to drop gcc entirely on Linux.
- `bootstrap/REBUILD_SEED.md` is **referenced by `kcc.sh` but missing** from the
  repo — recreate it (or fold it into this doc) once the bug is pinned.

---

## The Linux build pipeline (on the Linux box)

Seeds live in `bootstrap/`:
- `kcc_seed_linux_x86_64` — the front-end compiler (`.k` → C, or `--ir` → KIR)
- `elf_host_linux_x86_64` — the ELF backend (KIR → ELF)
- `optimize_host_linux_x86_64` — optional KIR optimizer

Interfaces (note: **`elf_host` uses positional args**, unlike macOS `--ir`):

```sh
KCC=bootstrap/kcc_seed_linux_x86_64
ELF=bootstrap/elf_host_linux_x86_64
OPT=bootstrap/optimize_host_linux_x86_64

# .k -> KIR
"$KCC" --ir prog.k > prog.kir
# (optional) optimize
"$OPT" prog.kir > prog.opt.kir && mv prog.opt.kir prog.kir
# KIR -> ELF  (positional: INPUT OUTPUT)
"$ELF" prog.kir prog
chmod +x prog && ./prog
```

Current gcc bootstrap of the backend (what we want to ELIMINATE), from `kcc.sh`:

```sh
"$KCC" elf.k > /tmp/elf.c            # front-end emits C
gcc /tmp/elf.c -o elf_host -O2 -lm -w   # <-- the gcc dependency to kill
```

---

## PRIMARY TASK: fix the `elf.k` `>66-func` self-host bug

### Reproduce / bisect

```sh
KCC=bootstrap/kcc_seed_linux_x86_64
ELF=bootstrap/elf_host_linux_x86_64      # gcc-built g0

"$KCC" --ir compiler/linux_x86/elf.k > /tmp/elf.kir
"$ELF" /tmp/elf.kir /tmp/elf_self        # native backend compiles elf.k
chmod +x /tmp/elf_self
echo 'just run { kp("hi\n") }' > /tmp/h.k
"$KCC" --ir /tmp/h.k > /tmp/h.kir
/tmp/elf_self /tmp/h.kir /tmp/h && ./tmp/h   # does the SELF-built backend work?
```

If `elf_self` mis-compiles (wrong output / SIGSEGV), **bisect by function
count**: truncate `elf.k` to N functions (keep a valid `__main__`), self-compile,
and find the exact N where it breaks. The number "66" suggests it's really a
*text-size* threshold crossed around the 66th function, not a literal count —
confirm which.

### Most-likely root causes (ranked by macOS precedent)

This exact class of bug bit macOS hard this session. Check these first:

1. **Conditional-branch range overflow** — *the #1 macOS bug.* macOS used `CBZ`
   with a 19-bit (±256 KB) immediate that silently wrapped on large functions;
   fix was to widen it (`cbnz +2; b target`). **x86-64 equivalent:** short
   conditional jumps `jcc rel8` (±127 bytes) overflow once a function's body
   grows; the emitter must use the **near form `0F 8x rel32`**. Grep `elf.k` for
   its `jcc`/`Jz`/`Jnz`/`b_cond` emitters and confirm they use rel32, not rel8.
   A `>66 funcs` threshold is consistent with *cumulative text* pushing some
   relative target out of rel8/rel32 range.
2. **Function-offset table vs actual emission mismatch.** macOS had a pre-pass
   (`computeFunctionInstrs`) that must exactly match what the emitter emits; any
   per-op miscount corrupts every subsequent `CALL`/jump delta. If `elf.k` has an
   analogous size pre-pass, verify it matches the real emitter byte-for-byte
   (especially for any op whose size is data-dependent).
3. **Relative `CALL E8 rel32`** is 32-bit signed (±2 GB) — unlikely to overflow
   at 66 funcs, but a *miscounted* function start would still point CALLs at the
   wrong place. Cross-check the symbol/offset table.
4. **Negative-constant sign extension** — *already fixed* in `elf.k` (`hexQword`
   sign-extends; see the LOAD-BEARING banner at line ~60). Same class as the
   macOS `toInt`/`PUSH_INT` fix this session. Note as handled; don't regress it.

### Verify the fix (the fixpoint, same as macOS)

```sh
# g0 = gcc-built backend (bootstrap)
"$KCC" --ir compiler/linux_x86/elf.k > /tmp/elf.kir
"$ELF"        /tmp/elf.kir /tmp/g1   # g0 builds g1 (native)
chmod +x /tmp/g1
/tmp/g1       /tmp/elf.kir /tmp/g2   # g1 builds g2
chmod +x /tmp/g2
/tmp/g2       /tmp/elf.kir /tmp/g3   # g2 builds g3
sha256sum /tmp/g1 /tmp/g2 /tmp/g3    # PASS = all three identical
```

`g1 == g2 == g3` (identical sha256) is the self-host fixpoint. Linux has **no
code-signing**, so none of the macOS "freshly-written binary SIGKILL" flakiness
applies — runs should be deterministic without the sync/copy dance.

Once green: replace the gcc bootstrap in `kcc.sh` (Linux branch, ~line 215-232)
with the native rebuild, and refresh `bootstrap/elf_host_linux_x86_64`.

---

## SECONDARY TASK: native front-end (drop gcc entirely)

After `elf.k` self-hosts, compile the **front-end** `compiler/compile.k` with the
native ELF backend to produce a native `kcc` — eliminating the last gcc use.

Gap sweep (run via the Krypton script `tools`-style; results from compile.kir vs
`elf.k`'s handled builtins):

- **Opcode verbs used by `compile.kir`:** FUNC PARAM LOCAL BUILTIN STORE LOAD POP
  PUSH SUB LABEL GTE JUMPIFNOT INDEX EQ RETURN JUMP NEG END CALL LT ADD LTE
  JUMPIF MUL NEQ GT MOD NOT — all standard.
- **Builtins flagged MISSING in `elf.k`:** `gcShadowCount`, `gcShadowPush`,
  `gcShadowPop`, `shellRun` (4). The three `gcShadow*` are likely *false
  positives* (the front-end emits them but the backend may handle GC differently
  or inline) — verify before implementing. `shellRun` is a real gap.

**Caveat — the sweep is builtin-only and UNDERCOUNTS the real gap:**
`compile.k` uses **closures/lambdas/function-pointers in ~69 places** (indirect
`CALL` through a variable + captured-environment via `envGet`). Those are NOT a
builtin, so they don't appear in the list above — but on macOS they were the
single biggest front-end blocker (the backend emits `__fp__N` placeholders
instead of working code). **Expect closures to be the real front-end blocker on
Linux too.** Implementing them = function-value representation (code address as a
value) + indirect call + heap-allocated captured env.

---

## Cross-cutting lessons from the macOS self-host (apply to Linux)

- **No allocator reclamation.** The macOS bump heap never frees; a full
  self-compile only fit after converting hot paths from O(n²) string
  concatenation to O(n) StringBuilders (`sbNew/sbAppend/sbToString` with a
  *stable handle* so realloc-on-grow doesn't invalidate caller handles) and a
  256-entry hex lookup table. If `elf.k` builds output via `s = s + ...` in hot
  loops and a big compile OOMs/slows, apply the same treatment. Check Linux's
  heap model first — it may differ from macOS's fixed bump arena.
- **Fixpoint debugging is expensive.** A *1232-byte* divergence on macOS took
  many rebuild→self-compile→diff cycles to isolate. Diff the generations
  (`cmp -l g1 g2`), decode the diverging instruction, and trace the operand back
  to the source op. That method found every macOS bug.
- **Bug classes are shared across backends.** Negative constants, branch-range
  overflow, and instruction-count/offset-table mismatches showed up on both
  macOS and Linux. A fix on one platform is a strong hint for the other.

---

## Done criteria

1. `elf.k` self-hosts: `g1 == g2 == g3` (byte-identical), each runs correctly.
2. `kcc.sh` Linux branch rebuilds `elf_host` natively (no gcc), seed refreshed.
3. (Stretch) front-end `compile.k` compiles via native ELF backend → native
   `kcc` → **gcc fully removed from the Linux path**.
4. Recreate `bootstrap/REBUILD_SEED.md` (or update `kcc.sh` to point here).
