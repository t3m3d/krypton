// elf.k — minimal Krypton native ELF backend for x86-64 Linux
//
// Reads .kir from stdin or argv, emits a static ELF executable.
// Entry milestone (this version): supports a tiny subset so we can prove
// the IR → ELF pipeline end-to-end. Incrementally grow from here.
//
// Supported IR ops:
//   FUNC name argcount        - only __main__ recognized as entry
//   PUSH "string literal"     - push pointer to string
//   PUSH integer              - push immediate int
//   BUILTIN kp 1              - pop arg, call kr_print (SYS_write to stdout)
//   POP                       - drop top of stack
//   END                       - function end (returns)
//
// Layout produced:
//   [0..63]    ELF64 header
//   [64..119]  one PT_LOAD program header (R+X)
//   [120..]    code section:
//                _start: call __main__, then SYS_exit(0)
//                __main__: translated IR ops
//                kr_print: strlen + SYS_write
//   [...]      string constants (in same R+X segment)
//
// Calling convention: SysV (RDI/RSI/RDX/RCX/R8/R9). No shadow space.
//
// Usage:  kcc kompiler/elf.k input.kir output.elf

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

// hexBytesLen: number of bytes encoded in a hexByte stream (each byte is "xHH" = 3 chars)
func hexBytesLen(s) { emit len(s) / 3 }

// ── IR parsing helpers ─────────────────────────────────────────────

// Strip leading whitespace; return rest
func skipWs(s, i) {
    while i < len(s) && (s[i] == " " || s[i] == "\t") { i += 1 }
    emit i + ""
}

// Parse a quoted string literal starting at index i (must point at the opening ")
// Returns: "value\noff_after_close_quote"
func parseQuoted(s, i) {
    let v = ""
    i += 1  // skip opening "
    while i < len(s) && s[i] != "\"" {
        if s[i] == "\\" && i + 1 < len(s) {
            let c = s[i + 1]
            if c == "n" { v = v + "\n" }
            else if c == "t" { v = v + "\t" }
            else if c == "r" { v = v + "\r" }
            else if c == "\\" { v = v + "\\" }
            else if c == "\"" { v = v + "\"" }
            else if c == "0" { v = v + "" }  // skip
            else { v = v + c }
            i += 2
        } else {
            v = v + s[i]
            i += 1
        }
    }
    if i < len(s) { i += 1 }  // skip closing "
    emit v + "\n" + i
}

// ── Code emitters (x86-64 instructions) ────────────────────────────

// MOV RAX, imm64    →  48 B8 imm64
func emitMovRaxImm64(n) { emit hexByte(0x48) + hexByte(0xB8) + hexQword(n) }

// MOV EAX, imm32    →  B8 imm32
func emitMovEaxImm32(n) { emit hexByte(0xB8) + hexDword(n) }

// MOV EDI, imm32    →  BF imm32
func emitMovEdiImm32(n) { emit hexByte(0xBF) + hexDword(n) }

// MOV EDX, imm32    →  BA imm32
func emitMovEdxImm32(n) { emit hexByte(0xBA) + hexDword(n) }

// MOV RDI, imm64    →  48 BF imm64
func emitMovRdiImm64(n) { emit hexByte(0x48) + hexByte(0xBF) + hexQword(n) }

// MOV RSI, imm64    →  48 BE imm64
func emitMovRsiImm64(n) { emit hexByte(0x48) + hexByte(0xBE) + hexQword(n) }

// PUSH RDI          →  57
func emitPushRdi() { emit hexByte(0x57) }

// POP RDI           →  5F
func emitPopRdi() { emit hexByte(0x5F) }

// SYSCALL           →  0F 05
func emitSyscall() { emit hexByte(0x0F) + hexByte(0x05) }

// XOR EDI, EDI      →  31 FF
func emitXorEdi() { emit hexByte(0x31) + hexByte(0xFF) }

// RET               →  C3
func emitRet() { emit hexByte(0xC3) }

// CALL rel32        →  E8 disp32
// Arg: disp from end of CALL instruction to target.
func emitCallRel32(disp) { emit hexByte(0xE8) + hexDword(disp) }

// JMP rel32         →  E9 disp32
func emitJmpRel32(disp) { emit hexByte(0xE9) + hexDword(disp) }

// PUSH RBP; MOV RBP, RSP    standard frame setup
func emitPrologue() { emit hexByte(0x55) + hexByte(0x48) + hexByte(0x89) + hexByte(0xE5) }

// MOV RSP, RBP; POP RBP; RET
func emitEpilogue() {
    emit hexByte(0x48) + hexByte(0x89) + hexByte(0xEC) + hexByte(0x5D) + hexByte(0xC3)
}

// ── Built-in stubs (hand-emitted machine code) ─────────────────────

// kr_print: print a NUL-terminated string to stdout via SYS_write.
//   In:  RDI = string pointer
//   Out: nothing useful
//
// strlen via inline loop, then SYS_write(1, str, len), preserve callee-saved.
//
// Layout (37 bytes):
//   [0]  53                PUSH RBX                       (1)
//   [1]  48 89 FB          MOV RBX, RDI                   (3)  ; save str
//   [4]  31 C0             XOR EAX, EAX                   (2)  ; len = 0
//   .scan:
//   [6]  80 3C 03 00       CMP byte [RBX+RAX], 0          (4)
//   [10] 74 04             JZ .done +4                    (2)
//   [12] 48 FF C0          INC RAX                        (3)
//   [15] EB F5             JMP .scan -11                  (2)
//   .done:                                                       len in RAX
//   [17] 48 89 C2          MOV RDX, RAX                   (3)  ; len → arg2
//   [20] 48 89 DE          MOV RSI, RBX                   (3)  ; str → arg1
//   [23] BF 01 00 00 00    MOV EDI, 1                     (5)  ; fd=stdout
//   [28] B8 01 00 00 00    MOV EAX, 1                     (5)  ; SYS_write
//   [33] 0F 05             SYSCALL                        (2)
//   [35] 5B                POP RBX                        (1)
//   [36] C3                RET                            (1)
func emitKrPrintCode() {
    let c = ""
    c = c + hexByte(0x53)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xFB)
    c = c + hexByte(0x31) + hexByte(0xC0)
    c = c + hexByte(0x80) + hexByte(0x3C) + hexByte(0x03) + hexByte(0x00)
    c = c + hexByte(0x74) + hexByte(0x04)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC0)
    c = c + hexByte(0xEB) + hexByte(245)        // -11 as unsigned
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC2)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDE)
    c = c + hexByte(0xBF) + hexDword(1)
    c = c + hexByte(0xB8) + hexDword(1)
    c = c + hexByte(0x0F) + hexByte(0x05)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krPrintSize() { emit 37 }

// _start: call __main__, then SYS_exit(0).
//   [0]  E8 disp32         CALL __main__                  (5)
//   [5]  31 FF             XOR EDI, EDI                   (2)
//   [7]  B8 3C 00 00 00    MOV EAX, 60                    (5)
//   [12] 0F 05             SYSCALL                        (2)
// Total: 14 bytes.
func startSize() { emit 14 }
func emitStartCode(callDisp) {
    let c = ""
    c = c + hexByte(0xE8) + hexDword(callDisp)
    c = c + hexByte(0x31) + hexByte(0xFF)
    c = c + hexByte(0xB8) + hexDword(60)
    c = c + hexByte(0x0F) + hexByte(0x05)
    emit c
}

// ── String table ───────────────────────────────────────────────────
// Strings are appended to the segment after all code.
// We collect them in a "values\nvalues\n..." list and refer by index.

// Append string s to table; returns "newTable\nindex"
func internStr(table, count, s) {
    // Search if already present
    let i = 0
    while i < count {
        if getLine(table, i) == s {
            emit table + "\n" + i
        }
        i += 1
    }
    // Not found, append
    let newTable = table
    if count > 0 { newTable = newTable + "\n" }
    newTable = newTable + s
    emit newTable + "\n" + count
}

// ── Pass 1: scan IR, intern strings, count code requirements ───────
// Produces: "stringTable\n---\nopList\n..."
// where opList is one line per IR op encoded as: OP_CODE arg
// OP_CODE: 1=PUSH_STR idx, 2=PUSH_INT n, 3=BUILTIN_KP, 4=POP, 5=END_FUNC

func parseIR(ir) {
    let strTab = ""
    let strCount = 0
    let opList = ""
    let opFirst = "1"

    let nl = lineCount(ir)
    let i = 0
    while i < nl {
        let line = trim(getLine(ir, i))
        if len(line) > 0 && line[0] != ";" {
            // Find the first space
            let j = 0
            while j < len(line) && line[j] != " " { j += 1 }
            let op = substring(line, 0, j)
            let rest = ""
            if j < len(line) { rest = trim(substring(line, j + 1, len(line))) }

            if op == "FUNC" {
                // FUNC name argcount — we only support __main__
                // No op emitted; main is implicit.
            } else if op == "PUSH" {
                if len(rest) > 0 && rest[0] == "\"" {
                    let parsed = parseQuoted(rest, 0)
                    let val = getLine(parsed, 0)
                    let interned = internStr(strTab, strCount, val)
                    let lc = lineCount(interned)
                    let idx = toInt(getLine(interned, lc - 1))
                    // table is everything except last line
                    let tabSb = sbNew()
                    let tk = 0
                    while tk < lc - 1 {
                        if tk > 0 { tabSb = sbAppend(tabSb, "\n") }
                        tabSb = sbAppend(tabSb, getLine(interned, tk))
                        tk += 1
                    }
                    strTab = sbToString(tabSb)
                    if idx >= strCount { strCount = idx + 1 }
                    if opFirst == "0" { opList = opList + "\n" }
                    opList = opList + "PUSH_STR " + idx
                    opFirst = "0"
                } else {
                    if opFirst == "0" { opList = opList + "\n" }
                    opList = opList + "PUSH_INT " + rest
                    opFirst = "0"
                }
            } else if op == "BUILTIN" {
                // BUILTIN name argcount
                let bj = 0
                while bj < len(rest) && rest[bj] != " " { bj += 1 }
                let bname = substring(rest, 0, bj)
                if bname == "kp" || bname == "print" {
                    if opFirst == "0" { opList = opList + "\n" }
                    opList = opList + "BUILTIN_KP"
                    opFirst = "0"
                } else {
                    // unsupported builtin — skip for now
                    if opFirst == "0" { opList = opList + "\n" }
                    opList = opList + "UNSUPPORTED " + bname
                    opFirst = "0"
                }
            } else if op == "POP" {
                if opFirst == "0" { opList = opList + "\n" }
                opList = opList + "POP"
                opFirst = "0"
            } else if op == "END" {
                if opFirst == "0" { opList = opList + "\n" }
                opList = opList + "END_FUNC"
                opFirst = "0"
            }
        }
        i += 1
    }
    emit strTab + "\n---\n" + opList
}

// ── Pass 2: emit code for __main__ ─────────────────────────────────
// We need to know string virtual addresses, so this is called after layout.

func emitMainCode(opList, strVAddrs) {
    let c = ""
    c = c + hexByte(0x55)                                             // PUSH RBP
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xE5)             // MOV RBP, RSP

    let nl = lineCount(opList)
    let i = 0
    while i < nl {
        let line = getLine(opList, i)
        let j = 0
        while j < len(line) && line[j] != " " { j += 1 }
        let op = substring(line, 0, j)
        let rest = ""
        if j < len(line) { rest = trim(substring(line, j + 1, len(line))) }

        if op == "PUSH_STR" {
            let idx = toInt(rest)
            let vaddr = toInt(getLine(strVAddrs, idx))
            // MOV RDI, vaddr  ; PUSH RDI
            c = c + hexByte(0x48) + hexByte(0xBF) + hexQword(vaddr)
            c = c + hexByte(0x57)
        } else if op == "PUSH_INT" {
            let n = toInt(rest)
            c = c + hexByte(0x48) + hexByte(0xBF) + hexQword(n)
            c = c + hexByte(0x57)
        } else if op == "BUILTIN_KP" {
            // Pop arg into RDI, call kr_print.
            c = c + hexByte(0x5F)                                     // POP RDI
            // CALL kr_print — disp filled by caller (placeholder + patch)
            // We use a marker: emit 5 bytes 90 + dword that the caller patches.
            // Simpler: encode as CALL with a placeholder disp, fix afterwards via second pass.
            // For now, we know the address stitching happens above; we'll patch in main().
            c = c + hexByte(0xE8) + hexDword(0)                       // CALL placeholder
            // After CALL, push the result (kr_print returns void; push 0)
            c = c + hexByte(0x6A) + hexByte(0x00)                     // PUSH 0
        } else if op == "POP" {
            c = c + hexByte(0x5F)                                     // POP RDI (discard)
        } else if op == "END_FUNC" {
            c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xEC)     // MOV RSP, RBP
            c = c + hexByte(0x5D)                                     // POP RBP
            c = c + hexByte(0xC3)                                     // RET
        }
        i += 1
    }
    emit c
}

// ── Driver (just run gives us argc/argv plumbing) ──────────────────

just run {
    let inFile = arg("0")
    let outFile = arg("1")
    if len(inFile) == 0 || len(outFile) == 0 {
        printErr("usage: kcc kompiler/elf.k input.kir output.elf")
        exit("1")
    }

    let ir = readFile(inFile)
    if len(ir) == 0 {
        printErr("elf: cannot read " + inFile)
        exit("1")
    }

    let parsed = parseIR(ir)
    // Split parsed at "---"
    let pn = lineCount(parsed)
    let strTab = ""
    let opList = ""
    let inOps = "0"
    let pi = 0
    while pi < pn {
        let pl = getLine(parsed, pi)
        if pl == "---" {
            inOps = "1"
        } else if inOps == "0" {
            if len(strTab) > 0 { strTab = strTab + "\n" }
            strTab = strTab + pl
        } else {
            if len(opList) > 0 { opList = opList + "\n" }
            opList = opList + pl
        }
        pi += 1
    }

    let strCount = 0
    if len(strTab) > 0 { strCount = lineCount(strTab) }

    // ── Layout ──────────────────────────────────────────────────────
    //   header (120 bytes) + _start + main + kr_print + strings
    let VADDR_BASE = 4194304       // 0x400000
    let HDR_SIZE = 120
    let SEG_BASE_VADDR = VADDR_BASE + HDR_SIZE

    let startSz = startSize()
    let krpSz = krPrintSize()

    // First, emit main without knowing kr_print's vaddr (we'll patch via deterministic offsets).
    // But we DO know layout by the time we emit:
    //   _start at [HDR_SIZE]
    //   __main__ at [HDR_SIZE + startSz]
    //   kr_print at [HDR_SIZE + startSz + main_size]
    //   strings at [HDR_SIZE + startSz + main_size + krpSz]
    //
    // We need main_size to know where kr_print lives, but main needs to know kr_print's vaddr.
    // Solution: emit main TWICE — once with fake address to learn its size, once for real.

    // Build placeholder string vaddrs for size measurement
    let phVAddrs = ""
    let pj = 0
    while pj < strCount {
        if pj > 0 { phVAddrs = phVAddrs + "\n" }
        phVAddrs = phVAddrs + "0"
        pj += 1
    }

    let mainProbe = emitMainCode(opList, phVAddrs)
    let mainSize = hexBytesLen(mainProbe)

    let mainVAddr = SEG_BASE_VADDR + startSz
    let krPrintVAddr = mainVAddr + mainSize

    // String virtual addresses
    let stringsBase = krPrintVAddr + krpSz
    let strVAddrs = ""
    let strData = ""
    let curOff = 0
    let si = 0
    while si < strCount {
        let sv = getLine(strTab, si)
        if si > 0 { strVAddrs = strVAddrs + "\n" }
        strVAddrs = strVAddrs + (stringsBase + curOff)
        strData = strData + hexStr(sv) + hexByte(0)
        curOff = curOff + len(sv) + 1
        si += 1
    }

    // Real main with correct string vaddrs
    let mainCodeRaw = emitMainCode(opList, strVAddrs)

    // Now patch CALL placeholders (E8 00 00 00 00 followed by 6A 00) to real disps.
    let patchedSb = sbNew()
    let ml = hexBytesLen(mainCodeRaw)
    let mi = 0
    // Note: substring is essential — Krypton's `+` does numeric add when both
    // operands look numeric (e.g. "5"+"5" → 10), so char-by-char concat
    // mangles hex digits. substring keeps it pure string.
    while mi < ml {
        let triple = substring(mainCodeRaw, mi*3, mi*3 + 3)   // "xHH"
        let b = substring(triple, 1, 3)                        // "HH"
        let isCall = "0"
        if b == "E8" && mi + 6 < ml {
            let z1 = substring(mainCodeRaw, (mi+1)*3 + 1, (mi+1)*3 + 3)
            let z2 = substring(mainCodeRaw, (mi+2)*3 + 1, (mi+2)*3 + 3)
            let z3 = substring(mainCodeRaw, (mi+3)*3 + 1, (mi+3)*3 + 3)
            let z4 = substring(mainCodeRaw, (mi+4)*3 + 1, (mi+4)*3 + 3)
            let p1 = substring(mainCodeRaw, (mi+5)*3 + 1, (mi+5)*3 + 3)
            let p2 = substring(mainCodeRaw, (mi+6)*3 + 1, (mi+6)*3 + 3)
            if z1 == "00" && z2 == "00" && z3 == "00" && z4 == "00" && p1 == "6A" && p2 == "00" {
                isCall = "1"
            }
        }
        if isCall == "1" {
            let ripAfter = mainVAddr + mi + 5
            let disp = krPrintVAddr - ripAfter
            patchedSb = sbAppend(patchedSb, hexByte(0xE8))
            patchedSb = sbAppend(patchedSb, hexDword(disp))
            mi = mi + 5
        } else {
            patchedSb = sbAppend(patchedSb, triple)
            mi = mi + 1
        }
    }
    let mainCode = sbToString(patchedSb)

    // _start: CALL __main__ — disp = mainVAddr - (start_vaddr + 5)
    let startVAddr = SEG_BASE_VADDR
    let startCallDisp = mainVAddr - (startVAddr + 5)
    let startCode = emitStartCode(startCallDisp)

    let krPrintCode = emitKrPrintCode()

    let segment = startCode + mainCode + krPrintCode + strData
    let segSize = hexBytesLen(segment)
    let fileSize = HDR_SIZE + segSize

    // ── ELF64 header ─────────────────────────────────────────────────
    let entry = startVAddr
    let eh = ""
    eh = eh + hexByte(0x7F) + hexByte(0x45) + hexByte(0x4C) + hexByte(0x46)
    eh = eh + hexByte(2) + hexByte(1) + hexByte(1) + hexByte(0)
    eh = eh + hexPad(8)
    eh = eh + hexWord(2)             // ET_EXEC
    eh = eh + hexWord(0x3E)          // EM_X86_64
    eh = eh + hexDword(1)
    eh = eh + hexQword(entry)
    eh = eh + hexQword(64)
    eh = eh + hexQword(0)
    eh = eh + hexDword(0)
    eh = eh + hexWord(64) + hexWord(56) + hexWord(1)
    eh = eh + hexWord(0) + hexWord(0) + hexWord(0)

    let ph = ""
    ph = ph + hexDword(1)              // PT_LOAD
    ph = ph + hexDword(5)              // R+X
    ph = ph + hexQword(0)
    ph = ph + hexQword(VADDR_BASE)
    ph = ph + hexQword(VADDR_BASE)
    ph = ph + hexQword(fileSize)
    ph = ph + hexQword(fileSize)
    ph = ph + hexQword(0x1000)

    let elfBytes = eh + ph + segment
    writeBytes(outFile, elfBytes)
    printErr("elf: wrote " + outFile + " (" + (len(elfBytes) / 3) + " bytes, " + strCount + " strings)")
}
