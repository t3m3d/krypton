# Make C optional on macOS (not required) — C-free sockets for the native backend
#
# Goal: Krypton runs WITHOUT any C compiler present. C stays available for
# parity/status (--gcc / --c), but is never NEEDED for .k/.ks to work.
macOS serves HTTP with **zero C** — by teaching `compiler/macos_arm64/
macho_arm64_self.k` to emit BSD socket syscalls directly, exactly as it
already emits open/read/write/close for `BUILTIN_READFILE`.

## Status: ABI VALIDATED

`docs/proto/macos_rawsocket_probe.c` does socket→bind→listen→accept→write→
close using **only** `svc #0x80` (no libc socket calls — libSystem is linked
only because macOS requires it for any executable; the backend hand-writes
its Mach-O and already handles that). Verified on macOS Tahoe arm64:

    $ ./sp2 &           # RAWSOCK ready
    $ curl localhost:8090   # -> hello rawsock

## Syscall ABI (what the backend must emit)

macOS arm64: syscall number in **x16**, args in **x0..x5**, trap = `svc #0x80`.
BSD syscalls take the class bit: **number = 0x2000000 | n**.

| call        | n   | full (0x2000000\|n) | args (x0,x1,x2,...)             | returns |
|-------------|-----|---------------------|----------------------------------|---------|
| socket      | 97  | 0x2000061           | domain=2(AF_INET), type=1(STREAM), proto=0 | fd |
| bind        | 104 | 0x2000068           | fd, &sockaddr, len=16            | 0/-1    |
| listen      | 106 | 0x200006A           | fd, backlog                      | 0/-1    |
| accept      | 30  | 0x200001E           | fd, &addr(or 0), &addrlen(or 0)  | client fd |
| recvfrom    | 29  | 0x200001D           | fd, buf, len, flags=0, 0, 0      | nbytes  |
| sendto/write| 4   | 0x2000004           | fd, buf, len                     | nbytes  |
| setsockopt  | 105 | 0x2000069           | fd, level, optname, &val, len    | 0/-1    |
| close       | 6   | 0x2000006           | fd                               | 0/-1    |

(The probe used `write`(4) on the client fd, not `sendto` — works fine for
blocking TCP and is simpler to emit. `recvfrom` with flags/addr = 0 reads.)

## sockaddr_in layout (16 bytes, what bind expects)

    offset 0 : uint8  sin_len   = 16
    offset 1 : uint8  sin_family= 2   (AF_INET)
    offset 2 : uint16 sin_port  = BIG-ENDIAN port  (e.g. 8080 -> 0x1F90 -> bytes 1F 90)
    offset 4 : uint32 sin_addr  = 0   (INADDR_ANY)
    offset 8 : uint8[8] zero

Port byte order: `(port>>8)|((port&0xff)<<8)` to get big-endian on a
little-endian machine, then store as the 16-bit field.

## Backend work (mirror BUILTIN_READFILE in macho_arm64_self.k)

Add builtins, each = a few `arm64_movz_x_imm` (args) + `arm64_movz_x_imm(16, SYSNO)`
+ `arm64_svc(0x80)` + push result:

- BUILTIN_SOCKET    (0 args -> fd on stack)        sysno via movz: 97, class bit via movk
- BUILTIN_BIND      (fd, port)  -> builds sockaddr in a scratch buffer, syscall 104
- BUILTIN_LISTEN    (fd, backlog) -> 106
- BUILTIN_ACCEPT    (fd) -> 30, push client fd
- BUILTIN_RECV      (fd, buf, len) -> 29 (flags/addr=0)
- BUILTIN_SEND      (fd, str) -> 4 (write), len computed
- BUILTIN_CLOSE     (fd) -> 6
- BUILTIN_SETSOCKOPT(fd, level, opt, val) -> 105  (for SO_REUSEADDR=4, level SOL_SOCKET=0xffff)

NOTE on the class bit: 0x2000000 | 97 = 0x2000061. movz can't load 0x2000061
in one op; use movz x16,#97 then movk x16,#0x200,lsl#16 (0x200<<16 = 0x2000000).
Confirm `arm64_movk` exists in the backend (arm64_movz_x_imm_lsl16 is already
used for the 1MB readFile buffer, so the lsl16 pattern is available).

## Then: rewrite stdlib/server.k

Replace the `cfunc{}` block + the `_srv*` C functions with pure-Krypton
wrappers over the new builtins. Keep the public API identical
(serverInit/serverNext/serverReqPath/serverRespond/...) so kweb + KSML and
the live site.htk don't change. Windows keeps its existing Winsock cfunc via
`#ifdef _WIN32` (don't touch the Windows path).

## Why this matters

server.k's cfunc is the ONE real C dependency left on macOS (the native
kcc-arm64 compiler is already C-free; fs/proc/winio/jsonrpc/gui are pure-
Krypton Win32 and Windows-only). Killing it = kweb/KSML serve on macOS with
no clang in the loop, and `--gcc` becomes truly optional on Mac.
