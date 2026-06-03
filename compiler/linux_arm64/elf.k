// compiler/linux_arm64/elf.k — native aarch64 Linux ELF backend (WIP).
//
// Cross backend: built by the x86 kcc, runs on x86, emits aarch64. Reads Krypton
// IR (arg 0), writes a static syscall-only aarch64 ELF (arg 1). Test under qemu.
//
// Milestone 2: a real stack machine. Integers + arithmetic (+ - * / %), locals
// (STORE/LOAD), and the kr_str_int / kr_print runtime helpers, so it compiles
// programs that compute and print numbers — e.g. kp(2 + 3 * 4) -> "14". kp also
// still prints string literals (kp dispatches on the int/pointer tag at 0x400000).
// Control flow (LABEL/JUMP/comparisons) is the next milestone.
//
// aarch64 words exceed the int ceiling (0x7F000000), so each is emitted byte-wise
// via two 16-bit halves (wordHL). Operand stack = register x20 (grows down);
// locals base = x19; helpers called via BL (return in x30, leaf, don't touch x19/x20).

func hexByte(n) {
    let HEX = "0123456789ABCDEF"
    let v = n
    if v < 0 { v = v + 256 }
    if v > 255 { v = v % 256 }
    emit "x" + HEX[v / 16] + HEX[v % 16]
}
// one 32-bit instruction as high16:low16 (each < 65536), little-endian.
func wordHL(hi16, lo16) {
    emit hexByte(lo16 % 256) + hexByte(lo16 / 256) + hexByte(hi16 % 256) + hexByte(hi16 / 256)
}

// ── instruction encoders (validated against qemu) ────────────────────────────
func e_movz(rd, imm)   { let p = imm * 32 + rd  emit wordHL(53888 + p / 65536, p % 65536) } // movz Xd,#imm
func e_movk16(rd, imm) { let p = imm * 32 + rd  emit wordHL(62112 + p / 65536, p % 65536) } // movk Xd,#imm,lsl16
func e_movzHi(rd, imm) { let p = imm * 32 + rd  emit wordHL(53920 + p / 65536, p % 65536) } // movz Xd,#imm,lsl16
func e_addi(rd, rn, imm) { let p = imm * 1024 + rn * 32 + rd  emit wordHL(37120 + p / 65536, p % 65536) }
func e_subi(rd, rn, imm) { let p = imm * 1024 + rn * 32 + rd  emit wordHL(53504 + p / 65536, p % 65536) }
func e_str0(rt, rn)  { let p = rn * 32 + rt  emit wordHL(63744, p) }                 // str Xt,[Xn]
func e_ldr0(rt, rn)  { let p = rn * 32 + rt  emit wordHL(63808, p) }                 // ldr Xt,[Xn]
func e_strIdx(rt, rn, slot) { let p = slot * 2048 + rn * 32 + rt  emit wordHL(63744 + p / 65536, p % 65536) }
func e_ldrIdx(rt, rn, slot) { let p = slot * 2048 + rn * 32 + rt  emit wordHL(63808 + p / 65536, p % 65536) }
func e_addr(rd, rn, rm) { emit wordHL(35584 + rm, rn * 32 + rd) }                    // add Xd,Xn,Xm
func e_subr(rd, rn, rm) { emit wordHL(51968 + rm, rn * 32 + rd) }                    // sub Xd,Xn,Xm
func e_mul(rd, rn, rm)  { let p = 31744 + rn * 32 + rd  emit wordHL(39680 + rm + p / 65536, p % 65536) }
func e_udiv(rd, rn, rm) { let p = 2048 + rn * 32 + rd   emit wordHL(39616 + rm + p / 65536, p % 65536) }
func e_msub(rd, rn, rm, ra) { let p = 32768 + ra * 1024 + rn * 32 + rd  emit wordHL(39680 + rm + p / 65536, p % 65536) }
func e_cmp(rn, rm)   { let p = rn * 32 + 31  emit wordHL(60160 + rm + p / 65536, p % 65536) } // subs xzr,Xn,Xm
func e_movr(rd, rm)  { let p = 992 + rd  emit wordHL(43520 + rm + p / 65536, p % 65536) }     // mov Xd,Xm
func e_strb(wt, xn)  { let p = xn * 32 + wt  emit wordHL(14592, p) }                 // strb Wt,[Xn]
func e_ldrbO(wt, xn, xm) { let p = 26624 + xn * 32 + wt  emit wordHL(14432 + xm + p / 65536, p % 65536) }
func e_ret() { emit wordHL(54879, 960) }
func e_svc() { emit wordHL(54272, 1) }
// branches: off = target - this instruction, in bytes (multiple of 4)
func e_b(off)  { let q = off / 4  if q < 0 { q = q + 67108864 }  emit wordHL(5120 + q / 65536, q % 65536) }
func e_bl(off) { let q = off / 4  if q < 0 { q = q + 67108864 }  emit wordHL(37888 + q / 65536, q % 65536) }
func e_cbz(rt, off)  { let q = off / 4  if q < 0 { q = q + 524288 }  let p = q * 32 + rt  emit wordHL(46080 + p / 65536, p % 65536) }
func e_cbnz(rt, off) { let q = off / 4  if q < 0 { q = q + 524288 }  let p = q * 32 + rt  emit wordHL(46336 + p / 65536, p % 65536) }
func e_bhs(off) { let q = off / 4  if q < 0 { q = q + 524288 }  let p = q * 32 + 2  emit wordHL(21504 + p / 65536, p % 65536) }

// composites
func c_push() { emit e_subi(20, 20, 16) + e_str0(0, 20) }      // push x0
func c_pop0() { emit e_ldr0(0, 20) + e_addi(20, 20, 16) }      // pop -> x0
func c_pop1() { emit e_ldr0(1, 20) + e_addi(20, 20, 16) }      // pop -> x1
func c_loadImm(v) {                                            // x0 = v (32-bit)
    emit e_movz(0, v % 65536) + e_movk16(0, v / 65536)
}

// ── runtime helpers (ported from the validated prototype) ────────────────────
// kr_str_int: x0=value(>=0) -> x0 = ptr to NUL-terminated decimal in scratch.
func emitStrInt(scr) {
    let lo = scr % 65536
    let hi = scr / 65536
    let c = e_movz(1, lo) + e_movk16(1, hi) + e_addi(1, 1, 31) + e_movz(4, 10) + e_strb(31, 1)
    c = c + e_cbnz(0, 24)                                                  // if x0!=0 -> .loop
    c = c + e_subi(1, 1, 1) + e_movz(2, 48) + e_strb(2, 1) + e_movr(0, 1) + e_ret()   // zero
    c = c + e_udiv(3, 0, 4) + e_msub(5, 3, 4, 0) + e_addi(5, 5, 48) + e_subi(1, 1, 1)
    c = c + e_strb(5, 1) + e_movr(0, 3) + e_cbnz(0, 0 - 24) + e_movr(0, 1) + e_ret()  // .loop
    emit c
}
// kr_print: x0=ptr -> write the NUL-terminated string then a newline.
func emitPrint(nl) {
    let lo = nl % 65536
    let hi = nl / 65536
    let c = e_movr(1, 0) + e_movz(2, 0)
    c = c + e_ldrbO(3, 1, 2) + e_cbz(3, 12) + e_addi(2, 2, 1) + e_b(0 - 12)           // strlen
    c = c + e_movz(0, 1) + e_movz(8, 64) + e_svc()                                    // write(1,buf,len)
    c = c + e_movz(1, lo) + e_movk16(1, hi) + e_movz(2, 1) + e_movz(0, 1) + e_movz(8, 64) + e_svc() + e_ret()
    emit c
}

// ── IR helpers ───────────────────────────────────────────────────────────────
func opcode(ln) {                       // first token of an IR line
    let p = indexOf(ln, " ")
    if p < 0 { emit ln }
    emit substring(ln, 0, toInt(p))
}
func operand(ln) {                      // text after the first space
    let p = indexOf(ln, " ")
    if p < 0 { emit "" }
    emit substring(ln, toInt(p) + 1, len(ln))
}
func isStrPush(ln) {                     // PUSH "..."
    if startsWith(ln, "PUSH \"") { emit "1" }
    emit "0"
}
func quoted(ln) {
    let q1 = indexOf(ln, "\"")
    emit substring(ln, toInt(q1) + 1, len(ln) - 1)
}
// local slot for `name`, scanning LOCAL declarations in order.
func localSlot(ir, name) {
    let n = toInt(lineCount(ir))
    let i = 0
    let slot = 0
    while i < n {
        let ln = getLine(ir, i)
        if startsWith(ln, "LOCAL ") {
            if operand(ln) == name { emit slot + "" }
            slot = slot + 1
        }
        i = i + 1
    }
    emit "0"
}

// byte size each op lowers to (must equal the emit below).
func opSize(ln) {
    let op = opcode(ln)
    if op == "FUNC"    { emit 12 }       // prologue
    if op == "END"     { emit 12 }       // exit(0)
    if op == "LOCAL"   { emit 0 }
    if op == "PUSH"    { emit 16 }       // load imm/addr (2) + push (2)
    if op == "STORE"   { emit 12 }
    if op == "LOAD"    { emit 12 }
    if op == "ADD"     { emit 28 }
    if op == "SUB"     { emit 28 }
    if op == "MUL"     { emit 28 }
    if op == "DIV"     { emit 28 }
    if op == "MOD"     { emit 32 }
    if op == "POP"     { emit 4 }
    if op == "BUILTIN" {
        let b = operand(ln)
        if startsWith(b, "kp") { emit 28 }
        if startsWith(b, "gcShadowCount") { emit 12 }
        if startsWith(b, "gcShadowPop") { emit 16 }
        emit 0
    }
    emit 0
}

just run {
    let inFile  = arg("0")
    let outFile = arg("1")
    let ir = readFile(inFile)
    let nlines = toInt(lineCount(ir))

    let HDR = 120

    // ── pass 1: code size + string-literal layout ────────────────────────────
    let codeSize = 0
    let i = 0
    while i < nlines {
        codeSize = codeSize + toInt(opSize(getLine(ir, i)))
        i = i + 1
    }
    // helpers + scratch + newline, then string data.
    let strIntOff = HDR + codeSize
    let printOff  = strIntOff + 80
    let scratchOff = printOff + 64
    let nlOff = scratchOff + 32
    let dataOff = nlOff + 1
    let VBASE = 4194304

    // ── pass 2: emit code ────────────────────────────────────────────────────
    let code = ""
    let off = HDR                          // current byte offset (== vaddr offset)
    let sidx = 0                           // running string-literal index
    let strCursor = dataOff                // next string's data offset
    i = 0
    while i < nlines {
        let ln = getLine(ir, i)
        let op = opcode(ln)
        if op == "FUNC" {
            code = code + e_subi(31, 31, 2048) + e_addi(19, 31, 0) + e_addi(20, 31, 2048)
            off = off + 12
        }
        if op == "PUSH" {
            if isStrPush(ln) == "1" {
                let s = quoted(ln)
                // this string's vaddr offset:
                let sOff = dataOff
                let j = 0
                let k = 0
                while j < nlines {
                    let lj = getLine(ir, j)
                    if isStrPush(lj) == "1" {
                        if k == sidx { j = nlines }
                        else { sOff = sOff + (len(quoted(lj)) + 1)  k = k + 1 }
                    }
                    j = j + 1
                }
                let sa = VBASE + sOff
                code = code + e_movz(0, sa % 65536) + e_movk16(0, sa / 65536) + c_push()
                sidx = sidx + 1
            } else {
                code = code + c_loadImm(toInt(operand(ln))) + c_push()
            }
            off = off + 16
        }
        if op == "STORE" { code = code + c_pop0() + e_strIdx(0, 19, toInt(localSlot(ir, operand(ln))))  off = off + 12 }
        if op == "LOAD"  { code = code + e_ldrIdx(0, 19, toInt(localSlot(ir, operand(ln)))) + c_push()   off = off + 12 }
        if op == "ADD" { code = code + c_pop1() + c_pop0() + e_addr(0, 0, 1) + c_push()  off = off + 28 }
        if op == "SUB" { code = code + c_pop1() + c_pop0() + e_subr(0, 0, 1) + c_push()  off = off + 28 }
        if op == "MUL" { code = code + c_pop1() + c_pop0() + e_mul(0, 0, 1) + c_push()   off = off + 28 }
        if op == "DIV" { code = code + c_pop1() + c_pop0() + e_udiv(0, 0, 1) + c_push()  off = off + 28 }
        if op == "MOD" { code = code + c_pop1() + c_pop0() + e_udiv(2, 0, 1) + e_msub(0, 2, 1, 0) + c_push()  off = off + 32 }
        if op == "POP" { code = code + e_addi(20, 20, 16)  off = off + 4 }
        if op == "BUILTIN" {
            let b = operand(ln)
            if startsWith(b, "kp") {
                code = code + c_pop0() + e_movzHi(9, 64) + e_cmp(0, 9) + e_bhs(8)
                code = code + e_bl(strIntOff - (off + 20)) + e_bl(printOff - (off + 24))
                off = off + 28
            }
            if startsWith(b, "gcShadowCount") { code = code + e_movz(0, 0) + c_push()  off = off + 12 }
            if startsWith(b, "gcShadowPop") { code = code + e_addi(20, 20, 16) + e_movz(0, 0) + c_push()  off = off + 16 }
        }
        if op == "END" { code = code + e_movz(0, 0) + e_movz(8, 93) + e_svc()  off = off + 12 }
        i = i + 1
    }

    // helpers (returned bytes appended after main code); scratch/nl as full vaddrs
    let body = code + emitStrInt(VBASE + scratchOff) + emitPrint(VBASE + nlOff)

    // string data + scratch + newline
    let data = ""
    let z = 0
    while z < 32 { data = data + hexByte(0)  z = z + 1 }      // scratch
    data = data + hexByte(10)                                  // newline
    // string literals in order
    i = 0
    while i < nlines {
        let ln = getLine(ir, i)
        if isStrPush(ln) == "1" {
            let s = quoted(ln)
            let c = 0
            while c < len(s) { data = data + hexByte(charCode(substring(s, c, c + 1)))  c = c + 1 }
            data = data + hexByte(0)
        }
        i = i + 1
    }

    let total = dataOff + (countStrBytes(ir))

    // ELF64 header (aarch64, ET_EXEC) + PT_LOAD (RWX, scratch is writable)
    let eh = hexByte(127) + "x45x4Cx46" + "x02x01x01x00" + "x00x00x00x00x00x00x00x00"
    eh = eh + "x02x00" + "xB7x00" + "x01x00x00x00"
    eh = eh + le8(VBASE + HDR) + le8(64) + le8(0)
    eh = eh + "x00x00x00x00" + "x40x00" + "x38x00" + "x01x00" + "x00x00" + "x00x00" + "x00x00"
    let ph = "x01x00x00x00" + "x07x00x00x00"
    ph = ph + le8(0) + le8(VBASE) + le8(VBASE) + le8(total) + le8(total) + le8(65536)

    writeBytes(outFile, eh + ph + body + data)
}

func countStrBytes(ir) {
    let n = toInt(lineCount(ir))
    let i = 0
    let t = 33                              // 32 scratch + 1 newline
    while i < n {
        let ln = getLine(ir, i)
        if isStrPush(ln) == "1" { t = t + (len(quoted(ln)) + 1) }
        i = i + 1
    }
    emit t + ""
}

func le8(v) {
    let out = ""
    let x = v
    let k = 0
    while k < 8 { out = out + hexByte(x % 256)  x = x / 256  k = k + 1 }
    emit out
}
