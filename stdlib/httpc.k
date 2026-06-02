// stdlib/httpc.k — minimal HTTP/1.0 client in PURE KRYPTON. No clang.
//
// Built on the native C-free socket builtins (sockMake/sockConnect/sockSend/
// sockRecvStr/sockClose) plus `exec` for DNS (dig/host — no C resolver lib).
// macOS + Linux native path. (k:http is the separate curl/Windows C-path
// client; k:httpc is the clang-free native one.)
//
//   httpGet("example.com", "/")        -> full response (headers + body)
//   httpGetBody("example.com", "/")    -> body only
//   httpStatus(resp)                   -> 200
//
// HTTP/1.0 + Connection: close, so the server closes after the body and we
// read to EOF. Plain HTTP only (no TLS) — for https use a proxy or stunnel.

module httpc

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
