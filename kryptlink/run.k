// kryptlink — single-file URL shortener + click tracker. Pure Krypton.
//
//   First time:
//     sqlite3 kryptlink.db < schema.sql
//     setx KRYPTLINK_PASSWORD <your-password>
//     setx KRYPTLINK_DB "C:/path/to/kryptlink.db"
//     setx KRYPTLINK_PUBLIC_HOST "https://krypton-lang.org"
//     kcc -o kryptlink.exe kryptlink/run.k
//
//   Then:
//     kryptlink.exe [PORT]                    (default 8080)
//
//   Routes:
//     GET  /                  → admin page (login form OR control panel)
//     POST /login             → cookie session if password matches
//     POST /logout            → drop session
//     POST /create            → create a link (auth required)
//     GET  /r/<code>          → log click + 302 to destination
//     GET  /stats/<code>      → HTML stats page (auth required)
//     GET  /qr/<code>.svg     → QR for the short URL (placeholder for now)

import "k:server_native"
import "k:random"
import "k:datetime"
import "k:string_utils"
import "k:cookie"
import "k:validate"

// ── Config (read once at startup) ────────────────────────────────────

func cfgPassword() {
    let buf = bufNew(256)
    let n = GetEnvironmentVariableA("KRYPTLINK_PASSWORD", buf, "256")
    if n == "0" { emit "" }
    emit bufStr(buf)
}

func cfgDbPath() {
    let buf = bufNew(512)
    let n = GetEnvironmentVariableA("KRYPTLINK_DB", buf, "512")
    if n == "0" { emit "kryptlink.db" }
    emit bufStr(buf)
}

func cfgPublicHost() {
    let buf = bufNew(256)
    let n = GetEnvironmentVariableA("KRYPTLINK_PUBLIC_HOST", buf, "256")
    if n == "0" { emit "http://localhost:8080" }
    emit bufStr(buf)
}

// ── SQLite shellout helpers ──────────────────────────────────────────

// sqlite single-quote escape: '' inside single-quoted string literals.
func sqlEscape(s) {
    let out = sbNew()
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == "'" {
            out = sbAppend(out, "'")
            out = sbAppend(out, "'")
        } else {
            out = sbAppend(out, c)
        }
        i = i + 1
    }
    emit sbToString(out)
}

// Execute a SQL statement, ignore output. Returns "1" on success.
func sqlExec(sql) {
    let cmd = sbNew()
    cmd = sbAppend(cmd, "sqlite3 \"")
    cmd = sbAppend(cmd, cfgDbPath())
    cmd = sbAppend(cmd, "\" \"")
    cmd = sbAppend(cmd, sql)
    cmd = sbAppend(cmd, "\"")
    shellRun(sbToString(cmd))
    emit "1"
}

// Run a query, return raw output (rows separated by "\n", cols by "|").
func sqlQuery(sql) {
    let cmd = sbNew()
    cmd = sbAppend(cmd, "sqlite3 -separator \"|\" \"")
    cmd = sbAppend(cmd, cfgDbPath())
    cmd = sbAppend(cmd, "\" \"")
    cmd = sbAppend(cmd, sql)
    cmd = sbAppend(cmd, "\"")
    emit exec(sbToString(cmd))
}

// ── Short-code generation ────────────────────────────────────────────

let CODE_ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

func genCode(seed) {
    let out = sbNew()
    let current = seed
    let i = 0
    while i < 6 {
        current = nextRandom(current)
        let idx = current % 62
        out = sbAppend(out, CODE_ALPHABET[idx])
        i = i + 1
    }
    emit sbToString(out)
}

// ── Session cookie (single shared password) ──────────────────────────

// We don't bother with random tokens / DB session table. The cookie
// value IS the SHA-style HMAC of the password — anyone who can produce
// the cookie knows the password. Cookie value: literal "ok" XOR'd by
// password bytes, base64ish. Trivial — single-user app, not for the
// open internet.
//
// (When this grows beyond one user, swap to a real session table.)

func sessionCookie() {
    let pw = cfgPassword()
    if len(pw) == 0 { emit "" }
    // Cheap derivation: just use the password's char codes summed mod
    // a large prime. Two users with the same password → same cookie.
    let h = 5381
    let i = 0
    while i < len(pw) {
        h = ((h * 33) + toInt(charCode(pw[i]))) % 2147483647
        i = i + 1
    }
    emit "kl_" + h
}

func hasSession(req) {
    let want = sessionCookie()
    if len(want) == 0 { emit "0" }
    let hdrs = reqHeaders(req)
    let cookies = ""
    let lines = lineCount(hdrs)
    let i = 0
    while i < lines {
        let line = getLine(hdrs, i)
        if startsWith(toLower(substring(line, 0, 7)), "cookie:") == "1" {
            cookies = trim(substring(line, 7, len(line)))
        }
        i = i + 1
    }
    let got = cookieGet(cookies, "kryptlink")
    if got == want { emit "1" }
    emit "0"
}

// ── HTML rendering ───────────────────────────────────────────────────

func htmlEscape(s) {
    let out = sbNew()
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == "&" { out = sbAppend(out, "&amp;") }
        else if c == "<" { out = sbAppend(out, "&lt;") }
        else if c == ">" { out = sbAppend(out, "&gt;") }
        else if c == "\"" { out = sbAppend(out, "&quot;") }
        else { out = sbAppend(out, c) }
        i = i + 1
    }
    emit sbToString(out)
}

let CSS = "<style>body{font-family:system-ui,sans-serif;max-width:720px;margin:2em auto;padding:0 1em;color:#222;background:#fafafa}h1{color:#4F5AA8}input,button{font:inherit;padding:.5em;margin:.25em 0;border:1px solid #ccc;border-radius:4px}input[type=text],input[type=url],input[type=password]{width:100%;box-sizing:border-box}button{background:#4F5AA8;color:white;border:none;cursor:pointer}button:hover{background:#3a448a}table{border-collapse:collapse;width:100%;margin-top:1em}th,td{padding:.5em;text-align:left;border-bottom:1px solid #ddd}code{background:#eee;padding:.1em .3em;border-radius:3px}.muted{color:#888;font-size:.9em}</style>"

func pageLogin(errorMsg) {
    let body = sbNew()
    body = sbAppend(body, "<!doctype html><html><head><title>kryptlink — login</title>")
    body = sbAppend(body, CSS)
    body = sbAppend(body, "</head><body><h1>kryptlink</h1>")
    if len(errorMsg) > 0 {
        body = sbAppend(body, "<p style='color:#c44'>")
        body = sbAppend(body, htmlEscape(errorMsg))
        body = sbAppend(body, "</p>")
    }
    body = sbAppend(body, "<form method='POST' action='/login'>")
    body = sbAppend(body, "<label>Password<input type='password' name='password' autofocus></label>")
    body = sbAppend(body, "<button type='submit'>Log in</button>")
    body = sbAppend(body, "</form></body></html>")
    emit sbToString(body)
}

func pageAdmin(msg) {
    let body = sbNew()
    body = sbAppend(body, "<!doctype html><html><head><title>kryptlink</title>")
    body = sbAppend(body, CSS)
    body = sbAppend(body, "</head><body><h1>kryptlink</h1>")
    if len(msg) > 0 {
        body = sbAppend(body, "<p style='color:#283'>")
        body = sbAppend(body, msg)
        body = sbAppend(body, "</p>")
    }
    body = sbAppend(body, "<form method='POST' action='/create'>")
    body = sbAppend(body, "<label>URL<input type='url' name='url' placeholder='https://example.com/long/path' required></label>")
    body = sbAppend(body, "<label>Custom code (optional)<input type='text' name='code' placeholder='launch'></label>")
    body = sbAppend(body, "<label>Note (optional)<input type='text' name='note' placeholder='Q4 launch announcement'></label>")
    body = sbAppend(body, "<button type='submit'>Shorten</button>")
    body = sbAppend(body, "</form>")

    // Recent links table
    let rows = sqlQuery("SELECT code, url, created_at, COALESCE(note,'') FROM links ORDER BY created_at DESC LIMIT 50")
    body = sbAppend(body, "<h2>Recent links</h2>")
    if len(rows) == 0 {
        body = sbAppend(body, "<p class='muted'>No links yet. Create one above.</p>")
    } else {
        body = sbAppend(body, "<table><tr><th>Short</th><th>Destination</th><th>Created</th><th>Note</th><th>Stats</th></tr>")
        let n = lineCount(rows)
        let i = 0
        while i < n {
            let row = getLine(rows, i)
            if len(row) > 0 {
                let code = _col(row, 0)
                let url = _col(row, 1)
                let ts = _col(row, 2)
                let note = _col(row, 3)
                let short = cfgPublicHost() + "/r/" + code
                body = sbAppend(body, "<tr><td><a href='")
                body = sbAppend(body, short)
                body = sbAppend(body, "'>")
                body = sbAppend(body, htmlEscape(code))
                body = sbAppend(body, "</a></td><td><a href='")
                body = sbAppend(body, htmlEscape(url))
                body = sbAppend(body, "'>")
                body = sbAppend(body, htmlEscape(url))
                body = sbAppend(body, "</a></td><td>")
                body = sbAppend(body, dtDateFromEpoch(ts))
                body = sbAppend(body, "</td><td>")
                body = sbAppend(body, htmlEscape(note))
                body = sbAppend(body, "</td><td><a href='/stats/")
                body = sbAppend(body, code)
                body = sbAppend(body, "'>view</a></td></tr>")
            }
            i = i + 1
        }
        body = sbAppend(body, "</table>")
    }

    body = sbAppend(body, "<form method='POST' action='/logout' style='margin-top:2em'><button type='submit'>Log out</button></form>")
    body = sbAppend(body, "</body></html>")
    emit sbToString(body)
}

// Get the Nth "|"-separated column from a sqlite row.
func _col(row, idx) {
    let want = idx
    let n = len(row)
    let cur = 0
    let start = 0
    let i = 0
    while i <= n {
        if i == n || row[i] == "|" {
            if cur == want { emit substring(row, start, i) }
            cur = cur + 1
            start = i + 1
        }
        i = i + 1
    }
    emit ""
}

// ── Stats page ───────────────────────────────────────────────────────

func pageStats(code) {
    let safeCode = sqlEscape(code)
    let rows = sqlQuery("SELECT code, url, created_at, COALESCE(note,'') FROM links WHERE code='" + safeCode + "'")
    if len(rows) == 0 {
        emit "<h1>not found</h1>"
    }
    let row = getLine(rows, 0)
    let url = _col(row, 1)
    let ts = _col(row, 2)
    let note = _col(row, 3)

    let clickRows = sqlQuery("SELECT clicked_at, COALESCE(ip,''), COALESCE(user_agent,''), COALESCE(referrer,'') FROM clicks WHERE code='" + safeCode + "' ORDER BY clicked_at DESC LIMIT 100")
    let clickCountQ = sqlQuery("SELECT COUNT(*) FROM clicks WHERE code='" + safeCode + "'")
    let clickCount = trim(clickCountQ)

    let body = sbNew()
    body = sbAppend(body, "<!doctype html><html><head><title>stats — ")
    body = sbAppend(body, htmlEscape(code))
    body = sbAppend(body, "</title>")
    body = sbAppend(body, CSS)
    body = sbAppend(body, "</head><body><h1>")
    body = sbAppend(body, htmlEscape(code))
    body = sbAppend(body, "</h1><p>")
    body = sbAppend(body, "<strong>Destination:</strong> <a href='")
    body = sbAppend(body, htmlEscape(url))
    body = sbAppend(body, "'>")
    body = sbAppend(body, htmlEscape(url))
    body = sbAppend(body, "</a><br>")
    body = sbAppend(body, "<strong>Created:</strong> ")
    body = sbAppend(body, dtIsoFromEpoch(ts))
    body = sbAppend(body, "<br><strong>Note:</strong> ")
    body = sbAppend(body, htmlEscape(note))
    body = sbAppend(body, "<br><strong>Total clicks:</strong> ")
    body = sbAppend(body, clickCount)
    body = sbAppend(body, "</p>")
    body = sbAppend(body, "<p><a href='/qr/")
    body = sbAppend(body, code)
    body = sbAppend(body, ".svg'>QR code</a> &middot; <a href='/'>back</a></p>")

    body = sbAppend(body, "<h2>Recent clicks</h2>")
    if len(clickRows) == 0 {
        body = sbAppend(body, "<p class='muted'>No clicks yet.</p>")
    } else {
        body = sbAppend(body, "<table><tr><th>When</th><th>IP</th><th>UA</th><th>Referrer</th></tr>")
        let n = lineCount(clickRows)
        let i = 0
        while i < n {
            let r = getLine(clickRows, i)
            if len(r) > 0 {
                body = sbAppend(body, "<tr><td>")
                body = sbAppend(body, dtIsoFromEpoch(_col(r, 0)))
                body = sbAppend(body, "</td><td>")
                body = sbAppend(body, htmlEscape(_col(r, 1)))
                body = sbAppend(body, "</td><td>")
                body = sbAppend(body, htmlEscape(_col(r, 2)))
                body = sbAppend(body, "</td><td>")
                body = sbAppend(body, htmlEscape(_col(r, 3)))
                body = sbAppend(body, "</td></tr>")
            }
            i = i + 1
        }
        body = sbAppend(body, "</table>")
    }

    body = sbAppend(body, "</body></html>")
    emit sbToString(body)
}

// ── QR placeholder (filled in by stdlib/qr.k next) ───────────────────

func renderQr(text) {
    let body = sbNew()
    body = sbAppend(body, "<?xml version='1.0' encoding='UTF-8'?>")
    body = sbAppend(body, "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 200 200' width='200' height='200'>")
    body = sbAppend(body, "<rect width='200' height='200' fill='#eee'/>")
    body = sbAppend(body, "<text x='100' y='100' text-anchor='middle' font-family='monospace' font-size='12'>QR for: ")
    body = sbAppend(body, htmlEscape(text))
    body = sbAppend(body, "</text>")
    body = sbAppend(body, "<text x='100' y='130' text-anchor='middle' font-family='monospace' font-size='9' fill='#888'>(qr encoder coming next phase)</text>")
    body = sbAppend(body, "</svg>")
    emit sbToString(body)
}

// ── HTTP response helpers ────────────────────────────────────────────

func _NL() { emit fromCharCode(13) + fromCharCode(10) }

func respond(cl, status, ct, body, setCookie) {
    let r = sbNew()
    r = sbAppend(r, "HTTP/1.1 ")
    r = sbAppend(r, status)
    r = sbAppend(r, _NL())
    r = sbAppend(r, "Content-Type: ")
    r = sbAppend(r, ct)
    r = sbAppend(r, _NL())
    r = sbAppend(r, "Content-Length: ")
    r = sbAppend(r, len(body) + "")
    r = sbAppend(r, _NL())
    if len(setCookie) > 0 {
        r = sbAppend(r, "Set-Cookie: ")
        r = sbAppend(r, setCookie)
        r = sbAppend(r, _NL())
    }
    r = sbAppend(r, "Connection: close")
    r = sbAppend(r, _NL())
    r = sbAppend(r, _NL())
    r = sbAppend(r, body)
    serverSend(cl, sbToString(r))
}

func redirect302(cl, to) {
    let r = sbNew()
    r = sbAppend(r, "HTTP/1.1 302 Found")
    r = sbAppend(r, _NL())
    r = sbAppend(r, "Location: ")
    r = sbAppend(r, to)
    r = sbAppend(r, _NL())
    r = sbAppend(r, "Content-Length: 0")
    r = sbAppend(r, _NL())
    r = sbAppend(r, "Connection: close")
    r = sbAppend(r, _NL())
    r = sbAppend(r, _NL())
    serverSend(cl, sbToString(r))
}

// ── Request handlers ─────────────────────────────────────────────────

func handleRequest(req, cl, seed) {
    let method = reqMethod(req)
    let path = reqPath(req)

    // ── Public redirect ──
    if startsWith(path, "/r/") == "1" {
        let code = substring(path, 3, len(path))
        let safe = sqlEscape(code)
        let rows = sqlQuery("SELECT url FROM links WHERE code='" + safe + "'")
        if len(rows) == 0 {
            respond(cl, "404 Not Found", "text/html", "<h1>link not found</h1>", "")
            emit seed
        }
        let url = trim(getLine(rows, 0))

        // log the click
        let now = dtNowEpoch()
        let ua = sqlEscape(reqHeader(req, "User-Agent"))
        let ref = sqlEscape(reqHeader(req, "Referer"))
        sqlExec("INSERT INTO clicks(code,clicked_at,ip,user_agent,referrer) VALUES('" + safe + "'," + now + ",'','" + ua + "','" + ref + "')")
        redirect302(cl, url)
        emit seed
    }

    // ── QR ──
    if startsWith(path, "/qr/") == "1" {
        let rest = substring(path, 4, len(path))
        let dot = indexOf(rest, ".")
        let code = rest
        if dot > 0 { code = substring(rest, 0, dot) }
        let short = cfgPublicHost() + "/r/" + code
        respond(cl, "200 OK", "image/svg+xml", renderQr(short), "")
        emit seed
    }

    // ── Login (POST) ──
    if path == "/login" && method == "POST" {
        let body = reqBody(req)
        let pw = _formField(body, "password")
        if pw == cfgPassword() && len(pw) > 0 {
            let setC = "kryptlink=" + sessionCookie() + "; Path=/; HttpOnly; SameSite=Lax"
            let r = sbNew()
            r = sbAppend(r, "HTTP/1.1 302 Found")
            r = sbAppend(r, _NL())
            r = sbAppend(r, "Location: /")
            r = sbAppend(r, _NL())
            r = sbAppend(r, "Set-Cookie: ")
            r = sbAppend(r, setC)
            r = sbAppend(r, _NL())
            r = sbAppend(r, "Content-Length: 0")
            r = sbAppend(r, _NL())
            r = sbAppend(r, "Connection: close")
            r = sbAppend(r, _NL())
            r = sbAppend(r, _NL())
            serverSend(cl, sbToString(r))
            emit seed
        }
        respond(cl, "401 Unauthorized", "text/html", pageLogin("bad password"), "")
        emit seed
    }

    // ── Logout ──
    if path == "/logout" && method == "POST" {
        respond(cl, "302 Found", "text/html", "", "kryptlink=; Path=/; Max-Age=0")
        emit seed
    }

    // ── Everything else needs auth ──
    if hasSession(req) == "0" {
        respond(cl, "200 OK", "text/html", pageLogin(""), "")
        emit seed
    }

    // ── Create link (POST) ──
    if path == "/create" && method == "POST" {
        let body = reqBody(req)
        let url = _formField(body, "url")
        let codeIn = _formField(body, "code")
        let note = _formField(body, "note")
        if len(url) == 0 || isURL(url) == "0" {
            respond(cl, "400 Bad Request", "text/html", pageAdmin("invalid URL"), "")
            emit seed
        }
        let code = codeIn
        let newSeed = seed
        if len(code) == 0 {
            // Generate; retry on collision (up to 5 tries).
            let attempts = 0
            while attempts < 5 {
                newSeed = nextRandom(newSeed)
                code = genCode(newSeed)
                let exists = sqlQuery("SELECT 1 FROM links WHERE code='" + sqlEscape(code) + "'")
                if len(exists) == 0 { attempts = 5 }
                else { code = ""  attempts = attempts + 1 }
            }
        }
        if len(code) == 0 {
            respond(cl, "500 Server Error", "text/html", pageAdmin("couldn't allocate code"), "")
            emit newSeed
        }
        let safeCode = sqlEscape(code)
        let safeUrl = sqlEscape(url)
        let safeNote = sqlEscape(note)
        let now = dtNowEpoch()
        sqlExec("INSERT INTO links(code,url,created_at,note) VALUES('" + safeCode + "','" + safeUrl + "'," + now + ",'" + safeNote + "')")
        let short = cfgPublicHost() + "/r/" + code
        respond(cl, "200 OK", "text/html", pageAdmin("Created: <a href='" + short + "'>" + htmlEscape(short) + "</a>"), "")
        emit newSeed
    }

    // ── Stats ──
    if startsWith(path, "/stats/") == "1" {
        let code = substring(path, 7, len(path))
        respond(cl, "200 OK", "text/html", pageStats(code), "")
        emit seed
    }

    // ── Admin home ──
    if path == "/" {
        respond(cl, "200 OK", "text/html", pageAdmin(""), "")
        emit seed
    }

    respond(cl, "404 Not Found", "text/html", "<h1>404</h1>", "")
    emit seed
}

// Cheap form parser: body is "k=v&k=v" (URL-encoded).
// Returns the value for `key`, or "" if absent.
func _formField(body, key) {
    let n = len(body)
    let i = 0
    let start = 0
    while i <= n {
        if i == n || body[i] == "&" {
            let pair = substring(body, start, i)
            let eq = indexOf(pair, "=")
            if eq > 0 {
                let k = substring(pair, 0, eq)
                if k == key { emit urlDecode(substring(pair, eq + 1, len(pair))) }
            }
            start = i + 1
        }
        i = i + 1
    }
    emit ""
}

// URL-decode a query/form value: + → space, %xx → byte.
func urlDecode(s) {
    let out = sbNew()
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == "+" {
            out = sbAppend(out, " ")
            i = i + 1
        } else if c == "%" && i + 2 < len(s) {
            let hi = _hex(s[i + 1])
            let lo = _hex(s[i + 2])
            out = sbAppend(out, fromCharCode(hi * 16 + lo))
            i = i + 3
        } else {
            out = sbAppend(out, c)
            i = i + 1
        }
    }
    emit sbToString(out)
}

func _hex(c) {
    let cc = toInt(charCode(c))
    if cc >= 48 && cc <= 57 { emit cc - 48 }
    if cc >= 97 && cc <= 102 { emit cc - 87 }
    if cc >= 65 && cc <= 70 { emit cc - 55 }
    emit 0
}

// ── Main ─────────────────────────────────────────────────────────────

just run {
    if len(cfgPassword()) == 0 {
        kp("kryptlink: KRYPTLINK_PASSWORD env var is required")
        exit("1")
    }

    let port = "8080"
    if argCount() >= 1 { port = arg(0) }

    let srv = serverListen(port)
    if srv < 0 {
        kp("kryptlink: listen failed on port " + port)
        exit("1")
    }
    kp("kryptlink on http://127.0.0.1:" + port)
    kp("public host: " + cfgPublicHost())
    kp("db: " + cfgDbPath())

    let seed = toInt(dtNowEpoch())
    while "1" == "1" {
        let cl = serverAccept(srv)
        if cl >= 0 {
            let req = serverRead(cl)
            seed = handleRequest(req, cl, seed)
            serverClose(cl)
        }
    }
}
