# Linux Release Backlog

Tracking what's left before the Linux native backend (`compiler/linux_x86/elf.k`)
is release-quality. Two-agent split agreed 2026-06-02:

- **agent-l** (native Arch): owns ALL edits to existing files — especially `elf.k`
  codegen. Single editor of the hot file = near-zero merge conflicts.
- **agent-w** (Arch on WSL2): **greenfield only — creates NEW files, never edits
  existing ones.** If a track needs an existing-file change, it goes in the
  "Needed from agent-l" list below and agent-w stubs/works around it meanwhile.

Both: `git pull --rebase` before pushing (macOS/Windows agents share `main`).

---

## Done (agent-l, 2026-06-02)

- [x] Native `exec()` / `shellRun()` builtins in `elf.k` (inline syscalls, C-free). Verified.
- [x] Int/pointer tag ceiling raised `0x40000000 → 0x7F000000` (~1.07e9 → ~2.13e9,
      Unix epoch through ~2037). Commit `5f06fc97`, regression `tests/test_int_ceiling.k`.
- [x] yubiKrypt (TUI authenticator) runs on Linux — its macOS frontend reused verbatim.

## agent-l — native aarch64 backend (`compiler/linux_arm64/elf.k`)

- [x] **Milestone 1 (done):** minimal cross backend — `kp("literal")` → `write`+`exit`,
      static aarch64 ELF under qemu-user. First native aarch64 binary from the compiler.
- [x] **Milestone 2 (done):** real stack machine — integers + arithmetic (+ - * / %),
      locals (STORE/LOAD), and the `kr_str_int` / `kr_print` runtime helpers. Compiles
      programs that compute and print numbers and variables (kp(2+3*4)→14, let a=21
      kp(a+a)→42). kp dispatches int vs string on the 0x400000 tag. Verified under qemu.
- [ ] **Milestone 3:** control flow — LABEL/JUMP/JUMPIFNOT, comparisons (LT/GT/EQ),
      isTruthy → compile loops/conditionals (while, if).
- [ ] Then: string concat (CAT) + `kr_alloc`, negative-literal handling, MOVK for the
      operand-stack region (lift the program-size cap), `kcc.sh` wiring for `--native`.

## agent-l — edits to existing files (mostly `elf.k`)

- [ ] **Full 64-bit integers.** Current ceiling `0x7EFFFFFF` (~2.13e9) is a Y2038-class
      stopgap. Real fix = a tag scheme that doesn't equate the load base with the
      int/pointer threshold; reworks every `imm32` CMP site to 64-bit compares. Big.
- [ ] **`split()` builtin is broken** → `examples/binary_convert.k` SIGSEGVs (confirmed
      pre-existing, crashes on the pre-fix compiler too). Fix `krSplit`/`krRange` in `elf.k`.
- [ ] **`AF_UNIX` socket connect.** `sockConnect` is `AF_INET`/TCP only — blocks the local
      X11/Wayland transport for agent-w's GUI track. Add an `AF_UNIX` connect path.
- [ ] **Audit builtins** for other `>= 0x7F000000` pointer-tag assumptions now the range moved.
- [ ] (Longer-term) dynamic linking in `elf.k` — only if the socket-protocol GUI path proves
      insufficient. Currently static, syscall-only ELF.

## agent-w — greenfield (NEW files only)

- [ ] **`stdlib/x11.k` — pure-Krypton X11 client over a socket.** Speak the X11 wire protocol
      (handshake, `CreateWindow`, `MapWindow`, `PolyFillRectangle`/`ImageText8`) using the
      existing `sockMake`/`sockConnect`/`sockSend`/`sockRecv` builtins — no dynamic linking.
      This is the route to a Linux GUI frontend that mirrors how the macOS HTTP server was
      built C-free over sockets. **Transport dependency:** local display is `AF_UNIX`; start
      against TCP (`127.0.0.1:6000+N`) if the X server `-listen tcp`, else wait on agent-l's
      `AF_UNIX` connect. Wayland (`$XDG_RUNTIME_DIR/wayland-*`) is `AF_UNIX`-only → needs it.
- [ ] **App repo Linux ports** (sibling repos, fully owned by agent-w):
      - `kryofetch` standalone repo: add `run_linux.k` + `build_linux.sh` (adapt from
        `krypton/contrib/linguist/samples/kryofetch/run_linux.k`, which works).
      - `terk` (C++/Qt6 terminal): build on WSL Arch — `platform/linux/PTYPlatform.cpp`
        already exists; needs `qt6-base`, `cmake`. New build script / docs only.
      - `yubikrypt`: already runs on Linux — just verify + (optionally) `usbipd-win` USB test.
- [ ] **`tests/run_linux.sh` — a real test runner.** The current harness masks segfaults /
      ignores exit codes. New runner: compile+run each `tests/*.k`, check exit code, grep
      `[FAIL]`. Optional `.github/workflows/linux.yml` (WSL/CI). New files only.
- [ ] **Arch packaging:** `PKGBUILD`(s) for the apps.

## Needed from agent-l (filed by agent-w as it hits walls)

- `AF_UNIX` socket connect (for local X11/Wayland) — see above.
- _(append here)_

---

### Environment notes (WSL2)

- **WSL2, not WSL1** — `elf.k` emits raw syscalls (`mmap`, `pipe2`, `execve`, sockets);
  WSL1's syscall emulation can choke. WSL2 runs a real kernel.
- **Arch on WSL2** for parity with agent-l (pacman, same `gcc`/paths).
- **USB → WSL2** needs `usbipd-win` to attach a YubiKey for live detection; the "no key"
  path works without it. WSL2 clock can drift — relevant to TOTP.
- krypton binaries are **static, syscall-only ELF** — they run on any WSL2 kernel regardless
  of distro; distro only affects the build toolchain + tools apps shell out to.
