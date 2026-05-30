// wasm_self.k — Krypton-to-WebAssembly backend.
//
// Phase 1.0  ✅ skeleton + emit helpers
// Phase 1.1  ✅ parse FUNC blocks, build string table, IR-driven
//               Type/Import/Function/Memory/Export/Data sections
// Phase 1.2  🟡 partial — `PUSH "string"` + `BUILTIN kp 1` lowered;
//               lessons 01 + 02 + 03 produce matching output via the
//               Agent B Node loader. arithmetic / locals / calls land next.
// Phase 1.3+ ⏳ see docs/WASM_PHASE_1_SPLIT.md
//
// See docs/wasm_backend_design.md for the long-arc design and
// docs/WASM_HOST_ABI.md for the locked contract this code emits against.

module wasm_self

// ── Byte-emit helpers ────────────────────────────────────────────────
// Every byte goes through hexByte → "xHH"; writeBytes() at the end
// decodes hex pairs into raw bytes (avoids Krypton's null-terminator
// truncation on string concat).

func hexByte(n) {
    let HEX = "0123456789ABCDEF"
    let v = toInt(n)
    if v < 0 { v = v + 256 }
    if v > 255 { v = v % 256 }
    emit "x" + HEX[v / 16] + HEX[v % 16]
}

func b(n) { emit hexByte(n) }

func hexBytes(s) { emit len(s) / 3 }

// LEB128 unsigned, multi-byte safe.
func leb(n) {
    let out = sbNew()
    let v = n
    while v >= 128 {
        out = sbAppend(out, b((v % 128) + 128))
        v = v / 128
    }
    out = sbAppend(out, b(v))
    emit sbToString(out)
}

// ASCII string → hex bytes.
func bstr(s) {
    let out = sbNew()
    let i = 0
    while i < len(s) {
        out = sbAppend(out, hexByte(toInt(charCode(s[i]))))
        i += 1
    }
    emit sbToString(out)
}

// One section: id + LEB128 length + payload.
func wasmSection(id, payload) {
    emit b(id) + leb(hexBytes(payload)) + payload
}

// Magic "\0asm" + version 1.
func wasmHeader() {
    emit b(0) + b(97) + b(115) + b(109) +
         b(1) + b(0) + b(0) + b(0)
}

// ── IR parsing ───────────────────────────────────────────────────────
// State is encoded as comma-format strings; both `funcs` and `strs`
// use newline-encoded line tables. Each row stores all the data we
// need for that record.

// ── String table ─────────────────────────────────────────────────────
// Rows: "literal\toffset\tlength" — one per unique string literal.

func tab() { emit fromCharCode(9) }

func strTableNew() { emit "" }

// Returns the offset of `s` in the table. Appends if new.
// The returned table includes the new row.
func strTableAdd(table, s) {
    let n = lineCount(table)
    let i = 0
    let totalLen = 0
    while i < n {
        let row = getLine(table, i)
        if len(row) > 0 {
            let tabPos = indexOf(row, tab())
            let literal = substring(row, 0, tabPos)
            if literal == s {
                emit table
            }
            // accumulate length of stored literals to compute next offset
            let rest = substring(row, tabPos + 1, len(row))
            let secondTab = indexOf(rest, tab())
            let lenStr = substring(rest, secondTab + 1, len(rest))
            totalLen = totalLen + toInt(lenStr)
        }
        i += 1
    }
    // Not found — append at current totalLen offset.
    let newRow = s + tab() + totalLen + tab() + len(s)
    if len(table) == 0 {
        emit newRow
    }
    emit table + fromCharCode(10) + newRow
}

func strTableOffset(table, s) {
    let n = lineCount(table)
    let i = 0
    while i < n {
        let row = getLine(table, i)
        if len(row) > 0 {
            let tabPos = indexOf(row, tab())
            let literal = substring(row, 0, tabPos)
            if literal == s {
                let rest = substring(row, tabPos + 1, len(row))
                let secondTab = indexOf(rest, tab())
                emit toInt(substring(rest, 0, secondTab))
            }
        }
        i += 1
    }
    emit 0
}

func strTableLen(table, s) {
    let n = lineCount(table)
    let i = 0
    while i < n {
        let row = getLine(table, i)
        if len(row) > 0 {
            let tabPos = indexOf(row, tab())
            let literal = substring(row, 0, tabPos)
            if literal == s {
                let rest = substring(row, tabPos + 1, len(row))
                let secondTab = indexOf(rest, tab())
                emit toInt(substring(rest, secondTab + 1, len(rest)))
            }
        }
        i += 1
    }
    emit 0
}

// Concatenate all literal bytes for the Data section payload.
func strTableBlob(table) {
    let out = sbNew()
    let n = lineCount(table)
    let i = 0
    while i < n {
        let row = getLine(table, i)
        if len(row) > 0 {
            let tabPos = indexOf(row, tab())
            let literal = substring(row, 0, tabPos)
            out = sbAppend(out, literal)
        }
        i += 1
    }
    emit sbToString(out)
}

// ── IR helpers ───────────────────────────────────────────────────────

// Strip leading whitespace.
func ltrim(s) {
    let i = 0
    let n = len(s)
    while i < n {
        let c = s[i]
        if c != " " && c != "\t" { emit substring(s, i, n) }
        i += 1
    }
    emit ""
}

// Find the literal between the first pair of double quotes on a line.
// Returns "" if none.
func strBetweenQuotes(line) {
    let first = indexOf(line, "\"")
    if first < 0 { emit "" }
    let rest = substring(line, first + 1, len(line))
    let second = indexOf(rest, "\"")
    if second < 0 { emit "" }
    emit substring(rest, 0, second)
}

// Pre-scan a function's body and add every PUSH "str" literal to the
// string table.
func collectStrings(body, table) {
    let n = lineCount(body)
    let i = 0
    let t = table
    while i < n {
        let line = ltrim(getLine(body, i))
        if startsWith(line, "PUSH \"") {
            let s = strBetweenQuotes(line)
            t = strTableAdd(t, s)
        }
        i += 1
    }
    emit t
}

// ── Per-function body lowering ───────────────────────────────────────
// Phase 1.2 minimum: PUSH "str", BUILTIN kp 1, POP, END.
// Returns the body hex bytes (NOT including the function-body length
// prefix). Caller adds the length prefix.

func emitFuncBody(body, table) {
    let bb = b(0)                          // locals vec: empty
    let depth = 0                          // WASM stack depth tracker
    let n = lineCount(body)
    let i = 0
    while i < n {
        let line = ltrim(getLine(body, i))
        if startsWith(line, "PUSH \"") {
            let s = strBetweenQuotes(line)
            let off = strTableOffset(table, s)
            let slen = strTableLen(table, s)
            bb = bb + b(65) + leb(off) + b(65) + leb(slen)
            depth = depth + 2
        } else if startsWith(line, "BUILTIN kp ") {
            // call 0 (env.console_log) — pops 2 (ptr+len), returns void.
            // Don't push a dummy: the matching IR POP will not fire
            // because we depth-gate the drop emit.
            bb = bb + b(16) + b(0)
            depth = depth - 2
        } else if line == "POP" {
            if depth > 0 {
                bb = bb + b(26)            // drop
                depth = depth - 1
            }
        }
        // Everything else (LOCAL/LOAD/STORE/BUILTIN gcShadow*/SUB/RETURN):
        // skip in Phase 1.2. Phase 1.3 implements them faithfully.
        i += 1
    }
    bb = bb + b(11)                        // end
    emit bb
}

// ── Section builders (IR-driven) ─────────────────────────────────────

// Type section. We ship two function types:
//   type 0: (i32, i32) -> ()    matches env.console_log
//   type 1: () -> ()            matches every Krypton func in 1.2
//
// 1.3 will expand this to one type per unique (param-arity, return) shape.
func wasmTypes() {
    let payload =
        b(2) +
        b(96) + b(2) + b(127) + b(127) + b(0) +
        b(96) + b(0) + b(0)
    emit wasmSection(1, payload)
}

func wasmImports() {
    let payload =
        b(1) +
        b(3) + bstr("env") +
        b(11) + bstr("console_log") +
        b(0) + b(0)
    emit wasmSection(2, payload)
}

// One function per user-defined func in the IR. Phase 1.2 gives every
// one type-1 (() -> ()).
func wasmFuncs(funcCount) {
    let payload = leb(funcCount)
    let i = 0
    while i < funcCount {
        payload = payload + b(1)    // type 1
        i += 1
    }
    emit wasmSection(3, payload)
}

func wasmMemory() {
    let payload = b(1) + b(0) + b(1)
    emit wasmSection(5, payload)
}

// Phase 1.2 exports memory + _start (= __main__). User funcs are not
// individually exported.
func wasmExports(mainIdx) {
    let payload =
        b(2) +
        b(6) + bstr("memory") + b(2) + b(0) +
        b(6) + bstr("_start") + b(0) + leb(mainIdx)
    emit wasmSection(7, payload)
}

// Code section. funcBodies is a newline-list; one body per line as a
// hex string (already includes locals vec + opcodes + 0x0b end).
func wasmCode(funcBodies) {
    let cnt = lineCount(funcBodies)
    let payload = leb(cnt)
    let i = 0
    while i < cnt {
        let body = getLine(funcBodies, i)
        if len(body) > 0 {
            payload = payload + leb(hexBytes(body)) + body
        }
        i += 1
    }
    emit wasmSection(10, payload)
}

// One data segment loading the whole string blob at offset 0.
func wasmData(blob) {
    if len(blob) == 0 {
        // No strings used. Skip the section entirely.
        emit ""
    }
    let bytes = bstr(blob)
    let payload =
        b(1) +
        b(0) +                        // memory 0, active
        b(65) + b(0) + b(11) +        // offset: i32.const 0, end
        leb(len(blob)) + bytes
    emit wasmSection(11, payload)
}

// ── Driver ───────────────────────────────────────────────────────────
// Parse FUNC blocks out of the IR, walk each, build the module.

func buildModule(ir) {
    // Walk IR line by line. State machine: between funcs, inside func.
    let n = lineCount(ir)
    let strTab = strTableNew()
    let funcBodies = ""             // newline-list of hex-encoded bodies
    let funcCount = 0
    let mainIdx = 0
    let funcNames = ""              // newline-list of names in declaration order
    let i = 0
    while i < n {
        let line = ltrim(getLine(ir, i))
        if startsWith(line, "FUNC ") {
            // Collect this func's body until END.
            let body = ""
            i += 1
            while i < n {
                let l2 = ltrim(getLine(ir, i))
                if l2 == "END" {
                    i += 1
                    break
                }
                if len(body) == 0 { body = l2 }
                else              { body = body + fromCharCode(10) + l2 }
                i += 1
            }
            strTab = collectStrings(body, strTab)
            let hex = emitFuncBody(body, strTab)
            if len(funcBodies) == 0 { funcBodies = hex }
            else                    { funcBodies = funcBodies + fromCharCode(10) + hex }
            // Track function name → index for _start lookup.
            // Header: "FUNC __main__ 0". Field at position 1 is the name.
            let rest = substring(line, 5, len(line))
            let spacePos = indexOf(rest, " ")
            let name = rest
            if spacePos > 0 { name = substring(rest, 0, spacePos) }
            if name == "__main__" { mainIdx = funcCount + 1 } // +1 because import is index 0
            if len(funcNames) == 0 { funcNames = name }
            else                   { funcNames = funcNames + fromCharCode(10) + name }
            funcCount += 1
        } else {
            i += 1
        }
    }

    let blob = strTableBlob(strTab)
    emit wasmHeader() +
         wasmTypes() +
         wasmImports() +
         wasmFuncs(funcCount) +
         wasmMemory() +
         wasmExports(mainIdx) +
         wasmCode(funcBodies) +
         wasmData(blob)
}

just run {
    let irPath  = arg("0")
    let outPath = arg("1")
    if argCount() < 2 {
        printErr("wasm_self: usage: wasm_self <input.kir> <output.wasm>\n")
        emit 1
    }
    let ir = readFile(irPath)
    if len(ir) == 0 {
        printErr("wasm_self: could not read " + irPath + "\n")
        emit 1
    }
    let mod = buildModule(ir)
    writeBytes(outPath, mod)
    printErr("wasm_self: wrote " + outPath + " (" + hexBytes(mod) + " bytes)\n")
}
