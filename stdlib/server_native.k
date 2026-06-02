// stdlib/server_native.k — HTTP server in PURE KRYPTON. No C, no cfunc.
//
// Built entirely on the native BSD-socket builtins (sockMake/sockBind/
// sockListen/sockAccept/sockRecvStr/sockSend/sockClose) that the macOS arm64
// (and Linux) native backend emits as direct syscalls. Serve with zero C.
//
// IMPORTANT — state is threaded EXPLICITLY, not via module globals. Krypton
// imported modules export functions only; their top-level `let` state does
// NOT initialize or persist across the import boundary. So the caller holds
// the listening socket and per-request values:
//
//     import "k:htmk"
//     import "k:server_native"
//     just run {
//         let srv = serverListen("8080")
//         while "1" == "1" {
//             let cl = serverAccept(srv)            // client fd, or -1
//             if cl >= 0 {
//                 let req = serverRead(cl)          // raw request string
//                 let path = reqPath(req)
//                 serverSend(cl, htmlResponse("<h1>hi, no C</h1>"))
//             }
//         }
//     }
//
// Windows / the --gcc C path: use k:server (its cfunc). This module assumes
// the socket builtins exist (native backend only).

module server_native

func _NL() { emit fromCharCode(13) + fromCharCode(10) }   // CRLF
func _CR() { emit fromCharCode(13) }

// ── listen ────────────────────────────────────────────────────────────
// serverListen(port) -> listening socket fd (>=0), or -1 on failure.
// port is a string ("8080").
func serverListen(port) {
    let p = toInt(port)
    let fd = sockMake()
    if fd < 0 { emit 0 - 1 }
    let hi = p / 256                 // big-endian port bytes (no asm shifts)
    let lo = p - (hi * 256)
    sockBind(fd, hi, lo)
    sockListen(fd, 16)
    emit fd
}

// serverAccept(sock) -> client fd (>=0), or -1.
func serverAccept(sock) {
    let c = sockAccept(sock)
    if c < 0 { emit 0 - 1 }
    emit c
}

// serverRead(client) -> raw HTTP request as a string ("" on empty read).
func serverRead(client) {
    emit sockRecvStr(client)
}

// serverClose(fd) -> close a socket (listener or client).
func serverClose(fd) { sockClose(fd)  emit "" }

// ── request parsing (pure string ops over the request the caller holds) ──
// reqLine(req) -> the request line ("GET /x?y=1 HTTP/1.1").
func reqLine(req) {
    let crlf = indexOf(req, _NL())
    if crlf >= 0 { emit substring(req, 0, crlf) }
    emit req
}

func reqMethod(req) {
    let line = reqLine(req)
    let sp = indexOf(line, " ")
    if sp >= 0 { emit substring(line, 0, sp) }
    emit line
}

// reqTarget(req) -> the raw path+query ("/x?y=1").
func reqTarget(req) {
    let line = reqLine(req)
    let sp1 = indexOf(line, " ")
    if sp1 < 0 { emit "" }
    let rest = substring(line, sp1 + 1, len(line))
    let sp2 = indexOf(rest, " ")
    if sp2 >= 0 { emit substring(rest, 0, sp2) }
    emit rest
}

func reqPath(req) {
    let t = reqTarget(req)
    let q = indexOf(t, "?")
    if q >= 0 { emit substring(t, 0, q) }
    emit t
}

func reqQuery(req) {
    let t = reqTarget(req)
    let q = indexOf(t, "?")
    if q >= 0 { emit substring(t, q + 1, len(t)) }
    emit ""
}

// reqBody(req) -> the body after the blank CRLFCRLF line.
func reqBody(req) {
    let sep = indexOf(req, _NL() + _NL())
    if sep >= 0 { emit substring(req, sep + 4, len(req)) }
    emit ""
}

// reqHeaders(req) -> the raw header block (between request line and body).
func reqHeaders(req) {
    let crlf = indexOf(req, _NL())
    let sep = indexOf(req, _NL() + _NL())
    if crlf >= 0 && sep >= 0 { emit substring(req, crlf + 2, sep) }
    emit ""
}

// reqHeader(req, name) -> one header value (case-sensitive name match).
func reqHeader(req, name) {
    let hs = reqHeaders(req)
    let needle = name + ": "
    let p = indexOf(hs, needle)
    if p < 0 { emit "" }
    let after = substring(hs, p + len(needle), len(hs))
    let e = indexOf(after, _CR())
    if e >= 0 { emit substring(after, 0, e) }
    emit after
}

// ── url-decoded params ──────────────────────────────────────────────────
func _hexVal(c) {
    let v = toInt(charCode(c))
    if v >= 48 && v <= 57 { emit v - 48 }
    if v >= 97 && v <= 102 { emit v - 87 }
    if v >= 65 && v <= 70  { emit v - 55 }
    emit 0
}
func urlDecode(s) {
    let out = ""
    let i = 0
    let n = len(s)
    while i < n {
        let c = s[i]
        if c == "+" { out = out + " "  i += 1 }
        else if c == "%" && i + 2 < n {
            out = out + fromCharCode(_hexVal(s[i+1]) * 16 + _hexVal(s[i+2]))
            i += 3
        } else { out = out + c  i += 1 }
    }
    emit out
}
func paramOf(qs, key) {
    let needle = key + "="
    let p = indexOf(qs, needle)
    if p < 0 { emit "" }
    let rest = substring(qs, p + len(needle), len(qs))
    let amp = indexOf(rest, "&")
    let raw = rest
    if amp >= 0 { raw = substring(rest, 0, amp) }
    emit urlDecode(raw)
}
func queryValue(req, key) { emit paramOf(reqQuery(req), key) }
func formValue(req, key)  { emit paramOf(reqBody(req), key) }

// ── responses (build a full HTTP message string; caller sends it) ────────
func httpResponse(status, ct, body) {
    emit "HTTP/1.1 " + status + _NL() +
         "Content-Type: " + ct + "; charset=utf-8" + _NL() +
         "Content-Length: " + len(body) + _NL() +
         "Connection: close" + _NL() + _NL() + body
}
func htmlResponse(html) { emit httpResponse("200 OK", "text/html", html) }
func jsonResponse(json) { emit httpResponse("200 OK", "application/json", json) }
func textResponse(text) { emit httpResponse("200 OK", "text/plain", text) }
func notFound()         { emit httpResponse("404 Not Found", "text/html", "<h1>404 Not Found</h1>") }
func redirect(url) {
    emit "HTTP/1.1 302 Found" + _NL() + "Location: " + url + _NL() +
         "Content-Length: 0" + _NL() + "Connection: close" + _NL() + _NL()
}

// serverSend(client, fullResponse): write the response, close the client.
func serverSend(client, response) {
    sockSend(client, response, len(response))
    sockClose(client)
    emit ""
}

// Convenience: one call to respond + close with an HTML body.
func serveHtml(client, html) { serverSend(client, htmlResponse(html))  emit "" }
func serveText(client, text) { serverSend(client, textResponse(text))  emit "" }
func serveJson(client, json) { serverSend(client, jsonResponse(json))  emit "" }
func serve404(client)        { serverSend(client, notFound())  emit "" }
