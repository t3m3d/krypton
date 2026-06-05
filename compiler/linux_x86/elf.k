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
// Usage:  kcc compiler/linux_x86/elf.k input.kir output.elf

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

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  ⚠  DO NOT "SIMPLIFY" hexQword — read this before touching it. ⚠         ║
// ║                                                                          ║
// ║  The sign-extension below is LOAD-BEARING. The "obvious" one-line form   ║
// ║                                                                          ║
// ║      func hexQword(n) { emit hexDword(n) + hexDword(0) }                 ║
// ║                                                                          ║
// ║  works for every positive integer and silently corrupts every negative   ║
// ║  one. Symptom: any program that PUSH_INTs a negative literal (e.g.       ║
// ║  the optimizer folds `0 - 3` into `PUSH -3`) emits the bytes             ║
// ║      48 BF FD FF FF FF 00 00 00 00 57    ; MOV RDI, 0x00000000FFFFFFFD   ║
// ║  instead of                                                              ║
// ║      48 BF FD FF FF FF FF FF FF FF 57    ; MOV RDI, 0xFFFFFFFFFFFFFFFD   ║
// ║  At runtime the smart-int dispatch's signed CMP sees a fake-positive     ║
// ║  value bigger than 0x40000000, classifies it as a string pointer, and    ║
// ║  the kr_print loop tries to dereference address 0xFFFFFFFD → SEGV.       ║
// ║                                                                          ║
// ║  This bug ate ~half a day of bisecting and pinned the gcc-removal work   ║
// ║  for the entire Linux x86_64 path. Cost of the fix: 2 lines. Cost of    ║
// ║  the regression: full self-host bootstrap broken on every signed sub.   ║
// ║  If you find yourself "cleaning this up", STOP — write a regression     ║
// ║  test (see tests/test_arithmetic.k "sub negative result") first.        ║
// ╚══════════════════════════════════════════════════════════════════════════╝
func hexQword(n) {
    let high = 0
    if n < 0 { high = 0 - 1 }
    emit hexDword(n) + hexDword(high)
}

// Emit the bytes of an ABSOLUTE vaddr given as a load-base-relative OFFSET.
// The runtime tags any value >= VADDR_BASE (== the ELF load base) as a pointer
// and would dereference it inside toInt/%//, so we must NEVER form a full vaddr
// as a number. Instead all vaddr math is done in offset space (offsets stay in
// int range) and the base is folded in here, at emit time, as a byte-level add
// into the top byte (VADDR_BASE's only nonzero byte is the high byte of the low
// dword). This mirrors macho_arm64_self.k's "page offsets relative to base".
//
// VADDR_BASE = 0x7F000000 (top byte 0x7F). It was raised from 0x40000000 so the
// usable int range (values < VADDR_BASE) grows from 2^30 (~1.07e9) to 0x7EFFFFFF
// (~2.13e9) — covering Unix epoch seconds through ~2037. The base must stay a
// single-top-byte value <= 0x7F000000 so (a) it folds via one byte add and (b)
// every code/string vaddr (base + offset) stays a POSITIVE 32-bit sign-extended
// immediate (<= 0x7FFFFFFF). That caps program code+strings at 16 MiB of offset
// space (off < 0x01000000); these syscall-only binaries are KiB-sized, so fine.
// Heap is mmap(0) at ~0x7ffff… (47-bit), far above VADDR_BASE, so allocations
// are still correctly tagged as pointers regardless of this base.
func hexDwordVaddr(off) {
    let v = off
    let b0 = v % 256
    let b1 = (v / 256) % 256
    let b2 = (v / 65536) % 256
    let b3 = (v / 16777216) % 256 + 127  // + 0x7F = VADDR_BASE's top byte (0x7F000000)
    emit hexByte(b0) + hexByte(b1) + hexByte(b2) + hexByte(b3)
}
func hexQwordVaddr(off) { emit hexDwordVaddr(off) + hexDword(0) }

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

// Parse a quoted string literal starting at index i (must point at the opening ").
// Returns: "value\noff_after_close_quote"
//
// IMPORTANT: escape sequences are PRESERVED as 2-char text, not decoded.
// Decoding to actual control bytes happens at strData write time via
// decodeStr(). Reason: the return convention "value\npos" splits on actual
// newlines; if parseQuoted decoded \n here, any string containing one would
// get truncated by the caller's getLine. The strTab line-separated layout
// has the same constraint — strings in there must not contain real newlines.
//
// Use sbAppend rather than `v + s[i]` to avoid Krypton's numeric-+ coercion trap
// (e.g. "1" + "2" → 3 instead of "12" for digit-only chars).
func parseQuoted(s, i) {
    let vSb = sbNew()
    i += 1  // skip opening "
    while i < len(s) && s[i] != "\"" {
        if s[i] == "\\" && i + 1 < len(s) {
            // Preserve escape as 2-char text. Recognising it here is what
            // prevents a literal \" from terminating the string early.
            vSb = sbAppend(vSb, "\\")
            vSb = sbAppend(vSb, s[i + 1])
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

// Decode escape-encoded string back to raw bytes. Called only at strData write
// time (where we're emitting actual file bytes, not text that needs to round-trip
// through line-based parsing). Synthesises control bytes via fromCharCode so the
// elf.k source itself doesn't contain bare 1-byte escape literals — the seed
// can compile elf.k cleanly.
func decodeStr(s) {
    let nl = fromCharCode("10")
    let tab = fromCharCode("9")
    let cr = fromCharCode("13")
    let bs = fromCharCode("92")
    let dq = fromCharCode("34")
    let out = sbNew()
    let i = 0
    while i < len(s) {
        if s[i] == "\\" && i + 1 < len(s) {
            let c = s[i + 1]
            if c == "n" { out = sbAppend(out, nl) }
            else if c == "t" { out = sbAppend(out, tab) }
            else if c == "r" { out = sbAppend(out, cr) }
            else if c == "\\" { out = sbAppend(out, bs) }
            else if c == "\"" { out = sbAppend(out, dq) }
            else if c == "0" { }  // skip null escape (would terminate string)
            else { out = sbAppend(out, c) }
            i += 2
        } else {
            out = sbAppend(out, s[i])
            i += 1
        }
    }
    emit sbToString(out)
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

// kr_print: print a NUL-terminated string to stdout, then a trailing newline.
//   In:  RDI = string pointer
//   Out: nothing useful
//
// strlen via inline loop, then SYS_write(1, str, len), then SYS_write(1, "\n", 1).
// Trailing newline matches the C runtime's `printf("%s\n", s)` behavior so
// programs port cleanly between the C-emit path and the native ELF path.
//
// Layout (60 bytes):
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
//   ; trailing newline: write(1, "\n", 1) using stack as the buffer
//   [35] 6A 0A             PUSH 0x0A                      (2)  ; '\n' on stack
//   [37] 48 89 E6          MOV RSI, RSP                   (3)  ; arg1 = &'\n'
//   [40] BF 01 00 00 00    MOV EDI, 1                     (5)  ; fd=stdout
//   [45] BA 01 00 00 00    MOV EDX, 1                     (5)  ; len=1
//   [50] B8 01 00 00 00    MOV EAX, 1                     (5)  ; SYS_write
//   [55] 0F 05             SYSCALL                        (2)
//   [57] 58                POP RAX                        (1)  ; discard '\n'
//   [58] 5B                POP RBX                        (1)
//   [59] C3                RET                            (1)
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
    // trailing newline write — matches printf("%s\n", s) in the C runtime
    c = c + hexByte(0x6A) + hexByte(0x0A)                       // PUSH 0x0A
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xE6)       // MOV RSI, RSP
    c = c + hexByte(0xBF) + hexDword(1)                         // MOV EDI, 1
    c = c + hexByte(0xBA) + hexDword(1)                         // MOV EDX, 1
    c = c + hexByte(0xB8) + hexDword(1)                         // MOV EAX, 1
    c = c + hexByte(0x0F) + hexByte(0x05)                       // SYSCALL
    c = c + hexByte(0x58)                                       // POP RAX (discard)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krPrintSize() { emit 60 }

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
    c = c + hexByte(0x49) + hexByte(0x81) + hexByte(0xFC) + hexDwordVaddr(0) // [11-17] CMP R12, 0x400000
    c = c + hexByte(0x7D) + hexByte(0x0B)                                    // [18-19] JAE +11 → 31 (.a_ok)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)                    // [20-22] MOV RDI, R12
    c = c + hexByte(0xE8) + hexDword(dStrInt1)                               // [23-27] CALL kr_str_int
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC4)                    // [28-30] MOV R12, RAX
    // .a_ok (31): convert b (R13) if it's a small int
    c = c + hexByte(0x49) + hexByte(0x81) + hexByte(0xFD) + hexDwordVaddr(0) // [31-37] CMP R13, 0x400000
    c = c + hexByte(0x7D) + hexByte(0x0B)                                    // [38-39] JAE +11 → 51 (.b_ok)
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
    c = c + hexByte(0x48) + hexByte(0x81) + hexByte(0xFF) + hexDwordVaddr(0)
    c = c + hexByte(0x7D) + hexByte(0x04)
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

// kr_linecount: count newline-separated lines in a NUL-terminated string.
// Returns 1 + (number of internal \n), with a trailing \n NOT counted as a
// new line — matches the C runtime's `if (*(p-1) == '\n') count--;` rule.
// Empty string → 0.
//
// Layout (36 bytes):
//   [0-1]   31 C0            XOR EAX, EAX                  (2)
//   [2-4]   80 3F 00         CMP byte [RDI], 0             (3)
//   [5-6]   74 1C            JZ +28 → .ret at 35           (2)  ; empty → 0
//   [7-8]   FF C0            INC EAX                       (2)  ; non-empty → at least 1
//   .loop at 9:
//   [9-10]  8A 0F            MOV CL, [RDI]                 (2)
//   [11-12] 84 C9            TEST CL, CL                   (2)
//   [13-14] 74 0C            JZ +12 → .check at 27         (2)  ; reached NUL
//   [15-17] 80 F9 0A         CMP CL, '\n'                  (3)
//   [18-19] 75 02            JNE +2 → .skip                (2)
//   [20-21] FF C0            INC EAX                       (2)
//   .skip at 22:
//   [22-24] 48 FF C7         INC RDI                       (3)
//   [25-26] EB EE            JMP -18 → .loop at 9          (2)
//   .check at 27:
//   ; non-empty: subtract 1 if the last byte was '\n' (trailing-NL convention)
//   [27-30] 80 7F FF 0A      CMP byte [RDI-1], '\n'        (4)
//   [31-32] 75 02            JNE +2 → .ret at 35           (2)  ; skip DEC EAX
//   [33-34] FF C8            DEC EAX                       (2)
//   .ret at 35:
//   [35]    C3               RET                           (1)
func emitKrLinecountCode() {
    let c = ""
    c = c + hexByte(0x31) + hexByte(0xC0)                                       // [0-1]   XOR EAX, EAX
    c = c + hexByte(0x80) + hexByte(0x3F) + hexByte(0x00)                       // [2-4]   CMP [RDI], 0
    c = c + hexByte(0x74) + hexByte(0x1C)                                       // [5-6]   JZ → .ret at 35
    c = c + hexByte(0xFF) + hexByte(0xC0)                                       // [7-8]   INC EAX
    c = c + hexByte(0x8A) + hexByte(0x0F)                                       // [9-10]  MOV CL, [RDI]
    c = c + hexByte(0x84) + hexByte(0xC9)                                       // [11-12] TEST CL, CL
    c = c + hexByte(0x74) + hexByte(0x0C)                                       // [13-14] JZ → .check at 27
    c = c + hexByte(0x80) + hexByte(0xF9) + hexByte(0x0A)                       // [15-17] CMP CL, '\n'
    c = c + hexByte(0x75) + hexByte(0x02)                                       // [18-19] JNE +2 → .skip
    c = c + hexByte(0xFF) + hexByte(0xC0)                                       // [20-21] INC EAX
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7)                       // [22-24] INC RDI
    c = c + hexByte(0xEB) + hexByte(256 - 18)                                   // [25-26] JMP → .loop at 9
    c = c + hexByte(0x80) + hexByte(0x7F) + hexByte(0xFF) + hexByte(0x0A)       // [27-30] CMP byte [RDI-1], '\n'
    c = c + hexByte(0x75) + hexByte(0x02)                                       // [31-32] JNE +2 → .ret at 35 (skip DEC EAX at 33-34)
    c = c + hexByte(0xFF) + hexByte(0xC8)                                       // [33-34] DEC EAX
    c = c + hexByte(0xC3)                                                       // [35]    RET
    emit c
}
func krLinecountSize() { emit 36 }

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

// kr_getline: extract idx-th newline-separated line from a string.
// Identical to kr_split except separator byte is 0x0A ('\n') not 0x2C (',').
// Returns a fresh allocation containing the line (without the trailing \n).
func emitKrGetlineCodeFinal(thisVAddr, atoiVAddr, allocVAddr) {
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
    c = c + hexByte(0x74) + hexByte(0x12)
    c = c + hexByte(0x8A) + hexByte(0x07)
    c = c + hexByte(0x84) + hexByte(0xC0)
    c = c + hexByte(0x74) + hexByte(0x40)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7)
    c = c + hexByte(0x3C) + hexByte(0x0A)            // CMP AL, '\n' (was 0x2C)
    c = c + hexByte(0x75) + hexByte(256 - 18)
    c = c + hexByte(0x49) + hexByte(0xFF) + hexByte(0xCD)
    c = c + hexByte(0xEB) + hexByte(256 - 23)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xFB)
    c = c + hexByte(0x8A) + hexByte(0x07)
    c = c + hexByte(0x84) + hexByte(0xC0)
    c = c + hexByte(0x74) + hexByte(0x09)
    c = c + hexByte(0x3C) + hexByte(0x0A)            // CMP AL, '\n' (was 0x2C)
    c = c + hexByte(0x74) + hexByte(0x05)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7)
    c = c + hexByte(0xEB) + hexByte(256 - 15)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xFD)
    c = c + hexByte(0x49) + hexByte(0x29) + hexByte(0xDD)
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
func krGetlineSize() { emit 113 }

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

// kr_writebytes: hex-decode a "xHH" string and write the raw bytes to a file.
// Mirrors the C runtime kr_writebytes: scan content; for each 'x' followed by two
// hex digits, decode to a byte and write it. The backend builds the whole binary
// as a hex string (hexByte → "xHH"), so this is what actually emits the output.
//   In:  RDI = path ptr, RSI = hex content ptr (NUL-terminated)
//   Out: RAX = 1
// Strategy: open(path); over-allocate len(content) bytes; decode "xHH" triples
// into the buffer; write(fd, buf, count); close(fd). Uppercase hex only (our
// generator emits 0-9A-F), so the digit/letter split is a single CMP vs 'A'.
//
// Layout (157 bytes) — offsets in comments; relative jumps verified:
//   [54] .loop  [78] hi_digit  [81] hi_done  [96] lo_digit  [98] lo_done
//   [111] .skip  [116] .write
func emitKrWritebytesCode(thisVAddr, strlenVAddr, allocVAddr) {
    let dStrlen = strlenVAddr - (thisVAddr + 37)
    let dAlloc  = allocVAddr  - (thisVAddr + 45)
    let c = ""
    c = c + hexByte(0x41) + hexByte(0x54)                          // [0]  PUSH R12
    c = c + hexByte(0x41) + hexByte(0x55)                          // [2]  PUSH R13
    c = c + hexByte(0x41) + hexByte(0x56)                          // [4]  PUSH R14
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xF4)          // [6]  MOV R12, RSI (hexstr)
    c = c + hexByte(0xB8) + hexDword(2)                            // [9]  MOV EAX, 2 (open)
    c = c + hexByte(0xBE) + hexDword(577)                          // [14] MOV ESI, 577
    c = c + hexByte(0xBA) + hexDword(420)                          // [19] MOV EDX, 420
    c = c + hexByte(0x0F) + hexByte(0x05)                          // [24] SYSCALL
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC5)          // [26] MOV R13, RAX (fd)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)          // [29] MOV RDI, R12
    c = c + hexByte(0xE8) + hexDword(dStrlen)                      // [32] CALL kr_strlen (ends 37)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC7)          // [37] MOV RDI, RAX (hexlen)
    c = c + hexByte(0xE8) + hexDword(dAlloc)                       // [40] CALL kr_alloc (ends 45)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC6)          // [45] MOV R14, RAX (buf)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE6)          // [48] MOV RSI, R12 (p)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xF7)          // [51] MOV RDI, R14 (q)
    // .loop at 54:
    c = c + hexByte(0x8A) + hexByte(0x06)                          // [54] MOV AL, [RSI]
    c = c + hexByte(0x84) + hexByte(0xC0)                          // [56] TEST AL, AL
    c = c + hexByte(0x74) + hexByte(0x38)                          // [58] JZ .write (116)
    c = c + hexByte(0x3C) + hexByte(0x78)                          // [60] CMP AL, 'x'
    c = c + hexByte(0x75) + hexByte(0x2F)                          // [62] JNE .skip (111)
    c = c + hexByte(0x0F) + hexByte(0xB6) + hexByte(0x56) + hexByte(0x01)  // [64] MOVZX EDX,[RSI+1]
    c = c + hexByte(0x80) + hexByte(0xFA) + hexByte(0x41)          // [68] CMP DL, 'A'
    c = c + hexByte(0x72) + hexByte(0x05)                          // [71] JB hi_digit (78)
    c = c + hexByte(0x80) + hexByte(0xEA) + hexByte(0x37)          // [73] SUB DL, 0x37 (letter)
    c = c + hexByte(0xEB) + hexByte(0x03)                          // [76] JMP hi_done (81)
    c = c + hexByte(0x80) + hexByte(0xEA) + hexByte(0x30)          // [78] hi_digit: SUB DL, 0x30
    c = c + hexByte(0xC0) + hexByte(0xE2) + hexByte(0x04)          // [81] hi_done: SHL DL, 4
    c = c + hexByte(0x0F) + hexByte(0xB6) + hexByte(0x46) + hexByte(0x02)  // [84] MOVZX EAX,[RSI+2]
    c = c + hexByte(0x3C) + hexByte(0x41)                          // [88] CMP AL, 'A'
    c = c + hexByte(0x72) + hexByte(0x04)                          // [90] JB lo_digit (96)
    c = c + hexByte(0x2C) + hexByte(0x37)                          // [92] SUB AL, 0x37 (letter)
    c = c + hexByte(0xEB) + hexByte(0x02)                          // [94] JMP lo_done (98)
    c = c + hexByte(0x2C) + hexByte(0x30)                          // [96] lo_digit: SUB AL, 0x30
    c = c + hexByte(0x08) + hexByte(0xD0)                          // [98] lo_done: OR AL, DL
    c = c + hexByte(0x88) + hexByte(0x07)                          // [100] MOV [RDI], AL
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7)          // [102] INC RDI
    c = c + hexByte(0x48) + hexByte(0x83) + hexByte(0xC6) + hexByte(0x03)  // [105] ADD RSI, 3
    c = c + hexByte(0xEB) + hexByte(0xC7)                          // [109] JMP .loop (54)  disp -57
    // .skip at 111:
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC6)          // [111] INC RSI
    c = c + hexByte(0xEB) + hexByte(0xC2)                          // [114] JMP .loop (54)  disp -62
    // .write at 116:
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xFA)          // [116] MOV RDX, RDI (q)
    c = c + hexByte(0x4C) + hexByte(0x29) + hexByte(0xF2)          // [119] SUB RDX, R14 (count)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xF6)          // [122] MOV RSI, R14 (buf)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xEF)          // [125] MOV RDI, R13 (fd)
    c = c + hexByte(0xB8) + hexDword(1)                            // [128] MOV EAX, 1 (write)
    c = c + hexByte(0x0F) + hexByte(0x05)                          // [133] SYSCALL
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xEF)          // [135] MOV RDI, R13
    c = c + hexByte(0xB8) + hexDword(3)                            // [138] MOV EAX, 3 (close)
    c = c + hexByte(0x0F) + hexByte(0x05)                          // [143] SYSCALL
    c = c + hexByte(0xB8) + hexDword(1)                            // [145] MOV EAX, 1 (ret 1)
    c = c + hexByte(0x41) + hexByte(0x5E)                          // [150] POP R14
    c = c + hexByte(0x41) + hexByte(0x5D)                          // [152] POP R13
    c = c + hexByte(0x41) + hexByte(0x5C)                          // [154] POP R12
    c = c + hexByte(0xC3)                                          // [156] RET
    emit c
}
func krWritebytesSize() { emit 157 }

// ── Real StringBuilder (O(n) amortized) ────────────────────────────────────
// The old sbAppend was kr_concat (O(n²): copies the whole buffer every append),
// which made a full self-compile allocate >4 GB. These helpers give amortized
// O(n): a handle is a single heap block [cap:8][len:8][data:cap]; sbAppend writes
// in place and only re-allocs (doubling) on overflow. sbAppend returns the
// (possibly relocated) handle — callers do `sb = sbAppend(sb, x)`, so that's fine.
// sbToString returns the data pointer (NUL-terminated, maintained by sbAppend).
// kr_sbnew() → RAX = block (cap=256, len=0). Layout 30 bytes.
func emitKrSbnewCode(thisVAddr, allocVAddr) {
    let dA = allocVAddr - (thisVAddr + 10)
    let c = ""
    c = c + hexByte(0xBF) + hexDword(272)                                       // MOV EDI, 272 (16+256)
    c = c + hexByte(0xE8) + hexDword(dA)                                        // CALL kr_alloc → RAX=block
    c = c + hexByte(0x48) + hexByte(0xC7) + hexByte(0x00) + hexDword(256)       // MOV QWORD [RAX], 256 (cap)
    c = c + hexByte(0x48) + hexByte(0xC7) + hexByte(0x40) + hexByte(0x08) + hexDword(0)  // MOV QWORD [RAX+8], 0 (len)
    c = c + hexByte(0xC6) + hexByte(0x40) + hexByte(0x10) + hexByte(0x00)       // MOV BYTE [RAX+16], 0
    c = c + hexByte(0xC3)
    emit c
}
func krSbnewSize() { emit 30 }

// kr_sbappend(RDI=handle, RSI=s) → RAX = handle (possibly relocated). 124 bytes.
//   need = len+slen+1; if need>cap: newcap=need*2, alloc, copy [hdr..hdr+16+len];
//   then memcpy s into data[len..], len+=slen, data[len]=0.
func emitKrSbappendCode(thisVAddr, strlenVAddr, allocVAddr) {
    let d1 = strlenVAddr - (thisVAddr + 21)
    let d2 = allocVAddr  - (thisVAddr + 58)
    let c = ""
    c = c + hexByte(0x53)                                       // [0]  PUSH RBX
    c = c + hexByte(0x41) + hexByte(0x54)                       // [1]  PUSH R12
    c = c + hexByte(0x41) + hexByte(0x55)                       // [3]  PUSH R13
    c = c + hexByte(0x41) + hexByte(0x56)                       // [5]  PUSH R14
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xFB)       // [7]  MOV RBX, RDI (handle)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xF4)       // [10] MOV R12, RSI (s)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)       // [13] MOV RDI, R12
    c = c + hexByte(0xE8) + hexDword(d1)                        // [16] CALL kr_strlen → RAX=slen
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC5)       // [21] MOV R13, RAX (slen)
    c = c + hexByte(0x4C) + hexByte(0x8B) + hexByte(0x73) + hexByte(0x08)  // [24] MOV R14, [RBX+8] (len)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xF1)       // [28] MOV RCX, R14
    c = c + hexByte(0x4C) + hexByte(0x01) + hexByte(0xE9)       // [31] ADD RCX, R13
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC1)       // [34] INC RCX (need)
    c = c + hexByte(0x48) + hexByte(0x3B) + hexByte(0x0B)       // [37] CMP RCX, [RBX] (cap)
    c = c + hexByte(0x76) + hexByte(0x28)                       // [40] JBE .nogrow(82)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC8)       // [42] MOV RAX, RCX (need)
    c = c + hexByte(0x48) + hexByte(0xD1) + hexByte(0xE0)       // [45] SHL RAX, 1 (newcap)
    c = c + hexByte(0x50)                                       // [48] PUSH RAX
    c = c + hexByte(0x48) + hexByte(0x8D) + hexByte(0x78) + hexByte(0x10)  // [49] LEA RDI,[RAX+16]
    c = c + hexByte(0xE8) + hexDword(d2)                        // [53] CALL kr_alloc → RAX=nb
    c = c + hexByte(0x5A)                                       // [58] POP RDX (newcap)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDE)       // [59] MOV RSI, RBX (old)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC7)       // [62] MOV RDI, RAX (nb)
    c = c + hexByte(0x50)                                       // [65] PUSH RAX
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xF1)       // [66] MOV RCX, R14 (len)
    c = c + hexByte(0x48) + hexByte(0x83) + hexByte(0xC1) + hexByte(0x10)  // [69] ADD RCX, 16
    c = c + hexByte(0xF3) + hexByte(0xA4)                       // [73] REP MOVSB
    c = c + hexByte(0x58)                                       // [75] POP RAX (nb)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0x10)       // [76] MOV [RAX], RDX (cap=newcap)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC3)       // [79] MOV RBX, RAX (new handle)
    // .nogrow at 82:
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDF)       // [82] MOV RDI, RBX
    c = c + hexByte(0x48) + hexByte(0x83) + hexByte(0xC7) + hexByte(0x10)  // [85] ADD RDI, 16
    c = c + hexByte(0x4C) + hexByte(0x01) + hexByte(0xF7)       // [89] ADD RDI, R14 (data+len)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE6)       // [92] MOV RSI, R12 (s)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE9)       // [95] MOV RCX, R13 (slen)
    c = c + hexByte(0xF3) + hexByte(0xA4)                       // [98] REP MOVSB (append)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xF0)       // [100] MOV RAX, R14 (len)
    c = c + hexByte(0x4C) + hexByte(0x01) + hexByte(0xE8)       // [103] ADD RAX, R13 (newlen)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0x43) + hexByte(0x08)  // [106] MOV [RBX+8], RAX
    c = c + hexByte(0xC6) + hexByte(0x07) + hexByte(0x00)       // [110] MOV BYTE [RDI], 0
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xD8)       // [113] MOV RAX, RBX (return handle)
    c = c + hexByte(0x41) + hexByte(0x5E)                       // [116] POP R14
    c = c + hexByte(0x41) + hexByte(0x5D)                       // [118] POP R13
    c = c + hexByte(0x41) + hexByte(0x5C)                       // [120] POP R12
    c = c + hexByte(0x5B)                                       // [122] POP RBX
    c = c + hexByte(0xC3)                                       // [123] RET
    emit c
}
func krSbappendSize() { emit 124 }

// kr_sbtostring(RDI=handle) → RAX = data ptr (handle+16). 5 bytes.
func emitKrSbtostringCode() {
    let c = ""
    c = c + hexByte(0x48) + hexByte(0x8D) + hexByte(0x47) + hexByte(0x10)  // LEA RAX,[RDI+16]
    c = c + hexByte(0xC3)
    emit c
}
func krSbtostringSize() { emit 5 }

// kr_printerr: like kr_print, but writes to stderr (fd 2) instead of stdout.
// Also appends a trailing newline to match printf("%s\n", s) parity.
//   In:  RDI = string ptr (NUL-terminated)
//   Out: nothing
//
// Identical to kr_print except every fd is 2 instead of 1. Layout 60 bytes.
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
    c = c + hexByte(0xBF) + hexDword(2)         // fd=2 (stderr)
    c = c + hexByte(0xB8) + hexDword(1)
    c = c + hexByte(0x0F) + hexByte(0x05)
    // trailing newline write to fd=2
    c = c + hexByte(0x6A) + hexByte(0x0A)                       // PUSH 0x0A
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xE6)       // MOV RSI, RSP
    c = c + hexByte(0xBF) + hexDword(2)                         // MOV EDI, 2
    c = c + hexByte(0xBA) + hexDword(1)                         // MOV EDX, 1
    c = c + hexByte(0xB8) + hexDword(1)                         // MOV EAX, 1
    c = c + hexByte(0x0F) + hexByte(0x05)                       // SYSCALL
    c = c + hexByte(0x58)                                       // POP RAX (discard)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krPrinterrSize() { emit 60 }

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

// kr_istruthy: dispatch on smart-int, return 1 if value is "truthy" else 0.
//
// Krypton truthiness (per Spec.md):
//   - small int (RDI < 0x40000000):  truthy iff RDI != 0
//   - string ptr (RDI >= 0x40000000): truthy iff string is NOT one of:
//                                       ""  (empty)
//                                       "0" (the digit zero)
//                                       "false"
//
// Previously this only checked the empty case, so isTruthy("0") and
// isTruthy("false") wrongly returned 1. The boolean-literal change in
// 1.4.0 (true → "true", false → "false") made this a load-bearing bug
// — `if false { ... }` would run because "false" looked truthy.
//
// Layout (79 bytes):
//   [0-6]   CMP RDI, 0x40000000             (7)
//   [7-8]   7D 0A   JGE .str_path → 19      (2)
//   .int_path at 9:
//   [9-11]  TEST RDI, RDI                   (3)
//   [12-14] SETNE AL                        (3)
//   [15-17] MOVZX EAX, AL                   (3)
//   [18]    RET                             (1)
//   .str_path at 19:
//   [19-21] CMP byte [RDI], 0               (3)
//   [22-23] 74 2E   JZ .falsy → 70          (2)
//   [24-26] CMP byte [RDI], '0'             (3)
//   [27-28] 75 06   JNE .not_zero → 35      (2)
//   [29-32] CMP byte [RDI+1], 0             (4)
//   [33-34] 74 23   JZ .falsy → 70          (2)
//   .not_zero at 35:
//   [35-37] CMP byte [RDI], 'f'             (3)
//   [38-39] 75 21   JNE .truthy → 73        (2)
//   [40-43] CMP byte [RDI+1], 'a'           (4)
//   [44-45] 75 1B   JNE .truthy → 73        (2)
//   [46-49] CMP byte [RDI+2], 'l'           (4)
//   [50-51] 75 15   JNE .truthy → 73        (2)
//   [52-55] CMP byte [RDI+3], 's'           (4)
//   [56-57] 75 0F   JNE .truthy → 73        (2)
//   [58-61] CMP byte [RDI+4], 'e'           (4)
//   [62-63] 75 09   JNE .truthy → 73        (2)
//   [64-67] CMP byte [RDI+5], 0             (4)
//   [68-69] 75 03   JNE .truthy → 73        (2)
//   .falsy at 70:
//   [70-71] XOR EAX, EAX                    (2)
//   [72]    RET                             (1)
//   .truthy at 73:
//   [73-77] MOV EAX, 1                      (5)
//   [78]    RET                             (1)
func emitKrIstruthyCode(thisVAddr, atoiVAddr) {
    let c = ""
    c = c + hexByte(0x48) + hexByte(0x81) + hexByte(0xFF) + hexDwordVaddr(0)  // [0-6] CMP RDI, 0x40000000
    c = c + hexByte(0x7D) + hexByte(0x0A)                                          // [7-8] JGE → .str_path at 19
    // .int_path at 9
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xFF)                          // [9-11] TEST RDI, RDI
    c = c + hexByte(0x0F) + hexByte(0x95) + hexByte(0xC0)                          // [12-14] SETNE AL
    c = c + hexByte(0x0F) + hexByte(0xB6) + hexByte(0xC0)                          // [15-17] MOVZX EAX, AL
    c = c + hexByte(0xC3)                                                          // [18] RET
    // .str_path at 19
    c = c + hexByte(0x80) + hexByte(0x3F) + hexByte(0x00)                          // [19-21] CMP [RDI], 0
    c = c + hexByte(0x74) + hexByte(0x2E)                                          // [22-23] JZ → .falsy at 70
    c = c + hexByte(0x80) + hexByte(0x3F) + hexByte(0x30)                          // [24-26] CMP [RDI], '0'
    c = c + hexByte(0x75) + hexByte(0x06)                                          // [27-28] JNE → .not_zero at 35
    c = c + hexByte(0x80) + hexByte(0x7F) + hexByte(0x01) + hexByte(0x00)          // [29-32] CMP [RDI+1], 0
    c = c + hexByte(0x74) + hexByte(0x23)                                          // [33-34] JZ → .falsy at 70
    // .not_zero at 35: check for "false\0"
    c = c + hexByte(0x80) + hexByte(0x3F) + hexByte(0x66)                          // [35-37] CMP [RDI], 'f'
    c = c + hexByte(0x75) + hexByte(0x21)                                          // [38-39] JNE → .truthy at 73
    c = c + hexByte(0x80) + hexByte(0x7F) + hexByte(0x01) + hexByte(0x61)          // [40-43] CMP [RDI+1], 'a'
    c = c + hexByte(0x75) + hexByte(0x1B)                                          // [44-45] JNE → .truthy at 73
    c = c + hexByte(0x80) + hexByte(0x7F) + hexByte(0x02) + hexByte(0x6C)          // [46-49] CMP [RDI+2], 'l'
    c = c + hexByte(0x75) + hexByte(0x15)                                          // [50-51] JNE → .truthy at 73
    c = c + hexByte(0x80) + hexByte(0x7F) + hexByte(0x03) + hexByte(0x73)          // [52-55] CMP [RDI+3], 's'
    c = c + hexByte(0x75) + hexByte(0x0F)                                          // [56-57] JNE → .truthy at 73
    c = c + hexByte(0x80) + hexByte(0x7F) + hexByte(0x04) + hexByte(0x65)          // [58-61] CMP [RDI+4], 'e'
    c = c + hexByte(0x75) + hexByte(0x09)                                          // [62-63] JNE → .truthy at 73
    c = c + hexByte(0x80) + hexByte(0x7F) + hexByte(0x05) + hexByte(0x00)          // [64-67] CMP [RDI+5], 0
    c = c + hexByte(0x75) + hexByte(0x03)                                          // [68-69] JNE → .truthy at 73
    // .falsy at 70
    c = c + hexByte(0x31) + hexByte(0xC0)                                          // [70-71] XOR EAX, EAX
    c = c + hexByte(0xC3)                                                          // [72] RET
    // .truthy at 73
    c = c + hexByte(0xB8) + hexDword(1)                                            // [73-77] MOV EAX, 1
    c = c + hexByte(0xC3)                                                          // [78] RET
    emit c
}
func krIstruthySize() { emit 79 }

// kr_trim: strip leading and trailing space (0x20) characters from s.
// Returns a fresh allocation. Tab/newline/CR not handled (rare in trim usage).
//
// Layout (65 bytes):
//   [0]     53            PUSH RBX                                 (1)
//   [1-3]   48 89 FB      MOV RBX, RDI                              (3)
//   .lead at [4]:
//   [4-6]   80 3B 20      CMP byte [RBX], 0x20                      (3)
//   [7-8]   75 05         JNE +5 → .find_end at 14                  (2)
//   [9-11]  48 FF C3      INC RBX                                   (3)
//   [12-13] EB F6         JMP -10 → .lead at 4                      (2)
//   .find_end at [14]:
//   [14-16] 48 89 DF      MOV RDI, RBX                              (3)
//   [17-21] E8 dw         CALL kr_strlen                            (5)
//   [22-24] 48 89 C1      MOV RCX, RAX                              (3)
//   .trail at [25]:
//   [25-27] 48 85 C9      TEST RCX, RCX                             (3)
//   [28-29] 74 0C         JZ +12 → .copy at 42                      (2)
//   [30-34] 80 7C 0B FF 20  CMP byte [RBX+RCX-1], 0x20              (5)
//   [35-36] 75 05         JNE +5 → .copy at 42                      (2)
//   [37-39] 48 FF C9      DEC RCX                                   (3)
//   [40-41] EB EF         JMP -17 → .trail at 25                    (2)
//   .copy at [42]:
//   [42]    51            PUSH RCX                                  (1)
//   [43-46] 48 8D 79 01   LEA RDI, [RCX+1]                          (4)
//   [47-51] E8 dw         CALL kr_alloc                             (5)
//   [52]    59            POP RCX                                   (1)
//   [53]    50            PUSH RAX                                  (1)
//   [54-56] 48 89 C7      MOV RDI, RAX                              (3)
//   [57-59] 48 89 DE      MOV RSI, RBX                              (3)
//   [60-61] F3 A4         REP MOVSB                                 (2)
//   [62]    58            POP RAX                                   (1)
//   [63]    5B            POP RBX                                   (1)
//   [64]    C3            RET                                       (1)
func emitKrTrimCode(thisVAddr, strlenVAddr, allocVAddr) {
    // Strips ALL whitespace (bytes 1..0x20: tab, LF, VT, FF, CR, space) from both
    // ends — not just 0x20. Leading scan is NUL-safe via the unsigned (c-1)<=0x1F
    // test (NUL -> 0xFF, so it stops). Matches macOS kr_trim (commit bb86dc47).
    let dStrlen = strlenVAddr - (thisVAddr + 25)
    let dAlloc  = allocVAddr  - (thisVAddr + 55)
    let c = ""
    c = c + hexByte(0x53)                                            // [0]  push rbx
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xFB)            // [1]  mov rbx, rdi
    c = c + hexByte(0x8A) + hexByte(0x03)                            // [4]  mov al, [rbx]
    c = c + hexByte(0x2C) + hexByte(0x01)                            // [6]  sub al, 1
    c = c + hexByte(0x3C) + hexByte(0x1F)                            // [8]  cmp al, 0x1F
    c = c + hexByte(0x77) + hexByte(0x05)                            // [10] ja +5 -> [17] (not whitespace/NUL)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC3)            // [12] inc rbx
    c = c + hexByte(0xEB) + hexByte(256 - 13)                        // [15] jmp -13 -> [4]
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDF)            // [17] mov rdi, rbx
    c = c + hexByte(0xE8) + hexDword(dStrlen)                        // [20] call kr_strlen
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC1)            // [25] mov rcx, rax
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC9)            // [28] test rcx, rcx
    c = c + hexByte(0x74) + hexByte(0x0C)                            // [31] jz +12 -> [45]
    c = c + hexByte(0x80) + hexByte(0x7C) + hexByte(0x0B) + hexByte(0xFF) + hexByte(0x21) // [33] cmp byte [rbx+rcx-1], 0x21
    c = c + hexByte(0x73) + hexByte(0x05)                            // [38] jae +5 -> [45] (not whitespace)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC9)            // [40] dec rcx
    c = c + hexByte(0xEB) + hexByte(256 - 17)                        // [43] jmp -17 -> [28]
    c = c + hexByte(0x51)                                            // [45] push rcx
    c = c + hexByte(0x48) + hexByte(0x8D) + hexByte(0x79) + hexByte(0x01) // [46] lea rdi, [rcx+1]
    c = c + hexByte(0xE8) + hexDword(dAlloc)                         // [50] call kr_alloc
    c = c + hexByte(0x59)                                            // [55] pop rcx
    c = c + hexByte(0x50)                                            // [56] push rax
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC7)            // [57] mov rdi, rax
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDE)            // [60] mov rsi, rbx
    c = c + hexByte(0xF3) + hexByte(0xA4)                            // [63] rep movsb
    c = c + hexByte(0x58)                                            // [65] pop rax
    c = c + hexByte(0x5B)                                            // [66] pop rbx
    c = c + hexByte(0xC3)                                            // [67] ret
    emit c
}
func krTrimSize() { emit 68 }

// kr_toupper: ASCII uppercase. Allocates a fresh string with each lowercase
// letter (a-z, 0x61..0x7A) shifted by -32. Other bytes copied verbatim.
//
// Layout (60 bytes):
//   [0]     53            PUSH RBX                                  (1)
//   [1-3]   48 89 FB      MOV RBX, RDI                              (3)
//   [4-8]   E8 dw         CALL kr_strlen                            (5)
//   [9-11]  48 89 C1      MOV RCX, RAX                              (3)
//   [12]    51            PUSH RCX                                  (1)
//   [13-16] 48 8D 79 01   LEA RDI, [RCX+1]                          (4)
//   [17-21] E8 dw         CALL kr_alloc                             (5)
//   [22]    59            POP RCX                                   (1)
//   [23]    50            PUSH RAX                                  (1)
//   [24-26] 48 89 C7      MOV RDI, RAX                              (3)
//   .loop at [27]:
//   [27-29] 48 85 C9      TEST RCX, RCX                             (3)
//   [30-31] 74 19         JZ +25 → .done at 57                      (2)
//   [32-33] 8A 03         MOV AL, [RBX]                             (2)
//   [34-35] 3C 61         CMP AL, 'a'                               (2)
//   [36-37] 72 06         JB +6 → .copy at 44                       (2)
//   [38-39] 3C 7A         CMP AL, 'z'                               (2)
//   [40-41] 77 02         JA +2 → .copy at 44                       (2)
//   [42-43] 2C 20         SUB AL, 32                                (2)
//   .copy at [44]:
//   [44-45] 88 07         MOV [RDI], AL                             (2)
//   [46-48] 48 FF C7      INC RDI                                   (3)
//   [49-51] 48 FF C3      INC RBX                                   (3)
//   [52-54] 48 FF C9      DEC RCX                                   (3)
//   [55-56] EB E2         JMP -30 → .loop at 27                     (2)
//   .done at [57]:
//   [57]    58            POP RAX                                   (1)
//   [58]    5B            POP RBX                                   (1)
//   [59]    C3            RET                                       (1)
func emitKrToupperCode(thisVAddr, strlenVAddr, allocVAddr) {
    let dStrlen = strlenVAddr - (thisVAddr + 9)
    let dAlloc  = allocVAddr  - (thisVAddr + 22)
    let c = ""
    c = c + hexByte(0x53)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xFB)
    c = c + hexByte(0xE8) + hexDword(dStrlen)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC1)
    c = c + hexByte(0x51)
    c = c + hexByte(0x48) + hexByte(0x8D) + hexByte(0x79) + hexByte(0x01)
    c = c + hexByte(0xE8) + hexDword(dAlloc)
    c = c + hexByte(0x59)
    c = c + hexByte(0x50)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC7)
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC9)
    c = c + hexByte(0x74) + hexByte(0x19)
    c = c + hexByte(0x8A) + hexByte(0x03)
    c = c + hexByte(0x3C) + hexByte(0x61)
    c = c + hexByte(0x72) + hexByte(0x06)
    c = c + hexByte(0x3C) + hexByte(0x7A)
    c = c + hexByte(0x77) + hexByte(0x02)
    c = c + hexByte(0x2C) + hexByte(0x20)
    c = c + hexByte(0x88) + hexByte(0x07)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC3)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC9)
    c = c + hexByte(0xEB) + hexByte(256 - 30)
    c = c + hexByte(0x58)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krToupperSize() { emit 60 }

// kr_tolower: ASCII lowercase. Mirror of kr_toupper, range 'A'..'Z' shifted +32.
// Same 60-byte layout, just CMP imms 0x41/0x5A and ADD AL, 32 (instead of SUB).
func emitKrTolowerCode(thisVAddr, strlenVAddr, allocVAddr) {
    let dStrlen = strlenVAddr - (thisVAddr + 9)
    let dAlloc  = allocVAddr  - (thisVAddr + 22)
    let c = ""
    c = c + hexByte(0x53)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xFB)
    c = c + hexByte(0xE8) + hexDword(dStrlen)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC1)
    c = c + hexByte(0x51)
    c = c + hexByte(0x48) + hexByte(0x8D) + hexByte(0x79) + hexByte(0x01)
    c = c + hexByte(0xE8) + hexDword(dAlloc)
    c = c + hexByte(0x59)
    c = c + hexByte(0x50)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC7)
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC9)
    c = c + hexByte(0x74) + hexByte(0x19)
    c = c + hexByte(0x8A) + hexByte(0x03)
    c = c + hexByte(0x3C) + hexByte(0x41)            // CMP AL, 'A'
    c = c + hexByte(0x72) + hexByte(0x06)
    c = c + hexByte(0x3C) + hexByte(0x5A)            // CMP AL, 'Z'
    c = c + hexByte(0x77) + hexByte(0x02)
    c = c + hexByte(0x04) + hexByte(0x20)            // ADD AL, 32
    c = c + hexByte(0x88) + hexByte(0x07)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC3)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC9)
    c = c + hexByte(0xEB) + hexByte(256 - 30)
    c = c + hexByte(0x58)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krTolowerSize() { emit 60 }

// kr_reverse: byte-reverse a string. Allocates a fresh string of same length.
//
// Layout (58 bytes):
//   [0]     53                PUSH RBX                              (1)
//   [1-3]   48 89 FB          MOV RBX, RDI                          (3)
//   [4-8]   E8 dw             CALL kr_strlen                        (5)
//   [9-11]  48 89 C1          MOV RCX, RAX                          (3)
//   [12]    51                PUSH RCX                              (1)
//   [13-16] 48 8D 79 01       LEA RDI, [RCX+1]                      (4)
//   [17-21] E8 dw             CALL kr_alloc                         (5)
//   [22]    59                POP RCX                               (1)
//   [23]    50                PUSH RAX                              (1)
//   [24-26] 48 89 C7          MOV RDI, RAX                          (3)
//   [27-29] 48 85 C9          TEST RCX, RCX                         (3)
//   [30-31] 74 17             JZ +23 → .done at 55                  (2)
//   [32-36] 48 8D 74 0B FF    LEA RSI, [RBX+RCX-1]                  (5)
//   .loop at [37]:
//   [37-38] 8A 06             MOV AL, [RSI]                         (2)
//   [39-40] 88 07             MOV [RDI], AL                         (2)
//   [41-43] 48 FF C7          INC RDI                               (3)
//   [44-46] 48 FF CE          DEC RSI                               (3)
//   [47-49] 48 FF C9          DEC RCX                               (3)
//   [50-52] 48 85 C9          TEST RCX, RCX                         (3)
//   [53-54] 75 EE             JNZ -18 → .loop at 37                 (2)
//   .done at [55]:
//   [55]    58                POP RAX                               (1)
//   [56]    5B                POP RBX                               (1)
//   [57]    C3                RET                                   (1)
func emitKrReverseCode(thisVAddr, strlenVAddr, allocVAddr) {
    let dStrlen = strlenVAddr - (thisVAddr + 9)
    let dAlloc  = allocVAddr  - (thisVAddr + 22)
    let c = ""
    c = c + hexByte(0x53)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xFB)
    c = c + hexByte(0xE8) + hexDword(dStrlen)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC1)
    c = c + hexByte(0x51)
    c = c + hexByte(0x48) + hexByte(0x8D) + hexByte(0x79) + hexByte(0x01)
    c = c + hexByte(0xE8) + hexDword(dAlloc)
    c = c + hexByte(0x59)
    c = c + hexByte(0x50)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC7)
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC9)
    c = c + hexByte(0x74) + hexByte(0x17)
    c = c + hexByte(0x48) + hexByte(0x8D) + hexByte(0x74) + hexByte(0x0B) + hexByte(0xFF)
    c = c + hexByte(0x8A) + hexByte(0x06)
    c = c + hexByte(0x88) + hexByte(0x07)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xCE)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC9)
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC9)
    c = c + hexByte(0x75) + hexByte(256 - 18)
    c = c + hexByte(0x58)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krReverseSize() { emit 58 }

// kr_pow: integer power. RDI = base, RSI = exp (both string-or-int via kr_atoi).
// Returns RAX = base^exp as a small int. Overflow truncates silently.
//
// Layout (54 bytes):
//   [0]     53                PUSH RBX                              (1)
//   [1-2]   41 54             PUSH R12                              (2)
//   [3-5]   48 89 FB          MOV RBX, RDI                          (3)
//   [6-8]   49 89 F4          MOV R12, RSI                          (3)
//   [9-11]  48 89 DF          MOV RDI, RBX                          (3)
//   [12-16] E8 dd             CALL kr_atoi                          (5)  ; ends at 17
//   [17-19] 48 89 C3          MOV RBX, RAX                          (3)
//   [20-22] 4C 89 E7          MOV RDI, R12                          (3)
//   [23-27] E8 dd             CALL kr_atoi                          (5)  ; ends at 28
//   [28-30] 48 89 C1          MOV RCX, RAX                          (3)
//   [31-35] B8 01 00 00 00    MOV EAX, 1                            (5)
//   [36-38] 48 85 C9          TEST RCX, RCX                         (3)
//   [39-40] 74 09             JZ +9 → .done at 50                   (2)
//   .loop at [41]:
//   [41-44] 48 0F AF C3       IMUL RAX, RBX                         (4)
//   [45-47] 48 FF C9          DEC RCX                               (3)
//   [48-49] 75 F7             JNZ -9 → .loop at 41                  (2)
//   .done at [50]:
//   [50-51] 41 5C             POP R12                               (2)
//   [52]    5B                POP RBX                               (1)
//   [53]    C3                RET                                   (1)
func emitKrPowCode(thisVAddr, atoiVAddr) {
    let dAtoi1 = atoiVAddr - (thisVAddr + 17)
    let dAtoi2 = atoiVAddr - (thisVAddr + 28)
    let c = ""
    c = c + hexByte(0x53)
    c = c + hexByte(0x41) + hexByte(0x54)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xFB)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xF4)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDF)
    c = c + hexByte(0xE8) + hexDword(dAtoi1)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC3)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)
    c = c + hexByte(0xE8) + hexDword(dAtoi2)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC1)
    c = c + hexByte(0xB8) + hexByte(0x01) + hexByte(0x00) + hexByte(0x00) + hexByte(0x00)
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC9)
    c = c + hexByte(0x74) + hexByte(0x09)
    c = c + hexByte(0x48) + hexByte(0x0F) + hexByte(0xAF) + hexByte(0xC3)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC9)
    c = c + hexByte(0x75) + hexByte(256 - 9)
    c = c + hexByte(0x41) + hexByte(0x5C)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krPowSize() { emit 54 }

// kr_min / kr_max: RDI = a, RSI = b (string-or-int via kr_atoi). Returns the
// smaller / larger raw signed int in RAX. kr_atoi clobbers RAX/RDI/RCX/RDX/R8
// only — RBX/RSI survive, so a_raw is held in RBX across the 2nd atoi. (27 bytes)
//   [0-4]   E8 d32        CALL kr_atoi    RDI(a) -> RAX
//   [5-7]   48 89 C3      MOV RBX, RAX    a_raw
//   [8-10]  48 89 F7      MOV RDI, RSI    b
//   [11-15] E8 d32        CALL kr_atoi    RDI(b) -> RAX (b_raw)
//   [16-18] 48 39 C3      CMP RBX, RAX
//   [19-22] 48 0F 4F D8   CMOVG RBX, RAX  (min: if a>b, RBX=b)   [CMOVL=max]
//   [23-25] 48 89 D8      MOV RAX, RBX
//   [26]    C3            RET
func emitKrMinCode(thisVAddr, atoiVAddr) {
    let c = ""
    c = c + hexByte(0xE8) + hexDword(atoiVAddr - (thisVAddr + 5))
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC3)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xF7)
    c = c + hexByte(0xE8) + hexDword(atoiVAddr - (thisVAddr + 16))
    c = c + hexByte(0x48) + hexByte(0x39) + hexByte(0xC3)
    c = c + hexByte(0x48) + hexByte(0x0F) + hexByte(0x4F) + hexByte(0xD8)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xD8)
    c = c + hexByte(0xC3)
    emit c
}
func krMinSize() { emit 27 }
func emitKrMaxCode(thisVAddr, atoiVAddr) {
    let c = ""
    c = c + hexByte(0xE8) + hexDword(atoiVAddr - (thisVAddr + 5))
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC3)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xF7)
    c = c + hexByte(0xE8) + hexDword(atoiVAddr - (thisVAddr + 16))
    c = c + hexByte(0x48) + hexByte(0x39) + hexByte(0xC3)
    c = c + hexByte(0x48) + hexByte(0x0F) + hexByte(0x4C) + hexByte(0xD8)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xD8)
    c = c + hexByte(0xC3)
    emit c
}
func krMaxSize() { emit 27 }

// Bitwise builtins (parity with x64.k's kr_bit*/kr_sh*). Each kr_atoi's its
// arg(s) to raw ints (RBX/RSI survive kr_atoi), does the op, returns raw int in
// RAX — same raw-int convention as pow (results >= int ceiling share pow's
// existing tag limit). 2-arg shape (20B): atoi a -> RBX; atoi b -> RAX; op.
func emitKrBitandCode(thisVAddr, atoiVAddr) {
    let c = ""
    c = c + hexByte(0xE8) + hexDword(atoiVAddr - (thisVAddr + 5))
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC3)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xF7)
    c = c + hexByte(0xE8) + hexDword(atoiVAddr - (thisVAddr + 16))
    c = c + hexByte(0x48) + hexByte(0x21) + hexByte(0xD8)
    c = c + hexByte(0xC3)
    emit c
}
func krBitandSize() { emit 20 }
func emitKrBitorCode(thisVAddr, atoiVAddr) {
    let c = ""
    c = c + hexByte(0xE8) + hexDword(atoiVAddr - (thisVAddr + 5))
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC3)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xF7)
    c = c + hexByte(0xE8) + hexDword(atoiVAddr - (thisVAddr + 16))
    c = c + hexByte(0x48) + hexByte(0x09) + hexByte(0xD8)
    c = c + hexByte(0xC3)
    emit c
}
func krBitorSize() { emit 20 }
func emitKrBitxorCode(thisVAddr, atoiVAddr) {
    let c = ""
    c = c + hexByte(0xE8) + hexDword(atoiVAddr - (thisVAddr + 5))
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC3)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xF7)
    c = c + hexByte(0xE8) + hexDword(atoiVAddr - (thisVAddr + 16))
    c = c + hexByte(0x48) + hexByte(0x31) + hexByte(0xD8)
    c = c + hexByte(0xC3)
    emit c
}
func krBitxorSize() { emit 20 }
// 1-arg (9B): atoi a -> RAX; NOT RAX.
func emitKrBitnotCode(thisVAddr, atoiVAddr) {
    let c = ""
    c = c + hexByte(0xE8) + hexDword(atoiVAddr - (thisVAddr + 5))
    c = c + hexByte(0x48) + hexByte(0xF7) + hexByte(0xD0)
    c = c + hexByte(0xC3)
    emit c
}
func krBitnotSize() { emit 9 }
// shifts (26B): atoi a -> RBX; atoi b -> RCX(count); RAX=a; SH? RAX, CL.
func emitKrShlCode(thisVAddr, atoiVAddr) {
    let c = ""
    c = c + hexByte(0xE8) + hexDword(atoiVAddr - (thisVAddr + 5))
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC3)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xF7)
    c = c + hexByte(0xE8) + hexDword(atoiVAddr - (thisVAddr + 16))
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC1)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xD8)
    c = c + hexByte(0x48) + hexByte(0xD3) + hexByte(0xE0)
    c = c + hexByte(0xC3)
    emit c
}
func krShlSize() { emit 26 }
func emitKrShrCode(thisVAddr, atoiVAddr) {
    let c = ""
    c = c + hexByte(0xE8) + hexDword(atoiVAddr - (thisVAddr + 5))
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC3)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xF7)
    c = c + hexByte(0xE8) + hexDword(atoiVAddr - (thisVAddr + 16))
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC1)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xD8)
    c = c + hexByte(0x48) + hexByte(0xD3) + hexByte(0xE8)
    c = c + hexByte(0xC3)
    emit c
}
func krShrSize() { emit 26 }

// kr_hex: convert int to lowercase hex string (sign + magnitude). 107 bytes.
//   In: RDI = tagged arg (atoi'd internally). Out: RAX = ptr to NUL-term string.
//   Prefix: CALL kr_atoi; MOV RDI,RAX. Then base-16 digit loop with a-f fixup.
//   24-byte buffer (<=16 hex digits + sign + nul), built backward from buf+23.
func emitKrHexCode(thisVAddr, allocVAddr, atoiVAddr) {
    let c = ""
    c = c + hexByte(0xE8) + hexDword(atoiVAddr - (thisVAddr + 5))  // [0]   CALL kr_atoi
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC7)          // [5]   MOV RDI, RAX
    c = c + hexByte(0x53)                                          // [8]   PUSH RBX
    c = c + hexByte(0x41) + hexByte(0x54)                          // [9]   PUSH R12
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xFC)          // [11]  MOV R12, RDI
    c = c + hexByte(0xBF) + hexDword(24)                           // [14]  MOV EDI, 24
    c = c + hexByte(0xE8) + hexDword(allocVAddr - (thisVAddr + 24))// [19]  CALL kr_alloc
    c = c + hexByte(0x48) + hexByte(0x8D) + hexByte(0x58) + hexByte(0x17)  // [24] LEA RBX,[RAX+23]
    c = c + hexByte(0xC6) + hexByte(0x03) + hexByte(0x00)          // [28]  MOV byte [RBX], 0
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE0)          // [31]  MOV RAX, R12
    c = c + hexByte(0x31) + hexByte(0xC9)                          // [34]  XOR ECX, ECX
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)          // [36]  TEST RAX, RAX
    c = c + hexByte(0x79) + hexByte(0x05)                          // [39]  JNS +5 -> 46
    c = c + hexByte(0x48) + hexByte(0xF7) + hexByte(0xD8)          // [41]  NEG RAX
    c = c + hexByte(0xFF) + hexByte(0xC1)                          // [44]  INC ECX
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)          // [46]  TEST RAX, RAX (.pos)
    c = c + hexByte(0x75) + hexByte(0x08)                          // [49]  JNZ +8 -> 59
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xCB)          // [51]  DEC RBX
    c = c + hexByte(0xC6) + hexByte(0x03) + hexByte(0x30)          // [54]  MOV [RBX], '0'
    c = c + hexByte(0xEB) + hexByte(0x29)                          // [57]  JMP +41 -> 100 (.done)
    c = c + hexByte(0x31) + hexByte(0xD2)                          // [59]  XOR EDX, EDX (.loop)
    c = c + hexByte(0xBE) + hexDword(16)                           // [61]  MOV ESI, 16
    c = c + hexByte(0x48) + hexByte(0xF7) + hexByte(0xF6)          // [66]  DIV RSI
    c = c + hexByte(0x80) + hexByte(0xC2) + hexByte(0x30)          // [69]  ADD DL, '0'
    c = c + hexByte(0x80) + hexByte(0xFA) + hexByte(0x39)          // [72]  CMP DL, '9'
    c = c + hexByte(0x76) + hexByte(0x03)                          // [75]  JBE +3 -> 80
    c = c + hexByte(0x80) + hexByte(0xC2) + hexByte(0x27)          // [77]  ADD DL, 0x27 (a-f)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xCB)          // [80]  DEC RBX (.store)
    c = c + hexByte(0x88) + hexByte(0x13)                          // [83]  MOV [RBX], DL
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)          // [85]  TEST RAX, RAX
    c = c + hexByte(0x75) + hexByte(256 - 31)                      // [88]  JNZ -31 -> 59
    c = c + hexByte(0x85) + hexByte(0xC9)                          // [90]  TEST ECX, ECX
    c = c + hexByte(0x74) + hexByte(0x06)                          // [92]  JZ +6 -> 100
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xCB)          // [94]  DEC RBX
    c = c + hexByte(0xC6) + hexByte(0x03) + hexByte(0x2D)          // [97]  MOV [RBX], '-'
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xD8)          // [100] MOV RAX, RBX (.done)
    c = c + hexByte(0x41) + hexByte(0x5C)                          // [103] POP R12
    c = c + hexByte(0x5B)                                          // [105] POP RBX
    c = c + hexByte(0xC3)                                          // [106] RET
    emit c
}
func krHexSize() { emit 107 }

// kr_bin: convert int to binary string (sign + magnitude). 99 bytes.
//   Same shape as kr_str_int but base 2 and a 72-byte buffer (<=64 bits + sign +
//   nul). Prefix CALL kr_atoi; MOV RDI,RAX folds the tag conversion in.
func emitKrBinCode(thisVAddr, allocVAddr, atoiVAddr) {
    let c = ""
    c = c + hexByte(0xE8) + hexDword(atoiVAddr - (thisVAddr + 5))  // [0]   CALL kr_atoi
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC7)          // [5]   MOV RDI, RAX
    c = c + hexByte(0x53)                                          // [8]   PUSH RBX
    c = c + hexByte(0x41) + hexByte(0x54)                          // [9]   PUSH R12
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xFC)          // [11]  MOV R12, RDI
    c = c + hexByte(0xBF) + hexDword(72)                           // [14]  MOV EDI, 72
    c = c + hexByte(0xE8) + hexDword(allocVAddr - (thisVAddr + 24))// [19]  CALL kr_alloc
    c = c + hexByte(0x48) + hexByte(0x8D) + hexByte(0x58) + hexByte(0x47)  // [24] LEA RBX,[RAX+71]
    c = c + hexByte(0xC6) + hexByte(0x03) + hexByte(0x00)          // [28]  MOV byte [RBX], 0
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE0)          // [31]  MOV RAX, R12
    c = c + hexByte(0x31) + hexByte(0xC9)                          // [34]  XOR ECX, ECX
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)          // [36]  TEST RAX, RAX
    c = c + hexByte(0x79) + hexByte(0x05)                          // [39]  JNS +5 -> 46
    c = c + hexByte(0x48) + hexByte(0xF7) + hexByte(0xD8)          // [41]  NEG RAX
    c = c + hexByte(0xFF) + hexByte(0xC1)                          // [44]  INC ECX
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)          // [46]  TEST RAX, RAX (.pos)
    c = c + hexByte(0x75) + hexByte(0x08)                          // [49]  JNZ +8 -> 59
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xCB)          // [51]  DEC RBX
    c = c + hexByte(0xC6) + hexByte(0x03) + hexByte(0x30)          // [54]  MOV [RBX], '0'
    c = c + hexByte(0xEB) + hexByte(0x21)                          // [57]  JMP +33 -> 92 (.done)
    c = c + hexByte(0x31) + hexByte(0xD2)                          // [59]  XOR EDX, EDX (.loop)
    c = c + hexByte(0xBE) + hexDword(2)                            // [61]  MOV ESI, 2
    c = c + hexByte(0x48) + hexByte(0xF7) + hexByte(0xF6)          // [66]  DIV RSI
    c = c + hexByte(0x80) + hexByte(0xC2) + hexByte(0x30)          // [69]  ADD DL, '0'
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xCB)          // [72]  DEC RBX
    c = c + hexByte(0x88) + hexByte(0x13)                          // [75]  MOV [RBX], DL
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)          // [77]  TEST RAX, RAX
    c = c + hexByte(0x75) + hexByte(256 - 23)                      // [80]  JNZ -23 -> 59
    c = c + hexByte(0x85) + hexByte(0xC9)                          // [82]  TEST ECX, ECX
    c = c + hexByte(0x74) + hexByte(0x06)                          // [84]  JZ +6 -> 92
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xCB)          // [86]  DEC RBX
    c = c + hexByte(0xC6) + hexByte(0x03) + hexByte(0x2D)          // [89]  MOV [RBX], '-'
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xD8)          // [92]  MOV RAX, RBX (.done)
    c = c + hexByte(0x41) + hexByte(0x5C)                          // [95]  POP R12
    c = c + hexByte(0x5B)                                          // [97]  POP RBX
    c = c + hexByte(0xC3)                                          // [98]  RET
    emit c
}
func krBinSize() { emit 99 }

// kr_repeat: build a string formed by concatenating s n times.
//   In:  RDI = s (string ptr), RSI = n (small int OR string via kr_atoi)
//   Out: RAX = pointer to fresh "ssss...s\0" of length slen*n
//
// Layout (90 bytes):
//   [0]     53                PUSH RBX                              (1)
//   [1-2]   41 54             PUSH R12                              (2)
//   [3-4]   41 55             PUSH R13                              (2)
//   [5-6]   41 56             PUSH R14                              (2)
//   [7-9]   48 89 FB          MOV RBX, RDI                          (3)  ; rbx = s
//   [10-12] 48 89 F7          MOV RDI, RSI                          (3)  ; rdi = n
//   [13-17] E8 dd              CALL kr_atoi                          (5)  ; ends 18
//   [18-20] 49 89 C4          MOV R12, RAX                          (3)  ; r12 = n int
//   [21-23] 48 89 DF          MOV RDI, RBX                          (3)
//   [24-28] E8 dd              CALL kr_strlen                        (5)  ; ends 29
//   [29-31] 49 89 C5          MOV R13, RAX                          (3)  ; r13 = slen
//   [32-34] 4C 89 E8          MOV RAX, R13                          (3)
//   [35-38] 49 0F AF C4       IMUL RAX, R12                         (4)  ; rax = slen * n
//   [39-41] 49 89 C6          MOV R14, RAX                          (3)  ; r14 = total
//   [42-45] 49 8D 7E 01       LEA RDI, [R14+1]                      (4)
//   [46-50] E8 dd              CALL kr_alloc                         (5)  ; ends 51
//   [51]    50                PUSH RAX                              (1)
//   [52-54] 48 89 C7          MOV RDI, RAX                          (3)  ; dest
//   [55-57] 4C 89 E1          MOV RCX, R12                          (3)  ; counter
//   [58-60] 48 85 C9          TEST RCX, RCX                         (3)
//   [61-62] 74 0F             JZ +15 → .done at 78                  (2)
//   .loop at [63]:
//   [63]    51                PUSH RCX                              (1)
//   [64-66] 48 89 DE          MOV RSI, RBX                          (3)
//   [67-69] 4C 89 E9          MOV RCX, R13                          (3)
//   [70-71] F3 A4             REP MOVSB                             (2)
//   [72]    59                POP RCX                               (1)
//   [73-75] 48 FF C9          DEC RCX                               (3)
//   [76-77] 75 F1             JNZ -15 → .loop at 63                 (2)
//   .done at [78]:
//   [78-80] C6 07 00          MOV byte [RDI], 0                     (3)
//   [81]    58                POP RAX                               (1)
//   [82-83] 41 5E             POP R14                               (2)
//   [84-85] 41 5D             POP R13                               (2)
//   [86-87] 41 5C             POP R12                               (2)
//   [88]    5B                POP RBX                               (1)
//   [89]    C3                RET                                   (1)
func emitKrRepeatCode(thisVAddr, atoiVAddr, strlenVAddr, allocVAddr) {
    let dAtoi   = atoiVAddr   - (thisVAddr + 18)
    let dStrlen = strlenVAddr - (thisVAddr + 29)
    let dAlloc  = allocVAddr  - (thisVAddr + 51)
    let c = ""
    c = c + hexByte(0x53)
    c = c + hexByte(0x41) + hexByte(0x54)
    c = c + hexByte(0x41) + hexByte(0x55)
    c = c + hexByte(0x41) + hexByte(0x56)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xFB)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xF7)
    c = c + hexByte(0xE8) + hexDword(dAtoi)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC4)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDF)
    c = c + hexByte(0xE8) + hexDword(dStrlen)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC5)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE8)
    c = c + hexByte(0x49) + hexByte(0x0F) + hexByte(0xAF) + hexByte(0xC4)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC6)
    c = c + hexByte(0x49) + hexByte(0x8D) + hexByte(0x7E) + hexByte(0x01)
    c = c + hexByte(0xE8) + hexDword(dAlloc)
    c = c + hexByte(0x50)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC7)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE1)
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC9)
    c = c + hexByte(0x74) + hexByte(0x0F)
    c = c + hexByte(0x51)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDE)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE9)
    c = c + hexByte(0xF3) + hexByte(0xA4)
    c = c + hexByte(0x59)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC9)
    c = c + hexByte(0x75) + hexByte(256 - 15)
    c = c + hexByte(0xC6) + hexByte(0x07) + hexByte(0x00)
    c = c + hexByte(0x58)
    c = c + hexByte(0x41) + hexByte(0x5E)
    c = c + hexByte(0x41) + hexByte(0x5D)
    c = c + hexByte(0x41) + hexByte(0x5C)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krRepeatSize() { emit 90 }

// kr_isnum: returns 1 if s is a numeric string (optional leading '-' then
// digits only, non-empty). NOT smart-int aware — call only on string ptrs.
//
// Layout (45 bytes):
//   [0-1]   31 C0           XOR EAX, EAX                   (2)  ; default 0
//   [2-4]   80 3F 00        CMP byte [RDI], 0              (3)
//   [5-6]   74 25           JE +37 → .not_num at 44        (2)  ; empty
//   [7-9]   80 3F 2D        CMP byte [RDI], '-'            (3)
//   [10-11] 75 06           JNE +6 → .scan at 18           (2)
//   [12-14] 48 FF C7        INC RDI                        (3)
//   [15-17] 80 3F 00        CMP byte [RDI], 0              (3)
//   .scan_check at 18: must NOT be empty after '-'
//   [18-19] 74 18           JE +24 → .not_num at 44        (2)  ; just "-"
//   .scan at [20]:
//   [20-22] 80 3F 30        CMP byte [RDI], '0'            (3)
//   [23-24] 72 12           JB +18 → .not_num at 44        (2)
//   [25-27] 80 3F 39        CMP byte [RDI], '9'            (3)
//   [28-29] 77 0D           JA +13 → .not_num at 44        (2)
//   [30-32] 48 FF C7        INC RDI                        (3)
//   [33-35] 80 3F 00        CMP byte [RDI], 0              (3)
//   [36-37] 75 E6           JNE -26 → .scan at 20          (2)
//   .is_num at [38]:
//   [38-42] B8 01 00 00 00  MOV EAX, 1                     (5)
//   .not_num at [44]:  (one byte gap is JNE's natural fall-through)
//   [43]    90              NOP  (pad so .not_num at fixed 44) (1)
//   [44]    C3              RET                            (1)
func emitKrIsnumCode() {
    let c = ""
    c = c + hexByte(0x31) + hexByte(0xC0)
    c = c + hexByte(0x80) + hexByte(0x3F) + hexByte(0x00)
    c = c + hexByte(0x74) + hexByte(0x25)
    c = c + hexByte(0x80) + hexByte(0x3F) + hexByte(0x2D)
    c = c + hexByte(0x75) + hexByte(0x06)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7)
    c = c + hexByte(0x80) + hexByte(0x3F) + hexByte(0x00)
    c = c + hexByte(0x74) + hexByte(0x18)
    c = c + hexByte(0x80) + hexByte(0x3F) + hexByte(0x30)
    c = c + hexByte(0x72) + hexByte(0x12)
    c = c + hexByte(0x80) + hexByte(0x3F) + hexByte(0x39)
    c = c + hexByte(0x77) + hexByte(0x0D)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7)
    c = c + hexByte(0x80) + hexByte(0x3F) + hexByte(0x00)
    c = c + hexByte(0x75) + hexByte(256 - 18)   // JNE -18 → .scan at offset 20
    c = c + hexByte(0xB8) + hexByte(0x01) + hexByte(0x00) + hexByte(0x00) + hexByte(0x00)
    c = c + hexByte(0x90)
    c = c + hexByte(0xC3)
    emit c
}
func krIsnumSize() { emit 45 }

// kr_plus: numeric-aware "+". Mirrors C runtime's kr_plus:
//   if both args are numeric (small int OR digit-only string), return int sum
//   else return concat
//
// In:  RDI = a, RSI = b
// Out: RAX = result
//
// kr_atoi already passes through small ints unchanged, so we just call
// kr_atoi on each "is numeric" arg. The check uses kr_isnum on string args
// (small ints are trivially numeric).
//
// Layout (76 bytes):
//   [0]     53                PUSH RBX                              (1)
//   [1-2]   41 54             PUSH R12                              (2)
//   [3-5]   48 89 FB          MOV RBX, RDI                          (3)  ; rbx = a
//   [6-8]   49 89 F4          MOV R12, RSI                          (3)  ; r12 = b
//
//   ; check a numeric
//   [9-15]  48 81 FB 00 00 00 40   CMP RBX, 0x40000000              (7)
//   [16-17] 72 0A             JB +10 → .a_ok at 28                  (2)  ; a is small int
//   [18-20] 48 89 DF          MOV RDI, RBX                          (3)
//   [21-25] E8 dd_isnum                                              (5)
//   [26-27] 85 C0             TEST EAX, EAX                         (2)
//   ; fall-through to .a_ok if non-zero, else jump to concat
//   ; we want: if zero → .concat at 67. disp = 67 - 30 = 37.
//   ; reorder: put JZ here:
//   ; actually we need explicit JZ. Let me redo.
//
// Restart layout to keep code linear:
//
//   [0]     53                PUSH RBX                              (1)
//   [1-2]   41 54             PUSH R12                              (2)
//   [3-5]   48 89 FB          MOV RBX, RDI                          (3)
//   [6-8]   49 89 F4          MOV R12, RSI                          (3)
//
//   [9-15]  48 81 FB 00 00 00 40   CMP RBX, 0x40000000              (7)
//   [16-17] 72 0B             JB +11 → .a_done at 29                (2)
//   [18-20] 48 89 DF          MOV RDI, RBX                          (3)
//   [21-25] E8 dd_isnum                                              (5)
//   [26-27] 85 C0             TEST EAX, EAX                         (2)
//   [28]    74 ??             JZ → .concat                          -- but we need 2-byte JZ
//   ; oops jz d8 is 2 bytes. let's say:
//   [28-29] 74 21             JZ +33 → .concat at 63                (2)
//   .a_done at 30:
//
// Hmm offsets shifting. Let me just write it linearly and re-derive:
//
//   [0]     PUSH RBX                                       (1)
//   [1-2]   PUSH R12                                       (2)
//   [3-5]   MOV RBX, RDI                                   (3)
//   [6-8]   MOV R12, RSI                                   (3)
//   [9-15]  CMP RBX, 0x40000000                            (7)
//   [16-17] JB +10 → 28 (.a_ok)                            (2)
//   [18-20] MOV RDI, RBX                                   (3)
//   [21-25] CALL kr_isnum                                  (5)
//   [26-27] 85 C0  TEST EAX, EAX                          (2)
//   .a_ok at 28:
//   [28-29] 74 22  JZ +34 → .concat at 64                  (2)
//   [30-36] CMP R12, 0x40000000                            (7)
//   [37-38] JB +10 → 49 (.b_ok)                            (2)
//   [39-41] MOV RDI, R12                                   (3)
//   [42-46] CALL kr_isnum                                  (5)
//   [47-48] 85 C0  TEST EAX, EAX                          (2)
//   .b_ok at 49:
//   [49-50] 74 0D  JZ +13 → .concat at 64                  (2)
//   ; both numeric → atoi both, sum
//   [51-53] MOV RDI, RBX                                   (3)
//   [54-58] CALL kr_atoi                                   (5)
//   [59]    50  PUSH RAX                                   (1)
//   [60-62] 4C 89 E7  MOV RDI, R12                         (3)
//   [63-67] CALL kr_atoi                                   (5)
//   [68]    5F  POP RDI                                    (1)
//   [69-71] 48 01 F8  ADD RAX, RDI                         (3)
//   [72]    EB 0A  JMP +10 → .done at 84                   (2)
//   .concat at 74:
//   [74-76] 48 89 DF  MOV RDI, RBX                         (3)
//   [77-79] 4C 89 E6  MOV RSI, R12                         (3)
//   [80-84] CALL kr_concat                                 (5)  ; ends at 85
//   .done at 85:
//   [85-86] 41 5C  POP R12                                 (2)
//   [87]    5B  POP RBX                                    (1)
//   [88]    C3  RET                                        (1)
//
// Total: 89 bytes. Recompute jumps:
//   .concat target = 74. From [28-29] JZ disp = 74 - 30 = 44 = 0x2C
//   From [49-50] JZ disp = 74 - 51 = 23 = 0x17
//   .b_ok target = 49. From [37-38] JB disp = 49 - 39 = 10 = 0x0A
//   .a_ok target = 28. From [16-17] JB disp = 28 - 18 = 10 = 0x0A
//   .done target = 85. From [72-73] JMP disp = 85 - 74 = 11 = 0x0B
func emitKrPlusCode(thisVAddr, isnumVAddr, atoiVAddr, concatVAddr) {
    let dIsnumA  = isnumVAddr  - (thisVAddr + 26)
    let dIsnumB  = isnumVAddr  - (thisVAddr + 47)
    let dAtoiA   = atoiVAddr   - (thisVAddr + 59)
    let dAtoiB   = atoiVAddr   - (thisVAddr + 68)
    let dConcat  = concatVAddr - (thisVAddr + 85)
    let c = ""
    c = c + hexByte(0x53)
    c = c + hexByte(0x41) + hexByte(0x54)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xFB)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xF4)
    c = c + hexByte(0x48) + hexByte(0x81) + hexByte(0xFB) + hexDwordVaddr(0)
    c = c + hexByte(0x7C) + hexByte(0x0C)        // JL +12 → past JZ (a small int incl negative → skip isnum)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDF)
    c = c + hexByte(0xE8) + hexDword(dIsnumA)
    c = c + hexByte(0x85) + hexByte(0xC0)
    c = c + hexByte(0x74) + hexByte(0x2C)
    c = c + hexByte(0x49) + hexByte(0x81) + hexByte(0xFC) + hexDwordVaddr(0)
    c = c + hexByte(0x7C) + hexByte(0x0C)        // JL +12 → past JZ (b small int incl negative → skip isnum)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)
    c = c + hexByte(0xE8) + hexDword(dIsnumB)
    c = c + hexByte(0x85) + hexByte(0xC0)
    c = c + hexByte(0x74) + hexByte(0x17)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDF)
    c = c + hexByte(0xE8) + hexDword(dAtoiA)
    c = c + hexByte(0x50)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)
    c = c + hexByte(0xE8) + hexDword(dAtoiB)
    c = c + hexByte(0x5F)
    c = c + hexByte(0x48) + hexByte(0x01) + hexByte(0xF8)
    c = c + hexByte(0xEB) + hexByte(0x0B)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDF)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE6)
    c = c + hexByte(0xE8) + hexDword(dConcat)
    c = c + hexByte(0x41) + hexByte(0x5C)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krPlusSize() { emit 89 }

// kr_atoi2: shared helper. Atoi both args, return (rax=atoi(a), rdx=atoi(b)).
//   In:  RDI = a, RSI = b
//   Out: RAX = atoi(a), RDX = atoi(b)
//
// Layout (18 bytes):
//   [0]     56                PUSH RSI                              (1)  ; save b
//   [1-5]   E8 dd_atoi        CALL kr_atoi(rdi=a)                   (5)
//   [6]     5F                POP RDI                               (1)  ; b → rdi
//   [7]     50                PUSH RAX                              (1)  ; save atoi(a)
//   [8-12]  E8 dd_atoi        CALL kr_atoi(rdi=b)                   (5)
//   [13-15] 48 89 C2          MOV RDX, RAX                          (3)  ; rdx = atoi(b)
//   [16]    58                POP RAX                               (1)  ; rax = atoi(a)
//   [17]    C3                RET                                   (1)
func emitKrAtoi2Code(thisVAddr, atoiVAddr) {
    let dAtoi1 = atoiVAddr - (thisVAddr + 6)
    let dAtoi2 = atoiVAddr - (thisVAddr + 13)
    let c = ""
    c = c + hexByte(0x56)
    c = c + hexByte(0xE8) + hexDword(dAtoi1)
    c = c + hexByte(0x5F)
    c = c + hexByte(0x50)
    c = c + hexByte(0xE8) + hexDword(dAtoi2)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC2)
    c = c + hexByte(0x58)
    c = c + hexByte(0xC3)
    emit c
}
func krAtoi2Size() { emit 18 }

// kr_subi: atoi(a) - atoi(b)
//   In:  RDI = a, RSI = b
//   Out: RAX = result
//
// Layout (9 bytes): CALL kr_atoi2 (5) + SUB RAX, RDX (3) + RET (1)
func emitKrSubiCode(thisVAddr, atoi2VAddr) {
    let d = atoi2VAddr - (thisVAddr + 5)
    let c = ""
    c = c + hexByte(0xE8) + hexDword(d)
    c = c + hexByte(0x48) + hexByte(0x29) + hexByte(0xD0)
    c = c + hexByte(0xC3)
    emit c
}
func krSubiSize() { emit 9 }

// kr_muli: atoi(a) * atoi(b)
//   Layout (10 bytes): CALL kr_atoi2 (5) + IMUL RAX, RDX (4) + RET (1)
func emitKrMuliCode(thisVAddr, atoi2VAddr) {
    let d = atoi2VAddr - (thisVAddr + 5)
    let c = ""
    c = c + hexByte(0xE8) + hexDword(d)
    c = c + hexByte(0x48) + hexByte(0x0F) + hexByte(0xAF) + hexByte(0xC2)
    c = c + hexByte(0xC3)
    emit c
}
func krMuliSize() { emit 10 }

// kr_divi: atoi(a) / atoi(b) (signed)
//   Layout (14 bytes):
//     [0-4]   E8 dd        CALL kr_atoi2                            (5)
//     [5-7]   48 89 D1     MOV RCX, RDX                             (3)  ; save b in RCX (CQO needs RDX)
//     [8-9]   48 99        CQO                                      (2)  ; sign-extend RAX → RDX:RAX
//     [10-12] 48 F7 F9     IDIV RCX                                 (3)
//     [13]    C3           RET                                      (1)  ; quotient already in RAX
func emitKrDiviCode(thisVAddr, atoi2VAddr) {
    let d = atoi2VAddr - (thisVAddr + 5)
    let c = ""
    c = c + hexByte(0xE8) + hexDword(d)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xD1)
    c = c + hexByte(0x48) + hexByte(0x99)
    c = c + hexByte(0x48) + hexByte(0xF7) + hexByte(0xF9)
    c = c + hexByte(0xC3)
    emit c
}
func krDiviSize() { emit 14 }

// kr_modi: atoi(a) % atoi(b)
//   Layout (17 bytes): same as kr_divi but MOV RAX, RDX before RET
func emitKrModiCode(thisVAddr, atoi2VAddr) {
    let d = atoi2VAddr - (thisVAddr + 5)
    let c = ""
    c = c + hexByte(0xE8) + hexDword(d)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xD1)
    c = c + hexByte(0x48) + hexByte(0x99)
    c = c + hexByte(0x48) + hexByte(0xF7) + hexByte(0xF9)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xD0)   // MOV RAX, RDX
    c = c + hexByte(0xC3)
    emit c
}
func krModiSize() { emit 17 }

// kr_strcmp: standard C strcmp.
//   In:  RDI = a, RSI = b (both NUL-terminated)
//   Out: RAX = a - b at first differing byte (signed 64-bit), 0 if equal
//
// Layout (31 bytes):
//   .loop at [0]:
//   [0-1]   8A 07           MOV AL, [RDI]                  (2)
//   [2-3]   3A 06           CMP AL, [RSI]                  (2)
//   [4-5]   75 0C           JNE +12 → .differ at 18        (2)
//   [6-7]   84 C0           TEST AL, AL                    (2)
//   [8-9]   74 12           JZ +18 → .equal at 28          (2)
//   [10-12] 48 FF C7        INC RDI                        (3)
//   [13-15] 48 FF C6        INC RSI                        (3)
//   [16-17] EB EE           JMP -18 → .loop at 0           (2)
//   .differ at [18]:
//   [18-20] 0F B6 07        MOVZX EAX, byte [RDI]          (3)
//   [21-23] 0F B6 0E        MOVZX ECX, byte [RSI]          (3)
//   [24-26] 48 29 C8        SUB RAX, RCX  (64-bit signed)  (3)
//   [27]    C3              RET                            (1)
//   .equal at [28]:
//   [28-29] 31 C0           XOR EAX, EAX                   (2)
//   [30]    C3              RET                            (1)
//
// Why 64-bit SUB and not 32-bit: SUB EAX, ECX zero-extends the result to RAX,
// turning -1 into 0xFFFFFFFF (huge positive). Caller's signed SETcc then sees
// wrong sign. SUB RAX, RCX preserves the negative sign properly.
// NOTE: a 4-byte guard is prepended so kr_strcmp never dereferences a non-pointer.
// Krypton tags ints < 0x40000000 and pointers ≥ it. A comparison like
// `someString == 0` (or string-vs-int) must NOT strcmp the int operand — the C
// runtime treats mismatched types as not-equal. So: if EITHER operand is below
// VADDR_BASE (a small int / null), return their raw signed difference (non-zero,
// so EQ→false / NEQ→true) without touching memory. Real strings (data ≥
// 0x40000078, heap ≈ 0x7ffff…) always pass the guard. New layout (56 bytes):
//   [0-6]   48 81 FF imm32   CMP RDI, 0x40000000          (7)
//   [7-8]   72 28            JB +0x28 → .mixed at 49      (2)
//   [9-15]  48 81 FE imm32   CMP RSI, 0x40000000          (7)
//   [16-17] 72 1F            JB +0x1F → .mixed at 49      (2)
//   [18-48] (original strcmp body, unchanged, internal jumps are relative)
//   [49-51] 48 89 F8         MOV RAX, RDI                 (3)
//   [52-54] 48 29 F0         SUB RAX, RSI                 (3)
//   [55]    C3               RET                          (1)
func emitKrStrcmpCode() {
    let c = ""
    c = c + hexByte(0x48) + hexByte(0x81) + hexByte(0xFF) + hexDwordVaddr(0)  // [0-6] CMP RDI, 0x40000000
    c = c + hexByte(0x72) + hexByte(0x28)                                          // [7-8] JB → .mixed at 49
    c = c + hexByte(0x48) + hexByte(0x81) + hexByte(0xFE) + hexDwordVaddr(0)  // [9-15] CMP RSI, 0x40000000
    c = c + hexByte(0x72) + hexByte(0x1F)                                          // [16-17] JB → .mixed at 49
    c = c + hexByte(0x8A) + hexByte(0x07)
    c = c + hexByte(0x3A) + hexByte(0x06)
    c = c + hexByte(0x75) + hexByte(0x0C)
    c = c + hexByte(0x84) + hexByte(0xC0)
    c = c + hexByte(0x74) + hexByte(0x12)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC6)
    c = c + hexByte(0xEB) + hexByte(256 - 18)
    c = c + hexByte(0x0F) + hexByte(0xB6) + hexByte(0x07)
    c = c + hexByte(0x0F) + hexByte(0xB6) + hexByte(0x0E)
    c = c + hexByte(0x48) + hexByte(0x29) + hexByte(0xC8)
    c = c + hexByte(0xC3)
    c = c + hexByte(0x31) + hexByte(0xC0)
    c = c + hexByte(0xC3)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xF8)   // [49-51] .mixed: MOV RAX, RDI
    c = c + hexByte(0x48) + hexByte(0x29) + hexByte(0xF0)   // [52-54] SUB RAX, RSI
    c = c + hexByte(0xC3)                                    // [55] RET
    emit c
}
func krStrcmpSize() { emit 56 }

// kr_cmpi: signed-integer-or-strcmp comparison helper for EQ/NEQ/LT/GT/LTE/GTE.
//   If both args are "numeric" (small int OR digit-only string), returns
//   atoi(a) - atoi(b). Else returns strcmp(a, b). Caller does SETcc on the
//   result. Mirrors C runtime kr_lt/kr_eq dispatch.
//
//   In:  RDI = a, RSI = b
//   Out: RAX = signed difference
//
// Layout (92 bytes) — same skeleton as kr_plus, replacing the "atoi+add" tail
// with "atoi-atoi" and the "concat" tail with "strcmp":
//   [0]     53                PUSH RBX                              (1)
//   [1-2]   41 54             PUSH R12                              (2)
//   [3-5]   48 89 FB          MOV RBX, RDI                          (3)
//   [6-8]   49 89 F4          MOV R12, RSI                          (3)
//   [9-15]  48 81 FB imm32    CMP RBX, 0x40000000                   (7)
//   [16-17] 72 0C             JB +12 → .a_done at 30                (2)
//   [18-20] 48 89 DF          MOV RDI, RBX                          (3)
//   [21-25] E8 dd_isnum       CALL kr_isnum                         (5)
//   [26-27] 85 C0             TEST EAX, EAX                         (2)
//   [28-29] 74 2F             JZ +47 → .strcmp at 77                (2)
//   .a_done at [30]:
//   [30-36] 49 81 FC imm32    CMP R12, 0x40000000                   (7)
//   [37-38] 72 0C             JB +12 → .b_done at 51                (2)
//   [39-41] 4C 89 E7          MOV RDI, R12                          (3)
//   [42-46] E8 dd_isnum       CALL kr_isnum                         (5)
//   [47-48] 85 C0             TEST EAX, EAX                         (2)
//   [49-50] 74 1A             JZ +26 → .strcmp at 77                (2)
//   .b_done at [51]:
//   [51-53] 48 89 DF          MOV RDI, RBX                          (3)
//   [54-58] E8 dd_atoi        CALL kr_atoi                          (5)
//   [59]    50                PUSH RAX                              (1)
//   [60-62] 4C 89 E7          MOV RDI, R12                          (3)
//   [63-67] E8 dd_atoi        CALL kr_atoi                          (5)
//   [68]    5F                POP RDI                               (1)  ; rdi = atoi(a)
//   [69-71] 48 29 C7          SUB RDI, RAX                          (3)  ; rdi = atoi(a) - atoi(b)
//   [72-74] 48 89 F8          MOV RAX, RDI                          (3)
//   [75-76] EB 0B             JMP +11 → .done at 88                 (2)
//   .strcmp at [77]:
//   [77-79] 48 89 DF          MOV RDI, RBX                          (3)
//   [80-82] 4C 89 E6          MOV RSI, R12                          (3)
//   [83-87] E8 dd_strcmp      CALL kr_strcmp                        (5)
//   .done at [88]:
//   [88-89] 41 5C             POP R12                               (2)
//   [90]    5B                POP RBX                               (1)
//   [91]    C3                RET                                   (1)
func emitKrCmpiCode(thisVAddr, isnumVAddr, atoiVAddr, strcmpVAddr) {
    let dIsnumA  = isnumVAddr  - (thisVAddr + 26)
    let dIsnumB  = isnumVAddr  - (thisVAddr + 47)
    let dAtoiA   = atoiVAddr   - (thisVAddr + 59)
    let dAtoiB   = atoiVAddr   - (thisVAddr + 68)
    let dStrcmp  = strcmpVAddr - (thisVAddr + 88)
    let c = ""
    c = c + hexByte(0x53)
    c = c + hexByte(0x41) + hexByte(0x54)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xFB)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xF4)
    c = c + hexByte(0x48) + hexByte(0x81) + hexByte(0xFB) + hexDwordVaddr(0)
    c = c + hexByte(0x7C) + hexByte(0x0C)        // JL +12 — signed so negatives count as int
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDF)
    c = c + hexByte(0xE8) + hexDword(dIsnumA)
    c = c + hexByte(0x85) + hexByte(0xC0)
    c = c + hexByte(0x74) + hexByte(0x2F)
    c = c + hexByte(0x49) + hexByte(0x81) + hexByte(0xFC) + hexDwordVaddr(0)
    c = c + hexByte(0x7C) + hexByte(0x0C)        // JL +12 — signed so negatives count as int
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)
    c = c + hexByte(0xE8) + hexDword(dIsnumB)
    c = c + hexByte(0x85) + hexByte(0xC0)
    c = c + hexByte(0x74) + hexByte(0x1A)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDF)
    c = c + hexByte(0xE8) + hexDword(dAtoiA)
    c = c + hexByte(0x50)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)
    c = c + hexByte(0xE8) + hexDword(dAtoiB)
    c = c + hexByte(0x5F)
    c = c + hexByte(0x48) + hexByte(0x29) + hexByte(0xC7)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xF8)
    c = c + hexByte(0xEB) + hexByte(0x0B)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDF)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE6)
    c = c + hexByte(0xE8) + hexDword(dStrcmp)
    c = c + hexByte(0x41) + hexByte(0x5C)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krCmpiSize() { emit 92 }

// kr_strstr: substring search. Returns offset of first occurrence of needle
// in haystack, or -1 if not found. Empty needle matches at offset 0.
//
//   In:  RDI = haystack, RSI = needle (both NUL-terminated)
//   Out: RAX = offset (>= 0) or -1
//
// Naive O(N*M) scan. Used internally by kr_contains and kr_indexof.
//
// Layout (61 bytes):
//   [0]     53                PUSH RBX                              (1)
//   [1-2]   41 54             PUSH R12                              (2)
//   [3-5]   48 89 FB          MOV RBX, RDI                          (3)  ; rbx = haystack
//   [6-8]   49 89 F4          MOV R12, RSI                          (3)  ; r12 = needle
//   [9-11]  48 31 C0          XOR RAX, RAX                          (3)  ; i = 0
//   .try at [12]:
//   [12-14] 48 89 DF          MOV RDI, RBX                          (3)
//   [15-17] 48 01 C7          ADD RDI, RAX                          (3)  ; rdi = haystack + i
//   [18-20] 4C 89 E6          MOV RSI, R12                          (3)  ; rsi = needle
//   .match_loop at [21]:
//   [21-22] 8A 0E             MOV CL, [RSI]                         (2)
//   [23-24] 84 C9             TEST CL, CL                           (2)
//   [25-26] 74 1E             JZ +30 → .found at 57                 (2)
//   [27-28] 8A 17             MOV DL, [RDI]                         (2)
//   [29-30] 84 D2             TEST DL, DL                           (2)
//   [31-32] 74 12             JZ +18 → .nomatch at 51               (2)
//   [33-34] 38 D1             CMP CL, DL                            (2)
//   [35-36] 75 08             JNE +8 → .next at 45                  (2)
//   [37-39] 48 FF C7          INC RDI                               (3)
//   [40-42] 48 FF C6          INC RSI                               (3)
//   [43-44] EB E8             JMP -24 → .match_loop at 21           (2)
//   .next at [45]:
//   [45-47] 48 FF C0          INC RAX                               (3)
//   [48-49] EB DA             JMP -38 → .try at 12                  (2)
//   .nomatch at [51]:
//   [51-53] 48 31 C0          XOR RAX, RAX                          (3)
//   [54-56] 48 FF C8          DEC RAX                               (3)  ; rax = -1
//   .found at [57]:
//   [57-58] 41 5C             POP R12                               (2)
//   [59]    5B                POP RBX                               (1)
//   [60]    C3                RET                                   (1)
func emitKrStrstrCode() {
    let c = ""
    c = c + hexByte(0x53)
    c = c + hexByte(0x41) + hexByte(0x54)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xFB)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xF4)
    c = c + hexByte(0x48) + hexByte(0x31) + hexByte(0xC0)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDF)
    c = c + hexByte(0x48) + hexByte(0x01) + hexByte(0xC7)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE6)
    c = c + hexByte(0x8A) + hexByte(0x0E)
    c = c + hexByte(0x84) + hexByte(0xC9)
    c = c + hexByte(0x74) + hexByte(0x1D)        // JZ +29 → .found at 56
    c = c + hexByte(0x8A) + hexByte(0x17)
    c = c + hexByte(0x84) + hexByte(0xD2)
    c = c + hexByte(0x74) + hexByte(0x11)        // JZ +17 → .nomatch at 50
    c = c + hexByte(0x38) + hexByte(0xD1)
    c = c + hexByte(0x75) + hexByte(0x08)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC6)
    c = c + hexByte(0xEB) + hexByte(256 - 24)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC0)
    c = c + hexByte(0xEB) + hexByte(256 - 38)
    c = c + hexByte(0x48) + hexByte(0x31) + hexByte(0xC0)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC8)
    c = c + hexByte(0x41) + hexByte(0x5C)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krStrstrSize() { emit 60 }

// kr_contains: 1 if needle is substring of s, else 0. Wraps kr_strstr.
//   In:  RDI = s, RSI = needle
//   Out: RAX = 0 or 1
//
// Layout (18 bytes):
//   [0-4]   E8 dd_strstr      CALL kr_strstr                        (5)  ; rax = offset or -1
//   [5-7]   48 85 C0          TEST RAX, RAX                         (3)  ; SF = 1 if rax < 0
//   [8-10]  0F 98 C2          SETS DL                               (3)  ; dl = SF (1 if not found)
//   [11-13] 0F B6 C2          MOVZX EAX, DL                         (3)
//   [14-16] 83 F0 01          XOR EAX, 1                            (3)  ; flip: 1 if found
//   [17]    C3                RET                                   (1)
func emitKrContainsCode(thisVAddr, strstrVAddr) {
    let dStrstr = strstrVAddr - (thisVAddr + 5)
    let c = ""
    c = c + hexByte(0xE8) + hexDword(dStrstr)
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)
    c = c + hexByte(0x0F) + hexByte(0x98) + hexByte(0xC2)
    c = c + hexByte(0x0F) + hexByte(0xB6) + hexByte(0xC2)
    c = c + hexByte(0x83) + hexByte(0xF0) + hexByte(0x01)
    c = c + hexByte(0xC3)
    emit c
}
func krContainsSize() { emit 18 }

// kr_indexof: offset of first occurrence of needle in s, or -1.
//   In:  RDI = s, RSI = needle
//   Out: RAX = offset or -1   (raw kr_strstr return)
//
// Layout (6 bytes): just CALL kr_strstr then RET.
//   [0-4]   E8 dd_strstr      CALL kr_strstr                        (5)
//   [5]     C3                RET                                   (1)
func emitKrIndexofCode(thisVAddr, strstrVAddr) {
    let d = strstrVAddr - (thisVAddr + 5)
    let c = ""
    c = c + hexByte(0xE8) + hexDword(d)
    c = c + hexByte(0xC3)
    emit c
}
func krIndexofSize() { emit 6 }

// kr_endswith: 1 if s ends with suffix, else 0.
//   In:  RDI = s, RSI = suffix
//   Out: RAX = 0 or 1
//
// Algorithm: ls = strlen(s); lp = strlen(suffix). If lp > ls, no.
// Otherwise compare s[ls-lp..ls] vs suffix byte-by-byte.
//
// Layout (87 bytes):
//   [0]     53                PUSH RBX                              (1)
//   [1-2]   41 54             PUSH R12                              (2)
//   [3-4]   41 55             PUSH R13                              (2)
//   [5-7]   48 89 FB          MOV RBX, RDI                          (3)  ; rbx = s
//   [8-10]  49 89 F4          MOV R12, RSI                          (3)  ; r12 = suffix
//   [11-13] 48 89 DF          MOV RDI, RBX                          (3)
//   [14-18] E8 dd_strlen      CALL kr_strlen                        (5)  ; ls in rax
//   [19-21] 49 89 C5          MOV R13, RAX                          (3)  ; r13 = ls
//   [22-24] 4C 89 E7          MOV RDI, R12                          (3)
//   [25-29] E8 dd_strlen      CALL kr_strlen                        (5)  ; lp in rax
//   [30-32] 49 39 C5          CMP R13, RAX                          (3)
//   [33-34] 72 2C             JB +44 → .nope at 79                  (2)  ; ls < lp → no
//   [35-37] 49 29 C5          SUB R13, RAX                          (3)  ; r13 = ls - lp = start offset
//   [38-40] 48 89 DF          MOV RDI, RBX                          (3)
//   [41-43] 4C 01 EF          ADD RDI, R13                          (3)  ; rdi = s + offset
//   [44-46] 4C 89 E6          MOV RSI, R12                          (3)  ; rsi = suffix
//   [47-49] 48 89 C1          MOV RCX, RAX                          (3)  ; rcx = lp = remaining
//   .loop at [50]:
//   [50-52] 48 85 C9          TEST RCX, RCX                         (3)
//   [53-54] 74 11             JZ +17 → .yes at 72                   (2)
//   [55-56] 8A 07             MOV AL, [RDI]                         (2)
//   [57-58] 3A 06             CMP AL, [RSI]                         (2)
//   [59-60] 75 12             JNE +18 → .nope at 79                 (2)
//   [61-63] 48 FF C7          INC RDI                               (3)
//   [64-66] 48 FF C6          INC RSI                               (3)
//   [67-69] 48 FF C9          DEC RCX                               (3)
//   [70-71] EB EA             JMP -22 → .loop at 50                 (2)
//   .yes at [72]:
//   [72-76] B8 01 00 00 00    MOV EAX, 1                            (5)
//   [77-78] EB 02             JMP +2 → .done at 81                  (2)
//   .nope at [79]:
//   [79-80] 31 C0             XOR EAX, EAX                          (2)
//   .done at [81]:
//   [81-82] 41 5D             POP R13                               (2)
//   [83-84] 41 5C             POP R12                               (2)
//   [85]    5B                POP RBX                               (1)
//   [86]    C3                RET                                   (1)
func emitKrEndswithCode(thisVAddr, strlenVAddr) {
    let dS1 = strlenVAddr - (thisVAddr + 19)
    let dS2 = strlenVAddr - (thisVAddr + 30)
    let c = ""
    c = c + hexByte(0x53)
    c = c + hexByte(0x41) + hexByte(0x54)
    c = c + hexByte(0x41) + hexByte(0x55)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xFB)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xF4)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDF)
    c = c + hexByte(0xE8) + hexDword(dS1)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC5)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)
    c = c + hexByte(0xE8) + hexDword(dS2)
    c = c + hexByte(0x49) + hexByte(0x39) + hexByte(0xC5)
    c = c + hexByte(0x72) + hexByte(0x2C)
    c = c + hexByte(0x49) + hexByte(0x29) + hexByte(0xC5)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDF)
    c = c + hexByte(0x4C) + hexByte(0x01) + hexByte(0xEF)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE6)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC1)
    c = c + hexByte(0x48) + hexByte(0x85) + hexByte(0xC9)
    c = c + hexByte(0x74) + hexByte(0x11)
    c = c + hexByte(0x8A) + hexByte(0x07)
    c = c + hexByte(0x3A) + hexByte(0x06)
    c = c + hexByte(0x75) + hexByte(0x12)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC6)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC9)
    c = c + hexByte(0xEB) + hexByte(256 - 22)
    c = c + hexByte(0xB8) + hexByte(0x01) + hexByte(0x00) + hexByte(0x00) + hexByte(0x00)
    c = c + hexByte(0xEB) + hexByte(0x02)
    c = c + hexByte(0x31) + hexByte(0xC0)
    c = c + hexByte(0x41) + hexByte(0x5D)
    c = c + hexByte(0x41) + hexByte(0x5C)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krEndswithSize() { emit 87 }

// kr_replace: replace all occurrences of `find` with `rep` in `s`.
// Returns a freshly allocated string. Empty `find` returns `s` unchanged
// (avoids infinite loop). Allocates ls*(lr+1)+1 upper bound for output.
//
//   In:  RDI = s, RSI = find, RDX = rep
//   Out: RAX = freshly allocated NUL-terminated string
//
// Layout (142 bytes):
//   [0]    53                 PUSH RBX
//   [1-2]  41 54              PUSH R12
//   [3-4]  41 55              PUSH R13
//   [5-6]  41 56              PUSH R14
//   [7-8]  41 57              PUSH R15
//   [9-11] 48 89 FB           MOV RBX, RDI         ; rbx = s
//   [12-14] 49 89 F4          MOV R12, RSI         ; r12 = find
//   [15-17] 49 89 D5          MOV R13, RDX         ; r13 = rep
//   [18-20] 4C 89 E7          MOV RDI, R12
//   [21-25] E8 dStrlen        CALL kr_strlen       ; rax = lf
//   [26-28] 49 89 C6          MOV R14, RAX         ; r14 = lf
//   [29-31] 4D 85 F6          TEST R14, R14
//   [32-33] 75 05             JNE +5 → .has_find at 39
//   [34-36] 48 89 D8          MOV RAX, RBX         ; lf=0 → return s
//   [37-38] EB 5D             JMP +93 → .epilogue at 132
//   .has_find at [39]:
//   [39-41] 4C 89 EF          MOV RDI, R13
//   [42-46] E8 dStrlen        CALL kr_strlen       ; rax = lr
//   [47-49] 49 89 C7          MOV R15, RAX         ; r15 = lr
//   [50-52] 48 89 DF          MOV RDI, RBX
//   [53-57] E8 dStrlen        CALL kr_strlen       ; rax = ls
//   [58-60] 4C 89 F9          MOV RCX, R15         ; rcx = lr
//   [61-63] 48 FF C1          INC RCX              ; lr+1
//   [64-66] 48 F7 E1          MUL RCX              ; rax = ls*(lr+1)
//   [67-69] 48 FF C0          INC RAX              ; +1 for NUL
//   [70-72] 48 89 C7          MOV RDI, RAX
//   [73-77] E8 dAlloc         CALL kr_alloc        ; rax = buf
//   [78]   50                 PUSH RAX             ; save buf
//   [79-81] 48 89 C7          MOV RDI, RAX         ; rdi = dst
//   [82-84] 48 89 DE          MOV RSI, RBX         ; rsi = src
//   .scan at [85]:
//   [85-86] 8A 06             MOV AL, [RSI]
//   [87-88] 84 C0             TEST AL, AL
//   [89-90] 74 25             JZ +37 → .done at 128
//   [91]   56                 PUSH RSI
//   [92]   57                 PUSH RDI
//   [93-95] 4C 89 F1          MOV RCX, R14         ; rcx = lf
//   [96-98] 4C 89 E7          MOV RDI, R12         ; rdi = find ptr
//   [99-100] F3 A6            REPE CMPSB           ; cmp [rsi] vs [rdi]
//   [101]  5F                 POP RDI              ; restore dst
//   [102]  5E                 POP RSI              ; restore src
//   [103-104] 75 14           JNE +20 → .copy1 at 125
//   ; matched: copy rep to dst, advance src by lf
//   [105]  56                 PUSH RSI
//   [106]  57                 PUSH RDI
//   [107-109] 4C 89 EE        MOV RSI, R13         ; rsi = rep
//   [110-112] 4C 89 F9        MOV RCX, R15         ; rcx = lr
//   [113-114] F3 A4           REP MOVSB
//   [115]  5F                 POP RDI
//   [116]  5E                 POP RSI
//   [117-119] 4C 01 FF        ADD RDI, R15         ; dst += lr
//   [120-122] 4C 01 F6        ADD RSI, R14         ; src += lf
//   [123-124] EB D8           JMP -40 → .scan at 85
//   .copy1 at [125]:
//   [125]  A4                 MOVSB                ; *dst++ = *src++
//   [126-127] EB D5           JMP -43 → .scan at 85
//   .done at [128]:
//   [128-130] C6 07 00        MOV byte [RDI], 0    ; NUL terminator
//   [131]  58                 POP RAX              ; rax = buf
//   .epilogue at [132]:
//   [132-133] 41 5F           POP R15
//   [134-135] 41 5E           POP R14
//   [136-137] 41 5D           POP R13
//   [138-139] 41 5C           POP R12
//   [140]  5B                 POP RBX
//   [141]  C3                 RET
func emitKrReplaceCode(thisVAddr, strlenVAddr, allocVAddr) {
    // NOTE: kr_alloc clobbers R15 — it IS the heap_next pointer, advanced
    // by every alloc. So we can't use R15 to hold local state across an
    // alloc call. (Tried PUSH/POP R15 around alloc — fixed nothing because
    // restoring R15 undoes the alloc itself, breaking subsequent allocs
    // anywhere in the program.) Use R10 instead: caller-save, but none of
    // the callees here (kr_strlen, kr_alloc) touch R10. R10 encoding is
    // the same length as R15 encoding (both need REX.B/REX.R), so byte
    // count stays at 142 and all jump distances are unchanged.
    let dStrlen1 = strlenVAddr - (thisVAddr + 26)
    let dStrlen2 = strlenVAddr - (thisVAddr + 47)
    let dStrlen3 = strlenVAddr - (thisVAddr + 58)
    let dAlloc   = allocVAddr  - (thisVAddr + 78)
    let c = ""
    c = c + hexByte(0x53)
    c = c + hexByte(0x41) + hexByte(0x54)
    c = c + hexByte(0x41) + hexByte(0x55)
    c = c + hexByte(0x41) + hexByte(0x56)
    c = c + hexByte(0x41) + hexByte(0x53)   // PUSH R11 (was R15) — must NOT save/restore R15: it is the
                                            // global heap_next, advanced by kr_alloc below; restoring it
                                            // would undo this call's allocation (caller reuses the buffer).
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xFB)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xF4)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xD5)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)
    c = c + hexByte(0xE8) + hexDword(dStrlen1)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC6)
    c = c + hexByte(0x4D) + hexByte(0x85) + hexByte(0xF6)
    c = c + hexByte(0x75) + hexByte(0x05)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xD8)
    c = c + hexByte(0xEB) + hexByte(0x5D)         // JMP +93 → .epilogue at 132
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xEF)
    c = c + hexByte(0xE8) + hexDword(dStrlen2)
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC2)   // MOV R10, RAX (was R15) — lr in R10 now
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDF)
    c = c + hexByte(0xE8) + hexDword(dStrlen3)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xD1)   // MOV RCX, R10 (was R15)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC1)
    c = c + hexByte(0x48) + hexByte(0xF7) + hexByte(0xE1)
    c = c + hexByte(0x48) + hexByte(0xFF) + hexByte(0xC0)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC7)
    c = c + hexByte(0xE8) + hexDword(dAlloc)
    c = c + hexByte(0x50)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xC7)
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0xDE)
    c = c + hexByte(0x8A) + hexByte(0x06)
    c = c + hexByte(0x84) + hexByte(0xC0)
    c = c + hexByte(0x74) + hexByte(0x25)
    c = c + hexByte(0x56)
    c = c + hexByte(0x57)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xF1)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xE7)
    c = c + hexByte(0xF3) + hexByte(0xA6)
    c = c + hexByte(0x5F)
    c = c + hexByte(0x5E)
    c = c + hexByte(0x75) + hexByte(0x14)
    c = c + hexByte(0x56)
    c = c + hexByte(0x57)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xEE)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0xD1)   // MOV RCX, R10 (was R15) — lr
    c = c + hexByte(0xF3) + hexByte(0xA4)
    c = c + hexByte(0x5F)
    c = c + hexByte(0x5E)
    c = c + hexByte(0x4C) + hexByte(0x01) + hexByte(0xD7)   // ADD RDI, R10 (was R15) — dst += lr
    c = c + hexByte(0x4C) + hexByte(0x01) + hexByte(0xF6)
    c = c + hexByte(0xEB) + hexByte(256 - 40)
    c = c + hexByte(0xA4)
    c = c + hexByte(0xEB) + hexByte(256 - 43)
    c = c + hexByte(0xC6) + hexByte(0x07) + hexByte(0x00)
    c = c + hexByte(0x58)
    c = c + hexByte(0x41) + hexByte(0x5B)   // POP R11 (was R15) — discard the saved value; R15 keeps the
                                            // post-alloc heap_next so the caller sees this call's allocation.
    c = c + hexByte(0x41) + hexByte(0x5E)
    c = c + hexByte(0x41) + hexByte(0x5D)
    c = c + hexByte(0x41) + hexByte(0x5C)
    c = c + hexByte(0x5B)
    c = c + hexByte(0xC3)
    emit c
}
func krReplaceSize() { emit 142 }

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
// (heap size note: bumped from 64KB → 16MB so larger programs don't exhaust
//  the bump allocator. mmap is lazy on Linux — only pages actually touched
//  get backed by physical memory, so the cost of reserving 16MB is near zero.)
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
func startSize() { emit 90 }
func emitStartCode(callDisp, atoiDisp) {
    let c = ""
    c = c + hexByte(0x4C) + hexByte(0x8B) + hexByte(0x24) + hexByte(0x24)
    c = c + hexByte(0x4C) + hexByte(0x8D) + hexByte(0x6C) + hexByte(0x24) + hexByte(0x08)
    c = c + hexByte(0xB8) + hexDword(9)
    c = c + hexByte(0x31) + hexByte(0xFF)
    // heap: ~1.875 GB (bump-only, no GC; mmap lazy so only touched pages cost RAM).
    // elf.kir self-compile peaks at ~260 MB, but the larger compile.kir
    // (front-end, ~552 KB output) exhausted the old 512 MB cap and SIGSEGV'd —
    // the native self-host of the front-end. 0x70000000 stays just under the
    // int/pointer threshold (0x7F000000) so it still emits cleanly through
    // hexDword. MOV ESI, 0x70000000.
    c = c + hexByte(0xBE) + hexDword(0x70000000)
    c = c + hexByte(0xBA) + hexDword(3)
    c = c + hexByte(0x41) + hexByte(0xBA) + hexDword(0x22)
    c = c + hexByte(0x49) + hexByte(0xC7) + hexByte(0xC0) + hexDword(0 - 1)
    c = c + hexByte(0x45) + hexByte(0x31) + hexByte(0xC9)
    c = c + hexByte(0x0F) + hexByte(0x05)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0x20)
    c = c + hexByte(0x4C) + hexByte(0x89) + hexByte(0x68) + hexByte(0x08)
    // envp = argv + (argc+1)*8 = R13 + R12*8 + 8; stash at heap[16] for environ().
    c = c + hexByte(0x4B) + hexByte(0x8D) + hexByte(0x4C) + hexByte(0xE5) + hexByte(0x08)  // LEA RCX,[R13+R12*8+8]
    c = c + hexByte(0x48) + hexByte(0x89) + hexByte(0x48) + hexByte(0x10)                  // MOV [RAX+16],RCX
    c = c + hexByte(0x49) + hexByte(0x89) + hexByte(0xC6)
    c = c + hexByte(0x4C) + hexByte(0x8D) + hexByte(0x78) + hexByte(0x18)  // LEA R15,[RAX+24] (heap_next past 3 globals)
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
    if op == "SUB"        { emit 35 }   // smart-int dispatch + kr_subi slow path
    if op == "MUL"        { emit 36 }   // same shape, IMUL is 4 bytes vs SUB's 3
    if op == "DIV"        { emit 37 }   // CQO + IDIV + PUSH = 6 bytes fast path
    if op == "MOD"        { emit 37 }   // same as DIV but PUSH RDX
    if op == "CALL_FUNC"  { emit 13 }   // E8 d32 (5) + ADD RSP imm32 (7) + PUSH RAX (1)
    if op == "EQ"         { emit 44 }   // smart-int dispatch + kr_cmpi slow path
    if op == "NEQ"        { emit 44 }
    if op == "LT"         { emit 44 }
    if op == "GT"         { emit 44 }
    if op == "LTE"        { emit 44 }
    if op == "GTE"        { emit 44 }
    if op == "NEG"        { emit 5 }    // POP RAX + NEG RAX + PUSH RAX
    if op == "NOT"        { emit 10 }   // POP RDI + CALL kr_istruthy + XOR EAX,1 + PUSH RAX
    if op == "RETURN"     { emit 6 }    // POP RAX (1) + MOV RSP,RBP (3) + POP RBP (1) + RET (1)
    if op == "BUILTIN_KP" { emit 25 }   // smart: POP+CMP+JAE+kr_str_int+kr_print+PUSH 0
    if op == "BUILTIN_TOSTR" { emit 7 } // POP RDI (1) + CALL d32 (5) + PUSH RAX (1)
    if op == "BUILTIN_TOINT" { emit 7 } // POP RDI + CALL kr_atoi + PUSH RAX
    if op == "BUILTIN_LENGTH"{ emit 7 } // POP RDI + CALL kr_length + PUSH RAX
    if op == "BUILTIN_LEN"   { emit 24 } // smart: POP+CMP+JGE+CALL kr_str_int+MOV+CALL kr_strlen+PUSH
    if op == "BUILTIN_SPLIT" { emit 8 } // POP RSI(1) + POP RDI(1) + CALL kr_split(5) + PUSH RAX(1)
    if op == "BUILTIN_RANGE" { emit 8 } // POP RSI + POP RDI + CALL kr_range + PUSH RAX
    if op == "INDEX"         { emit 8 } // POP RSI + POP RDI + CALL kr_index + PUSH RAX
    if op == "BUILTIN_ARG"   { emit 7 } // POP RDI + CALL kr_arg + PUSH RAX
    if op == "BUILTIN_ARGCOUNT"{ emit 6 } // CALL kr_argcount + PUSH RAX (no args)
    if op == "BUILTIN_SUBSTRING" { emit 9 } // POP RDX + POP RSI + POP RDI + CALL + PUSH RAX
    if op == "BUILTIN_SB_NEW"    { emit 6 }  // CALL kr_sbnew + PUSH RAX
    if op == "BUILTIN_SB_APPEND" { emit 8 }  // POP RSI + POP RDI + CALL kr_sbappend + PUSH RAX
    if op == "BUILTIN_SB_TOSTR"  { emit 7 }  // POP RDI + CALL kr_sbtostring + PUSH RAX
    if op == "BUILTIN_READFILE"  { emit 7 }  // POP RDI + CALL kr_readfile + PUSH RAX
    if op == "BUILTIN_WRITEFILE" { emit 8 }  // POP RSI + POP RDI + CALL kr_writefile + PUSH RAX
    if op == "BUILTIN_WRITEBYTES"{ emit 8 }  // POP RSI + POP RDI + CALL kr_writebytes + PUSH RAX
    if op == "BUILTIN_PRINTERR"  { emit 8 }  // POP RDI + CALL kr_printerr + PUSH 0
    if op == "BUILTIN_CHARCODE"  { emit 7 }  // POP RDI + CALL kr_charcode + PUSH RAX
    if op == "BUILTIN_FROMCHARCODE" { emit 7 } // POP RDI + CALL + PUSH RAX
    if op == "BUILTIN_EXIT"      { emit 7 }  // POP RDI + CALL kr_exit + PUSH RAX (RAX never used)
    if op == "BUILTIN_ISDIGIT"   { emit 7 }  // POP RDI + CALL + PUSH RAX
    if op == "BUILTIN_ISALPHA"   { emit 7 }
    if op == "BUILTIN_ABS"       { emit 7 }
    if op == "BUILTIN_STARTSWITH"{ emit 8 }  // POP RSI + POP RDI + CALL + PUSH RAX
    if op == "BUILTIN_ISTRUTHY"  { emit 7 }  // POP RDI + CALL + PUSH RAX
    if op == "BUILTIN_LINECOUNT" { emit 7 }  // POP RDI + CALL + PUSH RAX
    if op == "BUILTIN_GETLINE"   { emit 8 }  // POP RSI + POP RDI + CALL + PUSH RAX
    if op == "BUILTIN_TRIM"      { emit 7 }  // POP RDI + CALL + PUSH RAX
    if op == "BUILTIN_TOUPPER"   { emit 7 }  // POP RDI + CALL + PUSH RAX
    if op == "BUILTIN_TOLOWER"   { emit 7 }  // POP RDI + CALL + PUSH RAX
    if op == "BUILTIN_REVERSE"   { emit 7 }  // POP RDI + CALL + PUSH RAX
    if op == "BUILTIN_POW"       { emit 8 }  // POP RSI + POP RDI + CALL + PUSH RAX
    if op == "BUILTIN_MIN"       { emit 8 }  // POP RSI + POP RDI + CALL kr_min + PUSH RAX
    if op == "BUILTIN_MAX"       { emit 8 }  // POP RSI + POP RDI + CALL kr_max + PUSH RAX
    if op == "BUILTIN_BITAND"    { emit 8 }  // POP RSI + POP RDI + CALL + PUSH RAX
    if op == "BUILTIN_BITOR"     { emit 8 }
    if op == "BUILTIN_BITXOR"    { emit 8 }
    if op == "BUILTIN_SHL"       { emit 8 }
    if op == "BUILTIN_SHR"       { emit 8 }
    if op == "BUILTIN_HX"        { emit 7 }  // POP RDI + CALL kr_hex + PUSH RAX
    if op == "BUILTIN_BN"        { emit 7 }  // POP RDI + CALL kr_bin + PUSH RAX
    if op == "BUILTIN_BITNOT"    { emit 7 }  // POP RDI + CALL + PUSH RAX (1-arg)
    if op == "BUILTIN_REPEAT"    { emit 8 }  // POP RSI + POP RDI + CALL + PUSH RAX
    if op == "BUILTIN_CONTAINS"  { emit 8 }  // POP RSI + POP RDI + CALL + PUSH RAX
    if op == "BUILTIN_INDEXOF"   { emit 8 }
    if op == "BUILTIN_ENDSWITH"  { emit 8 }
    if op == "BUILTIN_REPLACE"   { emit 9 }  // POP RDX + POP RSI + POP RDI + CALL + PUSH RAX
    if op == "BUILTIN_ENVNEW"    { emit 2 }  // PUSH 0 (NULL env)
    if op == "BUILTIN_ENVSET"    { emit 31 } // alloc 24-byte EnvEntry, store name/val/prev, push entry
    if op == "BUILTIN_ENVGET"    { emit 61 } // walk linked list, strcmp names, return value or empty
    if op == "SETFIELD_STR"      { emit 40 } // envSet with name from immediate (strTab vaddr)
    if op == "GETFIELD_STR"      { emit 70 } // envGet with name from immediate (strTab vaddr)
    if op == "BUILTIN_HASFIELD"  { emit 54 } // envGet-like: returns 1 if found, 0 if not
    if op == "BUILTIN_STRUCTFIELDS" { emit 88 } // walk env, build comma-sep string of names
    // Native BSD-socket builtins — inline x86-64 syscalls, NO C runtime (Path A).
    // Linux ABI: nr in RAX, args RDI,RSI,RDX,R10,R8,R9; `syscall` = 0F 05.
    // Counts MUST equal the emit block in emitFuncCode exactly (or offsets desync).
    if op == "BUILTIN_SOCKMAKE"    { emit 20 } // socket(2,1,0)=41
    if op == "BUILTIN_SOCKBIND"    { emit 50 } // bind(fd,&sa,16)=49; builds 16B sockaddr_in on stack
    if op == "BUILTIN_SOCKLISTEN"  { emit 10 } // listen(fd,backlog)=50
    if op == "BUILTIN_SOCKACCEPT"  { emit 13 } // accept(fd,0,0)=43
    if op == "BUILTIN_SOCKRECV"    { emit 20 } // recvfrom(fd,buf,len,0,0,0)=45
    if op == "BUILTIN_SOCKSEND"    { emit 11 } // write(fd,buf,len)=1
    if op == "BUILTIN_SOCKCLOSE"   { emit 9 }  // close(fd)=3
    if op == "BUILTIN_SOCKCONNECT" { emit 77 } // connect(fd,&sa,16)=42; sockaddr_in with IP a.b.c.d on stack
    if op == "BUILTIN_SOCKRECVSTR" { emit 57 } // kr_alloc 64K, recvfrom, NUL-term, return buf
    if op == "BUILTIN_UNIXCONNECT" { emit 90 } // socket(AF_UNIX,STREAM,0)+connect(&sockaddr_un{path}); for X11/Wayland
    // Byte-buffer builtins (Phase C parity from x64.k, but inline/C-free) — for binary
    // wire protocols (X11) that NUL-laden Krypton C-strings can't hold. buf ptr is a
    // kr_alloc'd heap pointer; offsets index it directly. (kr_bufgetdwordat result may
    // exceed 0x7F000000 and be re-tagged as a pointer — caller's caution until 64-bit ints.)
    if op == "BUILTIN_BUFNEW"        { emit 7 }  // pop size; call kr_alloc; push ptr
    if op == "BUILTIN_BUFSETBYTE"    { emit 7 }  // [buf+off] = val
    if op == "BUILTIN_BUFGETBYTE"    { emit 7 }  // movzx byte
    if op == "BUILTIN_BUFGETWORDAT"  { emit 7 }  // movzx word (u16 LE)
    if op == "BUILTIN_BUFGETDWORDAT" { emit 6 }  // mov eax (u32 LE)
    if op == "BUILTIN_BUFGETQWORDAT" { emit 7 }  // mov rax (u64 LE)
    // readProc(path): inline open + read-loop + close (works on /proc & /sys
    // virtual files whose st_size is 0, where kr_readfile's fstat path reads 0).
    if op == "BUILTIN_READPROC"    { emit 95 }
    // environ(name): walk envp (saved at [R14+16] by _start) for "name=", return
    // the value ptr (into the env block, NUL-terminated) or "" if absent.
    if op == "BUILTIN_ENVIRON"     { emit 69 }
    // exec(cmd): pipe2+fork+dup2+execve(/bin/sh -c cmd)+read-loop+wait4, capture
    // stdout, return buffer. shellRun(cmd): fork+execve+wait4, return exit code
    // as a string (kr_str_int). Counts MUST equal the emit blocks byte-for-byte.
    if op == "BUILTIN_EXEC"        { emit 265 }
    if op == "BUILTIN_SHELLRUN"    { emit 142 }
    if op == "POP"        { emit 1 }
    if op == "LABEL"      { emit 0 }
    if op == "JUMP"       { emit 5 }    // E9 + d32
    if op == "JUMPIFNOT"  { emit 10 }   // POP RAX (1) + TEST RAX,RAX (3) + JZ d32 (6)
    if op == "JUMPIF"     { emit 10 }   // POP RAX (1) + TEST RAX,RAX (3) + JNZ d32 (6)
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
                // Some Krypton builtins (getLine, lineCount, envGet, envSet, ...)
                // are emitted by compile.k as CALL rather than BUILTIN. Intercept
                // the known builtin-aliases here so they route through our
                // hand-rolled runtime helpers instead of trying to call a
                // (non-existent) user function symbol.
                let cj = 0
                while cj < len(rest) && rest[cj] != " " { cj += 1 }
                let cname = substring(rest, 0, cj)
                if opCount > 0 { opSb = sbAppend(opSb, "\n") }
                if cname == "getLine" {
                    opSb = sbAppend(opSb, "BUILTIN_GETLINE")
                } else if cname == "lineCount" {
                    opSb = sbAppend(opSb, "BUILTIN_LINECOUNT")
                } else if cname == "writeBytes" {
                    // writeBytes(path, hexContent): hex-decode "xHH" → raw bytes →
                    // file. NOT writeFile (which writes a NUL-terminated string and
                    // would stop at the binary's first 0 byte). Routes to the
                    // dedicated kr_writebytes helper.
                    opSb = sbAppend(opSb, "BUILTIN_WRITEBYTES")
                } else if cname == "bitAnd" {
                    opSb = sbAppend(opSb, "BUILTIN_BITAND")
                } else if cname == "bitOr" {
                    opSb = sbAppend(opSb, "BUILTIN_BITOR")
                } else if cname == "bitXor" {
                    opSb = sbAppend(opSb, "BUILTIN_BITXOR")
                } else if cname == "bitNot" {
                    opSb = sbAppend(opSb, "BUILTIN_BITNOT")
                } else if cname == "shl" {
                    opSb = sbAppend(opSb, "BUILTIN_SHL")
                } else if cname == "shr" {
                    opSb = sbAppend(opSb, "BUILTIN_SHR")
                } else {
                    opSb = sbAppend(opSb, "CALL_FUNC " + rest)
                }
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
                } else if bname == "length" || bname == "count" {
                    // count is an alias for length — both count comma-separated
                    // elements in a string-as-list.
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
                } else if bname == "isTruthy" {
                    opSb = sbAppend(opSb, "BUILTIN_ISTRUTHY")
                } else if bname == "lineCount" {
                    opSb = sbAppend(opSb, "BUILTIN_LINECOUNT")
                } else if bname == "getLine" {
                    opSb = sbAppend(opSb, "BUILTIN_GETLINE")
                } else if bname == "trim" {
                    opSb = sbAppend(opSb, "BUILTIN_TRIM")
                } else if bname == "toUpper" {
                    opSb = sbAppend(opSb, "BUILTIN_TOUPPER")
                } else if bname == "toLower" {
                    opSb = sbAppend(opSb, "BUILTIN_TOLOWER")
                } else if bname == "reverse" {
                    opSb = sbAppend(opSb, "BUILTIN_REVERSE")
                } else if bname == "pow" {
                    opSb = sbAppend(opSb, "BUILTIN_POW")
                } else if bname == "min" {
                    opSb = sbAppend(opSb, "BUILTIN_MIN")
                } else if bname == "max" {
                    opSb = sbAppend(opSb, "BUILTIN_MAX")
                } else if bname == "hex" {
                    opSb = sbAppend(opSb, "BUILTIN_HX")
                } else if bname == "bin" {
                    opSb = sbAppend(opSb, "BUILTIN_BN")
                } else if bname == "repeat" {
                    opSb = sbAppend(opSb, "BUILTIN_REPEAT")
                } else if bname == "contains" {
                    opSb = sbAppend(opSb, "BUILTIN_CONTAINS")
                } else if bname == "indexOf" {
                    opSb = sbAppend(opSb, "BUILTIN_INDEXOF")
                } else if bname == "endsWith" {
                    opSb = sbAppend(opSb, "BUILTIN_ENDSWITH")
                } else if bname == "replace" {
                    opSb = sbAppend(opSb, "BUILTIN_REPLACE")
                } else if bname == "envNew" {
                    opSb = sbAppend(opSb, "BUILTIN_ENVNEW")
                } else if bname == "envSet" {
                    opSb = sbAppend(opSb, "BUILTIN_ENVSET")
                } else if bname == "envGet" {
                    opSb = sbAppend(opSb, "BUILTIN_ENVGET")
                } else if bname == "structNew" {
                    // Same shape as envNew: returns NULL sentinel.
                    opSb = sbAppend(opSb, "BUILTIN_ENVNEW")
                } else if bname == "setField" {
                    // Same shape as envSet (env, name, val) → new entry.
                    opSb = sbAppend(opSb, "BUILTIN_ENVSET")
                } else if bname == "getField" {
                    opSb = sbAppend(opSb, "BUILTIN_ENVGET")
                } else if bname == "hasField" {
                    opSb = sbAppend(opSb, "BUILTIN_HASFIELD")
                } else if bname == "structFields" {
                    opSb = sbAppend(opSb, "BUILTIN_STRUCTFIELDS")
                } else if bname == "gcShadowCount" {
                    // GC root-shadow ops emitted by the 2.x front-end. This
                    // backend has no precise-GC shadow stack, so stub them — but
                    // with the CORRECT stack effect or the eval stack desyncs
                    // (the unsupported no-op left the following STORE popping a
                    // never-pushed value). gcShadowCount() takes 0 args and
                    // PUSHES a count → push a dummy 0.
                    opSb = sbAppend(opSb, "PUSH_INT 0")
                } else if bname == "gcShadowPush" || bname == "gcShadowPop" {
                    // 1 arg, returns a value (the arg is the GC root / pop-count,
                    // which we ignore). Consume the arg, push a dummy result so
                    // the surrounding LOAD…POP stays balanced.
                    opSb = sbAppend(opSb, "POP\nPUSH_INT 0")
                    opCount += 1
                } else if bname == "sockMake" {
                    opSb = sbAppend(opSb, "BUILTIN_SOCKMAKE")
                } else if bname == "sockBind" {
                    opSb = sbAppend(opSb, "BUILTIN_SOCKBIND")
                } else if bname == "sockListen" {
                    opSb = sbAppend(opSb, "BUILTIN_SOCKLISTEN")
                } else if bname == "sockAccept" {
                    opSb = sbAppend(opSb, "BUILTIN_SOCKACCEPT")
                } else if bname == "sockRecv" {
                    opSb = sbAppend(opSb, "BUILTIN_SOCKRECV")
                } else if bname == "sockSend" {
                    opSb = sbAppend(opSb, "BUILTIN_SOCKSEND")
                } else if bname == "sockClose" {
                    opSb = sbAppend(opSb, "BUILTIN_SOCKCLOSE")
                } else if bname == "sockConnect" {
                    opSb = sbAppend(opSb, "BUILTIN_SOCKCONNECT")
                } else if bname == "sockRecvStr" {
                    opSb = sbAppend(opSb, "BUILTIN_SOCKRECVSTR")
                } else if bname == "unixConnect" {
                    opSb = sbAppend(opSb, "BUILTIN_UNIXCONNECT")
                } else if bname == "bufNew" {
                    opSb = sbAppend(opSb, "BUILTIN_BUFNEW")
                } else if bname == "bufSetByte" {
                    opSb = sbAppend(opSb, "BUILTIN_BUFSETBYTE")
                } else if bname == "bufGetByte" {
                    opSb = sbAppend(opSb, "BUILTIN_BUFGETBYTE")
                } else if bname == "bufGetWordAt" {
                    opSb = sbAppend(opSb, "BUILTIN_BUFGETWORDAT")
                } else if bname == "bufGetDwordAt" {
                    opSb = sbAppend(opSb, "BUILTIN_BUFGETDWORDAT")
                } else if bname == "bufGetQwordAt" {
                    opSb = sbAppend(opSb, "BUILTIN_BUFGETQWORDAT")
                } else if bname == "readProc" {
                    opSb = sbAppend(opSb, "BUILTIN_READPROC")
                } else if bname == "environ" {
                    opSb = sbAppend(opSb, "BUILTIN_ENVIRON")
                } else if bname == "exec" {
                    opSb = sbAppend(opSb, "BUILTIN_EXEC")
                } else if bname == "shellRun" {
                    opSb = sbAppend(opSb, "BUILTIN_SHELLRUN")
                } else {
                    // Unknown builtin: emit a marker and leave the stack
                    // alone. Programs that hit this are already incorrect;
                    // a "balanced" stub that pushes 0 makes things WORSE
                    // because callers like length() then dereference 0.
                    opSb = sbAppend(opSb, "UNSUPPORTED " + bname)
                }
                opCount += 1
            } else if op == "ADD" || op == "SUB" || op == "MUL" || op == "DIV" || op == "MOD"
                   || op == "EQ" || op == "NEQ" || op == "LT" || op == "GT" || op == "LTE" || op == "GTE"
                   || op == "CAT" || op == "INDEX" || op == "POP" || op == "RETURN"
                   || op == "NEG" || op == "NOT" {
                if opCount > 0 { opSb = sbAppend(opSb, "\n") }
                opSb = sbAppend(opSb, op)
                opCount += 1
            } else if op == "LABEL" || op == "JUMP" || op == "JUMPIFNOT" || op == "JUMPIF" {
                if opCount > 0 { opSb = sbAppend(opSb, "\n") }
                opSb = sbAppend(opSb, op + " " + rest)
                opCount += 1
            } else if op == "STRUCTNEW" {
                // Same shape as envNew: produce an empty struct (NULL sentinel).
                if opCount > 0 { opSb = sbAppend(opSb, "\n") }
                opSb = sbAppend(opSb, "BUILTIN_ENVNEW")
                opCount += 1
            } else if op == "SETFIELD" || op == "GETFIELD" {
                // Field name comes as op-text suffix. Intern it as a string so
                // we can reference it by strTab index from emitFuncCode.
                let interned = internStr(strTab, strCount, rest)
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
                opSb = sbAppend(opSb, op + "_STR " + idx)
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
    // Prefix the strTab with its line count so the reader can consume exactly
    // that many lines: a string-table ENTRY may itself be "~~~" (the section
    // delimiter), so scanning for "~~~" would truncate the table. Read by count.
    emit strCount + "\n" + strTab + "\n" + sbToString(resultSb)
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

func emitFuncCode(opList, strVAddrs, argcount, localCount, labels, funcVAddrs, funcStartVAddr, krPrintVAddr, krStrIntVAddr, krConcatVAddr, krAtoiVAddr, krLengthVAddr, krStrlenVAddr, krSplitVAddr, krRangeVAddr, krIndexVAddr, krArgVAddr, krArgcountVAddr, krSubstringVAddr, krAllocVAddr, krReadfileVAddr, krWritefileVAddr, krPrinterrVAddr, krCharcodeVAddr, krFromcharcodeVAddr, krExitVAddr, krIsdigitVAddr, krIsalphaVAddr, krAbsVAddr, krStartswithVAddr, krIstruthyVAddr, krLinecountVAddr, krGetlineVAddr, krTrimVAddr, krToupperVAddr, krTolowerVAddr, krPowVAddr, krRepeatVAddr, krPlusVAddr, krSubiVAddr, krMuliVAddr, krDiviVAddr, krModiVAddr, krCmpiVAddr, krContainsVAddr, krIndexofVAddr, krEndswithVAddr, krReplaceVAddr, krStrcmpVAddr, krReverseVAddr, krSbnewVAddr, krSbappendVAddr, krSbtostringVAddr, krMinVAddr, krMaxVAddr, krBitandVAddr, krBitorVAddr, krBitxorVAddr, krBitnotVAddr, krShlVAddr, krShrVAddr, krHexVAddr, krBinVAddr) {
    let c = sbNew()
    c = sbAppend(c, hexByte(0x55))  // [+0] PUSH RBP
    c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xE5))  // [+1] MOV RBP, RSP
    if localCount > 0 {
        // SUB RSP, imm32 (allocate 8 bytes per local, 16-byte aligned)
        let bytes = localCount * 8
        let pad = 0
        if bytes % 16 != 0 { pad = 16 - (bytes % 16) }
        let total = bytes + pad
        c = sbAppend(c, hexByte(0x48) + hexByte(0x81) + hexByte(0xEC) + hexDword(total))
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
            let vaddr = toInt(getLine(strVAddrs, idx))   // load-base offset
            c = sbAppend(c, hexByte(0x48) + hexByte(0xBF) + hexQwordVaddr(vaddr))
            c = sbAppend(c, hexByte(0x57))
        } else if op == "PUSH_INT" {
            let n = toInt(rest)
            c = sbAppend(c, hexByte(0x48) + hexByte(0xBF) + hexQword(n))
            c = sbAppend(c, hexByte(0x57))
        } else if op == "STORE_LOCAL" {
            let slot = toInt(rest)
            let dispVal = 0 - (slot * 8)
            c = sbAppend(c, hexByte(0x58))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0x85) + hexDword(dispVal))
        } else if op == "LOAD_LOCAL" {
            let slot = toInt(rest)
            let dispVal = 0 - (slot * 8)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x8B) + hexByte(0x85) + hexDword(dispVal))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "LOAD_PARAM" {
            // PARAM idx 0 (first declared) is at the BOTTOM of pushed args, i.e. highest RBP offset.
            // Stack from caller: pushes p0, p1, ..., pN-1 in order. After CALL+prologue:
            //   [RBP+0]=savedRBP, [RBP+8]=retaddr, [RBP+16]=pN-1, [RBP+24]=pN-2, ..., [RBP+16+(N-1)*8]=p0
            let idx = toInt(rest)
            let dispVal = 16 + (argcount - 1 - idx) * 8
            c = sbAppend(c, hexByte(0x48) + hexByte(0x8B) + hexByte(0x85) + hexDword(dispVal))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "STORE_PARAM" {
            let idx = toInt(rest)
            let dispVal = 16 + (argcount - 1 - idx) * 8
            c = sbAppend(c, hexByte(0x58))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0x85) + hexDword(dispVal))
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
            //   CALL kr_plus at [29-33]: disp = krPlusVAddr - (funcStartVAddr + off + 34)
            //
            // Slow path now calls kr_plus (numeric-aware) instead of kr_concat:
            // matches C runtime semantics where "5"+"3" = 8, "5"+"x" = "5x".
            let plusDisp = krPlusVAddr - (funcStartVAddr + off + 34)
            c = sbAppend(c, hexByte(0x59) + hexByte(0x58))  // [0-1] POP RCX, POP RAX
            c = sbAppend(c, hexByte(0xBA) + hexDwordVaddr(0))  // [2-6] MOV EDX, 0x40000000
            c = sbAppend(c, hexByte(0x48) + hexByte(0x39) + hexByte(0xD0))  // [7-9] CMP RAX, RDX
            c = sbAppend(c, hexByte(0x7D) + hexByte(0x0B))  // [10-11] JAE +11 → 23
            c = sbAppend(c, hexByte(0x48) + hexByte(0x39) + hexByte(0xD1))  // [12-14] CMP RCX, RDX
            c = sbAppend(c, hexByte(0x7D) + hexByte(0x06))  // [15-16] JAE +6 → 23
            c = sbAppend(c, hexByte(0x48) + hexByte(0x01) + hexByte(0xC8))  // [17-19] ADD RAX, RCX (fast int path)
            c = sbAppend(c, hexByte(0x50))  // [20] PUSH RAX
            c = sbAppend(c, hexByte(0xEB) + hexByte(0x0C))  // [21-22] JMP +12 → 35
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xC7))  // [23-25] MOV RDI, RAX
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xCE))  // [26-28] MOV RSI, RCX
            c = sbAppend(c, hexByte(0xE8) + hexDword(plusDisp))  // [29-33] CALL kr_plus
            c = sbAppend(c, hexByte(0x50))  // [34] PUSH RAX
        } else if op == "CAT" {
            // String concat: POP RSI (b, top) ; POP RDI (a) ; CALL kr_concat ; PUSH RAX
            // CALL is at offset 2 from start of this op, ends at 7. disp computed from emit RIP.
            c = sbAppend(c, hexByte(0x5E))  // POP RSI (b)
            c = sbAppend(c, hexByte(0x5F))  // POP RDI (a)
            let catDisp = krConcatVAddr - (funcStartVAddr + off + 2 + 5)
            c = sbAppend(c, hexByte(0xE8) + hexDword(catDisp))
            c = sbAppend(c, hexByte(0x50))  // PUSH RAX
        } else if op == "SUB" || op == "MUL" || op == "DIV" || op == "MOD" {
            // Smart-int dispatch (29 bytes): fast path if both args are small ints
            // (native op preserves correctness since both are real ints), otherwise
            // call the kr_*i helper which atois both args. Mirrors C runtime where
            // these ops are always atoi-based, but we keep the int+int fast path
            // because that's the common case and is much faster than C.
            //
            // Layout:
            //   [0]    59           POP RCX (b)                            (1)
            //   [1]    58           POP RAX (a)                            (1)
            //   [2-6]  BA imm       MOV EDX, 0x40000000                    (5)
            //   [7-9]  48 39 D0     CMP RAX, RDX                           (3)
            //   [10-11] 73 0B       JAE +11 → .slow at 23                  (2)
            //   [12-14] 48 39 D1    CMP RCX, RDX                           (3)
            //   [15-16] 73 06       JAE +6 → .slow at 23                   (2)
            //   ; fast int path (3 bytes for op + 1 PUSH + 2 JMP = varies)
            //   [17-19] op          (3 bytes for SUB/IMUL; for DIV/MOD see below)
            //   [20]    50/52       PUSH RAX (or RDX for MOD)              (1)
            //   [21-22] EB ?        JMP .end                               (2)
            //   .slow at [23]:
            //   [23-25] 48 89 C7    MOV RDI, RAX                           (3)
            //   [26-28] 48 89 CE    MOV RSI, RCX                           (3)
            //   [29-33] E8 dd       CALL kr_*i                             (5)
            //   [34]    50          PUSH RAX                               (1)
            //   .end at [35]
            //
            // For SUB: fast path is 48 29 C8 (3) + 50 (1) = 4 bytes at [17-20]
            // For MUL: fast path is 48 0F AF C1 (4) + 50 (1) = 5 bytes — needs adjustment
            // For DIV/MOD: CQO + IDIV RCX (5 bytes) + PUSH RAX/RDX (1) — adjust
            //
            // To keep all four ops the same total size, lay them out with:
            //   - SUB: [17-19] SUB RAX, RCX; [20] PUSH RAX           (3+1=4 bytes)
            //   - MUL: [17-20] IMUL RAX, RCX; [21] PUSH RAX          (4+1=5 bytes — shifts JMP target)
            //   - DIV: [17-18] CQO; [19-21] IDIV RCX; [22] PUSH RAX  (2+3+1=6 bytes)
            //   - MOD: [17-18] CQO; [19-21] IDIV RCX; [22] PUSH RDX  (6 bytes)
            // The JMP target shifts depending on fast-path size. Compute per op.

            let helperVAddr = krSubiVAddr
            if op == "MUL" { helperVAddr = krMuliVAddr }
            if op == "DIV" { helperVAddr = krDiviVAddr }
            if op == "MOD" { helperVAddr = krModiVAddr }

            // Fast-path body bytes
            let fastBody = ""
            if op == "SUB" {
                fastBody = hexByte(0x48) + hexByte(0x29) + hexByte(0xC8) + hexByte(0x50)
            }
            if op == "MUL" {
                fastBody = hexByte(0x48) + hexByte(0x0F) + hexByte(0xAF) + hexByte(0xC1) + hexByte(0x50)
            }
            if op == "DIV" {
                fastBody = hexByte(0x48) + hexByte(0x99) + hexByte(0x48) + hexByte(0xF7) + hexByte(0xF9) + hexByte(0x50)
            }
            if op == "MOD" {
                fastBody = hexByte(0x48) + hexByte(0x99) + hexByte(0x48) + hexByte(0xF7) + hexByte(0xF9) + hexByte(0x52)
            }
            let fastLen = hexBytesLen(fastBody)
            // Slow path: MOV RDI, RAX (3) + MOV RSI, RCX (3) + CALL d32 (5) + PUSH RAX (1) = 12 bytes
            // Total op size = 17 (header) + fastLen + 2 (JMP) + 12 (slow) = fastLen + 31
            // .slow offset = 17 + fastLen + 2
            let slowOff = 17 + fastLen + 2
            let totalSize = fastLen + 31
            // JAE distance: target slow at slowOff. From [10-11] after at 12. disp1 = slowOff - 12
            // From [15-16] after at 17. disp2 = slowOff - 17
            let disp1 = slowOff - 12
            let disp2 = slowOff - 17
            // JMP .end: target = end of op = totalSize. From after JMP at slowOff. disp3 = totalSize - slowOff
            let disp3 = totalSize - slowOff
            // CALL helper: at offset slowOff + 6. Ends at slowOff + 11. disp = helperVAddr - (funcStartVAddr + off + slowOff + 11)
            let callDisp = helperVAddr - (funcStartVAddr + off + slowOff + 11)

            c = sbAppend(c, hexByte(0x59) + hexByte(0x58))  // [0-1] POP RCX, POP RAX
            c = sbAppend(c, hexByte(0xBA) + hexDwordVaddr(0))  // [2-6] MOV EDX, 0x40000000
            c = sbAppend(c, hexByte(0x48) + hexByte(0x39) + hexByte(0xD0))  // [7-9] CMP RAX, RDX
            c = sbAppend(c, hexByte(0x7D) + hexByte(disp1))  // [10-11] JAE → slow
            c = sbAppend(c, hexByte(0x48) + hexByte(0x39) + hexByte(0xD1))  // [12-14] CMP RCX, RDX
            c = sbAppend(c, hexByte(0x7D) + hexByte(disp2))  // [15-16] JAE → slow
            c = sbAppend(c, fastBody)  // [17..] fast int path
            c = sbAppend(c, hexByte(0xEB) + hexByte(disp3))  // JMP → .end
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xC7))  // [.slow] MOV RDI, RAX
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xCE))  // MOV RSI, RCX
            c = sbAppend(c, hexByte(0xE8) + hexDword(callDisp))  // CALL kr_*i
            c = sbAppend(c, hexByte(0x50))  // PUSH RAX
        } else if op == "EQ" || op == "NEQ" || op == "LT" || op == "GT" || op == "LTE" || op == "GTE" {
            // Numeric-or-strcmp dispatch (44 bytes). Fast path: both small ints
            // → CMP directly. Slow path: CALL kr_cmpi which handles
            // numeric-string + strcmp fallback. Then SETcc on the result.
            //
            // Layout:
            //   [0-1]   POP RCX, POP RAX                                 (2)
            //   [2-6]   MOV EDX, 0x40000000                              (5)
            //   [7-9]   CMP RAX, RDX                                     (3)
            //   [10-11] JAE +10 → .slow at 22                            (2)
            //   [12-14] CMP RCX, RDX                                     (3)
            //   [15-16] JAE +5 → .slow at 22                             (2)
            //   ; both ints — fast int path
            //   [17-19] CMP RAX, RCX                                     (3)
            //   [20-21] JMP +14 → .setcc at 36                           (2)
            //   .slow at [22]:
            //   [22-24] MOV RDI, RAX                                     (3)
            //   [25-27] MOV RSI, RCX                                     (3)
            //   [28-32] CALL kr_cmpi                                     (5)
            //   [33-35] TEST RAX, RAX                                    (3)  ; sets flags from RAX = a-b
            //   .setcc at [36]:
            //   [36-37] XOR EDX, EDX                                     (2)
            //   [38-40] SETcc DL                                         (3)
            //   [41]    PUSH RDX                                         (1)
            //   .end at [42]
            //
            // SETcc DL on CMP RAX, RCX flags === SETcc DL on TEST (RAX-RCX) flags
            // for signed/zero predicates (SF, ZF, OF), so same opcode works
            // on both paths.
            let cmpiDisp = krCmpiVAddr - (funcStartVAddr + off + 33)
            let cc = 0x94
            if op == "NEQ" { cc = 0x95 }
            if op == "LT"  { cc = 0x9C }
            if op == "GT"  { cc = 0x9F }
            if op == "LTE" { cc = 0x9E }
            if op == "GTE" { cc = 0x9D }
            c = sbAppend(c, hexByte(0x59) + hexByte(0x58))  // [0-1]
            c = sbAppend(c, hexByte(0xBA) + hexDwordVaddr(0))  // [2-6]
            c = sbAppend(c, hexByte(0x48) + hexByte(0x39) + hexByte(0xD0))  // [7-9] CMP RAX, RDX
            c = sbAppend(c, hexByte(0x7D) + hexByte(0x0A))  // [10-11] JAE → 22
            c = sbAppend(c, hexByte(0x48) + hexByte(0x39) + hexByte(0xD1))  // [12-14] CMP RCX, RDX
            c = sbAppend(c, hexByte(0x7D) + hexByte(0x05))  // [15-16] JAE → 22
            c = sbAppend(c, hexByte(0x48) + hexByte(0x39) + hexByte(0xC8))  // [17-19] CMP RAX, RCX (fast)
            c = sbAppend(c, hexByte(0xEB) + hexByte(0x0E))  // [20-21] JMP → 36
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xC7))  // [22-24] MOV RDI, RAX
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xCE))  // [25-27] MOV RSI, RCX
            c = sbAppend(c, hexByte(0xE8) + hexDword(cmpiDisp))  // [28-32] CALL kr_cmpi
            c = sbAppend(c, hexByte(0x48) + hexByte(0x85) + hexByte(0xC0))  // [33-35] TEST RAX, RAX
            // SETcc reads flags set by CMP/TEST above — must NOT clobber flags first.
            // Use SETcc DL → MOVZX RDX, DL to zero-extend AFTER the SETcc.
            c = sbAppend(c, hexByte(0x0F) + hexByte(cc) + hexByte(0xC2))  // [36-38] SETcc DL
            c = sbAppend(c, hexByte(0x48) + hexByte(0x0F) + hexByte(0xB6) + hexByte(0xD2))  // [39-42] MOVZX RDX, DL
            c = sbAppend(c, hexByte(0x52))  // [43] PUSH RDX
        } else if op == "LABEL" {
            // No code; nothing to emit.
        } else if op == "JUMP" {
            let targetStr = labelOffset(labels, rest)
            let target = toInt(targetStr)
            // E9 d32. After this 5-byte instruction, position is off+5.
            let disp = target - (off + 5)
            c = sbAppend(c, hexByte(0xE9) + hexDword(disp))
        } else if op == "JUMPIFNOT" {
            let targetStr = labelOffset(labels, rest)
            let target = toInt(targetStr)
            // POP RAX (1) ; TEST RAX,RAX (3) ; JZ d32 (6). Total 10. After this, position = off+10.
            c = sbAppend(c, hexByte(0x58))  // POP RAX
            c = sbAppend(c, hexByte(0x48) + hexByte(0x85) + hexByte(0xC0))  // TEST RAX, RAX
            let disp = target - (off + 10)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x84) + hexDword(disp))  // JZ d32
        } else if op == "JUMPIF" {
            // Mirror of JUMPIFNOT but JNZ instead of JZ. compile.k uses
            // this for short-circuit OR (jump if true).
            let targetStr = labelOffset(labels, rest)
            let target = toInt(targetStr)
            c = sbAppend(c, hexByte(0x58))  // POP RAX
            c = sbAppend(c, hexByte(0x48) + hexByte(0x85) + hexByte(0xC0))  // TEST RAX, RAX
            let disp = target - (off + 10)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x85) + hexDword(disp))  // JNZ d32
        } else if op == "RETURN" {
            c = sbAppend(c, hexByte(0x58))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xEC))
            c = sbAppend(c, hexByte(0x5D))
            c = sbAppend(c, hexByte(0xC3))
        } else if op == "NEG" {
            // POP RAX ; NEG RAX ; PUSH RAX (5 bytes)
            c = sbAppend(c, hexByte(0x58))
            c = sbAppend(c, hexByte(0x48) + hexByte(0xF7) + hexByte(0xD8))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "NOT" {
            // Use kr_istruthy then negate, so `!"false"` and `!"0"` (which
            // are non-zero string pointers but falsy per Krypton's truthiness
            // rules) negate to 1, not 0. Previous TEST-RAX-then-SETE form
            // checked pointer-non-zero, missing the falsy-string cases.
            //
            // POP RDI ; CALL kr_istruthy ; XOR EAX, 1 ; PUSH RAX (10 bytes)
            c = sbAppend(c, hexByte(0x5F))  // POP RDI
            let itDispNot = krIstruthyVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(itDispNot))  // CALL kr_istruthy
            c = sbAppend(c, hexByte(0x83) + hexByte(0xF0) + hexByte(0x01))  // XOR EAX, 1 (zero-extended)
            c = sbAppend(c, hexByte(0x50))  // PUSH RAX
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
            c = sbAppend(c, hexByte(0x5F))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x81) + hexByte(0xFF) + hexDwordVaddr(0))
            c = sbAppend(c, hexByte(0x7D) + hexByte(0x08))
            c = sbAppend(c, hexByte(0xE8) + hexDword(siDisp))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xC7))
            c = sbAppend(c, hexByte(0xE8) + hexDword(kpDisp))
            c = sbAppend(c, hexByte(0x6A) + hexByte(0x00))
        } else if op == "BUILTIN_TOSTR" {
            // POP RDI ; CALL kr_str_int ; PUSH RAX
            c = sbAppend(c, hexByte(0x5F))
            let tsDisp = krStrIntVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(tsDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_TOINT" {
            // POP RDI ; CALL kr_atoi ; PUSH RAX
            c = sbAppend(c, hexByte(0x5F))
            let tiDisp = krAtoiVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(tiDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_LENGTH" {
            // POP RDI ; CALL kr_length ; PUSH RAX
            c = sbAppend(c, hexByte(0x5F))
            let lnDisp = krLengthVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(lnDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_LEN" {
            // Smart-int len: convert int → string before strlen, so len(0)
            // returns "1" (the length of "0") rather than dereferencing
            // address 0 as a string pointer. Matches the C runtime where
            // every value is already char* and len = strlen(v).
            //
            // Layout (24 bytes):
            //   [0]   5F                       POP RDI
            //   [1-7] 48 81 FF 00 00 00 40     CMP RDI, 0x40000000
            //   [8-9] 7D 08                    JGE +8 → 18 (.is_str)
            //   [10-14] E8 dw                  CALL kr_str_int
            //   [15-17] 48 89 C7               MOV RDI, RAX
            //   .is_str at 18:
            //   [18-22] E8 dw                  CALL kr_strlen
            //   [23]    50                     PUSH RAX
            let siDisp = krStrIntVAddr - (funcStartVAddr + off + 15)
            let slDisp = krStrlenVAddr - (funcStartVAddr + off + 23)
            c = sbAppend(c, hexByte(0x5F))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x81) + hexByte(0xFF) + hexDwordVaddr(0))
            c = sbAppend(c, hexByte(0x7D) + hexByte(0x08))
            c = sbAppend(c, hexByte(0xE8) + hexDword(siDisp))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xC7))
            c = sbAppend(c, hexByte(0xE8) + hexDword(slDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_SPLIT" {
            // POP RSI (idx, top) ; POP RDI (list) ; CALL kr_split ; PUSH RAX
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            let spDisp = krSplitVAddr - (funcStartVAddr + off + 7)
            c = sbAppend(c, hexByte(0xE8) + hexDword(spDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_RANGE" {
            // POP RSI (b, top) ; POP RDI (a) ; CALL kr_range ; PUSH RAX
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            let rgDisp = krRangeVAddr - (funcStartVAddr + off + 7)
            c = sbAppend(c, hexByte(0xE8) + hexDword(rgDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "INDEX" {
            // POP RSI (idx, top) ; POP RDI (string) ; CALL kr_index ; PUSH RAX
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            let ixDisp = krIndexVAddr - (funcStartVAddr + off + 7)
            c = sbAppend(c, hexByte(0xE8) + hexDword(ixDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_ARG" {
            // POP RDI ; CALL kr_arg ; PUSH RAX
            c = sbAppend(c, hexByte(0x5F))
            let agDisp = krArgVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(agDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_ARGCOUNT" {
            // CALL kr_argcount ; PUSH RAX
            let acDisp = krArgcountVAddr - (funcStartVAddr + off + 5)
            c = sbAppend(c, hexByte(0xE8) + hexDword(acDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_SUBSTRING" {
            // POP RDX (end, top) ; POP RSI (start) ; POP RDI (str) ; CALL kr_substring ; PUSH RAX
            c = sbAppend(c, hexByte(0x5A))
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            let sbDisp = krSubstringVAddr - (funcStartVAddr + off + 8)
            c = sbAppend(c, hexByte(0xE8) + hexDword(sbDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_SB_NEW" {
            // CALL kr_sbnew ; PUSH RAX
            let snDisp = krSbnewVAddr - (funcStartVAddr + off + 5)
            c = sbAppend(c, hexByte(0xE8) + hexDword(snDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_SB_APPEND" {
            // POP RSI (s) ; POP RDI (handle) ; CALL kr_sbappend ; PUSH RAX
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            let saDisp = krSbappendVAddr - (funcStartVAddr + off + 7)
            c = sbAppend(c, hexByte(0xE8) + hexDword(saDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_SB_TOSTR" {
            // POP RDI (handle) ; CALL kr_sbtostring ; PUSH RAX
            c = sbAppend(c, hexByte(0x5F))
            let stDisp = krSbtostringVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(stDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_READFILE" {
            // POP RDI ; CALL kr_readfile ; PUSH RAX
            c = sbAppend(c, hexByte(0x5F))
            let rfDisp = krReadfileVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(rfDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_SOCKMAKE" {
            // sockMake() -> socket(AF_INET=2, SOCK_STREAM=1, 0) = syscall 41. (20 bytes)
            c = sbAppend(c, hexByte(0xBF) + hexDword(2))    // mov edi, 2      (domain)
            c = sbAppend(c, hexByte(0xBE) + hexDword(1))    // mov esi, 1      (type)
            c = sbAppend(c, hexByte(0x31) + hexByte(0xD2))  // xor edx, edx    (proto = 0)
            c = sbAppend(c, hexByte(0xB8) + hexDword(41))   // mov eax, 41     (SYS_socket)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))  // syscall
            c = sbAppend(c, hexByte(0x50))                  // push rax        (fd)
        } else if op == "BUILTIN_SOCKBIND" {
            // sockBind(fd, portHi, portLo) -> bind(fd, &sockaddr_in, 16) = 49. (50 bytes)
            // TOS=portLo, next=portHi, next=fd. Build the 16-byte sockaddr_in on the
            // machine stack (transient — the kernel copies it during bind). Linux has
            // NO sin_len byte: [fam=02 00][port hi][port lo][addr=0 x4][8 zero].
            c = sbAppend(c, hexByte(0x58))                  // pop rax (portLo)
            c = sbAppend(c, hexByte(0x59))                  // pop rcx (portHi)
            c = sbAppend(c, hexByte(0x5F))                  // pop rdi (fd -> bind arg1)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x83) + hexByte(0xEC) + hexByte(0x10)) // sub rsp,16
            c = sbAppend(c, hexByte(0x31) + hexByte(0xD2))  // xor edx,edx (scratch zero)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0x14) + hexByte(0x24)) // mov [rsp],rdx
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0x54) + hexByte(0x24) + hexByte(0x08)) // mov [rsp+8],rdx
            c = sbAppend(c, hexByte(0xC6) + hexByte(0x04) + hexByte(0x24) + hexByte(0x02)) // mov byte [rsp],2 (AF_INET)
            c = sbAppend(c, hexByte(0x88) + hexByte(0x4C) + hexByte(0x24) + hexByte(0x02)) // mov [rsp+2],cl (port hi BE)
            c = sbAppend(c, hexByte(0x88) + hexByte(0x44) + hexByte(0x24) + hexByte(0x03)) // mov [rsp+3],al (port lo)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xE6)) // mov rsi,rsp (&sockaddr)
            c = sbAppend(c, hexByte(0xBA) + hexDword(16))   // mov edx,16  (addrlen)
            c = sbAppend(c, hexByte(0xB8) + hexDword(49))   // mov eax,49  (SYS_bind)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))  // syscall
            c = sbAppend(c, hexByte(0x48) + hexByte(0x83) + hexByte(0xC4) + hexByte(0x10)) // add rsp,16
            c = sbAppend(c, hexByte(0x50))                  // push rax (result)
        } else if op == "BUILTIN_SOCKLISTEN" {
            // sockListen(fd, backlog) -> listen(fd, backlog) = 50. TOS=backlog. (10 bytes)
            c = sbAppend(c, hexByte(0x5E))                  // pop rsi (backlog)
            c = sbAppend(c, hexByte(0x5F))                  // pop rdi (fd)
            c = sbAppend(c, hexByte(0xB8) + hexDword(50))   // mov eax,50 (SYS_listen)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))  // syscall
            c = sbAppend(c, hexByte(0x50))                  // push rax
        } else if op == "BUILTIN_SOCKACCEPT" {
            // sockAccept(fd) -> accept(fd, NULL, NULL) = 43. TOS=fd. (13 bytes)
            c = sbAppend(c, hexByte(0x5F))                  // pop rdi (fd)
            c = sbAppend(c, hexByte(0x31) + hexByte(0xF6))  // xor esi,esi (addr=NULL)
            c = sbAppend(c, hexByte(0x31) + hexByte(0xD2))  // xor edx,edx (addrlen=NULL)
            c = sbAppend(c, hexByte(0xB8) + hexDword(43))   // mov eax,43 (SYS_accept)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))  // syscall
            c = sbAppend(c, hexByte(0x50))                  // push rax (client fd)
        } else if op == "BUILTIN_SOCKRECV" {
            // sockRecv(fd, buf, len) -> recvfrom(fd,buf,len,0,0,0) = 45. (20 bytes)
            // TOS=len, next=buf, next=fd.
            c = sbAppend(c, hexByte(0x5A))                  // pop rdx (len)
            c = sbAppend(c, hexByte(0x5E))                  // pop rsi (buf)
            c = sbAppend(c, hexByte(0x5F))                  // pop rdi (fd)
            c = sbAppend(c, hexByte(0x45) + hexByte(0x31) + hexByte(0xD2)) // xor r10d,r10d (flags)
            c = sbAppend(c, hexByte(0x45) + hexByte(0x31) + hexByte(0xC0)) // xor r8d,r8d  (from=NULL)
            c = sbAppend(c, hexByte(0x45) + hexByte(0x31) + hexByte(0xC9)) // xor r9d,r9d  (fromlen=NULL)
            c = sbAppend(c, hexByte(0xB8) + hexDword(45))   // mov eax,45 (SYS_recvfrom)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))  // syscall
            c = sbAppend(c, hexByte(0x50))                  // push rax (nbytes)
        } else if op == "BUILTIN_SOCKSEND" {
            // sockSend(fd, buf, len) -> write(fd, buf, len) = 1 (blocking TCP). (11 bytes)
            // TOS=len, next=buf, next=fd.
            c = sbAppend(c, hexByte(0x5A))                  // pop rdx (len)
            c = sbAppend(c, hexByte(0x5E))                  // pop rsi (buf)
            c = sbAppend(c, hexByte(0x5F))                  // pop rdi (fd)
            c = sbAppend(c, hexByte(0xB8) + hexDword(1))    // mov eax,1 (SYS_write)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))  // syscall
            c = sbAppend(c, hexByte(0x50))                  // push rax (nbytes)
        } else if op == "BUILTIN_SOCKCLOSE" {
            // sockClose(fd) -> close(fd) = 3. TOS=fd. (9 bytes)
            c = sbAppend(c, hexByte(0x5F))                  // pop rdi (fd)
            c = sbAppend(c, hexByte(0xB8) + hexDword(3))    // mov eax,3 (SYS_close)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))  // syscall
            c = sbAppend(c, hexByte(0x50))                  // push rax
        } else if op == "BUILTIN_SOCKCONNECT" {
            // sockConnect(fd, a, b, c, d, portHi, portLo) -> connect(fd,&sa,16) = 42.
            // Client side; IP a.b.c.d + big-endian port (pre-split in Krypton).
            // TOS=portLo, then portHi, d, c, b, a, fd. Builds the 16-byte
            // sockaddr_in on the stack (Linux: no sin_len; family @ offset 0). (77 bytes)
            c = sbAppend(c, hexByte(0x58))                  // pop rax (portLo -> al)
            c = sbAppend(c, hexByte(0x59))                  // pop rcx (portHi -> cl)
            c = sbAppend(c, hexByte(0x5A))                  // pop rdx (ip d -> dl)
            c = sbAppend(c, hexByte(0x5B))                  // pop rbx (ip c -> bl)
            c = sbAppend(c, hexByte(0x5E))                  // pop rsi (ip b -> sil)
            c = sbAppend(c, hexByte(0x5F))                  // pop rdi (ip a -> dil)
            c = sbAppend(c, hexByte(0x41) + hexByte(0x58))  // pop r8  (fd)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x83) + hexByte(0xEC) + hexByte(0x10)) // sub rsp,16
            c = sbAppend(c, hexByte(0x45) + hexByte(0x31) + hexByte(0xC9)) // xor r9d,r9d (zero)
            c = sbAppend(c, hexByte(0x4C) + hexByte(0x89) + hexByte(0x0C) + hexByte(0x24)) // mov [rsp],r9   (zero [0..7])
            c = sbAppend(c, hexByte(0x4C) + hexByte(0x89) + hexByte(0x4C) + hexByte(0x24) + hexByte(0x08)) // mov [rsp+8],r9 (zero [8..15])
            c = sbAppend(c, hexByte(0xC6) + hexByte(0x04) + hexByte(0x24) + hexByte(0x02)) // mov byte [rsp],2 (AF_INET; [1]=0)
            c = sbAppend(c, hexByte(0x88) + hexByte(0x4C) + hexByte(0x24) + hexByte(0x02)) // mov [rsp+2],cl (port hi BE)
            c = sbAppend(c, hexByte(0x88) + hexByte(0x44) + hexByte(0x24) + hexByte(0x03)) // mov [rsp+3],al (port lo)
            c = sbAppend(c, hexByte(0x40) + hexByte(0x88) + hexByte(0x7C) + hexByte(0x24) + hexByte(0x04)) // mov [rsp+4],dil (ip a)
            c = sbAppend(c, hexByte(0x40) + hexByte(0x88) + hexByte(0x74) + hexByte(0x24) + hexByte(0x05)) // mov [rsp+5],sil (ip b)
            c = sbAppend(c, hexByte(0x88) + hexByte(0x5C) + hexByte(0x24) + hexByte(0x06)) // mov [rsp+6],bl (ip c)
            c = sbAppend(c, hexByte(0x88) + hexByte(0x54) + hexByte(0x24) + hexByte(0x07)) // mov [rsp+7],dl (ip d)
            c = sbAppend(c, hexByte(0x4C) + hexByte(0x89) + hexByte(0xC7)) // mov rdi,r8 (fd)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xE6)) // mov rsi,rsp (&sockaddr)
            c = sbAppend(c, hexByte(0xBA) + hexDword(16))   // mov edx,16 (addrlen)
            c = sbAppend(c, hexByte(0xB8) + hexDword(42))   // mov eax,42 (SYS_connect)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))  // syscall
            c = sbAppend(c, hexByte(0x48) + hexByte(0x83) + hexByte(0xC4) + hexByte(0x10)) // add rsp,16
            c = sbAppend(c, hexByte(0x50))                  // push rax (result)
        } else if op == "BUILTIN_UNIXCONNECT" {
            // unixConnect(path) -> socket(AF_UNIX=1, SOCK_STREAM=1, 0) then
            // connect(fd, &sockaddr_un{ family=1, sun_path=path }, 110). Returns the
            // fd on success, or the (negative) connect errno on failure. TOS = path
            // (NUL-terminated string ptr). For local X11 / Wayland display sockets.
            // The path is byte-copied (incl. its NUL) into sun_path @ offset 2; the
            // kernel stops at that NUL, so the rest of the buffer need not be zeroed.
            // 90 bytes — MUST equal opSize BUILTIN_UNIXCONNECT. rbx/r8 are scratch
            // here (same convention as BUILTIN_SOCKCONNECT).
            c = sbAppend(c, hexByte(0x5E))                                                  // pop rsi (path)
            c = sbAppend(c, hexByte(0x56))                                                  // push rsi (save path across socket())
            c = sbAppend(c, hexByte(0xBF) + hexDword(1))                                    // mov edi,1  (AF_UNIX)
            c = sbAppend(c, hexByte(0xBE) + hexDword(1))                                    // mov esi,1  (SOCK_STREAM)
            c = sbAppend(c, hexByte(0x31) + hexByte(0xD2))                                  // xor edx,edx (proto 0)
            c = sbAppend(c, hexByte(0xB8) + hexDword(41))                                   // mov eax,41 (SYS_socket)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))                                  // syscall -> rax = fd
            c = sbAppend(c, hexByte(0x5B))                                                  // pop rbx (path restored)
            c = sbAppend(c, hexByte(0x49) + hexByte(0x89) + hexByte(0xC0))                  // mov r8,rax (fd)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x83) + hexByte(0xEC) + hexByte(0x70))  // sub rsp,112
            c = sbAppend(c, hexByte(0x66) + hexByte(0xC7) + hexByte(0x04) + hexByte(0x24) + hexByte(0x01) + hexByte(0x00)) // mov word [rsp],1 (sun_family)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x8D) + hexByte(0x7C) + hexByte(0x24) + hexByte(0x02)) // lea rdi,[rsp+2] (sun_path)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xDE))                  // mov rsi,rbx (src = path)
            // .copy (offset 0): byte-copy path incl. terminating NUL
            c = sbAppend(c, hexByte(0x8A) + hexByte(0x06))                                  // mov al,[rsi]
            c = sbAppend(c, hexByte(0x88) + hexByte(0x07))                                  // mov [rdi],al
            c = sbAppend(c, hexByte(0x84) + hexByte(0xC0))                                  // test al,al
            c = sbAppend(c, hexByte(0x74) + hexByte(0x08))                                  // je .done (+8)
            c = sbAppend(c, hexByte(0x48) + hexByte(0xFF) + hexByte(0xC6))                  // inc rsi
            c = sbAppend(c, hexByte(0x48) + hexByte(0xFF) + hexByte(0xC7))                  // inc rdi
            c = sbAppend(c, hexByte(0xEB) + hexByte(0xF0))                                  // jmp .copy (-16)
            // .done: connect(fd, &sockaddr_un, 110)
            c = sbAppend(c, hexByte(0x4C) + hexByte(0x89) + hexByte(0xC7))                  // mov rdi,r8 (fd)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xE6))                  // mov rsi,rsp (&sockaddr_un)
            c = sbAppend(c, hexByte(0xBA) + hexDword(110))                                  // mov edx,110 (addrlen)
            c = sbAppend(c, hexByte(0xB8) + hexDword(42))                                   // mov eax,42 (SYS_connect)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))                                  // syscall -> rax = 0 ok / -errno
            c = sbAppend(c, hexByte(0x48) + hexByte(0x83) + hexByte(0xC4) + hexByte(0x70))  // add rsp,112
            c = sbAppend(c, hexByte(0x48) + hexByte(0x85) + hexByte(0xC0))                  // test rax,rax
            c = sbAppend(c, hexByte(0x75) + hexByte(0x03))                                  // jne .fail (+3)
            c = sbAppend(c, hexByte(0x4C) + hexByte(0x89) + hexByte(0xC0))                  // mov rax,r8 (success -> return fd)
            c = sbAppend(c, hexByte(0x50))                                                  // push rax (result)
        } else if op == "BUILTIN_BUFNEW" {
            // bufNew(size) -> kr_alloc(size). TOS=size. (7 bytes)
            c = sbAppend(c, hexByte(0x5F))                                          // pop rdi (size)
            let baDisp = krAllocVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(baDisp))                       // call kr_alloc
            c = sbAppend(c, hexByte(0x50))                                          // push rax (ptr)
        } else if op == "BUILTIN_BUFSETBYTE" {
            // bufSetByte(buf, off, val) -> [buf+off] = val&0xFF, returns val. TOS=val. (7 bytes)
            c = sbAppend(c, hexByte(0x58))                                          // pop rax (val)
            c = sbAppend(c, hexByte(0x59))                                          // pop rcx (off)
            c = sbAppend(c, hexByte(0x5E))                                          // pop rsi (buf)
            c = sbAppend(c, hexByte(0x88) + hexByte(0x04) + hexByte(0x0E))          // mov [rsi+rcx], al
            c = sbAppend(c, hexByte(0x50))                                          // push rax (val)
        } else if op == "BUILTIN_BUFGETBYTE" {
            // bufGetByte(buf, off) -> zero-extended byte. TOS=off. (7 bytes)
            c = sbAppend(c, hexByte(0x59))                                          // pop rcx (off)
            c = sbAppend(c, hexByte(0x5E))                                          // pop rsi (buf)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0xB6) + hexByte(0x04) + hexByte(0x0E)) // movzx eax, byte [rsi+rcx]
            c = sbAppend(c, hexByte(0x50))                                          // push rax
        } else if op == "BUILTIN_BUFGETWORDAT" {
            // bufGetWordAt(buf, off) -> u16 LE. TOS=off. (7 bytes)
            c = sbAppend(c, hexByte(0x59))                                          // pop rcx (off)
            c = sbAppend(c, hexByte(0x5E))                                          // pop rsi (buf)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0xB7) + hexByte(0x04) + hexByte(0x0E)) // movzx eax, word [rsi+rcx]
            c = sbAppend(c, hexByte(0x50))                                          // push rax
        } else if op == "BUILTIN_BUFGETDWORDAT" {
            // bufGetDwordAt(buf, off) -> u32 LE. TOS=off. (6 bytes)
            c = sbAppend(c, hexByte(0x59))                                          // pop rcx (off)
            c = sbAppend(c, hexByte(0x5E))                                          // pop rsi (buf)
            c = sbAppend(c, hexByte(0x8B) + hexByte(0x04) + hexByte(0x0E))          // mov eax, [rsi+rcx] (zero-extends)
            c = sbAppend(c, hexByte(0x50))                                          // push rax
        } else if op == "BUILTIN_BUFGETQWORDAT" {
            // bufGetQwordAt(buf, off) -> u64 LE. TOS=off. (7 bytes)
            c = sbAppend(c, hexByte(0x59))                                          // pop rcx (off)
            c = sbAppend(c, hexByte(0x5E))                                          // pop rsi (buf)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x8B) + hexByte(0x04) + hexByte(0x0E)) // mov rax, [rsi+rcx]
            c = sbAppend(c, hexByte(0x50))                                          // push rax
        } else if op == "BUILTIN_SOCKRECVSTR" {
            // sockRecvStr(fd): kr_alloc a 64KB+1 buffer, recvfrom into it, NUL-terminate
            // at nbytes, return the buffer as a string. TOS=fd. (57 bytes)
            // RBX=fd and R12=buf survive the kr_alloc CALL (kr_alloc touches only
            // RAX/R15/RDI). Mirrors macOS BUILTIN_SOCKRECVSTR.
            c = sbAppend(c, hexByte(0x5B))                  // pop rbx (fd)
            c = sbAppend(c, hexByte(0xBF) + hexDword(65537)) // mov edi, 0x10001 (size = 64K+1)
            let raDisp = krAllocVAddr - (funcStartVAddr + off + 11)
            c = sbAppend(c, hexByte(0xE8) + hexDword(raDisp)) // call kr_alloc -> rax=buf
            c = sbAppend(c, hexByte(0x49) + hexByte(0x89) + hexByte(0xC4)) // mov r12, rax (buf)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xDF)) // mov rdi, rbx (fd)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xC6)) // mov rsi, rax (buf)
            c = sbAppend(c, hexByte(0xBA) + hexDword(65536)) // mov edx, 0x10000 (len = 64K)
            c = sbAppend(c, hexByte(0x45) + hexByte(0x31) + hexByte(0xD2)) // xor r10d,r10d (flags)
            c = sbAppend(c, hexByte(0x45) + hexByte(0x31) + hexByte(0xC0)) // xor r8d,r8d  (from=NULL)
            c = sbAppend(c, hexByte(0x45) + hexByte(0x31) + hexByte(0xC9)) // xor r9d,r9d  (fromlen=NULL)
            c = sbAppend(c, hexByte(0xB8) + hexDword(45))   // mov eax, 45 (SYS_recvfrom)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))  // syscall -> rax = nbytes
            c = sbAppend(c, hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)) // test rax,rax
            c = sbAppend(c, hexByte(0x79) + hexByte(0x02))  // jns +2 (skip clamp if >=0)
            c = sbAppend(c, hexByte(0x31) + hexByte(0xC0))  // xor eax,eax (clamp negative -> 0)
            c = sbAppend(c, hexByte(0x41) + hexByte(0xC6) + hexByte(0x04) + hexByte(0x04) + hexByte(0x00)) // mov byte [r12+rax],0
            c = sbAppend(c, hexByte(0x4C) + hexByte(0x89) + hexByte(0xE0)) // mov rax, r12 (return buf)
            c = sbAppend(c, hexByte(0x50))                  // push rax
        } else if op == "BUILTIN_READPROC" {
            // readProc(path): open(path, O_RDONLY); kr_alloc 256KB; read-loop into
            // the buffer until EOF; close; NUL-terminate; return buffer. Reads /proc
            // and /sys virtual files (st_size==0) that kr_readfile's fstat path can't.
            // RBX=fd, R12=buf, R13=cursor, R8=remaining — all survive kr_alloc (touches
            // only RAX/R15/RDI) and `syscall` (clobbers only RCX/R11). (91 bytes)
            c = sbAppend(c, hexByte(0x5F))                                  // [0]  pop rdi (path)
            c = sbAppend(c, hexByte(0x31) + hexByte(0xF6))                  // [1]  xor esi,esi (O_RDONLY)
            c = sbAppend(c, hexByte(0x31) + hexByte(0xD2))                  // [3]  xor edx,edx (mode 0)
            c = sbAppend(c, hexByte(0xB8) + hexDword(2))                    // [5]  mov eax,2 (SYS_open)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))                  // [10] syscall -> rax=fd
            c = sbAppend(c, hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)) // [12] test rax,rax
            c = sbAppend(c, hexByte(0x78) + hexByte(0x47))                  // [15] js +0x47 -> .err(88)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xC3)) // [17] mov rbx,rax (fd)
            c = sbAppend(c, hexByte(0xBF) + hexDword(0x40000))             // [20] mov edi,0x40000 (alloc 256KB)
            let rpDisp = krAllocVAddr - (funcStartVAddr + off + 30)
            c = sbAppend(c, hexByte(0xE8) + hexDword(rpDisp))              // [25] call kr_alloc -> rax=buf
            c = sbAppend(c, hexByte(0x49) + hexByte(0x89) + hexByte(0xC4)) // [30] mov r12,rax (buf base)
            c = sbAppend(c, hexByte(0x49) + hexByte(0x89) + hexByte(0xC5)) // [33] mov r13,rax (cursor)
            c = sbAppend(c, hexByte(0x41) + hexByte(0xB8) + hexDword(0x3FFFF)) // [36] mov r8d,0x3FFFF (remaining; 1 byte spare for NUL)
            c = sbAppend(c, hexByte(0x31) + hexByte(0xC0))                 // [42] .loop: xor eax,eax (SYS_read)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xDF)) // [44] mov rdi,rbx (fd)
            c = sbAppend(c, hexByte(0x4C) + hexByte(0x89) + hexByte(0xEE)) // [47] mov rsi,r13 (cursor)
            c = sbAppend(c, hexByte(0x4C) + hexByte(0x89) + hexByte(0xC2)) // [50] mov rdx,r8 (remaining)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))                 // [53] syscall -> rax=nread
            c = sbAppend(c, hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)) // [55] test rax,rax
            c = sbAppend(c, hexByte(0x7E) + hexByte(0x08))                 // [58] jle +8 -> .done(68)
            c = sbAppend(c, hexByte(0x49) + hexByte(0x01) + hexByte(0xC5)) // [60] add r13,rax (cursor += nread)
            c = sbAppend(c, hexByte(0x49) + hexByte(0x29) + hexByte(0xC0)) // [63] sub r8,rax (remaining -= nread)
            c = sbAppend(c, hexByte(0x7F) + hexByte(0xE6))                 // [66] jg -26 -> .loop(42)
            c = sbAppend(c, hexByte(0x41) + hexByte(0xC6) + hexByte(0x45) + hexByte(0x00) + hexByte(0x00)) // [68] .done: mov byte [r13],0 (disp8=0, imm8=0; 5 bytes)
            c = sbAppend(c, hexByte(0xB8) + hexDword(3))                   // [72] mov eax,3 (SYS_close)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xDF)) // [77] mov rdi,rbx (fd)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))                 // [80] syscall
            c = sbAppend(c, hexByte(0x4C) + hexByte(0x89) + hexByte(0xE0)) // [82] mov rax,r12 (return buf)
            c = sbAppend(c, hexByte(0xEB) + hexByte(0x06))                 // [86] jmp +6 -> .end(94)
            c = sbAppend(c, hexByte(0x4C) + hexByte(0x89) + hexByte(0xF8)) // [88] .err: mov rax,r15 (zeroed heap byte = "")
            c = sbAppend(c, hexByte(0x49) + hexByte(0xFF) + hexByte(0xC7)) // [91] inc r15 (consume the NUL byte so the next kr_alloc can't alias/overwrite this empty string)
            c = sbAppend(c, hexByte(0x50))                                 // [94] .end: push rax
        } else if op == "BUILTIN_ENVIRON" {
            // environ(name) -> ptr to the value of env var `name`, or "" if unset.
            // envp (char**) was stashed at [R14+16] by _start. Walks entries, matches
            // the "NAME=" prefix, returns &value (into the env block, NUL-terminated).
            // Position-independent (no CALL); internal rel8 jumps only. (69 bytes)
            c = sbAppend(c, hexByte(0x5F))                                  // [0]  pop rdi (name)
            c = sbAppend(c, hexByte(0x49) + hexByte(0x8B) + hexByte(0x76) + hexByte(0x10)) // [1]  mov rsi,[r14+16] (envp)
            c = sbAppend(c, hexByte(0x4C) + hexByte(0x8B) + hexByte(0x06)) // [5]  .loop: mov r8,[rsi] (entry)
            c = sbAppend(c, hexByte(0x4D) + hexByte(0x85) + hexByte(0xC0)) // [8]  test r8,r8
            c = sbAppend(c, hexByte(0x74) + hexByte(0x31))                 // [11] jz +0x31 -> .notfound(62)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xF9)) // [13] mov rcx,rdi (name cursor)
            c = sbAppend(c, hexByte(0x4C) + hexByte(0x89) + hexByte(0xC2)) // [16] mov rdx,r8 (entry cursor)
            c = sbAppend(c, hexByte(0x8A) + hexByte(0x01))                 // [19] .cmp: mov al,[rcx]
            c = sbAppend(c, hexByte(0x84) + hexByte(0xC0))                 // [21] test al,al (name end?)
            c = sbAppend(c, hexByte(0x74) + hexByte(0x10))                 // [23] jz +0x10 -> .nameend(41)
            c = sbAppend(c, hexByte(0x44) + hexByte(0x8A) + hexByte(0x0A)) // [25] mov r9b,[rdx]
            c = sbAppend(c, hexByte(0x44) + hexByte(0x38) + hexByte(0xC8)) // [28] cmp al,r9b
            c = sbAppend(c, hexByte(0x75) + hexByte(0x17))                 // [31] jne +0x17 -> .next(56)
            c = sbAppend(c, hexByte(0x48) + hexByte(0xFF) + hexByte(0xC1)) // [33] inc rcx
            c = sbAppend(c, hexByte(0x48) + hexByte(0xFF) + hexByte(0xC2)) // [36] inc rdx
            c = sbAppend(c, hexByte(0xEB) + hexByte(0xEA))                 // [39] jmp -22 -> .cmp(19)
            c = sbAppend(c, hexByte(0x44) + hexByte(0x8A) + hexByte(0x0A)) // [41] .nameend: mov r9b,[rdx]
            c = sbAppend(c, hexByte(0x41) + hexByte(0x80) + hexByte(0xF9) + hexByte(0x3D)) // [44] cmp r9b,0x3D ('=')
            c = sbAppend(c, hexByte(0x75) + hexByte(0x06))                 // [48] jne +6 -> .next(56)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x8D) + hexByte(0x42) + hexByte(0x01)) // [50] lea rax,[rdx+1] (value ptr)
            c = sbAppend(c, hexByte(0xEB) + hexByte(0x0C))                 // [54] jmp +0x0C -> .done(68)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x83) + hexByte(0xC6) + hexByte(0x08)) // [56] .next: add rsi,8
            c = sbAppend(c, hexByte(0xEB) + hexByte(0xC7))                 // [60] jmp -57 -> .loop(5)
            c = sbAppend(c, hexByte(0x4C) + hexByte(0x89) + hexByte(0xF8)) // [62] .notfound: mov rax,r15 (zeroed heap = "")
            c = sbAppend(c, hexByte(0x49) + hexByte(0xFF) + hexByte(0xC7)) // [65] inc r15 (consume NUL so kr_concat can't alias)
            c = sbAppend(c, hexByte(0x50))                                 // [68] .done: push rax
        } else if op == "BUILTIN_SHELLRUN" {
            // shellRun(cmd): fork + execve("/bin/sh","-c",cmd) with INHERITED
            // stdio, wait4, return WEXITSTATUS as a decimal string (kr_str_int).
            // Mirrors macOS BUILTIN_SHELLRUN. CHILD block first so the only
            // forward jump is a short rel8 and the child path always ends in
            // execve/exit (never falls back into the VM → no fork-bomb). R14/R15
            // reserved; syscall clobbers only RCX/R11. cmd ptr is TOS. (142 bytes)
            // --- arg setup: build "/bin/sh\0","-c\0" + argv[] on a 64B frame ---
            c = sbAppend(c, hexByte(0x5B))                                 // [0]  pop rbx (cmd)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x83) + hexByte(0xEC) + hexByte(0x40)) // [1]  sub rsp,64
            c = sbAppend(c, hexByte(0xC7) + hexByte(0x04) + hexByte(0x24) + hexDword(0x6e69622f)) // [5]  mov dword [rsp],"/bin"
            c = sbAppend(c, hexByte(0xC7) + hexByte(0x44) + hexByte(0x24) + hexByte(0x04) + hexDword(0x0068732f)) // [12] mov dword [rsp+4],"/sh\0"
            c = sbAppend(c, hexByte(0xC7) + hexByte(0x44) + hexByte(0x24) + hexByte(0x08) + hexDword(0x0000632d)) // [20] mov dword [rsp+8],"-c\0\0"
            c = sbAppend(c, hexByte(0x48) + hexByte(0x8D) + hexByte(0x04) + hexByte(0x24)) // [28] lea rax,[rsp]
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0x44) + hexByte(0x24) + hexByte(0x10)) // [32] mov [rsp+16],rax (argv0=&"/bin/sh")
            c = sbAppend(c, hexByte(0x48) + hexByte(0x8D) + hexByte(0x44) + hexByte(0x24) + hexByte(0x08)) // [37] lea rax,[rsp+8]
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0x44) + hexByte(0x24) + hexByte(0x18)) // [42] mov [rsp+24],rax (argv1=&"-c")
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0x5C) + hexByte(0x24) + hexByte(0x20)) // [47] mov [rsp+32],rbx (argv2=cmd)
            c = sbAppend(c, hexByte(0x31) + hexByte(0xC0))                 // [52] xor eax,eax
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0x44) + hexByte(0x24) + hexByte(0x28)) // [54] mov [rsp+40],rax (argv3=NULL)
            // --- fork ---
            c = sbAppend(c, hexByte(0xB8) + hexDword(57))                  // [59] mov eax,57 (fork)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))                 // [64] syscall
            c = sbAppend(c, hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)) // [66] test rax,rax
            c = sbAppend(c, hexByte(0x75) + hexByte(0x20))                 // [69] jnz +0x20 -> .parent(103)
            // --- CHILD (71): execve("/bin/sh", argv@rsp+16, envp); exit(127) ---
            c = sbAppend(c, hexByte(0x48) + hexByte(0x8D) + hexByte(0x3C) + hexByte(0x24)) // [71] lea rdi,[rsp] (path)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x8D) + hexByte(0x74) + hexByte(0x24) + hexByte(0x10)) // [75] lea rsi,[rsp+16] (argv)
            c = sbAppend(c, hexByte(0x49) + hexByte(0x8B) + hexByte(0x56) + hexByte(0x10)) // [80] mov rdx,[r14+16] (envp)
            c = sbAppend(c, hexByte(0xB8) + hexDword(59))                  // [84] mov eax,59 (execve)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))                 // [89] syscall
            c = sbAppend(c, hexByte(0xBF) + hexDword(127))                 // [91] mov edi,127
            c = sbAppend(c, hexByte(0xB8) + hexDword(60))                  // [96] mov eax,60 (exit)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))                 // [101] syscall
            // --- PARENT (103): wait4(pid,&status,0,0); push itoa(WEXITSTATUS) ---
            c = sbAppend(c, hexByte(0x89) + hexByte(0xC7))                 // [103] mov edi,eax (child pid)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x8D) + hexByte(0x74) + hexByte(0x24) + hexByte(0x30)) // [105] lea rsi,[rsp+48] (&status)
            c = sbAppend(c, hexByte(0x31) + hexByte(0xD2))                 // [110] xor edx,edx (options=0)
            c = sbAppend(c, hexByte(0x45) + hexByte(0x31) + hexByte(0xD2)) // [112] xor r10d,r10d (rusage=NULL)
            c = sbAppend(c, hexByte(0xB8) + hexDword(61))                  // [115] mov eax,61 (wait4)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))                 // [120] syscall
            c = sbAppend(c, hexByte(0x8B) + hexByte(0x44) + hexByte(0x24) + hexByte(0x30)) // [122] mov eax,[rsp+48] (status)
            c = sbAppend(c, hexByte(0xC1) + hexByte(0xE8) + hexByte(0x08)) // [126] shr eax,8
            c = sbAppend(c, hexByte(0x0F) + hexByte(0xB6) + hexByte(0xF8)) // [129] movzx edi,al (WEXITSTATUS)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x83) + hexByte(0xC4) + hexByte(0x40)) // [132] add rsp,64
            let srDisp = krStrIntVAddr - (funcStartVAddr + off + 141)
            c = sbAppend(c, hexByte(0xE8) + hexDword(srDisp))             // [136] call kr_str_int -> rax=string
            c = sbAppend(c, hexByte(0x50))                                 // [141] push rax
        } else if op == "BUILTIN_EXEC" {
            // exec(cmd): run "/bin/sh -c cmd", capture child stdout, return it as a
            // NUL-terminated string (NO trailing-whitespace strip — matches macOS
            // BUILTIN_EXEC, so exec("echo hi")=="hi\n"). pipe2+fork+dup2+execve in
            // the child; parent closes the write end, read-loops into a 64KB+1
            // kr_alloc buffer (mirrors readProc), wait4's the child (no zombies).
            // CHILD block first (jnz over it) so the child path always ends in
            // execve/exit — never falls back into the VM (no fork-bomb). RBX=buf,
            // R12=read_fd, R13=cursor, R8=remaining survive kr_alloc (touches only
            // RAX/R15/RDI) and syscall (clobbers only RCX/R11). cmd=TOS. (265 bytes)
            // --- arg setup: "/bin/sh\0","-c\0" + argv[] on a 64B frame ---
            c = sbAppend(c, hexByte(0x5B))                                 // [0]  pop rbx (cmd)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x83) + hexByte(0xEC) + hexByte(0x40)) // [1]  sub rsp,64
            c = sbAppend(c, hexByte(0xC7) + hexByte(0x04) + hexByte(0x24) + hexDword(0x6e69622f)) // [5]  mov dword [rsp],"/bin"
            c = sbAppend(c, hexByte(0xC7) + hexByte(0x44) + hexByte(0x24) + hexByte(0x04) + hexDword(0x0068732f)) // [12] mov dword [rsp+4],"/sh\0"
            c = sbAppend(c, hexByte(0xC7) + hexByte(0x44) + hexByte(0x24) + hexByte(0x08) + hexDword(0x0000632d)) // [20] mov dword [rsp+8],"-c\0\0"
            c = sbAppend(c, hexByte(0x48) + hexByte(0x8D) + hexByte(0x04) + hexByte(0x24)) // [28] lea rax,[rsp]
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0x44) + hexByte(0x24) + hexByte(0x10)) // [32] mov [rsp+16],rax (argv0)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x8D) + hexByte(0x44) + hexByte(0x24) + hexByte(0x08)) // [37] lea rax,[rsp+8]
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0x44) + hexByte(0x24) + hexByte(0x18)) // [42] mov [rsp+24],rax (argv1)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0x5C) + hexByte(0x24) + hexByte(0x20)) // [47] mov [rsp+32],rbx (argv2=cmd)
            c = sbAppend(c, hexByte(0x31) + hexByte(0xC0))                 // [52] xor eax,eax
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0x44) + hexByte(0x24) + hexByte(0x28)) // [54] mov [rsp+40],rax (argv3=NULL)
            // --- pipe2(&pipefd@[rsp+48], 0) ---
            c = sbAppend(c, hexByte(0x48) + hexByte(0x8D) + hexByte(0x7C) + hexByte(0x24) + hexByte(0x30)) // [59] lea rdi,[rsp+48]
            c = sbAppend(c, hexByte(0x31) + hexByte(0xF6))                 // [64] xor esi,esi (flags=0)
            c = sbAppend(c, hexByte(0xB8) + hexDword(293))                 // [66] mov eax,293 (pipe2)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))                 // [71] syscall
            // --- fork ---
            c = sbAppend(c, hexByte(0xB8) + hexDword(57))                  // [73] mov eax,57 (fork)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))                 // [78] syscall
            c = sbAppend(c, hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)) // [80] test rax,rax
            c = sbAppend(c, hexByte(0x75) + hexByte(0x46))                 // [83] jnz +0x46 -> .parent(155)
            // --- CHILD (85): dup2(write,1); close pipe ends; execve; exit(127) ---
            c = sbAppend(c, hexByte(0x8B) + hexByte(0x7C) + hexByte(0x24) + hexByte(0x34)) // [85] mov edi,[rsp+52] (write_fd)
            c = sbAppend(c, hexByte(0xBE) + hexDword(1))                   // [89] mov esi,1 (stdout)
            c = sbAppend(c, hexByte(0xB8) + hexDword(33))                  // [94] mov eax,33 (dup2)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))                 // [99] syscall
            c = sbAppend(c, hexByte(0x8B) + hexByte(0x7C) + hexByte(0x24) + hexByte(0x30)) // [101] mov edi,[rsp+48] (read_fd)
            c = sbAppend(c, hexByte(0xB8) + hexDword(3))                   // [105] mov eax,3 (close)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))                 // [110] syscall
            c = sbAppend(c, hexByte(0x8B) + hexByte(0x7C) + hexByte(0x24) + hexByte(0x34)) // [112] mov edi,[rsp+52] (write_fd)
            c = sbAppend(c, hexByte(0xB8) + hexDword(3))                   // [116] mov eax,3 (close)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))                 // [121] syscall
            c = sbAppend(c, hexByte(0x48) + hexByte(0x8D) + hexByte(0x3C) + hexByte(0x24)) // [123] lea rdi,[rsp] (path)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x8D) + hexByte(0x74) + hexByte(0x24) + hexByte(0x10)) // [127] lea rsi,[rsp+16] (argv)
            c = sbAppend(c, hexByte(0x49) + hexByte(0x8B) + hexByte(0x56) + hexByte(0x10)) // [132] mov rdx,[r14+16] (envp)
            c = sbAppend(c, hexByte(0xB8) + hexDword(59))                  // [136] mov eax,59 (execve)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))                 // [141] syscall
            c = sbAppend(c, hexByte(0xBF) + hexDword(127))                 // [143] mov edi,127
            c = sbAppend(c, hexByte(0xB8) + hexDword(60))                  // [148] mov eax,60 (exit)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))                 // [153] syscall
            // --- PARENT (155): close write; alloc; read-loop; close read; wait4 ---
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0x44) + hexByte(0x24) + hexByte(0x38)) // [155] mov [rsp+56],rax (child pid)
            c = sbAppend(c, hexByte(0x8B) + hexByte(0x7C) + hexByte(0x24) + hexByte(0x34)) // [160] mov edi,[rsp+52] (write_fd)
            c = sbAppend(c, hexByte(0xB8) + hexDword(3))                   // [164] mov eax,3 (close)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))                 // [169] syscall
            c = sbAppend(c, hexByte(0x44) + hexByte(0x8B) + hexByte(0x64) + hexByte(0x24) + hexByte(0x30)) // [171] mov r12d,[rsp+48] (read_fd)
            c = sbAppend(c, hexByte(0xBF) + hexDword(65537))              // [176] mov edi,0x10001 (64K+1)
            let exDisp = krAllocVAddr - (funcStartVAddr + off + 186)
            c = sbAppend(c, hexByte(0xE8) + hexDword(exDisp))             // [181] call kr_alloc -> rax=buf
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xC3)) // [186] mov rbx,rax (buf base)
            c = sbAppend(c, hexByte(0x49) + hexByte(0x89) + hexByte(0xC5)) // [189] mov r13,rax (cursor)
            c = sbAppend(c, hexByte(0x41) + hexByte(0xB8) + hexDword(65536)) // [192] mov r8d,0x10000 (remaining)
            c = sbAppend(c, hexByte(0x31) + hexByte(0xC0))                 // [198] .loop: xor eax,eax (read=0)
            c = sbAppend(c, hexByte(0x44) + hexByte(0x89) + hexByte(0xE7)) // [200] mov edi,r12d (fd)
            c = sbAppend(c, hexByte(0x4C) + hexByte(0x89) + hexByte(0xEE)) // [203] mov rsi,r13 (cursor)
            c = sbAppend(c, hexByte(0x4C) + hexByte(0x89) + hexByte(0xC2)) // [206] mov rdx,r8 (remaining)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))                 // [209] syscall -> rax=nread
            c = sbAppend(c, hexByte(0x48) + hexByte(0x85) + hexByte(0xC0)) // [211] test rax,rax
            c = sbAppend(c, hexByte(0x7E) + hexByte(0x08))                 // [214] jle +8 -> .done(224)
            c = sbAppend(c, hexByte(0x49) + hexByte(0x01) + hexByte(0xC5)) // [216] add r13,rax (cursor+=n)
            c = sbAppend(c, hexByte(0x49) + hexByte(0x29) + hexByte(0xC0)) // [219] sub r8,rax (remaining-=n)
            c = sbAppend(c, hexByte(0x7F) + hexByte(0xE6))                 // [222] jg -26 -> .loop(198)
            c = sbAppend(c, hexByte(0x41) + hexByte(0xC6) + hexByte(0x45) + hexByte(0x00) + hexByte(0x00)) // [224] .done: mov byte [r13],0
            c = sbAppend(c, hexByte(0x44) + hexByte(0x89) + hexByte(0xE7)) // [229] mov edi,r12d (read_fd)
            c = sbAppend(c, hexByte(0xB8) + hexDword(3))                   // [232] mov eax,3 (close)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))                 // [237] syscall
            c = sbAppend(c, hexByte(0x8B) + hexByte(0x7C) + hexByte(0x24) + hexByte(0x38)) // [239] mov edi,[rsp+56] (child pid)
            c = sbAppend(c, hexByte(0x31) + hexByte(0xF6))                 // [243] xor esi,esi (status=NULL)
            c = sbAppend(c, hexByte(0x31) + hexByte(0xD2))                 // [245] xor edx,edx (options=0)
            c = sbAppend(c, hexByte(0x45) + hexByte(0x31) + hexByte(0xD2)) // [247] xor r10d,r10d (rusage=NULL)
            c = sbAppend(c, hexByte(0xB8) + hexDword(61))                  // [250] mov eax,61 (wait4)
            c = sbAppend(c, hexByte(0x0F) + hexByte(0x05))                 // [255] syscall
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xD8)) // [257] mov rax,rbx (return buf)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x83) + hexByte(0xC4) + hexByte(0x40)) // [260] add rsp,64
            c = sbAppend(c, hexByte(0x50))                                 // [264] push rax
        } else if op == "BUILTIN_WRITEFILE" {
            // POP RSI (content, top) ; POP RDI (path) ; CALL kr_writefile ; PUSH RAX
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            let wfDisp = krWritefileVAddr - (funcStartVAddr + off + 7)
            c = sbAppend(c, hexByte(0xE8) + hexDword(wfDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_WRITEBYTES" {
            // POP RSI (content) ; POP RDI (path) ; CALL kr_writebytes ; PUSH RAX
            // kr_writebytes is laid out immediately after kr_writefile (66 bytes),
            // so its vaddr is krWritefileVAddr + 66 (see the segment assembly).
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            let wbDisp = (krWritefileVAddr + 66) - (funcStartVAddr + off + 7)
            c = sbAppend(c, hexByte(0xE8) + hexDword(wbDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_PRINTERR" {
            // POP RDI ; CALL kr_printerr ; PUSH 0  (8 bytes)
            c = sbAppend(c, hexByte(0x5F))
            let peDisp = krPrinterrVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(peDisp))
            c = sbAppend(c, hexByte(0x6A) + hexByte(0x00))
        } else if op == "BUILTIN_CHARCODE" {
            // POP RDI ; CALL kr_charcode ; PUSH RAX  (7 bytes)
            c = sbAppend(c, hexByte(0x5F))
            let ccDisp = krCharcodeVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(ccDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_FROMCHARCODE" {
            // POP RDI ; CALL kr_fromcharcode ; PUSH RAX  (7 bytes)
            c = sbAppend(c, hexByte(0x5F))
            let fcDisp = krFromcharcodeVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(fcDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_EXIT" {
            // POP RDI ; CALL kr_exit ; PUSH RAX (kr_exit doesn't return)  (7 bytes)
            c = sbAppend(c, hexByte(0x5F))
            let exDisp = krExitVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(exDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_ISDIGIT" {
            c = sbAppend(c, hexByte(0x5F))
            let idDisp = krIsdigitVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(idDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_ISALPHA" {
            c = sbAppend(c, hexByte(0x5F))
            let iaDisp = krIsalphaVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(iaDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_ABS" {
            c = sbAppend(c, hexByte(0x5F))
            let abDisp = krAbsVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(abDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_STARTSWITH" {
            // POP RSI (prefix, top) ; POP RDI (s) ; CALL ; PUSH RAX
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            let swDisp = krStartswithVAddr - (funcStartVAddr + off + 7)
            c = sbAppend(c, hexByte(0xE8) + hexDword(swDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_ISTRUTHY" {
            // POP RDI ; CALL kr_istruthy ; PUSH RAX
            c = sbAppend(c, hexByte(0x5F))
            let itDisp = krIstruthyVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(itDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_LINECOUNT" {
            // POP RDI ; CALL kr_linecount ; PUSH RAX (7 bytes)
            c = sbAppend(c, hexByte(0x5F))
            let lcDisp = krLinecountVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(lcDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_GETLINE" {
            // POP RSI (idx, top) ; POP RDI (str) ; CALL kr_getline ; PUSH RAX
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            let glDisp = krGetlineVAddr - (funcStartVAddr + off + 7)
            c = sbAppend(c, hexByte(0xE8) + hexDword(glDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_TRIM" {
            // POP RDI ; CALL kr_trim ; PUSH RAX (7 bytes)
            c = sbAppend(c, hexByte(0x5F))
            let trDisp = krTrimVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(trDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_TOUPPER" {
            // POP RDI ; CALL kr_toupper ; PUSH RAX (7 bytes)
            c = sbAppend(c, hexByte(0x5F))
            let tuDisp = krToupperVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(tuDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_TOLOWER" {
            // POP RDI ; CALL kr_tolower ; PUSH RAX (7 bytes)
            c = sbAppend(c, hexByte(0x5F))
            let tlDisp = krTolowerVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(tlDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_REVERSE" {
            // POP RDI ; CALL kr_reverse ; PUSH RAX (7 bytes)
            c = sbAppend(c, hexByte(0x5F))
            let rvDisp = krReverseVAddr - (funcStartVAddr + off + 6)
            c = sbAppend(c, hexByte(0xE8) + hexDword(rvDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_POW" {
            // POP RSI (exp) ; POP RDI (base) ; CALL kr_pow ; PUSH RAX (8 bytes)
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            let pwDisp = krPowVAddr - (funcStartVAddr + off + 7)
            c = sbAppend(c, hexByte(0xE8) + hexDword(pwDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_MIN" {
            // POP RSI (b) ; POP RDI (a) ; CALL kr_min ; PUSH RAX (8 bytes)
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            let mnDisp = krMinVAddr - (funcStartVAddr + off + 7)
            c = sbAppend(c, hexByte(0xE8) + hexDword(mnDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_MAX" {
            // POP RSI (b) ; POP RDI (a) ; CALL kr_max ; PUSH RAX (8 bytes)
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            let mxDisp = krMaxVAddr - (funcStartVAddr + off + 7)
            c = sbAppend(c, hexByte(0xE8) + hexDword(mxDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_BITAND" {
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            c = sbAppend(c, hexByte(0xE8) + hexDword(krBitandVAddr - (funcStartVAddr + off + 7)))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_BITOR" {
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            c = sbAppend(c, hexByte(0xE8) + hexDword(krBitorVAddr - (funcStartVAddr + off + 7)))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_BITXOR" {
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            c = sbAppend(c, hexByte(0xE8) + hexDword(krBitxorVAddr - (funcStartVAddr + off + 7)))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_SHL" {
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            c = sbAppend(c, hexByte(0xE8) + hexDword(krShlVAddr - (funcStartVAddr + off + 7)))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_SHR" {
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            c = sbAppend(c, hexByte(0xE8) + hexDword(krShrVAddr - (funcStartVAddr + off + 7)))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_BITNOT" {
            c = sbAppend(c, hexByte(0x5F))
            c = sbAppend(c, hexByte(0xE8) + hexDword(krBitnotVAddr - (funcStartVAddr + off + 6)))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_HX" {
            // POP RDI ; CALL kr_hex ; PUSH RAX (7 bytes)
            c = sbAppend(c, hexByte(0x5F))
            c = sbAppend(c, hexByte(0xE8) + hexDword(krHexVAddr - (funcStartVAddr + off + 6)))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_BN" {
            // POP RDI ; CALL kr_bin ; PUSH RAX (7 bytes)
            c = sbAppend(c, hexByte(0x5F))
            c = sbAppend(c, hexByte(0xE8) + hexDword(krBinVAddr - (funcStartVAddr + off + 6)))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_REPEAT" {
            // POP RSI (n) ; POP RDI (s) ; CALL kr_repeat ; PUSH RAX (8 bytes)
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            let rpDisp = krRepeatVAddr - (funcStartVAddr + off + 7)
            c = sbAppend(c, hexByte(0xE8) + hexDword(rpDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_CONTAINS" {
            // POP RSI (needle) ; POP RDI (s) ; CALL kr_contains ; PUSH RAX
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            let cnDisp = krContainsVAddr - (funcStartVAddr + off + 7)
            c = sbAppend(c, hexByte(0xE8) + hexDword(cnDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_INDEXOF" {
            // POP RSI (needle) ; POP RDI (s) ; CALL kr_indexof ; PUSH RAX
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            let ioDisp = krIndexofVAddr - (funcStartVAddr + off + 7)
            c = sbAppend(c, hexByte(0xE8) + hexDword(ioDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_ENDSWITH" {
            // POP RSI (suffix) ; POP RDI (s) ; CALL kr_endswith ; PUSH RAX
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            let ewDisp = krEndswithVAddr - (funcStartVAddr + off + 7)
            c = sbAppend(c, hexByte(0xE8) + hexDword(ewDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_REPLACE" {
            // POP RDX (rep, top) ; POP RSI (find) ; POP RDI (s) ;
            // CALL kr_replace ; PUSH RAX. (9 bytes)
            c = sbAppend(c, hexByte(0x5A))  // POP RDX
            c = sbAppend(c, hexByte(0x5E))  // POP RSI
            c = sbAppend(c, hexByte(0x5F))  // POP RDI
            let rpDisp = krReplaceVAddr - (funcStartVAddr + off + 8)
            c = sbAppend(c, hexByte(0xE8) + hexDword(rpDisp))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_ENVNEW" {
            // envNew() — push 0 (NULL env sentinel). 2 bytes.
            c = sbAppend(c, hexByte(0x6A) + hexByte(0x00))
        } else if op == "BUILTIN_ENVSET" {
            // envSet(env, name, val) — allocate 24-byte EnvEntry,
            // store {name, value, prev=env}, push entry ptr.
            //
            // Stack on entry (top first): val, name, env.
            //
            // Layout (31 bytes):
            //   [0]    5A             POP RDX            ; val (top)
            //   [1]    5E             POP RSI            ; name
            //   [2]    5F             POP RDI            ; env (will be prev)
            //   [3]    57             PUSH RDI           ; save env
            //   [4]    56             PUSH RSI           ; save name
            //   [5]    52             PUSH RDX           ; save val
            //   [6-10] BF 18 00 00 00 MOV EDI, 24
            //   [11-15] E8 dw_alloc   CALL kr_alloc      ; RAX = entry
            //   [16]   5A             POP RDX            ; val
            //   [17]   5E             POP RSI            ; name
            //   [18]   5F             POP RDI            ; env (prev)
            //   [19-22] 48 89 30      MOV [RAX], RSI     ; entry.name = name
            //                          (3 bytes)
            //   [22-25] 48 89 50 08   MOV [RAX+8], RDX   ; entry.value = val (4)
            //   [26-29] 48 89 78 10   MOV [RAX+16], RDI  ; entry.prev = env (4)
            //   [30]   50             PUSH RAX           ; result
            let alDisp1 = krAllocVAddr - (funcStartVAddr + off + 16)
            c = sbAppend(c, hexByte(0x5A))
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            c = sbAppend(c, hexByte(0x57))
            c = sbAppend(c, hexByte(0x56))
            c = sbAppend(c, hexByte(0x52))
            c = sbAppend(c, hexByte(0xBF) + hexDword(24))
            c = sbAppend(c, hexByte(0xE8) + hexDword(alDisp1))
            c = sbAppend(c, hexByte(0x5A))
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0x30))  // MOV [RAX], RSI
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0x50) + hexByte(0x08))  // MOV [RAX+8], RDX
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0x78) + hexByte(0x10))  // MOV [RAX+16], RDI
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_ENVGET" {
            // envGet(env, name) — walk EnvEntry linked list, strcmp names,
            // return entry.value if match. If not found, return ptr to a
            // freshly-alloc'd 1-byte buffer (which is zero from mmap, so
            // acts as empty NUL-terminated string).
            //
            // Stack on entry (top first): name, env.
            // R12 holds current entry (callee-saved across CALLs); RBX holds name.
            //
            // Layout (61 bytes):
            //   [0]    5E              POP RSI                  ; name (top)
            //   [1]    5F              POP RDI                  ; env (start entry)
            //   [2]    53              PUSH RBX
            //   [3-4]  41 54           PUSH R12
            //   [5-7]  48 89 F3        MOV RBX, RSI             ; save name
            //   [8-10] 49 89 FC        MOV R12, RDI             ; cur entry
            //   .loop at 11:
            //   [11-13] 4D 85 E4       TEST R12, R12
            //   [14-15] 74 1F          JZ +31 → .notfound at 47
            //   [16-19] 49 8B 3C 24    MOV RDI, [R12]           ; entry.name
            //   [20-22] 48 89 DE       MOV RSI, RBX             ; name
            //   [23-27] E8 dw_strcmp   CALL kr_strcmp
            //   [28-30] 48 85 C0       TEST RAX, RAX
            //   [31-32] 75 07          JNE +7 → .next at 40
            //   ; matched
            //   [33-37] 49 8B 44 24 08 MOV RAX, [R12+8]         ; entry.value
            //   [38-39] EB 11          JMP +17 → .ret at 57
            //   .next at 40:
            //   [40-44] 4D 8B 64 24 10 MOV R12, [R12+16]        ; entry.prev
            //   [45-46] EB CC          JMP -52 → .loop at 11
            //   .notfound at 47:
            //   [47-51] BF 01 00 00 00 MOV EDI, 1
            //   [52-56] E8 dw_alloc    CALL kr_alloc            ; RAX = ptr to NUL byte
            //   .ret at 57:
            //   [57-58] 41 5C          POP R12
            //   [59]    5B             POP RBX
            //   [60]    50             PUSH RAX
            let scDisp = krStrcmpVAddr - (funcStartVAddr + off + 28)
            let alDisp2 = krAllocVAddr - (funcStartVAddr + off + 57)
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            c = sbAppend(c, hexByte(0x53))
            c = sbAppend(c, hexByte(0x41) + hexByte(0x54))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xF3))
            c = sbAppend(c, hexByte(0x49) + hexByte(0x89) + hexByte(0xFC))
            c = sbAppend(c, hexByte(0x4D) + hexByte(0x85) + hexByte(0xE4))
            c = sbAppend(c, hexByte(0x74) + hexByte(0x1F))
            c = sbAppend(c, hexByte(0x49) + hexByte(0x8B) + hexByte(0x3C) + hexByte(0x24))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xDE))
            c = sbAppend(c, hexByte(0xE8) + hexDword(scDisp))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x85) + hexByte(0xC0))
            c = sbAppend(c, hexByte(0x75) + hexByte(0x07))
            c = sbAppend(c, hexByte(0x49) + hexByte(0x8B) + hexByte(0x44) + hexByte(0x24) + hexByte(0x08))
            c = sbAppend(c, hexByte(0xEB) + hexByte(0x11))
            c = sbAppend(c, hexByte(0x4D) + hexByte(0x8B) + hexByte(0x64) + hexByte(0x24) + hexByte(0x10))
            c = sbAppend(c, hexByte(0xEB) + hexByte(256 - 36))  // JMP -36 → .loop at 11
            c = sbAppend(c, hexByte(0xBF) + hexDword(1))
            c = sbAppend(c, hexByte(0xE8) + hexDword(alDisp2))
            c = sbAppend(c, hexByte(0x41) + hexByte(0x5C))
            c = sbAppend(c, hexByte(0x5B))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "SETFIELD_STR" {
            // setField(env, val) with name immediate from strTab[idx].
            // Stack on entry (top first): val, env.
            //
            // Layout (40 bytes):
            //   [0]    5A             POP RDX           ; val
            //   [1]    5F             POP RDI           ; env (will become prev)
            //   [2]    57             PUSH RDI          ; save env
            //   [3]    52             PUSH RDX          ; save val
            //   [4-13] 48 BE imm64    MOV RSI, name_va  (10)
            //   [14]   56             PUSH RSI          ; save name
            //   [15-19] BF 18 00 00 00 MOV EDI, 24
            //   [20-24] E8 dw_alloc   CALL kr_alloc     ; RAX = entry
            //   [25]   5E             POP RSI           ; name
            //   [26]   5A             POP RDX           ; val
            //   [27]   5F             POP RDI           ; env (prev)
            //   [28-30] 48 89 30      MOV [RAX], RSI    ; entry.name = name (3)
            //   [31-34] 48 89 50 08   MOV [RAX+8], RDX  ; entry.value = val (4)
            //   [35-38] 48 89 78 10   MOV [RAX+16], RDI ; entry.prev = env (4)
            //   [39]   50             PUSH RAX
            let idx = toInt(rest)
            let nameVAddr = toInt(getLine(strVAddrs, idx))
            let alDispS = krAllocVAddr - (funcStartVAddr + off + 25)
            c = sbAppend(c, hexByte(0x5A))
            c = sbAppend(c, hexByte(0x5F))
            c = sbAppend(c, hexByte(0x57))
            c = sbAppend(c, hexByte(0x52))
            c = sbAppend(c, hexByte(0x48) + hexByte(0xBE) + hexQwordVaddr(nameVAddr))
            c = sbAppend(c, hexByte(0x56))
            c = sbAppend(c, hexByte(0xBF) + hexDword(24))
            c = sbAppend(c, hexByte(0xE8) + hexDword(alDispS))
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5A))
            c = sbAppend(c, hexByte(0x5F))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0x30))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0x50) + hexByte(0x08))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0x78) + hexByte(0x10))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "GETFIELD_STR" {
            // getField(env) with name immediate from strTab[idx].
            // Stack on entry: env (top).
            //
            // Layout (70 bytes):
            //   [0-9]  48 BE imm64     MOV RSI, name_va         (10)
            //   [10]   5F              POP RDI                  ; env
            //   [11]   53              PUSH RBX
            //   [12-13] 41 54          PUSH R12
            //   [14-16] 48 89 F3       MOV RBX, RSI             ; save name
            //   [17-19] 49 89 FC       MOV R12, RDI             ; cur entry
            //   .loop at 20:
            //   [20-22] 4D 85 E4       TEST R12, R12
            //   [23-24] 74 1F          JZ +31 → .notfound at 56
            //   [25-28] 49 8B 3C 24    MOV RDI, [R12]           ; entry.name
            //   [29-31] 48 89 DE       MOV RSI, RBX
            //   [32-36] E8 dw_strcmp   CALL kr_strcmp
            //   [37-39] 48 85 C0       TEST RAX, RAX
            //   [40-41] 75 07          JNE +7 → .next at 49
            //   [42-46] 49 8B 44 24 08 MOV RAX, [R12+8]
            //   [47-48] EB 11          JMP +17 → .ret at 66
            //   .next at 49:
            //   [49-53] 4D 8B 64 24 10 MOV R12, [R12+16]
            //   [54-55] EB DC          JMP -36 → .loop at 20
            //   .notfound at 56:
            //   [56-60] BF 01 00 00 00 MOV EDI, 1
            //   [61-65] E8 dw_alloc    CALL kr_alloc
            //   .ret at 66:
            //   [66-67] 41 5C          POP R12
            //   [68]   5B              POP RBX
            //   [69]   50              PUSH RAX
            let idxG = toInt(rest)
            let nameVA_G = toInt(getLine(strVAddrs, idxG))
            let scDispG = krStrcmpVAddr - (funcStartVAddr + off + 37)
            let alDispG = krAllocVAddr - (funcStartVAddr + off + 66)
            c = sbAppend(c, hexByte(0x48) + hexByte(0xBE) + hexQwordVaddr(nameVA_G))
            c = sbAppend(c, hexByte(0x5F))
            c = sbAppend(c, hexByte(0x53))
            c = sbAppend(c, hexByte(0x41) + hexByte(0x54))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xF3))
            c = sbAppend(c, hexByte(0x49) + hexByte(0x89) + hexByte(0xFC))
            c = sbAppend(c, hexByte(0x4D) + hexByte(0x85) + hexByte(0xE4))
            c = sbAppend(c, hexByte(0x74) + hexByte(0x1F))
            c = sbAppend(c, hexByte(0x49) + hexByte(0x8B) + hexByte(0x3C) + hexByte(0x24))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xDE))
            c = sbAppend(c, hexByte(0xE8) + hexDword(scDispG))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x85) + hexByte(0xC0))
            c = sbAppend(c, hexByte(0x75) + hexByte(0x07))
            c = sbAppend(c, hexByte(0x49) + hexByte(0x8B) + hexByte(0x44) + hexByte(0x24) + hexByte(0x08))
            c = sbAppend(c, hexByte(0xEB) + hexByte(0x11))
            c = sbAppend(c, hexByte(0x4D) + hexByte(0x8B) + hexByte(0x64) + hexByte(0x24) + hexByte(0x10))
            c = sbAppend(c, hexByte(0xEB) + hexByte(256 - 36))
            c = sbAppend(c, hexByte(0xBF) + hexDword(1))
            c = sbAppend(c, hexByte(0xE8) + hexDword(alDispG))
            c = sbAppend(c, hexByte(0x41) + hexByte(0x5C))
            c = sbAppend(c, hexByte(0x5B))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_HASFIELD" {
            // hasField(env, name) — return 1 if name in env, else 0.
            // Stack on entry: name (top), env.
            //
            // Layout (54 bytes):
            //   [0]    5E              POP RSI                  ; name
            //   [1]    5F              POP RDI                  ; env
            //   [2]    53              PUSH RBX
            //   [3-4]  41 54           PUSH R12
            //   [5-7]  48 89 F3        MOV RBX, RSI
            //   [8-10] 49 89 FC        MOV R12, RDI
            //   .loop at 11:
            //   [11-13] 4D 85 E4       TEST R12, R12
            //   [14-15] 74 1F          JZ +31 → .notfound at 47
            //   [16-19] 49 8B 3C 24    MOV RDI, [R12]
            //   [20-22] 48 89 DE       MOV RSI, RBX
            //   [23-27] E8 dw_strcmp   CALL kr_strcmp
            //   [28-30] 48 85 C0       TEST RAX, RAX
            //   [31-32] 75 07          JNE +7 → .next at 40
            //   [33-37] B8 01 00 00 00 MOV EAX, 1
            //   [38-39] EB 0A          JMP +10 → .ret at 50
            //   .next at 40:
            //   [40-44] 4D 8B 64 24 10 MOV R12, [R12+16]
            //   [45-46] EB DC          JMP -36 → .loop at 11
            //   .notfound at 47:
            //   [47-49] 48 31 C0       XOR RAX, RAX
            //   .ret at 50:
            //   [50-51] 41 5C          POP R12
            //   [52]   5B              POP RBX
            //   [53]   50              PUSH RAX
            let scDispH = krStrcmpVAddr - (funcStartVAddr + off + 28)
            c = sbAppend(c, hexByte(0x5E))
            c = sbAppend(c, hexByte(0x5F))
            c = sbAppend(c, hexByte(0x53))
            c = sbAppend(c, hexByte(0x41) + hexByte(0x54))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xF3))
            c = sbAppend(c, hexByte(0x49) + hexByte(0x89) + hexByte(0xFC))
            c = sbAppend(c, hexByte(0x4D) + hexByte(0x85) + hexByte(0xE4))
            c = sbAppend(c, hexByte(0x74) + hexByte(0x1F))
            c = sbAppend(c, hexByte(0x49) + hexByte(0x8B) + hexByte(0x3C) + hexByte(0x24))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xDE))
            c = sbAppend(c, hexByte(0xE8) + hexDword(scDispH))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x85) + hexByte(0xC0))
            c = sbAppend(c, hexByte(0x75) + hexByte(0x07))
            c = sbAppend(c, hexByte(0xB8) + hexDword(1))
            c = sbAppend(c, hexByte(0xEB) + hexByte(0x0A))
            c = sbAppend(c, hexByte(0x4D) + hexByte(0x8B) + hexByte(0x64) + hexByte(0x24) + hexByte(0x10))
            c = sbAppend(c, hexByte(0xEB) + hexByte(256 - 36))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x31) + hexByte(0xC0))
            c = sbAppend(c, hexByte(0x41) + hexByte(0x5C))
            c = sbAppend(c, hexByte(0x5B))
            c = sbAppend(c, hexByte(0x50))
        } else if op == "BUILTIN_STRUCTFIELDS" {
            // structFields(env) — return comma-separated list of field names (most-recent first).
            // Stack on entry: env (top).
            //
            // Layout (88 bytes):
            //   [0]    5F              POP RDI                  ; env
            //   [1]    53              PUSH RBX
            //   [2-3]  41 54           PUSH R12
            //   [4-5]  41 55           PUSH R13                 ; will hold "," string
            //   [6-8]  49 89 FC        MOV R12, RDI             ; cur
            //   ; alloc 2-byte buffer for "," (byte 1 stays NUL from mmap)
            //   [9-13] BF 02 00 00 00  MOV EDI, 2
            //   [14-18] E8 dw_alloc    CALL kr_alloc
            //   [19-21] C6 00 2C       MOV byte [RAX], ',' (0x2C)
            //   [22-24] 49 89 C5       MOV R13, RAX             ; comma str
            //   ; alloc 1-byte empty result
            //   [25-29] BF 01 00 00 00 MOV EDI, 1
            //   [30-34] E8 dw_alloc    CALL kr_alloc
            //   [35-37] 48 89 C3       MOV RBX, RAX             ; result
            //   .loop at 38:
            //   [38-40] 4D 85 E4       TEST R12, R12
            //   [41-42] 74 24          JZ +36 → .done at 79
            //   [43-45] 48 89 DF       MOV RDI, RBX             ; result
            //   [46-49] 49 8B 34 24    MOV RSI, [R12]           ; name
            //   [50-54] E8 dw_concat   CALL kr_concat
            //   [55-57] 48 89 C3       MOV RBX, RAX
            //   [58-60] 48 89 DF       MOV RDI, RBX
            //   [61-63] 4C 89 EE       MOV RSI, R13             ; ","
            //   [64-68] E8 dw_concat   CALL kr_concat
            //   [69-71] 48 89 C3       MOV RBX, RAX
            //   [72-76] 4D 8B 64 24 10 MOV R12, [R12+16]
            //   [77-78] EB D7          JMP -41 → .loop at 38
            //   .done at 79:
            //   [79-81] 48 89 D8       MOV RAX, RBX
            //   [82-83] 41 5D          POP R13
            //   [84-85] 41 5C          POP R12
            //   [86]   5B              POP RBX
            //   [87]   50              PUSH RAX
            let alDispSF1 = krAllocVAddr - (funcStartVAddr + off + 19)
            let alDispSF2 = krAllocVAddr - (funcStartVAddr + off + 35)
            let cnDispSF1 = krConcatVAddr - (funcStartVAddr + off + 55)
            let cnDispSF2 = krConcatVAddr - (funcStartVAddr + off + 69)
            c = sbAppend(c, hexByte(0x5F))
            c = sbAppend(c, hexByte(0x53))
            c = sbAppend(c, hexByte(0x41) + hexByte(0x54))
            c = sbAppend(c, hexByte(0x41) + hexByte(0x55))
            c = sbAppend(c, hexByte(0x49) + hexByte(0x89) + hexByte(0xFC))
            c = sbAppend(c, hexByte(0xBF) + hexDword(2))
            c = sbAppend(c, hexByte(0xE8) + hexDword(alDispSF1))
            c = sbAppend(c, hexByte(0xC6) + hexByte(0x00) + hexByte(0x2C))
            c = sbAppend(c, hexByte(0x49) + hexByte(0x89) + hexByte(0xC5))
            c = sbAppend(c, hexByte(0xBF) + hexDword(1))
            c = sbAppend(c, hexByte(0xE8) + hexDword(alDispSF2))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xC3))
            c = sbAppend(c, hexByte(0x4D) + hexByte(0x85) + hexByte(0xE4))
            c = sbAppend(c, hexByte(0x74) + hexByte(0x24))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xDF))
            c = sbAppend(c, hexByte(0x49) + hexByte(0x8B) + hexByte(0x34) + hexByte(0x24))
            c = sbAppend(c, hexByte(0xE8) + hexDword(cnDispSF1))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xC3))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xDF))
            c = sbAppend(c, hexByte(0x4C) + hexByte(0x89) + hexByte(0xEE))
            c = sbAppend(c, hexByte(0xE8) + hexDword(cnDispSF2))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xC3))
            c = sbAppend(c, hexByte(0x4D) + hexByte(0x8B) + hexByte(0x64) + hexByte(0x24) + hexByte(0x10))
            c = sbAppend(c, hexByte(0xEB) + hexByte(256 - 41))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xD8))
            c = sbAppend(c, hexByte(0x41) + hexByte(0x5D))
            c = sbAppend(c, hexByte(0x41) + hexByte(0x5C))
            c = sbAppend(c, hexByte(0x5B))
            c = sbAppend(c, hexByte(0x50))
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
            c = sbAppend(c, hexByte(0xE8) + hexDword(disp))
            // ADD RSP, argc*8 (clean up args; harmless when argc=0)
            c = sbAppend(c, hexByte(0x48) + hexByte(0x81) + hexByte(0xC4) + hexDword(cargc * 8))
            // PUSH RAX (return value onto Krypton stack)
            c = sbAppend(c, hexByte(0x50))
        } else if op == "POP" {
            c = sbAppend(c, hexByte(0x5F))
        } else if op == "END_FUNC" {
            c = sbAppend(c, hexByte(0x48) + hexByte(0x31) + hexByte(0xC0))
            c = sbAppend(c, hexByte(0x48) + hexByte(0x89) + hexByte(0xEC))
            c = sbAppend(c, hexByte(0x5D))
            c = sbAppend(c, hexByte(0xC3))
        }

        if op != "LABEL" { off = off + opByteSize(op) }
        i += 1
    }
    emit sbToString(c)
}

// ── Driver (just run gives us argc/argv plumbing) ──────────────────

just run {
    let inFile = arg("0")
    let outFile = arg("1")
    if len(inFile) == 0 || len(outFile) == 0 {
        printErr("usage: kcc compiler/linux_x86/elf.k input.kir output.elf")
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

    // First line is the strTab line count. Read EXACTLY that many lines as the
    // string table — do NOT scan for "~~~", because a table ENTRY may itself be
    // the literal "~~~" (the section delimiter), which would truncate the table
    // and leave later string indices dangling (→ vaddr 0 → null deref). Reading
    // by count also correctly preserves interned "" (empty) entries.
    let declaredStr = toInt(getLine(parsed, 0))
    let pi = 1
    let strLines = 0
    while strLines < declaredStr {
        let pl = getLine(parsed, pi)
        if strLines > 0 { strTab = strTab + "\n" }
        strTab = strTab + pl
        strLines += 1
        pi += 1
    }

    let strCount = strLines

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
    // VADDR_BASE = 0x40000000 (1 GiB). The smart-int convention treats
    // values < VADDR_BASE as integers and ≥ VADDR_BASE as string pointers.
    // Loading the binary at 1 GiB means integer values up to ~1 billion
    // work correctly as ints (vs the previous 4M limit at 0x400000). CMP
    // uses 32-bit sign-extended immediates, so 0x40000000 is the largest
    // POSITIVE-treated threshold we can encode in a single instruction.
    // NOTE: VADDR_BASE (0x40000000) is NOT bound as a runtime value here — it
    // equals the int/pointer threshold, so `let VADDR_BASE = 0x40000000` would
    // emit a PUSH_INT that the self-hosted backend mangles to 0 (the value is
    // classified as a pointer and deref'd). The base is folded in at emit time
    // by hexDwordVaddr/hexQwordVaddr instead, so no code below needs it.
    let HDR_SIZE = 120
    // SEG_BASE_VADDR and every krXxxVAddr / funcVAddr / string vaddr below are
    // LOAD-BASE-RELATIVE OFFSETS (not full vaddrs). The full vaddr is VADDR_BASE
    // + offset, but VADDR_BASE == the int/pointer threshold, so doing arithmetic
    // on full vaddrs makes the runtime treat them as pointers and deref them
    // (toInt/%// → garbage). Keeping everything in offset space (< VADDR_BASE)
    // keeps it in int range; CALL displacements (target-site) are unaffected
    // because the base cancels; absolute addresses are emitted via
    // hexQwordVaddr/hexDwordVaddr which fold the base in at the byte level.
    let SEG_BASE_VADDR = HDR_SIZE
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
    let krWbSz = krWritebytesSize()
    let krSnSz = krSbnewSize()
    let krSaSz = krSbappendSize()
    let krStSz = krSbtostringSize()
    let krPeSz = krPrinterrSize()
    let krCcdSz = krCharcodeSize()
    let krFccSz = krFromcharcodeSize()
    let krExSz = krExitSize()
    let krIdSz = krIsdigitSize()
    let krIaSz = krIsalphaSize()
    let krAbSz = krAbsSize()
    let krSwSz = krStartswithSize()
    let krItSz = krIstruthySize()
    let krLcSz = krLinecountSize()
    let krGlSz = krGetlineSize()
    let krTrSz = krTrimSize()
    let krTuSz = krToupperSize()
    let krTlSz = krTolowerSize()
    let krPwSz = krPowSize()
    let krRpSz = krRepeatSize()
    let krInSz = krIsnumSize()
    let krPlSz = krPlusSize()
    let krA2Sz = krAtoi2Size()
    let krSiSz2 = krSubiSize()
    let krMiSz = krMuliSize()
    let krDiSz = krDiviSize()
    let krMoSz = krModiSize()
    let krScSz = krStrcmpSize()
    let krCmSz = krCmpiSize()
    let krSsSz = krStrstrSize()
    let krCnSz = krContainsSize()
    let krIoSz = krIndexofSize()
    let krEwSz = krEndswithSize()
    let krRpSz2 = krReplaceSize()
    let krRvSz = krReverseSize()
    let krMinSz = krMinSize()
    let krMaxSz = krMaxSize()
    let krBaSz = krBitandSize()
    let krBoSz = krBitorSize()
    let krBxSz = krBitxorSize()
    let krBnSz = krBitnotSize()
    let krShlSz = krShlSize()
    let krSrSz = krShrSize()
    let krHxSz = krHexSize()
    let krBiSz = krBinSize()

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
    let krWritebytesVAddr = krWritefileVAddr + krWfSz   // placed right after kr_writefile
    let krSbnewVAddr = krWritebytesVAddr + krWbSz       // real StringBuilder helpers
    let krSbappendVAddr = krSbnewVAddr + krSnSz
    let krSbtostringVAddr = krSbappendVAddr + krSaSz
    let krPrinterrVAddr  = krSbtostringVAddr + krStSz
    let krCharcodeVAddr  = krPrinterrVAddr + krPeSz
    let krFromcharcodeVAddr = krCharcodeVAddr + krCcdSz
    let krExitVAddr      = krFromcharcodeVAddr + krFccSz
    let krIsdigitVAddr   = krExitVAddr + krExSz
    let krIsalphaVAddr   = krIsdigitVAddr + krIdSz
    let krAbsVAddr       = krIsalphaVAddr + krIaSz
    let krStartswithVAddr = krAbsVAddr + krAbSz
    let krIstruthyVAddr   = krStartswithVAddr + krSwSz
    let krLinecountVAddr  = krIstruthyVAddr + krItSz
    let krGetlineVAddr    = krLinecountVAddr + krLcSz
    let krTrimVAddr       = krGetlineVAddr + krGlSz
    let krToupperVAddr    = krTrimVAddr + krTrSz
    let krTolowerVAddr    = krToupperVAddr + krTuSz
    let krPowVAddr        = krTolowerVAddr + krTlSz
    let krRepeatVAddr     = krPowVAddr + krPwSz
    let krIsnumVAddr      = krRepeatVAddr + krRpSz
    let krPlusVAddr       = krIsnumVAddr + krInSz
    let krAtoi2VAddr      = krPlusVAddr + krPlSz
    let krSubiVAddr       = krAtoi2VAddr + krA2Sz
    let krMuliVAddr       = krSubiVAddr + krSiSz2
    let krDiviVAddr       = krMuliVAddr + krMiSz
    let krModiVAddr       = krDiviVAddr + krDiSz
    let krStrcmpVAddr     = krModiVAddr + krMoSz
    let krCmpiVAddr       = krStrcmpVAddr + krScSz
    let krStrstrVAddr     = krCmpiVAddr + krCmSz
    let krContainsVAddr   = krStrstrVAddr + krSsSz
    let krIndexofVAddr    = krContainsVAddr + krCnSz
    let krEndswithVAddr   = krIndexofVAddr + krIoSz
    let krReplaceVAddr    = krEndswithVAddr + krEwSz
    let krReverseVAddr    = krReplaceVAddr + krRpSz2
    let krMinVAddr        = krReverseVAddr + krRvSz
    let krMaxVAddr        = krMinVAddr + krMinSz
    let krBitandVAddr     = krMaxVAddr + krMaxSz
    let krBitorVAddr      = krBitandVAddr + krBaSz
    let krBitxorVAddr     = krBitorVAddr + krBoSz
    let krBitnotVAddr     = krBitxorVAddr + krBxSz
    let krShlVAddr        = krBitnotVAddr + krBnSz
    let krShrVAddr        = krShlVAddr + krShlSz
    let krHexVAddr        = krShrVAddr + krSrSz
    let krBinVAddr        = krHexVAddr + krHxSz

    // String virtual addresses (after all runtime helpers)
    let stringsBase = krBinVAddr + krBiSz
    let strVAddrs = ""
    let strData = ""
    let curOff = 0
    let si = 0
    while si < strCount {
        let sv = decodeStr(getLine(strTab, si))
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

        let codeI = emitFuncCode(opStr2, strVAddrs, argc2, lcCount2, lab2, funcVAddrs, funcStartV2, krPrintVAddr, krStrIntVAddr, krConcatVAddr, krAtoiVAddr, krLengthVAddr, krStrlenVAddr, krSplitVAddr, krRangeVAddr, krIndexVAddr, krArgVAddr, krArgcountVAddr, krSubstringVAddr, krAllocVAddr, krReadfileVAddr, krWritefileVAddr, krPrinterrVAddr, krCharcodeVAddr, krFromcharcodeVAddr, krExitVAddr, krIsdigitVAddr, krIsalphaVAddr, krAbsVAddr, krStartswithVAddr, krIstruthyVAddr, krLinecountVAddr, krGetlineVAddr, krTrimVAddr, krToupperVAddr, krTolowerVAddr, krPowVAddr, krRepeatVAddr, krPlusVAddr, krSubiVAddr, krMuliVAddr, krDiviVAddr, krModiVAddr, krCmpiVAddr, krContainsVAddr, krIndexofVAddr, krEndswithVAddr, krReplaceVAddr, krStrcmpVAddr, krReverseVAddr, krSbnewVAddr, krSbappendVAddr, krSbtostringVAddr, krMinVAddr, krMaxVAddr, krBitandVAddr, krBitorVAddr, krBitxorVAddr, krBitnotVAddr, krShlVAddr, krShrVAddr, krHexVAddr, krBinVAddr)
        allFuncCode = allFuncCode + codeI
        oIdx2 += 1
    }

    // _start: CALL __main__ (mmap'd heap initialization is in emitStartCode)
    let startVAddr = SEG_BASE_VADDR
    let mainVAddr = toInt(funcVAddr(funcVAddrs, "__main__"))
    // CALL __main__ ends at start-code offset 72 (was 63; +9 for the envp save).
    let startCallDisp = mainVAddr - (startVAddr + 72)
    // CALL kr_atoi ends at start-code offset 80 (was 71).
    let startAtoiDisp = krAtoiVAddr - (startVAddr + 80)
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
    let krWritebytesCode = emitKrWritebytesCode(krWritebytesVAddr, krStrlenVAddr, krAllocVAddr)
    let krSbnewCode = emitKrSbnewCode(krSbnewVAddr, krAllocVAddr)
    let krSbappendCode = emitKrSbappendCode(krSbappendVAddr, krStrlenVAddr, krAllocVAddr)
    let krSbtostringCode = emitKrSbtostringCode()
    let krPrinterrCode  = emitKrPrinterrCode()
    let krCharcodeCode  = emitKrCharcodeCode()
    let krFromcharcodeCode = emitKrFromcharcodeCode(krFromcharcodeVAddr, krAtoiVAddr, krAllocVAddr)
    let krExitCode      = emitKrExitCode(krExitVAddr, krAtoiVAddr)
    let krIsdigitCode   = emitKrIsdigitCode()
    let krIsalphaCode   = emitKrIsalphaCode()
    let krAbsCode       = emitKrAbsCode(krAbsVAddr, krAtoiVAddr)
    let krStartswithCode = emitKrStartswithCode()
    let krIstruthyCode   = emitKrIstruthyCode(krIstruthyVAddr, krAtoiVAddr)
    let krLinecountCode  = emitKrLinecountCode()
    let krGetlineCode    = emitKrGetlineCodeFinal(krGetlineVAddr, krAtoiVAddr, krAllocVAddr)
    let krTrimCode       = emitKrTrimCode(krTrimVAddr, krStrlenVAddr, krAllocVAddr)
    let krToupperCode    = emitKrToupperCode(krToupperVAddr, krStrlenVAddr, krAllocVAddr)
    let krTolowerCode    = emitKrTolowerCode(krTolowerVAddr, krStrlenVAddr, krAllocVAddr)
    let krPowCode        = emitKrPowCode(krPowVAddr, krAtoiVAddr)
    let krRepeatCode     = emitKrRepeatCode(krRepeatVAddr, krAtoiVAddr, krStrlenVAddr, krAllocVAddr)
    let krIsnumCode      = emitKrIsnumCode()
    let krPlusCode       = emitKrPlusCode(krPlusVAddr, krIsnumVAddr, krAtoiVAddr, krConcatVAddr)
    let krAtoi2Code      = emitKrAtoi2Code(krAtoi2VAddr, krAtoiVAddr)
    let krSubiCode       = emitKrSubiCode(krSubiVAddr, krAtoi2VAddr)
    let krMuliCode       = emitKrMuliCode(krMuliVAddr, krAtoi2VAddr)
    let krDiviCode       = emitKrDiviCode(krDiviVAddr, krAtoi2VAddr)
    let krModiCode       = emitKrModiCode(krModiVAddr, krAtoi2VAddr)
    let krStrcmpCode     = emitKrStrcmpCode()
    let krCmpiCode       = emitKrCmpiCode(krCmpiVAddr, krIsnumVAddr, krAtoiVAddr, krStrcmpVAddr)
    let krStrstrCode     = emitKrStrstrCode()
    let krContainsCode   = emitKrContainsCode(krContainsVAddr, krStrstrVAddr)
    let krIndexofCode    = emitKrIndexofCode(krIndexofVAddr, krStrstrVAddr)
    let krEndswithCode   = emitKrEndswithCode(krEndswithVAddr, krStrlenVAddr)
    let krReplaceCode2   = emitKrReplaceCode(krReplaceVAddr, krStrlenVAddr, krAllocVAddr)
    let krReverseCode    = emitKrReverseCode(krReverseVAddr, krStrlenVAddr, krAllocVAddr)
    let krMinCode        = emitKrMinCode(krMinVAddr, krAtoiVAddr)
    let krMaxCode        = emitKrMaxCode(krMaxVAddr, krAtoiVAddr)
    let krBitandCode     = emitKrBitandCode(krBitandVAddr, krAtoiVAddr)
    let krBitorCode      = emitKrBitorCode(krBitorVAddr, krAtoiVAddr)
    let krBitxorCode     = emitKrBitxorCode(krBitxorVAddr, krAtoiVAddr)
    let krBitnotCode     = emitKrBitnotCode(krBitnotVAddr, krAtoiVAddr)
    let krShlCode        = emitKrShlCode(krShlVAddr, krAtoiVAddr)
    let krShrCode        = emitKrShrCode(krShrVAddr, krAtoiVAddr)
    let krHexCode        = emitKrHexCode(krHexVAddr, krAllocVAddr, krAtoiVAddr)
    let krBinCode        = emitKrBinCode(krBinVAddr, krAllocVAddr, krAtoiVAddr)

    let segment = startCode + allFuncCode + krPrintCode + krStrIntCode + krAllocCode + krStrlenCode + krConcatCode + krAtoiCode + krLengthCode + krSplitCode + krRangeCode + krIndexCode + krArgCode + krArgcountCode + krSubstringCode + krReadfileCode + krWritefileCode + krWritebytesCode + krSbnewCode + krSbappendCode + krSbtostringCode + krPrinterrCode + krCharcodeCode + krFromcharcodeCode + krExitCode + krIsdigitCode + krIsalphaCode + krAbsCode + krStartswithCode + krIstruthyCode + krLinecountCode + krGetlineCode + krTrimCode + krToupperCode + krTolowerCode + krPowCode + krRepeatCode + krIsnumCode + krPlusCode + krAtoi2Code + krSubiCode + krMuliCode + krDiviCode + krModiCode + krStrcmpCode + krCmpiCode + krStrstrCode + krContainsCode + krIndexofCode + krEndswithCode + krReplaceCode2 + krReverseCode + krMinCode + krMaxCode + krBitandCode + krBitorCode + krBitxorCode + krBitnotCode + krShlCode + krShrCode + krHexCode + krBinCode + strData
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
    eh = eh + hexQwordVaddr(entry)   // entry is a load-base offset
    eh = eh + hexQword(64)
    eh = eh + hexQword(0)
    eh = eh + hexDword(0)
    eh = eh + hexWord(64) + hexWord(56) + hexWord(1)
    eh = eh + hexWord(0) + hexWord(0) + hexWord(0)

    let ph = ""
    ph = ph + hexDword(1)              // PT_LOAD
    ph = ph + hexDword(5)              // R+X
    ph = ph + hexQword(0)
    ph = ph + hexQwordVaddr(0)   // p_vaddr = VADDR_BASE + offset 0
    ph = ph + hexQwordVaddr(0)   // p_paddr
    ph = ph + hexQword(fileSize)
    ph = ph + hexQword(fileSize)
    ph = ph + hexQword(0x1000)

    let elfBytes = eh + ph + segment
    writeBytes(outFile, elfBytes)
    printErr("elf: wrote " + outFile + " (" + (len(elfBytes) / 3) + " bytes, " + funcCount + " funcs, " + strCount + " strings)")
}
