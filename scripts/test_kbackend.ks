#!/usr/bin/env kr
// kr scripts/test_kbackend.ks
// Replaces kcode-win/backend/test_kbackend.py. JSON-RPC smoke for kbackend.exe.
import "k:proc"
import "k:fs"

func frame(body) {
    emit "Content-Length: " + len(body) + "\r\n\r\n" + body
}

func _findBodyStart(buf) {
    let i = 0
    while i + 3 < len(buf) {
        if buf[i] == "\r" {
            if buf[i + 1] == "\n" {
                if buf[i + 2] == "\r" {
                    if buf[i + 3] == "\n" { emit i + 4 }
                }
            }
        }
        i += 1
    }
    emit -1
}

func _contentLength(headers) {
    let pfx = "Content-Length:"
    let p = indexOf(headers, pfx)
    if p < 0 { emit 0 }
    let i = p + len(pfx)
    while i < len(headers) && (headers[i] == " " || headers[i] == "\t") { i += 1 }
    let sb = sbNew()
    while i < len(headers) && headers[i] >= "0" && headers[i] <= "9" {
        sb = sbAppend(sb, headers[i])
        i += 1
    }
    emit toInt(sbToString(sb))
}

func reqInit()    { emit "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}" }
func reqInited() { emit "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}" }
func reqPing()   { emit "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\",\"params\":{}}" }
func reqRun(cmd) { emit "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"build/run\",\"params\":{\"cmd\":\"" + cmd + "\"}}" }
func reqShutdown() { emit "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"shutdown\"}" }
func reqExit()   { emit "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}" }

just run {
    let candidates = "kbackend.exe,../kcode-win/kbackend.exe,C:\\krypton\\kbackend.exe"
    let path = ""
    let n = length(candidates)
    let i = 0
    while i < n {
        let cand = split(candidates, i + "")
        if fsFileExists(cand) == "1" {
            path = cand
            i = n
        } else {
            i += 1
        }
    }
    if len(path) == 0 {
        kp("kbackend.exe not found in ./, ../kcode-win/, or C:\\krypton\\")
        exit("1")
    }
    kp("spawning: " + path)

    let p = procSpawn(path, "")
    if p == "0" {
        kp("FAIL: procSpawn failed")
        exit("1")
    }

    procWrite(p, frame(reqInit()))
    procWrite(p, frame(reqInited()))
    procWrite(p, frame(reqPing()))
    procWrite(p, frame(reqRun("echo hello kbackend")))
    procWrite(p, frame(reqShutdown()))
    procWrite(p, frame(reqExit()))

    procSleep(500)
    let buf = procRead(p, 65536)

    kp("============================================================")
    kp("RESPONSES")
    kp("============================================================")
    let pos = 0
    let nf = 0
    while pos < len(buf) {
        let tail = substring(buf, pos, len(buf))
        let bodyOff = _findBodyStart(tail)
        if bodyOff < 0 {
            pos = len(buf)
        } else {
            let headers = substring(tail, 0, bodyOff - 4)
            let bodyLen = _contentLength(headers)
            let body = substring(tail, bodyOff, bodyOff + bodyLen)
            nf += 1
            kp("\n--- frame " + nf + " (" + bodyLen + " bytes) ---")
            kp(body)
            pos = pos + bodyOff + bodyLen
        }
    }
    kp("\n" + nf + " framed messages received")
    procClose(p)
}
