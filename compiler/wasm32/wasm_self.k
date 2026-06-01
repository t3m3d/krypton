// wasm_self.k — Krypton-to-WebAssembly backend.
//
// Phase 1.0  ✅ skeleton + emit helpers
// Phase 1.1  ✅ parse FUNC blocks, build string table, IR-driven sections
// Phase 1.2  ✅ LOCAL / STORE / LOAD / PUSH "str" / PUSH N / BUILTIN kp /
//               ADD / SUB / POP / gc bookkeeping → lesson 01 runs e2e.
// Phase 1.3  ✅ string concat (tagged-i32 scheme). Values are tagged i32:
//               int N -> (N<<1), string handle H -> (H<<1)|1; LSB is the tag.
//               ADD dispatches int-add vs $concat. kp dispatches
//               console_log_int vs console_log, +console_log(4,1) newline.
//               Helpers $int2str/$tostr/$concat hand-emitted (fn idx 2,3,4);
//               bump allocator in global 0. Newline string at fixed mem
//               offset 0; real string handles start at strBase()=5.
//               → RUN.sh lessons 01,02,04 PASS (PASS=3/8).
// Phase 1.4  ⏳ string builtins (len/index/substring/startsWith → 03),
//               control flow (JUMPIF/JUMP/LABEL → 05,06), function calls
//               (CALL/BUILTIN user funcs → 07), more print (08),
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

// Signed LEB128 for non-negative i32.const operands. Unsigned leb misreads
// any single byte with bit 6 set (values 64..127) as negative, so an extra
// zero continuation byte is appended whenever the final group's sign bit
// would otherwise be set. All compile-time constants we emit are >= 0
// (handles, tags, offsets, bump pointer, non-negative literals); runtime
// negatives come from SUB/NEG, never from i32.const.
func sleb(n) {
    let out = ""
    let v = n
    let more = 1
    while more == 1 {
        let byte = v % 128
        v = v / 128
        if v == 0 && byte < 64 {
            more = 0                         // last group, sign bit clear
        } else {
            byte = byte + 128                // continuation bit
        }
        out = out + b(byte)
    }
    emit out
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
        if c != " " && c != "\t" {
            // also strip trailing whitespace incl. \r (CRLF line endings
            // from Windows-emitted IR otherwise leave "POP\r" which
            // breaks `line == "POP"` equality checks downstream).
            let j = n - 1
            while j > i {
                let cj = s[j]
                if cj != " " && cj != "\t" && cj != "\r" && cj != "\n" { emit substring(s, i, j + 1) }
                j -= 1
            }
            emit substring(s, i, n)
        }
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
//
// The literal is stored HEX-ENCODED in each row (2 hex chars/byte) so that a
// literal containing a tab or newline byte can't corrupt the TAB-field /
// newline-row table structure. Row: <hexLiteral> TAB <offset> TAB <byteLen>.

func strTableNew() { emit "" }

// hex-encode a string to 2 chars/byte (uppercase, no separators).
// NB: Krypton coerces `digitStr + digitStr` to integer addition, which
// corrupts a growing all-hex string. Build via fromCharCode so each append
// goes through a guaranteed-string path (concatChar), never numeric `+`.
func hexDigitChar(v) {
    // v in 0..15 -> '0'..'9','A'..'F' as a 1-char string.
    if v < 10 { emit fromCharCode(48 + v) }
    emit fromCharCode(55 + v)
}

func strHexEncode(s) {
    // Prefix with a non-digit sentinel so `out` is never a pure number; this
    // defeats Krypton's digitStr+digitStr -> integer-add coercion. Strip after.
    let out = "x"
    let i = 0
    while i < len(s) {
        let v = toInt(charCode(s[i]))
        out = out + hexDigitChar(v / 16)
        out = out + hexDigitChar(v % 16)
        i += 1
    }
    emit substring(out, 1, len(out))
}

// hex value of a single char '0'-'9''A'-'F'.
func hexVal(c) {
    let v = toInt(charCode(c))
    if v >= 48 && v <= 57 { emit v - 48 }      // 0-9
    emit v - 55                                 // A-F
}

func strRowLiteralHex(row) {
    let p = indexOf(row, tab())
    emit substring(row, 0, p)
}

// decoded byte length of a row's literal = hexlen / 2.
func strRowByteLen(row) {
    emit len(strRowLiteralHex(row)) / 2
}

func strRowOffset(row) {
    let p1 = indexOf(row, tab())
    let rest = substring(row, p1 + 1, len(row))
    let p2 = indexOf(rest, tab())
    emit toInt(substring(rest, 0, p2))
}

// Total bytes currently used by the table (each entry = 4 header + byteLen).
func strTableUsed(table) {
    let n = lineCount(table)
    let i = 0
    let total = 0
    while i < n {
        let row = getLine(table, i)
        if len(row) > 0 {
            total = total + 4 + strRowByteLen(row)
        }
        i += 1
    }
    emit total
}

func strTableAdd(table, s) {
    let hexS = strHexEncode(s)
    let n = lineCount(table)
    let i = 0
    while i < n {
        let row = getLine(table, i)
        if len(row) > 0 && strRowLiteralHex(row) == hexS {
            emit table
        }
        i += 1
    }
    let off = strTableUsed(table)
    // row: <hexLiteral> TAB <offset> TAB <byteLen>. No raw bytes -> tab/newline
    // safe even when the literal itself contains 0x09 / 0x0a.
    let newRow = hexS + tab() + off + tab() + len(s)
    if len(table) == 0 { emit newRow }
    emit table + fromCharCode(10) + newRow
}

// Newline string lives at a FIXED offset 0 ([len=1][0x0a] = 5 bytes), NOT in
// the table. Real string handles start after it.
func strBase() { emit 5 }

func strTableOffset(table, s) {
    let hexS = strHexEncode(s)
    let n = lineCount(table)
    let i = 0
    while i < n {
        let row = getLine(table, i)
        if len(row) > 0 && strRowLiteralHex(row) == hexS {
            emit strRowOffset(row) + strBase()
        }
        i += 1
    }
    emit strBase()
}

// Emit the fixed newline string at offset 0, then a 4-byte little-endian
// length prefix + literal bytes (decoded from hex) for every row.
func strTableBlob(table) {
    // newline string: len=1, byte 0x0a. kp prints it via console_log(4,1).
    let out = b(1) + b(0) + b(0) + b(0) + b(10)
    let n = lineCount(table)
    let i = 0
    while i < n {
        let row = getLine(table, i)
        if len(row) > 0 {
            let hexL = strRowLiteralHex(row)
            let l = len(hexL) / 2
            // u32 little-endian length
            out = out + b(l) + b(l / 256) + b((l / 65536) % 256) + b((l / 16777216) % 256)
            // decode hex pairs -> raw bytes
            let k = 0
            while k < len(hexL) {
                out = out + b(hexVal(hexL[k]) * 16 + hexVal(hexL[k + 1]))
                k += 2
            }
        }
        i += 1
    }
    emit out
}

// ── Quoted-string + integer helpers ──────────────────────────────────

// Extract + unescape the quoted literal. Finds the closing quote (skipping
// \") then unescapes the slice. NB: Krypton's `+` coerces two numeric-looking
// strings to integer addition ("4"+"2"==6!), so we must NOT build the result
// by char-by-char `+`. Instead slice with substring (always returns a string)
// and only rewrite escapes.
func strBetweenQuotes(line) {
    let first = indexOf(line, "\"")
    if first < 0 { emit "" }
    // find closing quote, honoring backslash escapes
    let i = first + 1
    let n = len(line)
    let close = -1
    while i < n {
        let c = line[i]
        if c == "\\" { i += 2 }
        else if c == "\"" { close = i  i = n }
        else { i += 1 }
    }
    if close < 0 { emit "" }
    let raw = substring(line, first + 1, close)    // slice (guaranteed string)
    // unescape. NB: Krypton source escapes are NOT C-style: "\\n" in source
    // is already a single newline char, so `replace(raw, "\\n", ...)` would
    // hunt for newlines, not the literal 2-byte backslash-n that IR files
    // actually carry. Build the patterns via fromCharCode(92) instead.
    let bs = fromCharCode(92)
    raw = replace(raw, bs + "\"", "\"")
    raw = replace(raw, bs + "n",  fromCharCode(10))
    raw = replace(raw, bs + "t",  fromCharCode(9))
    raw = replace(raw, bs + bs,   bs)
    emit raw
}

// Returns 1 if `line` matches `PUSH <integer>` (no quotes).
func isPushInt(line) {
    if !lineStarts(line, "PUSH ") { emit 0 }
    let rest = substring(line, 5, len(line))
    if len(rest) == 0 { emit 0 }
    let c0 = rest[0]
    if c0 == "\"" { emit 0 }
    if c0 == "-" { emit 1 }
    // String `<=` is unreliable in Krypton; compare codepoints numerically.
    let cc = toInt(charCode(c0))
    if cc >= 48 && cc <= 57 { emit 1 }
    emit 0
}

// NB: named pushIntVal, not parseInt — `parseInt` is a Krypton builtin that
// shadows user funcs and would parse the whole "PUSH N" line, yielding garbage.
func pushIntVal(line) {
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

// Collect PARAM names (wasm local indices 0..P-1, before declared locals).
func collectParams(body) {
    let n = lineCount(body)
    let i = 0
    let lst = localsNew()
    while i < n {
        let line = ltrim(getLine(body, i))
        if lineStarts(line, "PARAM ") {
            let name = substring(line, 6, len(line))
            lst = localsAdd(lst, name)
        }
        i += 1
    }
    emit lst
}

// Concatenate two newline name-lists (params first, then locals).
func nameListJoin(a, c) {
    if len(a) == 0 { emit c }
    if len(c) == 0 { emit a }
    emit a + fromCharCode(10) + c
}

// True (1) if the body has any RETURN -> the func returns an i32 value.
func bodyHasReturn(body) {
    let n = lineCount(body)
    let i = 0
    while i < n {
        if ltrim(getLine(body, i)) == "RETURN" { emit 1 }
        i += 1
    }
    emit 0
}

// wasm func-index of a user function name (imports 0-1, helpers 2-10, users 11+).
func funcIndexOf(funcNames, name) {
    let n = lineCount(funcNames)
    let i = 0
    while i < n {
        if getLine(funcNames, i) == name { emit 11 + i }
        i += 1
    }
    emit 8
}

// Second token of "CALL name N".
func callName(line) {
    let rest = substring(line, 5, len(line))
    let p = indexOf(rest, " ")
    if p < 0 { emit rest }
    emit substring(rest, 0, p)
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

// ── Control-flow construct stack (structured if/else + while loops) ───
// IR is goto-style (JUMPIFNOT/JUMP/LABEL); wasm needs structured
// if/else/end + block/loop/br. One stack row per OPEN wasm construct
// (top = innermost), so `br` depths compute directly. Row format:
//   kind TAB labelA TAB labelB
//   "if"  CLOSE  ELSE   (if/if-else; CLOSE "-" until JUMP sets it)
//   "blk" WEND   -      (loop's outer block; br target = loop exit)
//   "lp"  WLOOP  -      (loop's inner loop;  br target = continue)
// labelA is the br target for that construct.
func cfPush(s, row) {
    if len(s) == 0 { emit row }
    emit s + fromCharCode(10) + row
}
func cfTop(s) {
    let n = lineCount(s)
    if n == 0 { emit "" }
    emit getLine(s, n - 1)
}
func cfDrop(s) {
    let n = lineCount(s)
    if n <= 1 { emit "" }
    let out = getLine(s, 0)
    let k = 1
    while k < n - 1 { out = out + fromCharCode(10) + getLine(s, k)  k += 1 }
    emit out
}
// field idx (0=kind,1=labelA,2=labelB) of a TAB-split row.
func cfField(row, idx) {
    let r = row
    let i = 0
    while i < idx {
        let p = indexOf(r, tab())
        r = substring(r, p + 1, len(r))
        i += 1
    }
    let p = indexOf(r, tab())
    if p < 0 { emit r }
    emit substring(r, 0, p)
}
// Set labelA (the close label) of the top frame — used when JUMP reveals
// an if-else's endif target.
func cfSetClose(s, closeL) {
    let n = lineCount(s)
    let top = getLine(s, n - 1)
    let kind = cfField(top, 0)
    let elseL = cfField(top, 2)
    let row = kind + tab() + closeL + tab() + elseL
    if n <= 1 { emit row }
    let out = getLine(s, 0)
    let k = 1
    while k < n - 1 { out = out + fromCharCode(10) + getLine(s, k)  k += 1 }
    emit out + fromCharCode(10) + row
}
// br depth to the construct whose labelA == label (0 = innermost / top).
func cfDepth(s, label) {
    let n = lineCount(s)
    let d = 0
    let k = n - 1
    while k >= 0 {
        if cfField(getLine(s, k), 1) == label { emit d }
        d += 1
        k -= 1
    }
    emit 0
}

// Emit one function body. Returns the body hex (locals vec + opcodes + end).
// Values are tagged i32 (see header): int N -> (N<<1), string H -> (H<<1)|1.
// localsList = params ++ declared-locals (combined, for index lookup);
// paramCount of those are wasm function params (not declared in the vec).
// Scratch locals (kpTmp,t0,t1) follow all of them. funcNames resolves CALL.
func emitFuncBody(body, table, localsList, paramCount, funcNames, dummyRet) {
    let combinedCount = localsCount(localsList)
    let kpTmpIdx = combinedCount
    let t0Idx = combinedCount + 1
    let t1Idx = combinedCount + 2
    // Locals declared in the vec = non-param locals + 3 scratch.
    let declLocals = (combinedCount - paramCount) + 3

    // Locals vec: 1 entry, <declLocals> i32 (type 0x7F).
    let bb = b(1) + leb(declLocals) + b(127)

    let n = lineCount(body)
    let i = 0
    let labelStack = ""        // control-flow frame stack (see cfPush): one row per open if
    while i < n {
        let line = ltrim(getLine(body, i))
        if lineStarts(line, "LOCAL ") {
            // Already accounted for in the locals header. No opcode.
        } else if lineStarts(line, "PARAM ") {
            // Function parameter; already a wasm local 0..P-1. No opcode.
        } else if lineStarts(line, "CALL ") {
            // Args already on stack (left-to-right). call <funcidx>.
            bb = bb + iCALL(funcIndexOf(funcNames, callName(line)))
        } else if lineStarts(line, "PUSH \"") {
            let s = strBetweenQuotes(line)
            let h = strTableOffset(table, s)
            bb = bb + iC((h * 2) + 1)           // i32.const (handle<<1)|1
        } else if isPushInt(line) > 0 {
            let v = pushIntVal(line)
            bb = bb + iC(v * 2)                 // i32.const (N<<1)
        } else if lineStarts(line, "STORE ") {
            let name = substring(line, 6, len(line))
            let idx = localsIndex(localsList, name)
            if idx < 0 { idx = kpTmpIdx }
            bb = bb + iLS(idx)                  // local.set
        } else if lineStarts(line, "LOAD ") {
            let name = substring(line, 5, len(line))
            let idx = localsIndex(localsList, name)
            if idx < 0 { idx = kpTmpIdx }
            bb = bb + iLG(idx)                  // local.get
        } else if line == "ADD" {
            // Tag dispatch: if either operand is a pointer (LSB 1) -> $concat,
            // else plain i32.add (two tagged ints sum to a tagged int).
            bb = bb + iLS(t1Idx) + iLS(t0Idx)               // t1=b, t0=a
            bb = bb + iLG(t0Idx) + iLG(t1Idx) + b(114)      // a | b
            bb = bb + iC(1) + b(113)                        // & 1
            bb = bb + b(4) + b(127)                         // if (result i32)
            bb = bb + iLG(t0Idx) + iLG(t1Idx) + iCALL(4)    //   $concat
            bb = bb + b(5)                                  // else
            bb = bb + iLG(t0Idx) + iLG(t1Idx) + b(106)      //   i32.add
            bb = bb + b(11)                                 // end
        } else if line == "SUB" {
            bb = bb + b(107)                    // i32.sub  ((2N)-(2M)=2(N-M))
        } else if line == "MUL" {
            // a * (b>>1): (N<<1)*M = (N*M)<<1.
            bb = bb + iC(1) + b(117) + b(108)  // i32.const 1; shr_s; i32.mul
        } else if line == "DIV" {
            // (a/b)<<1: (2N)/(2M)=N/M, retag.
            bb = bb + b(109) + iC(1) + b(116)  // i32.div_s; i32.const 1; shl
        } else if line == "MOD" {
            bb = bb + b(111)                    // i32.rem_s ((2N)%(2M)=2(N%M))
        } else if line == "EQ" {
            bb = bb + b(70) + iC(1) + b(116)   // i32.eq;   retag <<1 (tagged bool)
        } else if line == "NEQ" {
            bb = bb + b(71) + iC(1) + b(116)   // i32.ne
        } else if line == "LT" {
            bb = bb + b(72) + iC(1) + b(116)   // i32.lt_s
        } else if line == "GT" {
            bb = bb + b(74) + iC(1) + b(116)   // i32.gt_s
        } else if line == "LTE" {
            bb = bb + b(76) + iC(1) + b(116)   // i32.le_s
        } else if line == "GTE" {
            bb = bb + b(78) + iC(1) + b(116)   // i32.ge_s
        } else if lineStarts(line, "BUILTIN kp ") {
            // Tag dispatch on stack top: LSB 1 -> string (console_log),
            // LSB 0 -> int (console_log_int). Push dummy 0 after (IR's
            // "every BUILTIN returns 1 value"); trailing POP drops it.
            bb = bb + iLT(kpTmpIdx) + iC(1) + b(113)        // tee; &1
            bb = bb + b(4) + b(64)                          // if (void)
            bb = bb + iLG(kpTmpIdx) + iC(1) + b(118) + iLS(kpTmpIdx)  // base=v>>1u (set, not tee)
            bb = bb + iLG(kpTmpIdx) + iC(4) + b(106)        // bytes ptr = base+4
            bb = bb + iLG(kpTmpIdx) + b(40) + b(2) + b(0)   // len = i32.load base
            bb = bb + iCALL(0)                              // console_log(ptr,len)
            bb = bb + b(5)                                  // else
            bb = bb + iLG(kpTmpIdx) + iC(1) + b(117) + iCALL(1)  // console_log_int(v>>1s)
            bb = bb + b(11)                                 // end
            // kp is print-with-newline: emit the seeded "\n" (bytes at offset 4).
            bb = bb + iC(4) + iC(1) + iCALL(0)             // console_log(4, 1)
            bb = bb + iC(0)                                 // dummy result
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
        } else if line == "INDEX" {
            bb = bb + iCALL(5)                  // $index(str, idx) -> tagged 1-char str
        } else if lineStarts(line, "BUILTIN len ") {
            // tagged str -> tagged int length. base=v>>1u; load[base]; <<1.
            bb = bb + iC(1) + b(118) + b(40) + b(2) + b(0) + iC(1) + b(116)
        } else if lineStarts(line, "BUILTIN substring ") {
            bb = bb + iCALL(6)                  // $substring(str,start,end)
        } else if lineStarts(line, "BUILTIN startsWith ") {
            bb = bb + iCALL(7)                  // $startsWith(str,prefix) -> tagged bool
        } else if lineStarts(line, "BUILTIN isTruthy ") {
            // tagged v -> tagged bool. kcc -r kr_truthy treats empty string
            // AND int 0 as falsy. Tag dispatch: LSB 0 = int (v != 0),
            // LSB 1 = string (mem[v>>1] (length) != 0).
            bb = bb + iLT(t1Idx) + iC(1) + b(113) + b(69)   // tee t1; & 1; i32.eqz (int path?)
            bb = bb + b(4) + b(127)                          // if (result i32)
            bb = bb + iLG(t1Idx) + iC(0) + b(71)             //   int: v != 0
            bb = bb + b(5)                                   // else
            bb = bb + iLG(t1Idx) + iC(1) + b(118)            //   str: ptr = v>>1
            bb = bb + b(40) + b(2) + b(0) + iC(0) + b(71)    //         len; != 0
            bb = bb + b(11)                                  // end
            bb = bb + iC(1) + b(116)                         // tagged bool: << 1
        } else if lineStarts(line, "BUILTIN toInt ") {
            bb = bb + iCALL(8)                  // $toint(str) -> tagged int
        } else if lineStarts(line, "BUILTIN count ") {
            bb = bb + iCALL(9)                  // $count(str) -> tagged int (comma fields)
        } else if lineStarts(line, "BUILTIN split ") {
            bb = bb + iCALL(10)                 // $split(str, idx) -> tagged string field
        } else if lineStarts(line, "BUILTIN argCount ") {
            // Browser has no CLI args. Always 0 — lessons that gate on
            // `argCount() >= 1` take the else branch (their no-arg help text).
            bb = bb + iC(0)                     // tagged 0
        } else if lineStarts(line, "BUILTIN arg ") {
            // Drop the index and push tagged 0. arg() is only reached when
            // argCount() > 0, which we hard-wire to 0, so this branch is
            // dead code in practice (tag/type don't matter).
            bb = bb + b(26)                     // drop index
            bb = bb + iC(0)                     // tagged 0 (placeholder)
        } else if lineStarts(line, "BUILTIN sbNew ") {
            // String builder = tagged string. New one = empty string at bump:
            // store len 0, bump += 4, push (dst<<1)|1.
            bb = bb + b(35) + leb(0)                       // global.get 0 (dst)
            bb = bb + b(35) + leb(0) + iC(0) + b(54) + b(2) + b(0)  // [dst] = 0
            bb = bb + b(35) + leb(0) + iC(4) + b(106) + b(36) + leb(0)  // bump += 4
            bb = bb + iC(1) + b(116) + iC(1) + b(114)      // (dst<<1)|1
        } else if lineStarts(line, "BUILTIN sbAppend ") {
            bb = bb + iCALL(4)                  // sb + s -> $concat (sb is a tagged string)
        } else if lineStarts(line, "BUILTIN sbToString ") {
            // sb already IS a tagged string; identity (no opcode).
        } else if line == "NOT" {
            // tagged bool of falsiness. Same tag-dispatch as isTruthy:
            // for int, v == 0; for string, mem[v>>1] (length) == 0.
            // kcc -r treats "" as falsy so !"" must yield tagged true.
            bb = bb + iLT(t1Idx) + iC(1) + b(113) + b(69)   // tee t1; & 1; i32.eqz (int path?)
            bb = bb + b(4) + b(127)                          // if (result i32)
            bb = bb + iLG(t1Idx) + b(69)                     //   int: v == 0
            bb = bb + b(5)                                   // else
            bb = bb + iLG(t1Idx) + iC(1) + b(118)            //   str: ptr = v>>1
            bb = bb + b(40) + b(2) + b(0) + b(69)            //         len; i32.eqz
            bb = bb + b(11)                                  // end
            bb = bb + iC(1) + b(116)                         // tagged bool: << 1
        } else if lineStarts(line, "JUMPIFNOT ") {
            let lbl = substring(line, 10, len(line))
            if lineStarts(lbl, "_wend") {
                // Loop exit test: branch out of the enclosing block if !cond.
                bb = bb + b(69)                            // i32.eqz (true=2->0, false=0->1)
                bb = bb + b(13) + leb(cfDepth(labelStack, lbl))  // br_if <block>
            } else if lineStarts(lbl, "_else") {
                // if-else: open `if`; else label recorded, close set later by JUMP.
                bb = bb + b(4) + b(64)                     // if (void)
                labelStack = cfPush(labelStack, "if" + tab() + "-" + tab() + lbl)
            } else if lineStarts(lbl, "_and") {
                // short-circuit AND diamond: value-producing if-else (result i32).
                bb = bb + b(4) + b(127)                    // if (result i32)
                labelStack = cfPush(labelStack, "if" + tab() + "-" + tab() + lbl)
            } else {
                // plain if: skip target is the endif (close) label.
                bb = bb + b(4) + b(64)                     // if (void)
                labelStack = cfPush(labelStack, "if" + tab() + lbl + tab() + "-")
            }
        } else if lineStarts(line, "JUMPIF ") {
            // short-circuit OR diamond: jump-if-true. Invert (eqz) so the wasm
            // then-branch is the fall-through; else-branch is the _or body.
            let lbl = substring(line, 7, len(line))
            bb = bb + b(69) + b(4) + b(127)                // i32.eqz; if (result i32)
            labelStack = cfPush(labelStack, "if" + tab() + "-" + tab() + lbl)
        } else if lineStarts(line, "JUMP ") {
            let lbl = substring(line, 5, len(line))
            if lineStarts(lbl, "_wloop") {
                bb = bb + b(12) + leb(cfDepth(labelStack, lbl))  // br <loop> (continue)
            } else if lineStarts(lbl, "_wend") {
                bb = bb + b(12) + leb(cfDepth(labelStack, lbl))  // br <block> (break)
            } else {
                // then-branch end of an if-else: emit `else`, record endif as close.
                bb = bb + b(5)                             // else
                labelStack = cfSetClose(labelStack, lbl)
            }
        } else if lineStarts(line, "LABEL ") {
            let lbl = substring(line, 6, len(line))
            if lineStarts(lbl, "_wloop") {
                // Loop start: outer block (exit target) + inner loop (continue).
                let wend = "_wend_" + substring(lbl, 7, len(lbl))
                bb = bb + b(2) + b(64)                     // block (void)
                bb = bb + b(3) + b(64)                     // loop (void)
                labelStack = cfPush(labelStack, "blk" + tab() + wend + tab() + "-")
                labelStack = cfPush(labelStack, "lp" + tab() + lbl + tab() + "-")
            } else if lineStarts(lbl, "_wend") {
                bb = bb + b(11) + b(11)                    // end loop; end block
                labelStack = cfDrop(labelStack)
                labelStack = cfDrop(labelStack)
            } else {
                let top = cfTop(labelStack)
                if len(top) > 0 {
                    if lbl == cfField(top, 2) {
                        // if-else else label; `else` already emitted by JUMP -> consume.
                    } else if lbl == cfField(top, 1) {
                        bb = bb + b(11)                    // end (close if/if-else)
                        labelStack = cfDrop(labelStack)
                    }
                }
            }
        } else if line == "POP" {
            bb = bb + b(26)                     // drop
        } else if line == "RETURN" {
            bb = bb + b(15)                     // return
        }
        // Unhandled IR ops are skipped silently. Track them in 1.4.
        i += 1
    }
    // Non-main user funcs are typed ->i32 so callers can always POP/drop the
    // result. Void funcs (no RETURN) fall through here with empty stack, so
    // leave a dummy i32. Value funcs reach here only after RETURN (unreachable),
    // so the extra const is harmless and keeps the fallthru well-typed.
    if dummyRet > 0 { bb = bb + iC(0) }
    bb = bb + b(11)                             // end
    emit bb
}

// ── Opcode shorthands (variable-operand ops; single-byte ops use b()) ─
func iLG(i)   { emit b(32) + leb(i) }      // local.get
func iLS(i)   { emit b(33) + leb(i) }      // local.set
func iLT(i)   { emit b(34) + leb(i) }      // local.tee
func iC(v)    { emit b(65) + sleb(v) }     // i32.const (signed LEB, non-neg)
func iCALL(i) { emit b(16) + leb(i) }      // call

// ── Runtime helper functions (hand-emitted wasm) ─────────────────────
// Function index map: 0 console_log(import), 1 console_log_int(import),
// 2 $int2str, 3 $tostr, 4 $concat, 5+ user funcs. global 0 = bump pointer.
// Single-byte opcodes used below:
//   load i32 = 28/02/00, load8_u = 2d/00/00, store i32 = 36/02/00,
//   store8 = 3a/00/00, add 6a sub 6b mul 6c div_u 6e rem_u 70,
//   and 71 or 72 shl 74 shr_s 75 shr_u 76, eqz 45 lt_s 48 ge_u 4f,
//   if 04 (40 void / 7f i32) else 05 end 0b block 02/40 loop 03/40
//   br 0c brif 0d. global.get 23/00 global.set 24/00.

// $int2str(n:i32) -> i32 base ptr to [len:u32][ascii]. param 0 = n.
// Locals: 1 neg, 2 cnt, 3 len, 4 dst, 5 pos, 6 t.
func emitInt2Str() {
    let bb = b(1) + leb(6) + b(127)                    // 6 i32 locals
    // if n < 0 { neg=1; n = 0 - n }
    bb = bb + iLG(0) + iC(0) + b(72)                   // n < 0  (lt_s)
    bb = bb + b(4) + b(64)
    bb = bb + iC(1) + iLS(1)                           // neg = 1
    bb = bb + iC(0) + iLG(0) + b(107) + iLS(0)         // n = 0 - n
    bb = bb + b(11)
    // count digits -> cnt
    bb = bb + iLG(0) + b(69)                           // n == 0 (eqz)
    bb = bb + b(4) + b(64)
    bb = bb + iC(1) + iLS(2)                           // cnt = 1
    bb = bb + b(5)                                     // else
    bb = bb + iLG(0) + iLS(6)                          // t = n
    bb = bb + b(2) + b(64) + b(3) + b(64)             // block; loop
    bb = bb + iLG(6) + b(69) + b(13) + leb(1)          // if t==0 br 1 (exit)
    bb = bb + iLG(2) + iC(1) + b(106) + iLS(2)         // cnt++
    bb = bb + iLG(6) + iC(10) + b(110) + iLS(6)        // t /= 10 (div_u)
    bb = bb + b(12) + leb(0)                           // br 0 (loop)
    bb = bb + b(11) + b(11)                            // end loop; end block
    bb = bb + b(11)                                    // end if
    // len = cnt + neg
    bb = bb + iLG(2) + iLG(1) + b(106) + iLS(3)
    // dst = bump
    bb = bb + b(35) + leb(0) + iLS(4)                  // global.get 0
    // store len u32 at dst
    bb = bb + iLG(4) + iLG(3) + b(54) + b(2) + b(0)    // i32.store
    // if neg: store '-' (45) at dst+4
    bb = bb + iLG(1) + b(4) + b(64)
    bb = bb + iLG(4) + iC(4) + b(106) + iC(45) + b(58) + b(0) + b(0)  // store8
    bb = bb + b(11)
    // pos = dst + 4 + len
    bb = bb + iLG(4) + iC(4) + b(106) + iLG(3) + b(106) + iLS(5)
    // fill digits
    bb = bb + iLG(0) + b(69)                           // n == 0
    bb = bb + b(4) + b(64)
    bb = bb + iLG(5) + iC(1) + b(107) + iC(48) + b(58) + b(0) + b(0)  // buf[pos-1]='0'
    bb = bb + b(5)                                     // else
    bb = bb + iLG(0) + iLS(6)                          // t = n
    bb = bb + b(2) + b(64) + b(3) + b(64)             // block; loop
    bb = bb + iLG(6) + b(69) + b(13) + leb(1)          // if t==0 br 1
    bb = bb + iLG(5) + iC(1) + b(107) + iLS(5)         // pos--
    bb = bb + iLG(5)                                   // addr = pos
    bb = bb + iLG(6) + iC(10) + b(112) + iC(48) + b(106)  // '0' + t%10 (rem_u)
    bb = bb + b(58) + b(0) + b(0)                      // store8
    bb = bb + iLG(6) + iC(10) + b(110) + iLS(6)        // t /= 10
    bb = bb + b(12) + leb(0)                           // br 0
    bb = bb + b(11) + b(11)                            // end loop; end block
    bb = bb + b(11)                                    // end if
    // bump = dst + 4 + len
    bb = bb + iLG(4) + iC(4) + b(106) + iLG(3) + b(106) + b(36) + leb(0)  // global.set 0
    // return dst
    bb = bb + iLG(4)
    bb = bb + b(11)                                    // end func
    emit bb
}

// $index(str,idx) -> tagged 1-char string. params 0=str,1=idx.
// locals: 2 base, 3 i, 4 dst, 5 byte.
func emitIndex() {
    let bb = b(1) + leb(4) + b(127)
    bb = bb + iLG(0) + iC(1) + b(118) + iLS(2)          // base = str>>1
    bb = bb + iLG(1) + iC(1) + b(117) + iLS(3)          // i = idx>>1
    bb = bb + iLG(2) + iC(4) + b(106) + iLG(3) + b(106) // base+4+i
    bb = bb + b(45) + b(0) + b(0) + iLS(5)              // byte = load8_u
    bb = bb + b(35) + leb(0) + iLS(4)                   // dst = bump
    bb = bb + iLG(4) + iC(1) + b(54) + b(2) + b(0)      // [dst] = 1
    bb = bb + iLG(4) + iC(4) + b(106) + iLG(5) + b(58) + b(0) + b(0)  // [dst+4]=byte
    bb = bb + b(35) + leb(0) + iC(5) + b(106) + b(36) + leb(0)        // bump += 5
    bb = bb + iLG(4) + iC(1) + b(116) + iC(1) + b(114)  // (dst<<1)|1
    bb = bb + b(11)
    emit bb
}

// $substring(str,start,end) -> tagged string. params 0=str,1=start,2=end.
// locals: 3 base, 4 s, 5 e, 6 n, 7 dst, 8 i.
func emitSubstr() {
    let bb = b(1) + leb(6) + b(127)
    bb = bb + iLG(0) + iC(1) + b(118) + iLS(3)          // base
    bb = bb + iLG(1) + iC(1) + b(117) + iLS(4)          // s
    bb = bb + iLG(2) + iC(1) + b(117) + iLS(5)          // e
    bb = bb + iLG(5) + iLG(4) + b(107) + iLS(6)         // n = e - s
    bb = bb + b(35) + leb(0) + iLS(7)                   // dst = bump
    bb = bb + iLG(7) + iLG(6) + b(54) + b(2) + b(0)     // [dst] = n
    bb = bb + iC(0) + iLS(8)                            // i = 0
    bb = bb + b(2) + b(64) + b(3) + b(64)               // block; loop
    bb = bb + iLG(8) + iLG(6) + b(79) + b(13) + leb(1)  // i>=n br 1
    bb = bb + iLG(7) + iC(4) + b(106) + iLG(8) + b(106) // dst+4+i
    bb = bb + iLG(3) + iC(4) + b(106) + iLG(4) + b(106) + iLG(8) + b(106) + b(45) + b(0) + b(0)  // load8 base+4+s+i
    bb = bb + b(58) + b(0) + b(0)                       // store8
    bb = bb + iLG(8) + iC(1) + b(106) + iLS(8)          // i++
    bb = bb + b(12) + leb(0)                            // br 0
    bb = bb + b(11) + b(11)                             // end loop; block
    bb = bb + b(35) + leb(0) + iC(4) + b(106) + iLG(6) + b(106) + b(36) + leb(0)  // bump += 4+n
    bb = bb + iLG(7) + iC(1) + b(116) + iC(1) + b(114) // (dst<<1)|1
    bb = bb + b(11)
    emit bb
}

// $startsWith(str,prefix) -> tagged bool. params 0=str,1=prefix.
// locals: 2 sb, 3 pb, 4 sl, 5 pl, 6 i, 7 res.
func emitStartsWith() {
    let bb = b(1) + leb(6) + b(127)
    bb = bb + iLG(0) + iC(1) + b(118) + iLS(2)          // sb = str>>1
    bb = bb + iLG(1) + iC(1) + b(118) + iLS(3)          // pb = prefix>>1
    bb = bb + iLG(2) + b(40) + b(2) + b(0) + iLS(4)     // sl = load[sb]
    bb = bb + iLG(3) + b(40) + b(2) + b(0) + iLS(5)     // pl = load[pb]
    bb = bb + iC(1) + iLS(7)                            // res = 1
    bb = bb + iLG(5) + iLG(4) + b(74)                   // pl > sl (gt_s)
    bb = bb + b(4) + b(64)                              // if
    bb = bb + iC(0) + iLS(7)                            //   res = 0
    bb = bb + b(5)                                      // else
    bb = bb + iC(0) + iLS(6)                            //   i = 0
    bb = bb + b(2) + b(64) + b(3) + b(64)               //   block; loop
    bb = bb + iLG(6) + iLG(5) + b(79) + b(13) + leb(1)  //   i>=pl br 1
    bb = bb + iLG(2) + iC(4) + b(106) + iLG(6) + b(106) + b(45) + b(0) + b(0)  // s[i]
    bb = bb + iLG(3) + iC(4) + b(106) + iLG(6) + b(106) + b(45) + b(0) + b(0)  // p[i]
    bb = bb + b(71)                                     //   ne
    bb = bb + b(4) + b(64)                              //   if
    bb = bb + iC(0) + iLS(7) + b(12) + leb(2)           //     res=0; br 2 (exit block)
    bb = bb + b(11)                                     //   end if
    bb = bb + iLG(6) + iC(1) + b(106) + iLS(6)          //   i++
    bb = bb + b(12) + leb(0)                            //   br 0
    bb = bb + b(11) + b(11)                             //   end loop; block
    bb = bb + b(11)                                     // end if/else
    bb = bb + iLG(7) + iC(1) + b(116)                   // res<<1 (tagged)
    bb = bb + b(11)
    emit bb
}

// $toint(v:i32 tagged string) -> tagged int. param 0=v.
// locals: 1 base, 2 len, 3 i, 4 acc, 5 neg, 6 ch.
func emitToInt() {
    let bb = b(1) + leb(6) + b(127)
    bb = bb + iLG(0) + iC(1) + b(118) + iLS(1)         // base = v>>1u
    bb = bb + iLG(1) + b(40) + b(2) + b(0) + iLS(2)    // len = load[base]
    bb = bb + iC(0) + iLS(4)                           // acc = 0
    bb = bb + iC(0) + iLS(5)                           // neg = 0
    bb = bb + iC(0) + iLS(3)                           // i = 0
    // leading '-'?
    bb = bb + iLG(2) + iC(0) + b(74)                   // len > 0 (gt_s)
    bb = bb + b(4) + b(64)                             // if
    bb = bb + iLG(1) + iC(4) + b(106) + b(45) + b(0) + b(0) + iC(45) + b(70)  // base+4 load8 == '-'
    bb = bb + b(4) + b(64)                             //   if
    bb = bb + iC(1) + iLS(5) + iC(1) + iLS(3)          //     neg=1; i=1
    bb = bb + b(11) + b(11)                            //   end; end
    // loop: while i<len { acc = acc*10 + digit }
    bb = bb + b(2) + b(64) + b(3) + b(64)              // block; loop
    bb = bb + iLG(3) + iLG(2) + b(78) + b(13) + leb(1) // i>=len (ge_s) br 1
    bb = bb + iLG(1) + iC(4) + b(106) + iLG(3) + b(106) + b(45) + b(0) + b(0) + iLS(6)  // ch = load8[base+4+i]
    bb = bb + iLG(6) + iC(48) + b(78)                  // ch >= '0'
    bb = bb + iLG(6) + iC(57) + b(76)                  // ch <= '9'
    bb = bb + b(113)                                   // and
    bb = bb + b(4) + b(64)                             // if (valid digit)
    bb = bb + iLG(4) + iC(10) + b(108) + iLG(6) + b(106) + iC(48) + b(107) + iLS(4)  // acc = acc*10 + ch - 48
    bb = bb + b(11)                                    // end if
    bb = bb + iLG(3) + iC(1) + b(106) + iLS(3)         // i++
    bb = bb + b(12) + leb(0)                           // br 0
    bb = bb + b(11) + b(11)                            // end loop; end block
    // neg?
    bb = bb + iLG(5) + b(4) + b(64)                    // if neg
    bb = bb + iC(0) + iLG(4) + b(107) + iLS(4)         //   acc = 0 - acc
    bb = bb + b(11)                                    // end
    bb = bb + iLG(4) + iC(1) + b(116)                  // acc << 1 (tagged int)
    bb = bb + b(11)                                    // end func
    emit bb
}

// $count(str) -> tagged int = number of comma-separated fields (commas+1).
// Empty string -> 1 field. param 0=str. locals: 1 base,2 len,3 i,4 cnt.
func emitCount() {
    let bb = b(1) + leb(4) + b(127)
    bb = bb + iLG(0) + iC(1) + b(118) + iLS(1)         // base = str>>1
    bb = bb + iLG(1) + b(40) + b(2) + b(0) + iLS(2)    // len = load[base]
    bb = bb + iC(1) + iLS(4)                           // cnt = 1
    bb = bb + iC(0) + iLS(3)                           // i = 0
    bb = bb + b(2) + b(64) + b(3) + b(64)              // block; loop
    bb = bb + iLG(3) + iLG(2) + b(78) + b(13) + leb(1) // i>=len br 1
    bb = bb + iLG(1) + iC(4) + b(106) + iLG(3) + b(106) + b(45) + b(0) + b(0)  // load8 base+4+i
    bb = bb + iC(44) + b(70)                           // == ',' (44)
    bb = bb + b(4) + b(64)                             // if
    bb = bb + iLG(4) + iC(1) + b(106) + iLS(4)         //   cnt++
    bb = bb + b(11)                                    // end if
    bb = bb + iLG(3) + iC(1) + b(106) + iLS(3)         // i++
    bb = bb + b(12) + leb(0)                           // br 0
    bb = bb + b(11) + b(11)                            // end loop; block
    bb = bb + iLG(4) + iC(1) + b(116)                  // cnt << 1
    bb = bb + b(11)
    emit bb
}

// $split(str, idx) -> tagged string = the idx-th comma field. params 0=str,1=idx.
// locals: 2 base,3 len,4 want,5 field,6 i,7 s (field start),8 dst,9 j.
func emitSplit() {
    let bb = b(1) + leb(8) + b(127)
    bb = bb + iLG(0) + iC(1) + b(118) + iLS(2)         // base = str>>1
    bb = bb + iLG(2) + b(40) + b(2) + b(0) + iLS(3)    // len = load[base]
    bb = bb + iLG(1) + iC(1) + b(117) + iLS(4)         // want = idx>>1
    bb = bb + iC(0) + iLS(5)                           // field = 0
    bb = bb + iC(0) + iLS(7)                           // s = 0 (current field start)
    bb = bb + iC(0) + iLS(6)                           // i = 0
    // scan to the start of field `want`; s = start, then find its end.
    bb = bb + b(2) + b(64) + b(3) + b(64)              // block; loop  (find start)
    bb = bb + iLG(5) + iLG(4) + b(78) + b(13) + leb(1) // field>=want br 1 (found start at s)
    bb = bb + iLG(6) + iLG(3) + b(78) + b(13) + leb(1) // i>=len br 1 (ran out)
    bb = bb + iLG(2) + iC(4) + b(106) + iLG(6) + b(106) + b(45) + b(0) + b(0)  // load8 base+4+i
    bb = bb + iC(44) + b(70)                           // == ','
    bb = bb + b(4) + b(64)
    bb = bb + iLG(5) + iC(1) + b(106) + iLS(5)         //   field++
    bb = bb + iLG(6) + iC(1) + b(106) + iLS(7)         //   s = i+1
    bb = bb + b(11)
    bb = bb + iLG(6) + iC(1) + b(106) + iLS(6)         // i++
    bb = bb + b(12) + leb(0)
    bb = bb + b(11) + b(11)
    // now s = start of wanted field; find end e: first ',' at/after s, or len.
    bb = bb + iLG(7) + iLS(6)                          // i = s
    bb = bb + b(2) + b(64) + b(3) + b(64)              // block; loop (find end)
    bb = bb + iLG(6) + iLG(3) + b(78) + b(13) + leb(1) // i>=len br 1
    bb = bb + iLG(2) + iC(4) + b(106) + iLG(6) + b(106) + b(45) + b(0) + b(0)
    bb = bb + iC(44) + b(70)
    bb = bb + b(13) + leb(1)                           // br_if 1 (hit ',')
    bb = bb + iLG(6) + iC(1) + b(106) + iLS(6)         // i++
    bb = bb + b(12) + leb(0)
    bb = bb + b(11) + b(11)
    // field length = i - s ; copy [base+4+s .. base+4+i) to dst+4
    bb = bb + iLG(6) + iLG(7) + b(107) + iLS(5)        // field(len) = i - s
    bb = bb + b(35) + leb(0) + iLS(8)                  // dst = bump
    bb = bb + iLG(8) + iLG(5) + b(54) + b(2) + b(0)    // [dst] = field len
    bb = bb + iC(0) + iLS(9)                           // j = 0
    bb = bb + b(2) + b(64) + b(3) + b(64)
    bb = bb + iLG(9) + iLG(5) + b(79) + b(13) + leb(1) // j>=field (ge_u) br 1
    bb = bb + iLG(8) + iC(4) + b(106) + iLG(9) + b(106)        // dst+4+j
    bb = bb + iLG(2) + iC(4) + b(106) + iLG(7) + b(106) + iLG(9) + b(106) + b(45) + b(0) + b(0)  // load8 base+4+s+j
    bb = bb + b(58) + b(0) + b(0)
    bb = bb + iLG(9) + iC(1) + b(106) + iLS(9)         // j++
    bb = bb + b(12) + leb(0)
    bb = bb + b(11) + b(11)
    bb = bb + b(35) + leb(0) + iC(4) + b(106) + iLG(5) + b(106) + b(36) + leb(0)  // bump += 4+field
    bb = bb + iLG(8) + iC(1) + b(116) + iC(1) + b(114) // (dst<<1)|1
    bb = bb + b(11)
    emit bb
}

// $tostr(v:i32 tagged) -> i32 base ptr. param 0 = v. No extra locals.
func emitToStr() {
    let bb = b(0)                                      // 0 local groups
    bb = bb + iLG(0) + iC(1) + b(113)                 // v & 1
    bb = bb + b(4) + b(127)                            // if (result i32)
    bb = bb + iLG(0) + iC(1) + b(118)                 //   v >> 1 (unsigned) = ptr
    bb = bb + b(5)                                     // else
    bb = bb + iLG(0) + iC(1) + b(117) + iCALL(2)      //   $int2str(v>>1 signed)
    bb = bb + b(11)                                    // end if
    bb = bb + b(11)                                    // end func
    emit bb
}

// $concat(a:i32, b:i32) -> i32 tagged string. params 0=a, 1=b.
// Locals: 2 pa, 3 pb, 4 la, 5 lb, 6 dst, 7 i.
func emitConcat() {
    let bb = b(1) + leb(6) + b(127)                    // 6 i32 locals
    bb = bb + iLG(0) + iCALL(3) + iLS(2)              // pa = $tostr(a)
    bb = bb + iLG(1) + iCALL(3) + iLS(3)              // pb = $tostr(b)
    bb = bb + iLG(2) + b(40) + b(2) + b(0) + iLS(4)   // la = load[pa]
    bb = bb + iLG(3) + b(40) + b(2) + b(0) + iLS(5)   // lb = load[pb]
    bb = bb + b(35) + leb(0) + iLS(6)                 // dst = bump
    // store len = la+lb at dst
    bb = bb + iLG(6) + iLG(4) + iLG(5) + b(106) + b(54) + b(2) + b(0)
    // copy a: i=0; while i<la
    bb = bb + iC(0) + iLS(7)
    bb = bb + b(2) + b(64) + b(3) + b(64)
    bb = bb + iLG(7) + iLG(4) + b(79) + b(13) + leb(1)   // i>=la (ge_u) br 1
    bb = bb + iLG(6) + iC(4) + b(106) + iLG(7) + b(106)  // dst+4+i
    bb = bb + iLG(2) + iC(4) + b(106) + iLG(7) + b(106) + b(45) + b(0) + b(0)  // load8 pa+4+i
    bb = bb + b(58) + b(0) + b(0)                        // store8
    bb = bb + iLG(7) + iC(1) + b(106) + iLS(7)           // i++
    bb = bb + b(12) + leb(0)
    bb = bb + b(11) + b(11)
    // copy b: i=0; while i<lb
    bb = bb + iC(0) + iLS(7)
    bb = bb + b(2) + b(64) + b(3) + b(64)
    bb = bb + iLG(7) + iLG(5) + b(79) + b(13) + leb(1)   // i>=lb br 1
    bb = bb + iLG(6) + iC(4) + b(106) + iLG(4) + b(106) + iLG(7) + b(106)  // dst+4+la+i
    bb = bb + iLG(3) + iC(4) + b(106) + iLG(7) + b(106) + b(45) + b(0) + b(0)  // load8 pb+4+i
    bb = bb + b(58) + b(0) + b(0)                        // store8
    bb = bb + iLG(7) + iC(1) + b(106) + iLS(7)           // i++
    bb = bb + b(12) + leb(0)
    bb = bb + b(11) + b(11)
    // bump = dst + 4 + la + lb
    bb = bb + iLG(6) + iC(4) + b(106) + iLG(4) + b(106) + iLG(5) + b(106) + b(36) + leb(0)
    // return (dst<<1)|1
    bb = bb + iLG(6) + iC(1) + b(116) + iC(1) + b(114)
    bb = bb + b(11)                                      // end func
    emit bb
}

// ── Section builders ─────────────────────────────────────────────────

func wasmTypes() {
    let payload =
        b(7) +
        b(96) + b(2) + b(127) + b(127) + b(0) +            // 0 (i32,i32)->void
        b(96) + b(0) + b(0) +                              // 1 ()->void
        b(96) + b(1) + b(127) + b(0) +                     // 2 (i32)->void
        b(96) + b(1) + b(127) + b(1) + b(127) +            // 3 (i32)->i32
        b(96) + b(2) + b(127) + b(127) + b(1) + b(127) +   // 4 (i32,i32)->i32
        b(96) + b(3) + b(127) + b(127) + b(127) + b(1) + b(127) +  // 5 (i32,i32,i32)->i32
        b(96) + b(0) + b(1) + b(127)                       // 6 ()->i32
    emit wasmSection(1, payload)
}

func wasmImports() {
    let payload =
        b(2) +
        b(3) + bstr("env") + b(11) + bstr("console_log")     + b(0) + b(0) +
        b(3) + bstr("env") + b(15) + bstr("console_log_int") + b(0) + b(2)
    emit wasmSection(2, payload)
}

// Map (paramCount, returnsVal) -> a type index from wasmTypes().
// types: 0 (i32,i32)->void, 1 ()->void, 2 (i32)->void, 3 (i32)->i32,
//        4 (i32,i32)->i32, 5 (i32,i32,i32)->i32.
func userFuncType(p, r) {
    if r == 0 {
        if p == 0 { emit 1 }
        if p == 1 { emit 2 }
        if p == 2 { emit 0 }
        emit 1
    }
    if p == 0 { emit 6 }         // ()->i32
    if p == 1 { emit 3 }
    if p == 2 { emit 4 }
    if p == 3 { emit 5 }
    emit 3                       // fallback: (i32)->i32
}

// Defined funcs (9 helpers + user funcs). Helper type indices in
// func-index order: 2 int2str:t3, 3 tostr:t3, 4 concat:t4, 5 index:t4,
// 6 substr:t5, 7 startsWith:t4, 8 toint:t3, 9 count:t3, 10 split:t4.
// funcSigs = "P,R" per user func.
func wasmFuncs(funcSigs) {
    let cnt = lineCount(funcSigs)
    let payload = leb(9 + cnt) +
                  b(3) + b(3) + b(4) + b(4) + b(5) + b(4) + b(3) + b(3) + b(4)
    let i = 0
    while i < cnt {
        let row = getLine(funcSigs, i)
        let cpos = indexOf(row, ",")
        let p = toInt(substring(row, 0, cpos))
        let r = toInt(substring(row, cpos + 1, len(row)))
        payload = payload + b(userFuncType(p, r))
        i += 1
    }
    emit wasmSection(3, payload)
}

// Global 0: mutable i32 bump pointer, init to end of static string data.
func wasmGlobals(bumpStart) {
    let payload =
        b(1) +
        b(127) + b(1) +                       // i32, mutable
        b(65) + sleb(bumpStart) + b(11)       // init: i32.const bumpStart; end
    emit wasmSection(6, payload)
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

// Parse "FUNC name P" -> name (token after FUNC, before next space).
func funcLineName(line) {
    let rest = substring(line, 5, len(line))
    let sp = indexOf(rest, " ")
    if sp > 0 { emit substring(rest, 0, sp) }
    emit rest
}

func buildModule(ir) {
    let n = lineCount(ir)

    // Pass 1: collect all user func names (in order) for CALL resolution.
    let funcNames = ""
    let i = 0
    while i < n {
        let line = ltrim(getLine(ir, i))
        if lineStarts(line, "FUNC ") {
            funcNames = nameListJoin(funcNames, funcLineName(line))
        }
        i += 1
    }

    // Pass 2: emit each func body; collect string table, signatures, mainIdx.
    let strTab = strTableNew()
    let funcBodies = ""
    let funcSigs = ""           // newline list of "P,R" per user func
    let mainIdx = 0
    let fIdx = 0
    i = 0
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
            let params = collectParams(body)
            let pCount = localsCount(params)
            let combined = nameListJoin(params, collectLocals(body))
            let isMain = 0
            if funcLineName(line) == "__main__" { isMain = 1 }
            // All non-main funcs return i32 (void ones leave a dummy) so every
            // CALL leaves exactly one value for the IR's trailing POP.
            let rVal = 0
            if isMain == 0 { rVal = 1 }
            let hex = emitFuncBody(body, strTab, combined, pCount, funcNames, rVal)
            if len(funcBodies) == 0 { funcBodies = hex }
            else                    { funcBodies = funcBodies + fromCharCode(10) + hex }
            let sig = pCount + "," + rVal
            if len(funcSigs) == 0 { funcSigs = sig }
            else                  { funcSigs = funcSigs + fromCharCode(10) + sig }
            if isMain == 1 { mainIdx = fIdx + 11 }  // 2 imports + 9 helpers
            fIdx += 1
        } else {
            i += 1
        }
    }

    let blob = strTableBlob(strTab)
    let bumpStart = strBase() + strTableUsed(strTab)   // +5 for fixed newline string

    // Prepend the 3 runtime helper bodies (indices 2,3,4) to the user funcs.
    let helperBodies = emitInt2Str()    + fromCharCode(10) +
                       emitToStr()      + fromCharCode(10) +
                       emitConcat()     + fromCharCode(10) +
                       emitIndex()      + fromCharCode(10) +
                       emitSubstr()     + fromCharCode(10) +
                       emitStartsWith() + fromCharCode(10) +
                       emitToInt()      + fromCharCode(10) +
                       emitCount()      + fromCharCode(10) +
                       emitSplit()
    let allBodies = helperBodies
    if len(funcBodies) > 0 { allBodies = helperBodies + fromCharCode(10) + funcBodies }

    emit wasmHeader() +
         wasmTypes() +
         wasmImports() +
         wasmFuncs(funcSigs) +
         wasmMemory() +
         wasmGlobals(bumpStart) +
         wasmExports(mainIdx) +
         wasmCode(allBodies) +
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
