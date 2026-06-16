// admin.k -- Krypton-native blog admin for krypton-lang.org.
// Runs on the kry.li VPS, listens on 127.0.0.1:8088, fronted by nginx
// at https://admin.krypton-lang.org.
//
// State files (created on demand):
//   /opt/krypton-admin/pwhash    sha256 of "salt:" + password
//   /opt/krypton-admin/secret    32-byte hex, HMAC server secret
//   /opt/krypton-admin/krypton/  git clone of t3m3d/krypton (docs/blog content)
//
// Routes:
//   GET  /             -> list posts, "+ new" button (auth)
//   GET  /login        -> login form (or first-run setup form)
//   POST /login        -> set session cookie if password matches
//   POST /setup        -> first-run: store password hash
//   GET  /new          -> blank editor (auth)
//   GET  /edit/:slug   -> existing-post editor (auth)
//   POST /save         -> write .md, git commit + push (auth)
//   GET  /logout       -> clear cookie

import "k:server_native"

// Module-level `let` constants are silently GC-reused in current Krypton
// (see feedback_module_mutable_globals.md). Wrap as zero-arg functions.
func PORT()       { emit "8088" }
func STATE_DIR()  { emit "/opt/krypton-admin" }
func REPO_DIR()   { emit "/opt/krypton-admin/krypton" }
func BLOG_DIR()   { emit "/opt/krypton-admin/krypton/docs/blog" }
func USER()       { emit "t3m3d" }
func SALT()       { emit "kryptoadmin-2026" }
func COOKIE()     { emit "kadmin" }

// ─── tiny utilities ────────────────────────────────────────────────────

func fileExistsSh(path) {
    let rc = shellRun("test -f " + path)
    if rc == "0" { emit "1" }
    emit "0"
}

func readFileSh(path) {
    emit readFile(path)
}

func writeFileSh(path, content) {
    writeFile(path, content)
    emit ""
}

func escapeForShell(s) {
    let out = ""
    let i = 0
    let n = len(s)
    while i < n {
        let c = s[i]
        if c == "\\" { out = out + "\\\\" }
        else if c == "\"" { out = out + "\\\"" }
        else if c == "$"  { out = out + "\\$" }
        else if c == "`"  { out = out + "\\`" }
        else              { out = out + c }
        i = i + 1
    }
    emit out
}

func htmlEscape(s) {
    let out = ""
    let i = 0
    let n = len(s)
    while i < n {
        let c = s[i]
        if      c == "&"  { out = out + "&amp;" }
        else if c == "<"  { out = out + "&lt;" }
        else if c == ">"  { out = out + "&gt;" }
        else if c == "\"" { out = out + "&quot;" }
        else              { out = out + c }
        i = i + 1
    }
    emit out
}

func sha256Hex(s) {
    let out = exec("printf '%s' \"" + escapeForShell(s) + "\" | sha256sum | awk '{print $1}'")
    emit trim(out)
}

func nowEpoch() {
    let out = exec("date +%s")
    emit trim(out)
}

func randHex() {
    let out = exec("head -c 32 /dev/urandom | sha256sum | awk '{print $1}'")
    emit trim(out)
}

// ─── auth ──────────────────────────────────────────────────────────────

func loadOrCreateSecret() {
    let p = STATE_DIR() + "/secret"
    if fileExistsSh(p) == "1" { emit trim(readFileSh(p)) }
    let s = randHex()
    writeFileSh(p, s)
    emit s
}

func loadPwhash() {
    let p = STATE_DIR() + "/pwhash"
    if fileExistsSh(p) == "1" { emit trim(readFileSh(p)) }
    emit ""
}

func savePwhash(pw) {
    writeFileSh(STATE_DIR() + "/pwhash", sha256Hex(SALT() + ":" + pw))
}

func makeSessionToken() {
    let exp = toInt(nowEpoch()) + 604800   // 7 days
    let payload = USER() + "|" + toStr(exp)
    let sig = sha256Hex(loadOrCreateSecret() + ":" + payload)
    emit payload + "|" + sig
}

func validateSession(cookie) {
    if len(cookie) == 0 { emit "0" }
    let parts = split(cookie, "|")
    if length(parts) < 3 { emit "0" }
    let user = getLine(parts, 0)
    let exp  = getLine(parts, 1)
    let sig  = getLine(parts, 2)
    if user != USER() { emit "0" }
    if toInt(exp) < toInt(nowEpoch()) { emit "0" }
    let expected = sha256Hex(loadOrCreateSecret() + ":" + user + "|" + exp)
    if sig != expected { emit "0" }
    emit "1"
}

func sessionFromReq(req) {
    let cookieHdr = reqHeader(req, "Cookie")
    if len(cookieHdr) == 0 { emit "" }
    // Cookie: kadmin=value; other=foo
    let p = indexOf(cookieHdr, COOKIE() + "=")
    if p < 0 { emit "" }
    let rest = substring(cookieHdr, p + len(COOKIE()) + 1, len(cookieHdr))
    let semi = indexOf(rest, ";")
    if semi >= 0 { emit substring(rest, 0, semi) }
    emit rest
}

func isAuthed(req) {
    emit validateSession(sessionFromReq(req))
}

// ─── HTML rendering ────────────────────────────────────────────────────

func page(title, body) {
    emit "<!doctype html><html lang=\"en\"><head>" +
         "<meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">" +
         "<title>" + htmlEscape(title) + " - Krypton Admin</title>" +
         "<style>" +
         "body{font-family:system-ui,sans-serif;max-width:780px;margin:2em auto;padding:0 1em;background:#0f0f17;color:#e4e4ec;line-height:1.5}" +
         "a{color:#8842ff;text-decoration:none}a:hover{text-decoration:underline}" +
         "h1{border-bottom:1px solid #2d2d40;padding-bottom:.3em;color:#fff}" +
         "input,textarea,button{font:inherit;background:#1a1a26;color:#e4e4ec;border:1px solid #2d2d40;border-radius:4px;padding:.5em .75em;box-sizing:border-box}" +
         "input[type=text],input[type=password],textarea{width:100%}" +
         "textarea{min-height:24em;font-family:Cascadia Code,Consolas,monospace;font-size:.9em}" +
         "button{background:#7722ff;border-color:#7722ff;color:#fff;cursor:pointer;padding:.6em 1.2em;font-weight:600}" +
         "button:hover{background:#5d16da}" +
         "form{margin:1em 0}label{display:block;margin:1em 0 .3em;color:#9a9aaa;font-size:.9em}" +
         ".post{display:block;padding:.8em 1em;border:1px solid #2d2d40;border-radius:6px;margin:.5em 0;background:#1a1a26}" +
         ".post:hover{border-color:#7722ff}.tag{color:#8842ff;font-size:.85em;margin-right:.7em}" +
         ".muted{color:#9a9aaa;font-size:.9em}" +
         "</style></head><body>" + body + "</body></html>"
}

func loginPage(msg) {
    let setup = loadPwhash() == ""
    let title = "Set password (first run)"
    let action = "/setup"
    let btn = "Set password"
    if setup == "0" {
        title = "Sign in"
        action = "/login"
        btn = "Sign in"
    }
    let warn = ""
    if len(msg) > 0 { warn = "<p style='color:#f38ba8'>" + htmlEscape(msg) + "</p>" }
    emit page(title,
        "<h1>" + title + "</h1>" + warn +
        "<form method=POST action=" + action + ">" +
        "<label>User</label><input type=text value=\"" + USER() + "\" disabled>" +
        "<label>Password</label><input type=password name=pw autofocus required>" +
        "<p><button type=submit>" + btn + "</button></p>" +
        "</form>"
    )
}

func listPostsHtml() {
    let raw = trim(exec("ls -1 " + BLOG_DIR() + "/*.md 2>/dev/null | sort -r"))
    if len(raw) == 0 { emit "<p class=muted>No posts yet.</p>" }
    let lines = raw
    let n = lineCount(lines)
    let out = ""
    let i = 0
    while i < n {
        let path = getLine(lines, i)
        let base = trim(exec("basename '" + path + "' .md"))
        let title = trim(exec("head -1 '" + path + "' | sed 's/^# *//'"))
        out = out + "<a class=post href=\"/edit/" + htmlEscape(base) + "\">" +
              "<span class=tag>" + htmlEscape(substring(base, 0, 10)) + "</span>" +
              htmlEscape(title) + "</a>"
        i = i + 1
    }
    emit out
}

func homePage() {
    emit page("Posts",
        "<h1>Krypton Blog Admin</h1>" +
        "<p><a href=\"/new\"><button>+ New post</button></a> " +
        "<a href=\"/logout\" class=muted>logout</a></p>" +
        listPostsHtml()
    )
}

func editorPage(slug, title, body, isNew) {
    let action = "/save"
    let h = "Edit post"
    if isNew == "1" { h = "New post" }
    emit page(h,
        "<h1>" + h + "</h1>" +
        "<p><a href=\"/\">&larr; back</a></p>" +
        "<form method=POST action=" + action + ">" +
        "<input type=hidden name=isnew value=\"" + isNew + "\">" +
        "<label>Slug (auto-prefixed with today's date if new)</label>" +
        "<input type=text name=slug value=\"" + htmlEscape(slug) + "\" required>" +
        "<label>Title</label>" +
        "<input type=text name=title value=\"" + htmlEscape(title) + "\" required>" +
        "<label>Body (markdown)</label>" +
        "<textarea name=body required>" + htmlEscape(body) + "</textarea>" +
        "<p><button type=submit>Save + publish</button></p>" +
        "</form>"
    )
}

// ─── route handlers ────────────────────────────────────────────────────

func handleLogin(req, client) {
    let pw = formValue(req, "pw")
    let stored = loadPwhash()
    if len(stored) == 0 {
        serveHtml(client, loginPage("First run: use /setup to set the password"))
        emit ""
    }
    if sha256Hex(SALT() + ":" + pw) != stored {
        serveHtml(client, loginPage("Wrong password."))
        emit ""
    }
    let token = makeSessionToken()
    let resp = "HTTP/1.1 302 Found\r\n" +
               "Location: /\r\n" +
               "Set-Cookie: " + COOKIE() + "=" + token + "; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=604800\r\n" +
               "Content-Length: 0\r\nConnection: close\r\n\r\n"
    serverSend(client, resp)
    emit ""
}

func handleSetup(req, client) {
    if loadPwhash() != "" {
        serveHtml(client, loginPage("Password already set. Use /login."))
        emit ""
    }
    let pw = formValue(req, "pw")
    if len(pw) < 8 {
        serveHtml(client, loginPage("Password must be 8+ characters."))
        emit ""
    }
    savePwhash(pw)
    serveHtml(client, loginPage("Password set. Sign in now."))
    emit ""
}

func handleSave(req, client) {
    let slug   = formValue(req, "slug")
    let title  = formValue(req, "title")
    let body   = formValue(req, "body")
    let isNew  = formValue(req, "isnew")

    let date = trim(exec("date +%Y-%m-%d"))
    let fullSlug = slug
    if isNew == "1" {
        // Prefix today's date if not already
        if substring(slug, 0, 10) != date {
            fullSlug = date + "-" + slug
        }
    }

    let mdPath = BLOG_DIR() + "/" + fullSlug + ".md"
    let mdBody = "# " + title + "\n\n**" + date + "**\n\n" + body + "\n"
    writeFileSh(mdPath, mdBody)

    // Commit + push (the GitHub Action picks it up and rebuilds + FTPs)
    let gitOut = exec(
        "cd " + REPO_DIR() + " && " +
        "git add docs/blog/" + fullSlug + ".md && " +
        "git -c user.email=admin@krypton-lang.org -c user.name='admin' commit -m 'blog: " + fullSlug + "' 2>&1 && " +
        "git push origin main 2>&1"
    )

    let body2 = "<h1>Saved</h1>" +
        "<p>Wrote <code>" + htmlEscape(mdPath) + "</code> and committed to git.</p>" +
        "<p>The GitHub Action will rebuild + deploy the site in ~60s.</p>" +
        "<pre style='background:#1a1a26;padding:1em;border-radius:4px;overflow-x:auto;font-size:.85em'>" +
        htmlEscape(gitOut) + "</pre>" +
        "<p><a href=\"/\">&larr; back to posts</a></p>"
    serveHtml(client, page("Saved", body2))
    emit ""
}

func handleEdit(req, client, slug) {
    let path = BLOG_DIR() + "/" + slug + ".md"
    if fileExistsSh(path) == "0" {
        serve404(client)
        emit ""
    }
    let content = readFileSh(path)
    // Pull title from first "# " line
    let firstLine = trim(getLine(content, 0))
    let title = ""
    if substring(firstLine, 0, 2) == "# " {
        title = substring(firstLine, 2, len(firstLine))
    }
    // Body = everything after the first blank line
    let body = ""
    let nl = lineCount(content)
    let i = 1
    let pastTitle = "0"
    while i < nl {
        let ln = getLine(content, i)
        if pastTitle == "0" {
            if len(trim(ln)) == 0 { pastTitle = "1" }
        } else {
            if len(body) > 0 { body = body + "\n" }
            body = body + ln
        }
        i = i + 1
    }
    serveHtml(client, editorPage(slug, title, body, "0"))
    emit ""
}

func handleLogout(client) {
    let resp = "HTTP/1.1 302 Found\r\n" +
               "Location: /login\r\n" +
               "Set-Cookie: " + COOKIE() + "=; Path=/; Max-Age=0\r\n" +
               "Content-Length: 0\r\nConnection: close\r\n\r\n"
    serverSend(client, resp)
    emit ""
}

// ─── dispatch ──────────────────────────────────────────────────────────

func dispatch(req, client) {
    let method = reqMethod(req)
    let path   = reqPath(req)

    // Always-open routes
    if path == "/login" {
        if method == "POST" { handleLogin(req, client)  emit "" }
        serveHtml(client, loginPage(""))
        emit ""
    }
    if path == "/setup" && method == "POST" {
        handleSetup(req, client)
        emit ""
    }

    // Everything else needs auth
    if isAuthed(req) == "0" {
        serverSend(client, redirect("/login"))
        emit ""
    }

    if path == "/" {
        serveHtml(client, homePage())
        emit ""
    }
    if path == "/new" {
        serveHtml(client, editorPage("", "", "", "1"))
        emit ""
    }
    if path == "/logout" {
        handleLogout(client)
        emit ""
    }
    if path == "/save" && method == "POST" {
        handleSave(req, client)
        emit ""
    }
    // /edit/<slug>
    if startsWith(path, "/edit/") {
        let slug = substring(path, 6, len(path))
        handleEdit(req, client, slug)
        emit ""
    }

    serve404(client)
}

// ─── main ─────────────────────────────────────────────────────────────

just run {
    let sock = serverListen(PORT())
    if sock < 0 {
        print("ERROR: serverListen failed on " + PORT())
        exit("1")
    }
    print("[admin] listening on 127.0.0.1:" + PORT())

    while toInt("1") == 1 {
        let client = serverAccept(sock)
        if client >= 0 {
            let req = serverRead(client)
            dispatch(req, client)
        }
    }
}
