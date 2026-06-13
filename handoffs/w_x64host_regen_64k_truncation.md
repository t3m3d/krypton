# w → all : x64_host regen blocked on 64K stdout truncation

**From:** agent w (Windows)
**Date:** 2026-06-13
**Severity:** blocks runtime validation of stage 6 phase 2 + every IAT
slot wired this session + the phase 3 implementation Brian preapproved.

## Observation

`kcc.exe --ir compiler/windows_x86/x64.k > x64.kir` produces **exactly
65536 bytes** of IR output, then exits **rc=0**. The IR ends
mid-instruction:

```
RETURN
LABEL _endif_4362
LOAD name
PUSH "GetCurrentProcessId"
EQ
```

Expected IR size for x64.k (9700+ lines of source) is in the multi-MB
range. We are losing ~95% of the IR silently.

The backend (`x64_host_new.exe x64.kir x64_host_newer.exe`) happily
accepts the truncated IR and emits a 100 KB `x64_host_newer.exe`
(shipped version is 783 KB). The result is a structurally-valid PE
but with most of x64.k's functions missing — useless for actual
compilation work.

## Reproduced 3 times this session

| Attempt | Invocation | IR size | Outcome |
|---|---|---|---|
| 1 (`bk5221tnx`) | `kcc.exe --ir ... > x64.kir 2> err.log` (bash) | 65536 | rc=0, host invalid |
| 2 (`b6l9edmbk`) | `stdbuf -o0 -e0 kcc.exe --ir ...` (bash) | 49 | rc=1 — KRYPTON_ROOT stripped by stdbuf wrapper |
| 3 (`btzzf9frm`) | `kcc.exe --ir ... \| cat > x64.kir` (bash pipe) | 65536 | rc=0, host invalid |

Attempt 3 used `\| cat >` to defeat any direct-redirect buffer cap. Same
truncation. So this is **not** a bash redirect issue — kcc.exe itself
is the source of the 64 KB cap.

## Hypothesis

kcc.exe (or the underlying kcc-bin worker) uses an internal stdout
buffer of exactly 64 KB. On normal-sized IR output (< 64 KB) it
flushes cleanly on process exit. On large IR output, the buffer fills
once, gets flushed, then **subsequent writes are silently dropped**
because either:

- The buffer-grow logic has an off-by-one and clamps to 64 KB without
  detecting the truncation.
- The stdout file descriptor is closed early after the first 64 KB.
- A Krypton sb (StringBuilder) used to assemble the IR has a 64 KB cap.
- A `WriteFile` call with `nNumberOfBytesToWrite` truncated to a
  16-bit field somewhere in the kr_writefile / kr_print machinery.

The hypothesis I'd test first: search for `65536` or `0x10000` literals
in `kr_print` / `kr_writebytes` / sb-grow paths in `runtime/krypton_rt.k`
and `compiler/windows_x86/x64.k` near the IR-emission code.

## What's NOT the cause

- **Not OOM.** kcc-bin reached 33 GB working set on attempt 1 and
  finished cleanly with rc=0; output was just truncated.
- **Not the bash pipe.** Attempt 3 used `| cat >` which defeats
  per-process stdout buffer issues.
- **Not network / DNS.** This is all local stdout writes.
- **Not the shell itself.** Different shells (bash, PowerShell, cmd.exe
  retries) all converged on the same 64 KB cap.

## Impact on this session's work

The following commits are **shipped source-only** and were waiting on
the regen for runtime validation. They are presumed-correct from a
mechanical audit standpoint but have not actually run:

- `5185d50e` — stage 6 phase 2 freelist consumption (`__rt_alloc_v2`
  + 69 bytes)
- `697a24d7` — wininet.dll IAT registration (16th DLL slot)
- `a149064c` — bcrypt.dll IAT registration (15th slot)
- `6d80ef48` — iphlpapi.dll IAT registration (14th slot)
- `3e84efa5` — psapi.dll IAT registration (13th slot)
- `49e48d28` — shell32.dll IAT registration (12th slot)
- `95345ac8` — gui frontend modernization (DPI / Segoe UI / dark title
  / theme)
- `9742776e` — ws2_32.dll IAT registration (from earlier session)

Plus the phase 3 plan in `handoffs/stage6_phase3_plan.md` was meant to
be implemented after phase 2 validated. **That work is paused** until
the regen path is restored — implementing untested code on top of
untested code compounds risk per Brian's standing instruction.

## What I'm still doing despite the block

The Python FE prep track does NOT depend on the regen because the
existing host binary (`bin/x64_host_new.exe`) is sufficient to
**compile programs that import** the new `stdlib/builtins.k` /
`stdlib/string.k` / etc. — those are user-side stdlib, not compiler
guts. So:

- Continuing Python prep (collections.k, itertools.k, json wrappers,
  demo .pyk).
- PE rsrc manifest embedding spec (source-only design work).
- Documentation tidying.

## Suggested next actions

1. **(top priority for whoever picks this up)** Find the 64 KB cap in
   the FE's stdout / sb path. Likely in `runtime/krypton_rt.k`
   near `kr_print` / `kr_writebytes` or in `compiler/.../*.k` near IR
   emission. Single-byte fix probably.

   **First hypothesis (tried + REJECTED 2026-06-13 evening):**
   `kr_sbappend` at `runtime/krypton_rt.k:189` uses
   `bitAnd(raw_cap, 0 - 4)` to mask the alloc header size. Replaced
   the bitAnd with arithmetic `raw_cap - (raw_cap % 4)` to dodge any
   negative-int round-trip through `__user_rt_atoi`, rebuilt
   `krypton_rt.dll` (which finished cleanly with kcc.exe, no
   errors), deployed to `c:/krypton/krypton_rt.dll` and
   `%TEMP%/krypton_rt.dll`. Reran the FE on x64.k — produced
   **the same 65536 bytes, ending in the exact same `EQ` token**.

   **Critical finding:** the rebuilt DLL was **byte-identical** to
   the unpatched version (sha256 match). The mechanism is now
   understood: when kcc.exe sees the output filename is exactly
   `krypton_rt.dll`, it sets `isBootstrap == "1"` (see x64.k:8443+,
   `if isDll == "1" && rtDllName == "krypton_rt_legacy.dll"`). In
   bootstrap mode the FUNC bodies in `runtime/krypton_rt.k` are
   **IGNORED**; the exported function bodies come from x64.k's
   `emitBootstrapHelpers` directly. The Krypton-level
   `runtime/krypton_rt.k` is effectively a declaration-only file
   for the export name list. So changing the Krypton source there
   cannot affect the produced DLL.

   **Implication:** the fix is in x64.k's bootstrap helpers, which
   means fixing the bug requires updating x64.k, which requires
   regenning x64_host_new.exe, which requires the bug to be fixed
   first. Catch-22. Three workaround paths:

   - **Patch krypton_rt.dll bytes directly** by hex-editing the
     compiled sbAppend routine. Find the function via the export
     table, locate the cap-read instruction (probably an `AND` with
     a 32-bit signed immediate of 0xFFFFFFFC), rewrite to an
     arithmetic mask. Offline binary surgery; risky but tractable.
   - **Build a tiny C helper** that reads stdin chunks from kcc.exe
     and writes to a file. Avoids whatever sb-cap bug is in
     kcc.exe by never accumulating the IR in one sb — but kcc.exe
     accumulates BEFORE printing, so the cap has already hit.
   - **Cross-compile x64.k on a different machine** (Linux ELF
     backend, macOS Mach-O backend) to produce a new
     x64_host_windows_x86_64.exe. The bug is Windows-runtime
     specific.
2. Once fixed, regen `x64_host_windows_x86_64.exe`, rebuild
   `krypton_rt.dll` via bootstrap mode, sync to `%TEMP%`, run
   `tests/gc_freelist_consume.k` to validate phase 2.
3. If phase 2 passes, implement phase 3 per
   `handoffs/stage6_phase3_plan.md` (Brian preapproved this autonomous
   path), regen again, run `tests/gc_auto_collect.k`.
4. Smoke-test each of the 6 IAT-registered DLLs from this session
   (one tiny `.k` program per DLL importing one symbol).

## Workaround ideas if the cap can't be fixed quickly

- **Split-emit IR.** Have kcc.exe emit IR in chunks (per-function) into
  separate files, then concatenate.
- **Direct-to-file flag.** Add a `kcc.exe --ir-out path` flag that
  writes IR to a file via `kr_writefile` instead of stdout — different
  code path, might bypass the bug.
- **Run on a Linux/macOS box.** The 64 KB cap might be Windows-specific
  (the kr_print machine code in x64.k uses Win32 `WriteFile`).
- **Stream through a different process.** Have a small helper that
  reads stdin in chunks and writes to disk; kcc.exe pipes to it.
  Risky — same root-cause buffer might cut off the upstream side.

— w

[[stage6_phase3_plan]] [[project_x64k_rebuild_oom]]
