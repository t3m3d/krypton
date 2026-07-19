// stdlib/bytes.k -- length-aware binary data and Unicode conversion.
//
// Krypton strings remain NUL-terminated text. ByteBuffer values keep their
// length separately and may contain every byte from 0x00 through 0xFF.
// Layout: [len:u64, cap:u64, reserved:u64, reserved:u64, payload...].

module bytes

func bytesNew(capacity) {
    let cap = toInt(capacity)
    if cap < 0 { cap = 0 }
    let b = bufNew(cap + 32)
    bufSetQwordAt(b, 0, 0)
    bufSetQwordAt(b, 8, cap)
    emit b
}

func bytesWithLength(length) {
    let n = toInt(length)
    if n < 0 { n = 0 }
    let b = bytesNew(n)
    bufSetQwordAt(b, 0, n)
    emit b
}

func bytesRaw(b)      { emit ptrAdd(b, 32) }
func bytesLen(b)      { emit toInt(bufGetQwordAt(b, 0)) }
func bytesCap(b)      { emit toInt(bufGetQwordAt(b, 8)) }
func bytesIsEmpty(b)  { emit bytesLen(b) == 0 }

func bytesSetLength(b, length) {
    let n = toInt(length)
    if n < 0 || n > bytesCap(b) { emit "0" }
    bufSetQwordAt(b, 0, n)
    emit "1"
}

func bytesGet(b, index) {
    let i = toInt(index)
    if i < 0 || i >= bytesLen(b) { emit "0" }
    emit bufGetByte(bytesRaw(b), i)
}

// Writes inside capacity and extends length through index. Returns 0 on OOB.
func bytesSet(b, index, value) {
    let i = toInt(index)
    if i < 0 || i >= bytesCap(b) { emit "0" }
    let v = toInt(value)
    if v < 0 || v > 255 { emit "0" }
    bufSetByte(bytesRaw(b), i, v)
    if i >= bytesLen(b) { bufSetQwordAt(b, 0, i + 1) }
    emit "1"
}

func bytesReserve(b, required) {
    let need = toInt(required)
    if need <= bytesCap(b) { emit b }
    let cap = bytesCap(b)
    if cap < 1 { cap = 1 }
    while cap < need { cap = cap * 2 }
    let out = bytesNew(cap)
    let n = bytesLen(b)
    let i = 0
    while i < n {
        bufSetByte(bytesRaw(out), i, bufGetByte(bytesRaw(b), i))
        i += 1
    }
    bufSetQwordAt(out, 0, n)
    emit out
}

func bytesAppendByte(b, value) {
    let n = bytesLen(b)
    let out = bytesReserve(b, n + 1)
    bytesSet(out, n, value)
    emit out
}

func bytesAppendBuffer(dst, src) {
    let dn = bytesLen(dst)
    let sn = bytesLen(src)
    let out = bytesReserve(dst, dn + sn)
    let i = 0
    while i < sn {
        bufSetByte(bytesRaw(out), dn + i, bufGetByte(bytesRaw(src), i))
        i += 1
    }
    bufSetQwordAt(out, 0, dn + sn)
    emit out
}

func bytesCopy(dst, dstOffset, src, srcOffset, count) {
    let d = toInt(dstOffset)
    let s = toInt(srcOffset)
    let n = toInt(count)
    if d < 0 || s < 0 || n < 0 { emit "0" }
    if s + n > bytesLen(src) || d + n > bytesCap(dst) { emit "0" }
    let i = 0
    let sameBuffer = ptrToInt(dst) == ptrToInt(src)
    if sameBuffer && d > s && d < s + n {
        i = n
        while i > 0 {
            i -= 1
            bufSetByte(bytesRaw(dst), d + i, bufGetByte(bytesRaw(src), s + i))
        }
    } else {
        while i < n {
            bufSetByte(bytesRaw(dst), d + i, bufGetByte(bytesRaw(src), s + i))
            i += 1
        }
    }
    if d + n > bytesLen(dst) { bufSetQwordAt(dst, 0, d + n) }
    emit "1"
}

func bytesSlice(b, start, end) {
    let lo = toInt(start)
    let hi = toInt(end)
    if lo < 0 || hi < lo || hi > bytesLen(b) { emit bytesNew(0) }
    let out = bytesWithLength(hi - lo)
    let i = 0
    while i < hi - lo {
        bufSetByte(bytesRaw(out), i, bufGetByte(bytesRaw(b), lo + i))
        i += 1
    }
    emit out
}

func bytesZero(b, start, count) {
    let lo = toInt(start)
    let n = toInt(count)
    if lo < 0 || n < 0 || lo + n > bytesLen(b) { emit "0" }
    let i = 0
    while i < n { bufSetByte(bytesRaw(b), lo + i, 0)  i += 1 }
    emit "1"
}

func _bytesCanRead(b, offset, width) {
    let off = toInt(offset)
    emit off >= 0 && off + width <= bytesLen(b)
}

func _bytesCanWrite(b, offset, width) {
    let off = toInt(offset)
    emit off >= 0 && off + width <= bytesCap(b)
}

func _bytesExtendForWrite(b, offset, width) {
    let end = toInt(offset) + width
    if end > bytesLen(b) { bufSetQwordAt(b, 0, end) }
}

func bytesReadU8(b, off)  { emit bytesGet(b, off) }
func bytesReadU16LE(b, off) {
    if !_bytesCanRead(b, off, 2) { emit "0" }
    emit bufGetWordAt(bytesRaw(b), off)
}
func bytesReadU32LE(b, off) {
    if !_bytesCanRead(b, off, 4) { emit "0" }
    emit bufGetDwordAt(bytesRaw(b), off)
}
func bytesReadU64LE(b, off) {
    if !_bytesCanRead(b, off, 8) { emit "0" }
    emit bufGetQwordAt(bytesRaw(b), off)
}

func bytesReadI8(b, off) {
    let v = toInt(bytesReadU8(b, off))
    if v >= 128 { emit v - 256 }
    emit v
}
func bytesReadI16LE(b, off) {
    let v = toInt(bytesReadU16LE(b, off))
    if v >= 32768 { emit v - 65536 }
    emit v
}
func bytesReadI32LE(b, off) {
    let v = toInt(bytesReadU32LE(b, off))
    let signBit = 1073741824 * 2
    let fullRange = signBit * 2
    if v >= signBit { emit v - fullRange }
    emit v
}
func bytesReadI64LE(b, off) {
    if !_bytesCanRead(b, off, 8) { emit "0" }
    let low = toInt(bytesReadU32LE(b, off))
    let high = toInt(bytesReadU32LE(b, toInt(off) + 4))
    let wordRange = 1073741824 * 4
    if high >= 1073741824 * 2 { high -= wordRange }
    emit high * wordRange + low
}

func bytesWriteU8(b, off, value) { emit bytesSet(b, off, value) }
func bytesWriteU16LE(b, off, value) {
    if !_bytesCanWrite(b, off, 2) { emit "0" }
    bufSetWordAt(bytesRaw(b), off, value)
    _bytesExtendForWrite(b, off, 2)
    emit "1"
}
func bytesWriteU32LE(b, off, value) {
    if !_bytesCanWrite(b, off, 4) { emit "0" }
    bufSetDwordAt(bytesRaw(b), off, value)
    _bytesExtendForWrite(b, off, 4)
    emit "1"
}
func bytesWriteU64LE(b, off, value) {
    if !_bytesCanWrite(b, off, 8) { emit "0" }
    bufSetQwordAt(bytesRaw(b), off, value)
    _bytesExtendForWrite(b, off, 8)
    emit "1"
}

func bytesWriteI8(b, off, value) {
    let v = toInt(value)
    if v < -128 || v > 127 { emit "0" }
    if v < 0 { v += 256 }
    emit bytesWriteU8(b, off, v)
}
func bytesWriteI16LE(b, off, value) {
    let v = toInt(value)
    if v < -32768 || v > 32767 { emit "0" }
    if v < 0 { v += 65536 }
    emit bytesWriteU16LE(b, off, v)
}
func bytesWriteI32LE(b, off, value) {
    let v = toInt(value)
    let signBit = 1073741824 * 2
    let fullRange = signBit * 2
    if v < 0 - signBit || v >= signBit { emit "0" }
    if v < 0 { v += fullRange }
    emit bytesWriteU32LE(b, off, v)
}
func bytesWriteI64LE(b, off, value) {
    if !_bytesCanWrite(b, off, 8) { emit "0" }
    bufSetQwordAt(bytesRaw(b), off, value)
    _bytesExtendForWrite(b, off, 8)
    emit "1"
}

func bytesAppendU16LE(b, value) {
    let n = bytesLen(b)
    let out = bytesReserve(b, n + 2)
    bytesWriteU16LE(out, n, value)
    emit out
}

func bytesAppendU32LE(b, value) {
    let n = bytesLen(b)
    let out = bytesReserve(b, n + 4)
    bytesWriteU32LE(out, n, value)
    emit out
}

// Windows x86-64 pointer/handle storage. Keep names explicit so a future
// 32-bit target can provide target-width implementations.
func bytesReadUPtrLE(b, off) { emit bytesReadU64LE(b, off) }
func bytesWriteUPtrLE(b, off, value) { emit bytesWriteU64LE(b, off, value) }
func bytesAppendUPtrLE(b, value) {
    let n = bytesLen(b)
    let out = bytesReserve(b, n + 8)
    bytesWriteUPtrLE(out, n, value)
    emit out
}

func bytesFromUtf8(s) {
    let out = bytesWithLength(len(s))
    let i = 0
    while i < len(s) {
        bufSetByte(bytesRaw(out), i, charCode(substring(s, i, i + 1)))
        i += 1
    }
    emit out
}

func _utf8AppendByte(sb, value) {
    emit sbAppend(sb, fromCharCode(toInt(value)))
}

func _utf8AppendReplacement(sb) {
    sb = _utf8AppendByte(sb, 239)
    sb = _utf8AppendByte(sb, 191)
    emit _utf8AppendByte(sb, 189)
}

func _utf8AppendCodepoint(sb, codepoint) {
    let cp = toInt(codepoint)
    if cp <= 127 { emit _utf8AppendByte(sb, cp) }
    if cp <= 2047 {
        sb = _utf8AppendByte(sb, 192 + cp / 64)
        emit _utf8AppendByte(sb, 128 + cp % 64)
    }
    if cp <= 65535 {
        sb = _utf8AppendByte(sb, 224 + cp / 4096)
        sb = _utf8AppendByte(sb, 128 + cp / 64 % 64)
        emit _utf8AppendByte(sb, 128 + cp % 64)
    }
    sb = _utf8AppendByte(sb, 240 + cp / 262144)
    sb = _utf8AppendByte(sb, 128 + cp / 4096 % 64)
    sb = _utf8AppendByte(sb, 128 + cp / 64 % 64)
    emit _utf8AppendByte(sb, 128 + cp % 64)
}

// Decoder state: [continuations:u64, codepoint:u64, minimum:u64].
func utf8DecoderNew() {
    let state = bufNew(24)
    bufSetQwordAt(state, 0, 0)
    bufSetQwordAt(state, 8, 0)
    bufSetQwordAt(state, 16, 0)
    emit state
}

func _utf8Reset(state) {
    bufSetQwordAt(state, 0, 0)
    bufSetQwordAt(state, 8, 0)
    bufSetQwordAt(state, 16, 0)
}

// Returns validated UTF-8 text. State retains an incomplete rune between calls.
func utf8DecodeChunk(state, chunk, finalChunk) {
    let sb = sbNew()
    let i = 0
    while i < bytesLen(chunk) {
        let byte = toInt(bytesGet(chunk, i))
        let again = 1
        while again == 1 {
            again = 0
            let need = toInt(bufGetQwordAt(state, 0))
            if need == 0 {
                if byte <= 127 {
                    sb = _utf8AppendByte(sb, byte)
                } else if byte >= 194 && byte <= 223 {
                    bufSetQwordAt(state, 0, 1)
                    bufSetQwordAt(state, 8, byte - 192)
                    bufSetQwordAt(state, 16, 128)
                } else if byte >= 224 && byte <= 239 {
                    bufSetQwordAt(state, 0, 2)
                    bufSetQwordAt(state, 8, byte - 224)
                    bufSetQwordAt(state, 16, 2048)
                } else if byte >= 240 && byte <= 244 {
                    bufSetQwordAt(state, 0, 3)
                    bufSetQwordAt(state, 8, byte - 240)
                    bufSetQwordAt(state, 16, 65536)
                } else {
                    sb = _utf8AppendReplacement(sb)
                }
            } else if byte >= 128 && byte <= 191 {
                let cp = toInt(bufGetQwordAt(state, 8)) * 64 + byte - 128
                need -= 1
                bufSetQwordAt(state, 0, need)
                bufSetQwordAt(state, 8, cp)
                if need == 0 {
                    let minimum = toInt(bufGetQwordAt(state, 16))
                    if cp < minimum || cp > 1114111 || (cp >= 55296 && cp <= 57343) {
                        sb = _utf8AppendReplacement(sb)
                    } else {
                        sb = _utf8AppendCodepoint(sb, cp)
                    }
                    _utf8Reset(state)
                }
            } else {
                sb = _utf8AppendReplacement(sb)
                _utf8Reset(state)
                again = 1
            }
        }
        i += 1
    }
    if finalChunk == "1" || finalChunk == 1 {
        if toInt(bufGetQwordAt(state, 0)) != 0 {
            sb = _utf8AppendReplacement(sb)
            _utf8Reset(state)
        }
    }
    emit sbToString(sb)
}

func bytesToUtf8(b) {
    let state = utf8DecoderNew()
    emit utf8DecodeChunk(state, b, 1)
}

func _utf8Continuation(v) { emit v >= 128 && v <= 191 }

// Converts Krypton's UTF-8 text bytes to a UTF-16LE ByteBuffer.
func utf16leEncode(s, nulTerminated) {
    let input = bytesFromUtf8(s)
    let out = bytesNew(bytesLen(input) * 2 + 4)
    let i = 0
    while i < bytesLen(input) {
        let b0 = toInt(bytesGet(input, i))
        let cp = 65533
        let used = 1
        if b0 <= 127 {
            cp = b0
        } else if b0 >= 194 && b0 <= 223 && i + 1 < bytesLen(input) {
            let b1 = toInt(bytesGet(input, i + 1))
            if _utf8Continuation(b1) { cp = (b0 - 192) * 64 + b1 - 128  used = 2 }
        } else if b0 >= 224 && b0 <= 239 && i + 2 < bytesLen(input) {
            let b1 = toInt(bytesGet(input, i + 1))
            let b2 = toInt(bytesGet(input, i + 2))
            if _utf8Continuation(b1) && _utf8Continuation(b2) {
                let candidate = (b0 - 224) * 4096 + (b1 - 128) * 64 + b2 - 128
                if candidate >= 2048 && !(candidate >= 55296 && candidate <= 57343) {
                    cp = candidate
                    used = 3
                }
            }
        } else if b0 >= 240 && b0 <= 244 && i + 3 < bytesLen(input) {
            let b1 = toInt(bytesGet(input, i + 1))
            let b2 = toInt(bytesGet(input, i + 2))
            let b3 = toInt(bytesGet(input, i + 3))
            if _utf8Continuation(b1) && _utf8Continuation(b2) && _utf8Continuation(b3) {
                let candidate = (b0 - 240) * 262144 + (b1 - 128) * 4096 + (b2 - 128) * 64 + b3 - 128
                if candidate >= 65536 && candidate <= 1114111 { cp = candidate  used = 4 }
            }
        }
        if cp <= 65535 {
            out = bytesAppendU16LE(out, cp)
        } else {
            let v = cp - 65536
            out = bytesAppendU16LE(out, 55296 + v / 1024)
            out = bytesAppendU16LE(out, 56320 + v % 1024)
        }
        i += used
    }
    if nulTerminated == "1" || nulTerminated == 1 { out = bytesAppendU16LE(out, 0) }
    emit out
}

func utf16leDecode(b, stopAtNul) {
    let sb = sbNew()
    let i = 0
    while i + 1 < bytesLen(b) {
        let u = toInt(bytesReadU16LE(b, i))
        if u == 0 && (stopAtNul == "1" || stopAtNul == 1) { break }
        let cp = u
        let used = 2
        if u >= 55296 && u <= 56319 {
            if i + 3 < bytesLen(b) {
                let low = toInt(bytesReadU16LE(b, i + 2))
                if low >= 56320 && low <= 57343 {
                    cp = 65536 + (u - 55296) * 1024 + low - 56320
                    used = 4
                } else { cp = 65533 }
            } else { cp = 65533 }
        } else if u >= 56320 && u <= 57343 {
            cp = 65533
        }
        sb = _utf8AppendCodepoint(sb, cp)
        i += used
    }
    if i < bytesLen(b) { sb = _utf8AppendReplacement(sb) }
    emit sbToString(sb)
}

// envLines is one KEY=VALUE entry per line. Output ends in two UTF-16 NULs.
func utf16leEnvironmentBlock(envLines) {
    let out = bytesNew(len(envLines) * 2 + 4)
    let entries = 0
    let i = 0
    while i < lineCount(envLines) {
        let line = getLine(envLines, i)
        if line != "" {
            let encoded = utf16leEncode(line, 0)
            out = bytesAppendBuffer(out, encoded)
            out = bytesAppendU16LE(out, 0)
            entries += 1
        }
        i += 1
    }
    if entries == 0 { out = bytesAppendU16LE(out, 0) }
    out = bytesAppendU16LE(out, 0)
    emit out
}

func bytesFromString(s, encoding) {
    let enc = toLower(encoding)
    if enc == "utf16le" || enc == "utf-16le" { emit utf16leEncode(s, 0) }
    emit bytesFromUtf8(s)
}

func bytesToString(b, encoding) {
    let enc = toLower(encoding)
    if enc == "utf16le" || enc == "utf-16le" { emit utf16leDecode(b, 0) }
    emit bytesToUtf8(b)
}
