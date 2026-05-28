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
