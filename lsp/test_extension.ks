#!/usr/bin/env kr
// kr lsp/test_extension.ks
// Replaces lsp/test_extension.js. Smoke-tests the kls.exe framing
// without VS Code in the loop: initialize, didOpen good, document
// symbols, completion, didOpen bad (diagnostics), shutdown.
import "k:proc"
import "k:fs"

func frame(body) {
    emit "Content-Length: " + len(body) + "\r\n\r\n" + body
}

func _bodyStart(buf) {
    let i = 0
    while i + 3 < len(buf) {
        if buf[i] == "\r" && buf[i + 1] == "\n" && buf[i + 2] == "\r" && buf[i + 3] == "\n" {
            emit i + 4
        }
        i += 1
    }
    emit -1
}

func _cLen(headers) {
    let p = indexOf(headers, "Content-Length:")
    if p < 0 { emit 0 }
    let i = p + 15
    while i < len(headers) && (headers[i] == " " || headers[i] == "\t") { i += 1 }
    let sb = sbNew()
    while i < len(headers) && headers[i] >= "0" && headers[i] <= "9" {
        sb = sbAppend(sb, headers[i])
        i += 1
    }
    emit toInt(sbToString(sb))
}

func _jstr(s) {
    let out = sbNew()
    out = sbAppend(out, "\"")
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == "\\"      { out = sbAppend(out, "\\\\") }
        else if c == "\"" { out = sbAppend(out, "\\\"") }
        else if c == "\n" { out = sbAppend(out, "\\n") }
        else if c == "\r" { out = sbAppend(out, "\\r") }
        else if c == "\t" { out = sbAppend(out, "\\t") }
        else { out = sbAppend(out, c) }
        i += 1
    }
    out = sbAppend(out, "\"")
    emit sbToString(out)
}

let GOOD = "module sample\n\nfunc add(a, b) {\n    emit a + b\n}\n\nfunc greet(name) {\n    kp(\"hi \" + name)\n}\n\nfunc main() {\n    let x = add(2, 3)\n}\n"

let BAD = "func broken() {\n    let x = \"unterminated\n"

just run {
    let klsPath = "C:\\krypton\\kls.exe"
    if fsFileExists(klsPath) != "1" { klsPath = "kls.exe" }

    let p = procSpawn(klsPath, "")
    if p == "0" {
        kp("FAIL: kls.exe not found")
        exit("1")
    }
    kp("launching: " + klsPath)

    let goodUri = "file:///x/sample.k"
    let badUri  = "file:///x/bad.k"

    procWrite(p, frame("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"processId\":0,\"rootUri\":null,\"capabilities\":{}}}"))
    procWrite(p, frame("{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}"))
    procWrite(p, frame("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":" + _jstr(goodUri) + ",\"languageId\":\"krypton\",\"version\":1,\"text\":" + _jstr(GOOD) + "}}}"))
    procWrite(p, frame("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/documentSymbol\",\"params\":{\"textDocument\":{\"uri\":" + _jstr(goodUri) + "}}}"))
    procWrite(p, frame("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":" + _jstr(goodUri) + "},\"position\":{\"line\":0,\"character\":0}}}"))
    procWrite(p, frame("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":" + _jstr(badUri) + ",\"languageId\":\"krypton\",\"version\":1,\"text\":" + _jstr(BAD) + "}}}"))
    procWrite(p, frame("{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"shutdown\"}"))
    procWrite(p, frame("{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"))

    procSleep(800)
    let buf = procRead(p, 65536)

    kp("============================================================")
    kp("FRAMED MESSAGES")
    kp("============================================================")
    let pos = 0
    let nf = 0
    while pos < len(buf) {
        let tail = substring(buf, pos, len(buf))
        let off = _bodyStart(tail)
        if off < 0 { pos = len(buf) }
        else {
            let headers = substring(tail, 0, off - 4)
            let bodyLen = _cLen(headers)
            let body = substring(tail, off, off + bodyLen)
            nf += 1
            let tag = "result"
            if contains(body, "publishDiagnostics") { tag = "publishDiagnostics" }
            else if contains(body, "\"id\":1") { tag = "id=1 initialize" }
            else if contains(body, "\"id\":2") { tag = "id=2 documentSymbol" }
            else if contains(body, "\"id\":3") { tag = "id=3 completion" }
            else if contains(body, "\"id\":99") { tag = "id=99 shutdown" }
            kp("\n--- frame " + nf + " " + tag + " (" + bodyLen + " bytes) ---")
            if bodyLen <= 500 {
                kp(body)
            } else {
                kp(substring(body, 0, 500))
                kp("... (" + (bodyLen - 500) + " truncated)")
            }
            pos = pos + off + bodyLen
        }
    }
    kp("\n" + nf + " framed messages received")
    procClose(p)
}
