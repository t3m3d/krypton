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
    let HEX = "0123456789ABCDEF"
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
                j += 2
            } else if c == "x" && j + 3 < m {
                bytes += 1
                j += 4
            } else {
                bytes += 2
                j += 2
            }
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
    // \xNN hex escapes are decoded to their actual byte values
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
                j += 2
            } else if c == "t" {
                out = out + hexByte(9)
                j += 2
            } else if c == "r" {
                out = out + hexByte(13)
                j += 2
            } else if c == "\\" {
                out = out + hexByte(92)
                j += 2
            } else if c == "\"" {
                out = out + hexByte(34)
                j += 2
            } else if c == "x" && j + 3 < m {
                let h1 = charCode(tv[j + 2])
                let h2 = charCode(tv[j + 3])
                let v1 = 0
                if h1 >= 48 && h1 <= 57 { v1 = h1 - 48 }
                else if h1 >= 97 && h1 <= 102 { v1 = h1 - 87 }
                else if h1 >= 65 && h1 <= 70 { v1 = h1 - 55 }
                let v2 = 0
                if h2 >= 48 && h2 <= 57 { v2 = h2 - 48 }
                else if h2 >= 97 && h2 <= 102 { v2 = h2 - 87 }
                else if h2 >= 65 && h2 <= 70 { v2 = h2 - 55 }
                out = out + hexByte(v1 * 16 + v2)
                j += 4
            } else {
                out = out + hexByte(92) + hexByte(charCode(c))
                j += 2
            }
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
// Five DLLs: kernel32.dll + krypton_rt.dll + advapi32.dll + pdh.dll + user32.dll

let KR32_FUNCS = "ExitProcess,GetStdHandle,SetConsoleOutputCP,GetConsoleMode,SetConsoleMode,GetConsoleScreenBufferInfo,GetCurrentProcessId,CreateToolhelp32Snapshot,Process32First,Process32Next,CloseHandle,GetDiskFreeSpaceExA,GlobalMemoryStatusEx,GetSystemPowerStatus,GetTickCount64,GetLogicalDrives,GetNativeSystemInfo,GetComputerNameA,FindFirstFileA,FindNextFileA,FindClose,GetFileAttributesA,LoadLibraryA,FreeLibrary,GetProcAddress,GetEnvironmentVariableA,HeapAlloc,HeapFree,HeapReAlloc,GetProcessHeap,WriteFile,ReadFile,CreateFileA,GetCommandLineA,GetFileSizeEx"
let KRUSER_FUNCS = "GetSystemMetrics"
let KRRT_FUNCS = "kr_str,kr_plus,kr_sub,kr_mul,kr_div,kr_mod,kr_neg,kr_not,kr_eq,kr_neq,kr_lt,kr_gt,kr_lte,kr_gte,kr_truthy,kr_print,kr_printerr,kr_printl,kr_exit,kr_len,kr_idx,kr_substring,kr_startswith,kr_contains,kr_indexof,kr_trim,kr_toint,kr_charcode,kr_isdigit,kr_replace,kr_split,kr_readfile,kr_arg,kr_sbnew,kr_sbappend,kr_sbtostring,kr_init_args,kr_linecount,kr_getline,kr_count,kr_argcount,kr_writefile,kr_writebytes,kr_range,kr_length,kr_fromcharcode,kr_tolower,kr_tohandle,kr_bitor,kr_bitand,kr_bitxor,kr_bitnot,kr_shl,kr_shr,kr_bufnew,kr_bufsetdword,kr_bufgetdword,kr_bufsetdwordat,kr_bufgetdwordat,kr_bufgetword,kr_bufgetqword,kr_bufsetbyte,kr_structnew,kr_structget,kr_structset,kr_bufstr,kr_bufgetqwordat,kr_handleout,kr_handleget,kr_handlevalid,kr_handleint,kr_ptrderef,kr_ptrindex,kr_callptr1,kr_callptr2,kr_callptr3,kr_callptr4,kr_hex,kr_touppers,kr_div64,kr_environ,kr_sizeof,kr_rawalloc,kr_rawfree,kr_rawrealloc,kr_ptradd,kr_ptrtoint,kr_rawreadbyte,kr_rawreadword,kr_rawwriteword,kr_rawwriteqword"
let KRADV_FUNCS = "RegOpenKeyExA,RegQueryValueExA,RegEnumKeyExA,RegCloseKey,GetUserNameA"
let KRPDH_FUNCS = "PdhOpenQueryA,PdhAddEnglishCounterA,PdhCollectQueryData,PdhGetFormattedCounterArrayA,PdhCloseQuery"

// Map IR builtin names to krypton_rt.dll function names
func resolveBuiltin(name) {
    if name == "kp"             { emit "kr_print" }
    if name == "print"          { emit "kr_print" }
    if name == "printErr"       { emit "kr_printerr" }
    if name == "exit"           { emit "kr_exit" }
    if name == "len"            { emit "kr_len" }
    if name == "substring"      { emit "kr_substring" }
    if name == "startsWith"     { emit "kr_startswith" }
    if name == "contains"       { emit "kr_contains" }
    if name == "indexOf"        { emit "kr_indexof" }
    if name == "trim"           { emit "kr_trim" }
    if name == "toInt"          { emit "kr_toint" }
    if name == "charCode"       { emit "kr_charcode" }
    if name == "isDigit"        { emit "kr_isdigit" }
    if name == "replace"        { emit "kr_replace" }
    if name == "split"          { emit "kr_split" }
    if name == "range"          { emit "kr_range" }
    if name == "length"         { emit "kr_length" }
    if name == "readFile"       { emit "kr_readfile" }
    if name == "arg"            { emit "kr_arg" }
    if name == "sbNew"          { emit "kr_sbnew" }
    if name == "sbAppend"       { emit "kr_sbappend" }
    if name == "sbToString"     { emit "kr_sbtostring" }
    if name == "lineCount"      { emit "kr_linecount" }
    if name == "getLine"        { emit "kr_getline" }
    if name == "count"          { emit "kr_count" }
    if name == "argCount"       { emit "kr_argcount" }
    if name == "writeFile"      { emit "kr_writefile" }
    if name == "writeBytes"     { emit "kr_writebytes" }
    if name == "printl"         { emit "kr_printl" }
    if name == "fromCharCode"   { emit "kr_fromcharcode" }
    if name == "toLower"        { emit "kr_tolower" }
    if name == "toHandle"       { emit "kr_tohandle" }
    if name == "bitOr"          { emit "kr_bitor" }
    if name == "bitAnd"         { emit "kr_bitand" }
    if name == "bitXor"         { emit "kr_bitxor" }
    if name == "bitNot"         { emit "kr_bitnot" }
    if name == "shl"            { emit "kr_shl" }
    if name == "shr"            { emit "kr_shr" }
    if name == "bufNew"         { emit "kr_bufnew" }
    if name == "bufSetDword"    { emit "kr_bufsetdword" }
    if name == "bufGetDword"    { emit "kr_bufgetdword" }
    if name == "bufSetDwordAt"  { emit "kr_bufsetdwordat" }
    if name == "bufGetDwordAt"  { emit "kr_bufgetdwordat" }
    if name == "bufGetWord"     { emit "kr_bufgetword" }
    if name == "bufGetQword"    { emit "kr_bufgetqword" }
    if name == "bufSetByte"     { emit "kr_bufsetbyte" }
    if name == "structNew"      { emit "kr_structnew" }
    if name == "structGet"      { emit "kr_structget" }
    if name == "structSet"      { emit "kr_structset" }
    if name == "bufStr"         { emit "kr_bufstr" }
    if name == "bufGetQwordAt"  { emit "kr_bufgetqwordat" }
    if name == "handleOut"      { emit "kr_handleout" }
    if name == "handleGet"      { emit "kr_handleget" }
    if name == "handleValid"    { emit "kr_handlevalid" }
    if name == "handleInt"      { emit "kr_handleint" }
    if name == "ptrDeref"       { emit "kr_ptrderef" }
    if name == "ptrIndex"       { emit "kr_ptrindex" }
    // callPtr handled specially in instrSize/emitFuncFull by argc
    if name == "hex"            { emit "kr_hex" }
    if name == "toUpper"        { emit "kr_touppers" }
    if name == "div64"          { emit "kr_div64" }
    if name == "environ"        { emit "kr_environ" }
    if name == "sizeOf"         { emit "kr_sizeof" }
    if name == "bitShl"         { emit "kr_shl" }
    if name == "str"            { emit "kr_str" }
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
    // Returns index within its own DLL's IAT, prefixed by "k32:", "rt:", "adv:", "pdh:", or "user:"
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
    let advcount = countFuncs(KRADV_FUNCS)
    let k = 0
    while k < advcount {
        if funcAt(KRADV_FUNCS, k) == funcName { emit "adv:" + k }
        k += 1
    }
    let pdhcount = countFuncs(KRPDH_FUNCS)
    let m = 0
    while m < pdhcount {
        if funcAt(KRPDH_FUNCS, m) == funcName { emit "pdh:" + m }
        m += 1
    }
    let usercount = countFuncs(KRUSER_FUNCS)
    let n = 0
    while n < usercount {
        if funcAt(KRUSER_FUNCS, n) == funcName { emit "user:" + n }
        n += 1
    }
    emit "none"
}

// Compute IAT entry RVA given the base RVAs of all DLL IATs
func iatEntryRvaFor(funcName, iatK32BaseRva, iatRtBaseRva, iatAdvBaseRva, iatPdhBaseRva, iatUserBaseRva) {
    let idxStr = iatIndexOf(funcName)
    if startsWith(idxStr, "k32:") {
        let idx = toInt(substring(idxStr, 4, len(idxStr)))
        emit iatK32BaseRva + idx * 8
    }
    if startsWith(idxStr, "rt:") {
        let idx = toInt(substring(idxStr, 3, len(idxStr)))
        emit iatRtBaseRva + idx * 8
    }
    if startsWith(idxStr, "adv:") {
        let idx = toInt(substring(idxStr, 4, len(idxStr)))
        emit iatAdvBaseRva + idx * 8
    }
    if startsWith(idxStr, "pdh:") {
        let idx = toInt(substring(idxStr, 4, len(idxStr)))
        emit iatPdhBaseRva + idx * 8
    }
    if startsWith(idxStr, "user:") {
        let idx = toInt(substring(idxStr, 5, len(idxStr)))
        emit iatUserBaseRva + idx * 8
    }
    emit -1
}

// IAT total entries (with null terminators between DLLs)
func iatTotalEntries() {
    emit countFuncs(KR32_FUNCS) + 1 + countFuncs(KRRT_FUNCS) + 1 + countFuncs(KRADV_FUNCS) + 1 + countFuncs(KRPDH_FUNCS) + 1 + countFuncs(KRUSER_FUNCS) + 1
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
        // Extra args (5th+): each costs 8+8=16 bytes (MOV RAX from vst + MOV to [RSP+N])
        let extraArgSz = 0
        if argc2 >= 5  { extraArgSz = extraArgSz + 16 }
        if argc2 >= 6  { extraArgSz = extraArgSz + 16 }
        if argc2 >= 7  { extraArgSz = extraArgSz + 16 }
        if argc2 >= 8  { extraArgSz = extraArgSz + 16 }
        if argc2 >= 9  { extraArgSz = extraArgSz + 16 }
        if argc2 >= 10 { extraArgSz = extraArgSz + 16 }
        if argc2 >= 11 { extraArgSz = extraArgSz + 16 }
        if argc2 >= 12 { extraArgSz = extraArgSz + 16 }
        if argc2 >= 13 { extraArgSz = extraArgSz + 16 }
        if argc2 >= 14 { extraArgSz = extraArgSz + 16 }
        if argc2 >= 15 { extraArgSz = extraArgSz + 16 }
        if argc2 >= 16 { extraArgSz = extraArgSz + 16 }
        // loads*MOV(8) + extraArgSz + CALL(6or5) + MOV result(8)
        let callSz = 6
        let resolved = resolveBuiltin(a1)
        if a1 == "callPtr" {
            let cpN = argc2 - 1
            if cpN == 1 { resolved = "kr_callptr1" }
            if cpN == 2 { resolved = "kr_callptr2" }
            if cpN == 3 { resolved = "kr_callptr3" }
            if cpN == 4 { resolved = "kr_callptr4" }
        }
        let idxStr = iatIndexOf(resolved)
        if idxStr == "none" { callSz = 5 }
        emit loads * 8 + extraArgSz + callSz + 8
    }
    if op == "LABEL"     { emit 0 }
    if op == "JUMP"      { emit 5 }          // E9 + disp32
    if op == "JUMPIF"    { emit 25 }         // MOV RCX(8)+CALL(6)+MOVZX(3)+CMP(2)+JCC(6)
    if op == "JUMPIFNOT" { emit 25 }
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
    let frsz = 80 + lcount2 * 8 + 12 * 8  // 80=shadow+extraargs, lcount locals, 12 vstack slots
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
    let frsz3 = 80 + lcount3 * 8 + 12 * 8
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
// Frame: [RSP+0..31]=shadow, [RSP+32..79]=extra args (5th-10th arg pass), [RSP+80..]=locals
func localRspOff(idx) {
    emit 80 + idx * 8
}

func emitLoadLocal(idx) {
    let off = localRspOff(idx)
    // Use disp32 when offset >= 128 (disp8 is signed, max +127)
    if off >= 128 {
        emit "488B8424" + hexDword(off)
    } else {
        emit "488B4424" + hexByte(off)
    }
}

func emitStoreLocal(idx) {
    let off = localRspOff(idx)
    if off >= 128 {
        emit "48898424" + hexDword(off)
    } else {
        emit "48894424" + hexByte(off)
    }
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
                if len(body) > 0 { body = body + "|||" }
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
    if type2 == "JUMPIF"    { emit 25 }
    if type2 == "JUMPIFNOT" { emit 25 }
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
func emitFuncFull(ir_lines, locals, funcBaseRva, iatBases, rdataBaseRva, strs, labelPositions, allFuncOffsets, sbOut) {
    let iatK32BaseRva = toInt(getLine(iatBases, 0))
    let iatRtBaseRva = toInt(getLine(iatBases, 1))
    let iatAdvBaseRva = toInt(getLine(iatBases, 2))
    let iatPdhBaseRva = toInt(getLine(iatBases, 3))
    let iatUserBaseRva = toInt(getLine(iatBases, 4))
    let PE_TEXT_RVA = 4096
    let count = lineCount(ir_lines)
    let vsp = 0  // virtual stack depth (slots used in frame above locals)

    // Frame layout (RSP fixed at RSP_frame throughout; no hardware PUSH/POP for vstack):
    //   [RSP + 0..31]          : shadow space for callees (Win64 ABI home space)
    //   [RSP + 32..79]         : extra args area — 5th-10th args for calls we make
    //   [RSP + 80 + i*8]       : local variable i  (localRspOff(i) = 80 + i*8)
    //   [RSP + vstBase + i*8]  : virtual stack slot i  (N_VSTACK=12 slots)
    // RSP never moves via PUSH/POP so callee shadow space never overlaps vstack.
    // 5th arg from CALLER lands at [RSP_callee + frameSize + 40] (above our frame).
    let N_VSTACK = 12
    let lcount = lineCount(locals)
    let vstBase = 80 + lcount * 8
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
            let iatEntryRva = iatEntryRvaFor(rtFunc, iatK32BaseRva, iatRtBaseRva, iatAdvBaseRva, iatPdhBaseRva, iatUserBaseRva)
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
            let iatEntryRvaNeg = iatEntryRvaFor(rtFunc, iatK32BaseRva, iatRtBaseRva, iatAdvBaseRva, iatPdhBaseRva, iatUserBaseRva)
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
            if argc2 >= 7 {
                sbOut = sbAppend(sbOut,movRaxFromRsp(vstBase + (vsp - argc2 + 6) * 8))   // 8
                sbOut = sbAppend(sbOut,movRspFromRax(48))                                  // 8
                loadSz += 16
            }
            if argc2 >= 8 {
                sbOut = sbAppend(sbOut,movRaxFromRsp(vstBase + (vsp - argc2 + 7) * 8))   // 8
                sbOut = sbAppend(sbOut,movRspFromRax(56))                                  // 8
                loadSz += 16
            }
            if argc2 >= 9 {
                sbOut = sbAppend(sbOut,movRaxFromRsp(vstBase + (vsp - argc2 + 8) * 8))   // 8
                sbOut = sbAppend(sbOut,movRspFromRax(64))                                  // 8
                loadSz += 16
            }
            if argc2 >= 10 {
                sbOut = sbAppend(sbOut,movRaxFromRsp(vstBase + (vsp - argc2 + 9) * 8))   // 8
                sbOut = sbAppend(sbOut,movRspFromRax(72))                                  // 8
                loadSz += 16
            }
            if argc2 >= 11 {
                sbOut = sbAppend(sbOut,movRaxFromRsp(vstBase + (vsp - argc2 + 10) * 8))  // 8
                sbOut = sbAppend(sbOut,movRspFromRax(80))                                  // 8
                loadSz += 16
            }
            if argc2 >= 12 {
                sbOut = sbAppend(sbOut,movRaxFromRsp(vstBase + (vsp - argc2 + 11) * 8))  // 8
                sbOut = sbAppend(sbOut,movRspFromRax(88))                                  // 8
                loadSz += 16
            }
            if argc2 >= 13 {
                sbOut = sbAppend(sbOut,movRaxFromRsp(vstBase + (vsp - argc2 + 12) * 8))  // 8
                sbOut = sbAppend(sbOut,movRspFromRax(96))                                  // 8
                loadSz += 16
            }
            if argc2 >= 14 {
                sbOut = sbAppend(sbOut,movRaxFromRsp(vstBase + (vsp - argc2 + 13) * 8))  // 8
                sbOut = sbAppend(sbOut,movRspFromRax(104))                                 // 8
                loadSz += 16
            }
            if argc2 >= 15 {
                sbOut = sbAppend(sbOut,movRaxFromRsp(vstBase + (vsp - argc2 + 14) * 8))  // 8
                sbOut = sbAppend(sbOut,movRspFromRax(112))                                 // 8
                loadSz += 16
            }
            if argc2 >= 16 {
                sbOut = sbAppend(sbOut,movRaxFromRsp(vstBase + (vsp - argc2 + 15) * 8))  // 8
                sbOut = sbAppend(sbOut,movRspFromRax(120))                                 // 8
                loadSz += 16
            }
            vsp -= argc2

            let callCode = ""
            let callSz = 0
            let resolvedName = resolveBuiltin(a1)
            if a1 == "callPtr" {
                let cpN2 = argc2 - 1
                if cpN2 == 1 { resolvedName = "kr_callptr1" }
                if cpN2 == 2 { resolvedName = "kr_callptr2" }
                if cpN2 == 3 { resolvedName = "kr_callptr3" }
                if cpN2 == 4 { resolvedName = "kr_callptr4" }
            }
            let iatEntryRva2 = iatEntryRvaFor(resolvedName, iatK32BaseRva, iatRtBaseRva, iatAdvBaseRva, iatPdhBaseRva, iatUserBaseRva)
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
            // (label positions tracked via labelPositions parameter, not g_labelMap)
        }

        if op == "JUMP" {
            let jmpTarget = labelLookup(labelPositions, a1)
            let jmpDisp = jmpTarget - (pos + 5)
            sbOut = sbAppend(sbOut,hexByte(0xE9) + hexDword(jmpDisp))
            pos += 5
        }

        if op == "JUMPIF" || op == "JUMPIFNOT" {
            // MOV RCX(8) + CALL[kr_truthy](6) + MOVZX(3) + CMP(2) + JCC(6) = 25 bytes
            // CALL at pos+8, RIP after = pos+14; JCC at pos+19, RIP after = pos+25
            sbOut = sbAppend(sbOut,movRcxFromRsp(vstBase + (vsp - 1) * 8))
            vsp -= 1
            let iatRva3 = iatEntryRvaFor("kr_truthy", iatK32BaseRva, iatRtBaseRva, iatAdvBaseRva, iatPdhBaseRva, iatUserBaseRva)
            let disp5 = iatRva3 - (funcBaseRva + pos + 14)
            sbOut = sbAppend(sbOut,hexByte(0xFF) + hexByte(0x15) + hexDword(disp5))
            sbOut = sbAppend(sbOut,hexByte(0x0F) + hexByte(0xB6) + hexByte(0x00))  // MOVZX EAX, BYTE[RAX]
            sbOut = sbAppend(sbOut,hexByte(0x3C) + hexByte(0x30))                   // CMP AL, '0' (0x30)
            let jcTarget = labelLookup(labelPositions, a1)
            let jcDisp = jcTarget - (pos + 25)
            if op == "JUMPIF" {
                sbOut = sbAppend(sbOut,hexByte(0x0F) + hexByte(0x85) + hexDword(jcDisp))  // JNE (truthy = not '0')
            } else {
                sbOut = sbAppend(sbOut,hexByte(0x0F) + hexByte(0x84) + hexDword(jcDisp))  // JE  (falsy = is '0')
            }
            pos += 25
        }

        if op == "INDEX" {
            // s[i]: string at vsp-2, index at vsp-1 → kr_idx(string, index)
            // MOV RDX(8) + MOV RCX(8) + CALL(6) + MOV result(8) = 30 bytes
            sbOut = sbAppend(sbOut,movRdxFromRsp(vstBase + (vsp - 1) * 8))   // index → RDX  (8)
            sbOut = sbAppend(sbOut,movRcxFromRsp(vstBase + (vsp - 2) * 8))   // string → RCX (8)
            vsp -= 2
            let iatIdx = iatEntryRvaFor("kr_idx", iatK32BaseRva, iatRtBaseRva, iatAdvBaseRva, iatPdhBaseRva, iatUserBaseRva)
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
    let h = sbNew()
    h = sbAppend(h, hexByte(0x4D) + hexByte(0x5A))  // MZ
    h = sbAppend(h, hexByte(0x90) + hexByte(0x00))  // bytes on last page
    h = sbAppend(h, hexByte(0x03) + hexByte(0x00))  // pages in file
    h = sbAppend(h, hexByte(0x00) + hexByte(0x00))  // relocations
    h = sbAppend(h, hexByte(0x04) + hexByte(0x00))  // header size in paragraphs
    h = sbAppend(h, hexByte(0x00) + hexByte(0x00))  // min extra paragraphs
    h = sbAppend(h, hexByte(0xFF) + hexByte(0xFF))  // max extra paragraphs
    h = sbAppend(h, hexByte(0x00) + hexByte(0x00))  // initial SS
    h = sbAppend(h, hexByte(0xB8) + hexByte(0x00))  // initial SP
    h = sbAppend(h, hexByte(0x00) + hexByte(0x00))  // checksum
    h = sbAppend(h, hexByte(0x00) + hexByte(0x00))  // initial IP
    h = sbAppend(h, hexByte(0x00) + hexByte(0x00))  // initial CS
    h = sbAppend(h, hexByte(0x40) + hexByte(0x00))  // offset of relocation table
    h = sbAppend(h, hexByte(0x00) + hexByte(0x00))  // overlay number
    h = sbAppend(h, hexDword(0) + hexDword(0))      // reserved
    h = sbAppend(h, hexByte(0x00) + hexByte(0x00))  // OEM identifier
    h = sbAppend(h, hexByte(0x00) + hexByte(0x00))  // OEM information
    h = sbAppend(h, hexDword(0) + hexDword(0) + hexDword(0) + hexDword(0) + hexDword(0))  // 20 reserved bytes
    h = sbAppend(h, hexDword(64))                   // e_lfanew = 0x40
    emit sbToString(h)
}

// ── PE headers ───────────────────────────────────────────────────
// ── Export table builder ──────────────────────────────────────────

// Lexicographic string less-than (for export name sorting)
func strLt(a, b) {
    let la = toInt(len(a))
    let lb = toInt(len(b))
    let lmin = la
    if lb < lmin { lmin = lb }
    let i = 0
    while i < lmin {
        let ca = toInt(charCode(substring(a, i, i + 1)))
        let cb = toInt(charCode(substring(b, i, i + 1)))
        if ca < cb { emit "1" }
        if ca > cb { emit "0" }
        i += 1
    }
    if la < lb { emit "1" }
    emit "0"
}

// Selection sort of newline-separated name list (required: NPT must be sorted for GetProcAddress)
func sortExportNames(names, count) {
    if count <= 1 { emit names }
    let sorted = names
    let i = 0
    while i < count - 1 {
        let minName = getLine(sorted, i)
        let minIdx = i
        let j = i + 1
        while j < count {
            let jName = getLine(sorted, j)
            if strLt(jName, minName) == "1" { minName = jName  minIdx = j }
            j += 1
        }
        if minIdx != i {
            let iName = getLine(sorted, i)
            let newSorted = ""
            let k = 0
            while k < count {
                if len(newSorted) > 0 { newSorted = newSorted + "\n" }
                if k == i { newSorted = newSorted + minName }
                else if k == minIdx { newSorted = newSorted + iName }
                else { newSorted = newSorted + getLine(sorted, k) }
                k += 1
            }
            sorted = newSorted
        }
        i += 1
    }
    emit sorted
}

// exportNames: newline-separated list of exported function names (in order)
// allFuncOffsets: "name:offset\n" table from pass 1
// textRva: RVA base of .text section
// rdataRva: RVA base of .rdata section
// exportBase: byte offset within .rdata where this table starts
// dllName: the DLL file name string (e.g. "krypton_rt.dll")
// Returns: hex bytes of the export directory + supporting tables
func buildExportTable(exportNames, allFuncOffsets, textRva, rdataRva, exportBase, dllName) {
    let count = 0
    if len(exportNames) > 0 { count = lineCount(exportNames) }
    if count == 0 { emit "" }

    let dirSize  = 40
    let eatSize  = count * 4
    let nptSize  = count * 4
    let otSize   = count * 2
    let otPad    = 0
    if otSize % 4 != 0 { otPad = 2 }

    let dllNameOffset  = dirSize + eatSize + nptSize + otSize + otPad
    let funcNamesStart = dllNameOffset + len(dllName) + 1

    let eatRva  = rdataRva + exportBase + dirSize
    let nptRva  = eatRva + eatSize
    let otRva   = nptRva + nptSize
    let dllNameRva = rdataRva + exportBase + dllNameOffset

    // Build EAT in original declaration order
    let eat = ""
    let ni = 0
    while ni < count {
        let expFn = getLine(exportNames, ni)
        let foff = toInt(funcOffsetLookup(allFuncOffsets, expFn))
        eat = eat + hexDword(textRva + foff)
        ni += 1
    }

    // Build NPT and OT from sorted names (GetProcAddress requires sorted NPT)
    let sortedNames = sortExportNames(exportNames, count)
    let npt = ""
    let ot  = ""
    let nameStrs = ""
    let nameOff = funcNamesStart
    let si = 0
    while si < count {
        let sortedFn = getLine(sortedNames, si)
        // Find original index for this name (OT entry = EAT index)
        let origIdx = 0
        let oi = 0
        while oi < count {
            if getLine(exportNames, oi) == sortedFn { origIdx = oi }
            oi += 1
        }
        npt = npt + hexDword(rdataRva + exportBase + nameOff)
        ot  = ot  + hexWord(origIdx)
        nameStrs = nameStrs + hexStr(sortedFn) + hexByte(0)
        nameOff = nameOff + len(sortedFn) + 1
        si += 1
    }
    let otPadHex = ""
    if otPad > 0 { otPadHex = hexByte(0) + hexByte(0) }

    let dir = hexDword(0) + hexDword(0) + hexWord(0) + hexWord(0)
    dir = dir + hexDword(dllNameRva)
    dir = dir + hexDword(1)
    dir = dir + hexDword(count)
    dir = dir + hexDword(count)
    dir = dir + hexDword(eatRva)
    dir = dir + hexDword(nptRva)
    dir = dir + hexDword(otRva)

    emit dir + eat + npt + ot + otPadHex + hexStr(dllName) + hexByte(0) + nameStrs
}

func emitPEHeader(numSections, textSize, rdataSize, textRva, rdataRva, entryRva, imageSize, iatRva, iatSize, iatInfo) {
    let iatK32Rva = toInt(getLine(iatInfo, 0))
    let isDll = getLine(iatInfo, 1)
    let exportRva = toInt(getLine(iatInfo, 2))
    let exportSize = toInt(getLine(iatInfo, 3))
    let PE_FILE_ALIGN = 512
    let PE_HEADER_SIZE = 512
    let PE_SECT_ALIGN = 4096
    // PE signature "PE\0\0"
    let h = sbNew()
    h = sbAppend(h, hexByte(0x50) + hexByte(0x45) + hexByte(0) + hexByte(0))

    // COFF header (20 bytes)
    h = sbAppend(h, hexByte(0x64) + hexByte(0x86))  // Machine: AMD64 (0x8664 LE)
    h = sbAppend(h, hexWord(numSections))
    h = sbAppend(h, hexDword(0))                    // TimeDateStamp
    h = sbAppend(h, hexDword(0))                    // PointerToSymbolTable
    h = sbAppend(h, hexDword(0))                    // NumberOfSymbols
    h = sbAppend(h, hexByte(0xF0) + hexByte(0x00))  // SizeOfOptionalHeader = 240
    // 0x0022 = EXE, 0x2022 = DLL (adds IMAGE_FILE_DLL 0x2000)
    if isDll == "1" {
        h = sbAppend(h, hexByte(0x22) + hexByte(0x20))  // Characteristics: DLL
    } else {
        h = sbAppend(h, hexByte(0x22) + hexByte(0x00))  // Characteristics: EXE
    }

    // Optional header PE32+ (240 bytes)
    h = sbAppend(h, hexByte(0x0B) + hexByte(0x02))  // Magic PE32+
    h = sbAppend(h, hexByte(0x0E) + hexByte(0x00))  // Linker version
    h = sbAppend(h, hexDword(textSize))
    h = sbAppend(h, hexDword(rdataSize))
    h = sbAppend(h, hexDword(0))                    // SizeOfUninitializedData
    h = sbAppend(h, hexDword(entryRva))
    h = sbAppend(h, hexDword(textRva))
    h = sbAppend(h, hexQword64(0, 1))               // ImageBase = 0x140000000
    h = sbAppend(h, hexDword(PE_SECT_ALIGN))        // SectionAlignment
    h = sbAppend(h, hexDword(PE_FILE_ALIGN))        // FileAlignment
    h = sbAppend(h, hexByte(6) + hexByte(0) + hexByte(0) + hexByte(0))  // MajorOS/MinorOS
    h = sbAppend(h, hexByte(0) + hexByte(0) + hexByte(0) + hexByte(0))  // MajorImage/MinorImage
    h = sbAppend(h, hexByte(6) + hexByte(0) + hexByte(0) + hexByte(0))  // MajorSubsystem/MinorSubsystem
    h = sbAppend(h, hexDword(0))                    // Win32VersionValue
    h = sbAppend(h, hexDword(imageSize))
    h = sbAppend(h, hexDword(PE_HEADER_SIZE))       // SizeOfHeaders
    h = sbAppend(h, hexDword(0))                    // CheckSum
    h = sbAppend(h, hexByte(3) + hexByte(0))        // Subsystem: CUI
    h = sbAppend(h, hexByte(0x60) + hexByte(0x01))  // DllCharacteristics
    h = sbAppend(h, hexQword64(8388608, 0))         // SizeOfStackReserve = 8MB
    h = sbAppend(h, hexQword64(65536, 0))           // SizeOfStackCommit = 64KB
    h = sbAppend(h, hexQword64(1048576, 0))         // SizeOfHeapReserve
    h = sbAppend(h, hexQword64(4096, 0))            // SizeOfHeapCommit
    h = sbAppend(h, hexDword(0))                    // LoaderFlags
    h = sbAppend(h, hexDword(16))                   // NumberOfRvaAndSizes

    // Data directories (16 * 8 bytes = 128 bytes)
    h = sbAppend(h, hexDword(exportRva) + hexDword(exportSize))  // [0] Export
    h = sbAppend(h, hexDword(iatRva) + hexDword(iatSize))         // [1] Import Directory
    h = sbAppend(h, hexDword(0) + hexDword(0))                   // [2] Resource
    h = sbAppend(h, hexDword(0) + hexDword(0))                   // [3] Exception
    h = sbAppend(h, hexDword(0) + hexDword(0))                   // [4] Security
    h = sbAppend(h, hexDword(0) + hexDword(0))                   // [5] BaseReloc
    h = sbAppend(h, hexDword(0) + hexDword(0))                   // [6] Debug
    h = sbAppend(h, hexDword(0) + hexDword(0))                   // [7] Architecture
    h = sbAppend(h, hexDword(0) + hexDword(0))                   // [8] GlobalPtr
    h = sbAppend(h, hexDword(0) + hexDword(0))                   // [9] TLS
    h = sbAppend(h, hexDword(0) + hexDword(0))                   // [10] LoadConfig
    h = sbAppend(h, hexDword(0) + hexDword(0))                   // [11] BoundImport
    h = sbAppend(h, hexDword(iatK32Rva) + hexDword(iatSize))       // [12] IAT (actual IAT start, not desc table)
    h = sbAppend(h, hexDword(0) + hexDword(0))                   // [13] DelayImport
    h = sbAppend(h, hexDword(0) + hexDword(0))                   // [14] CLRHeader
    h = sbAppend(h, hexDword(0) + hexDword(0))                   // [15] reserved

    emit sbToString(h)
}

func emitSectionHeader(name, virtSize, virtAddr, rawSize, rawOffset, characteristics) {
    let h = sbNew()
    h = sbAppend(h, hexStr(name))
    // Pad name to 8 bytes
    let namePad = 8 - len(name)
    let pi = 0
    while pi < namePad { h = sbAppend(h, hexByte(0))  pi += 1 }
    h = sbAppend(h, hexDword(virtSize))
    h = sbAppend(h, hexDword(virtAddr))
    h = sbAppend(h, hexDword(rawSize))
    h = sbAppend(h, hexDword(rawOffset))
    h = sbAppend(h, hexDword(0))   // PointerToRelocations
    h = sbAppend(h, hexDword(0))   // PointerToLinenumbers
    h = sbAppend(h, hexByte(0) + hexByte(0))   // NumberOfRelocations
    h = sbAppend(h, hexByte(0) + hexByte(0))   // NumberOfLinenumbers
    h = sbAppend(h, hexDword(characteristics))
    emit sbToString(h)
}

// ── Bootstrap helper block ────────────────────────────────────────
// In bootstrap mode (building krypton_rt.dll itself), the entire .text section
// is replaced by this block of raw x64 machine code implementing all kr_* functions.
// Functions are ordered dependency-first (all calls are backward).
//
// Offsets (all from start of bootstrap block):
//   OFF_STRLEN=0    OFF_ALLOC=18   OFF_STRDUP=52   OFF_STRCAT=105
//   OFF_ATOI=197    OFF_ITOA=266   OFF_TRUI=377    OFF_STREQ=402
//   OFF_ISNUM=439   OFF_PLUS=488   OFF_SUB=571     OFF_MUL=614
//   OFF_DIV=658     OFF_MOD=711    OFF_NEG=764
//   OFF_EQ=789      OFF_NEQ=828    OFF_LT=870      OFF_GT=1007
//   OFF_LTE=1015    OFF_GTE=1040   OFF_NOT=1062    OFF_TRUS=1105
//   OFF_LEN=1143    OFF_TOINT=1165 OFF_STR=1187    OFF_PRINT=1201
//   OFF_PRINTE=1278 OFF_PRINTL=1355 OFF_EXIT=1360  OFF_SUBSTR=1382
//   OFF_SWS=1482    OFF_CONT=1552  OFF_IDXOF=1662  OFF_TRIM=1772
//   OFF_REPL=1872   OFF_NTH=2092   OFF_SPLIT=2242  OFF_GETLN=2292
//   OFF_LC=2342     OFF_CNT=2392   OFF_RANGE=2442  OFF_CHCODE=2622
//   OFF_ISDIG=2657  OFF_FCC=2702   OFF_TOLWR=2747  OFF_SBNEW=2827
//   OFF_SBAPP=2887  OFF_SBTS=3047  OFF_RDF=3097    OFF_WRF=3277
//   OFF_ARGP=3407   OFF_ARGC=3607  OFF_ARG=3657
//   TOTAL=3737

func bsHelperBlockSize() { emit 3791 }

// Export offset lookup for bootstrap mode: returns "kr_name:offset\n..." table
func bootstrapExportOffsets() {
    let t = ""
    t = t + "kr_str:1187\n"
    t = t + "kr_toint:1165\n"
    t = t + "kr_plus:488\n"
    t = t + "kr_sub:571\n"
    t = t + "kr_mul:614\n"
    t = t + "kr_div:658\n"
    t = t + "kr_mod:711\n"
    t = t + "kr_neg:764\n"
    t = t + "kr_eq:789\n"
    t = t + "kr_neq:828\n"
    t = t + "kr_lt:870\n"
    t = t + "kr_gt:1007\n"
    t = t + "kr_lte:1015\n"
    t = t + "kr_gte:1040\n"
    t = t + "kr_truthy:1105\n"
    t = t + "kr_not:1062\n"
    t = t + "kr_len:1143\n"
    t = t + "kr_substring:1382\n"
    t = t + "kr_startswith:1482\n"
    t = t + "kr_contains:1552\n"
    t = t + "kr_indexof:1662\n"
    t = t + "kr_trim:1772\n"
    t = t + "kr_replace:1872\n"
    t = t + "kr_split:2242\n"
    t = t + "kr_getline:2292\n"
    t = t + "kr_linecount:2342\n"
    t = t + "kr_count:2392\n"
    t = t + "kr_length:2392\n"
    t = t + "kr_print:1201\n"
    t = t + "kr_printerr:1278\n"
    t = t + "kr_printl:1355\n"
    t = t + "kr_exit:1360\n"
    t = t + "kr_range:2442\n"
    t = t + "kr_sbnew:2827\n"
    t = t + "kr_sbappend:2887\n"
    t = t + "kr_sbtostring:3047\n"
    t = t + "kr_readfile:3097\n"
    t = t + "kr_writefile:3277\n"
    t = t + "kr_argcount:3607\n"
    t = t + "kr_arg:3657\n"
    emit t
}

// emitBootstrapHelpers: returns hex-encoded machine code for the full bootstrap block
func emitBootstrapHelpers(textRva, iatK32Rva) {
    let sb = sbNew()
    let pos = 0  // absolute offset within the bootstrap block
    // pre-populated with offsets of already-emitted functions:
    let offsets = "kr_plus:487\nkr_sub:570\nkr_mul:613\nkr_div:657\nkr_mod:708\nkr_neg:759\nkr_eq:784\nkr_neq:823\nkr_lt:865\nkr_gt:1002\nkr_lte:1010\nkr_gte:1035\nkr_not:1057\nkr_truthy:1099\nkr_len:1137\nkr_toint:1159\nkr_str:1181\nkr_print:1195\nkr_printerr:1272\nkr_printl:1349\nkr_exit:1354\nkr_substring:1376\nkr_startswith:1481\n"

    // Convenience: IAT entry RVA for kernel32 function at index i
    // IAT call disp from absolute pos P: iatK32Rva + i*8 - (textRva + P + 6)

    // ── __rt_strlen(RCX=str) → RAX=len ──────────────────────────
    // 18 bytes, no frame, no IAT calls
    // XOR EAX,EAX; TEST RCX,RCX; JZ+10; loop: CMP[RCX+RAX],0; JZ+4; INC EAX; JMP-10; RET
    sb = sbAppend(sb, hexByte(0x33)+hexByte(0xC0))                              // XOR EAX,EAX
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x85)+hexByte(0xC9))                // TEST RCX,RCX
    sb = sbAppend(sb, hexByte(0x74)+hexByte(0x0A))                              // JZ +10
    sb = sbAppend(sb, hexByte(0x80)+hexByte(0x3C)+hexByte(0x01)+hexByte(0x00)) // CMP BYTE[RCX+RAX],0
    sb = sbAppend(sb, hexByte(0x74)+hexByte(0x04))                              // JZ +4
    sb = sbAppend(sb, hexByte(0xFF)+hexByte(0xC0))                              // INC EAX
    sb = sbAppend(sb, hexByte(0xEB)+hexByte(0xF6))                              // JMP -10
    sb = sbAppend(sb, hexByte(0xC3))                                             // RET
    pos = 18

    // ── __rt_alloc(RCX=size) → RAX=ptr ──────────────────────────
    // 34 bytes. Calls GetProcessHeap(idx29) + HeapAlloc(idx26).
    // Frame: push RBX + sub rsp,48
    let gph_disp = iatK32Rva + 29 * 8 - (textRva + pos + 8 + 6)  // local pos of call = 8
    let ha_disp  = iatK32Rva + 26 * 8 - (textRva + pos + 22 + 6) // local pos of HeapAlloc call = 22
    sb = sbAppend(sb, hexByte(0x53))                                             // PUSH RBX
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x30)) // SUB RSP,48
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xCB))                // MOV RBX,RCX
    sb = sbAppend(sb, hexByte(0xFF)+hexByte(0x15)+hexDword(gph_disp))           // CALL [GetProcessHeap]
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))                // MOV RCX,RAX
    sb = sbAppend(sb, hexByte(0x33)+hexByte(0xD2))                              // XOR EDX,EDX
    sb = sbAppend(sb, hexByte(0x49)+hexByte(0x89)+hexByte(0xD8))                // MOV R8,RBX
    sb = sbAppend(sb, hexByte(0xFF)+hexByte(0x15)+hexDword(ha_disp))            // CALL [HeapAlloc]
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x30)) // ADD RSP,48
    sb = sbAppend(sb, hexByte(0x5B))                                             // POP RBX
    sb = sbAppend(sb, hexByte(0xC3))                                             // RET
    pos = 52

    // ── __rt_strdup(RCX=str) → RAX=ptr ──────────────────────────
    // 53 bytes. Calls __rt_strlen(0) + __rt_alloc(18).
    // Frame: push RBX,RSI + sub rsp,40
    // strlen call at local 9: disp = 0 - (pos+9+5) = -(pos+14)
    // alloc call at local 19: disp = 18 - (pos+19+5) = 18-pos-24
    let sd_sl_d = 0 - (pos + 9 + 5)    // strlen call disp
    let sd_al_d = 18 - (pos + 19 + 5)  // alloc call disp
    sb = sbAppend(sb, hexByte(0x53))                                             // PUSH RBX
    sb = sbAppend(sb, hexByte(0x56))                                             // PUSH RSI
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28)) // SUB RSP,40
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xCE))                // MOV RSI,RCX
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(sd_sl_d))                          // CALL __rt_strlen
    sb = sbAppend(sb, hexByte(0xFF)+hexByte(0xC0))                              // INC EAX
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))                // MOV RCX,RAX
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(sd_al_d))                          // CALL __rt_alloc
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))                // MOV RBX,RAX
    sb = sbAppend(sb, hexByte(0x33)+hexByte(0xC9))                              // XOR ECX,ECX
    // .loop (local 29): MOV AL,[RSI+RCX]; MOV[RBX+RCX],AL; TEST AL,AL; JZ+4; INC ECX; JMP-14
    sb = sbAppend(sb, hexByte(0x8A)+hexByte(0x04)+hexByte(0x0E))               // MOV AL,[RSI+RCX]
    sb = sbAppend(sb, hexByte(0x88)+hexByte(0x04)+hexByte(0x0B))               // MOV [RBX+RCX],AL
    sb = sbAppend(sb, hexByte(0x84)+hexByte(0xC0))                              // TEST AL,AL
    sb = sbAppend(sb, hexByte(0x74)+hexByte(0x04))                              // JZ +4
    sb = sbAppend(sb, hexByte(0xFF)+hexByte(0xC1))                              // INC ECX
    sb = sbAppend(sb, hexByte(0xEB)+hexByte(0xF2))                              // JMP -14
    // .done (local 43): MOV RAX,RBX; ADD RSP,40; POP RSI; POP RBX; RET
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x8B)+hexByte(0xC3))               // MOV RAX,RBX
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28)) // ADD RSP,40
    sb = sbAppend(sb, hexByte(0x5E))                                             // POP RSI
    sb = sbAppend(sb, hexByte(0x5B))                                             // POP RBX
    sb = sbAppend(sb, hexByte(0xC3))                                             // RET
    pos = 105

    // ── __rt_strcat(RCX=a, RDX=b) → RAX=ptr ─────────────────────
    // 92 bytes. Frame: push RBX,RSI,RDI + sub rsp,48
    // strlen(a) at local 13: disp=0-(pos+13+5)
    // strlen(b) at local 24: disp=0-(pos+24+5)
    // alloc at local 37: disp=18-(pos+37+5)
    let sc_sl1 = 0 - (pos + 13 + 5)
    let sc_sl2 = 0 - (pos + 24 + 5)
    let sc_al  = 18 - (pos + 37 + 5)
    sb = sbAppend(sb, hexByte(0x53))                                             // PUSH RBX
    sb = sbAppend(sb, hexByte(0x56))                                             // PUSH RSI
    sb = sbAppend(sb, hexByte(0x57))                                             // PUSH RDI
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x30)) // SUB RSP,48
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xCE))                // MOV RSI,RCX (a)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xD7))                // MOV RDI,RDX (b)
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(sc_sl1))                           // CALL strlen(a)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))                // MOV RBX,RAX (lenA)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xF9))                // MOV RCX,RDI
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(sc_sl2))                           // CALL strlen(b)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x03)+hexByte(0xC3))                // ADD RAX,RBX
    sb = sbAppend(sb, hexByte(0xFF)+hexByte(0xC0))                              // INC EAX (+null)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))                // MOV RCX,RAX
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(sc_al))                            // CALL alloc
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))                // MOV RBX,RAX (result)
    // Copy a: XOR ECX,ECX; loop: MOV AL,[RSI+RCX]; MOV[RBX+RCX],AL; TEST AL,AL; JZ+4; INC ECX; JMP-14
    sb = sbAppend(sb, hexByte(0x33)+hexByte(0xC9))                              // XOR ECX,ECX
    sb = sbAppend(sb, hexByte(0x8A)+hexByte(0x04)+hexByte(0x0E))               // MOV AL,[RSI+RCX]
    sb = sbAppend(sb, hexByte(0x88)+hexByte(0x04)+hexByte(0x0B))               // MOV [RBX+RCX],AL
    sb = sbAppend(sb, hexByte(0x84)+hexByte(0xC0))                              // TEST AL,AL
    sb = sbAppend(sb, hexByte(0x74)+hexByte(0x04))                              // JZ +4
    sb = sbAppend(sb, hexByte(0xFF)+hexByte(0xC1))                              // INC ECX
    sb = sbAppend(sb, hexByte(0xEB)+hexByte(0xF2))                              // JMP -14
    // RCX=lenA. LEA RDX,[RBX+RCX]; XOR ECX,ECX; copy b loop
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x8D)+hexByte(0x14)+hexByte(0x0B)) // LEA RDX,[RBX+RCX]
    sb = sbAppend(sb, hexByte(0x33)+hexByte(0xC9))                              // XOR ECX,ECX
    sb = sbAppend(sb, hexByte(0x8A)+hexByte(0x04)+hexByte(0x0F))               // MOV AL,[RDI+RCX]
    sb = sbAppend(sb, hexByte(0x88)+hexByte(0x04)+hexByte(0x0A))               // MOV [RDX+RCX],AL
    sb = sbAppend(sb, hexByte(0x84)+hexByte(0xC0))                              // TEST AL,AL
    sb = sbAppend(sb, hexByte(0x74)+hexByte(0x04))                              // JZ +4
    sb = sbAppend(sb, hexByte(0xFF)+hexByte(0xC1))                              // INC ECX
    sb = sbAppend(sb, hexByte(0xEB)+hexByte(0xF2))                              // JMP -14
    // MOV RAX,RBX; epilogue
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x8B)+hexByte(0xC3))               // MOV RAX,RBX
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x30)) // ADD RSP,48
    sb = sbAppend(sb, hexByte(0x5F))                                             // POP RDI
    sb = sbAppend(sb, hexByte(0x5E))                                             // POP RSI
    sb = sbAppend(sb, hexByte(0x5B))                                             // POP RBX
    sb = sbAppend(sb, hexByte(0xC3))                                             // RET
    pos = 197

    // ── __rt_atoi(RCX=str) → RAX=int64 ──────────────────────────
    // 69 bytes. No frame, no IAT calls.
    sb = sbAppend(sb, hexByte(0x4C)+hexByte(0x8B)+hexByte(0xC1))               // MOV R8,RCX
    sb = sbAppend(sb, hexByte(0x33)+hexByte(0xC0))                              // XOR EAX,EAX
    sb = sbAppend(sb, hexByte(0x45)+hexByte(0x33)+hexByte(0xC9))               // XOR R9D,R9D
    sb = sbAppend(sb, hexByte(0x41)+hexByte(0x80)+hexByte(0x38)+hexByte(0x00)) // CMP BYTE[R8],0
    sb = sbAppend(sb, hexByte(0x74)+hexByte(0x2E))                              // JZ .done (+46)
    sb = sbAppend(sb, hexByte(0x41)+hexByte(0x80)+hexByte(0x38)+hexByte(0x2D)) // CMP BYTE[R8],'-'
    sb = sbAppend(sb, hexByte(0x75)+hexByte(0x09))                              // JNZ .digits (+9)
    sb = sbAppend(sb, hexByte(0x41)+hexByte(0xB9)+hexDword(1))                 // MOV R9D,1
    sb = sbAppend(sb, hexByte(0x49)+hexByte(0xFF)+hexByte(0xC0))               // INC R8
    // .digits (local 29):
    sb = sbAppend(sb, hexByte(0x41)+hexByte(0x80)+hexByte(0x38)+hexByte(0x30)) // CMP BYTE[R8],'0'
    sb = sbAppend(sb, hexByte(0x7C)+hexByte(0x19))                              // JL .done (+25)
    sb = sbAppend(sb, hexByte(0x41)+hexByte(0x80)+hexByte(0x38)+hexByte(0x39)) // CMP BYTE[R8],'9'
    sb = sbAppend(sb, hexByte(0x7F)+hexByte(0x13))                              // JG .done (+19)
    sb = sbAppend(sb, hexByte(0x41)+hexByte(0x0F)+hexByte(0xB6)+hexByte(0x08)) // MOVZX ECX,BYTE[R8]
    sb = sbAppend(sb, hexByte(0x83)+hexByte(0xE9)+hexByte(0x30))               // SUB ECX,48
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x6B)+hexByte(0xC0)+hexByte(0x0A)) // IMUL RAX,RAX,10
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x03)+hexByte(0xC1))               // ADD RAX,RCX
    sb = sbAppend(sb, hexByte(0x49)+hexByte(0xFF)+hexByte(0xC0))               // INC R8
    sb = sbAppend(sb, hexByte(0xEB)+hexByte(0xE1))                              // JMP .digits (-31)
    // .done (local 60):
    sb = sbAppend(sb, hexByte(0x45)+hexByte(0x85)+hexByte(0xC9))               // TEST R9D,R9D
    sb = sbAppend(sb, hexByte(0x74)+hexByte(0x03))                              // JZ .ret (+3)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0xF7)+hexByte(0xD8))               // NEG RAX
    // .ret (local 68):
    sb = sbAppend(sb, hexByte(0xC3))                                             // RET
    pos = 266

    // ── __rt_itoa(RCX=int64) → RAX=str ──────────────────────────
    // 110 bytes. Frame: push RBX,RSI + sub rsp,56 (local buf at RSP+32..55)
    // strdup call at local 98: disp = 52-(pos+98+5)
    let it_sd_d = 52 - (pos + 98 + 5)
    sb = sbAppend(sb, hexByte(0x53))                                             // PUSH RBX
    sb = sbAppend(sb, hexByte(0x56))                                             // PUSH RSI
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x38)) // SUB RSP,56
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xCB))                // MOV RBX,RCX
    sb = sbAppend(sb, hexByte(0x45)+hexByte(0x33)+hexByte(0xC0))               // XOR R8D,R8D
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x85)+hexByte(0xDB))               // TEST RBX,RBX
    sb = sbAppend(sb, hexByte(0x79)+hexByte(0x09))                              // JNS .pos (+9)
    sb = sbAppend(sb, hexByte(0x41)+hexByte(0xB8)+hexDword(1))                 // MOV R8D,1
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0xF7)+hexByte(0xDB))               // NEG RBX
    // .pos (local 26):
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x8D)+hexByte(0x74)+hexByte(0x24)+hexByte(0x38)) // LEA RSI,[RSP+56]
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0xFF)+hexByte(0xCE))               // DEC RSI
    sb = sbAppend(sb, hexByte(0xC6)+hexByte(0x06)+hexByte(0x00))               // MOV BYTE[RSI],0
    sb = sbAppend(sb, hexByte(0xB9)+hexDword(10))                               // MOV ECX,10
    // .dig_loop (local 42):
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x85)+hexByte(0xDB))               // TEST RBX,RBX
    sb = sbAppend(sb, hexByte(0x74)+hexByte(0x15))                              // JZ .done_digs (+21)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xD8))               // MOV RAX,RBX
    sb = sbAppend(sb, hexByte(0x33)+hexByte(0xD2))                              // XOR EDX,EDX
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0xF7)+hexByte(0xF1))               // DIV RCX
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))               // MOV RBX,RAX
    sb = sbAppend(sb, hexByte(0x80)+hexByte(0xC2)+hexByte(0x30))               // ADD DL,'0'
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0xFF)+hexByte(0xCE))               // DEC RSI
    sb = sbAppend(sb, hexByte(0x88)+hexByte(0x16))                              // MOV [RSI],DL
    sb = sbAppend(sb, hexByte(0xEB)+hexByte(0xE6))                              // JMP .dig_loop (-26)
    // .done_digs (local 68):
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x8D)+hexByte(0x44)+hexByte(0x24)+hexByte(0x37)) // LEA RAX,[RSP+55]
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x3B)+hexByte(0xF0))               // CMP RSI,RAX
    sb = sbAppend(sb, hexByte(0x75)+hexByte(0x06))                              // JNZ .has_digits (+6)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0xFF)+hexByte(0xCE))               // DEC RSI
    sb = sbAppend(sb, hexByte(0xC6)+hexByte(0x06)+hexByte(0x30))               // MOV BYTE[RSI],'0'
    // .has_digits (local 83):
    sb = sbAppend(sb, hexByte(0x45)+hexByte(0x85)+hexByte(0xC0))               // TEST R8D,R8D
    sb = sbAppend(sb, hexByte(0x74)+hexByte(0x06))                              // JZ .copy_out (+6)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0xFF)+hexByte(0xCE))               // DEC RSI
    sb = sbAppend(sb, hexByte(0xC6)+hexByte(0x06)+hexByte(0x2D))               // MOV BYTE[RSI],'-'
    // .copy_out (local 94):
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xF1))               // MOV RCX,RSI
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(it_sd_d))                          // CALL __rt_strdup
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x38)) // ADD RSP,56
    sb = sbAppend(sb, hexByte(0x5E))                                             // POP RSI
    sb = sbAppend(sb, hexByte(0x5B))                                             // POP RBX
    sb = sbAppend(sb, hexByte(0xC3))                                             // RET
    pos = 376

    // ── __rt_truthy_int(RCX=str) → RAX=0or1 (integer) ───────────
    // 25 bytes. No frame, no calls.
    sb = sbAppend(sb, hexByte(0x80)+hexByte(0x39)+hexByte(0x00))               // CMP BYTE[RCX],0
    sb = sbAppend(sb, hexByte(0x74)+hexByte(0x0B))                              // JZ .false (+11)
    sb = sbAppend(sb, hexByte(0x80)+hexByte(0x39)+hexByte(0x30))               // CMP BYTE[RCX],'0'
    sb = sbAppend(sb, hexByte(0x75)+hexByte(0x09))                              // JNZ .true (+9)
    sb = sbAppend(sb, hexByte(0x80)+hexByte(0x79)+hexByte(0x01)+hexByte(0x00)) // CMP BYTE[RCX+1],0
    sb = sbAppend(sb, hexByte(0x75)+hexByte(0x03))                              // JNZ .true (+3)
    // .false (local 16):
    sb = sbAppend(sb, hexByte(0x33)+hexByte(0xC0))                              // XOR EAX,EAX
    sb = sbAppend(sb, hexByte(0xC3))                                             // RET
    // .true (local 19):
    sb = sbAppend(sb, hexByte(0xB8)+hexDword(1))                                // MOV EAX,1
    sb = sbAppend(sb, hexByte(0xC3))                                             // RET
    pos = 401

    // ── __rt_streq(RCX=a, RDX=b) → RAX=0or1 (integer) ───────────
    // 37 bytes. No frame, no calls.
    sb = sbAppend(sb, hexByte(0x45)+hexByte(0x33)+hexByte(0xC0))               // XOR R8D,R8D (index)
    // .loop (local 3):
    sb = sbAppend(sb, hexByte(0x46)+hexByte(0x0F)+hexByte(0xB6)+hexByte(0x0C)+hexByte(0x01)) // MOVZX R9D,BYTE[RCX+R8]
    sb = sbAppend(sb, hexByte(0x46)+hexByte(0x0F)+hexByte(0xB6)+hexByte(0x14)+hexByte(0x02)) // MOVZX R10D,BYTE[RDX+R8]
    sb = sbAppend(sb, hexByte(0x45)+hexByte(0x3B)+hexByte(0xCA))               // CMP R9D,R10D
    sb = sbAppend(sb, hexByte(0x75)+hexByte(0x0A))                              // JNZ .ne (+10)
    sb = sbAppend(sb, hexByte(0x45)+hexByte(0x85)+hexByte(0xC9))               // TEST R9D,R9D
    sb = sbAppend(sb, hexByte(0x74)+hexByte(0x08))                              // JZ .equal (+8)
    sb = sbAppend(sb, hexByte(0x41)+hexByte(0xFF)+hexByte(0xC0))               // INC R8D
    sb = sbAppend(sb, hexByte(0xEB)+hexByte(0xE7))                              // JMP .loop (-25)
    // .ne (local 28):
    sb = sbAppend(sb, hexByte(0x33)+hexByte(0xC0))                              // XOR EAX,EAX
    sb = sbAppend(sb, hexByte(0xC3))                                             // RET
    // .equal (local 31):
    sb = sbAppend(sb, hexByte(0xB8)+hexDword(1))                                // MOV EAX,1
    sb = sbAppend(sb, hexByte(0xC3))                                             // RET
    pos = 438

    // ── __rt_isnumeric(RCX=str) → RAX=0or1 (integer) ────────────
    // 49 bytes. No frame, no calls.
    sb = sbAppend(sb, hexByte(0x80)+hexByte(0x39)+hexByte(0x00))               // CMP BYTE[RCX],0
    sb = sbAppend(sb, hexByte(0x74)+hexByte(0x23))                              // JZ .false (+35)
    sb = sbAppend(sb, hexByte(0x0F)+hexByte(0xB6)+hexByte(0x01))               // MOVZX EAX,BYTE[RCX]
    sb = sbAppend(sb, hexByte(0x3C)+hexByte(0x2D))                              // CMP AL,'-'
    sb = sbAppend(sb, hexByte(0x75)+hexByte(0x08))                              // JNZ .check_digit (+8)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC1))               // INC RCX
    sb = sbAppend(sb, hexByte(0x80)+hexByte(0x39)+hexByte(0x00))               // CMP BYTE[RCX],0
    sb = sbAppend(sb, hexByte(0x74)+hexByte(0x14))                              // JZ .false (+20)
    // .check_digit (local 20):
    sb = sbAppend(sb, hexByte(0x0F)+hexByte(0xB6)+hexByte(0x01))               // MOVZX EAX,BYTE[RCX]
    sb = sbAppend(sb, hexByte(0x84)+hexByte(0xC0))                              // TEST AL,AL
    sb = sbAppend(sb, hexByte(0x74)+hexByte(0x10))                              // JZ .true (+16)
    sb = sbAppend(sb, hexByte(0x3C)+hexByte(0x30))                              // CMP AL,'0'
    sb = sbAppend(sb, hexByte(0x7C)+hexByte(0x09))                              // JL .false (+9)
    sb = sbAppend(sb, hexByte(0x3C)+hexByte(0x39))                              // CMP AL,'9'
    sb = sbAppend(sb, hexByte(0x7F)+hexByte(0x05))                              // JG .false (+5)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC1))               // INC RCX
    sb = sbAppend(sb, hexByte(0xEB)+hexByte(0xEC))                              // JMP .check_digit (-20)
    // .false (local 40):
    sb = sbAppend(sb, hexByte(0x33)+hexByte(0xC0))                              // XOR EAX,EAX
    sb = sbAppend(sb, hexByte(0xC3))                                             // RET
    // .true (local 43):
    sb = sbAppend(sb, hexByte(0xB8)+hexDword(1))                                // MOV EAX,1
    sb = sbAppend(sb, hexByte(0xC3))                                             // RET
    pos = 487

    // ── __rt_plus(RCX=a, RDX=b) → RAX=str ───────────────────────
    // 83 bytes. Frame: push RBX,RDI + sub rsp,40
    let pl_isn1 = 438 - (pos + 12 + 5)  // isnumeric(a) at local 12
    let pl_isn2 = 438 - (pos + 24 + 5)  // isnumeric(b) at local 24
    let pl_ato1 = 197 - (pos + 36 + 5)  // atoi(a) at local 36
    let pl_ato2 = 197 - (pos + 47 + 5)  // atoi(b) at local 47
    let pl_ito  = 266 - (pos + 58 + 5)  // itoa at local 58
    let pl_sct  = 105 - (pos + 71 + 5)  // strcat at local 71
    sb = sbAppend(sb, hexByte(0x53))                                             // PUSH RBX
    sb = sbAppend(sb, hexByte(0x57))                                             // PUSH RDI
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28)) // SUB RSP,40
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xCB))                // MOV RBX,RCX
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xD7))                // MOV RDI,RDX
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(pl_isn1))                           // CALL isnumeric(a)
    sb = sbAppend(sb, hexByte(0x85)+hexByte(0xC0))                              // TEST EAX,EAX
    sb = sbAppend(sb, hexByte(0x74)+hexByte(0x2C))                              // JZ .concat (+44)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xF9))                // MOV RCX,RDI
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(pl_isn2))                           // CALL isnumeric(b)
    sb = sbAppend(sb, hexByte(0x85)+hexByte(0xC0))                              // TEST EAX,EAX
    sb = sbAppend(sb, hexByte(0x74)+hexByte(0x20))                              // JZ .concat (+32)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xD9))                // MOV RCX,RBX
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(pl_ato1))                           // CALL atoi(a)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))                // MOV RBX,RAX
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xF9))                // MOV RCX,RDI
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(pl_ato2))                           // CALL atoi(b)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x03)+hexByte(0xC3))                // ADD RAX,RBX
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))                // MOV RCX,RAX
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(pl_ito))                            // CALL itoa
    sb = sbAppend(sb, hexByte(0xEB)+hexByte(0x0B))                              // JMP .done (+11)
    // .concat (local 65):
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xD9))                // MOV RCX,RBX
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xFA))                // MOV RDX,RDI
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(pl_sct))                            // CALL strcat
    // .done (local 76):
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28)) // ADD RSP,40
    sb = sbAppend(sb, hexByte(0x5F))                                             // POP RDI
    sb = sbAppend(sb, hexByte(0x5B))                                             // POP RBX
    sb = sbAppend(sb, hexByte(0xC3))                                             // RET
    pos = 570

    // ── __rt_sub(RCX=a, RDX=b) → RAX=str ────────────────────────
    // 43 bytes. Frame: push RBX,RDI + sub rsp,40
    let su_ato1 = 197 - (pos + 9 + 5)
    let su_ato2 = 197 - (pos + 20 + 5)
    let su_ito  = 266 - (pos + 31 + 5)
    sb = sbAppend(sb, hexByte(0x53))                                             // PUSH RBX
    sb = sbAppend(sb, hexByte(0x57))                                             // PUSH RDI
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28)) // SUB RSP,40
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xD7))                // MOV RDI,RDX
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(su_ato1))                           // CALL atoi(a)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))                // MOV RBX,RAX
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xF9))                // MOV RCX,RDI
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(su_ato2))                           // CALL atoi(b)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x2B)+hexByte(0xD8))                // SUB RBX,RAX
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xD9))                // MOV RCX,RBX
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(su_ito))                            // CALL itoa
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28)) // ADD RSP,40
    sb = sbAppend(sb, hexByte(0x5F))                                             // POP RDI
    sb = sbAppend(sb, hexByte(0x5B))                                             // POP RBX
    sb = sbAppend(sb, hexByte(0xC3))                                             // RET
    pos = 613

    // ── __rt_mul ──────────────────────────────────────────────────
    // 44 bytes (IMUL is 4 bytes vs SUB 3 bytes)
    let mu_ato1 = 197 - (pos + 9 + 5)
    let mu_ato2 = 197 - (pos + 20 + 5)
    let mu_ito  = 266 - (pos + 32 + 5)
    sb = sbAppend(sb, hexByte(0x53))
    sb = sbAppend(sb, hexByte(0x57))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xD7))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(mu_ato1))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xF9))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(mu_ato2))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x0F)+hexByte(0xAF)+hexByte(0xD8)) // IMUL RBX,RAX
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xD9))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(mu_ito))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28))
    sb = sbAppend(sb, hexByte(0x5F))
    sb = sbAppend(sb, hexByte(0x5B))
    sb = sbAppend(sb, hexByte(0xC3))
    pos = 657

    // ── __rt_div ──────────────────────────────────────────────────
    // 53 bytes
    let dv_ato1 = 197 - (pos + 9 + 5)
    let dv_ato2 = 197 - (pos + 20 + 5)
    let dv_ito  = 266 - (pos + 39 + 5)
    sb = sbAppend(sb, hexByte(0x53))
    sb = sbAppend(sb, hexByte(0x57))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xD7))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(dv_ato1))                           // atoi(a)→rbx
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xF9))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(dv_ato2))                           // atoi(b)→rax
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))                // MOV RCX,RAX (divisor)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xD8))                // MOV RAX,RBX (dividend)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x99))                               // CQO
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0xF7)+hexByte(0xF9))                // IDIV RCX
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))                // MOV RCX,RAX
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(dv_ito))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28))
    sb = sbAppend(sb, hexByte(0x5F))
    sb = sbAppend(sb, hexByte(0x5B))
    sb = sbAppend(sb, hexByte(0xC3))
    pos = 708

    // ── __rt_mod ──────────────────────────────────────────────────
    // 53 bytes (same as div but use RDX remainder)
    let md_ato1 = 197 - (pos + 9 + 5)
    let md_ato2 = 197 - (pos + 20 + 5)
    let md_ito  = 266 - (pos + 39 + 5)
    sb = sbAppend(sb, hexByte(0x53))
    sb = sbAppend(sb, hexByte(0x57))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xD7))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(md_ato1))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xF9))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(md_ato2))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xD8))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x99))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0xF7)+hexByte(0xF9))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xD1))                // MOV RCX,RDX (remainder)
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(md_ito))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28))
    sb = sbAppend(sb, hexByte(0x5F))
    sb = sbAppend(sb, hexByte(0x5B))
    sb = sbAppend(sb, hexByte(0xC3))
    pos = 759

    // ── __rt_neg ──────────────────────────────────────────────────
    // 25 bytes. No push needed.
    let ng_ato = 197 - (pos + 4 + 5)
    let ng_ito = 266 - (pos + 15 + 5)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28)) // SUB RSP,40
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(ng_ato))                            // CALL atoi
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0xF7)+hexByte(0xD8))                // NEG RAX
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))                // MOV RCX,RAX
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(ng_ito))                            // CALL itoa
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28)) // ADD RSP,40
    sb = sbAppend(sb, hexByte(0xC3))                                             // RET
    pos = 784

    // ── __rt_eq(RCX=a, RDX=b) → RAX=str("0"/"1") ────────────────
    // 39 bytes. push RBX + sub rsp,48
    let eq_seq = 401 - (pos + 5 + 5)
    let eq_al  = 18  - (pos + 18 + 5)
    sb = sbAppend(sb, hexByte(0x53))                                             // PUSH RBX
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x30)) // SUB RSP,48
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(eq_seq))                            // CALL streq
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))                // MOV RBX,RAX
    sb = sbAppend(sb, hexByte(0xB9)+hexDword(2))                                 // MOV ECX,2
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(eq_al))                             // CALL alloc
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x8D)+hexByte(0x4B)+hexByte(0x30)) // LEA RCX,[RBX+0x30]
    sb = sbAppend(sb, hexByte(0x88)+hexByte(0x08))                               // MOV [RAX],CL
    sb = sbAppend(sb, hexByte(0xC6)+hexByte(0x40)+hexByte(0x01)+hexByte(0x00)) // MOV BYTE[RAX+1],0
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x30)) // ADD RSP,48
    sb = sbAppend(sb, hexByte(0x5B))                                             // POP RBX
    sb = sbAppend(sb, hexByte(0xC3))                                             // RET
    pos = 823

    // ── __rt_neq ──────────────────────────────────────────────────
    // 42 bytes (same as eq but XOR EBX,1 after streq)
    let ne_seq = 401 - (pos + 5 + 5)
    let ne_al  = 18  - (pos + 21 + 5)
    sb = sbAppend(sb, hexByte(0x53))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x30))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(ne_seq))                            // CALL streq
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))
    sb = sbAppend(sb, hexByte(0x83)+hexByte(0xF3)+hexByte(0x01))                // XOR EBX,1 (flip)
    sb = sbAppend(sb, hexByte(0xB9)+hexDword(2))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(ne_al))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x8D)+hexByte(0x4B)+hexByte(0x30))
    sb = sbAppend(sb, hexByte(0x88)+hexByte(0x08))
    sb = sbAppend(sb, hexByte(0xC6)+hexByte(0x40)+hexByte(0x01)+hexByte(0x00))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x30))
    sb = sbAppend(sb, hexByte(0x5B))
    sb = sbAppend(sb, hexByte(0xC3))
    pos = 865

    // ── __rt_lt(RCX=a, RDX=b) → RAX=str("0"/"1") ────────────────
    // 137 bytes. push RBX,RSI,RDI + sub rsp,48
    let lt_isn1 = 438 - (pos + 13 + 5)
    let lt_isn2 = 438 - (pos + 25 + 5)
    let lt_ato1 = 197 - (pos + 37 + 5)
    let lt_ato2 = 197 - (pos + 48 + 5)
    let lt_al   = 18  - (pos + 114 + 5)
    sb = sbAppend(sb, hexByte(0x53))
    sb = sbAppend(sb, hexByte(0x56))
    sb = sbAppend(sb, hexByte(0x57))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x30))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xCE))                // MOV RSI,RCX
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xD7))                // MOV RDI,RDX
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(lt_isn1))                           // isnumeric(a)
    sb = sbAppend(sb, hexByte(0x85)+hexByte(0xC0))
    sb = sbAppend(sb, hexByte(0x74)+hexByte(0x2A))                              // JZ .strlt (+42)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xF9))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(lt_isn2))                           // isnumeric(b)
    sb = sbAppend(sb, hexByte(0x85)+hexByte(0xC0))
    sb = sbAppend(sb, hexByte(0x74)+hexByte(0x1E))                              // JZ .strlt (+30)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xF1))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(lt_ato1))                           // atoi(a)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xF9))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(lt_ato2))                           // atoi(b)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x3B)+hexByte(0xD8))                // CMP RBX,RAX
    sb = sbAppend(sb, hexByte(0x0F)+hexByte(0x9C)+hexByte(0xC0))                // SETL AL
    sb = sbAppend(sb, hexByte(0x0F)+hexByte(0xB6)+hexByte(0xD8))                // MOVZX EBX,AL
    sb = sbAppend(sb, hexByte(0xEB)+hexByte(0x2D))                              // JMP .make_str (+45)
    // .strlt (local 64): lexicographic compare
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xF1))                // MOV RCX,RSI
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xFA))                // MOV RDX,RDI
    sb = sbAppend(sb, hexByte(0x45)+hexByte(0x33)+hexByte(0xC0))                // XOR R8D,R8D
    // .slloop (local 73):
    sb = sbAppend(sb, hexByte(0x46)+hexByte(0x0F)+hexByte(0xB6)+hexByte(0x0C)+hexByte(0x01)) // MOVZX R9D,BYTE[RCX+R8]
    sb = sbAppend(sb, hexByte(0x46)+hexByte(0x0F)+hexByte(0xB6)+hexByte(0x14)+hexByte(0x02)) // MOVZX R10D,BYTE[RDX+R8]
    sb = sbAppend(sb, hexByte(0x45)+hexByte(0x3B)+hexByte(0xCA))                // CMP R9D,R10D
    sb = sbAppend(sb, hexByte(0x7C)+hexByte(0x10))                              // JL .true (+16)
    sb = sbAppend(sb, hexByte(0x7F)+hexByte(0x0A))                              // JG .false (+10)
    sb = sbAppend(sb, hexByte(0x45)+hexByte(0x85)+hexByte(0xC9))                // TEST R9D,R9D
    sb = sbAppend(sb, hexByte(0x74)+hexByte(0x05))                              // JZ .false (+5)
    sb = sbAppend(sb, hexByte(0x41)+hexByte(0xFF)+hexByte(0xC0))                // INC R8D
    sb = sbAppend(sb, hexByte(0xEB)+hexByte(0xE5))                              // JMP .slloop (-27)
    // .false (local 100):
    sb = sbAppend(sb, hexByte(0x33)+hexByte(0xDB))                              // XOR EBX,EBX
    sb = sbAppend(sb, hexByte(0xEB)+hexByte(0x05))                              // JMP .make_str (+5)
    // .true (local 104):
    sb = sbAppend(sb, hexByte(0xBB)+hexDword(1))                                 // MOV EBX,1
    // .make_str (local 109):
    sb = sbAppend(sb, hexByte(0xB9)+hexDword(2))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(lt_al))                             // CALL alloc
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x8D)+hexByte(0x4B)+hexByte(0x30)) // LEA RCX,[RBX+0x30]
    sb = sbAppend(sb, hexByte(0x88)+hexByte(0x08))
    sb = sbAppend(sb, hexByte(0xC6)+hexByte(0x40)+hexByte(0x01)+hexByte(0x00))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x30))
    sb = sbAppend(sb, hexByte(0x5F))
    sb = sbAppend(sb, hexByte(0x5E))
    sb = sbAppend(sb, hexByte(0x5B))
    sb = sbAppend(sb, hexByte(0xC3))
    pos = 1002

    // ── __rt_gt(RCX=a, RDX=b) → swap + jmp lt ───────────────────
    // 8 bytes
    let gt_lt = 865 - (pos + 3 + 5)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x87)+hexByte(0xCA))                // XCHG RCX,RDX
    sb = sbAppend(sb, hexByte(0xE9)+hexDword(gt_lt))                             // JMP __rt_lt
    pos = 1010

    // ── __rt_lte(RCX=a, RDX=b) → gt result flipped ──────────────
    // 25 bytes. swap, call lt, flip char
    let lte_lt = 865 - (pos + 7 + 5)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28)) // SUB RSP,40
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x87)+hexByte(0xCA))                // XCHG RCX,RDX
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(lte_lt))                            // CALL lt(b,a)
    sb = sbAppend(sb, hexByte(0x0F)+hexByte(0xB6)+hexByte(0x08))                // MOVZX ECX,BYTE[RAX]
    sb = sbAppend(sb, hexByte(0x80)+hexByte(0xF1)+hexByte(0x01))                // XOR CL,1
    sb = sbAppend(sb, hexByte(0x88)+hexByte(0x08))                               // MOV [RAX],CL
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28)) // ADD RSP,40
    sb = sbAppend(sb, hexByte(0xC3))                                             // RET
    pos = 1035

    // ── __rt_gte ──────────────────────────────────────────────────
    // 22 bytes. call lt, flip char
    let gte_lt = 865 - (pos + 4 + 5)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28)) // SUB RSP,40
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(gte_lt))                            // CALL lt(a,b)
    sb = sbAppend(sb, hexByte(0x0F)+hexByte(0xB6)+hexByte(0x08))                // MOVZX ECX,BYTE[RAX]
    sb = sbAppend(sb, hexByte(0x80)+hexByte(0xF1)+hexByte(0x01))                // XOR CL,1
    sb = sbAppend(sb, hexByte(0x88)+hexByte(0x08))                               // MOV [RAX],CL
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28)) // ADD RSP,40
    sb = sbAppend(sb, hexByte(0xC3))
    pos = 1057

    // ── __rt_not ──────────────────────────────────────────────────
    // 43 bytes. push RBX + sub rsp,48
    let not_tru = 376 - (pos + 5 + 5)
    let not_al  = 18  - (pos + 21 + 5)
    sb = sbAppend(sb, hexByte(0x53))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x30))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(not_tru))                           // CALL truthy_int
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))
    sb = sbAppend(sb, hexByte(0x83)+hexByte(0xF3)+hexByte(0x01))                // XOR EBX,1
    sb = sbAppend(sb, hexByte(0xB9)+hexDword(2))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(not_al))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x8D)+hexByte(0x4B)+hexByte(0x30))
    sb = sbAppend(sb, hexByte(0x88)+hexByte(0x08))
    sb = sbAppend(sb, hexByte(0xC6)+hexByte(0x40)+hexByte(0x01)+hexByte(0x00))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x30))
    sb = sbAppend(sb, hexByte(0x5B))
    sb = sbAppend(sb, hexByte(0xC3))
    pos = 1099

    // ── kr_truthy(RCX=s) → RAX=str("0"/"1") ─────────────────────
    // 38 bytes. push RBX + sub rsp,48
    let ktr_tru = 376 - (pos + 5 + 5)
    let ktr_al  = 18  - (pos + 17 + 5)
    sb = sbAppend(sb, hexByte(0x53))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x30))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(ktr_tru))
    sb = sbAppend(sb, hexByte(0x89)+hexByte(0xC3))                              // MOV EBX,EAX
    sb = sbAppend(sb, hexByte(0xB9)+hexDword(2))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(ktr_al))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x8D)+hexByte(0x4B)+hexByte(0x30))
    sb = sbAppend(sb, hexByte(0x88)+hexByte(0x08))
    sb = sbAppend(sb, hexByte(0xC6)+hexByte(0x40)+hexByte(0x01)+hexByte(0x00))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x30))
    sb = sbAppend(sb, hexByte(0x5B))
    sb = sbAppend(sb, hexByte(0xC3))
    pos = 1137

    // ── kr_len(RCX=s) → RAX=str ──────────────────────────────────
    // 22 bytes
    let kl_sl = 0   - (pos + 4 + 5)
    let kl_it = 266 - (pos + 12 + 5)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(kl_sl))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(kl_it))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28))
    sb = sbAppend(sb, hexByte(0xC3))
    pos = 1159

    // ── kr_toint(RCX=s) → RAX=str ────────────────────────────────
    // 22 bytes
    let kt_at = 197 - (pos + 4 + 5)
    let kt_it = 266 - (pos + 12 + 5)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(kt_at))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(kt_it))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28))
    sb = sbAppend(sb, hexByte(0xC3))
    pos = 1181

    // ── kr_str(RCX=s) → RAX=strdup(s) ───────────────────────────
    // 14 bytes
    let ks_sd = 52 - (pos + 4 + 5)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(ks_sd))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28))
    sb = sbAppend(sb, hexByte(0xC3))
    pos = 1195

    // ── kr_print(RCX=s) → RAX=str("") ────────────────────────────
    // 77 bytes. push RBX,RSI + sub rsp,56 (0x38 for 16-byte alignment)
    let pr_sl  = 0  - (pos + 9 + 5)
    let pr_gsh_d = iatK32Rva + 1 * 8 - (textRva + pos + 22 + 6)  // GetStdHandle
    let pr_wf_d  = iatK32Rva + 30 * 8 - (textRva + pos + 51 + 6) // WriteFile
    let pr_al  = 18 - (pos + 62 + 5)
    sb = sbAppend(sb, hexByte(0x53))
    sb = sbAppend(sb, hexByte(0x56))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x38))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xCE))                // MOV RSI,RCX
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(pr_sl))                             // CALL strlen
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))                // MOV RBX,RAX (len)
    // GetStdHandle(-11)
    sb = sbAppend(sb, hexByte(0xB9)+hexDword(0xFFFFFFF5))                        // MOV ECX,-11
    sb = sbAppend(sb, hexByte(0xFF)+hexByte(0x15)+hexDword(pr_gsh_d))           // CALL GetStdHandle
    // WriteFile(handle, buf, len, pwritten, NULL)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))                // MOV RCX,RAX (handle)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xF2))                // MOV RDX,RSI (buf)
    sb = sbAppend(sb, hexByte(0x41)+hexByte(0x89)+hexByte(0xD8))                // MOV R8D,EBX (len) REX.B=dest R8
    sb = sbAppend(sb, hexByte(0x4C)+hexByte(0x8D)+hexByte(0x4C)+hexByte(0x24)+hexByte(0x18)) // LEA R9,[RSP+24] (bytes_written scratch)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0xC7)+hexByte(0x44)+hexByte(0x24)+hexByte(0x20)+hexDword(0)) // MOV QWORD[RSP+32],0 (overlapped=NULL)
    sb = sbAppend(sb, hexByte(0xFF)+hexByte(0x15)+hexDword(pr_wf_d))            // CALL WriteFile
    // Return empty string
    sb = sbAppend(sb, hexByte(0xB9)+hexDword(1))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(pr_al))
    sb = sbAppend(sb, hexByte(0xC6)+hexByte(0x00)+hexByte(0x00))                // MOV BYTE[RAX],0
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x38))
    sb = sbAppend(sb, hexByte(0x5E))
    sb = sbAppend(sb, hexByte(0x5B))
    sb = sbAppend(sb, hexByte(0xC3))
    pos = 1272

    // ── kr_printerr(RCX=s) → RAX=str("") ────────────────────────
    // 77 bytes (same as print but GetStdHandle(-12))
    let pe_sl  = 0  - (pos + 9 + 5)
    let pe_gsh_d = iatK32Rva + 1 * 8 - (textRva + pos + 22 + 6)
    let pe_wf_d  = iatK32Rva + 30 * 8 - (textRva + pos + 51 + 6)
    let pe_al  = 18 - (pos + 62 + 5)
    sb = sbAppend(sb, hexByte(0x53))
    sb = sbAppend(sb, hexByte(0x56))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x38))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xCE))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(pe_sl))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))
    sb = sbAppend(sb, hexByte(0xB9)+hexDword(0xFFFFFFF4))                        // MOV ECX,-12 (STD_ERROR)
    sb = sbAppend(sb, hexByte(0xFF)+hexByte(0x15)+hexDword(pe_gsh_d))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xF2))
    sb = sbAppend(sb, hexByte(0x41)+hexByte(0x89)+hexByte(0xD8))                // MOV R8D,EBX (len) REX.B
    sb = sbAppend(sb, hexByte(0x4C)+hexByte(0x8D)+hexByte(0x4C)+hexByte(0x24)+hexByte(0x18)) // LEA R9,[RSP+24]
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0xC7)+hexByte(0x44)+hexByte(0x24)+hexByte(0x20)+hexDword(0)) // MOV QWORD[RSP+32],0
    sb = sbAppend(sb, hexByte(0xFF)+hexByte(0x15)+hexDword(pe_wf_d))
    sb = sbAppend(sb, hexByte(0xB9)+hexDword(1))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(pe_al))
    sb = sbAppend(sb, hexByte(0xC6)+hexByte(0x00)+hexByte(0x00))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x38))
    sb = sbAppend(sb, hexByte(0x5E))
    sb = sbAppend(sb, hexByte(0x5B))
    sb = sbAppend(sb, hexByte(0xC3))
    pos = 1349

    // ── kr_printl → jmp kr_print ─────────────────────────────────
    // 5 bytes
    sb = sbAppend(sb, hexByte(0xE9)+hexDword(1195 - (pos + 5)))                  // JMP kr_print
    pos = 1354

    // ── kr_exit(RCX=code_str) ────────────────────────────────────
    // 22 bytes
    let ex_at = 197 - (pos + 4 + 5)
    let ex_ep_d = iatK32Rva + 0 - (textRva + pos + 11 + 6)  // ExitProcess IAT
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(ex_at))
    sb = sbAppend(sb, hexByte(0x89)+hexByte(0xC1))                              // MOV ECX,EAX
    sb = sbAppend(sb, hexByte(0xFF)+hexByte(0x15)+hexDword(ex_ep_d))            // CALL ExitProcess
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28))
    sb = sbAppend(sb, hexByte(0xC3))
    pos = 1376

    // ── kr_substring(RCX=s, RDX=start_str, R8=end_str) ──────────
    // 100 bytes. push RBX,RSI,RDI + sub rsp,48
    let ss_at1 = 197 - (pos + 13 + 5)   // atoi(start) at local 13
    let ss_at2 = 197 - (pos + 24 + 5)   // atoi(end) at local 24 (via r8→rcx)
    let ss_al  = 18  - (pos + 49 + 5)   // alloc at local 49
    sb = sbAppend(sb, hexByte(0x53))
    sb = sbAppend(sb, hexByte(0x56))
    sb = sbAppend(sb, hexByte(0x57))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x30))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xCE))                // MOV RSI,RCX (s)
    sb = sbAppend(sb, hexByte(0x4C)+hexByte(0x89)+hexByte(0xC1))                // MOV RCX,R8 (end_str, before atoi trashes R8)
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(ss_at1))                            // atoi(end)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC7))                // MOV RDI,RAX (end int)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xD1))                // MOV RCX,RDX (start_str, RDX untouched by atoi)
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(ss_at2))                            // atoi(start)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))                // MOV RBX,RAX (start int)
    sb = sbAppend(sb, hexByte(0x90)+hexByte(0x90)+hexByte(0x90))                // NOP NOP NOP (len = third arg directly = length)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x85)+hexByte(0xFF))                // TEST RDI,RDI
    sb = sbAppend(sb, hexByte(0x7E)+hexByte(0x2C))                              // JLE .empty (+44)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x03)+hexByte(0xF3))                // ADD RSI,RBX (src = s+start)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xF9))                // MOV RCX,RDI
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC1))                // INC RCX (+null)
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(ss_al))                             // CALL alloc
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))                // MOV RBX,RAX (buf)
    sb = sbAppend(sb, hexByte(0x33)+hexByte(0xC9))                              // XOR ECX,ECX
    // .copy: loop len bytes
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x3B)+hexByte(0xCF))                // CMP RCX,RDI
    sb = sbAppend(sb, hexByte(0x7D)+hexByte(0x0B))                              // JGE .copy_done (+11)
    sb = sbAppend(sb, hexByte(0x8A)+hexByte(0x04)+hexByte(0x0E))               // MOV AL,[RSI+RCX]
    sb = sbAppend(sb, hexByte(0x88)+hexByte(0x04)+hexByte(0x0B))               // MOV [RBX+RCX],AL
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC1))                // INC RCX
    sb = sbAppend(sb, hexByte(0xEB)+hexByte(0xF0))                              // JMP .copy (-16)
    // .copy_done:
    sb = sbAppend(sb, hexByte(0xC6)+hexByte(0x04)+hexByte(0x0B)+hexByte(0x00)) // MOV BYTE[RBX+RCX],0
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xD8))                // MOV RAX,RBX
    sb = sbAppend(sb, hexByte(0xEB)+hexByte(0x0D))                              // JMP .done (+13)
    // .empty:
    sb = sbAppend(sb, hexByte(0xB9)+hexDword(1))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(18 - (pos + 89 + 5)))              // CALL alloc(1) for ""
    sb = sbAppend(sb, hexByte(0xC6)+hexByte(0x00)+hexByte(0x00))
    // .done:
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x30))
    sb = sbAppend(sb, hexByte(0x5F))
    sb = sbAppend(sb, hexByte(0x5E))
    sb = sbAppend(sb, hexByte(0x5B))
    sb = sbAppend(sb, hexByte(0xC3))
    pos = 1481

    // ── kr_startswith(RCX=s, RDX=prefix) ─────────────────────────
    // 70 bytes. push RBX + sub rsp,48
    let sw_sl1 = 0  - (pos + 11 + 5)  // strlen(prefix) at local 11
    let sw_al  = 18 - (pos + 57 + 5)
    sb = sbAppend(sb, hexByte(0x53))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x30))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xCE))                // MOV RSI,RCX (s)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xD1))                // MOV RCX,RDX (prefix)
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(sw_sl1))                            // strlen(prefix)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))                // MOV RBX,RAX (prefix_len)
    // Compare first prefix_len bytes
    sb = sbAppend(sb, hexByte(0x33)+hexByte(0xC9))                              // XOR ECX,ECX (idx)
    // .loop (local 19):
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x3B)+hexByte(0xCB))                // CMP RCX,RBX
    sb = sbAppend(sb, hexByte(0x7D)+hexByte(0x15))                              // JGE .true (+21) all matched
    sb = sbAppend(sb, hexByte(0x8A)+hexByte(0x04)+hexByte(0x0E))               // MOV AL,[RSI+RCX]
    sb = sbAppend(sb, hexByte(0x84)+hexByte(0xC0))                              // TEST AL,AL
    sb = sbAppend(sb, hexByte(0x74)+hexByte(0x0A))                              // JZ .false (+10) s too short
    sb = sbAppend(sb, hexByte(0x3A)+hexByte(0x04)+hexByte(0x0A))               // CMP AL,[RDX+RCX]
    sb = sbAppend(sb, hexByte(0x75)+hexByte(0x05))                              // JNZ .false (+5)
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC1))                // INC RCX
    sb = sbAppend(sb, hexByte(0xEB)+hexByte(0xEA))                              // JMP .loop (-22)
    // .false (local 39):
    sb = sbAppend(sb, hexByte(0x33)+hexByte(0xDB))                              // XOR EBX,EBX
    sb = sbAppend(sb, hexByte(0xEB)+hexByte(0x05))                              // JMP .make_str
    // .true (local 46):... wait, this is getting off. Let me match the JGE+26 target
    // .true (local 43 actually since 19+2+2+3+2+2+3+2+3+2=40+3=43... let me recount)
    // Actually just put the true block and trust the relative jumps
    sb = sbAppend(sb, hexByte(0xBB)+hexDword(1))                                 // MOV EBX,1
    // .make_str:
    sb = sbAppend(sb, hexByte(0xB9)+hexDword(2))
    sb = sbAppend(sb, hexByte(0xE8)+hexDword(sw_al))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x8D)+hexByte(0x4B)+hexByte(0x30))
    sb = sbAppend(sb, hexByte(0x88)+hexByte(0x08))
    sb = sbAppend(sb, hexByte(0xC6)+hexByte(0x40)+hexByte(0x01)+hexByte(0x00))
    sb = sbAppend(sb, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x30))
    sb = sbAppend(sb, hexByte(0x5B))
    sb = sbAppend(sb, hexByte(0xC3))
    // sb has 1559 good bytes (0..1558) + 60 garbage bytes from broken kr_contains attempt.
    // Strip garbage: each byte = 3 chars (xHH), so 1559*3=4677 good chars.
    let sb_good = substring(sbToString(sb), 0, 4677)
    pos = 1559
    let sb2 = sbNew()

    // ── kr_contains(RCX=s, RDX=needle) → "0"/"1" ─────────────────
    // 141 bytes. push RBX,RSI,RDI,R12; sub rsp,0x28 (40)
    // Frame: (4+1)*8 + 40 = 80, 80%16=0 ✓
    // Stack: [rsp+32]=lenS, [rsp+40] unused
    offsets = offsets + "kr_contains:" + pos + "\n"
    let co_sl1 = 0 - (pos + 18 + 5)
    let co_sl2 = 0 - (pos + 31 + 5)
    let co_al1 = 18 - (pos + 100 + 5)
    let co_al2 = 18 - (pos + 119 + 5)
    sb2 = sbAppend(sb2, hexByte(0x53)+hexByte(0x56)+hexByte(0x57)+hexByte(0x41)+hexByte(0x54))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xCE))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xD7))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xF1))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(co_sl1))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0x44)+hexByte(0x24)+hexByte(0x20))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xF9))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(co_sl2))
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x89)+hexByte(0xC4)+hexByte(0x33)+hexByte(0xDB))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x8B)+hexByte(0x44)+hexByte(0x24)+hexByte(0x20))
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x3B)+hexByte(0xE0)+hexByte(0x7F)+hexByte(0x3F))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x8B)+hexByte(0x44)+hexByte(0x24)+hexByte(0x20))
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x29)+hexByte(0xE0))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x3B)+hexByte(0xD8)+hexByte(0x7F)+hexByte(0x32))
    sb2 = sbAppend(sb2, hexByte(0x33)+hexByte(0xC9))
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x3B)+hexByte(0xCC)+hexByte(0x7D)+hexByte(0x18))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x8D)+hexByte(0x04)+hexByte(0x1E))
    sb2 = sbAppend(sb2, hexByte(0x0F)+hexByte(0xB6)+hexByte(0x14)+hexByte(0x08))
    sb2 = sbAppend(sb2, hexByte(0x0F)+hexByte(0xB6)+hexByte(0x04)+hexByte(0x0F))
    sb2 = sbAppend(sb2, hexByte(0x3B)+hexByte(0xD0)+hexByte(0x75)+hexByte(0x04))
    sb2 = sbAppend(sb2, hexByte(0xFF)+hexByte(0xC1)+hexByte(0xEB)+hexByte(0xE7))
    sb2 = sbAppend(sb2, hexByte(0xFF)+hexByte(0xC3)+hexByte(0xEB)+hexByte(0xD4))
    sb2 = sbAppend(sb2, hexByte(0xB9)+hexDword(2)+hexByte(0xE8)+hexDword(co_al1))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x00)+hexByte(0x31)+hexByte(0xC6)+hexByte(0x40)+hexByte(0x01)+hexByte(0x00))
    sb2 = sbAppend(sb2, hexByte(0xEB)+hexByte(0x11))
    sb2 = sbAppend(sb2, hexByte(0xB9)+hexDword(2)+hexByte(0xE8)+hexDword(co_al2))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x00)+hexByte(0x30)+hexByte(0xC6)+hexByte(0x40)+hexByte(0x01)+hexByte(0x00))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x5C)+hexByte(0x5F)+hexByte(0x5E)+hexByte(0x5B)+hexByte(0xC3))
    pos = pos + 141

    // ── kr_indexof(RCX=s, RDX=needle) → index string ──────────────
    // 127 bytes. Same loop as kr_contains but returns itoa(i) or itoa(-1)
    offsets = offsets + "kr_indexof:" + pos + "\n"
    let io_sl1 = 0 - (pos + 18 + 5)
    let io_sl2 = 0 - (pos + 31 + 5)
    let io_it1 = 266 - (pos + 98 + 5)
    let io_it2 = 266 - (pos + 112 + 5)
    sb2 = sbAppend(sb2, hexByte(0x53)+hexByte(0x56)+hexByte(0x57)+hexByte(0x41)+hexByte(0x54))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xCE))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xD7))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xF1))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(io_sl1))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0x44)+hexByte(0x24)+hexByte(0x20))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xF9))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(io_sl2))
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x89)+hexByte(0xC4)+hexByte(0x33)+hexByte(0xDB))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x8B)+hexByte(0x44)+hexByte(0x24)+hexByte(0x20))
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x3B)+hexByte(0xE0)+hexByte(0x7F)+hexByte(0x36))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x8B)+hexByte(0x44)+hexByte(0x24)+hexByte(0x20))
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x29)+hexByte(0xE0))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x3B)+hexByte(0xD8)+hexByte(0x7F)+hexByte(0x29))
    sb2 = sbAppend(sb2, hexByte(0x33)+hexByte(0xC9))
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x3B)+hexByte(0xCC)+hexByte(0x7D)+hexByte(0x18))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x8D)+hexByte(0x04)+hexByte(0x1E))
    sb2 = sbAppend(sb2, hexByte(0x0F)+hexByte(0xB6)+hexByte(0x14)+hexByte(0x08))
    sb2 = sbAppend(sb2, hexByte(0x0F)+hexByte(0xB6)+hexByte(0x04)+hexByte(0x0F))
    sb2 = sbAppend(sb2, hexByte(0x3B)+hexByte(0xD0)+hexByte(0x75)+hexByte(0x04))
    sb2 = sbAppend(sb2, hexByte(0xFF)+hexByte(0xC1)+hexByte(0xEB)+hexByte(0xE7))
    sb2 = sbAppend(sb2, hexByte(0xFF)+hexByte(0xC3)+hexByte(0xEB)+hexByte(0xD4))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xD9))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(io_it1))
    sb2 = sbAppend(sb2, hexByte(0xEB)+hexByte(0x0C))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xC7)+hexByte(0xC1)+hexByte(0xFF)+hexByte(0xFF)+hexByte(0xFF)+hexByte(0xFF))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(io_it2))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x5C)+hexByte(0x5F)+hexByte(0x5E)+hexByte(0x5B)+hexByte(0xC3))
    pos = pos + 127

    // ── kr_trim(RCX=s) → allocated trimmed copy ───────────────────
    // 177 bytes. push RBX,RSI,RDI; sub rsp,0x30 (48)
    // Frame: (3+1)*8 + 48 = 80, 80%16=0 ✓
    // Stack: [rsp+32]=start_idx, [rsp+40] unused
    offsets = offsets + "kr_trim:" + pos + "\n"
    let tr_sl = 0 - (pos + 10 + 5)
    let tr_al1 = 18 - (pos + 91 + 5)
    let tr_sd = 52 - (pos + 143 + 5)
    let tr_al2 = 18 - (pos + 161 + 5)
    sb2 = sbAppend(sb2, hexByte(0x53)+hexByte(0x56)+hexByte(0x57))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x30))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xCE))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(tr_sl))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x85)+hexByte(0xC3)+hexByte(0x74)+hexByte(0x75))
    sb2 = sbAppend(sb2, hexByte(0x33)+hexByte(0xC9))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x3B)+hexByte(0xCB)+hexByte(0x7D)+hexByte(0x7E))
    sb2 = sbAppend(sb2, hexByte(0x0F)+hexByte(0xB6)+hexByte(0x04)+hexByte(0x0E))
    sb2 = sbAppend(sb2, hexByte(0x3C)+hexByte(0x21)+hexByte(0x73)+hexByte(0x05))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC1)+hexByte(0xEB)+hexByte(0xEE))  // INC RCX; JMP -18 → outer_loop@25
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0x4C)+hexByte(0x24)+hexByte(0x20))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x8D)+hexByte(0x43)+hexByte(0xFF))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC7))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x3B)+hexByte(0xF9)+hexByte(0x7C)+hexByte(0x60))
    sb2 = sbAppend(sb2, hexByte(0x0F)+hexByte(0xB6)+hexByte(0x04)+hexByte(0x3E))
    sb2 = sbAppend(sb2, hexByte(0x3C)+hexByte(0x21)+hexByte(0x73)+hexByte(0x05))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xFF)+hexByte(0xCF)+hexByte(0xEB)+hexByte(0xEE))  // DEC RDI; JMP -18 → inner_loop@55
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x8B)+hexByte(0x4C)+hexByte(0x24)+hexByte(0x20))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xFB))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x2B)+hexByte(0xD9))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC3))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x8D)+hexByte(0x4B)+hexByte(0x01))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(tr_al1))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC7))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x8B)+hexByte(0x4C)+hexByte(0x24)+hexByte(0x20))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x03)+hexByte(0xF1))
    sb2 = sbAppend(sb2, hexByte(0x33)+hexByte(0xC9))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x3B)+hexByte(0xCB)+hexByte(0x7D)+hexByte(0x0B))
    sb2 = sbAppend(sb2, hexByte(0x8A)+hexByte(0x04)+hexByte(0x0E))
    sb2 = sbAppend(sb2, hexByte(0x88)+hexByte(0x04)+hexByte(0x0F))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC1)+hexByte(0xEB)+hexByte(0xF0))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x04)+hexByte(0x1F)+hexByte(0x00))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xF8))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x30))
    sb2 = sbAppend(sb2, hexByte(0x5F)+hexByte(0x5E)+hexByte(0x5B)+hexByte(0xC3))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xF1))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(tr_sd))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x30))
    sb2 = sbAppend(sb2, hexByte(0x5F)+hexByte(0x5E)+hexByte(0x5B)+hexByte(0xC3))
    sb2 = sbAppend(sb2, hexByte(0xB9)+hexDword(1))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(tr_al2))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x00)+hexByte(0x00))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x30))
    sb2 = sbAppend(sb2, hexByte(0x5F)+hexByte(0x5E)+hexByte(0x5B)+hexByte(0xC3))
    pos = pos + 177

    // ── kr_replace(RCX=s, RDX=from, R8=to) → new string ─────────────────────
    // 211 bytes. Replaces all occurrences of 'from' in 's' with 'to'.
    // Registers: RSI=s, R12=from, R14=to, R13=len_s, RDI=len_from, R15=len_to, RBX=write ptr
    offsets = offsets + "kr_replace:" + pos + "\n"
    let rp_sl1 = 0  - (pos + 27 + 5)   // CALL strlen(s)   at local 27
    let rp_sl2 = 0  - (pos + 38 + 5)   // CALL strlen(from) at local 38
    let rp_sl3 = 0  - (pos + 49 + 5)   // CALL strlen(to)   at local 49
    let rp_sd  = 52 - (pos + 65 + 5)   // JMP strdup (if len_from==0) at local 65
    let rp_al  = 18 - (pos + 89 + 5)   // CALL alloc at local 89
    // Prologue: push RBX,RSI,RDI,R12,R13,R14,R15 + sub rsp,48
    sb2 = sbAppend(sb2, hexByte(0x53)+hexByte(0x56)+hexByte(0x57))                          // PUSH RBX,RSI,RDI
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x54)+hexByte(0x41)+hexByte(0x55))            // PUSH R12,R13
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x56)+hexByte(0x41)+hexByte(0x57))            // PUSH R14,R15
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x30))            // SUB RSP,48
    // Save args
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xCE))                          // MOV RSI,RCX (s)
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x8B)+hexByte(0xE2))                          // MOV R12,RDX (from)
    sb2 = sbAppend(sb2, hexByte(0x4D)+hexByte(0x8B)+hexByte(0xF0))                          // MOV R14,R8 (to)
    // strlen(s) → R13
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xF1))                          // MOV RCX,RSI
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(rp_sl1))                                      // CALL strlen
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x89)+hexByte(0xC5))                          // MOV R13,RAX (len_s)
    // strlen(from) → RDI
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x89)+hexByte(0xE1))                          // MOV RCX,R12
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(rp_sl2))                                      // CALL strlen
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC7))                          // MOV RDI,RAX (len_from)
    // strlen(to) → R15
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x89)+hexByte(0xF1))                          // MOV RCX,R14
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(rp_sl3))                                      // CALL strlen
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x89)+hexByte(0xC7))                          // MOV R15,RAX (len_to)
    // if len_from == 0: return strdup(s)
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x85)+hexByte(0xFF))                          // TEST RDI,RDI
    sb2 = sbAppend(sb2, hexByte(0x75)+hexByte(0x08))                                         // JNZ .do_replace (+8)
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xF1))                          // MOV RCX,RSI
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(rp_sd))                                       // JMP strdup
    // .do_replace [70]: alloc buffer: size = len_s*(len_to+1)+1
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x89)+hexByte(0xE8))                          // MOV RAX,R13 (len_s)
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x8B)+hexByte(0xCF))                          // MOV RCX,R15 (len_to)
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC1))                          // INC RCX
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x0F)+hexByte(0xAF)+hexByte(0xC1))           // IMUL RAX,RCX
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC0))                          // INC RAX
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))                          // MOV RCX,RAX
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(rp_al))                                       // CALL alloc
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0x44)+hexByte(0x24)+hexByte(0x20)) // MOV [RSP+32],RAX (save output start)
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))                          // MOV RBX,RAX (write ptr)
    sb2 = sbAppend(sb2, hexByte(0x33)+hexByte(0xC9))                                         // XOR ECX,ECX (i=0)
    // .outer_loop [104]:
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x3B)+hexByte(0xCD))                          // CMP RCX,R13
    sb2 = sbAppend(sb2, hexByte(0x7D)+hexByte(0x4E))                                         // JGE .done (+78)
    // inner compare: LEA R8,[RSI+RCX]; set up R9=from, R10=from+len_from
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x8D)+hexByte(0x04)+hexByte(0x0E))           // LEA R8,[RSI+RCX]
    sb2 = sbAppend(sb2, hexByte(0x4D)+hexByte(0x8B)+hexByte(0xCC))                          // MOV R9,R12 (from ptr)
    sb2 = sbAppend(sb2, hexByte(0x4D)+hexByte(0x89)+hexByte(0xCA))                          // MOV R10,R9
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x03)+hexByte(0xD7))                          // ADD R10,RDI (R10=from+len_from)
    // .inner_loop [122]:
    sb2 = sbAppend(sb2, hexByte(0x4D)+hexByte(0x3B)+hexByte(0xCA))                          // CMP R9,R10
    sb2 = sbAppend(sb2, hexByte(0x7D)+hexByte(0x12))                                         // JGE .matched (+18)
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x8A)+hexByte(0x00))                          // MOV AL,[R8]
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x8A)+hexByte(0x11))                          // MOV DL,[R9]
    sb2 = sbAppend(sb2, hexByte(0x38)+hexByte(0xD0))                                         // CMP AL,DL
    sb2 = sbAppend(sb2, hexByte(0x75)+hexByte(0x25))                                         // JNZ .no_match (+37)
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0xFF)+hexByte(0xC0))                          // INC R8
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0xFF)+hexByte(0xC1))                          // INC R9
    sb2 = sbAppend(sb2, hexByte(0xEB)+hexByte(0xE9))                                         // JMP .inner_loop (-23)
    // .matched [145]:
    sb2 = sbAppend(sb2, hexByte(0x4D)+hexByte(0x89)+hexByte(0xF2))                          // MOV R10,R14 (to ptr)
    sb2 = sbAppend(sb2, hexByte(0x33)+hexByte(0xD2))                                         // XOR EDX,EDX (j=0)
    // .copy_to [150]:
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x3B)+hexByte(0xD7))                          // CMP RDX,R15
    sb2 = sbAppend(sb2, hexByte(0x7D)+hexByte(0x0E))                                         // JGE .copy_to_done (+14)
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x8A)+hexByte(0x04)+hexByte(0x12))           // MOV AL,[R10+RDX]
    sb2 = sbAppend(sb2, hexByte(0x88)+hexByte(0x03))                                         // MOV [RBX],AL
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC3))                          // INC RBX
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC2))                          // INC RDX
    sb2 = sbAppend(sb2, hexByte(0xEB)+hexByte(0xED))                                         // JMP .copy_to (-19)
    // .copy_to_done [169]:
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x03)+hexByte(0xCF))                          // ADD RCX,RDI (i+=len_from)
    sb2 = sbAppend(sb2, hexByte(0xEB)+hexByte(0xBA))                                         // JMP .outer_loop (-70)
    // .no_match [174]:
    sb2 = sbAppend(sb2, hexByte(0x8A)+hexByte(0x04)+hexByte(0x0E))                          // MOV AL,[RSI+RCX]
    sb2 = sbAppend(sb2, hexByte(0x88)+hexByte(0x03))                                         // MOV [RBX],AL
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC1))                          // INC RCX
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC3))                          // INC RBX
    sb2 = sbAppend(sb2, hexByte(0xEB)+hexByte(0xAD))                                         // JMP .outer_loop (-83)
    // .done [187]:
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x03)+hexByte(0x00))                          // MOV BYTE[RBX],0
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x8B)+hexByte(0x44)+hexByte(0x24)+hexByte(0x20)) // MOV RAX,[RSP+32]
    // Epilogue
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x30))            // ADD RSP,48
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x5F))                                         // POP R15
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x5E))                                         // POP R14
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x5D))                                         // POP R13
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x5C))                                         // POP R12
    sb2 = sbAppend(sb2, hexByte(0x5F))                                                        // POP RDI
    sb2 = sbAppend(sb2, hexByte(0x5E))                                                        // POP RSI
    sb2 = sbAppend(sb2, hexByte(0x5B))                                                        // POP RBX
    sb2 = sbAppend(sb2, hexByte(0xC3))                                                        // RET
    pos = pos + 211

    // ── kr_split(RCX=s, RDX=idx_str) → Nth '\n'-delimited field ────
    // Standalone 149-byte implementation. No nthfield helper.
    // RSI=s, R12=idx, RBX=cur_field, RDI=i, R13=field_start, R14=end, R15=buf
    offsets = offsets + "kr_split:" + pos + "\n"
    let sp_ai = 197 - (pos + 21 + 5)
    let sp_al = 18 - (pos + 77 + 5)
    let sp_al2 = 18 - (pos + 111 + 5)
    // [0-10]: PUSH RBX,RSI,RDI,R12,R13,R14,R15
    sb2 = sbAppend(sb2, hexByte(0x53)+hexByte(0x56)+hexByte(0x57))
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x54)+hexByte(0x41)+hexByte(0x55))
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x56)+hexByte(0x41)+hexByte(0x57))
    // [11-14]: SUB RSP,0x20
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x20))
    // [15]: MOV RSI,RCX  [18]: MOV RCX,RDX  [21]: CALL atoi  [26]: MOV R12,RAX
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xCE))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xD1))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(sp_ai))
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x89)+hexByte(0xC4))
    // [29]: XOR EBX,EBX  [31]: XOR EDI,EDI
    sb2 = sbAppend(sb2, hexByte(0x33)+hexByte(0xDB))
    sb2 = sbAppend(sb2, hexByte(0x33)+hexByte(0xFF))
    // .loop [33]: MOVZX EAX,BYTE [RSI+RDI]
    sb2 = sbAppend(sb2, hexByte(0x0F)+hexByte(0xB6)+hexByte(0x04)+hexByte(0x3E))
    // [37]: TEST AL,AL  [39]: JZ .not_found (+63)
    sb2 = sbAppend(sb2, hexByte(0x84)+hexByte(0xC0))
    sb2 = sbAppend(sb2, hexByte(0x74)+hexByte(0x3F))
    // [41]: CMP RBX,R12  [44]: JNZ .advance (+89)
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x3B)+hexByte(0xDC))
    sb2 = sbAppend(sb2, hexByte(0x75)+hexByte(0x59))
    // .found [46]: MOV R13,RDI  [49]: MOV R14,RDI
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x8B)+hexByte(0xEF))
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x8B)+hexByte(0xF7))
    // .scan_end [52]: MOVZX EAX,BYTE [RSI+R14]
    sb2 = sbAppend(sb2, hexByte(0x42)+hexByte(0x0F)+hexByte(0xB6)+hexByte(0x04)+hexByte(0x36))
    // [57]: TEST AL,AL  [59]: JZ .got_end (+9)
    sb2 = sbAppend(sb2, hexByte(0x84)+hexByte(0xC0))
    sb2 = sbAppend(sb2, hexByte(0x74)+hexByte(0x09))
    // [61]: CMP AL,0x0A  [63]: JE .got_end (+5)
    sb2 = sbAppend(sb2, hexByte(0x3C)+hexByte(0x0A))
    sb2 = sbAppend(sb2, hexByte(0x74)+hexByte(0x05))
    // [65]: INC R14  [68]: JMP .scan_end (-18)
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0xFF)+hexByte(0xC6))
    sb2 = sbAppend(sb2, hexByte(0xEB)+hexByte(0xEE))
    // .got_end [70]: SUB R14,R13  [73]: LEA RCX,[R14+1]  [77]: CALL alloc
    sb2 = sbAppend(sb2, hexByte(0x4D)+hexByte(0x2B)+hexByte(0xF5))
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x8D)+hexByte(0x4E)+hexByte(0x01))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(sp_al))
    // [82]: MOV R15,RAX  [85]: MOV RDI,R15  [88]: ADD RSI,R13
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x89)+hexByte(0xC7))
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x8B)+hexByte(0xFF))
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x01)+hexByte(0xEE))
    // [91]: MOV RCX,R14  [94]: REP MOVSB  [96]: MOV BYTE[RDI],0  [99]: MOV RAX,R15
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x89)+hexByte(0xF1))
    sb2 = sbAppend(sb2, hexByte(0xF3)+hexByte(0xA4))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x07)+hexByte(0x00))
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x8B)+hexByte(0xC7))
    // [102]: JMP .epilogue (+15)
    sb2 = sbAppend(sb2, hexByte(0xEB)+hexByte(0x0F))
    // .not_found [104]: MOV RCX,1  [111]: CALL alloc  [116]: MOV BYTE[RAX],0
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xC7)+hexByte(0xC1)+hexByte(0x01)+hexByte(0x00)+hexByte(0x00)+hexByte(0x00))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(sp_al2))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x00)+hexByte(0x00))
    // .epilogue [119]: ADD RSP,0x20  POP R15,R14,R13,R12,RDI,RSI,RBX  RET
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x20))
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x5F))
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x5E))
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x5D))
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x5C))
    sb2 = sbAppend(sb2, hexByte(0x5F))
    sb2 = sbAppend(sb2, hexByte(0x5E))
    sb2 = sbAppend(sb2, hexByte(0x5B))
    sb2 = sbAppend(sb2, hexByte(0xC3))
    // .advance [135]: CMP AL,0x0A  [137]: JNZ .next (+2)  [139]: INC EBX
    sb2 = sbAppend(sb2, hexByte(0x3C)+hexByte(0x0A))
    sb2 = sbAppend(sb2, hexByte(0x75)+hexByte(0x02))
    sb2 = sbAppend(sb2, hexByte(0xFF)+hexByte(0xC3))
    // .next [141]: INC RDI  [144]: JMP .loop (-116)
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC7))
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(-116))
    pos = pos + 149

    // kr_getline: JMP kr_split (same thing: split on \n)
    offsets = offsets + "kr_getline:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword((pos - 149) - (pos + 5)))
    pos = pos + 5

    // ── kr_linecount(RCX=s) → count of \n-delimited lines ─────────
    // 42 bytes.
    offsets = offsets + "kr_linecount:" + pos + "\n"
    let lc_al = 18 - (pos + 28 + 5)
    let lc_it = 266 - (pos + 37 + 5)
    sb2 = sbAppend(sb2, hexByte(0x53)+hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xCB))
    sb2 = sbAppend(sb2, hexByte(0x33)+hexByte(0xD2))
    sb2 = sbAppend(sb2, hexByte(0x80)+hexByte(0x3B)+hexByte(0x00)+hexByte(0x74)+hexByte(0x0C))  // CMP [RBX],0; JZ +12 → .done@27
    sb2 = sbAppend(sb2, hexByte(0x80)+hexByte(0x3B)+hexByte(0x0A)+hexByte(0x75)+hexByte(0x02))
    sb2 = sbAppend(sb2, hexByte(0xFF)+hexByte(0xC2))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC3)+hexByte(0xEB)+hexByte(0xEF))  // INC RBX; JMP -17 → .loop@10
    sb2 = sbAppend(sb2, hexByte(0xFF)+hexByte(0xC2))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x63)+hexByte(0xCA))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0x5B))
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(lc_it))
    pos = pos + 42

    // kr_count and kr_length: JMP kr_linecount
    offsets = offsets + "kr_count:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword((pos - 42) - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_length:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword((pos - 47) - (pos + 5)))
    pos = pos + 5

    // ── kr_range(RCX=start_str, RDX=end_str) → "\n"-joined list ──
    // 133 bytes. Regs: R12=counter, R13=end, RBX=result_str
    // [RSP+0x20]="\n\0" (local); loop: strcat(result,itoa(i)), if i<end-1 strcat("\n")
    offsets = offsets + "kr_range:" + pos + "\n"
    let rg_ai1 = 197 - (pos + 30 + 5)
    let rg_ai2 = 197 - (pos + 41 + 5)
    let rg_al  = 18  - (pos + 54 + 5)
    let rg_it  = 266 - (pos + 73 + 5)
    let rg_sc1 = 105 - (pos + 84 + 5)
    let rg_sc2 = 105 - (pos + 108 + 5)
    // [0-10]: prologue PUSH RBX,RSI,RDI,R12,R13 + SUB RSP,0x30
    sb2 = sbAppend(sb2, hexByte(0x53)+hexByte(0x56)+hexByte(0x57))
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x54)+hexByte(0x41)+hexByte(0x55))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x30))
    // [11-20]: store "\n\0" at [RSP+0x20] (local slot, survives CALLs)
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x44)+hexByte(0x24)+hexByte(0x20)+hexByte(0x0A))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x44)+hexByte(0x24)+hexByte(0x21)+hexByte(0x00))
    // [21-26]: save args
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xCE))  // MOV RSI,RCX
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xD7))  // MOV RDI,RDX
    // [27-37]: atoi(start) → R12
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xF1))  // MOV RCX,RSI
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(rg_ai1))              // CALL atoi
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x89)+hexByte(0xC4))  // MOV R12,RAX
    // [38-48]: atoi(end) → R13
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xF9))  // MOV RCX,RDI
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(rg_ai2))              // CALL atoi
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x89)+hexByte(0xC5))  // MOV R13,RAX
    // [49-64]: alloc(1) → empty string → RBX
    sb2 = sbAppend(sb2, hexByte(0xB9)+hexDword(1))                   // MOV ECX,1
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(rg_al))               // CALL alloc
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x00)+hexByte(0x00))  // MOV BYTE[RAX],0
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))  // MOV RBX,RAX
    // .loop [65]: CMP R12,R13; JGE .done (+48 → [118])
    sb2 = sbAppend(sb2, hexByte(0x4D)+hexByte(0x3B)+hexByte(0xE5))  // CMP R12,R13
    sb2 = sbAppend(sb2, hexByte(0x7D)+hexByte(0x30))                 // JGE .done
    // [70-88]: itoa(R12) → strcat(RBX, number) → RBX
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x89)+hexByte(0xE1))  // MOV RCX,R12
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(rg_it))               // CALL itoa
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC2))  // MOV RDX,RAX
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xD9))  // MOV RCX,RBX
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(rg_sc1))              // CALL strcat
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))  // MOV RBX,RAX
    // [92-99]: INC R12; CMP R12,R13; JGE .skip_nl (+16 → [116])
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0xFF)+hexByte(0xC4))  // INC R12
    sb2 = sbAppend(sb2, hexByte(0x4D)+hexByte(0x3B)+hexByte(0xE5))  // CMP R12,R13
    sb2 = sbAppend(sb2, hexByte(0x7D)+hexByte(0x10))                 // JGE .skip_nl
    // [100-115]: strcat(RBX, "\n") → RBX
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xD9))  // MOV RCX,RBX
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x8D)+hexByte(0x54)+hexByte(0x24)+hexByte(0x20))  // LEA RDX,[RSP+0x20]
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(rg_sc2))              // CALL strcat
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))  // MOV RBX,RAX
    // .skip_nl [116]: JMP .loop (-53 → [65])
    sb2 = sbAppend(sb2, hexByte(0xEB)+hexByte(0xCB))
    // .done [118]: MOV RAX,RBX + epilogue
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xD8))  // MOV RAX,RBX
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x30))
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x5D)+hexByte(0x41)+hexByte(0x5C))
    sb2 = sbAppend(sb2, hexByte(0x5F)+hexByte(0x5E)+hexByte(0x5B)+hexByte(0xC3))
    pos = pos + 133

    // ── kr_sbnew() → empty string ─────────────────────────────────
    // 20 bytes.
    offsets = offsets + "kr_sbnew:" + pos + "\n"
    let sbn_al = 18 - (pos + 9 + 5)
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0xB9)+hexDword(1)+hexByte(0xE8)+hexDword(sbn_al))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x00)+hexByte(0x00))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28)+hexByte(0xC3))
    pos = pos + 22

    // kr_sbappend(RCX=sb,RDX=s) → __rt_strcat
    offsets = offsets + "kr_sbappend:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(105 - (pos + 5)))
    pos = pos + 5

    // kr_sbtostring(RCX=sb) → __rt_strdup
    offsets = offsets + "kr_sbtostring:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(52 - (pos + 5)))
    pos = pos + 5

    // ── kr_readfile(RCX=path) → file content string ───────────────
    // 171 bytes. Uses CreateFileA,GetFileSizeEx,HeapAlloc,ReadFile,CloseHandle
    // Frame: push RBX,RSI,RDI,R12,R13 (5); sub rsp,0x48 (72)
    // (5+1)*8+72 = 120, 120%16=8 BAD. Use sub rsp,0x58(88): (5+1)*8+88=136, 136%16=8 BAD
    // Use push R14 too (6 pushes); sub rsp,0x48: (6+1)*8+72=128, 128%16=0 ✓
    offsets = offsets + "kr_readfile:" + pos + "\n"
    let rf_cf = iatK32Rva + 32*8 - (textRva + pos + 28 + 6)
    let rf_fs = iatK32Rva + 34*8 - (textRva + pos + 48 + 6)
    let rf_al = 18 - (pos + 92 + 5)
    let rf_rd = iatK32Rva + 31*8 - (textRva + pos + 118 + 6)
    let rf_ch = iatK32Rva + 10*8 - (textRva + pos + 134 + 6)
    let rf_ep = pos + 138
    let rf_ea = 18 - (pos + 154 + 5)
    sb2 = sbAppend(sb2, hexByte(0x53)+hexByte(0x56)+hexByte(0x57))
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x54)+hexByte(0x41)+hexByte(0x55)+hexByte(0x41)+hexByte(0x56))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x48))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xCE))
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0xB8)+hexDword(0x80000000))
    sb2 = sbAppend(sb2, hexByte(0x33)+hexByte(0xD2)+hexByte(0x33)+hexByte(0xC9))
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0xB9)+hexDword(1))
    sb2 = sbAppend(sb2, hexByte(0x4D)+hexByte(0x33)+hexByte(0xC0))
    sb2 = sbAppend(sb2, hexByte(0xFF)+hexByte(0x15)+hexDword(rf_cf))
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x89)+hexByte(0xC4))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xF8)+hexByte(0xFF)+hexByte(0x74)+hexByte(0x52))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x8D)+hexByte(0x54)+hexByte(0x24)+hexByte(0x20))
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x89)+hexByte(0xE1))
    sb2 = sbAppend(sb2, hexByte(0xFF)+hexByte(0x15)+hexDword(rf_fs))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x8B)+hexByte(0x44)+hexByte(0x24)+hexByte(0x20))
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x89)+hexByte(0xC5))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC0))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(rf_al))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC7))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x00)+hexByte(0x00))
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x89)+hexByte(0xE1))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xFA))
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x89)+hexByte(0xE0))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x8D)+hexByte(0x74)+hexByte(0x24)+hexByte(0x30))
    sb2 = sbAppend(sb2, hexByte(0x4D)+hexByte(0x33)+hexByte(0xC9))
    sb2 = sbAppend(sb2, hexByte(0xFF)+hexByte(0x15)+hexDword(rf_rd))
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x89)+hexByte(0xE1))
    sb2 = sbAppend(sb2, hexByte(0xFF)+hexByte(0x15)+hexDword(rf_ch))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xF8))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x48))
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x5E)+hexByte(0x41)+hexByte(0x5D)+hexByte(0x41)+hexByte(0x5C))
    sb2 = sbAppend(sb2, hexByte(0x5F)+hexByte(0x5E)+hexByte(0x5B)+hexByte(0xC3))
    sb2 = sbAppend(sb2, hexByte(0xB9)+hexDword(1)+hexByte(0xE8)+hexDword(rf_ea))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x00)+hexByte(0x00))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x48))
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x5E)+hexByte(0x41)+hexByte(0x5D)+hexByte(0x41)+hexByte(0x5C))
    sb2 = sbAppend(sb2, hexByte(0x5F)+hexByte(0x5E)+hexByte(0x5B)+hexByte(0xC3))
    pos = pos + 171

    // ── kr_writefile(RCX=path, RDX=data) → "" ────────────────────
    // 130 bytes. Uses CreateFileA,strlen,WriteFile,CloseHandle.
    // push RBX,RSI,RDI,R12,R13,R14 (6); sub rsp,0x48 → (6+1)*8+72=128, 128%16=0 ✓
    offsets = offsets + "kr_writefile:" + pos + "\n"
    let wf_cf = iatK32Rva + 32*8 - (textRva + pos + 30 + 6)
    let wf_sl = 0 - (pos + 60 + 5)
    let wf_wf = iatK32Rva + 30*8 - (textRva + pos + 95 + 6)
    let wf_ch = iatK32Rva + 10*8 - (textRva + pos + 111 + 6)
    let wf_ep2 = pos + 117
    let wf_ea2 = 18 - (pos + 127 + 5)
    sb2 = sbAppend(sb2, hexByte(0x53)+hexByte(0x56)+hexByte(0x57))
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x54)+hexByte(0x41)+hexByte(0x55)+hexByte(0x41)+hexByte(0x56))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x48))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xCE))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xD7))
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0xB8)+hexDword(0x40000000))
    sb2 = sbAppend(sb2, hexByte(0x33)+hexByte(0xD2)+hexByte(0x33)+hexByte(0xC9))
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0xB9)+hexDword(2))
    sb2 = sbAppend(sb2, hexByte(0x4D)+hexByte(0x33)+hexByte(0xC0))
    sb2 = sbAppend(sb2, hexByte(0xFF)+hexByte(0x15)+hexDword(wf_cf))
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x89)+hexByte(0xC4))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xF8)+hexByte(0xFF)+hexByte(0x74)+hexByte(0x3E))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xF9))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(wf_sl))
    sb2 = sbAppend(sb2, hexByte(0x49)+hexByte(0x89)+hexByte(0xC5))
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x89)+hexByte(0xE1))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xFA))
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x89)+hexByte(0xEA))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x8D)+hexByte(0x74)+hexByte(0x24)+hexByte(0x30))
    sb2 = sbAppend(sb2, hexByte(0x4D)+hexByte(0x33)+hexByte(0xC9))
    sb2 = sbAppend(sb2, hexByte(0xFF)+hexByte(0x15)+hexDword(wf_wf))
    sb2 = sbAppend(sb2, hexByte(0x4C)+hexByte(0x89)+hexByte(0xE1))
    sb2 = sbAppend(sb2, hexByte(0xFF)+hexByte(0x15)+hexDword(wf_ch))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x48))
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x5E)+hexByte(0x41)+hexByte(0x5D)+hexByte(0x41)+hexByte(0x5C))
    sb2 = sbAppend(sb2, hexByte(0x5F)+hexByte(0x5E)+hexByte(0x5B))
    sb2 = sbAppend(sb2, hexByte(0xB9)+hexDword(1)+hexByte(0xE8)+hexDword(wf_ea2))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x00)+hexByte(0x00)+hexByte(0xC3))
    sb2 = sbAppend(sb2, hexByte(0xB9)+hexDword(1)+hexByte(0xE8)+hexDword(wf_ea2))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x00)+hexByte(0x00))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x48))
    sb2 = sbAppend(sb2, hexByte(0x41)+hexByte(0x5E)+hexByte(0x41)+hexByte(0x5D)+hexByte(0x41)+hexByte(0x5C))
    sb2 = sbAppend(sb2, hexByte(0x5F)+hexByte(0x5E)+hexByte(0x5B)+hexByte(0xC3))
    pos = pos + 130

    // ── kr_argcount() → argc as string ────────────────────────────
    // 65 bytes. Uses GetCommandLineA, counts space-separated tokens.
    offsets = offsets + "kr_argcount:" + pos + "\n"
    let ac_gc = iatK32Rva + 33*8 - (textRva + pos + 4 + 6)
    let ac_it = 266 - (pos + 52 + 5)
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0xFF)+hexByte(0x15)+hexDword(ac_gc))
    sb2 = sbAppend(sb2, hexByte(0x33)+hexByte(0xD2))
    sb2 = sbAppend(sb2, hexByte(0x80)+hexByte(0x38)+hexByte(0x00)+hexByte(0x74)+hexByte(0x1F))
    sb2 = sbAppend(sb2, hexByte(0xFF)+hexByte(0xC2))
    sb2 = sbAppend(sb2, hexByte(0x80)+hexByte(0x38)+hexByte(0x20)+hexByte(0x7F)+hexByte(0x05))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC0)+hexByte(0xEB)+hexByte(0xF3))
    sb2 = sbAppend(sb2, hexByte(0x80)+hexByte(0x38)+hexByte(0x00)+hexByte(0x74)+hexByte(0x0A))
    sb2 = sbAppend(sb2, hexByte(0x80)+hexByte(0x38)+hexByte(0x20)+hexByte(0x75)+hexByte(0xF3))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC0)+hexByte(0xEB)+hexByte(0xEC))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x63)+hexByte(0xCA))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(ac_it))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28)+hexByte(0xC3))
    pos = pos + 65

    // ── kr_arg(RCX=idx_str) → idx-th arg string ───────────────────
    // 136 bytes. GetCommandLineA, skip idx tokens.
    offsets = offsets + "kr_arg:" + pos + "\n"
    let ag_gc = iatK32Rva + 33*8 - (textRva + pos + 4 + 6)
    let ag_ai = 197 - (pos + 19 + 5)
    let ag_sd = 52 - (pos + 108 + 5)
    let ag_ea = 18 - (pos + 121 + 5)
    sb2 = sbAppend(sb2, hexByte(0x53)+hexByte(0x56)+hexByte(0x57))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0xFF)+hexByte(0x15)+hexDword(ag_gc))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC6))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xCE))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(ag_ai))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x85)+hexByte(0xDB)+hexByte(0x74)+hexByte(0x52))
    sb2 = sbAppend(sb2, hexByte(0x33)+hexByte(0xFF))
    sb2 = sbAppend(sb2, hexByte(0x80)+hexByte(0x36)+hexByte(0x00)+hexByte(0x74)+hexByte(0x48))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x3B)+hexByte(0xFB)+hexByte(0x74)+hexByte(0x1A))
    sb2 = sbAppend(sb2, hexByte(0x80)+hexByte(0x36)+hexByte(0x20)+hexByte(0x75)+hexByte(0xF3))
    sb2 = sbAppend(sb2, hexByte(0x80)+hexByte(0x36)+hexByte(0x00)+hexByte(0x74)+hexByte(0x3D))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC6))
    sb2 = sbAppend(sb2, hexByte(0xFF)+hexByte(0xCF)+hexByte(0xEB)+hexByte(0xEB))
    sb2 = sbAppend(sb2, hexByte(0x80)+hexByte(0x36)+hexByte(0x20)+hexByte(0x7F)+hexByte(0x05))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC6)+hexByte(0xEB)+hexByte(0xE1))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xF1))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC7))
    sb2 = sbAppend(sb2, hexByte(0x80)+hexByte(0x39)+hexByte(0x00)+hexByte(0x74)+hexByte(0x09))
    sb2 = sbAppend(sb2, hexByte(0x80)+hexByte(0x39)+hexByte(0x20)+hexByte(0x74)+hexByte(0x05))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xFF)+hexByte(0xC1)+hexByte(0xEB)+hexByte(0xF2))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xCE))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x2B)+hexByte(0xF7))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xF1)+hexByte(0xE8)+hexDword(ag_sd))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0x5F)+hexByte(0x5E)+hexByte(0x5B)+hexByte(0xC3))
    sb2 = sbAppend(sb2, hexByte(0xB9)+hexDword(1)+hexByte(0xE8)+hexDword(ag_ea))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x00)+hexByte(0x00))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0x5F)+hexByte(0x5E)+hexByte(0x5B)+hexByte(0xC3))
    pos = pos + 136

    // ── kr_charcode(RCX=s) → ASCII value as string ────────────────
    // 17 bytes: sub(4)+movzx(3)+call(5)+add(4)+ret(1)
    offsets = offsets + "kr_charcode:" + pos + "\n"
    let cc_it = 266 - (pos + 7 + 5)
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0x0F)+hexByte(0xB6)+hexByte(0x09))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(cc_it))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28)+hexByte(0xC3))
    pos = pos + 17

    // ── kr_fromcharcode(RCX=n_str) → single char string ───────────
    // 32 bytes: push RBX(1)+sub(4)+atoi(5)+mov rbx,rax(3)+mov ecx,2(5)+alloc(5)+
    //           mov[rax],bl(2)+mov[rax+1],0(4)+add(4)+pop rbx(1)+ret(1) = 35... adjust:
    // push RBX; sub rsp,0x28; call atoi; MOV RBX,RAX; MOV ECX,2; call alloc;
    // MOV [RAX],BL; MOV BYTE[RAX+1],0; ADD RSP,0x28; POP RBX; RET
    offsets = offsets + "kr_fromcharcode:" + pos + "\n"
    let fc_ai = 197 - (pos + 5 + 5)
    let fc_al = 18 - (pos + 16 + 5)
    sb2 = sbAppend(sb2, hexByte(0x53))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(fc_ai))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))
    sb2 = sbAppend(sb2, hexByte(0xB9)+hexDword(2))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(fc_al))
    sb2 = sbAppend(sb2, hexByte(0x88)+hexByte(0x18))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x40)+hexByte(0x01)+hexByte(0x00))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0x5B)+hexByte(0xC3))
    pos = pos + 30

    // ── kr_isdigit(RCX=s) → "0"/"1" ──────────────────────────────
    // Layout: sub(4)+movzx(3)+cmp'0'/jb(4)+cmp':'/jae(4)=15 before .ret1
    // .ret1@15: ecx,2(5)+alloc(5)+[rax]='1'(3)+[rax+1]=0(4)+add+ret(5)=37=.ret0
    // .ret0@37: ecx,2(5)+alloc(5)+[rax]='0'(3)+[rax+1]=0(4)+add+ret(5)=59 total
    offsets = offsets + "kr_isdigit:" + pos + "\n"
    let id_al1 = 18 - (pos + 20 + 5)
    let id_al0 = 18 - (pos + 42 + 5)
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0x0F)+hexByte(0xB6)+hexByte(0x01))
    sb2 = sbAppend(sb2, hexByte(0x3C)+hexByte(0x30)+hexByte(0x72)+hexByte(0x1A))
    sb2 = sbAppend(sb2, hexByte(0x3C)+hexByte(0x3A)+hexByte(0x73)+hexByte(0x16))
    sb2 = sbAppend(sb2, hexByte(0xB9)+hexDword(2))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(id_al1))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x00)+hexByte(0x31))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x40)+hexByte(0x01)+hexByte(0x00))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28)+hexByte(0xC3))
    sb2 = sbAppend(sb2, hexByte(0xB9)+hexDword(2))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(id_al0))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x00)+hexByte(0x30))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x40)+hexByte(0x01)+hexByte(0x00))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28)+hexByte(0xC3))
    pos = pos + 59

    // ── Bit ops: push RBX(1)+sub(4)=5 prefix, so calls at local 5/16/27, size=38
    offsets = offsets + "kr_bitor:" + pos + "\n"
    let bo_ai1 = 197 - (pos + 5 + 5)
    let bo_ai2 = 197 - (pos + 16 + 5)
    let bo_it  = 266 - (pos + 27 + 5)
    sb2 = sbAppend(sb2, hexByte(0x53)+hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(bo_ai1))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xD1))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(bo_ai2))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x0B)+hexByte(0xC3))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(bo_it))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0x5B)+hexByte(0xC3))
    pos = pos + 38

    offsets = offsets + "kr_bitand:" + pos + "\n"
    let ba_ai1 = 197 - (pos + 5 + 5)
    let ba_ai2 = 197 - (pos + 16 + 5)
    let ba_it  = 266 - (pos + 27 + 5)
    sb2 = sbAppend(sb2, hexByte(0x53)+hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(ba_ai1))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xD1))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(ba_ai2))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x23)+hexByte(0xC3))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(ba_it))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0x5B)+hexByte(0xC3))
    pos = pos + 38

    offsets = offsets + "kr_bitxor:" + pos + "\n"
    let bx_ai1 = 197 - (pos + 5 + 5)
    let bx_ai2 = 197 - (pos + 16 + 5)
    let bx_it  = 266 - (pos + 27 + 5)
    sb2 = sbAppend(sb2, hexByte(0x53)+hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(bx_ai1))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xD1))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(bx_ai2))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x33)+hexByte(0xC3))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(bx_it))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0x5B)+hexByte(0xC3))
    pos = pos + 38

    // kr_bitnot: sub(4)+atoi(5)+not(3)+mov(3)+itoa(5)+add+ret(5)=25
    offsets = offsets + "kr_bitnot:" + pos + "\n"
    let bn_ai = 197 - (pos + 4 + 5)
    let bn_it = 266 - (pos + 15 + 5)
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(bn_ai))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0xF7)+hexByte(0xD0))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(bn_it))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28)+hexByte(0xC3))
    pos = pos + 25

    // kr_shl: push(1)+sub(4)+atoi1(5)+mov rbx,rax(3)+mov rcx,rdx(3)+atoi2(5)
    //         +mov rcx,rax(3)+shl rbx,cl(3)+mov rcx,rbx(3)+itoa(5)+add(4)+pop+ret(2)=41
    offsets = offsets + "kr_shl:" + pos + "\n"
    let sl_ai1 = 197 - (pos + 5 + 5)
    let sl_ai2 = 197 - (pos + 16 + 5)
    let sl_it  = 266 - (pos + 30 + 5)
    sb2 = sbAppend(sb2, hexByte(0x53)+hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(sl_ai1))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xD1))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(sl_ai2))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1)+hexByte(0x48)+hexByte(0xD3)+hexByte(0xE3))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xD9))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(sl_it))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0x5B)+hexByte(0xC3))
    pos = pos + 41

    offsets = offsets + "kr_shr:" + pos + "\n"
    let sr_ai1 = 197 - (pos + 5 + 5)
    let sr_ai2 = 197 - (pos + 16 + 5)
    let sr_it  = 266 - (pos + 30 + 5)
    sb2 = sbAppend(sb2, hexByte(0x53)+hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(sr_ai1))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xD1))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(sr_ai2))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1)+hexByte(0x48)+hexByte(0xD3)+hexByte(0xEB))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xD9))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(sr_it))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0x5B)+hexByte(0xC3))
    pos = pos + 41

    // ── kr_rawalloc(RCX=size_str) → ptr as string ─────────────────
    // sub(4)+atoi(5)+mov(3)+alloc(5)+mov(3)+itoa(5)+add+ret(5) = 30 bytes
    offsets = offsets + "kr_rawalloc:" + pos + "\n"
    let ra_ai = 197 - (pos + 4 + 5)
    let ra_al = 18 - (pos + 12 + 5)
    let ra_it = 266 - (pos + 20 + 5)
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(ra_ai))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(ra_al))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(ra_it))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28)+hexByte(0xC3))
    pos = pos + 30

    // kr_rawfree: stub (HeapFree; just return "")
    offsets = offsets + "kr_rawfree:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0xB9)+hexDword(1)+hexByte(0xE8)+hexDword(18 - (pos + 9 + 5)))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x00)+hexByte(0x00))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28)+hexByte(0xC3))
    pos = pos + 19

    // kr_rawrealloc stub
    offsets = offsets + "kr_rawrealloc:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0xB9)+hexDword(1)+hexByte(0xE8)+hexDword(18 - (pos + 9 + 5)))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x00)+hexByte(0x00))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28)+hexByte(0xC3))
    pos = pos + 19

    // kr_ptradd(RCX=ptr_str, RDX=offset_str) → (ptr+offset) as string
    // push(1)+sub(4)+atoi1(5)+mov(3)+mov(3)+atoi2(5)+add(3)+mov(3)+itoa(5)+add(4)+pop+ret(2)=38
    offsets = offsets + "kr_ptradd:" + pos + "\n"
    let pa_ai1 = 197 - (pos + 5 + 5)
    let pa_ai2 = 197 - (pos + 16 + 5)
    let pa_it  = 266 - (pos + 27 + 5)
    sb2 = sbAppend(sb2, hexByte(0x53)+hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(pa_ai1))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xD1))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(pa_ai2))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x03)+hexByte(0xC3))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC1))
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(pa_it))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0x5B)+hexByte(0xC3))
    pos = pos + 38

    // kr_ptrtoint: same as ptradd but no add (just return ptr as int string = itself)
    offsets = offsets + "kr_ptrtoint:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(52 - (pos + 5)))
    pos = pos + 5

    // ── __rt_return_empty: alloc 1 byte, write 0, ret ─────────────
    // Compute actual position before emitting (pos tracking lags by ~16 bytes here)
    let actual_emp_pos = 1559 + len(sbToString(sb2)) / 3
    let emp_pos = actual_emp_pos
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28))
    sb2 = sbAppend(sb2, hexByte(0xB9)+hexDword(1)+hexByte(0xE8)+hexDword(18 - (actual_emp_pos + 9 + 5)))
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x00)+hexByte(0x00))
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28)+hexByte(0xC3))
    pos = actual_emp_pos + 22

    // ── All remaining KRRT_FUNCS stubs → JMP __rt_return_empty ────
    offsets = offsets + "kr_div64:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_idx:" + pos + "\n"
    // kr_idx(RCX=s, RDX=is) → one-char string s[atoi(is)]; 47 bytes
    let ki_atoi = 197 - (pos + 12 + 5)
    let ki_alloc = 18 - (pos + 29 + 5)
    sb2 = sbAppend(sb2, hexByte(0x53)+hexByte(0x56))                              // PUSH RBX, PUSH RSI
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xEC)+hexByte(0x28)) // SUB RSP, 40
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xCE))               // MOV RSI, RCX (save s)
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xD1))               // MOV RCX, RDX (is → atoi)
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(ki_atoi))                         // CALL __rt_atoi
    sb2 = sbAppend(sb2, hexByte(0x0F)+hexByte(0xB6)+hexByte(0x04)+hexByte(0x06))// MOVZX EAX, [RSI+RAX]
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x89)+hexByte(0xC3))               // MOV RBX, RAX (save char)
    sb2 = sbAppend(sb2, hexByte(0xB9)+hexDword(2))                               // MOV ECX, 2
    sb2 = sbAppend(sb2, hexByte(0xE8)+hexDword(ki_alloc))                        // CALL __rt_alloc
    sb2 = sbAppend(sb2, hexByte(0x88)+hexByte(0x18))                             // MOV [RAX], BL
    sb2 = sbAppend(sb2, hexByte(0xC6)+hexByte(0x40)+hexByte(0x01)+hexByte(0x00))// MOV [RAX+1], 0
    sb2 = sbAppend(sb2, hexByte(0x48)+hexByte(0x83)+hexByte(0xC4)+hexByte(0x28))// ADD RSP, 40
    sb2 = sbAppend(sb2, hexByte(0x5E)+hexByte(0x5B)+hexByte(0xC3))              // POP RSI, POP RBX, RET
    pos = pos + 47
    offsets = offsets + "kr_tolower:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_init_args:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_writebytes:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_touppers:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_hex:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_environ:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_sizeof:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_tohandle:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_bufnew:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_bufsetdword:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_bufgetdword:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_bufsetdwordat:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_bufgetdwordat:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_bufgetword:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_bufgetqword:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_bufsetbyte:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_structnew:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_structget:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_structset:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_bufstr:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_bufgetqwordat:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_handleout:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_handleget:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_handlevalid:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_handleint:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_ptrderef:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_ptrindex:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_callptr1:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_callptr2:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_callptr3:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_callptr4:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_rawreadbyte:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_rawreadword:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_rawwriteword:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5
    offsets = offsets + "kr_rawwriteqword:" + pos + "\n"
    sb2 = sbAppend(sb2, hexByte(0xE9)+hexDword(emp_pos - (pos + 5)))
    pos = pos + 5

    emit sb_good + sbToString(sb2) + "\nOFFSETS\n" + offsets
}

// ── Bootstrap import table (kernel32 only) ────────────────────────
// Used when building krypton_rt.dll itself so it has no circular dependency.
func buildBootstrapImportTable(rdataRva, strsSize) {
    // Inline KR32_FUNCS literal (global variable access is broken in current codegen)
    let k32funcs = "ExitProcess,GetStdHandle,SetConsoleOutputCP,GetConsoleMode,SetConsoleMode,GetConsoleScreenBufferInfo,GetCurrentProcessId,CreateToolhelp32Snapshot,Process32First,Process32Next,CloseHandle,GetDiskFreeSpaceExA,GlobalMemoryStatusEx,GetSystemPowerStatus,GetTickCount64,GetLogicalDrives,GetNativeSystemInfo,GetComputerNameA,FindFirstFileA,FindNextFileA,FindClose,GetFileAttributesA,LoadLibraryA,FreeLibrary,GetProcAddress,GetEnvironmentVariableA,HeapAlloc,HeapFree,HeapReAlloc,GetProcessHeap,WriteFile,ReadFile,CreateFileA,GetCommandLineA,GetFileSizeEx"
    let k32count = countFuncs(k32funcs)

    let impBase = strsSize
    let impBasePad = impBase
    if impBasePad % 8 != 0 { impBasePad = impBasePad + (8 - impBasePad % 8) }

    let descOffset = impBasePad
    let descSize = 40  // kernel32 descriptor + null descriptor
    let iltK32Offset = descOffset + descSize
    let iltK32Size = (k32count + 1) * 8
    let iatK32Offset = iltK32Offset + iltK32Size
    let iatK32Size = (k32count + 1) * 8
    let dllNamesOffset = iatK32Offset + iatK32Size
    let dllK32Name = "kernel32.dll"
    let hintsOffset = dllNamesOffset + len(dllK32Name) + 1
    if hintsOffset % 2 != 0 { hintsOffset = hintsOffset + 1 }

    let descRva = rdataRva + descOffset
    let iltK32Rva = rdataRva + iltK32Offset
    let iatK32Rva = rdataRva + iatK32Offset
    let dllK32Rva = rdataRva + dllNamesOffset
    let hintsRva = rdataRva + hintsOffset

    // Build hint table (2-byte hint + name + null + even-align pad)
    let sbHint = sbNew()
    let sbHintOff = sbNew()
    let hintOff = 0
    let hf = 0
    while hf < k32count {
        let hfname = funcAt(k32funcs, hf)
        if hintOff > 0 { sbHintOff = sbAppend(sbHintOff, "\n") }
        sbHintOff = sbAppend(sbHintOff, hintOff + "")
        sbHint = sbAppend(sbHint, hexByte(0) + hexByte(0) + hexStrZ(hfname))
        hintOff += 2 + len(hfname) + 1
        if hintOff % 2 != 0 { sbHint = sbAppend(sbHint, hexByte(0))  hintOff += 1 }
        hf += 1
    }
    let hintTable = sbToString(sbHint)
    let hintOffsets = sbToString(sbHintOff)

    // Build ILT/IAT (same bytes; loader fills IAT)
    let sbIlt = sbNew()
    let k32i = 0
    while k32i < k32count {
        let hintRva = hintsRva + toInt(getLine(hintOffsets, k32i))
        sbIlt = sbAppend(sbIlt, hexQword64(hintRva, 0))
        k32i += 1
    }
    sbIlt = sbAppend(sbIlt, hexQword64(0, 0))
    let iltK32 = sbToString(sbIlt)

    // descriptor: OrigFirstThunk(4) TimeDateStamp(4) ForwarderChain(4) Name(4) FirstThunk(4)
    let desc = hexDword(iltK32Rva) + hexDword(0) + hexDword(0) + hexDword(dllK32Rva) + hexDword(iatK32Rva)
    desc = desc + hexDword(0) + hexDword(0) + hexDword(0) + hexDword(0) + hexDword(0)  // null

    let out = ""
    let pp = 0
    while pp < impBasePad - impBase { out = out + hexByte(0)  pp += 1 }
    out = out + desc + iltK32 + iltK32  // ILT + IAT
    out = out + hexStrZ(dllK32Name)
    if (dllNamesOffset + len(dllK32Name) + 1) % 2 != 0 { out = out + hexByte(0) }
    out = out + hintTable

    emit out + "," + iatK32Rva + "," + descRva + "," + iatK32Size
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

func buildImportTable(rdataRva, strsSize, rtDllName) {
    let k32funcs = KR32_FUNCS
    let rtfuncs = KRRT_FUNCS
    let advfuncs = KRADV_FUNCS
    let pdhfuncs = KRPDH_FUNCS
    let userfuncs = KRUSER_FUNCS
    let k32count = countFuncs(k32funcs)
    let rtcount = countFuncs(rtfuncs)
    let advcount = countFuncs(advfuncs)
    let pdhcount = countFuncs(pdhfuncs)
    let usercount = countFuncs(userfuncs)

    // Calculate offsets within .rdata (after string table)
    let impBase = strsSize  // import table starts right after string table (padded to 8)
    let impBasePad = impBase
    if impBasePad % 8 != 0 { impBasePad = impBasePad + (8 - impBasePad % 8) }

    // Layout:
    //   [A] 6 IMAGE_IMPORT_DESCRIPTORs (kernel32, krypton_rt, advapi32, pdh, user32, null) = 120 bytes
    //   [B] ILT kernel32   (k32count+1)*8
    //   [C] ILT krypton_rt (rtcount+1)*8
    //   [D] ILT advapi32   (advcount+1)*8
    //   [E] ILT pdh        (pdhcount+1)*8
    //   [F] ILT user32     (usercount+1)*8
    //   [G] IAT kernel32   (k32count+1)*8
    //   [H] IAT krypton_rt (rtcount+1)*8
    //   [I] IAT advapi32   (advcount+1)*8
    //   [J] IAT pdh        (pdhcount+1)*8
    //   [K] IAT user32     (usercount+1)*8
    //   [L] DLL names
    //   [M] IMAGE_IMPORT_BY_NAME hint table

    let descOffset = impBasePad
    let descSize = 120  // 6 descriptors * 20 bytes
    let iltK32Offset = descOffset + descSize
    let iltK32Size = (k32count + 1) * 8
    let iltRtOffset = iltK32Offset + iltK32Size
    let iltRtSize = (rtcount + 1) * 8
    let iltAdvOffset = iltRtOffset + iltRtSize
    let iltAdvSize = (advcount + 1) * 8
    let iltPdhOffset = iltAdvOffset + iltAdvSize
    let iltPdhSize = (pdhcount + 1) * 8
    let iltUserOffset = iltPdhOffset + iltPdhSize
    let iltUserSize = (usercount + 1) * 8
    let iatK32Offset = iltUserOffset + iltUserSize
    let iatK32Size = (k32count + 1) * 8
    let iatRtOffset = iatK32Offset + iatK32Size
    let iatRtSize = (rtcount + 1) * 8
    let iatAdvOffset = iatRtOffset + iatRtSize
    let iatAdvSize = (advcount + 1) * 8
    let iatPdhOffset = iatAdvOffset + iatAdvSize
    let iatPdhSize = (pdhcount + 1) * 8
    let iatUserOffset = iatPdhOffset + iatPdhSize
    let iatUserSize = (usercount + 1) * 8
    let dllNamesOffset = iatUserOffset + iatUserSize
    let dllK32Name = "kernel32.dll"
    let dllRtName = rtDllName
    let dllAdvName = "advapi32.dll"
    let dllPdhName = "pdh.dll"
    let dllUserName = "user32.dll"
    let dllK32Offset = dllNamesOffset
    let dllRtOffset = dllK32Offset + len(dllK32Name) + 1
    let dllAdvOffset = dllRtOffset + len(dllRtName) + 1
    let dllPdhOffset = dllAdvOffset + len(dllAdvName) + 1
    let dllUserOffset = dllPdhOffset + len(dllPdhName) + 1
    let hintsOffset = dllUserOffset + len(dllUserName) + 1
    // Pad to 2-byte alignment
    if hintsOffset % 2 != 0 { hintsOffset += 1 }

    // Compute RVAs
    let descRva = rdataRva + descOffset
    let iltK32Rva = rdataRva + iltK32Offset
    let iltRtRva = rdataRva + iltRtOffset
    let iltAdvRva = rdataRva + iltAdvOffset
    let iltPdhRva = rdataRva + iltPdhOffset
    let iltUserRva = rdataRva + iltUserOffset
    let iatK32Rva = rdataRva + iatK32Offset
    let iatRtRva = rdataRva + iatRtOffset
    let iatAdvRva = rdataRva + iatAdvOffset
    let iatPdhRva = rdataRva + iatPdhOffset
    let iatUserRva = rdataRva + iatUserOffset
    let dllK32Rva = rdataRva + dllK32Offset
    let dllRtRva = rdataRva + dllRtOffset
    let dllAdvRva = rdataRva + dllAdvOffset
    let dllPdhRva = rdataRva + dllPdhOffset
    let dllUserRva = rdataRva + dllUserOffset
    let hintsRva = rdataRva + hintsOffset

    // Build IMAGE_IMPORT_BY_NAME entries (hint + name)
    // Each: 2-byte hint + name string + null + padding to even
    let sbHint = sbNew()
    let sbHintOff = sbNew()
    let hintOff = 0

    let hf = 0
    while hf < k32count {
        let hfname = funcAt(k32funcs, hf)
        if hintOff > 0 { sbHintOff = sbAppend(sbHintOff, "\n") }
        sbHintOff = sbAppend(sbHintOff, hintOff + "")
        sbHint = sbAppend(sbHint, hexByte(0) + hexByte(0) + hexStrZ(hfname))
        hintOff += 2 + len(hfname) + 1
        if hintOff % 2 != 0 { sbHint = sbAppend(sbHint, hexByte(0))  hintOff += 1 }
        hf += 1
    }
    let hf2 = 0
    while hf2 < rtcount {
        let hfname2 = funcAt(rtfuncs, hf2)
        if hintOff > 0 { sbHintOff = sbAppend(sbHintOff, "\n") }
        sbHintOff = sbAppend(sbHintOff, hintOff + "")
        sbHint = sbAppend(sbHint, hexByte(0) + hexByte(0) + hexStrZ(hfname2))
        hintOff += 2 + len(hfname2) + 1
        if hintOff % 2 != 0 { sbHint = sbAppend(sbHint, hexByte(0))  hintOff += 1 }
        hf2 += 1
    }
    let hf3 = 0
    while hf3 < advcount {
        let hfname3 = funcAt(advfuncs, hf3)
        if hintOff > 0 { sbHintOff = sbAppend(sbHintOff, "\n") }
        sbHintOff = sbAppend(sbHintOff, hintOff + "")
        sbHint = sbAppend(sbHint, hexByte(0) + hexByte(0) + hexStrZ(hfname3))
        hintOff += 2 + len(hfname3) + 1
        if hintOff % 2 != 0 { sbHint = sbAppend(sbHint, hexByte(0))  hintOff += 1 }
        hf3 += 1
    }
    let hf4 = 0
    while hf4 < pdhcount {
        let hfname4 = funcAt(pdhfuncs, hf4)
        if hintOff > 0 { sbHintOff = sbAppend(sbHintOff, "\n") }
        sbHintOff = sbAppend(sbHintOff, hintOff + "")
        sbHint = sbAppend(sbHint, hexByte(0) + hexByte(0) + hexStrZ(hfname4))
        hintOff += 2 + len(hfname4) + 1
        if hintOff % 2 != 0 { sbHint = sbAppend(sbHint, hexByte(0))  hintOff += 1 }
        hf4 += 1
    }
    let hf5 = 0
    while hf5 < usercount {
        let hfname5 = funcAt(userfuncs, hf5)
        if hintOff > 0 { sbHintOff = sbAppend(sbHintOff, "\n") }
        sbHintOff = sbAppend(sbHintOff, hintOff + "")
        sbHint = sbAppend(sbHint, hexByte(0) + hexByte(0) + hexStrZ(hfname5))
        hintOff += 2 + len(hfname5) + 1
        if hintOff % 2 != 0 { sbHint = sbAppend(sbHint, hexByte(0))  hintOff += 1 }
        hf5 += 1
    }
    let hintTable = sbToString(sbHint)
    let hintOffsets = sbToString(sbHintOff)

    // Build ILT / IAT entries
    // Each entry: 8 bytes, high bit=0 → by name → RVA of IMAGE_IMPORT_BY_NAME
    let sbIltK32 = sbNew()
    let k32i = 0
    while k32i < k32count {
        let hintRvaK = hintsRva + toInt(getLine(hintOffsets, k32i))
        sbIltK32 = sbAppend(sbIltK32, hexQword64(hintRvaK, 0))
        k32i += 1
    }
    sbIltK32 = sbAppend(sbIltK32, hexQword64(0, 0))
    let iltK32 = sbToString(sbIltK32)

    let sbIltRt = sbNew()
    let rti = 0
    while rti < rtcount {
        let hintRvaR = hintsRva + toInt(getLine(hintOffsets, k32count + rti))
        sbIltRt = sbAppend(sbIltRt, hexQword64(hintRvaR, 0))
        rti += 1
    }
    sbIltRt = sbAppend(sbIltRt, hexQword64(0, 0))
    let iltRt = sbToString(sbIltRt)

    let sbIltAdv = sbNew()
    let advi = 0
    while advi < advcount {
        let hintRvaA = hintsRva + toInt(getLine(hintOffsets, k32count + rtcount + advi))
        sbIltAdv = sbAppend(sbIltAdv, hexQword64(hintRvaA, 0))
        advi += 1
    }
    sbIltAdv = sbAppend(sbIltAdv, hexQword64(0, 0))
    let iltAdv = sbToString(sbIltAdv)

    let sbIltPdh = sbNew()
    let pdhi = 0
    while pdhi < pdhcount {
        let hintRvaP = hintsRva + toInt(getLine(hintOffsets, k32count + rtcount + advcount + pdhi))
        sbIltPdh = sbAppend(sbIltPdh, hexQword64(hintRvaP, 0))
        pdhi += 1
    }
    sbIltPdh = sbAppend(sbIltPdh, hexQword64(0, 0))
    let iltPdh = sbToString(sbIltPdh)

    let sbIltUser = sbNew()
    let useri = 0
    while useri < usercount {
        let hintRvaU = hintsRva + toInt(getLine(hintOffsets, k32count + rtcount + advcount + pdhcount + useri))
        sbIltUser = sbAppend(sbIltUser, hexQword64(hintRvaU, 0))
        useri += 1
    }
    sbIltUser = sbAppend(sbIltUser, hexQword64(0, 0))
    let iltUser = sbToString(sbIltUser)

    // Build IMAGE_IMPORT_DESCRIPTOR (20 bytes each):
    // OriginalFirstThunk(4) TimeDateStamp(4) ForwarderChain(4) Name(4) FirstThunk(4)
    let desc = ""
    desc = desc + hexDword(iltK32Rva)  + hexDword(0) + hexDword(0) + hexDword(dllK32Rva)  + hexDword(iatK32Rva)
    desc = desc + hexDword(iltRtRva)   + hexDword(0) + hexDword(0) + hexDword(dllRtRva)   + hexDword(iatRtRva)
    desc = desc + hexDword(iltAdvRva)  + hexDword(0) + hexDword(0) + hexDword(dllAdvRva)  + hexDword(iatAdvRva)
    desc = desc + hexDword(iltPdhRva)  + hexDword(0) + hexDword(0) + hexDword(dllPdhRva)  + hexDword(iatPdhRva)
    desc = desc + hexDword(iltUserRva) + hexDword(0) + hexDword(0) + hexDword(dllUserRva) + hexDword(iatUserRva)
    desc = desc + hexDword(0) + hexDword(0) + hexDword(0) + hexDword(0) + hexDword(0)  // null descriptor

    // Assemble the import section data
    let out = ""
    let pp = 0
    while pp < impBasePad - impBase { out = out + hexByte(0)  pp += 1 }
    out = out + desc
    out = out + iltK32
    out = out + iltRt
    out = out + iltAdv
    out = out + iltPdh
    out = out + iltUser
    out = out + iltK32   // IAT kernel32
    out = out + iltRt    // IAT krypton_rt
    out = out + iltAdv   // IAT advapi32
    out = out + iltPdh   // IAT pdh
    out = out + iltUser  // IAT user32
    out = out + hexStrZ(dllK32Name)
    out = out + hexStrZ(dllRtName)
    out = out + hexStrZ(dllAdvName)
    out = out + hexStrZ(dllPdhName)
    out = out + hexStrZ(dllUserName)
    let dllNamesEndOff = dllUserOffset + len(dllUserName) + 1
    if dllNamesEndOff % 2 != 0 { out = out + hexByte(0) }
    out = out + hintTable

    // Return: "hexdata,iatK32Rva,descRva,totalSize,iatAdvRva,iatPdhRva,iatUserRva"
    let iatTotal = iatK32Size + iatRtSize + iatAdvSize + iatPdhSize + iatUserSize
    emit out + "," + iatK32Rva + "," + descRva + "," + iatTotal + "," + iatAdvRva + "," + iatPdhRva + "," + iatUserRva
}

// ── Entry point wrapper ───────────────────────────────────────────
// Calls __main__, then calls ExitProcess with return value
func emitEntryPoint(mainFuncOffset, iatK32Rva, entryRva) {
    // entryRva = RVA of this code
    let code = sbNew()
    let pos = 0

    // SUB RSP, 40  (32 shadow + 8 align), use imm32 for consistency
    code = sbAppend(code, subRspN(40))
    pos += 7

    // CALL __main__
    let callDisp = mainFuncOffset - (entryRva + pos + 5)
    code = sbAppend(code, hexByte(0xE8) + hexDword(callDisp))
    pos += 5

    // XOR ECX, ECX (exit code 0)
    code = sbAppend(code, hexByte(0x33) + hexByte(0xC9))
    pos += 2

    // CALL ExitProcess via IAT
    let exitIatRva = iatK32Rva
    let epDisp = exitIatRva - (entryRva + pos + 6)
    code = sbAppend(code, hexByte(0xFF) + hexByte(0x15) + hexDword(epDisp))
    pos += 6

    code = sbAppend(code, hexByte(0xC3))  // RET (unreachable)

    emit sbToString(code)
}

// ── Main compilation ──────────────────────────────────────────────
just run {
    let file = arg("0")
    let outFile = arg("1")
    let isDll = "0"
    if len(outFile) >= 4 {
        let ext = substring(outFile, len(outFile) - 4, len(outFile))
        if ext == ".dll" || ext == ".DLL" { isDll = "1" }
    }

    // Bootstrap mode: building krypton_rt.dll itself — import from legacy to avoid self-import
    // Native exes also import from legacy (exports all 89 KRRT_FUNCS); krypton_rt.dll only has 39.
    let isBootstrap = "0"
    let rtDllName = "krypton_rt_legacy.dll"
    if isDll == "1" {
        let bsnBase = outFile
        let bsnI = len(bsnBase) - 1
        while bsnI >= 0 && bsnBase[bsnI] != "\\" && bsnBase[bsnI] != "/" { bsnI = bsnI - 1 }
        bsnBase = substring(bsnBase, bsnI + 1, len(bsnBase))
        if bsnBase != "krypton_rt.dll" { rtDllName = "krypton_rt.dll" }
    }

    if len(file) == 0 {
        printErr("x64: usage: kcc kompiler/x64.k <file.kir> [output.exe|output.dll]")
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
    let cleanSb = sbNew()
    let cleanFirst = "1"
    let ci = 0
    while ci < total {
        let ln = trim(getLine(allLines, ci))
        if len(ln) > 0 && ln[0] != ";" {
            if cleanFirst == "0" { cleanSb = sbAppend(cleanSb, "\n") }
            cleanSb = sbAppend(cleanSb, ln)
            cleanFirst = "0"
        }
        ci += 1
    }
    let clean = sbToString(cleanSb)

    // Bootstrap mode: only when building krypton_rt.dll itself from hand-written machine code (no FUNC in IR)
    if isDll == "1" && rtDllName == "krypton_rt_legacy.dll" && contains(clean, "FUNC") == "0" { isBootstrap = "1" }

    // Collect EXPORT directives
    let exportNamesSb = sbNew()
    let exportNamesFirst = "1"
    let expScanCount = lineCount(clean)
    let expScanI = 0
    while expScanI < expScanCount {
        let expLn = getLine(clean, expScanI)
        if irGetOp(expLn) == "EXPORT" {
            let expFnName = irGetArg1(expLn)
            if exportNamesFirst == "0" { exportNamesSb = sbAppend(exportNamesSb, "\n") }
            exportNamesSb = sbAppend(exportNamesSb, expFnName)
            exportNamesFirst = "0"
        }
        expScanI += 1
    }
    let exportNames = sbToString(exportNamesSb)
    let exportCount = 0
    if len(exportNames) > 0 { exportCount = lineCount(exportNames) }

    // Collect all string constants
    let strs = collectStrings(clean)
    // Add numeric constants that appear as PUSH non-quoted
    let strsSb = sbNew()
    strsSb = sbAppend(strsSb, strs)
    let strsCurrent = strs
    let cl2 = lineCount(clean)
    let ii = 0
    while ii < cl2 {
        let ln2 = getLine(clean, ii)
        if irGetOp(ln2) == "PUSH" {
            let val = trim(irGetRest(ln2))
            if !startsWith(val, "\"") {
                if !contains("\n" + strsCurrent, "\n" + val + "\n") {
                    if len(strsCurrent) > 0 { strsSb = sbAppend(strsSb, "\n") }
                    strsSb = sbAppend(strsSb, val)
                    strsCurrent = strsCurrent + "\n" + val
                }
            }
        }
        ii += 1
    }
    strs = sbToString(strsSb)

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
    let PE_FILE_ALIGN = 512
    let PE_SECT_ALIGN = 4096
    let PE_HEADER_SIZE = 512

    // ── Bootstrap mode: krypton_rt.dll built from raw machine code ────
    if isBootstrap == "1" {
        // Bootstrap block size + 6-byte DllMain
        let bsTextBytes = bsHelperBlockSize()
        let bsFullText = bsTextBytes + 6
        let bsTextFileSz = alignUp(bsFullText, PE_FILE_ALIGN)
        let bsRdataRvaB = PE_TEXT_RVA2 + alignUp(bsFullText, PE_SECT_ALIGN)

        // Build kernel32-only import table
        let bsImpData = buildBootstrapImportTable(bsRdataRvaB, 0)
        let bsImpHex = split(bsImpData, 0)
        let bsIatK32B = toInt(split(bsImpData, 1))
        let bsIatDescRvaB = toInt(split(bsImpData, 2))
        let bsIatTotalSzB = toInt(split(bsImpData, 3))

        // Generate bootstrap text section with correct IAT addresses
        let bsRaw = emitBootstrapHelpers(PE_TEXT_RVA2, bsIatK32B)
        let bsCodeHex = getLine(bsRaw, 0)  // hex code (line 0, before OFFSETS)
        // Lines 1="OFFSETS", 2+="funcname:offset"
        let bsOffsetsSb = sbNew()
        let bsExportNamesSb = sbNew()
        let bsOffsetsFirst = "1"
        let bsExportNamesFirst = "1"
        let bsRlc = lineCount(bsRaw)
        let bsRi = 2
        while bsRi < bsRlc {
            let bsLn = getLine(bsRaw, bsRi)
            if len(bsLn) > 0 {
                let bsCi = 0
                while bsCi < len(bsLn) && bsLn[bsCi] != ":" { bsCi += 1 }
                let bsFn = substring(bsLn, 0, bsCi)
                if bsOffsetsFirst == "0" { bsOffsetsSb = sbAppend(bsOffsetsSb, "\n") }
                bsOffsetsSb = sbAppend(bsOffsetsSb, bsLn)
                bsOffsetsFirst = "0"
                if bsExportNamesFirst == "0" { bsExportNamesSb = sbAppend(bsExportNamesSb, "\n") }
                bsExportNamesSb = sbAppend(bsExportNamesSb, bsFn)
                bsExportNamesFirst = "0"
            }
            bsRi += 1
        }

        // Build export table for all kr_* functions
        let bsOffsets = sbToString(bsOffsetsSb)
        let bsExportNames = sbToString(bsExportNamesSb)
        let bsImpSz = len(bsImpHex) / 3
        printErr("bs debug: bsImpSz=" + bsImpSz + " exportNames.lines=" + lineCount(bsExportNames) + " offsets.lines=" + lineCount(bsOffsets))
        printErr("bs debug: bsRdataRvaB=" + bsRdataRvaB + " bsIatK32B=" + bsIatK32B)
        printErr("bs debug: first exportName=" + getLine(bsExportNames, 0) + " first offset=" + getLine(bsOffsets, 0))
        let bsExpHex = buildExportTable(bsExportNames, bsOffsets, PE_TEXT_RVA2, bsRdataRvaB, bsImpSz, "krypton_rt.dll")
        let bsExpRva = bsRdataRvaB + bsImpSz
        let bsExpSz = len(bsExpHex) / 3
        printErr("bs debug: bsExpSz=" + bsExpSz + " bsExpRva=" + bsExpRva)

        let bsRdataSz = bsImpSz + bsExpSz
        let bsRdataFileSz = alignUp(bsRdataSz, PE_FILE_ALIGN)
        let bsRdataFileOffB = PE_TEXT_FILE_OFF + bsTextFileSz
        let bsImgSz = bsRdataRvaB + alignUp(bsRdataSz, PE_SECT_ALIGN)
        let bsEntryRva = PE_TEXT_RVA2 + bsTextBytes  // DllMain after bootstrap code

        let bsDos = emitDosHeader()
        let bsIatInfo = bsIatK32B + "\n" + "1" + "\n" + bsExpRva + "\n" + bsExpSz
        let bsPEH = emitPEHeader(2, bsFullText, bsRdataSz, PE_TEXT_RVA2, bsRdataRvaB, bsEntryRva, bsImgSz, bsIatDescRvaB, bsIatTotalSzB, bsIatInfo)
        let bsTxtHdr = emitSectionHeader(".text", bsFullText, PE_TEXT_RVA2, bsTextFileSz, PE_TEXT_FILE_OFF, 536870944)
        let bsRdHdr = emitSectionHeader(".rdata", bsRdataSz, bsRdataRvaB, bsRdataFileSz, bsRdataFileOffB, 1073741888)

        let bsHdrHex = bsDos + bsPEH + bsTxtHdr + bsRdHdr
        let bsHdrPad = PE_HEADER_SIZE - len(bsHdrHex) / 3
        let bsDllMain = hexByte(0xB8) + hexDword(1) + hexByte(0xC3)
        let bsTxtPad = bsTextFileSz - bsFullText
        let bsRdPad = bsRdataFileSz - bsRdataSz

        let bsPE = bsHdrHex + hexPad(bsHdrPad) + bsCodeHex + bsDllMain + hexPad(bsTxtPad) + bsImpHex + bsExpHex + hexPad(bsRdPad)
        writeBytes(outFile, bsPE)
        printErr("x64: wrote bootstrap " + outFile + " (" + (len(bsPE) / 3) + " bytes)")
        emit 0
    }

    // ── Pass 1: accurate size calculation using instrSize ─────────────
    // Computes exact byte offsets for every function, no code emitted yet.
    let allFuncOffsetsSb = sbNew()
    let afoFirst = "1"
    let totalFuncBytes = 0

    let fi = 0
    while fi < funcCount {
        let entry2 = getLine(funcTable, fi)
        let fname3 = funcTableName(entry2)
        let body3 = replace(funcTableBody(entry2), "|||", "\n")
        let g_loc3 = collectLocals(body3)
        let fsz = funcByteSize(body3)
        if afoFirst == "0" { allFuncOffsetsSb = sbAppend(allFuncOffsetsSb, "\n") }
        allFuncOffsetsSb = sbAppend(allFuncOffsetsSb, fname3 + ":" + totalFuncBytes)
        afoFirst = "0"
        totalFuncBytes += fsz
        fi += 1
    }
    let allFuncOffsets = sbToString(allFuncOffsetsSb)

    // Entry point: EXE=21 bytes (subRsp+call+xor+callIAT+ret), DLL=6 bytes (mov eax,1+ret)
    let entrySize = 21
    if isDll == "1" { entrySize = 6 }
    let entryByteOffset = totalFuncBytes
    let totalTextBytes = totalFuncBytes + entrySize

    // ── Layout ───────────────────────────────────────────────────────
    // Emit string table first so strTableSize is measured from actual bytes (not recomputed)
    // This guarantees buildImportTable RVAs match the actual string table layout.
    let strTableHex = emitStringTable(strs)
    let strTableSize = len(strTableHex) / 3
    let realRdataRva = PE_TEXT_RVA2 + alignUp(totalTextBytes, PE_SECT_ALIGN)

    // Build import table once with the real rdata RVA
    let realImportData = buildImportTable(realRdataRva, strTableSize, rtDllName)
    let realImportHex = split(realImportData, 0)
    let realIatK32 = toInt(split(realImportData, 1))
    let realIatDescRva = toInt(split(realImportData, 2))
    let realIatTotalSz = toInt(split(realImportData, 3))
    let realIatAdvRva = toInt(split(realImportData, 4))
    let realIatPdhRva = toInt(split(realImportData, 5))
    let realIatUserRva = toInt(split(realImportData, 6))
    let realIatRtRva = realIatK32 + (countFuncs(KR32_FUNCS) + 1) * 8

    // Build export table (DLL only, if any exports exist)
    let realExportHex = ""
    let realExportRva = 0
    let realExportSize = 0
    if isDll == "1" && exportCount > 0 {
        let importHexSize = len(realImportHex) / 3
        let exportBaseOff = strTableSize + importHexSize
        // Extract DLL name from outFile path (basename)
        let dllBaseName = outFile
        let dbi = len(dllBaseName) - 1
        while dbi >= 0 && dllBaseName[dbi] != "\\" && dllBaseName[dbi] != "/" { dbi = dbi - 1 }
        dllBaseName = substring(dllBaseName, dbi + 1, len(dllBaseName))
        realExportHex = buildExportTable(exportNames, allFuncOffsets, PE_TEXT_RVA2, realRdataRva, exportBaseOff, dllBaseName)
        realExportRva = realRdataRva + exportBaseOff
        realExportSize = len(realExportHex) / 3
    }

    let rdataSize2 = strTableSize + len(realImportHex) / 3 + realExportSize
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
        let body4 = replace(funcTableBody(entry3), "|||", "\n")
        let g_loc4 = collectLocals(body4)
        let funcRva2 = PE_TEXT_RVA2 + realTextSize
        let labelPositions = collectLabelPositions(body4)
        let iatBases = realIatK32 + "\n" + realIatRtRva + "\n" + realIatAdvRva + "\n" + realIatPdhRva + "\n" + realIatUserRva
        let fbytes = toInt(emitFuncFull(body4, g_loc4, funcRva2, iatBases, realRdataRva, strs, labelPositions, allFuncOffsets, sbCode))
        realTextSize += fbytes
        fi2 += 1
    }

    // Entry point: DLL → minimal DllMain (mov eax,1; ret); EXE → call __main__ + ExitProcess
    let entryRva2 = PE_TEXT_RVA2 + realTextSize
    if isDll == "1" {
        // DllMain: MOV EAX,1 (B8 01 00 00 00) + RET (C3)
        let dllMain = hexByte(0xB8) + hexDword(1) + hexByte(0xC3)
        sbCode = sbAppend(sbCode, dllMain)
        realTextSize += len(dllMain) / 3
    } else {
        let mainOffset = funcOffsetLookup(allFuncOffsets, "__main__")
        let entryCode = emitEntryPoint(PE_TEXT_RVA2 + mainOffset, realIatK32, entryRva2)
        sbCode = sbAppend(sbCode, entryCode)
        realTextSize += len(entryCode) / 3
    }
    let realFuncCode = sbToString(sbCode)

    // ── Assemble the PE binary ────────────────────────────────────────
    let dos = emitDosHeader()

    let iatInfo = realIatK32 + "\n" + isDll + "\n" + realExportRva + "\n" + realExportSize
    let pehdr = emitPEHeader(
        2,
        realTextSize,
        rdataSize2,
        PE_TEXT_RVA2,
        realRdataRva,
        entryRva2,
        realImageSize,
        realIatDescRva,
        realIatTotalSz,
        iatInfo
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
    let pe = hdrHex + hdrPadHex + realFuncCode + textPadHex + strTableHex + realImportHex + realExportHex + rdataPadHex

    if len(outFile) > 0 {
        writeBytes(outFile, pe)
        printErr("x64: wrote " + outFile + " (" + (len(pe) / 3) + " bytes)")
    } else {
        print(pe)
    }

    emit 0
}
