# Krypton Web Router Design (`stdlib/router.k`)

Design notes, 2026-05-28. No implementation yet — this locks the API and
the dispatch model so `router.k` can be built from it in a later session.

Goal: move the `.htk` web framework toward Express/Node-shaped ergonomics
("JS-like robustness") without language changes. Today every app
hand-writes an `if path == "/x"` ladder inside the `serverNext()` loop (see
`web/kweb.htk`, `web/examples/interactive.htk`). The router replaces that
ladder with a registered route table, path params, a middleware chain, and
a path-traversal-safe static handler.

---

## Feasibility (why this works with no compiler changes)

**Status: implemented in `stdlib/router.k`, demo `web/examples/router.htk`,
verified end-to-end (path params, query, POST form, JSON, 404, 405+Allow,
middleware).**

The handler-storage question turned out subtler than first sketched, and
the original plan (store funcptrs in a `map.k` string table) is WRONG —
recorded here so it isn't retried:

- `funcptr(fn)` returns the **raw code pointer** (`((char*)fn)`), not a
  decimal string. `callPtr(p, a, b)` casts that pointer straight back to a
  function and calls it. Multi-arg + return-value capture both work for
  Krypton functions.
- A funcptr **cannot** be stored in a string map. Concatenating a raw code
  pointer into `"key=" + val` makes Krypton treat the pointer as a C string
  and copy the *machine-code bytes* at that address — the address value is
  lost, and the later `callPtr` segfaults. (`gui.k` only survives this
  because `guiState` is a *native* pointer-preserving store, and it's
  Windows/gui-bound — not usable from a portable server module.)
- The portable fix: a Krypton **env** (`envNew`/`envSet`/`envGet`) preserves
  raw pointers (see `stdlib/mmap.k`, which stores `LPVOID`s this way). The
  route table is an env. `envSet` is a *value type* — every builder
  reassigns (`app = appGet(app, ...)`). An iterable key-list lives in the
  same env under `__routes` as a plain newline string (strings are safe);
  dispatch walks it, `envGet`s each key to the funcptr, and `callPtr`s it.

Primitives relied on, all already shipped: `funcptr`, `callPtr` (multi-arg +
return capture), `envNew`/`envSet`/`envGet`, `lineCount`/`getLine`,
`substring`/`indexOf`/`startsWith`. No new runtime support needed.

The path-param map (`reqParam`) is a separate `key=val\n` string built by the
matcher — that one holds only strings, so string storage is fine there.

---

## Handler shape

Decided: handlers **call the response themselves** (Express `res.send`
style), not "return a body and let the router send it".

```
func showUser(req, res) {
    let id = reqParam(req, "id")
    resSend(res, htPage("User", "", htP("user " + id)))
}
```

`callPtr(handler, req, res)` passes both. `req` and `res` are string handles
(serialized maps), consistent with every other Krypton collection.

### `req` — serialized request map

Built once per request from the existing `server.k` accessors and passed to
the handler. Fields:

- `method`  — from `serverReqMethod()`
- `path`    — from `serverReqPath()`
- `query`   — raw query string (`serverReqQuery()`)
- `body`    — raw body (`serverReqBody()`)
- `params`  — `:name` captures from the matched route, packed as a sub-map
- plus lazy accessors that wrap existing helpers.

Accessor wrappers (thin, so handlers never touch the raw map encoding):

```
reqMethod(req)        reqPath(req)
reqParam(req, name)     // path param  → uses params sub-map
reqQuery(req, key)      // wraps queryParam(req.query, key)
reqBody(req)            reqForm(req, key)   // queryParam over urlencoded body
reqCookie(req, name)    // wraps serverReqCookie
reqHeader(req, name)    // wraps serverReqHeader
```

### `res` — deferred-response handle

`server.k` response functions already target the current client socket
(global state), so `res` does not own the socket. It carries *deferred*
status + headers so `resStatus`/`resHeader`/`resCookie` can compose before
the body flush. Because Krypton passes by value, res helpers that mutate
must be threaded:

```
res = resStatus(res, "404")
res = resHeader(res, "X-Thing", "1")
resSend(res, body)        // flush: builds raw response, calls _srvRespondRaw
```

res API:

```
resSend(res, html)      → text/html        (flush)
resJson(res, jsonStr)   → application/json  (flush)
resText(res, s)         → text/plain        (flush)
resRedirect(res, url)   → 302 + Location    (flush; wraps serverRedirect)
resStatus(res, code)    → set status, returns res   (no flush)
resHeader(res, k, v)    → add header, returns res    (no flush)
resCookie(res, k, v, opts) → add Set-Cookie, returns res (no flush)
resFile(res, path)      → static file w/ mime (flush; wraps serverRespondFile)
```

`resSend`/`resJson`/`resText` read the deferred status+headers off `res`,
assemble one raw HTTP response, and emit via `_srvRespondRaw` (so a custom
status like 404 ships with the body in a single write). The plain
`serverRespond*` helpers stay as the zero-ceremony path for apps that don't
need custom status/headers.

---

## Route table + matching

Table key: `"<METHOD> <pattern>"`, value: handler address.

```
appNew()                          → app (empty map handle)
appGet(app, pattern, addr)        → app
appPost(app, pattern, addr)       → app
appPut / appDelete / appPatch     → app
appUse(app, addr)                 → app   (middleware, order preserved)
appStatic(app, urlPrefix, dir)    → app
appRun(app, port)                 → never returns (accept loop)
```

Pattern segments, matched left-to-right against the request path split on
`/`:

- literal — `users` matches `users`
- `:name`  — captures one segment into `params[name]`
- `*`      — wildcard tail; captures the remainder into `params["*"]`

Matcher returns `(matched?, paramsSubmap)`. Segment counts must match unless
the pattern ends in `*`. First registered match wins (insertion order
preserved by appending to the map).

Status fallbacks during dispatch:

- no path match for any method → **404** (`resStatus` 404 + default body)
- path matches but method does not → **405** with an `Allow` header listing
  the methods registered for that path.

---

## Middleware chain

`appUse` registers handler addresses run in order *before* route dispatch.
Each middleware has the handler signature and signals continuation by its
emitted value:

```
func logger(req, res) {
    printErr(reqMethod(req) + " " + reqPath(req))
    emit "next"          // continue chain
}
```

Protocol: a middleware that emits `"next"` continues; anything else (or a
flush via `resSend`) short-circuits — the router stops and assumes the
middleware produced the response. This is the minimal Express
`next()` model without needing real continuation passing.

Use cases this unlocks: request logging, auth gates, CORS, body-size limits.

---

## `appStatic` — and the traversal fix

`web/kweb.htk:152` currently does `filePath = "dist" + path` straight from
the request — `GET /../../etc/passwd` (or `..\..\` on Windows) escapes the
web root. `appStatic` must, before any `fopen`:

1. reject the request if any path segment equals `..` (after splitting on
   both `/` and `\`),
2. reject NUL bytes / control chars,
3. only then join `dir + normalizedPath` and call `serverRespondFile`.

This also retro-fixes the static path in `kweb serve` once it adopts the
router.

---

## Dispatch loop (what `appRun` does)

```
serverInit(port)
while "1" == "1" {
    if serverNext() == "1" {
        let req = _reqBuild(app)          // capture method/path/query/body
        let res = _resNew()
        if _runMiddleware(app, req, res) == "next" {   // chain
            _dispatch(app, req, res)       // match route → callPtr(addr,req,res)
        }
        // if nothing flushed, _dispatch sent 404/405
    }
}
```

Single-threaded, one-request-at-a-time, `Connection: close` — unchanged from
today's `server.k`. Concurrency is a separate, later effort (would need
C-side poll/threads in `server.k`).

---

## Example app (target ergonomics)

```
import "k:htmk"
import "k:server"
import "k:router"

func logger(req, res) { printErr(reqMethod(req) + " " + reqPath(req)); emit "next" }
func home(req, res)   { resSend(res, htPage("Home", "", htH1("hi"))) }
func user(req, res)   { resSend(res, htP("user " + reqParam(req, "id"))) }
func missing(req, res){ res = resStatus(res, "404"); resSend(res, htH1("nope")) }

just run {
    let app = appNew()
    app = appUse(app,    funcptr(logger))
    app = appGet(app,    "/",         funcptr(home))
    app = appGet(app,    "/user/:id", funcptr(user))
    app = appStatic(app, "/assets",   "dist/assets")
    appRun(app, "8080")
}
```

---

## Scope boundary

In scope for `router.k`: route table, `:param`/`*` matching, middleware
chain, `req`/`res` handles + accessor/helper wrappers, `appStatic` with
traversal guard, 404/405.

Out of scope (bolt onto the router later, each its own module):

- `session.k` — server-side session store over a cookie id + `map.k`.
- multipart/form-data + file upload parsing (`form.k`).
- SSE / live updates — needs a C addition in `server.k`: the current model
  closes the socket after every respond; SSE must keep it open and stream
  `text/event-stream`. Pairs with the htmx attrs already in `htmk.k`.
- `http.k` client: PUT/DELETE/PATCH + combined status/headers/body return.
- `kr_mime` additions (`.webp .avif .mp4 .xml .mjs .map`) and clear-cookie /
  multi-cookie helpers.

## Decisions / open questions

1. **`res` model — RESOLVED: immediate-flush, no deferred state.** Each
   `res*` helper flushes via the matching `k:server` call (`resStatus` takes
   the body and a status code and sends in one shot). Avoids the
   by-value-reassignment footgun and needs no global. The `res` value is a
   reserved handle (currently `""`).
2. **Trailing slash — RESOLVED: same route.** The matcher normalizes by
   consuming both sides segment-by-segment, so `/user` and `/user/` match
   the same pattern.
3. Still open: should `appStatic` auto-serve `index.html` for a directory
   request? (today a bare-dir request just 404s when `serverRespondFile`
   can't open it.) Deferred until a real use appears.
