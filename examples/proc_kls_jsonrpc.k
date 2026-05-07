// proc_kls_jsonrpc.k — smoke test for stdlib/proc.k.
//
// Spawns kls.exe (the Krypton Language Server), sends an LSP
// `initialize` request as JSON-RPC over stdin (with Content-Length
// framing), reads the response from stdout. Confirms the
// bidirectional pipe API works end-to-end against a real LSP server.

import "stdlib/proc.k"

func makeFrame(body) {
    // LSP framing: Content-Length: N\r\n\r\n<body>
    let n = len(body)
    emit "Content-Length: " + n + "\r\n\r\n" + body
}

just run {
    // Initialize request — LSP spec calls this the very first message.
    let body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"processId\":null,\"rootUri\":null,\"capabilities\":{}}}"
    let frame = makeFrame(body)

    kp("spawning kls.exe")
    let p = procSpawn("kls.exe", "")
    if p == "0" {
        kp("FAIL: procSpawn returned 0 (kls.exe not found on PATH?)")
        exit(1)
    }
    kp("spawned, handle=" + p)

    kp("alive=" + procAlive(p))

    kp("writing initialize request (" + len(frame) + " bytes)")
    let w = procWrite(p, frame)
    kp("write result=" + w)

    kp("reading response...")
    let reply = procRead(p, 4096)
    kp("got " + len(reply) + " bytes")
    kp("---reply---")
    kp(reply)
    kp("---end reply---")

    kp("closing")
    procClose(p)
    kp("done")
}
