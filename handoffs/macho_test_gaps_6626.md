# macOS (macho) test gaps — builtin parity backlog (2026-06-06, Agent M)

**NEW 2026-06-06 — `k:map` (stdlib/map.k) BROKEN on macho — ROOT-CAUSED (name
collision with broken macho-only builtins).** Found building kryoterm's grid.
`map.k` defines `func mapSet`/`mapGet`/`mapHas`, but **`mapHas,mapGet,mapSet,mapDel`
are in compile.k's builtins list (`compile.k:1424`)** → the frontend emits
`BUILTIN_MAPSET`/`BUILTIN_MAPGET` for those calls, SHADOWING map.k's functions.
Those builtin handlers exist **only in macho_arm64_self.k (9 refs); elf.k and
x64.k have 0, and there is NO `BUILTIN_MAPNEW` anywhere** (the native map can't
even be constructed). So on macho the broken/vestigial builtin wins and corrupts
the string map (3-key loop → 1 line, keys dropped); on Linux/Windows the same
calls fall through (no backend handler) and map.k effectively works.
Bisection proof: a verbatim copy of map.k's 8 functions renamed `my*` works; rename
`mySet`/`myGet` → `mapSet`/`mapGet` and it breaks — names are the only diff.
**FIX (cross-platform, needs the owner — NOT a safe unsupervised patch on the
just-shipped self-host compiler):** (1) remove `mapHas,mapGet,mapSet,mapDel` from
`compile.k:1424` builtins list so user funcs win; (2) drop the dead
`BUILTIN_MAP*` emitters in `macho_arm64_self.k`; (3) make the files that call
`mapGet/mapSet` WITHOUT importing k:map — `stdlib/json.k`, `json_parse.k`,
`struct_utils.k`, `native_extras.k`, `examples/import_demo.k` — `import "k:map"`
(or the build must guarantee map.k links); (4) regen ALL frontend seeds + the
macho host; (5) re-test json.k + map.k on all 3 platforms. The proper long-term
fix is frontend precedence: a user-defined `func` should shadow a same-named
builtin. **kryoterm is unblocked already** (flat-string grid, no map needed).

Found while doing a fresh-clone build/test pass on macOS. **Not regressions** —
these are builtins/edges that exist on Linux `elf.k` but aren't ported to
`compiler/macos_arm64/macho_arm64_self.k` yet. Basics (arithmetic, strings,
negative numbers, booleans, logical ops, recursion, structs-core, SB, exec,
file I/O) all pass.

## How to reproduce
```
./build.sh            # ships/uses bootstrap/kcc_driver_macos_aarch64 (now committed)
./build.sh test       # native macOS suite
```
**Harness fix landed this session:** `build.sh`'s native scorer used to grep only
for `[FAIL]`, so a crashed test binary (empty output) scored as a false **OK**.
It now also fails on crash signals (rc 132–139 = SIGILL/ABRT/FPE/BUS/SEGV). That
flipped the honest count to **48 passed / 10 failed / 1 skipped**.

## The 10 failures (all macho builtin/edge gaps)

| test | symptom | likely cause |
|---|---|---|
| test_buffer.k     | assertion/SIGBUS | `bufNew/bufSetByte/bufGetByte/bufGetWordAt/bufGetDwordAt` — **0** implemented in macho (exist in elf.k since `7282660d`) |
| test_unixconnect.k| `[FAIL] bogus path returns negative errno` | `unixConnect` (AF_UNIX) — **0** in macho (Linux-only builtin, `ea06a652`). Probably should be a macOS SKIP, not a port |
| test_env_ops.k    | SIGILL | `envNew/envSet/envGet` env-map builtins missing on macho |
| test_settings.k   | crash sig 4 (SIGILL) | `k:settings` stdlib → a builtin macho lacks |
| test_structs.k    | crash sig 10 (SIGBUS) | struct builtin edge (core struct ops pass elsewhere; some op faults) |
| test_fs_extended.k| crash sig 4 (SIGILL) | an extended-fs builtin missing on macho |
| test_try_catch.k  | crash sig 4 (SIGILL) | exception path edge |
| test_logical.k    | crash sig 8 (SIGFPE) | core logical asserts PASS; a later edge faults (div/mod by 0?) |
| test_booleans.k   | assertion | core bool asserts PASS; a later edge assert |
| test_negative_nums.k | assertion | core neg asserts PASS; a later edge assert |

## Suggested routing
- **Real ports** (parity with elf.k): byte buffers, env-map, the settings/fs
  builtins — same kind of work as the SB port. Mirror the elf.k handlers into
  macho's builtin emitter block.
- **unixConnect**: likely a macOS SKIP (AF_UNIX is Linux transport) rather than a
  port — or stub to return -ENOSYS cleanly so the test's negative-errno assert
  passes.
- **The 3 "core-passes-edge-fails"** (logical/booleans/negative_nums): worth a
  per-assertion look — the head asserts pass, so it's one specific later line.

I did NOT touch `macho_arm64_self.k` (deep ARM64 codegen, backend-owner turf).
Flagging for whoever owns macho parity (coordinate w/ W's SB-port lane).

— M (macOS)
