#!/usr/bin/env kr
// vault_format_smoke.ks -- structured payload check for Krypton Vault.

import "k:json_emit"
import "k:json_parse"

func emptyVaultJson() {
    emit jeObj2("version", jeNum(1), "items", jeArr0())
}

func emptyVaultPlain() {
    emit "KVJSON1\n" + emptyVaultJson()
}

func itemJson(title, user, url, pass) {
    emit jeObj4("title", jeStr(title), "username", jeStr(user), "url", jeStr(url), "password", jeStr(pass))
}

func plainJson(plain) {
    if startsWith(plain, "KVJSON1\n") { emit substring(plain, 8, len(plain)) }
    emit ""
}

func vaultJsonAppend(plain, item) {
    let js = plainJson(plain)
    if contains(js, "\"items\":[]") {
        emit "KVJSON1\n" + replace(js, "\"items\":[]", "\"items\":[" + item + "]")
    } else {
        let close = len(js) - 2
        let prefix = substring(js, 0, close)
        let suffix = substring(js, close, len(js))
        emit "KVJSON1\n" + prefix + "," + item + suffix
    }
}

func vaultJsonRemoveMatch(plain, query) {
    let parsed = jpParse(plainJson(plain))
    let count = jpArrLen(parsed, "items")
    let items = ""
    let removed = 0
    let j = 0
    while j < count {
        let base = "items." + j
        let titleValue = jpGet(parsed, base + ".title")
        let userValue = jpGet(parsed, base + ".username")
        let urlValue = jpGet(parsed, base + ".url")
        let passValue = jpGet(parsed, base + ".password")
        let hay = titleValue + " " + userValue + " " + urlValue
        if removed == 0 && contains(hay, query) {
            removed = 1
        } else {
            let item = itemJson(titleValue, userValue, urlValue, passValue)
            if items == "" { items = item } else { items = items + "\t" + item }
        }
        j += 1
    }
    emit "KVJSON1\n" + jeObj2("version", jeNum(1), "items", jeArrFrom(items))
}

just run {
    let plain = emptyVaultPlain()
    plain = vaultJsonAppend(plain, itemJson("GitHub", "me@example.com", "https://github.com", "secret"))
    plain = vaultJsonAppend(plain, itemJson("Mail", "me@example.com", "https://mail.example.com", "secret2"))
    let parsed = jpParse(plainJson(plain))
    if jpArrLen(parsed, "items") != 2 {
        printErr("item count mismatch")
        exit(1)
    }
    if jpGet(parsed, "items.0.title") != "GitHub" {
        printErr("first item mismatch")
        exit(1)
    }
    if jpGet(parsed, "items.1.url") != "https://mail.example.com" {
        printErr("second item mismatch")
        exit(1)
    }
    plain = vaultJsonRemoveMatch(plain, "GitHub")
    parsed = jpParse(plainJson(plain))
    if jpArrLen(parsed, "items") != 1 {
        printErr("delete count mismatch")
        exit(1)
    }
    if jpGet(parsed, "items.0.title") != "Mail" {
        printErr("delete item mismatch")
        exit(1)
    }
    kp("vault format smoke ok")
}
