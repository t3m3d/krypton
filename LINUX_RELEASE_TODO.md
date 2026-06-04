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
- [x] **Milestone 5 (done):** user functions + recursion (call frames on sp, CALL=bl,
      per-fn locals, CAT, int threshold→0x7F000000). factorial/fib recursion, nested
      calls, 3-arg fns; fibonacci/factorial/fizzbuzz byte-identical to kcc.sh. Commits
      aa566dc7, ba08a05f.
- [ ] **Known bugs (next):**
      1. **kp leaks +16/op** — x86 backend (elf_host) miscompiles the kp handler (dupes
         an `add x20`); arm64 source verified correct by bisection. Print-heavy programs
         (100s of lines) drift x20 off the op stack and crash. Likely fixed when the x86
         backend is fixed, or by a StringBuilder rewrite of this file.
      2. **Backend crashes on ~1000+ op programs** — naive `code = code + ...` is O(n^2);
         rewrite with sbAppend (like x86 elf.k).
      3. **Missing stdlib builtins** — substring/charCode/len/toInt/range/split/trim/...
         Most example programs need these (the "make programs work" track, M6).
- [ ] Then: negative literals (movn), MOVK for the op-stack region, `kcc.sh --native`
      auto-using this backend on aarch64.

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

**STATUS 2026-06-03: greenfield closed.** Every item below shipped; remaining
agent-w work is queued under `kryoterm` phases 1-3 in its own repo, all of
which are blocked waiting on agent-l (x11.k Phase B/C + forkpty).

- [x] **`stdlib/x11.k` Phase A1 + A2** — connect, 12-byte handshake, full
      server-info parse on top of agent-l's `bufNew`/`bufSetByte`/`bufGet*At`.
      Verified end-to-end against Xvfb on Arch/WSL2. Commits `635958b4` +
      `fad4a878`. **Phase B+ reassigned to agent-l** (deeper Linux syscall
      surface lives there).
- [x] **App repo Linux ports** — all three sibling repos shipped:
      - `kryofetch` — `run_linux.k` + `build_linux.sh` + Arch `PKGBUILD`
        (commits `4fb897f`, `36d40c7` in `t3m3d/kryofetch`)
      - `terk` — `build_linux.sh` + `BUILD_LINUX.md` + Arch `PKGBUILD`
        (commits `a26e8e5`, `f4f3eca` in `t3m3d/terk`)
      - `yubikrypt` — Arch `PKGBUILD`; macOS frontend reused verbatim on Linux
        (commits `edfc5c9`, `e98a534` in `t3m3d/yubikrypt`)
      - **(new)** `kryoterm` — pure-Krypton terminal sibling repo, phase 0
        stub (spawn child + echo stdout) shipped as 4126 B static ELF.
        Phases 1-3 blocked on x11.k Phase B/C + forkpty (agent-l).
- [x] **`tests/run_linux.sh`** — real test runner. Iterates `tests/*.k`,
      classifies PASS / FAIL (timeout, signal-death, non-zero exit, `[FAIL]`
      markers) / SKIP. Exits non-zero on any failure.
- [x] **`.github/workflows/linux.yml`** — CI on `ubuntu-latest`, bootstraps
      via `build.sh`, runs `tests/run_linux.sh`. Commit `b4a1b71e`.
- [x] **Arch packaging** — all four PKGBUILDs above. `.gitattributes` pinning
      `*.sh`/`*.k`/`*.ks`/`PKGBUILD` to LF in every sibling repo so Windows
      tooling can't CRLF-break shebang lines on Linux.

## agent-w — bonus stdlib shipped (NEW files, beyond the original TODO)

- [x] **`stdlib/arch.k`** — host CPU detection (`x86_64`/`arm64`/`x86`/
      `armv7`/`unknown`), `isArm/isX86/is64Bit`. Layered detection via
      `/proc/sys/kernel/arch` → `PROCESSOR_ARCHITECTURE` → `HOSTTYPE` →
      `CPUTYPE`. Skips `shellRun` (inherits stdio on Linux, doesn't capture).
- [x] **`kcc.ks --print-arch`** + arch-aware backend auto-routing in the
      KryptScript driver. Commit `77ce6f62`. `--arm64` / `--x64` flags
      override auto-detection.
- [x] **`stdlib/color.k`** — hex ↔ rgb ↔ hsl + lighten/darken/mix.
- [x] **`stdlib/mime.k`** — ~50-entry MIME lookup by ext or path.
- [x] **`stdlib/cookie.k`** — `Cookie:` parse + `Set-Cookie:` build with attrs.
- [x] **`tests/smoke_new_stdlib.k`** — 21/21 PASS for color/mime/cookie.
- [x] **`examples/arch_info.k`** — `k:arch` demo example. Commit `7dd1413b`.
- [x] **Site updates** — programs page (kryofetch / yubikrypt / kryoterm
      cards), system-following light/dark theme, hero typing-anim fix,
      WASM particle theming via `themedRGB()`, sponsor slot stub for
      thepeoplewire.com, `PAGES.md` rendering-layer inventory.

## agent-w — deferred (filed for future)

- **`stdlib/uuid.k`** — attempted, deferred. Krypton's `random()` returns 0
  on Linux (no entropy primitive wired through); `rdtsc`/`timestamp` exceed
  the 0x7F000000 smart-int ceiling and get re-tagged as pointers, breaking
  the modulo math. Coming back once agent-l ships a small-int entropy
  primitive (or once the int ceiling is raised again).

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
