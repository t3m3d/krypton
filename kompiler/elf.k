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

// Inter-block separator: SOH (0x01) — Krypton's lexer doesn't process "\r" escape,
// so we manufacture a guaranteed-unique single byte that won't appear in IR/strings.
func sepChar() { emit fromCharCode("1") }

// Extract block at index `idx` from a sepChar()-separated string. Returns "" if not found.
// Krypton's `||` does NOT short-circuit reliably for array-index accesses, so we use
// nested ifs with explicit boundary checks.
func extractBlock(s, idx) {
    let n = len(s)
    let bIdx = 0
    let bStart = 0
    let i = 0
    let sep = sepChar()
    while i <= n {
        let isBoundary = "0"
        if i == n { isBoundary = "1" }
        if i < n {
            if s[i] == sep { isBoundary = "1" }
        }
        if isBoundary == "1" {
            if bIdx == idx { emit substring(s, bStart, i) }
            bIdx += 1
            bStart = i + 1
        }
        i += 1
    }
    emit ""
}

// ── IR parsing helpers ─────────────────────────────────────────────

// Strip leading whitespace; return rest
func skipWs(s, i) {
    while i < len(s) && (s[i] == " " || s[i] == "\t") { i += 1 }
    emit i + ""
}

// Parse a quoted string literal starting at index i (must point at the opening ")
// Returns: "value\noff_after_close_quote"
//
// Use sbAppend rather than `v + s[i]` to avoid Krypton's numeric-+ coercion trap
// (e.g. "1" + "2" → 3 instead of "12" for digit-only chars).
func parseQuoted(s, i) {
    let vSb = sbNew()
    i += 1  // skip opening "
    while i < len(s) && s[i] != "\"" {
        if s[i] == "\\" && i + 1 < len(s) {
            let c = s[i + 1]
            if c == "n" { vSb = sbAppend(vSb, "\n") }
            else if c == "t" { vSb = sbAppend(vSb, "\t") }
            else if c == "r" { vSb = sbAppend(vSb, "\r") }
            else if c == "\\" { vSb = sbAppend(vSb, "\\") }
            else if c == "\"" { vSb = sbAppend(vSb, "\"") }
            else if c == "0" { }  // skip null escape
            else { vSb = sbAppend(vSb, c) }
            i += 2
        } else {
            vSb = sbAppend(vSb, s[i])
            i += 1
        }
    }
    if i < len(s) { i += 1 }  // skip closing "
    let v = sbToString(vSb)
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

// kr_alloc: bump allocator using R15 (heap_next).
//   In:  RDI = size in bytes
//   Out: RAX = pointer to allocated block
//
// Layout (7 bytes):
//   [0]  4C 89 F8         MOV RAX, R15          (3)
//   [3]  49 01 FF         ADD R15, RDI          (3)
//   [6]  C3               RET                   (1)
func emitKrAllocCode() {
    let c = ""
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xF8)
    c = c + hexByte(0x49) + hexByte(0x01) + hexByte(0xFF)
    c = c + hexByte(0xC3)
    emit c
}
func krAllocSize() { emit 7 }

// kr_strlen: count bytes until NUL.
//   In:  RDI = string ptr
//   Out: RAX = length
//
// Layout (14 bytes):
//   [0]  31 C0          XOR EAX, EAX               (2)
//   [2]  80 3C 07 00    CMP byte [RDI+RAX], 0      (4)
//   [6]  74 04          JZ +4 → 12 (.done)         (2)
//   [8]  48 FF C0       INC RAX                    (3)
//   [11] EB F5          JMP -11 → 2 (.loop)        (2)
//   [13] C3             RET                        (1)
func emitKrStrlenCode() {
    let c = ""
    c = c + hexByte(0x31) + hexByte(0xC0)
    c = c + hexByte(0x80) + hexByte(0x3C) + hexByte(0x07) + hexByte(0x00)
    c = c + hexByte(0x74) + hexByte(0x04)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC0)
    c = c + hexByte(0xEB) + hexByte(256 - 11)
    c = c + hexByte(0xC3)
    emit c
}
func krStrlenSize() { emit 14 }

// kr_concat: concatenate two args. Auto-converts int args (< 0x400000) to strings via kr_str_int.
//   In:  RDI = a (string ptr OR small int), RSI = b (same)
//   Out: RAX = ptr to fresh "ab" allocated from heap
//
// Layout (118 bytes):
//   [0-4]   prologue (PUSH RBX, R12, R13)
//   [5-10]  save args: R12=a, R13=b
//   [11-30] convert a if int (CMP+JAE+kr_str_int call)
//   [31-50] convert b if int (same pattern)
//   [51-79] strlen×2 + alloc(la+lb+1)
//   [80-94] REP MOVSB copy a
//   [95-110] byte-loop copy b until NUL
//   [111-117] epilogue
func emitKrConcatCodeFinal(thisVAddr, strIntVAddr, strlenVAddr, allocVAddr) {
    let dStrInt1 = strIntVAddr - (thisVAddr + 28)
    let dStrInt2 = strIntVAddr - (thisVAddr + 48)
    let dStrlen1 = strlenVAddr - (thisVAddr + 59)
    let dStrlen2 = strlenVAddr - (thisVAddr + 70)
    let dAlloc   = allocVAddr  - (thisVAddr + 80)
    let c = ""
    c = c + hexByte(0x53)                                                    // [0]   PUSH RBX
    c = c + hexByte(0x41) + hexByte(0x54)                                    // [1-2] PUSH R12
    c = c + hexByte(0x41) + hexByte(0x55)                                    // [3-4] PUSH R13
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xFC)                    // [5-7] MOV R12, RDI (a)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xF5)                    // [8-10] MOV R13, RSI (b)
    // Convert a (R12) if it's a small int
    c = c + hexByte(0x49) + hexByte(0x81) + hexByte(0xFC) + hexDword(0x400000) // [11-17] CMP R12, 0x400000
    c = c + hexByte(0x73) + hexByte(0x0B)                                    // [18-19] JAE +11 → 31 (.a_ok)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)                    // [20-22] MOV RDI, R12
    c = c + hexByte(0xE8) + hexDword(dStrInt1)                               // [23-27] CALL kr_str_int
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC4)                    // [28-30] MOV R12, RAX
    // .a_ok (31): convert b (R13) if it's a small int
    c = c + hexByte(0x49) + hexByte(0x81) + hexByte(0xFD) + hexDword(0x400000) // [31-37] CMP R13, 0x400000
    c = c + hexByte(0x73) + hexByte(0x0B)                                    // [38-39] JAE +11 → 51 (.b_ok)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xEF)                    // [40-42] MOV RDI, R13
    c = c + hexByte(0xE8) + hexDword(dStrInt2)                               // [43-47] CALL kr_str_int
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC5)                    // [48-50] MOV R13, RAX
    // .b_ok (51): now do the regular concat with R12=a, R13=b
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)                    // [51-53] MOV RDI, R12
    c = c + hexByte(0xE8) + hexDword(dStrlen1)                               // [54-58] CALL kr_strlen → la
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC3)                    // [59-61] MOV RBX, RAX (la)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xEF)                    // [62-64] MOV RDI, R13
    c = c + hexByte(0xE8) + hexDword(dStrlen2)                               // [65-69] CALL kr_strlen → lb
    c = c + hexByte(0x48) + hexByte(0x8D) + hexByte(0x7C) + hexByte(0x18) + hexByte(0x01) // [70-74] LEA RDI, [RAX+RBX+1]
    c = c + hexByte(0xE8) + hexDword(dAlloc)                                 // [75-79] CALL kr_alloc → dest
    c = c + hexByte(0x50)                                                    // [80] PUSH RAX (save dest)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC7)                    // [81-83] MOV RDI, RAX
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE6)                    // [84-86] MOV RSI, R12 (a)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xD9)                    // [87-89] MOV RCX, RBX (la)
    c = c + hexByte(0xF3) + hexByte(0xA4)                                    // [90-91] REP MOVSB
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xEE)                    // [92-94] MOV RSI, R13 (b)
    // .cp_b (95):
    c = c + hexByte(0x8A) + hexByte(0x06)                                    // [95-96] MOV AL, [RSI]
    c = c + hexByte(0x84) + hexByte(0xC0)                                    // [97-98] TEST AL, AL
    c = c + hexByte(0x74) + hexByte(0x0A)                                    // [99-100] JZ +10 → 111 (.done)
    c = c + hexByte(0x88) + hexByte(0x07)                                    // [101-102] MOV [RDI], AL
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7)                    // [103-105] INC RDI
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC6)                    // [106-108] INC RSI
    c = c + hexByte(0xEB) + hexByte(256 - 16)                                // [109-110] JMP -16 → 95
    // .done (111):
    c = c + hexByte(0x58)                                                    // [111] POP RAX
    c = c + hexByte(0x41) + hexByte(0x5D)                                    // [112-113] POP R13
    c = c + hexByte(0x41) + hexByte(0x5C)                                    // [114-115] POP R12
    c = c + hexByte(0x5B)                                                    // [116] POP RBX
    c = c + hexByte(0xC3)                                                    // [117] RET
    emit c
}
func krConcatSize() { emit 118 }

// kr_atoi: parse integer from string. If RDI is already an int (< 0x400000), return as-is.
//   In:  RDI = arg
//   Out: RAX = int value
//
// Layout (~64 bytes):
//   [0-6]   48 81 FF 00 00 40 00   CMP RDI, 0x400000        (7)
//   [7-8]   73 04                  JAE +4 → 13 (.parse)     (2)
//   [9-11]  48 89 F8               MOV RAX, RDI             (3)
//   [12]    C3                     RET                      (1)
// .parse at 13:
//   [13-14] 31 C0                  XOR EAX, EAX             (2)
//   [15-17] 45 31 C0               XOR R8D, R8D             (3)  ; sign flag
//   [18-20] 80 3F 2D               CMP byte [RDI], '-'      (3)
//   [21-22] 75 06                  JNE +6 → 29 (.digits)    (2)
//   [23-25] 48 FF C7               INC RDI                  (3)
//   [26-28] 41 FF C0               INC R8D                  (3)
// .digits at 29:
//   [29-30] 8A 0F                  MOV CL, [RDI]            (2)
//   [31-32] 84 C9                  TEST CL, CL              (2)
//   [33-34] 74 1B                  JZ +27 → 62 (.done)      (2)
//   [35-37] 80 F9 30               CMP CL, '0'              (3)
//   [38-39] 7C 16                  JL +22 → 62              (2)
//   [40-42] 80 F9 39               CMP CL, '9'              (3)
//   [43-44] 7F 11                  JG +17 → 62              (2)
//   [45-47] 80 E9 30               SUB CL, '0'              (3)
//   [48-51] 48 6B C0 0A            IMUL RAX, RAX, 10        (4)
//   [52-55] 48 0F B6 D1            MOVZX RDX, CL            (4)
//   [56-58] 48 01 D0               ADD RAX, RDX             (3)
//   [59-61] 48 FF C7               INC RDI                  (3)
//   [62-63] EB CB                  JMP -53 → 29 (.digits)   (2)
//
// Hmm offsets don't align — .done should NOT be at 62 (that's the JMP back). Let me recompute.
// Real layout:
//   [29-30] MOV CL, [RDI]                              (2)
//   [31-32] TEST CL, CL                                (2)
//   [33-34] JZ → .done                                 (2)
//   [35-37] CMP CL, '0'                                (3)
//   [38-39] JL → .done                                 (2)
//   [40-42] CMP CL, '9'                                (3)
//   [43-44] JG → .done                                 (2)
//   [45-47] SUB CL, '0'                                (3)
//   [48-51] IMUL RAX, RAX, 10                          (4)
//   [52-55] MOVZX RDX, CL                              (4)
//   [56-58] ADD RAX, RDX                               (3)
//   [59-61] INC RDI                                    (3)
//   [62-63] JMP -35 → 29 (.digits)                     (2)  ; after JMP at 64, target = 64-35 = 29
// .done at 64:
//   [64-66] 45 85 C0               TEST R8D, R8D       (3)
//   [67-68] 74 03                  JZ +3 → 72 (.ret)   (2)
//   [69-71] 48 F7 D8               NEG RAX             (3)
// .ret at 72:
//   [72]    C3                     RET                 (1)
// Total: 73 bytes
//
// JZ .done from [33-34] (after at 35): target 64. disp = 64-35 = 29 = 0x1D
// JL .done from [38-39] (after at 40): target 64. disp = 64-40 = 24 = 0x18
// JG .done from [43-44] (after at 45): target 64. disp = 64-45 = 19 = 0x13
// JMP .digits from [62-63] (after at 64): target 29. disp = 29-64 = -35 = 0xDD
func emitKrAtoiCode() {
    let c = ""
    c = c + hexByte(0x48) + hexByte(0x81) + hexByte(0xFF) + hexDword(0x400000)
    c = c + hexByte(0x73) + hexByte(0x04)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xF8)
    c = c + hexByte(0xC3)
    c = c + hexByte(0x31) + hexByte(0xC0)
    c = c + hexByte(0x45) + hexByte(0x31) + hexByte(0xC0)
    c = c + hexByte(0x80) + hexByte(0x3F) + hexByte(0x2D)
    c = c + hexByte(0x75) + hexByte(0x06)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7)
    c = c + hexByte(0x41) + hexByte(0xFF) + hexByte(0xC0)
    c = c + hexByte(0x8A) + hexByte(0x0F)
    c = c + hexByte(0x84) + hexByte(0xC9)
    c = c + hexByte(0x74) + hexByte(0x1D)
    c = c + hexByte(0x80) + hexByte(0xF9) + hexByte(0x30)
    c = c + hexByte(0x7C) + hexByte(0x18)
    c = c + hexByte(0x80) + hexByte(0xF9) + hexByte(0x39)
    c = c + hexByte(0x7F) + hexByte(0x13)
    c = c + hexByte(0x80) + hexByte(0xE9) + hexByte(0x30)
    c = c + hexByte(0x48) + hexByte(0x6B) + hexByte(0xC0) + hexByte(0x0A)
    c = c + hexByte(0x48) + hexByte(0x0F) + hexByte(0xB6) + hexByte(0xD1)
    c = c + hexByte(0x48) + hexByte(0x01) + hexByte(0xD0)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7)
    c = c + hexByte(0xEB) + hexByte(256 - 35)
    c = c + hexByte(0x45) + hexByte(0x85) + hexByte(0xC0)
    c = c + hexByte(0x74) + hexByte(0x03)
    c = c + hexByte(0x48) + hexByte(0xF7) + hexByte(0xD8)
    c = c + hexByte(0xC3)
    emit c
}
func krAtoiSize() { emit 73 }

// kr_length: count comma-separated elements in a Krypton list string.
//   In:  RDI = list string
//   Out: RAX = count (0 if empty, else 1 + comma count)
//
// Layout (28 bytes):
//   [0-1]   31 C0            XOR EAX, EAX                  (2)
//   [2-4]   80 3F 00         CMP byte [RDI], 0             (3)
//   [5-6]   74 14            JZ +20 → 27 (.ret)            (2)
//   [7-8]   FF C0            INC EAX                       (2)
// .loop at 9:
//   [9-10]  8A 0F            MOV CL, [RDI]                 (2)
//   [11-12] 84 C9            TEST CL, CL                   (2)
//   [13-14] 74 0C            JZ +12 → 27 (.ret)            (2)
//   [15-17] 80 F9 2C         CMP CL, ','                   (3)
//   [18-19] 75 02            JNE +2 → 22 (.skip)           (2)
//   [20-21] FF C0            INC EAX                       (2)
// .skip at 22:
//   [22-24] 48 FF C7         INC RDI                       (3)
//   [25-26] EB EE            JMP -18 → 9                   (2)
// .ret at 27:
//   [27]    C3               RET                           (1)
func emitKrLengthCode() {
    let c = ""
    c = c + hexByte(0x31) + hexByte(0xC0)
    c = c + hexByte(0x80) + hexByte(0x3F) + hexByte(0x00)
    c = c + hexByte(0x74) + hexByte(0x14)
    c = c + hexByte(0xFF) + hexByte(0xC0)
    c = c + hexByte(0x8A) + hexByte(0x0F)
    c = c + hexByte(0x84) + hexByte(0xC9)
    c = c + hexByte(0x74) + hexByte(0x0C)
    c = c + hexByte(0x80) + hexByte(0xF9) + hexByte(0x2C)
    c = c + hexByte(0x75) + hexByte(0x02)
    c = c + hexByte(0xFF) + hexByte(0xC0)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7)
    c = c + hexByte(0xEB) + hexByte(256 - 18)
    c = c + hexByte(0xC3)
    emit c
}
func krLengthSize() { emit 28 }

// kr_split: extract idx-th comma-separated element from a list string.
//   In:  RDI = list string ptr, RSI = idx (string or already-int)
//   Out: RAX = ptr to fresh heap-allocated element string
//
// Layout (113 bytes):
//   [0]     53                PUSH RBX                                     (1)
//   [1-2]   41 54             PUSH R12                                     (2)
//   [3-4]   41 55             PUSH R13                                     (2)
//   [5-7]   49 89 FC          MOV R12, RDI            (save s)             (3)
//   [8-10]  48 89 F7          MOV RDI, RSI                                 (3)
//   [11-15] E8 dw             CALL kr_atoi                                 (5)
//   [16-18] 49 89 C5          MOV R13, RAX            (remaining = idx)    (3)
//   [19-21] 4C 89 E7          MOV RDI, R12            (current ptr)        (3)
// .skip at 22:
//   [22-24] 4D 85 ED          TEST R13, R13                                (3)
//   [25-26] 74 0D             JZ +13 → 40 (.scan_setup)                    (2)
//   [27-28] 8A 07             MOV AL, [RDI]                                (2)
//   [29-30] 84 C0             TEST AL, AL                                  (2)
//   [31-32] 74 40             JZ +64 → 97 (.empty)                         (2)
//   [33-35] 48 FF C7          INC RDI                                      (3)
//   [36-37] 3C 2C             CMP AL, ','                                  (2)
//   [38-39] 75 EE             JNE -18 → 22 (.skip)                         (2)
//   [40-42] 49 FF CD          DEC R13                                      (3)
//   [43-44] EB E9             JMP -23 → 22 (.skip)                         (2)
// .scan_setup at 45:
//   [45-47] 48 89 FB          MOV RBX, RDI            (element start)      (3)
// .scan at 48:
//   [48-49] 8A 07             MOV AL, [RDI]                                (2)
//   [50-51] 84 C0             TEST AL, AL                                  (2)
//   [52-53] 74 08             JZ +8 → 63 (.got_end)                        (2)
//   [54-55] 3C 2C             CMP AL, ','                                  (2)
//   [56-57] 74 04             JE +4 → 63 (.got_end)                        (2)
//   [58-60] 48 FF C7          INC RDI                                      (3)
//   [61-62] EB F1             JMP -15 → 48 (.scan)                         (2)
// .got_end at 63:
//   [63-65] 4C 89 FD          MOV R13, RDI            (end ptr)            (3)
//   [66-68] 4D 29 DD          SUB R13, RBX            (length)             (3)
//   [69-72] 49 8D 7D 01       LEA RDI, [R13+1]                             (4)
//   [73-77] E8 dw             CALL kr_alloc                                (5)
//   [78]    50                PUSH RAX                (save dest_start)    (1)
//   [79-81] 48 89 C7          MOV RDI, RAX                                 (3)
//   [82-84] 48 89 DE          MOV RSI, RBX                                 (3)
//   [85-87] 4C 89 E9          MOV RCX, R13                                 (3)
//   [88-89] F3 A4             REP MOVSB                                    (2)
//   [90]    58                POP RAX                                      (1)
//   [91-92] 41 5D             POP R13                                      (2)
//   [93-94] 41 5C             POP R12                                      (2)
//   [95]    5B                POP RBX                                      (1)
//   [96]    C3                RET                                          (1)
// .empty at 97:
//   [97-101] BF 01 00 00 00   MOV EDI, 1                                   (5)
//   [102-106] E8 dw           CALL kr_alloc                                (5)
//   [107-108] 41 5D           POP R13                                      (2)
//   [109-110] 41 5C           POP R12                                      (2)
//   [111]    5B               POP RBX                                      (1)
//   [112]    C3               RET                                          (1)
func emitKrSplitCodeFinal(thisVAddr, atoiVAddr, allocVAddr) {
    let dAtoi   = atoiVAddr  - (thisVAddr + 16)
    let dAlloc1 = allocVAddr - (thisVAddr + 78)
    let dAlloc2 = allocVAddr - (thisVAddr + 107)
    let c = ""
    c = c + hexByte(0x53)
    c = c + hexByte(0x41) + hexByte(0x54)
    c = c + hexByte(0x41) + hexByte(0x55)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xFC)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xF7)
    c = c + hexByte(0xE8) + hexDword(dAtoi)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC5)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)
    c = c + hexByte(0x4D) + hexByte(0x85) + hexByte(0xED)
    c = c + hexByte(0x74) + hexByte(0x12)   // JZ +18 → .scan_setup at 45
    c = c + hexByte(0x8A) + hexByte(0x07)
    c = c + hexByte(0x84) + hexByte(0xC0)
    c = c + hexByte(0x74) + hexByte(0x40)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7)
    c = c + hexByte(0x3C) + hexByte(0x2C)
    c = c + hexByte(0x75) + hexByte(256 - 18)
    c = c + hexByte(0x49) + hexByte(0xFF) + hexByte(0xCD)
    c = c + hexByte(0xEB) + hexByte(256 - 23)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xFB)
    c = c + hexByte(0x8A) + hexByte(0x07)
    c = c + hexByte(0x84) + hexByte(0xC0)
    c = c + hexByte(0x74) + hexByte(0x09)   // JZ +9 → .got_end (was off-by-one)
    c = c + hexByte(0x3C) + hexByte(0x2C)
    c = c + hexByte(0x74) + hexByte(0x05)   // JE +5 → .got_end (was off-by-one)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7)
    c = c + hexByte(0xEB) + hexByte(256 - 15)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xFD)   // MOV R13, RDI
    c = c + hexByte(0x49) + hexByte(0x29) + hexByte(0xDD)   // SUB R13, RBX (was wrong REX)
    c = c + hexByte(0x49) + hexByte(0x8D) + hexByte(0x7D) + hexByte(0x01)
    c = c + hexByte(0xE8) + hexDword(dAlloc1)
    c = c + hexByte(0x50)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC7)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDE)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE9)
    c = c + hexByte(0xF3) + hexByte(0xA4)
    c = c + hexByte(0x58)
    c = c + hexByte(0x41) + hexByte(0x5D)
    c = c + hexByte(0x41) + hexByte(0x5C)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    c = c + hexByte(0xBF) + hexDword(1)
    c = c + hexByte(0xE8) + hexDword(dAlloc2)
    c = c + hexByte(0x41) + hexByte(0x5D)
    c = c + hexByte(0x41) + hexByte(0x5C)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krSplitSize() { emit 113 }

// kr_range: build comma-separated list "a,a+1,...,b-1".
//   In:  RDI = a (start), RSI = b (end)
//   Out: RAX = ptr to fresh "a,a+1,...,b-1" or "" if a >= b
//
// Strategy: atoi both, alloc (end-start)*12+1 bytes (12 = max digits for any int we'll see),
// loop calling kr_str_int for each i and copying digits + comma. Last iteration skips comma.
//
// Layout (135 bytes):
//   [0]      53                PUSH RBX                          (1)
//   [1-2]    41 54             PUSH R12                          (2)
//   [3-4]    41 55             PUSH R13                          (2)
//   [5-6]    41 56             PUSH R14                          (2)
//   [7-11]   E8 dw             CALL kr_atoi   (RDI=a still)      (5)
//   [12-14]  49 89 C4          MOV R12, RAX   (start)            (3)
//   [15-17]  48 89 F7          MOV RDI, RSI                      (3)
//   [18-22]  E8 dw             CALL kr_atoi                      (5)
//   [23-25]  49 89 C5          MOV R13, RAX   (end)              (3)
//   [26-28]  4D 39 EC          CMP R12, R13                      (3)
//   [29-30]  7D 56             JGE +86 → 117 (.empty)            (2)
//   [31-33]  4C 89 E8          MOV RAX, R13                      (3)
//   [34-36]  4C 29 E0          SUB RAX, R12                      (3)
//   [37-40]  48 6B C0 0C       IMUL RAX, RAX, 12                 (4)
//   [41-43]  48 FF C0          INC RAX                           (3)
//   [44-46]  48 89 C7          MOV RDI, RAX                      (3)
//   [47-51]  E8 dw             CALL kr_alloc                     (5)
//   [52-54]  48 89 C3          MOV RBX, RAX   (write ptr)        (3)
//   [55-57]  49 89 C6          MOV R14, RAX   (saved buf start)  (3)
// .loop at 58:
//   [58-60]  4D 39 EC          CMP R12, R13                      (3)
//   [61-62]  7D 2B             JGE +43 → 106 (.done)             (2)
//   [63-65]  4C 89 E7          MOV RDI, R12                      (3)
//   [66-70]  E8 dw             CALL kr_str_int                   (5)
//   [71-73]  48 89 C6          MOV RSI, RAX                      (3)
// .copy at 74:
//   [74-75]  8A 0E             MOV CL, [RSI]                     (2)
//   [76-77]  84 C9             TEST CL, CL                       (2)
//   [78-79]  74 0A             JZ +10 → 90 (.add_comma)          (2)
//   [80-81]  88 0B             MOV [RBX], CL                     (2)
//   [82-84]  48 FF C3          INC RBX                           (3)
//   [85-87]  48 FF C6          INC RSI                           (3)
//   [88-89]  EB F0             JMP -16 → 74 (.copy)              (2)
// .add_comma at 90:
//   [90-92]  49 FF C4          INC R12                           (3)
//   [93-95]  4D 39 EC          CMP R12, R13                      (3)
//   [96-97]  7D D8             JGE -40 → 58 (.loop)              (2)  ; last iter
//   [98-100] C6 03 2C          MOV byte [RBX], ','               (3)
//   [101-103] 48 FF C3         INC RBX                           (3)
//   [104-105] EB D0            JMP -48 → 58 (.loop)              (2)
// .done at 106:
//   [106-108] 4C 89 F0         MOV RAX, R14                      (3)
//   [109-110] 41 5E            POP R14                           (2)
//   [111-112] 41 5D            POP R13                           (2)
//   [113-114] 41 5C            POP R12                           (2)
//   [115]    5B                POP RBX                           (1)
//   [116]    C3                RET                               (1)
// .empty at 117:
//   [117-121] BF 01 00 00 00   MOV EDI, 1                        (5)
//   [122-126] E8 dw            CALL kr_alloc                     (5)
//   [127-128] 41 5E            POP R14                           (2)
//   [129-130] 41 5D            POP R13                           (2)
//   [131-132] 41 5C            POP R12                           (2)
//   [133]    5B                POP RBX                           (1)
//   [134]    C3                RET                               (1)
func emitKrRangeCodeFinal(thisVAddr, atoiVAddr, allocVAddr, strIntVAddr) {
    let dAtoi1 = atoiVAddr   - (thisVAddr + 12)
    let dAtoi2 = atoiVAddr   - (thisVAddr + 23)
    let dAlloc1 = allocVAddr - (thisVAddr + 52)
    let dStrInt = strIntVAddr - (thisVAddr + 71)
    let dAlloc2 = allocVAddr - (thisVAddr + 127)
    let c = ""
    c = c + hexByte(0x53)
    c = c + hexByte(0x41) + hexByte(0x54)
    c = c + hexByte(0x41) + hexByte(0x55)
    c = c + hexByte(0x41) + hexByte(0x56)
    c = c + hexByte(0xE8) + hexDword(dAtoi1)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC4)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xF7)
    c = c + hexByte(0xE8) + hexDword(dAtoi2)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC5)
    c = c + hexByte(0x4D) + hexByte(0x39) + hexByte(0xEC)
    c = c + hexByte(0x7D) + hexByte(0x56)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE8)
    c = c + hexByte(0x4C) + hexByte(0x29) + hexByte(0xE0)
    c = c + hexByte(0x48) + hexByte(0x6B) + hexByte(0xC0) + hexByte(0x0C)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC0)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC7)
    c = c + hexByte(0xE8) + hexDword(dAlloc1)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC3)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC6)
    c = c + hexByte(0x4D) + hexByte(0x39) + hexByte(0xEC)
    c = c + hexByte(0x7D) + hexByte(0x2B)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)
    c = c + hexByte(0xE8) + hexDword(dStrInt)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC6)
    c = c + hexByte(0x8A) + hexByte(0x0E)
    c = c + hexByte(0x84) + hexByte(0xC9)
    c = c + hexByte(0x74) + hexByte(0x0A)
    c = c + hexByte(0x88) + hexByte(0x0B)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC3)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC6)
    c = c + hexByte(0xEB) + hexByte(256 - 16)
    c = c + hexByte(0x49) + hexByte(0xFF) + hexByte(0xC4)
    c = c + hexByte(0x4D) + hexByte(0x39) + hexByte(0xEC)
    c = c + hexByte(0x7D) + hexByte(256 - 40)
    c = c + hexByte(0xC6) + hexByte(0x03) + hexByte(0x2C)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC3)
    c = c + hexByte(0xEB) + hexByte(256 - 48)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xF0)
    c = c + hexByte(0x41) + hexByte(0x5E)
    c = c + hexByte(0x41) + hexByte(0x5D)
    c = c + hexByte(0x41) + hexByte(0x5C)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    c = c + hexByte(0xBF) + hexDword(1)
    c = c + hexByte(0xE8) + hexDword(dAlloc2)
    c = c + hexByte(0x41) + hexByte(0x5E)
    c = c + hexByte(0x41) + hexByte(0x5D)
    c = c + hexByte(0x41) + hexByte(0x5C)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krRangeSize() { emit 135 }

// kr_index: return s[i] as a 1-char NUL-terminated string.
//   In:  RDI = string ptr, RSI = idx (string or int)
//   Out: RAX = ptr to fresh 2-byte heap-allocated string [s[i], 0]
//
// Layout (36 bytes):
//   [0]    53               PUSH RBX                          (1)
//   [1-2]  41 54            PUSH R12                          (2)
//   [3-5]  49 89 FC         MOV R12, RDI    (save string)     (3)
//   [6-8]  48 89 F7         MOV RDI, RSI                      (3)
//   [9-13] E8 dw            CALL kr_atoi    (RAX = idx)       (5)
//   [14-17] 41 8A 0C 04     MOV CL, [R12+RAX*1]               (4)
//   [18-19] 88 CB           MOV BL, CL                        (2)
//   [20-24] BF 02 00 00 00  MOV EDI, 2                        (5)
//   [25-29] E8 dw           CALL kr_alloc                     (5)
//   [30-31] 88 18           MOV [RAX], BL                     (2)
//   [32-33] 41 5C           POP R12                           (2)
//   [34]    5B              POP RBX                           (1)
//   [35]    C3              RET                               (1)
func emitKrIndexCodeFinal(thisVAddr, atoiVAddr, allocVAddr) {
    let dAtoi  = atoiVAddr  - (thisVAddr + 14)
    let dAlloc = allocVAddr - (thisVAddr + 30)
    let c = ""
    c = c + hexByte(0x53)
    c = c + hexByte(0x41) + hexByte(0x54)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xFC)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xF7)
    c = c + hexByte(0xE8) + hexDword(dAtoi)
    c = c + hexByte(0x41) + hexByte(0x8A) + hexByte(0x0C) + hexByte(0x04)
    c = c + hexByte(0x88) + hexByte(0xCB)
    c = c + hexByte(0xBF) + hexDword(2)
    c = c + hexByte(0xE8) + hexDword(dAlloc)
    c = c + hexByte(0x88) + hexByte(0x18)
    c = c + hexByte(0x41) + hexByte(0x5C)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krIndexSize() { emit 36 }

// kr_argcount: returns argc - 1 (number of user args, matching Krypton convention).
//   Out: RAX = argc - 1
//
// argc is stashed at [R14] by _start.
//
// Layout (7 bytes):
//   [0-2]  49 8B 06     MOV RAX, [R14]
//   [3-5]  48 FF C8     DEC RAX
//   [6]    C3           RET
func emitKrArgcountCode() {
    let c = ""
    c = c + hexByte(0x49) + hexByte(0x8B) + hexByte(0x06)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC8)
    c = c + hexByte(0xC3)
    emit c
}
func krArgcountSize() { emit 7 }

// kr_arg: return argv[idx + 1] as a string ptr (idx+1 to skip program name).
//   In:  RDI = idx (string or int)
//   Out: RAX = ptr to argv[idx+1] (or undefined if out of range)
//
// argv ptr is stashed at [R14+8].
//
// Layout (17 bytes):
//   [0-4]   E8 dw            CALL kr_atoi              (5)
//   [5-7]   48 FF C0         INC RAX                   (3)  ; skip argv[0]
//   [8-11]  49 8B 7E 08      MOV RDI, [R14+8]          (4)  ; argv ptr
//   [12-15] 48 8B 04 C7      MOV RAX, [RDI + RAX*8]    (4)
//   [16]    C3               RET                       (1)
func emitKrArgCodeFinal(thisVAddr, atoiVAddr) {
    let dAtoi = atoiVAddr - (thisVAddr + 5)
    let c = ""
    c = c + hexByte(0xE8) + hexDword(dAtoi)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC0)
    c = c + hexByte(0x49) + hexByte(0x8B) + hexByte(0x7E) + hexByte(0x08)
    c = c + hexByte(0x48) + hexByte(0x8B) + hexByte(0x04) + hexByte(0xC7)
    c = c + hexByte(0xC3)
    emit c
}
func krArgSize() { emit 17 }

// kr_substring: returns substring of s from start (inclusive) to end (exclusive).
//   In:  RDI = str ptr, RSI = start (string or int), RDX = end (string or int)
//   Out: RAX = ptr to new alloc'd string
//
// Stack layout at entry: caller did POP RDX (end) ; POP RSI (start) ; POP RDI (str).
// kr_atoi accepts both string ptrs (parses) and small ints (passthrough).
//
// Layout (73 bytes):
//   [0]      53                PUSH RBX                              (1)
//   [1-2]    41 54             PUSH R12                              (2)
//   [3-4]    41 55             PUSH R13                              (2)
//   [5-7]    49 89 D5          MOV R13, RDX                          (3)  ; raw end
//   [8-10]   49 89 F4          MOV R12, RSI                          (3)  ; raw start
//   [11-13]  48 89 FB          MOV RBX, RDI                          (3)  ; src ptr (preserved)
//   [14-16]  4C 89 EF          MOV RDI, R13                          (3)
//   [17-21]  E8 dw             CALL kr_atoi                          (5)
//   [22-24]  49 89 C5          MOV R13, RAX                          (3)  ; end as int
//   [25-27]  4C 89 E7          MOV RDI, R12                          (3)
//   [28-32]  E8 dw             CALL kr_atoi                          (5)
//   [33-35]  49 89 C4          MOV R12, RAX                          (3)  ; start as int
//   [36-38]  4C 89 EF          MOV RDI, R13                          (3)
//   [39-41]  4C 29 E7          SUB RDI, R12                          (3)  ; len = end - start
//   [42-45]  48 83 C7 01       ADD RDI, 1                            (4)  ; +NUL
//   [46-50]  E8 dw             CALL kr_alloc                         (5)
//   [51-53]  48 89 C7          MOV RDI, RAX                          (3)  ; dest
//   [54-56]  48 89 DE          MOV RSI, RBX                          (3)
//   [57-59]  4C 01 E6          ADD RSI, R12                          (3)  ; src + start
//   [60-62]  4C 89 E9          MOV RCX, R13                          (3)
//   [63-65]  4C 29 E1          SUB RCX, R12                          (3)  ; len bytes
//   [66-67]  F3 A4             REP MOVSB                             (2)
//   [68-69]  41 5D             POP R13                               (2)
//   [70-71]  41 5C             POP R12                               (2)
//   [72]     5B                POP RBX                               (1)
//   [73]     C3                RET                                   (1)
// (alloc'd memory is mmap'd zero-init, so trailing NUL is automatic; we asked for len+1)
//
// Wait, that's 74 bytes total. Recount: 1+2+2+3+3+3+3+5+3+3+5+3+3+3+4+5+3+3+3+3+3+2+2+2+1+1 = 73.
// Let me recount layout offsets: [0]=PUSH RBX (1B), [1]=PUSH R12 (2B → 1-2), [3]=PUSH R13 (2B → 3-4),
// [5]=MOV R13,RDX (3B → 5-7), [8]=MOV R12,RSI (3B → 8-10), [11]=MOV RBX,RDI (3B → 11-13),
// [14]=MOV RDI,R13 (3B → 14-16), [17]=CALL (5B → 17-21), [22]=MOV R13,RAX (3B → 22-24),
// [25]=MOV RDI,R12 (3B → 25-27), [28]=CALL (5B → 28-32), [33]=MOV R12,RAX (3B → 33-35),
// [36]=MOV RDI,R13 (3B → 36-38), [39]=SUB RDI,R12 (3B → 39-41), [42]=ADD RDI,1 (4B → 42-45),
// [46]=CALL kr_alloc (5B → 46-50), [51]=MOV RDI,RAX (3B → 51-53), [54]=MOV RSI,RBX (3B → 54-56),
// [57]=ADD RSI,R12 (3B → 57-59), [60]=MOV RCX,R13 (3B → 60-62), [63]=SUB RCX,R12 (3B → 63-65),
// [66]=REP MOVSB (2B → 66-67), [68]=POP R13 (2B → 68-69), [70]=POP R12 (2B → 70-71),
// [72]=POP RBX (1B → 72), [73]=RET (1B → 73). Total = 74 bytes.
func emitKrSubstringCode(thisVAddr, atoiVAddr, allocVAddr) {
    let dAtoi1  = atoiVAddr  - (thisVAddr + 22)
    let dAtoi2  = atoiVAddr  - (thisVAddr + 33)
    let dAlloc  = allocVAddr - (thisVAddr + 51)
    let c = ""
    c = c + hexByte(0x53)
    c = c + hexByte(0x41) + hexByte(0x54)
    c = c + hexByte(0x41) + hexByte(0x55)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xD5)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xF4)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xFB)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xEF)
    c = c + hexByte(0xE8) + hexDword(dAtoi1)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC5)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)
    c = c + hexByte(0xE8) + hexDword(dAtoi2)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC4)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xEF)
    c = c + hexByte(0x4C) + hexByte(0x29) + hexByte(0xE7)
    c = c + hexByte(0x48) + hexByte(0x83) + hexByte(0xC7) + hexByte(0x01)
    c = c + hexByte(0xE8) + hexDword(dAlloc)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC7)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDE)
    c = c + hexByte(0x4C) + hexByte(0x01) + hexByte(0xE6)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE9)
    c = c + hexByte(0x4C) + hexByte(0x29) + hexByte(0xE1)
    c = c + hexByte(0xF3) + hexByte(0xA4)
    c = c + hexByte(0x41) + hexByte(0x5D)
    c = c + hexByte(0x41) + hexByte(0x5C)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krSubstringSize() { emit 74 }

// kr_readfile: read entire file into a fresh allocation.
//   In:  RDI = path string ptr (NUL-terminated)
//   Out: RAX = ptr to file contents (NUL-terminated; length = file size)
//
// Syscalls used (Linux x86-64):
//   SYS_open  = 2,  args: path (RDI), flags (RSI), mode (RDX) → fd in RAX
//   SYS_read  = 0,  args: fd (RDI), buf (RSI), count (RDX)    → nbytes in RAX
//   SYS_close = 3,  args: fd (RDI)                            → 0 in RAX
//   SYS_fstat = 5,  args: fd (RDI), statbuf (RSI)             → 0 in RAX
// Linux struct stat: 144 bytes total; st_size at offset 48 (8 bytes).
//
// SYSCALL clobbers RCX and R11. All other regs (incl. R12-R15) are preserved.
// We use 144 bytes of stack as the statbuf scratch area.
//
// No error handling in this version: open() failing leaves fd negative; subsequent
// syscalls fail; we still return whatever buf we allocated. Caller responsibility.
//
// Layout (103 bytes):
//   [0]      53                PUSH RBX                                 (1)
//   [1-2]    41 54             PUSH R12                                 (2)
//   [3-4]    41 55             PUSH R13                                 (2)
//   [5-11]   48 81 EC 90 00 00 00   SUB RSP, 144   (statbuf area)      (7)
//   [12-14]  48 89 FB          MOV RBX, RDI       (save path)           (3)
//   [15-19]  B8 02 00 00 00    MOV EAX, 2         (SYS_open)            (5)
//   [20-22]  48 89 DF          MOV RDI, RBX                             (3)
//   [23-24]  31 F6             XOR ESI, ESI       (O_RDONLY = 0)        (2)
//   [25-26]  31 D2             XOR EDX, EDX       (mode = 0)            (2)
//   [27-28]  0F 05             SYSCALL                                  (2)
//   [29-31]  49 89 C4          MOV R12, RAX       (fd)                  (3)
//   [32-36]  B8 05 00 00 00    MOV EAX, 5         (SYS_fstat)           (5)
//   [37-39]  4C 89 E7          MOV RDI, R12                             (3)
//   [40-42]  48 89 E6          MOV RSI, RSP       (statbuf @ RSP)       (3)
//   [43-44]  0F 05             SYSCALL                                  (2)
//   [45-49]  4C 8B 6C 24 30    MOV R13, [RSP + 48]   (st_size)          (5)
//   [50-52]  4C 89 EF          MOV RDI, R13                             (3)
//   [53-55]  48 FF C7          INC RDI            (size + 1 for NUL)    (3)
//   [56-60]  E8 dw             CALL kr_alloc                            (5)
//   [61-63]  48 89 C3          MOV RBX, RAX       (buf)                 (3)
//   [64-65]  31 C0             XOR EAX, EAX       (SYS_read)            (2)
//   [66-68]  4C 89 E7          MOV RDI, R12       (fd)                  (3)
//   [69-71]  48 89 DE          MOV RSI, RBX       (buf)                 (3)
//   [72-74]  4C 89 EA          MOV RDX, R13       (size)                (3)
//   [75-76]  0F 05             SYSCALL                                  (2)
//   [77-81]  B8 03 00 00 00    MOV EAX, 3         (SYS_close)           (5)
//   [82-84]  4C 89 E7          MOV RDI, R12                             (3)
//   [85-86]  0F 05             SYSCALL                                  (2)
//   [87-89]  48 89 D8          MOV RAX, RBX       (return buf)          (3)
//   [90-96]  48 81 C4 90 00 00 00   ADD RSP, 144                       (7)
//   [97-98]  41 5D             POP R13                                  (2)
//   [99-100] 41 5C             POP R12                                  (2)
//   [101]    5B                POP RBX                                  (1)
//   [102]    C3                RET                                      (1)
func emitKrReadfileCode(thisVAddr, allocVAddr) {
    // CALL kr_alloc spans bytes 56..60 (5-byte E8+dword); next instr at 61.
    let dAlloc = allocVAddr - (thisVAddr + 61)
    let c = ""
    c = c + hexByte(0x53)
    c = c + hexByte(0x41) + hexByte(0x54)
    c = c + hexByte(0x41) + hexByte(0x55)
    c = c + hexByte(0x48) + hexByte(0x81) + hexByte(0xEC) + hexDword(144)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xFB)
    c = c + hexByte(0xB8) + hexDword(2)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDF)
    c = c + hexByte(0x31) + hexByte(0xF6)
    c = c + hexByte(0x31) + hexByte(0xD2)
    c = c + hexByte(0x0F) + hexByte(0x05)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC4)
    c = c + hexByte(0xB8) + hexDword(5)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xE6)
    c = c + hexByte(0x0F) + hexByte(0x05)
    c = c + hexByte(0x4C) + hexByte(0x8B) + hexByte(0x6C) + hexByte(0x24) + hexByte(0x30)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xEF)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7)
    c = c + hexByte(0xE8) + hexDword(dAlloc)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC3)
    c = c + hexByte(0x31) + hexByte(0xC0)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDE)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xEA)
    c = c + hexByte(0x0F) + hexByte(0x05)
    c = c + hexByte(0xB8) + hexDword(3)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)
    c = c + hexByte(0x0F) + hexByte(0x05)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xD8)
    c = c + hexByte(0x48) + hexByte(0x81) + hexByte(0xC4) + hexDword(144)
    c = c + hexByte(0x41) + hexByte(0x5D)
    c = c + hexByte(0x41) + hexByte(0x5C)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krReadfileSize() { emit 103 }

// kr_writefile: write content to path (truncating). Returns 0.
//   In:  RDI = path ptr, RSI = content ptr (NUL-terminated)
//   Out: RAX = 0
//
// Syscalls:
//   SYS_open  = 2,  flags = O_WRONLY|O_CREAT|O_TRUNC = 1|64|512 = 577, mode = 0644 = 420
//   SYS_write = 1
//   SYS_close = 3
//
// Layout (66 bytes):
//   [0]      53                PUSH RBX                                  (1)
//   [1-2]    41 54             PUSH R12                                  (2)
//   [3-5]    48 89 F3          MOV RBX, RSI       (save content)         (3)
//   [6-10]   B8 02 00 00 00    MOV EAX, 2         (SYS_open)             (5)
//   [11-15]  BE 41 02 00 00    MOV ESI, 577       (O_WRONLY|CREAT|TRUNC) (5)
//   [16-20]  BA A4 01 00 00    MOV EDX, 420       (mode 0644)            (5)
//   [21-22]  0F 05             SYSCALL                                   (2)
//   [23-25]  49 89 C4          MOV R12, RAX       (fd)                   (3)
//   [26-28]  48 89 DF          MOV RDI, RBX       (content)              (3)
//   [29-33]  E8 dw             CALL kr_strlen     (RAX = len)            (5)
//   [34-36]  48 89 C2          MOV RDX, RAX                              (3)
//   [37-39]  48 89 DE          MOV RSI, RBX                              (3)
//   [40-42]  4C 89 E7          MOV RDI, R12                              (3)
//   [43-47]  B8 01 00 00 00    MOV EAX, 1         (SYS_write)            (5)
//   [48-49]  0F 05             SYSCALL                                   (2)
//   [50-54]  B8 03 00 00 00    MOV EAX, 3         (SYS_close)            (5)
//   [55-57]  4C 89 E7          MOV RDI, R12                              (3)
//   [58-59]  0F 05             SYSCALL                                   (2)
//   [60-61]  31 C0             XOR EAX, EAX                              (2)
//   [62-63]  41 5C             POP R12                                   (2)
//   [64]     5B                POP RBX                                   (1)
//   [65]     C3                RET                                       (1)
func emitKrWritefileCode(thisVAddr, strlenVAddr) {
    // CALL kr_strlen ends at offset 34.
    let dStrlen = strlenVAddr - (thisVAddr + 34)
    let c = ""
    c = c + hexByte(0x53)
    c = c + hexByte(0x41) + hexByte(0x54)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xF3)
    c = c + hexByte(0xB8) + hexDword(2)
    c = c + hexByte(0xBE) + hexDword(577)
    c = c + hexByte(0xBA) + hexDword(420)
    c = c + hexByte(0x0F) + hexByte(0x05)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC4)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDF)
    c = c + hexByte(0xE8) + hexDword(dStrlen)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC2)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDE)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)
    c = c + hexByte(0xB8) + hexDword(1)
    c = c + hexByte(0x0F) + hexByte(0x05)
    c = c + hexByte(0xB8) + hexDword(3)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)
    c = c + hexByte(0x0F) + hexByte(0x05)
    c = c + hexByte(0x31) + hexByte(0xC0)
    c = c + hexByte(0x41) + hexByte(0x5C)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krWritefileSize() { emit 66 }

// kr_printerr: like kr_print, but writes to stderr (fd 2) instead of stdout.
//   In:  RDI = string ptr (NUL-terminated)
//   Out: nothing
//
// Identical to kr_print except byte at offset 24 is `02` instead of `01`.
//
// Layout (37 bytes):
//   [0..]   same as kr_print but [23-27] BF 02 00 00 00  MOV EDI, 2
func emitKrPrinterrCode() {
    let c = ""
    c = c + hexByte(0x53)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xFB)
    c = c + hexByte(0x31) + hexByte(0xC0)
    c = c + hexByte(0x80) + hexByte(0x3C) + hexByte(0x03) + hexByte(0x00)
    c = c + hexByte(0x74) + hexByte(0x04)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC0)
    c = c + hexByte(0xEB) + hexByte(245)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC2)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDE)
    c = c + hexByte(0xBF) + hexDword(2)         // ← fd=2 (stderr)
    c = c + hexByte(0xB8) + hexDword(1)
    c = c + hexByte(0x0F) + hexByte(0x05)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krPrinterrSize() { emit 37 }

// kr_charcode: returns the first byte of s as an integer.
//   In:  RDI = string ptr
//   Out: RAX = byte value (0..255), or 0 if empty
//
// Layout (5 bytes):
//   [0-3]  0F B6 07          MOVZX EAX, byte [RDI]    (3)
//   [4]    C3                RET                       (1)
//   wait that's only 4 bytes. Let me recount.
//   MOVZX EAX, byte [RDI] = 0F B6 07 = 3 bytes
//   RET = 1 byte. Total 4 bytes.
func emitKrCharcodeCode() {
    let c = ""
    c = c + hexByte(0x0F) + hexByte(0xB6) + hexByte(0x07)
    c = c + hexByte(0xC3)
    emit c
}
func krCharcodeSize() { emit 4 }

// kr_fromcharcode: returns a 1-char NUL-terminated string with byte n.
//   In:  RDI = int (or string-int) — the byte value
//   Out: RAX = ptr to allocated 2-byte string [byte, NUL]
//
// Layout (29 bytes):
//   [0]      53                PUSH RBX                            (1)
//   [1-5]    E8 dw             CALL kr_atoi    (n → int in RAX)    (5)
//   [6-8]    48 89 C3          MOV RBX, RAX    (save byte value)   (3)
//   [9-13]   BF 02 00 00 00    MOV EDI, 2      (alloc 2 bytes)     (5)
//   [14-18]  E8 dw             CALL kr_alloc                       (5)
//   [19-21]  88 18             MOV [RAX], BL                       (2)
//                                                  byte stored
//   ; second byte already 0 from mmap zero-init
//   [21]     5B                POP RBX                             (1)
//   [22]     C3                RET                                 (1)
//   Wait recount: 1+5+3+5+5+2+1+1 = 23 bytes.
func emitKrFromcharcodeCode(thisVAddr, atoiVAddr, allocVAddr) {
    let dAtoi  = atoiVAddr  - (thisVAddr + 6)
    let dAlloc = allocVAddr - (thisVAddr + 19)
    let c = ""
    c = c + hexByte(0x53)
    c = c + hexByte(0xE8) + hexDword(dAtoi)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC3)
    c = c + hexByte(0xBF) + hexDword(2)
    c = c + hexByte(0xE8) + hexDword(dAlloc)
    c = c + hexByte(0x88) + hexByte(0x18)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krFromcharcodeSize() { emit 23 }

// kr_exit: SYS_exit(atoi(n)). Does not return.
//   In:  RDI = exit code (int or numeric string)
//
// Layout (16 bytes):
//   [0-4]   E8 dw             CALL kr_atoi      (RAX = code)       (5)
//   [5-7]   48 89 C7          MOV RDI, RAX                          (3)
//   [8-12]  B8 3C 00 00 00    MOV EAX, 60      (SYS_exit)           (5)
//   [13-14] 0F 05             SYSCALL                               (2)
//   [15]    C3                RET  (unreachable but keeps size)     (1)
func emitKrExitCode(thisVAddr, atoiVAddr) {
    let dAtoi = atoiVAddr - (thisVAddr + 5)
    let c = ""
    c = c + hexByte(0xE8) + hexDword(dAtoi)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC7)
    c = c + hexByte(0xB8) + hexDword(60)
    c = c + hexByte(0x0F) + hexByte(0x05)
    c = c + hexByte(0xC3)
    emit c
}
func krExitSize() { emit 16 }

// kr_isdigit: returns 1 if first byte of s is '0'..'9', else 0.
//   In:  RDI = string ptr
//   Out: RAX = 0 or 1 (small int — smart kp/concat handle this)
//
// Layout (16 bytes):
//   [0-2]   0F B6 07          MOVZX EAX, byte [RDI]            (3)
//   [3-5]   83 E8 30          SUB EAX, 0x30                    (3)
//   [6-8]   83 F8 09          CMP EAX, 9                       (3)
//   [9-11]  0F 96 C0          SETBE AL                         (3)
//   [12-14] 0F B6 C0          MOVZX EAX, AL                    (3)
//   [15]    C3                RET                              (1)
func emitKrIsdigitCode() {
    let c = ""
    c = c + hexByte(0x0F) + hexByte(0xB6) + hexByte(0x07)
    c = c + hexByte(0x83) + hexByte(0xE8) + hexByte(0x30)
    c = c + hexByte(0x83) + hexByte(0xF8) + hexByte(0x09)
    c = c + hexByte(0x0F) + hexByte(0x96) + hexByte(0xC0)
    c = c + hexByte(0x0F) + hexByte(0xB6) + hexByte(0xC0)
    c = c + hexByte(0xC3)
    emit c
}
func krIsdigitSize() { emit 16 }

// kr_isalpha: returns 1 if first byte of s is A-Z or a-z, else 0.
//   Trick: OR with 0x20 maps uppercase to lowercase, then check 'a'..'z'.
//
// Layout (19 bytes):
//   [0-2]   0F B6 07          MOVZX EAX, byte [RDI]            (3)
//   [3-5]   83 C8 20          OR EAX, 0x20                     (3)
//   [6-8]   83 E8 61          SUB EAX, 0x61                    (3) ; 'a' = 0x61
//   [9-11]  83 F8 19          CMP EAX, 25                      (3) ; 'z'-'a' = 25
//   [12-14] 0F 96 C0          SETBE AL                         (3)
//   [15-17] 0F B6 C0          MOVZX EAX, AL                    (3)
//   [18]    C3                RET                              (1)
func emitKrIsalphaCode() {
    let c = ""
    c = c + hexByte(0x0F) + hexByte(0xB6) + hexByte(0x07)
    c = c + hexByte(0x83) + hexByte(0xC8) + hexByte(0x20)
    c = c + hexByte(0x83) + hexByte(0xE8) + hexByte(0x61)
    c = c + hexByte(0x83) + hexByte(0xF8) + hexByte(0x19)
    c = c + hexByte(0x0F) + hexByte(0x96) + hexByte(0xC0)
    c = c + hexByte(0x0F) + hexByte(0xB6) + hexByte(0xC0)
    c = c + hexByte(0xC3)
    emit c
}
func krIsalphaSize() { emit 19 }

// kr_abs: atoi the arg, return absolute value.
//   In:  RDI = int (or numeric string)
//   Out: RAX = |n|
//
// Layout (14 bytes):
//   [0-4]   E8 dw             CALL kr_atoi                     (5)
//   [5-7]   48 85 C0          TEST RAX, RAX                    (3)
//   [8-9]   79 03             JNS +3 → .done                   (2)
//   [10-12] 48 F7 D8          NEG RAX                          (3)
//   .done:
//   [13]    C3                RET                              (1)
func emitKrAbsCode(thisVAddr, atoiVAddr) {
    let dAtoi = atoiVAddr - (thisVAddr + 5)
    let c = ""
    c = c + hexByte(0xE8) + hexDword(dAtoi)
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)
    c = c + hexByte(0x79) + hexByte(0x03)
    c = c + hexByte(0x48) + hexByte(0xF7) + hexByte(0xD8)
    c = c + hexByte(0xC3)
    emit c
}
func krAbsSize() { emit 14 }

// kr_startswith: returns 1 if s starts with prefix, 0 otherwise.
//   In:  RDI = s, RSI = prefix  (both NUL-terminated)
//   Out: RAX = 0 or 1
//
// Layout (27 bytes):
//   .loop at [0]:
//   [0-1]   8A 06             MOV AL, [RSI]                    (2)
//   [2-3]   84 C0             TEST AL, AL                      (2)
//   [4-5]   74 0C             JZ +12 → .match at 18            (2)
//   [6-7]   3A 07             CMP AL, [RDI]                    (2)
//   [8-9]   75 0E             JNE +14 → .nomatch at 24         (2)
//   [10-12] 48 FF C6          INC RSI                          (3)
//   [13-15] 48 FF C7          INC RDI                          (3)
//   [16-17] EB EE             JMP -18 → .loop at 0             (2)
//   .match at [18]:
//   [18-22] B8 01 00 00 00    MOV EAX, 1                       (5)
//   [23]    C3                RET                              (1)
//   .nomatch at [24]:
//   [24-25] 31 C0             XOR EAX, EAX                     (2)
//   [26]    C3                RET                              (1)
func emitKrStartswithCode() {
    let c = ""
    c = c + hexByte(0x8A) + hexByte(0x06)
    c = c + hexByte(0x84) + hexByte(0xC0)
    c = c + hexByte(0x74) + hexByte(0x0C)
    c = c + hexByte(0x3A) + hexByte(0x07)
    c = c + hexByte(0x75) + hexByte(0x0E)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC6)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7)
    c = c + hexByte(0xEB) + hexByte(238)        // -18 as unsigned
    c = c + hexByte(0xB8) + hexDword(1)
    c = c + hexByte(0xC3)
    c = c + hexByte(0x31) + hexByte(0xC0)
    c = c + hexByte(0xC3)
    emit c
}
func krStartswithSize() { emit 27 }


// Re-emit kr_str_int with the kr_alloc CALL disp filled in.
// strIntVAddr  = vaddr of kr_str_int's first byte
// allocVAddr   = vaddr of kr_alloc's first byte
func emitKrStrIntCodeFinal(strIntVAddr, allocVAddr) {
    // CALL is at offset 11, ends at 16. disp = allocVAddr - (strIntVAddr + 16)
    let callDisp = allocVAddr - (strIntVAddr + 16)
    let c = ""
    c = c + hexByte(0x53)
    c = c + hexByte(0x41) + hexByte(0x54)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xFC)
    c = c + hexByte(0xBF) + hexDword(24)
    c = c + hexByte(0xE8) + hexDword(callDisp)                     // CALL kr_alloc (resolved)
    c = c + hexByte(0x48) + hexByte(0x8D) + hexByte(0x58) + hexByte(0x17)
    c = c + hexByte(0xC6) + hexByte(0x03) + hexByte(0x00)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE0)
    c = c + hexByte(0x31) + hexByte(0xC9)
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)
    c = c + hexByte(0x79) + hexByte(0x05)
    c = c + hexByte(0x48) + hexByte(0xF7) + hexByte(0xD8)
    c = c + hexByte(0xFF) + hexByte(0xC1)
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)
    c = c + hexByte(0x75) + hexByte(0x08)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xCB)
    c = c + hexByte(0xC6) + hexByte(0x03) + hexByte(0x30)
    c = c + hexByte(0xEB) + hexByte(0x21)
    c = c + hexByte(0x31) + hexByte(0xD2)
    c = c + hexByte(0xBE) + hexDword(10)
    c = c + hexByte(0x48) + hexByte(0xF7) + hexByte(0xF6)
    c = c + hexByte(0x80) + hexByte(0xC2) + hexByte(0x30)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xCB)
    c = c + hexByte(0x88) + hexByte(0x13)
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)
    c = c + hexByte(0x75) + hexByte(256 - 23)
    c = c + hexByte(0x85) + hexByte(0xC9)
    c = c + hexByte(0x74) + hexByte(0x06)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xCB)
    c = c + hexByte(0xC6) + hexByte(0x03) + hexByte(0x2D)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xD8)
    c = c + hexByte(0x41) + hexByte(0x5C)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}

// kr_str_int: convert signed 64-bit integer to NUL-terminated decimal string.
//   In:  RDI = integer
//   Out: RAX = pointer to first digit
//
// Strategy: allocate 24 bytes, build string from the END backward (so digits
// land in correct order without a reverse loop). Returns ptr to first digit.
//
// Byte-by-byte layout (offsets in [brackets]):
//   [0]   53                    PUSH RBX
//   [1]   41 54                 PUSH R12
//   [3]   49 89 FC              MOV R12, RDI       ; save n
//   [6]   BF 18 00 00 00        MOV EDI, 24
//   [11]  E8 00 00 00 00        CALL kr_alloc      ; PATCHED post-emit
//   [16]  48 8D 58 17           LEA RBX, [RAX+23]  ; ptr = buf+23
//   [20]  C6 03 00              MOV byte [RBX], 0  ; nullterm
//   [23]  4C 89 E0              MOV RAX, R12       ; restore n
//   [26]  31 C9                 XOR ECX, ECX       ; neg flag
//   [28]  48 85 C0              TEST RAX, RAX
//   [31]  79 05                 JNS +5 → 38 (.pos)
//   [33]  48 F7 D8              NEG RAX
//   [36]  FF C1                 INC ECX
//   [38]  48 85 C0              TEST RAX, RAX     ; .pos:
//   [41]  75 08                 JNZ +8 → 51 (.digit_loop)
//   [43]  48 FF CB              DEC RBX
//   [46]  C6 03 30              MOV byte [RBX], '0'
//   [49]  EB 20                 JMP +32 → 83 (.done)
//   [51]  31 D2                 XOR EDX, EDX       ; .digit_loop:
//   [53]  BE 0A 00 00 00        MOV ESI, 10
//   [58]  48 F7 F6              DIV RSI            ; rax /= 10, rdx = rem
//   [61]  80 C2 30              ADD DL, '0'
//   [64]  48 FF CB              DEC RBX
//   [67]  88 13                 MOV [RBX], DL
//   [69]  48 85 C0              TEST RAX, RAX
//   [72]  75 ED                 JNZ -19 → 51 (.digit_loop)  ; 74 + (-19) = 55... wait
//   ...
//
// Recomputed disp values below.
func emitKrStrIntCode() {
    let c = ""
    c = c + hexByte(0x53)                                          // [0]   PUSH RBX
    c = c + hexByte(0x41) + hexByte(0x54)                          // [1-2] PUSH R12
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xFC)          // [3-5] MOV R12, RDI
    c = c + hexByte(0xBF) + hexDword(24)                           // [6-10] MOV EDI, 24
    c = c + hexByte(0xE8) + hexDword(0)                            // [11-15] CALL kr_alloc (PATCHED)
    c = c + hexByte(0x48) + hexByte(0x8D) + hexByte(0x58) + hexByte(0x17)  // [16-19] LEA RBX, [RAX+23]
    c = c + hexByte(0xC6) + hexByte(0x03) + hexByte(0x00)          // [20-22] MOV byte [RBX], 0
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE0)          // [23-25] MOV RAX, R12
    c = c + hexByte(0x31) + hexByte(0xC9)                          // [26-27] XOR ECX, ECX
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)          // [28-30] TEST RAX, RAX
    c = c + hexByte(0x79) + hexByte(0x05)                          // [31-32] JNS +5 → 38
    c = c + hexByte(0x48) + hexByte(0xF7) + hexByte(0xD8)          // [33-35] NEG RAX
    c = c + hexByte(0xFF) + hexByte(0xC1)                          // [36-37] INC ECX
    // .pos at 38:
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)          // [38-40] TEST RAX, RAX
    c = c + hexByte(0x75) + hexByte(0x08)                          // [41-42] JNZ +8 → 51
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xCB)          // [43-45] DEC RBX
    c = c + hexByte(0xC6) + hexByte(0x03) + hexByte(0x30)          // [46-48] MOV [RBX], '0'
    c = c + hexByte(0xEB) + hexByte(0x21)                          // [49-50] JMP +33 → 84 (.done)
    // .digit_loop at 51:
    c = c + hexByte(0x31) + hexByte(0xD2)                          // [51-52] XOR EDX, EDX
    c = c + hexByte(0xBE) + hexDword(10)                           // [53-57] MOV ESI, 10
    c = c + hexByte(0x48) + hexByte(0xF7) + hexByte(0xF6)          // [58-60] DIV RSI
    c = c + hexByte(0x80) + hexByte(0xC2) + hexByte(0x30)          // [61-63] ADD DL, '0'
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xCB)          // [64-66] DEC RBX
    c = c + hexByte(0x88) + hexByte(0x13)                          // [67-68] MOV [RBX], DL
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)          // [69-71] TEST RAX, RAX
    c = c + hexByte(0x75) + hexByte(256 - 23)                      // [72-73] JNZ -23 → 51
    c = c + hexByte(0x85) + hexByte(0xC9)                          // [74-75] TEST ECX, ECX
    c = c + hexByte(0x74) + hexByte(0x06)                          // [76-77] JZ +6 → 84 (.done)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xCB)          // [78-80] DEC RBX
    c = c + hexByte(0xC6) + hexByte(0x03) + hexByte(0x2D)          // [81-83] MOV [RBX], '-'
    // Hmm that puts '-' write at 81-83 which collides with .done...
    // Recount: 78-80 (DEC RBX, 3 bytes), 81-83 (MOV byte [RBX], '-', 3 bytes).
    // .done would then be at 84.
    // .done at 84:
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xD8)          // [84-86] MOV RAX, RBX
    c = c + hexByte(0x41) + hexByte(0x5C)                          // [87-88] POP R12
    c = c + hexByte(0x5B)                                          // [89]   POP RBX
    c = c + hexByte(0xC3)                                          // [90]   RET
    emit c
}
// 91 bytes total. Need to fix the JMP +32 → 83 above to JMP +33 → 84.
func krStrIntSize() { emit 91 }

// _start:
//   1. Save argc + argv ptr from stack (RSP layout: argc, argv[0..N], NULL, envp...)
//   2. mmap(0, 65536, PROT_R|PROT_W, MAP_PRIVATE|MAP_ANON, -1, 0) → heap base
//   3. Stash argc at [heap+0], argv ptr at [heap+8]
//   4. R14 = heap base (globals — argc/argv lookup); R15 = heap_next (= heap+16)
//   5. CALL __main__
//   6. CALL kr_atoi on return value (string→int OR int passthrough)
//   7. SYS_exit(RAX)
//
// Layout (81 bytes):
//   [0-3]   4C 8B 24 24            MOV R12, [RSP]      (argc)            (4)
//   [4-8]   4C 8D 6C 24 08         LEA R13, [RSP+8]    (argv ptr)        (5)
//   [9-13]  B8 09 00 00 00         MOV EAX, 9          (SYS_mmap)        (5)
//   [14-15] 31 FF                  XOR EDI, EDI                          (2)
//   [16-20] BE 00 00 01 00         MOV ESI, 0x10000    (size=64KB)       (5)
//   [21-25] BA 03 00 00 00         MOV EDX, 3                            (5)
//   [26-31] 41 BA 22 00 00 00      MOV R10D, 0x22                        (6)
//   [32-38] 49 C7 C0 FF FF FF FF   MOV R8, -1                            (7)
//   [39-41] 45 31 C9               XOR R9D, R9D                          (3)
//   [42-43] 0F 05                  SYSCALL                               (2)
//   [44-46] 4C 89 20               MOV [RAX], R12      (heap[0]=argc)    (3)
//   [47-50] 4C 89 68 08            MOV [RAX+8], R13    (heap[8]=argv)    (4)
//   [51-53] 49 89 C6               MOV R14, RAX        (globals base)    (3)
//   [54-57] 4C 8D 78 10            LEA R15, [RAX+16]   (heap_next past globals) (4)
//   [58-62] E8 dw                  CALL __main__                         (5)
//   [63-65] 48 89 C7               MOV RDI, RAX                          (3)
//   [66-70] E8 dw                  CALL kr_atoi                          (5)
//   [71-73] 48 89 C7               MOV RDI, RAX                          (3)
//   [74-78] B8 3C 00 00 00         MOV EAX, 60                           (5)
//   [79-80] 0F 05                  SYSCALL                               (2)
func startSize() { emit 81 }
func emitStartCode(callDisp, atoiDisp) {
    let c = ""
    c = c + hexByte(0x4C) + hexByte(0x8B) + hexByte(0x24) + hexByte(0x24)
    c = c + hexByte(0x4C) + hexByte(0x8D) + hexByte(0x6C) + hexByte(0x24) + hexByte(0x08)
    c = c + hexByte(0xB8) + hexDword(9)
    c = c + hexByte(0x31) + hexByte(0xFF)
    c = c + hexByte(0xBE) + hexDword(65536)
    c = c + hexByte(0xBA) + hexDword(3)
    c = c + hexByte(0x41) + hexByte(0xBA) + hexDword(0x22)
    c = c + hexByte(0x49) + hexByte(0xC7) + hexByte(0xC0) + hexDword(0 - 1)
    c = c + hexByte(0x45) + hexByte(0x31) + hexByte(0xC9)
    c = c + hexByte(0x0F) + hexByte(0x05)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0x20)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0x68) + hexByte(0x08)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC6)
    c = c + hexByte(0x4C) + hexByte(0x8D) + hexByte(0x78) + hexByte(0x10)
    c = c + hexByte(0xE8) + hexDword(callDisp)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC7)
    c = c + hexByte(0xE8) + hexDword(atoiDisp)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC7)
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

// Local symbol table: lookup name → 1-based slot index. Returns 0 if not found.
// Encoding: localTable is "name1\nname2\n...".
func localSlot(localTable, name) {
    if len(localTable) == 0 { emit "0" }
    let n = lineCount(localTable)
    let i = 0
    while i < n {
        if getLine(localTable, i) == name { emit (i + 1) + "" }
        i += 1
    }
    emit "0"
}

// Lookup label offset by name. Returns "" if not found.
// Encoding: labels is "name:offset\nname:offset\n...".
func labelOffset(labels, name) {
    if len(labels) == 0 { emit "" }
    let n = lineCount(labels)
    let i = 0
    while i < n {
        let l = getLine(labels, i)
        let j = 0
        while j < len(l) && l[j] != ":" { j += 1 }
        if substring(l, 0, j) == name {
            emit substring(l, j + 1, len(l))
        }
        i += 1
    }
    emit ""
}

// Same lookup pattern, used for funcVAddrs: "name:vaddr\n..."
func funcVAddr(table, name) { emit labelOffset(table, name) }

// Predictable byte size for each lowered op. MUST match emit exactly.
// Always uses disp32 form for locals (no disp8 optimization).
func opByteSize(op) {
    if op == "PUSH_STR"   { emit 11 }   // 48 BF imm64 (10) + 50/57 push (1)
    if op == "PUSH_INT"   { emit 11 }
    if op == "STORE_LOCAL"{ emit 8 }    // POP RAX (1) + MOV [RBP+d32], RAX (7)
    if op == "LOAD_LOCAL" { emit 8 }    // MOV RAX, [RBP+d32] (7) + PUSH RAX (1)
    if op == "LOAD_PARAM" { emit 8 }    // same encoding (positive disp32)
    if op == "STORE_PARAM"{ emit 8 }
    if op == "ADD"        { emit 35 }   // smart dispatch: int add OR call kr_concat
    if op == "CAT"        { emit 8 }    // POP RSI + POP RDI + CALL kr_concat + PUSH RAX
    if op == "SUB"        { emit 6 }
    if op == "MUL"        { emit 7 }
    if op == "DIV"        { emit 8 }    // POP+POP+CQO(2)+IDIV(3)+PUSH RAX
    if op == "MOD"        { emit 8 }    // same shape, PUSH RDX
    if op == "CALL_FUNC"  { emit 13 }   // E8 d32 (5) + ADD RSP imm32 (7) + PUSH RAX (1)
    if op == "EQ"         { emit 11 }   // POP RCX(1)+POP RAX(1)+XOR EDX,EDX(2)+CMP RAX,RCX(3)+SETcc DL(3)+PUSH RDX(1)
    if op == "NEQ"        { emit 11 }
    if op == "LT"         { emit 11 }
    if op == "GT"         { emit 11 }
    if op == "LTE"        { emit 11 }
    if op == "GTE"        { emit 11 }
    if op == "RETURN"     { emit 6 }    // POP RAX (1) + MOV RSP,RBP (3) + POP RBP (1) + RET (1)
    if op == "BUILTIN_KP" { emit 25 }   // smart: POP+CMP+JAE+kr_str_int+kr_print+PUSH 0
    if op == "BUILTIN_TOSTR" { emit 7 } // POP RDI (1) + CALL d32 (5) + PUSH RAX (1)
    if op == "BUILTIN_TOINT" { emit 7 } // POP RDI + CALL kr_atoi + PUSH RAX
    if op == "BUILTIN_LENGTH"{ emit 7 } // POP RDI + CALL kr_length + PUSH RAX
    if op == "BUILTIN_LEN"   { emit 7 } // POP RDI + CALL kr_strlen + PUSH RAX (string length)
    if op == "BUILTIN_SPLIT" { emit 8 } // POP RSI(1) + POP RDI(1) + CALL kr_split(5) + PUSH RAX(1)
    if op == "BUILTIN_RANGE" { emit 8 } // POP RSI + POP RDI + CALL kr_range + PUSH RAX
    if op == "INDEX"         { emit 8 } // POP RSI + POP RDI + CALL kr_index + PUSH RAX
    if op == "BUILTIN_ARG"   { emit 7 } // POP RDI + CALL kr_arg + PUSH RAX
    if op == "BUILTIN_ARGCOUNT"{ emit 6 } // CALL kr_argcount + PUSH RAX (no args)
    if op == "BUILTIN_SUBSTRING" { emit 9 } // POP RDX + POP RSI + POP RDI + CALL + PUSH RAX
    if op == "BUILTIN_SB_NEW"    { emit 11 } // MOV EDI,1 + CALL kr_alloc + PUSH RAX
    if op == "BUILTIN_SB_APPEND" { emit 8 }  // POP RSI + POP RDI + CALL kr_concat + PUSH RAX
    if op == "BUILTIN_SB_TOSTR"  { emit 0 }  // no-op: ptr stays on stack
    if op == "BUILTIN_READFILE"  { emit 7 }  // POP RDI + CALL kr_readfile + PUSH RAX
    if op == "BUILTIN_WRITEFILE" { emit 8 }  // POP RSI + POP RDI + CALL kr_writefile + PUSH RAX
    if op == "BUILTIN_PRINTERR"  { emit 8 }  // POP RDI + CALL kr_printerr + PUSH 0
    if op == "BUILTIN_CHARCODE"  { emit 7 }  // POP RDI + CALL kr_charcode + PUSH RAX
    if op == "BUILTIN_FROMCHARCODE" { emit 7 } // POP RDI + CALL + PUSH RAX
    if op == "BUILTIN_EXIT"      { emit 7 }  // POP RDI + CALL kr_exit + PUSH RAX (RAX never used)
    if op == "BUILTIN_ISDIGIT"   { emit 7 }  // POP RDI + CALL + PUSH RAX
    if op == "BUILTIN_ISALPHA"   { emit 7 }
    if op == "BUILTIN_ABS"       { emit 7 }
    if op == "BUILTIN_STARTSWITH"{ emit 8 }  // POP RSI + POP RDI + CALL + PUSH RAX
    if op == "POP"        { emit 1 }
    if op == "LABEL"      { emit 0 }
    if op == "JUMP"       { emit 5 }    // E9 + d32
    if op == "JUMPIFNOT"  { emit 10 }   // POP RAX (1) + TEST RAX,RAX (3) + JZ d32 (6)
    if op == "END_FUNC"   { emit 8 }    // XOR RAX,RAX (3) + MOV RSP,RBP (3) + POP RBP (1) + RET (1)
    emit 0
}

// Compute prologue size given localCount.
// Always: PUSH RBP (1) + MOV RBP,RSP (3) = 4 bytes baseline.
// If localCount > 0: + SUB RSP,imm32 (7 bytes).
func prologueSize(localCount) {
    if localCount > 0 { emit 11 }
    emit 4
}

// ── Pass 1: scan IR, intern strings, lower IR ops ──────────────────
// Multi-function output. Sections separated by "~~~":
//   1) stringTable     newline-separated string literals
//   2) ~~~
//   3) function block 1
//   4) ~~~
//   5) function block 2
//   ...
//
// Each function block:
//   line 0: "FUNC name argcount localCount"   (paramCount = argcount; params in line 1)
//   line 1: paramName1\tparamName2\t...        (TAB-separated; empty if argcount=0)
//   line 2: localName1\tlocalName2\t...        (TAB-separated; empty if no locals)
//   line 3: opCount
//   lines 4..: lowered ops, one per line
//
// Lowered ops (resolved):
//   PUSH_STR idx
//   PUSH_INT n
//   LOAD_PARAM idx           args at [RBP + 16 + (argcount-1-idx)*8]
//   STORE_PARAM idx          (rare; assignment to param)
//   LOAD_LOCAL slot          locals at [RBP - slot*8]   (slot is 1-based)
//   STORE_LOCAL slot
//   ADD/SUB/MUL/DIV/MOD
//   EQ/NEQ/LT/GT/LTE/GTE
//   LABEL name               (per-function label; resolved during emit)
//   JUMP name / JUMPIFNOT name
//   CALL_FUNC name argcount
//   BUILTIN_KP
//   RETURN / POP / END_FUNC

// Find index of name in TAB-separated list. Returns -1 if not found, else 0-based.
func tabFind(list, name) {
    if len(list) == 0 { emit "-1" }
    let n = len(list)
    let i = 0
    let idx = 0
    let tokStart = 0
    while i <= n {
        if i == n || list[i] == "\t" {
            if substring(list, tokStart, i) == name { emit idx + "" }
            idx += 1
            tokStart = i + 1
        }
        i += 1
    }
    emit "-1"
}

// Append name to TAB-separated list; return new list
func tabAppend(list, name) {
    if len(list) == 0 { emit name }
    emit list + "\t" + name
}

// Count TAB-separated entries in list
func tabCount(list) {
    if len(list) == 0 { emit 0 }
    let n = len(list)
    let i = 0
    let c = 1
    while i < n {
        if list[i] == "\t" { c += 1 }
        i += 1
    }
    emit c
}

func parseIR(ir) {
    let strTab = ""
    let strCount = 0

    // Result: strTab + "~~~" + funcBlock1 + "~~~" + funcBlock2 + ...
    let resultSb = sbNew()
    let firstFunc = "1"

    // Per-function state
    let curName = ""
    let curArgc = 0
    let params = ""
    let locals = ""
    let opSb = sbNew()
    let opCount = 0
    let inFunc = "0"

    let nl = lineCount(ir)
    let i = 0
    while i < nl {
        let line = trim(getLine(ir, i))
        if len(line) > 0 && line[0] != ";" {
            let j = 0
            while j < len(line) && line[j] != " " { j += 1 }
            let op = substring(line, 0, j)
            let rest = ""
            if j < len(line) { rest = trim(substring(line, j + 1, len(line))) }

            if op == "FUNC" {
                // Flush previous function if any
                if inFunc == "1" {
                    if firstFunc == "0" { resultSb = sbAppend(resultSb, "\n") }
                    firstFunc = "0"
                    resultSb = sbAppend(resultSb, "~~~\n")
                    resultSb = sbAppend(resultSb, "FUNC " + curName + " " + curArgc + " " + tabCount(locals) + "\n")
                    resultSb = sbAppend(resultSb, params + "\n")
                    resultSb = sbAppend(resultSb, locals + "\n")
                    resultSb = sbAppend(resultSb, opCount + "\n")
                    resultSb = sbAppend(resultSb, sbToString(opSb))
                }
                // Start new function
                let sp = 0
                while sp < len(rest) && rest[sp] != " " { sp += 1 }
                curName = substring(rest, 0, sp)
                curArgc = 0
                if sp < len(rest) { curArgc = toInt(trim(substring(rest, sp + 1, len(rest)))) }
                params = ""
                locals = ""
                opSb = sbNew()
                opCount = 0
                inFunc = "1"
            } else if op == "PARAM" {
                params = tabAppend(params, rest)
            } else if op == "LOCAL" {
                if toInt(tabFind(locals, rest)) < 0 {
                    locals = tabAppend(locals, rest)
                }
            } else if op == "LOAD" {
                let pIdx = toInt(tabFind(params, rest))
                let lIdx = toInt(tabFind(locals, rest))
                if opCount > 0 { opSb = sbAppend(opSb, "\n") }
                if pIdx >= 0 {
                    opSb = sbAppend(opSb, "LOAD_PARAM " + pIdx)
                } else if lIdx >= 0 {
                    opSb = sbAppend(opSb, "LOAD_LOCAL " + (lIdx + 1))
                } else {
                    opSb = sbAppend(opSb, "UNKNOWN_LOAD " + rest)
                }
                opCount += 1
            } else if op == "STORE" {
                let pIdx = toInt(tabFind(params, rest))
                let lIdx = toInt(tabFind(locals, rest))
                if pIdx < 0 && lIdx < 0 {
                    locals = tabAppend(locals, rest)
                    lIdx = toInt(tabFind(locals, rest))
                }
                if opCount > 0 { opSb = sbAppend(opSb, "\n") }
                if pIdx >= 0 {
                    opSb = sbAppend(opSb, "STORE_PARAM " + pIdx)
                } else {
                    opSb = sbAppend(opSb, "STORE_LOCAL " + (lIdx + 1))
                }
                opCount += 1
            } else if op == "PUSH" {
                if len(rest) > 0 && rest[0] == "\"" {
                    let parsed = parseQuoted(rest, 0)
                    let val = getLine(parsed, 0)
                    let interned = internStr(strTab, strCount, val)
                    let lcInt = lineCount(interned)
                    let idx = toInt(getLine(interned, lcInt - 1))
                    let tabSb = sbNew()
                    let tk = 0
                    while tk < lcInt - 1 {
                        if tk > 0 { tabSb = sbAppend(tabSb, "\n") }
                        tabSb = sbAppend(tabSb, getLine(interned, tk))
                        tk += 1
                    }
                    strTab = sbToString(tabSb)
                    if idx >= strCount { strCount = idx + 1 }
                    if opCount > 0 { opSb = sbAppend(opSb, "\n") }
                    opSb = sbAppend(opSb, "PUSH_STR " + idx)
                    opCount += 1
                } else {
                    if opCount > 0 { opSb = sbAppend(opSb, "\n") }
                    opSb = sbAppend(opSb, "PUSH_INT " + rest)
                    opCount += 1
                }
            } else if op == "CALL" {
                if opCount > 0 { opSb = sbAppend(opSb, "\n") }
                opSb = sbAppend(opSb, "CALL_FUNC " + rest)
                opCount += 1
            } else if op == "BUILTIN" {
                let bj = 0
                while bj < len(rest) && rest[bj] != " " { bj += 1 }
                let bname = substring(rest, 0, bj)
                if opCount > 0 { opSb = sbAppend(opSb, "\n") }
                if bname == "kp" || bname == "print" {
                    opSb = sbAppend(opSb, "BUILTIN_KP")
                } else if bname == "toStr" || bname == "kr_str" {
                    opSb = sbAppend(opSb, "BUILTIN_TOSTR")
                } else if bname == "toInt" || bname == "parseInt" {
                    opSb = sbAppend(opSb, "BUILTIN_TOINT")
                } else if bname == "length" {
                    opSb = sbAppend(opSb, "BUILTIN_LENGTH")
                } else if bname == "len" {
                    opSb = sbAppend(opSb, "BUILTIN_LEN")
                } else if bname == "split" {
                    opSb = sbAppend(opSb, "BUILTIN_SPLIT")
                } else if bname == "range" {
                    opSb = sbAppend(opSb, "BUILTIN_RANGE")
                } else if bname == "arg" {
                    opSb = sbAppend(opSb, "BUILTIN_ARG")
                } else if bname == "argCount" {
                    opSb = sbAppend(opSb, "BUILTIN_ARGCOUNT")
                } else if bname == "substring" {
                    opSb = sbAppend(opSb, "BUILTIN_SUBSTRING")
                } else if bname == "sbNew" {
                    opSb = sbAppend(opSb, "BUILTIN_SB_NEW")
                } else if bname == "sbAppend" {
                    opSb = sbAppend(opSb, "BUILTIN_SB_APPEND")
                } else if bname == "sbToString" {
                    opSb = sbAppend(opSb, "BUILTIN_SB_TOSTR")
                } else if bname == "readFile" {
                    opSb = sbAppend(opSb, "BUILTIN_READFILE")
                } else if bname == "writeFile" {
                    opSb = sbAppend(opSb, "BUILTIN_WRITEFILE")
                } else if bname == "printErr" {
                    opSb = sbAppend(opSb, "BUILTIN_PRINTERR")
                } else if bname == "charCode" {
                    opSb = sbAppend(opSb, "BUILTIN_CHARCODE")
                } else if bname == "fromCharCode" {
                    opSb = sbAppend(opSb, "BUILTIN_FROMCHARCODE")
                } else if bname == "exit" {
                    opSb = sbAppend(opSb, "BUILTIN_EXIT")
                } else if bname == "isDigit" {
                    opSb = sbAppend(opSb, "BUILTIN_ISDIGIT")
                } else if bname == "isAlpha" {
                    opSb = sbAppend(opSb, "BUILTIN_ISALPHA")
                } else if bname == "abs" {
                    opSb = sbAppend(opSb, "BUILTIN_ABS")
                } else if bname == "startsWith" {
                    opSb = sbAppend(opSb, "BUILTIN_STARTSWITH")
                } else {
                    opSb = sbAppend(opSb, "UNSUPPORTED " + bname)
                }
                opCount += 1
            } else if op == "ADD" || op == "SUB" || op == "MUL" || op == "DIV" || op == "MOD"
                   || op == "EQ" || op == "NEQ" || op == "LT" || op == "GT" || op == "LTE" || op == "GTE"
                   || op == "CAT" || op == "INDEX" || op == "POP" || op == "RETURN" {
                if opCount > 0 { opSb = sbAppend(opSb, "\n") }
                opSb = sbAppend(opSb, op)
                opCount += 1
            } else if op == "LABEL" || op == "JUMP" || op == "JUMPIFNOT" {
                if opCount > 0 { opSb = sbAppend(opSb, "\n") }
                opSb = sbAppend(opSb, op + " " + rest)
                opCount += 1
            } else if op == "END" {
                if opCount > 0 { opSb = sbAppend(opSb, "\n") }
                opSb = sbAppend(opSb, "END_FUNC")
                opCount += 1
            }
        }
        i += 1
    }
    // Flush last function
    if inFunc == "1" {
        if firstFunc == "0" { resultSb = sbAppend(resultSb, "\n") }
        resultSb = sbAppend(resultSb, "~~~\n")
        resultSb = sbAppend(resultSb, "FUNC " + curName + " " + curArgc + " " + tabCount(locals) + "\n")
        resultSb = sbAppend(resultSb, params + "\n")
        resultSb = sbAppend(resultSb, locals + "\n")
        resultSb = sbAppend(resultSb, opCount + "\n")
        resultSb = sbAppend(resultSb, sbToString(opSb))
    }

    // resultSb already begins each func with "~~~\n", so just concatenate.
    emit strTab + "\n" + sbToString(resultSb)
}

// ── Pass 2 (layout): compute label offsets and total code size ─────
// Walks opList summing op sizes; records "labelName:offset" for each LABEL.
// Returns "labels\n---\ntotalSize".
func computeLayout(opList, localCount) {
    let labels = ""
    let off = prologueSize(localCount)

    let nl = lineCount(opList)
    let i = 0
    while i < nl {
        let line = getLine(opList, i)
        let j = 0
        while j < len(line) && line[j] != " " { j += 1 }
        let op = substring(line, 0, j)
        let rest = ""
        if j < len(line) { rest = trim(substring(line, j + 1, len(line))) }

        if op == "LABEL" {
            if len(labels) > 0 { labels = labels + "\n" }
            labels = labels + rest + ":" + off
        } else {
            off = off + opByteSize(op)
        }
        i += 1
    }
    emit labels + "\n---\n" + off
}

// ── Pass 3: emit code with correct jump displacements ──────────────
// labels: name→offset table built by computeLayout.
// argcount: number of parameters (used to compute PARAM offsets above RBP)
// funcVAddrs: name→vaddr table for CALL targets (lines: "name:vaddr"). Pass "" if unused.
// funcStartVAddr: virtual address of THIS function's first byte (for CALL disp calc)
// krPrintVAddr/krStrIntVAddr: vaddrs of runtime helpers, used by BUILTIN_KP/BUILTIN_TOSTR

func emitFuncCode(opList, strVAddrs, argcount, localCount, labels, funcVAddrs, funcStartVAddr, krPrintVAddr, krStrIntVAddr, krConcatVAddr, krAtoiVAddr, krLengthVAddr, krStrlenVAddr, krSplitVAddr, krRangeVAddr, krIndexVAddr, krArgVAddr, krArgcountVAddr, krSubstringVAddr, krAllocVAddr, krReadfileVAddr, krWritefileVAddr, krPrinterrVAddr, krCharcodeVAddr, krFromcharcodeVAddr, krExitVAddr, krIsdigitVAddr, krIsalphaVAddr, krAbsVAddr, krStartswithVAddr) {
    let c = ""
    c = c + hexByte(0x55)                                             // [+0] PUSH RBP
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xE5)             // [+1] MOV RBP, RSP
    if localCount > 0 {
        // SUB RSP, imm32 (allocate 8 bytes per local, 16-byte aligned)
        let bytes = localCount * 8
        let pad = 0
        if bytes % 16 != 0 { pad = 16 - (bytes % 16) }
        let total = bytes + pad
        c = c + hexByte(0x48) + hexByte(0x81) + hexByte(0xEC) + hexDword(total)
    }

    let off = prologueSize(localCount)
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
            c = c + hexByte(0x48) + hexByte(0xBF) + hexQword(vaddr)
            c = c + hexByte(0x57)
        } else if op == "PUSH_INT" {
            let n = toInt(rest)
            c = c + hexByte(0x48) + hexByte(0xBF) + hexQword(n)
            c = c + hexByte(0x57)
        } else if op == "STORE_LOCAL" {
            let slot = toInt(rest)
            let dispVal = 0 - (slot * 8)
            c = c + hexByte(0x58)
            c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0x85) + hexDword(dispVal)
        } else if op == "LOAD_LOCAL" {
            let slot = toInt(rest)
            let dispVal = 0 - (slot * 8)
            c = c + hexByte(0x48) + hexByte(0x8B) + hexByte(0x85) + hexDword(dispVal)
            c = c + hexByte(0x50)
        } else if op == "LOAD_PARAM" {
            // PARAM idx 0 (first declared) is at the BOTTOM of pushed args, i.e. highest RBP offset.
            // Stack from caller: pushes p0, p1, ..., pN-1 in order. After CALL+prologue:
            //   [RBP+0]=savedRBP, [RBP+8]=retaddr, [RBP+16]=pN-1, [RBP+24]=pN-2, ..., [RBP+16+(N-1)*8]=p0
            let idx = toInt(rest)
            let dispVal = 16 + (argcount - 1 - idx) * 8
            c = c + hexByte(0x48) + hexByte(0x8B) + hexByte(0x85) + hexDword(dispVal)
            c = c + hexByte(0x50)
        } else if op == "STORE_PARAM" {
            let idx = toInt(rest)
            let dispVal = 16 + (argcount - 1 - idx) * 8
            c = c + hexByte(0x58)
            c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0x85) + hexDword(dispVal)
        } else if op == "ADD" {
            // Smart dispatch (35 bytes): if EITHER arg is a string ptr (≥ 0x400000),
            // call kr_concat (which auto-converts int args via kr_str_int). Else native int add.
            //
            // Layout:
            //   [0]   59                POP RCX (b)                   (1)
            //   [1]   58                POP RAX (a)                   (1)
            //   [2-6] BA 00 00 40 00    MOV EDX, 0x400000             (5)
            //   [7-9] 48 39 D0          CMP RAX, RDX                  (3)
            //   [10]  73 06             JAE +6 → 18 (.concat)         (2)
            //   [12]  48 39 D1          CMP RCX, RDX                  (3)
            //   [15]  73 01             JAE +1 → 18 (.concat)         (2)
            //   ; both ints — fallthrough int path
            //   [17]  EB 0A             JMP +10 → 29 (.intpath)       (2)
            //   .concat at 19? wait, JAE is 2 bytes...
            // Recompute:
            //   [0]   59                POP RCX                       (1)
            //   [1]   58                POP RAX                       (1)
            //   [2-6] BA 00 00 40 00    MOV EDX, 0x400000             (5)
            //   [7-9] 48 39 D0          CMP RAX, RDX                  (3)
            //   [10]  73 03             JAE +3 → 15 (skip CMP-b's JB) (2)
            // Easier to flip to "JB then JB then int_path; else fallthrough to concat":
            //   [0]   59                POP RCX (b)                   (1)
            //   [1]   58                POP RAX (a)                   (1)
            //   [2-6] BA 00 00 40 00    MOV EDX, 0x400000             (5)
            //   [7-9] 48 39 D0          CMP RAX, RDX                  (3)
            //   [10-11] 73 09           JAE +9 → 21 (.concat)         (2)
            //   [12-14] 48 39 D1        CMP RCX, RDX                  (3)
            //   [15-16] 73 04           JAE +4 → 21 (.concat)         (2)
            //   [17-19] 48 01 C8        ADD RAX, RCX (int path)       (3)
            //   [20]    EB 0A           JMP +10 → 31 (well need PUSH+JMP order check)
            // Hmm let me re-layout cleanly:
            //   [0]   59                POP RCX                       (1)
            //   [1]   58                POP RAX                       (1)
            //   [2-6] BA 00 00 40 00    MOV EDX, 0x400000             (5)
            //   [7-9] 48 39 D0          CMP RAX, RDX                  (3)
            //   [10-11] 73 09           JAE +9 → 21 (.concat)         (2)
            //   [12-14] 48 39 D1        CMP RCX, RDX                  (3)
            //   [15-16] 73 04           JAE +4 → 21 (.concat)         (2)
            //   [17-19] 48 01 C8        ADD RAX, RCX                  (3)
            //   [20]    50              PUSH RAX                      (1)
            //   [21]    ...wait conflict with .concat at 21.
            // Need int path to JMP over concat path. Layout v2:
            //   [0-1]   POP RCX, POP RAX                              (2)
            //   [2-6]   MOV EDX, 0x400000                             (5)
            //   [7-9]   CMP RAX, RDX                                  (3)
            //   [10-11] JAE +9 → 21 (.concat)                         (2)
            //   [12-14] CMP RCX, RDX                                  (3)
            //   [15-16] JAE +4 → 21 (.concat)                         (2)
            //   [17-19] ADD RAX, RCX (int path)                       (3)
            //   [20]    PUSH RAX                                      (1)  → next at 21
            // .concat at 21 collides with int path's PUSH at 20. Need int path to jump past concat.
            // Cleanest: int path at end, concat in middle, JMP from int to .end.
            //   [0-1]   POP RCX, POP RAX                              (2)
            //   [2-6]   MOV EDX, 0x400000                             (5)
            //   [7-9]   CMP RAX, RDX                                  (3)
            //   [10-11] 72 0F          JB +15 → 27 (.try_b)           (2)  -- a is string, go concat
            // Hmm getting complicated. Easiest layout:
            //   if (a >= thresh) goto concat
            //   if (b >= thresh) goto concat
            //   int_add; PUSH RAX; JMP end
            //   concat: MOV RDI, RAX; MOV RSI, RCX; CALL; PUSH RAX
            //   end:
            // Sizes: 2+5+3+2+3+2+3+1+2+3+3+5+1 = 35 bytes
            //   [0-1]   POP RCX, POP RAX                              (2)
            //   [2-6]   MOV EDX, 0x400000                             (5)
            //   [7-9]   CMP RAX, RDX                                  (3)
            //   [10-11] 73 0C           JAE +12 → 24 (.concat)        (2)
            //   [12-14] CMP RCX, RDX                                  (3)
            //   [15-16] 73 07           JAE +7 → 24 (.concat)         (2)
            //   [17-19] 48 01 C8        ADD RAX, RCX                  (3)
            //   [20]    50              PUSH RAX                      (1)
            //   [21-22] EB 0C           JMP +12 → 35 (.end)           (2)
            //   .concat at 24:
            //   [24-26] 48 89 C7        MOV RDI, RAX                  (3)
            //   [27-29] 48 89 CE        MOV RSI, RCX                  (3)
            //   [30-34] E8 dw           CALL kr_concat                (5)
            //   [35]... need PUSH after CALL — but no room before .end!
            // OK 35 bytes isn't enough for both paths. Need ~40.
            // Just bump to 38 bytes. Will need to update opByteSize.
            // FINAL layout (38 bytes):
            //   [0-1]   POP RCX, POP RAX                              (2)
            //   [2-6]   MOV EDX, 0x400000                             (5)
            //   [7-9]   CMP RAX, RDX                                  (3)
            //   [10-11] 73 0E           JAE +14 → 26 (.concat)        (2)
            //   [12-14] CMP RCX, RDX                                  (3)
            //   [15-16] 73 09           JAE +9 → 26 (.concat)         (2)
            //   [17-19] 48 01 C8        ADD RAX, RCX                  (3)
            //   [20]    50              PUSH RAX                      (1)
            //   [21-22] EB 0F           JMP +15 → 38 (.end)           (2)
            //   ; padding 21-25 not needed; .concat at 23 directly
            // Actually, more carefully:
            //   [0-1]   POP RCX, POP RAX                              (2)
            //   [2-6]   MOV EDX, 0x400000                             (5)
            //   [7-9]   CMP RAX, RDX                                  (3)
            //   [10-11] 73 ??           JAE → .concat                 (2)
            //   [12-14] CMP RCX, RDX                                  (3)
            //   [15-16] 73 ??           JAE → .concat                 (2)
            //   [17-19] 48 01 C8        ADD RAX, RCX                  (3)
            //   [20]    50              PUSH RAX                      (1)
            //   [21-22] EB ??           JMP → .end                    (2)
            //   .concat at 23:
            //   [23-25] 48 89 C7        MOV RDI, RAX                  (3)
            //   [26-28] 48 89 CE        MOV RSI, RCX                  (3)
            //   [29-33] E8 dw           CALL kr_concat                (5)
            //   [34]    50              PUSH RAX                      (1)
            //   .end at 35
            //   Total: 35 bytes ✓ (same as before)
            //   JAE #1 at [10-11]: target 23. After JAE at 12. disp = 23-12 = 11 = 0x0B
            //   JAE #2 at [15-16]: target 23. After JAE at 17. disp = 23-17 = 6 = 0x06
            //   JMP at [21-22]: target 35. After JMP at 23. disp = 35-23 = 12 = 0x0C
            //   CALL kr_concat at [29-33]: disp = krConcatVAddr - (funcStartVAddr + off + 34)
            let concatDisp = krConcatVAddr - (funcStartVAddr + off + 34)
            c = c + hexByte(0x59) + hexByte(0x58)                                  // [0-1] POP RCX, POP RAX
            c = c + hexByte(0xBA) + hexDword(0x400000)                              // [2-6] MOV EDX, 0x400000
            c = c + hexByte(0x48) + hexByte(0x39) + hexByte(0xD0)                  // [7-9] CMP RAX, RDX
            c = c + hexByte(0x73) + hexByte(0x0B)                                  // [10-11] JAE +11 → 23
            c = c + hexByte(0x48) + hexByte(0x39) + hexByte(0xD1)                  // [12-14] CMP RCX, RDX
            c = c + hexByte(0x73) + hexByte(0x06)                                  // [15-16] JAE +6 → 23
            c = c + hexByte(0x48) + hexByte(0x01) + hexByte(0xC8)                  // [17-19] ADD RAX, RCX
            c = c + hexByte(0x50)                                                  // [20] PUSH RAX
            c = c + hexByte(0xEB) + hexByte(0x0C)                                  // [21-22] JMP +12 → 35
            c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC7)                  // [23-25] MOV RDI, RAX
            c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xCE)                  // [26-28] MOV RSI, RCX
            c = c + hexByte(0xE8) + hexDword(concatDisp)                            // [29-33] CALL kr_concat
            c = c + hexByte(0x50)                                                  // [34] PUSH RAX
        } else if op == "CAT" {
            // String concat: POP RSI (b, top) ; POP RDI (a) ; CALL kr_concat ; PUSH RAX
            // CALL is at offset 2 from start of this op, ends at 7. disp computed from emit RIP.
            c = c + hexByte(0x5E)                                     // POP RSI (b)
            c = c + hexByte(0x5F)                                     // POP RDI (a)
            let catDisp = krConcatVAddr - (funcStartVAddr + off + 2 + 5)
            c = c + hexByte(0xE8) + hexDword(catDisp)
            c = c + hexByte(0x50)                                     // PUSH RAX
        } else if op == "SUB" {
            c = c + hexByte(0x59) + hexByte(0x58)
            c = c + hexByte(0x48) + hexByte(0x29) + hexByte(0xC8)
            c = c + hexByte(0x50)
        } else if op == "MUL" {
            c = c + hexByte(0x59) + hexByte(0x58)
            c = c + hexByte(0x48) + hexByte(0x0F) + hexByte(0xAF) + hexByte(0xC1)
            c = c + hexByte(0x50)
        } else if op == "DIV" || op == "MOD" {
            // POP RCX (divisor) ; POP RAX (dividend) ; CQO ; IDIV RCX ; PUSH RAX/RDX
            c = c + hexByte(0x59)                                     // POP RCX
            c = c + hexByte(0x58)                                     // POP RAX
            c = c + hexByte(0x48) + hexByte(0x99)                     // CQO (sign-extend RAX → RDX:RAX)
            c = c + hexByte(0x48) + hexByte(0xF7) + hexByte(0xF9)     // IDIV RCX
            if op == "DIV" {
                c = c + hexByte(0x50)                                 // PUSH RAX (quotient)
            } else {
                c = c + hexByte(0x52)                                 // PUSH RDX (remainder)
            }
        } else if op == "EQ" || op == "NEQ" || op == "LT" || op == "GT" || op == "LTE" || op == "GTE" {
            // POP RCX (top arg) ; POP RAX (lower arg) ; XOR EDX,EDX ; CMP RAX,RCX ; SETcc DL ; PUSH RDX
            c = c + hexByte(0x59)                                     // POP RCX
            c = c + hexByte(0x58)                                     // POP RAX
            c = c + hexByte(0x33) + hexByte(0xD2)                     // XOR EDX, EDX
            c = c + hexByte(0x48) + hexByte(0x39) + hexByte(0xC8)     // CMP RAX, RCX
            // SETcc DL — opcodes 0F 9_ C2:
            //   EQ  → SETE  (0F 94)
            //   NEQ → SETNE (0F 95)
            //   LT  → SETL  (0F 9C)  signed
            //   GT  → SETG  (0F 9F)
            //   LTE → SETLE (0F 9E)
            //   GTE → SETGE (0F 9D)
            let cc = 0x94
            if op == "NEQ" { cc = 0x95 }
            if op == "LT"  { cc = 0x9C }
            if op == "GT"  { cc = 0x9F }
            if op == "LTE" { cc = 0x9E }
            if op == "GTE" { cc = 0x9D }
            c = c + hexByte(0x0F) + hexByte(cc) + hexByte(0xC2)
            c = c + hexByte(0x52)                                     // PUSH RDX
        } else if op == "LABEL" {
            // No code; nothing to emit.
        } else if op == "JUMP" {
            let targetStr = labelOffset(labels, rest)
            let target = toInt(targetStr)
            // E9 d32. After this 5-byte instruction, position is off+5.
            let disp = target - (off + 5)
            c = c + hexByte(0xE9) + hexDword(disp)
        } else if op == "JUMPIFNOT" {
            let targetStr = labelOffset(labels, rest)
            let target = toInt(targetStr)
            // POP RAX (1) ; TEST RAX,RAX (3) ; JZ d32 (6). Total 10. After this, position = off+10.
            c = c + hexByte(0x58)                                     // POP RAX
            c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)     // TEST RAX, RAX
            let disp = target - (off + 10)
            c = c + hexByte(0x0F) + hexByte(0x84) + hexDword(disp)    // JZ d32
        } else if op == "RETURN" {
            c = c + hexByte(0x58)
            c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xEC)
            c = c + hexByte(0x5D)
            c = c + hexByte(0xC3)
        } else if op == "BUILTIN_KP" {
            // Smart kp: convert int → string before printing.
            // Layout (25 bytes):
            //   [0]   5F                       POP RDI
            //   [1-7] 48 81 FF 00 00 40 00     CMP RDI, 0x400000
            //   [8-9] 73 08                    JAE +8 → 18 (.is_str)
            //   [10-14] E8 dw                  CALL kr_str_int
            //   [15-17] 48 89 C7               MOV RDI, RAX
            //   [18-22] E8 dw                  CALL kr_print
            //   [23-24] 6A 00                  PUSH 0
            let siDisp = krStrIntVAddr - (funcStartVAddr + off + 15)
            let kpDisp = krPrintVAddr  - (funcStartVAddr + off + 23)
            c = c + hexByte(0x5F)
            c = c + hexByte(0x48) + hexByte(0x81) + hexByte(0xFF) + hexDword(0x400000)
            c = c + hexByte(0x73) + hexByte(0x08)
            c = c + hexByte(0xE8) + hexDword(siDisp)
            c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC7)
            c = c + hexByte(0xE8) + hexDword(kpDisp)
            c = c + hexByte(0x6A) + hexByte(0x00)
        } else if op == "BUILTIN_TOSTR" {
            // POP RDI ; CALL kr_str_int ; PUSH RAX
            c = c + hexByte(0x5F)
            let tsDisp = krStrIntVAddr - (funcStartVAddr + off + 6)
            c = c + hexByte(0xE8) + hexDword(tsDisp)
            c = c + hexByte(0x50)
        } else if op == "BUILTIN_TOINT" {
            // POP RDI ; CALL kr_atoi ; PUSH RAX
            c = c + hexByte(0x5F)
            let tiDisp = krAtoiVAddr - (funcStartVAddr + off + 6)
            c = c + hexByte(0xE8) + hexDword(tiDisp)
            c = c + hexByte(0x50)
        } else if op == "BUILTIN_LENGTH" {
            // POP RDI ; CALL kr_length ; PUSH RAX
            c = c + hexByte(0x5F)
            let lnDisp = krLengthVAddr - (funcStartVAddr + off + 6)
            c = c + hexByte(0xE8) + hexDword(lnDisp)
            c = c + hexByte(0x50)
        } else if op == "BUILTIN_LEN" {
            // POP RDI ; CALL kr_strlen ; PUSH RAX (string length)
            c = c + hexByte(0x5F)
            let slDisp = krStrlenVAddr - (funcStartVAddr + off + 6)
            c = c + hexByte(0xE8) + hexDword(slDisp)
            c = c + hexByte(0x50)
        } else if op == "BUILTIN_SPLIT" {
            // POP RSI (idx, top) ; POP RDI (list) ; CALL kr_split ; PUSH RAX
            c = c + hexByte(0x5E)
            c = c + hexByte(0x5F)
            let spDisp = krSplitVAddr - (funcStartVAddr + off + 7)
            c = c + hexByte(0xE8) + hexDword(spDisp)
            c = c + hexByte(0x50)
        } else if op == "BUILTIN_RANGE" {
            // POP RSI (b, top) ; POP RDI (a) ; CALL kr_range ; PUSH RAX
            c = c + hexByte(0x5E)
            c = c + hexByte(0x5F)
            let rgDisp = krRangeVAddr - (funcStartVAddr + off + 7)
            c = c + hexByte(0xE8) + hexDword(rgDisp)
            c = c + hexByte(0x50)
        } else if op == "INDEX" {
            // POP RSI (idx, top) ; POP RDI (string) ; CALL kr_index ; PUSH RAX
            c = c + hexByte(0x5E)
            c = c + hexByte(0x5F)
            let ixDisp = krIndexVAddr - (funcStartVAddr + off + 7)
            c = c + hexByte(0xE8) + hexDword(ixDisp)
            c = c + hexByte(0x50)
        } else if op == "BUILTIN_ARG" {
            // POP RDI ; CALL kr_arg ; PUSH RAX
            c = c + hexByte(0x5F)
            let agDisp = krArgVAddr - (funcStartVAddr + off + 6)
            c = c + hexByte(0xE8) + hexDword(agDisp)
            c = c + hexByte(0x50)
        } else if op == "BUILTIN_ARGCOUNT" {
            // CALL kr_argcount ; PUSH RAX
            let acDisp = krArgcountVAddr - (funcStartVAddr + off + 5)
            c = c + hexByte(0xE8) + hexDword(acDisp)
            c = c + hexByte(0x50)
        } else if op == "BUILTIN_SUBSTRING" {
            // POP RDX (end, top) ; POP RSI (start) ; POP RDI (str) ; CALL kr_substring ; PUSH RAX
            c = c + hexByte(0x5A)
            c = c + hexByte(0x5E)
            c = c + hexByte(0x5F)
            let sbDisp = krSubstringVAddr - (funcStartVAddr + off + 8)
            c = c + hexByte(0xE8) + hexDword(sbDisp)
            c = c + hexByte(0x50)
        } else if op == "BUILTIN_SB_NEW" {
            // MOV EDI, 1 ; CALL kr_alloc ; PUSH RAX  (sb starts as a 1-byte NUL)
            c = c + hexByte(0xBF) + hexDword(1)
            let snDisp = krAllocVAddr - (funcStartVAddr + off + 10)
            c = c + hexByte(0xE8) + hexDword(snDisp)
            c = c + hexByte(0x50)
        } else if op == "BUILTIN_SB_APPEND" {
            // POP RSI (s) ; POP RDI (sb) ; CALL kr_concat ; PUSH RAX
            c = c + hexByte(0x5E)
            c = c + hexByte(0x5F)
            let saDisp = krConcatVAddr - (funcStartVAddr + off + 7)
            c = c + hexByte(0xE8) + hexDword(saDisp)
            c = c + hexByte(0x50)
        } else if op == "BUILTIN_SB_TOSTR" {
            // no-op: the sb pointer IS the string. Leave it on the stack untouched.
        } else if op == "BUILTIN_READFILE" {
            // POP RDI ; CALL kr_readfile ; PUSH RAX
            c = c + hexByte(0x5F)
            let rfDisp = krReadfileVAddr - (funcStartVAddr + off + 6)
            c = c + hexByte(0xE8) + hexDword(rfDisp)
            c = c + hexByte(0x50)
        } else if op == "BUILTIN_WRITEFILE" {
            // POP RSI (content, top) ; POP RDI (path) ; CALL kr_writefile ; PUSH RAX
            c = c + hexByte(0x5E)
            c = c + hexByte(0x5F)
            let wfDisp = krWritefileVAddr - (funcStartVAddr + off + 7)
            c = c + hexByte(0xE8) + hexDword(wfDisp)
            c = c + hexByte(0x50)
        } else if op == "BUILTIN_PRINTERR" {
            // POP RDI ; CALL kr_printerr ; PUSH 0  (8 bytes)
            c = c + hexByte(0x5F)
            let peDisp = krPrinterrVAddr - (funcStartVAddr + off + 6)
            c = c + hexByte(0xE8) + hexDword(peDisp)
            c = c + hexByte(0x6A) + hexByte(0x00)
        } else if op == "BUILTIN_CHARCODE" {
            // POP RDI ; CALL kr_charcode ; PUSH RAX  (7 bytes)
            c = c + hexByte(0x5F)
            let ccDisp = krCharcodeVAddr - (funcStartVAddr + off + 6)
            c = c + hexByte(0xE8) + hexDword(ccDisp)
            c = c + hexByte(0x50)
        } else if op == "BUILTIN_FROMCHARCODE" {
            // POP RDI ; CALL kr_fromcharcode ; PUSH RAX  (7 bytes)
            c = c + hexByte(0x5F)
            let fcDisp = krFromcharcodeVAddr - (funcStartVAddr + off + 6)
            c = c + hexByte(0xE8) + hexDword(fcDisp)
            c = c + hexByte(0x50)
        } else if op == "BUILTIN_EXIT" {
            // POP RDI ; CALL kr_exit ; PUSH RAX (kr_exit doesn't return)  (7 bytes)
            c = c + hexByte(0x5F)
            let exDisp = krExitVAddr - (funcStartVAddr + off + 6)
            c = c + hexByte(0xE8) + hexDword(exDisp)
            c = c + hexByte(0x50)
        } else if op == "BUILTIN_ISDIGIT" {
            c = c + hexByte(0x5F)
            let idDisp = krIsdigitVAddr - (funcStartVAddr + off + 6)
            c = c + hexByte(0xE8) + hexDword(idDisp)
            c = c + hexByte(0x50)
        } else if op == "BUILTIN_ISALPHA" {
            c = c + hexByte(0x5F)
            let iaDisp = krIsalphaVAddr - (funcStartVAddr + off + 6)
            c = c + hexByte(0xE8) + hexDword(iaDisp)
            c = c + hexByte(0x50)
        } else if op == "BUILTIN_ABS" {
            c = c + hexByte(0x5F)
            let abDisp = krAbsVAddr - (funcStartVAddr + off + 6)
            c = c + hexByte(0xE8) + hexDword(abDisp)
            c = c + hexByte(0x50)
        } else if op == "BUILTIN_STARTSWITH" {
            // POP RSI (prefix, top) ; POP RDI (s) ; CALL ; PUSH RAX
            c = c + hexByte(0x5E)
            c = c + hexByte(0x5F)
            let swDisp = krStartswithVAddr - (funcStartVAddr + off + 7)
            c = c + hexByte(0xE8) + hexDword(swDisp)
            c = c + hexByte(0x50)
        } else if op == "CALL_FUNC" {
            // Parse "name argcount"
            let cj = 0
            while cj < len(rest) && rest[cj] != " " { cj += 1 }
            let cname = substring(rest, 0, cj)
            let cargc = 0
            if cj < len(rest) { cargc = toInt(trim(substring(rest, cj + 1, len(rest)))) }
            let cVAddr = toInt(funcVAddr(funcVAddrs, cname))
            // CALL d32: disp = target - (current_vaddr + 5)
            let curVAddr = funcStartVAddr + off
            let disp = cVAddr - (curVAddr + 5)
            c = c + hexByte(0xE8) + hexDword(disp)
            // ADD RSP, argc*8 (clean up args; harmless when argc=0)
            c = c + hexByte(0x48) + hexByte(0x81) + hexByte(0xC4) + hexDword(cargc * 8)
            // PUSH RAX (return value onto Krypton stack)
            c = c + hexByte(0x50)
        } else if op == "POP" {
            c = c + hexByte(0x5F)
        } else if op == "END_FUNC" {
            c = c + hexByte(0x48) + hexByte(0x31) + hexByte(0xC0)
            c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xEC)
            c = c + hexByte(0x5D)
            c = c + hexByte(0xC3)
        }

        if op != "LABEL" { off = off + opByteSize(op) }
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
    // Format: strTab \n ~~~ \n FUNC line + params + locals + opCount + ops \n ~~~ \n ...
    // Sections separated by lines containing only "~~~".

    // Split parsed into strTab + funcs[]
    let pn = lineCount(parsed)
    let strTab = ""
    // funcs as parallel arrays (each \n-separated by index)
    let funcNames = ""
    let funcArgcs = ""
    let funcLocalCounts = ""
    let funcParams = ""           // each line: tab-separated params for func i
    let funcOpLists = ""          // each line: \v-separated ops for func i (use vertical tab as separator)
    // Actually we need multi-line opLists per func. Use a different encoding.
    // Simpler: store as parallel arrays where each entry is its own SB.
    // Krypton doesn't have arrays — use sbAppend with a unique separator.
    // We'll use a structured single string and re-parse per func when needed.

    // Walk parsed:
    //   line 0..n: strTab lines (until "~~~")
    //   then for each func:
    //     "~~~"
    //     "FUNC name argcount localCount"
    //     params (tab-separated, possibly empty)
    //     locals (tab-separated, possibly empty)
    //     opCount
    //     opCount ops (each on its own line)

    let pi = 0
    // First, collect strTab
    while pi < pn {
        let pl = getLine(parsed, pi)
        if pl == "~~~" { break }
        if len(strTab) > 0 { strTab = strTab + "\n" }
        strTab = strTab + pl
        pi += 1
    }

    let strCount = 0
    if len(strTab) > 0 { strCount = lineCount(strTab) }

    // Now walk function blocks. Build parallel structures encoded compactly.
    // We'll use sbAppend with markers, then parse per function when emitting.
    // For simplicity, store each func as a separate "funcBlock" string in a master list.
    let funcBlocksSb = sbNew()
    let funcCount = 0
    let funcFirst = "1"

    while pi < pn {
        let pl = getLine(parsed, pi)
        if pl == "~~~" {
            pi += 1
            // Read FUNC header
            if pi >= pn { break }
            let header = getLine(parsed, pi)         // "FUNC name argcount localCount"
            pi += 1
            if pi >= pn { break }
            let pms = getLine(parsed, pi)            // params (tab-separated, possibly "")
            pi += 1
            if pi >= pn { break }
            let lcs = getLine(parsed, pi)            // locals (tab-separated, possibly "")
            pi += 1
            if pi >= pn { break }
            let opc = toInt(getLine(parsed, pi))
            pi += 1

            // Collect opc op lines
            let opSb = sbNew()
            let oi = 0
            while oi < opc && pi < pn {
                if oi > 0 { opSb = sbAppend(opSb, "\n") }
                opSb = sbAppend(opSb, getLine(parsed, pi))
                pi += 1
                oi += 1
            }

            // Encode function: header\n{params}\n{locals}\n{opCount}\n{ops}
            // Use \r as inter-block separator (rare in source).
            if funcFirst == "0" { funcBlocksSb = sbAppend(funcBlocksSb, sepChar()) }
            funcFirst = "0"
            funcBlocksSb = sbAppend(funcBlocksSb, header + "\n" + pms + "\n" + lcs + "\n" + opc + "\n" + sbToString(opSb))
            funcCount += 1
        } else {
            pi += 1
        }
    }
    let funcBlocks = sbToString(funcBlocksSb)

    // Helper: extract function block i. Returns "header\n{params}\n{locals}\n{opCount}\n{ops}"
    // Splits funcBlocks on \r.

    // Build per-function info: name, argc, localCount, params, locals, opList
    // Find __main__ index — it must be emitted first.
    let mainIdx = 0 - 1
    let fbi = 0
    let fbn = len(funcBlocks)
    let fi = 0
    let fStart = 0
    while fi <= fbn {
        let isBoundary = "0"
        if fi == fbn { isBoundary = "1" }
        if fi < fbn {
            if funcBlocks[fi] == sepChar() { isBoundary = "1" }
        }
        if isBoundary == "1" {
            let block = substring(funcBlocks, fStart, fi)
            let header = getLine(block, 0)
            let hsp1 = 0
            while hsp1 < len(header) && header[hsp1] != " " { hsp1 += 1 }
            let hsp2 = hsp1 + 1
            while hsp2 < len(header) && header[hsp2] != " " { hsp2 += 1 }
            let fname = substring(header, hsp1 + 1, hsp2)
            if fname == "__main__" { mainIdx = fbi }
            fbi += 1
            fStart = fi + 1
        }
        fi += 1
    }

    // Build emit order: __main__ first (so _start can call it), then others
    let order = ""
    if mainIdx >= 0 {
        order = "" + mainIdx
    }
    let oi = 0
    while oi < funcCount {
        if oi != mainIdx {
            if len(order) > 0 { order = order + "\n" }
            order = order + oi
        }
        oi += 1
    }

    // ── Layout pass: compute size of each function (need labels per func) ─
    let VADDR_BASE = 4194304
    let HDR_SIZE = 120
    let SEG_BASE_VADDR = VADDR_BASE + HDR_SIZE
    let startSz = startSize()
    let krpSz = krPrintSize()

    // For each function, compute labels and codeSize using computeLayout
    // We store in parallel newline-separated lists.
    let funcSizes = ""
    let funcLabelsList = ""    // one entry per func, but each entry is multi-line — encode with \r separator
    let flSb = sbNew()
    let flFirst = "1"

    // ── Layout pass: per function, compute labels and code size ──────
    let krSiSz = krStrIntSize()
    let krAlSz = krAllocSize()
    let krSlSz = krStrlenSize()
    let krCcSz = krConcatSize()
    let krAiSz = krAtoiSize()
    let krLnSz = krLengthSize()
    let krSpSz = krSplitSize()
    let krRgSz = krRangeSize()
    let krIxSz = krIndexSize()
    let krAgSz = krArgSize()
    let krAcSz = krArgcountSize()
    let krSbSz = krSubstringSize()
    let krRfSz = krReadfileSize()
    let krWfSz = krWritefileSize()
    let krPeSz = krPrinterrSize()
    let krCcdSz = krCharcodeSize()
    let krFccSz = krFromcharcodeSize()
    let krExSz = krExitSize()
    let krIdSz = krIsdigitSize()
    let krIaSz = krIsalphaSize()
    let krAbSz = krAbsSize()
    let krSwSz = krStartswithSize()

    let fIdx = 0
    while fIdx < funcCount {
        let block = extractBlock(funcBlocks, fIdx)
        let header = getLine(block, 0)
        let hsp1 = 0
        while hsp1 < len(header) && header[hsp1] != " " { hsp1 += 1 }
        let hsp2 = hsp1 + 1
        while hsp2 < len(header) && header[hsp2] != " " { hsp2 += 1 }
        let hsp3 = hsp2 + 1
        while hsp3 < len(header) && header[hsp3] != " " { hsp3 += 1 }
        let lcCount = toInt(substring(header, hsp3 + 1, len(header)))

        let blockNl = lineCount(block)
        let opSb2 = sbNew()
        let ok = 4
        while ok < blockNl {
            if ok > 4 { opSb2 = sbAppend(opSb2, "\n") }
            opSb2 = sbAppend(opSb2, getLine(block, ok))
            ok += 1
        }
        let opStr = sbToString(opSb2)

        let li = computeLayout(opStr, lcCount)
        let liNl2 = lineCount(li)
        let lab = ""
        let csize = 0
        let liSect2 = 0
        let liI2 = 0
        while liI2 < liNl2 {
            let liLn2 = getLine(li, liI2)
            if liLn2 == "---" {
                liSect2 = 1
            } else if liSect2 == 0 {
                if len(lab) > 0 { lab = lab + "\n" }
                lab = lab + liLn2
            } else {
                csize = toInt(liLn2)
            }
            liI2 += 1
        }
        if len(funcSizes) > 0 { funcSizes = funcSizes + "\n" }
        funcSizes = funcSizes + csize
        if flFirst == "0" { flSb = sbAppend(flSb, sepChar()) }
        flFirst = "0"
        flSb = sbAppend(flSb, lab)

        fIdx += 1
    }
    funcLabelsList = sbToString(flSb)

    // Compute each function's vaddr based on order
    let funcVAddrs = ""
    let totalCodeSize = 0
    let oIdx = 0
    while oIdx < funcCount {
        let fid = toInt(getLine(order, oIdx))
        let blk2 = extractBlock(funcBlocks, fid)
        let h = getLine(blk2, 0)
        let s1 = 0
        while s1 < len(h) && h[s1] != " " { s1 += 1 }
        let s2 = s1 + 1
        while s2 < len(h) && h[s2] != " " { s2 += 1 }
        let nm = substring(h, s1 + 1, s2)
        let vaddr = SEG_BASE_VADDR + startSz + totalCodeSize
        if len(funcVAddrs) > 0 { funcVAddrs = funcVAddrs + "\n" }
        funcVAddrs = funcVAddrs + nm + ":" + vaddr
        totalCodeSize = totalCodeSize + toInt(getLine(funcSizes, fid))
        oIdx += 1
    }

    // Layout: _start | functions | kr_print | kr_str_int | kr_alloc | kr_strlen | kr_concat | kr_atoi | kr_length | strings
    let krPrintVAddr  = SEG_BASE_VADDR + startSz + totalCodeSize
    let krStrIntVAddr = krPrintVAddr + krpSz
    let krAllocVAddr  = krStrIntVAddr + krSiSz
    let krStrlenVAddr = krAllocVAddr + krAlSz
    let krConcatVAddr = krStrlenVAddr + krSlSz
    let krAtoiVAddr   = krConcatVAddr + krCcSz
    let krLengthVAddr = krAtoiVAddr + krAiSz
    let krSplitVAddr  = krLengthVAddr + krLnSz
    let krRangeVAddr  = krSplitVAddr + krSpSz
    let krIndexVAddr  = krRangeVAddr + krRgSz
    let krArgVAddr    = krIndexVAddr + krIxSz
    let krArgcountVAddr = krArgVAddr + krAgSz
    let krSubstringVAddr = krArgcountVAddr + krAcSz
    let krReadfileVAddr  = krSubstringVAddr + krSbSz
    let krWritefileVAddr = krReadfileVAddr + krRfSz
    let krPrinterrVAddr  = krWritefileVAddr + krWfSz
    let krCharcodeVAddr  = krPrinterrVAddr + krPeSz
    let krFromcharcodeVAddr = krCharcodeVAddr + krCcdSz
    let krExitVAddr      = krFromcharcodeVAddr + krFccSz
    let krIsdigitVAddr   = krExitVAddr + krExSz
    let krIsalphaVAddr   = krIsdigitVAddr + krIdSz
    let krAbsVAddr       = krIsalphaVAddr + krIaSz
    let krStartswithVAddr = krAbsVAddr + krAbSz

    // String virtual addresses (after all runtime helpers)
    let stringsBase = krStartswithVAddr + krSwSz
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

    // ── Emit pass: for each function in order, emit code with resolved CALL targets ──
    let allFuncCode = ""
    let oIdx2 = 0
    while oIdx2 < funcCount {
        let fid2 = toInt(getLine(order, oIdx2))
        let blk3 = extractBlock(funcBlocks, fid2)
        let hh = getLine(blk3, 0)
        let ss1 = 0
        while ss1 < len(hh) && hh[ss1] != " " { ss1 += 1 }
        let ss2 = ss1 + 1
        while ss2 < len(hh) && hh[ss2] != " " { ss2 += 1 }
        let ss3 = ss2 + 1
        while ss3 < len(hh) && hh[ss3] != " " { ss3 += 1 }
        let argc2 = toInt(substring(hh, ss2 + 1, ss3))
        let lcCount2 = toInt(substring(hh, ss3 + 1, len(hh)))
        let blkNl = lineCount(blk3)
        let opSb3 = sbNew()
        let ok2 = 4
        while ok2 < blkNl {
            if ok2 > 4 { opSb3 = sbAppend(opSb3, "\n") }
            opSb3 = sbAppend(opSb3, getLine(blk3, ok2))
            ok2 += 1
        }
        let opStr2 = sbToString(opSb3)

        let lab2 = extractBlock(funcLabelsList, fid2)
        let nm2 = substring(hh, ss1 + 1, ss2)
        let funcStartV2 = toInt(funcVAddr(funcVAddrs, nm2))

        let codeI = emitFuncCode(opStr2, strVAddrs, argc2, lcCount2, lab2, funcVAddrs, funcStartV2, krPrintVAddr, krStrIntVAddr, krConcatVAddr, krAtoiVAddr, krLengthVAddr, krStrlenVAddr, krSplitVAddr, krRangeVAddr, krIndexVAddr, krArgVAddr, krArgcountVAddr, krSubstringVAddr, krAllocVAddr, krReadfileVAddr, krWritefileVAddr, krPrinterrVAddr, krCharcodeVAddr, krFromcharcodeVAddr, krExitVAddr, krIsdigitVAddr, krIsalphaVAddr, krAbsVAddr, krStartswithVAddr)
        allFuncCode = allFuncCode + codeI
        oIdx2 += 1
    }

    // _start: CALL __main__ (mmap'd heap initialization is in emitStartCode)
    let startVAddr = SEG_BASE_VADDR
    let mainVAddr = toInt(funcVAddr(funcVAddrs, "__main__"))
    // CALL __main__ is at offset 38 in start code (after mmap setup). After CALL = 43.
    let startCallDisp = mainVAddr - (startVAddr + 63)
    // CALL kr_atoi is at offset 46. After CALL = 51.
    let startAtoiDisp = krAtoiVAddr - (startVAddr + 71)
    let startCode = emitStartCode(startCallDisp, startAtoiDisp)

    let krPrintCode  = emitKrPrintCode()
    let krStrIntCode = emitKrStrIntCodeFinal(krStrIntVAddr, krAllocVAddr)
    let krAllocCode  = emitKrAllocCode()
    let krStrlenCode = emitKrStrlenCode()
    let krConcatCode = emitKrConcatCodeFinal(krConcatVAddr, krStrIntVAddr, krStrlenVAddr, krAllocVAddr)
    let krAtoiCode   = emitKrAtoiCode()
    let krLengthCode = emitKrLengthCode()
    let krSplitCode  = emitKrSplitCodeFinal(krSplitVAddr, krAtoiVAddr, krAllocVAddr)
    let krRangeCode  = emitKrRangeCodeFinal(krRangeVAddr, krAtoiVAddr, krAllocVAddr, krStrIntVAddr)
    let krIndexCode  = emitKrIndexCodeFinal(krIndexVAddr, krAtoiVAddr, krAllocVAddr)
    let krArgCode    = emitKrArgCodeFinal(krArgVAddr, krAtoiVAddr)
    let krArgcountCode = emitKrArgcountCode()
    let krSubstringCode = emitKrSubstringCode(krSubstringVAddr, krAtoiVAddr, krAllocVAddr)
    let krReadfileCode  = emitKrReadfileCode(krReadfileVAddr, krAllocVAddr)
    let krWritefileCode = emitKrWritefileCode(krWritefileVAddr, krStrlenVAddr)
    let krPrinterrCode  = emitKrPrinterrCode()
    let krCharcodeCode  = emitKrCharcodeCode()
    let krFromcharcodeCode = emitKrFromcharcodeCode(krFromcharcodeVAddr, krAtoiVAddr, krAllocVAddr)
    let krExitCode      = emitKrExitCode(krExitVAddr, krAtoiVAddr)
    let krIsdigitCode   = emitKrIsdigitCode()
    let krIsalphaCode   = emitKrIsalphaCode()
    let krAbsCode       = emitKrAbsCode(krAbsVAddr, krAtoiVAddr)
    let krStartswithCode = emitKrStartswithCode()

    let segment = startCode + allFuncCode + krPrintCode + krStrIntCode + krAllocCode + krStrlenCode + krConcatCode + krAtoiCode + krLengthCode + krSplitCode + krRangeCode + krIndexCode + krArgCode + krArgcountCode + krSubstringCode + krReadfileCode + krWritefileCode + krPrinterrCode + krCharcodeCode + krFromcharcodeCode + krExitCode + krIsdigitCode + krIsalphaCode + krAbsCode + krStartswithCode + strData
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
    printErr("elf: wrote " + outFile + " (" + (len(elfBytes) / 3) + " bytes, " + funcCount + " funcs, " + strCount + " strings)")
}
