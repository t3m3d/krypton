// URL encoding / decoding — RFC 3986 percent-encoding plus the
// query-string helpers callers actually reach for. Closes the
// Python `urllib.parse.quote` / `unquote` / `urlencode` gap.
//
// Pure Krypton, zero syscalls — safe on every platform.
module url

// Lower-nibble hex digit (0-15 → "0".."F").
func _url_hex(n) {
    if n < 10 { emit fromCharCode((48 + n) + "") }
    emit fromCharCode((55 + n) + "")
}

// True for chars that survive percent-encoding unchanged (RFC 3986
// unreserved set: A-Z a-z 0-9 - _ . ~).
func _url_safe(c) {
    if c >= "A" && c <= "Z" { emit "1" }
    if c >= "a" && c <= "z" { emit "1" }
    if c >= "0" && c <= "9" { emit "1" }
    if c == "-" || c == "_" || c == "." || c == "~" { emit "1" }
    emit "0"
}

// urlEncode(s)  — percent-encode every reserved byte (incl. space → %20).
// Use for path segments. For query-string values, prefer urlEncodeQuery
// which encodes space as `+` per application/x-www-form-urlencoded.
func urlEncode(s) {
    let out = sbNew()
    let i = 0
    while i < len(s) {
        let c = s[i]
        if _url_safe(c) == "1" {
            out = sbAppend(out, c)
        } else {
            let b = toInt(charCode(c))
            out = sbAppend(out, "%")
            out = sbAppend(out, _url_hex(b / 16))
            out = sbAppend(out, _url_hex(b % 16))
        }
        i += 1
    }
    emit sbToString(out)
}

func urlEncodeQuery(s) {
    let out = sbNew()
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == " " {
            out = sbAppend(out, "+")
        } else if _url_safe(c) == "1" {
            out = sbAppend(out, c)
        } else {
            let b = toInt(charCode(c))
            out = sbAppend(out, "%")
            out = sbAppend(out, _url_hex(b / 16))
            out = sbAppend(out, _url_hex(b % 16))
        }
        i += 1
    }
    emit sbToString(out)
}

// Hex digit char ('0'..'F' / 'a'..'f') → int; -1 on failure.
func _url_unhex(c) {
    if c >= "0" && c <= "9" { emit toInt(charCode(c)) - 48 }
    if c >= "A" && c <= "F" { emit toInt(charCode(c)) - 55 }
    if c >= "a" && c <= "f" { emit toInt(charCode(c)) - 87 }
    emit -1
}

// urlDecode(s) — reverse of urlEncode. Treats `+` as literal (matches
// urlEncode semantics). Use urlDecodeQuery for application/x-www-form-
// urlencoded payloads where `+` means space.
func urlDecode(s) {
    let out = sbNew()
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == "%" && i + 2 < len(s) {
            let hi = _url_unhex(s[i + 1])
            let lo = _url_unhex(s[i + 2])
            if hi >= 0 && lo >= 0 {
                out = sbAppend(out, fromCharCode((hi * 16 + lo) + ""))
                i += 3
            } else {
                out = sbAppend(out, c)
                i += 1
            }
        } else {
            out = sbAppend(out, c)
            i += 1
        }
    }
    emit sbToString(out)
}

func urlDecodeQuery(s) {
    let out = sbNew()
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == "+" {
            out = sbAppend(out, " ")
            i += 1
        } else if c == "%" && i + 2 < len(s) {
            let hi = _url_unhex(s[i + 1])
            let lo = _url_unhex(s[i + 2])
            if hi >= 0 && lo >= 0 {
                out = sbAppend(out, fromCharCode((hi * 16 + lo) + ""))
                i += 3
            } else {
                out = sbAppend(out, c)
                i += 1
            }
        } else {
            out = sbAppend(out, c)
            i += 1
        }
    }
    emit sbToString(out)
}

// urlBuild(base, queryCsv) — `queryCsv` is "k=v,k=v" (Krypton's native
// flat-map shape). Values are urlEncodeQuery-d, keys are not (must be
// safe identifiers — same restriction Python's urlencode applies).
//
//   urlBuild("https://api/x", "name=brian,note=hi mom")
//     → "https://api/x?name=brian&note=hi+mom"
func urlBuild(base, queryCsv) {
    if len(queryCsv) == 0 { emit base }
    let n = length(queryCsv)
    let out = base + "?"
    let i = 0
    while i < n {
        let kv = split(queryCsv, i + "")
        let eq = indexOf(kv, "=")
        if eq > 0 {
            let k = substring(kv, 0, eq)
            let v = substring(kv, eq + 1, len(kv))
            if i > 0 { out = out + "&" }
            out = out + k + "=" + urlEncodeQuery(v)
        }
        i += 1
    }
    emit out
}

// urlScheme("https://x.com/p")  → "https"; "" if no scheme.
func urlScheme(url) {
    let i = indexOf(url, "://")
    if i < 0 { emit "" }
    emit substring(url, 0, i)
}

// urlHost("https://x.com:8080/p") → "x.com:8080". "" on bad input.
func urlHost(url) {
    let i = indexOf(url, "://")
    if i < 0 { emit "" }
    let rest = substring(url, i + 3, len(url))
    let n = len(rest)
    let j = 0
    while j < n {
        let c = rest[j]
        if c == "/" || c == "?" || c == "#" { emit substring(rest, 0, j) }
        j = j + 1
    }
    emit rest
}

// urlPath("https://x.com/a/b?q=1") → "/a/b". "/" if no path.
func urlPath(url) {
    let i = indexOf(url, "://")
    let start = 0
    if i >= 0 {
        let rest = substring(url, i + 3, len(url))
        let h = 0
        while h < len(rest) && rest[h] != "/" && rest[h] != "?" && rest[h] != "#" {
            h = h + 1
        }
        if h >= len(rest) { emit "/" }
        if rest[h] == "?" || rest[h] == "#" { emit "/" }
        // path = from h up to ? or # or end
        let p = h
        while p < len(rest) && rest[p] != "?" && rest[p] != "#" { p = p + 1 }
        emit substring(rest, h, p)
    }
    emit url
}

// urlQuery("https://x/p?a=1&b=2") → "a=1&b=2". "" if none.
func urlQuery(url) {
    let q = indexOf(url, "?")
    if q < 0 { emit "" }
    let h = indexOf(url, "#")
    if h > q { emit substring(url, q + 1, h) }
    emit substring(url, q + 1, len(url))
}

// Parse a "k=v&k=v" query string into Krypton's comma-CSV flat-map
// shape ("k=v,k=v"). Values are urlDecodeQuery-d, keys urlDecode-d.
//
//   urlParseQuery("name=brian&note=hi+mom") → "name=brian,note=hi mom"
func urlParseQuery(qs) {
    if len(qs) == 0 { emit "" }
    let out = sbNew()
    let any = 0
    let start = 0
    let n = len(qs)
    let i = 0
    while i <= n {
        if i == n || qs[i] == "&" {
            let pair = substring(qs, start, i)
            let eq = indexOf(pair, "=")
            if eq > 0 {
                let k = urlDecode(substring(pair, 0, eq))
                let v = urlDecodeQuery(substring(pair, eq + 1, len(pair)))
                if any == 1 { out = sbAppend(out, ",") }
                out = sbAppend(out, k)
                out = sbAppend(out, "=")
                out = sbAppend(out, v)
                any = 1
            }
            start = i + 1
        }
        i = i + 1
    }
    emit sbToString(out)
}
