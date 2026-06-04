// server.k — cross-platform HTTP server for Krypton .htk web apps
// Windows: Winsock2 (ws2_32.dll)
// Linux / macOS / BSD / Unix: POSIX sockets
//
// Build:
//   Windows:  kcc app.htk > /tmp/app.c && gcc /tmp/app.c -o app.exe -lws2_32 -w
//   Linux:    kcc app.htk > /tmp/app.c && gcc /tmp/app.c -o app -w
//   macOS:    kcc app.htk > /tmp/app.c && clang /tmp/app.c -o app -w
//   Or:       khtk app.htk   (auto-detects platform)

module server

jxt {
    func _srvInit(port)
    func _srvNext()
    func _srvMethod()
    func _srvPath()
    func _srvQuery()
    func _srvBody()
    func _srvHeaders()
    func _srvCookie()
    func _srvRespond(status, contentType, body)
    func _srvRespondRaw(rawResponse)
    func _srvRespondFile(path)
    func _srvStop()
}

cfunc {

// ── Krypton-side API ──────────────────────────────────────────────────────

func serverInit(port)     { _srvInit(port) }
func serverStop()         { _srvStop() }
func serverNext()         { emit _srvNext() }
func serverReqMethod()    { emit _srvMethod() }
func serverReqPath()      { emit _srvPath() }
func serverReqQuery()     { emit _srvQuery() }
func serverReqBody()      { emit _srvBody() }
func serverReqHeaders()   { emit _srvHeaders() }
func serverReqCookieRaw() { emit _srvCookie() }

func serverRespond(html)              { _srvRespond("200 OK", "text/html", html) }
func serverRespondJSON(json)          { _srvRespond("200 OK", "application/json", json) }
func serverRespondText(text)          { _srvRespond("200 OK", "text/plain", text) }
func serverRespondFile(path)          { emit _srvRespondFile(path) }
func serverRespondWith(status, ct, b) { _srvRespond(status, ct, b) }

func serverRespond404()  { _srvRespond("404 Not Found", "text/html", "<h1>404 Not Found</h1>") }
func serverRespond400()  { _srvRespond("400 Bad Request", "text/html", "<h1>400 Bad Request</h1>") }
func serverRespond403()  { _srvRespond("403 Forbidden", "text/html", "<h1>403 Forbidden</h1>") }
func serverRespond500()  { _srvRespond("500 Internal Server Error", "text/html", "<h1>500 Internal Server Error</h1>") }

func serverRedirect(url) {
    let NL = fromCharCode(13) + fromCharCode(10)
    _srvRespondRaw("HTTP/1.1 302 Found" + NL + "Location: " + url + NL + "Content-Length: 0" + NL + "Connection: close" + NL + NL)
}

func serverRedirect301(url) {
    let NL = fromCharCode(13) + fromCharCode(10)
    _srvRespondRaw("HTTP/1.1 301 Moved Permanently" + NL + "Location: " + url + NL + "Content-Length: 0" + NL + "Connection: close" + NL + NL)
}

func serverSetCookie(cookieName, cookieVal, opts) {
    let NL = fromCharCode(13) + fromCharCode(10)
    let cookie = cookieName + "=" + cookieVal
    if len(opts) > 0 { cookie = cookie + "; " + opts }
    _srvRespondRaw("HTTP/1.1 200 OK" + NL + "Set-Cookie: " + cookie + NL + "Content-Type: text/html; charset=utf-8" + NL + "Content-Length: 0" + NL + "Connection: close" + NL + NL)
}

func serverRespondWithCookie(html, cookieName, cookieVal, opts) {
    let NL = fromCharCode(13) + fromCharCode(10)
    let cookie = cookieName + "=" + cookieVal
    if len(opts) > 0 { cookie = cookie + "; " + opts }
    let blen = len(html)
    _srvRespondRaw("HTTP/1.1 200 OK" + NL + "Content-Type: text/html; charset=utf-8" + NL + "Set-Cookie: " + cookie + NL + "Content-Length: " + (blen + "") + NL + "Connection: close" + NL + NL + html)
}

func serverRespondCORS(html) {
    let NL = fromCharCode(13) + fromCharCode(10)
    let blen = len(html)
    _srvRespondRaw("HTTP/1.1 200 OK" + NL + "Content-Type: text/html; charset=utf-8" + NL + "Access-Control-Allow-Origin: *" + NL + "Access-Control-Allow-Methods: GET, POST, OPTIONS" + NL + "Access-Control-Allow-Headers: Content-Type" + NL + "Content-Length: " + (blen + "") + NL + "Connection: close" + NL + NL + html)
}

// ── Cookie parsing ───────────────────────────────────────────────────
// serverReqCookie("session") → "abc123"
// Parses from "name1=val1; name2=val2" format

func serverReqCookie(key) {
    let raw = serverReqCookieRaw()
    if len(raw) == 0 { emit "" }
    let i = 0
    let n = len(raw)
    while i < n {
        while i < n && raw[i] == " " { i += 1 }
        let eq = indexOf(substring(raw, i, n), "=")
        if eq < 0 { emit "" }
        eq += i
        let k = substring(raw, i, eq)
        let semi = indexOf(substring(raw, eq + 1, n), ";")
        let vEnd = n
        if semi >= 0 { vEnd = eq + 1 + semi }
        let v = substring(raw, eq + 1, vEnd)
        if k == key { emit v }
        i = vEnd + 1
    }
    emit ""
}

// ── Request header lookup ────────────────────────────────────────────
// serverReqHeader("User-Agent") → "Mozilla/5.0..."

func serverReqHeader(headerName) {
    let raw = serverReqHeaders()
    let search = headerName + ": "
    let pos = indexOf(raw, search)
    if pos < 0 { emit "" }
    let start = pos + len(search)
    let eol = indexOf(substring(raw, start, len(raw)), fromCharCode(13))
    if eol < 0 { emit substring(raw, start, len(raw)) }
    emit substring(raw, start, start + eol)
}

// ── URL decode ────────────────────────────────────────────────────────────

func _srvHexVal(c) {
    if c >= "0" && c <= "9" { emit charCode(c) - charCode("0") }
    if c >= "a" && c <= "f" { emit charCode(c) - charCode("a") + 10 }
    if c >= "A" && c <= "F" { emit charCode(c) - charCode("A") + 10 }
    emit 0
}

func urlDecode(s) {
    let out = sbNew()
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == "+" {
            out = sbAppend(out, " ")
            i += 1
        } else if c == "%" && i + 2 < len(s) {
            let hi = _srvHexVal(s[i + 1])
            let lo = _srvHexVal(s[i + 2])
            out = sbAppend(out, fromCharCode(hi * 16 + lo))
            i += 3
        } else {
            out = sbAppend(out, c)
            i += 1
        }
    }
    emit sbToString(out)
}

// ── Query / form param parsing ────────────────────────────────────────────

func queryParam(qs, key) {
    let i = 0
    let n = len(qs)
    while i < n {
        let eq = indexOf(substring(qs, i, n), "=")
        if eq < 0 { emit "" }
        eq += i
        let k = urlDecode(substring(qs, i, eq))
        let amp = indexOf(substring(qs, eq + 1, n), "&")
        let vEnd = n
        if amp >= 0 { vEnd = eq + 1 + amp }
        let v = urlDecode(substring(qs, eq + 1, vEnd))
        if k == key { emit v }
        i = vEnd + 1
    }
    emit ""
}

func queryParamAll(qs, key) {
    let out = ""
    let i = 0
    let n = len(qs)
    while i < n {
        let eq = indexOf(substring(qs, i, n), "=")
        if eq < 0 { emit out }
        eq += i
        let k = urlDecode(substring(qs, i, eq))
        let amp = indexOf(substring(qs, eq + 1, n), "&")
        let vEnd = n
        if amp >= 0 { vEnd = eq + 1 + amp }
        let v = urlDecode(substring(qs, eq + 1, vEnd))
        if k == key {
            if len(out) > 0 { out = out + "," }
            out = out + v
        }
        i = vEnd + 1
    }
    emit out
}
