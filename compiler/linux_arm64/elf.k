// compiler/linux_arm64/elf.k — native aarch64 Linux ELF backend (WIP, milestone 1).
//
// Reads Krypton IR (arg 0), emits a STATIC, syscall-only aarch64 ELF (arg 1).
// It is a CROSS backend: built by the x86 kcc, it runs on x86 and emits aarch64,
// exactly as compiler/linux_x86/elf.k runs on x86 and emits x86. Test the output
// under qemu-user (qemu-aarch64-static + binfmt).
//
// Milestone 1 (this file): lowers kp("string literal") -> write(1, str, len) per
// string, then exit(0). It is the seed of a full backend — grows toward elf.k
// parity (integers, helpers, control flow) next.
//
// aarch64 instruction words (e.g. 0xD2800020) exceed the int/pointer tag ceiling
// (0x7F000000), so EVERY word is emitted byte-wise via two 16-bit halves that
// stay safely in int range. Output uses the same writeBytes "xHH" hex format as
// the x86 backend. Limitation (milestone 1): total program < 4096 bytes so the
// string address fits a single ADD #imm12 (note for the next pass: add MOVK).

func hexByte(n) {
    let HEX = "0123456789ABCDEF"
    let v = n
    if v < 0 { v = v + 256 }
    if v > 255 { v = v % 256 }
    emit "x" + HEX[v / 16] + HEX[v % 16]
}

// Emit one 32-bit instruction given as high16:low16 (each < 65536), little-endian.
func wordHL(hi16, lo16) {
    emit hexByte(lo16 % 256) + hexByte(lo16 / 256) + hexByte(hi16 % 256) + hexByte(hi16 / 256)
}

// movz Xrd, #imm16            base 0xD2800000 (hi16 = 0xD280 = 53888)
func movz(rd, imm) {
    let lowp = imm * 32 + rd
    emit wordHL(53888 + lowp / 65536, lowp % 65536)
}
// movz Xrd, #imm16, LSL #16   base 0xD2A00000 (hi16 = 0xD2A0 = 53920)
func movzHi(rd, imm) {
    let lowp = imm * 32 + rd
    emit wordHL(53920 + lowp / 65536, lowp % 65536)
}
// add Xrd, Xrn, #imm12        base 0x91000000 (hi16 = 0x9100 = 37120)
func addImm(rd, rn, imm) {
    let lowp = imm * 1024 + rn * 32 + rd
    emit wordHL(37120 + lowp / 65536, lowp % 65536)
}
// svc #0                      0xD4000001
func svc0() { emit wordHL(54272, 1) }

// write(1, 0x400000+off, lng).  off < 4096, lng < 65536 (milestone 1).
func emitWrite(off, lng) {
    emit movz(0, 1) + movzHi(1, 64) + addImm(1, 1, off) + movz(2, lng) + movz(8, 64) + svc0()
}
func emitExit(codeVal) {
    emit movz(0, codeVal) + movz(8, 93) + svc0()
}

// --- IR scanning: kp'd string literals ---------------------------------------
// A kp'd string = a `PUSH "..."` line whose next IR line is `BUILTIN kp ...`.
func isKpPush(ir, i) {
    let ln = getLine(ir, i)
    if startsWith(ln, "PUSH \"") {
        let nx = getLine(ir, i + 1)
        if startsWith(nx, "BUILTIN kp") { emit "1" }
    }
    emit "0"
}
func quoted(ln) {
    let q1 = indexOf(ln, "\"")
    emit substring(ln, toInt(q1) + 1, len(ln) - 1)   // PUSH lines end with the closing quote
}
func kpCount(ir) {
    let n = toInt(lineCount(ir))
    let i = 0
    let c = 0
    while i < n {
        if isKpPush(ir, i) == "1" { c = c + 1 }
        i = i + 1
    }
    emit c + ""
}
// idx-th kp'd string content (0-based).
func kpStr(ir, idx) {
    let target = toInt(idx)
    let n = toInt(lineCount(ir))
    let i = 0
    let c = 0
    while i < n {
        if isKpPush(ir, i) == "1" {
            if c == target { emit quoted(getLine(ir, i)) }
            c = c + 1
        }
        i = i + 1
    }
    emit ""
}

// raw string bytes as "xHH" hex, plus a trailing newline (kp = println).
func strBytes(s) {
    let out = ""
    let i = 0
    while i < len(s) {
        out = out + hexByte(charCode(substring(s, i, i + 1)))
        i = i + 1
    }
    emit out + hexByte(10)
}

just run {
    let inFile  = arg("0")
    let outFile = arg("1")
    let ir = readFile(inFile)

    let ns = toInt(kpCount(ir))

    // Layout: 64-byte ELF header + 56-byte phdr = 120. Code = ns writes (24 bytes
    // each) + exit (12). String data follows. vaddr base 0x400000.
    let HDR = 120
    let codeSize = ns * 24 + 12
    let dataStart = HDR + codeSize
    let VBASE = 4194304          // 0x400000
    let entry = VBASE + HDR

    // ---- code ----
    let code = ""
    let i = 0
    let off = dataStart
    while i < ns {
        let s = kpStr(ir, i)
        let lng = len(s) + 1                 // + newline
        code = code + emitWrite(off, lng)
        off = off + lng
        i = i + 1
    }
    code = code + emitExit(0)

    // ---- string data ----
    let data = ""
    i = 0
    while i < ns {
        data = data + strBytes(kpStr(ir, i))
        i = i + 1
    }

    let total = dataStart
    i = 0
    while i < ns { total = total + (len(kpStr(ir, i)) + 1)  i = i + 1 }

    // ---- ELF64 header (aarch64, ET_EXEC) ----
    let eh = hexByte(127) + "x45x4Cx46"      // 7f 'E' 'L' 'F'
    eh = eh + "x02x01x01x00" + "x00x00x00x00x00x00x00x00"  // class64,LE,ver,SYSV + pad
    eh = eh + "x02x00" + "xB7x00" + "x01x00x00x00"          // ET_EXEC, EM_AARCH64, e_version
    eh = eh + le8(entry) + le8(64) + le8(0)                 // e_entry, e_phoff=64, e_shoff=0
    eh = eh + "x00x00x00x00"                                // e_flags
    eh = eh + "x40x00" + "x38x00" + "x01x00"                // ehsize=64, phentsize=56, phnum=1
    eh = eh + "x00x00" + "x00x00" + "x00x00"                // shentsize, shnum, shstrndx

    // ---- program header PT_LOAD (R+X) ----
    let ph = "x01x00x00x00" + "x05x00x00x00"                // p_type=PT_LOAD, p_flags=R+X
    ph = ph + le8(0) + le8(VBASE) + le8(VBASE)              // p_offset, p_vaddr, p_paddr
    ph = ph + le8(total) + le8(total) + le8(65536)          // p_filesz, p_memsz, p_align

    writeBytes(outFile, eh + ph + code + data)
}

// little-endian 8-byte (64-bit) value as "xHH" hex. v fits well under 2^31 here.
func le8(v) {
    let out = ""
    let x = v
    let k = 0
    while k < 8 {
        out = out + hexByte(x % 256)
        x = x / 256
        k = k + 1
    }
    emit out
}
