// router.k — Express-style routing for Krypton .htk web apps.
//
// Self-contained: no imports. Calls into k:server (serverInit/serverNext/
// serverReq*/serverRespond*/queryParam), so the app must import k:server
// alongside k:router. Uses only runtime builtins otherwise.
//
// Handler storage: the route table is a Krypton env (envNew/envSet/envGet),
// which preserves raw pointers — funcptr(handler) round-trips intact. A
// plain string map CANNOT hold a funcptr: concatenating a raw code pointer
// into "key=val" copies the machine-code bytes, not the address, and the
// later callPtr segfaults. env is the portable equivalent of gui.k's native
// callback registry. (envSet is a value type — always reassign: app = ...)
//
// Handlers take (req, res) and produce the response themselves:
//   func home(req, res) { resSend(res, htPage("Home", "", htH1("hi"))) }
// req is the path-param map (reqParam); method/path/query/body/headers/
// cookies are read live off k:server (reqMethod/reqQuery/reqForm/...).
//
// Design: docs/web_router_design.md

module router

// ── params map (strings only — safe in a key=val\n string) ─────────────

func _rmGet(m, key) {
    let n = lineCount(m)
    let i = 0
    while i < n {
        let line = getLine(m, i)
        let eq = indexOf(line, "=")
        if eq >= 0 {
            if substring(line, 0, eq) == key {
                emit substring(line, eq + 1, len(line))
            }
        }
        i += 1
    }
    emit ""
}

func _rmSet(m, key, val) {
    emit m + key + "=" + val + "\n"
}

// ── route matching ────────────────────────────────────────────────────
// "no" on mismatch, else the captured-params map (possibly ""). ":name"
// captures one segment; trailing "*" captures the remainder under "*".

func _matchRoute(pattern, path) {
    let plen = len(pattern)
    let slen = len(path)
    let pi = 0
    let si = 0
    if plen > 0 && pattern[0] == "/" { pi = 1 }
    if slen > 0 && path[0] == "/" { si = 1 }
    let params = ""
    while pi < plen || si < slen {
        let pe = pi
        while pe < plen && pattern[pe] != "/" { pe += 1 }
        let se = si
        while se < slen && path[se] != "/" { se += 1 }
        let pseg = substring(pattern, pi, pe)
        let sseg = substring(path, si, se)
        if pseg == "*" {
            params = _rmSet(params, "*", substring(path, si, slen))
            emit params
        }
        if len(pseg) > 0 && pseg[0] == ":" {
            params = _rmSet(params, substring(pseg, 1, len(pseg)), sseg)
        } else {
            if pseg != sseg { emit "no" }
        }
        pi = pe + 1
        si = se + 1
    }
    emit params
}

// ── app builders (app is an env; always reassign: app = appGet(app,...)) ─

func appNew() {
    let app = envNew()
    app = envSet(app, "__routes", "")
    app = envSet(app, "__statics", "")
    app = envSet(app, "__mwn", "0")
    emit app
}

func _addRoute(app, method, pat, addr) {
    let key = method + " " + pat
    app = envSet(app, key, addr)
    app = envSet(app, "__routes", envGet(app, "__routes") + key + "\n")
    emit app
}

func appGet(app, pat, addr)    { emit _addRoute(app, "GET", pat, addr) }
func appPost(app, pat, addr)   { emit _addRoute(app, "POST", pat, addr) }
func appPut(app, pat, addr)    { emit _addRoute(app, "PUT", pat, addr) }
func appDelete(app, pat, addr) { emit _addRoute(app, "DELETE", pat, addr) }
func appPatch(app, pat, addr)  { emit _addRoute(app, "PATCH", pat, addr) }

func appStatic(app, prefix, dir) {
    app = envSet(app, "@static " + prefix, dir)
    app = envSet(app, "__statics", envGet(app, "__statics") + prefix + "\n")
    emit app
}

func appUse(app, addr) {
    let n = envGet(app, "__mwn")
    app = envSet(app, "@mw" + n, addr)
    app = envSet(app, "__mwn", (toInt(n) + 1) + "")
    emit app
}

// ── request accessors ─────────────────────────────────────────────────
// req IS the path-param map. method/path/query/body/headers/cookies are
// read live off k:server — valid because the server is single-threaded and
// the handler runs synchronously within the current request.

func reqMethod(req)     { emit serverReqMethod() }
func reqPath(req)       { emit serverReqPath() }
func reqParam(req, nm)  { emit _rmGet(req, nm) }
func reqQuery(req, key) { emit queryParam(serverReqQuery(), key) }
func reqBody(req)       { emit serverReqBody() }
func reqForm(req, key)  { emit queryParam(serverReqBody(), key) }
func reqCookie(req, nm) { emit serverReqCookie(nm) }
func reqHeader(req, nm) { emit serverReqHeader(nm) }

// ── response helpers (immediate flush — no deferred state) ─────────────

func resSend(res, html)             { serverRespond(html) }
func resHtml(res, html)             { serverRespond(html) }
func resJson(res, json)             { serverRespondJSON(json) }
func resText(res, txt)              { serverRespondText(txt) }
func resStatus(res, status, html)   { serverRespondWith(status, "text/html", html) }
func resRedirect(res, url)          { serverRedirect(url) }
func resFile(res, path)             { emit serverRespondFile(path) }
func resCookie(res, html, nm, v, o) { serverRespondWithCookie(html, nm, v, o) }

// ── static path-traversal guard ───────────────────────────────────────

func _safePath(p) {
    if indexOf(p, "..") >= 0 { emit "0" }
    if indexOf(p, fromCharCode(0)) >= 0 { emit "0" }
    emit "1"
}

// ── dispatch ──────────────────────────────────────────────────────────

func _respond405(allow) {
    let NL = fromCharCode(13) + fromCharCode(10)
    let body = "<h1>405 Method Not Allowed</h1>"
    _srvRespondRaw("HTTP/1.1 405 Method Not Allowed" + NL +
        "Allow: " + allow + NL +
        "Content-Type: text/html; charset=utf-8" + NL +
        "Content-Length: " + (len(body) + "") + NL +
        "Connection: close" + NL + NL + body)
}

func _runMiddleware(app, req, res) {
    let cnt = toInt(envGet(app, "__mwn"))
    let i = 0
    while i < cnt {
        let r = callPtr(envGet(app, "@mw" + i), req, res)
        if r != "next" { emit "stop" }
        i += 1
    }
    emit "next"
}

func _dispatch(app, res) {
    let method = serverReqMethod()
    let path = serverReqPath()
    let allow = ""

    // pass 1: routes
    let routes = envGet(app, "__routes")
    let n = lineCount(routes)
    let i = 0
    while i < n {
        let key = getLine(routes, i)
        if len(key) > 0 {
            let sp = indexOf(key, " ")
            let km = substring(key, 0, sp)
            let kp = substring(key, sp + 1, len(key))
            let pm = _matchRoute(kp, path)
            if pm != "no" {
                if km == method {
                    callPtr(envGet(app, key), pm, res)
                    emit "1"
                } else {
                    if len(allow) > 0 { allow = allow + ", " }
                    allow = allow + km
                }
            }
        }
        i += 1
    }

    // pass 2: static mounts
    let statics = envGet(app, "__statics")
    let sn = lineCount(statics)
    let j = 0
    while j < sn {
        let prefix = getLine(statics, j)
        if len(prefix) > 0 {
            if startsWith(path, prefix) {
                let rest = substring(path, len(prefix), len(path))
                if _safePath(rest) == "1" {
                    let ok = serverRespondFile(envGet(app, "@static " + prefix) + rest)
                    if ok == "1" { emit "1" }
                }
            }
        }
        j += 1
    }

    if len(allow) > 0 {
        _respond405(allow)
        emit "1"
    }
    serverRespond404()
    emit "1"
}

// ── run loop ──────────────────────────────────────────────────────────

func appRun(app, port) {
    serverInit(port)
    while "1" == "1" {
        let got = serverNext()
        if got == "1" {
            let res = ""
            if _runMiddleware(app, "", res) == "next" {
                _dispatch(app, res)
            }
        }
    }
}
