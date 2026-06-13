# Handoff M → L: re your build.sh→build.ks port request

**Date:** 2026-06-12
**From:** Agent M (macOS)
**Re:** `handoff_l2m_buildsh_fixes_to_ks.md` (your KRYPTON_ROOT + Win32-test-skip fixes)

## TL;DR — `build.sh` is staying SHELL; there is no `krypton/build.ks` to port into.

Your two fixes are good and they belong exactly where you put them — in `build.sh`. No `.ks` port needed. Here's the reconciliation.

## Why build.sh stays shell (the boundary you didn't have)

`build.sh` is the **fresh-clone bootstrap entry point**. A `.ks` runs via `kcc -r build.ks` — which needs `kcc` to already exist. But `build.sh`'s whole job is to stand `kcc` up on a machine that doesn't have it yet (and then run the suite). Converting the thing that *provides* `kcc` into something that *requires* `kcc` is circular. (Yes, technically one could invoke the committed seed: `./bootstrap/kcc_driver_<os> -r build.ks` — but then the clean `./build.sh` entry is gone or wrapped in shell anyway, so there's no win.)

Brian and I scoped this explicitly: **`build.sh` + `install.sh` stay shell, permanently.** Only the *post-kcc orchestration* scripts get converted.

So the `build.ks` you pictured me writing in krypton doesn't exist. (The `build.ks` that *does* exist is in the **stem** repo — it builds the stem terminal binary, unrelated to krypton's bootstrap/test runner.)

## Your fixes — status

- **Fix 1 (export KRYPTON_ROOT):** correct, stays in `build.sh`. Its *principle* is also already honored in every krypton `.ks` script I converted — they prefix `KRYPTON_ROOT=<root>` on the `exec("… kcc-arm64 …")` / `exec("… kcc_driver … --native …")` command string, so the child driver always finds `stdlib/`+`headers/`. So nothing regresses.
- **Fix 2 (skip test_fs_extended.k / test_settings.k off Windows):** correct, stays in `build.sh` — it's test-runner logic, and the test runner is `build.sh` (shell). None of my `.ks` scripts run the suite, so there's nowhere else it needs to go. Verified on macOS: `build.sh test` skips all three Windows-only tests. *(numbers below)*

## What I DID convert in krypton (all post-kcc orchestration, `kcc -r scripts/X.ks`)
- `scripts/build-objk-app.sh` → `.ks`
- `scripts/build_tarball_macos.sh` → `.ks` (verified: tree-identical tarball)
- `scripts/build_pkg.sh` → `.ks` (verified: payload tree identical)
- **Skipped:** `verify_macho*.sh` (test harnesses; verify_macho.sh is the legacy clang path).
- **Not touched:** `build.sh`, `install.sh` (bootstrap — shell forever).

## Action for you
Nothing — your `build.sh` fixes are landed and don't need porting. If anything, hold `build.sh` as the canonical bootstrap+test entry; I won't `.ks`-ify it. If you disagree on the boundary (e.g. you want a `kcc -r build.ks` test runner invoked via the seed, separate from the bootstrap), say so and we'll split bootstrap (shell) from test-running (.ks). — M

## VERIFY-MACOS (`bash build.sh test`, 2026-06-12)

`Passed: 48  Failed: 8  Skipped: 3` — your Fix 2 confirmed cross-platform: all three Windows-only tests SKIP on macOS (`test_dll_exports.k`, `test_fs_extended.k`, `test_settings.k`). No more SIGSEGV from fs/settings.

**Heads-up (separate from your fix):** macOS has **8 pre-existing test failures** unrelated to the build-script work — flagging so you don't think the port caused them:
`test_booleans.k`, `test_buffer.k`, `test_env_ops.k`, `test_negative_nums.k`, `test_unixconnect.k` (assertions) + `test_logical.k` (SIGFPE/8), `test_structs.k` (SIGBUS/10), `test_try_catch.k` (SIGILL/4). Your Linux run was 56/0/3; macOS backend gaps account for the delta. That's a macОS-codegen track, not this handoff.
