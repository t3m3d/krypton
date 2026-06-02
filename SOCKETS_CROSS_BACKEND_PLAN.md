# Cross-backend socket builtins — plan to make C optional on all platforms

Goal: `stdlib/server_native.k` (pure-Krypton HTTP server) works on macOS,
Windows, and Linux, so **no platform needs C to serve**. C stays available
(`--gcc` / `k:server` cfunc) for parity/status, but is never required.

The server needs 8 socket builtins. Each native backend must emit them.
macOS is done; Windows + Linux are the remaining work.

| builtin              | args                | returns        |
|----------------------|---------------------|----------------|
| `sockMake()`         | —                   | listen/conn fd |
| `sockBind(fd,hi,lo)` | fd, port hi byte, lo byte (big-endian, split in Krypton) | 0/err |
| `sockListen(fd,bk)`  | fd, backlog         | 0/err          |
| `sockAccept(fd)`     | fd                  | client fd / -1 |
| `sockRecvStr(fd)`    | fd                  | request string (recv into heap buf, NUL-term) |
| `sockSend(fd,buf,n)` | fd, string, len     | nbytes         |
| `sockClose(fd)`      | fd                  | 0/err          |
| `sockRecv(fd,b,n)`   | fd, buf, len        | nbytes (raw; sockRecvStr is the one server_native uses) |

`sockBind` takes the port pre-split into big-endian bytes (`hi=port/256`,
`lo=port-hi*256`) so backends don't need shift ops in hand-asm. It builds a
16-byte `sockaddr_in`: `[len=16][fam=2][port hi][port lo][4-byte addr=0][8 zero]`
(on Linux the sin_len byte is unused/0 — see notes).

Each builtin is added in THREE places (learned the hard way — half = SIGILL):
1. `compiler/compile.k` — the `builtins` list (~line 4199) so the IR emits
   `BUILTIN sockX`, not `CALL sockX`. **Then rebuild the frontend seed.**
2. The backend's instruction-count table (offset resolution; count MUST equal
   the emit exactly).
3. The backend's emit block.

---

## macOS — DONE (compiler/macos_arm64/macho_arm64_self.k)

Inline arm64 syscalls via `svc #0x80`, syscall nr in **x16**, args x0-x5.
macOS BSD numbers (no class bit needed — bare works, matches readFile):
socket=97 bind=104 listen=106 accept=30 recvfrom=29 sendto/write=4 close=6.
sockaddr_in: sin_len=16, sin_family=2, port big-endian, INADDR_ANY.
Verified: full HTTP server serves, zero C. (commits d920a307, 62c1d736,
b4251e41, 4a8b33c3). server_native.k verified serving HTML/JSON/query.

---

## Linux — TODO (Agent L) — compiler/linux_x86/elf.k (x86-64)

**KEY DIFFERENCE:** elf.k's existing builtins do NOT inline syscalls — they
`CALL kr_*` C-runtime helpers (e.g. `BUILTIN_READFILE` = `POP RDI; CALL
kr_readfile; PUSH RAX`). Those kr_* functions are C, compiled by gcc/clang.
So elf.k is NOT syscall-inline today; its readFile/print/etc still route
through a C runtime.

Two paths for L:
- **(A) Inline syscalls** (macOS approach): emit `syscall` (`0F 05`) directly
  for the socket ops. nr in **RAX**, args **RDI, RSI, RDX, R10, R8, R9**.
  x86-64 Linux numbers: socket=41 bind=49 listen=50 accept=43 recvfrom=45
  sendto/write=1 close=3 setsockopt=54. sockaddr_in: NO sin_len byte —
  offset 0 is `sin_family` (u16, =2 AF_INET), offset 2 = port (BE), offset 4
  = addr. So the 16-byte struct is `[fam lo=2][fam hi=0][port hi][port lo]
  [4 addr=0][8 zero]`. (Differs from macOS which has the sin_len byte.)
  This makes the socket path C-free even though the rest of elf.k still uses
  kr_* C helpers — partial win, but enough for server_native to serve.
- **(B) Full kr_* runtime in Krypton** — bigger: rewrite the whole C runtime
  (kr_readfile, kr_print, _alloc, ...) as Krypton/syscalls. That's the path to
  elf.k being fully clang-free, not just sockets. Much larger; separate effort.

For "Linux can serve C-free", **path A** is the target: add the 8 socket
builtins as inline `syscall` emits. Mirror BUILTIN_READFILE's structure but
replace `CALL kr_readfile` with the `syscall` sequence.

elf.k count-table is ~line 3126 (`if op == "BUILTIN_X" { emit N }`); the
emit block is the matching `opTok ==` chain. Same 3-edit discipline.

NOTE: there's a known elf.k self-host bug at >66 funcs (per kcc.sh comment /
bootstrap notes) — confirm the backend still builds after additions.

---

## Windows — TODO (Agent W) — compiler/windows_x86/x64.k (PE/COFF)

x64.k already calls Win32 via IAT (FindFirstFileA etc. in fs.k/gui.k). Sockets
= Winsock (`ws2_32.dll`), same IAT mechanism, NOT raw syscalls (Windows has no
stable syscall ABI). Steps:
- x64.k emits IAT imports for ws2_32: WSAStartup, socket, bind, listen, accept,
  recv, send, closesocket, htons.
- `WSAStartup(MAKEWORD(2,2), &wsadata)` MUST run once before any socket call
  (Windows-only; macOS/Linux skip it). Cleanest: have `sockMake` lazily call
  WSAStartup on first use, or add a `sockInit()` builtin server_native calls
  once.
- Win32 ABI marshalling: x64.k's existing int-arg/itoa-return convention
  (compileWin32IntArgs) applies. sockaddr_in same layout as Linux (no sin_len;
  family u16 at offset 0).
- Winsock fd is a SOCKET (unsigned), INVALID_SOCKET = ~0, not -1; adjust the
  `< 0` checks or have the builtin normalize to -1 on failure.

---

## What "C optional everywhere" depends on (the real checklist)

1. Socket builtins in all 3 backends — macOS ✅, Linux ⏳ (L), Windows ⏳ (W).
2. `server_native.k` already platform-agnostic at the Krypton level — once the
   builtins exist per backend, it serves everywhere unchanged.
3. Consumers (kweb, web/site/site.htk, examples) migrate `k:server` →
   `k:server_native` for C-free serving. (Cleanup, not a blocker.)
4. `k:server`'s cfunc + the `--gcc` path STAY (parity/status, per project goal
   "hold status with C"). The cfunc doesn't get deleted — it stops being
   *required*. server_native becomes the default native path.

Milestone = "no platform NEEDS C to serve" = step 1 done on all three backends.

---

## Open self-hosting bug (separate from sockets, found 2026-06-01)

The committed macho_host (clang-built) compiles compile.k fine (frontend can be
built native). But a macho_host **rebuilt by itself** (self-hosted, no clang)
SIGSEGVs (exit 139) when compiling compile.k. So the full clang-free *bootstrap*
of the frontend is blocked by a self-host regression in the macho backend, NOT
by sockets. Chase separately. Running compiled programs + serving is already
C-free; rebuilding the frontend from source still needs clang once until this
is fixed.

## Syscall ABI quick reference

| | macOS arm64 | Linux x86_64 | Windows x64 |
|-|-------------|--------------|-------------|
| mechanism | `svc #0x80` | `syscall` (0F 05) | IAT call (ws2_32.dll) |
| nr in | x16 | RAX | (named import) |
| args | x0-x5 | RDI,RSI,RDX,R10,R8,R9 | RCX,RDX,R8,R9 + stack |
| socket | 97 | 41 | WSASocket/socket |
| bind | 104 | 49 | bind |
| listen | 106 | 50 | listen |
| accept | 30 | 43 | accept |
| recv | 29 (recvfrom) | 45 (recvfrom) | recv |
| send | 4 (write) | 1 (write) | send |
| close | 6 | 3 | closesocket |
| sockaddr | has sin_len byte[0] | no sin_len (family@0) | no sin_len (family@0) |
| init | none | none | WSAStartup first |
