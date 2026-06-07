// compiler/linux_aarch64/elf.k — native aarch64 Linux ELF backend (WIP).
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
func e_and(rd, rn, rm) { emit wordHL(35328 + rm, rn * 32 + rd) }                     // and Xd,Xn,Xm (0x8A00)
func e_orr(rd, rn, rm) { emit wordHL(43520 + rm, rn * 32 + rd) }                     // orr Xd,Xn,Xm (0xAA00)
func e_eor(rd, rn, rm) { emit wordHL(51712 + rm, rn * 32 + rd) }                     // eor Xd,Xn,Xm (0xCA00)
func e_orn(rd, rn, rm) { emit wordHL(43552 + rm, rn * 32 + rd) }                     // orn Xd,Xn,Xm (0xAA20); mvn = orn Xd,xzr,Xm
func e_lslv(rd, rn, rm) { let p = 8192 + rn * 32 + rd  emit wordHL(39616 + rm + p / 65536, p % 65536) } // lslv Xd,Xn,Xm
func e_lsrv(rd, rn, rm) { let p = 9216 + rn * 32 + rd  emit wordHL(39616 + rm + p / 65536, p % 65536) } // lsrv Xd,Xn,Xm
func e_csel(rd, rn, rm, cond) { let p = cond * 4096 + rn * 32 + rd  emit wordHL(39552 + rm + p / 65536, p % 65536) } // csel Xd,Xn,Xm,cond
func e_movr(rd, rm)  { let p = 992 + rd  emit wordHL(43520 + rm + p / 65536, p % 65536) }     // mov Xd,Xm
func e_strb(wt, xn)  { let p = xn * 32 + wt  emit wordHL(14592, p) }                 // strb Wt,[Xn]
func e_ldrbO(wt, xn, xm) { let p = 26624 + xn * 32 + wt  emit wordHL(14432 + xm + p / 65536, p % 65536) }
func e_ldrb0(wt, xn) { let p = xn * 32 + wt  emit wordHL(14656, p) }                 // ldrb Wt,[Xn]
func e_strbO(wt, xn, off) { let p = off * 1024 + xn * 32 + wt  emit wordHL(14592 + p / 65536, p % 65536) } // strb Wt,[Xn,#off]
func e_strbR(wt, xn, xm) { let p = 26624 + xn * 32 + wt  emit wordHL(14368 + xm + p / 65536, p % 65536) } // strb Wt,[Xn,Xm]
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
func e_bge(dsp) { let q = dsp / 4  if q < 0 { q = q + 524288 }  let p = q * 32 + 10 emit wordHL(21504 + p / 65536, p % 65536) } // b.ge (signed >=, cond GE=10)
func e_blt(dsp) { let q = dsp / 4  if q < 0 { q = q + 524288 }  let p = q * 32 + 11 emit wordHL(21504 + p / 65536, p % 65536) } // b.lt (signed <, cond LT=11)
func e_ble(dsp) { let q = dsp / 4  if q < 0 { q = q + 524288 }  let p = q * 32 + 13 emit wordHL(21504 + p / 65536, p % 65536) } // b.le (signed <=, cond LE=13)
func e_bne(dsp) { let q = dsp / 4  if q < 0 { q = q + 524288 }  let p = q * 32 + 1  emit wordHL(21504 + p / 65536, p % 65536) } // b.ne (cond NE=1)
func e_bgt(dsp) { let q = dsp / 4  if q < 0 { q = q + 524288 }  let p = q * 32 + 12 emit wordHL(21504 + p / 65536, p % 65536) } // b.gt (signed >, cond GT=12)
func e_movn(rd, imm) { let p = imm * 32 + rd  emit wordHL(37504 + p / 65536, p % 65536) } // movn Xd,#imm (NOT imm); movn Xd,#0 = -1
func e_beq(dsp) { let q = dsp / 4  if q < 0 { q = q + 524288 }  let p = q * 32 + 0  emit wordHL(21504 + p / 65536, p % 65536) } // b.eq (cond EQ=0)

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
// Signed: handles negative val by emitting '-' then the magnitude. 128 bytes.
// x6 = neg flag. Layout offsets in [brackets].
func emitStrInt(allocOff, thisOff) {
    let c = e_movr(24, 30) + e_movr(10, 0) + e_movz(0, 24)            // [0]  x24=lr; x10=val; x0=24 (size)
    c = c + e_bl(allocOff - (thisOff + 12))                          // [12] bl kr_alloc -> x0=buf
    c = c + e_addi(1, 0, 23) + e_movr(0, 10) + e_movz(4, 10) + e_strb(31, 1)  // [16] x1=buf+23; x0=val; x4=10; *x1=NUL
    c = c + e_movz(6, 0) + e_cmpi0(0) + e_bge(12) + e_subr(0, 31, 0) + e_movz(6, 1)  // [32] x6=0; if val<0: neg x0, x6=1
    c = c + e_cbz(0, 36)                                             // [52] x0==0 -> .zero (88)
    c = c + e_udiv(3, 0, 4) + e_msub(5, 3, 4, 0) + e_addi(5, 5, 48) + e_subi(1, 1, 1)  // [56] .loop
    c = c + e_strb(5, 1) + e_movr(0, 3) + e_cbnz(0, 0 - 24)          // [72] *x1=dig; x0=q; x0!=0 -> .loop (56)
    c = c + e_b(16)                                                  // [84] -> .signcheck (100)
    c = c + e_subi(1, 1, 1) + e_movz(2, 48) + e_strb(2, 1)           // [88] .zero: x1--; *x1='0'
    c = c + e_cbz(6, 16)                                             // [100] .signcheck: x6==0 -> .done (116)
    c = c + e_subi(1, 1, 1) + e_movz(2, 45) + e_strb(2, 1)           // [104] x1--; *x1='-'
    c = c + e_movr(0, 1) + e_movr(30, 24) + e_ret()                  // [116] .done: x0=x1; restore lr; ret
    emit c
}
// kr_hex: x0=int -> x0=lowercase hex string (sign+magnitude). 144 bytes. 24B buf.
func emitHex(allocOff, thisOff) {
    let c = e_movr(24, 30) + e_movr(10, 0) + e_movz(0, 24)            // [0]  x24=lr; x10=val; x0=24
    c = c + e_bl(allocOff - (thisOff + 12))                          // [12] bl kr_alloc -> x0=buf
    c = c + e_addi(1, 0, 23) + e_movr(0, 10) + e_movz(4, 16) + e_strb(31, 1)  // [16] x1=buf+23; x0=val; x4=16; *x1=0
    c = c + e_movz(6, 0) + e_cmpi0(0) + e_bge(12) + e_subr(0, 31, 0) + e_movz(6, 1)  // [32] sign
    c = c + e_cbz(0, 52)                                             // [52] x0==0 -> .zero (104)
    c = c + e_udiv(3, 0, 4) + e_msub(5, 3, 4, 0) + e_addi(5, 5, 48)  // [56] .loop: x3=x0/16; x5=rem; +'0'
    c = c + e_subi(7, 5, 58) + e_cmpi0(7) + e_blt(8) + e_addi(5, 5, 39)  // [68] if x5>'9'(x7>=0): x5 += 0x27 (a-f)
    c = c + e_subi(1, 1, 1) + e_strb(5, 1) + e_movr(0, 3) + e_cbnz(0, 0 - 40)  // [84] .store; x0=q; !=0 -> .loop (56)
    c = c + e_b(16)                                                  // [100] -> .signcheck (116)
    c = c + e_subi(1, 1, 1) + e_movz(2, 48) + e_strb(2, 1)           // [104] .zero: *x1='0'
    c = c + e_cbz(6, 16)                                             // [116] .signcheck: x6==0 -> .done (132)
    c = c + e_subi(1, 1, 1) + e_movz(2, 45) + e_strb(2, 1)           // [120] *x1='-'
    c = c + e_movr(0, 1) + e_movr(30, 24) + e_ret()                  // [132] .done
    emit c
}
// kr_bin: x0=int -> x0=binary string (sign+magnitude). 128 bytes. 72B buf (64 bits + sign + nul).
func emitBin(allocOff, thisOff) {
    let c = e_movr(24, 30) + e_movr(10, 0) + e_movz(0, 72)            // [0]  x24=lr; x10=val; x0=72
    c = c + e_bl(allocOff - (thisOff + 12))                          // [12] bl kr_alloc -> x0=buf
    c = c + e_addi(1, 0, 71) + e_movr(0, 10) + e_movz(4, 2) + e_strb(31, 1)  // [16] x1=buf+71; x0=val; x4=2; *x1=0
    c = c + e_movz(6, 0) + e_cmpi0(0) + e_bge(12) + e_subr(0, 31, 0) + e_movz(6, 1)  // [32] sign
    c = c + e_cbz(0, 36)                                             // [52] x0==0 -> .zero (88)
    c = c + e_udiv(3, 0, 4) + e_msub(5, 3, 4, 0) + e_addi(5, 5, 48) + e_subi(1, 1, 1)  // [56] .loop
    c = c + e_strb(5, 1) + e_movr(0, 3) + e_cbnz(0, 0 - 24)          // [72] *x1=dig; x0=q; !=0 -> .loop (56)
    c = c + e_b(16)                                                  // [84] -> .signcheck (100)
    c = c + e_subi(1, 1, 1) + e_movz(2, 48) + e_strb(2, 1)           // [88] .zero: *x1='0'
    c = c + e_cbz(6, 16)                                             // [100] .signcheck: x6==0 -> .done (116)
    c = c + e_subi(1, 1, 1) + e_movz(2, 45) + e_strb(2, 1)           // [104] *x1='-'
    c = c + e_movr(0, 1) + e_movr(30, 24) + e_ret()                  // [116] .done
    emit c
}
// kr_padleft(x0=s, x1=width int, x2=pad ptr) -> padded string. 136 bytes.
// width<=len(s) returns s. Else alloc(width+1), fill (width-len) pad chars, copy s.
// x10=s x11=width x12=padchar x13=slen x14=buf x26=lr.
func emitPadLeft(allocOff, thisOff) {
    let c = e_movr(26, 30) + e_movr(10, 0) + e_movr(11, 1) + e_ldrb0(12, 2)  // [0] save lr,s,width; x12=pad[0]
    c = c + e_movz(13, 0)                                            // [16] slen=0
    c = c + e_ldrbO(3, 10, 13) + e_cbz(3, 12) + e_addi(13, 13, 1) + e_b(0 - 12)  // [20] .sl: strlen(s)->x13
    c = c + e_cmp(11, 13) + e_ble(84)                               // [36] width<=slen -> .rets (124)
    c = c + e_addi(0, 11, 1) + e_bl(allocOff - (thisOff + 48))      // [44] x0=alloc(width+1)
    c = c + e_movr(14, 0) + e_movr(1, 0) + e_subr(2, 11, 13)        // [52] x14=buf; x1=cursor; x2=width-slen
    c = c + e_cbz(2, 20) + e_strb(12, 1) + e_addi(1, 1, 1) + e_subi(2, 2, 1) + e_b(0 - 16)  // [64] .fill: pad
    c = c + e_movz(3, 0)                                            // [84] .copy: i=0
    c = c + e_ldrbO(4, 10, 3) + e_strb(4, 1) + e_addi(1, 1, 1) + e_cbz(4, 12) + e_addi(3, 3, 1) + e_b(0 - 20)  // [88] .cl: copy s incl nul
    c = c + e_movr(0, 14) + e_movr(30, 26) + e_ret()               // [112] .cdone: return buf
    c = c + e_movr(0, 10) + e_movr(30, 26) + e_ret()               // [124] .rets: return s
    emit c
}
// kr_padright(x0=s, x1=width int, x2=pad ptr) -> padded string. 140 bytes.
// Copies s (no nul), then fills (width-len) pad chars, then writes the NUL.
func emitPadRight(allocOff, thisOff) {
    let c = e_movr(26, 30) + e_movr(10, 0) + e_movr(11, 1) + e_ldrb0(12, 2)  // [0] save lr,s,width; x12=pad[0]
    c = c + e_movz(13, 0)                                            // [16] slen=0
    c = c + e_ldrbO(3, 10, 13) + e_cbz(3, 12) + e_addi(13, 13, 1) + e_b(0 - 12)  // [20] .sl: strlen(s)->x13
    c = c + e_cmp(11, 13) + e_ble(88)                               // [36] width<=slen -> .rets (128)
    c = c + e_addi(0, 11, 1) + e_bl(allocOff - (thisOff + 48))      // [44] x0=alloc(width+1)
    c = c + e_movr(14, 0) + e_movr(1, 0)                            // [52] x14=buf; x1=cursor
    c = c + e_movz(3, 0)                                            // [60] i=0
    c = c + e_ldrbO(4, 10, 3) + e_cbz(4, 20) + e_strb(4, 1) + e_addi(1, 1, 1) + e_addi(3, 3, 1) + e_b(0 - 20)  // [64] .cl: copy s (no nul)
    c = c + e_subr(2, 11, 13)                                      // [88] .pad: x2=width-slen
    c = c + e_cbz(2, 20) + e_strb(12, 1) + e_addi(1, 1, 1) + e_subi(2, 2, 1) + e_b(0 - 16)  // [92] .fill: pad
    c = c + e_strb(31, 1)                                          // [112] .term: *x1=NUL
    c = c + e_movr(0, 14) + e_movr(30, 26) + e_ret()              // [116] return buf
    c = c + e_movr(0, 10) + e_movr(30, 26) + e_ret()              // [128] .rets: return s
    emit c
}
// kr_toupper(x0=s) -> new heap string with a-z uppercased. 112 bytes.
// x10=s x11=len x14=buf x26=lr. Copies+transforms in one pass.
func emitToUpper(allocOff, thisOff) {
    let c = e_movr(26, 30) + e_movr(10, 0) + e_movz(11, 0)          // [0] lr; x10=s; len=0
    c = c + e_ldrbO(3, 10, 11) + e_cbz(3, 12) + e_addi(11, 11, 1) + e_b(0 - 12)  // [12] .sl: strlen -> x11
    c = c + e_addi(0, 11, 1) + e_bl(allocOff - (thisOff + 32))      // [28] x0=alloc(len+1)
    c = c + e_movr(14, 0) + e_movz(3, 0)                            // [36] x14=buf; i=0
    c = c + e_cmp(3, 11) + e_bge(48)                                // [44] .cl: i>=len -> .done (92)
    c = c + e_ldrbO(4, 10, 3)                                       // [52] w4=s[i]
    c = c + e_subi(5, 4, 97) + e_cmpi0(5) + e_blt(20)               // [56] c<'a' -> .store (84)
    c = c + e_subi(5, 4, 123) + e_cmpi0(5) + e_bge(8)               // [68] c>'z' -> .store (84)
    c = c + e_subi(4, 4, 32)                                        // [80] c -= 32
    c = c + e_strbR(4, 14, 3) + e_addi(3, 3, 1) + e_b(0 - 48)       // [84] .store: buf[i]=c; i++; -> .cl (44)
    c = c + e_strbR(31, 14, 11) + e_movr(0, 14) + e_movr(30, 26) + e_ret()  // [96] .done: buf[len]=0; return buf
    emit c
}
// kr_tolower(x0=s) -> new heap string with A-Z lowercased. 112 bytes.
func emitToLower(allocOff, thisOff) {
    let c = e_movr(26, 30) + e_movr(10, 0) + e_movz(11, 0)          // [0]
    c = c + e_ldrbO(3, 10, 11) + e_cbz(3, 12) + e_addi(11, 11, 1) + e_b(0 - 12)  // [12] strlen
    c = c + e_addi(0, 11, 1) + e_bl(allocOff - (thisOff + 32))      // [28] alloc
    c = c + e_movr(14, 0) + e_movz(3, 0)                            // [36]
    c = c + e_cmp(3, 11) + e_bge(48)                                // [44] .cl
    c = c + e_ldrbO(4, 10, 3)                                       // [52]
    c = c + e_subi(5, 4, 65) + e_cmpi0(5) + e_blt(20)               // [56] c<'A' -> .store
    c = c + e_subi(5, 4, 91) + e_cmpi0(5) + e_bge(8)                // [68] c>'Z' -> .store
    c = c + e_addi(4, 4, 32)                                        // [80] c += 32
    c = c + e_strbR(4, 14, 3) + e_addi(3, 3, 1) + e_b(0 - 48)       // [84] .store
    c = c + e_strbR(31, 14, 11) + e_movr(0, 14) + e_movr(30, 26) + e_ret()  // [96] .done
    emit c
}
// kr_reverse(x0=s) -> new heap string reversed. 92 bytes. buf[i]=s[len-1-i].
func emitReverse(allocOff, thisOff) {
    let c = e_movr(26, 30) + e_movr(10, 0) + e_movz(11, 0)          // [0]
    c = c + e_ldrbO(3, 10, 11) + e_cbz(3, 12) + e_addi(11, 11, 1) + e_b(0 - 12)  // [12] strlen -> x11
    c = c + e_addi(0, 11, 1) + e_bl(allocOff - (thisOff + 32))      // [28] alloc
    c = c + e_movr(14, 0) + e_movz(3, 0)                            // [36] buf; i=0
    c = c + e_cmp(3, 11) + e_bge(28)                                // [44] .cl: i>=len -> .done (76)
    c = c + e_subr(5, 11, 3) + e_subi(5, 5, 1) + e_ldrbO(4, 10, 5)  // [52] x5=len-1-i; w4=s[x5]
    c = c + e_strbR(4, 14, 3) + e_addi(3, 3, 1) + e_b(0 - 28)       // [64] buf[i]=w4; i++; -> .cl (44)
    c = c + e_strbR(31, 14, 11) + e_movr(0, 14) + e_movr(30, 26) + e_ret()  // [76] .done
    emit c
}
// kr_startswith(x1=s, x0=prefix) -> x0=1/0. 48 bytes. No alloc.
func emitStartsWith() {
    let c = e_movz(3, 0)                                            // [0] i=0
    c = c + e_ldrbO(4, 0, 3) + e_cbz(4, 24)                         // [4] .cl: pc=prefix[i]; ==0 -> .yes (32)
    c = c + e_ldrbO(5, 1, 3) + e_cmp(4, 5) + e_bne(20)              // [12] sc=s[i]; differ -> .no (40)
    c = c + e_addi(3, 3, 1) + e_b(0 - 24)                           // [24] i++; -> .cl (4)
    c = c + e_movz(0, 1) + e_ret()                                  // [32] .yes: x0=1
    c = c + e_movz(0, 0) + e_ret()                                  // [40] .no: x0=0
    emit c
}
// kr_endswith(x1=s, x0=suffix) -> x0=1/0. 104 bytes. Compares s tail.
func emitEndsWith() {
    let c = e_movz(6, 0)                                            // [0] slen=0
    c = c + e_ldrbO(3, 1, 6) + e_cbz(3, 12) + e_addi(6, 6, 1) + e_b(0 - 12)  // [4] strlen(s)->x6
    c = c + e_movz(7, 0)                                            // [20] suflen=0
    c = c + e_ldrbO(3, 0, 7) + e_cbz(3, 12) + e_addi(7, 7, 1) + e_b(0 - 12)  // [24] strlen(suffix)->x7
    c = c + e_cmp(7, 6) + e_bgt(52)                                 // [40] suflen>slen -> .no (96)
    c = c + e_subr(8, 6, 7) + e_movz(3, 0)                          // [48] start=slen-suflen; i=0
    c = c + e_ldrbO(4, 0, 3) + e_cbz(4, 28)                         // [56] .cl: suf[i]; ==0 -> .yes (88)
    c = c + e_addr(5, 8, 3) + e_ldrbO(9, 1, 5) + e_cmp(4, 9) + e_bne(20)  // [64] s[start+i]; differ -> .no (96)
    c = c + e_addi(3, 3, 1) + e_b(0 - 28)                           // [80] i++; -> .cl (56)
    c = c + e_movz(0, 1) + e_ret()                                  // [88] .yes
    c = c + e_movz(0, 0) + e_ret()                                  // [96] .no
    emit c
}
// kr_repeat(x1=s, x0=n) -> new heap string s repeated n times. 120 bytes.
// x10=s x11=n x6=slen x14=buf x12=k. Uses MUL for total length.
func emitRepeat(allocOff, thisOff) {
    let c = e_movr(26, 30) + e_movr(10, 1) + e_movr(11, 0)          // [0] lr; x10=s; x11=n
    c = c + e_movz(6, 0)                                            // [12] slen=0
    c = c + e_ldrbO(3, 10, 6) + e_cbz(3, 12) + e_addi(6, 6, 1) + e_b(0 - 12)  // [16] strlen(s)->x6
    c = c + e_mul(0, 6, 11) + e_addi(0, 0, 1)                       // [32] x0 = slen*n + 1
    c = c + e_bl(allocOff - (thisOff + 40))                         // [40] x0=buf
    c = c + e_movr(14, 0) + e_movr(1, 0) + e_movz(12, 0)            // [44] x14=buf; x1=cursor; k=0
    c = c + e_cmp(12, 11) + e_bge(44)                               // [56] .outer: k>=n -> .term (104)
    c = c + e_movz(3, 0)                                            // [64] j=0
    c = c + e_cmp(3, 6) + e_bge(24)                                 // [68] .inner: j>=slen -> .nextk (96)
    c = c + e_ldrbO(4, 10, 3) + e_strb(4, 1) + e_addi(1, 1, 1) + e_addi(3, 3, 1) + e_b(0 - 24)  // [76] copy s[j]
    c = c + e_addi(12, 12, 1) + e_b(0 - 44)                         // [96] .nextk: k++; -> .outer (56)
    c = c + e_strb(31, 1) + e_movr(0, 14) + e_movr(30, 26) + e_ret()  // [104] .term: *x1=0; return buf
    emit c
}
// kr_contains(x1=s, x0=sub) -> x0=1/0. 120 bytes. Naive substring search.
func emitContains() {
    let c = e_movz(6, 0)                                            // [0] slen=0
    c = c + e_ldrbO(3, 1, 6) + e_cbz(3, 12) + e_addi(6, 6, 1) + e_b(0 - 12)  // [4] strlen(s)->x6
    c = c + e_movz(7, 0)                                            // [20] sublen=0
    c = c + e_ldrbO(3, 0, 7) + e_cbz(3, 12) + e_addi(7, 7, 1) + e_b(0 - 12)  // [24] strlen(sub)->x7
    c = c + e_movz(8, 0)                                            // [40] start=0
    c = c + e_addr(9, 8, 7) + e_cmp(9, 6) + e_bgt(60)               // [44] .outer: start+sublen>slen -> .no (112)
    c = c + e_movz(3, 0)                                            // [56] j=0
    c = c + e_cmp(3, 7) + e_bge(40)                                 // [60] .inner: j>=sublen -> .yes (104)
    c = c + e_addr(5, 8, 3) + e_ldrbO(4, 1, 5) + e_ldrbO(9, 0, 3) + e_cmp(4, 9) + e_bne(12)  // [68] s[start+j]!=sub[j] -> .nextstart (96)
    c = c + e_addi(3, 3, 1) + e_b(0 - 32)                           // [88] j++; -> .inner (60)
    c = c + e_addi(8, 8, 1) + e_b(0 - 56)                           // [96] .nextstart: start++; -> .outer (44)
    c = c + e_movz(0, 1) + e_ret()                                  // [104] .yes
    c = c + e_movz(0, 0) + e_ret()                                  // [112] .no
    emit c
}
// kr_indexof(x1=s, x0=sub) -> x0=position or -1. 120 bytes. Same search; returns start/-1.
func emitIndexOf() {
    let c = e_movz(6, 0)                                            // [0] slen=0
    c = c + e_ldrbO(3, 1, 6) + e_cbz(3, 12) + e_addi(6, 6, 1) + e_b(0 - 12)  // [4] strlen(s)->x6
    c = c + e_movz(7, 0)                                            // [20] sublen=0
    c = c + e_ldrbO(3, 0, 7) + e_cbz(3, 12) + e_addi(7, 7, 1) + e_b(0 - 12)  // [24] strlen(sub)->x7
    c = c + e_movz(8, 0)                                            // [40] start=0
    c = c + e_addr(9, 8, 7) + e_cmp(9, 6) + e_bgt(60)               // [44] .outer: start+sublen>slen -> .notfound (112)
    c = c + e_movz(3, 0)                                            // [56] j=0
    c = c + e_cmp(3, 7) + e_bge(40)                                 // [60] .inner: j>=sublen -> .found (104)
    c = c + e_addr(5, 8, 3) + e_ldrbO(4, 1, 5) + e_ldrbO(9, 0, 3) + e_cmp(4, 9) + e_bne(12)  // [68] mismatch -> .nextstart (96)
    c = c + e_addi(3, 3, 1) + e_b(0 - 32)                           // [88] j++; -> .inner (60)
    c = c + e_addi(8, 8, 1) + e_b(0 - 56)                           // [96] .nextstart: start++; -> .outer (44)
    c = c + e_movr(0, 8) + e_ret()                                  // [104] .found: return start
    c = c + e_movn(0, 0) + e_ret()                                  // [112] .notfound: return -1
    emit c
}
// kr_trim(x0=s) -> new heap string with leading/trailing chars <=32 stripped. 168 bytes.
func emitTrim(allocOff, thisOff) {
    let c = e_movr(26, 30) + e_movr(10, 0) + e_movz(6, 0)           // [0] lr; x10=s; len=0
    c = c + e_ldrbO(3, 10, 6) + e_cbz(3, 12) + e_addi(6, 6, 1) + e_b(0 - 12)  // [12] strlen->x6
    c = c + e_movz(3, 0)                                            // [28] start=0
    c = c + e_cmp(3, 6) + e_bge(28)                                 // [32] .ls: start>=len -> .startdone (64)
    c = c + e_ldrbO(4, 10, 3) + e_subi(5, 4, 33) + e_cmpi0(5) + e_bge(12)  // [40] c>=33 -> .startdone (64)
    c = c + e_addi(3, 3, 1) + e_b(0 - 28)                           // [56] start++; -> .ls (32)
    c = c + e_movr(4, 6)                                            // [64] .startdone: end=len
    c = c + e_cmp(4, 3) + e_ble(32)                                 // [68] .le: end<=start -> .enddone (104)
    c = c + e_subi(5, 4, 1) + e_ldrbO(9, 10, 5) + e_subi(5, 9, 33) + e_cmpi0(5) + e_bge(12)  // [76] s[end-1]>=33 -> .enddone (104)
    c = c + e_subi(4, 4, 1) + e_b(0 - 32)                           // [96] end--; -> .le (68)
    c = c + e_subr(7, 4, 3) + e_addi(0, 7, 1)                       // [104] .enddone: newlen=end-start; x0=newlen+1
    c = c + e_bl(allocOff - (thisOff + 112)) + e_movr(14, 0)        // [112] alloc -> x14=buf
    c = c + e_movz(5, 0)                                            // [120] i=0
    c = c + e_cmp(5, 7) + e_bge(24)                                 // [124] .cp: i>=newlen -> .done (152)
    c = c + e_addr(9, 3, 5) + e_ldrbO(4, 10, 9) + e_strbR(4, 14, 5) + e_addi(5, 5, 1) + e_b(0 - 24)  // [132] buf[i]=s[start+i]
    c = c + e_strbR(31, 14, 7) + e_movr(0, 14) + e_movr(30, 26) + e_ret()  // [152] .done: buf[newlen]=0; return
    emit c
}
// kr_split(x1=list, x0=idx int) -> idx-th comma-separated element (fresh string). 160 bytes.
// x10=ptr x11=remaining x12=elem-start x13=len x9=',' x26=lr.
func emitSplit(allocOff, thisOff) {
    let c = e_movr(26, 30) + e_movr(11, 0) + e_movr(10, 1) + e_movz(9, 44)  // [0] lr; rem=idx; ptr=list; x9=','
    c = c + e_cmpi0(11) + e_beq(32)                                // [16] .skip: rem==0 -> .scan_setup (48)
    c = c + e_ldrb0(3, 10) + e_cbz(3, 112)                         // [24] c=[ptr]; c==0 -> .empty (140)
    c = c + e_addi(10, 10, 1) + e_cmp(3, 9) + e_bne(8)             // [32] ptr++; c!=',' -> .skipcont (48)
    c = c + e_subi(11, 11, 1)                                      // [44] rem--
    c = c + e_b(0 - 32)                                            // [48] .skipcont: -> .skip (16)
    c = c + e_movr(12, 10)                                         // [52] .scan_setup: elem start
    c = c + e_ldrb0(3, 10) + e_cbz(3, 20)                          // [56] .scan: c=[ptr]; c==0 -> .got_end (80)
    c = c + e_cmp(3, 9) + e_beq(12)                                // [64] c==',' -> .got_end (80)
    c = c + e_addi(10, 10, 1) + e_b(0 - 20)                        // [72] ptr++; -> .scan (56)
    c = c + e_subr(13, 10, 12) + e_addi(0, 13, 1)                  // [80] .got_end: len=ptr-start; x0=len+1
    c = c + e_bl(allocOff - (thisOff + 88))                        // [88] x0=buf
    c = c + e_movr(1, 0) + e_movz(5, 0)                            // [92] dst=buf; i=0
    c = c + e_cmp(5, 13) + e_bge(20)                               // [100] .cp: i>=len -> .cpdone (124)
    c = c + e_ldrbO(4, 12, 5) + e_strbR(4, 1, 5) + e_addi(5, 5, 1) + e_b(0 - 20)  // [108] dst[i]=start[i]
    c = c + e_strbR(31, 1, 13) + e_movr(0, 1) + e_movr(30, 26) + e_ret()  // [124] .cpdone: dst[len]=0; return
    c = c + e_movz(0, 1) + e_bl(allocOff - (thisOff + 144)) + e_strb(31, 0) + e_movr(30, 26) + e_ret()  // [140] .empty: ""
    emit c
}
// kr_count(x0=list) -> number of comma-separated elements (commas+1, or 0 if empty). 64 bytes.
func emitCount() {
    let c = e_ldrb0(3, 0) + e_cbz(3, 52)                           // [0] empty -> .zero (56)
    c = c + e_movz(1, 0) + e_movz(2, 0) + e_movz(9, 44)            // [8] commas=0; i=0; x9=','
    c = c + e_ldrbO(3, 0, 2) + e_cbz(3, 24)                        // [20] .cl: c=s[i]; c==0 -> .done (48)
    c = c + e_cmp(3, 9) + e_bne(8)                                 // [28] c!=',' -> .cont (40)
    c = c + e_addi(1, 1, 1)                                        // [36] commas++
    c = c + e_addi(2, 2, 1) + e_b(0 - 24)                          // [40] .cont: i++; -> .cl (20)
    c = c + e_addi(0, 1, 1) + e_ret()                             // [48] .done: x0=commas+1
    c = c + e_movz(0, 0) + e_ret()                                // [56] .zero: x0=0
    emit c
}
// kr_pow(x1=base, x0=exp) -> base^exp. 32 bytes. result=1; result*=base, exp times.
func emitPow() {
    let c = e_movz(2, 1)                                          // [0] result=1
    c = c + e_cmpi0(0) + e_beq(16)                                // [4] .lp: exp==0 -> .done (24)
    c = c + e_mul(2, 2, 1) + e_subi(0, 0, 1) + e_b(0 - 16)        // [12] result*=base; exp--; -> .lp (4)
    c = c + e_movr(0, 2) + e_ret()                                // [24] .done: x0=result
    emit c
}
// kr_range(x1=start, x0=end) -> comma-string "start,...,end-1". 156 bytes.
// Builds elements via kr_str_int. x25=v x11=end x12=buf x13=cursor x26=lr
// (all survive str_int, which clobbers x0-x6/x10/x24/x30).
func emitRange(allocOff, strIntOff, thisOff) {
    let c = e_movr(26, 30) + e_movr(25, 1) + e_movr(11, 0)        // [0] lr; v=start; end
    c = c + e_subr(2, 0, 1) + e_cmpi0(2) + e_ble(116)            // [12] count=end-start; <=0 -> .empty (136)
    c = c + e_movz(3, 12) + e_mul(0, 2, 3) + e_addi(0, 0, 2)     // [24] x0 = count*12 + 2
    c = c + e_bl(allocOff - (thisOff + 36))                      // [36] x0=buf
    c = c + e_movr(12, 0) + e_movr(13, 0)                        // [40] buf base; cursor
    c = c + e_cmp(25, 11) + e_bge(68)                            // [48] .loop: v>=end -> .done (120)
    c = c + e_movr(0, 25) + e_bl(strIntOff - (thisOff + 60))     // [56] x0 = str(v)
    c = c + e_ldrb0(4, 0) + e_cbz(4, 20)                         // [64] .cp: c=*istr; ==0 -> .cpdone (88)
    c = c + e_strb(4, 13) + e_addi(0, 0, 1) + e_addi(13, 13, 1) + e_b(0 - 20)  // [72] *cursor=c; istr++; cursor++; -> .cp (64)
    c = c + e_addi(5, 25, 1) + e_cmp(5, 11) + e_bge(16)          // [88] .cpdone: v+1>=end -> .skipcomma (112)
    c = c + e_movz(4, 44) + e_strb(4, 13) + e_addi(13, 13, 1)    // [100] *cursor=','; cursor++
    c = c + e_addi(25, 25, 1) + e_b(0 - 68)                      // [112] .skipcomma: v++; -> .loop (48)
    c = c + e_strb(31, 13) + e_movr(0, 12) + e_movr(30, 26) + e_ret()  // [120] .done: *cursor=0; return buf
    c = c + e_movz(0, 1) + e_bl(allocOff - (thisOff + 140)) + e_strb(31, 0) + e_movr(30, 26) + e_ret()  // [136] .empty: ""
    emit c
}
// kr_sbnew() -> handle block [cap:8][len:8][data]. cap=256, len=0. 36 bytes.
func emitSbNew(allocOff, thisOff) {
    let c = e_movr(26, 30) + e_movz(0, 272)                       // [0] lr; size=16+256
    c = c + e_bl(allocOff - (thisOff + 8))                        // [8] x0=handle
    c = c + e_movz(1, 256) + e_str0(1, 0)                         // [12] [handle]=cap=256
    c = c + e_str8(31, 0, 1) + e_strbO(31, 0, 16)                 // [20] [handle+8]=len=0; data[0]=0
    c = c + e_movr(30, 26) + e_ret()                             // [28] return handle (x0)
    emit c
}
// kr_sbappend(x1=handle, x0=s) -> handle (possibly relocated). 176 bytes.
// x10=handle x11=s x12=slen x13=len (all survive the alloc in the grow path).
func emitSbAppend(allocOff, thisOff) {
    let c = e_movr(26, 30) + e_movr(10, 1) + e_movr(11, 0)        // [0] lr; handle; s
    c = c + e_movz(12, 0)                                         // [12] slen=0
    c = c + e_ldrbO(3, 11, 12) + e_cbz(3, 12) + e_addi(12, 12, 1) + e_b(0 - 12)  // [16] strlen(s)->x12
    c = c + e_ldr8(13, 10, 1)                                     // [32] len=[handle+8]
    c = c + e_addr(4, 13, 12) + e_addi(4, 4, 1)                   // [36] need=len+slen+1
    c = c + e_ldr0(5, 10) + e_cmp(4, 5) + e_ble(64)               // [44] cap=[handle]; need<=cap -> .nogrow (116)
    c = c + e_movz(6, 2) + e_mul(6, 4, 6)                         // [56] newcap=need*2
    c = c + e_addi(0, 6, 16) + e_bl(allocOff - (thisOff + 68))    // [64] x0=alloc(newcap+16)=nb
    c = c + e_movr(7, 0) + e_movz(8, 0) + e_addi(14, 13, 16)      // [72] nb; i=0; count=len+16
    c = c + e_cmp(8, 14) + e_bge(20)                              // [84] .cpold: i>=count -> .cpolddone (108)
    c = c + e_ldrbO(3, 10, 8) + e_strbR(3, 7, 8) + e_addi(8, 8, 1) + e_b(0 - 20)  // [92] nb[i]=handle[i]
    c = c + e_str0(6, 7) + e_movr(10, 7)                          // [108] .cpolddone: [nb]=newcap; handle=nb
    c = c + e_addi(4, 10, 16) + e_addr(4, 4, 13)                  // [116] .nogrow: x4=handle+16+len (dst)
    c = c + e_movz(8, 0)                                          // [124] i=0
    c = c + e_cmp(8, 12) + e_bge(20)                              // [128] .cpapp: i>=slen -> .cpappdone (152)
    c = c + e_ldrbO(3, 11, 8) + e_strbR(3, 4, 8) + e_addi(8, 8, 1) + e_b(0 - 20)  // [136] dst[i]=s[i]
    c = c + e_addr(5, 13, 12) + e_str8(5, 10, 1)                  // [152] .cpappdone: newlen=len+slen; [handle+8]=newlen
    c = c + e_strbR(31, 4, 12)                                    // [160] dst[slen]=0
    c = c + e_movr(0, 10) + e_movr(30, 26) + e_ret()             // [164] return handle
    emit c
}
// kr_sbtostring(x0=handle) -> data ptr = handle+16. 8 bytes.
func emitSbToString() {
    emit e_addi(0, 0, 16) + e_ret()
}
// kr_eq(x0=a, x1=b) -> x0=1/0. Polymorphic: both pointers (>=VBASE) -> strcmp;
// else numeric compare (mixed int/ptr falls here and compares unequal). 76 bytes.
func emitEq() {
    let c = e_movzHi(9, 32512)                                    // [0] x9=VBASE
    c = c + e_cmp(0, 9) + e_blt(44)                               // [4] a<VBASE -> .numeric (52)
    c = c + e_cmp(1, 9) + e_blt(36)                               // [12] b<VBASE -> .numeric (52)
    c = c + e_movz(2, 0)                                          // [20] i=0
    c = c + e_ldrbO(3, 0, 2) + e_ldrbO(4, 1, 2) + e_cmp(3, 4) + e_bne(24)  // [24] .sl: a[i] vs b[i]; differ -> .ne (60)
    c = c + e_cbz(3, 28)                                          // [40] a[i]==0 (both, equal) -> .eq (68)
    c = c + e_addi(2, 2, 1) + e_b(0 - 24)                         // [44] i++; -> .sl (24)
    c = c + e_cmp(0, 1) + e_beq(12)                               // [52] .numeric: a==b -> .eq (68)
    c = c + e_movz(0, 0) + e_ret()                                // [60] .ne: x0=0
    c = c + e_movz(0, 1) + e_ret()                                // [68] .eq: x0=1
    emit c
}
// kr_index(x1=s, x0=idx) -> fresh 1-char string of s[idx]. 36 bytes. (char indexing)
func emitIndex(allocOff, thisOff) {
    let c = e_movr(26, 30) + e_ldrbO(2, 1, 0) + e_movr(10, 2)     // [0] lr; w2=s[idx]; save char
    c = c + e_movz(0, 2) + e_bl(allocOff - (thisOff + 16))        // [12] x0=alloc(2)
    c = c + e_strb(10, 0) + e_strbO(31, 0, 1)                     // [20] buf[0]=char; buf[1]=0
    c = c + e_movr(30, 26) + e_ret()                            // [28] return buf
    emit c
}
// kr_readfile(x0=path) -> NUL-terminated contents. 120 bytes. aarch64 syscalls:
// openat=56(AT_FDCWD=-100), fstat=80(st_size@+48), read=63, close=57. 144B stack statbuf.
// NB: keep each `c = c +` line <=3 terms — the x86 backend MISCOMPILES long
// concat chains here (drops terms), so syscall instructions silently vanish.
func emitReadFile(allocOff, thisOff) {
    let c = e_movr(26, 30) + e_subi(31, 31, 144)                  // [0,4] lr; sub sp,#144 (statbuf)
    c = c + e_movr(1, 0) + e_movn(0, 99)                          // [8,12] x1=path; x0=AT_FDCWD
    c = c + e_movz(2, 0) + e_movz(3, 0)                           // [16,20] O_RDONLY; mode 0
    c = c + e_movz(8, 56) + e_svc()                              // [24,28] openat
    c = c + e_movr(10, 0) + e_movr(0, 10)                        // [32,36] fd=x10; x0=fd
    c = c + e_addi(1, 31, 0) + e_movz(8, 80)                     // [40,44] statbuf=sp; fstat nr
    c = c + e_svc() + e_ldr8(11, 31, 6)                          // [48,52] fstat; size=[sp+48]
    c = c + e_addi(0, 11, 1) + e_bl(allocOff - (thisOff + 60))    // [56,60] buf = alloc(size+1)
    c = c + e_movr(12, 0) + e_movr(0, 10)                        // [64,68] buf; fd
    c = c + e_movr(1, 12) + e_movr(2, 11)                        // [72,76] buf; size
    c = c + e_movz(8, 63) + e_svc()                             // [80,84] read
    c = c + e_strbR(31, 12, 11) + e_movr(0, 10)                 // [88,92] buf[size]=0; fd
    c = c + e_movz(8, 57) + e_svc()                             // [96,100] close
    c = c + e_movr(0, 12) + e_addi(31, 31, 144)                 // [104,108] return buf; restore sp
    c = c + e_movr(30, 26) + e_ret()                           // [112,116]
    emit c
}
// kr_writefile(x1=path, x0=content) -> 0. 96 bytes. openat(WRONLY|CREAT|TRUNC=577,
// mode 0644=420), write, close.
// NB: <=3 terms per line (x86-backend miscompile drops terms from long chains).
func emitWriteFile() {
    let c = e_movr(26, 30) + e_movr(10, 0)                        // [0,4] lr; content
    c = c + e_movz(11, 0)                                         // [8] len=0
    c = c + e_ldrbO(3, 10, 11) + e_cbz(3, 12)                     // [12,16] .sl: content[len]; ==0 -> openat (28)
    c = c + e_addi(11, 11, 1) + e_b(0 - 12)                       // [20,24] len++; -> .sl (12)
    c = c + e_movn(0, 99) + e_movz(2, 577)                        // [28,32] x0=AT_FDCWD; flags
    c = c + e_movz(3, 420) + e_movz(8, 56)                        // [36,40] mode 0644; openat nr
    c = c + e_svc() + e_movr(12, 0)                              // [44,48] openat; fd=x12
    c = c + e_movr(0, 12) + e_movr(1, 10)                        // [52,56] fd; content
    c = c + e_movr(2, 11) + e_movz(8, 64)                        // [60,64] len; write nr
    c = c + e_svc() + e_movr(0, 12)                             // [68,72] write; fd
    c = c + e_movz(8, 57) + e_svc()                            // [76,80] close
    c = c + e_movz(0, 0) + e_movr(30, 26)                      // [84,88] return 0
    c = c + e_ret()                                            // [92]
    emit c
}
// Structs = a linked list of 24-byte nodes [name:8][val:8][prev:8]; env head is
// the most-recent node (NULL = empty). setField prepends; getField walks+strcmps.
// kr_setfield(x0=env, x1=name, x2=val) -> x0=new node. 44 bytes.
func emitSetField(allocOff, thisOff) {
    let c = e_movr(26, 30) + e_movr(10, 0)                        // [0,4] lr; env
    c = c + e_movr(11, 1) + e_movr(12, 2)                         // [8,12] name; val
    c = c + e_movz(0, 24) + e_bl(allocOff - (thisOff + 20))       // [16,20] node=alloc(24)
    c = c + e_str0(11, 0) + e_str8(12, 0, 1)                      // [24,28] node[0]=name; node[8]=val
    c = c + e_str8(10, 0, 2) + e_movr(30, 26)                     // [32,36] node[16]=prev=env
    c = c + e_ret()                                              // [40]
    emit c
}
// kr_getfield(x1=env, x0=name) -> x0=val, or fresh "" if not found. 92 bytes.
func emitGetField(allocOff, thisOff) {
    let c = e_movr(26, 30) + e_movr(11, 0) + e_movr(10, 1)        // [0,4,8] lr; name; cur=env
    c = c + e_cbz(10, 60)                                         // [12] .loop: cur==0 -> .notfound (72)
    c = c + e_ldr0(0, 10) + e_movz(2, 0)                          // [16,20] x0=cur.name; i=0
    c = c + e_ldrbO(3, 0, 2) + e_ldrbO(4, 11, 2)                  // [24,28] .sc: curname[i]; name[i]
    c = c + e_cmp(3, 4) + e_bne(16)                               // [32,36] differ -> .nomatch (52)
    c = c + e_cbz(3, 20) + e_addi(2, 2, 1)                        // [40,44] both 0 -> .match (60); i++
    c = c + e_b(0 - 24)                                           // [48] -> .sc (24)
    c = c + e_ldr8(10, 10, 2) + e_b(0 - 44)                       // [52,56] .nomatch: cur=prev; -> .loop (12)
    c = c + e_ldr8(0, 10, 1) + e_movr(30, 26) + e_ret()          // [60,64,68] .match: x0=cur.val; ret
    c = c + e_movz(0, 1) + e_bl(allocOff - (thisOff + 76))        // [72,76] .notfound: x0=alloc(1)
    c = c + e_strb(31, 0) + e_movr(30, 26) + e_ret()            // [80,84,88] *x0=0 (""); ret
    emit c
}
// kr_hasfield(x1=env, x0=name) -> x0=1/0. 72 bytes. No alloc.
func emitHasField() {
    let c = e_movr(11, 0) + e_movr(10, 1)                         // [0,4] name; cur=env
    c = c + e_cbz(10, 56)                                         // [8] .loop: cur==0 -> .no (64)
    c = c + e_ldr0(0, 10) + e_movz(2, 0)                          // [12,16] cur.name; i=0
    c = c + e_ldrbO(3, 0, 2) + e_ldrbO(4, 11, 2)                  // [20,24] .sc
    c = c + e_cmp(3, 4) + e_bne(16)                               // [28,32] differ -> .nomatch (48)
    c = c + e_cbz(3, 20) + e_addi(2, 2, 1)                        // [36,40] both 0 -> .yes (56); i++
    c = c + e_b(0 - 24)                                           // [44] -> .sc (20)
    c = c + e_ldr8(10, 10, 2) + e_b(0 - 44)                       // [48,52] .nomatch: cur=prev; -> .loop (8)
    c = c + e_movz(0, 1) + e_ret()                                // [56,60] .yes
    c = c + e_movz(0, 0) + e_ret()                                // [64,68] .no
    emit c
}
// kr_structfields(x0=env) -> "name,name,..." (head-first, trailing comma). 104 bytes.
// Builds via kr_plus. x24=cur x25=result x10="," x26=lr (survive kr_plus/kr_alloc).
func emitStructFields(allocOff, plusOff, thisOff) {
    let c = e_movr(26, 30) + e_movr(24, 0)                        // [0,4] lr; cur=env
    c = c + e_movz(0, 2) + e_bl(allocOff - (thisOff + 12))        // [8,12] alloc(2) for ","
    c = c + e_movz(1, 44) + e_strb(1, 0)                          // [16,20] comma[0]=','
    c = c + e_strbO(31, 0, 1) + e_movr(10, 0)                     // [24,28] comma[1]=0; x10=comma
    c = c + e_movz(0, 1) + e_bl(allocOff - (thisOff + 36))        // [32,36] alloc(1) empty result
    c = c + e_strb(31, 0) + e_movr(25, 0)                         // [40,44] result[0]=0; result=""
    c = c + e_cbz(24, 44)                                         // [48] .loop: cur==0 -> .done (92)
    c = c + e_movr(0, 25) + e_ldr0(1, 24)                         // [52,56] a=result; b=cur.name
    c = c + e_bl(plusOff - (thisOff + 60)) + e_movr(25, 0)        // [60,64] result = result+name
    c = c + e_movr(0, 25) + e_movr(1, 10)                         // [68,72] a=result; b=","
    c = c + e_bl(plusOff - (thisOff + 76)) + e_movr(25, 0)        // [76,80] result = result+","
    c = c + e_ldr8(24, 24, 2) + e_b(0 - 40)                       // [84,88] cur=cur.prev; -> .loop (48)
    c = c + e_movr(0, 25) + e_movr(30, 26) + e_ret()             // [92,96,100] .done: return result
    emit c
}
// kr_plus(a=x0, b=x1) -> x0. Polymorphic +: both ints -> a+b; else convert each
// to a string (kr_str_int for the int side) and concat into a fresh heap buffer.
// Saves lr in x23; VBASE in x9; sa=x11 sb=x12 b=x13 lenA=x14 lenB=x16 dst=x17.
func emitPlus(strIntOff, allocOff, thisOff) {
    let c = e_movr(23, 30) + e_movzHi(9, 32512)                                       // lr; x9=VBASE
    c = c + e_cmp(0, 9) + e_bge(24) + e_cmp(1, 9) + e_bge(16)                      // either signed>=VBASE (ptr) -> concat
    c = c + e_addr(0, 0, 1) + e_movr(30, 23) + e_ret()                            // both int: a+b
    c = c + e_movr(13, 1)                                                          // [cc] x13=b
    c = c + e_cmp(0, 9) + e_bge(8) + e_bl(strIntOff - (thisOff + 48))             // conv a (int side only)
    c = c + e_movr(11, 0)                                                          // [as] sa
    c = c + e_movr(0, 13) + e_cmp(0, 9) + e_bge(8) + e_bl(strIntOff - (thisOff + 68))  // conv b (int side only)
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
    c = c + e_bge(8)
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
// kr_substring: x0=s ptr, x1=start, x2=end -> x0=new heap string s[start:end].
func emitSubstr(allocOff, thisOff) {
    let c = e_movr(26, 30)                                     // save x30 (clobbered by bl kr_alloc)
    c = c + e_subr(3, 2, 1) + e_addr(4, 0, 1)                  // x3=len=end-start, x4=src=s+start
    c = c + e_movr(10, 3) + e_movr(11, 4) + e_addi(0, 3, 1)    // save len/src, x0=size=len+1
    c = c + e_bl(allocOff - (thisOff + 24))                    // x0=dst (clobbers x0/x15/x22/x30)
    c = c + e_movz(5, 0) + e_cmp(5, 10) + e_bhs(20)            // i=0; .cl: i<len? no -> .done
    c = c + e_ldrbO(6, 11, 5) + e_strbR(6, 0, 5) + e_addi(5, 5, 1) + e_b(0 - 20) // dst[i]=src[i]; i++
    c = c + e_strbR(31, 0, 10) + e_movr(30, 26) + e_ret()      // .done: dst[len]=0; restore x30; ret
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
    if op == "CALL" {                                                  // bl, or inlined bitwise builtin
        let cn = headName(ln)
        if cn == "bitAnd" { emit "28" }
        if cn == "bitOr"  { emit "28" }
        if cn == "bitXor" { emit "28" }
        if cn == "bitNot" { emit "20" }
        if cn == "shl"    { emit "28" }
        if cn == "shr"    { emit "28" }
        emit "4"
    }
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
    if op == "LT" || op == "GT" || op == "LTE" || op == "GTE" { emit 32 }
    if op == "EQ"  { emit 28 }     // polymorphic kr_eq (numeric OR strcmp)
    if op == "NEQ" { emit 36 }     // kr_eq + invert
    if op == "INDEX" { emit 28 }   // list[idx] -> kr_split (pop0+pop1+bl+push)
    if op == "SETFIELD" { emit 36 }  // p.x=v: pop val/env, name imm -> kr_setfield
    if op == "GETFIELD" { emit 28 }  // p.x: pop env, name imm -> kr_getfield
    if op == "BUILTIN" {
        let b = operand(ln)
        if startsWith(b, "kp") { emit 20 }   // pop + bl kpDisp + push (no movz between bl and push)
        if startsWith(b, "gcShadowCount") { emit 12 }
        if startsWith(b, "gcShadowPush") { emit 16 }
        if startsWith(b, "gcShadowPop") { emit 16 }
        if startsWith(b, "charCode") { emit 20 }
        if startsWith(b, "length") { emit 20 }  // collection count -> kr_count (BEFORE "len" to avoid strlen match)
        if startsWith(b, "len") { emit 40 }
        if startsWith(b, "toStr") { emit 32 }
        if startsWith(b, "toInt") { emit 20 }
        if startsWith(b, "fromCharCode") { emit 36 }
        if startsWith(b, "substring") { emit 36 }
        if startsWith(b, "isTruthy") { emit 24 }
        if startsWith(b, "min") { emit 32 }   // pop0+pop1+cmp+csel+push
        if startsWith(b, "max") { emit 32 }
        if startsWith(b, "hex") { emit 20 }   // pop0 + bl kr_hex + push
        if startsWith(b, "bin") { emit 20 }   // pop0 + bl kr_bin + push
        if startsWith(b, "padLeft")  { emit 68 }  // pop x2/x1/x0 + (stringify s if int) + bl + push
        if startsWith(b, "padRight") { emit 68 }
        if startsWith(b, "toUpper") { emit 20 }   // pop0 + bl + push
        if startsWith(b, "toLower") { emit 20 }
        if startsWith(b, "reverse") { emit 20 }
        if startsWith(b, "startsWith") { emit 28 }  // pop0+pop1 + bl + push
        if startsWith(b, "endsWith")   { emit 28 }
        if startsWith(b, "repeat")     { emit 28 }
        if startsWith(b, "contains")   { emit 28 }
        if startsWith(b, "indexOf")    { emit 28 }
        if startsWith(b, "trim")       { emit 20 }  // 1-arg: pop0 + bl + push
        if startsWith(b, "split")      { emit 28 }  // 2-arg (list, idx)
        if startsWith(b, "count")      { emit 20 }  // 1-arg (list)
        if startsWith(b, "abs")        { emit 28 }  // inline: pop+cmp+bge+neg+push
        if startsWith(b, "pow")        { emit 28 }  // 2-arg -> kr_pow
        if startsWith(b, "range 1")    { emit 24 }  // range(n): pop+movz x1,0+bl+push
        if startsWith(b, "range 2")    { emit 28 }  // range(start,end): pop0+pop1+bl+push
        if startsWith(b, "sbNew")      { emit 12 }  // 0-arg: bl + push
        if startsWith(b, "sbAppend")   { emit 28 }  // 2-arg (handle, s)
        if startsWith(b, "sbToString") { emit 20 }  // 1-arg (handle)
        if startsWith(b, "exit")       { emit 24 }  // inline: pop x0 + movz x8,93 + svc + push
        if startsWith(b, "bufNew ")    { emit 20 }  // alloc(size): pop+bl alloc+push
        if startsWith(b, "bufSetByte ") { emit 36 } // [buf+off]=val: 3 pops + strb + push
        if startsWith(b, "bufGetByte ") { emit 28 } // buf[off]: 2 pops + ldrb + push
        if startsWith(b, "readFile")   { emit 20 }  // 1-arg (path)
        if startsWith(b, "writeFile")  { emit 28 }  // 2-arg (path, content)
        if startsWith(b, "gcCollect")    { emit 12 }  // no-op (bump allocator): push 0
        if startsWith(b, "gcAllocCount") { emit 12 }  // stub: push 0
        if startsWith(b, "gcWalkAllocs") { emit 12 }  // stub: push 0
        if startsWith(b, "rdtsc")        { emit 24 }  // mrs cntvct_el0 + mask low 30 bits + push
        if startsWith(b, "structNew")  { emit 12 }  // push 0 (empty env)
        if startsWith(b, "envNew")     { emit 12 }
        if startsWith(b, "setField")   { emit 36 }  // 3-arg (env, name, val) -> kr_setfield
        if startsWith(b, "envSet")     { emit 36 }
        if startsWith(b, "getField")   { emit 28 }  // 2-arg (env, name) -> kr_getfield
        if startsWith(b, "envGet")     { emit 28 }
        if startsWith(b, "hasField")   { emit 28 }  // 2-arg -> kr_hasfield (1/0)
        if startsWith(b, "structFields") { emit 20 }  // 1-arg -> kr_structfields
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
    let plusOff   = strIntOff + 128   // str_int grew 100->128 for signed (negative) support
    let printOff  = plusOff + 212
    let kpDispOff = printOff + 64
    let atoiOff = kpDispOff + 32
    let substrOff = atoiOff + 44
    let hexOff = substrOff + 68    // substr is 68 bytes
    let binOff = hexOff + 144      // kr_hex is 144 bytes
    let padleftOff = binOff + 128  // kr_bin is 128 bytes
    let padrightOff = padleftOff + 136  // kr_padleft is 136 bytes
    let toupperOff = padrightOff + 140  // kr_padright is 140 bytes
    let tolowerOff = toupperOff + 112   // kr_toupper is 112 bytes
    let reverseOff = tolowerOff + 112   // kr_tolower is 112 bytes
    let startswithOff = reverseOff + 92 // kr_reverse is 92 bytes
    let endswithOff = startswithOff + 48  // kr_startswith is 48 bytes
    let repeatOff = endswithOff + 104   // kr_endswith is 104 bytes
    let containsOff = repeatOff + 120   // kr_repeat is 120 bytes
    let indexofOff = containsOff + 120  // kr_contains is 120 bytes
    let trimOff = indexofOff + 120      // kr_indexof is 120 bytes
    let splitOff = trimOff + 168        // kr_trim is 168 bytes
    let countOff = splitOff + 160       // kr_split is 160 bytes
    let powOff = countOff + 64          // kr_count is 64 bytes
    let rangeOff = powOff + 32          // kr_pow is 32 bytes
    let sbnewOff = rangeOff + 156       // kr_range is 156 bytes
    let sbappendOff = sbnewOff + 36     // kr_sbnew is 36 bytes
    let sbtostringOff = sbappendOff + 176  // kr_sbappend is 176 bytes
    let eqOff = sbtostringOff + 8        // kr_sbtostring is 8 bytes
    let indexOff = eqOff + 76            // kr_eq is 76 bytes
    let readfileOff = indexOff + 36      // kr_index is 36 bytes
    let writefileOff = readfileOff + 120 // kr_readfile is 120 bytes
    let setfieldOff = writefileOff + 96  // kr_writefile is 96 bytes
    let getfieldOff = setfieldOff + 44   // kr_setfield is 44 bytes
    let hasfieldOff = getfieldOff + 92   // kr_getfield is 92 bytes
    let structfieldsOff = hasfieldOff + 72  // kr_hasfield is 72 bytes
    let nlOff = structfieldsOff + 104     // kr_structfields is 104 bytes
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
    // Field-name table (for dot syntax: SETFIELD/GETFIELD names are immediates).
    // Stored right after the string literals; one entry per op (no dedup).
    let fieldBase = dataOff + strBytes
    let fieldBytes = 0
    i = 0
    while i < nlines {
        let lf = getLine(ir, i)
        let opf = opcode(lf)
        if opf == "SETFIELD" || opf == "GETFIELD" { fieldBytes = fieldBytes + (len(operand(lf)) + 1) }
        i = i + 1
    }
    let total = fieldBase + fieldBytes
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
    let fieldCursor = fieldBase       // running offset into the field-name table
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
        // s[idx] -> kr_index (i-th CHARACTER). pop0->x0=idx, pop1->x1=s. 28 bytes.
        // (Element access on a comma-collection uses split(coll, i), not [].)
        if op == "INDEX" { code = code + c_pop0() + c_pop1() + e_bl(indexOff - (off + 16)) + c_push()  off = off + 28 }
        // p.x = v -> kr_setfield(env, name_imm, val). Stack: val(top), env. 36 bytes.
        if op == "SETFIELD" {
            code = code + e_ldr0(2, 20) + e_addi(20, 20, 16)              // pop val -> x2
            code = code + e_ldr0(0, 20) + e_addi(20, 20, 16)              // pop env -> x0
            code = code + e_movz(1, fieldCursor % 65536) + e_movk16(1, 32512 + fieldCursor / 65536)  // x1 = &name
            code = code + e_bl(setfieldOff - (off + 24)) + c_push()
            fieldCursor = fieldCursor + (len(operand(ln)) + 1)
            off = off + 36
        }
        // p.x -> kr_getfield(env, name_imm). Stack: env(top). 28 bytes.
        if op == "GETFIELD" {
            code = code + e_ldr0(1, 20) + e_addi(20, 20, 16)              // pop env -> x1
            code = code + e_movz(0, fieldCursor % 65536) + e_movk16(0, 32512 + fieldCursor / 65536)  // x0 = &name
            code = code + e_bl(getfieldOff - (off + 16)) + c_push()
            fieldCursor = fieldCursor + (len(operand(ln)) + 1)
            off = off + 28
        }
        if op == "POP" { code = code + e_addi(20, 20, 16)  off = off + 4 }
        if op == "LT"  { code = code + c_pop1() + c_pop0() + e_cmp(0, 1) + e_cset(0, 10) + c_push()  off = off + 32 }
        if op == "GT"  { code = code + c_pop1() + c_pop0() + e_cmp(0, 1) + e_cset(0, 13) + c_push()  off = off + 32 }
        // EQ/NEQ are polymorphic (string contents OR numeric) via kr_eq.
        if op == "EQ"  { code = code + c_pop1() + c_pop0() + e_bl(eqOff - (off + 16)) + c_push()   off = off + 28 }
        if op == "NEQ" { code = code + c_pop1() + c_pop0() + e_bl(eqOff - (off + 16)) + e_cmpi0(0) + e_cset(0, 1) + c_push()   off = off + 36 }
        if op == "LTE" { code = code + c_pop1() + c_pop0() + e_cmp(0, 1) + e_cset(0, 12) + c_push()  off = off + 32 }
        if op == "GTE" { code = code + c_pop1() + c_pop0() + e_cmp(0, 1) + e_cset(0, 11) + c_push()  off = off + 32 }
        if op == "JUMP" { code = code + e_b(toInt(labelAbsOffset(ir, operand(ln))) - off)  off = off + 4 }
        if op == "JUMPIFNOT" { code = code + c_pop0() + e_cbz(0, toInt(labelAbsOffset(ir, operand(ln))) - (off + 8))  off = off + 12 }
        if op == "CALL" {
            let cn = headName(ln)
            // bitwise builtins arrive as generic CALLs (front-end emits CALL, not BUILTIN).
            if cn == "bitAnd" { code = code + c_pop0() + c_pop1() + e_and(0, 1, 0) + c_push()  off = off + 28 }
            if cn == "bitOr"  { code = code + c_pop0() + c_pop1() + e_orr(0, 1, 0) + c_push()  off = off + 28 }
            if cn == "bitXor" { code = code + c_pop0() + c_pop1() + e_eor(0, 1, 0) + c_push()  off = off + 28 }
            if cn == "bitNot" { code = code + c_pop0() + e_orn(0, 31, 0) + c_push()  off = off + 20 }
            if cn == "shl" { code = code + c_pop0() + c_pop1() + e_lslv(0, 1, 0) + c_push()  off = off + 28 }
            if cn == "shr" { code = code + c_pop0() + c_pop1() + e_lsrv(0, 1, 0) + c_push()  off = off + 28 }
            if cn != "bitAnd" && cn != "bitOr" && cn != "bitXor" && cn != "bitNot" && cn != "shl" && cn != "shr" {
                code = code + e_bl(toInt(funcVaddrOf(ir, cn)) - off)  off = off + 4
            }
        }
        if op == "BUILTIN" {
            let b = operand(ln)
            if startsWith(b, "isTruthy") { code = code + c_pop0() + e_cmpi0(0) + e_cset(0, 0) + c_push()  off = off + 24 }
            // min/max(a,b): pop b->x0, a->x1; cmp a,b; csel. cond LT=11 (min), GT=12 (max). 32 bytes.
            // (bitwise builtins arrive as CALL, handled in the CALL branch below.)
            if startsWith(b, "min") { code = code + c_pop0() + c_pop1() + e_cmp(1, 0) + e_csel(0, 1, 0, 11) + c_push()  off = off + 32 }
            if startsWith(b, "max") { code = code + c_pop0() + c_pop1() + e_cmp(1, 0) + e_csel(0, 1, 0, 12) + c_push()  off = off + 32 }
            // hex/bin(n) -> string (kr_hex/kr_bin). 20 bytes.
            if startsWith(b, "hex") { code = code + c_pop0() + e_bl(hexOff - (off + 8)) + c_push()  off = off + 20 }
            if startsWith(b, "bin") { code = code + c_pop0() + e_bl(binOff - (off + 8)) + c_push()  off = off + 20 }
            // padLeft/padRight(s, width, pad): pop pad->x2, width->x1, s->x0; bl; push. 36 bytes.
            // padLeft/padRight(s,width,pad): pop pad->x2,width->x1,s->x0; if s is an
            // int (<VBASE) stringify it via str_int (save/restore width+pad); then bl. 68B.
            if startsWith(b, "padLeft") {
                code = code + e_ldr0(2, 20) + e_addi(20, 20, 16)   // [0] pop pad->x2
                code = code + e_ldr0(1, 20) + e_addi(20, 20, 16)   // [8] pop width->x1
                code = code + e_ldr0(0, 20) + e_addi(20, 20, 16)   // [16] pop s->x0
                code = code + e_movzHi(9, 32512) + e_cmp(0, 9)     // [24] x9=VBASE; cmp
                code = code + e_bge(24)                            // [32] s>=VBASE -> .skip (56)
                code = code + e_movr(11, 1) + e_movr(12, 2)        // [36] save width,pad
                code = code + e_bl(strIntOff - (off + 44))         // [44] x0=str(s)
                code = code + e_movr(1, 11) + e_movr(2, 12)        // [48] restore width,pad
                code = code + e_bl(padleftOff - (off + 56))        // [56] .skip
                code = code + c_push()                             // [60]
                off = off + 68
            }
            if startsWith(b, "padRight") {
                code = code + e_ldr0(2, 20) + e_addi(20, 20, 16)
                code = code + e_ldr0(1, 20) + e_addi(20, 20, 16)
                code = code + e_ldr0(0, 20) + e_addi(20, 20, 16)
                code = code + e_movzHi(9, 32512) + e_cmp(0, 9)
                code = code + e_bge(24)
                code = code + e_movr(11, 1) + e_movr(12, 2)
                code = code + e_bl(strIntOff - (off + 44))
                code = code + e_movr(1, 11) + e_movr(2, 12)
                code = code + e_bl(padrightOff - (off + 56))
                code = code + c_push()
                off = off + 68
            }
            // 1-arg string->string transforms (kr_toupper/tolower/reverse). 20 bytes.
            if startsWith(b, "toUpper") { code = code + c_pop0() + e_bl(toupperOff - (off + 8)) + c_push()  off = off + 20 }
            if startsWith(b, "toLower") { code = code + c_pop0() + e_bl(tolowerOff - (off + 8)) + c_push()  off = off + 20 }
            if startsWith(b, "reverse") { code = code + c_pop0() + e_bl(reverseOff - (off + 8)) + c_push()  off = off + 20 }
            // 2-arg string builtins: pop0->x0 (2nd arg), pop1->x1 (1st arg); bl; push. 28 bytes.
            if startsWith(b, "startsWith") { code = code + c_pop0() + c_pop1() + e_bl(startswithOff - (off + 16)) + c_push()  off = off + 28 }
            if startsWith(b, "endsWith")   { code = code + c_pop0() + c_pop1() + e_bl(endswithOff - (off + 16)) + c_push()  off = off + 28 }
            if startsWith(b, "repeat")     { code = code + c_pop0() + c_pop1() + e_bl(repeatOff - (off + 16)) + c_push()  off = off + 28 }
            if startsWith(b, "contains")   { code = code + c_pop0() + c_pop1() + e_bl(containsOff - (off + 16)) + c_push()  off = off + 28 }
            if startsWith(b, "indexOf")    { code = code + c_pop0() + c_pop1() + e_bl(indexofOff - (off + 16)) + c_push()  off = off + 28 }
            if startsWith(b, "trim")       { code = code + c_pop0() + e_bl(trimOff - (off + 8)) + c_push()  off = off + 20 }
            if startsWith(b, "split")      { code = code + c_pop0() + c_pop1() + e_bl(splitOff - (off + 16)) + c_push()  off = off + 28 }
            if startsWith(b, "count")      { code = code + c_pop0() + e_bl(countOff - (off + 8)) + c_push()  off = off + 20 }
            // abs(x): inline. pop x0; if x0<0 neg; push. 28 bytes.
            if startsWith(b, "abs")        { code = code + c_pop0() + e_cmpi0(0) + e_bge(8) + e_subr(0, 31, 0) + c_push()  off = off + 28 }
            // pow(base, exp): pop0->x0=exp, pop1->x1=base; kr_pow. 28 bytes.
            if startsWith(b, "pow")        { code = code + c_pop0() + c_pop1() + e_bl(powOff - (off + 16)) + c_push()  off = off + 28 }
            // range(n): pop n->x0; start=0; kr_range. 24 bytes.
            if startsWith(b, "range 1")    { code = code + c_pop0() + e_movz(1, 0) + e_bl(rangeOff - (off + 12)) + c_push()  off = off + 24 }
            // range(start,end): pop end->x0, start->x1; kr_range. 28 bytes.
            if startsWith(b, "range 2")    { code = code + c_pop0() + c_pop1() + e_bl(rangeOff - (off + 16)) + c_push()  off = off + 28 }
            // StringBuilder: sbNew (0-arg), sbAppend (handle,s -> x1=handle,x0=s), sbToString (handle).
            if startsWith(b, "sbNew")      { code = code + e_bl(sbnewOff - off) + c_push()  off = off + 12 }
            if startsWith(b, "sbAppend")   { code = code + c_pop0() + c_pop1() + e_bl(sbappendOff - (off + 16)) + c_push()  off = off + 28 }
            if startsWith(b, "sbToString") { code = code + c_pop0() + e_bl(sbtostringOff - (off + 8)) + c_push()  off = off + 20 }
            // exit(code): pop x0; SYS_exit(93); (push is dead, never reached). 24 bytes.
            if startsWith(b, "exit")       { code = code + c_pop0() + e_movz(8, 93) + e_svc() + c_push()  off = off + 24 }
            // bufNew(size): alloc(size) -> ptr. pop0->x0=size; bl alloc; push. 20 bytes.
            if startsWith(b, "bufNew ")    { code = code + c_pop0() + e_bl(allocOff - (off + 8)) + c_push()  off = off + 20 }
            // bufSetByte(buf, off, val): 3-arg. pop val->x2, off->x1, buf->x0; strb w2,[x0,x1]; push buf. 36 bytes.
            if startsWith(b, "bufSetByte ") { code = code + e_ldr0(2, 20) + e_addi(20, 20, 16) + e_ldr0(1, 20) + e_addi(20, 20, 16) + e_ldr0(0, 20) + e_addi(20, 20, 16) + e_strbR(2, 0, 1) + c_push()  off = off + 36 }
            // bufGetByte(buf, off): pop0->x0=off, pop1->x1=buf; ldrb w0,[x1,x0]; push. 28 bytes.
            if startsWith(b, "bufGetByte ") { code = code + c_pop0() + c_pop1() + e_ldrbO(0, 1, 0) + c_push()  off = off + 28 }
            // readFile(path): pop0->x0=path; kr_readfile. 20 bytes.
            if startsWith(b, "readFile")   { code = code + c_pop0() + e_bl(readfileOff - (off + 8)) + c_push()  off = off + 20 }
            // writeFile(path, content): pop0->x0=content, pop1->x1=path; kr_writefile. 28 bytes.
            if startsWith(b, "writeFile")  { code = code + c_pop0() + c_pop1() + e_bl(writefileOff - (off + 16)) + c_push()  off = off + 28 }
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
            // GC builtins: no-op for a bump allocator (no GC). Push 0.
            if startsWith(b, "gcCollect")    { code = code + e_movz(0, 0) + c_push()  off = off + 12 }
            if startsWith(b, "gcAllocCount") { code = code + e_movz(0, 0) + c_push()  off = off + 12 }
            if startsWith(b, "gcWalkAllocs") { code = code + e_movz(0, 0) + c_push()  off = off + 12 }
            // rdtsc: mrs x0,cntvct_el0; keep low 30 bits (<<34>>34) so it fits the int tag. +push.
            if startsWith(b, "rdtsc")        { code = code + wordHL(54587, 57408) + e_movz(1, 34) + e_lslv(0, 0, 1) + e_lsrv(0, 0, 1) + c_push()  off = off + 24 }
            // structs (env linked list). structNew/envNew -> empty env (0).
            if startsWith(b, "structNew")  { code = code + e_movz(0, 0) + c_push()  off = off + 12 }
            if startsWith(b, "envNew")     { code = code + e_movz(0, 0) + c_push()  off = off + 12 }
            // setField(env,name,val): 3-arg pop val->x2,name->x1,env->x0; kr_setfield. 36 bytes.
            if startsWith(b, "setField")   { code = code + e_ldr0(2, 20) + e_addi(20, 20, 16) + e_ldr0(1, 20) + e_addi(20, 20, 16) + e_ldr0(0, 20) + e_addi(20, 20, 16) + e_bl(setfieldOff - (off + 24)) + c_push()  off = off + 36 }
            if startsWith(b, "envSet")     { code = code + e_ldr0(2, 20) + e_addi(20, 20, 16) + e_ldr0(1, 20) + e_addi(20, 20, 16) + e_ldr0(0, 20) + e_addi(20, 20, 16) + e_bl(setfieldOff - (off + 24)) + c_push()  off = off + 36 }
            // getField(env,name): pop name->x0, env->x1; kr_getfield. 28 bytes.
            if startsWith(b, "getField")   { code = code + c_pop0() + c_pop1() + e_bl(getfieldOff - (off + 16)) + c_push()  off = off + 28 }
            if startsWith(b, "envGet")     { code = code + c_pop0() + c_pop1() + e_bl(getfieldOff - (off + 16)) + c_push()  off = off + 28 }
            // hasField(env,name): pop name->x0, env->x1; kr_hasfield -> 1/0. 28 bytes.
            if startsWith(b, "hasField")   { code = code + c_pop0() + c_pop1() + e_bl(hasfieldOff - (off + 16)) + c_push()  off = off + 28 }
            // structFields(env): pop env->x0; kr_structfields. 20 bytes.
            if startsWith(b, "structFields") { code = code + c_pop0() + e_bl(structfieldsOff - (off + 8)) + c_push()  off = off + 20 }
            // charCode(s) -> first byte of s (int). 20 bytes.
            if startsWith(b, "charCode") {
                let kc = sbNew()
                kc = sbAppend(kc, c_pop0())
                kc = sbAppend(kc, e_ldrb0(0, 0))
                kc = sbAppend(kc, c_push())
                code = code + sbToString(kc)
                off = off + 20
            }
            // length(collection) -> element count (kr_count). MUST precede "len " so
            // "length" isn't mistaken for strlen. 20 bytes.
            if startsWith(b, "length") { code = code + c_pop0() + e_bl(countOff - (off + 8)) + c_push()  off = off + 20 }
            // len(s) -> strlen (int). "len " (trailing space) so it doesn't match "length". 40 bytes.
            if startsWith(b, "len ") {
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
                kc = sbAppend(kc, e_bge(8))                  // signed>=VBASE = pointer -> already a string
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
            // substring(s, start, end) -> s[start:end] (kr_substring). 36 bytes.
            if startsWith(b, "substring") {
                let kc = sbNew()
                kc = sbAppend(kc, e_ldr0(2, 20) + e_addi(20, 20, 16))   // pop end -> x2
                kc = sbAppend(kc, e_ldr0(1, 20) + e_addi(20, 20, 16))   // pop start -> x1
                kc = sbAppend(kc, e_ldr0(0, 20) + e_addi(20, 20, 16))   // pop s -> x0
                kc = sbAppend(kc, e_bl(substrOff - (off + 24)))         // x0 = s[start:end]
                kc = sbAppend(kc, c_push())
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
    // built via sbAppend (not one long + chain) — the x86 backend miscompiles
    // long concat chains in this position and silently drops a term.
    let bb = sbNew()
    bb = sbAppend(bb, code)
    bb = sbAppend(bb, emitAlloc())
    bb = sbAppend(bb, emitStrInt(allocOff, strIntOff))
    bb = sbAppend(bb, emitPlus(strIntOff, allocOff, plusOff))
    bb = sbAppend(bb, emitPrint(nlOff))
    bb = sbAppend(bb, emitKpDisp(kpDispOff, strIntOff, printOff))
    bb = sbAppend(bb, emitAtoi())
    bb = sbAppend(bb, emitSubstr(allocOff, substrOff))
    bb = sbAppend(bb, emitHex(allocOff, hexOff))
    bb = sbAppend(bb, emitBin(allocOff, binOff))
    bb = sbAppend(bb, emitPadLeft(allocOff, padleftOff))
    bb = sbAppend(bb, emitPadRight(allocOff, padrightOff))
    bb = sbAppend(bb, emitToUpper(allocOff, toupperOff))
    bb = sbAppend(bb, emitToLower(allocOff, tolowerOff))
    bb = sbAppend(bb, emitReverse(allocOff, reverseOff))
    bb = sbAppend(bb, emitStartsWith())
    bb = sbAppend(bb, emitEndsWith())
    bb = sbAppend(bb, emitRepeat(allocOff, repeatOff))
    bb = sbAppend(bb, emitContains())
    bb = sbAppend(bb, emitIndexOf())
    bb = sbAppend(bb, emitTrim(allocOff, trimOff))
    bb = sbAppend(bb, emitSplit(allocOff, splitOff))
    bb = sbAppend(bb, emitCount())
    bb = sbAppend(bb, emitPow())
    bb = sbAppend(bb, emitRange(allocOff, strIntOff, rangeOff))
    bb = sbAppend(bb, emitSbNew(allocOff, sbnewOff))
    bb = sbAppend(bb, emitSbAppend(allocOff, sbappendOff))
    bb = sbAppend(bb, emitSbToString())
    bb = sbAppend(bb, emitEq())
    bb = sbAppend(bb, emitIndex(allocOff, indexOff))
    bb = sbAppend(bb, emitReadFile(allocOff, readfileOff))
    bb = sbAppend(bb, emitWriteFile())
    bb = sbAppend(bb, emitSetField(allocOff, setfieldOff))
    bb = sbAppend(bb, emitGetField(allocOff, getfieldOff))
    bb = sbAppend(bb, emitHasField())
    bb = sbAppend(bb, emitStructFields(allocOff, plusOff, structfieldsOff))
    bb = sbAppend(bb, "")     // guards: x86 backend drops trailing sbAppends (scales w/ chain len)
    bb = sbAppend(bb, "")
    bb = sbAppend(bb, "")
    bb = sbAppend(bb, "")
    bb = sbAppend(bb, "")
    bb = sbAppend(bb, "")
    bb = sbAppend(bb, "")
    bb = sbAppend(bb, "")
    bb = sbAppend(bb, "")
    bb = sbAppend(bb, "")
    bb = sbAppend(bb, "")
    bb = sbAppend(bb, "")
    bb = sbAppend(bb, "")
    bb = sbAppend(bb, "")
    bb = sbAppend(bb, "")
    bb = sbAppend(bb, "")
    let body = sbToString(bb)

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
    // field-name table (dot syntax), in SETFIELD/GETFIELD order — matches fieldCursor
    i = 0
    while i < nlines {
        let ln = getLine(ir, i)
        let opf = opcode(ln)
        if opf == "SETFIELD" || opf == "GETFIELD" {
            let s = operand(ln)
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
