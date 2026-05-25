// HTTP client via curl (Win10 1803+ ships System32\curl.exe).
// No native WinHTTP binding — adding one would mean ws2_32 / winhttp DLL
// IAT additions and is real work; deliberate not-yet decision, not laziness.
module http

import "head:fileio"

// k:fs chain-import inside a stdlib module silently drops fs's funcs from
// IR (compile.k bug, see project_python_replacement.md). Hence inline.
func _http_tempdir() {
    let buf = bufNew(1024)
    let n = GetTempPathA("1024", buf)
    if n == "0" { emit "" }
    emit bufStr(buf)
}

// Krypton string literals can't carry a bare " — build via fromCharCode.
func _http_q(s) {
    let DQ = fromCharCode("34")
    let out = sbNew()
    out = sbAppend(out, DQ)
    let i = 0
    while i < len(s) {
        let ch = s[i]
        if ch == DQ {
            out = sbAppend(out, DQ)
            out = sbAppend(out, DQ)
        } else {
            out = sbAppend(out, ch)
        }
        i += 1
    }
    out = sbAppend(out, DQ)
    emit sbToString(out)
}

func _http_hdrs(headers) {
    if len(headers) == 0 { emit "" }
    let out = ""
    let n = lineCount(headers)
    let i = 0
    while i < n {
        let ln = getLine(headers, i)
        if len(ln) > 0 {
            out = out + " -H " + _http_q(ln)
        }
        i += 1
    }
    emit out
}

func httpGet(url) {
    let cmd = "curl -sSL " + _http_q(url)
    emit exec(cmd)
}

func httpGetWithHeaders(url, headers) {
    let cmd = "curl -sSL" + _http_hdrs(headers) + " " + _http_q(url)
    emit exec(cmd)
}

// Body via tempfile + --data-binary @file. Don't "simplify" to inline --data:
// arbitrary JSON breaks cmd.exe quoting in ways that look fine until they don't.
func httpPost(url, body, contentType) {
    let tmp = _http_tempdir() + "_krhttp_post.bin"
    writeFile(tmp, body)
    let cmd = "curl -sSL -X POST"
    if len(contentType) > 0 {
        cmd = cmd + " -H " + _http_q("Content-Type: " + contentType)
    }
    cmd = cmd + " --data-binary " + _http_q("@" + tmp) + " " + _http_q(url)
    let r = exec(cmd)
    DeleteFileA(tmp)
    emit r
}

func httpStatus(url) {
    let cmd = "curl -sSL -o nul -w %{http_code} " + _http_q(url)
    let s = exec(cmd)
    if len(s) == 0 { emit "0" }
    emit trim(s)
}

// Streams to disk via -o; not subject to exec()'s 64KB return cap (vs httpGet).
func httpDownload(url, path) {
    let cmd = "curl -sSL -o " + _http_q(path) + " " + _http_q(url)
    shellRun(cmd)
    emit "1"
}
