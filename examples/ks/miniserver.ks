#!/usr/bin/env kr
// miniserver.ks — tiny HTTP server, 100% C-free (k:server_native, native sockets).
//
//   kr examples/ks/miniserver.ks [PORT]     (default 8080)
//
// Serves:
//   GET /          -> HTML hello
//   GET /json      -> {"ok":true}
//   GET /echo?x=.. -> echoes the x query param
//   anything else  -> 404
//
// Pair with examples/ks/fetch.ks (k:httpc) for a fully clang-free client+server.
//
// Platforms: Linux + macOS today (the sockMake/Bind/Listen/Accept/RecvStr
// builtins are wired through the macho_arm64 and elf backends).  Windows
// support: ws2_32.dll IAT registration landed in x64.k 2026-06-13 and
// the wrappers live in stdlib/winsock.k; once stdlib/server_native.k
// is updated to dispatch sockMake/... to winsock.k's sockMakeWin/... on
// Windows (and the x64_host binary is regenerated -- see
// docs/backend_history.md#Windows ws2_32 IAT notes), this example runs unchanged there
// too.

import "k:server_native"

just run {
    let port = "8080"
    if argCount() >= 1 { port = arg(0) }

    let srv = serverListen(port)
    if srv < 0 {
        print("listen failed on port " + port)
        exit("1")
    }
    print("miniserver (C-free) on http://127.0.0.1:" + port)

    while "1" == "1" {
        let cl = serverAccept(srv)
        if cl >= 0 {
            let req = serverRead(cl)
            let path = reqPath(req)
            if path == "/" {
                serveHtml(cl, "<h1>hello from krypton, no C</h1>")
            } else if path == "/json" {
                serveJson(cl, "{\"ok\":true}")
            } else if path == "/echo" {
                serveText(cl, "echo: " + queryValue(req, "x"))
            } else {
                serve404(cl)
            }
        }
    }
}
