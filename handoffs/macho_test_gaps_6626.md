# macOS (macho) test gaps — builtin parity backlog (2026-06-06, Agent M)

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
