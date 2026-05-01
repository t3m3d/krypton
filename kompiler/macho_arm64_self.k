// macho_arm64_self.k — self-hosted arm64 Mach-O hello-world emitter.
//
// Goal: produce a runnable arm64 Mach-O for macOS Tahoe with NO external
// assembler/linker. Calls _puts from libSystem via dyld stubs. Runs after
// `codesign -s - --force` (in-Krypton ad-hoc signing is the next slice).
//
// This is v0.1: hardcoded "Hi\n" greeting, fixed _puts import, no IR.
// Once it runs, we generalize: parameterize the message, then wire to IR.
//
// Output binary layout (file offsets):
//   0x0000  mach_header_64 (32 B)
//   0x0020  load commands (12 LCs, sizeofcmds = 880)
//   0x0390  zero pad to 0x0460
//   0x0460  __TEXT,__text    : 8 arm64 instructions for _main (32 B)
//   0x0480  __TEXT,__stubs   : 1 stub for _puts (12 B)
//   0x048c  __TEXT,__cstring : "Hi\0" (3 B)
//   0x048f  zero pad to 0x4000
//   0x4000  __DATA_CONST,__got : 1 chained-bind ptr (8 B)
//   0x4008  zero pad to 0x8000
//   0x8000  __LINKEDIT
//           0x8000 chained_fixups (96 B, hardcoded for import "_puts")
//           0x8060 symtab          (3 nlist_64, 48 B; computed)
//           0x8090 indirect_symtab (2 × uint32, 8 B)
//           0x8098 strtab          (40 B, hardcoded)
//           0x80c0 code signature placeholder (256 B, filled by external codesign)
//   end
//
// Usage: kcc kompiler/macho_arm64_self.k <output_path>
// Then:  codesign -s - --force <output_path>
// Then:  <output_path>   → prints "Hi"

// ── byte/hex helpers (same idiom as elf.k) ──────────────────────────────────

func hexByte(n) {
    let HEX = "0123456789ABCDEF"
    let v = toInt(n)
    if v < 0 { v = v + 256 }
    if v > 255 { v = v % 256 }
    emit "x" + HEX[v / 16] + HEX[v % 16]
}

func hexWord(n) {
    let v = toInt(n)
    emit hexByte(v % 256) + hexByte((v / 256) % 256)
}

func hexDword(n) {
    let v = toInt(n)
    let b0 = v % 256
    if b0 < 0 { b0 = b0 + 256 }
    let q1 = v / 256
    if v % 256 != 0 && v < 0 { q1 = q1 - 1 }
    let b1 = q1 % 256
    if b1 < 0 { b1 = b1 + 256 }
    let q2 = q1 / 256
    if q1 % 256 != 0 && q1 < 0 { q2 = q2 - 1 }
    let b2 = q2 % 256
    if b2 < 0 { b2 = b2 + 256 }
    let q3 = q2 / 256
    if q2 % 256 != 0 && q2 < 0 { q3 = q3 - 1 }
    let b3 = q3 % 256
    if b3 < 0 { b3 = b3 + 256 }
    emit hexByte(b0) + hexByte(b1) + hexByte(b2) + hexByte(b3)
}

// hexQword: low 32 bits via hexDword(lo), then high 32 bits via hexDword(hi).
// All our 64-bit fields fit in either low-32 (offsets) or have a known high-32.
func hexQword2(lo, hi) { emit hexDword(lo) + hexDword(hi) }
func hexQword(n) { emit hexDword(n) + hexDword(0) }

func hexPad(n) {
    let out = ""
    let i = 0
    while i < n {
        out = out + hexByte(0)
        i += 1
    }
    emit out
}

func hexStr(s) {
    let out = ""
    let i = 0
    while i < len(s) {
        out = out + hexByte(charCode(s[i]))
        i += 1
    }
    emit out
}

func hexBytesLen(s) { emit len(s) / 3 }

// ── Mach-O constants ────────────────────────────────────────────────────────

func MH_MAGIC_64() { emit 0xfeedfacf }
func CPU_TYPE_ARM64() { emit 0x0100000c }      // = 16777228
func MH_EXECUTE() { emit 2 }
func MH_NOUNDEFS() { emit 0x1 }
func MH_DYLDLINK() { emit 0x4 }
func MH_TWOLEVEL() { emit 0x80 }
func MH_PIE() { emit 0x200000 }

// LC_REQ_DYLD = 0x80000000; some commands OR it in
func LC_SEGMENT_64() { emit 0x19 }
func LC_SYMTAB() { emit 0x2 }
func LC_DYSYMTAB() { emit 0xb }
func LC_LOAD_DYLIB() { emit 0xc }
func LC_LOAD_DYLINKER() { emit 0xe }
func LC_BUILD_VERSION() { emit 0x32 }
func LC_MAIN() { emit 0x80000028 }
func LC_DYLD_CHAINED_FIXUPS() { emit 0x80000034 }
func LC_CODE_SIGNATURE() { emit 0x1d }

// VM protections
func VM_PROT_READ() { emit 1 }
func VM_PROT_WRITE() { emit 2 }
func VM_PROT_EXECUTE() { emit 4 }

// Section flags
func S_REGULAR() { emit 0x0 }
func S_CSTRING_LITERALS() { emit 0x2 }
func S_NON_LAZY_SYMBOL_POINTERS() { emit 0x6 }
func S_SYMBOL_STUBS() { emit 0x8 }
func S_ATTR_SOME_INSTRUCTIONS() { emit 0x00000400 }
func S_ATTR_PURE_INSTRUCTIONS() { emit 0x80000000 }
// __text:   PURE | SOME = 0x80000400 (type S_REGULAR)
// __stubs:  PURE | SOME | type S_SYMBOL_STUBS = 0x80000408
// __cstring: type S_CSTRING_LITERALS = 0x00000002
// __got:    type S_NON_LAZY_SYMBOL_POINTERS = 0x00000006

// ── Layout constants (file offsets and vaddrs) ──────────────────────────────

func TEXT_VADDR()         { emit 0x100000000 }
func DATA_CONST_VADDR()   { emit 0x100004000 }
func LINKEDIT_VADDR()     { emit 0x100008000 }
func PAGEZERO_VMSIZE()    { emit 0x100000000 }
func SEG_PAGE_SIZE()      { emit 0x4000 }       // 16 KB

func TEXT_FILE_OFF()      { emit 0 }
func DATA_FILE_OFF()      { emit 0x4000 }
func LINKEDIT_FILE_OFF()  { emit 0x8000 }

// Offsets/sizes are computed by the driver based on input IR (or the
// hello-world default) and stashed in module-level lets so the LC emitters
// can read them. All "fixed-by-page-layout" values stay constant.

let g_TEXT_SIZE       = 32          // bytes of __text (computed from IR)
let g_CSTRING_SIZE    = 3           // total bytes of __cstring (computed)
let g_CODESIG_SIZE    = 212         // computed: 20 + 88 + 8 + nCodeSlots*32
let g_FILE_TOTAL_SIZE = 33172       // computed: CODESIG_OFF + CODESIG_SIZE

func TEXT_OFF()           { emit 0x460 }        // fixed: just past header+LCs
func TEXT_SIZE()          { emit g_TEXT_SIZE }
func STUBS_OFF()          { emit 0x460 + g_TEXT_SIZE }
func STUBS_SIZE()         { emit 12 }           // 1 stub for _puts × 12 bytes
func CSTRING_OFF()        { emit 0x460 + g_TEXT_SIZE + 12 }
func CSTRING_SIZE()       { emit g_CSTRING_SIZE }
func GOT_OFF()            { emit 0x4000 }
func GOT_SIZE()           { emit 8 }

func CHAINED_FIXUPS_OFF() { emit 0x8000 }
func CHAINED_FIXUPS_SIZE() { emit 96 }
func SYMTAB_OFF()         { emit 0x8060 }
func NSYMS()              { emit 3 }
func SYMTAB_SIZE()        { emit 48 }           // 3 × nlist_64 (16 bytes each)
func INDIRECT_SYMTAB_OFF() { emit 0x8090 }
func NINDIRECTSYMS()      { emit 2 }
func INDIRECT_SYMTAB_SIZE() { emit 8 }
func STRTAB_OFF()         { emit 0x8098 }
func STRTAB_SIZE()        { emit 40 }           // padded to 8

func CODESIG_OFF()        { emit 0x80c0 }       // 16-byte aligned past LINKEDIT metadata
func CODESIG_SIZE()       { emit g_CODESIG_SIZE }
func FILE_TOTAL_SIZE()    { emit g_FILE_TOTAL_SIZE }

// strtab byte offsets for our 3 fixed symbols
func STRX_MH()    { emit 2 }   // "__mh_execute_header"
func STRX_MAIN()  { emit 22 }  // "_main"
func STRX_PUTS()  { emit 28 }  // "_puts"

// ── byte/word readers over the "xHH"-encoded byte string ───────────────────
// hexByte() returns "xHH" (3 chars). To read a byte at byte-index i, we look
// at chars [i*3+1 .. i*3+2] and parse as hex.

func hexCharVal(c) {
    if c == "0" { emit 0 }
    if c == "1" { emit 1 }
    if c == "2" { emit 2 }
    if c == "3" { emit 3 }
    if c == "4" { emit 4 }
    if c == "5" { emit 5 }
    if c == "6" { emit 6 }
    if c == "7" { emit 7 }
    if c == "8" { emit 8 }
    if c == "9" { emit 9 }
    if c == "A" { emit 10 }
    if c == "B" { emit 11 }
    if c == "C" { emit 12 }
    if c == "D" { emit 13 }
    if c == "E" { emit 14 }
    if c == "F" { emit 15 }
    emit 0
}

func byteAtHex(hex, i) {
    let p = i * 3
    let hi = hexCharVal(hex[p + 1])
    let lo = hexCharVal(hex[p + 2])
    emit hi * 16 + lo
}

// 32-bit big-endian word at byte index i. Krypton ints are 32-bit signed but
// the bit pattern is what matters; bitAnd/bitShr/bitShl from compile.k cast
// to unsigned int internally so this works for high-bit-set values too.
func u32BeAtHex(hex, i) {
    let b0 = byteAtHex(hex, i)
    let b1 = byteAtHex(hex, i + 1)
    let b2 = byteAtHex(hex, i + 2)
    let b3 = byteAtHex(hex, i + 3)
    emit b0 * 0x1000000 + b1 * 0x10000 + b2 * 0x100 + b3
}

// Emit a 32-bit BE word as 4 hex bytes (for SHA-256 output and for big-endian
// fields in CodeDirectory / SuperBlob).
func hexDwordBe(n) {
    let b3 = bitAnd(bitShr(n, 24), 0xff)
    let b2 = bitAnd(bitShr(n, 16), 0xff)
    let b1 = bitAnd(bitShr(n, 8),  0xff)
    let b0 = bitAnd(n, 0xff)
    emit hexByte(b3) + hexByte(b2) + hexByte(b1) + hexByte(b0)
}

// ── unsigned 32-bit primitives (use language builtins; runtime casts to uint) ─
// rotr — bitwise rotate right by n in [1, 31]
func u32_rotr(v, n) { emit bitOr(bitShr(v, n), bitShl(v, 32 - n)) }
// shr — logical right shift (already unsigned via kr_bitshr)
func u32_shr(v, n) { emit bitShr(v, n) }
// add wrapping mod 2^32 — Krypton's signed add naturally wraps in 32 bits
func u32_add(a, b) { emit a + b }

// ── SHA-256 ────────────────────────────────────────────────────────────────
// Hashes byteCount bytes of `hex` starting at byte index `byteOff`.
// Returns the 32-byte digest as 96 hex chars (xHH × 32).

// Round constants K[0..63]
func sha256_K(i) {
    if i == 0  { emit 0x428a2f98 }
    if i == 1  { emit 0x71374491 }
    if i == 2  { emit 0xb5c0fbcf }
    if i == 3  { emit 0xe9b5dba5 }
    if i == 4  { emit 0x3956c25b }
    if i == 5  { emit 0x59f111f1 }
    if i == 6  { emit 0x923f82a4 }
    if i == 7  { emit 0xab1c5ed5 }
    if i == 8  { emit 0xd807aa98 }
    if i == 9  { emit 0x12835b01 }
    if i == 10 { emit 0x243185be }
    if i == 11 { emit 0x550c7dc3 }
    if i == 12 { emit 0x72be5d74 }
    if i == 13 { emit 0x80deb1fe }
    if i == 14 { emit 0x9bdc06a7 }
    if i == 15 { emit 0xc19bf174 }
    if i == 16 { emit 0xe49b69c1 }
    if i == 17 { emit 0xefbe4786 }
    if i == 18 { emit 0x0fc19dc6 }
    if i == 19 { emit 0x240ca1cc }
    if i == 20 { emit 0x2de92c6f }
    if i == 21 { emit 0x4a7484aa }
    if i == 22 { emit 0x5cb0a9dc }
    if i == 23 { emit 0x76f988da }
    if i == 24 { emit 0x983e5152 }
    if i == 25 { emit 0xa831c66d }
    if i == 26 { emit 0xb00327c8 }
    if i == 27 { emit 0xbf597fc7 }
    if i == 28 { emit 0xc6e00bf3 }
    if i == 29 { emit 0xd5a79147 }
    if i == 30 { emit 0x06ca6351 }
    if i == 31 { emit 0x14292967 }
    if i == 32 { emit 0x27b70a85 }
    if i == 33 { emit 0x2e1b2138 }
    if i == 34 { emit 0x4d2c6dfc }
    if i == 35 { emit 0x53380d13 }
    if i == 36 { emit 0x650a7354 }
    if i == 37 { emit 0x766a0abb }
    if i == 38 { emit 0x81c2c92e }
    if i == 39 { emit 0x92722c85 }
    if i == 40 { emit 0xa2bfe8a1 }
    if i == 41 { emit 0xa81a664b }
    if i == 42 { emit 0xc24b8b70 }
    if i == 43 { emit 0xc76c51a3 }
    if i == 44 { emit 0xd192e819 }
    if i == 45 { emit 0xd6990624 }
    if i == 46 { emit 0xf40e3585 }
    if i == 47 { emit 0x106aa070 }
    if i == 48 { emit 0x19a4c116 }
    if i == 49 { emit 0x1e376c08 }
    if i == 50 { emit 0x2748774c }
    if i == 51 { emit 0x34b0bcb5 }
    if i == 52 { emit 0x391c0cb3 }
    if i == 53 { emit 0x4ed8aa4a }
    if i == 54 { emit 0x5b9cca4f }
    if i == 55 { emit 0x682e6ff3 }
    if i == 56 { emit 0x748f82ee }
    if i == 57 { emit 0x78a5636f }
    if i == 58 { emit 0x84c87814 }
    if i == 59 { emit 0x8cc70208 }
    if i == 60 { emit 0x90befffa }
    if i == 61 { emit 0xa4506ceb }
    if i == 62 { emit 0xbef9a3f7 }
    if i == 63 { emit 0xc67178f2 }
    emit 0
}

// Build a 16-line "h0\nh1\n...h7" string holding the running hash state.
// Initial values (FIPS 180-4 §5.3.3):
func sha256_initState() {
    let s = ""
    s = s + "1779033703\n"      // 0x6a09e667
    s = s + "-1150833019\n"     // 0xbb67ae85 (signed)
    s = s + "1013904242\n"      // 0x3c6ef372
    s = s + "-1521486534\n"     // 0xa54ff53a
    s = s + "1359893119\n"      // 0x510e527f
    s = s + "-1694144372\n"     // 0x9b05688c
    s = s + "528734635\n"       // 0x1f83d9ab
    s = s + "1541459225"        // 0x5be0cd19
    emit s
}

// Process one 512-bit (64-byte) chunk. `chunkHex` is 192 hex chars (64 × 3).
// `state` is the 8-word state (newline-separated as decimals).
// Returns the updated state in the same format.
func sha256_processChunk(state, chunkHex) {
    // Load 16 words from chunk (BE) and extend to 64 words.
    // We store W[i] in local vars W0..W63 conceptually, but Krypton has no
    // arrays of integers — use a newline-separated string of decimals.
    let W = ""
    let i = 0
    while i < 16 {
        let w = u32BeAtHex(chunkHex, i * 4)
        if i > 0 { W = W + "\n" }
        W = W + ("" + w)
        i += 1
    }
    while i < 64 {
        let w15 = toInt(getLine(W, i - 15))
        let w2  = toInt(getLine(W, i - 2))
        let w16 = toInt(getLine(W, i - 16))
        let w7  = toInt(getLine(W, i - 7))
        // sigma0(x) = ROTR(x,7) XOR ROTR(x,18) XOR SHR(x,3)
        let s0 = bitXor(bitXor(u32_rotr(w15, 7), u32_rotr(w15, 18)), bitShr(w15, 3))
        // sigma1(x) = ROTR(x,17) XOR ROTR(x,19) XOR SHR(x,10)
        let s1 = bitXor(bitXor(u32_rotr(w2, 17), u32_rotr(w2, 19)), bitShr(w2, 10))
        let wi = w16 + s0 + w7 + s1
        W = W + "\n" + ("" + wi)
        i += 1
    }
    // Init working vars
    let a = toInt(getLine(state, 0))
    let b = toInt(getLine(state, 1))
    let c = toInt(getLine(state, 2))
    let d = toInt(getLine(state, 3))
    let e = toInt(getLine(state, 4))
    let f = toInt(getLine(state, 5))
    let g = toInt(getLine(state, 6))
    let h = toInt(getLine(state, 7))
    // 64 rounds
    let r = 0
    while r < 64 {
        let S1 = bitXor(bitXor(u32_rotr(e, 6), u32_rotr(e, 11)), u32_rotr(e, 25))
        let ch = bitXor(bitAnd(e, f), bitAnd(bitNot(e), g))
        let wr = toInt(getLine(W, r))
        let T1 = h + S1 + ch + sha256_K(r) + wr
        let S0 = bitXor(bitXor(u32_rotr(a, 2), u32_rotr(a, 13)), u32_rotr(a, 22))
        let mj = bitXor(bitXor(bitAnd(a, b), bitAnd(a, c)), bitAnd(b, c))
        let T2 = S0 + mj
        h = g
        g = f
        f = e
        e = d + T1
        d = c
        c = b
        b = a
        a = T1 + T2
        r += 1
    }
    // Update state
    let h0 = toInt(getLine(state, 0)) + a
    let h1 = toInt(getLine(state, 1)) + b
    let h2 = toInt(getLine(state, 2)) + c
    let h3 = toInt(getLine(state, 3)) + d
    let h4 = toInt(getLine(state, 4)) + e
    let h5 = toInt(getLine(state, 5)) + f
    let h6 = toInt(getLine(state, 6)) + g
    let h7 = toInt(getLine(state, 7)) + h
    emit ("" + h0) + "\n" + ("" + h1) + "\n" + ("" + h2) + "\n" + ("" + h3) + "\n" + ("" + h4) + "\n" + ("" + h5) + "\n" + ("" + h6) + "\n" + ("" + h7)
}

// Hash byteCount bytes of `data` (a hex-encoded byte string) starting at byteOff.
// Returns 32-byte SHA-256 digest as 96 hex chars.
func sha256_hex(data, byteOff, byteCount) {
    // We need to feed 64-byte chunks. The padding rule (FIPS 180-4 §5.1.1):
    //   append 1 bit, then k zero bits where (l + 1 + k) ≡ 448 mod 512,
    //   then 64-bit BE message length in bits.
    // For our use, byteCount is up to 16384 (= one OS page) so all messages
    // fit: total padded length = byteCount + 1 + zero_pad + 8 ≡ 0 (mod 64).
    // Build the padded message into a hex-encoded string.
    let msg = ""
    let i = 0
    while i < byteCount {
        msg = msg + hexByte(byteAtHex(data, byteOff + i))
        i += 1
    }
    // Append 0x80 sentinel
    msg = msg + hexByte(0x80)
    // Append zero bytes until length ≡ 56 (mod 64)
    let padLen = byteCount + 1
    while (padLen % 64) != 56 {
        msg = msg + hexByte(0)
        padLen += 1
    }
    // Append 64-bit BE length in bits
    let bits = byteCount * 8
    msg = msg + hexByte(0) + hexByte(0) + hexByte(0) + hexByte(0)
    msg = msg + hexDwordBe(bits)
    // Process each 64-byte chunk
    let state = sha256_initState()
    let totalBytes = hexBytesLen(msg)
    let off = 0
    while off < totalBytes {
        // Extract 64-byte chunk as a hex string of length 192
        let chunkHex = ""
        let cb = 0
        while cb < 64 {
            chunkHex = chunkHex + hexByte(byteAtHex(msg, off + cb))
            cb += 1
        }
        state = sha256_processChunk(state, chunkHex)
        off += 64
    }
    // Output state as 32 BE bytes
    let out = ""
    let si = 0
    while si < 8 {
        out = out + hexDwordBe(toInt(getLine(state, si)))
        si += 1
    }
    emit out
}

// ── arm64 instruction encodings (32-bit little-endian) ──────────────────────
// Each emit returns 4 hex bytes via hexDword.

// stp x29, x30, [sp, #-16]!   →  0xa9bf7bfd
func arm64_stp_fp_lr_pre16()    { emit hexDword(0xa9bf7bfd) }
// mov x29, sp                  →  0x910003fd
func arm64_mov_fp_sp()          { emit hexDword(0x910003fd) }
// adrp Rd, #imm21 (page rel)
func arm64_adrp(rd, imm21) {
    let immlo = imm21 % 4
    let immhi = imm21 / 4
    let insn = 0x90000000
    insn = insn + (immlo * 0x20000000)   // bits[30:29]
    insn = insn + (immhi * 0x20)         // bits[23:5]
    insn = insn + rd                     // bits[4:0]
    emit hexDword(insn)
}
// add Rd, Rn, #imm12 (64-bit, no shift)
func arm64_add_imm(rd, rn, imm12) {
    let insn = 0x91000000
    insn = insn + (imm12 * 0x400)        // bits[21:10]
    insn = insn + (rn * 0x20)            // bits[9:5]
    insn = insn + rd
    emit hexDword(insn)
}
// bl rel26 (rel26 = byte_delta / 4, in instruction units)
func arm64_bl(rel26) {
    let mask = 0x03ffffff
    let r = rel26
    if r < 0 { r = r + 0x04000000 }      // 2's complement into 26 bits
    r = r % 0x04000000
    emit hexDword(0x94000000 + r)
}
// movz w0, #0   →  0x52800000
func arm64_movz_w0_zero()       { emit hexDword(0x52800000) }
// ldp x29, x30, [sp], #16   →  0xa8c17bfd
func arm64_ldp_fp_lr_post16()   { emit hexDword(0xa8c17bfd) }
// ret                       →  0xd65f03c0
func arm64_ret()                { emit hexDword(0xd65f03c0) }

// ldr Xt, [Xn, #imm12_scaled]  (64-bit, unsigned offset)
func arm64_ldr_imm(rt, rn, imm12_scaled) {
    let insn = 0xf9400000
    insn = insn + (imm12_scaled * 0x400) // bits[21:10]
    insn = insn + (rn * 0x20)
    insn = insn + rt
    emit hexDword(insn)
}
// br Xn  →  0xd61f0000 | (Xn << 5)
func arm64_br(rn) { emit hexDword(0xd61f0000 + rn * 0x20) }

// str Xt, [sp, #-16]!   (push Xt to eval stack)  → 0xf81f0fe0 | Rt
func arm64_push(rt) { emit hexDword(0xf81f0fe0 + rt) }
// ldr Xt, [sp], #16     (pop top of eval stack into Xt) → 0xf84107e0 | Rt
func arm64_pop(rt)  { emit hexDword(0xf84107e0 + rt) }
// Convenience aliases for x0 (most common usage)
func arm64_push_x0() { emit arm64_push(0) }
func arm64_pop_x0()  { emit arm64_pop(0) }

// sub sp, sp, #imm12 (64-bit)  → 0xd10003ff | (imm12 << 10)
func arm64_sub_sp(imm12) {
    let insn = 0xd10003ff
    insn = insn + (imm12 * 0x400)
    emit hexDword(insn)
}
// add sp, sp, #imm12 (64-bit)  → 0x910003ff | (imm12 << 10)
func arm64_add_sp(imm12) {
    let insn = 0x910003ff
    insn = insn + (imm12 * 0x400)
    emit hexDword(insn)
}

// stur Xt, [Xn, #imm9]  (signed 9-bit unscaled offset, 64-bit)
//   encoding: 0xf8000000 | (imm9 << 12) | (Rn << 5) | Rt
func arm64_stur(rt, rn, imm9) {
    let i = imm9
    if i < 0 { i = i + 512 }   // 9-bit two's complement
    i = i % 512
    let insn = 0xf8000000
    insn = insn + (i * 0x1000)
    insn = insn + (rn * 0x20)
    insn = insn + rt
    emit hexDword(insn)
}
// ldur Xt, [Xn, #imm9]  → 0xf8400000 | (imm9 << 12) | (Rn << 5) | Rt
func arm64_ldur(rt, rn, imm9) {
    let i = imm9
    if i < 0 { i = i + 512 }
    i = i % 512
    let insn = 0xf8400000
    insn = insn + (i * 0x1000)
    insn = insn + (rn * 0x20)
    insn = insn + rt
    emit hexDword(insn)
}

// movz Wd, #imm16  (32-bit, no shift)  → 0x52800000 | (imm16 << 5) | Rd
func arm64_movz_w_imm(rd, imm16) {
    let insn = 0x52800000
    insn = insn + (imm16 * 0x20)
    insn = insn + rd
    emit hexDword(insn)
}
// movz Xd, #imm16 (64-bit, no shift)  → 0xd2800000 | (imm16 << 5) | Rd
func arm64_movz_x_imm(rd, imm16) {
    let insn = 0xd2800000
    insn = insn + (imm16 * 0x20)
    insn = insn + rd
    emit hexDword(insn)
}
// movn Xd, #imm16 (64-bit, no shift) — Rd = ~(imm16) sign-extended → 0x92800000 | (imm16 << 5) | Rd
func arm64_movn_x_imm(rd, imm16) {
    let insn = 0x92800000
    insn = insn + (imm16 * 0x20)
    insn = insn + rd
    emit hexDword(insn)
}

// add Xd, Xn, Xm (64-bit, no shift) → 0x8b000000 | (Rm<<16) | (Rn<<5) | Rd
func arm64_add_xxx(rd, rn, rm) {
    let insn = 0x8b000000 + (rm * 0x10000) + (rn * 0x20) + rd
    emit hexDword(insn)
}
// sub Xd, Xn, Xm (64-bit, no shift) → 0xcb000000 | (Rm<<16) | (Rn<<5) | Rd
func arm64_sub_xxx(rd, rn, rm) {
    let insn = 0xcb000000 + (rm * 0x10000) + (rn * 0x20) + rd
    emit hexDword(insn)
}
// mul Xd, Xn, Xm (madd Xd, Xn, Xm, xzr) → 0x9b007c00 | (Rm<<16) | (Rn<<5) | Rd
func arm64_mul_xxx(rd, rn, rm) {
    let insn = 0x9b007c00 + (rm * 0x10000) + (rn * 0x20) + rd
    emit hexDword(insn)
}
// sdiv Xd, Xn, Xm (signed divide) → 0x9ac00c00 | (Rm<<16) | (Rn<<5) | Rd
func arm64_sdiv_xxx(rd, rn, rm) {
    let insn = 0x9ac00c00 + (rm * 0x10000) + (rn * 0x20) + rd
    emit hexDword(insn)
}
// msub Xd, Xn, Xm, Xa  →  Rd = Ra - Rn*Rm   → 0x9b008000 | (Rm<<16) | (Ra<<10) | (Rn<<5) | Rd
func arm64_msub_xxxx(rd, rn, rm, ra) {
    let insn = 0x9b008000 + (rm * 0x10000) + (ra * 0x400) + (rn * 0x20) + rd
    emit hexDword(insn)
}
// svc #imm16 → 0xd4000001 | (imm16 << 5)
func arm64_svc(imm16) {
    let insn = 0xd4000001 + (imm16 * 0x20)
    emit hexDword(insn)
}

// cmp Xn, Xm  (alias for `subs xzr, Xn, Xm`) → 0xeb00001f | (Rm<<16) | (Rn<<5)
func arm64_cmp_xx(rn, rm) {
    emit hexDword(0xeb00001f + (rm * 0x10000) + (rn * 0x20))
}
// cset Xd, <cond>  (alias for `csinc Xd, xzr, xzr, invert(cond)`)
//   csinc encoding: 0x9a800400 | (Rm<<16) | (cond<<12) | (Rn<<5) | Rd
//   For CSET we set Rm=Rn=xzr(31) and use invert(cond) — flipping bit 0 of cond inverts.
// AArch64 cond codes used here: EQ=0, NE=1, GE=0xA, LT=0xB, GT=0xC, LE=0xD.
func arm64_cset(rd, cond) {
    let inv = cond
    if (cond % 2) == 0 { inv = cond + 1 } else { inv = cond - 1 }
    emit hexDword(0x9a800400 + (31 * 0x10000) + (inv * 0x1000) + (31 * 0x20) + rd)
}
// b <imm26>  (unconditional branch, signed 26-bit in instruction units)
//   encoding: 0x14000000 | (imm26 & 0x3ffffff)
func arm64_b(rel) {
    let r = rel
    if r < 0 { r = r + 0x4000000 }
    r = r % 0x4000000
    emit hexDword(0x14000000 + r)
}
// cbz Xt, <imm19>  (compare and branch on zero, signed 19-bit)
//   encoding: 0xb4000000 | ((imm19 & 0x7ffff) << 5) | Rt
func arm64_cbz(rt, rel) {
    let r = rel
    if r < 0 { r = r + 0x80000 }
    r = r % 0x80000
    emit hexDword(0xb4000000 + (r * 0x20) + rt)
}

// ── simple-subset IR parser (slice 3a/3b) ───────────────────────────────────
// Supports: FUNC __main__ 0 / LOCAL <name> / PUSH "literal" / STORE <name> /
//           LOAD <name> / BUILTIN kp 1 / POP / END.
// Layout-string format:
//   line 0: nKpCalls
//   line 1: nStrings
//   line 2: nLocals
//   lines 3..3+nStrings-1:  each unique string content
//   lines 3+nStrings..3+nStrings+nLocals-1: each unique local name
//   remaining lines: normalized ops, one per line:
//     PUSH_STR <idx> | LOAD_LOCAL <idx> | STORE_LOCAL <idx> |
//     BUILTIN_KP | POP | END

// Helper: find or add a name to a newline-separated list. Returns 0-based idx
// (the result is the modified list with the new entry appended if not found,
// followed by "|" then the index, allowing the caller to extract both).
func internIntoList(list, count, name) {
    let i = 0
    while i < count {
        if getLine(list, i) == name {
            emit list + "|" + i
        }
        i += 1
    }
    let newList = list
    if count > 0 { newList = newList + "\n" }
    newList = newList + name
    emit newList + "|" + count
}

func parseSimpleIR(ir) {
    let strings = ""
    let nStrings = 0
    let locals = ""
    let nLocals = 0
    let opSb = sbNew()
    let nOps = 0
    let nKp = 0
    let nl = lineCount(ir)
    let i = 0
    while i < nl {
        let line = trim(getLine(ir, i))
        if len(line) > 0 {
            if line[0] != ";" {
                let j = 0
                while j < len(line) && line[j] != " " { j += 1 }
                let op = substring(line, 0, j)
                let rest = ""
                if j < len(line) { rest = trim(substring(line, j + 1, len(line))) }

                if op == "PUSH" {
                    if len(rest) > 0 {
                        if rest[0] == "\"" {
                            let content = ""
                            let k = 1
                            while k < len(rest) && rest[k] != "\"" {
                                content = content + rest[k]
                                k += 1
                            }
                            let res = internIntoList(strings, nStrings, content)
                            // res is "list|idx" — split on the last "|"
                            let bar = len(res) - 1
                            while bar >= 0 && res[bar] != "|" { bar -= 1 }
                            strings = substring(res, 0, bar)
                            let idx = toInt(substring(res, bar + 1, len(res)))
                            if idx == nStrings { nStrings += 1 }
                            if nOps > 0 { opSb = sbAppend(opSb, "\n") }
                            opSb = sbAppend(opSb, "PUSH_STR " + idx)
                            nOps += 1
                        } else {
                            // Integer literal: keep as-is (might be negative)
                            if nOps > 0 { opSb = sbAppend(opSb, "\n") }
                            opSb = sbAppend(opSb, "PUSH_INT " + rest)
                            nOps += 1
                        }
                    }
                } else if op == "ADD" {
                    if nOps > 0 { opSb = sbAppend(opSb, "\n") }
                    opSb = sbAppend(opSb, "ADD")
                    nOps += 1
                } else if op == "SUB" {
                    if nOps > 0 { opSb = sbAppend(opSb, "\n") }
                    opSb = sbAppend(opSb, "SUB")
                    nOps += 1
                } else if op == "MUL" {
                    if nOps > 0 { opSb = sbAppend(opSb, "\n") }
                    opSb = sbAppend(opSb, "MUL")
                    nOps += 1
                } else if op == "DIV" {
                    if nOps > 0 { opSb = sbAppend(opSb, "\n") }
                    opSb = sbAppend(opSb, "DIV")
                    nOps += 1
                } else if op == "MOD" {
                    if nOps > 0 { opSb = sbAppend(opSb, "\n") }
                    opSb = sbAppend(opSb, "MOD")
                    nOps += 1
                } else if op == "LT" || op == "GT" || op == "EQ" {
                    if nOps > 0 { opSb = sbAppend(opSb, "\n") }
                    opSb = sbAppend(opSb, op)
                    nOps += 1
                } else if op == "LTE" {
                    if nOps > 0 { opSb = sbAppend(opSb, "\n") }
                    opSb = sbAppend(opSb, "LE")    // normalize to AArch64 cond family
                    nOps += 1
                } else if op == "GTE" {
                    if nOps > 0 { opSb = sbAppend(opSb, "\n") }
                    opSb = sbAppend(opSb, "GE")
                    nOps += 1
                } else if op == "NEQ" {
                    if nOps > 0 { opSb = sbAppend(opSb, "\n") }
                    opSb = sbAppend(opSb, "NE")
                    nOps += 1
                } else if op == "LABEL" {
                    if nOps > 0 { opSb = sbAppend(opSb, "\n") }
                    opSb = sbAppend(opSb, "LABEL " + rest)
                    nOps += 1
                } else if op == "JUMP" {
                    if nOps > 0 { opSb = sbAppend(opSb, "\n") }
                    opSb = sbAppend(opSb, "JUMP " + rest)
                    nOps += 1
                } else if op == "JUMPIFNOT" {
                    if nOps > 0 { opSb = sbAppend(opSb, "\n") }
                    opSb = sbAppend(opSb, "JUMPIFNOT " + rest)
                    nOps += 1
                } else if op == "LOCAL" {
                    let res = internIntoList(locals, nLocals, rest)
                    let bar = len(res) - 1
                    while bar >= 0 && res[bar] != "|" { bar -= 1 }
                    locals = substring(res, 0, bar)
                    let idx = toInt(substring(res, bar + 1, len(res)))
                    if idx == nLocals { nLocals += 1 }
                    // LOCAL emits no op — just declares the slot
                } else if op == "LOAD" {
                    // Auto-add if not declared (defensive)
                    let res = internIntoList(locals, nLocals, rest)
                    let bar = len(res) - 1
                    while bar >= 0 && res[bar] != "|" { bar -= 1 }
                    locals = substring(res, 0, bar)
                    let idx = toInt(substring(res, bar + 1, len(res)))
                    if idx == nLocals { nLocals += 1 }
                    if nOps > 0 { opSb = sbAppend(opSb, "\n") }
                    opSb = sbAppend(opSb, "LOAD_LOCAL " + idx)
                    nOps += 1
                } else if op == "STORE" {
                    let res = internIntoList(locals, nLocals, rest)
                    let bar = len(res) - 1
                    while bar >= 0 && res[bar] != "|" { bar -= 1 }
                    locals = substring(res, 0, bar)
                    let idx = toInt(substring(res, bar + 1, len(res)))
                    if idx == nLocals { nLocals += 1 }
                    if nOps > 0 { opSb = sbAppend(opSb, "\n") }
                    opSb = sbAppend(opSb, "STORE_LOCAL " + idx)
                    nOps += 1
                } else if op == "BUILTIN" {
                    let bj = 0
                    while bj < len(rest) && rest[bj] != " " { bj += 1 }
                    let bname = substring(rest, 0, bj)
                    if bname == "kp" {
                        if nOps > 0 { opSb = sbAppend(opSb, "\n") }
                        opSb = sbAppend(opSb, "BUILTIN_KP")
                        nOps += 1
                        nKp += 1
                    } else if bname == "exit" {
                        if nOps > 0 { opSb = sbAppend(opSb, "\n") }
                        opSb = sbAppend(opSb, "BUILTIN_EXIT")
                        nOps += 1
                    }
                } else if op == "POP" {
                    if nOps > 0 { opSb = sbAppend(opSb, "\n") }
                    opSb = sbAppend(opSb, "POP")
                    nOps += 1
                } else if op == "END" {
                    if nOps > 0 { opSb = sbAppend(opSb, "\n") }
                    opSb = sbAppend(opSb, "END")
                    nOps += 1
                }
            }
        }
        i += 1
    }
    let r = "" + nKp + "\n" + nStrings + "\n" + nLocals + "\n"
    if nStrings > 0 { r = r + strings + "\n" }
    if nLocals > 0  { r = r + locals + "\n" }
    r = r + sbToString(opSb)
    emit r
}

// Lines 0..2 of the parsed format are nKp / nStrings / nLocals.
// String entries start at line 3, locals after that, ops after locals.
func irStringStart() { emit 3 }
func irLocalStart(parsed) {
    let nStrings = toInt(getLine(parsed, 1))
    emit 3 + nStrings
}
func irOpStart(parsed) {
    let nStrings = toInt(getLine(parsed, 1))
    let nLocals = toInt(getLine(parsed, 2))
    emit 3 + nStrings + nLocals
}

// Compute byte offset within __cstring for each interned string.
// Returns a newline-separated list of integer offsets (in declaration order).
func computeStringOffsets(parsed) {
    let nStrings = toInt(getLine(parsed, 1))
    let r = ""
    let off = 0
    let si = 0
    while si < nStrings {
        if si > 0 { r = r + "\n" }
        r = r + ("" + off)
        let s = getLine(parsed, irStringStart() + si)
        off = off + len(s) + 1     // +1 for NUL
        si += 1
    }
    emit r
}

// Total bytes of __cstring (sum of len+1 for each string).
func computeCStringSize(parsed) {
    let nStrings = toInt(getLine(parsed, 1))
    let off = 0
    let si = 0
    while si < nStrings {
        let s = getLine(parsed, irStringStart() + si)
        off = off + len(s) + 1
        si += 1
    }
    emit off
}

// Emit the __cstring section bytes from the parsed IR.
func emitCStringFromIR(parsed) {
    let nStrings = toInt(getLine(parsed, 1))
    let s = ""
    let si = 0
    while si < nStrings {
        let str = getLine(parsed, irStringStart() + si)
        s = s + asciiToHex(str) + hexByte(0)
        si += 1
    }
    emit s
}

// Frame size for locals: 8 bytes per local, rounded up to 16.
//   nLocals = 0 → 0
//   nLocals = 1 → 16
//   nLocals = 2 → 16
//   nLocals = 3 → 32
func computeFrameSize(parsed) {
    let nLocals = toInt(getLine(parsed, 2))
    if nLocals == 0 { emit 0 }
    emit ((nLocals + 1) / 2) * 16
}

// Per-op instruction count under the slice 3b/3c eval-stack model.
//   PUSH_STR     : 3  (adrp + add + str push)
//   PUSH_INT     : 2  (movz/movn + str push)  [for 16-bit values]
//   LOAD_LOCAL   : 2  (ldur + str push)
//   STORE_LOCAL  : 2  (ldr pop + stur)
//   ADD/SUB/MUL/DIV : 4 (ldr pop b + ldr pop a + op x0,x1,x0 + str push)
//   MOD          : 5  (ldr + ldr + sdiv + msub + str)
//   BUILTIN_KP   : 4  (ldr pop + bl + movz + str push 0)
//   BUILTIN_EXIT : 5  (ldr pop + movz x16 + svc + movz dead + str dead)
//   POP          : 1  (ldr discard)
//   END          : 3  + 1 if frame (movz w0 0 + ldp + ret + maybe add sp first)
//   prologue     : 2  + 1 if frame (stp + mov fp sp + maybe sub sp)
func opInstrCount(opTok) {
    if opTok == "PUSH_STR"     { emit 3 }
    if opTok == "PUSH_INT"     { emit 2 }
    if opTok == "LOAD_LOCAL"   { emit 2 }
    if opTok == "STORE_LOCAL"  { emit 2 }
    if opTok == "ADD"          { emit 4 }
    if opTok == "SUB"          { emit 4 }
    if opTok == "MUL"          { emit 4 }
    if opTok == "DIV"          { emit 4 }
    if opTok == "MOD"          { emit 5 }
    if opTok == "LT"           { emit 5 }   // pop b, pop a, cmp, cset, push
    if opTok == "GT"           { emit 5 }
    if opTok == "LE"           { emit 5 }
    if opTok == "GE"           { emit 5 }
    if opTok == "EQ"           { emit 5 }
    if opTok == "NE"           { emit 5 }
    if opTok == "JUMP"         { emit 1 }
    if opTok == "JUMPIFNOT"    { emit 2 }   // pop x0, cbz x0, target
    if opTok == "LABEL"        { emit 0 }
    if opTok == "BUILTIN_KP"   { emit 4 }
    if opTok == "BUILTIN_EXIT" { emit 5 }
    if opTok == "POP"          { emit 1 }
    if opTok == "END"          { emit 3 }
    emit 0
}

// Build a label table: for each LABEL op, record its instruction index
// (0-based, relative to the start of __text including prologue). Returns a
// newline-separated list of "name=instr_idx" entries.
func buildLabelTable(parsed) {
    let opStart = irOpStart(parsed)
    let nOps = lineCount(parsed) - opStart
    let frameSize = computeFrameSize(parsed)
    let table = ""
    let n = 2
    if frameSize > 0 { n = 3 }
    let i = 0
    while i < nOps {
        let opLine = getLine(parsed, opStart + i)
        let sp = 0
        while sp < len(opLine) && opLine[sp] != " " { sp += 1 }
        let tok = substring(opLine, 0, sp)
        if tok == "LABEL" {
            let name = trim(substring(opLine, sp + 1, len(opLine)))
            if len(table) > 0 { table = table + "\n" }
            table = table + name + "=" + ("" + n)
        }
        n = n + opInstrCount(tok)
        i += 1
    }
    emit table
}

// Look up a label in the label table. Returns instruction index or -1 if not found.
func findLabel(table, name) {
    let nl = lineCount(table)
    let i = 0
    while i < nl {
        let line = getLine(table, i)
        let eq = 0
        while eq < len(line) && line[eq] != "=" { eq += 1 }
        if substring(line, 0, eq) == name {
            emit toInt(substring(line, eq + 1, len(line)))
        }
        i += 1
    }
    emit 0 - 1
}

// Map IR comparison op token → AArch64 cond code.
func irCmpToCond(opTok) {
    if opTok == "EQ" { emit 0x0 }
    if opTok == "NE" { emit 0x1 }
    if opTok == "GE" { emit 0xa }
    if opTok == "LT" { emit 0xb }
    if opTok == "GT" { emit 0xc }
    if opTok == "LE" { emit 0xd }
    emit 0
}

// Total __text size in bytes, given parsed IR. Walks ops + adds prologue/frame.
func computeTextSize(parsed) {
    let opStart = irOpStart(parsed)
    let nOps = lineCount(parsed) - opStart
    let frameSize = computeFrameSize(parsed)
    let frameInstrs = 0
    if frameSize > 0 { frameInstrs = 2 }     // sub sp + add sp (one each in prologue/epilogue)
    let n = 2 + frameInstrs                  // prologue: stp + mov fp sp [+ sub sp]
    let i = 0
    while i < nOps {
        let opLine = getLine(parsed, opStart + i)
        let sp = 0
        while sp < len(opLine) && opLine[sp] != " " { sp += 1 }
        let tok = substring(opLine, 0, sp)
        n = n + opInstrCount(tok)
        i += 1
    }
    emit n * 4
}

// Emit __text bytes for the parsed IR. Eval stack lives at SP, growing toward
// lower addresses; locals live at FP-negative offsets (8 bytes each).
//
// Layout assumption (slice 3a/3b): __text + __stubs + __cstring fits on the
// first 4 KB ADRP page (offset < 0x1000 from TEXT_VADDR). For larger programs
// we'll need real per-instruction page math.
func emitTextFromIR(parsed, strOffsets) {
    let opStart = irOpStart(parsed)
    let nOps = lineCount(parsed) - opStart
    let frameSize = computeFrameSize(parsed)
    let labels = buildLabelTable(parsed)

    let s = ""
    // prologue: stp x29, x30, [sp, #-16]!; mov x29, sp; [sub sp, sp, #frame]
    s = s + arm64_stp_fp_lr_pre16()
    s = s + arm64_mov_fp_sp()
    let instrIdx = 2
    if frameSize > 0 {
        s = s + arm64_sub_sp(frameSize)
        instrIdx += 1
    }

    let textVaddr = 0x100000000
    let textOff = 0x460
    let stubsOff = textOff + g_TEXT_SIZE
    let cstringOff = stubsOff + 12
    let stubVaddr = textVaddr + stubsOff

    let oi = 0
    while oi < nOps {
        let opLine = getLine(parsed, opStart + oi)
        let spIdx = 0
        while spIdx < len(opLine) && opLine[spIdx] != " " { spIdx += 1 }
        let opTok = substring(opLine, 0, spIdx)
        let restTok = ""
        if spIdx < len(opLine) { restTok = trim(substring(opLine, spIdx + 1, len(opLine))) }

        if opTok == "PUSH_STR" {
            let strIdx = toInt(restTok)
            let strOff = toInt(getLine(strOffsets, strIdx))
            let strVaddr = textVaddr + cstringOff + strOff
            let adrpPc = textVaddr + textOff + instrIdx * 4
            let pcPage = adrpPc / 4096 * 4096
            let strPage = strVaddr / 4096 * 4096
            let imm21 = (strPage - pcPage) / 4096
            s = s + arm64_adrp(0, imm21)
            instrIdx += 1
            s = s + arm64_add_imm(0, 0, strVaddr % 4096)
            instrIdx += 1
            s = s + arm64_push_x0()
            instrIdx += 1
        } else if opTok == "PUSH_INT" {
            let n = toInt(restTok)
            if n >= 0 {
                s = s + arm64_movz_x_imm(0, n % 65536)   // movz x0, #imm16 (zero-ext)
            } else {
                s = s + arm64_movn_x_imm(0, (0 - n - 1) % 65536) // movn x0, #(~n & 0xffff)
            }
            instrIdx += 1
            s = s + arm64_push_x0()
            instrIdx += 1
        } else if opTok == "ADD" {
            s = s + arm64_pop(0)                    // x0 = b
            s = s + arm64_pop(1)                    // x1 = a
            s = s + arm64_add_xxx(0, 1, 0)          // x0 = a + b
            s = s + arm64_push(0)
            instrIdx += 4
        } else if opTok == "SUB" {
            s = s + arm64_pop(0)
            s = s + arm64_pop(1)
            s = s + arm64_sub_xxx(0, 1, 0)          // x0 = a - b
            s = s + arm64_push(0)
            instrIdx += 4
        } else if opTok == "MUL" {
            s = s + arm64_pop(0)
            s = s + arm64_pop(1)
            s = s + arm64_mul_xxx(0, 1, 0)
            s = s + arm64_push(0)
            instrIdx += 4
        } else if opTok == "DIV" {
            s = s + arm64_pop(0)
            s = s + arm64_pop(1)
            s = s + arm64_sdiv_xxx(0, 1, 0)         // signed divide
            s = s + arm64_push(0)
            instrIdx += 4
        } else if opTok == "MOD" {
            s = s + arm64_pop(0)                    // x0 = b
            s = s + arm64_pop(1)                    // x1 = a
            s = s + arm64_sdiv_xxx(2, 1, 0)         // x2 = a / b
            s = s + arm64_msub_xxxx(0, 2, 0, 1)     // x0 = a - x2 * b = a mod b
            s = s + arm64_push(0)
            instrIdx += 5
        } else if opTok == "BUILTIN_EXIT" {
            s = s + arm64_pop_x0()                  // x0 = exit code
            s = s + arm64_movz_x_imm(16, 1)         // x16 = SYS_exit
            s = s + arm64_svc(0x80)                 // trap (no return)
            // Dead code — keep for IR-level eval-stack/POP balance:
            s = s + arm64_movz_w_imm(0, 0)
            s = s + arm64_push_x0()
            instrIdx += 5
        } else if opTok == "LT" || opTok == "GT" || opTok == "LE" || opTok == "GE" || opTok == "EQ" || opTok == "NE" {
            s = s + arm64_pop(0)                    // x0 = b
            s = s + arm64_pop(1)                    // x1 = a
            s = s + arm64_cmp_xx(1, 0)              // cmp a, b → flags
            s = s + arm64_cset(0, irCmpToCond(opTok))
            s = s + arm64_push(0)
            instrIdx += 5
        } else if opTok == "LABEL" {
            // No instructions emitted; labels just record positions (handled in pre-pass)
        } else if opTok == "JUMP" {
            let target = findLabel(labels, restTok)
            let delta = target - instrIdx
            s = s + arm64_b(delta)
            instrIdx += 1
        } else if opTok == "JUMPIFNOT" {
            s = s + arm64_pop_x0()
            instrIdx += 1
            let target = findLabel(labels, restTok)
            let delta = target - instrIdx
            s = s + arm64_cbz(0, delta)
            instrIdx += 1
        } else if opTok == "LOAD_LOCAL" {
            let lIdx = toInt(restTok)
            let off = 0 - (8 + lIdx * 8)
            s = s + arm64_ldur(0, 29, off)         // ldur x0, [x29, #-(8+i*8)]
            instrIdx += 1
            s = s + arm64_push_x0()
            instrIdx += 1
        } else if opTok == "STORE_LOCAL" {
            let lIdx = toInt(restTok)
            let off = 0 - (8 + lIdx * 8)
            s = s + arm64_pop_x0()
            instrIdx += 1
            s = s + arm64_stur(0, 29, off)         // stur x0, [x29, #-(8+i*8)]
            instrIdx += 1
        } else if opTok == "BUILTIN_KP" {
            s = s + arm64_pop_x0()
            instrIdx += 1
            let blPc = textVaddr + textOff + instrIdx * 4
            let rel26 = (stubVaddr - blPc) / 4
            s = s + arm64_bl(rel26)
            instrIdx += 1
            s = s + arm64_movz_w_imm(0, 0)         // movz w0, #0 (return value)
            instrIdx += 1
            s = s + arm64_push_x0()
            instrIdx += 1
        } else if opTok == "POP" {
            s = s + arm64_pop_x0()
            instrIdx += 1
        } else if opTok == "END" {
            if frameSize > 0 {
                s = s + arm64_add_sp(frameSize)
                instrIdx += 1
            }
            s = s + arm64_movz_w0_zero()
            s = s + arm64_ldp_fp_lr_post16()
            s = s + arm64_ret()
            instrIdx += 3
        }
        oi += 1
    }
    emit s
}

// ── _main code (8 instructions, 32 bytes) ───────────────────────────────────
// _main vaddr = 0x100000460. "Hi" vaddr = 0x10000048C. Stub vaddr = 0x100000480.
//
//   stp x29, x30, [sp, #-16]!
//   mov x29, sp
//   adrp x0, "Hi"@PAGE                ; PC=0x...468, page_rel=0
//   add  x0, x0, "Hi"@PAGEOFF         ; +0x48c
//   bl   _puts$stub                   ; PC=0x...470 → 0x...480, rel26=4
//   mov  w0, #0
//   ldp  x29, x30, [sp], #16
//   ret
func emitMainCode() {
    let s = ""
    s = s + arm64_stp_fp_lr_pre16()
    s = s + arm64_mov_fp_sp()
    s = s + arm64_adrp(0, 0)                 // "Hi" is on same page as _main
    s = s + arm64_add_imm(0, 0, 0x48c)       // page-offset of "Hi"
    s = s + arm64_bl(4)                      // (0x480 - 0x470) / 4 = 4
    s = s + arm64_movz_w0_zero()
    s = s + arm64_ldp_fp_lr_post16()
    s = s + arm64_ret()
    emit s
}

// ── _puts$stub (3 instructions, 12 bytes) ───────────────────────────────────
// stub vaddr = 0x100000480. __got slot vaddr = 0x100004000.
//
//   adrp x16, __got@PAGE               ; PC=0x...480, page_rel=4
//   ldr  x16, [x16, #__got@PAGEOFF]    ; offset 0 (got is at page base)
//   br   x16
func emitStubCode() {
    let s = ""
    s = s + arm64_adrp(16, 4)
    s = s + arm64_ldr_imm(16, 16, 0)
    s = s + arm64_br(16)
    emit s
}

// ── __cstring "Hi\0" (3 bytes) ──────────────────────────────────────────────
func emitCString() { emit hexStr("Hi") + hexByte(0) }

// ── __got slot (8 bytes) ────────────────────────────────────────────────────
// dyld_chained_ptr_64_bind: bind=1, next=0, reserved=0, addend=0, ordinal=0.
// Encoded: bit 63 = 1, all other bits 0. 8-byte LE: 00 00 00 00 00 00 00 80.
func emitGotSlot() { emit hexDword(0) + hexDword(0x80000000) }

// ── chained_fixups payload (96 bytes, hardcoded) ────────────────────────────
// dyld_chained_fixups_header (32 B):
//   fixups_version=0, starts_offset=32, imports_offset=80,
//   symbols_offset=84, imports_count=1, imports_format=1, symbols_format=0
// + dyld_chained_starts_in_image (4 segs) at offset 32
// + dyld_chained_starts_in_segment (page_size 0x4000, format 6,
//   seg_offset=0x4000, page_count=1, page_start[0]=0) at offset 56
// + import (4 B): lib_ordinal=1 (libSystem), name_offset=1
// + symbols: NUL "_puts" NUL (8 B)
func emitChainedFixups() {
    let s = ""
    // header — 32 B
    s = s + hexDword(0)              // fixups_version
    s = s + hexDword(32)             // starts_offset
    s = s + hexDword(80)             // imports_offset
    s = s + hexDword(84)             // symbols_offset
    s = s + hexDword(1)              // imports_count
    s = s + hexDword(1)              // imports_format = DYLD_CHAINED_IMPORT
    s = s + hexDword(0)              // symbols_format = uncompressed
    s = s + hexDword(0)              // pad to 32B
    // starts_in_image — 20 B + 4 B pad = 24 B (seg_info_offset[2] = 24 confirms layout)
    s = s + hexDword(4)              // seg_count
    s = s + hexDword(0)              // [0] __PAGEZERO
    s = s + hexDword(0)              // [1] __TEXT
    s = s + hexDword(24)             // [2] __DATA_CONST → 24 B from starts_in_image
    s = s + hexDword(0)              // [3] __LINKEDIT
    s = s + hexDword(0)              // 4 B pad to reach offset 24 of starts_in_image
    // starts_in_segment for __DATA_CONST — 24 B (header 8 + segoff 8 + maxptr 4 + page_count+page_start 4)
    s = s + hexDword(24)             // size
    s = s + hexWord(0x4000)          // page_size = 16 KB
    s = s + hexWord(6)               // pointer_format = DYLD_CHAINED_PTR_64_OFFSET
    s = s + hexQword(0x4000)         // segment_offset (within __DATA_CONST in file)
    s = s + hexDword(0)              // max_valid_pointer
    s = s + hexWord(1)               // page_count
    s = s + hexWord(0)               // page_start[0] = 0 (chain starts at byte 0 of page)
    // imports table — 4 B (1 import) at offset 80
    // dyld_chained_import: lib_ordinal=1, weak=0, name_offset=1
    // packed: ordinal | (weak<<8) | (name_offset<<9) = 1 | (1<<9) = 0x201
    s = s + hexDword(0x00000201)
    // symbols section starts at offset 84, runs to offset 96 = 12 B
    s = s + hexByte(0)               // sentinel at offset 0
    s = s + hexStr("_puts") + hexByte(0)  // 6 B
    s = s + hexPad(5)                // pad to 12 B (total chained-fixups = 96)
    emit s
}

// ── symtab (48 B = 3 × nlist_64) ────────────────────────────────────────────
// Symbols (in declaration order, matches strtab layout):
//   0: __mh_execute_header  (defined, sect 1, value = TEXT_VADDR)
//   1: _main                (defined, sect 1, value = TEXT_VADDR + TEXT_OFF)
//   2: _puts                (undefined, lib ordinal 1 in n_desc)
func emitSymtab() {
    let s = ""
    // sym 0: __mh_execute_header
    s = s + hexDword(STRX_MH())                 // n_strx = 2
    s = s + hexByte(0x0f)                       // n_type = N_EXT | N_SECT
    s = s + hexByte(1)                          // n_sect = 1 (__text)
    s = s + hexWord(0x10)                       // n_desc = REFERENCED_DYNAMICALLY (matches clang)
    s = s + hexQword2(TEXT_VADDR(), 1)          // n_value = 0x100000000
    // sym 1: _main
    s = s + hexDword(STRX_MAIN())
    s = s + hexByte(0x0f)
    s = s + hexByte(1)
    s = s + hexWord(0)
    s = s + hexQword2(TEXT_VADDR() + TEXT_OFF(), 1)  // 0x100000460
    // sym 2: _puts (undef, imported)
    s = s + hexDword(STRX_PUTS())
    s = s + hexByte(0x01)                       // n_type = N_EXT (UNDF)
    s = s + hexByte(0)                          // n_sect = 0
    s = s + hexWord(0x0100)                     // n_desc: lib_ordinal=1 in high byte
    s = s + hexQword(0)
    emit s
}

// ── indirect symtab (8 B = 2 × uint32) ──────────────────────────────────────
// Both entries reference symtab idx 2 (_puts):
//   entry 0 → __stubs[0]  → _puts
//   entry 1 → __got[0]    → _puts
func emitIndirectSymtab() {
    emit hexDword(2) + hexDword(2)
}

// ── strtab (40 B padded) ────────────────────────────────────────────────────
// Layout (matches reference for compatibility):
//   [0]  ' '              (1 B, "space" sentinel some strtabs use)
//   [1]  NUL              (1 B, empty string at idx 1)
//   [2]  "__mh_execute_header\0"  (20 B)
//   [22] "_main\0"        (6 B)
//   [28] "_puts\0"        (6 B)
//   [34] pad to 40        (6 NULs)
func emitStrtab() {
    let s = ""
    s = s + hexByte(0x20)            // ' '
    s = s + hexByte(0)               // NUL @ offset 1
    s = s + hexStr("__mh_execute_header") + hexByte(0)
    s = s + hexStr("_main") + hexByte(0)
    s = s + hexStr("_puts") + hexByte(0)
    s = s + hexPad(6)                // pad to 40 bytes
    emit s
}

// ── ad-hoc code signature builder ───────────────────────────────────────────
// All code-signing fields are BIG-endian.
//
// SuperBlob structure (20 B header + 1 BlobIndex):
//   magic   = 0xfade0cc0
//   length  = 20 + len(CodeDirectory)
//   count   = 1
//   index[0]: type = 0 (CSSLOT_CODEDIRECTORY), offset = 20
//   then CodeDirectory blob.
//
// CodeDirectory (version 0x20400 = SUPPORTSEXECSEG, ad-hoc flag):
//   88 B header — see field-by-field comments below.
//   identifier — UTF-8 string + NUL (we use "krypton\0" = 8 B).
//   special slots — none for our minimal binary.
//   code slots — SHA-256 of each pageSize-byte page of the file from offset 0
//                up to codeLimit. Last page may be partial.

// 64-bit BE qword: just two BE dwords (we use only low 32 bits in our fields).
func hexQwordBe(hi, lo) { emit hexDwordBe(hi) + hexDwordBe(lo) }

// Build the CodeDirectory blob. fileBytes is the hex-encoded file content
// from offset 0 to codeLimit (the bytes the kernel verifies against).
func buildCodeDirectory(fileBytes, codeLimit, identifier) {
    let pageSize = 0x4000          // 16 KB
    let pageLog2 = 14
    let hashSize = 32              // SHA-256
    let hashType = 2
    let nSpecialSlots = 0
    let nCodeSlots = (codeLimit + pageSize - 1) / pageSize
    let identLen = len(identifier) + 1   // include trailing NUL
    let identOffset = 88
    let hashOffset = identOffset + identLen + nSpecialSlots * hashSize
    let cdLength = hashOffset + nCodeSlots * hashSize

    let cd = ""
    cd = cd + hexDwordBe(0xfade0c02)         // magic CSMAGIC_CODEDIRECTORY
    cd = cd + hexDwordBe(cdLength)
    cd = cd + hexDwordBe(0x00020400)         // version (SUPPORTSEXECSEG)
    cd = cd + hexDwordBe(0x00000002)         // flags = adhoc
    cd = cd + hexDwordBe(hashOffset)
    cd = cd + hexDwordBe(identOffset)
    cd = cd + hexDwordBe(nSpecialSlots)
    cd = cd + hexDwordBe(nCodeSlots)
    cd = cd + hexDwordBe(codeLimit)
    cd = cd + hexByte(hashSize) + hexByte(hashType)
    cd = cd + hexByte(0) + hexByte(pageLog2) // platform=0, log2(pageSize)
    cd = cd + hexDwordBe(0)                  // spare2
    cd = cd + hexDwordBe(0)                  // scatterOffset
    cd = cd + hexDwordBe(0)                  // teamOffset
    cd = cd + hexDwordBe(0)                  // spare3
    cd = cd + hexQwordBe(0, 0)               // codeLimit64 = 0 (using 32-bit)
    cd = cd + hexQwordBe(0, 0)               // execSegBase = 0 (file off of __TEXT)
    cd = cd + hexQwordBe(0, 0x4000)          // execSegLimit = __TEXT vmsize
    cd = cd + hexQwordBe(0, 1)               // execSegFlags = MAIN_BINARY

    // Identifier string with trailing NUL
    cd = cd + asciiToHex(identifier) + hexByte(0)

    // Code slot hashes — SHA-256 of each page
    let p = 0
    while p < nCodeSlots {
        let pageOff = p * pageSize
        let pageLen = pageSize
        if pageOff + pageLen > codeLimit {
            pageLen = codeLimit - pageOff
        }
        cd = cd + sha256_hex(fileBytes, pageOff, pageLen)
        p += 1
    }
    emit cd
}

// Wrap the CodeDirectory in a SuperBlob with a single CSSLOT_CODEDIRECTORY
// blob index. Returns the full signature bytes (hex-encoded).
func buildSuperBlob(cdHex) {
    let cdLen = hexBytesLen(cdHex)
    let totalLen = 12 + 8 + cdLen          // SuperBlob header + 1 index + CD
    let s = ""
    s = s + hexDwordBe(0xfade0cc0)         // magic CSMAGIC_EMBEDDED_SIGNATURE
    s = s + hexDwordBe(totalLen)
    s = s + hexDwordBe(1)                  // count = 1
    s = s + hexDwordBe(0)                  // type = CSSLOT_CODEDIRECTORY
    s = s + hexDwordBe(20)                 // offset to CD = 20
    s = s + cdHex
    emit s
}

// ── load commands ───────────────────────────────────────────────────────────

// LC_SEGMENT_64 __PAGEZERO (72 B, no sections)
func emitLcPagezero() {
    let s = ""
    s = s + hexDword(LC_SEGMENT_64()) + hexDword(72)
    s = s + hexStr("__PAGEZERO") + hexPad(6)        // 16-byte segname
    s = s + hexQword2(0, 0)                         // vmaddr
    s = s + hexQword2(0, 1)                         // vmsize = 0x100000000
    s = s + hexQword(0)                             // fileoff
    s = s + hexQword(0)                             // filesize
    s = s + hexDword(0)                             // maxprot
    s = s + hexDword(0)                             // initprot
    s = s + hexDword(0)                             // nsects
    s = s + hexDword(0)                             // flags
    emit s
}

// LC_SEGMENT_64 __TEXT (with 3 sections: __text, __stubs, __cstring)
// cmdsize = 72 + 3*80 = 312
func emitLcSegText() {
    let s = ""
    s = s + hexDword(LC_SEGMENT_64()) + hexDword(312)
    s = s + hexStr("__TEXT") + hexPad(10)
    s = s + hexQword2(0, 1)                         // vmaddr = 0x100000000
    s = s + hexQword(0x4000)                        // vmsize = 16 KB
    s = s + hexQword(0)                             // fileoff
    s = s + hexQword(0x4000)                        // filesize = 16 KB (page)
    s = s + hexDword(5)                             // maxprot = R+X
    s = s + hexDword(5)                             // initprot = R+X
    s = s + hexDword(3)                             // nsects
    s = s + hexDword(0)                             // flags
    // Section 1: __text
    s = s + hexStr("__text") + hexPad(10)
    s = s + hexStr("__TEXT") + hexPad(10)
    s = s + hexQword2(TEXT_VADDR() + TEXT_OFF(), 1) // addr
    s = s + hexQword(TEXT_SIZE())                   // size
    s = s + hexDword(TEXT_OFF())                    // file offset
    s = s + hexDword(2)                             // align = 2^2 = 4
    s = s + hexDword(0)                             // reloff
    s = s + hexDword(0)                             // nreloc
    s = s + hexDword(0x80000400)                    // flags = PURE | SOME (S_REGULAR)
    s = s + hexDword(0)                             // reserved1
    s = s + hexDword(0)                             // reserved2
    s = s + hexDword(0)                             // reserved3
    // Section 2: __stubs
    s = s + hexStr("__stubs") + hexPad(9)
    s = s + hexStr("__TEXT") + hexPad(10)
    s = s + hexQword2(TEXT_VADDR() + STUBS_OFF(), 1)
    s = s + hexQword(STUBS_SIZE())
    s = s + hexDword(STUBS_OFF())
    s = s + hexDword(2)                             // align 4
    s = s + hexDword(0)
    s = s + hexDword(0)
    s = s + hexDword(0x80000408)                    // PURE | SOME | S_SYMBOL_STUBS
    s = s + hexDword(0)                             // reserved1 = 0 (idx into indirect symtab)
    s = s + hexDword(12)                            // reserved2 = stub size
    s = s + hexDword(0)                             // reserved3
    // Section 3: __cstring
    s = s + hexStr("__cstring") + hexPad(7)
    s = s + hexStr("__TEXT") + hexPad(10)
    s = s + hexQword2(TEXT_VADDR() + CSTRING_OFF(), 1)
    s = s + hexQword(CSTRING_SIZE())
    s = s + hexDword(CSTRING_OFF())
    s = s + hexDword(0)                             // align 1
    s = s + hexDword(0)
    s = s + hexDword(0)
    s = s + hexDword(0x00000002)                    // S_CSTRING_LITERALS
    s = s + hexDword(0)
    s = s + hexDword(0)
    s = s + hexDword(0)
    emit s
}

// LC_SEGMENT_64 __DATA_CONST (1 section: __got)
// cmdsize = 72 + 80 = 152
func emitLcSegDataConst() {
    let s = ""
    s = s + hexDword(LC_SEGMENT_64()) + hexDword(152)
    s = s + hexStr("__DATA_CONST") + hexPad(4)
    s = s + hexQword2(0x4000, 1)                    // vmaddr = 0x100004000
    s = s + hexQword(0x4000)                        // vmsize
    s = s + hexQword(0x4000)                        // fileoff
    s = s + hexQword(0x4000)                        // filesize
    s = s + hexDword(3)                             // maxprot = R+W
    s = s + hexDword(3)                             // initprot = R+W
    s = s + hexDword(1)                             // nsects
    s = s + hexDword(0x10)                          // SG_READ_ONLY
    // Section 1: __got
    s = s + hexStr("__got") + hexPad(11)
    s = s + hexStr("__DATA_CONST") + hexPad(4)
    s = s + hexQword2(0x4000, 1)                    // addr = 0x100004000
    s = s + hexQword(GOT_SIZE())
    s = s + hexDword(GOT_OFF())
    s = s + hexDword(3)                             // align 8
    s = s + hexDword(0)
    s = s + hexDword(0)
    s = s + hexDword(0x00000006)                    // S_NON_LAZY_SYMBOL_POINTERS
    s = s + hexDword(1)                             // reserved1 = 1 (indirect symtab idx)
    s = s + hexDword(0)
    s = s + hexDword(0)
    emit s
}

// LC_SEGMENT_64 __LINKEDIT (no sections, 72 B)
func emitLcSegLinkedit() {
    let s = ""
    s = s + hexDword(LC_SEGMENT_64()) + hexDword(72)
    s = s + hexStr("__LINKEDIT") + hexPad(6)
    s = s + hexQword2(0x8000, 1)                    // vmaddr = 0x100008000
    s = s + hexQword(0x4000)                        // vmsize
    s = s + hexQword(LINKEDIT_FILE_OFF())
    s = s + hexQword(FILE_TOTAL_SIZE() - LINKEDIT_FILE_OFF()) // filesize
    s = s + hexDword(1)                             // maxprot = R
    s = s + hexDword(1)                             // initprot = R
    s = s + hexDword(0)                             // nsects
    s = s + hexDword(0)
    emit s
}

// LC_DYLD_CHAINED_FIXUPS (16 B)
func emitLcChainedFixups() {
    let s = ""
    s = s + hexDword(LC_DYLD_CHAINED_FIXUPS()) + hexDword(16)
    s = s + hexDword(CHAINED_FIXUPS_OFF())
    s = s + hexDword(CHAINED_FIXUPS_SIZE())
    emit s
}

// LC_SYMTAB (24 B)
func emitLcSymtab() {
    let s = ""
    s = s + hexDword(LC_SYMTAB()) + hexDword(24)
    s = s + hexDword(SYMTAB_OFF())
    s = s + hexDword(NSYMS())
    s = s + hexDword(STRTAB_OFF())
    s = s + hexDword(STRTAB_SIZE())
    emit s
}

// LC_DYSYMTAB (80 B)
// We have: nlocalsym=0, nextdefsym=2 (mh_execute_header, _main), nundefsym=1 (_puts).
// Symbol order in symtab matches: idx 0,1 are extdef; idx 2 is undef.
func emitLcDysymtab() {
    let s = ""
    s = s + hexDword(LC_DYSYMTAB()) + hexDword(80)
    s = s + hexDword(0)                             // ilocalsym
    s = s + hexDword(0)                             // nlocalsym
    s = s + hexDword(0)                             // iextdefsym
    s = s + hexDword(2)                             // nextdefsym
    s = s + hexDword(2)                             // iundefsym
    s = s + hexDword(1)                             // nundefsym
    s = s + hexDword(0)                             // tocoff
    s = s + hexDword(0)                             // ntoc
    s = s + hexDword(0)                             // modtaboff
    s = s + hexDword(0)                             // nmodtab
    s = s + hexDword(0)                             // extrefsymoff
    s = s + hexDword(0)                             // nextrefsyms
    s = s + hexDword(INDIRECT_SYMTAB_OFF())
    s = s + hexDword(NINDIRECTSYMS())
    s = s + hexDword(0)                             // extreloff
    s = s + hexDword(0)                             // nextrel
    s = s + hexDword(0)                             // locreloff
    s = s + hexDword(0)                             // nlocrel
    emit s
}

// LC_LOAD_DYLINKER (32 B): cmd + cmdsize + name_offset + "/usr/lib/dyld\0" + pad
func emitLcLoadDylinker() {
    let s = ""
    s = s + hexDword(LC_LOAD_DYLINKER()) + hexDword(32)
    s = s + hexDword(12)                            // name offset (after 12-byte header)
    s = s + hexStr("/usr/lib/dyld") + hexByte(0)    // 14 B
    s = s + hexPad(6)                               // pad to 32 total
    emit s
}

// LC_BUILD_VERSION (24 B): platform=1 (MACOS), minos=14.0, sdk=14.0, ntools=0
func emitLcBuildVersion() {
    let s = ""
    s = s + hexDword(LC_BUILD_VERSION()) + hexDword(24)
    s = s + hexDword(1)                             // PLATFORM_MACOS
    s = s + hexDword(0x000e0000)                    // minos = 14.0.0
    s = s + hexDword(0x000e0000)                    // sdk = 14.0.0
    s = s + hexDword(0)                             // ntools
    emit s
}

// LC_MAIN (24 B): entry offset in __TEXT, stack size
func emitLcMain() {
    let s = ""
    s = s + hexDword(LC_MAIN()) + hexDword(24)
    s = s + hexQword(TEXT_OFF())                    // entryoff
    s = s + hexQword(0)                             // stacksize
    emit s
}

// LC_LOAD_DYLIB libSystem (56 B)
//   header: cmd, cmdsize, name_off=24, timestamp=2, current_ver=1356.0.0, compat_ver=1.0.0
//   then "/usr/lib/libSystem.B.dylib\0" = 27 B, padded to 32 → 56 total
// version field encoding: (major<<16) | (minor<<8) | patch
//   1356.0.0 = 0x054C0000
//   1.0.0    = 0x00010000
func emitLcLoadDylib() {
    let s = ""
    s = s + hexDword(LC_LOAD_DYLIB()) + hexDword(56)
    s = s + hexDword(24)                            // name offset
    s = s + hexDword(2)                             // timestamp
    s = s + hexDword(0x054c0000)                    // current_version 1356.0.0
    s = s + hexDword(0x00010000)                    // compat_version 1.0.0
    s = s + hexStr("/usr/lib/libSystem.B.dylib") + hexByte(0)  // 27 B
    s = s + hexPad(5)                               // pad to 32 → cmdsize 56
    emit s
}

// LC_CODE_SIGNATURE (16 B)
func emitLcCodeSignature() {
    let s = ""
    s = s + hexDword(LC_CODE_SIGNATURE()) + hexDword(16)
    s = s + hexDword(CODESIG_OFF())
    s = s + hexDword(CODESIG_SIZE())
    emit s
}

// ── header (32 B) ───────────────────────────────────────────────────────────

func emitHeader(ncmds, sizeofcmds) {
    let s = ""
    s = s + hexDword(MH_MAGIC_64())
    s = s + hexDword(CPU_TYPE_ARM64())
    s = s + hexDword(0)                             // cpusubtype
    s = s + hexDword(MH_EXECUTE())
    s = s + hexDword(ncmds)
    s = s + hexDword(sizeofcmds)
    s = s + hexDword(MH_NOUNDEFS() + MH_DYLDLINK() + MH_TWOLEVEL() + MH_PIE())
    s = s + hexDword(0)                             // reserved
    emit s
}

// ── driver ──────────────────────────────────────────────────────────────────

// Encode an ASCII string as a hex-encoded byte sequence.
func asciiToHex(s) {
    let out = ""
    let i = 0
    while i < len(s) {
        out = out + hexByte(charCode(s[i]))
        i += 1
    }
    emit out
}

just run {
    let arg0 = arg("0")
    if len(arg0) == 0 {
        printErr("usage: kcc kompiler/macho_arm64_self.k <output_path>")
        printErr("       kcc kompiler/macho_arm64_self.k --ir <input.kir> <output_path>")
        printErr("       kcc kompiler/macho_arm64_self.k --sha256-test")
        exit("1")
    }

    let outFile = arg0

    // --ir <input.kir> <output_path>: compile the simple-subset IR to a
    // signed arm64 Mach-O. Sets globals from IR-derived layout, then falls
    // through to the same emission path as the hello-world default.
    let irOps = ""
    let irStrOffsets = ""
    let useIr = "0"
    if arg0 == "--ir" {
        let inFile = arg("1")
        outFile = arg("2")
        if len(inFile) == 0 || len(outFile) == 0 {
            printErr("usage: --ir <input.kir> <output_path>")
            exit("1")
        }
        let ir = readFile(inFile)
        if len(ir) == 0 {
            printErr("macho_arm64_self: cannot read " + inFile)
            exit("1")
        }
        irOps = parseSimpleIR(ir)
        irStrOffsets = computeStringOffsets(irOps)
        g_TEXT_SIZE = computeTextSize(irOps)
        g_CSTRING_SIZE = computeCStringSize(irOps)
        useIr = "1"
    }

    if arg0 == "--sha256-test" {
        // Verify SHA-256 against canonical test vectors before trusting the
        // impl in the signing path.
        let empty = ""
        let h0 = sha256_hex(empty, 0, 0)
        printErr("SHA-256(\"\")    = " + h0)
        printErr("expected         = xE3xB0xC4x42x98xFCx1Cx14x9AxFBxF4xC8x99x6FxB9x24x27xAEx41xE4x64x9Bx93x4CxA4x95x99x1Bx78x52xB8x55")

        let abc = asciiToHex("abc")
        let h1 = sha256_hex(abc, 0, 3)
        printErr("SHA-256(\"abc\") = " + h1)
        printErr("expected         = xBAx78x16xBFx8Fx01xCFxEAx41x41x40xDEx5DxAEx22x23xB0x03x61xA3x96x17x7Ax9CxB4x10xFFx61xF2x00x15xAD")

        // 56-byte boundary case (one chunk, all in one block w/ short pad)
        let s56 = asciiToHex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
        let h2 = sha256_hex(s56, 0, 56)
        printErr("SHA-256(56-byte) = " + h2)
        printErr("expected         = x24x8Dx6Ax61xD2x06x38xB8xE5xC0x26x93x0Cx3Ex60x39xA3x3CxE4x59x64xFFx21x67xF6xECxEDxD4x19xDBx06xC1")
        exit("0")
    }

    // Build all 12 load commands
    let lcs = ""
    lcs = lcs + emitLcPagezero()
    lcs = lcs + emitLcSegText()
    lcs = lcs + emitLcSegDataConst()
    lcs = lcs + emitLcSegLinkedit()
    lcs = lcs + emitLcChainedFixups()
    lcs = lcs + emitLcSymtab()
    lcs = lcs + emitLcDysymtab()
    lcs = lcs + emitLcLoadDylinker()
    lcs = lcs + emitLcBuildVersion()
    lcs = lcs + emitLcMain()
    lcs = lcs + emitLcLoadDylib()
    lcs = lcs + emitLcCodeSignature()

    let sizeofcmds = hexBytesLen(lcs)
    let header = emitHeader(12, sizeofcmds)

    // Pre-text padding: from (32 + sizeofcmds) up to TEXT_OFF
    let prefix = header + lcs
    let prefixSize = hexBytesLen(prefix)
    let preTextPad = TEXT_OFF() - prefixSize

    let textCode = ""
    let cstrData = ""
    if useIr == "1" {
        textCode = emitTextFromIR(irOps, irStrOffsets)
        cstrData = emitCStringFromIR(irOps)
    } else {
        textCode = emitMainCode()
        cstrData = emitCString()
    }
    let stubCode = emitStubCode()

    // Pad after __cstring up to __DATA_CONST page boundary (file 0x4000)
    let textSegEnd = CSTRING_OFF() + CSTRING_SIZE()
    let postCstringPad = DATA_FILE_OFF() - textSegEnd

    // __DATA_CONST: __got slot + zero pad to LINKEDIT
    let gotData = emitGotSlot()
    let postGotPad = LINKEDIT_FILE_OFF() - DATA_FILE_OFF() - GOT_SIZE()

    // __LINKEDIT: chained fixups, symtab, indirect symtab, strtab
    let leChained = emitChainedFixups()
    let leSymtab = emitSymtab()
    let leIndirect = emitIndirectSymtab()
    let leStrtab = emitStrtab()
    // Pad strtab end to CODESIG_OFF (16-byte align)
    let strtabEnd = STRTAB_OFF() + STRTAB_SIZE()
    let preCodesigPad = CODESIG_OFF() - strtabEnd

    // Build the file body up to (but NOT including) the code signature.
    // This is exactly `codeLimit` bytes — what the kernel hashes.
    let body = prefix + hexPad(preTextPad)
    body = body + textCode + stubCode + cstrData + hexPad(postCstringPad)
    body = body + gotData + hexPad(postGotPad)
    body = body + leChained + leSymtab + leIndirect + leStrtab + hexPad(preCodesigPad)

    let codeLimit = hexBytesLen(body)
    if codeLimit != CODESIG_OFF() {
        printErr("macho_arm64_self: BUG: body size " + codeLimit + " != CODESIG_OFF " + CODESIG_OFF())
        exit("1")
    }

    // Compute ad-hoc code signature in Krypton — no external `codesign`.
    let cd = buildCodeDirectory(body, codeLimit, "krypton")
    let sig = buildSuperBlob(cd)
    let sigLen = hexBytesLen(sig)
    if sigLen != CODESIG_SIZE() {
        printErr("macho_arm64_self: BUG: sig size " + sigLen + " != CODESIG_SIZE " + CODESIG_SIZE())
        exit("1")
    }

    let machoBytes = body + sig
    writeBytes(outFile, machoBytes)
    printErr("macho_arm64_self: wrote " + outFile + " (" + (hexBytesLen(machoBytes)) + " bytes, ad-hoc signed)")
}
