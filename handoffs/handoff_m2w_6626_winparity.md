# Handoff M→W — Windows fresh-clone / 2.2.0 release parity (2026-06-06)

**Context:** I fixed the macOS half of the fresh-clone build (kcc.sh was removed
in 0c0dc57b; build/install/test still pointed at it or hit a driver bug). macOS
is now green. These are the matching **Windows** items so 2.2.0 cuts as an equal
Windows+macOS release. Low/medium priority — pick up when you're back.

## What I shipped on macOS (reference)

- `f99da5bd` — macOS `build.sh`/`install.sh` were broken on a fresh clone:
  - `bootstrap/kcc_driver_macos_aarch64` **wasn't committed** (only `_linux_x86_64`).
    Built it from `kcc.ks` via the repo native toolchain (clang-free) and shipped it.
  - **`kcc.ks` bug:** the macOS *default compile* path used `positional(0)` to find
    the source, which mistook `build.sh`'s leading `--native` flag (the documented
    default) for the source → `kcc: no source file`. Changed it to `linuxSrc()`
    (the flag-tolerant finder the Linux branch already uses).
  - Verified: `./build.sh` installs the seed, fibonacci smoke → 4181, no gcc.
- `15a8a0cc` — repointed test runners off `kcc.sh`: `tests/run_linux.sh`,
  `tests/wasm/RUN.sh`, `tests/smoke_2_1_features.sh` (latter also dropped the
  `bash "$KCC"` prefix — the driver is a binary now, not bash).

## Windows TODO (yours)

### 1. `kcc.ks` Windows branch has the SAME `--native` bug
The Windows **default compile** path (~`kcc.ks:552`) is still `let src = positional(0)`.
`build.sh` calls the driver as `--native <src> -o <out>`, so `positional(0)` will
mistake `--native` for the source → "no source file" on Windows too. The Windows
`--ir` branch already uses `linuxSrc()`; just change the default path the same way:
```
-    let src = positional(0)
+    let src = linuxSrc()        // skip leading no-op flags like --native (matches --help)
```
(`linuxSrc()` is platform-agnostic despite the name — scans argv, skips `-flags`,
handles `-o VALUE`.)

### 2. No Windows driver seed in `bootstrap/`
`bootstrap/` has `kcc_driver_linux_x86_64` and now `kcc_driver_macos_aarch64`, but
**no Windows driver seed**. `build.sh` sets `KCC_DRIVER=bootstrap/kcc_driver_windows_x86_64.exe`
and `install.sh` expects it too — both will fail on a fresh Windows clone the same
way macOS did. Compile `kcc.ks` → the Windows driver binary and commit it under
the name `build.sh`/`install.sh` expect (`bootstrap/kcc_driver_windows_x86_64.exe`),
or reconcile with the `kcc-bin.exe` layout your `findRoot` already looks for. Then
verify a fresh-clone `bootstrap.bat` → `./build.sh`/`kcc -e`/`kr` round-trip.

### 3. `bootstrap.bat` help text echoes the dead `kcc.sh`
Cosmetic but user-facing — lines 5, 37, 42 still say `kcc.sh`:
```
5:  REM ... so kcc, kcc.sh --native, etc. work ...
37: echo   bash kcc.sh --native examples/hello.k -o hello.exe ...
42: echo   - Run kcc.sh from cmd/PowerShell-launched bash ...
```
Update to the current `kcc` / `kcc.ks` driver invocation.

### 4. (clean) `tools/kr/run.k`
No `kcc.sh` references — nothing to do.

## Optional shared follow-up (either of us)
macOS `kcc -e` / `kcc -r` let the backend's `wrote <path> (... signed)` status
line hit **stderr** (stdout stays clean, so piping works fine). It only shows up
when a caller merges `2>&1` (e.g. `tests/smoke_2_1_features.sh`, which is
Windows-shaped). If we want `2>&1` to stay clean in run/eval modes, the driver
could suppress the host's stderr in `-e`/`-r` (temp-binary modes) while keeping it
for `-o`. Check whether the Windows backend emits an equivalent line.

`CHANGELOG.md` still mentions `kcc.sh` in historical entries — left as-is (record).

— M (macOS)
