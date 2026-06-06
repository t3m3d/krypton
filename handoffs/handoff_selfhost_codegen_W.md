# HANDOFF → Agent W — self-host codegen crash (blocks the 2.2.0 release)

**Owner: W (native codegen / krypton_rt).** This is the bug blocking everything
downstream: a fresh `kcc` built from current `compile.k` can't compile real
programs, so we can't cut a 2.2.0 macOS release → no socket-capable kcc →
`server_native`/kryptlink can't serve on macOS, and no C-free seeds can ship.
Confirmed still live on HEAD 2026-06-05 (macOS). L confirmed it reproduces on
Linux too. See prior analysis: `handoffs/handoff_param_crash_M_response.md`.

**✅ RESOLVED — FINAL macOS Mach-O VERIFICATION PASSES (Agent M, 2026-06-06, on
origin/main 84b8a574 = post-`03a2d6ae` dead-branch delete).** Built an FE with
the **repo** toolchain (`compiler/macos_arm64/kcc-arm64` --ir → `bootstrap/
macho_host_macos_aarch64`) from current compile.k (21122 IR lines). Matrix now
all green: `kp(2+3)` rc 0 + real `FUNC __main__` (213 B IR); `kp("x"+toStr(5))`,
`func f(){}`, `func f(x){}` all rc 0 with `FUNC __main__`. **Full self-host
fixpoint: gen0 (kcc-arm64) == gen1 (repo-built FE) IR, BYTE-IDENTICAL, 21122
lines.** So macho self-host is stable. Cross-platform sign-off complete: L =
Linux x86 ✅, M = macOS Mach-O ✅.

**PITFALL that wasted a pass (don't repeat):** building the test FE with the
installed **brew `kcc 2.1.1`** (`/usr/local/krypton` macho_host) reproduces the
OLD crash (header-only `kp(2+3)`, rc 139 on string/func) even on fixed source —
because that backend predates the polymorphic-EQ + dead-branch fixes. The macho
self-host MUST be tested with the **repo** backend, not the installed brew kcc.
The macho fix is two parts already on HEAD: (1) source `03a2d6ae` deletes the
dead irMode==0 `compileBlock`/`compileFunc` branches (elf.k+macho.k mishandle the
unresolved CALLs); (2) macho_arm64_self.k already carries polymorphic EQ/INDEX/LT
(byte strcmp / char-indexing). No further macho codegen change needed. (My
earlier same-day note claiming "still live / dead-call theory refuted" was a
stale-backend artifact — superseded by this run.)

## Symptom (current minimal matrix)

Build an FE natively from current source, then feed it tiny programs:
```
kcc --native compiler/compile.k -o /tmp/fe        # builds fine (1.5 MB)
printf 'just run { kp(2+3) }\n'              | (write /tmp/t.ks) ; /tmp/fe --ir /tmp/t.ks
printf 'just run { kp("x" + toStr(5)) }\n'   ...                 ; /tmp/fe --ir /tmp/t.ks
printf 'func f(x){ emit x }\njust run { kp(toStr(f(9))) }\n' ... ; /tmp/fe --ir /tmp/t.ks
```
| input | result |
|---|---|
| `kp(2+3)` (trivial) | rc 0 but emits only a **~34-byte IR header — no `FUNC __main__` body** |
| `kp("x" + toStr(5))` (string build) | **SIGSEGV/SIGILL, rc 139**, empty IR |
| `func f(){...}` (no-param func) | **rc 139** |
| `func f(x){...}` (param func) | **rc 139** |

So the FE's **IR body-emission is miscompiled by the seed**: it drops the
`__main__` body for trivial input and crashes the moment real work
(string-building / user funcs) is emitted. The *installed* kcc 2.1.1 (clang-era
seed) compiles all of these correctly — only an FE rebuilt from current
`compile.k` is broken.

## What it is NOT (already ruled out — don't re-chase)
- **Not the dangling refs.** `compileBlock`/`compileFunc` (compile.k:2705/3126/3314)
  are `irMode==0`-guarded → not on the `--ir` path.
- **Not the forward-decl `decl` bug.** That real adjacent NULL-deref was fixed in
  `1c7d794f` (my patch) — FE still crashes, so the core is elsewhere.
- **Not size/layout sensitive.** Padding the string table (+720) and func count
  (+60) both failed to fix (prior doc).
- **Not platform-specific.** Reproduces on macOS macho AND Linux elf → it's the
  shared front-end source / shared codegen, not a backend quirk.

## Bisect (L, prior doc)
Broke at **`fd3c735e`** — the ~2300-line C-purge. The 129 *added* lines are the
suspects (deletions can't add a miscompiled construct). L's gdb on the Linux FE:
`strlen(NULL)` (`cmpb $0x0,(%rdi,%rax)`, rdi=0) in the param/IR path → a string
value resolves to NULL in the emitted code.

## Suggested attack (W)
The seed mis-emits something in `compile.k`'s IR `__main__`/body-emission path.
Either (a) diff the native/IR the seed produces for `irMain`/`irFuncIR` between
the working installed-2.1.1 seed and the broken rebuilt FE for a minimal
`func f(x)`, or (b) bisect *within* current compile.k's IR body-emit for the
construct the backend lowers to a NULL string load. You can debug the ELF on
Linux (coordinate with L — macOS blocks lldb on ad-hoc-signed binaries).

## Repro file
`printf 'func f(x){ emit x }\njust run { kp(toStr(f(9))) }\n' > /tmp/p.ks`
then `kcc --native compiler/compile.k -o /tmp/fe && /tmp/fe --ir /tmp/p.ks` → rc 139.

— Agent M (macOS)
