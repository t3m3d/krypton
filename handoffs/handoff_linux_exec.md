# Handoff — implement `exec`/`shellRun` on the Linux native backend (Agent L → next)

## Status (2026-06-02, after the merge + parity work)

The Linux native backend (`compiler/linux_x86/elf.k`) now has, all C-free / inline syscalls:
- **sockets**: sockMake/Bind/Listen/Accept/Recv/Send/Close/RecvStr/**Connect** — `k:server_native`
  and `examples/ks/miniserver.ks` serve HTTP, and `k:httpc` can connect. Verified.
- **readProc(path)**: reads `/proc` & `/sys` virtual files (fixed `readFile` returning empty on them).
- **environ(name)**: reads env vars (envp saved at `[R14+16]` in `_start`). kryofetch uses it.

**Still unimplemented (no-op, return their argument verbatim — NOT a crash):**
`exec`, `shellRun`. This is the LAST gap blocking the Krypton-native driver path on Linux.

## Why exec matters

`kcc.ks` (the KryptScript driver replacing `kcc.sh`) and the scripting batteries
`k:sh` / `k:env` / `k:fsx` are **`exec`-based** (e.g. `env.k` calls `exec`, not the
`environ` builtin; `fsx.k` shells out 16×). Until `exec` works on the Linux native
backend, those modules and `kcc.ks` can't drive anything here — so **`kcc.sh` remains
Linux's operational driver**. macOS has `exec` (via its backend), which is why `kcc.ks`
is "macOS-wired-only" today. Implementing `exec` on Linux unblocks full parity.

(Note: `environ` is implemented as a builtin, but `k:env` wraps `exec("printenv ...")`,
not the builtin — so `k:env` still needs `exec`. Either implement `exec`, or separately
rewrite `k:env` to call the `environ()` builtin. The former is the general fix.)

## Why I did NOT hand-assemble it unattended

`exec(cmd)` = run `/bin/sh -c cmd`, capture stdout, return it. The only mechanism without
libc is raw `pipe2`+`fork`+`dup2`+`execve`+`read`-loop+`wait4`. That's ~150–200 bytes of
intricate machine code with TWO control-flow paths (parent/child) sharing one code stream,
plus on-stack `argv` construction. A subtle bug risks zombie processes or a **fork-bomb**,
and it ships in a committed binary seed used by every machine. This needs supervised,
iterative testing — not an overnight one-shot. Everything else this session was additive
and independently verifiable; `exec` is categorically riskier.

## Implementation plan (x86-64 Linux)

Add `BUILTIN_EXEC` (and route `shellRun` to it, or a variant) with the standard 3 edits
in `elf.k` — name→op map (~line 3390), `opByteSize` count table (~line 3130, MUST equal
emit exactly), emit block in `emitFuncCode` (~line 4096). Mirror the inline-syscall style
of the socket builtins. `exec` is in `compile.k`'s builtins list already, so NO frontend
rebuild is needed (just rebuild `elf_host` + refresh `bootstrap/elf_host_linux_x86_64`).

Syscall numbers (x86-64): `pipe2`=293, `fork`=57, `dup2`=33, `execve`=59, `close`=3,
`read`=0, `wait4`=61, `exit`=60. envp is at `[R14+16]` (added for `environ`).

Sketch (TOS = cmd ptr in RDI after `pop rdi`):
```
  ; save cmd; make pipe (pipefd on stack)
  sub rsp,16 ; lea rdi,[rsp] ; xor esi,esi ; mov eax,293 ; syscall   ; pipe2(&pf,0)
  ; pf[0]=read @ [rsp], pf[1]=write @ [rsp+4]
  mov eax,57 ; syscall                                                ; fork
  test rax,rax ; jnz .parent
  ; ---- child ----
  mov edi,[rsp+4] ; mov esi,1 ; mov eax,33 ; syscall                  ; dup2(write,1)
  mov edi,[rsp]   ; mov eax,3 ; syscall                               ; close(read)
  mov edi,[rsp+4] ; mov eax,3 ; syscall                               ; close(write)
  ; build argv=[&"/bin/sh", &"-c", cmd, NULL] on the stack:
  ;   mov rax, 0x0068732f6e69622f ; push rax   ; "/bin/sh\0"  -> rsp=&sh
  ;   mov rax, 0x000000000000632d ; push rax   ; "-c\0"       -> rsp=&dashc
  ;   push 0 ; push cmd ; push &dashc ; push &sh   (argv contiguous, rsp=&argv[0])
  ; (track the two string addresses; alignment/order matter — argv must be contiguous)
  mov rdi,&"/bin/sh" ; mov rsi,&argv ; mov rdx,[R14+16] ; mov eax,59 ; syscall  ; execve
  mov edi,127 ; mov eax,60 ; syscall                                  ; exit(127) if execve fails
  ; ---- parent ----  (rax = child pid)
.parent:
  ; close write end; kr_alloc 256KB buf; read-loop [read end -> buf] until 0;
  ; wait4(pid,0,0,0); close read end; NUL-terminate; add rsp,16; return buf
```
Register budget: R14/R15 are RESERVED (globals/heap). kr_alloc preserves all but RAX/R15/RDI.
`syscall` clobbers RCX/R11. You have RBX/R12/R13 as callee-saved scratch (3) + the stack.
Mirror `readProc`'s read-loop (already in elf.k) for the parent's capture side.

## Verification gates (do ALL before committing)
1. `exec("echo hi")` -> `"hi\n"`; `exec("printf abc")` -> `"abc"`.
2. No zombies: run a loop of 100 `exec` calls, check `ps` shows no `<defunct>` children.
3. Empty/var output, command-not-found (sh prints to stderr, stdout empty -> "").
4. `./build.sh test` 55/0; rebuild `elf_host`; self-build still clean.
5. Then `k:sh`/`k:env`/`k:fsx` and `kcc.ks` Linux branch can be wired (see kcc.ks `findRoot`/
   the `os != "Darwin"` stub — replace with a Linux native path mirroring `compileMacos`).

Files: `compiler/linux_x86/elf.k` (+ rebuild `elf_host`, refresh `bootstrap/elf_host_linux_x86_64`).
Memory: see `~/.claude/.../memory/krypton-kcc-and-seed-gotchas.md` for backend conventions.
