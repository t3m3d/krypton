// stdlib/httpc.k — minimal HTTP client in PURE KRYPTON. No clang.
//
// Two paths:
//
// 1.  POSIX (macOS + Linux): the original socket-based HTTP/1.0 client
//     built on the native C-free socket builtins (sockMake / sockConnect
//     / sockSend / sockRecvStr / sockClose) plus `exec` for DNS
//     (dig/host).  Plain HTTP only -- for HTTPS use a proxy or stunnel.
//
//       httpGet("example.com", "/")        -> full response
//       httpGetBody("example.com", "/")    -> body only
//       httpStatus(resp)                   -> 200
//
// 2.  Windows (added 2026-06-13): WinINet via the freshly-IAT-registered
//     wininet.dll surface.  Takes a full URL, follows redirects, handles
//     both HTTP and HTTPS, no curl-spawn, no dig.
//
//       httpGetUrl("https://krypton-lang.org/")    -> full body
//       httpGetUrlStatus("https://...")            -> 200
//
//     The Windows path needs the x64_host_windows_x86_64.exe regen
//     (see docs/backend_history.md#Windows ws2_32 IAT notes) before the IAT slots
//     populate at load time -- calling httpGetUrl on a binary built
//     with the current host produces a zero-IAT segfault.

module httpc

import "head:wininet"

func _q(s) { emit "\"" + s + "\"" }

// native trim() strips spaces only; chomp \n\r\t too.
func _chomp(s) {
    let lo = 0
    let hi = len(s)
    while lo < hi {
        let c = toInt(charCode(s[lo]))
        if c == 32 || c == 9 || c == 10 || c == 13 { lo += 1 } else { break }
    }
    while hi > lo {
        let c = toInt(charCode(s[hi - 1]))
        if c == 32 || c == 9 || c == 10 || c == 13 { hi -= 1 } else { break }
    }
    emit substring(s, lo, hi)
}

func _NL() { emit fromCharCode(13) + fromCharCode(10) }

// resolve(host) -> dotted-quad IP string, or "" on failure. Uses dig, falls
// back to `host`. Both are clang-free external tools.
func _isDottedQuad(s) {
    let i = 0
    let dots = 0
    while i < len(s) {
        let c = toInt(charCode(s[i]))
        if c == 46 { dots += 1 }
        else if c < 48 || c > 57 { emit 0 }
        i += 1
    }
    if dots == 3 { emit 1 }
    emit 0
}

func resolve(host) {
    // already an IP literal (e.g. 127.0.0.1) -> use as-is, dig won't resolve it.
    if _isDottedQuad(host) == 1 { emit host }
    let ip = _chomp(exec("dig +short " + _q(host) + " A 2>/dev/null | grep -E '^[0-9.]+$' | head -1"))
    if ip != "" { emit ip }
    // fallback: `host` command
    ip = _chomp(exec("host -t A " + _q(host) + " 2>/dev/null | grep 'has address' | head -1 | awk '{print $NF}'"))
    emit ip
}

// nth dot-separated octet of an IP, as an int. Avoids splitBy (broken native).
func _octet(ip, idx) {
    let start = 0
    let field = 0
    while field < idx {
        let rest = substring(ip, start, len(ip))
        let dot = indexOf(rest, ".")
        if dot < 0 { emit 0 }
        start = start + dot + 1
        field += 1
    }
    let rest = substring(ip, start, len(ip))
    let dot = indexOf(rest, ".")
    if dot >= 0 { emit toInt(substring(rest, 0, dot)) }
    emit toInt(rest)
}

// httpGetPort(host, path, port) -> full raw response string ("" on failure).
func httpGetPort(host, path, port) {
    let ip = resolve(host)
    if ip == "" { emit "" }
    let a = _octet(ip, 0)
    let b = _octet(ip, 1)
    let c = _octet(ip, 2)
    let d = _octet(ip, 3)
    let hi = port / 256
    let lo = port - (hi * 256)

    let fd = sockMake()
    if fd < 0 { emit "" }
    let rc = sockConnect(fd, a, b, c, d, hi, lo)
    if rc < 0 { sockClose(fd)  emit "" }

    let req = "GET " + path + " HTTP/1.0" + _NL() +
              "Host: " + host + _NL() +
              "User-Agent: krypton-httpc/1.0" + _NL() +
              "Connection: close" + _NL() + _NL()
    sockSend(fd, req, len(req))

    // read to EOF: sockRecvStr returns "" when the peer closes.
    let resp = ""
    let chunk = sockRecvStr(fd)
    while len(chunk) > 0 {
        resp = resp + chunk
        chunk = sockRecvStr(fd)
    }
    sockClose(fd)
    emit resp
}

// httpGet(host, path) -> full response over port 80.
func httpGet(host, path) { emit httpGetPort(host, path, 80) }

func _bodyOf(r) {
    let sep = indexOf(r, _NL() + _NL())
    if sep >= 0 { emit substring(r, sep + 4, len(r)) }
    emit r
}

// httpGetBody(host, path) -> just the body (after the blank CRLFCRLF).
func httpGetBody(host, path) { emit _bodyOf(httpGet(host, path)) }

// httpGetBodyPort(host, path, port) -> body only, on a custom port.
func httpGetBodyPort(host, path, port) { emit _bodyOf(httpGetPort(host, path, port)) }

// httpStatus(resp) -> numeric status code from a response ("HTTP/1.0 200 OK").
func httpStatus(resp) {
    let sp1 = indexOf(resp, " ")
    if sp1 < 0 { emit 0 }
    let rest = substring(resp, sp1 + 1, len(resp))
    let sp2 = indexOf(rest, " ")
    if sp2 >= 0 { emit toInt(substring(rest, 0, sp2)) }
    emit toInt(rest)
}

// ── Windows / WinINet path ───────────────────────────────────────────
//
// httpGetUrl(url) -> response body as a string, or "" on failure.
// Handles HTTP + HTTPS uniformly; WinINet uses the IE proxy + cookie
// settings, which is what end-user apps generally want.

let _UA = "krypton-httpc/2.0"
let _INTERNET_FLAG_SECURE = "8388608"        // 0x00800000 -- HTTPS
let _INTERNET_FLAG_NO_CACHE_WRITE = "67108864" // 0x04000000
// Streaming buffer size per InternetReadFile call.
let _HTTPC_BUF_BYTES = "8192"

func _isHttps(url) {
    if len(url) < 8 { emit 0 }
    if substring(url, 0, 8) == "https://" { emit 1 }
    emit 0
}

func httpGetUrl(url) {
    let hInet = InternetOpenA(_UA, "0", "0", "0", "0")
    if ptrToInt(hInet) == "0" { emit "" }
    let flags = _INTERNET_FLAG_NO_CACHE_WRITE
    if _isHttps(url) == 1 {
        flags = toStr(toInt(_INTERNET_FLAG_NO_CACHE_WRITE) + toInt(_INTERNET_FLAG_SECURE))
    }
    let hReq = InternetOpenUrlA(hInet, url, "0", "0", flags, "0")
    if ptrToInt(hReq) == "0" {
        InternetCloseHandle(hInet)
        emit ""
    }
    let out = sbNew()
    let buf = bufNew(_HTTPC_BUF_BYTES)
    let nRead = bufNew("4")
    bufSetDwordAt(nRead, "0", "0")
    let again = "1"
    while again == "1" {
        let ok = InternetReadFile(hReq, buf, _HTTPC_BUF_BYTES, nRead)
        if ok == "0" { again = "0" }
        let got = toInt(bufGetDwordAt(nRead, "0"))
        if got == 0 { again = "0" }
        let i = 0
        while i < got {
            let b = bufGetByte(buf, toStr(i))
            out = sbAppend(out, chr(b))
            i += 1
        }
    }
    InternetCloseHandle(hReq)
    InternetCloseHandle(hInet)
    emit sbToString(out)
}

// httpGetUrlStatus(url) -> HTTP status code from a WinINet GET, or 0 on failure.
let _HTTP_QUERY_STATUS_CODE = "19"
let _HTTP_QUERY_FLAG_NUMBER = "536870912"     // 0x20000000
func httpGetUrlStatus(url) {
    let hInet = InternetOpenA(_UA, "0", "0", "0", "0")
    if ptrToInt(hInet) == "0" { emit 0 }
    let flags = _INTERNET_FLAG_NO_CACHE_WRITE
    if _isHttps(url) == 1 {
        flags = toStr(toInt(_INTERNET_FLAG_NO_CACHE_WRITE) + toInt(_INTERNET_FLAG_SECURE))
    }
    let hReq = InternetOpenUrlA(hInet, url, "0", "0", flags, "0")
    if ptrToInt(hReq) == "0" {
        InternetCloseHandle(hInet)
        emit 0
    }
    let codeBuf = bufNew("4")
    let lenBuf = bufNew("4")
    bufSetDwordAt(lenBuf, "0", "4")
    let level = toStr(toInt(_HTTP_QUERY_STATUS_CODE) + toInt(_HTTP_QUERY_FLAG_NUMBER))
    HttpQueryInfoA(hReq, level, codeBuf, lenBuf, "0")
    let code = toInt(bufGetDwordAt(codeBuf, "0"))
    InternetCloseHandle(hReq)
    InternetCloseHandle(hInet)
    emit code
}
