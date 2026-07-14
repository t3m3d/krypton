#!/usr/bin/env kr
// vault_crypto_smoke.ks -- seal/open check for the macOS vault crypto bridge.

import "k:vault_crypto_macos"
import "k:json_emit"

just run {
    let master = "correct horse battery staple"
    let item = jeObj4("title", jeStr("GitHub"), "username", jeStr("me"), "url", jeStr("https://github.com"), "password", jeStr("secret"))
    let plain = "KVJSON1\n" + jeObj2("version", jeNum(1), "items", jeArr1(item))
    let sealed = vaultSeal(master, plain)
    if sealed == "" {
        printErr("seal failed")
        exit(1)
    }
    let opened = vaultOpen(master, sealed)
    if opened != plain {
        printErr("open mismatch")
        exit(1)
    }
    kp("vault crypto smoke ok")
}
