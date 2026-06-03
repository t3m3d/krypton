# Handoff — agent-w (Arch on WSL2): Linux greenfield tracks

You're parallelizing the Linux push with agent-l (native Arch). The full backlog +
ownership is in `LINUX_RELEASE_TODO.md`. This is your onboarding.

## The one rule

**Create NEW files only. Never edit an existing file in the krypton repo.**
agent-l owns every edit to existing files (especially `compiler/linux_x86/elf.k`,
the hand-assembled codegen — concurrent edits there = ugly conflicts). If a task
needs an existing-file change, add it to the "Needed from agent-l" list in
`LINUX_RELEASE_TODO.md` and stub/work around it. The sibling app repos
(`kryofetch`, `terk`, `yubikrypt`) are yours to edit freely.

`git pull --rebase` before every push — macOS/Windows/Linux agents all share `main`.

## Environment

- **Arch on WSL2** (you have it installed — use that, don't add a distro). WSL2, not WSL1.
- `sudo pacman -S --needed base-devel gcc git` and, for terk: `qt6-base cmake`.
- Build krypton: the repo's `kcc.sh` auto-bootstraps `elf_host` via gcc on first `--native`.
  Smoke test: `kcc.sh -r tests/test_int_ceiling.k` should print 8× `[PASS]`.
- Binaries are static syscall-only ELF — they run natively under WSL2.

## Your tracks (start top-down; first two have zero elf.k dependency)

1. **App ports** — dependency-free, do these first to validate your toolchain:
   - `kryofetch` repo: new `run_linux.k` + `build_linux.sh`, adapted from
     `krypton/contrib/linguist/samples/kryofetch/run_linux.k` (already works on Linux).
   - `terk` repo: build on WSL Arch. Qt6 + CMake; `platform/linux/PTYPlatform.cpp` exists.
     Produce a `BUILD_LINUX.md` / script. (terk is C++, not krypton — pure build task.)
   - `yubikrypt`: confirm it runs (`./yubikrypt once`) — already verified by agent-l.

2. **`tests/run_linux.sh`** — a NEW test runner that actually fails on segfaults/exit codes
   (the existing harness masks them). Compile+run each `tests/*.k`, assert rc==0, grep `[FAIL]`.

3. **`stdlib/x11.k` — pure-Krypton X11 client over a socket** (the flagship: a Linux GUI
   frontend with no dynamic linking, built on the existing `sock*` builtins). Speak the X11
   wire protocol: connect → handshake → `CreateWindow` → `MapWindow` → draw.
   **Transport:** local display sockets are `AF_UNIX`, but `sockConnect` is currently
   `AF_INET`/TCP. Two options: (a) prototype against TCP if your X server listens
   (`127.0.0.1:6000+N`); (b) file the `AF_UNIX` connect need for agent-l and build the
   protocol layer against a captured byte stream meanwhile. Wayland is `AF_UNIX`-only.

4. **Arch packaging** — `PKGBUILD`s for the apps.

## Coordination

- Status + cross-deps live in `LINUX_RELEASE_TODO.md` — keep it current.
- Don't touch `elf.k`, `kcc.sh`, or any existing compiler/stdlib file. New files only.
