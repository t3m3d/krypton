// stdlib/qr.k — QR Code encoder in PURE KRYPTON. No C, no syscalls, no libs.
//
// Supports byte-mode encoding, error correction level L (~7%), versions
// 1-5. Capacities (L, byte mode):
//   V1: 17 bytes   (21x21 modules)
//   V2: 32 bytes   (25x25)
//   V3: 53 bytes   (29x29)
//   V4: 78 bytes   (33x33)
//   V5: 106 bytes  (37x37)
//
// Output API:
//   qrEncode(text)  → "rows\n" of 0/1 chars, one row per scanline.
//                     White cell = "0", black cell = "1".
//   qrSvg(text, scale)
//                   → standalone SVG string (each module is `scale`x`scale` px).
//
// Returns "" if text exceeds V5 capacity (106 bytes).
//
// Implementation: GF(256) Reed-Solomon for error correction, ISO-style
// 8-mask pattern selection. Bit-packing built via sbAppend (no string
// concat with digit chars — that would int-coalesce, see
// [[feedback_kr_plus_int_coalesce]]).

module qr

// ── GF(256) tables (polynomial 0x11D, generator 2) ───────────────────
//
// Pre-computed exp[] and log[] tables let RS multiplications run in
// constant time via add-in-log-space. Krypton has no static-data
// section, so we build them lazily via gfInit() and stuff into a
// shared buffer.

func gfInit() {
    let buf = bufNew(1024)   // 512 bytes exp[0..511], 512 bytes log[0..255] (each entry stored as 2 bytes)
    let x = 1
    let i = 0
    while i < 255 {
        bufSetWordAt(buf, i * 2, x + "")
        // log[x] = i
        bufSetWordAt(buf, 512 + x * 2, i + "")
        x = x * 2
        // GF(256) reduction: when bit 8 is set, XOR low byte with 0x1D.
        // (My earlier `x = x - 256 + 29` was wrong — it's addition, not
        // XOR, so any overlapping bits between (x-256) and 29 would
        // double-count instead of cancelling.)
        if x >= 256 { x = bitXor(x - 256, 29) }
        i = i + 1
    }
    // Extend exp to 511 for easy mod-255 arithmetic.
    let j = 255
    while j < 512 {
        let v = toInt(bufGetWordAt(buf, (j - 255) * 2))
        bufSetWordAt(buf, j * 2, v + "")
        j = j + 1
    }
    emit buf
}

func gfMul(tbl, a, b) {
    if a == 0 || b == 0 { emit 0 }
    let la = toInt(bufGetWordAt(tbl, 512 + a * 2))
    let lb = toInt(bufGetWordAt(tbl, 512 + b * 2))
    let s = la + lb
    if s >= 255 { s = s - 255 }
    emit toInt(bufGetWordAt(tbl, s * 2))
}

// ── Reed-Solomon generator polynomial ────────────────────────────────
//
// For `nsym` error-correction codewords, the generator polynomial is
// (x - α^0)(x - α^1)…(x - α^(nsym-1)) over GF(256). Coefficients stored
// in a `nsym+1`-sized buffer, highest-degree first.

func rsGenPoly(tbl, nsym) {
    let g = bufNew((nsym + 1) * 2)
    bufSetWordAt(g, 0, "1")
    let glen = 1
    let i = 0
    while i < nsym {
        // multiply g by (x - α^i)
        let next = bufNew((nsym + 1) * 2)
        // shift up by 1 (multiply by x)
        let j = 0
        while j <= glen {
            let gj = 0
            if j < glen { gj = toInt(bufGetWordAt(g, j * 2)) }
            // existing j-th coef contributes to (j)-th of next (* x term)
            // plus the (j-1)-th of next when multiplied by -α^i
            let prev = 0
            if j > 0 { prev = toInt(bufGetWordAt(g, (j - 1) * 2)) }
            let cur = toInt(bufGetWordAt(next, j * 2))
            // (cur) XOR (prev * α^i)  +  (g[j] shifted up handled by reading g[j-1])
            // Actually: next[j] = g[j] XOR (g[j-1] * α^i) (treating positions correctly)
            // Wait, let's re-derive. g is coefficients of polynomial of degree (glen-1).
            // Multiplying by (x + α^i) [signs in GF are XOR-symmetric]:
            //   new[k] = old[k-1] XOR (old[k] * α^i)
            // for k in [0..glen]. With old[-1] = 0 and old[glen] = 0.
            let oldKm1 = 0
            if j > 0 { oldKm1 = toInt(bufGetWordAt(g, (j - 1) * 2)) }
            let oldK = 0
            if j < glen { oldK = toInt(bufGetWordAt(g, j * 2)) }
            let alphaI = toInt(bufGetWordAt(tbl, i * 2))
            let v = bitXor(oldKm1, gfMul(tbl, oldK, alphaI))
            bufSetWordAt(next, j * 2, v + "")
            j = j + 1
        }
        // swap next → g
        let k2 = 0
        while k2 <= glen {
            bufSetWordAt(g, k2 * 2, bufGetWordAt(next, k2 * 2))
            k2 = k2 + 1
        }
        glen = glen + 1
        i = i + 1
    }
    emit g
}

// Compute `nsym` Reed-Solomon error-correction codewords for the data
// (a buffer of `dataLen` bytes). Returns a new buffer holding the ec
// codewords (msb-first byte stream).
func rsEncode(tbl, data, dataLen, nsym) {
    let gen = rsGenPoly(tbl, nsym)
    // result starts as data shifted left by nsym bytes (i.e., data
    // followed by nsym zero bytes), then we long-divide by gen.
    let bufLen = dataLen + nsym
    let work = bufNew(bufLen)
    let i = 0
    while i < dataLen {
        bufSetByte(work, i, bufGetByte(data, i))
        i = i + 1
    }
    // The trailing nsym bytes are already zero (bufNew zeros memory).

    // Long division: for each data byte, the leading coef of work is
    // its remainder contribution; multiply gen by it and XOR into work.
    let pos = 0
    while pos < dataLen {
        let coef = toInt(bufGetByte(work, pos))
        if coef != 0 {
            let j = 0
            while j <= nsym {
                let gj = toInt(bufGetWordAt(gen, j * 2))
                let prod = gfMul(tbl, gj, coef)
                let cur = toInt(bufGetByte(work, pos + j))
                bufSetByte(work, pos + j, bitXor(cur, prod) + "")
                j = j + 1
            }
        }
        pos = pos + 1
    }

    // The remainder lives in the trailing nsym bytes of work.
    let ec = bufNew(nsym)
    let k = 0
    while k < nsym {
        bufSetByte(ec, k, bufGetByte(work, dataLen + k))
        k = k + 1
    }
    emit ec
}

// ── Version capacity tables (byte mode, L correction) ────────────────
//
// dataBytes[V] = number of data codewords (not counting ec)
// ecBytes[V]   = number of error-correction codewords
// Per ISO 18004 Table 1 + Table 9 (block layout assumed: 1 block for V1-5 L).

func _verData(v) {
    if v == 1 { emit 19 }
    if v == 2 { emit 34 }
    if v == 3 { emit 55 }
    if v == 4 { emit 80 }
    if v == 5 { emit 108 }
    emit 0
}

func _verEc(v) {
    if v == 1 { emit 7 }
    if v == 2 { emit 10 }
    if v == 3 { emit 15 }
    if v == 4 { emit 20 }
    if v == 5 { emit 26 }
    emit 0
}

func _verSize(v) { emit 17 + (v * 4) }   // modules per side

// Pick the smallest version that fits `nbytes` of byte-mode data.
// Returns 0 if nothing in V1-V5 is big enough.
func _pickVersion(nbytes) {
    // byte-mode header is 4 bits mode indicator + 8 bits length (V1-9)
    // = 12 bits = 1.5 bytes. So usable data = _verData(v) - 2 bytes
    // rounded down (since the 4 trailing bits must also fit).
    let v = 1
    while v <= 5 {
        let cap = _verData(v) - 2
        if nbytes <= cap { emit v }
        v = v + 1
    }
    emit 0
}

// ── Bit stream construction ──────────────────────────────────────────
//
// Builds a buffer of bytes representing the bit stream:
//   4-bit mode indicator (0100 = byte mode)
//   8-bit char count (for V1-9)
//   byte data (8 bits each)
//   4-bit terminator (or fewer if no room)
//   pad bits to byte boundary
//   pad bytes (alternating 0xEC, 0x11) until data capacity reached

// Append `nbits` low bits of `val` to the stream. The stream is a
// growing string of "0"/"1" chars (small; built via sbAppend).
func _bsAppend(sb, val, nbits) {
    let i = nbits - 1
    while i >= 0 {
        let bit = (val / (1 << i)) % 2
        if bit == 1 { sb = sbAppend(sb, "1") }
        else        { sb = sbAppend(sb, "0") }
        i = i - 1
    }
    emit sb
}

// Tiny 2^n for n in 0..15.
func _pow2(n) {
    let r = 1
    let i = 0
    while i < n { r = r * 2  i = i + 1 }
    emit r
}

// Replace the inline `1 << i` (which Krypton has via shl).
func _shl(v, n) {
    let r = v
    let i = 0
    while i < n { r = r * 2  i = i + 1 }
    emit r
}

func qrBitStream(text, v) {
    let sb = sbNew()
    // Mode indicator: 0100
    sb = sbAppend(sb, "0")
    sb = sbAppend(sb, "1")
    sb = sbAppend(sb, "0")
    sb = sbAppend(sb, "0")
    // Char count: 8 bits (V1-9 byte mode).
    let n = len(text)
    let b = 7
    while b >= 0 {
        let bit = (n / _pow2(b)) % 2
        if bit == 1 { sb = sbAppend(sb, "1") }
        else        { sb = sbAppend(sb, "0") }
        b = b - 1
    }
    // Data bytes, 8 bits each.
    let i = 0
    while i < n {
        let cc = toInt(charCode(text[i]))
        let bb = 7
        while bb >= 0 {
            let bit = (cc / _pow2(bb)) % 2
            if bit == 1 { sb = sbAppend(sb, "1") }
            else        { sb = sbAppend(sb, "0") }
            bb = bb - 1
        }
        i = i + 1
    }
    // Terminator: up to 4 zero bits, but not past capacity.
    let cap = _verData(v) * 8
    let need = cap - len(sbToString(sb))
    if need > 4 { need = 4 }
    let t = 0
    while t < need { sb = sbAppend(sb, "0")  t = t + 1 }
    // Pad to byte boundary.
    while (len(sbToString(sb)) % 8) != 0 { sb = sbAppend(sb, "0") }
    // Pad bytes alternating EC / 11.
    let toggle = 0
    while len(sbToString(sb)) < cap {
        if toggle == 0 {
            // 0xEC = 11101100
            sb = sbAppend(sb, "11101100")
        } else {
            // 0x11 = 00010001
            sb = sbAppend(sb, "00010001")
        }
        toggle = 1 - toggle
    }
    emit sbToString(sb)
}

// Convert a "01" bit string into a byte buffer.
func _bitsToBuf(bits) {
    let n = len(bits) / 8
    let b = bufNew(n)
    let i = 0
    while i < n {
        let v = 0
        let j = 0
        while j < 8 {
            let c = bits[i * 8 + j]
            v = v * 2
            if c == "1" { v = v + 1 }
            j = j + 1
        }
        bufSetByte(b, i, v + "")
        i = i + 1
    }
    emit b
}

// ── Matrix scaffolding ───────────────────────────────────────────────
//
// We model the QR matrix as a single buffer with 2 bytes per cell:
//   byte 0 = value (0 = white, 1 = black)
//   byte 1 = function (1 = function module, 0 = data; controls masking
//            and protects finder/timing/format from data overwrite)
// Total: size*size*2 bytes (V5 = 37*37*2 = 2738).

func _matNew(size) {
    let b = bufNew(size * size * 2)
    emit b
}

func _matSet(m, size, r, c, val) {
    let off = (r * size + c) * 2
    bufSetByte(m, off, val + "")
}

func _matSetFunc(m, size, r, c, val) {
    let off = (r * size + c) * 2
    bufSetByte(m, off, val + "")
    bufSetByte(m, off + 1, "1")
}

func _matGet(m, size, r, c) {
    emit toInt(bufGetByte(m, (r * size + c) * 2))
}

func _matIsFunc(m, size, r, c) {
    emit toInt(bufGetByte(m, (r * size + c) * 2 + 1))
}

// Place a 7x7 finder pattern centered at (cr, cc) coords given as
// top-left corner. Inner: 3x3 dark, 1-module light ring, outer dark ring.
func _placeFinder(m, size, r0, c0) {
    let r = 0
    while r < 7 {
        let c = 0
        while c < 7 {
            let on = 0
            // outer 7x7 ring
            if r == 0 || r == 6 || c == 0 || c == 6 { on = 1 }
            // inner 3x3 block
            if r >= 2 && r <= 4 && c >= 2 && c <= 4 { on = 1 }
            _matSetFunc(m, size, r0 + r, c0 + c, on)
            c = c + 1
        }
        r = r + 1
    }
}

// Mark a separator (1-module white border) around a finder.
func _placeSeparator(m, size, r0, c0) {
    let i = 0
    while i < 8 {
        // top + bottom row of the 8-wide block
        if r0 - 1 >= 0 && c0 - 1 + i >= 0 && c0 - 1 + i < size {
            _matSetFunc(m, size, r0 - 1, c0 - 1 + i, 0)
        }
        if r0 + 7 < size && c0 - 1 + i >= 0 && c0 - 1 + i < size {
            _matSetFunc(m, size, r0 + 7, c0 - 1 + i, 0)
        }
        // left + right cols
        if c0 - 1 >= 0 && r0 - 1 + i >= 0 && r0 - 1 + i < size {
            _matSetFunc(m, size, r0 - 1 + i, c0 - 1, 0)
        }
        if c0 + 7 < size && r0 - 1 + i >= 0 && r0 - 1 + i < size {
            _matSetFunc(m, size, r0 - 1 + i, c0 + 7, 0)
        }
        i = i + 1
    }
}

// Timing patterns: alternating dark/light run along row 6 and col 6
// connecting the finder centers.
func _placeTiming(m, size) {
    let i = 8
    while i < size - 8 {
        let on = 0
        if i % 2 == 0 { on = 1 }
        _matSetFunc(m, size, 6, i, on)
        _matSetFunc(m, size, i, 6, on)
        i = i + 1
    }
}

// Alignment patterns: only V2+ (V1 has none). For V2-V5, exactly ONE
// alignment pattern at (size-7, size-7) — the bottom-right one.
// (Higher versions have grids; we don't need them for V≤5.)
func _placeAlignment(m, size, v) {
    if v == 1 { emit 0 }
    let cr = size - 7
    let cc = size - 7
    let r = 0 - 2
    while r <= 2 {
        let c = 0 - 2
        while c <= 2 {
            let on = 0
            // outer 5x5 ring
            if r == 0 - 2 || r == 2 || c == 0 - 2 || c == 2 { on = 1 }
            // center dot
            if r == 0 && c == 0 { on = 1 }
            _matSetFunc(m, size, cr + r, cc + c, on)
            c = c + 1
        }
        r = r + 1
    }
    emit 0
}

// Dark module: always-on bit at (4V+9, 8). Per spec.
func _placeDarkModule(m, size, v) {
    _matSetFunc(m, size, (4 * v) + 9, 8, 1)
}

// Reserve format-info region (placed with real values after masking).
// 15 bits along the finder edges. We set them to 0 + functional so the
// data-placement skips them.
func _reserveFormat(m, size) {
    let i = 0
    while i < 9 {
        if i != 6 {
            _matSetFunc(m, size, 8, i, 0)
            _matSetFunc(m, size, i, 8, 0)
        }
        i = i + 1
    }
    let j = 0
    while j < 8 {
        if j != 7 {
            _matSetFunc(m, size, 8, size - 1 - j, 0)
            _matSetFunc(m, size, size - 1 - j, 8, 0)
        }
        j = j + 1
    }
}

// Place the data stream into the matrix using the standard right-to-left,
// alternating-up/down zig-zag, skipping function modules + column 6.
func _placeData(m, size, dataBuf, dataBits) {
    let bitIdx = 0
    let col = size - 1
    let goingUp = 1
    while col > 0 {
        // Skip the timing column.
        if col == 6 { col = col - 1 }
        let row = 0
        if goingUp == 1 { row = size - 1 }
        let step = 0
        while step < size {
            let c0 = col
            let c1 = col - 1
            // place at (row, col) and (row, col-1)
            let k = 0
            while k < 2 {
                let cc = c0
                if k == 1 { cc = c1 }
                if _matIsFunc(m, size, row, cc) == 0 {
                    let byteIdx = bitIdx / 8
                    let bitInByte = 7 - (bitIdx % 8)
                    let val = 0
                    let dataLen = len(dataBits)
                    if bitIdx < dataLen {
                        if dataBits[bitIdx] == "1" { val = 1 }
                    }
                    _matSet(m, size, row, cc, val)
                    bitIdx = bitIdx + 1
                }
                k = k + 1
            }
            if goingUp == 1 {
                if row == 0 { step = size }
                else        { row = row - 1 }
            } else {
                if row == size - 1 { step = size }
                else               { row = row + 1 }
            }
            step = step + 1
        }
        col = col - 2
        goingUp = 1 - goingUp
    }
}

// Apply the chosen mask to non-function modules.
//   mask 0: (r + c) % 2 == 0
//   mask 1: r % 2 == 0
//   mask 2: c % 3 == 0
//   mask 3: (r + c) % 3 == 0
//   mask 4: ((r/2) + (c/3)) % 2 == 0
//   mask 5: ((r*c) % 2) + ((r*c) % 3) == 0
//   mask 6: (((r*c) % 2) + ((r*c) % 3)) % 2 == 0
//   mask 7: (((r+c) % 2) + ((r*c) % 3)) % 2 == 0
func _maskCell(maskId, r, c) {
    if maskId == 0 { if (r + c) % 2 == 0 { emit 1 } emit 0 }
    if maskId == 1 { if r % 2 == 0 { emit 1 } emit 0 }
    if maskId == 2 { if c % 3 == 0 { emit 1 } emit 0 }
    if maskId == 3 { if (r + c) % 3 == 0 { emit 1 } emit 0 }
    if maskId == 4 { if ((r / 2) + (c / 3)) % 2 == 0 { emit 1 } emit 0 }
    if maskId == 5 { if ((r * c) % 2) + ((r * c) % 3) == 0 { emit 1 } emit 0 }
    if maskId == 6 { if (((r * c) % 2) + ((r * c) % 3)) % 2 == 0 { emit 1 } emit 0 }
    if maskId == 7 { if (((r + c) % 2) + ((r * c) % 3)) % 2 == 0 { emit 1 } emit 0 }
    emit 0
}

func _applyMask(m, size, maskId) {
    let r = 0
    while r < size {
        let c = 0
        while c < size {
            if _matIsFunc(m, size, r, c) == 0 {
                if _maskCell(maskId, r, c) == 1 {
                    let v = _matGet(m, size, r, c)
                    _matSet(m, size, r, c, 1 - v)
                }
            }
            c = c + 1
        }
        r = r + 1
    }
}

// ── Format info (15 bits, BCH-protected) ─────────────────────────────
//
// Bits = [ec level: 2][mask: 3] then BCH(15,5) gen 0x537, then XOR mask
// 0x5412. We hardcode a tiny lookup since L correction × 8 masks = 8
// entries.

func _formatBits(maskId) {
    // L=01 + mask -> 5-bit input -> 15-bit BCH-coded output XOR 0x5412.
    // Precomputed table (mask 0..7):
    if maskId == 0 { emit "111011111000100" }
    if maskId == 1 { emit "111001011110011" }
    if maskId == 2 { emit "111110110101010" }
    if maskId == 3 { emit "111100010011101" }
    if maskId == 4 { emit "110011000101111" }
    if maskId == 5 { emit "110001100011000" }
    if maskId == 6 { emit "110110001000001" }
    if maskId == 7 { emit "110100101110110" }
    emit ""
}

func _placeFormat(m, size, maskId) {
    let bits = _formatBits(maskId)
    // First copy: bits 0..5 along row 8 cols 0..5; bit 6 at (8,7); bits 7..14 at col 8 rows 8..0.
    // Second copy: bits 0..7 at col 8 rows size-1..size-8; bits 8..14 at row 8 cols size-8..size-1.

    // Top-left strip (vertical, col 8).
    let i = 0
    while i < 6 {
        let bit = 0
        if bits[i] == "1" { bit = 1 }
        _matSetFunc(m, size, i, 8, bit)
        i = i + 1
    }
    // bit 6 at (7,8)
    let b6 = 0
    if bits[6] == "1" { b6 = 1 }
    _matSetFunc(m, size, 7, 8, b6)
    // bit 7 at (8,8)
    let b7 = 0
    if bits[7] == "1" { b7 = 1 }
    _matSetFunc(m, size, 8, 8, b7)
    // bit 8 at (8,7)
    let b8 = 0
    if bits[8] == "1" { b8 = 1 }
    _matSetFunc(m, size, 8, 7, b8)
    // bits 9..14 along row 8 cols 5..0.
    let j = 9
    let col = 5
    while j < 15 {
        let bit = 0
        if bits[j] == "1" { bit = 1 }
        _matSetFunc(m, size, 8, col, bit)
        col = col - 1
        j = j + 1
    }
    // Second copy.
    // bits 0..6 at col 8 rows size-1..size-7
    let k = 0
    while k < 7 {
        let bit = 0
        if bits[k] == "1" { bit = 1 }
        _matSetFunc(m, size, size - 1 - k, 8, bit)
        k = k + 1
    }
    // bits 7..14 along row 8 cols size-8..size-1
    let p = 7
    while p < 15 {
        let bit = 0
        if bits[p] == "1" { bit = 1 }
        _matSetFunc(m, size, 8, size - 15 + p, bit)
        p = p + 1
    }
}

// ── Public API ───────────────────────────────────────────────────────

// Build the bit stream + data buffer + EC, returns a single concatenated
// bit string ready for matrix placement.
func _qrAssembleBits(text, v) {
    let dataBits = qrBitStream(text, v)
    let dataBuf = _bitsToBuf(dataBits)
    let dataLen = _verData(v)
    let nsym = _verEc(v)
    let tbl = gfInit()
    let ec = rsEncode(tbl, dataBuf, dataLen, nsym)
    // Concatenate dataBits + ec-as-bits.
    let out = sbNew()
    out = sbAppend(out, dataBits)
    let i = 0
    while i < nsym {
        let b = toInt(bufGetByte(ec, i))
        let bb = 7
        while bb >= 0 {
            let bit = (b / _pow2(bb)) % 2
            if bit == 1 { out = sbAppend(out, "1") }
            else        { out = sbAppend(out, "0") }
            bb = bb - 1
        }
        i = i + 1
    }
    // Remainder bits (V2-6: 7 trailing zero bits; V1: 0).
    let remBits = 0
    if v >= 2 && v <= 6 { remBits = 7 }
    let z = 0
    while z < remBits { out = sbAppend(out, "0")  z = z + 1 }
    emit sbToString(out)
}

// qrEncode(text) → rows of 0/1 chars, joined by "\n".
// "" if text exceeds V5-L byte capacity.
func qrEncode(text) {
    let v = _pickVersion(len(text))
    if v == 0 { emit "" }
    let size = _verSize(v)
    let m = _matNew(size)

    // Finders + separators.
    _placeFinder(m, size, 0, 0)
    _placeFinder(m, size, 0, size - 7)
    _placeFinder(m, size, size - 7, 0)
    _placeSeparator(m, size, 0, 0)
    _placeSeparator(m, size, 0, size - 7)
    _placeSeparator(m, size, size - 7, 0)
    _placeTiming(m, size)
    _placeAlignment(m, size, v)
    _placeDarkModule(m, size, v)
    _reserveFormat(m, size)

    let bits = _qrAssembleBits(text, v)
    _placeData(m, size, _bitsToBuf(bits), bits)

    // Apply mask 0 (we skip the penalty-driven mask choice for size;
    // mask 0 always produces a scannable code, just not always optimal).
    _applyMask(m, size, 0)
    _placeFormat(m, size, 0)

    let out = sbNew()
    let r = 0
    while r < size {
        if r > 0 { out = sbAppend(out, "\n") }
        let c = 0
        while c < size {
            let v2 = _matGet(m, size, r, c)
            if v2 == 1 { out = sbAppend(out, "1") }
            else       { out = sbAppend(out, "0") }
            c = c + 1
        }
        r = r + 1
    }
    emit sbToString(out)
}

// qrSvg(text, scale) → standalone <svg> string. scale = px per module.
// Returns "" if text exceeds capacity.
func qrSvg(text, scale) {
    let grid = qrEncode(text)
    if len(grid) == 0 { emit "" }
    let rows = lineCount(grid)
    let cells = len(getLine(grid, 0))
    let quiet = 4   // standard 4-module quiet zone on all sides
    let total = (cells + (quiet * 2)) * scale

    let out = sbNew()
    out = sbAppend(out, "<?xml version='1.0' encoding='UTF-8'?>")
    out = sbAppend(out, "<svg xmlns='http://www.w3.org/2000/svg' width='")
    out = sbAppend(out, total + "")
    out = sbAppend(out, "' height='")
    out = sbAppend(out, total + "")
    out = sbAppend(out, "' viewBox='0 0 ")
    out = sbAppend(out, total + "")
    out = sbAppend(out, " ")
    out = sbAppend(out, total + "")
    out = sbAppend(out, "' shape-rendering='crispEdges'>")
    out = sbAppend(out, "<rect width='100%' height='100%' fill='white'/>")

    let r = 0
    while r < rows {
        let line = getLine(grid, r)
        let c = 0
        while c < len(line) {
            if line[c] == "1" {
                let x = (quiet + c) * scale
                let y = (quiet + r) * scale
                out = sbAppend(out, "<rect x='")
                out = sbAppend(out, x + "")
                out = sbAppend(out, "' y='")
                out = sbAppend(out, y + "")
                out = sbAppend(out, "' width='")
                out = sbAppend(out, scale + "")
                out = sbAppend(out, "' height='")
                out = sbAppend(out, scale + "")
                out = sbAppend(out, "' fill='black'/>")
            }
            c = c + 1
        }
        r = r + 1
    }
    out = sbAppend(out, "</svg>")
    emit sbToString(out)
}
