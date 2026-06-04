// stdlib/cookie.k — HTTP cookie parse + build in pure Krypton.
//
// Parses a single Cookie: request header value (`a=1; b=2`) into a
// key→value map for lookups, and builds Set-Cookie: response headers
// with the common attributes (Path, Domain, Max-Age, Expires, Secure,
// HttpOnly, SameSite). Companion to k:server_native and k:http.
//
// API:
//   cookieGet(header, name)      -> value or ""  (Cookie: header parse)
//   cookieParse(header)          -> "k1=v1,k2=v2" (comma-list, Krypton convention)
//   cookieBuild(name, value)     -> "name=value"  (just the pair)
//   cookieSet(name, value, opts) -> Set-Cookie: value string with attrs
//
// `opts` is a comma-separated string of `attr=val` (or bare flags) e.g.
//   "Path=/, Max-Age=3600, HttpOnly, SameSite=Lax"

module cookie

func _trim(s) {
    let i = 0
    let n = len(s)
    while i < n && charCode(s[i]) <= 32 { i += 1 }
    let j = n
    while j > i && charCode(s[j - 1]) <= 32 { j -= 1 }
    emit substring(s, i, j)
}

func cookieGet(header, name) {
    let needle = name + "="
    let p = indexOf(header, needle)
    if p < 0 { emit "" }
    // Must be at start OR preceded by "; " (avoid prefix-collision).
    if p > 0 {
        let prev = header[p - 1]
        if prev != " " && prev != ";" { emit "" }
    }
    let after = substring(header, p + len(needle), len(header))
    let semi = indexOf(after, ";")
    if semi >= 0 { emit _trim(substring(after, 0, semi)) }
    emit _trim(after)
}

// cookieParse: walks "a=1; b=2; c=3" → "a=1,b=2,c=3" (Krypton comma-list).
// Caller can then iterate or hand to k:fp helpers.
func cookieParse(header) {
    let out = ""
    let i = 0
    let n = len(header)
    let cur = ""
    while i < n {
        let c = header[i]
        if c == ";" {
            if len(out) > 0 { out = out + "," }
            out = out + _trim(cur)
            cur = ""
        } else { cur = cur + c }
        i += 1
    }
    if len(cur) > 0 {
        if len(out) > 0 { out = out + "," }
        out = out + _trim(cur)
    }
    emit out
}

func cookieBuild(name, value) { emit name + "=" + value }

// Translates "Path=/, Max-Age=3600, HttpOnly, SameSite=Lax" into the
// `; Attr=Val; Flag; ...` suffix appended to the cookie pair.
func _renderAttrs(opts) {
    let out = ""
    let i = 0
    let n = len(opts)
    let cur = ""
    while i <= n {
        let atEnd = 0
        if i == n { atEnd = 1 }
        if atEnd == 1 || opts[i] == "," {
            let trimmed = _trim(cur)
            if len(trimmed) > 0 { out = out + "; " + trimmed }
            cur = ""
        } else { cur = cur + opts[i] }
        i += 1
    }
    emit out
}

func cookieSet(name, value, opts) {
    emit name + "=" + value + _renderAttrs(opts)
}
