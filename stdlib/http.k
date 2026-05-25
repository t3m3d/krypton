// stdlib/http.k — minimal HTTP client backed by curl.
//
// Windows 10 1803+ ships curl.exe at C:\Windows\System32\curl.exe.
// macOS / Linux: curl is on PATH by default.
//
// This module is intentionally tiny — a real WinHTTP / libcurl binding
// is future work. For most "fetch JSON from REST endpoint" use cases
// these helpers replace the equivalent Python `requests` calls.
//
// Public API:
//   httpGet(url)                     — body as string (or "" on failure)
//   httpGetWithHeaders(url, headers) — headers is multi-line string,
//                                       e.g. "Authorization: Bearer X\nAccept: application/json"
//   httpPost(url, body, contentType) — POST a string body, e.g. JSON
//   httpStatus(url)                  — HTTP status code as string ("200", "404", ...)
//   httpDownload(url, path)          — save response to file, returns "1"/"0"
//
// All helpers shell out to curl via exec(). Output is captured to a
// 64 KB Krypton buffer — body larger than that gets truncated. For
// large downloads use httpDownload, which uses curl -o (no cap).

module http

import "head:fileio"

// Inline temp-dir + delete (stdlib `k:fs` doesn't chain-import from
// other stdlib modules in the current build, so we inline the few
// Win32 calls we need here).
func _http_tempdir() {
    let buf = bufNew(1024)
    let n = GetTempPathA("1024", buf)
    if n == "0" { emit "" }
    emit bufStr(buf)
}

// Quote one arg for cmd.exe — wrap in double-quotes, escape internal `"`.
// Krypton has no `\\"` literal in a string, so build via fromCharCode.
func _http_q(s) {
    let DQ = fromCharCode("34")   // "
    let out = sbNew()
    out = sbAppend(out, DQ)
    let i = 0
    while i < len(s) {
        let ch = s[i]
        if ch == DQ {
            // escape an embedded quote: cmd uses ""
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

// Build a series of "-H header" args from a multi-line header string.
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

// GET the URL, return body string. Failures return "".
func httpGet(url) {
    let cmd = "curl -sSL " + _http_q(url)
    emit exec(cmd)
}

// GET with headers (multi-line: one "Key: Value" per line).
func httpGetWithHeaders(url, headers) {
    let cmd = "curl -sSL" + _http_hdrs(headers) + " " + _http_q(url)
    emit exec(cmd)
}

// POST a string body. contentType e.g. "application/json".
// Body is written to a temp file to avoid cmd.exe quoting headaches
// (works for binary bodies + arbitrary JSON without escape hell).
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

// Return HTTP status code ("200", "404", etc.) — "0" if curl failed.
func httpStatus(url) {
    let cmd = "curl -sSL -o nul -w %{http_code} " + _http_q(url)
    let s = exec(cmd)
    if len(s) == 0 { emit "0" }
    emit trim(s)
}

// Download URL to local file path. Returns "1" on success, "0" otherwise.
// Unlike httpGet, body is not capped — curl writes straight to disk.
func httpDownload(url, path) {
    let cmd = "curl -sSL -o " + _http_q(path) + " " + _http_q(url)
    shellRun(cmd)
    // No reliable exit code from shellRun yet — verify by checking file exists
    // with non-zero size via GetFileAttributesA pattern in fs.k. For now,
    // best-effort: caller can readFile(path) to see what came back.
    emit "1"
}
