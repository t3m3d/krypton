// compiler/linux_arm64/elf.k — native aarch64 Linux ELF backend (WIP).
//
// Cross backend: built by the x86 kcc, runs on x86, emits aarch64. Reads Krypton
// IR (arg 0), writes a static syscall-only aarch64 ELF (arg 1). Test under qemu.
//
// Status (M1-M5): a real stack machine with integers + arithmetic (+ - * / %),
// string interpolation (CAT/ADD via kr_plus), locals, control flow (loops/ifs),
// and USER FUNCTIONS with recursion (call frames on sp, op stack in x20, heap in
// x22). Compiles real programs: factorial/fib recursion, nested calls, kp("n="+n).
// kp dispatches int vs string on the 0x7F000000 tag.
//
// NOTE: kp's bytes are built via a local sbAppend, NOT consecutive `code = code + ..`
// statements — the x86 backend (elf_host) miscompiles 3+ consecutive `+=`-style
// string appends in a deeply-nested block (drops/dupes instructions). Print-heavy
// programs now work to ~1000s of lines. Still missing many stdlib builtins
// (substring/charCode/len/toInt/range/...) and the main `code` accumulator is still
// O(n^2) `+` (crashes the backend on ~5000+ op programs) — both future work.
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
func e_cmpi0(rn) { let p = rn * 32 + 31  emit wordHL(61696 + p / 65536, p % 65536) }          // cmp Xn,#0
func e_cset(rd, cc) { let p = 2016 + cc * 4096 + rd  emit wordHL(39583 + p / 65536, p % 65536) } // cset Xd (csinc cond=cc)
func e_movr(rd, rm)  { let p = 992 + rd  emit wordHL(43520 + rm + p / 65536, p % 65536) }     // mov Xd,Xm
func e_strb(wt, xn)  { let p = xn * 32 + wt  emit wordHL(14592, p) }                 // strb Wt,[Xn]
func e_ldrbO(wt, xn, xm) { let p = 26624 + xn * 32 + wt  emit wordHL(14432 + xm + p / 65536, p % 65536) }
func e_ldrb0(wt, xn) { let p = xn * 32 + wt  emit wordHL(14656, p) }                 // ldrb Wt,[Xn]
func e_strbO(wt, xn, off) { let p = off * 1024 + xn * 32 + wt  emit wordHL(14592 + p / 65536, p % 65536) } // strb Wt,[Xn,#off]
func e_str8(rt, rn, off8) { let p = off8 * 1024 + rn * 32 + rt  emit wordHL(63744 + p / 65536, p % 65536) } // str Xt,[Xn,#off8*8]
func e_ldr8(rt, rn, off8) { let p = off8 * 1024 + rn * 32 + rt  emit wordHL(63808 + p / 65536, p % 65536) } // ldr Xt,[Xn,#off8*8]
func e_ret() { emit wordHL(54879, 960) }
func e_svc() { emit wordHL(54272, 1) }
// branches: off = target - this instruction, in bytes (multiple of 4)
func e_b(dsp)  { let q = dsp / 4  if q < 0 { q = q + 67108864 }  emit wordHL(5120 + q / 65536, q % 65536) }
func e_bl(dsp) { let q = dsp / 4  if q < 0 { q = q + 67108864 }  emit wordHL(37888 + q / 65536, q % 65536) }
func e_cbz(rt, dsp)  { let q = dsp / 4  if q < 0 { q = q + 524288 }  let p = q * 32 + rt  emit wordHL(46080 + p / 65536, p % 65536) }
func e_cbnz(rt, dsp) { let q = dsp / 4  if q < 0 { q = q + 524288 }  let p = q * 32 + rt  emit wordHL(46336 + p / 65536, p % 65536) }
func e_bhs(dsp) { let q = dsp / 4  if q < 0 { q = q + 524288 }  let p = q * 32 + 2  emit wordHL(21504 + p / 65536, p % 65536) }

// composites
func c_push() { emit e_subi(20, 20, 16) + e_str0(0, 20) }      // push x0
func c_pop0() { emit e_ldr0(0, 20) + e_addi(20, 20, 16) }      // pop -> x0
func c_pop1() { emit e_ldr0(1, 20) + e_addi(20, 20, 16) }      // pop -> x1
func c_loadImm(v) {                                            // x0 = v (32-bit)
    emit e_movz(0, v % 65536) + e_movk16(0, v / 65536)
}

// ── runtime helpers (ported from the validated prototype) ────────────────────
// Heap = BSS above the file; x22 = bump pointer (set in the prologue).
// kr_alloc: x0=size -> x0=ptr, bumps x22. Leaf (uses x15).
func emitAlloc() {
    emit e_movr(15, 22) + e_addr(22, 22, 0) + e_movr(0, 15) + e_ret()
}
// kr_str_int: x0=value(>=0) -> x0 = ptr to NUL-term decimal in a FRESH heap buffer
// (heap-allocated so two conversions can coexist during concat). Saves lr in x24;
// allocOff/thisOff are byte offsets, BL disp = allocOff-(thisOff+12).
func emitStrInt(allocOff, thisOff) {
    let c = e_movr(24, 30) + e_movr(10, 0) + e_movz(0, 24)            // save lr, val; size=24
    c = c + e_bl(allocOff - (thisOff + 12))                          // bl kr_alloc -> x0=buf
    c = c + e_addi(1, 0, 23) + e_movr(0, 10) + e_movz(4, 10) + e_strb(31, 1)  // x1=buf+23; x0=val; *x1=NUL
    c = c + e_cbnz(0, 28)                                            // x0!=0 -> .loop (idx15)
    c = c + e_subi(1, 1, 1) + e_movz(2, 48) + e_strb(2, 1) + e_movr(0, 1) + e_movr(30, 24) + e_ret()  // "0"
    c = c + e_udiv(3, 0, 4) + e_msub(5, 3, 4, 0) + e_addi(5, 5, 48) + e_subi(1, 1, 1)  // .loop
    c = c + e_strb(5, 1) + e_movr(0, 3) + e_cbnz(0, 0 - 24) + e_movr(0, 1) + e_movr(30, 24) + e_ret()
    emit c
}
// kr_plus(a=x0, b=x1) -> x0. Polymorphic +: both ints -> a+b; else convert each
// to a string (kr_str_int for the int side) and concat into a fresh heap buffer.
// Saves lr in x23; VBASE in x9; sa=x11 sb=x12 b=x13 lenA=x14 lenB=x16 dst=x17.
func emitPlus(strIntOff, allocOff, thisOff) {
    let c = e_movr(23, 30) + e_movzHi(9, 32512)                                       // lr; x9=VBASE
    c = c + e_cmp(0, 9) + e_bhs(24) + e_cmp(1, 9) + e_bhs(16)                      // either >=VBASE -> concat
    c = c + e_addr(0, 0, 1) + e_movr(30, 23) + e_ret()                            // both int: a+b
    c = c + e_movr(13, 1)                                                          // [cc] x13=b
    c = c + e_cmp(0, 9) + e_bhs(8) + e_bl(strIntOff - (thisOff + 48))             // conv a
    c = c + e_movr(11, 0)                                                          // [as] sa
    c = c + e_movr(0, 13) + e_cmp(0, 9) + e_bhs(8) + e_bl(strIntOff - (thisOff + 68))  // conv b
    c = c + e_movr(12, 0)                                                          // [bs] sb
    c = c + e_movz(14, 0) + e_ldrbO(3, 11, 14) + e_cbz(3, 12) + e_addi(14, 14, 1) + e_b(0 - 12)  // strlen sa
    c = c + e_movz(16, 0) + e_ldrbO(3, 12, 16) + e_cbz(3, 12) + e_addi(16, 16, 1) + e_b(0 - 12)  // strlen sb
    c = c + e_addr(0, 14, 16) + e_addi(0, 0, 1) + e_bl(allocOff - (thisOff + 124)) + e_movr(17, 0)  // dst=alloc(lenA+lenB+1)
    c = c + e_movz(2, 0) + e_cmp(2, 14) + e_bhs(24) + e_ldrbO(3, 11, 2) + e_strb(3, 0) + e_addi(0, 0, 1) + e_addi(2, 2, 1) + e_b(0 - 24)  // copy sa
    c = c + e_movz(2, 0) + e_cmp(2, 16) + e_bhs(24) + e_ldrbO(3, 12, 2) + e_strb(3, 0) + e_addi(0, 0, 1) + e_addi(2, 2, 1) + e_b(0 - 24)  // copy sb
    c = c + e_strb(31, 0) + e_movr(0, 17) + e_movr(30, 23) + e_ret()              // NUL; return dst
    emit c
}
// kp dispatch, extracted from the driver so the huge `just run` stays small enough
// for the x86 backend to compile correctly (a large-function miscompile drops/garbles
// statements). Pops arg; pointer -> print, int -> kr_str_int then print; push dummy 0.
// kp dispatch helper (x0 = value in; prints it; preserves x20/x19). The op-stack
// pop/push stays in the driver — only the x20-free dispatch lives here, since
// add/sub x20 inside an emit* helper triggers an x86-backend miscompile. 32 bytes.
func emitKpDisp(thisOff, siOff, prOff) {
    let c = e_movr(25, 30)
    c = c + e_movzHi(9, 32512)
    c = c + e_cmp(0, 9)
    c = c + e_bhs(8)
    c = c + e_bl(siOff - (thisOff + 16))
    c = c + e_bl(prOff - (thisOff + 20))
    c = c + e_movr(30, 25)
    c = c + e_ret()
    emit c
}
// kr_atoi: x0=string ptr -> x0=parsed non-negative int (stops at NUL/non-digit).
func emitAtoi() {
    let c = e_movr(1, 0) + e_movz(0, 0) + e_movz(4, 10)        // x1=ptr, x0=0, x4=10
    c = c + e_ldrb0(2, 1) + e_cbz(2, 24)                       // .loop: w2=[x1]; 0 -> .done
    c = c + e_mul(0, 0, 4) + e_subi(2, 2, 48) + e_addr(0, 0, 2) // x0 = x0*10 + (c-'0')
    c = c + e_addi(1, 1, 1) + e_b(0 - 24)                      // x1++; -> .loop
    c = c + e_ret()                                            // .done: ret
    emit c
}
// kr_print: x0=ptr -> write the NUL-terminated string then a newline.
func emitPrint(nlOff) {
    let lo = nlOff % 65536
    let hi = 32512 + nlOff / 65536              // fold the 0x7F000000 load base
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
// "FUNC add 2" -> "add" ; "CALL add 2" -> "add"
func headName(ln) {
    let rest = operand(ln)
    let p = indexOf(rest, " ")
    if p < 0 { emit rest }
    emit substring(rest, 0, toInt(p))
}
// "FUNC add 2" -> "2"
func funcArgc(ln) {
    let rest = operand(ln)
    let p = indexOf(rest, " ")
    if p < 0 { emit "0" }
    emit substring(rest, toInt(p) + 1, len(rest))
}
// count PARAM+LOCAL slots of the function starting at line fStart.
func countLocals(ir, fStart) {
    let n = toInt(lineCount(ir))
    let i = fStart + 1
    let c = 0
    while i < n {
        let op = opcode(getLine(ir, i))
        if op == "FUNC" { emit c + "" }
        if op == "END"  { emit c + "" }
        if op == "PARAM" { c = c + 1 }
        if op == "LOCAL" { c = c + 1 }
        i = i + 1
    }
    emit c + ""
}
// slot index of `name` within the function at fStart (PARAM then LOCAL, in order).
func localSlotIn(ir, fStart, name) {
    let n = toInt(lineCount(ir))
    let i = fStart + 1
    let slot = 0
    while i < n {
        let ln = getLine(ir, i)
        let op = opcode(ln)
        if op == "FUNC" { emit "0" }
        if op == "END"  { emit "0" }
        if op == "PARAM" { if operand(ln) == name { emit slot + "" }  slot = slot + 1 }
        if op == "LOCAL" { if operand(ln) == name { emit slot + "" }  slot = slot + 1 }
        i = i + 1
    }
    emit "0"
}
// byte size of IR line i, WITH function context (FUNC=prologue, RETURN/END=epilogue).
func opBytes(ir, i) {
    let ln = getLine(ir, i)
    let op = opcode(ln)
    if op == "FUNC"   { emit (5 + 3 * toInt(funcArgc(ln))) * 4 + "" }   // prologue
    if op == "PARAM"  { emit "0" }
    if op == "LOCAL"  { emit "0" }
    if op == "RETURN" { emit "20" }                                    // epilogue
    if op == "END"    { emit "20" }                                    // epilogue
    if op == "CALL"   { emit "4" }                                     // bl
    emit toInt(opSize(ln)) + ""
}
// absolute byte offset of LABEL `name` (walks _start + all function code).
func labelAbsOffset(ir, name) {
    let n = toInt(lineCount(ir))
    let i = 0
    let off = 152                       // HDR(120) + _start(32)
    while i < n {
        let ln = getLine(ir, i)
        if opcode(ln) == "LABEL" {
            if operand(ln) == name { emit off + "" }
        }
        off = off + toInt(opBytes(ir, i))
        i = i + 1
    }
    emit "0"
}
// absolute byte offset of FUNC `name`.
func funcVaddrOf(ir, name) {
    let n = toInt(lineCount(ir))
    let i = 0
    let off = 152
    while i < n {
        let ln = getLine(ir, i)
        if opcode(ln) == "FUNC" {
            if headName(ln) == name { emit off + "" }
        }
        off = off + toInt(opBytes(ir, i))
        i = i + 1
    }
    emit "0"
}
// byte size of a non-structural op (body of a function).
func opSize(ln) {
    let op = opcode(ln)
    if op == "PUSH"    { emit 16 }
    if op == "STORE"   { emit 12 }
    if op == "LOAD"    { emit 12 }
    if op == "ADD"     { emit 28 }
    if op == "CAT"     { emit 28 }
    if op == "SUB"     { emit 28 }
    if op == "MUL"     { emit 28 }
    if op == "DIV"     { emit 28 }
    if op == "MOD"     { emit 32 }
    if op == "POP"     { emit 4 }
    if op == "LABEL"     { emit 0 }
    if op == "JUMP"      { emit 4 }
    if op == "JUMPIFNOT" { emit 12 }
    if op == "LT" || op == "GT" || op == "EQ" || op == "NEQ" || op == "LTE" || op == "GTE" { emit 32 }
    if op == "BUILTIN" {
        let b = operand(ln)
        if startsWith(b, "kp") { emit 20 }   // pop + bl kpDisp + push (no movz between bl and push)
        if startsWith(b, "gcShadowCount") { emit 12 }
        if startsWith(b, "gcShadowPush") { emit 16 }
        if startsWith(b, "gcShadowPop") { emit 16 }
        if startsWith(b, "charCode") { emit 20 }
        if startsWith(b, "len") { emit 40 }
        if startsWith(b, "toStr") { emit 32 }
        if startsWith(b, "toInt") { emit 20 }
        if startsWith(b, "fromCharCode") { emit 36 }
        if startsWith(b, "isTruthy") { emit 24 }
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
    let START = 32                       // _start size (2x movz/movk + bl + 3 exit)

    // total function code size (multi-function, context-aware)
    let codeSize = 0
    let i = 0
    while i < nlines { codeSize = codeSize + toInt(opBytes(ir, i))  i = i + 1 }

    let allocOff  = HDR + START + codeSize
    let strIntOff = allocOff + 16
    let plusOff   = strIntOff + 100
    let printOff  = plusOff + 212
    let kpDispOff = printOff + 64
    let atoiOff = kpDispOff + 32
    let nlOff = atoiOff + 44
    let dataOff = nlOff + 1
    // Load base = 0x7F000000 (= 32512<<16) so the int/pointer threshold is high
    // enough for real ints (matches the x86 backend). The backend itself can't hold
    // a >=0x7F000000 value (its own int ceiling), so all addresses stay as OFFSETS
    // and 0x7F00 is folded into the movk high half at emit time.

    let strBytes = 0
    i = 0
    while i < nlines {
        let l0 = getLine(ir, i)
        if isStrPush(l0) == "1" { strBytes = strBytes + (len(quoted(l0)) + 1) }
        i = i + 1
    }
    let total = dataOff + strBytes
    let heapOff = (total + 15) / 16 * 16            // heap start (offset from load base)
    let opOff = heapOff + 1048576 + 65536           // x20 start = heap + 1 MiB + 64 KiB

    // ── _start: x20=op stack, x22=heap, bl __main__, exit(0) ──────────────────
    let mainOff = toInt(funcVaddrOf(ir, "__main__"))
    let code = e_movz(20, opOff % 65536) + e_movk16(20, 32512 + opOff / 65536)
    code = code + e_movz(22, heapOff % 65536) + e_movk16(22, 32512 + heapOff / 65536)
    code = code + e_bl(mainOff - (HDR + 16))
    code = code + e_movz(0, 0) + e_movz(8, 93) + e_svc()
    let off = HDR + START

    // ── functions: each gets a frame on sp (x19=locals base); op stack is x20 ──
    let curF = 0
    let frame = 0
    let sidx = 0
    i = 0
    while i < nlines {
        let ln = getLine(ir, i)
        let op = opcode(ln)
        if op == "FUNC" {
            curF = i
            let argc = toInt(funcArgc(ln))
            frame = toInt(countLocals(ir, i)) * 16
            code = code + e_subi(31, 31, 16) + e_str0(19, 31) + e_str8(30, 31, 1)   // save x19, x30
            code = code + e_subi(31, 31, frame) + e_addi(19, 31, 0)                 // alloc locals, x19=sp
            let p = 0
            while p < argc {                                                        // pop args -> param slots
                code = code + e_ldr0(0, 20) + e_addi(20, 20, 16) + e_strIdx(0, 19, argc - 1 - p)
                p = p + 1
            }
            off = off + (5 + 3 * argc) * 4
        }
        if op == "PUSH" {
            if isStrPush(ln) == "1" {
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
                code = code + e_movz(0, sOff % 65536) + e_movk16(0, 32512 + sOff / 65536) + c_push()
                sidx = sidx + 1
            } else {
                code = code + c_loadImm(toInt(operand(ln))) + c_push()
            }
            off = off + 16
        }
        if op == "STORE" { code = code + c_pop0() + e_strIdx(0, 19, toInt(localSlotIn(ir, curF, operand(ln))))  off = off + 12 }
        if op == "LOAD"  { code = code + e_ldrIdx(0, 19, toInt(localSlotIn(ir, curF, operand(ln)))) + c_push()   off = off + 12 }
        if op == "ADD" { code = code + c_pop1() + c_pop0() + e_bl(plusOff - (off + 16)) + c_push()  off = off + 28 }  // polymorphic via kr_plus
        if op == "CAT" { code = code + c_pop1() + c_pop0() + e_bl(plusOff - (off + 16)) + c_push()  off = off + 28 }  // template-string concat via kr_plus
        if op == "SUB" { code = code + c_pop1() + c_pop0() + e_subr(0, 0, 1) + c_push()  off = off + 28 }
        if op == "MUL" { code = code + c_pop1() + c_pop0() + e_mul(0, 0, 1) + c_push()   off = off + 28 }
        if op == "DIV" { code = code + c_pop1() + c_pop0() + e_udiv(0, 0, 1) + c_push()  off = off + 28 }
        if op == "MOD" { code = code + c_pop1() + c_pop0() + e_udiv(2, 0, 1) + e_msub(0, 2, 1, 0) + c_push()  off = off + 32 }
        if op == "POP" { code = code + e_addi(20, 20, 16)  off = off + 4 }
        if op == "LT"  { code = code + c_pop1() + c_pop0() + e_cmp(0, 1) + e_cset(0, 10) + c_push()  off = off + 32 }
        if op == "GT"  { code = code + c_pop1() + c_pop0() + e_cmp(0, 1) + e_cset(0, 13) + c_push()  off = off + 32 }
        if op == "EQ"  { code = code + c_pop1() + c_pop0() + e_cmp(0, 1) + e_cset(0, 1) + c_push()   off = off + 32 }
        if op == "NEQ" { code = code + c_pop1() + c_pop0() + e_cmp(0, 1) + e_cset(0, 0) + c_push()   off = off + 32 }
        if op == "LTE" { code = code + c_pop1() + c_pop0() + e_cmp(0, 1) + e_cset(0, 12) + c_push()  off = off + 32 }
        if op == "GTE" { code = code + c_pop1() + c_pop0() + e_cmp(0, 1) + e_cset(0, 11) + c_push()  off = off + 32 }
        if op == "JUMP" { code = code + e_b(toInt(labelAbsOffset(ir, operand(ln))) - off)  off = off + 4 }
        if op == "JUMPIFNOT" { code = code + c_pop0() + e_cbz(0, toInt(labelAbsOffset(ir, operand(ln))) - (off + 8))  off = off + 12 }
        if op == "CALL" { code = code + e_bl(toInt(funcVaddrOf(ir, headName(ln))) - off)  off = off + 4 }
        if op == "BUILTIN" {
            let b = operand(ln)
            if startsWith(b, "isTruthy") { code = code + c_pop0() + e_cmpi0(0) + e_cset(0, 0) + c_push()  off = off + 24 }
            if startsWith(b, "kp") {
                let kc = sbNew()
                kc = sbAppend(kc, c_pop0())                         // pop arg -> x0
                kc = sbAppend(kc, e_bl(kpDispOff - (off + 8)))      // dispatch + print
                kc = sbAppend(kc, c_push())                         // push dummy (IR POPs it)
                code = code + sbToString(kc)
                off = off + 20
            }
            if startsWith(b, "gcShadowCount") { code = code + e_movz(0, 0) + c_push()  off = off + 12 }
            if startsWith(b, "gcShadowPush") { code = code + e_addi(20, 20, 16) + e_movz(0, 0) + c_push()  off = off + 16 }
            if startsWith(b, "gcShadowPop") { code = code + e_addi(20, 20, 16) + e_movz(0, 0) + c_push()  off = off + 16 }
            // charCode(s) -> first byte of s (int). 20 bytes.
            if startsWith(b, "charCode") {
                let kc = sbNew()
                kc = sbAppend(kc, c_pop0())
                kc = sbAppend(kc, e_ldrb0(0, 0))
                kc = sbAppend(kc, c_push())
                code = code + sbToString(kc)
                off = off + 20
            }
            // len(s)/length(s) -> strlen (int). 40 bytes.
            if startsWith(b, "len") {
                let kc = sbNew()
                kc = sbAppend(kc, c_pop0())                  // x0 = ptr
                kc = sbAppend(kc, e_movz(1, 0))              // len=0
                kc = sbAppend(kc, e_ldrbO(2, 0, 1))          // .loop: w2=[x0+len]
                kc = sbAppend(kc, e_cbz(2, 12))              // 0 -> .done
                kc = sbAppend(kc, e_addi(1, 1, 1))           // len++
                kc = sbAppend(kc, e_b(0 - 12))               // loop
                kc = sbAppend(kc, e_movr(0, 1))              // x0 = len
                kc = sbAppend(kc, c_push())
                code = code + sbToString(kc)
                off = off + 40
            }
            // toStr(x) -> x as a string (kr_str_int for ints; identity for strings). 32 bytes.
            if startsWith(b, "toStr") {
                let kc = sbNew()
                kc = sbAppend(kc, c_pop0())
                kc = sbAppend(kc, e_movzHi(9, 32512))
                kc = sbAppend(kc, e_cmp(0, 9))
                kc = sbAppend(kc, e_bhs(8))                  // pointer -> already a string
                kc = sbAppend(kc, e_bl(strIntOff - (off + 20)))
                kc = sbAppend(kc, c_push())
                code = code + sbToString(kc)
                off = off + 32
            }
            // toInt(s) -> parse non-negative decimal (kr_atoi). 20 bytes.
            if startsWith(b, "toInt") {
                let kc = sbNew()
                kc = sbAppend(kc, c_pop0())                       // x0 = string ptr
                kc = sbAppend(kc, e_bl(atoiOff - (off + 8)))      // x0 = parsed int
                kc = sbAppend(kc, c_push())
                code = code + sbToString(kc)
                off = off + 20
            }
            // fromCharCode(n) -> 1-char string for byte n (kr_alloc(2)). 36 bytes.
            if startsWith(b, "fromCharCode") {
                let kc = sbNew()
                kc = sbAppend(kc, c_pop0())                       // x0 = code (int)
                kc = sbAppend(kc, e_movr(10, 0))                  // save code in x10
                kc = sbAppend(kc, e_movz(0, 2))                   // size = 2
                kc = sbAppend(kc, e_bl(allocOff - (off + 16)))    // x0 = buf
                kc = sbAppend(kc, e_strb(10, 0))                  // buf[0] = code
                kc = sbAppend(kc, e_strbO(31, 0, 1))             // buf[1] = NUL
                kc = sbAppend(kc, c_push())                       // push buf
                code = code + sbToString(kc)
                off = off + 36
            }
        }
        // RETURN and END: epilogue (free locals, restore x19/x30, ret). For __main__
        // this returns to _start, which then exits(0).
        if op == "RETURN" { code = code + e_addi(31, 31, frame) + e_ldr0(19, 31) + e_ldr8(30, 31, 1) + e_addi(31, 31, 16) + e_ret()  off = off + 20 }
        if op == "END"    { code = code + e_addi(31, 31, frame) + e_ldr0(19, 31) + e_ldr8(30, 31, 1) + e_addi(31, 31, 16) + e_ret()  off = off + 20 }
        i = i + 1
    }

    // helpers appended after main code, in layout order (alloc, str_int, plus, print)
    let body = code + emitAlloc() + emitStrInt(allocOff, strIntOff) + emitPlus(strIntOff, allocOff, plusOff) + emitPrint(nlOff) + emitKpDisp(kpDispOff, strIntOff, printOff) + emitAtoi()

    // data region: newline byte (at nlOff) then string literals
    let data = hexByte(10)                                     // newline
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

    // ELF64 header (aarch64, ET_EXEC) + PT_LOAD (RWX); total/heapBase computed above
    let eh = hexByte(127) + "x45x4Cx46" + "x02x01x01x00" + "x00x00x00x00x00x00x00x00"
    eh = eh + "x02x00" + "xB7x00" + "x01x00x00x00"
    eh = eh + le8vaddr(HDR) + le8(64) + le8(0)
    eh = eh + "x00x00x00x00" + "x40x00" + "x38x00" + "x01x00" + "x00x00" + "x00x00" + "x00x00"
    let ph = "x01x00x00x00" + "x07x00x00x00"
    let memsz = heapOff + 1048576 + 65536                  // 1 MiB heap + 64 KiB op stack (BSS)
    ph = ph + le8(0) + le8vaddr(0) + le8vaddr(0) + le8(total) + le8(memsz) + le8(65536)

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

// Emit (0x7F000000 + off) as an 8-byte LE vaddr without holding the full value
// (the backend's own int ceiling is 0x7F000000). byte3 = 0x7F + (off>>24).
func le8vaddr(off) {
    emit hexByte(off % 256) + hexByte((off / 256) % 256) + hexByte((off / 65536) % 256) + hexByte(127 + off / 16777216) + hexByte(0) + hexByte(0) + hexByte(0) + hexByte(0)
}
