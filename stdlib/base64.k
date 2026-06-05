// RFC 4648 base64 encode/decode. Standard alphabet only (no
// URL-safe -_ variant — drop those in a 1-line callsite if needed).
// Pure Krypton, no syscalls.
//
// Closes the Python `base64.b64encode` / `b64decode` gap. Common
// uses: HTTP Basic auth header, data: URIs, embedding binary in
// JSON, signed cookies.
module base64

// Alphabet index → char.
func _b64_enc(n) {
    if n < 26 { emit fromCharCode((65 + n) + "") }
    if n < 52 { emit fromCharCode((71 + n) + "") }
    if n < 62 { emit fromCharCode((n - 4) + "") }
    if n == 62 { emit "+" }
    emit "/"
}

// Char → alphabet index, or -1 if invalid.
func _b64_dec(c) {
    if c >= "A" && c <= "Z" { emit toInt(charCode(c)) - 65 }
    if c >= "a" && c <= "z" { emit toInt(charCode(c)) - 71 }
    if c >= "0" && c <= "9" { emit toInt(charCode(c)) + 4 }
    if c == "+" { emit 62 }
    if c == "/" { emit 63 }
    emit -1
}

// b64Encode(s) — string in, base64 string out. Always padded with `=`.
func b64Encode(s) {
    let out = sbNew()
    let i = 0
    let n = len(s)
    while i + 3 <= n {
        let b0 = toInt(charCode(s[i]))
        let b1 = toInt(charCode(s[i + 1]))
        let b2 = toInt(charCode(s[i + 2]))
        out = sbAppend(out, _b64_enc(b0 / 4))
        out = sbAppend(out, _b64_enc((b0 % 4) * 16 + b1 / 16))
        out = sbAppend(out, _b64_enc((b1 % 16) * 4 + b2 / 64))
        out = sbAppend(out, _b64_enc(b2 % 64))
        i += 3
    }
    let rem = n - i
    if rem == 1 {
        let b0 = toInt(charCode(s[i]))
        out = sbAppend(out, _b64_enc(b0 / 4))
        out = sbAppend(out, _b64_enc((b0 % 4) * 16))
        out = sbAppend(out, "=")
        out = sbAppend(out, "=")
    }
    if rem == 2 {
        let b0 = toInt(charCode(s[i]))
        let b1 = toInt(charCode(s[i + 1]))
        out = sbAppend(out, _b64_enc(b0 / 4))
        out = sbAppend(out, _b64_enc((b0 % 4) * 16 + b1 / 16))
        out = sbAppend(out, _b64_enc((b1 % 16) * 4))
        out = sbAppend(out, "=")
    }
    emit sbToString(out)
}

// b64Decode(s) — base64 in, raw string out. Tolerates whitespace
// (newlines/CR/spaces) per RFC 4648 §3.3. Returns "" on malformed input.
func b64Decode(s) {
    let out = sbNew()
    let buf = sbNew()
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c != " " && c != "\n" && c != "\r" && c != "\t" {
            buf = sbAppend(buf, c)
        }
        i += 1
    }
    let clean = sbToString(buf)
    let m = len(clean)
    if m % 4 != 0 { emit "" }
    let j = 0
    while j < m {
        let c0 = clean[j]
        let c1 = clean[j + 1]
        let c2 = clean[j + 2]
        let c3 = clean[j + 3]
        let d0 = _b64_dec(c0)
        let d1 = _b64_dec(c1)
        if d0 < 0 || d1 < 0 { emit "" }
        let b0 = d0 * 4 + d1 / 16
        out = sbAppend(out, fromCharCode(b0 + ""))
        if c2 != "=" {
            let d2 = _b64_dec(c2)
            if d2 < 0 { emit "" }
            let b1 = (d1 % 16) * 16 + d2 / 4
            out = sbAppend(out, fromCharCode(b1 + ""))
            if c3 != "=" {
                let d3 = _b64_dec(c3)
                if d3 < 0 { emit "" }
                let b2 = (d2 % 4) * 64 + d3
                out = sbAppend(out, fromCharCode(b2 + ""))
            }
        }
        j += 4
    }
    emit sbToString(out)
}

// ── URL-safe variant (RFC 4648 §5) ───────────────────────────────────
// Replaces `+` → `-`, `/` → `_`, and drops trailing `=` padding. Common
// for JWT, signed cookies, anywhere base64 lives in a URL path or query.

func b64EncodeUrl(s) {
    let std = b64Encode(s)
    let out = sbNew()
    let i = 0
    while i < len(std) {
        let c = std[i]
        if c == "+" { out = sbAppend(out, "-") }
        else if c == "/" { out = sbAppend(out, "_") }
        else if c == "=" { }
        else { out = sbAppend(out, c) }
        i = i + 1
    }
    emit sbToString(out)
}

func b64DecodeUrl(s) {
    // Re-pad to a multiple of 4 and flip URL chars back to standard.
    let buf = sbNew()
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == "-" { buf = sbAppend(buf, "+") }
        else if c == "_" { buf = sbAppend(buf, "/") }
        else { buf = sbAppend(buf, c) }
        i = i + 1
    }
    let mid = sbToString(buf)
    let need = 4 - (len(mid) % 4)
    if need == 4 { need = 0 }
    let pad = sbNew()
    pad = sbAppend(pad, mid)
    let p = 0
    while p < need { pad = sbAppend(pad, "=")  p = p + 1 }
    emit b64Decode(sbToString(pad))
}
