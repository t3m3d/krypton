# w session summary — 2026-06-13

**Author:** agent w (Windows)
**Span:** 2026-06-13 single overnight session (~12 hours).
**Status of work:** all shipped to `origin/main`. Runtime validation
of the GC and IAT pieces still blocked on the 64K regen bug (see
`handoffs/w_x64host_regen_64k_truncation.md`).

## Headlines

- **5 new Windows DLLs IAT-registered** in
  `compiler/windows_x86/x64.k`: shell32, psapi, iphlpapi, bcrypt,
  wininet. 17 IAT slots total now.
- **5 new stdlib wrappers** for those DLLs:
  `stdlib/{shell,proc_ex,iphlp,crypto,httpc}.k` (httpc gains a
  WinINet fast path).
- **GUI frontend modernization**: opt-in `guiEnableModernChrome()`,
  Segoe UI 9pt cached font, `guiEnableDarkTitle`, `guiApplyExplorerTheme`.
  Plus the CC v6 manifest template sidecar.
- **Stage 6 phase 2 freelist consume** cherry-picked onto main
  (commit `5185d50e`) and stage 6 phase 3 plan committed
  (`handoffs/stage6_phase3_plan.md`).
- **Three-agent .ks unification** locked in: `.k` canonical
  source, `.ks` fallback for shebang scripts, `.objk` retired.
  Objective-K is `import "k:cocoa"`, not a separate dialect.
- **Python frontend prep**: 14 stdlib modules + 3 docs + 1 demo file
  to give Brian's upcoming Copilot FE scaffolding a complete
  lowering target.
- **3 handoffs** to / from l on the memory-model ABI alignment;
  raw-mem surface now matches between Windows + aarch64.
- **Roadmap doc** committed: `handoff_w2all_overall.md` covers 14
  Tier A + Tier B features with effort estimates.
- **Hard blocker filed**: the 64K stdout truncation bug in kcc.exe
  documented with reproducer, three rejected hypotheses + the
  current best one (x64.k bootstrap helpers), and three workaround
  paths.

## Commits in chronological order

| Commit | What |
|---|---|
| `49e48d2` | shell32 IAT wiring + stdlib/shell.k + retired gui.k LoadLibrary dance |
| `3e84efa` | psapi IAT + stdlib/proc_ex.k |
| `6d80ef4` | iphlpapi IAT + stdlib/iphlp.k |
| `a149064` | bcrypt IAT + stdlib/crypto.k |
| `fc7e4e8` | docs: catalog the new k:* modules in spec/grammar |
| `697a24d` | wininet IAT + stdlib/httpc.k WinINet path |
| `95345ac` | gui frontend modernization |
| `5185d50` | stage 6 phase 2 freelist consume (cherry-picked) |
| `e103148` | w2l_memory.md handoff (rawAlloc / rawFree / rawRealloc ABI) |
| `101c1c6` | stage 6 phase 3 design plan (byte-level) |
| `3deb672` | handoff_w2all_overall.md roadmap |
| `1320514` | w2l_ptr_classification.md reply |
| `2c93972` | w2l_ptreq_int_ack.md (int 1/0 alignment) |
| `705e682` | w2m_ks_unifies_objk.md (.ks convention) |
| `812b699` | clarification: .k canonical / .ks fallback |
| `b1031bb` | python prep handoff + stdlib/builtins.k |
| `8e89b0e` | py-prefix → k-suffix rename in builtins.k |
| `9c94a81` | stdlib/string.k (37 funcs) |
| `7ca2f19` | stdlib/list.k (15 funcs) |
| `795700e` | stdlib/dict.k (16 funcs) |
| `98d89b1` | docs/python_to_kir.md lowering spec |
| `9fa56ef` | docs/python_compat.md non-goal matrix |
| `2cf9033` | stdlib/sys.k + stdlib/os.k |
| `4a44706` | stdlib/math.k |
| `e852629` | rename: drop _py suffix from stdlib + module decls |
| `b8c5b27` | regen diagnostic filed |
| `9c66ea6` | stdlib/itertools.k (15 funcs) |
| `5693130` | stdlib/functools.k + stdlib/jsonk.k |
| `30a01e6` | stdlib/time.k + stdlib/randomk.k |
| `55d583d` | examples/python_demo.pyk |
| `e941efe` | diagnostic: sbAppend hypothesis |
| `2913521` | diagnostic: sbAppend hypothesis REJECTED |
| `66349be` | diagnostic: bootstrap-mode mechanism explained |
| `a5d5ed9` | w2l_help_regen_x64host.md (ask l for cross-compile) |
| `bf2fec4` | stdlib/hashlib.k + stdlib/pathlib.k |

35 commits, all on `main`. No force-pushes, no rebases against
shared history, every push went through `git pull --rebase` before
merging.

## What I tried and abandoned

- **Three regen attempts** at `bin/x64_host_windows_x86_64.exe` via
  the FE → BE pipeline. All hit the same 64K IR truncation. Three
  workaround paths still untried (offline DLL patch, cross-compile
  via l's backend, beefier Windows box).
- **Source patch of `runtime/krypton_rt.k`** sbAppend to dodge the
  suspected `bitAnd(raw_cap, 0-4)` bug. Produced a byte-identical
  DLL — the bootstrap-mode build ignores Krypton-level FUNC bodies,
  so source-level fixes can't affect the produced binary. Mechanism
  documented in the regen diagnostic.
- **`stdbuf -o0`** to defeat stdout buffering. Stripped
  `KRYPTON_ROOT` from kcc.exe's env; rc=1 instant fail.
- **`cmd.exe //c`** to bypass mingw bash redirect. Path-quoting
  bash → cmd translation failed with rc=127.

All of these are documented in
`handoffs/w_x64host_regen_64k_truncation.md` so whoever picks the
problem up doesn't repeat the failed paths.

## Status by track

### IAT registration sweep
- Source-only. 5 DLLs wired (shell32, psapi, iphlpapi, bcrypt,
  wininet) on top of the prior ws2_32 work.
- Pattern reproduced cleanly 5 times; descriptor index 12 → 16,
  descSize 280 → 360.
- Runtime validation **blocked on regen**.

### Stage 6 phase 2 freelist
- Source-only on `main`. 69-byte freelist-consumption block at
  offset 76 of `__rt_alloc_v2`. `bsHelperBlockSize` 9376 → 9445.
- Test program `tests/gc_freelist_consume.k` committed (came with
  the cherry-pick).
- m **landed** Mach-O port (commit `70c82ac3`). l shipped freelist
  construction; consume side waiting per their staging.
- Runtime validation on Windows **blocked on regen**.

### Stage 6 phase 3
- Plan filed at `handoffs/stage6_phase3_plan.md` with byte-level
  detail (auto-check tail at `__rt_alloc_v2`, 72-byte append, both
  RET sites replaced with JMP rel32 + 2 NOPs). Brian preapproved
  implementation after phase 2 validates.
- **Not implemented** — would compound risk to land untested code on
  top of untested code per Brian's standing rule.

### gui frontend modernization
- `guiEnableModernChrome()` + Segoe UI cache + dark title + theme
  apply. `SetProcessDpiAwarenessContext` added to `KRUSER_FUNCS`.
- `runtime/krypton.exe.manifest.template` sidecar for CC v6 chrome.
- PE rsrc-section manifest embedding plan **not started** — would
  modify x64.k and that's a risk-compounding move pending regen.

### Python FE prep
- 14 stdlib modules covering builtins / string / list / dict / sys /
  os / math / itertools / functools / jsonk / time / randomk /
  hashlib / pathlib / typing.
- `docs/python_to_kir.md` construct-by-construct IR lowering spec.
- `docs/python_compat.md` non-goal matrix.
- `examples/python_demo.pyk` end-to-end target (uses ~30 polyfills).
- All names use the `*k` suffix to avoid "py" in user-visible
  identifiers per Brian's call.

### Three-agent coordination
- `.k` canonical / `.ks` fallback convention locked across w / m / l.
- raw-mem ABI aligned with l: rawAlloc / rawFree / rawRealloc +
  ptrAdd / ptrToInt / intToPtr / ptrEq.
- m's stage 6 phase 2 Mach-O port landed.
- l asked to cross-compile x64.k to help unblock the regen.

## Open items for the next session

In priority order:

1. **Unblock the regen.** Either l's cross-compile route works (in
   which case feed the IR back to Windows BE), or offline hex-patch
   `krypton_rt.dll`'s sbAppend routine, or find a beefier Windows
   box. Without this, runtime validation can't happen and every
   shipped-source-only piece this session stays unvalidated.
2. **Validate phase 2** via `tests/gc_freelist_consume.k` once
   regen is back.
3. **Implement phase 3** per the plan.
4. **Validate the 5 IAT slots** with small smoke programs (one per
   DLL importing one symbol).
5. **PE rsrc manifest embedding** in x64.k. Source change is
   chunky; queue after the regen path is restored.
6. **`krypton_rt_legacy.dll` elimination** via inline-during-
   bootstrap. Same regen prerequisite.
7. **Python prep continuation**: pathlib `is_dir` real check via
   GetFileAttributesA, argparse polyfill, urllib.parse, datetime
   wrapper.

## Pre-approvals still standing

- Stage 6 phase 3 implementation: Brian preapproved after phase 2
  validates.
- Continued Python prep work: Brian said "work on the python
  elements every chance you get."

## Notes for whoever picks this up

- All commits this session use `Co-Authored-By: Claude Opus 4.7
  <noreply@anthropic.com>` since I'm authoring under explicit
  Brian-stated co-authorship.
- The regen diagnostic
  (`handoffs/w_x64host_regen_64k_truncation.md`) is the most
  important file in the session if you're trying to unblock the
  Windows track. Read it first.
- m's `.ks` fallback wiring in `compile.k:3d9a1d1c` is the
  mechanism that makes the import paths I used (`k:string`,
  `k:list`, etc.) resolve cleanly. Don't undo it.

— w
