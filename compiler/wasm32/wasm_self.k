// wasm_self.k — Krypton-to-WebAssembly backend (Phase 1.0 skeleton).
//
// Pipeline:
//   .k → kcc IR → wasm_self.k → .wasm
//
// Status (2026-05-30):
//   Phase 1.0  ✅ skeleton + emit helpers + empty module output
//   Phase 1.1  ⏳ Type/Import/Function/Memory/Export sections from IR
//   Phase 1.2  ⏳ Constants, arithmetic, kp() → console_log
//   Phase 1.3  ⏳ Function decls + locals + return
//   Phase 1.4  ⏳ if/while/for control flow
//   Phase 1.5  ⏳ Strings + dynamic dispatch (tagged-pointer encoding)
//   Phase 1.6  ⏳ Stdlib subset (len, listNew, mapNew, ...)
//   Phase 1.7  ⏳ End-to-end: tutorials 1-13 produce running .wasm
//
// See docs/wasm_backend_design.md for the full plan.

module wasm_self

// ── Byte-emit helpers ────────────────────────────────────────────────
// Lifted from wasm_proof/hello_wasm.htk. Every byte goes through
// hexByte → "xHH"; the final writeBytes() decodes hex pairs into raw
// bytes (avoids Krypton's C-string null-terminator issue).

func hexByte(n) {
    let HEX = "0123456789ABCDEF"
    let v = toInt(n)
    if v < 0 { v = v + 256 }
    if v > 255 { v = v % 256 }
    emit "x" + HEX[v / 16] + HEX[v % 16]
}

// One-byte shorthand. Every section helper uses this.
func b(n) { emit hexByte(n) }

// Count actual bytes encoded by a hex-string (each byte = 3 hex chars).
func hexBytes(s) { emit len(s) / 3 }

// LEB128 unsigned encoding. Used for every WASM length / index.
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

// Encode ASCII string as hex bytes. Caller passes only ASCII.
func bstr(s) {
    let out = sbNew()
    let i = 0
    while i < len(s) {
        out = sbAppend(out, hexByte(toInt(charCode(s[i]))))
        i += 1
    }
    emit sbToString(out)
}

// Section: 1-byte ID + LEB128 payload-length + payload bytes.
func wasmSection(id, payload) {
    emit b(id) + leb(hexBytes(payload)) + payload
}

// Magic "\0asm" + version 1.
func wasmHeader() {
    emit b(0) + b(97) + b(115) + b(109) +
         b(1) + b(0) + b(0) + b(0)
}

// ── Section builders (Phase 1.0 stubs; expand in 1.1+) ───────────────

// Type section. For Phase 1.0 we ship two function types:
//   type 0: (i32, i32) -> ()    matches env.console_log
//   type 1: () -> ()            matches _start
func wasmTypes() {
    let payload =
        b(2) +
        b(96) + b(2) + b(127) + b(127) + b(0) +
        b(96) + b(0) + b(0)
    emit wasmSection(1, payload)
}

// Import section. env.console_log (i32, i32) → ().
// In Phase 1.2 we'll add console_log_int, console_log_f64, and host fetch.
func wasmImports() {
    let payload =
        b(1) +
        b(3) + bstr("env") +
        b(11) + bstr("console_log") +
        b(0) + b(0)
    emit wasmSection(2, payload)
}

// Function section. One function, signature type 1 (() -> ()).
// Phase 1.3 walks the IR and emits one entry per Krypton func.
func wasmFuncs() {
    let payload = b(1) + b(1)
    emit wasmSection(3, payload)
}

// Memory section. One memory, no max, initial = 1 page (64 KB).
// Phase 1.5 may set a higher initial for programs with large data.
func wasmMemory() {
    let payload = b(1) + b(0) + b(1)
    emit wasmSection(5, payload)
}

// Export section. memory + _start. Tutorial _start is the body of
// `just run { ... }`; user funcs are not exported by default.
func wasmExports() {
    let payload =
        b(2) +
        b(6) + bstr("memory") + b(2) + b(0) +
        b(6) + bstr("_start") + b(0) + b(1)
    emit wasmSection(7, payload)
}

// Code section. For Phase 1.0 this is just the Phase 0 body: push (0, 5),
// call console_log, end. Phase 1.2 starts emitting real IR translations.
func wasmCode() {
    let body =
        b(0) +                    // locals count
        b(65) + b(0) +            // i32.const 0   (ptr)
        b(65) + b(5) +            // i32.const 5   (len)
        b(16) + b(0) +            // call 0
        b(11)                     // end
    let payload = b(1) + leb(hexBytes(body)) + body
    emit wasmSection(10, payload)
}

// Data section. "Hello" at offset 0. Phase 1.5 lays out a real string
// table here; for now this is the Phase 0 proof.
func wasmData() {
    let payload =
        b(1) +
        b(0) +
        b(65) + b(0) + b(11) +
        b(5) +
        bstr("Hello")
    emit wasmSection(11, payload)
}

// ── Driver ───────────────────────────────────────────────────────────

// Build a complete .wasm module from the IR text. Phase 1.0 ignores the
// IR and produces the same 95-byte "Hello" module the Phase 0 proof did.
// Phase 1.1 starts parsing FUNC blocks and emitting per-function code.
func buildModule(irText) {
    emit wasmHeader() +
         wasmTypes() +
         wasmImports() +
         wasmFuncs() +
         wasmMemory() +
         wasmExports() +
         wasmCode() +
         wasmData()
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
