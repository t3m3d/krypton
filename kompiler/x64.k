// x64.k — Krypton IR to Windows PE64 native binary emitter
// Usage: kcc kompiler/x64.k <file.kir> -o <output.exe>
//   or:  kcc kompiler/x64.k <file.kir> > output_hex.txt
//
// Reads Krypton IR (.kir), emits a Windows x64 PE executable.
// The executable imports from krypton_rt.dll (ship alongside .exe).
// No C compiler or assembler required.

// ── IR helpers (shared with optimize.k / llvm.k) ─────────────────

func irGetOp(line) {
    let t = trim(line)
    let i = 0
    while i < len(t) && t[i] != " " { i += 1 }
    emit substring(t, 0, i)
}

func irGetArg1(line) {
    let t = trim(line)
    let i = 0
    while i < len(t) && t[i] != " " { i += 1 }
    if i >= len(t) { emit "" }
    i += 1
    let start = i
    while i < len(t) && t[i] != " " { i += 1 }
    emit trim(substring(t, start, i))
}

func irGetArg2(line) {
    let t = trim(line)
    let i = 0
    let sp = 0
    while i < len(t) {
        if t[i] == " " {
            sp += 1
            if sp == 2 { emit trim(substring(t, i + 1, len(t))) }
        }
        i += 1
    }
    emit ""
}

func irGetRest(line) {
    let t = trim(line)
    let i = 0
    while i < len(t) && t[i] != " " { i += 1 }
    if i >= len(t) { emit "" }
    emit trim(substring(t, i + 1, len(t)))
}

// ── Binary encoding helpers ───────────────────────────────────────
// All bytes represented as 2-char uppercase hex strings
// Final output assembled with writeBytes()

let HEX = "0123456789ABCDEF"

func hexByte(n) {
    let v = toInt(n)
    if v < 0 { v = v + 256 }
    if v > 255 { v = v % 256 }
    emit "x" + HEX[v / 16] + HEX[v % 16]
}

func hexWord(n) {
    let v = toInt(n)
    // little-endian 16-bit
    emit hexByte(v % 256) + hexByte((v / 256) % 256)
}

func hexDword(n) {
    let v = toInt(n)
    // little-endian 32-bit, two's complement (handles negative displacements)
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
    // little-endian 64-bit, upper 4 bytes = 0
    emit hexDword(n) + hexDword(0)
}

func hexQword64(lo, hi) {
    emit hexDword(lo) + hexDword(hi)
}

func hexPad(n) {
    // emit n zero bytes
    let out = ""
    let i = 0
    while i < n {
        out = out + hexByte(0)
        i += 1
    }
    emit out
}

func hexStr(s) {
    // emit string bytes (not null-terminated, just raw chars)
    let out = ""
    let i = 0
    while i < len(s) {
        out = out + hexByte(charCode(s[i]))
        i += 1
    }
    emit out
}

func hexStrZ(s) {
    // emit null-terminated string
    emit hexStr(s) + hexByte(0)
}

func hexPadTo(current, target) {
    // emit padding to reach target offset
    let n = target - current
    if n <= 0 { emit "" }
    emit hexPad(n)
}

// ── x86-64 instruction encoder ───────────────────────────────────
// Register numbers: rax=0 rcx=1 rdx=2 rbx=3 rsp=4 rbp=5 rsi=6 rdi=7
//                  r8=8  r9=9  r10=10 r11=11 r12=12 r13=13 r14=14 r15=15

func x64_rex(w, r, x, b) {
    // REX byte: 0100 WRXB
    let v = 64 + w * 8 + r * 4 + x * 2 + b
    emit hexByte(v)
}

func x64_modrm(mod, reg, rm) {
    emit hexByte(mod * 64 + (reg % 8) * 8 + (rm % 8))
}

func x64_push_r(r) {
    // PUSH r64
    if r >= 8 { emit "41" + hexByte(80 + r - 8) }
    else { emit hexByte(80 + r) }
}

func x64_pop_r(r) {
    // POP r64
    if r >= 8 { emit "41" + hexByte(88 + r - 8) }
    else { emit hexByte(88 + r) }
}

func x64_ret() { emit "C3" }

func x64_nop() { emit "90" }

func x64_sub_rsp(n) {
    // SUB RSP, imm8
    emit "4883EC" + hexByte(n)
}

func x64_add_rsp(n) {
    // ADD RSP, imm8
    emit "4883C4" + hexByte(n)
}

func x64_mov_rr(dst, src) {
    // MOV r64, r64  (REX.W 89 ModRM)
    let rexB = 0
    let rexR = 0
    if src >= 8 { rexR = 1 }
    if dst >= 8 { rexB = 1 }
    emit x64_rex(1, rexR, 0, rexB) + "89" + x64_modrm(3, src % 8, dst % 8)
}

func x64_mov_r_imm32(r, imm) {
    // MOV r32, imm32 (zero-extends to 64-bit)
    if r >= 8 { emit "41" + hexByte(184 + r - 8) + hexDword(imm) }
    else { emit hexByte(184 + r) + hexDword(imm) }
}

func x64_mov_r_imm64(r, lo, hi) {
    // MOV r64, imm64
    let rexB = 0
    if r >= 8 { rexB = 1 }
    emit x64_rex(1, 0, 0, rexB) + hexByte(184 + r % 8) + hexDword(lo) + hexDword(hi)
}

func x64_call_rel32(offset) {
    // CALL rel32 (relative to next instruction)
    emit "E8" + hexDword(offset)
}

func x64_jmp_rel32(offset) {
    emit "E9" + hexDword(offset)
}

func x64_jmp_rel8(offset) {
    emit "EB" + hexByte(offset)
}

func x64_jz_rel8(offset) {
    emit "74" + hexByte(offset)
}

func x64_jnz_rel8(offset) {
    emit "75" + hexByte(offset)
}

func x64_test_rax_rax() {
    emit "4885C0"
}

func x64_xor_eax_eax() {
    emit "33C0"
}

func x64_call_mem_rip(offset) {
    // CALL [RIP + offset]  (call through IAT entry)
    // FF 15 disp32
    emit "FF15" + hexDword(offset)
}

func x64_lea_rcx_rip(offset) {
    // LEA RCX, [RIP + offset]
    emit "488D0D" + hexDword(offset)
}

func x64_lea_rdx_rip(offset) {
    // LEA RDX, [RIP + offset]
    emit "488D15" + hexDword(offset)
}

func x64_mov_rcx_rsp_slot(slot) {
    // MOV RCX, [RSP + slot*8 + 32]  (shadow space is 32 bytes)
    let off = slot * 8 + 32
    emit "488B4C24" + hexByte(off)
}

func x64_mov_rsp_slot_rax(slot) {
    // MOV [RSP + slot*8 + 32], RAX
    let off = slot * 8 + 32
    emit "48894424" + hexByte(off)
}

func x64_push_imm8(v) {
    emit "6A" + hexByte(v)
}

func x64_xor_r9_r9() { emit "4D33C9" }   // XOR R9, R9
func x64_xor_r8_r8() { emit "4533C0" }   // XOR R8, R8

// ── PE layout constants ───────────────────────────────────────────
// Image base: 0x140000000 (standard PE32+ base)
// File alignment: 0x200
// Section alignment: 0x1000
// Header size: 0x200 (fits in one file-aligned block)
// .text RVA:  0x1000, file offset 0x200
// .rdata RVA: computed from .text size rounded up to section alignment
// .bss/.data is handled by the runtime DLL, not needed here

let PE_IMAGE_BASE_LO = 0           // 0x140000000 split: lo=0, hi=0x1
let PE_IMAGE_BASE_HI = 1
let PE_FILE_ALIGN = 512            // 0x200
let PE_SECT_ALIGN = 4096           // 0x1000
let PE_HEADER_SIZE = 512           // 0x200
let PE_TEXT_RVA = 4096             // 0x1000

func alignUp(v, a) {
    let rem = v % a
    if rem == 0 { emit v }
    emit v + (a - rem)
}

// ── String / constant table ───────────────────────────────────────
// Collect all PUSH string values and assign offsets in .rdata

func irUndoPrimary(s) {
    // Reverse irPrimary's escaping: \\n -> \n and \\t -> \t
    // Use replace (not char-by-char loop) to avoid kr_plus numeric-addition bug:
    // e.g. building "20" char-by-char gives kr_plus("2","0")=2 (adds instead of concat)
    let out = replace(s, "\\" + "\\" + "n", "\\" + "n")
    out = replace(out, "\\" + "\\" + "t", "\\" + "t")
    emit out
}

func irStrLen(s) {
    // Byte count of IR string in rdata: undo irPrimary then apply expandEscapes rules
    let tv = irUndoPrimary(s)
    let m = len(tv)
    let bytes = 0
    let j = 0
    while j < m {
        if tv[j] == "\\" && j + 1 < m {
            let c = tv[j + 1]
            if c == "n" || c == "t" || c == "r" || c == "\\" || c == "\"" {
                bytes += 1
            } else {
                bytes += 2
            }
            j += 2
        } else {
            bytes += 1
            j += 1
        }
    }
    emit bytes
}

func hexStrIR(s) {
    // Emit hex bytes of IR string: undo irPrimary then apply expandEscapes
    // Each byte uses hexByte() = "xXX" (3 chars), matching the rest of the PE builder
    let tv = irUndoPrimary(s)
    let m = len(tv)
    let out = ""
    let j = 0
    while j < m {
        let ch = tv[j]
        if ch == "\\" && j + 1 < m {
            let c = tv[j + 1]
            if c == "n" {
                out = out + hexByte(10)
            } else if c == "t" {
                out = out + hexByte(9)
            } else if c == "r" {
                out = out + hexByte(13)
            } else if c == "\\" {
                out = out + hexByte(92)
            } else if c == "\"" {
                out = out + hexByte(34)
            } else {
                out = out + hexByte(92) + hexByte(charCode(c))
            }
            j += 2
        } else {
            out = out + hexByte(charCode(ch))
            j += 1
        }
    }
    emit out
}

func collectStrings(ir) {
    // Return newline-separated list of unique string values (no quotes)
    let lines = ir
    let count = lineCount(lines)
    let strs = ""
    let i = 0
    while i < count {
        let line = getLine(lines, i)
        let op = irGetOp(line)
        if op == "PUSH" {
            let val = trim(irGetRest(line))
            let inner = val
            if startsWith(val, "\"") { inner = substring(val, 1, len(val) - 1) }
            // Add if not already present (handles both quoted and unquoted/numeric)
            if !contains("\n" + strs + "\n", "\n" + inner + "\n") {
                if len(strs) > 0 { strs = strs + "\n" }
                strs = strs + inner
            }
        }
        i += 1
    }
    emit strs
}

func strOffset(strs, target) {
    // Find byte offset of target string in the packed string table
    let count = lineCount(strs)
    let off = 0
    let i = 0
    while i < count {
        let s = getLine(strs, i)
        if s == target { emit off }
        off += irStrLen(s) + 1  // +1 for null terminator
        i += 1
    }
    emit -1
}

func totalStrBytes(strs) {
    let count = lineCount(strs)
    let total = 0
    let i = 0
    while i < count {
        total += irStrLen(getLine(strs, i)) + 1
        i += 1
    }
    emit total
}

func emitStringTable(strs) {
    let count = lineCount(strs)
    let out = ""
    let i = 0
    while i < count {
        out = out + hexStrIR(getLine(strs, i)) + hexByte(0)
        i += 1
    }
    emit out
}

// ── Import table builder ──────────────────────────────────────────
// Two DLLs: kernel32.dll + krypton_rt.dll
// kernel32 imports: ExitProcess
// krypton_rt imports: kr_str, kr_plus, kr_sub, kr_mul, kr_div, kr_mod,
//                     kr_neg, kr_eq, kr_neq, kr_lt, kr_gt, kr_lte, kr_gte,
//                     kr_truthy, kr_print, kr_printerr, kr_exit

let KR32_FUNCS = "ExitProcess"
let KRRT_FUNCS = "kr_str,kr_plus,kr_sub,kr_mul,kr_div,kr_mod,kr_neg,kr_not,kr_eq,kr_neq,kr_lt,kr_gt,kr_lte,kr_gte,kr_truthy,kr_print,kr_printerr,kr_printl,kr_exit,kr_len,kr_idx,kr_substring,kr_startswith,kr_contains,kr_indexof,kr_trim,kr_toint,kr_charcode,kr_isdigit,kr_replace,kr_split,kr_readfile,kr_arg,kr_sbnew,kr_sbappend,kr_sbtostring,kr_init_args,kr_linecount,kr_getline,kr_count,kr_argcount,kr_writefile,kr_writebytes,kr_range,kr_length"

// Map IR builtin names to krypton_rt.dll function names
func resolveBuiltin(name) {
    if name == "kp"          { emit "kr_print" }
    if name == "print"       { emit "kr_print" }
    if name == "printErr"    { emit "kr_printerr" }
    if name == "exit"        { emit "kr_exit" }
    if name == "len"         { emit "kr_len" }
    if name == "substring"   { emit "kr_substring" }
    if name == "startsWith"  { emit "kr_startswith" }
    if name == "contains"    { emit "kr_contains" }
    if name == "indexOf"     { emit "kr_indexof" }
    if name == "trim"        { emit "kr_trim" }
    if name == "toInt"       { emit "kr_toint" }
    if name == "charCode"    { emit "kr_charcode" }
    if name == "isDigit"     { emit "kr_isdigit" }
    if name == "replace"     { emit "kr_replace" }
    if name == "split"       { emit "kr_split" }
    if name == "range"       { emit "kr_range" }
    if name == "length"      { emit "kr_length" }
    if name == "readFile"    { emit "kr_readfile" }
    if name == "arg"         { emit "kr_arg" }
    if name == "sbNew"       { emit "kr_sbnew" }
    if name == "sbAppend"    { emit "kr_sbappend" }
    if name == "sbToString"  { emit "kr_sbtostring" }
    if name == "lineCount"   { emit "kr_linecount" }
    if name == "getLine"     { emit "kr_getline" }
    if name == "count"       { emit "kr_count" }
    if name == "argCount"    { emit "kr_argcount" }
    if name == "writeFile"   { emit "kr_writefile" }
    if name == "writeBytes"  { emit "kr_writebytes" }
    if name == "printl"      { emit "kr_printl" }
    emit name
}

func countFuncs(csv) {
    // count comma-separated items
    let n = 1
    let i = 0
    while i < len(csv) {
        if csv[i] == "," { n += 1 }
        i += 1
    }
    emit n
}

func funcAt(csv, idx) {
    let n = 0
    let start = 0
    let i = 0
    while i < len(csv) {
        if csv[i] == "," {
            if n == idx { emit substring(csv, start, i) }
            n += 1
            start = i + 1
        }
        i += 1
    }
    emit substring(csv, start, len(csv))
}

func iatIndexOf(funcName) {
    // Returns index within its own DLL's IAT, prefixed by "k32:" or "rt:"
    let k32count = countFuncs(KR32_FUNCS)
    let i = 0
    while i < k32count {
        if funcAt(KR32_FUNCS, i) == funcName { emit "k32:" + i }
        i += 1
    }
    let rtcount = countFuncs(KRRT_FUNCS)
    let j = 0
    while j < rtcount {
        if funcAt(KRRT_FUNCS, j) == funcName { emit "rt:" + j }
        j += 1
    }
    emit "none"
}

// Compute IAT entry RVA given the base RVAs of k32 and rt IATs
func iatEntryRvaFor(funcName, iatK32BaseRva, iatRtBaseRva) {
    let idxStr = iatIndexOf(funcName)
    if startsWith(idxStr, "k32:") {
        let idx = toInt(substring(idxStr, 4, len(idxStr)))
        emit iatK32BaseRva + idx * 8
    }
    if startsWith(idxStr, "rt:") {
        let idx = toInt(substring(idxStr, 3, len(idxStr)))
        emit iatRtBaseRva + idx * 8
    }
    emit -1
}

// IAT total entries (with null terminators between DLLs)
func iatTotalEntries() {
    emit countFuncs(KR32_FUNCS) + 1 + countFuncs(KRRT_FUNCS) + 1
}

// ── Instruction byte-size calculator ─────────────────────────────
// Returns the exact number of bytes emitFuncFull emits for each IR op.
// Used for label position pre-pass and accurate function size calculation.
// Frame-based virtual stack: values stored in RSP slots, no hardware PUSH/POP.
func instrSize(op, a1, a2) {
    if op == "PARAM" { emit 0 }          // handled in prologue pre-loop
    if op == "LOCAL" { emit 10 }         // XOR EAX(2) + MOV [RSP+off32](8)
    if op == "PUSH"  { emit 15 }         // LEA RAX(7) + MOV[RSP+vst](8)
    if op == "LOAD"  { emit 16 }         // MOV RAX from local(8) + MOV RAX to vstack(8)
    if op == "STORE" { emit 16 }         // MOV RAX from vstack(8) + MOV RAX to local(8)
    if op == "RETURN"{ emit 16 }         // MOV RAX from vstack(8) + ADD RSP(7) + RET(1)
    if op == "POP"   { emit 0 }          // just vsp--, no code emitted
    if op == "ADD" || op == "SUB" || op == "MUL" || op == "DIV" || op == "MOD" || op == "CAT" {
        emit 30  // MOV RDX(8) + MOV RCX(8) + CALL[IAT](6) + MOV[vst](8)
    }
    if op == "EQ" || op == "NEQ" || op == "LT" || op == "GT" || op == "LTE" || op == "GTE" {
        emit 30
    }
    if op == "NEG" || op == "NOT" { emit 22 }   // MOV RCX(8) + CALL[IAT](6) + MOV[vst](8)
    if op == "CALL" || op == "BUILTIN" {
        let argc2 = toInt(a2)
        let loads = argc2
        if loads > 4 { loads = 4 }
        // Extra args (5th+): each costs 8+8=16 bytes (MOV RAX from vst + MOV to [RSP+32])
        let extraArgSz = 0
        if argc2 >= 5 { extraArgSz = extraArgSz + 16 }
        if argc2 >= 6 { extraArgSz = extraArgSz + 16 }
        // loads*MOV(8) + extraArgSz + CALL(6or5) + MOV result(8)
        let callSz = 6
        let resolved = resolveBuiltin(a1)
        let idxStr = iatIndexOf(resolved)
        if idxStr == "none" { callSz = 5 }
        emit loads * 8 + extraArgSz + callSz + 8
    }
    if op == "LABEL"     { emit 0 }
    if op == "JUMP"      { emit 5 }          // E9 + disp32
    if op == "JUMPIF"    { emit 22 }         // MOV RCX(8)+CALL(6)+TEST(2)+JCC(6)
    if op == "JUMPIFNOT" { emit 22 }
    if op == "BREAK"     { emit 5 }          // JMP rel32
    if op == "INDEX"     { emit 30 }         // MOV RDX(8)+MOV RCX(8)+CALL(6)+MOV[vst](8)
    if op == "END"       { emit 10 }         // XOR EAX(2) + ADD RSP(7) + RET(1)
    emit 0
}

// Exact byte size of a compiled function body
func funcByteSize(bodyLines) {
    let count = lineCount(bodyLines)
    // Compute frame size to determine prologue size
    let lcount2 = 0
    let lpi = 0
    while lpi < count {
        let lline = getLine(bodyLines, lpi)
        let lop = irGetOp(lline)
        if lop == "PARAM" || lop == "LOCAL" { lcount2 += 1 }
        if lop != "PARAM" && lop != "LOCAL" && lop != "FUNC" { break }
        lpi += 1
    }
    let frsz = 72 + lcount2 * 8 + 12 * 8  // 72=shadow+extraargs, lcount locals, 12 vstack slots
    if frsz % 16 != 8 {
        let rem2 = frsz % 16
        if rem2 < 8 { frsz = frsz + (8 - rem2) }
        else { frsz = frsz + (24 - rem2) }
    }
    let sz = subRspNSz(frsz)   // SUB RSP prologue (always 7)
    // Param saves (pre-loop) — 8 bytes for params 0-3 (reg→local), 16 for params 4+ (stack→local)
    let pi = 0
    let paramCount = 0
    while pi < count {
        let line = getLine(bodyLines, pi)
        let op = irGetOp(line)
        if op == "PARAM" {
            if paramCount < 4 { sz += 8 } else { sz += 16 }
            paramCount += 1
        }
        if op != "PARAM" && op != "LOCAL" && op != "FUNC" { break }
        pi += 1
    }
    // Main loop
    let i = 0
    while i < count {
        let line = getLine(bodyLines, i)
        let op = irGetOp(line)
        sz += instrSize(op, irGetArg1(line), irGetArg2(line))
        i += 1
    }
    emit sz
}

// Pre-pass: collect label byte positions within a function body
func collectLabelPositions(bodyLines) {
    let count = lineCount(bodyLines)
    // Compute frame size for prologue size
    let lcount3 = 0
    let lpi3 = 0
    while lpi3 < count {
        let lline3 = getLine(bodyLines, lpi3)
        let lop3 = irGetOp(lline3)
        if lop3 == "PARAM" || lop3 == "LOCAL" { lcount3 += 1 }
        if lop3 != "PARAM" && lop3 != "LOCAL" && lop3 != "FUNC" { break }
        lpi3 += 1
    }
    let frsz3 = 72 + lcount3 * 8 + 12 * 8
    if frsz3 % 16 != 8 {
        let rem3 = frsz3 % 16
        if rem3 < 8 { frsz3 = frsz3 + (8 - rem3) }
        else { frsz3 = frsz3 + (24 - rem3) }
    }
    let pos = subRspNSz(frsz3)
    // Param saves — 8 bytes for params 0-3 (reg→local), 16 for params 4+ (stack→local)
    let pi = 0
    let paramCount3 = 0
    while pi < count {
        let line = getLine(bodyLines, pi)
        let op = irGetOp(line)
        if op == "PARAM" {
            if paramCount3 < 4 { pos += 8 } else { pos += 16 }
            paramCount3 += 1
        }
        if op != "PARAM" && op != "LOCAL" && op != "FUNC" { break }
        pi += 1
    }
    let labelMap = ""
    let i = 0
    while i < count {
        let line = getLine(bodyLines, i)
        let op = irGetOp(line)
        let a1 = irGetArg1(line)
        if op == "LABEL" {
            if len(labelMap) > 0 { labelMap = labelMap + "\n" }
            labelMap = labelMap + a1 + ":" + pos
        }
        pos += instrSize(op, a1, irGetArg2(line))
        i += 1
    }
    emit labelMap
}

// Look up label byte offset in "name:off\n..." map
func labelLookup(labelMap, name) {
    let count = lineCount(labelMap)
    let i = 0
    while i < count {
        let entry = getLine(labelMap, i)
        let ci = 0
        while ci < len(entry) && entry[ci] != ":" { ci += 1 }
        if substring(entry, 0, ci) == name {
            emit toInt(substring(entry, ci + 1, len(entry)))
        }
        i += 1
    }
    emit -1
}

// Look up function byte offset in "name:off\n..." map
func funcOffsetLookup(offsets, name) {
    let count = lineCount(offsets)
    let i = 0
    while i < count {
        let entry = getLine(offsets, i)
        let ci = 0
        while ci < len(entry) && entry[ci] != ":" { ci += 1 }
        if substring(entry, 0, ci) == name {
            emit toInt(substring(entry, ci + 1, len(entry)))
        }
        i += 1
    }
    emit -1
}

// ── Code generation ───────────────────────────────────────────────
// Each IR function compiles to x86-64 calling Windows x64 ABI.
// All Krypton values are char* (8-byte pointers).
//
// Stack frame layout per function:
//   [RSP+0]      return address (after call)
//   [RSP+8]      shadow space (32 bytes = 4 * 8)
//   [RSP+40]     local[0]   (8 bytes each)
//   [RSP+48]     local[1]
//   ...
//   Total frame: 32 (shadow) + locals*8 + alignment

// We maintain a "virtual stack" during IR interpretation.
// Values are passed in RCX, RDX, R8, R9, then stack for calls.
// Between IR instructions we keep values in actual RSP-relative slots.

// Function metadata: pass as global context strings
let g_funcName = ""
let g_locals = ""       // newline-separated local variable names
let g_labelMap = ""     // "labelName:byteOffset\n" entries

func localIndex(name) {
    let count = lineCount(g_locals)
    let i = 0
    while i < count {
        if getLine(g_locals, i) == name { emit i }
        i += 1
    }
    emit -1
}

func localCount() {
    if len(g_locals) == 0 { emit 0 }
    emit lineCount(g_locals)
}

// Slot offset from RSP for a local.
// Frame: [RSP+0..31]=shadow, [RSP+32..71]=extra args (5th-9th arg pass), [RSP+72..]=locals
func localRspOff(idx) {
    emit 72 + idx * 8
}

func emitLoadLocal(idx) {
    // MOV RAX, [RSP + off]   (48 8B 44 24 off)
    let off = localRspOff(idx)
    emit "488B4424" + hexByte(off)
}

func emitStoreLocal(idx) {
    // MOV [RSP + off], RAX
    let off = localRspOff(idx)
    emit "48894424" + hexByte(off)
}

// ── Collect locals and params for a function body ─────────────────
func collectLocals(body) {
    let lines = body
    let count = lineCount(lines)
    let locals = ""
    let i = 0
    while i < count {
        let line = getLine(lines, i)
        let op = irGetOp(line)
        if op == "PARAM" || op == "LOCAL" {
            let name = irGetArg1(line)
            if len(locals) > 0 { locals = locals + "\n" }
            locals = locals + name
        }
        i += 1
    }
    emit locals
}

// ── Emit code for one IR function body ───────────────────────────
// Returns hex bytes for the function.
// Also needs: base RVA of this function's code, IAT base RVA, rdata base RVA, strs list
func emitFuncCode(body, funcRva, iatRva, rdataRva, strs) {
    let lines = body
    let count = lineCount(lines)
    let code = ""
    let lcount = localCount()

    // Prologue: SUB RSP, frameSize
    // Frame: 32 shadow + lcount*8 locals + 8 alignment if needed
    let frameSize = 32 + lcount * 8
    // Align to 16: after CALL pushes ret addr (8 bytes), RSP was 16-aligned
    // So before CALL RSP must be 16-aligned, meaning frameSize should be multiple of 16
    let frameSizePad = frameSize
    if frameSizePad % 16 != 0 { frameSizePad = frameSizePad + (16 - frameSizePad % 16) }
    code = code + "4883EC" + hexByte(frameSizePad)  // SUB RSP, frameSize

    // Track virtual stack depth (pointers in registers / memory)
    // We use a simple scheme: values sit in RSP slots above locals
    // Call results go to RAX; we push to a "vstack" starting after locals
    let vstackBase = frameSizePad  // vstack slots are at [RSP + vstackBase + i*8]
    let vsp = 0  // virtual stack pointer (# items on vstack)

    // Helper: emit PUSH vstack (move RAX to vstack top)
    // MOV [RSP + vstackBase + vsp*8], RAX
    // Helper: emit POP vstack to RCX (move vstack top to RCX)

    let codePos = 3  // bytes emitted so far (SUB RSP = 4 bytes)
    let i = 0
    while i < count {
        let line = getLine(lines, i)
        let op = irGetOp(line)

        if op == "PARAM" || op == "LOCAL" {
            // Already counted; PARAM n means arg n was in RCX/RDX/R8/R9
            // We need to save params to their slots
            let name = irGetArg1(line)
            let idx = localIndex(name)
            if op == "PARAM" {
                // First 4 params come from shadow space (already there from caller)
                // Actually in Win64, params are in RCX, RDX, R8, R9
                // The caller wrote them to shadow space: [RSP+8], [RSP+16], [RSP+24], [RSP+32]
                // After our SUB RSP, frameSize: shadow is at [RSP+frameSizePad+8] etc.
                // Simpler: just save them from the registers
                let paramIdx = idx  // 0=rcx, 1=rdx, 2=r8, 3=r9
                if paramIdx == 0 { code = code + "48894C24" + hexByte(localRspOff(0)) }   // MOV [RSP+off], RCX
                if paramIdx == 1 { code = code + "4889542" + "4" + hexByte(localRspOff(1)) }
                if paramIdx == 2 { code = code + "4C894424" + hexByte(localRspOff(2)) }   // MOV [RSP+off], R8
                if paramIdx == 3 { code = code + "4C894C24" + hexByte(localRspOff(3)) }   // MOV [RSP+off], R9
            } else {
                // LOCAL: initialize to _K_EMPTY (null pointer = 0 for now, runtime handles it)
                // XOR EAX, EAX then store
                code = code + "33C0"  // XOR EAX, EAX
                code = code + "48894424" + hexByte(localRspOff(idx))
            }
        }

        if op == "PUSH" {
            let val = trim(irGetRest(line))
            if startsWith(val, "\"") {
                // String literal: LEA RAX, [RIP + offset_to_string_in_rdata]
                let inner = substring(val, 1, len(val) - 1)
                let soff = strOffset(strs, inner)
                // RIP at next instruction; LEA is 7 bytes: 48 8D 05 disp32
                // disp32 = (rdataRva + soff) - (funcRva + codePos + 7)
                // We need to know codePos... this requires two-pass compilation
                // For now emit a placeholder - see NOTE below
                code = code + "PUSH_STR:" + soff + ":"
            } else {
                // Numeric literal: push as string pointer from rdata
                let soff = strOffset(strs, val)
                code = code + "PUSH_STR:" + soff + ":"
            }
            vsp += 1
        }

        i += 1
    }

    // Epilogue
    code = code + "4883C4" + hexByte(frameSizePad)  // ADD RSP, frameSize
    code = code + "C3"  // RET

    emit code
}

// ── Main two-pass emitter ─────────────────────────────────────────
// Pass 1: determine sizes (layout)
// Pass 2: emit bytes with known addresses

// For v1.2.7 we do a simplified single-pass that handles the core IR
// and produces a working PE for programs using the subset of:
// PUSH, LOAD, STORE, CALL, BUILTIN, RETURN, JUMP, JUMPIF, JUMPIFNOT, LABEL
// ADD, SUB, MUL, DIV, MOD, EQ, NEQ, LT, GT, LTE, GTE, CAT, NOT, NEG, POP

// We emit each instruction as a call into krypton_rt.dll via IAT.
// Values flow through a simple operand stack mapped to RSP slots.

func emitInstr(op, arg1, arg2, vsp, iatRva, rdataRva, codeRva, strs) {
    // Returns: "hexbytes:newVsp"
    // iatRva = RVA of IAT array start, each entry is 8 bytes
    // IAT order: k32 funcs, then krypton_rt funcs (see iatIndexOf)

    let out = ""
    let newVsp = vsp

    if op == "PUSH" {
        // LEA RAX, [RIP + disp]   then push RAX to vstack
        // disp = rdataRva + strOff - (codeRva + 7)
        // We handle this in caller since we need codeRva
        // Return a placeholder marker
        out = "PUSH:" + arg1
        newVsp = vsp + 1
    }

    if op == "POP" {
        newVsp = vsp - 1
    }

    if op == "LOAD" {
        // Load local var to vstack top
        // emit "LOAD:name"
        out = "LOAD:" + arg1
        newVsp = vsp + 1
    }

    if op == "STORE" {
        // Pop vstack to local var
        out = "STORE:" + arg1
        newVsp = vsp - 1
    }

    if op == "RETURN" {
        // Return value is top of vstack -> RAX
        out = "RETURN"
        newVsp = vsp - 1
    }

    if op == "CALL" || op == "BUILTIN" {
        // Call function with arg2 arguments
        out = op + ":" + arg1 + ":" + arg2
        newVsp = vsp - toInt(arg2) + 1  // pops argc, pushes result
    }

    // Arithmetic: pop 2, push 1 result
    if op == "ADD" { out = "BINOP:kr_plus"  newVsp = vsp - 1 }
    if op == "SUB" { out = "BINOP:kr_sub"   newVsp = vsp - 1 }
    if op == "MUL" { out = "BINOP:kr_mul"   newVsp = vsp - 1 }
    if op == "DIV" { out = "BINOP:kr_div"   newVsp = vsp - 1 }
    if op == "MOD" { out = "BINOP:kr_mod"   newVsp = vsp - 1 }
    if op == "CAT" { out = "BINOP:kr_plus"  newVsp = vsp - 1 }
    if op == "EQ"  { out = "BINOP:kr_eq"    newVsp = vsp - 1 }
    if op == "NEQ" { out = "BINOP:kr_neq"   newVsp = vsp - 1 }
    if op == "LT"  { out = "BINOP:kr_lt"    newVsp = vsp - 1 }
    if op == "GT"  { out = "BINOP:kr_gt"    newVsp = vsp - 1 }
    if op == "LTE" { out = "BINOP:kr_lte"   newVsp = vsp - 1 }
    if op == "GTE" { out = "BINOP:kr_gte"   newVsp = vsp - 1 }
    if op == "NEG" { out = "UNOP:kr_neg"    }
    if op == "NOT" { out = "UNOP:kr_not"    }

    if op == "JUMP"      { out = "JUMP:" + arg1       }
    if op == "JUMPIF"    { out = "JUMPIF:" + arg1     newVsp = vsp - 1 }
    if op == "JUMPIFNOT" { out = "JUMPIFNOT:" + arg1  newVsp = vsp - 1 }
    if op == "LABEL"     { out = "LABEL:" + arg1      }

    emit out + "|" + newVsp
}

// ── Parse IR into function list ───────────────────────────────────
func parseFunctions(ir) {
    // Returns a table: "funcName|argc|body\n" per function
    // body is the raw lines joined with \x01 (to avoid newline collision)
    let lines = ir
    let total = lineCount(lines)
    let table = ""
    let i = 0
    while i < total {
        let line = getLine(lines, i)
        let op = irGetOp(line)
        if op == "FUNC" {
            let fname = irGetArg1(line)
            let argc = irGetArg2(line)
            let body = ""
            i += 1
            while i < total {
                let bl = getLine(lines, i)
                if len(body) > 0 { body = body + "\x01" }
                body = body + bl
                i += 1
                if irGetOp(bl) == "END" { break }
            }
            if len(table) > 0 { table = table + "\n" }
            table = table + fname + "|" + argc + "|" + body
        } else {
            i += 1
        }
    }
    emit table
}

func funcTableName(entry) {
    // entry format: "name|argc|body" — find first |
    let i = 0
    while i < len(entry) {
        if entry[i] == "|" { emit substring(entry, 0, i) }
        i += 1
    }
    emit entry
}
func funcTableArgc(entry) {
    // find second field (between first and second |)
    let i = 0
    let pipes = 0
    let start = 0
    while i < len(entry) {
        if entry[i] == "|" {
            pipes += 1
            if pipes == 1 { start = i + 1 }
            if pipes == 2 { emit substring(entry, start, i) }
        }
        i += 1
    }
    emit ""
}
func funcTableBody(entry) {
    // body starts after second |
    let i = 0
    let bars = 0
    while i < len(entry) {
        if entry[i] == "|" {
            bars += 1
            if bars == 2 { emit substring(entry, i + 1, len(entry)) }
        }
        i += 1
    }
    emit ""
}

// ── Full code emitter (two passes via size estimation) ────────────
// We use a simple approach: emit all instructions as structured tokens,
// then resolve addresses in a second pass.

// Structured token format per instruction:
//   "BYTES:hexdata"     — raw bytes, emit as-is
//   "PUSH_STR:soff"     — LEA RAX, [rdata+soff] then push RAX to vstack
//   "LOAD:name"         — load local to vstack
//   "STORE:name"        — store vstack top to local
//   "RETURN"            — return vstack top
//   "BINOP:funcname"    — call runtime func with 2 args
//   "UNOP:funcname"     — call runtime func with 1 arg
//   "CALL:name:argc"    — call user or builtin function
//   "BUILTIN:name:argc" — call builtin
//   "JUMP:label"        — unconditional jump
//   "JUMPIF:label"      — conditional jump if truthy
//   "JUMPIFNOT:label"   — conditional jump if not truthy
//   "LABEL:name"        — label marker (no bytes)
//   "PROLOGUE:frameSize" — function prologue
//   "EPILOGUE:frameSize" — function epilogue (ADD RSP + RET)

// Size of each token type (estimated, conservative):
func tokenSize(tok) {
    let type2 = irGetOp(tok)
    if type2 == "BYTES"     { emit (len(tok) - 6) / 2 }
    if type2 == "PUSH_STR"  { emit 7 + 2 }   // LEA RAX(7) + MOV [vstack](8) = ~15
    if type2 == "LOAD"      { emit 11 }  // MOV RAX + MOV to vstack
    if type2 == "STORE"     { emit 11 }  // MOV from vstack + MOV to local
    if type2 == "RETURN"    { emit 8 }   // MOV RAX from vstack
    if type2 == "BINOP"     { emit 40 }  // load 2 args + CALL
    if type2 == "UNOP"      { emit 25 }  // load 1 arg + CALL
    if type2 == "CALL"      { emit 60 }  // setup args + CALL
    if type2 == "BUILTIN"   { emit 60 }
    if type2 == "JUMP"      { emit 5 }
    if type2 == "JUMPIF"    { emit 20 }
    if type2 == "JUMPIFNOT" { emit 20 }
    if type2 == "LABEL"     { emit 0 }
    if type2 == "PROLOGUE"  { emit 4 }
    if type2 == "EPILOGUE"  { emit 5 }
    emit 0
}

// ── RSP-relative MOV helpers — always imm32 (8 bytes), always correct ──
func movRaxFromRsp(off) { emit hexByte(0x48)+hexByte(0x8B)+hexByte(0x84)+hexByte(0x24)+hexDword(off) }
func movRspFromRax(off) { emit hexByte(0x48)+hexByte(0x89)+hexByte(0x84)+hexByte(0x24)+hexDword(off) }
func movRspFromRcx(off) { emit hexByte(0x48)+hexByte(0x89)+hexByte(0x8C)+hexByte(0x24)+hexDword(off) }
func movRspFromRdx(off) { emit hexByte(0x48)+hexByte(0x89)+hexByte(0x94)+hexByte(0x24)+hexDword(off) }
func movRspFromR8(off)  { emit hexByte(0x4C)+hexByte(0x89)+hexByte(0x84)+hexByte(0x24)+hexDword(off) }
func movRspFromR9(off)  { emit hexByte(0x4C)+hexByte(0x89)+hexByte(0x8C)+hexByte(0x24)+hexDword(off) }
func movRcxFromRsp(off) { emit hexByte(0x48)+hexByte(0x8B)+hexByte(0x8C)+hexByte(0x24)+hexDword(off) }
func movRdxFromRsp(off) { emit hexByte(0x48)+hexByte(0x8B)+hexByte(0x94)+hexByte(0x24)+hexDword(off) }
func movR8FromRsp(off)  { emit hexByte(0x4C)+hexByte(0x8B)+hexByte(0x84)+hexByte(0x24)+hexDword(off) }
func movR9FromRsp(off)  { emit hexByte(0x4C)+hexByte(0x8B)+hexByte(0x8C)+hexByte(0x24)+hexDword(off) }

// SUB/ADD RSP always imm32 (7 bytes)
func subRspN(n) { emit hexByte(0x48)+hexByte(0x81)+hexByte(0xEC)+hexDword(n) }
func subRspNSz(n) { emit 7 }
func addRspN(n) { emit hexByte(0x48)+hexByte(0x81)+hexByte(0xC4)+hexDword(n) }
func addRspNSz(n) { emit 7 }

// ── Simplified full emitter ───────────────────────────────────────
// Generates the actual hex-encoded function machine code
// with known addresses for everything.

// emitFuncFull: appends machine code directly to sbOut (no return string).
// Returns number of bytes written as a string (for realTextSize accounting).
func emitFuncFull(ir_lines, locals, funcBaseRva, iatK32BaseRva, iatRtBaseRva, rdataBaseRva, strs, labelPositions, allFuncOffsets, sbOut) {
    let count = lineCount(ir_lines)
    let vsp = 0  // virtual stack depth (slots used in frame above locals)

    // Frame layout (RSP fixed at RSP_frame throughout; no hardware PUSH/POP for vstack):
    //   [RSP + 0..31]          : shadow space for callees (Win64 ABI home space)
    //   [RSP + 32..71]         : extra args area — 5th-9th args for calls we make
    //   [RSP + 72 + i*8]       : local variable i  (localRspOff(i) = 72 + i*8)
    //   [RSP + vstBase + i*8]  : virtual stack slot i  (N_VSTACK=12 slots)
    // RSP never moves via PUSH/POP so callee shadow space never overlaps vstack.
    // 5th arg from CALLER lands at [RSP_callee + frameSize + 40] (above our frame).
    let N_VSTACK = 12
    let lcount = lineCount(locals)
    let vstBase = 72 + lcount * 8
    let frameSize = vstBase + N_VSTACK * 8
    if frameSize % 16 != 8 {
        let rem = frameSize % 16
        if rem < 8 { frameSize = frameSize + (8 - rem) }
        else { frameSize = frameSize + (24 - rem) }
    }

    // prologue: SUB RSP, frameSize
    sbOut = sbAppend(sbOut, subRspN(frameSize))
    let pos = subRspNSz(frameSize)

    // Save parameters from registers to local slots
    let paramIdx = 0
    let pi = 0
    while pi < count {
        let line = getLine(ir_lines, pi)
        let op = irGetOp(line)
        if op == "PARAM" {
            let off = localRspOff(paramIdx)
            if paramIdx == 0 { sbOut = sbAppend(sbOut,movRspFromRcx(off))  pos += 8 }
            if paramIdx == 1 { sbOut = sbAppend(sbOut,movRspFromRdx(off))  pos += 8 }
            if paramIdx == 2 { sbOut = sbAppend(sbOut,movRspFromR8(off))   pos += 8 }
            if paramIdx == 3 { sbOut = sbAppend(sbOut,movRspFromR9(off))   pos += 8 }
            if paramIdx >= 4 {
                // 5th+ arg: caller put it at [RSP + frameSize + 40 + (paramIdx-4)*8]
                // (above callee's frame in caller's extra-args area)
                let stackArgOff = frameSize + 40 + (paramIdx - 4) * 8
                sbOut = sbAppend(sbOut,movRaxFromRsp(stackArgOff))   // MOV RAX, [RSP+stackArgOff] (8)
                sbOut = sbAppend(sbOut,movRspFromRax(off))           // MOV [RSP+localOff], RAX    (8)
                pos += 16
            }
            paramIdx += 1
        }
        if op != "PARAM" && op != "LOCAL" && op != "FUNC" { break }
        pi += 1
    }

    let i = 0
    while i < count {
        let line = getLine(ir_lines, i)
        let op = irGetOp(line)
        let a1 = irGetArg1(line)
        let a2 = irGetArg2(line)

        if op == "LOCAL" {
            let idx = 0
            let li = 0
            while li < lcount {
                if getLine(locals, li) == a1 { idx = li  break }
                li += 1
            }
            sbOut = sbAppend(sbOut,hexByte(0x33) + hexByte(0xC0))    // XOR EAX, EAX  (2)
            sbOut = sbAppend(sbOut,movRspFromRax(localRspOff(idx)))   // MOV [RSP+off], RAX (8)
            pos += 10
        }

        if op == "PUSH" {
            // LEA RAX, [RIP+disp]  (7 bytes) + MOV [RSP+vstSlot], RAX  (8 bytes) = 15
            let val = trim(irGetRest(line))
            let sval = val
            if startsWith(val, "\"") { sval = substring(val, 1, len(val) - 1) }
            let soff = strOffset(strs, sval)
            let disp = (rdataBaseRva + soff) - (funcBaseRva + pos + 7)
            sbOut = sbAppend(sbOut,hexByte(0x48) + hexByte(0x8D) + hexByte(0x05) + hexDword(disp))
            sbOut = sbAppend(sbOut,movRspFromRax(vstBase + vsp * 8))
            pos += 15
            vsp += 1
        }

        if op == "LOAD" {
            // MOV RAX, [RSP+localOff]  (8) + MOV [RSP+vstSlot], RAX  (8) = 16
            let idx = 0
            let li2 = 0
            while li2 < lcount {
                if getLine(locals, li2) == a1 { idx = li2  break }
                li2 += 1
            }
            sbOut = sbAppend(sbOut,movRaxFromRsp(localRspOff(idx)))
            sbOut = sbAppend(sbOut,movRspFromRax(vstBase + vsp * 8))
            pos += 16
            vsp += 1
        }

        if op == "STORE" {
            // vsp-- + MOV RAX, [RSP+vstSlot]  (8) + MOV [RSP+localOff], RAX  (8) = 16
            let idx = 0
            let li3 = 0
            while li3 < lcount {
                if getLine(locals, li3) == a1 { idx = li3  break }
                li3 += 1
            }
            vsp -= 1
            sbOut = sbAppend(sbOut,movRaxFromRsp(vstBase + vsp * 8))
            sbOut = sbAppend(sbOut,movRspFromRax(localRspOff(idx)))
            pos += 16
        }

        if op == "RETURN" {
            // MOV RAX, [RSP+vstSlot]  (8) + ADD RSP, frameSize  (7) + RET  (1) = 16
            vsp -= 1
            sbOut = sbAppend(sbOut,movRaxFromRsp(vstBase + vsp * 8))
            sbOut = sbAppend(sbOut,addRspN(frameSize))
            sbOut = sbAppend(sbOut,hexByte(0xC3))
            pos += 16
        }

        if op == "POP" {
            // No bytes emitted — just drop top vstack slot
            vsp -= 1
        }

        // Binary ops: b=vstack[vsp-1], a=vstack[vsp-2]
        // MOV RDX(8) + MOV RCX(8) + CALL[IAT](6) + MOV result(8) = 30 bytes
        if op == "ADD" || op == "SUB" || op == "MUL" || op == "DIV" || op == "MOD" || op == "CAT" || op == "EQ" || op == "NEQ" || op == "LT" || op == "GT" || op == "LTE" || op == "GTE" {
            let rtFunc = "kr_plus"
            if op == "SUB" { rtFunc = "kr_sub" }
            if op == "MUL" { rtFunc = "kr_mul" }
            if op == "DIV" { rtFunc = "kr_div" }
            if op == "MOD" { rtFunc = "kr_mod" }
            if op == "EQ"  { rtFunc = "kr_eq" }
            if op == "NEQ" { rtFunc = "kr_neq" }
            if op == "LT"  { rtFunc = "kr_lt" }
            if op == "GT"  { rtFunc = "kr_gt" }
            if op == "LTE" { rtFunc = "kr_lte" }
            if op == "GTE" { rtFunc = "kr_gte" }
            sbOut = sbAppend(sbOut,movRdxFromRsp(vstBase + (vsp - 1) * 8))   // RDX = b  (8)
            sbOut = sbAppend(sbOut,movRcxFromRsp(vstBase + (vsp - 2) * 8))   // RCX = a  (8)
            vsp -= 2
            let iatEntryRva = iatEntryRvaFor(rtFunc, iatK32BaseRva, iatRtBaseRva)
            // CALL at pos+16, RIP after CALL = pos+22
            let disp2 = iatEntryRva - (funcBaseRva + pos + 22)
            sbOut = sbAppend(sbOut,hexByte(0xFF) + hexByte(0x15) + hexDword(disp2))   // 6 bytes
            sbOut = sbAppend(sbOut,movRspFromRax(vstBase + vsp * 8))                   // 8 bytes
            vsp += 1
            pos += 30
        }

        // Unary ops: MOV RCX(8) + CALL[IAT](6) + MOV result(8) = 22 bytes
        if op == "NEG" || op == "NOT" {
            let rtFunc = "kr_neg"
            if op == "NOT" { rtFunc = "kr_not" }
            sbOut = sbAppend(sbOut,movRcxFromRsp(vstBase + (vsp - 1) * 8))   // RCX = top  (8)
            // CALL at pos+8, RIP after CALL = pos+14
            let iatEntryRvaNeg = iatEntryRvaFor(rtFunc, iatK32BaseRva, iatRtBaseRva)
            let disp3 = iatEntryRvaNeg - (funcBaseRva + pos + 14)
            sbOut = sbAppend(sbOut,hexByte(0xFF) + hexByte(0x15) + hexDword(disp3))   // 6 bytes
            sbOut = sbAppend(sbOut,movRspFromRax(vstBase + (vsp - 1) * 8))             // replace top  (8)
            pos += 22
            // vsp unchanged (pop 1, push 1)
        }

        if op == "CALL" || op == "BUILTIN" {
            // Load args from vstack: first arg at vsp-argc2, last at vsp-1
            // RCX=arg[0], RDX=arg[1], R8=arg[2], R9=arg[3]
            let argc2 = toInt(a2)
            let loadSz = 0
            if argc2 >= 1 { sbOut = sbAppend(sbOut,movRcxFromRsp(vstBase + (vsp - argc2) * 8))       loadSz += 8 }
            if argc2 >= 2 { sbOut = sbAppend(sbOut,movRdxFromRsp(vstBase + (vsp - argc2 + 1) * 8))   loadSz += 8 }
            if argc2 >= 3 { sbOut = sbAppend(sbOut,movR8FromRsp(vstBase + (vsp - argc2 + 2) * 8))    loadSz += 8 }
            if argc2 >= 4 { sbOut = sbAppend(sbOut,movR9FromRsp(vstBase + (vsp - argc2 + 3) * 8))    loadSz += 8 }
            // 5th+ args: write to [RSP+32 + (i-4)*8] (caller's extra-args area)
            // Callee reads these from [RSP_callee + frameSize + 40 + (i-4)*8]
            if argc2 >= 5 {
                sbOut = sbAppend(sbOut,movRaxFromRsp(vstBase + (vsp - argc2 + 4) * 8))   // 8
                sbOut = sbAppend(sbOut,movRspFromRax(32))                                  // 8
                loadSz += 16
            }
            if argc2 >= 6 {
                sbOut = sbAppend(sbOut,movRaxFromRsp(vstBase + (vsp - argc2 + 5) * 8))   // 8
                sbOut = sbAppend(sbOut,movRspFromRax(40))                                  // 8
                loadSz += 16
            }
            vsp -= argc2

            let callCode = ""
            let callSz = 0
            let resolvedName = resolveBuiltin(a1)
            let iatEntryRva2 = iatEntryRvaFor(resolvedName, iatK32BaseRva, iatRtBaseRva)
            if iatEntryRva2 >= 0 {
                // IAT call: FF 15 disp32 (6 bytes); CALL at pos+loadSz, RIP after = pos+loadSz+6
                let disp4 = iatEntryRva2 - (funcBaseRva + pos + loadSz + 6)
                callCode = hexByte(0xFF) + hexByte(0x15) + hexDword(disp4)
                callSz = 6
            } else {
                // User-defined: E8 rel32 (5 bytes)
                let targetOff = funcOffsetLookup(allFuncOffsets, a1)
                let targetRva = PE_TEXT_RVA + targetOff
                let userDisp = targetRva - (funcBaseRva + pos + loadSz + 5)
                callCode = hexByte(0xE8) + hexDword(userDisp)
                callSz = 5
            }
            sbOut = sbAppend(sbOut,callCode)
            sbOut = sbAppend(sbOut,movRspFromRax(vstBase + vsp * 8))   // store result  (8)
            vsp += 1
            pos += loadSz + callSz + 8
        }

        if op == "LABEL" {
            g_labelMap = g_labelMap + a1 + ":" + pos + "\n"
        }

        if op == "JUMP" {
            let jmpTarget = labelLookup(labelPositions, a1)
            let jmpDisp = jmpTarget - (pos + 5)
            sbOut = sbAppend(sbOut,hexByte(0xE9) + hexDword(jmpDisp))
            pos += 5
        }

        if op == "JUMPIF" || op == "JUMPIFNOT" {
            // MOV RCX(8) + CALL[kr_truthy](6) + TEST(2) + JCC(6) = 22 bytes
            // CALL at pos+8, RIP after = pos+14; JCC at pos+16, RIP after = pos+22
            sbOut = sbAppend(sbOut,movRcxFromRsp(vstBase + (vsp - 1) * 8))
            vsp -= 1
            let iatRva3 = iatEntryRvaFor("kr_truthy", iatK32BaseRva, iatRtBaseRva)
            let disp5 = iatRva3 - (funcBaseRva + pos + 14)
            sbOut = sbAppend(sbOut,hexByte(0xFF) + hexByte(0x15) + hexDword(disp5))
            sbOut = sbAppend(sbOut,hexByte(0x85) + hexByte(0xC0))   // TEST EAX, EAX
            let jcTarget = labelLookup(labelPositions, a1)
            let jcDisp = jcTarget - (pos + 22)
            if op == "JUMPIF" {
                sbOut = sbAppend(sbOut,hexByte(0x0F) + hexByte(0x85) + hexDword(jcDisp))  // JNE
            } else {
                sbOut = sbAppend(sbOut,hexByte(0x0F) + hexByte(0x84) + hexDword(jcDisp))  // JE
            }
            pos += 22
        }

        if op == "INDEX" {
            // s[i]: string at vsp-2, index at vsp-1 → kr_idx(string, index)
            // MOV RDX(8) + MOV RCX(8) + CALL(6) + MOV result(8) = 30 bytes
            sbOut = sbAppend(sbOut,movRdxFromRsp(vstBase + (vsp - 1) * 8))   // index → RDX  (8)
            sbOut = sbAppend(sbOut,movRcxFromRsp(vstBase + (vsp - 2) * 8))   // string → RCX (8)
            vsp -= 2
            let iatIdx = iatEntryRvaFor("kr_idx", iatK32BaseRva, iatRtBaseRva)
            // CALL at pos+16, RIP after = pos+22
            let dispIdx = iatIdx - (funcBaseRva + pos + 22)
            sbOut = sbAppend(sbOut,hexByte(0xFF) + hexByte(0x15) + hexDword(dispIdx))   // 6 bytes
            sbOut = sbAppend(sbOut,movRspFromRax(vstBase + vsp * 8))   // 8 bytes
            vsp += 1
            pos += 30
        }

        if op == "BREAK" {
            // Find innermost enclosing while loop via balanced backward scan.
            // Going backward: each _wend_ we pass increases nesting depth;
            // each _wloop_ decreases depth. When depth==0 and we see _wloop_N,
            // _wend_N is the BREAK target.
            let depth = 0
            let bk = i - 1
            let wendName = ""
            while bk >= 0 && len(wendName) == 0 {
                let bkline = getLine(ir_lines, bk)
                let bkop = irGetOp(bkline)
                if bkop == "LABEL" {
                    let bklabel = irGetArg1(bkline)
                    if startsWith(bklabel, "_wend_") { depth += 1 }
                    if startsWith(bklabel, "_wloop_") {
                        if depth == 0 {
                            let loopNum = substring(bklabel, 7, len(bklabel))
                            wendName = "_wend_" + loopNum
                        }
                        if depth > 0 { depth -= 1 }
                    }
                }
                bk -= 1
            }
            let wendTarget = labelLookup(labelPositions, wendName)
            let breakDisp = wendTarget - (pos + 5)
            sbOut = sbAppend(sbOut,hexByte(0xE9) + hexDword(breakDisp))
            pos += 5
        }

        if op == "END" {
            sbOut = sbAppend(sbOut,hexByte(0x33) + hexByte(0xC0))   // XOR EAX, EAX (2)
            sbOut = sbAppend(sbOut,addRspN(frameSize))               // ADD RSP, frameSize (7)
            sbOut = sbAppend(sbOut,hexByte(0xC3))                    // RET (1)
            pos += 10
        }

        i += 1
    }

    emit pos
}

// ── DOS header (64 bytes) ─────────────────────────────────────────
func emitDosHeader() {
    // MZ signature + stub — 64 bytes total, e_lfanew=0x40
    let h = hexByte(0x4D) + hexByte(0x5A)  // MZ
    h = h + hexByte(0x90) + hexByte(0x00)  // bytes on last page
    h = h + hexByte(0x03) + hexByte(0x00)  // pages in file
    h = h + hexByte(0x00) + hexByte(0x00)  // relocations
    h = h + hexByte(0x04) + hexByte(0x00)  // header size in paragraphs
    h = h + hexByte(0x00) + hexByte(0x00)  // min extra paragraphs
    h = h + hexByte(0xFF) + hexByte(0xFF)  // max extra paragraphs
    h = h + hexByte(0x00) + hexByte(0x00)  // initial SS
    h = h + hexByte(0xB8) + hexByte(0x00)  // initial SP
    h = h + hexByte(0x00) + hexByte(0x00)  // checksum
    h = h + hexByte(0x00) + hexByte(0x00)  // initial IP
    h = h + hexByte(0x00) + hexByte(0x00)  // initial CS
    h = h + hexByte(0x40) + hexByte(0x00)  // offset of relocation table
    h = h + hexByte(0x00) + hexByte(0x00)  // overlay number
    h = h + hexDword(0) + hexDword(0)      // reserved
    h = h + hexByte(0x00) + hexByte(0x00)  // OEM identifier
    h = h + hexByte(0x00) + hexByte(0x00)  // OEM information
    h = h + hexDword(0) + hexDword(0) + hexDword(0) + hexDword(0) + hexDword(0)  // 20 reserved bytes
    h = h + hexDword(64)                   // e_lfanew = 0x40
    emit h
}

// ── PE headers ───────────────────────────────────────────────────
func emitPEHeader(numSections, textSize, rdataSize, textRva, rdataRva, entryRva, imageSize, iatRva, iatSize) {
    // PE signature "PE\0\0"
    let h = hexByte(0x50) + hexByte(0x45) + hexByte(0) + hexByte(0)

    // COFF header (20 bytes)
    h = h + hexByte(0x64) + hexByte(0x86)  // Machine: AMD64 (0x8664 LE)
    h = h + hexWord(numSections)
    h = h + hexDword(0)                    // TimeDateStamp
    h = h + hexDword(0)                    // PointerToSymbolTable
    h = h + hexDword(0)                    // NumberOfSymbols
    h = h + hexByte(0xF0) + hexByte(0x00)  // SizeOfOptionalHeader = 240
    h = h + hexByte(0x22) + hexByte(0x00)  // Characteristics

    // Optional header PE32+ (240 bytes)
    h = h + hexByte(0x0B) + hexByte(0x02)  // Magic PE32+
    h = h + hexByte(0x0E) + hexByte(0x00)  // Linker version
    h = h + hexDword(textSize)
    h = h + hexDword(rdataSize)
    h = h + hexDword(0)                    // SizeOfUninitializedData
    h = h + hexDword(entryRva)
    h = h + hexDword(textRva)
    h = h + hexQword64(0, 1)               // ImageBase = 0x140000000
    h = h + hexDword(PE_SECT_ALIGN)        // SectionAlignment
    h = h + hexDword(PE_FILE_ALIGN)        // FileAlignment
    h = h + hexByte(6) + hexByte(0) + hexByte(0) + hexByte(0)  // MajorOS/MinorOS
    h = h + hexByte(0) + hexByte(0) + hexByte(0) + hexByte(0)  // MajorImage/MinorImage
    h = h + hexByte(6) + hexByte(0) + hexByte(0) + hexByte(0)  // MajorSubsystem/MinorSubsystem
    h = h + hexDword(0)                    // Win32VersionValue
    h = h + hexDword(imageSize)
    h = h + hexDword(PE_HEADER_SIZE)       // SizeOfHeaders
    h = h + hexDword(0)                    // CheckSum
    h = h + hexByte(3) + hexByte(0)        // Subsystem: CUI
    h = h + hexByte(0x60) + hexByte(0x01)  // DllCharacteristics
    h = h + hexQword64(8388608, 0)         // SizeOfStackReserve = 8MB
    h = h + hexQword64(65536, 0)           // SizeOfStackCommit = 64KB
    h = h + hexQword64(1048576, 0)         // SizeOfHeapReserve
    h = h + hexQword64(4096, 0)            // SizeOfHeapCommit
    h = h + hexDword(0)                    // LoaderFlags
    h = h + hexDword(16)                   // NumberOfRvaAndSizes

    // Data directories (16 * 8 bytes = 128 bytes)
    h = h + hexDword(0) + hexDword(0)                   // [0] Export
    h = h + hexDword(iatRva) + hexDword(iatSize)         // [1] Import Directory
    h = h + hexDword(0) + hexDword(0)                   // [2] Resource
    h = h + hexDword(0) + hexDword(0)                   // [3] Exception
    h = h + hexDword(0) + hexDword(0)                   // [4] Security
    h = h + hexDword(0) + hexDword(0)                   // [5] BaseReloc
    h = h + hexDword(0) + hexDword(0)                   // [6] Debug
    h = h + hexDword(0) + hexDword(0)                   // [7] Architecture
    h = h + hexDword(0) + hexDword(0)                   // [8] GlobalPtr
    h = h + hexDword(0) + hexDword(0)                   // [9] TLS
    h = h + hexDword(0) + hexDword(0)                   // [10] LoadConfig
    h = h + hexDword(0) + hexDword(0)                   // [11] BoundImport
    h = h + hexDword(iatRva) + hexDword(iatSize)         // [12] IAT
    h = h + hexDword(0) + hexDword(0)                   // [13] DelayImport
    h = h + hexDword(0) + hexDword(0)                   // [14] CLRHeader
    h = h + hexDword(0) + hexDword(0)                   // [15] reserved

    emit h
}

func emitSectionHeader(name, virtSize, virtAddr, rawSize, rawOffset, characteristics) {
    let h = hexStr(name)
    // Pad name to 8 bytes
    let namePad = 8 - len(name)
    let pi = 0
    while pi < namePad { h = h + hexByte(0)  pi += 1 }
    h = h + hexDword(virtSize)
    h = h + hexDword(virtAddr)
    h = h + hexDword(rawSize)
    h = h + hexDword(rawOffset)
    h = h + hexDword(0)   // PointerToRelocations
    h = h + hexDword(0)   // PointerToLinenumbers
    h = h + hexByte(0) + hexByte(0)   // NumberOfRelocations
    h = h + hexByte(0) + hexByte(0)   // NumberOfLinenumbers
    h = h + hexDword(characteristics)
    emit h
}

// ── Import table emitter ──────────────────────────────────────────
// Layout in .rdata (after string table):
//   [A] IMAGE_IMPORT_DESCRIPTOR for kernel32.dll (20 bytes)
//   [B] IMAGE_IMPORT_DESCRIPTOR for krypton_rt.dll (20 bytes)
//   [C] Null terminator descriptor (20 bytes)
//   [D] ILT for kernel32 (k32count+1 entries * 8 bytes)
//   [E] ILT for krypton_rt (rtcount+1 entries * 8 bytes)
//   [F] IAT for kernel32 (same structure as ILT, filled by loader)
//   [G] IAT for krypton_rt (same structure as ILT)
//   [H] DLL name "kernel32.dll\0"
//   [I] DLL name "krypton_rt.dll\0"
//   [J] IMAGE_IMPORT_BY_NAME entries for each function

func buildImportTable(rdataRva, strsSize) {
    let k32funcs = KR32_FUNCS
    let rtfuncs = KRRT_FUNCS
    let k32count = countFuncs(k32funcs)
    let rtcount = countFuncs(rtfuncs)

    // Calculate offsets within .rdata (after string table)
    let impBase = strsSize  // import table starts right after string table (padded to 8)
    let impBasePad = impBase
    if impBasePad % 8 != 0 { impBasePad = impBasePad + (8 - impBasePad % 8) }

    // Offsets from start of .rdata:
    let descOffset = impBasePad
    let descSize = 60  // 3 descriptors * 20 bytes
    let iltK32Offset = descOffset + descSize
    let iltK32Size = (k32count + 1) * 8
    let iltRtOffset = iltK32Offset + iltK32Size
    let iltRtSize = (rtcount + 1) * 8
    let iatK32Offset = iltRtOffset + iltRtSize
    let iatK32Size = (k32count + 1) * 8
    let iatRtOffset = iatK32Offset + iatK32Size
    let iatRtSize = (rtcount + 1) * 8
    let dllK32Offset = iatRtOffset + iatRtSize
    let dllK32Name = "kernel32.dll"
    let dllRtOffset = dllK32Offset + len(dllK32Name) + 1
    let dllRtName = "krypton_rt.dll"
    let hintsOffset = dllRtOffset + len(dllRtName) + 1
    // Pad to 2-byte alignment
    if hintsOffset % 2 != 0 { hintsOffset += 1 }

    // Compute RVAs
    let descRva = rdataRva + descOffset
    let iltK32Rva = rdataRva + iltK32Offset
    let iltRtRva = rdataRva + iltRtOffset
    let iatK32Rva = rdataRva + iatK32Offset
    let iatRtRva = rdataRva + iatRtOffset
    let dllK32Rva = rdataRva + dllK32Offset
    let dllRtRva = rdataRva + dllRtOffset
    let hintsRva = rdataRva + hintsOffset

    // Build IMAGE_IMPORT_BY_NAME entries (hint + name)
    // Each: 2-byte hint + name string + null + padding to even
    let hintTable = ""
    let hintOffsets = ""  // newline-separated offsets
    let hintOff = 0
    let hf = 0
    while hf < k32count {
        let hfname = funcAt(k32funcs, hf)
        if len(hintOffsets) > 0 { hintOffsets = hintOffsets + "\n" }
        hintOffsets = hintOffsets + hintOff
        hintTable = hintTable + hexByte(0) + hexByte(0) + hexStrZ(hfname)
        hintOff += 2 + len(hfname) + 1
        if hintOff % 2 != 0 { hintTable = hintTable + hexByte(0)  hintOff += 1 }
        hf += 1
    }
    let hf2 = 0
    while hf2 < rtcount {
        let hfname2 = funcAt(rtfuncs, hf2)
        if len(hintOffsets) > 0 { hintOffsets = hintOffsets + "\n" }
        hintOffsets = hintOffsets + hintOff
        hintTable = hintTable + hexByte(0) + hexByte(0) + hexStrZ(hfname2)
        hintOff += 2 + len(hfname2) + 1
        if hintOff % 2 != 0 { hintTable = hintTable + hexByte(0)  hintOff += 1 }
        hf2 += 1
    }

    // Build ILT / IAT entries
    // Each entry: 8 bytes, high bit=0 → by name → RVA of IMAGE_IMPORT_BY_NAME
    let iltK32 = ""
    let k32i = 0
    while k32i < k32count {
        let hintRvaK = hintsRva + toInt(getLine(hintOffsets, k32i))
        iltK32 = iltK32 + hexQword64(hintRvaK, 0)
        k32i += 1
    }
    iltK32 = iltK32 + hexQword64(0, 0)  // null terminator

    let iltRt = ""
    let rti = 0
    while rti < rtcount {
        let hintRvaR = hintsRva + toInt(getLine(hintOffsets, k32count + rti))
        iltRt = iltRt + hexQword64(hintRvaR, 0)
        rti += 1
    }
    iltRt = iltRt + hexQword64(0, 0)    // null terminator

    // Build IMAGE_IMPORT_DESCRIPTOR (20 bytes each):
    // OriginalFirstThunk(4) TimeDateStamp(4) ForwarderChain(4) Name(4) FirstThunk(4)
    let desc = ""
    desc = desc + hexDword(iltK32Rva)
    desc = desc + hexDword(0)
    desc = desc + hexDword(0)   // ForwarderChain
    desc = desc + hexDword(dllK32Rva)
    desc = desc + hexDword(iatK32Rva)

    desc = desc + hexDword(iltRtRva)
    desc = desc + hexDword(0)
    desc = desc + hexDword(0)   // ForwarderChain
    desc = desc + hexDword(dllRtRva)
    desc = desc + hexDword(iatRtRva)

    desc = desc + hexDword(0) + hexDword(0) + hexDword(0) + hexDword(0) + hexDword(0)  // null descriptor

    // Assemble the import section data
    let out = ""
    // Padding before import data
    let pp = 0
    while pp < impBasePad - impBase { out = out + hexByte(0)  pp += 1 }
    out = out + desc          // descriptors
    out = out + iltK32        // ILT kernel32
    out = out + iltRt         // ILT krypton_rt
    out = out + iltK32        // IAT kernel32 (initially same as ILT)
    out = out + iltRt         // IAT krypton_rt
    out = out + hexStrZ(dllK32Name)  // "kernel32.dll\0"
    out = out + hexStrZ(dllRtName)   // "krypton_rt.dll\0"
    if (dllK32Offset + len(dllK32Name) + 1 + len(dllRtName) + 1) % 2 != 0 { out = out + hexByte(0) }
    out = out + hintTable

    // Return: "hexdata,iatK32Rva,descRva,totalSize"  (comma-separated, split() compatible)
    let iatTotal = iatK32Size + iatRtSize
    emit out + "," + iatK32Rva + "," + descRva + "," + iatTotal
}

// ── Entry point wrapper ───────────────────────────────────────────
// Calls __main__, then calls ExitProcess with return value
func emitEntryPoint(mainFuncOffset, iatK32Rva, entryRva) {
    // entryRva = RVA of this code
    let code = ""
    let pos = 0

    // SUB RSP, 40  (32 shadow + 8 align), use imm32 for consistency
    code = code + subRspN(40)
    pos += 7

    // CALL __main__
    let callDisp = mainFuncOffset - (entryRva + pos + 5)
    code = code + hexByte(0xE8) + hexDword(callDisp)
    pos += 5

    // XOR ECX, ECX (exit code 0)
    code = code + hexByte(0x33) + hexByte(0xC9)
    pos += 2

    // CALL ExitProcess via IAT
    let exitIatRva = iatK32Rva
    let epDisp = exitIatRva - (entryRva + pos + 6)
    code = code + hexByte(0xFF) + hexByte(0x15) + hexDword(epDisp)
    pos += 6

    code = code + hexByte(0xC3)  // RET (unreachable)

    emit code
}

// ── Main compilation ──────────────────────────────────────────────
just run {
    let file = arg("0")
    let outFile = arg("1")

    if len(file) == 0 {
        printErr("x64: usage: kcc kompiler/x64.k <file.kir> [output.exe]")
        emit 1
    }

    let ir = readFile(file)
    if len(ir) == 0 {
        printErr("x64: cannot read: " + file)
        emit 1
    }

    // Clean IR: strip comments and blank lines
    let allLines = ir
    let total = lineCount(allLines)
    let clean = ""
    let ci = 0
    while ci < total {
        let ln = trim(getLine(allLines, ci))
        if len(ln) > 0 && ln[0] != ";" {
            if len(clean) > 0 { clean = clean + "\n" }
            clean = clean + ln
        }
        ci += 1
    }

    // Collect all string constants
    let strs = collectStrings(clean)
    // Add numeric constants that appear as PUSH non-quoted
    let cl2 = lineCount(clean)
    let ii = 0
    while ii < cl2 {
        let ln2 = getLine(clean, ii)
        if irGetOp(ln2) == "PUSH" {
            let val = trim(irGetRest(ln2))
            if !startsWith(val, "\"") {
                if !contains("\n" + strs, "\n" + val + "\n") {
                    if len(strs) > 0 { strs = strs + "\n" }
                    strs = strs + val
                }
            }
        }
        ii += 1
    }

    // Parse functions
    let funcTable = parseFunctions(clean)
    let funcCount = 0
    if len(funcTable) > 0 { funcCount = lineCount(funcTable) }

    // Layout:
    // File 0x000: DOS header (64 = 0x40 bytes)
    // File 0x040: PE header + optional + data dirs (240+24+4 = 268 bytes? = 0x10C)
    // Actually: PE sig(4) + COFF(20) + OptHdr(240) = 264 = 0x108
    // Then section headers: 2 * 40 = 80 = 0x50
    // Total headers = 0x40 + 0x108 + 0x50 = 0x198, pad to 0x200
    // File 0x200: .text section
    // File 0x?00: .rdata section

    let PE_TEXT_FILE_OFF = 512     // 0x200
    let PE_TEXT_RVA2 = 4096        // 0x1000

    // ── Pass 1: accurate size calculation using instrSize ─────────────
    // Computes exact byte offsets for every function, no code emitted yet.
    let allFuncOffsets = ""   // "funcName:byteOffset\n" for all functions
    let totalFuncBytes = 0

    let fi = 0
    while fi < funcCount {
        let entry2 = getLine(funcTable, fi)
        let fname3 = funcTableName(entry2)
        let body3 = replace(funcTableBody(entry2), "\x01", "\n")
        g_locals = collectLocals(body3)
        let fsz = funcByteSize(body3)
        if len(allFuncOffsets) > 0 { allFuncOffsets = allFuncOffsets + "\n" }
        allFuncOffsets = allFuncOffsets + fname3 + ":" + totalFuncBytes
        totalFuncBytes += fsz
        fi += 1
    }

    // Entry point: 7(subRsp)+5(call)+2(xor)+6(call IAT)+1(ret) = 21 bytes
    let entrySize = 21
    let entryByteOffset = totalFuncBytes
    let totalTextBytes = totalFuncBytes + entrySize

    // ── Layout ───────────────────────────────────────────────────────
    // Emit string table first so strTableSize is measured from actual bytes (not recomputed)
    // This guarantees buildImportTable RVAs match the actual string table layout.
    let strTableHex = emitStringTable(strs)
    let strTableSize = len(strTableHex) / 3
    let realRdataRva = PE_TEXT_RVA2 + alignUp(totalTextBytes, PE_SECT_ALIGN)

    // Build import table once with the real rdata RVA
    let realImportData = buildImportTable(realRdataRva, strTableSize)
    let realImportHex = split(realImportData, 0)
    let realIatK32 = toInt(split(realImportData, 1))
    let realIatDescRva = toInt(split(realImportData, 2))
    let realIatTotalSz = toInt(split(realImportData, 3))
    let realIatRtRva = realIatK32 + (countFuncs(KR32_FUNCS) + 1) * 8

    let rdataSize2 = strTableSize + len(realImportHex) / 3
    let realTextFileSize = alignUp(totalTextBytes, PE_FILE_ALIGN)
    let realRdataFileOff = PE_TEXT_FILE_OFF + realTextFileSize
    let realImageSize = realRdataRva + alignUp(rdataSize2, PE_SECT_ALIGN)

    // ── Pass 2: code generation with real addresses ───────────────────
    let sbCode = sbNew()
    let realTextSize = 0

    let fi2 = 0
    while fi2 < funcCount {
        let entry3 = getLine(funcTable, fi2)
        let fname4 = funcTableName(entry3)
        let body4 = replace(funcTableBody(entry3), "\x01", "\n")
        g_locals = collectLocals(body4)
        let funcRva2 = PE_TEXT_RVA2 + realTextSize
        let labelPositions = collectLabelPositions(body4)
        let fbytes = toInt(emitFuncFull(body4, g_locals, funcRva2, realIatK32, realIatRtRva, realRdataRva, strs, labelPositions, allFuncOffsets, sbCode))
        realTextSize += fbytes
        fi2 += 1
    }

    // Entry point
    let mainOffset = funcOffsetLookup(allFuncOffsets, "__main__")
    let entryRva2 = PE_TEXT_RVA2 + realTextSize
    let entryCode = emitEntryPoint(PE_TEXT_RVA2 + mainOffset, realIatK32, entryRva2)
    sbCode = sbAppend(sbCode, entryCode)
    realTextSize += len(entryCode) / 3
    let realFuncCode = sbToString(sbCode)

    // ── Assemble the PE binary ────────────────────────────────────────
    let dos = emitDosHeader()

    let pehdr = emitPEHeader(
        2,
        realTextSize,
        rdataSize2,
        PE_TEXT_RVA2,
        realRdataRva,
        entryRva2,
        realImageSize,
        realIatDescRva,
        realIatTotalSz
    )

    let textSecHdr = emitSectionHeader(
        ".text",
        realTextSize,
        PE_TEXT_RVA2,
        realTextFileSize,
        PE_TEXT_FILE_OFF,
        536870944   // 0x20000020: code, execute, read
    )

    let finalRdataFileSize = alignUp(rdataSize2, PE_FILE_ALIGN)
    let rdataSecHdr = emitSectionHeader(
        ".rdata",
        rdataSize2,
        realRdataRva,
        finalRdataFileSize,
        realRdataFileOff,
        1073741888  // 0x40000040: initialized data, read
    )

    // Headers total size check: 0x40 + 4+20+240 + 2*40 = 0x40 + 0x108 + 0x50 = 0x198
    // Pad to 0x200
    let hdrHex = dos + pehdr + textSecHdr + rdataSecHdr
    let hdrBytes = len(hdrHex) / 3
    let hdrPad = PE_HEADER_SIZE - hdrBytes
    let hdrPadHex = hexPad(hdrPad)

    // Text section: code + padding to file alignment
    let textPad = realTextFileSize - realTextSize
    let textPadHex = hexPad(textPad)

    // Rdata section: strings + import table + padding
    // strTableHex already computed above (before buildImportTable)
    let rdataPad = finalRdataFileSize - rdataSize2
    let rdataPadHex = hexPad(rdataPad)

    // Assemble full PE (direct concatenation — sections are all measured, not huge)
    let pe = hdrHex + hdrPadHex + realFuncCode + textPadHex + strTableHex + realImportHex + rdataPadHex

    if len(outFile) > 0 {
        writeBytes(outFile, pe)
        printErr("x64: wrote " + outFile + " (" + (len(pe) / 3) + " bytes)")
    } else {
        print(pe)
    }

    emit 0
}
