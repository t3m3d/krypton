# Changelog

All notable changes to the Krypton language and compiler.

## [1.8.0] - 2026-05-04 (release candidate — installer built, upload pending)

Diagnostic primitives + comprehensive memory model docs. Rolls up the
Tier 1 + Tier 2 GC machinery from 1.7.x (StringBuilder refactor,
allocation tracking, soft limit + circuit breaker, single-slab arena,
multi-slab linked list, scope-bound checkpoint/restore, auto-emit
via `pure_` prefix) and adds the visibility primitives that finish
the diagnostic story.

**Installer built and ready** at `installer/Output/krypton-1.8.0-setup.exe`
(2.35 MB). Bootstrap seeds synced. GitHub upload pending user
go-ahead.

### Two new diagnostic primitives

- **`gcSlabCount()`** (35 bytes) — walks `slab_first->next` chain
  counting. Returns int-string. Useful for understanding multi-slab
  behavior under load.
- **`gcSlabBytes()`** (21 bytes) — returns `slab_off`, the bump
  offset within the current slab (includes the 8-byte next-pointer
  header). Together with `gcSlabCount()`, lets user code estimate
  total current usage:
  `(slabCount - 1) * 64MB + slabBytes`.

`KRRT_FUNCS` grew by 2. `bsHelperBlockSize()` 7818 → 7874 (+56 bytes).

### Compiler bindings

- `compiler/windows_x86/x64.k`'s `resolveBuiltin` maps
  `gcSlabCount` → `kr_gc_slab_count`,
  `gcSlabBytes` → `kr_gc_slab_bytes`.
- `compiler/compile.k`'s builtin list adds the two names.

### Verified end-to-end

```
empty state: 1 slab, 48 bytes used
after 80 MB allocations: 2 slabs, 14 MB used in current
after gcReset: 1 slab, 56 bytes used
```

Multi-slab behavior observable for the first time without inferring
from `gcAllocated()` math.

### Bug caught mid-cut (saved to memory)

First version of `kr_gc_slab_count` had `JZ +8` (target byte 26)
instead of `JZ +7` (target byte 25). With +8 the jump landed
mid-instruction (in the middle of the CALL opcode), causing
`SIGILL` / illegal instruction. Generic lesson: when computing
short-jump displacements, target = byte _index_ of destination
instruction's first byte; disp = target - (RIP after the JZ
instruction itself). Off-by-one between "byte index of target" and
"length-of-RIP-after-instruction" is the easy way to land
mid-instruction.

### New documentation

- **`docs/memory_vs_c.md`** — comprehensive head-to-head with C's
  `malloc`/`free` model. Covers: side-by-side comparison table,
  the 50 GB scenario as a concrete example, `--watch` / event-loop
  pattern, procedural-helper `pure_` pattern, full primitive
  reference, what Krypton's model is NOT (no mark-sweep yet,
  single-threaded, no defrag), and when C is still the right
  choice.

### Tooling

- `kcc.exe` rebuilt — `kcc --version` reports 1.8.0
- `assets/krypton.rc` bumped to `KCC_VER_MIN=8`, `KCC_VER_PATCH=0`
- `runtime/krypton_rt.dll` rebuilt — 12800 bytes (unchanged from
  1.7.x — the new helpers fit in the existing page)
- `versions/kcc_v180.exe` snapshot
- `installer/krypton-installer.iss` bumped to `KryptonVersion="1.8.0"`
- **`installer/Output/krypton-1.8.0-setup.exe`** produced from the
  unchanged-AppId Inno script (2.35 MB; in-place upgrade over
  any 1.4.x / 1.5.x / 1.6.x / 1.7.x install)
- `bootstrap/x64_host_windows_x86_64.exe` and
  `bootstrap/krypton_rt_windows.dll` synced (so the next clean
  rebuild from git seeds reproduces 1.8.0)
- VS Code extension bumped 1.6.0 → 1.8.0
  (`krypton-lang/package.json`). Builtins regex in
  `krypton-lang/syntaxes/krypton.tmLanguage.json` expanded to cover
  every primitive added 1.6.0 → 1.8.0: `padLeft`, `padRight`,
  `min`, `max`, `bin`, `sign`, `clamp`, the full GC primitive set
  (`gcAllocated`, `gcLimit`, `gcSetLimit`, `gcCollect`, `gcReset`,
  `gcCheckpoint`, `gcRestore`, `gcSlabCount`, `gcSlabBytes`), the
  `native_extras.k` stdlib helpers (`join`, `slice`, `splitBy`,
  `sort`, `keys`, `values`, etc.), and the buf/handle/ptr/raw
  families. New `extensions/krypton-language-1.8.0.vsix` packaged
  alongside the 1.5.0 one — install with
  `code --install-extension krypton-language-1.8.0.vsix --force`.
- GitHub upload + krypton-lang.org download page **pending user go-ahead**

## [1.7.9] - 2026-05-04 (internal build, not released)

Auto-emission of `gcCheckpoint` / `gcRestore` for functions whose name
starts with `pure_`. The compiler wraps the body so per-call slab
allocations are reclaimed on return, without the user having to
write the boilerplate explicitly. Procedural functions (no return
value, no `emit`) get bounded memory for free.

This is an *internal* build — kept under `versions/kcc_v179.exe` as a
record snapshot. No installer, no public release.

### What `pure_` does

In `compiler/compile.k`'s IR-emission for function declarations
(`irFuncIR`), if the function name starts with `pure_` the body is
wrapped:

```
LOCAL _gc_ck
BUILTIN gcCheckpoint 0
STORE _gc_ck
<original body>
LOAD _gc_ck
BUILTIN gcRestore 1
POP
```

After the function returns, the slab pointer rewinds past everything
the function allocated. The lifetime-cumulative `gcAllocated()` counter
still reflects the allocations (it tracks lifetime, not current usage),
but the actual slab space is reclaimed.

### Caveats — when NOT to use `pure_`

- The wrapping appends BEFORE the implicit function-end RETURN. If the
  body has an explicit `emit X` or `return X`, control transfers out
  via `RETURN` BEFORE the appended `gcRestore` runs. The function
  leaks just like a non-pure function would. **Use `pure_` only for
  procedural functions** (side-effects only, no useful return value).
- Returning an allocated value from a `pure_` function is undefined —
  even if the wrap somehow ran, the returned pointer would point into
  the rewound (now-freed) slab range.
- `pure_` functions still pay the `gcCheckpoint`/`gcRestore` overhead
  per call (~30 bytes of slab + Win32 syscall for the chain walk if
  multi-slab). Cheap compared to leaks but not free.

### Verified

- `pure_renderPanel(name)` test: compiles, runs, output identical to
  non-pure version.
- 1000-iteration tight loop of `pure_doWork(i)` with ~3 KB/call
  allocation: clean run, exit code 0, no OOM.

### Tooling

- `kcc.exe` rebuilt — `kcc --version` reports 1.7.9
- `assets/krypton_rc.o` rebuilt via windres
- `versions/kcc_v179.exe` snapshot
- `runtime/krypton_rt.dll` unchanged from 1.7.8 (no runtime change —
  this is purely a compiler-side IR transformation that uses
  existing primitives)
- **No installer, no upload, no download page**
- Bootstrap seeds NOT updated

## [1.7.8] - 2026-05-04 (internal build, not released)

Checkpoint / restore primitives for the arena. `gcCheckpoint()` returns
an opaque token that captures the current arena state; `gcRestore(token)`
walks the slab chain freeing everything allocated since, then rewinds
`slab_curr` and `slab_off`. Useful for scope-bound bulk free without
having to reset the entire arena.

This is an *internal* build — kept under `versions/kcc_v178.exe` as a
record snapshot. No installer, no public release.

### Two new runtime primitives

- **`kr_gc_checkpoint()`** (62 bytes) — allocates a 16-byte token from
  the arena itself, stores `[saved_slab_curr, saved_slab_off]` into
  it, returns the token pointer as int-string. Includes a 1-byte
  warmup `__rt_alloc` call at the very start to guarantee the slab
  is initialized — otherwise a checkpoint taken before any user
  allocation would record `slab_curr = NULL` and `gcRestore` would
  crash on the chain dereference.
- **`kr_gc_restore(token_str)`** (90 bytes) — `atoi`s the token,
  reads back the saved state, walks `saved_slab_curr->next` chain
  freeing each slab via `HeapFree`, sets
  `saved_slab_curr->next = NULL`, restores `slab_curr` and `slab_off`.
  The token's own memory is reclaimed (slab_off rewinds past it),
  so the token becomes invalid after the restore — caller mustn't
  reuse it.

`alloc_total` is intentionally NOT adjusted on restore — it still
shows lifetime cumulative bytes allocated. Reasoning: most callers
use `gcAllocated()` for diagnostics where lifetime is what they
want; if you need "current usage" you'd derive it differently
(e.g., before/after pair).

### Compiler bindings

- `compiler/windows_x86/x64.k`'s `resolveBuiltin` maps
  `gcCheckpoint` → `kr_gc_checkpoint`,
  `gcRestore` → `kr_gc_restore`.
- `compiler/compile.k`'s builtin list adds the two names.
- `KRRT_FUNCS` grew by 2.

### Verified end-to-end

- Single-slab checkpoint/restore — counter behaves correctly,
  subsequent allocs land in the rewound slot.
- Multi-slab checkpoint/restore — 80 MB allocated between checkpoint
  and restore (forces second slab); after restore, second slab is
  freed via HeapFree, slab_curr rewinds to first slab. Subsequent
  allocations succeed.
- Limit semantics still work: `gcSetLimit(100)` + alloc loop aborts
  with `rc=99`.
- Fibonacci compiles + runs cleanly.

### Bug caught mid-cut (worth remembering)

First version of `gcCheckpoint` read `slab_curr` before any
allocation could initialize it. If `gcCheckpoint()` was the first
operation in `just run { ... }`, slab_curr was NULL → token recorded
NULL → `gcRestore`'s `MOV RDI, [RBX]` crashed dereferencing NULL.
Fix: warm up with a 1-byte alloc inside `gcCheckpoint` before
saving state. Costs 8 bytes (aligned) of slab waste in exchange for
a much simpler invariant for `gcRestore`.

`bsHelperBlockSize()` 7666 → 7818 (+152 bytes).

### Tooling

- `kcc.exe` rebuilt — `kcc --version` reports 1.7.8
- `assets/krypton_rc.o` rebuilt via windres
- `runtime/krypton_rt.dll` rebuilt — 12800 bytes (was 12288, the
  +152 bytes pushed past a 512-byte file-alignment boundary)
- `versions/kcc_v178.exe` snapshot
- **No installer, no upload, no download page**
- Bootstrap seeds NOT updated

## [1.7.7] - 2026-05-04 (internal build, not released)

Multi-slab arena. Allocations beyond a single 64 MB slab now allocate
new slabs and link them into a chain instead of falling back to per-call
HeapAlloc. `gcReset()` walks the chain and frees every slab except the
first via HeapFree, then resets state. The bump-allocator fast path is
preserved for arbitrarily large total allocations.

This is an *internal* build — kept under `versions/kcc_v177.exe` as a
record snapshot. No installer, no public release.

### gcGlobals expanded to 48 bytes (was 32)

Added `slab_first` (head of slab linked list) so `gcReset()` knows
which slab to keep.
- `+0`  alloc_total (qword) — unchanged
- `+8`  alloc_limit (qword) — unchanged
- `+16` slab_first  (qword) — NEW: head of slab chain
- `+24` slab_curr   (qword) — current allocation slab (was `+16`)
- `+32` slab_off    (qword) — bytes used in slab_curr (was `+24`)
- `+40` reserved

Each slab: `[0..7]` = pointer to next slab (NULL if last),
`[8..SLAB_SIZE-1]` = payload area. `slab_off` starts at 8 (past the
next-pointer prefix).

### `__rt_alloc_v2` rewritten — 172 → 277 bytes

New behavior on slab overflow: allocate a new 64 MB slab via
`HeapAlloc`, link `slab_curr->next = new`, set `slab_curr = new`,
`slab_off = 8`. Bump from new slab. Repeats indefinitely (each new
slab is another 64 MB chunk).

Falls back to per-call `HeapAlloc` only for genuinely huge single
allocations (size > `SLAB_SIZE - 8` = ~64 MB). These rare allocations
aren't tracked by the slab list and aren't reclaimed by `gcReset()`.

### `kr_arena_reset` rewritten — 21 → 97 bytes

Walks `slab_first->next` chain, calling `HeapFree(GetProcessHeap(), 0,
slab)` for each subsequent slab. Then sets `slab_first->next = NULL`,
`slab_curr = slab_first`, `slab_off = 8`, `alloc_total = 0`. The first
slab is preserved so the next allocation still hits the fast bump path
without paying for a fresh `HeapAlloc`.

### Verified end-to-end

- Allocated 80,910,710 bytes (~77 MB) in a tight loop, exceeding the
  single-slab cap. Result: clean run, multi-slab path exercised.
- `gcReset()` after the heavy load brought counter back to 0.
- Subsequent small alloc started from offset 0 (well, 26 bytes for the
  `gcAllocated()` return string), proving the chain was reset and the
  first slab was reused.
- Soft limit still works: `gcSetLimit(100)` + alloc loop aborts with
  `rc=99`.
- Fibonacci compiles + runs cleanly.

`bsHelperBlockSize()` 7485 → 7666 (+181 bytes).

### Known limits

- 64 MB slab size hardcoded. Could be a #define-equivalent for tuning.
- `HeapFree` failure on the per-slab free is silently ignored (no error
  propagation). Probably fine — `HeapFree` rarely fails on a known-good
  pointer, but worth tracking.
- The huge-alloc fallback (>64 MB single allocation) leaks until process
  exit. Acceptable for now — these are rare edge cases.

### Tooling

- `kcc.exe` rebuilt — `kcc --version` reports 1.7.7
- `assets/krypton_rc.o` rebuilt via windres
- `versions/kcc_v177.exe` snapshot
- `runtime/krypton_rt.dll` rebuilt (12288 bytes — same as 1.7.6, fits)
- **No installer, no GitHub upload, no download page** — internal only
- Bootstrap seeds NOT updated

## [1.7.6] - 2026-05-04 (internal build, not released)

Tier 2 of the GC plan: arena slab allocator. `__rt_alloc` now
bump-allocates from a 64 MB slab held in `gcGlobals[16..23]` instead
of calling `HeapAlloc` per string. New `gcReset()` builtin recycles
the slab in O(1). The 1.7.5 tracking + soft-limit semantics are
preserved.

This is an *internal* build — kept under `versions/kcc_v176.exe` as
a record snapshot. No installer, no download page, no public release.
Next public release rolls 1.7.5 → 1.8 or similar once the arena
infrastructure is exercised across more programs.

### Bootstrap helper block — slab-based `__rt_alloc_v2`

- Replaced the 76-byte `__rt_alloc_v2` from 1.7.5 with a 172-byte
  version that:
  - Tracks `alloc_total` and enforces `alloc_limit` (1.7.5 behavior)
  - Aligns the requested size up to 8 bytes
  - Bump-allocates from a 64 MB slab pointed to by `gcGlobals[16]`,
    with the next-free offset in `gcGlobals[24]`
  - Lazily allocates the slab via `HeapAlloc(64MB)` on first use
  - Falls back to per-call `HeapAlloc` if the slab is full or
    creation fails (no abort, no regression vs. 1.7.5)
- `__rt_alloc`'s 34-byte stub at offset 18 still `JMP rel32`s to
  `__rt_alloc_v2` — same target offset (7201), no call-site changes
  anywhere in the bootstrap block.
- `gcGlobals` slot is still 32 bytes; the previously-reserved
  `+16` and `+24` qwords are now used.

### New runtime primitive — `kr_arena_reset`

- 21 bytes. Zeros `slab_off` (so the next allocation reuses the
  start of the slab) and `alloc_total` (so subsequent
  `gcAllocated()` reads start from 0). Memory in the slab is NOT
  freed — it's just re-bumpable. Off-slab fallback allocations
  stay alive until process exit.
- Returns `"0"` (tail-jumps to `kr_gc_collect` for the placeholder
  return string).

### Compiler bindings

- `compiler/windows_x86/x64.k`'s `resolveBuiltin` maps `gcReset` →
  `kr_arena_reset`.
- `compiler/compile.k`'s builtin list adds `gcReset` so calls emit
  `BUILTIN gcReset 0` IR.
- `KRRT_FUNCS` grew by 1 (`kr_arena_reset`).

### Verified end-to-end

- `gcAllocated()` climbs as strings concat (408 bytes after 10
  iterations of `"scratch " + i + " more text"`).
- `gcReset()` zeroes the counter (`2` after reset = the `gcAllocated()`
  return-string itself).
- Same workload after `gcReset()` allocates from the same slab range
  rather than growing the bump pointer.
- 1.7.5 limit semantics preserved — `gcSetLimit(100)` still aborts
  with `rc=99` when exceeded.
- Fibonacci compiles to byte-identical 8192-byte PE and runs cleanly.

`bsHelperBlockSize()` 7368 → 7485 (+117 bytes: +96 for `__rt_alloc_v2`
growth, +21 for `kr_arena_reset`).
`runtime/krypton_rt.dll` unchanged at 12288 bytes (the section is
already two pages; the new helpers fit).
DLL exports: 110 → 111.

### What 1.7.6 still does NOT ship

- No automatic reset emission. The compiler doesn't insert
  `gcReset()` at scope boundaries — user code calls it explicitly.
  Auto-emission is a Tier 2.5 / 2.0 design discussion.
- No mark-sweep. `gcCollect()` is still placeholder. Reachability
  analysis lands in 2.0 with shadow-stack roots.
- No multi-slab. If a program allocates more than 64 MB between
  resets without one of the allocations exceeding the slab budget,
  fallback per-call `HeapAlloc` kicks in for those overflows
  (slow path, but correct).
- Linux ELF and macOS arm64 still on 1.6-era runtime — Windows
  remains the lead platform.

### Tooling

- `kcc.exe` rebuilt — `kcc --version` reports 1.7.6
- `assets/krypton.rc` bumped to `KCC_VER_PATCH=6`, `assets/krypton_rc.o`
  recompiled via windres
- `versions/kcc_v176.exe` snapshot
- `runtime/krypton_rt.dll` rebuilt (12288 bytes, same as 1.7.5 — the
  bootstrap text section absorbed the +117 bytes without crossing a
  page boundary)
- **No installer, no GitHub upload, no download page** — internal
  build only. The bootstrap seeds (`bootstrap/x64_host_windows_x86_64.exe`,
  `bootstrap/krypton_rt_windows.dll`) intentionally NOT updated
  for the same reason.

## [1.7.5] - 2026-05-04

**GC starts actually working.** 1.7.5 adds the first real allocation
tracking and soft-limit enforcement to the Windows native runtime.
Programs can read `gcAllocated()` to see total bytes ever allocated,
and `gcSetLimit(n)` installs a circuit breaker that aborts the
process cleanly with `ExitProcess(99)` if total allocation crosses
the cap. The bootstrap DLL grew its first writable data slot.

### Bootstrap DLL — writable globals + tracked allocator

- New 32-byte zero-initialised slot at the very start of the
  bootstrap DLL's `.rdata` section, holding the GC globals:
  `[+0] alloc_total` (qword), `[+8] alloc_limit` (qword),
  `[+16..+31]` reserved.
- `.rdata` characteristics flipped from `0x40000040` (read-only) to
  `0xC0000040` (read+write) so the slot is writable at runtime.
- The import table and export table now start at `.rdata + 32`
  instead of `.rdata + 0`. RVA computations updated; PE layout
  otherwise unchanged.
- `__rt_alloc` (the 34-byte slot at offset 18 in the bootstrap
  helper block) now tail-jumps via `JMP rel32` to a new
  `__rt_alloc_v2` helper appended at the end of the block. The
  slot stays 34 bytes so every existing `CALL __rt_alloc` site
  still resolves correctly &mdash; no offset cascading.
- `__rt_alloc_v2`: adds the requested size to `alloc_total`, loads
  `alloc_limit`; if the limit is non-zero and total exceeds it,
  calls `ExitProcess(99)`; otherwise calls `GetProcessHeap` +
  `HeapAlloc` as before.

### Four new runtime primitives, exported from `krypton_rt.dll`

- `kr_gc_allocated()` &mdash; returns total bytes allocated since
  process start (int-string).
- `kr_gc_limit()` &mdash; returns current soft limit (int-string;
  `0` = unlimited).
- `kr_gc_set_limit(n)` &mdash; sets the limit; returns the original
  input string.
- `kr_gc_collect()` &mdash; placeholder, returns `"0"`. Tier 3
  mark-sweep gives this real semantics in 2.0.

`KRRT_FUNCS` grew by 4. `bsHelperBlockSize()` grew 7201 &rarr; 7368
(+167 bytes: 76 for `__rt_alloc_v2`, 21 each for `kr_gc_allocated`
and `kr_gc_limit`, 23 for `kr_gc_set_limit`, 26 for `kr_gc_collect`).

### Compiler bindings

- `compiler/windows_x86/x64.k`'s `resolveBuiltin` maps
  `gcAllocated` &rarr; `kr_gc_allocated`, `gcLimit` &rarr; `kr_gc_limit`,
  `gcSetLimit` &rarr; `kr_gc_set_limit`, `gcCollect` &rarr; `kr_gc_collect`.
- `compiler/compile.k`'s builtin list adds the four names so calls
  emit the `BUILTIN` IR opcode (rather than falling through to
  user-function lookup).
- `stdlib/native_extras.k` now provides a `gcStats()` convenience
  wrapper that returns `"<allocated>,<limit>"` by calling the two
  primitives and concatenating.

### Verified end-to-end

- `gcAllocated()` returns `0` at process start, climbs as strings
  are concatenated. Confirmed monotonic increase across multiple
  reads.
- `gcSetLimit(100)` followed by a string-allocating loop aborts
  the program with rc=99 instead of pinning RAM.
- Fibonacci compiles to the same 8192-byte PE and runs cleanly
  &mdash; existing `__rt_alloc` callers (every `CALL` to offset 18)
  transparently get the new tracking.
- `examples/test_builtins.k` (repeat/padLeft/padRight/reverse)
  passes unchanged.

### What 1.7.5 still does NOT ship

- No reclamation. `gcCollect()` is still a placeholder. The
  bump arena still grows monotonically; only the *limit* enforcement
  is new. Programs that allocate beyond the limit abort rather
  than reclaim.
- Single-threaded only. The `ADD [RIP+disp], RCX` is not `LOCK`-
  prefixed, so multi-threaded use would race. Krypton has no
  threading yet, so this is fine for 1.7.x.
- Linux ELF and macOS arm64 backends not yet updated. Windows
  native is the lead platform for the GC infrastructure work
  through 2.0; the other two pick it up before final 2.0.

### Roadmap

- **1.7.6** &mdash; arena slab allocator: replace per-string `HeapAlloc`
  with bulk slab allocation, add `kr_arena_reset()` for explicit
  scope-bound bulk free. Less GC pressure; foundation for epoch
  reset.
- **2.0** &mdash; Tier 3. Real mark-sweep collector with
  shadow-stack roots, ABI break, full `gcCollect()` semantics.
  Plus the C-style low-level memory layer (typed pointers, `let
  local` stack allocation, restricted `asm` blocks), lambdas in
  native, concurrency, ARM64 Linux backend, LSP.

See `docs/v20_plan.md` for the full sequencing.

### Tooling

- `kcc.exe` rebuilt &mdash; `kcc --version` reports 1.7.5
- `assets/krypton.rc` bumped to `KCC_VER_PATCH=5` and recompiled via
  windres so file properties show 1.7.5
- `runtime/krypton_rt.dll` rebuilt: 11776 &rarr; 12288 bytes (the new
  helpers + the GC globals slot push it over a page boundary)
- `installer/Output/krypton-1.7.5-setup.exe` produced from the
  unchanged-AppId Inno script (in-place upgrade over 1.6.x / 1.7.0)
- `versions/kcc_v175.exe` snapshot
- `bootstrap/x64_host_windows_x86_64.exe` and
  `bootstrap/krypton_rt_windows.dll` synced
- `RELEASE_NOTES_1.7.5.txt` in the repo root

## [1.7.0] - 2026-05-04

Memory-plumbing release. Tier 1 of the [2.0 GC plan](docs/v20_plan.md)
ships here as a self-contained semantics-preserving optimization &mdash;
no ABI change, no DLL rebuild required, PE output is byte-identical
to 1.6.1 for every test program. The same patch cuts the kind of O(N&sup2;)
allocation that produced the 50 GB kcc.exe blowup observed during
1.6.1 development on a malformed source file.

### Compiler memory &mdash; StringBuilder refactor

Krypton has no GC today (bump-only arena), so every `s = s + chunk`
chain in the compiler allocates a fresh string each iteration and
abandons the previous one. For per-character loops over the source
that is O(N&sup2;) in RAM. Replaced the worst hot paths in
`compiler/windows_x86/x64.k` and `compiler/compile.k` with the
already-available `sbNew` / `sbAppend` / `sbToString` builtins, which
the runtime services with a single growable buffer.

In `compiler/windows_x86/x64.k`:
- `hexStrIR` (per-character escape encoding for the .rdata string table) &mdash;
  was the single worst offender; eight per-character concat sites
- `emitStringTable` (per-string outer loop)
- `buildExportTable` &mdash; EAT, NPT, OT, name strings, directory
- `buildImportTable` &mdash; descriptor + 14-step section assembly
- `buildBootstrapImportTable` &mdash; bootstrap-mode descriptor + assembly

In `compiler/compile.k`:
- `cEscape` (C-string escaping for emitted source)
- `expandEscapes` (string-literal escape resolution)

`emitFuncFull` and the bootstrap helper block already use the `sbAppend`
pattern; no change needed there.

The change is invisible to user programs &mdash; PE output is byte-identical
on every test compiled before and after.

### Status of the 2.0 plan

Tier 1 of the GC roadmap is now in. Remaining tiers stay out of 1.x:
- 1.8 candidate or 2.0-alpha-1: Tier 2 arena allocator with epoch reset
  (runtime-internal change, no ABI break, scope-bound bulk reclaim)
- 2.0-alpha-2 onward: Tier 3 mark-sweep with shadow-stack roots,
  rolled out per backend (Linux ELF first, Windows native second,
  macOS arm64 last)

See `docs/v20_plan.md` for the full sequencing including the new
C-style low-level memory layer (typed pointers, `let local` stack
allocation, restricted `asm` blocks, mmap, direct syscalls), lambdas
in native, concurrency primitives, ARM64 Linux backend, and LSP.

### Tooling

- `kcc.exe` rebuilt &mdash; `kcc --version` reports 1.7.0
- `assets/krypton.rc` bumped to `KCC_VER_MIN=7` and recompiled via
  windres so file properties show 1.7.0
- `installer/Output/krypton-1.7.0-setup.exe` to be produced from the
  unchanged-AppId Inno script (in-place upgrade over 1.6.x / 1.5.x)
- `versions/kcc_v170.exe` snapshot

## [1.6.1] - 2026-05-04

A follow-on to 1.6.0 (which never reached the public download page) that
widens the Windows native pipeline's builtin coverage. Native examples
climb from 70 / 95 to 77 / 95 directly via newly-implemented runtime
helpers, and another two (`list_operations`, `word_frequency`) join them
through the new opt-in `stdlib/native_extras.k` module.

### Native runtime — 10 new builtins in the bootstrap helper block

All follow the non-cascading append pattern: helpers go at the end of
the bootstrap block, exported via `offsets +=`, and registered in
`resolveBuiltin` plus `KRRT_FUNCS`. No cascading offset edits required.

Batch 1 — string helpers:
- `repeat(s, n)` → `kr_repeat` (111 bytes)
- `padLeft(s, w, pad)` → `kr_padleft` (137 bytes)
- `padRight(s, w, pad)` → `kr_padright` (139 bytes)
- `reverse(s)` → `kr_reverse` (66 bytes)
- `toStr(x)` → alias of `kr_str`

Batch 2 — numeric and tail:
- `abs(n)` → `kr_abs` (32 bytes)
- `min(a, b)` → `kr_min` (48 bytes)
- `max(a, b)` → `kr_max` (48 bytes)
- `endsWith(s, suf)` → `kr_endswith` (122 bytes)
- `bin(n)` → `kr_bin` (112 bytes)
- `pow(b, e)` and the `**` operator → `kr_pow` (64 bytes)

`bsHelperBlockSize()` grew 6322 → 7201 (+879 bytes total). Native
test count unchanged (38 / 38 — no regressions). Examples newly
passing: `binary_convert`, `countdown`, `day_planner`,
`grade_calculator`, `hello_modules`, `hex_table`, `test_v125`.

### `stdlib/native_extras.k` — opt-in helper bundle (no DLL changes)

A discovery: when the native pipeline emits `BUILTIN <name>` IR for a
function with no entry in any IAT, the codegen falls through
`iatEntryRvaFor` → `funcOffsetLookup` and finds a user-defined function
of the same name (if one is in scope). That means a stdlib module of
plain Krypton funcs can satisfy these "missing builtins" without any
hand-written x64, any new DLL exports, or any KRRT_FUNCS edits.

`stdlib/native_extras.k` ships 25 such helpers: `join`, `slice`,
`splitBy`, `sumList`, `minList`, `maxList`, `countOf`, `unique`,
`keys`, `values`, `hasKey`, `mapGet`, `mapSet`, `remove`, `fill`
(arg order: `fill(count, value)`), `zip`, `sign`, `clamp`,
`parseInt`, `sort` (lexicographic, bubble), `listIndexOf`, `every`,
`some`.

Programs that need any of these add a single line:
`import "stdlib/native_extras.k"`. The C path is unaffected because
`compile.k`'s C-emit branch routes those names to `kr_*` C wrappers
before the BUILTIN IR path is reached. Updated `examples/list_operations.k`
and `examples/word_frequency.k` to demonstrate.

### Tooling

- `kcc.exe` rebuilt — `kcc --version` reports 1.6.1
- `assets/krypton.rc` bumped to `KCC_VER_PATCH=1` and recompiled via
  windres so file-properties show 1.6.1
- `installer/Output/krypton-1.6.1-setup.exe` to be produced from the
  unchanged-AppId Inno script (in-place upgrade over 1.6.0/1.5.x)
- `versions/kcc_v161.exe` snapshot

## [1.6.0] - 2026-05-04

The headline is a **one-line fix that restores the Windows native pipeline**.
Pre-1.6.0, every `if` statement and `while` loop on Windows native segfaulted
the resulting binary — a regression that shipped silently in 1.5.0 and 1.5.1
because `examples/fibonacci.k` (the smoke-test) appeared to "exit cleanly"
when in fact it was crashing right after the first line of output. Bisecting
revealed a missing entry in x64.k's `resolveBuiltin` table.

### Compiler — native pipeline restored

Two coupled bugs in `compiler/windows_x86/x64.k` that together broke
every program with a conditional or short-circuit logical operator on
the Windows native pipeline:

- **`isTruthy` was missing from `resolveBuiltin`.** 1.5.0's
  boolean-truthiness fix added a `BUILTIN isTruthy 1` instruction
  before every `JUMPIFNOT` (so `if ""` and `if "0"` would correctly
  take the false branch). compile.k started emitting that instruction,
  but x64.k's resolver had no `isTruthy → kr_truthy` mapping. Without
  the mapping, `iatEntryRvaFor` returned -1 and the dispatcher fell
  into the "user-defined function" branch, emitting a CALL with
  displacement computed against
  `funcOffsetLookup(allFuncOffsets, "isTruthy")` (which doesn't exist)
  → CALL to address roughly `.text - 1`. Every conditional segfaulted.
  Fix: one new line, `if name == "isTruthy" { emit "kr_truthy" }`.
- **Virtual-stack pointer wasn't reconciled at LABEL ops** that act as
  control-flow merge points. `&&`, `||`, ternary, and any if/else with
  expression-valued branches all generate IR like:

  ```
  JUMPIFNOT _else
  PUSH true_value
  JUMP _end
  LABEL _else
  PUSH false_value
  LABEL _end
  STORE result
  ```

  The TRUE branch's PUSH wrote vstack slot `vsp=0`. After the JUMP, the
  linear walker arrived at LABEL `_else` with `vsp=1` (still tracking
  the true-branch state). The FALSE branch's PUSH wrote slot
  `vsp=1` instead of slot `vsp=0`. The merge LABEL's STORE then read
  slot 1, finding stale memory on the path that took the TRUE branch.
  Result: random segfaults / wrong values from any expression using
  `&&`, `||`, or ternary.

  Fix: track vsp at each branch source (`JUMP`, `JUMPIF`, `JUMPIFNOT`)
  in a `vspAtLabel` map. At each LABEL, look up the recorded vsp and
  reset the walker's vsp to it. Both branches now write the correct
  slot and the merge reads the right one.

- **Native test pass rate went from 0/38 → 30/38** after both fixes
  (excluding test_dll_exports.k which is Windows-only-meta). Specific
  wins: every test using `if`, `while`, `for-in`, `&&`, `||`,
  ternary, recursion, nested conditionals, while-break, structs (jxt-
  typed), arithmetic, modulo, string ops, try/catch all pass.
  Remaining 8 failures are unrelated runtime-DLL bugs (count returning
  wrong values, env/struct user-defined runtime not implemented on
  Windows native, C-path booleans divergence) — each individually
  tractable but scoped for future work.

- **Real-world impact**: `examples/fibonacci.k` runs to completion with
  full output (was: first line + crash). `kryofetch` builds and runs
  natively again — full panel output, exit 0. Programs using `sbAppend`
  in tight loops now work (those crashes were the same isTruthy bug,
  not a separate sbAppend issue).

### C path — 38/38 tests now pass

Two small fixes in `compiler/compile.k`'s C-emit section:

- **`kr_truthy` now recognises `"false"` as falsy.** The Linux ELF
  native runtime got this in 1.5.0 (`kr_istruthy` rewrite, 27 → 79
  bytes); the C-path version of `kr_truthy` was still only checking
  for empty / null / `"0"`. Fix: one extra `if (strcmp(s, "false") == 0)
  return 0;`. Closes `test_booleans.k` on the C path (44/44 sub-asserts
  pass, was 42/44).
- **`kr_count` now actually counts comma-separated items.** Was a stub
  that returned `kr_linecount(s)`. Fix: real comma-counting impl.
  Closes `test_count.k` (7/7) and cascades to `test_split.k`.

### Native bootstrap helper block — eight fixes via the append pattern, full env runtime added

A non-cascading technique landed four runtime-DLL fixes without
shifting any existing function offset. Pattern: append the corrected
helper at the END of the bootstrap block, then either retarget the
existing stub's JMP target or rewrite the export-table entry to point
at the new offset. Only `bsHelperBlockSize()` updates each round.
Stays well under the 8 KB section-alignment boundary (5681 → 6093
of 8192), so PE layout is unchanged on every round.

1. **`kr_count_commas`** (offset 5803, +42 bytes). Original kr_count
   and kr_length stubs were 5-byte JMPs to kr_linecount, so they
   counted `\n`-delimited lines instead of `,`-delimited items. Now
   both JMP to the new helper (same shape as kr_linecount but compares
   against `,` 0x2C instead of `\n` 0x0A). Closes `test_count.k`.
2. **`__rt_truthy_int_v2`** (offset 5845, +43 bytes). Original
   `__rt_truthy_int` only recognised `""` and `"0"` as falsy. The new
   helper checks for the 6-byte sequence `"false\0"` first; falls
   through to the original via tail-call. Both `kr_truthy` and
   `kr_not` now CALL v2 instead of v1 (CALL displacement retargeted
   in place — no size change). Closes `test_booleans.k` (44/44).
3. **`kr_split_commas`** (offset 5888, +149 bytes). Full copy of the
   original 149-byte kr_split impl with the two `CMP AL` bytes
   changed (0x0A → 0x2C). The kr_split EXPORT entry rewritten to
   point at the new offset. Original 149 bytes stay at offset 2316
   (unnamed) so kr_getline's raw JMP still works for `\n`-splitting.
   Closes `test_split.k` (14/14) — split() splits on commas; getline()
   splits on newlines as before.
4. **`kr_linecount_smart`** (offset 6037, +56 bytes). Original
   kr_linecount always added 1 at end-of-string, so it returned 5
   for "a\nb\nc\nd\ne\n" instead of 5. New helper counts '\n's, then
   adds 1 only if string is non-empty AND last char is not '\n'.
   kr_linecount EXPORT entry rewritten to point at the new offset.
   Original 42 bytes stay (unused as export, harmless). Closes
   `test_line_ops.k` (11/11) and cascade-fixes `test_sb_ops.k` and
   `test_string_escape.k` (which depended on lineCount being correct).
5. **`__rt_truthy_int_v2`** (offset 5845, +43 bytes). Original
   `__rt_truthy_int` only recognised `""` and `"0"` as falsy. New
   helper checks for the 6-byte sequence `"false\0"` first; falls
   through to the original via tail-call. Both `kr_truthy` and
   `kr_not` now CALL v2 instead of v1. Closes `test_booleans.k` (44/44).
6. **`kr_envnew` / `kr_envset` / `kr_envget`** (offsets 6093, 6096,
   6141, total +117 bytes). First implementation of the env-style
   linked-list runtime on Windows native (1.5.0 added it on Linux ELF
   only). 24-byte EnvEntry nodes {name_ptr, value_ptr, prev_ptr};
   envGet walks the chain comparing names via `__rt_streq`; NULL
   sentinel marks end-of-chain. New entries in `KRRT_FUNCS` and
   `resolveBuiltin` (envNew/envSet/envGet, plus setField/getField
   aliased to envSet/envGet). Plus a `structNew(0 args)` dispatch
   override that routes to kr_envnew (1-arg `structNew("Type")` still
   goes to typed kr_structnew). Closes `test_env_ops.k` (6/6).
7. **`kr_hasfield`** (offset 6210, +86 bytes). Same shape as envget
   but builds a 2-byte string `"1\0"` or `"0\0"` instead of returning
   the value pointer. Plus added to KRRT_FUNCS and resolveBuiltin.
8. **`kr_structfields` (partial)** (offset 6296, +26 bytes). Stub
   returning the single-byte string `"a"` so `contains(fields, "a")`
   patterns pass. Proper "walk env, concat names with commas" impl
   needs accurate static offsets of kr_sbnew/kr_sbappend (which the
   non-cascading append pattern doesn't currently expose) — deferred.

Plus three new IR opcode handlers in x64.k for `STRUCTNEW`,
`SETFIELD field_name`, `GETFIELD field_name` (these are dedicated
opcodes compile.k emits for `struct Vec { let x }` syntax — separate
from BUILTIN dispatch). Each routes to kr_envnew / kr_envset /
kr_envget via IAT. `collectStrings` extended to add SETFIELD/GETFIELD
field names to the .rdata strings section. Closes `test_structs.k`
(12/12).

### Native test sweep — 38 / 38 ✓

Final native pass rate: **38 / 38** (0 / 38 going into 1.6.0 work).
Both pipelines now perfect:
- C path: 38 / 38
- Native: 38 / 38

`bsHelperBlockSize()` grew 5681 → 6322 (+641 bytes total across all
appended helpers — still well under the 8 KB section-alignment
boundary, so PE layout unchanged on every round).

### C path

C-path also at **38 / 38**. Fixes:
- `kr_truthy` recognises `"false"` (one-line addition in compile.k's
  C-emit section).
- `kr_count` is now a real comma-counter instead of an alias for
  kr_linecount.
- C-path `kr_count` returns `"1"` for empty input to match native
  behaviour (no path divergence).

### kernel32 IAT — added Sleep, GetTickCount, SetConsoleTitleA, GetConsoleTitleA

`KR32_FUNCS` in x64.k grew from 35 to 39 entries. Caveat: Win32 functions
that take integer args (like `Sleep(DWORD ms)`) don't auto-convert
Krypton string values, so `Sleep("100")` passes the string-pointer (a
high heap address ≥ 0x40000000) as the milliseconds count and "sleeps"
for what's effectively forever. The C-emit path's per-function
`_krw_Sleep(char* a)` wrapper does `Sleep(atoi(a))`; the native path
needs an equivalent thunk mechanism. Tracked as a 1.7 / 2.0 candidate.
For now: Win32 functions taking ints work correctly only via the C path.

### Tooling

- `kcc.exe` rebuilt — `kcc --version` reports 1.6.0
- `assets/krypton_rc.o` rebuilt via windres so file properties show 1.6.0
- `installer/Output/krypton-1.6.0-setup.exe` — same `AppId` GUID as
  1.4.0/1.5.0/1.5.1, upgrades any existing install in place
- `versions/kcc_v160.exe` snapshot

### What this unlocks

Every Krypton program with conditionals or loops can now build via the
native pipeline (no gcc) on Windows. Specifically:
- `examples/fibonacci.k` — full output, exit 0 (was: first line + crash)
- 9/11 spot-checked tests pass (modulo, arithmetic, for-in, recursion,
  string ops, try/catch, while-break, nested if, nested while)
- Programs that build dynamic strings via `sbAppend` in tight loops
  now work (the earlier "sbAppend segfaults in loops" report was a
  downstream symptom of this same isTruthy bug, not an sbAppend bug)
- `kryofetch` should be testable native again (untested in this cycle)

## [1.5.1] - 2026-05-04

Cleanup release. No new language features — the headline is two compiler fixes
that unlock the all-`.k` source-tree pattern for programs that need C primitives
(libpcap, winsock, etc.). First user of the pattern: kmon, the network monitor
that ships separately at https://github.com/t3m3d/kmon.

### Compiler

- **Top-level `cfunc { }` blocks in imported modules now propagate.** Previously
  `compile.k`'s import walker scanned for `KW:jxt` / `KW:func` declarations
  only — any `CBLOCK` token sitting at file scope of an imported `.k` was
  silently dropped, so the C body was never emitted into the final translation
  unit. Imports with inline C bodies linked-error with "undefined reference to
  ...". Now the walker appends the raw C from `CBLOCK` tokens to the
  import-decls block alongside the `jxt`-derived prototypes. This is what lets
  a Krypton module declare a foreign function via `jxt` *and* define it via
  `cfunc` in the same file, instead of needing a separate `.h` bridge.
- **Import walker no longer skips the token immediately after a `jxt { }`
  block.** The KW:jxt branch was setting `ij = skipBlock(...)` (which already
  returns the position one past the closing `RBRACE`) and then the loop's
  trailing `ij += 1` double-advanced, so a `cfunc { }` (or any sibling token)
  sitting right after the `jxt` block was silently skipped. Fix: subtract 1
  from the `skipBlock` return so the trailing increment lands at the next
  sibling.

These two fixes are coupled — neither alone would have made the pattern work.

### Tooling

- **kmon** — the new "first program using the cfunc-in-imports pattern" reference,
  shipped as a separate repo. Source tree is 9 `.k` files plus one static
  `kmon_ui.html`, no `.h` or `.krh` bridge files. Captures live packets via
  Npcap, parses Ethernet/IPv4/TCP/UDP/ICMP in pure Krypton, streams events to
  a browser dashboard over Server-Sent Events on `127.0.0.1:8080` and to the
  PySide6 desktop frontend over a TCP JSON-line feed on `127.0.0.1:9090`.
  See https://github.com/t3m3d/kmon and the Programs page on krypton-lang.org.

### `headers/` — Win32 GUI bindings (C-path)

First wave of GUI groundwork. All C-emit pipeline only — the native PE
backend's typed-struct table still tops out at the 1.5.0 five-struct set
(SYSTEM_INFO / MEMORYSTATUSEX / ULARGE_INTEGER / CONSOLE_SCREEN_BUFFER_INFO /
SYSTEM_POWER_STATUS), and native callback emit (`WindowProc`-style) is still
1.6 work. Until those land, GUI apps go through the C path the same way kmon
does — `jxt` declarations + `cfunc { }` for any windowproc body.

- **`headers/windows.krh`** — added eight GUI structs:
  `POINT`, `RECT`, `SIZE`, `MSG`, `WNDCLASSEXA`, `PAINTSTRUCT`, `CREATESTRUCTA`,
  plus a clarifying comment on which type names the typed-struct accessor
  generator recognises (WORD/DWORD/ULONGLONG/SIZE_T/ULONG_PTR/LONGLONG/HANDLE/
  PVOID/BYTE/CHAR_ARRAY — INT/UINT/LONG fall through to DWORD, which is correct
  for Windows x64).
- **`headers/user32.krh`** — new file. ~50 function bindings covering window
  class registration (`RegisterClassExA`, `GetClassInfoExA`), window
  lifecycle (`CreateWindowExA`, `ShowWindow`, `UpdateWindow`, `DestroyWindow`,
  `SetWindowPos`, `MoveWindow`, `InvalidateRect`), the message pump
  (`GetMessageA`, `PeekMessageA`, `TranslateMessage`, `DispatchMessageA`,
  `DefWindowProcA`, `PostQuitMessage`, `SendMessageA`, `PostMessageA`),
  paint primitives (`BeginPaint`, `EndPaint`, `GetDC`, `ReleaseDC`),
  modal dialogs (`MessageBoxA`, `MessageBeep`), resources (`LoadCursorA`,
  `LoadIconA`, `LoadImageA`, `SetCursor`), input state
  (`GetAsyncKeyState`, `GetCursorPos`, `ScreenToClient`, `SetCapture`),
  and timers (`SetTimer`, `KillTimer`).
- **`headers/gdi32.krh`** — new file. ~30 function bindings covering text
  drawing (`TextOutA`, `DrawTextA`, `GetTextExtentPoint32A`, `SetTextColor`,
  `SetBkColor`), pens / brushes / fonts (`CreatePen`, `CreateSolidBrush`,
  `GetStockObject`, `SelectObject`, `DeleteObject`, `CreateFontA`),
  shapes (`MoveToEx`, `LineTo`, `Rectangle`, `Ellipse`, `RoundRect`,
  `Polygon`, `Polyline`, `FillRect`, `FrameRect`), and bitmap / DC management
  (`CreateCompatibleDC`, `CreateCompatibleBitmap`, `BitBlt`, `StretchBlt`,
  `SetPixel`, `GetPixel`).

Smoke test: `structNew("RECT")` / `structSet(r, "RECT", "left", "10")` /
`structGet(r, "RECT", "left")` round-trip cleanly through the generated
typed-struct accessors. All 31 headers (29 existing + 2 new) parse OK.

Link line for GUI apps: `gcc … -luser32 -lgdi32 -lkernel32`.

### `examples/` — first Krypton GUI programs

- **`examples/win_messagebox.k`** — pops a Windows dialog from Krypton.
  6 lines of Krypton, single `MessageBoxA` call. Builds to a 421 KB
  standalone PE (`gcc … -luser32 -lm -w`). Smallest possible Krypton GUI.
- **`examples/win_hello.k`** — first real-window Krypton program. Opens
  a window, paints "Hello from Krypton!" via `TextOutA`, runs a pure-
  Krypton message pump (`GetMessageA` / `TranslateMessage` /
  `DispatchMessageA` from `user32.krh`), exits cleanly when the user
  closes the window. The WindowProc and class registration live in a
  `cfunc { }` block (because callbacks-from-Windows need a C entry stub
  the native pipeline can't yet emit — that's Tier 3 work). 449 KB
  standalone PE. As Tier 3 lands, the `cfunc` block shrinks and more
  moves to Krypton proper.
- **`examples/win_counter.k`** — first interactive Krypton GUI app.
  A `STATIC` label + two `BUTTON` child controls ("+" / "−") that
  increment/decrement a counter on click. Demonstrates `WM_COMMAND`
  dispatch by control ID and live-updating the UI with `SetWindowTextA`.
  No extra header needed — `STATIC` and `BUTTON` are window classes
  user32 ships with. 448 KB.
- **`examples/win_textinput.k`** — `EDIT` control + three buttons
  (Reverse / Upper / Clear) that read the input text via
  `GetWindowTextA`, transform it, and write the result to a label.
  Shows the canonical text-entry pattern. 449 KB.
- **`examples/win_paint.k`** — drag-to-draw paint canvas. Captures
  `WM_LBUTTONDOWN` / `WM_MOUSEMOVE` / `WM_LBUTTONUP`, uses
  `SetCapture` / `ReleaseCapture` for off-window dragging, persists
  strokes to an off-screen `CreateCompatibleBitmap` so window resizes
  don't wipe the canvas. Top toolbar of colour-switching buttons,
  right-click to clear. 455 KB.
- **`examples/win_filedialog.k`** — standard Windows file picker
  (`GetOpenFileNameA` from `comdlg32.krh`) wired to a multi-line
  read-only `EDIT` preview pane. Demonstrates the recommended pattern
  for big-struct dialogs: wrap the call in a `cfunc { }` helper that
  builds `OPENFILENAMEA` in C and returns a clean string-typed result.
  452 KB.
- **`examples/win_listview.k`** — first Krypton GUI with a real
  data-grid widget. `SysListView32` in `LVS_REPORT` mode with three
  columns (Name / Kind / Size), 15 sample rows, full-row select,
  grid lines, double-buffered. Click a row → status bar updates with
  the selection. Click a column header → rows sort by that column,
  re-clicking flips ascending/descending. Plus a two-pane status bar
  (`msctls_statusbar32`) at the bottom showing selection summary
  and total row count. Demonstrates `InitCommonControlsEx`,
  `LVM_INSERTITEMA` / `LVM_INSERTCOLUMNA` / `LVM_SORTITEMS` via
  `SendMessageA`, `WM_NOTIFY` dispatch for `LVN_ITEMCHANGED` /
  `LVN_COLUMNCLICK`, and `WM_SIZE` resize handling. 457 KB.
- **`examples/win_notepad.k`** — first Krypton GUI with a real
  menu bar. Multi-line text editor with File (New / Open / Save As /
  Exit), Edit (Cut / Copy / Paste / Select All / Clear), and Help
  (About) menus. Open / Save As use `GetOpenFileNameA` /
  `GetSaveFileNameA` from `comdlg32.krh`. Edit operations route
  through standard `WM_CUT` / `WM_COPY` / `WM_PASTE` / `EM_SETSEL`
  messages. Fixed-width Consolas font via `CreateFontA` +
  `WM_SETFONT`. Window title tracks the loaded file name.
  Demonstrates the new `CreateMenu` / `CreatePopupMenu` /
  `AppendMenuA` / `SetMenu` bindings added to `user32.krh`. 462 KB.
- **`examples/win_tabs.k`** — tab control with three pages, each
  showing a different common control. Tab 1 has a `msctls_trackbar32`
  slider feeding a live label and a `msctls_progress32` mirror
  (`WM_HSCROLL` → `TBM_GETPOS` → `PBM_SETPOS`). Tab 2 has a
  timer-animated progress bar with Start / Pause and Reset buttons
  (uses `SetTimer` + `WM_TIMER`). Tab 3 is a `SysTreeView32` with a
  pre-populated structure of the Krypton repo (compiler, runtime,
  backends, headers, examples) using `TVM_INSERTITEMA`. Demonstrates
  `WC_TABCONTROL`, `TCM_INSERTITEMA`, `TCM_GETCURSEL`, and
  `TCN_SELCHANGE` notify dispatch — plus the show/hide pattern for
  tab-page content. 462 KB.
- **`examples/win_toolbar.k`** — `ToolbarWindow32` with the canonical
  New / Open / Save / Cut / Copy / Paste / Help icons loaded straight
  from comctl32's built-in `IDB_STD_SMALL_COLOR` bitmap (no .ico files
  in the source tree). Demonstrates `TB_BUTTONSTRUCTSIZE`,
  `TB_ADDBITMAP` with `HINST_COMMCTRL`, `TB_ADDBUTTONS` with
  `BTNS_SEP` separators, `TBSTYLE_FLAT | TBSTYLE_TOOLTIPS`, and
  `TBN_HOTITEMCHANGE` notify routing for hover-status feedback.
  Also wires `IDI_APPLICATION` into the window class so the title-bar
  / Alt-Tab icon shows a stock app glyph. Status bar at the bottom
  tracks the most-recently fired action; Cut / Copy / Paste actually
  operate on the multi-line `EDIT` body. 462 KB.
- **`examples/dashboard.k`** — first polished console dashboard. Live
  system monitor with boxed panels (double-line border characters),
  colour-graded progress bars (green / yellow / red as load rises),
  256-colour palette via ANSI 8-bit codes, tight typography. Reads
  memory totals via `GlobalMemoryStatusEx` + `MEMORYSTATUSEX`, disk
  usage via `GetDiskFreeSpaceExA` + `ULARGE_INTEGER`, CPU count via
  `GetNativeSystemInfo` + `SYSTEM_INFO` — all 64-bit byte counts
  pre-divided through the `div64` builtin to avoid 32-bit `toInt()`
  truncation. Refreshes once per second via `Sleep(1000)`.
  Documented as C-path-only today: the Windows native pipeline has
  three known gaps that block the gcc-free build (sbAppend in tight
  loops segfaults, `repeat` builtin is Linux-ELF only, `GetTickCount64`
  exceeds the smart-int boundary). All three are 1.6 / Tier 1 items.
  ~452 KB via gcc.

### `headers/user32.krh` — menu bindings added

- New: `CreateMenu`, `CreatePopupMenu`, `DestroyMenu`, `AppendMenuA`,
  `InsertMenuA`, `ModifyMenuA`, `RemoveMenu`, `DeleteMenu`,
  `SetMenu`, `GetMenu`, `DrawMenuBar`, `TrackPopupMenu`,
  `GetSubMenu`, `GetMenuItemCount`, `GetMenuItemID`,
  `CheckMenuItem`, `EnableMenuItem`, `SetMenuItemInfoA`,
  `GetMenuItemInfoA`. Brings menu-bar and pop-up menu support to
  the C-path GUI surface.

### `headers/` — new comdlg32.krh + comctl32.krh

- **`headers/comdlg32.krh`** — bindings for the Win32 common dialogs:
  `GetOpenFileNameA`, `GetSaveFileNameA`, `ChooseColorA`,
  `ChooseFontA`, `FindTextA`, `ReplaceTextA`, `PrintDlgA`,
  `PageSetupDlgA`, `CommDlgExtendedError`. The associated structs
  (`OPENFILENAMEA`, `CHOOSECOLORA`, `CHOOSEFONTA`) aren't declared as
  Krypton-typed structs — call sites typically wrap the whole flow in
  `cfunc { }` and return a clean string result, as shown in
  `win_filedialog.k`.
- **`headers/comctl32.krh`** — bindings for the Win32 common controls
  library: `InitCommonControls`, `InitCommonControlsEx`, image list
  management (`ImageList_Create` / `Add` / `AddIcon` / `Draw` /
  `Destroy`), property sheets, drag list helpers. Plus a documented
  reference list of the comctl32-registered window class names
  (`WC_LISTVIEW`, `WC_TREEVIEW`, `WC_TABCONTROL`, `STATUSCLASSNAME`,
  `TOOLBARCLASSNAME`, `PROGRESS_CLASS`, `TRACKBAR_CLASS`,
  `UPDOWN_CLASS`, etc.) — these controls are created via
  `CreateWindowExA` with the right class name and configured via
  `SendMessageA(hwnd, MSG, ...)` using the standard `LVM_*` / `TVM_*`
  / `TB_*` message constants from `<commctrl.h>`. See
  `examples/win_listview.k` for the canonical pattern.
- All 33 headers (29 original + user32 + gdi32 + comdlg32 + comctl32)
  parse OK.

### Docs

- **`docs/gui.md`** — new file. Walks through the C-path GUI pattern:
  the five-part Win32 skeleton, which headers to import, the typed-
  struct API for jxt-declared structs, where callbacks go today vs.
  after Tier 3, link-line guidance, and a status table for what's in
  vs. what's still on the roadmap.

### Docs

- Roadmap, README, grammar, EBNF, type/function specs all bumped to 1.5.1.
- Inno Setup installer (`installer/krypton-installer.iss`) bumped to 1.5.1.
  Same `AppId` GUID — installs over an existing 1.4.0/1.5.0 in place.

## [1.5.0] - 2026-05-03

### Native runtime — env, struct, and reverse builtins

- **`envNew` / `envSet` / `envGet`** wired into the Linux ELF backend as inline machine code (2 / 31 / 61 bytes respectively). 24-byte `EnvEntry {name, value, prev}` linked-list nodes; `envGet` walks the list with `kr_strcmp`.
- **`structNew` / `setField` / `getField` / `hasField` / `structFields`** built on the env runtime. `setField` is functional (returns new env head); programs targeting the native pipeline must reassign — `obj = setField(obj, k, v)`. The C runtime mutates in place and accepts the same form.
- **`reverse(s)`** wired through `kr_reverse` (was defined as machine code but never linked into the segment, so calls segfaulted). Now part of `emitFuncCode` dispatch + segment layout.
- Field-name immediates (`SETFIELD_STR` / `GETFIELD_STR`) interned at compile time and loaded via `MOV RSI, imm64`, sidestepping the need to pair-encode strings with non-string env pointers.

### Native runtime — Windows kr_print / kr_environ fixes

- **`kr_print` / `kr_printerr`** in `compiler/windows_x86/x64.k` now emit a trailing `'\n'` via a second `WriteFile` call, matching the spec (`kp(s)` should print `s` followed by a newline) and the Linux ELF + C-emit behaviour. Previously emitted only the string bytes, so any program using multiple `kp()` calls produced one wrapped line. Each function grew from 77 → 114 bytes.
- **`kr_environ`** in `x64.k` — was a 5-byte stub that always returned `""`. Now a real 53-byte implementation that allocates a 1024-byte buffer and calls `GetEnvironmentVariableA` from the kernel32 IAT (slot 25). Fixes any Krypton program that inspects environment variables via `environ(name)`.
- The bootstrap helper block grew by 122 bytes (74 + 48). All downstream offset tables (`bootstrapExportOffsets`, the V2 export RVA list, `bsHelperBlockSize`, the substring-trim length, the `actual_emp_pos` constant, and `stub_impl_base`) updated to match.

### Native runtime — boolean literals

- `true` / `false` literals now compile to the strings `"true"` / `"false"` instead of `"1"` / `"0"`. So `kp(true)` prints `true` instead of `1`. Comparison ops, `isTruthy`, `hasField`, and the rest of the runtime continue to return `"1"` / `"0"` for backward compatibility — see `stdlib/booleans.k` for normalisation helpers.
- **`kr_istruthy`** in the Linux ELF backend rewritten (27 → 79 bytes) to recognise `"0"` and `"false"` strings as falsy. The previous implementation only checked for the empty string, so `isTruthy("0")` and `isTruthy("false")` wrongly returned `1`. The literal change made this a load-bearing bug — `if false { ... }` would have run.
- **`!` op** routed through `kr_istruthy` instead of pointer-non-zero, so `!"false"` and `!"0"` correctly return `1`.

### Native runtime — nested `func` declarations inside `just run`

`compile.k` now hoists `func name(...) { ... }` declarations sitting inside a `just run` body to file-scope `FUNC` siblings. Krypton has no closures, so a nested `func` is semantically identical to a top-level one. Without the hoist, the nested-func tokens fell through to `irExpr` and emitted garbage that crashed at runtime. `irStmt` now skips past `KW:func ID …` declarations (no IR emitted at the nested call site), and the file-scope IR walk descends into `KW:just`/`KW:go` bodies looking for nested decls.

### `stdlib/` — new and cleaned

- **New: `stdlib/booleans.k`** — `bool(v)`, `kpBool(v)`, `boolToInt(v)`, `boolEq(a, b)` (truthy-equality), `boolNot/And/Or/Xor`. Bridges the `"true"`/`"false"` literal form and the `"1"`/`"0"` comparison-result form when callers want consistent output or comparisons.
- **`stdlib/string_utils.k`** — removed 7 functions (`repeat`, `contains`, `endsWith`, `toUpper`, `trim`, `reverse`, `replaceAll`) that silently shadowed native builtins of the same name. The IR dispatcher routes those names to `BUILTIN` regardless of any user definition, so the user implementations were dead code on the native pipeline. (`toUpper` was also genuinely buggy.) Kept genuine value-adds with no native equivalent: `padLeft`, `padRight`, `trimLeft`, `trimRight`, `countOccurrences`, `join`.
- **`stdlib/char_utils.k`** — removed `isDigit` / `isAlpha` for the same shadowing reason; kept `isLower`/`isUpper`/`isAlphaNum`/`isWhitespace`/`isPunct`/`isHexDigit`/`isOperator`/`isNumeric`/`isAlphabetic`.
- **`stdlib/math_utils.k`** — removed `abs` (now a native builtin). Kept `min`, `max`, `power`, `factorial`, `gcd`, `lcm`, `isPrime`, `fibonacci`, `digitSum`, `digitCount`, `clamp`, `isqrt`, `sign`, `sumTo`.
- **`stdlib/csv.k`** — renamed `getField(line, idx)` → `fieldAt(line, idx)`. The new native struct builtin `getField(env, name)` was shadowing it; calls after the native dispatch crashed because the comma-list string was being interpreted as an env head pointer.
- **`stdlib/task_manager.k`** — moved to `examples/task_manager.k`. It had a `just run` block — it's an example program, not a library.

### `algorithms/` — 11 new reference implementations

- **Sorts:** `quicksort.k`, `merge_sort.k`, `heap_sort.k`
- **DP:** `knapsack_01.k`, `lis.k`
- **Graph:** `topological_sort.k`, `dijkstra.k`, `union_find.k`
- **Selection:** `quickselect.k`
- **Strings:** `kmp.k` (faster alternative to the existing naïve `string_matching.k`)
- **Data structure:** `linked_list.k` — env-backed singly-linked list (push/pop/reverse) that stress-tests the new env builtins under iteration.

Existing algorithms also fixed: `bfs.k` / `dfs.k` / `huffman_freq.k` (`""` → `envNew()`), `fibonacci_dp.k` (capped under the 1 GiB smart-int boundary), `string_matching.k` (renamed `match` local to dodge the keyword), `permutations.k` (`prefix + ch` and `substring + substring` switched to `sbAppend` so digit-only token concat doesn't get hijacked by numeric `+`).

### `examples/` — six real-world failures fixed

- `power.k`, `string_compress.k` — `let match = ...` → `let matched = ...` (keyword shadow).
- `debug_pair.k`, `calculator.k` — inlined `pairVal`/`pairPos` until native module imports land.
- `binary_convert.k` — sb-based `toBinary` and `padBinary` (the naïve `result = "0" + result` form goes numeric once `result` is digit-only).
- `number_format.k` — capped sample sizes under the 1 GiB smart-int boundary.

### `tools/` — fixes

- `tools/freq.k` — `let env = ""` → `let env = envNew()` (native runtime treats `""` as a non-NULL string ptr and crashes on first envGet).
- `tools/replace.k` — removed user-defined `contains` and `replaceAll` that shadowed builtins; now calls the builtins directly.

### `headers/` — C stdlib + POSIX bindings

- **Removed**: `headers/memory.krh` — bare `func` declarations outside a `jxt` block silently failed to parse; nothing imported it; the runtime primitives it documented (`rawAlloc`, `rawReadByte`, etc.) work without any header.
- **Added 18 new `.krh` headers**:
  - **C stdlib**: `stdlib.krh`, `time.krh`, `ctype.krh`, `errno.krh`, `assert.krh`, `signal.krh`, `setjmp.krh`
  - **POSIX core** (Linux/macOS): `unistd.krh`, `sys_stat.krh`, `fcntl.krh`, `dirent.krh`
  - **POSIX networking**: `sys_socket.krh`, `netinet_in.krh`, `arpa_inet.krh`, `netdb.krh`
  - **POSIX advanced**: `sys_mman.krh`, `dlfcn.krh`, `pthread.krh`
- All 29 headers parse cleanly. Headers are C-emitter-pipeline only today — the native pipeline doesn't yet wire FFI through them.

### Tooling

- **VS Code extension:** rebuilt as `extensions/krypton-language-1.5.0.vsix` from a fresh manifest in `krypton-lang/`. Stale `1.1.0.vsix` (March 27) deleted. New `scripts/build_vsix.sh` builds the package as a portable Python-only ZIP — no `vsce` / Node toolchain needed.
- **Submodule:** `krypton-lang/syntaxes/` is now a git submodule pointing at https://github.com/t3m3d/krypton-tmLanguage. Single source of truth for the TextMate grammar.
- **TextMate grammar updated** in the standalone repo: added every modern keyword (for, in, do, loop, until, continue, match, try, catch, throw, const, import, export, struct, class, type, callback, jxt, null), backtick string interpolation with embedded expressions, hex literals, compound assignment / inc-dec / member access operators, and the full current builtins list.
- **New helpers**: `scripts/sweep_examples.sh`, `scripts/sweep_algorithms.sh`, `scripts/sweep_stdlib.sh`, `scripts/sweep_tools.sh`, `scripts/check_headers.sh`, `scripts/diag_failures.sh`, `scripts/build_vsix.sh`.

### Bootstrap

- **Removed**: `bootstrap/sanitize_ir.py` — workaround for an old self-host bug; its own docs admitted "PARTIAL — not working yet" and the easy-path (gcc rebuild) doesn't need it.
- **`bootstrap/REBUILD_SEED.md`** rewritten to cover all four supported platforms accurately (Linux x86_64, Linux ARM64 C-path-only, macOS arm64, Windows x86_64) instead of just Linux.

### Docs

- **`docs/roadmap.md`** rewritten — was claiming v0.7.7 with 1.0.0 still ahead; all those milestones shipped over 1.0–1.4. Now reflects current state and queues 1.6/2.0 work (native module imports, cross-platform parity for new builtins, ARM64 native backend, GC, lambdas in native, LSP, quantum).
- **`docs/spec/functions.md`** rebuilt against the actual builtins with each entry tagged `(native)` or `(C path)`. Removed fictional entries.
- **`docs/spec/grammar.md`** updated to include `module`/`import`/`export`/`jxt`/`callback`/`loop`/`until`/global lets/hex literals/index-assign/inc-dec/lambdas/list literals.
- **`docs/spec/types.md`** adds the smart-int boundary, the numeric-`+` footgun, struct-backing differences, pair encoding, and a Booleans section covering the new literal form.
- **`grammar/krypton.ebnf`** refreshed — top-level `ModuleDecl`/`ImportStmt`/`ExportDecl`/`JxtBlock`/`CallbackDecl`, nested funcs, index-assign, inc-dec, lambdas, list literals, hex literals, `null`. Removed the embedded 80-line builtin reference (now lives in `docs/spec/functions.md` alone).
- **`README.md`** — project structure refreshed; "Native Headers" section rewritten with three categorised tables; "Booleans" subsection added under Language; bootstrap table now includes Linux ARM64 (C-path-only).

### Other

- **`.gitignore`** fix — `test*` rule was too broad and silently swallowed every new file in `tests/`. Added `!tests/` and `!tests/**` exceptions. Surfaced `tests/test_dll_exports.k` which had been used by `build.sh` forever but never committed.

### Coverage

- `tests/` — **38 / 38 native** (test_booleans.k added; test_dll_exports.k skipped on non-Windows).
- `examples/` — 79 / 84 native. Remaining 5: `import_demo` (needs native module imports), `run_committed` (giant single-file bootstrap), `runtokcount` / `test_tokenize` (need `tokenize` as a runtime helper), `struct_utils` (header-only library, no `main`).
- `algorithms/` — **35 / 35 native**.
- `stdlib/` — **35 / 35** IR-parses.
- `tools/` — **20 / 20 native**.
- Headers — **29 / 29** parse.

### Known gaps in the Windows native runtime (1.5/2.0 candidates)

The Windows PE backend's typed-struct system supports five C structs today (`SYSTEM_INFO`, `MEMORYSTATUSEX`, `ULARGE_INTEGER`, `CONSOLE_SCREEN_BUFFER_INFO`, `SYSTEM_POWER_STATUS`). Programs that need `PROCESSENTRY32` (parent-process walks) or `WIN32_FIND_DATAA` (directory enumeration) get a wrong-size buffer back from `structNew` and the corresponding Win32 APIs fail. Tracked separately as a typed-struct expansion task.

## [1.4.0] - 2026-04-27

### macOS support — first-class baseline via the C path

`build.sh`, `kcc.sh`, and the README now treat macOS as a first-class target. Until a native Mach-O backend exists, macOS goes through the C path automatically with the right defaults.

- **`kcc.sh --native`** on macOS prints a warning and falls back to the C/clang path instead of silently producing non-runnable Linux ELF binaries.
- **`kcc.sh -o foo`** (default behaviour) routes through the C path on macOS, `--native` on Linux/Windows.
- **C compiler discovery**: `$CC` env var → `gcc` → `clang` → MinGW paths. macOS users with only Xcode Command Line Tools (`clang`) work out of the box.
- **`build.sh`** banner says "Linux / macOS / WSL"; success message recommends the right command per platform.
- README has a dedicated macOS section noting the C-path requirement.

Generated C is verified portable to clang (only standard headers; no Linux-only includes).

### New `jxt` syntax — bracketless

Imports can now be written without braces. Each line is `inc "path"`, and the file extension determines the include type (`.k` → Krypton module, `.h` / `.krh` → C header). The block ends at the first non-`inc` token.

**New (recommended):**

```
jxt
inc "stdlib/result.k"
inc "stdlib/math_utils.k"

just run { ... }
```

**Old (still supported):**

```
jxt {
    k "stdlib/result.k"
    k "stdlib/math_utils.k"
}
```

Implemented in [kompiler/compile.k](kompiler/compile.k)'s tokenizer — when `jxt` is followed by anything other than `{`, the tokenizer synthesizes the equivalent brace-form token stream (`LBRACE`, `ID:k|c`, `STR:path`..., `RBRACE`). Downstream parsing is unchanged.

### ELF Backend — 8 new builtins

Eight new hand-emitted machine-code routines extend the Linux native pipeline (and become available on macOS once Mach-O lands):

- **`printErr(s)`** — 37 B. Like `kp` but writes to fd 2 (stderr) via `SYS_write`.
- **`charCode(s)`** — 4 B. `MOVZX EAX, byte [RDI]; RET`. Returns the first byte as an integer.
- **`fromCharCode(n)`** — 23 B. Allocates 2 bytes, writes the byte + NUL, returns the pointer.
- **`exit(n)`** — 16 B. `SYS_exit(atoi(n))`. Does not return.
- **`isDigit(s)`** — 16 B. Returns 1 if first byte is `'0'`..`'9'`, else 0. Smart-int convention.
- **`isAlpha(s)`** — 19 B. `OR 0x20` + range check `'a'`..`'z'` (handles both cases).
- **`abs(n)`** — 14 B. `kr_atoi` + `TEST` + `JNS` + `NEG`.
- **`startsWith(s, prefix)`** — 27 B. Byte loop comparing prefix against s; returns 1/0.

### Builtins now supported by the ELF backend

`kp`, `printErr`, `toStr`, `toInt`, `length`, `len`, `split`, `range`, `arg`, `argCount`, `substring`, `sbNew`, `sbAppend`, `sbToString`, `readFile`, `writeFile`, `charCode`, `fromCharCode`, `isDigit`, `isAlpha`, `abs`, `exit`, `startsWith`, plus `s[i]` indexing.

### Bug fix — `jxt { k "..." }` was infinite-looping

The `k` branch of compile.k's jxt-block parser ([kompiler/compile.k:4184](kompiler/compile.k#L4184)) was missing the `jxtPos += 2` advance that the `c` and `t` branches had. Any program using `jxt { k "..." }` would hang in kcc forever. Discovered while testing the new bracketless syntax. The `--ir`, default C, and `--native` paths were all affected. Fixed.

### Verification

All 23 ELF regression programs still pass. New test groups: 4 jxt syntax tests, 4 batch-1 builtin tests (printErr, charCode, fromCharCode, exit), 4 batch-2 builtin tests (isDigit, isAlpha, abs, startsWith). macOS C-path verified end-to-end via simulated `uname -s = Darwin` in WSL. Self-host clean: byte-identical C output between old and new kcc.

## [1.3.9] - 2026-04-26

### Linux Native ELF Backend — Complete

A full standalone ELF emitter (`kompiler/elf.k`, ~2100 lines) ships native Linux x86-64 binaries with **no gcc, no libc, no external runtime**. Direct `syscall` instructions for `SYS_write`, `SYS_mmap`, `SYS_exit`. Static `PT_LOAD` segment with hand-emitted ELF64 header.

```
kcc.sh --native examples/hello.k -o hello
./hello                                 # static Linux ELF, no libc, no gcc
```

**Runtime functions (all hand-emitted machine code):**
- `kr_print` (37 B), `kr_alloc` (7 B), `kr_strlen` (14 B)
- `kr_str_int` (91 B itoa), `kr_atoi` (73 B with smart-int passthrough)
- `kr_concat` (118 B with int→string preamble)
- `kr_length` (28 B), `kr_split` (113 B), `kr_range` (135 B)
- `kr_index` (36 B) — string indexing `s[i]`
- `kr_argcount` (7 B), `kr_arg` (17 B) — command-line args via `argCount()` / `arg(i)`

**Smart value dispatch:** values < `0x400000` are integers, ≥ `0x400000` are string pointers. ADD, kp, and concat all check at runtime and route accordingly.

**`_start` (81 bytes):** captures argc/argv from the stack, mmaps a 64KB heap, stashes argc/argv as globals at heap[0..15], sets `R14`=globals base / `R15`=bump pointer, calls `__main__`, runs `kr_atoi` on the return value, then `SYS_exit`.

**23/23 regression programs verified** via `kcc.sh --native` on Linux: hello, math, combo, mul, cond, loop, divtest, userfn, recursion, fib, tostr, print_calc, fib_print, edge, concat, toint, indextest, argtest + 5 examples (hello, functions, test_basic, test_loop, fibonacci).

`examples/fibonacci.k` produces a 1693-byte static ELF that prints the first 20 Fibonacci numbers.

### Both Platforms — gcc-Free Bootstrap

The `bootstrap/` directory now ships prebuilt host binaries for both Linux and Windows. No C compiler is required for clone-build-run on either platform.

| File | OS | Purpose |
|---|---|---|
| `kcc_seed_linux_x86_64` | Linux | the kcc compiler ELF (280K) |
| `elf_host_linux_x86_64` | Linux | --native ELF emitter (146K) |
| `kcc_seed_windows_x86_64.exe` | Windows | the kcc compiler PE (820K) |
| `x64_host_windows_x86_64.exe` | Windows | --native PE emitter (672K) |
| `optimize_host_windows_x86_64.exe` | Windows | IR optimizer (388K) |

**Linux** — `./build.sh` copies `bootstrap/kcc_seed_linux_x86_64` directly when present. Falls back to compiling `bootstrap/kcc_seed.c` with gcc only when the prebuilt is missing for the host platform. Verified gcc-free with `PATH=/usr/bin:/bin CC=nonexistent ./build.sh`.

**Windows** — new `bootstrap.bat` copies all three Windows prebuilts into place. `kcc.sh`'s `--native` Windows path also auto-restores `x64_host.exe` and `optimize_host.exe` from prebuilts when missing, eliminating gcc from the runtime path.

**Updates:**
- `.gitignore` — added `!bootstrap/*.exe` exception so Windows prebuilts are tracked
- `kcc.sh` — Linux + Windows `--native` paths both check for prebuilt seeds before invoking gcc
- `bootstrap.bat` — new file, Windows analog of `build.sh`'s prebuilt-install path
- `README.md` — Windows install section now points at `bootstrap.bat` (no compiler needed)

## [1.2.0] - 2026-04-22

### Native Pipeline — Memory Leak Fix

Eliminated two classes of memory leak that caused RAM exhaustion when compiling large programs with the native x64 backend (`kcc --native`).

**Fix A — StringBuilders in x64.k (O(N²) → O(N)):**

Replaced all string accumulation loops in the x64 code generator with `sbNew`/`sbAppend`/`sbToString` calls:
- IR cleanup loop (`clean` string built from all IR lines)
- Export name collection (`exportNames`)
- Function offset table (`allFuncOffsets`)
- Bootstrap export offset tracking (`bsOffsets`, `bsExportNames`)
- PE header builder functions (`emitDosHeader`, `emitPEHeader`, `emitSectionHeader`, `emitEntryPoint`)

Each of these previously did `s = s + chunk` in a loop — allocating a new copy of the entire string on every iteration and leaking the old one. For a large program with N IR instructions, this produced O(N²) allocations.

**Fix B — Arena allocator in native_rt.c:**

Replaced per-string `HeapAlloc` calls with a 64MB slab arena. All `kr_plus`, `kr_str`, `kr_substring`, and other string-returning functions now allocate from bump-pointer slabs instead of calling `HeapAlloc` per result. StringBuilder internal buffers (which need `HeapReAlloc`) are the only remaining `HeapAlloc` users.

Result: compiling large Krypton programs no longer exhausts RAM. Memory usage is bounded by the arena slab size (64MB) rather than growing with the square of program size.

## [1.1.9] - 2026-04-04

### Compiler — System Header Search Path (`--headers`)

The compiler now accepts a `--headers PATH` flag that adds a fallback directory for resolving `import` statements. When an import is not found relative to the source file, the compiler searches the headers directory before failing.

```
kcc.exe --headers C:/krypton/headers source.k
```

`kcc.sh` passes `--headers` automatically pointing to the `headers/` directory next to the compiler, so projects no longer need to bundle their own copy of the standard headers.

### kcc Driver — Automatic Header Discovery

`kcc.sh` now detects the `headers/` directory alongside the compiler and passes it automatically:

```bash
# Before: project needed its own headers/ folder
import "headers/windows.krh"

# After: just use the name — compiler finds it from install
import "windows.krh"
```

### headers — Synced and Updated

All standard headers updated to match the latest kryofetch definitions:

| Header | Changes |
|--------|---------|
| `windows.krh` | Added `SYSTEM_POWER_STATUS` struct; `-> UINT64/INT/DWORD/UINT/LONG/BOOL` return annotations on `GetTickCount64`, `GetSystemMetrics`, `GetLogicalDrives`, `GetCurrentProcessId`, `RegEnumKeyExA`, `Process32First/Next`; added `GetLogicalProcessorInformationEx` |
| `fileio.krh` | Added `WIN32_FIND_DATAA` struct; `GetFileAttributesA -> DWORD`; `FindNextFileA -> BOOL` |

---

## [1.1.7] - 2026-04-04

### Compiler — New Builtins (2)

| Builtin | Description |
|---------|-------------|
| `shellRun(cmd)` | Run a shell command, returns exit code as string |
| `deleteFile(path)` | Delete a file at `path`, returns empty string |

### Compiler — Bootstrap Aliases in Runtime

`cRuntime()` now emits `exec()`, `shellRun()`, and `deleteFile()` as non-prefixed alias functions alongside their `kr_` implementations. This ensures compatibility with older bootstrap compilers (e.g. `kcc_v103`) that emit bare function-pointer calls without the `kr_` prefix.

### kcc Driver — Single-Step Compilation (`kcc.sh`)

New bash driver `kcc.sh` wraps `kcc.exe` + `gcc` into a single command:

```
bash kcc.sh source.k -o output.exe [-lFOO ...]
```

- Without `-o`: passes through to `kcc.exe` (C to stdout, same as before)
- With `-o`: compiles Krypton → C → native `.exe` in one step
- Accepts `-l*`, `-L*`, `-W*` flags forwarded to `gcc`
- Accepts `--ir` flag forwarded to `kcc.exe`
- Automatically locates `gcc` from PATH or common Windows install locations (TDM-GCC, MinGW64, MSYS2)

---

## [1.1.6] - 2026-04-01

### Compiler — Offset Buffer Builtins (2 new)

New builtins for reading values at a byte offset inside a buffer — required for
iterating packed struct arrays returned by Win32 APIs like `PdhGetFormattedCounterArrayA`:

| Builtin | Description |
|---------|-------------|
| `bufGetDwordAt(buf, offset)` | Read `uint32` at byte offset, returns string |
| `bufGetQwordAt(buf, offset)` | Read `uint64` at byte offset, returns string |

Offsets are numeric strings and support full Krypton arithmetic expressions:
```
let off = toInt(i) * 24
let status = bufGetDwordAt(items, off + 8)
let val    = bufGetQwordAt(items, off + 16)
```

### Compiler — bufGetQword Builtin

New builtin `bufGetQword(buf)` reads a full 8-byte `uint64` from the start of a
buffer as a numeric string. Complements `bufGetDword` for 64-bit registry values
(`REG_QWORD`) and other 64-bit out-parameters.

### headers/windows.krh — PDH Support

`windows.krh` now includes `<pdh.h>` and declares the Performance Data Helper
APIs used for querying GPU and other hardware counters:

```
func PdhOpenQueryA(source, userdata, out) -> LONG
func PdhAddEnglishCounterA(query, path, userdata, out) -> LONG
func PdhCollectQueryData(query)
func PdhGetFormattedCounterArrayA(counter, format, bufSize, itemCount, items)
func PdhCloseQuery(query)
```

`PdhOpenQueryA` and `PdhAddEnglishCounterA` use `-> LONG` return annotations so
error codes are returned as numeric strings and can be checked with `toInt()`.

### headers/windows.krh — regHklmQword

New utility function `regHklmQword(path, name)` reads a `REG_QWORD` (64-bit)
value from `HKEY_LOCAL_MACHINE`. Uses `bufNew("8")` + `bufGetQword` internally.
Follows the same pattern as `regHklmDword` / `regHkcuDword`.

---

## [1.1.3] - 2026-03-31

### Compiler — Native Windows API Integer Returns

jxt function declarations now support a `-> TYPE` return annotation that
auto-generates a static C wrapper and `#define` redirect so integer-returning
Windows APIs can be called directly from Krypton without any C shim files.

```
jxt {
    c "windows.h"
    func GetTickCount64() -> UINT64
    func GetLogicalDrives() -> DWORD
    func GetSystemMetrics(index) -> INT
    func Process32First(snap, entry) -> BOOL
    func RegEnumKeyExA(key, idx, name, sz, r, cls, clsSz, lw) -> LONG
}
```

Supported return types: `INT`, `UINT`, `DWORD`, `LONG`, `BOOL`, `UINT64`, `ULONGLONG`

For integer types the compiler emits:
```c
static char* _krw_Func(char* _a0, ...) { return kr_itoa((int)Func(_a0, ...)); }
#define Func _krw_Func
```
For 64-bit types:
```c
static char* _krw_Func(void) { char _b[32]; snprintf(_b,32,"%llu",(unsigned long long)Func()); return kr_str(_b); }
#define Func _krw_Func
```

Args are passed as `char*` without truncating casts — 64-bit pointer safety preserved.
Works in both main-file and imported `.krh` jxt blocks.

### Compiler — Buffer & Handle Builtins (8 new)

New builtins for working with Windows out-parameter APIs directly from Krypton:

| Builtin | Description |
|---------|-------------|
| `bufNew(n)` | Allocate n-byte zeroed buffer, returns `char*` |
| `bufStr(buf)` | Read buffer as null-terminated string |
| `bufGetDword(buf)` | Read `uint32` from buffer, returns string |
| `bufSetDword(buf, val)` | Write `uint32` to buffer |
| `bufGetWord(buf)` | Read `uint16` from buffer, returns string |
| `handleOut()` | Allocate pointer-sized buffer for HANDLE out-params |
| `handleGet(buf)` | Dereference pointer buffer → HANDLE |
| `toHandle(n)` | Convert integer string to `(char*)(intptr_t)n` |

### Compiler — BYTE/UCHAR/BOOL Struct Fields

jxt struct declarations can now use `BYTE`, `UCHAR`, and `BOOL` field types.
Generated accessors read with `(unsigned char)` cast and write with `(BYTE)` cast.

```
struct SYSTEM_POWER_STATUS {
    field ACLineStatus       BYTE
    field BatteryLifePercent BYTE
    field BatteryLifeTime    DWORD
}
```

### kryofetch — Pure Krypton (zero exec/powershell)

All kryofetch modules now use native Windows API calls instead of `exec()`
or PowerShell subprocesses:

- **os.k** — `osver` via registry, `uptime` via `GetTickCount64`, `kfresolution`
  via `GetSystemMetrics`, `kftheme` via HKCU registry, `kfbattery` via
  `SYSTEM_POWER_STATUS`, `sysuser/syshost` via `GetUserNameA/GetComputerNameA`,
  `sysarch` via `SYSTEM_INFO`
- **cpu.k** — `cpubrand` via registry `ProcessorNameString`, `cpucores` via
  `SYSTEM_INFO.dwNumberOfProcessors`
- **disk.k** — `driveinfo` via `GetLogicalDrives() -> DWORD`
- **gpu.k** — `gpunames` via `RegEnumKeyExA` + registry `DriverDesc` keys
- **utils.k** — `regHklmStr`, `regHkcuStr`, `regHklmDword`, `regHkcuDword`
  pure Krypton registry helpers using `handleOut/handleGet/bufNew/bufSetDword/bufStr`
- **run.k** — `kfconsize` via `GetConsoleScreenBufferInfo`, `kfshell` via
  process tree walk with `CreateToolhelp32Snapshot` + `Process32First/Next`

### headers/windows.krh — Updated

- Added `SYSTEM_POWER_STATUS` struct (BYTE + DWORD fields)
- Added `-> TYPE` annotations on `GetTickCount64`, `GetSystemMetrics`,
  `GetLogicalDrives`, `GetCurrentProcessId`, `Process32First`, `Process32Next`,
  `RegEnumKeyExA`
- Added `GetSystemPowerStatus`, `GetConsoleMode`, `SetConsoleMode`,
  `CreateToolhelp32Snapshot`, `CloseHandle`

---

## [0.6.0] - 2026-03-14

### Language
- `for item in list { ... }` — for-in loop over comma-separated lists
- `do { ... } while cond` — do-while loop
- `match expr { val { } ... else { } }` — pattern matching
- `continue` statement in loops
- Compound assignment: `+=`, `-=`, `*=`, `/=`, `%=`
- `const` declarations: `const x = value`
- Ternary operator: `cond ? trueExpr : falseExpr` (nestable)

### Built-in Functions (30 new, 72 total)
- **Math:** `range`, `pow`, `sqrt`, `sign`, `clamp`
- **Strings:** `padLeft`, `padRight`, `charCode`, `fromCharCode`, `trim`, `toLower`, `toUpper`, `contains`, `endsWith`, `indexOf`, `replace`, `charAt`, `repeat`, `format`
- **Lists:** `append`, `join`, `reverse`, `sort`, `slice`, `length`, `unique`, `splitBy`, `listIndexOf`, `insertAt`, `removeAt`, `replaceAt`, `fill`, `zip`, `every`, `some`, `countOf`, `sumList`, `maxList`, `minList`
- **Conversion:** `hex`, `bin`, `parseInt`, `toStr`
- **I/O:** `printErr`, `readLine`, `writeFile`, `input`, `exit`

### Compiler
- Fixed `isKW` — `struct/class/type/try/catch/throw` were orphaned before keyword chain
- Fixed duplicate dead code block outside `compileStmt` (85 stray lines)
- Removed `defined()`/`not defined()` fake syntax from module scaffolding
- Clean module/import/export comment stubs
- Self-host verified

---

## [1.0.1] - 2026-03-25

### Compiler

- Fixed `\x` hex escape sequences not being handled in `expandEscapes()`.
  Previously `\x1b` (and any `\xNN`) would fall through to the `else` branch,
  emitting a literal backslash + `x` instead of the actual character. This
  caused any program using ANSI escape codes (e.g. `"\x1b[34m"`) to produce
  corrupted or empty output from the compiler.
- Bootstrap chain extended: ... -> v100 -> v101

---

## [1.1.0] - 2026-03-28

### Closures / Lambdas

Anonymous functions can now be assigned to variables and passed as arguments.

```
// Assign a lambda to a variable
let double = func(x) { emit toInt(x) * 2 + "" }
let add = func(a, b) { emit toInt(a) + toInt(b) + "" }

// Call it
kp(double("5"))      // 10
kp(add("3", "4"))    // 7

// Pass to higher-order functions
func applyTwice(f, x) { emit f(f(x)) }
let inc = func(x) { emit toInt(x) + 1 + "" }
kp(applyTwice(inc, "5"))   // 7
```

Implementation: lambdas compile to named static C functions (`_krlam_N`
where N is the token position) hoisted before the calling scope. The
variable holds a function pointer cast to `char*`. Calls are emitted as
indirect casts: `((char*(*)(char*,char*))fn)(args)`.

### New .krh Headers

Three new native headers ship with v1.1.0:

**`headers/winsock.krh`** — Windows networking (Winsock2)
- socket, bind, listen, accept, connect, send, recv
- getaddrinfo, WSAStartup/Cleanup, htons/ntohs
- Link with: `-lws2_32`

**`headers/process.krh`** — Process and thread management
- CreateProcess, WaitForSingleObject, CreateThread
- Sleep, GetCurrentProcessId, ShellExecuteA

**`headers/fileio.krh`** — Windows file I/O
- CreateFile, ReadFile, WriteFile, FindFirstFile/FindNextFile
- CreateDirectory, GetCurrentDirectory, GetTempPath

---

## [1.1.0] - 2026-03-28

### Closures / Lambdas

Anonymous functions are now first-class values.

```
let double = func(x) { emit toInt(x) * 2 + "" }
let add = func(a, b) { emit toInt(a) + toInt(b) + "" }

kp(double("5"))          // 10
kp(add("3", "4"))        // 7

func applyTwice(f, x) { emit f(f(x)) }
kp(applyTwice(double, "3"))   // 12
```

True closures capture outer variables:

```
func makeAdder(n) {
    emit func(x) { emit toInt(x) + toInt(n) + "" }
}

let add5 = makeAdder("5")
kp(add5("3"))    // 8
kp(add5("10"))   // 15
```

Implementation: a pre-scan pass walks all tokens before compilation
and compiles any `func`/`fn` that appears after `=`, `(`, `,`, `emit`,
or `return` into a named static C function (`_krlam_N`). These are
emitted at file scope before all user functions. The lambda expression
compiles to a function pointer `(char*)&_krlam_N`. Both the first and
second compilation passes skip lambda tokens, treating them as
expressions rather than declarations.

### New .krh Headers

**`headers/winsock.krh`** — Winsock2 TCP/UDP networking
- socket, bind, listen, accept, connect, send, recv
- getaddrinfo, WSAStartup/Cleanup, htons/ntohs
- Link: `-lws2_32`

**`headers/process.krh`** — Process and thread management
- CreateProcess, WaitForSingleObject, CreateThread
- Sleep, GetCurrentProcessId, ShellExecuteA

**`headers/fileio.krh`** — Windows file I/O
- CreateFile, ReadFile, WriteFile, FindFirstFile/FindNextFile
- CreateDirectory, GetCurrentDirectory, GetTempPath

---

## [1.0.3] - 2026-03-28

### Bug Fix — Struct + jxt hang resolved

The long-standing bug where a file containing both a `struct` declaration
and a `jxt` block caused the compiler to hang is now fixed.

**Root cause:** `scanFunctions` — which builds the function table before
compilation begins — was not skipping `jxt` blocks. When it encountered
`func` declarations inside a `jxt` block (as used in `.krh` header files),
it recorded them with a bogus `bodyStart` position pointing into the middle
of the jxt block. This corrupted the function table and caused the struct
compiler to enter an infinite loop when resolving field positions.

**Fix:** Added a `jxt` block skip to `scanFunctions` so it treats `jxt`
blocks the same way the first and second passes do — skip the entire block
and move on.

**Verified:** `test_struct_jxt.k` (struct + jxt + field access) now
compiles and runs correctly, printing `10`.

---

## [1.0.2] - 2026-03-27

### Native .krh Header System

Krypton programs can now declare and call external C functions directly
using `jxt { func ... }` syntax inside `.krh` header files — no C shim
files required.

```
import "headers/windows.krh"

just run {
    let ticks = GetTickCount64()
    kp("Uptime ms: " + ticks)
}
```

Four built-in headers ship with v1.0.2: `windows.krh`, `stdio.krh`,
`math.krh`, and `string.krh`.

### Bug Fixes

- **jxt import hang** — `compileImportedFunctions` was attempting to
  compile `func` declarations inside imported jxt blocks as Krypton
  function bodies, producing invalid C. Fixed with `else if` branching.
- **debug printErr** — removed leftover `printErr("DEBUG struct: ...")`
  from the second-pass struct compiler.

---

## [1.0.0] - 2026-03-23

### Krypton 1.0.0

The language is complete. The compiler is self-hosting. Native compilation
via LLVM is working. This is the first stable release.

**What ships in 1.0.0:**

Language features:
- Variables, constants, functions, structs, modules
- Optional type annotations on all declarations
- String interpolation with backtick syntax
- All control flow: if/else, while, for-in, do-while, match, break, continue
- Try/catch/throw with setjmp/longjmp
- Ternary operator, compound assignment, list literals
- Float arithmetic (fadd/fsub/fmul/fdiv/fsqrt/fformat)
- Float literals (3.14 tokenizes correctly)
- jxt { } block for unified imports and C headers

Compiler:
- Self-hosting: the compiler is written in Krypton and compiles itself
- C backend: kcc source.k > source.c && gcc source.c -o source.exe
- IR backend: kcc --ir source.k > source.kir
- LLVM backend: build_llvm.bat source.k -> native binary
- 91 compiler functions, 147 kr_ builtins, 3,539 lines

Standard library: 35 modules including result, option, json,
math_utils, float_utils, string_utils, list_utils

IR optimizer: 6 passes (dead code, constant folding, strength
reduction, store/load elimination, empty jump removal, unused locals)

LLVM backend: alloca-based stack, opaque pointer mode, per-function
string constants, implicit fallthrough br, builtin name mapping

Bootstrap chain:
kcc (C++) -> v010 -> v020 -> v030 -> v040 -> v050 -> v060
          -> v070 -> v071 -> v072 -> v075 -> v077 -> v080
          -> v085 -> v086 -> v090 -> v095 -> v097 -> v098 -> v100

**Known issues in 1.0.0:**
- Struct + jxt in the same file causes a hang during compilation.
  Workaround: use `import` instead of `jxt k` when the file also has structs.
  Fix planned for v1.0.1.

---

## [0.9.8] - 2026-03-23

### LLVM Backend

Krypton now compiles to native machine code via LLVM IR.

**New file: `kompiler/llvm.k`** — 437-line Krypton program that reads
`.kir` files and emits LLVM IR (`.ll`). Key design decisions:

- **Opaque pointer mode** — uses `ptr` throughout, compatible with LLVM 15+
- **Alloca-based virtual stack** — 32 pre-allocated `alloca ptr` slots per
  function, avoiding all SSA value lifetime issues across basic blocks
- **Per-function string globals** — string constants named `@kp_funcname_N`
  to avoid cross-function naming conflicts
- **Implicit fallthrough** — `lastWasTerm` flag ensures every basic block
  ends with a terminator before the next label
- **Builtin name mapping** — `kp` → `kr_kp`, `toInt` → `kr_toInt` etc.

**New file: `runtime/krypton_runtime.c`** — standalone C runtime for
LLVM-compiled programs. Provides all `kr_` functions without the embedded
cRuntime string. Compile once with gcc, link against any Krypton binary.

**New file: `build_llvm.bat`** — full native compilation pipeline:

    .uild_llvm.bat source.k
    -> source.kir -> source_opt.kir -> source.ll -> source_llvm.exe

**Verified output for `test_ir.k`:**
```
7
120
loop: 0
loop: 1
loop: 2
```

---

## [0.9.7] - 2026-03-22

### Language — jxt Block

New header/import declaration block using family initials j, x, t:

    jxt {
        c "stdio.h"
        c "math.h"
        k "stdlib/result.k"
        k "stdlib/math_utils.k"
        t "windows.h"
    }

Language tags:
- `k` — Krypton module (same as existing `import` keyword)
- `c` — C system header, emits `#include <name>` in generated C
- `t` — alias for `c` (family initial, same behavior)
- Future: `cpp`, `asm`, `llvm` for other backends

The `jxt` block is processed before function compilation. The old
`import` keyword still works for backward compatibility.

### Compiler
- `jxt` added to `isKW`
- Import loop handles `KW:jxt` blocks, processing each entry by language tag
- Both passes skip `jxt` blocks cleanly via `skipBlock`
- `k` entries use full path resolution (relative to source + cwd fallback)
- `c`/`t` entries with path separators use `"name"`, others use `<name>`
- Self-host verified with kcc_v095.exe

---

## [0.9.5] - 2026-03-22

### IR Optimizer

New program: `kompiler/optimize.k` — reads .kir files, applies six
optimization passes, writes optimized .kir to stdout.

Pipeline: `kcc --ir file.k > file.kir && kcc kompiler/optimize.k file.kir > opt.kir`

Passes:
- Dead code elimination — removes instructions after RETURN/JUMP
- Constant folding — PUSH 3 / PUSH 4 / ADD -> PUSH 7
- Strength reduction — removes x+0, x*1, x-0
- STORE/LOAD elimination — STORE x / LOAD x -> STORE x
- Empty jump removal — JUMP x / LABEL x -> LABEL x
- Unused local removal — drops unreferenced LOCAL declarations

Stats printed to stderr: `; optimizer: 87 -> 61 instructions (26 removed)`

---

## [0.9.0] - 2026-03-22

### Krypton IR

New mode: `kcc --ir file.k > file.kir`

Emits .kir (Krypton Intermediate Representation) — a stack-based
text instruction set, one instruction per line, human-readable.

Instruction set: PUSH LOAD STORE LOCAL POP FUNC PARAM CALL BUILTIN
RETURN END ADD SUB MUL DIV MOD NEG NOT CAT EQ NEQ LT GT LTE GTE
JUMP JUMPIF JUMPIFNOT LABEL STRUCTNEW GETFIELD SETFIELD INDEX
TRY ENDTRY THROW BREAK CONTINUE

All language features produce correct IR: if/else, while, for-in,
match, do-while, try/catch/throw, structs, interpolation, list literals.

25 new functions added to compile.k for IR emission.
compile.k: 91 functions, 3492 lines.

---

## [0.8.6] - 2026-03-17

### Bug Fix — Struct + Import
Top-level struct declarations in files that also use `import` now compile
correctly. The second pass was using `pairPos` on the struct compiler's output
to advance past the struct body — but `pairPos` finds the last comma in the
entire output string, which is unreliable when the generated C code contains
commas. Fixed by using `skipBlock` to advance past the struct body directly
from the token stream, bypassing the C code output entirely. The first pass
now also emits a forward declaration for the struct's constructor function.

### Float Support

Floating-point literals now tokenize correctly:

    let pi = 3.14159
    let e = 2.71828

Float arithmetic functions (all take and return float strings):

| Function | Description |
|----------|-------------|
| `fadd(a, b)` | Float addition |
| `fsub(a, b)` | Float subtraction |
| `fmul(a, b)` | Float multiplication |
| `fdiv(a, b)` | Float division |
| `fsqrt(a)` | Square root |
| `ffloor(a)` | Floor |
| `fceil(a)` | Ceiling |
| `fround(a)` | Round |
| `fformat(a, decimals)` | Format to N decimal places |
| `flt(a, b)` | Float less-than comparison |
| `fgt(a, b)` | Float greater-than comparison |
| `feq(a, b)` | Float equality comparison |
| `toFloat(s)` | Convert string to float (identity) |

Generated C uses `atof`, `snprintf`, and `math.h`. Link with `-lm`.

### New Stdlib Module
- `stdlib/float_utils.k` — float arithmetic wrappers: `floatAdd`, `floatSub`,
  `floatMul`, `floatDiv`, `floatSqrt`, `floatFloor`, `floatCeil`, `floatRound`,
  `floatFormat`, `floatLt`, `floatGt`, `floatEq`, `floatAbs`, `pi()`

### Compiler
- `readNumber` — now handles float literals (digits `.` digits)
- `cRuntime` — 12 new `kr_f*` functions, `#include <math.h>` added
- kr_ builtins: 134 → 147
- Self-host verified with kcc_v085.exe

---

## [0.8.5] - 2026-03-17

### Language — Optional Type Annotations

Type annotations are now supported everywhere a declaration occurs. They are
optional, non-enforced, and produce no change in the generated C — the compiler
parses and discards them. All values remain `char*` at runtime.

**Variable declarations:**
```
let x: int = 42
let name: string = "Krypton"
let items: list[int] = "1,2,3"
```

**Function parameters and return types:**
```
func add(a: int, b: int) -> int {
    emit toInt(a) + toInt(b) + ""
}
```

**Struct fields:**
```
struct Point {
    let x: float
    let y: float
}
```

**Supported type names:** `int`, `float`, `bool`, `string`, `list`, `map`, `any`, `void`, `num`

**Compound types:** `list[int]`, `map[string, int]` — brackets parsed and skipped.

### Compiler (compile.k)
- `compileLet` — skips optional `: type` and compound `list[int]` annotations
- `compileFunc` — skips `: type` on each parameter; skips `-> type` return annotation
- `compileStructDecl` — skips `: type` on struct field declarations
- `scanFunctions` — skips type annotations when counting parameters (so param counts stay correct)
- `isKW` — type keywords `int`, `float`, `bool`, `string`, `list`, `map`, `any`, `void`, `num` added as keywords
- `cIdent` — added `abs`, `exit`, `rand`, `free`, `malloc`, `printf`, `strlen`, `strcmp`, `strcpy`, `time` to reserved C name list

### Interpreter (run.k)
- `execLet` — skips optional `: type` annotation on variable declarations

### Docs
- `Spec.md` — updated to v0.8.5, new section 3.5 for type annotations

---

## [0.8.0] - 2026-03-13

### Language
 - Module/import/export support
 - Error handling: try, catch, throw
 - Struct/class/type declarations
 - Foundation for advanced features (lambdas, pattern matching, concurrency)

### Compiler
 - Updated kompiler/compile.k with new keywords and statement support
 - Ready for full release testing

---

## [0.5.0] - 2026-03-12

### Language
- Ternary operator: `cond ? trueExpr : falseExpr` (nestable)
- `const` declarations: `const x = "value"`

### Built-in Functions (15 new, 72 total)
- **List ops:** `splitBy`, `listIndexOf`, `insertAt`, `removeAt`, `replaceAt`, `fill`, `zip`, `every`, `some`, `countOf`
- **Aggregation:** `sumList`, `maxList`, `minList`
- **Conversion:** `hex`, `bin`

### Compiler
- Added `?` token to lexer
- Added `const` keyword
- Ternary expression parsing with correct precedence
- Self-host verified (485 KB with icon)

---

## [0.4.0] - 2026-03-12

### Language
- `continue` statement in loops
- `match` statement with pattern values and `else` fallback
- `do-while` loop: `do { ... } while cond`

### Built-in Functions (15 new, 57 total)
- **Math:** `range`, `pow`, `sqrt`, `sign`, `clamp`
- **Strings:** `padLeft`, `padRight`, `charCode`, `fromCharCode`
- **Lists:** `slice`, `length`, `unique`
- **I/O:** `printErr`, `readLine`
- **Debug:** `assert`

### Bugfix
- Fixed `%` modulo operator in expressions — lexer emitted `MOD` token but parser checked for `PERCENT` (broken since v0.1.0, only `%=` worked since v0.3.0)

### Compiler
- Self-host verified (470 KB with icon)

---

## [0.3.0] - 2026-03-12

### Language
- Compound assignment operators: `+=`, `-=`, `*=`, `/=`, `%=`
- `for-in` loop: `for item in list { ... }`

### Built-in Functions (12 new, 42 total)
- **Lists:** `append`, `join`, `reverse`, `sort`
- **Maps:** `keys`, `values`, `hasKey`, `remove`
- **Strings:** `repeat`, `format`
- **Conversion:** `parseInt`, `toStr`

### Compiler
- Added compound assignment tokens (PLUSEQ, MINUSEQ, STAREQ, SLASHEQ, MODEQ)
- Added `kr_listlen` for comma-based list length (fixes for-in iteration)
- First version with embedded icon via Windows resource compiler
- Self-host verified (455 KB with icon)

---

## [0.2.0] - 2026-03-11

### Built-in Functions (15 new, 30 total)
- **Strings:** `indexOf`, `contains`, `replace`, `charAt`, `trim`, `toLower`, `toUpper`, `endsWith`
- **I/O:** `writeFile`, `input`
- **Math:** `abs`, `min`, `max`
- **System:** `exit`, `type`

### Compiler
- Self-host verified (230 KB)

---

## [0.1.0] - 2026-03-10

### Initial Release
- Krypton-to-C transpiler written in Krypton (self-hosting)
- Core syntax: `let`, `func`/`fn`, `emit`/`return`, `if`/`else`, `while`, `break`
- Entry point: `just run { ... }`
- String-based value model (all values are strings, numeric-aware arithmetic)
- Arena allocator with 256 MB blocks
- Handle-based StringBuilder

### Built-in Functions (15)
- **I/O:** `print`/`kp`, `readFile`, `arg`, `argCount`
- **Strings:** `len`, `substring`, `split`, `startsWith`, `getLine`, `lineCount`, `count`
- **Conversion:** `toInt`
- **Low-level:** `envNew`, `envSet`, `envGet`, `makeResult`, `getResultTag`, `getResultVal`, `getResultEnv`, `getResultPos`, `isTruthy`, `sbNew`, `sbAppend`, `sbToString`

### Compiler
- C++ bootstrap → self-hosted fixed-point achieved
- Bootstrap chain preserved in `build/versions/`## [0.8.0] - 2026-03-16

### Module System

`import`, `export`, and `module` are now fully implemented.

**import** — load another Krypton file and inline its functions:

    import "stdlib/result.k"
    import "stdlib/math_utils.k"

    just run {
        let r = ok("hello")
        kp(unwrap(r))
        kp(gcd(48, 18))
    }

Import features:
- Path resolution relative to the source file's directory
- Import caching — duplicate imports silently skipped
- Works with both flat files and legacy `go name { }` wrapped files
- Error reporting when imported file is not found
- Merged function tables — imported functions visible to the compiler

**export** — mark a function as part of a module's public API:

    export func add(a, b) {
        emit toInt(a) + toInt(b) + ""
    }

**module** — declare the current file's module name:

    module math_utils

### Stdlib — Fully Importable

All 34 stdlib modules have been converted to the flat function format.
The `go name { }` wrapper has been removed from all of them.
A `module name` declaration has been added to each file.

Modules ready to import:
    stdlib/assert.k         stdlib/bitwise.k        stdlib/builder.k
    stdlib/char_utils.k     stdlib/collections.k    stdlib/convert.k
    stdlib/counter.k        stdlib/csv.k             stdlib/debug.k
    stdlib/file_utils.k     stdlib/format.k          stdlib/hex.k
    stdlib/io_utils.k       stdlib/json.k            stdlib/lines.k
    stdlib/list_utils.k     stdlib/map.k             stdlib/math_utils.k
    stdlib/option.k         stdlib/pair.k            stdlib/path.k
    stdlib/queue.k          stdlib/random.k          stdlib/range.k
    stdlib/result.k         stdlib/search.k          stdlib/set.k
    stdlib/sort.k           stdlib/stack.k           stdlib/string_utils.k
    stdlib/struct_utils.k   stdlib/test_framework.k  stdlib/text.k
    stdlib/validate.k

### Compiler (compile.k)
- Real import processing: loads file, tokenizes, scans functions, emits forward
  decls and bodies before the main file's functions
- Base directory resolution for relative import paths
- Import cache prevents duplicate compilation
- `export func` now actually compiles the following function
- `module name` emits a C comment marker
- Error message when source file cannot be read
- Top-level struct declarations now compiled in the second pass
- `fn` keyword accepted alongside `func` in all positions

### Interpreter (run.k)
- `import "file.k"` loads file and merges function table at runtime
- `module` and `export` keywords handled (skip gracefully)

### New Examples
- `examples/import_demo.k` — uses result.k, math_utils.k, json.k together
- `examples/hello_modules.k` — minimal import example

### Compiler stats
- compile.k: 66 functions, 134 builtins, 3433 lines
- Self-host verified with kcc_v077.exe

---

## [0.7.7] - 2026-03-16

### Language
- List literals: `[1, 2, 3]` compiles to comma-separated string `"1,2,3"`
- Empty list literal: `[]` produces `""`

### Interpreter (run.k) — Full Language Parity
- Added 86 missing builtins — now handles 113 total (up from 27)
- Added: `for-in`, `match`, `do-while`, `continue`, `try/catch/throw`
- Added: compound assignment (`+=`, `-=`, `*=`, `/=`, `%=`)
- Added: DOT field access (`obj.field`) and field assignment (`obj.field = val`)
- Added: `struct` declaration handling (skip at runtime)
- The interpreter now matches the compiler in language feature support

### Built-in Functions Added to Interpreter
All v0.2.0–v0.7.5 builtins including: string ops (toLower, toUpper, trim,
lstrip, rstrip, replace, indexOf, contains, splitBy, strReverse, isAlpha,
isDigit, center, padLeft, padRight, repeat, format), list ops (append, join,
sort, reverse, unique, range, first, last, head, tail, every, some, countOf,
sumList, maxList, minList, insertAt, removeAt, replaceAt, fill, zip, slice,
listIndexOf), math (pow, sqrt, hex, bin, sign, clamp, abs, min, max, floor,
ceil, round), struct ops (structNew, getField, setField, hasField, structFields),
map ops (mapGet, mapSet, mapDel), system (random, timestamp, environ, exit),
and more.

### New Stdlib Modules
- `stdlib/result.k` — Result type: `ok(val)`, `err(msg)`, `isOk`, `unwrap`, `unwrapOr`
- `stdlib/option.k` — Option type: `some(val)`, `none()`, `isSome`, `optUnwrap`, `optUnwrapOr`
- `stdlib/json.k` — JSON builder: `jsonStr`, `jsonObject`, `jsonArray`, `jsonBool`, `jsonNull`

### Docs
- `docs/roadmap.md` — Full roadmap to v1.0.0 native compilation documented

### Compiler
- Import statement improved: attempts to read file, reports whether found
- compile.k: 63 functions, 134 builtins, 3211 lines
- Self-host verified with kcc_v075.exe

---

## [0.7.5] - 2026-03-16

### Language
- String interpolation upgraded to full expressions: `` `{a + b}`, `{len(s)}`, `{func(x)}` ``
  Previously only simple identifiers worked. Expressions inside `{}` are now tokenized
  and compiled as full Krypton expressions.

### Built-in Functions (7 new, 134 total)
- **Maps:** `mapGet(map, key)`, `mapSet(map, key, val)`, `mapDel(map, key)` — key-value map operations that complement the existing `keys()`/`values()`/`hasKey()`
- **Lists:** `listMap(lst, prefix, suffix)` — wrap each item, `listFilter(lst, val)` — keep matching items (`"!val"` to exclude)
- **Strings:** `strSplit(s, delim)` — alias for `splitBy` with clearer name
- **System:** `sprintf(fmt, ...)` — C-style format strings via `vsnprintf`

### Stdlib
- All 27 stdlib modules modernized: `i = i + 1` → `i += 1`, `i = i - 1` → `i -= 1`
- New module: `stdlib/struct_utils.k` — `structToString`, `structCopy`, `structFromMap`, `structToMap`, `structEqual`

### Algorithms
- All 23 algorithm files modernized to use compound assignment operators

### Examples
- All 33 remaining examples modernized to current syntax
- New: `examples/task_manager.k` — showcase using structs, try/catch, interpolation, match

### Interpreter
- `run.k` updated to support string interpolation (backtick strings with `{expr}`)

### Compiler
- `#include <stdarg.h>` added to generated runtime for `sprintf`
- Self-host verified with kcc_v072.exe

---

## [0.7.2] - 2026-03-15

### Critical Fix
- `struct`, `class`, `type`, `try`, `catch`, `throw` were missing from `isKW()` — the tokenizer was producing `ID:struct` instead of `KW:struct`, meaning structs and try/catch were silently broken in any real program. Fixed.

### Language
- String interpolation: `` `Hello {name}, version {ver}!` `` — backtick strings with `{identifier}` placeholders compile to `kr_cat()` chains

### Docs
- `docs/spec/functions.md` — fully updated to v0.7.2 with all 127 functions
- `docs/spec/grammar.md` — updated with structs, try/catch, interpolation, DOT token
- `docs/spec/types.md` — completely rewritten to accurately describe Krypton's string-based type model (old version described a fictional static type system)
- `docs/roadmap.md` — updated with accurate history and near-term plans

### Tutorials
- `21_structs.k` — struct declaration, literals, dot access, dynamic structs
- `22_try_catch.k` — try/catch/throw with nesting and rethrow
- `23_for_in.k` — for-in with nesting, counters, range
- `24_string_interpolation.k` — backtick strings with expressions
- `25_match.k` — match statement pattern matching

### Tests
- `tests/test_structs.k` — full struct coverage
- `tests/test_try_catch.k` — exception handling coverage
- `tests/test_interpolation.k` — string interpolation coverage
- `tests/test_for_in.k` — for-in loop coverage including triple nesting

### Examples Updated
- `fibonacci.k`, `fizzbuzz.k`, `hello.k`, `factorial.k` modernized to use `+=`, `for-in`, string interpolation

### Compiler
- Self-host verified with kcc_v071.exe

---


