// server.k — URL-decoding + query-param helpers.
//
// Historical: this module used to host a stateful HTTP server backed by
// a cfunc{} block of winsock / BSD-sockets C source. With the C-emit
// pipeline removed (2026-06-04), the stateful API (serverInit/serverNext/
// serverReqPath/serverRespond/...) is gone. Use stdlib/server_native.k
// instead — pure Krypton on the native socket builtins, explicit fd-passing
// instead of module-global state:
//
//     import "k:server_native"
//     just run {
//         let srv = serverListen("8080")
//         while "1" == "1" {
//             let cl = serverAccept(srv)
//             if cl >= 0 {
//                 serveHtml(cl, "<h1>hi</h1>")
//                 serverClose(cl)
//             }
//         }
//     }
//
// This file still exposes the URL-decode / query-string helpers because
// they're pure Krypton and have no dependency on the old server state.

module server

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
