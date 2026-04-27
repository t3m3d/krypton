// macho.k — Krypton native Mach-O backend for x86-64 macOS.
//
// First milestone (THIS version): emit a static Mach-O hello-world. Once the
// format is verified on real macOS hardware, we expand to full IR support
// the way elf.k did (parse .kir, emit user functions + runtime helpers).
//
// Why x86_64 first (not ARM64): same instruction emission as elf.k, runs on
// Intel macOS natively AND on Apple Silicon via Rosetta 2. ARM64 would need
// a brand-new ISA backend.
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
//   `codesign` ships with Xcode Command Line Tools. We don't embed
//   LC_CODE_SIGNATURE in this version; that's a future enhancement.
//
// Layout produced (file offsets):
//   [0..31]      mach_header_64                              (32 bytes)
//   [32..103]    LC_SEGMENT_64 __PAGEZERO  (no sections)     (72 bytes)
//   [104..255]   LC_SEGMENT_64 __TEXT      (1 section)       (152 bytes)
//   [256..439]   LC_UNIXTHREAD             (x86 thread state) (184 bytes)
//   [440..]      code (and string data, for now in same segment)
//
//   ncmds        = 3
//   sizeofcmds   = 72 + 152 + 184 = 408
//   header+cmds  = 32 + 408 = 440
//
// Calling convention: same as Linux/SysV (RDI/RSI/RDX/R10/R8/R9). The only
// real differences from ELF are: container format, syscall numbers (BSD
// class — OR'd with 0x2000000), and the entry-point mechanism.
//
// macOS x86_64 syscall numbers (BSD class, prefix with 0x2000000):
//   write = 4   →  RAX = 0x2000004
//   exit  = 1   →  RAX = 0x2000001
//   read  = 3   →  RAX = 0x2000003
//   open  = 5   →  RAX = 0x2000005
//   close = 6   →  RAX = 0x2000006
//   mmap  = 197 →  RAX = 0x20000C5
//
// Usage:  kcc kompiler/macho.k input.kir output (no extension; chmod +x by caller)
//         then: codesign -s - --force output

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
    // Krypton ints fit in ~63 bits via toInt, so the high dword is 0
    // for any address we care about EXCEPT the __TEXT vmaddr (0x100000000)
    // and PAGEZERO vmsize (also 0x100000000). Those need the high dword = 1.
    // For all other 64-bit values used here, high dword = 0.
    emit hexDword(n) + hexDword(0)
}

// hexQword4G: emits 0x0000000100000000 (4GB), used for PAGEZERO vmsize and
// __TEXT vmaddr. Krypton can't represent this as a single int directly.
func hexQword4G() { emit hexDword(0) + hexDword(1) }

// hex4GPlus: emits 0x100000000 + offset, where offset is < 4GB. Used for
// section addresses and the entry-point RIP.
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

// 16-byte fixed-width segment/section name. Pads with NULs.
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

func MH_MAGIC_64()  { emit 0xFEEDFACF }
func CPU_TYPE_X86_64()    { emit 0x01000007 }   // 7 | CPU_ARCH_ABI64 (0x01000000)
func CPU_SUBTYPE_X86_64_ALL() { emit 3 }
func MH_EXECUTE()    { emit 2 }
func MH_NOUNDEFS()   { emit 1 }

func LC_SEGMENT_64() { emit 0x19 }
func LC_UNIXTHREAD() { emit 0x05 }

// x86_THREAD_STATE64 flavor and count
func X86_THREAD_STATE64() { emit 4 }
// thread state is 21 64-bit fields = 168 bytes = 42 dwords
func X86_THREAD_STATE64_COUNT() { emit 42 }

// __TEXT segment vm permissions: maxprot/initprot
func VM_PROT_READ()  { emit 1 }
func VM_PROT_WRITE() { emit 2 }
func VM_PROT_EXEC()  { emit 4 }

// __text section flags: S_REGULAR(0) | S_ATTR_PURE_INSTRUCTIONS(0x80000000)
//                                    | S_ATTR_SOME_INSTRUCTIONS(0x400)
// = 0x80000400
func TEXT_SECT_FLAGS() { emit 0x80000400 }


// ── Mach-O header emission ─────────────────────────────────────────────────

// 32-byte mach_header_64.
func emitMachHeader(ncmds, sizeofcmds) {
    let c = ""
    c = c + hexDword(MH_MAGIC_64())
    c = c + hexDword(CPU_TYPE_X86_64())
    c = c + hexDword(CPU_SUBTYPE_X86_64_ALL())
    c = c + hexDword(MH_EXECUTE())
    c = c + hexDword(ncmds)
    c = c + hexDword(sizeofcmds)
    c = c + hexDword(MH_NOUNDEFS())
    c = c + hexDword(0)                         // reserved
    emit c
}

// LC_SEGMENT_64 __PAGEZERO — 72 bytes, no sections.
// Reserves the bottom 4GB so any null-deref or accidental low-address access
// segfaults. Standard macOS layout.
func emitPageZero() {
    let c = ""
    c = c + hexDword(LC_SEGMENT_64())           // cmd
    c = c + hexDword(72)                         // cmdsize
    c = c + hexName16("__PAGEZERO")              // segname
    c = c + hexQword(0)                          // vmaddr = 0
    c = c + hexQword4G()                         // vmsize = 0x100000000
    c = c + hexQword(0)                          // fileoff
    c = c + hexQword(0)                          // filesize
    c = c + hexDword(0)                          // maxprot
    c = c + hexDword(0)                          // initprot
    c = c + hexDword(0)                          // nsects
    c = c + hexDword(0)                          // flags
    emit c
}

// LC_SEGMENT_64 __TEXT — 72 (segment) + 80 (one __text section) = 152 bytes.
//
//   vmaddr   = 0x100000000 (just past PAGEZERO)
//   vmsize   = page-aligned filesize (0x1000 alignment)
//   fileoff  = 0   (whole file from offset 0 is the segment)
//   filesize = full file size
//   maxprot  = R+W+X = 7
//   initprot = R+X   = 5
//   nsects   = 1
//   section __text:
//     addr    = vmaddr + (file offset of code)
//     size    = code size + string data size
//     offset  = file offset of code (440 for our 3-cmd layout)
//     align   = 4 (2^4 = 16 bytes)
//     flags   = S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS
func emitTextSegment(filesize, vmsize, codeOffset, codeAndDataSize) {
    let c = ""
    // segment header
    c = c + hexDword(LC_SEGMENT_64())
    c = c + hexDword(152)                        // cmdsize = 72 + 80
    c = c + hexName16("__TEXT")
    c = c + hex4GPlus(0)                         // vmaddr = 0x100000000
    c = c + hexQword(vmsize)                     // vmsize (page-aligned)
    c = c + hexQword(0)                          // fileoff = 0
    c = c + hexQword(filesize)                   // filesize
    c = c + hexDword(7)                          // maxprot RWX
    c = c + hexDword(5)                          // initprot RX
    c = c + hexDword(1)                          // nsects
    c = c + hexDword(0)                          // flags
    // section __text (80 bytes)
    c = c + hexName16("__text")                  // sectname
    c = c + hexName16("__TEXT")                  // segname
    c = c + hex4GPlus(codeOffset)                // addr (vmaddr + codeOffset)
    c = c + hexQword(codeAndDataSize)            // size
    c = c + hexDword(codeOffset)                 // offset (file offset)
    c = c + hexDword(4)                          // align (2^4 = 16)
    c = c + hexDword(0)                          // reloff
    c = c + hexDword(0)                          // nreloc
    c = c + hexDword(TEXT_SECT_FLAGS())          // flags
    c = c + hexDword(0)                          // reserved1
    c = c + hexDword(0)                          // reserved2
    c = c + hexDword(0)                          // reserved3
    emit c
}

// LC_UNIXTHREAD — 184 bytes for x86_64.
//   cmd / cmdsize:    8 bytes  (LC_UNIXTHREAD, 184)
//   flavor / count:   8 bytes  (4=x86_THREAD_STATE64, 42)
//   thread state:   168 bytes  (21 × uint64 — RAX, RBX, RCX, RDX, RDI, RSI,
//                                RBP, RSP, R8..R15, RIP, RFLAGS, CS, FS, GS)
//
// We zero everything except RIP, which gets the entry-point virtual address.
// Field order in x86_thread_state64_t (Apple headers):
//   [0]  rax    [1]  rbx    [2]  rcx    [3]  rdx
//   [4]  rdi    [5]  rsi    [6]  rbp    [7]  rsp
//   [8]  r8     [9]  r9     [10] r10    [11] r11
//   [12] r12    [13] r13    [14] r14    [15] r15
//   [16] rip    [17] rflags [18] cs     [19] fs     [20] gs
func emitUnixThread(entryVAddr, entryHi) {
    let c = ""
    c = c + hexDword(LC_UNIXTHREAD())            // cmd
    c = c + hexDword(184)                         // cmdsize
    c = c + hexDword(X86_THREAD_STATE64())        // flavor
    c = c + hexDword(X86_THREAD_STATE64_COUNT())  // count (42 dwords of state)
    // 16 GP regs zeroed = 16 × 8 = 128 bytes
    c = c + hexPad(128)
    // [16] RIP — entry point. Encode as low + high dword (high = 1 for >4GB vmaddr).
    c = c + hexDword(entryVAddr) + hexDword(entryHi)
    // RFLAGS, CS, FS, GS — all zero
    c = c + hexPad(32)
    emit c
}


// ── Code emitters (x86_64 instructions — same encoding as elf.k) ───────────

// MOV EAX, imm32  →  B8 imm32       (5 bytes)
func emitMovEaxImm32(n) { emit hexByte(0xB8) + hexDword(n) }
// MOV EDI, imm32  →  BF imm32       (5 bytes)
func emitMovEdiImm32(n) { emit hexByte(0xBF) + hexDword(n) }
// MOV EDX, imm32  →  BA imm32       (5 bytes)
func emitMovEdxImm32(n) { emit hexByte(0xBA) + hexDword(n) }
// MOV RSI, imm64  →  48 BE imm64    (10 bytes)
func emitMovRsiImm64Lo(loDword, hiDword) {
    emit hexByte(0x48) + hexByte(0xBE) + hexDword(loDword) + hexDword(hiDword)
}
// XOR EDI, EDI    →  31 FF          (2 bytes)
func emitXorEdiEdi() { emit hexByte(0x31) + hexByte(0xFF) }
// SYSCALL         →  0F 05          (2 bytes)
func emitSyscall() { emit hexByte(0x0F) + hexByte(0x05) }


// ── Page alignment ─────────────────────────────────────────────────────────
// Mach-O __TEXT vmsize must be a multiple of 0x1000 (page size).
func alignUp4K(n) {
    let r = n % 4096
    if r == 0 { emit n }
    emit n + (4096 - r)
}


// ── Main: emit a hello-world Mach-O ────────────────────────────────────────
//
// First version is a hardcoded hello-world. Once the user verifies it runs
// on their Mac (with `codesign -s - --force <output>`), we'll plumb in IR
// parsing the way elf.k does.

just run {
    let outPath = arg("1")
    if len(outPath) == 0 {
        printErr("macho: usage: kcc kompiler/macho.k <ir-or-ignored> <output>")
        exit(1)
    }

    // Hello message
    let msg = "Hello from Krypton on macOS!" + fromCharCode(10)
    let msgLen = len(msg)

    // ── Compute layout ────────────────────────────────────────────────
    // header (32) + PAGEZERO (72) + TEXT (152) + UNIXTHREAD (184) = 440
    let codeOffset = 440
    let textVAddrLo = codeOffset                  // low dword of section addr
    // High dword of section addr = 1 (vmaddr 0x100000000 + small)

    // Code:
    //   _start:
    //     mov eax, 0x2000004     ; SYS_write          (5)
    //     mov edi, 1             ; fd = stdout        (5)
    //     mov rsi, msgVAddr      ; absolute address   (10)
    //     mov edx, msgLen                              (5)
    //     syscall                                       (2)
    //     mov eax, 0x2000001     ; SYS_exit            (5)
    //     xor edi, edi           ; status = 0          (2)
    //     syscall                                       (2)
    let codeSize = 36
    let msgOffset = codeOffset + codeSize          // file offset of msg
    let msgVAddrLo = msgOffset                     // low dword (high = 1)

    let totalCodeAndData = codeSize + msgLen
    let filesize = codeOffset + totalCodeAndData
    let vmsize = alignUp4K(filesize)

    // Entry point RIP = vmaddr + codeOffset
    let entryLo = codeOffset
    let entryHi = 1                                // 0x100000000

    // ── Emit everything ─────────────────────────────────────────────────
    let header   = emitMachHeader(3, 408)
    let pagezero = emitPageZero()
    let textSeg  = emitTextSegment(filesize, vmsize, codeOffset, totalCodeAndData)
    let unixThr  = emitUnixThread(entryLo, entryHi)

    let code = ""
    code = code + emitMovEaxImm32(0x2000004)       // SYS_write
    code = code + emitMovEdiImm32(1)               // fd = stdout
    code = code + emitMovRsiImm64Lo(msgVAddrLo, 1) // RSI = msg vaddr (high=1)
    code = code + emitMovEdxImm32(msgLen)
    code = code + emitSyscall()
    code = code + emitMovEaxImm32(0x2000001)       // SYS_exit
    code = code + emitXorEdiEdi()
    code = code + emitSyscall()

    let data = hexStr(msg)

    let all = header + pagezero + textSeg + unixThr + code + data

    // hexBytesLen returns the number of actual bytes encoded (each "xHH" = 1 byte)
    let bytesEmitted = hexBytesLen(all)

    // Sanity check: bytesEmitted should equal filesize
    if bytesEmitted != filesize {
        printErr("macho: internal layout error: emitted " + bytesEmitted + " bytes, expected " + filesize)
        exit(1)
    }

    // writeBytes decodes our hex-encoded "xHH" stream into raw binary bytes.
    // (writeFile would write the literal text "x4Fx45..." which is not what we want.)
    writeBytes(outPath, all)
    printErr("macho: wrote " + outPath + " (" + filesize + " bytes)")
    printErr("       Run `codesign -s - --force " + outPath + "` then `./" + outPath + "`")
}
