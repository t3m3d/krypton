# RELEASE BLOCKERS — linux_x86 (do NOT cut a release until all GREEN)

Per Brian 2026-05-29: **no new version ships until these work.** Suite currently
**60 pass / 2 fail / 4 skip** (4 skips are platform-gated, OK). The 2 fails + 2
non-suite issues below are the blockers. All are pre-existing (NOT from the GC or
FE-accumulation work; they fail on the pre-S0 bump backend too).

Test/build env: `export KRYPTON_ROOT=$(pwd)`; compile via
`./bootstrap/kcc_driver_linux_x86_64 --native FILE.k -o OUT`; suite via `./build.sh test`.
Box gotchas: ptrace-attach DISABLED (gdb -p fails; gdb launch/run works), no /usr/bin/time.

---
## BLOCKER 1 — test_array.k: fixed-size arrays (A5) broken
Fails the FIRST assertion `a[0] != 10`.
Repro: `just run { let a = array(5)  a[0] = 10  kp(a[0] + "") }` → wrong value.
Feature: `array(N)` allocates N 8-byte slots (GC buffer); `arr[i]` / `arr[i]=v` lower
to bufGet/SetQwordAt (64-bit int|ptr elements, zero-init). Suspect the array() alloc or
the bufGetQwordAt/bufSetQwordAt lowering in the linux_x86 backend (elf.k) and/or the FE
index lowering. Cross-check vs a backend where A5 passes (macOS?) to localize FE vs backend.

## BLOCKER 2 — test_static.k: static locals (A6) don't persist
`counter()` returns 1 on call 1 (c1 passes) but NOT 2 on call 2 (c2 fails) — the static
resets each call instead of persisting.
Repro: `func counter() { static let n = 0  n += 1  emit n }  just run { kp(counter()+"") kp(counter()+"") }`
→ prints 1 then 1 (should be 1 then 2). Feature: `static let` is FE-lowered to a
uniquely-mangled module global (per the test header, "no backend change"). So the FE
mangling/global-init likely re-initializes the global on every call instead of once.
Look in compile.k for `static` handling.

## BLOCKER 3 — kryofetch native build: elf_host codegen heap growth
elf_host's heap grows ~120MB/min with no plateau compiling kryofetch's 832KB IR
(reached ~5GB w/ an 8GB heap before crashing). Root cause NOT isolated
(growing-transient codegen pattern). FE+opt succeed; only final codegen exhausts.
Repro: build kryofetch/run_linux.k (krypton transitive-mark GC is committed).
Separate from the GC correctness work.

## BLOCKER 4 — repeat() broken on linux_x86
`repeat("x", N)` compiles but the emitted CALL targets the image base (krRepeatVAddr
resolves to SEG_BASE) → SIGSEGV. FE/builtin-dispatch mismatch in the bundled kcc-x64.
Repro: `just run { kp(repeat("x", 5)) }` → crash. Not in the suite.

---
## RESOLVED this session (for context, not blockers)
- GC transitive-mark: works, converges, suite-clean (commits 6cbffc1c / 94e3e08d).
- FE string-literal `+` accumulation: FIXED (3dc3c73b) — emits CAT; numeric `+` intact.

## Release gate
`./build.sh test` must show the 2 fails gone (→ 62 pass / 0 fail / 4 skip), AND
kryofetch + repeat() must build/run. THEN consider a release.
