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

// ── generic message emit helpers ───────────────────────────────────────────
// send a header-only request (no args)
func _wlSend0(fd, obj, op) {
    let m = bufNew(8)
    _wlPutU32(m, 0, obj)  _wlPutU16(m, 4, op)  _wlPutU16(m, 6, 8)
    sockSend(fd, m, 8)
    emit 1
}
// send a request with one u32 arg
func _wlSend1(fd, obj, op, a0) {
    let m = bufNew(12)
    _wlPutU32(m, 0, obj)  _wlPutU16(m, 4, op)  _wlPutU16(m, 6, 12)
    _wlPutU32(m, 8, a0)
    sockSend(fd, m, 12)
    emit 1
}
// send a request with two u32 args
func _wlSend2(fd, obj, op, a0, a1) {
    let m = bufNew(16)
    _wlPutU32(m, 0, obj)  _wlPutU16(m, 4, op)  _wlPutU16(m, 6, 16)
    _wlPutU32(m, 8, a0)  _wlPutU32(m, 12, a1)
    sockSend(fd, m, 16)
    emit 1
}

// ── object construction ─────────────────────────────────────────────────────
// wl_compositor.create_surface (opcode 0): new_id surface
func wlCreateSurface(fd, compId, surfId) { emit _wlSend1(fd, compId, 0, surfId) }
// xdg_wm_base.get_xdg_surface (opcode 2): new_id xdgsurf, object surface
func wlGetXdgSurface(fd, wmId, xdgSurfId, surfId) { emit _wlSend2(fd, wmId, 2, xdgSurfId, surfId) }
// xdg_surface.get_toplevel (opcode 1): new_id toplevel
func wlGetToplevel(fd, xdgSurfId, topId) { emit _wlSend1(fd, xdgSurfId, 1, topId) }
// xdg_toplevel.set_title (opcode 2): string
func wlSetTitle(fd, topId, title) {
    let slen = len(title) + 1
    let padded = _wlPad4(slen)
    let size = 8 + 4 + padded
    let m = bufNew(size)
    _wlPutU32(m, 0, topId)  _wlPutU16(m, 4, 2)  _wlPutU16(m, 6, size)
    _wlPutU32(m, 8, slen)
    let i = 0
    while i < len(title) { bufSetByte(m, 12 + i, charCode(title[i]))  i += 1 }
    sockSend(fd, m, size)
    emit 1
}
// xdg_toplevel.set_app_id (opcode 3): string
func wlSetAppId(fd, topId, appid) {
    let slen = len(appid) + 1
    let padded = _wlPad4(slen)
    let size = 8 + 4 + padded
    let m = bufNew(size)
    _wlPutU32(m, 0, topId)  _wlPutU16(m, 4, 3)  _wlPutU16(m, 6, size)
    _wlPutU32(m, 8, slen)
    let i = 0
    while i < len(appid) { bufSetByte(m, 12 + i, charCode(appid[i]))  i += 1 }
    sockSend(fd, m, size)
    emit 1
}

// ── surface lifecycle ───────────────────────────────────────────────────────
func wlCommit(fd, surfId)          { emit _wlSend0(fd, surfId, 6) }            // wl_surface.commit
func wlAckConfigure(fd, xdgSurfId, serial) { emit _wlSend1(fd, xdgSurfId, 4, serial) } // xdg_surface.ack_configure
func wlPong(fd, wmId, serial)      { emit _wlSend1(fd, wmId, 3, serial) }      // xdg_wm_base.pong

// wl_surface.attach (opcode 1): object buffer, int x, int y  (3 args)
func wlSurfaceAttach(fd, surfId, bufId, x, y) {
    let m = bufNew(20)
    _wlPutU32(m, 0, surfId)  _wlPutU16(m, 4, 1)  _wlPutU16(m, 6, 20)
    _wlPutU32(m, 8, bufId)  _wlPutU32(m, 12, x)  _wlPutU32(m, 16, y)
    sockSend(fd, m, 20)
    emit 1
}
// wl_surface.damage (opcode 2): int x, y, w, h
func wlDamage(fd, surfId, x, y, w, h) {
    let m = bufNew(24)
    _wlPutU32(m, 0, surfId)  _wlPutU16(m, 4, 2)  _wlPutU16(m, 6, 24)
    _wlPutU32(m, 8, x)  _wlPutU32(m, 12, y)  _wlPutU32(m, 16, w)  _wlPutU32(m, 20, h)
    sockSend(fd, m, 24)
    emit 1
}

// ── client-side framebuffer drawing ────────────────────────────────────────
// Wayland has no server-side draw: everything is rendered into the shm pixel
// buffer (the mmapShared addr, used directly as a buf). Pixels are XRGB8888,
// little-endian, i.e. 4 bytes per pixel in order B,G,R,X. `color` args are
// packed 0xRRGGBB ints. fbW/fbH are the buffer's width/height in pixels.

// fill the whole buffer with one color
func fbClear(px, fbW, fbH, color) { fbFillRect(px, fbW, 0, 0, fbW, fbH, color) }

// fill rect (x,y,w,h) with color. No clipping — caller keeps it in bounds.
func fbFillRect(px, fbW, x, y, w, h, color) {
    let b = color - color / 256 * 256
    let g = color / 256 - color / 65536 * 256
    let r = color / 65536 - color / 16777216 * 256
    let row = 0
    while row < h {
        let base = ((y + row) * fbW + x) * 4
        let col = 0
        while col < w {
            let o = base + col * 4
            bufSetByte(px, o, b)
            bufSetByte(px, o + 1, g)
            bufSetByte(px, o + 2, r)
            bufSetByte(px, o + 3, 0)
            col += 1
        }
        row += 1
    }
}

// blit a BGRA source image (4 bytes/px, same layout as cortex's icon rasters)
// to (dx,dy), clipped to the fb. Source alpha is ignored (opaque copy) — pre-
// composite against the destination bg first if you need transparency.
func fbBlitBGRA(px, fbW, fbH, dx, dy, src, sw, sh) {
    let sy = 0
    while sy < sh {
        let py = dy + sy
        if py >= 0 && py < fbH {
            let sx = 0
            while sx < sw {
                let pxx = dx + sx
                if pxx >= 0 && pxx < fbW {
                    let so = (sy * sw + sx) * 4
                    let dofs = (py * fbW + pxx) * 4
                    bufSetByte(px, dofs,     bufGetByte(src, so))
                    bufSetByte(px, dofs + 1, bufGetByte(src, so + 1))
                    bufSetByte(px, dofs + 2, bufGetByte(src, so + 2))
                    bufSetByte(px, dofs + 3, 0)
                }
                sx += 1
            }
        }
        sy += 1
    }
}

// read a pixel's packed 0xRRGGBB (for tests / verification)
func fbGetPixel(px, fbW, x, y) {
    let o = (y * fbW + x) * 4
    emit bufGetByte(px, o + 2) * 65536 + bufGetByte(px, o + 1) * 256 + bufGetByte(px, o)
}

// ── shared-memory buffers ───────────────────────────────────────────────────
// wl_shm.create_pool (opcode 0): new_id pool, fd(ancillary), int size.
// The fd rides out-of-band via SCM_RIGHTS (sockSendFd) — only pool+size are
// in the byte stream (16 bytes total).
func wlCreatePool(fd, shmId, poolId, memfd, size) {
    let m = bufNew(16)
    _wlPutU32(m, 0, shmId)  _wlPutU16(m, 4, 0)  _wlPutU16(m, 6, 16)
    _wlPutU32(m, 8, poolId)  _wlPutU32(m, 12, size)
    sockSendFd(fd, m, 16, memfd)
    emit 1
}
// wl_shm_pool.create_buffer (opcode 0): new_id buf, int offset,w,h,stride,format
func wlPoolCreateBuffer(fd, poolId, bufId, offset, w, h, stride, fmt) {
    let m = bufNew(32)
    _wlPutU32(m, 0, poolId)  _wlPutU16(m, 4, 0)  _wlPutU16(m, 6, 32)
    _wlPutU32(m, 8, bufId)  _wlPutU32(m, 12, offset)  _wlPutU32(m, 16, w)
    _wlPutU32(m, 20, h)  _wlPutU32(m, 24, stride)  _wlPutU32(m, 28, fmt)
    sockSend(fd, m, 32)
    emit 1
}
