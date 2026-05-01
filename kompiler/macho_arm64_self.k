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

func TEXT_OFF()           { emit 0x460 }        // file offset of __text
func TEXT_SIZE()          { emit 32 }           // 8 arm64 instructions
func STUBS_OFF()          { emit 0x480 }
func STUBS_SIZE()         { emit 12 }           // 1 stub × 12 bytes
func CSTRING_OFF()        { emit 0x48c }
func CSTRING_SIZE()       { emit 3 }            // "Hi\0"
func GOT_OFF()            { emit 0x4000 }
func GOT_SIZE()           { emit 8 }

func CHAINED_FIXUPS_OFF() { emit 0x8000 }
func CHAINED_FIXUPS_SIZE() { emit 96 }
func SYMTAB_OFF()         { emit 0x8060 }
func NSYMS()              { emit 3 }
func SYMTAB_SIZE()        { emit 48 }           // 3 × 16
func INDIRECT_SYMTAB_OFF() { emit 0x8090 }
func NINDIRECTSYMS()      { emit 2 }
func INDIRECT_SYMTAB_SIZE() { emit 8 }
func STRTAB_OFF()         { emit 0x8098 }
func STRTAB_SIZE()        { emit 40 }           // padded to 8

func CODESIG_OFF()        { emit 0x80c0 }       // aligned to 16
func CODESIG_SIZE()       { emit 256 }          // placeholder; codesign will fill
func FILE_TOTAL_SIZE()    { emit 0x81c0 }       // CODESIG_OFF + CODESIG_SIZE

// strtab byte offsets for our 3 symbols (computed from layout below)
func STRX_MH()    { emit 2 }   // "__mh_execute_header"
func STRX_MAIN()  { emit 22 }  // "_main"
func STRX_PUTS()  { emit 28 }  // "_puts"

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

// ── code signature placeholder ──────────────────────────────────────────────
// codesign rejects all-zero placeholders. Emit a minimal but valid empty
// SuperBlob (12 B) so codesign recognizes the slot and will overwrite it.
// All Apple code-signing fields are BIG-ENDIAN (unlike the rest of Mach-O).
//   magic  = 0xfade0cc0 (CSMAGIC_EMBEDDED_SIGNATURE)
//   length = 12 (just the header)
//   count  = 0 (no blob indices)
// External `codesign -s - --force` then fills the rest of the 256 B slot.
func emitCodeSigPlaceholder() {
    let s = ""
    // magic 0xfade0cc0 in BE
    s = s + hexByte(0xfa) + hexByte(0xde) + hexByte(0x0c) + hexByte(0xc0)
    // length 12 in BE
    s = s + hexByte(0x00) + hexByte(0x00) + hexByte(0x00) + hexByte(0x0c)
    // count 0 in BE
    s = s + hexByte(0x00) + hexByte(0x00) + hexByte(0x00) + hexByte(0x00)
    s = s + hexPad(CODESIG_SIZE() - 12)
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

just run {
    let outFile = arg("0")
    if len(outFile) == 0 {
        printErr("usage: kcc kompiler/macho_arm64_self.k <output_path>")
        exit("1")
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

    let textCode = emitMainCode()
    let stubCode = emitStubCode()
    let cstrData = emitCString()

    // Pad after __cstring up to __DATA_CONST page boundary (file 0x4000)
    let textSegEnd = CSTRING_OFF() + CSTRING_SIZE()
    let postCstringPad = DATA_FILE_OFF() - textSegEnd

    // __DATA_CONST: __got slot + zero pad to LINKEDIT
    let gotData = emitGotSlot()
    let postGotPad = LINKEDIT_FILE_OFF() - DATA_FILE_OFF() - GOT_SIZE()

    // __LINKEDIT: chained fixups, symtab, indirect symtab, strtab, codesig
    let leChained = emitChainedFixups()
    let leSymtab = emitSymtab()
    let leIndirect = emitIndirectSymtab()
    let leStrtab = emitStrtab()
    // Pad strtab end to CODESIG_OFF (16-byte align)
    let strtabEnd = STRTAB_OFF() + STRTAB_SIZE()
    let preCodesigPad = CODESIG_OFF() - strtabEnd
    let leCodesig = emitCodeSigPlaceholder()

    let machoBytes = prefix + hexPad(preTextPad)
    machoBytes = machoBytes + textCode + stubCode + cstrData + hexPad(postCstringPad)
    machoBytes = machoBytes + gotData + hexPad(postGotPad)
    machoBytes = machoBytes + leChained + leSymtab + leIndirect + leStrtab
    machoBytes = machoBytes + hexPad(preCodesigPad) + leCodesig

    writeBytes(outFile, machoBytes)
    printErr("macho_arm64_self: wrote " + outFile + " (" + (hexBytesLen(machoBytes)) + " bytes)")
    printErr("  next: codesign -s - --force " + outFile)
}
