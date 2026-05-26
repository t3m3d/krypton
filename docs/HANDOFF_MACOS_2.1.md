# Handoff — macOS arm64 2.1.0 port

**Date:** 2026-05-26
**Audience:** Claude (or Brian) picking up on the M4 MacBook to ship the macOS leg of Krypton 2.1.
**Companion docs:** `docs/HANDOFF_M1.md` (general setup), `docs/HANDOFF_MACOS_2026_05_23.md` (IO helpers — that handoff is done, this one supersedes it for 2.1 scope).

---

## State coming in

Windows 2.1.0 shipped 2026-05-25:
- `kcc --version` reports `2.1.0`
- `installer/Output/krypton-2.1.0-setup.exe` cut (2.5 MB)
- `CHANGELOG.md` and `releasenotes/RELEASE_NOTES_2.1.txt` finalized
- 99/99 regression + 9/9 smoke pass
- Download page (`downloads-page-2.1.txt`) already mentions "macOS 2.1 drops today" — so the deadline is real

What's already on macOS (from prior sessions):
- `compiler/macos_arm64/macho_arm64_self.k` has inline `readLine` / `shellRun` / `exec` / `mapHas` / `mapGet` / `mapSet` (~line 3478-3920). Different code than Windows but same shape.
- 2.0 .pkg installer at the previous location
- 35/39 native tests pass on macOS arm64

---

## What needs to ship for 2.1.0 on macOS

### Tier 1 — must-have for the release

1. **Version bump.** `kccVer = "2.1.0"` in `compile.k:5310` is already done — macOS uses the same `compile.k`. Rebuild the macho host so `kcc --version` reports 2.1.0:
   ```
   ./compiler/macos_arm64/kcc-arm64 compiler/compile.k > /tmp/k.c
   clang /tmp/k.c -o /tmp/kcc-new -O2 -lm
   mv /tmp/kcc-new compiler/macos_arm64/kcc-arm64
   ```

2. **Verify `kcc -e` / `kcc -r` / shebang work via `kcc.sh`.** These are driver-level (kcc.sh) and tokenizer-level (compile.k shebang skip) changes — they should work on macOS unchanged. Test:
   ```
   bash kcc.sh -e 'kp("mac says hi")'
   chmod +x test.k && ./test.k     # with #!/usr/bin/env kr at top
   ```
   If any breakage, it's almost certainly path resolution in kcc.sh — fix and re-verify.

3. **POSIX port of `stdlib/fs.k`.** Currently Win32-backed. macOS needs:
   - `fsCwd` → `getcwd(3)` syscall or libc
   - `fsChdir` → `chdir(2)`
   - `fsMkdir` → `mkdir(2)` (mode 0755)
   - `fsRmdir` → `rmdir(2)`
   - `fsDelete` → `unlink(2)`
   - `fsRename` → `rename(2)`
   - `fsCopy` → no syscall; emulate via `open` + `read`/`write` loop, or `copyfile(3)` if available
   - `fsTempDir` → `getenv("TMPDIR")` (macOS sets it per-user)
   - `fsHomeDir` → `getenv("HOME")`
   - `fsFileExists` → `access(F_OK)` or `stat()`
   - `fsIsDir` → `stat()` + `S_ISDIR`
   - `fsListDir` → `opendir`/`readdir`/`closedir`
   Implementation hint: model after the existing `headers/sys_stat.krh` + `headers/unistd.krh` declarations. Keep the same Krypton-side API (`fsXxx(path)` returns `"1"`/`"0"`); only the implementation switches Win32→POSIX.

4. **POSIX port of `stdlib/settings.k`.** Currently uses `%APPDATA%`. macOS convention is `~/Library/Application Support/<app>/settings.json` or XDG (`$XDG_CONFIG_HOME` or `~/.config/<app>/`). Recommend `~/Library/Application Support/<app>/` since that's what native macOS apps use. Also: `findTool` walks `$PATH` with `:` separator on macOS (not `;`).

5. **`shellRun` real exit code on macOS arm64.** The macOS inline `shellRun` was added earlier per memory — verify it returns the actual exit code (not hardcoded `"0"`). If it doesn't, mirror the Windows fix: `wait4(pid, &status, 0, 0)` + extract via `WEXITSTATUS` macro inline + itoa.

6. **`installer/build_pkg.sh`** already exists for the .pkg. Bump `KryptonVersion` and run:
   ```
   ./scripts/build_pkg.sh
   # produces releases/krypton-2.1.0-macos-arm64.pkg
   ```

### Tier 2 — nice-to-have if time permits

7. **Linux x86_64 port of `fs.k` + `settings.k`** — same POSIX shape as macOS. If macOS POSIX port is done, Linux gets the same code essentially for free. The downloads page already says "Linux 2.1 lands today" too.

8. **Update VS Code extension** — current is `vscode-ext-krypton-language-1.8.4.vsix`. Could bump to a 1.9.x with the 2.1 keywords (`readLine`, `shellRun`, `exec`, the fs builtins). Not blocking the release.

### Out of scope for 2.1.0

- Self-hosting `compile.k` on macOS — blocked by the DATA_VMSIZE=64KB Tahoe issue per `docs/macos_gc_port_plan.md`. Defer to 2.1.1.
- macOS Cocoa GUI — `stdlib/gui.k` stays Win32-only. Cocoa is months of work.
- Batch-file equivalent discussion — there's a memory note marked TOMORROW. Bring it up with Brian before shipping anything; it's a design question, not a coding one.

---

## Memory worth reading before you start

- `memory/MEMORY.md` — index. Top entries flag tomorrow's discussion topics.
- `memory/project_batch_file_equivalent_todo.md` — Brian wants to discuss the `.k`-as-script-on-cmd question first thing.
- `memory/project_python_replacement.md` — full state of the Windows 2.1.0 push, so you know what's expected to work cross-platform.
- `memory/feedback_less_comments.md` — comment-density rule + the "don't-backslide guardrails are LOAD-BEARING" clause. Apply this to anything you write.
- `memory/feedback_stdlib_install_sync.md` — Windows-specific gotcha; less relevant on macOS but worth knowing.

---

## Verification recipe before tagging

```bash
# from repo root on the Mac
./compiler/macos_arm64/kcc-arm64 --version          # expect 2.1.0
bash tests/smoke_2_1_features.sh                    # expect 9/9 (curl-based parts)
bash kcc.sh -e 'import "k:fs"; kp(fsCwd())'         # expect repo path
bash kcc.sh -e 'import "k:settings"; kp(settingsDir("krmacos_test"))'  # expect ~/Library/Application Support/krmacos_test
bash kcc.sh -r examples/settings_kcode_win.k        # should print resolved tools

# native test sweep (~35/39 at 2.0; should hold or improve)
for t in tests/*.k; do
    ./compiler/macos_arm64/kcc-arm64 "$t" 2>/dev/null && ...
done

# .pkg build
./scripts/build_pkg.sh
# produces releases/krypton-2.1.0-macos-arm64.pkg
```

---

## When you're done

1. Update CHANGELOG's `[2.1.0]` section to mark macOS + Linux entries green (currently they say "no / needs POSIX port — 2.1.1").
2. Update `releasenotes/RELEASE_NOTES_2.1.txt` with the macOS section confirmed shipped.
3. Update `downloads-page-2.1.txt` — remove the "macOS 2.1 drops today" banner, swap the 2.0 macOS download link for the new 2.1.0 link, copy the macOS bullets in from the 2.0 section + add the new 2.1 ones.
4. Tag: `git tag -f v2.1.0` (force if you tagged from Windows earlier).
5. Upload `krypton-2.1.0-macos-arm64.pkg` to the GitHub release.
6. Bring up the batch-file equivalent discussion with Brian.

---

## Honest scope note

This is a one-day port if the POSIX stdlib work goes smoothly. If `fs.k`/`settings.k` need a lot of fiddling with syscall ABI differences (return-as-pointer-vs-int, errno handling), it could slide to 2-3 sessions. Don't ship a half-working `fs.k` on macOS — better to leave it Windows-only and ship 2.1.0 as Windows-only than to ship a buggy POSIX layer.

If you punt the stdlib ports, you can still ship 2.1.0 on macOS with just:
- Version bump
- kcc -e / -r / shebang verification
- shellRun real exit code
- .pkg cut

The fs/settings POSIX ports can slip to 2.1.1 without embarrassment. Update the downloads page accordingly.
