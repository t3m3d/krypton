# Handoff — Agent L crashed mid-session → Arch Linux agent takes over

**Date:** 2026-06-02
**From:** Agent L (ParrotOS / Debian x86_64) — process crashed, OS instability
**To:** Arch Linux agent (same arch: x86_64 — every Linux native-backend note still applies)

## TL;DR

I crashed. No work was lost: everything I finished is already committed (branch
`main`, **9 commits ahead of `origin/main` — not yet pushed**). Nothing was left
half-written in the tree. The one remaining task is unchanged and fully specced.

## Repo state at crash

- Branch `main`, **9 commits ahead of origin** — `git push` to publish so you
  (on a different box) can pull them. If you're on THIS box, they're already local.
- Working tree clean except one **unrelated** stray: `krypton-lang/syntaxes`
  submodule pointer moved (`7f8d1047 → 44587efd`). Not mine, not part of the
  backend work — **leave it unstaged** unless you know why it moved.
- `./build.sh test` was green (55/0) at last run. Linux native backend done:
  sockets (Connect incl.), `readProc`, `environ` — all C-free inline syscalls.

## Your task: implement `exec` / `shellRun` on the Linux ELF backend

This is the LAST gap. It blocks `kcc.ks` + the exec-based `k:sh`/`k:env`/`k:fsx`
batteries on Linux, so `kcc.sh` stays the operational driver until it lands.

**Full plan, syscall numbers, register budget, asm sketch, and verification gates
are in `handoff_linux_exec.md` (repo root). Read that — it is complete.**

Key points carried over:
- File: `compiler/linux_x86/elf.k`. 3-edit discipline per builtin (name→op map,
  `opByteSize` count table MUST equal emit byte-for-byte, emit block). Skip one → SIGILL.
- `exec` already in `compile.k` builtins list → no frontend rebuild, just rebuild
  `elf_host` + refresh `bootstrap/elf_host_linux_x86_64`.
- **Why I didn't one-shot it:** `exec` = raw `pipe2`+`fork`+`dup2`+`execve`+`read`
  -loop+`wait4`, ~150–200 bytes, two control-flow paths in one stream. Bug risks
  zombies / fork-bomb, and it ships in a committed seed used by every machine.
  Needs supervised iterative testing — do NOT commit an elf.k change you haven't RUN
  (backend offset bugs surface as SIGILL/SIGSEGV at runtime, not compile time).

## Arch-specific install notes (differs from my Parrot/Debian guide)

`AGENT_L_LINUX_INSTALL.md` is Debian-worded (`apt`). On Arch:
- `sudo pacman -S --needed git base-devel` (gives `gcc` — needed only to rebuild
  `elf.k`, not to install; prebuilt x86_64 seed ships).
- Rest is identical: `git clone … && cd krypton && ./install.sh`, then
  `kcc.sh --version`. The one-time gcc elf-host bootstrap on first elf.k edit is
  the same (`kcc: rebuilding elf host (one-time gcc bootstrap...)`).

## Pointers

- `handoff_linux_exec.md` — the task (READ FIRST).
- `AGENT_L_LINUX_INSTALL.md` §6/§7 — backend status + builtin quirks (splitBy/lines
  broken, hex() returns decimal, use readProc not readFile for /proc, safe subset).
- `SOCKETS_CROSS_BACKEND_PLAN.md` — socket-builtin reference pattern to mirror.
- Memory `krypton-kcc-and-seed-gotchas.md` — kcc vs kcc.sh, stale-seed SIGSEGV,
  gcc-free install, broken native builtins.
