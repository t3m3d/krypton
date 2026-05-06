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
// Usage: kcc compiler/macos_arm64/macho_arm64_self.k <output_path>
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
// Globals come first (lets), then funcs that read them. Krypton's compile.k
// emits one C declaration per let in source order, so funcs can't forward-ref.

let g_TEXT_SIZE       = 32          // bytes of __text (computed from IR)
let g_CSTRING_SIZE    = 3           // total bytes of __cstring (computed)
// Cache of function start line numbers within `parsed` — set by the driver
// after parse to avoid O(F²) walks in funcStartLine. One int per line.
let g_funcStartCache  = ""
let g_ENTRY_OFF       = 0x460       // file offset of `_main`'s first instruction
// Dynamic layout — recomputed by computeLayout() in the driver.
let g_TEXT_VMSIZE         = 0x4000
let g_DATA_CONST_FILE_OFF = 0x4000
let g_DATA_FILE_OFF       = 0x8000
let g_LINKEDIT_FILE_OFF   = 0xC000
let g_DATA_VADDR          = 0x100008000
let g_LINKEDIT_VADDR      = 0x101008000
let g_CODESIG_OFF         = 0xC0C0
let g_CODESIG_SIZE        = 244
let g_FILE_TOTAL_SIZE     = 0xC0C0 + 244

func TEXT_VADDR()         { emit 0x100000000 }
func DATA_CONST_VADDR()   { emit 0x100000000 + g_TEXT_VMSIZE }
func LINKEDIT_VADDR()     { emit g_LINKEDIT_VADDR }
func PAGEZERO_VMSIZE()    { emit 0x100000000 }
func SEG_PAGE_SIZE()      { emit 0x4000 }       // 16 KB

func TEXT_FILE_OFF()      { emit 0 }
func DATA_CONST_FILE_OFF() { emit g_DATA_CONST_FILE_OFF }
func DATA_FILE_OFF()      { emit g_DATA_FILE_OFF }
func LINKEDIT_FILE_OFF()  { emit g_LINKEDIT_FILE_OFF }
func DATA_VADDR()         { emit g_DATA_VADDR }
func DATA_VMSIZE()        { emit 0x10000 }    // 64 KB virtual heap (zero-fill past file backing)
func DATA_FILESIZE()      { emit 0x4000 }    // 16 KB file backing (1 page; rest zero-fill)

// Computes layout from g_TEXT_SIZE / g_CSTRING_SIZE. LINKEDIT meta = 192 B.
// __TEXT vmsize = 16 KB-aligned (0x460 + text + stubs(12) + cstring).
func computeLayout() {
    let pageSize = 0x4000
    let textEnd = 0x460 + g_TEXT_SIZE + 12 + g_CSTRING_SIZE
    let textVmsize = ((textEnd + pageSize - 1) / pageSize) * pageSize
    if textVmsize < pageSize { textVmsize = pageSize }
    g_TEXT_VMSIZE = textVmsize
    g_DATA_CONST_FILE_OFF = textVmsize
    g_DATA_FILE_OFF = textVmsize + 0x4000
    g_LINKEDIT_FILE_OFF = textVmsize + 0x8000
    g_DATA_VADDR = 0x100000000 + textVmsize + 0x4000
    g_LINKEDIT_VADDR = g_DATA_VADDR + 0x10000       // + DATA_VMSIZE
    g_CODESIG_OFF = g_LINKEDIT_FILE_OFF + 192
    let nCodeSlots = (g_CODESIG_OFF + pageSize - 1) / pageSize
    g_CODESIG_SIZE = 116 + nCodeSlots * 32
    g_FILE_TOTAL_SIZE = g_CODESIG_OFF + g_CODESIG_SIZE
    emit 0
}

func TEXT_OFF()           { emit 0x460 }        // fixed: just past header+LCs
func TEXT_SIZE()          { emit g_TEXT_SIZE }
func STUBS_OFF()          { emit 0x460 + g_TEXT_SIZE }
func STUBS_SIZE()         { emit 12 }           // 1 stub for _puts × 12 bytes
func CSTRING_OFF()        { emit 0x460 + g_TEXT_SIZE + 12 }
func CSTRING_SIZE()       { emit g_CSTRING_SIZE }
func GOT_OFF()            { emit g_DATA_CONST_FILE_OFF }
func GOT_SIZE()           { emit 8 }

func CHAINED_FIXUPS_OFF() { emit g_LINKEDIT_FILE_OFF }
func CHAINED_FIXUPS_SIZE() { emit 96 }
func SYMTAB_OFF()         { emit g_LINKEDIT_FILE_OFF + 96 }
func NSYMS()              { emit 3 }
func SYMTAB_SIZE()        { emit 48 }           // 3 × nlist_64 (16 bytes each)
func INDIRECT_SYMTAB_OFF() { emit g_LINKEDIT_FILE_OFF + 144 }
func NINDIRECTSYMS()      { emit 2 }
func INDIRECT_SYMTAB_SIZE() { emit 8 }
func STRTAB_OFF()         { emit g_LINKEDIT_FILE_OFF + 152 }
func STRTAB_SIZE()        { emit 40 }           // padded to 8

func CODESIG_OFF()        { emit g_CODESIG_OFF }
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
// movz Xd, #imm16, LSL #16  → 0xd2a00000 | (imm16 << 5) | Rd
func arm64_movz_x_imm_lsl16(rd, imm16) {
    emit hexDword(0xd2a00000 + (imm16 * 0x20) + rd)
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
// cbnz Xt, <imm19>  → 0xb5000000 | ((imm19 & 0x7ffff) << 5) | Rt
func arm64_cbnz(rt, rel) {
    let r = rel
    if r < 0 { r = r + 0x80000 }
    r = r % 0x80000
    emit hexDword(0xb5000000 + (r * 0x20) + rt)
}
// cmp Xn, #imm12  (alias for `subs xzr, Xn, #imm12`) → 0xf100001f | (imm12 << 10) | (Rn << 5)
func arm64_cmp_imm(rn, imm12) {
    emit hexDword(0xf100001f + (imm12 * 0x400) + (rn * 0x20))
}
// mov Xd, Xm  (alias for `orr Xd, xzr, Xm`) → 0xaa0003e0 | (Rm << 16) | Rd
func arm64_mov_xx(rd, rm) {
    emit hexDword(0xaa0003e0 + (rm * 0x10000) + rd)
}
// ldrb Wt, [Xn], #imm9  (post-indexed byte load) → 0x38400400 | (imm9<<12) | (Rn<<5) | Rt
func arm64_ldrb_post(rt, rn, imm9) {
    let i = imm9
    if i < 0 { i = i + 512 }
    i = i % 512
    emit hexDword(0x38400400 + (i * 0x1000) + (rn * 0x20) + rt)
}
// ldrb Wt, [Xn]  (zero offset) → 0x39400000 | (Rn<<5) | Rt
func arm64_ldrb_zero(rt, rn) {
    emit hexDword(0x39400000 + (rn * 0x20) + rt)
}
// sub Xd, Xn, #imm12 (64-bit, no shift) → 0xd1000000 | (imm12<<10) | (Rn<<5) | Rd
func arm64_sub_imm(rd, rn, imm12) {
    emit hexDword(0xd1000000 + (imm12 * 0x400) + (rn * 0x20) + rd)
}
// str Xt, [Xn, #imm12_scaled] (unsigned offset, 64-bit) → 0xf9000000 | ...
func arm64_str_imm(rt, rn, imm12_scaled) {
    emit hexDword(0xf9000000 + (imm12_scaled * 0x400) + (rn * 0x20) + rt)
}
// strb Wt, [Xn, #imm12]  (unscaled byte store)
func arm64_strb_imm(rt, rn, imm12) {
    emit hexDword(0x39000000 + (imm12 * 0x400) + (rn * 0x20) + rt)
}
// ldrb Wt, [Xn, Xm, LSL #0]  (register-offset byte load, 32-bit)
func arm64_ldrb_reg(rt, rn, rm) {
    emit hexDword(0x38606800 + (rm * 0x10000) + (rn * 0x20) + rt)
}
// strb Wt, [Xn, Xm, LSL #0]  (register-offset byte store, 32-bit)
func arm64_strb_reg(rt, rn, rm) {
    emit hexDword(0x38206800 + (rm * 0x10000) + (rn * 0x20) + rt)
}
// ldr Xt, [Xn, Xm, LSL #3]  (register-offset 64-bit load with index*8)
func arm64_ldr_reg_lsl3(rt, rn, rm) {
    emit hexDword(0xf8607800 + (rm * 0x10000) + (rn * 0x20) + rt)
}
// lsr Xd, Xn, #32  (logical right shift by 32; alias for ubfm)
//   ubfm 64-bit: 0xd3400000 | (immr<<16) | (imms<<10) | (Rn<<5) | Rd
//   For LSR #N: immr=N, imms=63. For N=32: 0xd3400000 + (32<<16) + (63<<10) = 0xd360FC00
func arm64_lsr_imm32(rd, rn) {
    emit hexDword(0xd360FC00 + (rn * 0x20) + rd)
}
// neg Xd, Xn  (alias for sub Xd, xzr, Xn)
func arm64_neg(rd, rn) {
    emit hexDword(0xcb0003e0 + (rn * 0x10000) + rd)
}
// stp Xt1, Xt2, [sp, #-16]!  (push pair, pre-indexed, 16-byte block)
//   encoding: 0xa9bf0000 | (Rt2<<10) | (Rn=31<<5) | Rt
//   We hardcode sp(31) as base, imm7=-1 (= 0x7f in 7-bit).
//   General STP pre-indexed 64-bit: 0xa9800000 | (imm7 << 15) | (Rt2<<10) | (Rn<<5) | Rt
//   For pre-indexed -16 (= imm7 -2 since scale 8): imm7 = -2 = 0x7e
//   Actually wait: stp x29,x30,[sp,#-16]! is 0xa9bf7bfd which means imm7=0x7e? Let me verify:
//   0xa9bf7bfd = 1010_1001_1011_1111_0111_1011_1111_1101
//   bits[30:23] = 10101001 (stp pre-indexed)
//   bit[22] = 1 (load not store? wait no — stp store)
//   Hmm let me recheck. STP (signed offset, pre-indexed):
//   bits[31:23]: 1010_1001_1 (store/load encoded by bit?)
//   For this op we already have arm64_stp_fp_lr_pre16; just generalizing.
//   Actually let me just expose a general stp_pre helper for arbitrary pair.
func arm64_stp_pre16(rt1, rt2) {
    // stp Xt1, Xt2, [sp, #-16]! ; imm7 = -2 (encoded as 0x7e in 7 bits)
    emit hexDword(0xa9bf0000 + ((rt2 % 32) * 0x400) + (31 * 0x20) + (rt1 % 32))
}
// ldp Xt1, Xt2, [sp], #16  (post-indexed pop pair)
func arm64_ldp_post16(rt1, rt2) {
    emit hexDword(0xa8c10000 + ((rt2 % 32) * 0x400) + (31 * 0x20) + (rt1 % 32))
}
// stp Xt1, Xt2, [Xn, #imm7_scaled]  (signed offset, scale 8)
func arm64_stp_off(rt1, rt2, rn, imm7_scaled) {
    let i = imm7_scaled
    if i < 0 { i = i + 128 }
    i = i % 128
    emit hexDword(0xa9000000 + (i * 0x8000) + ((rt2 % 32) * 0x400) + ((rn % 32) * 0x20) + (rt1 % 32))
}
// ldp Xt1, Xt2, [Xn, #imm7_scaled]
func arm64_ldp_off(rt1, rt2, rn, imm7_scaled) {
    let i = imm7_scaled
    if i < 0 { i = i + 128 }
    i = i % 128
    emit hexDword(0xa9400000 + (i * 0x8000) + ((rt2 % 32) * 0x400) + ((rn % 32) * 0x20) + (rt1 % 32))
}
// udiv Xd, Xn, Xm
func arm64_udiv_xxx(rd, rn, rm) {
    emit hexDword(0x9ac00800 + (rm * 0x10000) + (rn * 0x20) + rd)
}
// b.cond #imm19  (conditional branch, signed 19-bit, 4-byte units)
//   encoding: 0x54000000 | ((imm19 & 0x7ffff) << 5) | cond
func arm64_b_cond(cond, rel) {
    let r = rel
    if r < 0 { r = r + 0x80000 }
    r = r % 0x80000
    emit hexDword(0x54000000 + (r * 0x20) + cond)
}
// brk #imm16  (software breakpoint trap) → 0xd4200000 | (imm16 << 5)
func arm64_brk(imm16) {
    emit hexDword(0xd4200000 + (imm16 * 0x20))
}
// add Xd, Xn, Xm (64-bit, no shift, register form) — alias for the 3-reg add.
// Already covered by arm64_add_xxx; just alias here.
//
// Variable-size bump allocator. Size in x4 (clobbered for rounding). Returns
// pointer in x0. Uses x1 (cell ptr), x2 (new bump). 7 instructions.
// Note: no 8-byte alignment of allocations — caller may waste a few bytes
// per call but bump pointer eventually drifts. Acceptable for our heap sizes.
// 15 instructions; size in x4 (preserved across the call). Uses x5 for limit
// (instead of x4 like emitAllocN) so the size register isn't clobbered.
func emitAllocVar(instrIdx, textVaddr, textOff) {
    let bumpVaddr = g_DATA_VADDR + 0x4000
    let pcAtAdrp = textVaddr + textOff + instrIdx * 4
    let pcPage = pcAtAdrp / 4096 * 4096
    let bumpPage = bumpVaddr / 4096 * 4096
    let imm21 = (bumpPage - pcPage) / 4096
    let s = ""
    s = s + arm64_adrp(1, imm21)                        // 0
    s = s + arm64_add_imm(1, 1, bumpVaddr % 4096)       // 1
    s = s + arm64_ldr_imm(9, 1, 3)                      // 2: ldr x9, [x1, #24] (alloc_total)
    s = s + arm64_add_xxx(9, 9, 4)                      // 3: x9 += x4 (size)
    s = s + arm64_str_imm(9, 1, 3)                      // 4: str x9, [x1, #24]
    s = s + arm64_ldr_imm(10, 1, 4)                     // 5: ldr x10, [x1, #32] (alloc_limit)
    s = s + arm64_cbz(10, 4)                            // 6: if limit==0 skip 3
    s = s + arm64_cmp_xx(9, 10)                         // 7: cmp x9, x10
    s = s + arm64_b_cond(0x09, 2)                       // 8: b.ls +2 (skip brk)
    s = s + arm64_brk(99)                               // 9: brk #99 (limit exceeded)
    s = s + arm64_ldr_imm(0, 1, 0)                      // 10
    s = s + arm64_cbnz(0, 2)                            // 11
    s = s + arm64_add_imm(0, 1, 64)                     // 12: first-time init (matches emitAllocN)
    s = s + arm64_add_xxx(2, 0, 4)                      // 13: x2 = x0 + x4
    s = s + arm64_str_imm(2, 1, 0)                      // 14
    emit s
}

// Bump allocator. Allocates `n` bytes (rounded up to 8-byte alignment) from the
// heap. Returns address in x0. Uses x1 (bump cell ptr), x2 (new bump value).
// 7 instructions; the caller must add 7 to its instrIdx. The adrp imm21 is
// computed from the caller-provided absolute instruction index.
//
// **Layout note** — the bump cell lives in the *zero-fill* portion of __DATA
// (past DATA_FILESIZE). macOS marks the file-backed portion of __DATA as
// effectively read-only on code-signed binaries (the strb to a file-backed
// page SIGSEGVs even though initprot=R+W). The zero-fill region (anonymous
// pages mapped by the kernel) IS writable. So:
//   bump cell @ DATA_VADDR + DATA_FILESIZE  (= 0x10000_C000)
//   heap     @ DATA_VADDR + DATA_FILESIZE + 8 .. DATA_VADDR + DATA_VMSIZE
// The cell starts at zero (zero-fill default). The cbnz dance handles the
// first-time case: if loaded ptr is 0, treat the cell address + 8 as the
// initial heap pointer.
// 15 instructions when GC tracking + limit check are enabled (was 7 pre-1.7.5).
// System-area layout in __DATA zero-fill (per emitAllocN/Var convention):
//   +0  bump_cell        (existing)
//   +8  argc save        (set by __main__ prologue, read by argCount())
//   +16 argv save        (set by __main__ prologue, read by arg())
//   +24 alloc_total      (NEW — bytes allocated cumulative)
//   +32 alloc_limit      (NEW — soft cap; 0 = no limit)
//   +40..+63 reserved
//   +64.. heap
func emitAllocN(n, instrIdx, textVaddr, textOff) {
    let bumpVaddr = g_DATA_VADDR + 0x4000          // bump cell in zero-fill region
    let pcAtAdrp = textVaddr + textOff + instrIdx * 4
    let pcPage = pcAtAdrp / 4096 * 4096
    let bumpPage = bumpVaddr / 4096 * 4096
    let imm21 = (bumpPage - pcPage) / 4096
    let nAligned = ((n + 7) / 8) * 8
    let s = ""
    s = s + arm64_adrp(1, imm21)                        // 0: adrp x1, bump_cell@PAGE
    s = s + arm64_add_imm(1, 1, bumpVaddr % 4096)       // 1: add  x1, x1, bump_cell@PAGEOFF
    s = s + arm64_ldr_imm(9, 1, 3)                      // 2: ldr  x9, [x1, #24]   (alloc_total)
    s = s + arm64_add_imm(9, 9, nAligned)               // 3: x9 += nAligned
    s = s + arm64_str_imm(9, 1, 3)                      // 4: str  x9, [x1, #24]
    s = s + arm64_ldr_imm(10, 1, 4)                     // 5: ldr  x10, [x1, #32]  (alloc_limit)
    s = s + arm64_cbz(10, 4)                            // 6: if limit==0 skip 3 (jump to ldr at 10)
    s = s + arm64_cmp_xx(9, 10)                         // 7: cmp x9, x10
    s = s + arm64_b_cond(0x09, 2)                       // 8: b.ls +2 (if total <= limit, skip brk)
    s = s + arm64_brk(99)                               // 9: brk #99 (limit exceeded)
    s = s + arm64_ldr_imm(0, 1, 0)                      // 10: ldr  x0, [x1]   ; current free (or 0 first time)
    s = s + arm64_cbnz(0, 2)                            // 11: if x0 != 0 skip next 1
    s = s + arm64_add_imm(0, 1, 64)                     // 12: x0 = bump_cell + 64 (heap, past system area)
    s = s + arm64_add_imm(2, 0, nAligned)               // 13: x2 = x0 + nAligned
    s = s + arm64_str_imm(2, 1, 0)                      // 14: str x2, [x1]    ; advance bump
    emit s
}

// ── full IR parser (slice 3e: multi-function) ──────────────────────────────
// Supports: FUNC <name> <argc> / PARAM <name> / LOCAL <name> / PUSH "literal"
// or PUSH <int> / STORE <name> / LOAD <name> / arithmetic / comparisons /
// LABEL / JUMP / JUMPIFNOT / BUILTIN kp/exit / CALL <name> <argc> / RETURN /
// POP / END.
//
// Output format:
//   line 0:  nFunctions
//   line 1:  nStrings
//   lines 2..1+nStrings:  each unique global string
//   then for each function (in declaration order), one block:
//     header line:  <name>\t<nParams>\t<nLocals>\t<nOps>
//     nParams lines:  param names
//     nLocals lines:  non-param local names (params excluded)
//     nOps lines:     normalized ops, one per line
//
// LOAD/STORE are normalized to LOAD_SLOT <i> / STORE_SLOT <i> where
// slot 0..nParams-1 = params, slot nParams..nParams+nLocals-1 = locals.

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

// Find name in newline-separated list of `count` entries. Returns idx or -1.
func findInList(list, count, name) {
    let i = 0
    while i < count {
        if getLine(list, i) == name { emit i }
        i += 1
    }
    emit 0 - 1
}

// sb-backed intern: search current sb content for `name`; if missing, append.
// Returns the index. Avoids the O(N²) list-copy cost of internIntoList.
func internSb(sbHandle, count, name) {
    let snap = sbToString(sbHandle)
    let i = 0
    while i < count {
        if getLine(snap, i) == name { emit i }
        i += 1
    }
    if count > 0 { sbAppend(sbHandle, "\n") }
    sbAppend(sbHandle, name)
    emit count
}

// Append a function block (header + params + locals + ops) to a sb.
func appendFunc(sb, name, params, nParams, locals, nLocals, opsStr, nOps) {
    sb = sbAppend(sb, name + "\t" + nParams + "\t" + nLocals + "\t" + nOps + "\n")
    let pi = 0
    while pi < nParams {
        sb = sbAppend(sb, getLine(params, pi) + "\n")
        pi += 1
    }
    let li = 0
    while li < nLocals {
        sb = sbAppend(sb, getLine(locals, li) + "\n")
        li += 1
    }
    sb = sbAppend(sb, opsStr)
    if len(opsStr) > 0 {
        if opsStr[len(opsStr) - 1] != "\n" { sb = sbAppend(sb, "\n") }
    }
    emit sb
}

func parseFullIR(ir) {
    // sbStrings holds interned globals as a newline-separated string. Using sb
    // for O(name_length) append (vs O(total_strings_length) for string concat).
    let sbStrings = sbNew()
    let nStrings = 0
    let funcsSb = sbNew()
    let nFunctions = 0

    // Per-function state (resets at each FUNC line)
    let inFunc = "0"
    let curName = ""
    let sbParams = sbNew()
    let nParams = 0
    let sbLocals = sbNew()
    let nLocals = 0
    let curOps = sbNew()
    let nOps = 0

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

                if op == "FUNC" {
                    // Finalize previous function (if any)
                    if inFunc == "1" {
                        funcsSb = appendFunc(funcsSb, curName, sbToString(sbParams), nParams, sbToString(sbLocals), nLocals, sbToString(curOps), nOps)
                        nFunctions += 1
                    }
                    // Start new function: parse "FUNC <name> <argc>"
                    let sp = 0
                    while sp < len(rest) && rest[sp] != " " { sp += 1 }
                    curName = substring(rest, 0, sp)
                    nParams = 0
                    sbParams = sbNew()
                    nLocals = 0
                    sbLocals = sbNew()
                    curOps = sbNew()
                    nOps = 0
                    inFunc = "1"
                } else if op == "PARAM" {
                    if nParams > 0 { sbAppend(sbParams, "\n") }
                    sbAppend(sbParams, rest)
                    nParams += 1
                } else if op == "LOAD" {
                    let paramSnap = sbToString(sbParams)
                    let pIdx = findInList(paramSnap, nParams, rest)
                    let slot = 0 - 1
                    if pIdx >= 0 {
                        slot = pIdx
                    } else {
                        let localSnap = sbToString(sbLocals)
                        let lIdx = findInList(localSnap, nLocals, rest)
                        if lIdx >= 0 {
                            slot = nParams + lIdx
                        } else {
                            if nLocals > 0 { sbAppend(sbLocals, "\n") }
                            sbAppend(sbLocals, rest)
                            slot = nParams + nLocals
                            nLocals += 1
                        }
                    }
                    curOps = sbAppend(curOps, "LOAD_SLOT " + slot + "\n")
                    nOps += 1
                } else if op == "STORE" {
                    let paramSnap = sbToString(sbParams)
                    let pIdx = findInList(paramSnap, nParams, rest)
                    let slot = 0 - 1
                    if pIdx >= 0 {
                        slot = pIdx
                    } else {
                        let localSnap = sbToString(sbLocals)
                        let lIdx = findInList(localSnap, nLocals, rest)
                        if lIdx >= 0 {
                            slot = nParams + lIdx
                        } else {
                            if nLocals > 0 { sbAppend(sbLocals, "\n") }
                            sbAppend(sbLocals, rest)
                            slot = nParams + nLocals
                            nLocals += 1
                        }
                    }
                    curOps = sbAppend(curOps, "STORE_SLOT " + slot + "\n")
                    nOps += 1
                } else if op == "CALL" {
                    let sp = 0
                    while sp < len(rest) && rest[sp] != " " { sp += 1 }
                    let cname = substring(rest, 0, sp)
                    let cargc = "0"
                    if sp < len(rest) { cargc = trim(substring(rest, sp + 1, len(rest))) }
                    curOps = sbAppend(curOps, "CALL_FUNC " + cname + " " + cargc + "\n")
                    nOps += 1
                } else if op == "RETURN" {
                    curOps = sbAppend(curOps, "RETURN\n")
                    nOps += 1
                } else if op == "PUSH" {
                    if len(rest) > 0 {
                        if rest[0] == "\"" {
                            // Build content via sb. Krypton's IR uses `\\` (two
                            // backslashes) as the escape opener:
                            //   \\n / \\t / \\r → newline / tab / CR
                            //   \\           → single backslash (lone `\\`, no escape kind)
                            //   \"           → literal quote (single backslash + quote)
                            let contentSb = sbNew()
                            let k = 1
                            while k < len(rest) && rest[k] != "\"" {
                                if rest[k] == "\\" {
                                    if (k + 1) < len(rest) {
                                        let nxt = rest[k + 1]
                                        if nxt == "\\" {
                                            // \\ + kind? Look at rest[k+2].
                                            if (k + 2) < len(rest) {
                                                let c = rest[k + 2]
                                                if c == "n"      { contentSb = sbAppend(contentSb, "\n"); k += 3 }
                                                else if c == "t" { contentSb = sbAppend(contentSb, "\t"); k += 3 }
                                                else if c == "r" { contentSb = sbAppend(contentSb, "\r"); k += 3 }
                                                else if c == "0" { k += 3 }   // skip null escape
                                                else {
                                                    // Lone `\\` (not followed by an escape kind) = single backslash
                                                    contentSb = sbAppend(contentSb, "\\")
                                                    k += 2
                                                }
                                            } else {
                                                contentSb = sbAppend(contentSb, "\\")
                                                k += 2
                                            }
                                        } else if nxt == "\"" {
                                            contentSb = sbAppend(contentSb, "\"")
                                            k += 2
                                        } else {
                                            // Lone `\` followed by something — treat as literal
                                            contentSb = sbAppend(contentSb, rest[k])
                                            k += 1
                                        }
                                    } else {
                                        contentSb = sbAppend(contentSb, rest[k])
                                        k += 1
                                    }
                                } else {
                                    contentSb = sbAppend(contentSb, rest[k])
                                    k += 1
                                }
                            }
                            // Store strings as hex-encoded (xHH...) so resolved
                            // escape bytes (newlines, tabs) don't collide with
                            // the line-based parsed format.
                            let content = asciiToHex(sbToString(contentSb))
                            let idx = internSb(sbStrings, nStrings, content)
                            if idx == nStrings { nStrings += 1 }
                            curOps = sbAppend(curOps, "PUSH_STR " + idx + "\n")
                            nOps += 1
                        } else {
                            curOps = sbAppend(curOps, "PUSH_INT " + rest + "\n")
                            nOps += 1
                        }
                    }
                } else if op == "ADD" || op == "SUB" || op == "MUL" || op == "DIV" || op == "MOD" || op == "LT" || op == "GT" || op == "EQ" {
                    curOps = sbAppend(curOps, op + "\n")
                    nOps += 1
                } else if op == "LTE" {
                    curOps = sbAppend(curOps, "LE\n")
                    nOps += 1
                } else if op == "GTE" {
                    curOps = sbAppend(curOps, "GE\n")
                    nOps += 1
                } else if op == "NEQ" {
                    curOps = sbAppend(curOps, "NE\n")
                    nOps += 1
                } else if op == "LABEL" {
                    curOps = sbAppend(curOps, "LABEL " + rest + "\n")
                    nOps += 1
                } else if op == "JUMP" {
                    curOps = sbAppend(curOps, "JUMP " + rest + "\n")
                    nOps += 1
                } else if op == "JUMPIFNOT" {
                    curOps = sbAppend(curOps, "JUMPIFNOT " + rest + "\n")
                    nOps += 1
                } else if op == "JUMPIF" {
                    curOps = sbAppend(curOps, "JUMPIF " + rest + "\n")
                    nOps += 1
                } else if op == "BREAK" {
                    // Resolve to a JUMP to the next LABEL _wend_* in the remaining IR
                    // (innermost enclosing while loop's end label).
                    let target = ""
                    let scan = i + 1
                    while scan < nl {
                        let sl = trim(getLine(ir, scan))
                        if startsWith(sl, "LABEL _wend_") {
                            target = trim(substring(sl, 6, len(sl)))
                            scan = nl
                        }
                        scan += 1
                    }
                    curOps = sbAppend(curOps, "JUMP " + target + "\n")
                    nOps += 1
                } else if op == "NEG" {
                    curOps = sbAppend(curOps, "NEG\n")
                    nOps += 1
                } else if op == "NOT" {
                    curOps = sbAppend(curOps, "NOT\n")
                    nOps += 1
                } else if op == "INDEX" {
                    curOps = sbAppend(curOps, "INDEX\n")
                    nOps += 1
                } else if op == "LOCAL" {
                    // Skip if already a param; otherwise add to locals list (no op emitted)
                    let pIdx = findInList(sbToString(sbParams), nParams, rest)
                    if pIdx < 0 {
                        let lIdx = findInList(sbToString(sbLocals), nLocals, rest)
                        if lIdx < 0 {
                            if nLocals > 0 { sbAppend(sbLocals, "\n") }
                            sbAppend(sbLocals, rest)
                            nLocals += 1
                        }
                    }
                } else if op == "BUILTIN" {
                    let bj = 0
                    while bj < len(rest) && rest[bj] != " " { bj += 1 }
                    let bname = substring(rest, 0, bj)
                    if bname == "kp" {
                        curOps = sbAppend(curOps, "BUILTIN_KP\n")
                        nOps += 1
                    } else if bname == "exit" {
                        curOps = sbAppend(curOps, "BUILTIN_EXIT\n")
                        nOps += 1
                    } else if bname == "len" {
                        curOps = sbAppend(curOps, "BUILTIN_LEN\n")
                        nOps += 1
                    } else if bname == "charCode" {
                        curOps = sbAppend(curOps, "BUILTIN_CHARCODE\n")
                        nOps += 1
                    } else if bname == "substring" {
                        curOps = sbAppend(curOps, "BUILTIN_SUBSTRING\n")
                        nOps += 1
                    } else if bname == "startsWith" {
                        curOps = sbAppend(curOps, "BUILTIN_STARTSWITH\n")
                        nOps += 1
                    } else if bname == "isDigit" {
                        curOps = sbAppend(curOps, "BUILTIN_ISDIGIT\n")
                        nOps += 1
                    } else if bname == "toInt" {
                        curOps = sbAppend(curOps, "BUILTIN_TOINT\n")
                        nOps += 1
                    } else if bname == "indexOf" {
                        curOps = sbAppend(curOps, "BUILTIN_INDEXOF\n")
                        nOps += 1
                    } else if bname == "sbNew" {
                        curOps = sbAppend(curOps, "BUILTIN_SBNEW\n")
                        nOps += 1
                    } else if bname == "sbAppend" {
                        curOps = sbAppend(curOps, "BUILTIN_SBAPPEND\n")
                        nOps += 1
                    } else if bname == "sbToString" {
                        curOps = sbAppend(curOps, "BUILTIN_SBTOSTRING\n")
                        nOps += 1
                    } else if bname == "length" {
                        // length() on lists; for compile.k usage on strings it's same as len
                        curOps = sbAppend(curOps, "BUILTIN_LEN\n")
                        nOps += 1
                    } else if bname == "contains" {
                        curOps = sbAppend(curOps, "BUILTIN_CONTAINS\n")
                        nOps += 1
                    } else if bname == "print" {
                        curOps = sbAppend(curOps, "BUILTIN_PRINT\n")
                        nOps += 1
                    } else if bname == "printErr" {
                        curOps = sbAppend(curOps, "BUILTIN_PRINTERR\n")
                        nOps += 1
                    } else if bname == "pow" {
                        curOps = sbAppend(curOps, "BUILTIN_POW\n")
                        nOps += 1
                    } else if bname == "endsWith" {
                        curOps = sbAppend(curOps, "BUILTIN_ENDSWITH\n")
                        nOps += 1
                    } else if bname == "arg" {
                        curOps = sbAppend(curOps, "BUILTIN_ARG\n")
                        nOps += 1
                    } else if bname == "argCount" {
                        curOps = sbAppend(curOps, "BUILTIN_ARGCOUNT\n")
                        nOps += 1
                    } else if bname == "readFile" {
                        curOps = sbAppend(curOps, "BUILTIN_READFILE\n")
                        nOps += 1
                    } else if bname == "writeFile" {
                        curOps = sbAppend(curOps, "BUILTIN_WRITEFILE\n")
                        nOps += 1
                    } else if bname == "trim" {
                        curOps = sbAppend(curOps, "BUILTIN_TRIM\n")
                        nOps += 1
                    } else if bname == "gcAllocated" {
                        curOps = sbAppend(curOps, "BUILTIN_GCALLOCATED\n")
                        nOps += 1
                    } else if bname == "gcLimit" {
                        curOps = sbAppend(curOps, "BUILTIN_GCLIMIT\n")
                        nOps += 1
                    } else if bname == "gcSetLimit" {
                        curOps = sbAppend(curOps, "BUILTIN_GCSETLIMIT\n")
                        nOps += 1
                    } else if bname == "gcReset" {
                        curOps = sbAppend(curOps, "BUILTIN_GCRESET\n")
                        nOps += 1
                    } else if bname == "gcCollect" {
                        curOps = sbAppend(curOps, "BUILTIN_GCCOLLECT\n")
                        nOps += 1
                    }
                } else if op == "POP" {
                    curOps = sbAppend(curOps, "POP\n")
                    nOps += 1
                } else if op == "END" {
                    curOps = sbAppend(curOps, "END\n")
                    nOps += 1
                }
            }
        }
        i += 1
    }
    // Finalize last function
    if inFunc == "1" {
        funcsSb = appendFunc(funcsSb, curName, sbToString(sbParams), nParams, sbToString(sbLocals), nLocals, sbToString(curOps), nOps)
        nFunctions += 1
    }
    // Build final output: nFunctions, nStrings, strings, then function blocks
    let r = ("" + nFunctions) + "\n" + ("" + nStrings) + "\n"
    if nStrings > 0 { r = r + sbToString(sbStrings) + "\n" }
    r = r + sbToString(funcsSb)
    emit r
}

// New parsed format (slice 3e):
//   line 0: nFunctions
//   line 1: nStrings
//   lines 2..1+nStrings: each unique string (global)
//   then per-function blocks: header line + nParams param names + nLocals
//   local names + nOps op lines.

func irStringStart() { emit 2 }

// Strings in `parsed` are hex-encoded (xHH...) — each "byte" of content takes
// 3 chars in the stored form. hexBytesLen converts back.

func computeStringOffsets(parsed) {
    let nStrings = toInt(getLine(parsed, 1))
    let r = ""
    let off = 0
    let si = 0
    while si < nStrings {
        if si > 0 { r = r + "\n" }
        r = r + ("" + off)
        let s = getLine(parsed, irStringStart() + si)
        off = off + hexBytesLen(s) + 1   // +1 for NUL terminator
        si += 1
    }
    emit r
}

func computeCStringSize(parsed) {
    let nStrings = toInt(getLine(parsed, 1))
    let off = 0
    let si = 0
    while si < nStrings {
        let s = getLine(parsed, irStringStart() + si)
        off = off + hexBytesLen(s) + 1
        si += 1
    }
    emit off
}

func emitCStringFromIR(parsed) {
    let nStrings = toInt(getLine(parsed, 1))
    let s = ""
    let si = 0
    while si < nStrings {
        let strHex = getLine(parsed, irStringStart() + si)
        s = s + strHex + hexByte(0)       // already hex-encoded; just append NUL byte
        si += 1
    }
    emit s
}

// ── per-function accessors ─────────────────────────────────────────────────

// Convert a function header "name\tnP\tnL\tnO" into a 4-line sub-string.
func parseFuncHeader(h) {
    let out = ""
    let i = 0
    while i < len(h) {
        if h[i] == "\t" { out = out + "\n" } else { out = out + h[i] }
        i += 1
    }
    emit out
}

func funcCount(parsed) { emit toInt(getLine(parsed, 0)) }

// Return the line number in `parsed` of the header for function fIdx.
// Uses g_funcStartCache when populated (set by buildFuncStartCache).
func funcStartLine(parsed, fIdx) {
    if len(g_funcStartCache) > 0 {
        emit toInt(getLine(g_funcStartCache, fIdx))
    }
    // Cold path (no cache): linear walk.
    let nStrings = toInt(getLine(parsed, 1))
    let pos = 2 + nStrings
    let i = 0
    while i < fIdx {
        let h = getLine(parsed, pos)
        let parts = parseFuncHeader(h)
        let nP = toInt(getLine(parts, 1))
        let nL = toInt(getLine(parts, 2))
        let nO = toInt(getLine(parts, 3))
        pos = pos + 1 + nP + nL + nO
        i += 1
    }
    emit pos
}

// Build the function-start cache (newline-separated start lines, one per func).
func buildFuncStartCache(parsed) {
    let nF = funcCount(parsed)
    let nStrings = toInt(getLine(parsed, 1))
    let pos = 2 + nStrings
    let sb = sbNew()
    let i = 0
    while i < nF {
        if i > 0 { sbAppend(sb, "\n") }
        sbAppend(sb, "" + pos)
        let h = getLine(parsed, pos)
        let parts = parseFuncHeader(h)
        let nP = toInt(getLine(parts, 1))
        let nL = toInt(getLine(parts, 2))
        let nO = toInt(getLine(parts, 3))
        pos = pos + 1 + nP + nL + nO
        i += 1
    }
    emit sbToString(sb)
}

func funcName(parsed, fIdx) {
    let h = getLine(parsed, funcStartLine(parsed, fIdx))
    let i = 0
    while i < len(h) && h[i] != "\t" { i += 1 }
    emit substring(h, 0, i)
}
func funcNParams(parsed, fIdx) {
    let parts = parseFuncHeader(getLine(parsed, funcStartLine(parsed, fIdx)))
    emit toInt(getLine(parts, 1))
}
func funcNLocals(parsed, fIdx) {
    let parts = parseFuncHeader(getLine(parsed, funcStartLine(parsed, fIdx)))
    emit toInt(getLine(parts, 2))
}
func funcNOps(parsed, fIdx) {
    let parts = parseFuncHeader(getLine(parsed, funcStartLine(parsed, fIdx)))
    emit toInt(getLine(parts, 3))
}
func funcOp(parsed, fIdx, oIdx) {
    let s = funcStartLine(parsed, fIdx)
    let nP = funcNParams(parsed, fIdx)
    let nL = funcNLocals(parsed, fIdx)
    emit getLine(parsed, s + 1 + nP + nL + oIdx)
}

// Per-function frame size (8 B per param+local, rounded up to 16).
func computeFrameSizeF(parsed, fIdx) {
    let total = funcNParams(parsed, fIdx) + funcNLocals(parsed, fIdx)
    if total == 0 { emit 0 }
    emit ((total + 1) / 2) * 16
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
// Per-op instruction count (frame-independent ops only — RETURN/END/CALL_FUNC
// are handled at the caller because they depend on frame size or argc).
func opInstrCount(opTok) {
    if opTok == "PUSH_STR"     { emit 3 }
    if opTok == "PUSH_INT"     { emit 2 }
    if opTok == "LOAD_SLOT"    { emit 2 }
    if opTok == "STORE_SLOT"   { emit 2 }
    if opTok == "ADD"          { emit 4 }
    if opTok == "SUB"          { emit 4 }
    if opTok == "MUL"          { emit 4 }
    if opTok == "DIV"          { emit 4 }
    if opTok == "MOD"          { emit 5 }
    if opTok == "LT"           { emit 5 }
    if opTok == "GT"           { emit 5 }
    if opTok == "LE"           { emit 5 }
    if opTok == "GE"           { emit 5 }
    if opTok == "EQ"           { emit 5 }
    if opTok == "NE"           { emit 5 }
    if opTok == "JUMP"             { emit 1 }
    if opTok == "JUMPIFNOT"        { emit 2 }
    if opTok == "JUMPIF"           { emit 2 }
    if opTok == "LABEL"            { emit 0 }
    if opTok == "NEG"              { emit 3 }   // pop, neg, push
    if opTok == "NOT"              { emit 4 }   // pop, cmp, cset, push
    if opTok == "INDEX"            { emit 21 }  // pop i, pop s, alloc(15), ldrb, strb char, strb NUL, push
    if opTok == "BUILTIN_KP"       { emit 21 }  // direct write() + write("\n") via syscall, survives explicit exit()
    if opTok == "BUILTIN_EXIT"     { emit 5 }
    if opTok == "BUILTIN_LEN"      { emit 7 }   // pop, mov, ldrb-post, cbnz, sub-reg, sub-imm, push
    if opTok == "BUILTIN_CHARCODE" { emit 3 }   // pop, ldrb, push
    if opTok == "BUILTIN_SUBSTRING"{ emit 31 }
    if opTok == "BUILTIN_STARTSWITH"{ emit 14 }
    if opTok == "BUILTIN_ISDIGIT"  { emit 10 }
    if opTok == "BUILTIN_TOINT"    { emit 16 }
    if opTok == "BUILTIN_INDEXOF"  { emit 21 }
    if opTok == "BUILTIN_SBNEW"        { emit 18 }
    if opTok == "BUILTIN_SBAPPEND"     { emit 21 }
    if opTok == "BUILTIN_SBTOSTRING"   { emit 3 }
    if opTok == "BUILTIN_CONTAINS"     { emit 23 }   // indexOf core (20) + cmp + cset + push
    if opTok == "BUILTIN_PRINT"        { emit 12 }
    if opTok == "BUILTIN_PRINTERR"     { emit 12 }
    if opTok == "BUILTIN_POW"          { emit 8 }
    if opTok == "BUILTIN_ENDSWITH"     { emit 29 }
    if opTok == "BUILTIN_ARG"          { emit 21 }  // inline-toInt + load argv + index
    if opTok == "BUILTIN_ARGCOUNT"     { emit 5 }
    if opTok == "BUILTIN_READFILE"     { emit 35 }
    if opTok == "BUILTIN_WRITEFILE"    { emit 22 }
    if opTok == "BUILTIN_TRIM"         { emit 50 }
    if opTok == "BUILTIN_GCALLOCATED"  { emit 4 }   // adrp + add + ldr [x1,#24] + push
    if opTok == "BUILTIN_GCLIMIT"      { emit 4 }   // adrp + add + ldr [x1,#32] + push
    if opTok == "BUILTIN_GCSETLIMIT"   { emit 5 }   // pop + adrp + add + str [x1,#32] + push
    if opTok == "BUILTIN_GCRESET"      { emit 6 }   // adrp + add + str xzr,[x1] + str xzr,[x1,#24] + movz + push
    if opTok == "BUILTIN_GCCOLLECT"    { emit 2 }   // movz + push (no-op stub)
    if opTok == "POP"              { emit 1 }
    emit 0
}

// Look up a "name=value" entry in a newline-separated table. Returns value
// (parsed as int) or -1 if not found. Used for both label tables and the
// function table.
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

// Compute the total instruction count of one function (frame-aware).
func computeFunctionInstrs(parsed, fIdx) {
    let frame = computeFrameSizeF(parsed, fIdx)
    let nP = funcNParams(parsed, fIdx)
    let nO = funcNOps(parsed, fIdx)
    let n = 2                      // prologue: stp + mov fp sp
    if frame > 0 { n = n + 1 }     // sub sp
    n = n + nP                     // save each param
    // __main__ also saves argc/argv to fixed cells (4 instr)
    if funcName(parsed, fIdx) == "__main__" { n = n + 4 }
    let oi = 0
    while oi < nO {
        let opLine = funcOp(parsed, fIdx, oi)
        let sp = 0
        while sp < len(opLine) && opLine[sp] != " " { sp += 1 }
        let tok = substring(opLine, 0, sp)
        if tok == "CALL_FUNC" {
            let s2 = sp + 1
            while s2 < len(opLine) && opLine[s2] != " " { s2 += 1 }
            let argc = 0
            if s2 < len(opLine) { argc = toInt(trim(substring(opLine, s2 + 1, len(opLine)))) }
            n = n + argc + 2
        } else if tok == "RETURN" {
            n = n + 3
            if frame > 0 { n = n + 1 }
        } else if tok == "END" {
            n = n + 3
            if frame > 0 { n = n + 1 }
        } else {
            n = n + opInstrCount(tok)
        }
        oi += 1
    }
    emit n
}

// Build per-function label table. instrIdx is "absolute" within __text (so
// callers can compute jump deltas without separate per-function bias).
func buildFunctionLabelTable(parsed, fIdx, funcStartInstr) {
    let frame = computeFrameSizeF(parsed, fIdx)
    let nP = funcNParams(parsed, fIdx)
    let nO = funcNOps(parsed, fIdx)
    let table = ""
    let n = funcStartInstr + 2
    if frame > 0 { n = n + 1 }
    n = n + nP
    if funcName(parsed, fIdx) == "__main__" { n = n + 4 }
    let oi = 0
    while oi < nO {
        let opLine = funcOp(parsed, fIdx, oi)
        let sp = 0
        while sp < len(opLine) && opLine[sp] != " " { sp += 1 }
        let tok = substring(opLine, 0, sp)
        if tok == "LABEL" {
            let name = trim(substring(opLine, sp + 1, len(opLine)))
            if len(table) > 0 { table = table + "\n" }
            table = table + name + "=" + ("" + n)
        } else if tok == "CALL_FUNC" {
            let s2 = sp + 1
            while s2 < len(opLine) && opLine[s2] != " " { s2 += 1 }
            let argc = 0
            if s2 < len(opLine) { argc = toInt(trim(substring(opLine, s2 + 1, len(opLine)))) }
            n = n + argc + 2
        } else if tok == "RETURN" {
            n = n + 3
            if frame > 0 { n = n + 1 }
        } else if tok == "END" {
            n = n + 3
            if frame > 0 { n = n + 1 }
        } else {
            n = n + opInstrCount(tok)
        }
        oi += 1
    }
    emit table
}

// Find the function index of __main__ (or -1 if absent).
func mainFuncIndex(parsed) {
    let nF = funcCount(parsed)
    let i = 0
    while i < nF {
        if funcName(parsed, i) == "__main__" { emit i }
        i += 1
    }
    emit 0 - 1
}

// Emission order: __main__ first (so its code is at TEXT_OFF, matching
// LC_MAIN's entryoff), then other functions in declaration order.
func emitOrder(parsed) {
    let nF = funcCount(parsed)
    let mainIdx = mainFuncIndex(parsed)
    let r = ""
    if mainIdx >= 0 { r = "" + mainIdx }
    let i = 0
    while i < nF {
        if i != mainIdx {
            if len(r) > 0 { r = r + "\n" }
            r = r + ("" + i)
        }
        i += 1
    }
    emit r
}

// Function table: name → starting instruction index in __text. Uses emitOrder
// (__main__ first), so the entry point at TEXT_OFF is always __main__.
func buildFunctionTable(parsed) {
    let order = emitOrder(parsed)
    let nF = funcCount(parsed)
    let r = ""
    let cur = 0
    let oi = 0
    while oi < nF {
        let fIdx = toInt(getLine(order, oi))
        if oi > 0 { r = r + "\n" }
        r = r + funcName(parsed, fIdx) + "=" + ("" + cur)
        cur = cur + computeFunctionInstrs(parsed, fIdx)
        oi += 1
    }
    emit r
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

// Total __text size in bytes — sum of all functions.
func computeTextSize(parsed) {
    let nF = funcCount(parsed)
    let total = 0
    let i = 0
    while i < nF {
        total = total + computeFunctionInstrs(parsed, i)
        i += 1
    }
    emit total * 4
}

// Emit one function: prologue (with param save) + ops + epilogue. instrIdx is
// absolute within __text (so jumps can use absolute deltas).
func emitOneFunction(parsed, fIdx, funcStartInstr, funcTable, strOffsets) {
    let frame = computeFrameSizeF(parsed, fIdx)
    let nP = funcNParams(parsed, fIdx)
    let nO = funcNOps(parsed, fIdx)
    let labels = buildFunctionLabelTable(parsed, fIdx, funcStartInstr)

    let textVaddr = 0x100000000
    let textOff = 0x460
    let stubsOff = textOff + g_TEXT_SIZE
    let cstringOff = stubsOff + 12
    let stubVaddr = textVaddr + stubsOff

    let s = ""
    let instrIdx = funcStartInstr

    s = s + arm64_stp_fp_lr_pre16()
    s = s + arm64_mov_fp_sp()
    instrIdx = instrIdx + 2
    if frame > 0 {
        s = s + arm64_sub_sp(frame)
        instrIdx = instrIdx + 1
    }
    // Save params x0..x(nP-1) into local slots
    let pi = 0
    while pi < nP {
        let off = 0 - (8 + pi * 8)
        s = s + arm64_stur(pi, 29, off)
        instrIdx = instrIdx + 1
        pi += 1
    }
    // __main__ saves argc/argv to fixed __DATA cells so arg()/argCount() can read.
    // Layout: bump cell @ +0, argc save @ +8, argv save @ +16, heap from +64.
    if funcName(parsed, fIdx) == "__main__" {
        let bumpVaddr = g_DATA_VADDR + 0x4000
        let pcAtAdrp = textVaddr + textOff + instrIdx * 4
        let pcPage = pcAtAdrp / 4096 * 4096
        let bumpPage = bumpVaddr / 4096 * 4096
        let imm21 = (bumpPage - pcPage) / 4096
        s = s + arm64_adrp(9, imm21)
        s = s + arm64_add_imm(9, 9, bumpVaddr % 4096)
        s = s + arm64_str_imm(0, 9, 1)        // str x0 (argc), [x9, #8]
        s = s + arm64_str_imm(1, 9, 2)        // str x1 (argv), [x9, #16]
        instrIdx = instrIdx + 4
    }

    let oi = 0
    while oi < nO {
        let opLine = funcOp(parsed, fIdx, oi)
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
            s = s + arm64_add_imm(0, 0, strVaddr % 4096)
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 3
        } else if opTok == "PUSH_INT" {
            let n = toInt(restTok)
            if n >= 0 {
                s = s + arm64_movz_x_imm(0, n % 65536)
            } else {
                s = s + arm64_movn_x_imm(0, (0 - n - 1) % 65536)
            }
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 2
        } else if opTok == "ADD" {
            s = s + arm64_pop(0)
            s = s + arm64_pop(1)
            s = s + arm64_add_xxx(0, 1, 0)
            s = s + arm64_push(0)
            instrIdx = instrIdx + 4
        } else if opTok == "SUB" {
            s = s + arm64_pop(0)
            s = s + arm64_pop(1)
            s = s + arm64_sub_xxx(0, 1, 0)
            s = s + arm64_push(0)
            instrIdx = instrIdx + 4
        } else if opTok == "MUL" {
            s = s + arm64_pop(0)
            s = s + arm64_pop(1)
            s = s + arm64_mul_xxx(0, 1, 0)
            s = s + arm64_push(0)
            instrIdx = instrIdx + 4
        } else if opTok == "DIV" {
            s = s + arm64_pop(0)
            s = s + arm64_pop(1)
            s = s + arm64_sdiv_xxx(0, 1, 0)
            s = s + arm64_push(0)
            instrIdx = instrIdx + 4
        } else if opTok == "MOD" {
            s = s + arm64_pop(0)
            s = s + arm64_pop(1)
            s = s + arm64_sdiv_xxx(2, 1, 0)
            s = s + arm64_msub_xxxx(0, 2, 0, 1)
            s = s + arm64_push(0)
            instrIdx = instrIdx + 5
        } else if opTok == "BUILTIN_EXIT" {
            s = s + arm64_pop_x0()
            s = s + arm64_movz_x_imm(16, 1)
            s = s + arm64_svc(0x80)
            s = s + arm64_movz_w_imm(0, 0)
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 5
        } else if opTok == "LT" || opTok == "GT" || opTok == "LE" || opTok == "GE" || opTok == "EQ" || opTok == "NE" {
            s = s + arm64_pop(0)
            s = s + arm64_pop(1)
            s = s + arm64_cmp_xx(1, 0)
            s = s + arm64_cset(0, irCmpToCond(opTok))
            s = s + arm64_push(0)
            instrIdx = instrIdx + 5
        } else if opTok == "LABEL" {
            // No instructions
        } else if opTok == "JUMP" {
            let target = findLabel(labels, restTok)
            let delta = target - instrIdx
            s = s + arm64_b(delta)
            instrIdx = instrIdx + 1
        } else if opTok == "JUMPIFNOT" {
            s = s + arm64_pop_x0()
            instrIdx = instrIdx + 1
            let target = findLabel(labels, restTok)
            let delta = target - instrIdx
            s = s + arm64_cbz(0, delta)
            instrIdx = instrIdx + 1
        } else if opTok == "JUMPIF" {
            s = s + arm64_pop_x0()
            instrIdx = instrIdx + 1
            let target = findLabel(labels, restTok)
            let delta = target - instrIdx
            s = s + arm64_cbnz(0, delta)
            instrIdx = instrIdx + 1
        } else if opTok == "NEG" {
            s = s + arm64_pop_x0()
            s = s + arm64_sub_xxx(0, 31, 0)         // sub x0, xzr, x0  (negate)
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 3
        } else if opTok == "NOT" {
            s = s + arm64_pop_x0()
            s = s + arm64_cmp_imm(0, 0)             // cmp x0, #0
            s = s + arm64_cset(0, 0x0)              // x0 = (x0 == 0) ? 1 : 0
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 4
        } else if opTok == "BUILTIN_LEN" {
            // len(s): pop string ptr, compute strlen inline, push int.
            //   mov  x1, x0           ; saved start
            //   ldrb w2, [x0], #1     ; load byte, post-inc
            //   cbnz w2, prev         ; loop back to ldrb if non-zero
            //   sub  x0, x0, x1       ; end - start
            //   sub  x0, x0, #1       ; subtract the NUL we counted past
            s = s + arm64_pop_x0()
            s = s + arm64_mov_xx(1, 0)
            s = s + arm64_ldrb_post(2, 0, 1)
            s = s + arm64_cbnz(2, 0 - 1)            // back 1 instruction (to ldrb)
            s = s + arm64_sub_xxx(0, 0, 1)
            s = s + arm64_sub_imm(0, 0, 1)
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 7
        } else if opTok == "BUILTIN_CHARCODE" {
            // charCode(s): pop string ptr, ldrb first byte, push as int.
            s = s + arm64_pop_x0()
            s = s + arm64_ldrb_zero(0, 0)           // ldrb w0, [x0]
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 3
        } else if opTok == "INDEX" {
            // s[i]: pop i (x3), pop s (x4), alloc 2 bytes (→ x0), copy s[i], NUL, push x0.
            s = s + arm64_pop(3)                    // x3 = i
            s = s + arm64_pop(4)                    // x4 = s
            instrIdx = instrIdx + 2
            s = s + emitAllocN(2, instrIdx, textVaddr, textOff)
            instrIdx = instrIdx + 15
            s = s + arm64_ldrb_reg(5, 4, 3)         // ldrb w5, [x4, x3]
            s = s + arm64_strb_imm(5, 0, 0)         // strb w5, [x0]
            s = s + arm64_strb_imm(31, 0, 1)        // strb wzr, [x0, #1]
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 4
        } else if opTok == "BUILTIN_SUBSTRING" {
            // substring(s, start, end): args on eval stack — TOS = end.
            s = s + arm64_pop(6)                    // x6 = end
            s = s + arm64_pop(7)                    // x7 = start
            s = s + arm64_pop(8)                    // x8 = s
            s = s + arm64_sub_xxx(4, 6, 7)          // x4 = end - start (len_data)
            s = s + arm64_add_imm(4, 4, 1)          // x4 = len_data + 1 (alloc room for NUL)
            instrIdx = instrIdx + 5
            s = s + emitAllocVar(instrIdx, textVaddr, textOff)
            instrIdx = instrIdx + 15
            s = s + arm64_add_xxx(9, 8, 7)          // x9 = src = s + start
            s = s + arm64_movz_x_imm(5, 0)          // x5 = i = 0
            s = s + arm64_sub_imm(4, 4, 1)          // x4 = len_data
            s = s + arm64_cmp_xx(5, 4)              // cmp i, len_data
            s = s + arm64_b_cond(0xa, 5)            // b.ge done (+5: ldrb,strb,add,b,strb_NUL)
            s = s + arm64_ldrb_reg(10, 9, 5)        // ldrb w10, [x9, x5]
            s = s + arm64_strb_reg(10, 0, 5)        // strb w10, [x0, x5]
            s = s + arm64_add_imm(5, 5, 1)          // i++
            s = s + arm64_b(0 - 5)                  // back to cmp
            s = s + arm64_strb_reg(31, 0, 4)        // strb wzr, [x0, x4] (NUL terminator)
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 11
        } else if opTok == "BUILTIN_STARTSWITH" {
            // startsWith(s, prefix): returns 1 if s starts with prefix, 0 otherwise.
            // Stack TOS = prefix, then s.
            s = s + arm64_pop(6)                    // x6 = prefix
            s = s + arm64_pop(7)                    // x7 = s
            s = s + arm64_movz_x_imm(5, 0)          // i = 0
            // LOOP_HEAD (instr 3 within op):
            s = s + arm64_ldrb_reg(8, 6, 5)         // w8 = prefix[i]
            s = s + arm64_cbz(8, 8)                 // if prefix[i]==0 → SUCCESS at instr 12 (+8)
            s = s + arm64_ldrb_reg(9, 7, 5)         // w9 = s[i]
            s = s + arm64_cmp_xx(8, 9)
            s = s + arm64_b_cond(0x1, 3)            // b.ne FAIL at instr 10 (+3)
            s = s + arm64_add_imm(5, 5, 1)          // i++
            s = s + arm64_b(0 - 6)                  // back to LOOP_HEAD
            // FAIL (after the back-jump, +1):
            s = s + arm64_movz_x_imm(0, 0)
            s = s + arm64_b(2)                      // skip success branch (+2 to push)
            // SUCCESS:
            s = s + arm64_movz_x_imm(0, 1)
            // END:
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 14
        } else if opTok == "BUILTIN_ISDIGIT" {
            // isDigit(s): returns 1 if s[0] is '0'..'9', 0 otherwise.
            s = s + arm64_pop(6)                    // x6 = s
            s = s + arm64_ldrb_zero(0, 6)           // w0 = s[0]
            s = s + arm64_cmp_imm(0, 48)            // '0'
            s = s + arm64_b_cond(0xb, 5)            // b.lt notdigit (+5)
            s = s + arm64_cmp_imm(0, 57)            // '9'
            s = s + arm64_b_cond(0xc, 3)            // b.gt notdigit (+3)
            s = s + arm64_movz_x_imm(0, 1)          // yes
            s = s + arm64_b(2)                      // skip notdigit
            // NOTDIGIT:
            s = s + arm64_movz_x_imm(0, 0)
            // END:
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 10
        } else if opTok == "BUILTIN_TOINT" {
            // toInt(s): parse decimal digits → int. 16 instructions.
            // Layout (instr indices within this op):
            //   0:pop  1:movz x0  2:movz x5  3:movz x4
            //   4:ldrb  5:cbz→DONE(+10)  6:cmp48  7:b.lt→DONE(+8)
            //   8:cmp57  9:b.gt→DONE(+6)  10:sub48  11:mul  12:add x0  13:add x5
            //   14:b←LOOP(-10)  15:push (DONE)
            s = s + arm64_pop(7)
            s = s + arm64_movz_x_imm(0, 0)
            s = s + arm64_movz_x_imm(5, 0)
            s = s + arm64_movz_x_imm(4, 10)
            s = s + arm64_ldrb_reg(6, 7, 5)
            s = s + arm64_cbz(6, 10)
            s = s + arm64_cmp_imm(6, 48)
            s = s + arm64_b_cond(0xb, 8)
            s = s + arm64_cmp_imm(6, 57)
            s = s + arm64_b_cond(0xc, 6)
            s = s + arm64_sub_imm(6, 6, 48)
            s = s + arm64_mul_xxx(0, 0, 4)
            s = s + arm64_add_xxx(0, 0, 6)
            s = s + arm64_add_imm(5, 5, 1)
            s = s + arm64_b(0 - 10)
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 16
        } else if opTok == "BUILTIN_SBNEW" {
            // sbNew(): alloc 32 KB, init length=0, return ptr.
            // Layout of sb buffer: [8-byte length][data ...].
            s = s + arm64_movz_x_imm(4, 32768)      // size = 32 KB
            instrIdx = instrIdx + 1
            s = s + emitAllocVar(instrIdx, textVaddr, textOff)
            instrIdx = instrIdx + 15
            s = s + arm64_str_imm(31, 0, 0)         // str xzr, [x0]  (len = 0)
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 2
        } else if opTok == "BUILTIN_SBAPPEND" {
            // sbAppend(sb, s): copy s bytes after sb's data, update length, return sb.
            // Stack TOS = s, then sb.
            // 21 instructions; layout (0-indexed within this op):
            //   0:pop x6=s  1:pop x7=sb
            //   2:ldr x4=len[sb]  3:add x8=sb+8  4:add x8+=x4 (dest)
            //   5:movz x5=0 (i)
            //   6:ldrb w9=s[i] (STRLEN)  7:cbz→DONE_STRLEN(+3)  8:add i++  9:b STRLEN(-3)
            //   10:movz x9=0 (j) (DONE_STRLEN)
            //   11:cmp j,x5 (COPY)  12:b.ge→COPY_DONE(+5)  13:ldrb w10=s[j]  14:strb w10=dest[j]  15:add j++  16:b COPY(-5)
            //   17:add x4=x4+x5 (new len) (COPY_DONE)
            //   18:str x4=[x7]
            //   19:strb wzr=[dest, x5] (NUL-term)
            //   20:push x7 (return sb)
            s = s + arm64_pop(6)
            s = s + arm64_pop(7)
            s = s + arm64_ldr_imm(4, 7, 0)
            s = s + arm64_add_imm(8, 7, 8)
            s = s + arm64_add_xxx(8, 8, 4)
            s = s + arm64_movz_x_imm(5, 0)
            s = s + arm64_ldrb_reg(9, 6, 5)         // STRLEN
            s = s + arm64_cbz(9, 3)
            s = s + arm64_add_imm(5, 5, 1)
            s = s + arm64_b(0 - 3)
            s = s + arm64_movz_x_imm(9, 0)          // DONE_STRLEN: j = 0
            s = s + arm64_cmp_xx(9, 5)              // COPY
            s = s + arm64_b_cond(0xa, 5)            // b.ge COPY_DONE
            s = s + arm64_ldrb_reg(10, 6, 9)
            s = s + arm64_strb_reg(10, 8, 9)
            s = s + arm64_add_imm(9, 9, 1)
            s = s + arm64_b(0 - 5)
            s = s + arm64_add_xxx(4, 4, 5)          // COPY_DONE
            s = s + arm64_str_imm(4, 7, 0)
            s = s + arm64_strb_reg(31, 8, 5)
            s = s + arm64_push(7)
            instrIdx = instrIdx + 21
        } else if opTok == "BUILTIN_SBTOSTRING" {
            // sbToString(sb): return ptr to data (= sb + 8). Data is already NUL-terminated.
            s = s + arm64_pop(7)
            s = s + arm64_add_imm(0, 7, 8)
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 3
        } else if opTok == "BUILTIN_CONTAINS" {
            // contains(s, sub): same logic as indexOf but returns bool (1 / 0).
            // 23 instructions. Stack TOS = sub, then s.
            // Layout: indexOf core (instrs 0..19) computes idx in x0 (or -1).
            // Then cmp x0, #0; cset x0, ge; push x0.
            //
            // The core exactly mirrors INDEXOF's emit BUT we drop the final push
            // and replace mov_xx (FOUND case) and movn (NOT_FOUND) with x0
            // setting = idx or -1 — then the final cmp/cset converts to bool.
            //   0:pop sub  1:pop s  2:movz x5
            //   3:ldrb s[i]  4:cbz→NOT_FOUND(+15)  5:movz j
            //   6:ldrb sub[j]  7:cbz→FOUND(+10)  8:add x10  9:ldrb s[i+j]  10:cbz→NOT_FOUND(+9)
            //   11:cmp  12:b.ne→NEXT_OUTER(+3)  13:add j++  14:b INNER(-8)
            //   15:add i++ (NEXT_OUTER)  16:b OUTER(-13)
            //   17:mov x0,x5 (FOUND)  18:b CONV(+2)
            //   19:movn x0 (NOT_FOUND)
            //   20 (CONV): cmp x0, #0  21:cset x0, ge  22:push x0
            s = s + arm64_pop(6)
            s = s + arm64_pop(7)
            s = s + arm64_movz_x_imm(5, 0)
            s = s + arm64_ldrb_reg(8, 7, 5)
            s = s + arm64_cbz(8, 15)
            s = s + arm64_movz_x_imm(4, 0)
            s = s + arm64_ldrb_reg(9, 6, 4)
            s = s + arm64_cbz(9, 10)
            s = s + arm64_add_xxx(10, 5, 4)
            s = s + arm64_ldrb_reg(11, 7, 10)
            s = s + arm64_cbz(11, 9)
            s = s + arm64_cmp_xx(9, 11)
            s = s + arm64_b_cond(0x1, 3)
            s = s + arm64_add_imm(4, 4, 1)
            s = s + arm64_b(0 - 8)
            s = s + arm64_add_imm(5, 5, 1)
            s = s + arm64_b(0 - 13)
            s = s + arm64_mov_xx(0, 5)
            s = s + arm64_b(2)
            s = s + arm64_movn_x_imm(0, 0)
            s = s + arm64_cmp_imm(0, 0)
            s = s + arm64_cset(0, 0xa)              // x0 = (x0 >= 0) ? 1 : 0
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 23
        } else if opTok == "BUILTIN_PRINT" {
            // print(s): write(1, s, strlen(s)) via raw syscall #4.
            //   0:pop x3=s  1:mov x1=x3
            //   2:ldrb w4=[x1] post-inc  3:cbnz→back(-1)
            //   4:sub x2=x1-x3  5:sub x2-=1  (now x2 = strlen)
            //   6:movz x0=1 (stdout)  7:mov x1=x3 (ptr again)
            //   8:movz x16=4 (write)  9:svc 0x80
            //   10:movz x0=0 (return)  11:push x0
            s = s + arm64_pop(3)
            s = s + arm64_mov_xx(1, 3)
            s = s + arm64_ldrb_post(4, 1, 1)
            s = s + arm64_cbnz(4, 0 - 1)
            s = s + arm64_sub_xxx(2, 1, 3)
            s = s + arm64_sub_imm(2, 2, 1)
            s = s + arm64_movz_x_imm(0, 1)
            s = s + arm64_mov_xx(1, 3)
            s = s + arm64_movz_x_imm(16, 4)
            s = s + arm64_svc(0x80)
            s = s + arm64_movz_w_imm(0, 0)
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 12
        } else if opTok == "BUILTIN_POW" {
            // pow(b, e): result = b^e (signed int). 8 instructions. TOS = e.
            //   0:pop x4=e  1:pop x5=b  2:movz x0=1
            //   3:cbz x4→DONE(+4)  4:mul x0,x0,x5  5:sub x4,x4,#1  6:b LOOP(-3)
            //   7:push x0
            s = s + arm64_pop(4)
            s = s + arm64_pop(5)
            s = s + arm64_movz_x_imm(0, 1)
            s = s + arm64_cbz(4, 4)
            s = s + arm64_mul_xxx(0, 0, 5)
            s = s + arm64_sub_imm(4, 4, 1)
            s = s + arm64_b(0 - 3)
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 8
        } else if opTok == "BUILTIN_ENDSWITH" {
            // endsWith(s, suffix): 29 instructions. TOS = suffix.
            // strlen both, check if len_p > len_s (→ 0), else compare last len_p bytes.
            //   0:pop x6=suffix  1:pop x7=s
            //   2:mov x8=x6  3:ldrb post (PLOOP)  4:cbnz back(-1)
            //   5:sub x4=x8-x6  6:sub x4,#1   ; len_p in x4
            //   7:mov x8=x7  8:ldrb post (SLOOP)  9:cbnz back(-1)
            //   10:sub x5=x8-x7  11:sub x5,#1  ; len_s in x5
            //   12:cmp x4, x5  13:b.gt FAIL(+14)
            //   14:sub x10=x5-x4  ; start
            //   15:movz x9=0  ; i
            //   16:cmp x9, x4 (CLOOP)  17:b.ge SUCCESS(+8)
            //   18:add x11=x10+x9  19:ldrb w12=s[x11]  20:ldrb w13=suffix[x9]  21:cmp x12,x13  22:b.ne FAIL(+5)
            //   23:add x9,#1  24:b CLOOP(-8)
            //   25:movz x0=1 (SUCCESS)  26:b END(+2)
            //   27:movz x0=0 (FAIL)
            //   28:push (END)
            s = s + arm64_pop(6)
            s = s + arm64_pop(7)
            s = s + arm64_mov_xx(8, 6)
            s = s + arm64_ldrb_post(9, 8, 1)
            s = s + arm64_cbnz(9, 0 - 1)
            s = s + arm64_sub_xxx(4, 8, 6)
            s = s + arm64_sub_imm(4, 4, 1)
            s = s + arm64_mov_xx(8, 7)
            s = s + arm64_ldrb_post(9, 8, 1)
            s = s + arm64_cbnz(9, 0 - 1)
            s = s + arm64_sub_xxx(5, 8, 7)
            s = s + arm64_sub_imm(5, 5, 1)
            s = s + arm64_cmp_xx(4, 5)
            s = s + arm64_b_cond(0xc, 14)
            s = s + arm64_sub_xxx(10, 5, 4)
            s = s + arm64_movz_x_imm(9, 0)
            s = s + arm64_cmp_xx(9, 4)              // CLOOP
            s = s + arm64_b_cond(0xa, 8)
            s = s + arm64_add_xxx(11, 10, 9)
            s = s + arm64_ldrb_reg(12, 7, 11)
            s = s + arm64_ldrb_reg(13, 6, 9)
            s = s + arm64_cmp_xx(12, 13)
            s = s + arm64_b_cond(0x1, 5)            // b.ne FAIL
            s = s + arm64_add_imm(9, 9, 1)
            s = s + arm64_b(0 - 8)
            s = s + arm64_movz_x_imm(0, 1)          // SUCCESS
            s = s + arm64_b(2)
            s = s + arm64_movz_x_imm(0, 0)          // FAIL
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 29
        } else if opTok == "BUILTIN_ARG" {
            // arg(s): s is a STRING like "0" — Krypton's all-string runtime convention.
            // Inline-toInt the string, then load argv[idx+1] from saved argv.
            // 21 instructions. Layout (0-indexed):
            //   0:pop x4=ptr  1:movz x6=0  2:movz x5=0  3:movz x10=10
            //   4:ldrb w7 (LOOP)  5:cbz→DONE(+10)  6:cmp48  7:b.lt→DONE(+8)
            //   8:cmp57  9:b.gt→DONE(+6)  10:sub x7,#48  11:mul x6=x6*10  12:add x6+=x7
            //   13:add x5++  14:b LOOP(-10)
            //   15 (DONE): adrp x9  16:add x9 +off
            //   17:ldr x9,[x9,#16] (argv)
            //   18:add x6,x6,#1 (idx+1)
            //   19:ldr x0,[x9, x6 LSL #3]  20:push
            s = s + arm64_pop(4)
            s = s + arm64_movz_x_imm(6, 0)
            s = s + arm64_movz_x_imm(5, 0)
            s = s + arm64_movz_x_imm(10, 10)
            s = s + arm64_ldrb_reg(7, 4, 5)
            s = s + arm64_cbz(7, 10)
            s = s + arm64_cmp_imm(7, 48)
            s = s + arm64_b_cond(0xb, 8)
            s = s + arm64_cmp_imm(7, 57)
            s = s + arm64_b_cond(0xc, 6)
            s = s + arm64_sub_imm(7, 7, 48)
            s = s + arm64_mul_xxx(6, 6, 10)
            s = s + arm64_add_xxx(6, 6, 7)
            s = s + arm64_add_imm(5, 5, 1)
            s = s + arm64_b(0 - 10)
            // DONE — load argv from save cell
            let bumpVaddr = g_DATA_VADDR + 0x4000
            let pcAtAdrp = textVaddr + textOff + (instrIdx + 15) * 4
            let pcPage = pcAtAdrp / 4096 * 4096
            let bumpPage = bumpVaddr / 4096 * 4096
            let imm21 = (bumpPage - pcPage) / 4096
            s = s + arm64_adrp(9, imm21)
            s = s + arm64_add_imm(9, 9, bumpVaddr % 4096)
            s = s + arm64_ldr_imm(9, 9, 2)            // ldr x9, [x9, #16] (argv)
            s = s + arm64_add_imm(6, 6, 1)            // idx + 1 (skip program name)
            s = s + arm64_ldr_reg_lsl3(0, 9, 6)       // x0 = argv[idx+1]
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 21
        } else if opTok == "BUILTIN_ARGCOUNT" {
            // argCount(): return argc - 1 (excluding program name). 5 instr.
            let bumpVaddr = g_DATA_VADDR + 0x4000
            let pcAtAdrp = textVaddr + textOff + instrIdx * 4
            let pcPage = pcAtAdrp / 4096 * 4096
            let bumpPage = bumpVaddr / 4096 * 4096
            let imm21 = (bumpPage - pcPage) / 4096
            s = s + arm64_adrp(5, imm21)
            s = s + arm64_add_imm(5, 5, bumpVaddr % 4096)
            s = s + arm64_ldr_imm(0, 5, 1)            // ldr x0, [x5, #8] (argc)
            s = s + arm64_sub_imm(0, 0, 1)            // -1 for program name
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 5
        } else if opTok == "BUILTIN_READFILE" {
            // readFile(path): open, alloc 1 MB buf, read, close, NUL-terminate, return.
            // 27 instructions. macOS arm64 syscalls: open=5, read=3, close=6.
            // Uses x19 (saved fd), x20 (saved buf ptr), x21 (saved bytes_read).
            s = s + arm64_pop(10)                       // x10 = path
            s = s + arm64_mov_xx(0, 10)
            s = s + arm64_movz_x_imm(1, 0)              // O_RDONLY
            s = s + arm64_movz_x_imm(16, 5)             // sys_open
            s = s + arm64_svc(0x80)
            s = s + arm64_mov_xx(19, 0)                 // save fd
            s = s + arm64_movz_x_imm_lsl16(4, 16)       // x4 = 16 << 16 = 1 MB
            instrIdx = instrIdx + 7
            s = s + emitAllocVar(instrIdx, textVaddr, textOff)
            instrIdx = instrIdx + 15
            s = s + arm64_mov_xx(20, 0)                 // save buf
            s = s + arm64_mov_xx(0, 19)                 // fd
            s = s + arm64_mov_xx(1, 20)                 // buf
            s = s + arm64_mov_xx(2, 4)                  // size
            s = s + arm64_movz_x_imm(16, 3)             // sys_read
            s = s + arm64_svc(0x80)
            s = s + arm64_mov_xx(21, 0)                 // save bytes_read
            s = s + arm64_mov_xx(0, 19)
            s = s + arm64_movz_x_imm(16, 6)             // sys_close
            s = s + arm64_svc(0x80)
            s = s + arm64_strb_reg(31, 20, 21)          // strb wzr, [buf, bytes_read]  (NUL)
            s = s + arm64_mov_xx(0, 20)                 // return buf
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 13
        } else if opTok == "BUILTIN_TRIM" {
            // trim(s): strip leading/trailing spaces (just ' ' for now). 42 instr.
            // Layout (0-indexed within this op):
            //   0:pop x6=s  1:movz x12=0
            //   2:ldrb w7 (LOOP1)  3:cbz→ALL_WS(+19)  4:cmp w7,#32  5:b.ne LOOP1_DONE(+3)
            //   6:add x12++  7:b LOOP1(-5)
            //   8 (LOOP1_DONE): mov x8=x6
            //   9:ldrb post w7,[x8],#1 (STRLEN)  10:cbnz back(-1)
            //   11:sub x5=x8-x6  12:sub x5,#1
            //   13 (LOOP2): sub x9=x5-1  14:ldrb w7,[x6,x9]
            //   15:cmp w7,#32  16:b.ne LOOP2_DONE(+4)
            //   17:sub x5,#1  18:cmp x5,x12  19:b.gt LOOP2(-6)
            //   20 (LOOP2_DONE): sub x10=x5-x12  21:b ALLOC(+2)
            //   22 (ALL_WS): movz x10=0  23:movz x12=0
            //   24 (ALLOC): add x4=x10+1
            //   25..31: emitAllocVar (7)
            //   32:add x9=x6+x12 (src)  33:movz x11=0 (i)
            //   34 (LOOP3): cmp x11,x10  35:b.ge LOOP3_DONE(+5)
            //   36:ldrb w13=[x9,x11]  37:strb w13=[x0,x11]  38:add x11++  39:b LOOP3(-5)
            //   40 (LOOP3_DONE): strb wzr=[x0,x10]  41:push
            s = s + arm64_pop(6)
            s = s + arm64_movz_x_imm(12, 0)
            s = s + arm64_ldrb_reg(7, 6, 12)
            s = s + arm64_cbz(7, 19)
            s = s + arm64_cmp_imm(7, 32)
            s = s + arm64_b_cond(0x1, 3)            // b.ne
            s = s + arm64_add_imm(12, 12, 1)
            s = s + arm64_b(0 - 5)
            s = s + arm64_mov_xx(8, 6)
            s = s + arm64_ldrb_post(7, 8, 1)
            s = s + arm64_cbnz(7, 0 - 1)
            s = s + arm64_sub_xxx(5, 8, 6)
            s = s + arm64_sub_imm(5, 5, 1)
            s = s + arm64_sub_imm(9, 5, 1)          // LOOP2
            s = s + arm64_ldrb_reg(7, 6, 9)
            s = s + arm64_cmp_imm(7, 32)
            s = s + arm64_b_cond(0x1, 4)            // b.ne LOOP2_DONE (+4)
            s = s + arm64_sub_imm(5, 5, 1)
            s = s + arm64_cmp_xx(5, 12)
            s = s + arm64_b_cond(0xc, 0 - 6)        // b.gt LOOP2
            s = s + arm64_sub_xxx(10, 5, 12)        // LOOP2_DONE
            s = s + arm64_b(3)                      // skip ALL_WS branch (3 instrs ahead to ALLOC)
            s = s + arm64_movz_x_imm(10, 0)         // ALL_WS
            s = s + arm64_movz_x_imm(12, 0)
            s = s + arm64_add_imm(4, 10, 1)         // ALLOC
            instrIdx = instrIdx + 25
            s = s + emitAllocVar(instrIdx, textVaddr, textOff)
            instrIdx = instrIdx + 15
            s = s + arm64_add_xxx(9, 6, 12)
            s = s + arm64_movz_x_imm(11, 0)
            s = s + arm64_cmp_xx(11, 10)            // LOOP3
            s = s + arm64_b_cond(0xa, 5)            // b.ge LOOP3_DONE (+5)
            s = s + arm64_ldrb_reg(13, 9, 11)
            s = s + arm64_strb_reg(13, 0, 11)
            s = s + arm64_add_imm(11, 11, 1)
            s = s + arm64_b(0 - 5)
            s = s + arm64_strb_reg(31, 0, 10)
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 10
        } else if opTok == "BUILTIN_GCALLOCATED" {
            // Read alloc_total at bump_cell + 24, push as int. 4 instructions.
            let bumpVaddr = g_DATA_VADDR + 0x4000
            let pcAtAdrp = textVaddr + textOff + instrIdx * 4
            let pcPage = pcAtAdrp / 4096 * 4096
            let bumpPage = bumpVaddr / 4096 * 4096
            let imm21 = (bumpPage - pcPage) / 4096
            s = s + arm64_adrp(1, imm21)
            s = s + arm64_add_imm(1, 1, bumpVaddr % 4096)
            s = s + arm64_ldr_imm(0, 1, 3)            // ldr x0, [x1, #24] (alloc_total)
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 4
        } else if opTok == "BUILTIN_GCLIMIT" {
            // Read alloc_limit at bump_cell + 32, push as int. 4 instructions.
            let bumpVaddr = g_DATA_VADDR + 0x4000
            let pcAtAdrp = textVaddr + textOff + instrIdx * 4
            let pcPage = pcAtAdrp / 4096 * 4096
            let bumpPage = bumpVaddr / 4096 * 4096
            let imm21 = (bumpPage - pcPage) / 4096
            s = s + arm64_adrp(1, imm21)
            s = s + arm64_add_imm(1, 1, bumpVaddr % 4096)
            s = s + arm64_ldr_imm(0, 1, 4)            // ldr x0, [x1, #32] (alloc_limit)
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 4
        } else if opTok == "BUILTIN_GCSETLIMIT" {
            // Pop value, store at alloc_limit, push back. 5 instructions.
            s = s + arm64_pop_x0()
            instrIdx = instrIdx + 1
            let bumpVaddr = g_DATA_VADDR + 0x4000
            let pcAtAdrp = textVaddr + textOff + instrIdx * 4
            let pcPage = pcAtAdrp / 4096 * 4096
            let bumpPage = bumpVaddr / 4096 * 4096
            let imm21 = (bumpPage - pcPage) / 4096
            s = s + arm64_adrp(1, imm21)
            s = s + arm64_add_imm(1, 1, bumpVaddr % 4096)
            s = s + arm64_str_imm(0, 1, 4)            // str x0, [x1, #32] (alloc_limit = arg)
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 4
        } else if opTok == "BUILTIN_GCRESET" {
            // Zero bump_cell + alloc_total; push 0. 6 instructions.
            let bumpVaddr = g_DATA_VADDR + 0x4000
            let pcAtAdrp = textVaddr + textOff + instrIdx * 4
            let pcPage = pcAtAdrp / 4096 * 4096
            let bumpPage = bumpVaddr / 4096 * 4096
            let imm21 = (bumpPage - pcPage) / 4096
            s = s + arm64_adrp(1, imm21)
            s = s + arm64_add_imm(1, 1, bumpVaddr % 4096)
            s = s + arm64_str_imm(31, 1, 0)           // str xzr, [x1] (bump_cell = 0)
            s = s + arm64_str_imm(31, 1, 3)           // str xzr, [x1, #24] (alloc_total = 0)
            s = s + arm64_movz_x_imm(0, 0)
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 6
        } else if opTok == "BUILTIN_GCCOLLECT" {
            // No-op stub. Push 0. 2 instructions.
            s = s + arm64_movz_x_imm(0, 0)
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 2
        } else if opTok == "BUILTIN_WRITEFILE" {
            // writeFile(path, content): open(path, O_WRONLY|O_CREAT|O_TRUNC, 0644),
            // strlen(content), write, close, return 0. 22 instructions.
            // O_WRONLY=1, O_CREAT=0x200, O_TRUNC=0x400 → flags = 0x601.
            s = s + arm64_pop(10)                       // content
            s = s + arm64_pop(11)                       // path
            s = s + arm64_mov_xx(0, 11)
            s = s + arm64_movz_x_imm(1, 0x601)
            s = s + arm64_movz_x_imm(2, 0x1a4)          // mode 0644
            s = s + arm64_movz_x_imm(16, 5)             // sys_open
            s = s + arm64_svc(0x80)
            s = s + arm64_mov_xx(19, 0)                 // save fd
            s = s + arm64_mov_xx(4, 10)                 // x4 = walk ptr
            s = s + arm64_ldrb_post(5, 4, 1)            // STRLEN_LOOP
            s = s + arm64_cbnz(5, 0 - 1)
            s = s + arm64_sub_xxx(2, 4, 10)             // len+1
            s = s + arm64_sub_imm(2, 2, 1)              // len
            s = s + arm64_mov_xx(0, 19)                 // fd
            s = s + arm64_mov_xx(1, 10)                 // content
            s = s + arm64_movz_x_imm(16, 4)             // sys_write
            s = s + arm64_svc(0x80)
            s = s + arm64_mov_xx(0, 19)
            s = s + arm64_movz_x_imm(16, 6)             // sys_close
            s = s + arm64_svc(0x80)
            s = s + arm64_movz_x_imm(0, 0)              // return 0
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 22
        } else if opTok == "BUILTIN_PRINTERR" {
            // printErr(s): write(2, s, strlen(s)) — same as print but fd=2 (stderr).
            s = s + arm64_pop(3)
            s = s + arm64_mov_xx(1, 3)
            s = s + arm64_ldrb_post(4, 1, 1)
            s = s + arm64_cbnz(4, 0 - 1)
            s = s + arm64_sub_xxx(2, 1, 3)
            s = s + arm64_sub_imm(2, 2, 1)
            s = s + arm64_movz_x_imm(0, 2)          // fd = stderr
            s = s + arm64_mov_xx(1, 3)
            s = s + arm64_movz_x_imm(16, 4)
            s = s + arm64_svc(0x80)
            s = s + arm64_movz_w_imm(0, 0)
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 12
        } else if opTok == "BUILTIN_INDEXOF" {
            // indexOf(s, sub): 21 instructions. Stack TOS = sub, then s.
            // Layout (0-indexed within this op):
            //   0:pop sub  1:pop s  2:movz x5
            //   3:ldrb s[i]  4:cbz→NOT_FOUND(+15)  5:movz x4=0
            //   6:ldrb sub[j]  7:cbz→FOUND(+10)  8:add x10=i+j  9:ldrb s[i+j]  10:cbz→NOT_FOUND(+9)
            //   11:cmp  12:b.ne→NEXT_OUTER(+3)  13:add j++  14:b INNER(-8)
            //   15:add i++ (NEXT_OUTER)  16:b OUTER(-13)
            //   17:mov x0,x5 (FOUND)  18:b END(+2)
            //   19:movn x0 (NOT_FOUND)
            //   20:push (END)
            s = s + arm64_pop(6)
            s = s + arm64_pop(7)
            s = s + arm64_movz_x_imm(5, 0)
            s = s + arm64_ldrb_reg(8, 7, 5)
            s = s + arm64_cbz(8, 15)
            s = s + arm64_movz_x_imm(4, 0)
            s = s + arm64_ldrb_reg(9, 6, 4)
            s = s + arm64_cbz(9, 10)
            s = s + arm64_add_xxx(10, 5, 4)
            s = s + arm64_ldrb_reg(11, 7, 10)
            s = s + arm64_cbz(11, 9)
            s = s + arm64_cmp_xx(9, 11)
            s = s + arm64_b_cond(0x1, 3)
            s = s + arm64_add_imm(4, 4, 1)
            s = s + arm64_b(0 - 8)
            s = s + arm64_add_imm(5, 5, 1)
            s = s + arm64_b(0 - 13)
            s = s + arm64_mov_xx(0, 5)
            s = s + arm64_b(2)
            s = s + arm64_movn_x_imm(0, 0)
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 21
        } else if opTok == "LOAD_SLOT" {
            let slot = toInt(restTok)
            let off = 0 - (8 + slot * 8)
            s = s + arm64_ldur(0, 29, off)
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 2
        } else if opTok == "STORE_SLOT" {
            let slot = toInt(restTok)
            let off = 0 - (8 + slot * 8)
            s = s + arm64_pop_x0()
            s = s + arm64_stur(0, 29, off)
            instrIdx = instrIdx + 2
        } else if opTok == "BUILTIN_KP" {
            // kp(s): write(1,s,strlen(s)) + write(1,"\n",1) via raw syscalls.
            // Direct write() bypasses libc stdio buffering — kp output survives
            // explicit exit() (which svc's _exit and skips libc fini handlers).
            s = s + arm64_pop(3)                      // x3 = str
            s = s + arm64_mov_xx(1, 3)                // x1 = scan ptr
            s = s + arm64_ldrb_post(4, 1, 1)          // ldrb w4, [x1], #1
            s = s + arm64_cbnz(4, 0 - 1)              // loop until NUL
            s = s + arm64_sub_xxx(2, 1, 3)            // x2 = len incl NUL
            s = s + arm64_sub_imm(2, 2, 1)            // x2 = real len
            s = s + arm64_movz_x_imm(0, 1)            // x0 = stdout
            s = s + arm64_mov_xx(1, 3)                // x1 = str ptr
            s = s + arm64_movz_x_imm(16, 4)           // x16 = SYS_write
            s = s + arm64_svc(0x80)                   // write(1, str, len)
            s = s + arm64_movz_w_imm(4, 0x0A)         // w4 = '\n'
            s = s + arm64_sub_imm(31, 31, 16)         // sub sp, sp, #16
            s = s + arm64_strb_imm(4, 31, 0)          // strb w4, [sp]
            s = s + arm64_add_imm(1, 31, 0)           // x1 = sp (mov from SP must use ADD form)
            s = s + arm64_movz_x_imm(2, 1)            // x2 = 1 byte
            s = s + arm64_movz_x_imm(0, 1)            // x0 = stdout
            s = s + arm64_movz_x_imm(16, 4)           // x16 = SYS_write
            s = s + arm64_svc(0x80)                   // write(1, "\n", 1)
            s = s + arm64_add_imm(31, 31, 16)         // restore sp
            s = s + arm64_movz_w_imm(0, 0)            // kp returns 0
            s = s + arm64_push_x0()
            instrIdx = instrIdx + 21
        } else if opTok == "CALL_FUNC" {
            // restTok = "<name> <argc>"
            let s2 = 0
            while s2 < len(restTok) && restTok[s2] != " " { s2 += 1 }
            let cname = substring(restTok, 0, s2)
            let argc = 0
            if s2 < len(restTok) { argc = toInt(trim(substring(restTok, s2 + 1, len(restTok)))) }
            // Pop args in reverse: x(argc-1) first (TOS), down to x0 (deepest)
            let ai = argc - 1
            while ai >= 0 {
                s = s + arm64_pop(ai)
                instrIdx = instrIdx + 1
                ai = ai - 1
            }
            // bl <target>
            let targetInstr = findLabel(funcTable, cname)
            let delta = targetInstr - instrIdx
            s = s + arm64_bl(delta)
            instrIdx = instrIdx + 1
            s = s + arm64_push(0)
            instrIdx = instrIdx + 1
        } else if opTok == "RETURN" {
            s = s + arm64_pop_x0()
            instrIdx = instrIdx + 1
            if frame > 0 {
                s = s + arm64_add_sp(frame)
                instrIdx = instrIdx + 1
            }
            s = s + arm64_ldp_fp_lr_post16()
            s = s + arm64_ret()
            instrIdx = instrIdx + 2
        } else if opTok == "POP" {
            s = s + arm64_pop_x0()
            instrIdx = instrIdx + 1
        } else if opTok == "END" {
            if frame > 0 {
                s = s + arm64_add_sp(frame)
                instrIdx = instrIdx + 1
            }
            s = s + arm64_movz_w0_zero()
            s = s + arm64_ldp_fp_lr_post16()
            s = s + arm64_ret()
            instrIdx = instrIdx + 3
        }
        oi += 1
    }
    emit s
}

// Top-level emitter: walk all functions in emission order (__main__ first)
// and concatenate.
func emitTextFromIR(parsed, strOffsets) {
    let order = emitOrder(parsed)
    let nF = funcCount(parsed)
    let funcTable = buildFunctionTable(parsed)
    let s = ""
    let oi = 0
    while oi < nF {
        let fIdx = toInt(getLine(order, oi))
        let funcStartInstr = findLabel(funcTable, funcName(parsed, fIdx))
        s = s + emitOneFunction(parsed, fIdx, funcStartInstr, funcTable, strOffsets)
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
    // starts_in_image — 24 B (seg_count + 5 × uint32 seg_info_offset)
    s = s + hexDword(5)              // seg_count (PAGEZERO/TEXT/DATA_CONST/DATA/LINKEDIT)
    s = s + hexDword(0)              // [0] __PAGEZERO
    s = s + hexDword(0)              // [1] __TEXT
    s = s + hexDword(24)             // [2] __DATA_CONST → starts_in_segment at offset 24
    s = s + hexDword(0)              // [3] __DATA      (heap; no chained pointers)
    s = s + hexDword(0)              // [4] __LINKEDIT
    // starts_in_segment for __DATA_CONST — 24 B (header 8 + segoff 8 + maxptr 4 + page_count+page_start 4)
    s = s + hexDword(24)             // size
    s = s + hexWord(0x4000)          // page_size = 16 KB
    s = s + hexWord(6)               // pointer_format = DYLD_CHAINED_PTR_64_OFFSET
    s = s + hexQword(g_DATA_CONST_FILE_OFF)  // segment_offset (image-base-relative; matches __DATA_CONST file offset)
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
    s = s + hexQword2(TEXT_VADDR() + g_ENTRY_OFF, 1) // _main vaddr (entry point)
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
    s = s + hexQword(g_TEXT_VMSIZE)                 // vmsize = TEXT_VMSIZE
    s = s + hexQword(0)                             // fileoff
    s = s + hexQword(g_TEXT_VMSIZE)                 // filesize = same
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
    s = s + hexQword2(g_TEXT_VMSIZE, 1)             // vmaddr = TEXT_VADDR + TEXT_VMSIZE
    s = s + hexQword(0x4000)                        // vmsize (one page)
    s = s + hexQword(g_DATA_CONST_FILE_OFF)         // fileoff
    s = s + hexQword(0x4000)                        // filesize
    s = s + hexDword(3)                             // maxprot = R+W
    s = s + hexDword(3)                             // initprot = R+W
    s = s + hexDword(1)                             // nsects
    s = s + hexDword(0x10)                          // SG_READ_ONLY
    // Section 1: __got
    s = s + hexStr("__got") + hexPad(11)
    s = s + hexStr("__DATA_CONST") + hexPad(4)
    s = s + hexQword2(g_TEXT_VMSIZE, 1)             // addr = same as segment vmaddr
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

// LC_SEGMENT_64 __DATA (1 section: __bump for the heap bump pointer + heap)
//   File backs the first 16 KB; 64 KB virtual is zero-fill.
//   First 8 bytes of __DATA = the bump pointer cell (initial value =
//   DATA_VADDR + 8, i.e. the first allocatable byte).
// cmdsize = 72 + 80 = 152
func emitLcSegData() {
    let s = ""
    s = s + hexDword(LC_SEGMENT_64()) + hexDword(152)
    s = s + hexStr("__DATA") + hexPad(10)
    s = s + hexQword2(g_TEXT_VMSIZE + 0x4000, 1)    // vmaddr = TEXT_VADDR + TEXT_VMSIZE + 16 KB
    s = s + hexQword(DATA_VMSIZE())
    s = s + hexQword(DATA_FILE_OFF())
    s = s + hexQword(DATA_FILESIZE())
    s = s + hexDword(3)                             // maxprot = R+W
    s = s + hexDword(3)                             // initprot = R+W
    s = s + hexDword(1)                             // nsects
    s = s + hexDword(0)                             // flags
    // Section: __bump  (size matches filesize; vmsize beyond that is kernel zero-fill)
    s = s + hexStr("__bump") + hexPad(10)
    s = s + hexStr("__DATA") + hexPad(10)
    s = s + hexQword2(g_TEXT_VMSIZE + 0x4000, 1)    // addr = same as segment vmaddr
    s = s + hexQword(DATA_FILESIZE())               // size = filesize
    s = s + hexDword(DATA_FILE_OFF())               // file offset
    s = s + hexDword(3)                             // align 2^3 = 8
    s = s + hexDword(0)                             // reloff
    s = s + hexDword(0)                             // nreloc
    s = s + hexDword(0)                             // flags = S_REGULAR (kernel zero-fills vmsize > filesize at segment level)
    s = s + hexDword(0)
    s = s + hexDword(0)
    s = s + hexDword(0)
    emit s
}

// LC_SEGMENT_64 __LINKEDIT (no sections, 72 B)
func emitLcSegLinkedit() {
    let s = ""
    s = s + hexDword(LC_SEGMENT_64()) + hexDword(72)
    s = s + hexStr("__LINKEDIT") + hexPad(6)
    s = s + hexQword2(g_TEXT_VMSIZE + 0x4000 + 0x10000, 1) // vmaddr = DATA + DATA_VMSIZE
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
    s = s + hexQword(g_ENTRY_OFF)                   // entryoff (vaddr of _main)
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
        printErr("usage: kcc compiler/macos_arm64/macho_arm64_self.k <output_path>")
        printErr("       kcc compiler/macos_arm64/macho_arm64_self.k --ir <input.kir> <output_path>")
        printErr("       kcc compiler/macos_arm64/macho_arm64_self.k --sha256-test")
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
        irOps = parseFullIR(ir)
        g_funcStartCache = buildFuncStartCache(irOps)
        irStrOffsets = computeStringOffsets(irOps)
        g_TEXT_SIZE = computeTextSize(irOps)
        g_CSTRING_SIZE = computeCStringSize(irOps)
        // Now that text/cstring sizes are known, compute the dynamic layout
        // (g_TEXT_VMSIZE rounds up to 16 KB pages; downstream offsets follow).
        computeLayout()
        // Locate __main__ in the function table so LC_MAIN entryoff and the
        // _main symtab entry point at the right function (not blindly TEXT_OFF).
        let fTable = buildFunctionTable(irOps)
        let mainInstr = findLabel(fTable, "__main__")
        if mainInstr < 0 {
            printErr("macho_arm64_self: no __main__ function found in IR")
            exit("1")
        }
        g_ENTRY_OFF = TEXT_OFF() + mainInstr * 4
        useIr = "1"
    }

    // Always run computeLayout (default mode picks up the static defaults; IR
    // mode overrides g_TEXT_SIZE/g_CSTRING_SIZE first). Idempotent for default values.
    computeLayout()

    if arg0 == "--debug-parse" {
        let inFile = arg("1")
        let ir = readFile(inFile)
        let parsed = parseFullIR(ir)
        printErr("=== parsed ===")
        printErr(parsed)
        printErr("=== end ===")
        exit("0")
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

    // Build all 13 load commands (added __DATA segment for the heap)
    let lcs = ""
    lcs = lcs + emitLcPagezero()
    lcs = lcs + emitLcSegText()
    lcs = lcs + emitLcSegDataConst()
    lcs = lcs + emitLcSegData()
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
    let header = emitHeader(13, sizeofcmds)

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
    let postCstringPad = DATA_CONST_FILE_OFF() - textSegEnd

    // __DATA_CONST: __got slot + zero pad to __DATA page boundary (0x8000)
    let gotData = emitGotSlot()
    let postGotPad = DATA_FILE_OFF() - DATA_CONST_FILE_OFF() - GOT_SIZE()

    // __DATA file backing — 16 KB of zeros (no useful initial data; the bump
    // cell lives in the zero-fill region past filesize, where pages are
    // anonymous-mapped and actually writable on code-signed binaries).
    let dataInit = ""
    let postDataPad = LINKEDIT_FILE_OFF() - DATA_FILE_OFF()

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
    body = body + dataInit + hexPad(postDataPad)
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
