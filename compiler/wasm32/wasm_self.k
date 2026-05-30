// wasm_self.k — Krypton-to-WebAssembly backend.
//
// Phase 1.0  ✅ skeleton + emit helpers
// Phase 1.1  ✅ parse FUNC blocks, build string table, IR-driven sections
// Phase 1.2  ✅ LOCAL / STORE / LOAD / PUSH "str" / PUSH N / BUILTIN kp /
//               ADD / SUB / POP / gc bookkeeping → lessons 01 and 04 run
//               end-to-end. Lesson 02 (string concat) hits ADD as i32 which
//               is wrong for strings but doesn't crash; real concat is 1.3.
// Phase 1.3+ ⏳ string concat runtime, function calls, control flow,
//               funcptr table, full stdlib subset.
//
// See docs/wasm_backend_design.md, docs/WASM_HOST_ABI.md, and
// docs/WASM_PHASE_1_SPLIT.md.

module wasm_self

// ── Byte-emit helpers ────────────────────────────────────────────────

func hexByte(n) {
    let HEX = "0123456789ABCDEF"
    let v = toInt(n)
    if v < 0 { v = v + 256 }
    if v > 255 { v = v % 256 }
    emit "x" + HEX[v / 16] + HEX[v % 16]
}

func b(n) { emit hexByte(n) }

func hexBytes(s) { emit len(s) / 3 }

func leb(n) {
    let out = ""
    let v = n
    while v >= 128 {
        out = out + b((v % 128) + 128)
        v = v / 128
    }
    emit out + b(v)
}

func bstr(s) {
    let out = ""
    let i = 0
    while i < len(s) {
        out = out + hexByte(toInt(charCode(s[i])))
        i += 1
    }
    emit out
}

func wasmSection(id, payload) {
    emit b(id) + leb(hexBytes(payload)) + payload
}

func wasmHeader() {
    emit b(0) + b(97) + b(115) + b(109) +
         b(1) + b(0) + b(0) + b(0)
}

// ── Tab/util ─────────────────────────────────────────────────────────

func tab() { emit fromCharCode(9) }

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

// Check whether the line literally starts with `prefix`.
func lineStarts(line, prefix) {
    if len(line) < len(prefix) { emit 0 }
    if substring(line, 0, len(prefix)) == prefix { emit 1 }
    emit 0
}

// ── String table ─────────────────────────────────────────────────────
// Strings are stored in linear memory as [length:u32 little-endian][bytes].
// A "handle" is the offset of the length field. PUSH "str" emits
// i32.const <handle>. kp dereferences: ptr = handle+4, len = mem[handle].

func strTableNew() { emit "" }

func strRowLiteral(row) {
    let p = indexOf(row, tab())
    emit substring(row, 0, p)
}

func strRowOffset(row) {
    let p1 = indexOf(row, tab())
    let rest = substring(row, p1 + 1, len(row))
    let p2 = indexOf(rest, tab())
    emit toInt(substring(rest, 0, p2))
}

func strRowLen(row) {
    let p1 = indexOf(row, tab())
    let rest = substring(row, p1 + 1, len(row))
    let p2 = indexOf(rest, tab())
    emit toInt(substring(rest, p2 + 1, len(rest)))
}

// Total bytes currently used by the table (each entry = 4 header + length).
func strTableUsed(table) {
    let n = lineCount(table)
    let i = 0
    let total = 0
    while i < n {
        let row = getLine(table, i)
        if len(row) > 0 {
            total = total + 4 + strRowLen(row)
        }
        i += 1
    }
    emit total
}

func strTableAdd(table, s) {
    let n = lineCount(table)
    let i = 0
    while i < n {
        let row = getLine(table, i)
        if len(row) > 0 && strRowLiteral(row) == s {
            emit table
        }
        i += 1
    }
    let off = strTableUsed(table)
    let newRow = s + tab() + off + tab() + len(s)
    if len(table) == 0 { emit newRow }
    emit table + fromCharCode(10) + newRow
}

func strTableOffset(table, s) {
    let n = lineCount(table)
    let i = 0
    while i < n {
        let row = getLine(table, i)
        if len(row) > 0 && strRowLiteral(row) == s {
            emit strRowOffset(row)
        }
        i += 1
    }
    emit 0
}

// Emit one 4-byte little-endian length prefix followed by the literal
// bytes, for every row. Caller wraps in a Data segment.
func strTableBlob(table) {
    let out = ""
    let n = lineCount(table)
    let i = 0
    while i < n {
        let row = getLine(table, i)
        if len(row) > 0 {
            let l = strRowLen(row)
            // u32 little-endian length
            out = out + b(l) + b(l / 256) + b((l / 65536) % 256) + b((l / 16777216) % 256)
            out = out + bstr(strRowLiteral(row))
        }
        i += 1
    }
    emit out
}

// ── Quoted-string + integer helpers ──────────────────────────────────

func strBetweenQuotes(line) {
    let first = indexOf(line, "\"")
    if first < 0 { emit "" }
    let rest = substring(line, first + 1, len(line))
    let second = indexOf(rest, "\"")
    if second < 0 { emit "" }
    emit substring(rest, 0, second)
}

// Returns 1 if `line` matches `PUSH <integer>` (no quotes).
func isPushInt(line) {
    if !lineStarts(line, "PUSH ") { emit 0 }
    let rest = substring(line, 5, len(line))
    if len(rest) == 0 { emit 0 }
    let c0 = rest[0]
    if c0 == "\"" { emit 0 }
    if c0 == "-" { emit 1 }
    if c0 >= "0" && c0 <= "9" { emit 1 }
    emit 0
}

func parseInt(line) {
    let rest = substring(line, 5, len(line))
    emit toInt(rest)
}

// ── Local-name table per function ────────────────────────────────────
// Newline-list of names. Index = position in list. The kp temp lives
// at index = list length (added implicitly).

func localsNew() { emit "" }

func localsAdd(list, name) {
    if len(list) == 0 { emit name }
    emit list + fromCharCode(10) + name
}

func localsIndex(list, name) {
    let n = lineCount(list)
    let i = 0
    while i < n {
        if getLine(list, i) == name { emit i }
        i += 1
    }
    emit -1
}

func localsCount(list) {
    if len(list) == 0 { emit 0 }
    emit lineCount(list)
}

// ── Body lowering ────────────────────────────────────────────────────

// First pass: collect every LOCAL declaration in the body.
func collectLocals(body) {
    let n = lineCount(body)
    let i = 0
    let lst = localsNew()
    while i < n {
        let line = ltrim(getLine(body, i))
        if lineStarts(line, "LOCAL ") {
            let name = substring(line, 6, len(line))
            lst = localsAdd(lst, name)
        }
        i += 1
    }
    emit lst
}

// Scan for string literals.
func collectStrings(body, table) {
    let n = lineCount(body)
    let i = 0
    let t = table
    while i < n {
        let line = ltrim(getLine(body, i))
        if lineStarts(line, "PUSH \"") {
            t = strTableAdd(t, strBetweenQuotes(line))
        }
        i += 1
    }
    emit t
}

// Emit one function body. Returns the body hex (locals vec + opcodes + end).
// `kpTmpIdx` is the local index reserved for the kp dereference dance.
func emitFuncBody(body, table, localsList) {
    let userCount = localsCount(localsList)
    let kpTmpIdx = userCount
    let totalLocals = userCount + 1            // +1 for kpTmp

    // Locals vec: 1 entry, <total> i32 (type 0x7F).
    let bb = b(1) + leb(totalLocals) + b(127)

    let n = lineCount(body)
    let i = 0
    while i < n {
        let line = ltrim(getLine(body, i))
        if lineStarts(line, "LOCAL ") {
            // Already accounted for in the locals header. No opcode.
        } else if lineStarts(line, "PUSH \"") {
            let s = strBetweenQuotes(line)
            let h = strTableOffset(table, s)
            bb = bb + b(65) + leb(h)            // i32.const handle
        } else if isPushInt(line) > 0 {
            let v = parseInt(line)
            bb = bb + b(65) + leb(v)            // i32.const v
        } else if lineStarts(line, "STORE ") {
            let name = substring(line, 6, len(line))
            let idx = localsIndex(localsList, name)
            if idx < 0 { idx = kpTmpIdx }
            bb = bb + b(33) + leb(idx)          // local.set
        } else if lineStarts(line, "LOAD ") {
            let name = substring(line, 5, len(line))
            let idx = localsIndex(localsList, name)
            if idx < 0 { idx = kpTmpIdx }
            bb = bb + b(32) + leb(idx)          // local.get
        } else if line == "ADD" {
            bb = bb + b(106)                    // i32.add
        } else if line == "SUB" {
            bb = bb + b(107)                    // i32.sub
        } else if line == "MUL" {
            bb = bb + b(108)                    // i32.mul
        } else if line == "DIV" {
            bb = bb + b(109)                    // i32.div_s
        } else if line == "MOD" {
            bb = bb + b(111)                    // i32.rem_s
        } else if lineStarts(line, "BUILTIN kp ") {
            // Stack top: handle (i32 offset into the string area).
            // tee kpTmp → (handle+4) → load length → call console_log,
            // then push dummy 0 to match IR's "every BUILTIN returns 1
            // value" convention. The trailing POP drops it cleanly.
            bb = bb + b(34) + leb(kpTmpIdx)     // local.tee kpTmp
            bb = bb + b(65) + leb(4)            // i32.const 4
            bb = bb + b(106)                    // i32.add  (ptr = handle + 4)
            bb = bb + b(32) + leb(kpTmpIdx)     // local.get kpTmp
            bb = bb + b(40) + b(2) + b(0)       // i32.load align=2 offset=0
            bb = bb + b(16) + b(0)              // call 0 (env.console_log)
            bb = bb + b(65) + b(0)              // i32.const 0  (dummy result)
        } else if lineStarts(line, "BUILTIN gcShadowCount ") {
            // Treated as a no-op that returns 0. IR pushes its result.
            bb = bb + b(65) + b(0)              // i32.const 0
        } else if lineStarts(line, "BUILTIN gcShadowPush ") {
            // Takes 1 arg, returns void. Drop the arg, push 0 to match
            // IR's "every BUILTIN returns 1 value" convention.
            bb = bb + b(26)                     // drop
            bb = bb + b(65) + b(0)              // i32.const 0
        } else if lineStarts(line, "BUILTIN gcShadowPop ") {
            // Takes 1 arg, returns void. Drop, push 0 (same reason).
            bb = bb + b(26)                     // drop
            bb = bb + b(65) + b(0)              // i32.const 0
        } else if line == "POP" {
            bb = bb + b(26)                     // drop
        } else if line == "RETURN" {
            bb = bb + b(15)                     // return
        }
        // Unhandled IR ops are skipped silently. Track them in 1.3.
        i += 1
    }
    bb = bb + b(11)                             // end
    emit bb
}

// ── Section builders ─────────────────────────────────────────────────

func wasmTypes() {
    let payload =
        b(2) +
        b(96) + b(2) + b(127) + b(127) + b(0) +     // (i32,i32)->void
        b(96) + b(0) + b(0)                         // ()->void
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

func wasmFuncs(funcCount) {
    let payload = leb(funcCount)
    let i = 0
    while i < funcCount {
        payload = payload + b(1)
        i += 1
    }
    emit wasmSection(3, payload)
}

func wasmMemory() {
    let payload = b(1) + b(0) + b(1)
    emit wasmSection(5, payload)
}

func wasmExports(mainIdx) {
    let payload =
        b(2) +
        b(6) + bstr("memory") + b(2) + b(0) +
        b(6) + bstr("_start") + b(0) + leb(mainIdx)
    emit wasmSection(7, payload)
}

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

func wasmData(blob) {
    if len(blob) == 0 { emit "" }
    let payload =
        b(1) +
        b(0) +                              // memory 0, active
        b(65) + b(0) + b(11) +              // offset: i32.const 0, end
        leb(hexBytes(blob)) + blob
    emit wasmSection(11, payload)
}

// ── Driver ───────────────────────────────────────────────────────────

func buildModule(ir) {
    let n = lineCount(ir)
    let strTab = strTableNew()
    let funcBodies = ""
    let funcCount = 0
    let mainIdx = 0
    let funcNames = ""
    let i = 0
    while i < n {
        let line = ltrim(getLine(ir, i))
        if lineStarts(line, "FUNC ") {
            let body = ""
            i += 1
            while i < n {
                let l2 = ltrim(getLine(ir, i))
                if l2 == "END" { i += 1  break }
                if len(body) == 0 { body = l2 }
                else              { body = body + fromCharCode(10) + l2 }
                i += 1
            }
            strTab = collectStrings(body, strTab)
            let locals = collectLocals(body)
            let hex = emitFuncBody(body, strTab, locals)
            if len(funcBodies) == 0 { funcBodies = hex }
            else                    { funcBodies = funcBodies + fromCharCode(10) + hex }
            let rest = substring(line, 5, len(line))
            let spacePos = indexOf(rest, " ")
            let name = rest
            if spacePos > 0 { name = substring(rest, 0, spacePos) }
            if name == "__main__" { mainIdx = funcCount + 1 }    // +1 for import
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
