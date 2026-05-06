// lsp/kls.k — Krypton Language Server (sessions 1+2).
//
// Speaks LSP 3.17 over stdio. Capabilities advertised so far:
//   - textDocumentSync          : full (didOpen / didChange / didClose)
//   - publishDiagnostics        : tokenizer + structural validator
//   - documentSymbolProvider    : top-level decls (func/struct/module/let)
//   - completionProvider        : keywords + builtins + buffer funcs
//
// Build (C path, since stdin needs cfunc):
//   kcc.exe --headers headers/ lsp/kls.k > lsp/_kls.c
//   gcc lsp/_kls.c -o kls.exe -w
//
// See lsp/build.bat.

import "lex.k"
import "validate.k"
import "symbols.k"
import "complete.k"
import "json_parse.k"
import "json_emit.k"
import "jsonrpc.k"

// ── Document table (URI → buffer text) ──────────────────────────
//
// Uses json_parse's jmSet/jmGet — the C-path mapSet builtin uses a
// flat comma list which corrupts when values contain commas (and
// Krypton source code is full of them).

func docPut(docs, uri, text) {
    emit jmSet(docs, "doc\t" + uri, text)
}

func docGet(docs, uri) {
    emit jmGet(docs, "doc\t" + uri)
}

func docDel(docs, uri) {
    emit jmSet(docs, "doc\t" + uri, "")
}

// ── lspTokenize result splitter ─────────────────────────────────
//
// `lspTokenize` returns "tokens<lxSep()>diagnostics". Pull either half.

func tokensOf(r) {
    let sepCh = lxSep()
    let i = 0
    while i < len(r) {
        if r[i] == sepCh { emit substring(r, 0, i) }
        i += 1
    }
    emit r
}

func diagsOf(r) {
    let sepCh = lxSep()
    let i = 0
    while i < len(r) {
        if r[i] == sepCh { emit substring(r, i + 1, len(r)) }
        i += 1
    }
    emit ""
}

// ── Diagnostic row (TAB-encoded) → JSON Diagnostic ──────────────

func diagField(row, idx) {
    let n = len(row)
    let i = 0
    let cur = 0
    let start = 0
    while i < n {
        if row[i] == "\t" {
            if cur == idx { emit substring(row, start, i) }
            cur += 1
            start = i + 1
            if cur == 5 && idx == 5 { emit substring(row, i + 1, n) }
        }
        i += 1
    }
    if cur == idx { emit substring(row, start, n) }
    emit ""
}

func diagsToJson(diagText) {
    if diagText == "" { emit "[]" }
    let nLines = lineCount(diagText)
    let parts = ""
    let i = 0
    while i < nLines {
        let row = getLine(diagText, i)
        if len(row) > 0 {
            let sev = toInt(diagField(row, 0))
            let sl  = toInt(diagField(row, 1))
            let sc  = toInt(diagField(row, 2))
            let el  = toInt(diagField(row, 3))
            let ec  = toInt(diagField(row, 4))
            let msg = diagField(row, 5)
            let frag = jeDiagnostic(sl, sc, el, ec, sev, msg)
            if parts == "" { parts = frag }
            else           { parts = parts + "\t" + frag }
        }
        i += 1
    }
    emit jeArrFrom(parts)
}

// Lex + validate, merge diagnostics, return JSON params.
func computeDiagnostics(uri, text) {
    let r       = lspTokenize(text)
    let toks    = tokensOf(r)
    let lexDiag = diagsOf(r)
    let valDiag = validateTokens(toks)
    let merged = lexDiag + valDiag
    let arr = diagsToJson(merged)
    emit jeObj2("uri", jeStr(uri), "diagnostics", arr)
}

func publishDiagnostics(uri, text) {
    let params = computeDiagnostics(uri, text)
    let msg = jeObj3("jsonrpc", jeStr("2.0"),
                     "method",  jeStr("textDocument/publishDiagnostics"),
                     "params",  params)
    jrWriteFrame(msg)
}

// ── Response builders ───────────────────────────────────────────

func sendResult(id, result) {
    let msg = jeObj3("jsonrpc", jeStr("2.0"),
                     "id",      jeRaw(id),
                     "result",  result)
    jrWriteFrame(msg)
}

func sendError(id, code, message) {
    let err = jeObj2("code", jeNum(code), "message", jeStr(message))
    let msg = jeObj3("jsonrpc", jeStr("2.0"),
                     "id",      jeRaw(id),
                     "error",   err)
    jrWriteFrame(msg)
}

// ── Capabilities ────────────────────────────────────────────────

func serverCapabilities() {
    let sync         = jeNum(1)              // Full
    let symProvider  = jeRaw("true")
    // CompletionOptions — empty triggerCharacters, no resolveProvider.
    let cmpOptions   = jeObj("triggerCharacters", jeArr0())
    let caps = jeObj4("textDocumentSync",       sync,
                      "documentSymbolProvider", symProvider,
                      "completionProvider",     cmpOptions,
                      "hoverProvider",          jeRaw("false"))
    let info = jeObj2("name", jeStr("kls"), "version", jeStr("0.2.0"))
    emit jeObj2("capabilities", caps, "serverInfo", info)
}

// ── documentSymbol handler ──────────────────────────────────────

func handleDocSymbol(uri, docs) {
    let text = docGet(docs, uri)
    let r    = lspTokenize(text)
    let toks = tokensOf(r)
    emit documentSymbolJson(toks)
}

// ── completion handler ──────────────────────────────────────────

func handleCompletion(uri, docs) {
    let text = docGet(docs, uri)
    let r    = lspTokenize(text)
    let toks = tokensOf(r)
    emit completionJson(toks)
}

// ── Method dispatch ─────────────────────────────────────────────

func handle(method, idJson, parsed, docs) {
    if method == "initialize" {
        sendResult(idJson, serverCapabilities())
        emit docs
    }
    if method == "initialized" {
        emit docs
    }
    if method == "shutdown" {
        sendResult(idJson, jeNull())
        emit docs
    }
    if method == "exit" {
        emit docs
    }
    if method == "textDocument/didOpen" {
        let uri  = jpGet(parsed, "params.textDocument.uri")
        let text = jpGet(parsed, "params.textDocument.text")
        docs = docPut(docs, uri, text)
        publishDiagnostics(uri, text)
        emit docs
    }
    if method == "textDocument/didChange" {
        let uri = jpGet(parsed, "params.textDocument.uri")
        let n = jpArrLen(parsed, "params.contentChanges")
        let text = ""
        if n > 0 {
            text = jpGet(parsed, "params.contentChanges." + (n - 1) + ".text")
        }
        docs = docPut(docs, uri, text)
        publishDiagnostics(uri, text)
        emit docs
    }
    if method == "textDocument/didClose" {
        let uri = jpGet(parsed, "params.textDocument.uri")
        docs = docDel(docs, uri)
        emit docs
    }
    if method == "textDocument/documentSymbol" {
        let uri = jpGet(parsed, "params.textDocument.uri")
        sendResult(idJson, handleDocSymbol(uri, docs))
        emit docs
    }
    if method == "textDocument/completion" {
        let uri = jpGet(parsed, "params.textDocument.uri")
        sendResult(idJson, handleCompletion(uri, docs))
        emit docs
    }
    if idJson != "" && idJson != "null" {
        sendError(idJson, -32601, "method not found: " + method)
    }
    emit docs
}

// ── Main loop ───────────────────────────────────────────────────

just run {
    jrInit()
    jrLog("kls 0.2.0 starting")
    let docs = jmNew()
    let running = 1
    while running == 1 {
        let frame = jrReadFrame()
        if frame == "" {
            jrLog("EOF on stdin, exiting")
            running = 0
        } else {
            let parsed = jpParse(frame)
            let method = jpGet(parsed, "method")
            let idType = jpTypeOf(parsed, "id")
            let idJson = ""
            if idType == "n" { idJson = jpGet(parsed, "id") }
            if idType == "s" { idJson = jeStr(jpGet(parsed, "id")) }
            jrLog("method: " + method)
            if method == "exit" {
                running = 0
            } else {
                docs = handle(method, idJson, parsed, docs)
            }
        }
    }
    jrLog("kls bye")
}
