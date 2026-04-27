// macho.k — Krypton native Mach-O backend for macOS (x86_64 and ARM64).
//
// First milestone: emit a static hello-world Mach-O for either architecture.
// Once the format is verified on real hardware, we expand to full IR support
// the way elf.k did (parse .kir, emit user functions + runtime helpers).
//
// Architecture is selected via the `--arch` flag:
//   --arch x86_64   (Intel Macs natively, Apple Silicon via Rosetta 2)
//   --arch arm64    (Apple Silicon natively)
//
// Default: x86_64 (broadest compatibility).
//
// IMPORTANT — code signing:
//   Apple Silicon (macOS 11+) REQUIRES a code signature. Without it the OS
//   refuses to execute the binary, with no useful error in Finder. Intel
//   macOS is more forgiving but recent versions are tightening up too.
//
//   After generating the binary, ad-hoc sign it:
//
//     codesign -s - --force ./hello
//
//   The dash after `-s` means ad-hoc signing — no Apple Developer ID needed.
//   `codesign` ships with Xcode Command Line Tools.
//
// Layout produced (file offsets, x86_64):
//   [0..31]      mach_header_64                              (32 bytes)
//   [32..103]    LC_SEGMENT_64 __PAGEZERO  (no sections)     (72 bytes)
//   [104..255]   LC_SEGMENT_64 __TEXT      (1 section)       (152 bytes)
//   [256..279]   LC_BUILD_VERSION                            (24 bytes)
//   [280..463]   LC_UNIXTHREAD             (x86 thread state) (184 bytes)
//   [464..]      code + string data
//
// Layout for ARM64 is the same except LC_UNIXTHREAD is 288 bytes
// (ARM_THREAD_STATE64 has 33 fields = 272 bytes vs x86_64's 21 = 168), so
// code starts at offset 568 instead of 464.
//
// Calling convention per arch:
//
//   x86_64 (BSD class — syscall numbers OR'd with 0x2000000):
//     RAX = syscall number (e.g., 0x2000004 for write)
//     RDI/RSI/RDX/R10/R8/R9 = args
//     SYSCALL instruction
//     RAX = result, carry flag set on error
//
//   ARM64:
//     X16 = syscall number (just the number, e.g., 4 for write)
//     X0..X5 = args
//     SVC #0x80 instruction
//     X0 = result
//
// Syscall numbers (same for both archs, just different encoding):
//   write = 4    exit  = 1    read  = 3
//   open  = 5    close = 6    mmap  = 197

// ── Hex helpers (duplicated from elf.k — keep in sync) ─────────────────────

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

func hexQword(n) {
    emit hexDword(n) + hexDword(0)
}

func hexQword4G() { emit hexDword(0) + hexDword(1) }
func hex4GPlus(offset) { emit hexDword(offset) + hexDword(1) }

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

func hexName16(s) {
    let n = len(s)
    if n > 16 { n = 16 }
    let out = ""
    let i = 0
    while i < n {
        out = out + hexByte(charCode(s[i]))
        i += 1
    }
    while i < 16 {
        out = out + hexByte(0)
        i += 1
    }
    emit out
}

func hexBytesLen(s) { emit len(s) / 3 }


// ── Mach-O constants ───────────────────────────────────────────────────────

func MH_MAGIC_64()     { emit 0xFEEDFACF }
func MH_EXECUTE()      { emit 2 }
func MH_NOUNDEFS()     { emit 1 }

func CPU_TYPE_X86_64() { emit 0x01000007 }
func CPU_TYPE_ARM64()  { emit 0x0100000C }
func CPU_SUBTYPE_X86_64_ALL() { emit 3 }
func CPU_SUBTYPE_ARM64_ALL()  { emit 0 }

func LC_SEGMENT_64()     { emit 0x19 }
func LC_UNIXTHREAD()     { emit 0x05 }
func LC_BUILD_VERSION()  { emit 0x32 }
func LC_CODE_SIGNATURE() { emit 0x1D }

// Thread state flavors / counts
func X86_THREAD_STATE64()       { emit 4 }
func X86_THREAD_STATE64_COUNT() { emit 42 }   // 168 / 4 = 42 dwords
func ARM_THREAD_STATE64()       { emit 6 }
func ARM_THREAD_STATE64_COUNT() { emit 68 }   // 272 / 4 = 68 dwords

// LC_BUILD_VERSION platform constants
func PLATFORM_MACOS() { emit 1 }

// __text section flags: S_REGULAR(0) | S_ATTR_PURE_INSTRUCTIONS(0x80000000)
//                                    | S_ATTR_SOME_INSTRUCTIONS(0x400)
func TEXT_SECT_FLAGS() { emit 0x80000400 }


// ── Mach-O header emission ─────────────────────────────────────────────────

// 32-byte mach_header_64. arch is "x86_64" or "arm64".
func emitMachHeader(arch, ncmds, sizeofcmds) {
    let cputype = CPU_TYPE_X86_64()
    let subtype = CPU_SUBTYPE_X86_64_ALL()
    if arch == "arm64" {
        cputype = CPU_TYPE_ARM64()
        subtype = CPU_SUBTYPE_ARM64_ALL()
    }
    let c = ""
    c = c + hexDword(MH_MAGIC_64())
    c = c + hexDword(cputype)
    c = c + hexDword(subtype)
    c = c + hexDword(MH_EXECUTE())
    c = c + hexDword(ncmds)
    c = c + hexDword(sizeofcmds)
    c = c + hexDword(MH_NOUNDEFS())
    c = c + hexDword(0)
    emit c
}

// LC_SEGMENT_64 __PAGEZERO — 72 bytes, no sections.
// Reserves the bottom 4GB. Mandatory on macOS.
func emitPageZero() {
    let c = ""
    c = c + hexDword(LC_SEGMENT_64())
    c = c + hexDword(72)
    c = c + hexName16("__PAGEZERO")
    c = c + hexQword(0)                          // vmaddr
    c = c + hexQword4G()                         // vmsize = 0x100000000
    c = c + hexQword(0)                          // fileoff
    c = c + hexQword(0)                          // filesize
    c = c + hexDword(0)                          // maxprot
    c = c + hexDword(0)                          // initprot
    c = c + hexDword(0)                          // nsects
    c = c + hexDword(0)                          // flags
    emit c
}

// LC_SEGMENT_64 __TEXT — 72 + 80 = 152 bytes (1 __text section).
//   vmaddr   = 0x100000000
//   vmsize   = page-aligned (0x4000 on Apple Silicon, 0x1000 on Intel; 0x4000 works for both)
//   fileoff  = 0
//   filesize = full file size
//   maxprot  = R+W+X = 7
//   initprot = R+X   = 5
//   nsects   = 1
func emitTextSegment(filesize, vmsize, codeOffset, codeAndDataSize) {
    let c = ""
    // segment header (72 bytes)
    c = c + hexDword(LC_SEGMENT_64())
    c = c + hexDword(152)
    c = c + hexName16("__TEXT")
    c = c + hex4GPlus(0)                         // vmaddr = 0x100000000
    c = c + hexQword(vmsize)
    c = c + hexQword(0)                          // fileoff
    c = c + hexQword(filesize)
    c = c + hexDword(7)                          // maxprot
    c = c + hexDword(5)                          // initprot
    c = c + hexDword(1)                          // nsects
    c = c + hexDword(0)                          // flags
    // section __text (80 bytes)
    c = c + hexName16("__text")
    c = c + hexName16("__TEXT")
    c = c + hex4GPlus(codeOffset)                // addr
    c = c + hexQword(codeAndDataSize)            // size
    c = c + hexDword(codeOffset)                 // offset
    c = c + hexDword(4)                          // align (2^4 = 16)
    c = c + hexDword(0)                          // reloff
    c = c + hexDword(0)                          // nreloc
    c = c + hexDword(TEXT_SECT_FLAGS())
    c = c + hexDword(0)                          // reserved1
    c = c + hexDword(0)                          // reserved2
    c = c + hexDword(0)                          // reserved3
    emit c
}

// Pre-reserved space for the code signature blob, in bytes. Must be 16-aligned.
// 256 is comfortably larger than the ad-hoc signature for any binary we emit
// today (typical ad-hoc sig: SuperBlob 12 + BlobIndex 8 + CodeDirectory ~50
// + identifier ~10 + N×32 page hashes ≈ 110 bytes). codesign will overwrite
// the reserved bytes with the real signature and update the actual size in
// LC_CODE_SIGNATURE.datasize. Bumping this is cheap if a future binary needs
// more page hashes (one per page of __TEXT).
func sigReservedSize() { emit 256 }

// Big-endian dword. Code signature blobs are BIG-endian (unlike the rest of
// Mach-O which is host-endian / little-endian).
func hexDwordBE(n) {
    let v = toInt(n)
    let b3 = v % 256
    if b3 < 0 { b3 = b3 + 256 }
    let q1 = v / 256
    if v % 256 != 0 && v < 0 { q1 = q1 - 1 }
    let b2 = q1 % 256
    if b2 < 0 { b2 = b2 + 256 }
    let q2 = q1 / 256
    if q1 % 256 != 0 && q1 < 0 { q2 = q2 - 1 }
    let b1 = q2 % 256
    if b1 < 0 { b1 = b1 + 256 }
    let q3 = q2 / 256
    if q2 % 256 != 0 && q2 < 0 { q3 = q3 - 1 }
    let b0 = q3 % 256
    if b0 < 0 { b0 = b0 + 256 }
    emit hexByte(b0) + hexByte(b1) + hexByte(b2) + hexByte(b3)
}

// Empty SuperBlob placeholder — 12 bytes of valid signature format that
// codesign recognizes as "an empty signature, replace me." Without this,
// codesign reads our reserved region as a malformed blob and refuses with
// "invalid or unsupported format for signature."
//
// Format (all big-endian):
//   magic   = 0xFADE0CC0  (CSMAGIC_EMBEDDED_SIGNATURE)
//   length  = 12          (header only, no blob entries)
//   count   = 0           (no slots)
func emitEmptySuperBlob() {
    let c = ""
    c = c + hexDwordBE(0xFADE0CC0)
    c = c + hexDwordBE(12)
    c = c + hexDwordBE(0)
    emit c
}

// LC_SEGMENT_64 __LINKEDIT — 72 bytes, no sections.
//
// macOS 11+ requires a __LINKEDIT segment. This is where the code signature
// will live. We pre-reserve `sigReservedSize` bytes for the signature; both
// __LINKEDIT.filesize and LC_CODE_SIGNATURE.datasize are set to that value
// so codesign sees a valid placeholder it can write into.
//
//   fileoff    = 16-byte-aligned end of __TEXT region
//   filesize   = sigReservedSize (codesign overwrites in place, may shrink)
//   vmaddr     = __TEXT_vmaddr + __TEXT_vmsize  (right after __TEXT)
//   vmsize     = page-aligned (0x4000 to match __TEXT's vmsize)
//   maxprot    = R only (1)
//   initprot   = R only (1)
func emitLinkEditSegment(fileoff, vmaddrLo, filesize) {
    let c = ""
    c = c + hexDword(LC_SEGMENT_64())
    c = c + hexDword(72)
    c = c + hexName16("__LINKEDIT")
    c = c + hex4GPlus(vmaddrLo)                  // vmaddr (low + 1 in high)
    c = c + hexQword(0x4000)                     // vmsize (16K page)
    c = c + hexQword(fileoff)                    // fileoff
    c = c + hexQword(filesize)                   // filesize
    c = c + hexDword(1)                          // maxprot R
    c = c + hexDword(1)                          // initprot R
    c = c + hexDword(0)                          // nsects
    c = c + hexDword(0)                          // flags
    emit c
}

// LC_CODE_SIGNATURE — 16 bytes.
//
// dataoff = 16-aligned offset where the signature blob lives.
// datasize = pre-allocated reservation (codesign writes within this; may
//   update to actual size after signing).
func emitCodeSignatureCmd(dataoff, datasize) {
    let c = ""
    c = c + hexDword(LC_CODE_SIGNATURE())
    c = c + hexDword(16)
    c = c + hexDword(dataoff)
    c = c + hexDword(datasize)
    emit c
}

// LC_BUILD_VERSION — 24 bytes. Tells macOS what platform/version this binary
// targets. Modern macOS (especially Apple Silicon) wants this; without it the
// kernel may refuse to load. ntools = 0 (no embedded tool versions).
//
// Version encoding: X.Y.Z packed as XXYYZZ in 32 bits (big-endian nibbles).
// macOS 11.0 = 0x000B0000. We use macOS 11.0 as min and 11.0 as SDK to keep
// it simple; that covers Apple Silicon (which started at 11.0) and is widely
// compatible.
func emitBuildVersion() {
    let c = ""
    c = c + hexDword(LC_BUILD_VERSION())         // cmd
    c = c + hexDword(24)                          // cmdsize
    c = c + hexDword(PLATFORM_MACOS())            // platform = 1
    c = c + hexDword(0x000B0000)                  // minos = 11.0.0
    c = c + hexDword(0x000B0000)                  // sdk = 11.0.0
    c = c + hexDword(0)                           // ntools
    emit c
}

// LC_UNIXTHREAD — entry point. Cmdsize and state layout differ per arch.
//
// x86_64 (184 bytes total):
//   cmd / cmdsize:  8 bytes  (LC_UNIXTHREAD, 184)
//   flavor / count: 8 bytes  (4=x86_THREAD_STATE64, 42)
//   thread state: 168 bytes  (RAX..R15, RIP at idx 16, RFLAGS, CS, FS, GS)
//
// ARM64 (288 bytes total):
//   cmd / cmdsize:  8 bytes  (LC_UNIXTHREAD, 288)
//   flavor / count: 8 bytes  (6=ARM_THREAD_STATE64, 68)
//   thread state: 272 bytes  (X0..X28, FP, LR, SP, PC, CPSR + 4 byte pad)
//
// arm_thread_state64_t layout (from <mach/arm/_structs.h>):
//   uint64 x[29]      ; 232 bytes (X0..X28)
//   uint64 fp         ; 8 bytes  (X29)
//   uint64 lr         ; 8 bytes  (X30)
//   uint64 sp         ; 8 bytes
//   uint64 pc         ; 8 bytes  (we set this to entry vaddr)
//   uint32 cpsr       ; 4 bytes
//   uint32 __pad      ; 4 bytes
//   = 272 bytes
//
// PC offset within state = 232 + 8 + 8 + 8 = 256 bytes from start of state.
func emitUnixThread(arch, entryLo, entryHi) {
    let c = ""
    if arch == "arm64" {
        c = c + hexDword(LC_UNIXTHREAD())
        c = c + hexDword(288)                            // cmdsize
        c = c + hexDword(ARM_THREAD_STATE64())
        c = c + hexDword(ARM_THREAD_STATE64_COUNT())
        // X0..X28 zeroed (29 * 8 = 232 bytes)
        c = c + hexPad(232)
        // FP, LR, SP zeroed (3 * 8 = 24 bytes)
        c = c + hexPad(24)
        // PC = entry vaddr (8 bytes)
        c = c + hexDword(entryLo) + hexDword(entryHi)
        // CPSR + pad = 8 bytes zeroed
        c = c + hexPad(8)
    } else {
        // x86_64
        c = c + hexDword(LC_UNIXTHREAD())
        c = c + hexDword(184)                            // cmdsize
        c = c + hexDword(X86_THREAD_STATE64())
        c = c + hexDword(X86_THREAD_STATE64_COUNT())
        // RAX..R15 = 16 regs × 8 = 128 bytes zeroed
        c = c + hexPad(128)
        // RIP = entry vaddr (8 bytes)
        c = c + hexDword(entryLo) + hexDword(entryHi)
        // RFLAGS, CS, FS, GS = 32 bytes zeroed
        c = c + hexPad(32)
    }
    emit c
}


// ── x86_64 instruction emitters ────────────────────────────────────────────

func x86_emitMovEaxImm32(n) { emit hexByte(0xB8) + hexDword(n) }
func x86_emitMovEdiImm32(n) { emit hexByte(0xBF) + hexDword(n) }
func x86_emitMovEdxImm32(n) { emit hexByte(0xBA) + hexDword(n) }
func x86_emitMovRsiImm64(loDword, hiDword) {
    emit hexByte(0x48) + hexByte(0xBE) + hexDword(loDword) + hexDword(hiDword)
}
func x86_emitXorEdiEdi() { emit hexByte(0x31) + hexByte(0xFF) }
func x86_emitSyscall()   { emit hexByte(0x0F) + hexByte(0x05) }


// ── ARM64 instruction emitters ─────────────────────────────────────────────
//
// All ARM64 instructions are 4 bytes, little-endian.
//
// MOVZ Xd, #imm16 {, LSL #(hw*16)}: zero-extend imm16 into Xd at shift hw.
//   Encoding: 1 10 100101 hw imm16(16) Rd(5)
//   hw: 0=no shift, 1=lsl16, 2=lsl32, 3=lsl48
//
// MOVK Xd, #imm16 {, LSL #(hw*16)}: keep other bits, write imm16 at shift.
//   Encoding: 1 11 100101 hw imm16(16) Rd(5)
//
// SVC #imm16: supervisor call. Encoding: 11010100 000 imm16(16) 00001
//
// We build the 32-bit instruction word as integer math then emit little-endian.

// emitArm64Word: encode a 32-bit instruction word as 4 little-endian bytes.
// Delegates to hexDword which already handles Krypton's truncate-toward-zero
// division correctly for high-bit-set values like 0xD2800020 (which Krypton
// stores as a negative signed int).
func emitArm64Word(w) { emit hexDword(w) }

// MOVZ Xd, #imm16, LSL #(hw*16). Rd is 0..30. hw is 0..3.
// Bit layout: 0xD2800000 | (hw << 21) | (imm16 << 5) | Rd
func arm64_emitMovz(rd, imm16, hw) {
    let w = 0xD2800000 + (hw * 0x200000) + (imm16 * 32) + rd
    emit emitArm64Word(w)
}

// MOVK Xd, #imm16, LSL #(hw*16).
// Bit layout: 0xF2800000 | (hw << 21) | (imm16 << 5) | Rd
func arm64_emitMovk(rd, imm16, hw) {
    let w = 0xF2800000 + (hw * 0x200000) + (imm16 * 32) + rd
    emit emitArm64Word(w)
}

// SVC #imm16. Encoding: 0xD4000001 | (imm16 << 5)
func arm64_emitSvc(imm16) {
    let w = 0xD4000001 + (imm16 * 32)
    emit emitArm64Word(w)
}

// Build a 64-bit value into Xd using exactly 3 instructions: MOVZ + 2 MOVKs.
// Always emits 12 bytes regardless of address (constant code size). MOVK with
// imm=0 is effectively a no-op (writes 0 over bits that are already 0 in the
// MOVZ-cleared register).
//
// Full address = 0x100000000 + lowBits, where lowBits < 4GB. Target encoding:
//   MOVZ Xd, #(lowBits & 0xFFFF)
//   MOVK Xd, #((lowBits >> 16) & 0xFFFF), LSL #16    (bits 31-16 of lowBits)
//   MOVK Xd, #1, LSL #32                              (the +0x100000000 high part)
func arm64_emitLoadAddr64(rd, lowBits) {
    let lo16 = lowBits % 65536
    let hi16 = (lowBits / 65536) % 65536
    let result = ""
    result = result + arm64_emitMovz(rd, lo16, 0)
    result = result + arm64_emitMovk(rd, hi16, 1)
    result = result + arm64_emitMovk(rd, 1, 2)
    emit result
}


// ── Page alignment ─────────────────────────────────────────────────────────
// Apple Silicon uses 16K pages (0x4000), Intel uses 4K (0x1000). 16K alignment
// works for both, so we use that universally.
func alignUp16K(n) {
    let r = n % 16384
    if r == 0 { emit n }
    emit n + (16384 - r)
}


// ── Main: emit hello-world Mach-O for the requested arch ───────────────────

just run {
    // Parse args: optional --arch flag + output path.
    let arch = "x86_64"
    let outPath = ""
    let ai = 0
    let n = argCount()
    while ai < n {
        let a = arg(ai)
        if a == "--arch" {
            ai += 1
            if ai < n { arch = arg(ai) }
        } else if startsWith(a, "--arch=") {
            arch = substring(a, 7, len(a))
        } else {
            // treat the LAST positional arg as output path; ignore earlier
            // ones (kcc.sh historically passes the IR file before the output)
            outPath = a
        }
        ai += 1
    }

    if arch != "x86_64" {
        if arch != "arm64" {
            printErr("macho: unsupported --arch '" + arch + "' (use x86_64 or arm64)")
            exit(1)
        }
    }

    if len(outPath) == 0 {
        printErr("macho: usage: macho [--arch x86_64|arm64] <output>")
        exit(1)
    }

    let msg = "Hello from Krypton on macOS!" + fromCharCode(10)
    let msgLen = len(msg)

    // ── Layout ──────────────────────────────────────────────────────────
    // Load commands (in order):
    //   PAGEZERO (72) + TEXT (152) + LINKEDIT (72) + BUILD_VERSION (24)
    //                              + UNIXTHREAD (varies) + CODE_SIGNATURE (16)
    let unixThrSize = 184
    if arch == "arm64" { unixThrSize = 288 }

    let cmdsSize = 72 + 152 + 72 + 24 + unixThrSize + 16
    let ncmds = 6
    let codeOffset = 32 + cmdsSize

    // Code size per arch (see comments above on instruction counts):
    //   x86_64: 36 bytes
    //   arm64:  40 bytes (10 instructions × 4)
    let codeSize = 36
    if arch == "arm64" { codeSize = 40 }

    let msgOffset = codeOffset + codeSize
    let msgVAddrLo = msgOffset

    // End of code+data, then pad to 16-byte align so the signature data area
    // starts on a 16-byte boundary (codesign requires this).
    let codeAndDataEnd = codeOffset + codeSize + msgLen
    let codeAndDataAligned = codeAndDataEnd
    let alignRem = codeAndDataEnd % 16
    if alignRem != 0 {
        codeAndDataAligned = codeAndDataEnd + (16 - alignRem)
    }
    let alignPadBytes = codeAndDataAligned - codeAndDataEnd

    // Pre-reserve sigReservedSize() bytes for the code signature blob.
    // codesign writes the actual signature into this region; macOS Tahoe
    // (26.x) refuses to extend the file itself, so we must allocate up front.
    let sigSize = sigReservedSize()

    // __TEXT covers the file from offset 0 up to the (aligned) end of code+data.
    // __LINKEDIT covers the signature reservation right after.
    let textFileSize = codeAndDataAligned
    let textVmSize   = alignUp16K(textFileSize)
    let linkeditVmAddrLo = textVmSize

    let filesize = codeAndDataAligned + sigSize

    let entryLo = codeOffset
    let entryHi = 1                                // 0x100000000

    // ── Emit headers ────────────────────────────────────────────────────
    let header   = emitMachHeader(arch, ncmds, cmdsSize)
    let pagezero = emitPageZero()
    let textSeg  = emitTextSegment(textFileSize, textVmSize, codeOffset, codeSize + msgLen)
    let linkSeg  = emitLinkEditSegment(codeAndDataAligned, linkeditVmAddrLo, sigSize)
    let buildVer = emitBuildVersion()
    let unixThr  = emitUnixThread(arch, entryLo, entryHi)
    let codeSig  = emitCodeSignatureCmd(codeAndDataAligned, sigSize)

    // ── Emit code (per arch) ────────────────────────────────────────────
    let code = ""
    if arch == "arm64" {
        // X0 = 1 (fd = stdout)
        code = code + arm64_emitMovz(0, 1, 0)
        // X1 = msg vaddr (MOVZ + 2x MOVK to build 0x100000000 + msgOffset)
        code = code + arm64_emitLoadAddr64(1, msgVAddrLo)
        // X2 = msgLen
        code = code + arm64_emitMovz(2, msgLen, 0)
        // X16 = 4 (SYS_write)
        code = code + arm64_emitMovz(16, 4, 0)
        // SVC #0x80
        code = code + arm64_emitSvc(0x80)
        // X0 = 0 (exit status)
        code = code + arm64_emitMovz(0, 0, 0)
        // X16 = 1 (SYS_exit)
        code = code + arm64_emitMovz(16, 1, 0)
        // SVC #0x80
        code = code + arm64_emitSvc(0x80)
    } else {
        // x86_64 BSD-class syscalls (number OR'd with 0x2000000)
        code = code + x86_emitMovEaxImm32(0x2000004)        // SYS_write
        code = code + x86_emitMovEdiImm32(1)                // fd
        code = code + x86_emitMovRsiImm64(msgVAddrLo, 1)    // RSI = msg addr
        code = code + x86_emitMovEdxImm32(msgLen)
        code = code + x86_emitSyscall()
        code = code + x86_emitMovEaxImm32(0x2000001)        // SYS_exit
        code = code + x86_emitXorEdiEdi()
        code = code + x86_emitSyscall()
    }

    let data = hexStr(msg)
    let pad  = hexPad(alignPadBytes)
    // Signature placeholder: 12-byte empty SuperBlob followed by zeros up to
    // sigReservedSize. Gives codesign a valid format header to recognize and
    // replace; the trailing zeros are simply unused space until codesign's
    // signature fills it (or stays as padding if signature is smaller).
    let sigPlaceholder = emitEmptySuperBlob() + hexPad(sigSize - 12)
    // Load command order: PAGEZERO, TEXT, LINKEDIT, BUILD_VERSION, UNIXTHREAD, CODE_SIGNATURE
    // File layout: header + cmds + code + data + alignment pad + signature reservation
    let all  = header + pagezero + textSeg + linkSeg + buildVer + unixThr + codeSig + code + data + pad + sigPlaceholder

    let bytesEmitted = hexBytesLen(all)
    if bytesEmitted != filesize {
        printErr("macho: internal layout error: emitted " + bytesEmitted + " bytes, expected " + filesize)
        exit(1)
    }

    writeBytes(outPath, all)
    printErr("macho: wrote " + outPath + " (" + filesize + " bytes, arch=" + arch + ")")
    printErr("       Run `codesign -s - --force " + outPath + "` then `./" + outPath + "`")
}
