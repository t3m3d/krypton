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

// _start: call __main__, use return value (RAX) as exit code, SYS_exit.
//   [0]  E8 disp32         CALL __main__                  (5)
//   [5]  48 89 C7          MOV RDI, RAX                   (3)  ; exit code = main's return
//   [8]  B8 3C 00 00 00    MOV EAX, 60                    (5)
//   [13] 0F 05             SYSCALL                        (2)
// Total: 15 bytes.
func startSize() { emit 15 }
func emitStartCode(callDisp) {
    let c = ""
    c = c + hexByte(0xE8) + hexDword(callDisp)
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
    if op == "ADD"        { emit 6 }    // POP+POP+ADD+PUSH
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
    if op == "BUILTIN_KP" { emit 8 }    // POP RDI (1) + CALL d32 (5) + PUSH 0 (2)
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
                } else {
                    opSb = sbAppend(opSb, "UNSUPPORTED " + bname)
                }
                opCount += 1
            } else if op == "ADD" || op == "SUB" || op == "MUL" || op == "DIV" || op == "MOD"
                   || op == "EQ" || op == "NEQ" || op == "LT" || op == "GT" || op == "LTE" || op == "GTE"
                   || op == "POP" || op == "RETURN" {
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

func emitFuncCode(opList, strVAddrs, argcount, localCount, labels, funcVAddrs, funcStartVAddr) {
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
            c = c + hexByte(0x59) + hexByte(0x58)
            c = c + hexByte(0x48) + hexByte(0x01) + hexByte(0xC8)
            c = c + hexByte(0x50)
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
            c = c + hexByte(0x5F)
            c = c + hexByte(0xE8) + hexDword(0)                       // CALL kr_print (patched post-emit)
            c = c + hexByte(0x6A) + hexByte(0x00)                     // PUSH 0
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
            if funcFirst == "0" { funcBlocksSb = sbAppend(funcBlocksSb, "\r") }
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
    let cur = ""
    let fbn = len(funcBlocks)
    let fi = 0
    let fStart = 0
    while fi <= fbn {
        if fi == fbn || funcBlocks[fi] == "\r" {
            let block = substring(funcBlocks, fStart, fi)
            let header = getLine(block, 0)
            // header = "FUNC name argc lcCount"
            // parse name (3rd whitespace-separated... wait FUNC is 1st, name 2nd)
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

    // Helper to extract block i
    // (inline since we don't have higher-order funcs)
    let fIdx = 0
    while fIdx < funcCount {
        // Walk funcBlocks to find block fIdx
        let bj = 0
        let bStart = 0
        let bI = 0
        let bbn = len(funcBlocks)
        let block = ""
        while bI <= bbn {
            if bI == bbn || funcBlocks[bI] == "\r" {
                if bj == fIdx {
                    block = substring(funcBlocks, bStart, bI)
                    break
                }
                bj += 1
                bStart = bI + 1
            }
            bI += 1
        }
        // Parse block
        let header = getLine(block, 0)
        let hsp1 = 0
        while hsp1 < len(header) && header[hsp1] != " " { hsp1 += 1 }
        let hsp2 = hsp1 + 1
        while hsp2 < len(header) && header[hsp2] != " " { hsp2 += 1 }
        let hsp3 = hsp2 + 1
        while hsp3 < len(header) && header[hsp3] != " " { hsp3 += 1 }
        let argcStr = substring(header, hsp2 + 1, hsp3)
        let lcStr = substring(header, hsp3 + 1, len(header))
        let argc = toInt(argcStr)
        let lcCount = toInt(lcStr)

        // ops are everything after line 3 (header, params, locals, opCount). But getLine works per-line.
        let blockNl = lineCount(block)
        let opcLine = toInt(getLine(block, 3))
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
        if flFirst == "0" { flSb = sbAppend(flSb, "\r") }
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
        // Get func name
        let bj2 = 0
        let bStart2 = 0
        let bI2 = 0
        let bbn2 = len(funcBlocks)
        let blk2 = ""
        while bI2 <= bbn2 {
            if bI2 == bbn2 || funcBlocks[bI2] == "\r" {
                if bj2 == fid {
                    blk2 = substring(funcBlocks, bStart2, bI2)
                    break
                }
                bj2 += 1
                bStart2 = bI2 + 1
            }
            bI2 += 1
        }
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

    let krPrintVAddr = SEG_BASE_VADDR + startSz + totalCodeSize

    // String virtual addresses (after kr_print)
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

    // ── Emit pass: for each function in order, emit code with real funcVAddrs ──
    let allFuncCode = ""
    let oIdx2 = 0
    while oIdx2 < funcCount {
        let fid2 = toInt(getLine(order, oIdx2))
        // Re-extract block
        let bj3 = 0
        let bStart3 = 0
        let bI3 = 0
        let bbn3 = len(funcBlocks)
        let blk3 = ""
        while bI3 <= bbn3 {
            if bI3 == bbn3 || funcBlocks[bI3] == "\r" {
                if bj3 == fid2 {
                    blk3 = substring(funcBlocks, bStart3, bI3)
                    break
                }
                bj3 += 1
                bStart3 = bI3 + 1
            }
            bI3 += 1
        }
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

        // Get this func's labels
        let bj4 = 0
        let bStart4 = 0
        let bI4 = 0
        let bbn4 = len(funcLabelsList)
        let lab2 = ""
        while bI4 <= bbn4 {
            if bI4 == bbn4 || funcLabelsList[bI4] == "\r" {
                if bj4 == fid2 {
                    lab2 = substring(funcLabelsList, bStart4, bI4)
                    break
                }
                bj4 += 1
                bStart4 = bI4 + 1
            }
            bI4 += 1
        }

        let nm2 = substring(hh, ss1 + 1, ss2)
        let funcStartV2 = toInt(funcVAddr(funcVAddrs, nm2))

        let codeI = emitFuncCode(opStr2, strVAddrs, argc2, lcCount2, lab2, funcVAddrs, funcStartV2)
        allFuncCode = allFuncCode + codeI
        oIdx2 += 1
    }

    // Patch BUILTIN_KP CALL placeholders (E8 00 00 00 00 6A 00 → real disp to kr_print)
    // Walk allFuncCode looking for the marker. funcStartVAddr changes per func, but we know
    // each func's start vaddr from funcVAddrs. To patch, we need each byte's absolute vaddr.
    // We track byte-offset within the combined code; vaddr = SEG_BASE+startSz+offset.
    let allFuncStartVAddr = SEG_BASE_VADDR + startSz
    let patchedSb = sbNew()
    let ml = hexBytesLen(allFuncCode)
    let mi = 0
    while mi < ml {
        let triple = substring(allFuncCode, mi*3, mi*3 + 3)
        let b = substring(triple, 1, 3)
        let isCall = "0"
        if b == "E8" && mi + 6 < ml {
            let z1 = substring(allFuncCode, (mi+1)*3 + 1, (mi+1)*3 + 3)
            let z2 = substring(allFuncCode, (mi+2)*3 + 1, (mi+2)*3 + 3)
            let z3 = substring(allFuncCode, (mi+3)*3 + 1, (mi+3)*3 + 3)
            let z4 = substring(allFuncCode, (mi+4)*3 + 1, (mi+4)*3 + 3)
            let p1 = substring(allFuncCode, (mi+5)*3 + 1, (mi+5)*3 + 3)
            let p2 = substring(allFuncCode, (mi+6)*3 + 1, (mi+6)*3 + 3)
            if z1 == "00" && z2 == "00" && z3 == "00" && z4 == "00" && p1 == "6A" && p2 == "00" {
                isCall = "1"
            }
        }
        if isCall == "1" {
            let ripAfter = allFuncStartVAddr + mi + 5
            let disp = krPrintVAddr - ripAfter
            patchedSb = sbAppend(patchedSb, hexByte(0xE8))
            patchedSb = sbAppend(patchedSb, hexDword(disp))
            mi = mi + 5
        } else {
            patchedSb = sbAppend(patchedSb, triple)
            mi = mi + 1
        }
    }
    let allFuncCodePatched = sbToString(patchedSb)

    // _start: CALL __main__
    let startVAddr = SEG_BASE_VADDR
    let mainVAddr = toInt(funcVAddr(funcVAddrs, "__main__"))
    let startCallDisp = mainVAddr - (startVAddr + 5)
    let startCode = emitStartCode(startCallDisp)

    let krPrintCode = emitKrPrintCode()

    let segment = startCode + allFuncCodePatched + krPrintCode + strData
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
