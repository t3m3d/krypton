# Handoff M → L (Linux) + W (Windows): verify + remove the last two build `.sh` in the stem repo

**Date:** 2026-06-12
**From:** Agent M (macOS)
**Repo:** `t3m3d/stem` (formerly `kryoterm`; `~/Documents/GitHub/kryoterm` locally, GitHub-renamed to `stem`)
**Stem-repo commit:** `a00ad8d` — "build scripts: convert .sh -> KryptScript .ks"

## What I did

Converted all of stem's build shell scripts to **KryptScript** (`.ks`, run with `kcc -r X.ks`). They orchestrate via `exec("cmd 2>&1")`, `writeFile()`, `environ()`, `arg(toStr(i))`/`argCount()`. One `.ks` calls another with `exec("kcc -r other.ks")`.

Verified on macOS (produce identical artifacts), `.sh` deleted:
`build_gui.ks`, `make_icon.ks`, `build.ks`, `build_app.ks`, `build_objk.ks`, `gui.ks`.

## What I need from you

I could not run the two cross-platform scripts on this macOS box, so I **kept their `.sh` alongside the new `.ks`**. Please verify on your platform, then delete the `.sh`:

### L (Linux) — `build_linux.ks`
- Run: `kcc -r build_linux.ks` (and `--run`, `--ks`).
- Expect: builds `./stem` from `run.k` (static syscall-only ELF), prints size; `--ks` builds from `run.ks`; `--run` execs it.
- kcc resolution mirrors the old `.sh`: `kcc` on PATH, else `$KRYPTON_ROOT/bootstrap/kcc_driver_linux_x86_64` (default `KRYPTON_ROOT=../krypton`).
- If green: `git rm build_linux.sh` and commit.

### W (Windows) — `build_windows.ks`
- Run (POSIX-ish shell — git-bash/MSYS): `kcc -r build_windows.ks` (and `--run`).
- Expect: `kcc stem_win.ks -o stem.exe`, then **PE Subsystem patch CUI(3)→GUI(2)**, then copies `stem_win.exe.manifest` → `stem.exe.manifest`.
- **Watch this:** the old `build_windows.sh` embedded a `python3` heredoc for the byte patch. I removed python — KryptScript strings are NUL-terminated so binary file I/O isn't possible. The `.ks` instead does:
  ```
  peOff = od -An -tu4 -j60 -N4 stem.exe        # u32 LE at file offset 0x3c
  printf '\002\000' | dd of=stem.exe bs=1 seek=$((peOff+92)) conv=notrunc
  ```
  i.e. write u16 `2` at `peOff + 24 + 0x44` (= `+92`). **Confirm `od` + `dd` exist in your Windows shell** and that the resulting `stem.exe` launches from Explorer with no console window. If `od`/`dd` aren't available there, swap in whatever byte-poke tool is (still no python, please).
- If green: `git rm build_windows.sh` and commit.

## Notes
- KCC env var still honored in `build_windows.ks` (`KCC` overrides; default `C:/krypton/kcc.exe`).
- README already points at `kcc -r` invocations for the macOS scripts.
- If a `.ks` misbehaves, the deleted `.sh` are recoverable from git history (pre-`a00ad8d`).
- Reference for the `.ks` build pattern + the binary-I/O limit: the macOS scripts in the same commit.
