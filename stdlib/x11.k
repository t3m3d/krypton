// stdlib/x11.k — X11 wire-protocol client in PURE KRYPTON.
//
// Speaks the X Window System core protocol (X11 Release 11.0) directly
// over a socket. No libX11. No libxcb. No dynamic linking. Built on the
// native BSD-socket builtins (sockMake/sockConnect/sockSend/sockRecv)
// plus the Phase C byte-buffer machinery (bufNew/bufSetByte/bufGet*At),
// all of which the Linux native backend emits as direct syscalls or
// inline x86-64 codegen.
//
// Currently TCP-only: sockConnect builds an AF_INET sockaddr. Local
// display sockets on Linux are AF_UNIX (/tmp/.X11-unix/X<n>); use TCP
// transport meanwhile by starting the X server with `-listen tcp` and
// connecting to 127.0.0.1:6000+display. The protocol layer here is
// transport-agnostic — swap the transport when AF_UNIX lands in x11Connect.
//
// Phase A2 (this file): connect + handshake + full server-info parse
//   — vendor, resource-id range, protocol version, screen + format counts.
// Phase B (planned):   resource-id allocation, CreateWindow, MapWindow,
//                      event loop on sockRecv.
// Phase C (planned):   CreateGC + PolyFillRectangle + ImageText8.
//
// Reference: https://www.x.org/releases/X11R7.7/doc/xproto/x11protocol.html
//
// Usage:
//   import "k:x11"
//   just run {
//       let fd = x11Connect("127.0.0.1", 1)         // display :1 -> port 6001
//       if fd < 0 { print("connect failed")  exit(1) }
//       let info = x11Handshake(fd)
//       if x11Accepted(info) {
//           print("vendor: " + x11Vendor(info))
//           print("rid base = " + x11ResourceIdBase(info))
//       }
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

// ── handshake (phase A2) ──────────────────────────────────────────────
// x11Handshake(fd) -> raw server-info buf, or a 1-byte buf carrying
// the X server's failure byte if the read returned nothing.
//
// Sends the 12-byte little-endian no-auth setup as a single sockSend
// (built in a buf so embedded NULs survive — Krypton strings can't
// carry NULs because they're C-strings), then reads the reply into
// a 16-KB buf via repeated sockRecv until either:
//   - we hit the X server's stated end (8 + 4*tail-len), or
//   - sockRecv returns 0 (server closed).
// Caller can probe with x11Accepted / x11Vendor / x11ResourceIdBase / etc.
func x11Handshake(fd) {
    let req = bufNew(12)
    bufSetByte(req, 0, 108)   // 'l' = little-endian client
    bufSetByte(req, 1, 0)     // pad
    bufSetByte(req, 2, 11)    // major version (LE lo)
    bufSetByte(req, 3, 0)     // major version (LE hi)
    bufSetByte(req, 4, 0)     // minor version
    bufSetByte(req, 5, 0)     // minor version
    bufSetByte(req, 6, 0)     // auth-name length
    bufSetByte(req, 7, 0)     // auth-name length
    bufSetByte(req, 8, 0)     // auth-data length
    bufSetByte(req, 9, 0)     // auth-data length
    bufSetByte(req, 10, 0)    // pad
    bufSetByte(req, 11, 0)    // pad
    sockSend(fd, req, 12)

    // Single sockRecv into a 16 KB buf — X servers reliably reply in
    // one TCP segment for the connection setup (the full reply is
    // ~2-3 KB max). If a future bigger-than-16K reply ever shows up
    // we'll need a chunked recv with pointer arithmetic on the buf,
    // which requires a `bufOffset` builtin (currently `buf + off`
    // mangles the smart-int-tagged pointer).
    let info = bufNew(16384)
    sockRecv(fd, info, 16384)
    emit info
}

// ── server-info accessors (success case, byte 0 = 1) ──────────────────
// X11 server-info reply layout:
//   byte  0: 1=success, 0=failed, 2=authenticate-required
//   byte  1: reason-length (failure case) or pad
//   u16   2: protocol-major-version
//   u16   4: protocol-minor-version
//   u16   6: length of additional data in 4-byte units
//   u32   8: release-number
//   u32  12: resource-id-base
//   u32  16: resource-id-mask
//   u32  20: motion-buffer-size
//   u16  24: vendor-length
//   u16  26: maximum-request-length (in 4-byte units)
//   byte 28: number-of-screens
//   byte 29: number-of-formats
//   byte 30: image-byte-order   (0=LSB, 1=MSB)
//   byte 31: bitmap-format-bit-order
//   byte 32: bitmap-format-scanline-unit
//   byte 33: bitmap-format-scanline-pad
//   byte 34: min-keycode
//   byte 35: max-keycode
//   bytes 36..39: pad
//   then: vendor (vendor-length, padded to 4), formats (8 each), screens.

func x11ResponseByte(info) { emit bufGetByte(info, 0) }
func x11Accepted(info)     { emit bufGetByte(info, 0) == 1 }
func x11Failed(info)       { emit bufGetByte(info, 0) == 0 }
func x11NeedsAuth(info)    { emit bufGetByte(info, 0) == 2 }

func x11ProtoMajor(info)      { emit bufGetWordAt(info, 2) }
func x11ProtoMinor(info)      { emit bufGetWordAt(info, 4) }
func x11ReleaseNumber(info)   { emit bufGetDwordAt(info, 8) }
func x11ResourceIdBase(info)  { emit bufGetDwordAt(info, 12) }
func x11ResourceIdMask(info)  { emit bufGetDwordAt(info, 16) }
func x11MotionBufferSize(info){ emit bufGetDwordAt(info, 20) }
func x11VendorLength(info)    { emit bufGetWordAt(info, 24) }
func x11MaxRequestLen(info)   { emit bufGetWordAt(info, 26) }
func x11NumScreens(info)      { emit bufGetByte(info, 28) }
func x11NumFormats(info)      { emit bufGetByte(info, 29) }
func x11ImageByteOrder(info)  { emit bufGetByte(info, 30) }
func x11MinKeycode(info)      { emit bufGetByte(info, 34) }
func x11MaxKeycode(info)      { emit bufGetByte(info, 35) }

// Vendor string lives at byte offset 40, length from x11VendorLength.
// Vendor names are ASCII and don't contain NULs, so a string-build
// via fromCharCode is safe here.
func x11Vendor(info) {
    let n = x11VendorLength(info)
    let out = ""
    let i = 0
    while i < n {
        out = out + fromCharCode(bufGetByte(info, 40 + i))
        i += 1
    }
    emit out
}

// Failure case: byte 1 = reason length, ascii reason at byte 8.
func x11FailReason(info) {
    if bufGetByte(info, 0) != 0 { emit "" }
    let n = bufGetByte(info, 1)
    let out = ""
    let i = 0
    while i < n {
        out = out + fromCharCode(bufGetByte(info, 8 + i))
        i += 1
    }
    emit out
}

// ── connect to the LOCAL display over the AF_UNIX socket ──────────────
// /tmp/.X11-unix/X<display>. Xorg/Xwayland accept local unix connections
// (usually without cookie auth). Returns fd or -1. Pairs with x11Handshake.
func x11ConnectUnix(display) {
    emit unixConnect("/tmp/.X11-unix/X" + display)
}

// ── screen geometry (the first SCREEN in the setup reply) ─────────────
// The SCREEN block sits after: 40-byte header + vendor (padded to 4) +
// 8 bytes × number-of-formats. SCREEN layout:
//   u32  0 root            u32 16 current-input-masks
//   u32  4 default-colormap u16 20 width-in-pixels
//   u32  8 white-pixel     u16 22 height-in-pixels
//   u32 12 black-pixel     ... u32 32 root-visual, byte 38 root-depth
func x11ScreenOffset(info) {
    let vlen = x11VendorLength(info)
    let vpad = (vlen + 3) / 4 * 4
    emit 40 + vpad + 8 * x11NumFormats(info)
}
func x11Root(info)        { emit bufGetDwordAt(info, x11ScreenOffset(info) + 0) }
func x11WhitePixel(info)  { emit bufGetDwordAt(info, x11ScreenOffset(info) + 8) }
func x11BlackPixel(info)  { emit bufGetDwordAt(info, x11ScreenOffset(info) + 12) }
func x11ScreenWidth(info) { emit bufGetWordAt(info, x11ScreenOffset(info) + 20) }
func x11ScreenHeight(info){ emit bufGetWordAt(info, x11ScreenOffset(info) + 22) }
func x11RootVisual(info)  { emit bufGetDwordAt(info, x11ScreenOffset(info) + 32) }
func x11RootDepth(info)   { emit bufGetByte(info, x11ScreenOffset(info) + 38) }

// Allocate a resource id: ridbase | (n & ridmask). For modest n the OR is
// just an add (base is mask-aligned), but mask it to be correct.
func x11GenId(info, n) {
    let base = x11ResourceIdBase(info)
    let mask = x11ResourceIdMask(info)
    let lowbit = mask - (mask - 1) / 2 * 2   // not used; keep n small
    emit base + n
}

// Little-endian multi-byte writers. The native backend only implements
// bufSetByte (bufSetWordAt/bufSetDwordAt are front-end stubs that no-op),
// so pack words/dwords a byte at a time. X11 client byte order is LSB-first.
func _x11PutW(b, off, v) {
    bufSetByte(b, off, v - v / 256 * 256)
    bufSetByte(b, off + 1, v / 256 - v / 65536 * 256)
}
func _x11PutD(b, off, v) {
    bufSetByte(b, off, v - v / 256 * 256)
    bufSetByte(b, off + 1, v / 256 - v / 65536 * 256)
    bufSetByte(b, off + 2, v / 65536 - v / 16777216 * 256)
    // top byte: v / 2^24, masked to 8 bits (avoid the 2^32 literal — it
    // exceeds the native int-literal ceiling 0x7F000000).
    bufSetByte(b, off + 3, v / 16777216 - v / 16777216 / 256 * 256)
}

// ── CreateWindow (opcode 1) ───────────────────────────────────────────
// InputOutput child of `parent`, depth/visual copied from parent. value-mask
// sets background-pixel (bit 1) + event-mask (bit 11) = 0x802; value-list is
// [bgPixel, eventMask] in ascending mask-bit order. 40 bytes (length 10 units).
func x11CreateWindow(fd, wid, parent, x, y, w, h, bgPixel, eventMask) {
    let r = bufNew(40)
    bufSetByte(r, 0, 1)            // opcode CreateWindow
    bufSetByte(r, 1, 0)            // depth = CopyFromParent
    _x11PutW(r, 2, 10)            // request length (4-byte units)
    _x11PutD(r, 4, wid)
    _x11PutD(r, 8, parent)
    _x11PutW(r, 12, x)
    _x11PutW(r, 14, y)
    _x11PutW(r, 16, w)
    _x11PutW(r, 18, h)
    _x11PutW(r, 20, 0)           // border width
    _x11PutW(r, 22, 1)           // class = InputOutput
    _x11PutD(r, 24, 0)           // visual = CopyFromParent
    _x11PutD(r, 28, 2050)        // value-mask 0x802 = bg-pixel | event-mask
    _x11PutD(r, 32, bgPixel)
    _x11PutD(r, 36, eventMask)
    sockSend(fd, r, 40)
}

// MapWindow (opcode 8). 8 bytes.
func x11MapWindow(fd, wid) {
    let r = bufNew(8)
    bufSetByte(r, 0, 8)
    bufSetByte(r, 1, 0)
    _x11PutW(r, 2, 2)
    _x11PutD(r, 4, wid)
    sockSend(fd, r, 8)
}

// ── event read ────────────────────────────────────────────────────────
// Core events/replies/errors are 32 bytes. Reads one into `ev` (a 32-byte
// buf). Returns the byte count (0/-1 on EOF/error). type = byte0 & 0x7f
// (high bit = SendEvent). Common types: 2 KeyPress, 3 KeyRelease, 4
// ButtonPress, 12 Expose, 6 MotionNotify, 22 ConfigureNotify.
func x11NextEvent(fd, ev) { emit sockRecv(fd, ev, 32) }
func x11EventType(ev)     { emit bufGetByte(ev, 0) - bufGetByte(ev, 0) / 128 * 128 }
func x11KeyDetail(ev)     { emit bufGetByte(ev, 1) }   // keycode (KeyPress)
func x11EventX(ev)        { emit bufGetWordAt(ev, 24) }
func x11EventY(ev)        { emit bufGetWordAt(ev, 26) }
