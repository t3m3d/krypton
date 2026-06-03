// stdlib/x11.k — X11 wire-protocol client in PURE KRYPTON.
//
// Speaks the X Window System core protocol (X11 Release 11.0) directly
// over a socket. No libX11. No libxcb. No dynamic linking. Built on the
// native BSD-socket builtins (sockMake/sockConnect/sockSend/sockRecvStr)
// that the Linux + macOS native backends emit as direct syscalls.
//
// Currently TCP-only: sockConnect builds an AF_INET sockaddr. Local
// display sockets on Linux are AF_UNIX (/tmp/.X11-unix/X<n>); use TCP
// transport meanwhile by starting the X server with `-listen tcp` and
// connecting to 127.0.0.1:6000+display. The protocol layer here is
// transport-agnostic — swap the transport when AF_UNIX lands.
//
// ── BLOCKERS ─────────────────────────────────────────────────────────
// Phase A1 (this file): connect + 12-byte handshake + accept byte.
//   Demonstrates the wire protocol works end-to-end against a real
//   X server (proven against Xorg/Xvfb on Arch on WSL2 2026-06-02).
//
// Phase A2 (BLOCKED — needs agent-l): parse full server-info reply.
//   Blocked on Linux because:
//     (1) elf.k has no bufNew/bufSetByte/bufGet*At builtins (those
//         are the Phase C typed-pointer machinery shipped in x64.k
//         but never ported). We need them so received bytes can be
//         held in a real byte buffer rather than a Krypton string.
//     (2) Krypton strings are C-strings: len(s) is strlen(s) and
//         stops at the first NUL. Every X11 reply contains NUL pad
//         bytes at offset 1, 3, 5, 7, etc. — making len() useless.
//         String concat also drops bytes after the first NUL.
//   Even byte-by-byte sockSend with the `sockSend(fd, "", 1)` NUL
//   trick can't rebuild a parseable response because all the byte-
//   access primitives we'd combine into one work off len() too.
//
//   Listed in LINUX_RELEASE_TODO.md under "Needed from agent-l":
//   port bufNew/bufSetByte/bufGetByte/bufGetWordAt/bufGetDwordAt
//   from x64.k Phase C to elf.k. Once that lands, this file can
//   ship Phase A2 (full server info), Phase B (windows), and
//   Phase C (drawing) without further Linux-side workarounds.
//
// Phase B / C: planned, see header comment in tests/x11_*.k.
//
// Reference: https://www.x.org/releases/X11R7.7/doc/xproto/x11protocol.html
//
// Usage (today, phase A1):
//   import "k:x11"
//   just run {
//       let fd = x11Connect("127.0.0.1", 1)
//       if fd < 0 { print("connect failed")  exit(1) }
//       let r = x11Handshake(fd)
//       if r == 1 { print("accepted") }
//       sockClose(fd)
//   }

module x11

// ── transport ─────────────────────────────────────────────────────────
// x11Connect(host, display) -> socket fd, or -1.
// host is "a.b.c.d" (loopback typically); display is the X display
// number (e.g. 1 for :1). TCP port = 6000 + display.
func x11Connect(host, display) {
    let fd = sockMake()
    if fd < 0 { emit 0 - 1 }
    let a = _ipOctet(host, 0)
    let b = _ipOctet(host, 1)
    let c = _ipOctet(host, 2)
    let d = _ipOctet(host, 3)
    let port = 6000 + display
    let hi = port / 256
    let lo = port - (hi * 256)
    let rc = sockConnect(fd, a, b, c, d, hi, lo)
    if rc < 0 { sockClose(fd)  emit 0 - 1 }
    emit fd
}

// Hand-rolled splitter — Linux krypton's split() returns the input
// string unchanged as of 2026-06-02 (LINUX_RELEASE_TODO).
func _ipOctet(s, idx) {
    let rest = s
    let i = 0
    while i < idx {
        let dot = indexOf(rest, ".")
        if dot < 0 { emit 0 }
        rest = substring(rest, dot + 1, len(rest))
        i += 1
    }
    let dot = indexOf(rest, ".")
    if dot >= 0 { rest = substring(rest, 0, dot) }
    emit toInt(rest)
}

// ── handshake (phase A1) ──────────────────────────────────────────────
// Sends the 12-byte no-auth setup, reads the first chunk, returns
// the X server's response byte:
//   1 = success / accepted
//   0 = failed / refused
//   2 = authentication required (server wants xauth)
//  -1 = read returned nothing (socket closed before reply)
//
// We don't try to parse beyond the first byte — see the Phase A2
// blocker note at the top of this file. Once bufNew lands on Linux,
// x11Handshake will return a full info buffer and we'll add the
// x11Vendor / x11ResourceIdBase / etc. accessors back.
func x11Handshake(fd) {
    _sendSetup(fd)
    let reply = sockRecvStr(fd)
    if len(reply) == 0 { emit 0 - 1 }
    emit charCode(reply[0])
}

// ── 12-byte handshake send (byte-by-byte, NUL-safe) ───────────────────
// Krypton-on-Linux can't build a 12-byte string with embedded NULs
// (fromCharCode(0) returns ""), so we issue 12 individual sockSend
// calls. For non-NUL bytes use a 1-char string. For NUL bytes use
// sockSend(fd, "", 1) — write() ignores the C-string terminator and
// writes len=1 byte from the empty string's buffer (which is 0x00).
//
// Wire layout (X11 Release 11.0, no auth):
//   byte  0: 'l' = little-endian client
//   byte  1: 0   = pad
//   u16   2: 11  = protocol-major-version
//   u16   4: 0   = protocol-minor-version
//   u16   6: 0   = auth-name length
//   u16   8: 0   = auth-data length
//   u16  10: 0   = pad
func _sendSetup(fd) {
    sockSend(fd, "l", 1)                 // byte 0
    sockSend(fd, "", 1)                  // byte 1 (NUL pad)
    sockSend(fd, fromCharCode(11), 1)    // byte 2 (major lo = 11)
    sockSend(fd, "", 1)                  // byte 3 (major hi)
    sockSend(fd, "", 1)                  // byte 4 (minor lo)
    sockSend(fd, "", 1)                  // byte 5 (minor hi)
    sockSend(fd, "", 1)                  // byte 6 (auth-name lo)
    sockSend(fd, "", 1)                  // byte 7 (auth-name hi)
    sockSend(fd, "", 1)                  // byte 8 (auth-data lo)
    sockSend(fd, "", 1)                  // byte 9 (auth-data hi)
    sockSend(fd, "", 1)                  // byte 10 (pad)
    sockSend(fd, "", 1)                  // byte 11 (pad)
    emit 0
}
