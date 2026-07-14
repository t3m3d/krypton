#!/usr/bin/env kr
// vault_sync_server.ks -- tiny opaque-blob sync server for Krypton Vault.
//
// Run behind HTTPS on the VPS. This service stores encrypted vault blobs only;
// clients must encrypt/decrypt locally before calling it.

import "k:server_native"
import "k:env"
import "k:json_emit"

func dq() { emit fromCharCode(34) }
func bs() { emit fromCharCode(92) }

func cleanLine(s) {
    let t = trim(s)
    if t == "0" { emit "" }
    emit t
}

func shellQuote(s) {
    emit dq() + replace(s, dq(), bs() + dq()) + dq()
}

func safeUser(user) {
    let out = sbNew()
    let i = 0
    while i < len(user) {
        let c = user[i]
        if (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9") || c == "-" || c == "_" || c == "." {
            out = sbAppend(out, c)
        }
        i += 1
    }
    let v = sbToString(out)
    if v == "" { emit "default" }
    emit v
}

func dataRoot() {
    let configured = env("KRYPTON_VAULT_DATA")
    if configured != "" { emit configured }
    emit env("HOME") + "/.config/krypton-vault/server"
}

func ensureRoot() {
    exec("mkdir -p " + shellQuote(dataRoot()))
    emit "1"
}

func vaultPath(user) {
    emit dataRoot() + "/" + safeUser(user) + ".blob"
}

func metaPath(user) {
    emit dataRoot() + "/" + safeUser(user) + ".meta"
}

func tokenOk(req) {
    let expected = env("KRYPTON_VAULT_TOKEN")
    if expected == "" { emit 0 }
    let got = queryValue(req, "token")
    if got == "" { got = formValue(req, "token") }
    if got == expected { emit 1 }
    emit 0
}

func unauthorized(client) {
    serverSend(client, httpResponse("401 Unauthorized", "application/json", jeObj("error", jeStr("unauthorized"))))
    emit "1"
}

func badRequest(client, message) {
    serverSend(client, httpResponse("400 Bad Request", "application/json", jeObj("error", jeStr(message))))
    emit "1"
}

func handleHealth(client) {
    serveJson(client, jeObj2("ok", jeBool(1), "service", jeStr("krypton-vault-sync")))
    emit "1"
}

func handleGetVault(req, client) {
    if tokenOk(req) == 0 { unauthorized(client)  emit "1" }
    let user = queryValue(req, "user")
    if user == "" { badRequest(client, "missing user")  emit "1" }
    ensureRoot()
    let blob = readFile(vaultPath(user))
    let meta = cleanLine(readFile(metaPath(user)))
    if meta == "" { meta = "0" }
    serveJson(client, jeObj3("user", jeStr(safeUser(user)), "rev", jeStr(meta), "blob", jeStr(blob)))
    emit "1"
}

func handlePutVault(req, client) {
    if tokenOk(req) == 0 { unauthorized(client)  emit "1" }
    let user = formValue(req, "user")
    let blob = formValue(req, "blob")
    let rev = formValue(req, "rev")
    if user == "" { badRequest(client, "missing user")  emit "1" }
    if blob == "" { badRequest(client, "missing blob")  emit "1" }
    if rev == "" { rev = "1" }
    ensureRoot()
    writeFile(vaultPath(user), blob)
    writeFile(metaPath(user), rev)
    serveJson(client, jeObj3("ok", jeBool(1), "user", jeStr(safeUser(user)), "rev", jeStr(rev)))
    emit "1"
}

func handleRequest(req, client) {
    let method = reqMethod(req)
    let path = reqPath(req)
    if path == "/health" { handleHealth(client)  emit "1" }
    if path == "/v1/vault" && method == "GET" { handleGetVault(req, client)  emit "1" }
    if path == "/v1/vault" && method == "POST" { handlePutVault(req, client)  emit "1" }
    serve404(client)
    emit "1"
}

just run {
    let port = envOr("PORT", "8080")
    let token = env("KRYPTON_VAULT_TOKEN")
    if token == "" {
        printErr("KRYPTON_VAULT_TOKEN is required")
        exit(1)
    }
    ensureRoot()
    let srv = serverListen(port)
    if srv < 0 {
        printErr("failed to listen on " + port)
        exit(1)
    }
    kp("krypton-vault-sync listening on :" + port)
    while 1 == 1 {
        let client = serverAccept(srv)
        if client >= 0 {
            let req = serverRead(client)
            handleRequest(req, client)
        }
    }
}
