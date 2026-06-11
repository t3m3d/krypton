// wayland.k — native Wayland client over the raw wire protocol, pure Krypton.
// Companion to stdlib/x11.k. No libwayland. Talks the wl wire format directly
// over the $WAYLAND_DISPLAY unix socket (unixConnect, same as X11).
//
// Wire format (little-endian): every message is
//   [0..3] object id (u32)
//   [4..5] opcode    (u16)
//   [6..7] size      (u16, total bytes incl. this 8-byte header)
//   [8..]  arguments
// Arg types: uint/int/new_id/object = 4 bytes; string = u32 length (incl
// trailing NUL) then the bytes, padded up to a 4-byte boundary; fd is passed
// out-of-band via SCM_RIGHTS (sockSendFd), never in the byte stream.
//
// Writes pack bytes one at a time (bufSetWordAt/bufSetDwordAt are no-op stubs
// in the Linux backend — see krypton-linux-native-bugs); reads use the
// implemented bufGet*At LE getters.

// ── little-endian byte packing (writes) ─────────────────────────────────
func _wlPutU32(buf, off, v) {
    bufSetByte(buf, off, v - v / 256 * 256)
    let b1 = v / 256
    bufSetByte(buf, off + 1, b1 - b1 / 256 * 256)
    let b2 = v / 65536
    bufSetByte(buf, off + 2, b2 - b2 / 256 * 256)
    let b3 = v / 16777216
    bufSetByte(buf, off + 3, b3 - b3 / 256 * 256)
}
func _wlPutU16(buf, off, v) {
    bufSetByte(buf, off,     v - v / 256 * 256)
    bufSetByte(buf, off + 1, v / 256 - v / 65536 * 256)
}
// round a byte length up to the next 4-byte boundary
func _wlPad4(n) {
    let p = n
    while p - p / 4 * 4 != 0 { p += 1 }
    emit p
}

// ── connect ──────────────────────────────────────────────────────────────
func wlSockPath() {
    let disp = environ("WAYLAND_DISPLAY")
    if disp == "" { disp = "wayland-0" }
    if len(disp) > 0 && disp[0] == "/" { emit disp }
    let dir = environ("XDG_RUNTIME_DIR")
    if dir == "" { dir = "/run/user/1000" }
    emit dir + "/" + disp
}
func wlConnect() { emit unixConnect(wlSockPath()) }

// ── requests ───────────────────────────────────────────────────────────────
// wl_display(1).get_registry(opcode 1): new_id registry.
func wlGetRegistry(fd, registryId) {
    let m = bufNew(12)
    _wlPutU32(m, 0, 1)
    _wlPutU16(m, 4, 1)
    _wlPutU16(m, 6, 12)
    _wlPutU32(m, 8, registryId)
    sockSend(fd, m, 12)
    emit 1
}
// wl_display(1).sync(opcode 0): new_id callback — round-trip marker.
func wlSync(fd, cbId) {
    let m = bufNew(12)
    _wlPutU32(m, 0, 1)
    _wlPutU16(m, 4, 0)
    _wlPutU16(m, 6, 12)
    _wlPutU32(m, 8, cbId)
    sockSend(fd, m, 12)
    emit 1
}
// wl_registry(registryId).bind(opcode 0): name, interface(string), version, new_id.
func wlBind(fd, registryId, name, iface, version, newId) {
    let ilen = len(iface) + 1
    let padded = _wlPad4(ilen)
    let size = 8 + 4 + 4 + padded + 4 + 4
    let m = bufNew(size)
    _wlPutU32(m, 0, registryId)
    _wlPutU16(m, 4, 0)
    _wlPutU16(m, 6, size)
    _wlPutU32(m, 8, name)
    _wlPutU32(m, 12, ilen)
    let i = 0
    while i < len(iface) { bufSetByte(m, 16 + i, charCode(iface[i]))  i += 1 }
    let voff = 16 + padded
    _wlPutU32(m, voff, version)
    _wlPutU32(m, voff + 4, newId)
    sockSend(fd, m, size)
    emit 1
}

// ── reading ────────────────────────────────────────────────────────────────
// Read up to maxlen bytes into b; returns nbytes (or <=0).
func wlRecvInto(fd, b, maxlen) { emit sockRecv(fd, b, maxlen) }

// message header getters (LE) at byte offset off
func wlObject(b, off) { emit bufGetDwordAt(b, off) }
func wlOpcode(b, off) { emit bufGetWordAt(b, off + 4) }
func wlSize(b, off)   { emit bufGetWordAt(b, off + 6) }
func wlU32(b, off)    { emit bufGetDwordAt(b, off) }   // raw u32 at absolute off

// read a wl string at absolute byte offset `off` (u32 len + bytes). Returns the
// string (without trailing NUL). Advance past it with wlStrEnd.
func wlReadStr(b, off) {
    let n = bufGetDwordAt(b, off)
    if n == 0 { emit "" }
    let s = ""
    let i = 0
    while i < n - 1 { s = s + fromCharCode(bufGetByte(b, off + 4 + i))  i += 1 }
    emit s
}
func wlStrEnd(b, off) {            // absolute offset just past a string field
    emit off + 4 + _wlPad4(bufGetDwordAt(b, off))
}
