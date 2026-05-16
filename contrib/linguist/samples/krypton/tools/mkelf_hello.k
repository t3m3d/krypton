// mkelf_hello.k — emit a minimal ELF64 binary for x86-64 Linux that:
//   - writes "hello from a hand-emitted ELF\n" to stdout via SYS_write
//   - exits with code 0 via SYS_exit
//
// Validates: ELF format, two key syscalls (write, exit), .rodata-style data
// embedded in the same R+X segment.
//
// Usage:  kcc tools/mkelf_hello.k > /tmp/_mke.c && gcc /tmp/_mke.c -o /tmp/_mke && /tmp/_mke
// Then on Linux:  exec /tmp/hello.elf  (must use exec for accurate rc through WSL)

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
    let b1 = (v / 256) % 256
    let b2 = (v / 65536) % 256
    let b3 = (v / 16777216) % 256
    emit hexByte(b0) + hexByte(b1) + hexByte(b2) + hexByte(b3)
}

func hexQword(n) {
    emit hexDword(n) + hexDword(0)
}

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

func main() {
    // ── Layout ────────────────────────────────────────────────────────
    //   [0..63]    ELF64 header
    //   [64..119]  one program header (PT_LOAD, R+X, covers whole file)
    //   [120..]    code, then the message string immediately after.
    //
    // Virtual base: 0x400000.  Code at 0x400078.  Message right after code.

    let VADDR_BASE = 4194304          // 0x400000
    let HDR_SIZE   = 120              // 64 ELF + 56 PHdr
    let CODE_VADDR = VADDR_BASE + HDR_SIZE

    let MSG = "hello from a hand-emitted ELF\n"
    let MSG_LEN = len(MSG)

    // Code:
    //   mov eax, 1            ; SYS_write = 1
    //   mov edi, 1            ; fd = stdout
    //   mov rsi, <msg_vaddr>  ; pointer to message
    //   mov edx, MSG_LEN      ; length
    //   syscall
    //   xor edi, edi          ; exit code 0
    //   mov eax, 60           ; SYS_exit = 60
    //   syscall
    //
    // Encoded:
    //   B8 01 00 00 00              5  mov eax, imm32
    //   BF 01 00 00 00              5  mov edi, imm32
    //   48 BE <8-byte imm>          10 mov rsi, imm64
    //   BA <imm32>                  5  mov edx, imm32
    //   0F 05                       2  syscall
    //   31 FF                       2  xor edi, edi
    //   B8 3C 00 00 00              5  mov eax, 60
    //   0F 05                       2  syscall
    // Total: 36 bytes
    let CODE_SIZE = 36
    let MSG_VADDR = CODE_VADDR + CODE_SIZE

    let code = ""
    code = code + hexByte(0xB8) + hexDword(1)              // mov eax, 1
    code = code + hexByte(0xBF) + hexDword(1)              // mov edi, 1
    code = code + hexByte(0x48) + hexByte(0xBE)            // REX.W + mov rsi, imm64
    code = code + hexQword(MSG_VADDR)                       // imm64 = msg vaddr
    code = code + hexByte(0xBA) + hexDword(MSG_LEN)         // mov edx, len
    code = code + hexByte(0x0F) + hexByte(0x05)             // syscall
    code = code + hexByte(0x31) + hexByte(0xFF)             // xor edi, edi
    code = code + hexByte(0xB8) + hexDword(60)              // mov eax, 60
    code = code + hexByte(0x0F) + hexByte(0x05)             // syscall

    let msgHex = hexStr(MSG)
    let segment = code + msgHex
    let SEG_SIZE = CODE_SIZE + MSG_LEN
    let FILE_SIZE = HDR_SIZE + SEG_SIZE

    // ── ELF64 header ─────────────────────────────────────────────────
    let eh = ""
    eh = eh + hexByte(0x7F) + hexByte(0x45) + hexByte(0x4C) + hexByte(0x46)  // 0x7F "ELF"
    eh = eh + hexByte(2) + hexByte(1) + hexByte(1) + hexByte(0)              // class=64, LE, ver, OSABI
    eh = eh + hexPad(8)
    eh = eh + hexWord(2)             // ET_EXEC
    eh = eh + hexWord(0x3E)          // EM_X86_64
    eh = eh + hexDword(1)
    eh = eh + hexQword(CODE_VADDR)   // e_entry
    eh = eh + hexQword(64)           // e_phoff
    eh = eh + hexQword(0)            // e_shoff
    eh = eh + hexDword(0)
    eh = eh + hexWord(64) + hexWord(56) + hexWord(1)
    eh = eh + hexWord(0) + hexWord(0) + hexWord(0)

    // ── Program header ───────────────────────────────────────────────
    let ph = ""
    ph = ph + hexDword(1)              // PT_LOAD
    ph = ph + hexDword(5)              // R+X
    ph = ph + hexQword(0)
    ph = ph + hexQword(VADDR_BASE)
    ph = ph + hexQword(VADDR_BASE)
    ph = ph + hexQword(FILE_SIZE)
    ph = ph + hexQword(FILE_SIZE)
    ph = ph + hexQword(0x1000)

    let elfBytes = eh + ph + segment
    writeBytes("/tmp/hello.elf", elfBytes)
    print("wrote /tmp/hello.elf (" + (len(elfBytes) / 3) + " bytes)")
    emit 0
}
