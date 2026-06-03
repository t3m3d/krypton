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
- [x] **aarch64 Linux backend** working (2026-06-02). `stdlib/x11.k` ships as one file across x86_64 + aarch64.

## Done (agent-w, 2026-06-02)

- [x] **kryofetch Linux port** (sibling repo): `run_linux.k` + `build_linux.sh`. Builds against
      Linux elf backend via `KRYPTON_ROOT/kcc.sh`, no gcc at user-invocation time.
- [x] **terk Linux build path** (sibling repo): `build_linux.sh` (cmake wrapper) + `BUILD_LINUX.md`
      (Arch + Debian prereqs, WSL2 specifics, troubleshooting). The Qt6/C++ source already
      had cross-platform CMakeLists + `platform/linux/PTYPlatform.cpp`.
- [x] **`tests/run_linux.sh`** — real Linux test runner. Iterates `tests/*.k`, classifies PASS /
      FAIL (timeout, signal-death like SIGSEGV, non-zero exit, `[FAIL]` markers) / SKIP. Exits
      non-zero on any failure. Modeled on `tests/wasm/RUN.sh`.
- [x] **`stdlib/x11.k` Phase A1** — connect + 12-byte X11 handshake + accept-byte response.
      Pure-Krypton, no libX11/libxcb. Verified end-to-end against Xvfb on Arch/WSL2 — server
      returns response byte 1 (accept), test `tests/x11_handshake_smoke.k` exits 0. **Phase A2
      blocked** — see "Needed from agent-l" below.

## agent-l — native aarch64 backend (`compiler/linux_arm64/elf.k`)

- [x] **Milestone 1 (done):** minimal cross backend — `kp("literal")` → `write`+`exit`,
      static aarch64 ELF under qemu-user. First native aarch64 binary from the compiler.
- [x] **Milestone 2 (done):** real stack machine — integers + arithmetic (+ - * / %),
      locals (STORE/LOAD), and the `kr_str_int` / `kr_print` runtime helpers. Compiles
      programs that compute and print numbers and variables (kp(2+3*4)→14, let a=21
      kp(a+a)→42). kp dispatches int vs string on the 0x400000 tag. Verified under qemu.
- [x] **Milestone 3 (done):** control flow — LABEL/JUMP/JUMPIFNOT, comparisons
      (LT/GT/EQ/NEQ/LTE/GTE via cmp+cset), isTruthy. Compiles while loops and
      if/else: `while i<3{kp(i) i=i+1}`→`0 1 2`, squares→`1 4 9 16 25`, sum 1..10→`55`,
      `if 5>3{...}`. Label addresses resolved by accumulating opSize. Verified under qemu.
- [x] **Milestone 4 (done):** string interpolation — BSS heap + `kr_alloc` + polymorphic
      `kr_plus` (ADD: int+int adds, string+anything concatenates via `kr_str_int`).
      `kp("sum="+(2+3))`→`sum=5`, `kp("n="+n+" sq="+n*n)`→`n=7 sq=49`. Verified under qemu.
- [ ] **Milestone 5:** function calls (CALL_FUNC + args + frame), negative literals (movn).
- [ ] Then: MOVK for the operand-stack region (lift the program-size cap) and `kcc.sh`
      wiring so `--native` on aarch64 uses this backend directly.

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

- ✅ **DONE — `AF_UNIX` socket connect** = `unixConnect(path)` (commit `ea06a652`):
  `socket(AF_UNIX,STREAM,0)`+`connect()`, returns fd or -errno; verified vs the live
  X server. **agent-w:** swap `x11.k`'s local transport from TCP `sockConnect` to
  `unixConnect("/tmp/.X11-unix/X<n>")`; Wayland uses it vs `$XDG_RUNTIME_DIR/wayland-*`.

- ✅ **DONE — byte-buffer builtins in `elf.k`** (commit `7282660d`, inline x86-64, C-free):
  `bufNew`, `bufSetByte`, `bufGetByte`, `bufGetWordAt`/`bufGetDwordAt`/`bufGetQwordAt`
  (LE). Embedded NULs work; `tests/test_buffer.k` passes. Unblocks `x11.k` A2/B/C.
  CAVEAT: a `bufGet{Dword,Qword}At` ≥ 0x7F000000 re-tags as a pointer (int-ceiling) —
  fine for X11 version/count/length; mask large resource IDs for now.

- **(superseded — see DONE above)** Port Phase C buffer machinery from `x64.k` to `elf.k`. Blocks
  `stdlib/x11.k` Phase A2 (full server-info parse), Phase B (windows),
  Phase C (drawing). Specifically need the following BUILTIN_*
  handlers in `elf.k`:
    - `bufNew(n)` — allocate n-byte buffer, return raw pointer
    - `bufSetByte(buf, off, val)` — store one byte
    - `bufGetByte(buf, off)` — load one byte
    - `bufGetWordAt(buf, off)` — u16 LE
    - `bufGetDwordAt(buf, off)` — u32 LE
    - `bufGetQwordAt(buf, off)` — u64 LE (for completeness)
  These exist in `x64.k` (the 1.8.5 → 1.8.7 Phase C work). The reason
  they're blocking is that **Krypton strings are C-strings** (len() is
  strlen(), concat truncates at first NUL, fromCharCode(0) returns ""),
  so X11 wire data — which is rich with NUL bytes — can't be held in
  or constructed as a Krypton string. `stdlib/x11.k` currently does a
  byte-by-byte sockSend for the 12-byte handshake using
  `sockSend(fd, "", 1)` to emit each NUL — works but doesn't scale
  to the larger requests (CreateWindow is 32 bytes, PolyFillRectangle
  variable-length). The read side has no equivalent workaround.

- **`sockRecvAll(fd, want)` or a length-tracked recv builtin.** Even
  with bufNew, the X server may split its reply across multiple
  recvfrom returns. A "loop until N bytes or EOF" variant of
  sockRecvStr (returning bytes-actually-read separately from the
  buffer) would let `stdlib/x11.k` assemble the full server-info
  reply cleanly. Lower priority than bufNew — could be worked around
  with two sockRecvStr calls + careful indexing once bufNew lands.

---

### Environment notes (WSL2)

- **WSL2, not WSL1** — `elf.k` emits raw syscalls (`mmap`, `pipe2`, `execve`, sockets);
  WSL1's syscall emulation can choke. WSL2 runs a real kernel.
- **Arch on WSL2** for parity with agent-l (pacman, same `gcc`/paths).
- **USB → WSL2** needs `usbipd-win` to attach a YubiKey for live detection; the "no key"
  path works without it. WSL2 clock can drift — relevant to TOTP.
- krypton binaries are **static, syscall-only ELF** — they run on any WSL2 kernel regardless
  of distro; distro only affects the build toolchain + tools apps shell out to.
