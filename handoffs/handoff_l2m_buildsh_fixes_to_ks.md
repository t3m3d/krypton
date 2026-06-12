# Handoff L → M: port two build.sh fixes into the new build.ks

**Date:** 2026-06-12
**From:** Agent L (Linux, Arch/Hyprland dev box)
**To:** Agent M (macOS) — you're converting `build.sh` → KryptScript `build.ks`
**Repo:** `krypton` (this repo)
**Commit to carry over:** `352790df` — "fix(build.sh): export KRYPTON_ROOT; skip
Win32-only fs/settings tests off Windows" (on `main`, may be unpushed when you
read this — `git show 352790df` if you don't see it).

## Why you're getting this

You're rewriting `build.sh` as `build.ks`. I landed two fixes in `build.sh`
*after* you likely branched, so a straight conversion of the old file will
**silently regress both**. Please port them into `build.ks`. Both are verified
on Linux x86_64 (kcc 2.3.0): with them, `./build.sh test` = **56 passed / 0
failed / 3 skipped** (was 2 SIGSEGV crashes); without #1 a fresh-clone build
fails outright.

## Fix 1 — default/export KRYPTON_ROOT before invoking the kcc driver

`build.sh` never set `KRYPTON_ROOT`. From a plain source checkout the bootstrap
driver (`bootstrap/kcc_driver_<os>_<arch>`) can't locate `stdlib/`+`headers/`,
so the `--native` smoke test dies with:

    kcc: cannot find install root (set KRYPTON_ROOT)

Fix (bash): right after `cd "$SCRIPT_DIR"` —

    export KRYPTON_ROOT="${KRYPTON_ROOT:-$SCRIPT_DIR}"

**build.ks equivalent:** before any `exec("... kcc_driver ... --native ...")`,
ensure the child sees `KRYPTON_ROOT`. If `environ("KRYPTON_ROOT")` is empty,
set it to the script/checkout dir (the dir containing `compile.k`/`stdlib/`).
Honour an existing value — don't clobber an override. Whatever mechanism your
other `.ks` scripts use to pass env into `exec()` (e.g. prefixing
`KRYPTON_ROOT=<dir> ` on the command string) is fine.

## Fix 2 — skip the two Win32-only tests on Linux/macOS

`stdlib/fs.k` and `stdlib/settings.k` are **pure Win32 IAT** (`CreateDirectoryA`,
`GetTempPathA`, `GetCurrentDirectoryA`, `GetEnvironmentVariableA`,
`GetFileAttributesA`, ...). On Linux/macOS the native ELF/Mach-O pipeline emits
calls to symbols that don't exist off Windows → the compiled test binary
**SIGSEGVs at runtime** (compiles fine; crashes on the first fs/settings call).
This is a test-gating gap, **not** a compiler bug.

So `test_fs_extended.k` and `test_settings.k` must join the existing
`test_dll_exports.k` Windows-only skip. In `build.sh` the case became:

    case "$NAME:$OSNAME" in
        test_dll_exports.k:linux|test_dll_exports.k:macos \
        |test_fs_extended.k:linux|test_fs_extended.k:macos \
        |test_settings.k:linux|test_settings.k:macos)
            echo -e "${CYAN}SKIP${RESET}  $NAME (Windows-only)"
            SKIPPED=$((SKIPPED + 1))
            continue
            ;;
    esac

**build.ks equivalent:** in the per-test loop, if `OSNAME` is linux or macos and
the basename is one of `test_dll_exports.k` / `test_fs_extended.k` /
`test_settings.k`, print a SKIP line, bump the skipped counter, and `continue`.

## Full reference diff (commit 352790df, build.sh)

```diff
@@ SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
 cd "$SCRIPT_DIR"
+
+# The bootstrap kcc driver locates stdlib/headers via KRYPTON_ROOT; from a plain
+# source checkout it's otherwise unset and `--native` fails with "cannot find
+# install root (set KRYPTON_ROOT)". Default it to this checkout; honour an override.
+export KRYPTON_ROOT="${KRYPTON_ROOT:-$SCRIPT_DIR}"
@@         case "$NAME:$OSNAME" in
-            test_dll_exports.k:linux|test_dll_exports.k:macos)
+            test_dll_exports.k:linux|test_dll_exports.k:macos \
+            |test_fs_extended.k:linux|test_fs_extended.k:macos \
+            |test_settings.k:linux|test_settings.k:macos)
+                # stdlib fs.k/settings.k are pure Win32 IAT (CreateDirectoryA,
+                # GetTempPathA, GetEnvironmentVariableA, ...); the native ELF
+                # pipeline emits calls to symbols absent off Windows → SIGSEGV.
                 echo -e "${CYAN}SKIP${RESET}  $NAME (Windows-only)"
                 SKIPPED=$((SKIPPED + 1))
                 continue
                 ;;
         esac
```

## When done

Verify on macOS that `kcc -r build.ks test` skips all three Windows-only tests
and the rest pass, then delete `build.sh` (recoverable from git history /
commit `352790df` if needed). — L
