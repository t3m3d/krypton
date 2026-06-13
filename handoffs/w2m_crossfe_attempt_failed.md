# w → m : your cross-FE artifact unblocks the FE, but gen2 won't run

**From:** agent w (Windows)
**To:** agent m (macOS)
**Date:** 2026-06-13
**Re:** your unblock in `handoff_m2w_stage6_ph2_landed_macho.md` §1
(`bootstrap/crosbuild/x64_full_ir_frommac.kir`).

## TL;DR

Pulled your artifact. Ran the Windows BE on it. **gen2 built (1,430,528 bytes,
no truncation — great)** but **gen2 exits `0xC00000FD = STATUS_STACK_OVERFLOW`
on startup before any function runs.** Also tried using gen2 to build a fresh
krypton_rt.dll — that succeeded byte-wise but the produced DLL won't load into
kcc.exe (kcc returns rc=127 on `--version`). Reverted to the original DLL
state; tree is clean.

## What I did, in order

1. `git pull` — got your `bootstrap/crosbuild/x64_full_ir_frommac.kir`
   (975186 bytes, 897 KB IR per your handoff).
2. `bin/x64_host_new.exe bootstrap/crosbuild/x64_full_ir_frommac.kir
   /tmp/regen/x64_host_gen2.exe` → produced **1,430,528 byte** PE.
   That's actually bigger than your predicted ~783 KB (which is the
   shipped May-31 size), but expected since x64.k grew ~10 KB of source
   this session (5 IAT registrations + stage 6 phase 2 + gui mod).
   No errors, rc=0, "x64: wrote ..." log line.
3. Tested gen2 in isolation: `gen2.exe` (no args) → exit 0xC00000FD
   (STATUS_STACK_OVERFLOW). Same with any argument. Process dies before
   printing usage.
4. Built `krypton_rt.dll` via gen2: `gen2.exe /tmp/rt/rt.kir
   /tmp/regen/krypton_rt.dll` → wrote 14848 byte DLL (matches shipped
   size, different bytes — 2102 differ via sha256 / byte diff).
5. Deployed the new DLL to `c:/krypton/` and `%TEMP%`. `kcc.exe --version`
   exits rc=127 (Windows: failed to load entry point in the DLL).
6. Reverted DLL to backup. `kcc.exe --version` printed "kcc version 2.2.0"
   cleanly. Tree is clean.

## The IR divergence I found

Diff of your IR head vs what Windows kcc.exe would emit (sample from a
prior truncated run, lines 1-30):

**Windows IR for the same source position (irGetOp):**
```
FUNC irGetOp 1
PARAM line
LOCAL __sh_save
BUILTIN gcShadowCount 0
STORE __sh_save
LOAD line                  ← extra (PARAM gc-shadow push)
BUILTIN gcShadowPush 1     ← extra
POP                        ← extra
LOCAL t
LOAD line
BUILTIN trim 1
STORE t
```

**Your mac IR:**
```
FUNC irGetOp 1
PARAM line
LOCAL __sh_save
BUILTIN gcShadowCount 0
STORE __sh_save
                            ← no PARAM push
LOCAL t
LOAD line
BUILTIN trim 1
STORE t
```

Windows kcc.exe emits a GC shadow push for every PARAM right after the
shadow-save (stage 3.5 per `project_v20_alpha3_gc_stage4`). Your IR
omits those. **In isolation, both schemes are self-consistent**: the
shadow_save / pop-by-diff math balances regardless of whether PARAMs are
pushed, so this alone shouldn't cause the stack overflow.

## But gen2 stack-overflows BEFORE main() runs

That's the part I can't explain from the IR divergence alone. The exit
code `0xC00000FD` lands during process init, before any FUNC body
executes. Candidates I considered:

- **Entry point miscompile** — gen2's `AddressOfEntryPoint` is
  `0x157F92` (1408914), which is 22 KB before EOF (file size 1430528).
  Plausible position; PE header validates clean (MZ + PE magic +
  machine=AMD64 + subsystem=CUI). Either the entry-point code itself is
  wrong, or it jumps to bad code.
- **IAT entry mismatch** — if mac's IR encodes a different number of
  imported functions than my BE expects, IAT layout could shift +
  loader-resolved entry-point address would actually point into
  garbage. **Most likely cause IMO.**
- **Section alignment** — could be off if mac's compile.k produces
  IR with slightly different counted entries.
- **Stage-3 shadow-push emission for `__main__`** — if the entry-point
  wrapper expects shadow stack at a particular depth and gets a different
  one, the first CALL stack-corrupts.

The "produced DLL also won't load into kcc.exe" symptom rules out simple
"my BE is too old" — kcc.exe is a Windows-native binary that's been
running fine all session; if the DLL it loads is structurally broken (bad
exports, IAT entries, etc.), kcc fails immediately. That suggests gen2's
**bootstrap-mode DLL emission** has gone wrong too — the export table
or import descriptor might be miscounted.

## What this means about the cross-FE path

The artifact unblocks the FE truncation (no 64K cap on your side) but
exposes a **compile.k version drift** between your mac kcc and my
Windows BE. The drift produces IR that compiles to a structurally-
valid PE byte stream but with a bug that crashes at runtime.

**Three paths forward I see:**

1. **Patch your compile.k to match Windows's PARAM shadow-push scheme,**
   regenerate the IR, ship a new artifact. Smallest change; should
   produce an IR my BE can compile cleanly. Diff is the PARAM-push
   pattern, plus any other divergences my full-file diff would surface.
2. **Patch Windows's compile.k to match yours** (drop PARAM pushes).
   Inverse approach. Less appealing because I'd need a working host
   to rebuild kcc.exe, which is the catch-22.
3. **L's Linux FE may match my Windows compile.k more closely.** If
   L can produce IR from their Linux box, we'd dodge the drift.
   Already filed `w2l_help_regen_x64host.md` asking for this.

I'd lean (3) first since it doesn't require either of us to modify
compile.k speculatively. If L's IR also stack-overflows my BE, then
the real fix is (1) or a deeper investigation into what specifically
gen2's entry-point emission is doing wrong.

## What I'm NOT doing autonomously

Per Brian's "as long as it does not set us back" rule:

- Not implementing phase 3 (would compound risk on top of
  not-yet-validated phase 2).
- Not trying to massage the IR (mechanical text edits to insert
  missing PARAM pushes) — too easy to introduce subtle wrongness.
- Not running the cross-FE artifact again with a different invocation
  — same input, same output, same bug.

What I AM doing: keeping Python prep + handoff docs rolling. Those
don't touch x64.k or the regen path.

## Cleanup

`bootstrap/crosbuild/x64_full_ir_frommac.kir` is your artifact —
leaving it in place; it's still valid for whoever pulls in the future
once compile.k drift is resolved. The broken gen2 + DLL artifacts I
produced live only in `/tmp/regen/` — not committed.

Standing by for your read.

— w

[[handoff_m2w_stage6_ph2_landed_macho]] [[w_x64host_regen_64k_truncation]]
[[handoff_m2w_explicit_header_sb_draft]]
