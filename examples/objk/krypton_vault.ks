#!/usr/bin/env kr
// krypton_vault.ks -- native macOS-first shell for Krypton Vault.
//
// This is a product scaffold with encrypted local persistence and blind VPS
// sync. Harden the prototype KDF before a public release.

import "k:okui"
import "k:vault_crypto_macos"
import "k:json_emit"
import "k:json_parse"

func dq() { emit fromCharCode(34) }
func bs() { emit fromCharCode(92) }

func appH() { emit sharedApp() }

func cleanLine(s) {
    let t = trim(s)
    if t == "0" { emit "" }
    emit t
}

func shellQuote(s) {
    emit dq() + replace(s, dq(), bs() + dq()) + dq()
}

func isDarkMode() {
    let mode = cleanLine(exec("defaults read -g AppleInterfaceStyle 2>/dev/null"))
    if contains(mode, "Dark") { emit 1 }
    emit 0
}

func vaultBg() {
    if isDarkMode() == 1 { emit rgb(28, 32, 38) }
    emit windowBackground()
}

func vaultText() {
    if isDarkMode() == 1 { emit rgb(230, 233, 236) }
    emit textColor()
}

func vaultMuted() {
    if isDarkMode() == 1 { emit rgb(156, 165, 174) }
    emit secondaryTextColor()
}

func tint(view) {
    doTextColor(view, vaultText())
    emit view
}

func tintMuted(view) {
    doTextColor(view, vaultMuted())
    emit view
}

func tintButton(view) {
    doButtonTextColor(view, vaultText())
    emit view
}

func setStatus(textValue) {
    doText(get(appH(), "status"), textValue)
    emit "1"
}

func fieldText(key) {
    emit text(get(appH(), key))
}

func nthField(line, want) {
    let start = 0
    let idx = 0
    let i = 0
    while i < len(line) {
        if line[i] == "\t" {
            if idx == want { emit substring(line, start, i) }
            idx += 1
            start = i + 1
        }
        i += 1
    }
    if idx == want { emit substring(line, start, len(line)) }
    emit ""
}

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
    if !startsWith(plain, "KVJSON1\n") {
        emit emptyVaultPlain()
    }
    let js = plainJson(plain)
    if contains(js, "\"items\":[]") {
        emit "KVJSON1\n" + replace(js, "\"items\":[]", "\"items\":[" + item + "]")
    } else {
        let arrStart = indexOf(js, "\"items\":[")
        if arrStart < 0 { emit emptyVaultPlain() }
        let close = len(js) - 2
        let prefix = substring(js, 0, close)
        let suffix = substring(js, close, len(js))
        emit "KVJSON1\n" + prefix + "," + item + suffix
    }
}

func normalizeBaseUrl(url) {
    let out = trim(url)
    while len(out) > 0 && out[len(out) - 1] == "/" { out = substring(out, 0, len(out) - 1) }
    emit out
}

func entryLine(title, user, url) {
    let line = title
    if user != "" { line = line + "    " + user }
    if url != "" { line = line + "    " + url }
    emit line
}

func appendVaultLine(line) {
    let vault = get(appH(), "vault")
    let count = get(appH(), "itemCount")
    if count == "" || count == "0" {
        doTextBox(vault, "")
        doSet(appH(), "itemCount", "1")
    }
    doAppend(vault, line)
    if len(line) == 0 || line[len(line) - 1] != "\n" { doAppend(vault, "\n") }
    doTextRangeColor(vault, vaultText(), 0, textLength(vault))
    emit "1"
}

func renderVaultWithFilter(plain, query) {
    let vault = get(appH(), "vault")
    let q = trim(query)
    doTextBox(vault, "")
    doSet(appH(), "itemCount", "0")
    if startsWith(plain, "KVJSON1\n") {
        let parsed = jpParse(plainJson(plain))
        let count = jpArrLen(parsed, "items")
        let j = 0
        while j < count {
            let base = "items." + j
            let titleValue = jpGet(parsed, base + ".title")
            let userValue = jpGet(parsed, base + ".username")
            let urlValue = jpGet(parsed, base + ".url")
            let hay = titleValue + " " + userValue + " " + urlValue
            if q == "" || contains(hay, q) {
                appendVaultLine(entryLine(titleValue, userValue, urlValue))
            }
            j += 1
        }
    } else {
    let n = lineCount(plain)
    let i = 0
    while i < n {
        let line = getLine(plain, i)
        if len(line) > 0 && line != "KVPLAIN1" {
            let titleValue = nthField(line, 0)
            let userValue = nthField(line, 1)
            let urlValue = nthField(line, 2)
            let hay = titleValue + " " + userValue + " " + urlValue
            if q == "" || contains(hay, q) {
                appendVaultLine(entryLine(titleValue, userValue, urlValue))
            }
        }
        i += 1
    }
    }
    if get(appH(), "itemCount") == "0" {
        doTextBox(vault, "No vault items in this local session.\n")
    }
    emit "1"
}

func renderVaultPlain(plain) {
    renderVaultWithFilter(plain, "")
    emit "1"
}

func vaultFindPassword(plain, query) {
    let q = trim(query)
    if q == "" { emit "" }
    if startsWith(plain, "KVJSON1\n") {
        let parsed = jpParse(plainJson(plain))
        let count = jpArrLen(parsed, "items")
        let j = 0
        while j < count {
            let base = "items." + j
            let titleValue = jpGet(parsed, base + ".title")
            let userValue = jpGet(parsed, base + ".username")
            let urlValue = jpGet(parsed, base + ".url")
            let hay = titleValue + " " + userValue + " " + urlValue
            if contains(hay, q) { emit jpGet(parsed, base + ".password") }
            j += 1
        }
    } else {
        let n = lineCount(plain)
        let i = 0
        while i < n {
            let line = getLine(plain, i)
            if len(line) > 0 && line != "KVPLAIN1" {
                let hay = nthField(line, 0) + " " + nthField(line, 1) + " " + nthField(line, 2)
                if contains(hay, q) { emit nthField(line, 3) }
            }
            i += 1
        }
    }
    emit ""
}

func vaultRemoveMatch(plain, query) {
    let q = trim(query)
    if q == "" { emit plain }
    if !startsWith(plain, "KVJSON1\n") { emit plain }
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
        if removed == 0 && contains(hay, q) {
            removed = 1
        } else {
            let item = itemJson(titleValue, userValue, urlValue, passValue)
            if items == "" { items = item } else { items = items + "\t" + item }
        }
        j += 1
    }
    if removed == 0 { emit plain }
    emit "KVJSON1\n" + jeObj2("version", jeNum(1), "items", jeArrFrom(items))
}

func clearEntryFields() {
    doText(get(appH(), "itemTitle"), "")
    doText(get(appH(), "itemUser"), "")
    doText(get(appH(), "itemUrl"), "")
    doText(get(appH(), "itemPassword"), "")
    emit "1"
}

func onUnlock(self, cmd, sender) {
    let master = fieldText("master")
    if len(master) < 12 {
        alert("Krypton Vault", "Use a longer master password before opening a vault.")
        setStatus("Locked")
        emit "1"
    }
    let opened = openLocalVault(master)
    if opened != "" {
        doSet(appH(), "vaultPlain", opened)
        renderVaultPlain(opened)
        setStatus("Unlocked saved vault")
    } else {
        if get(appH(), "vaultPlain") == "" {
            doSet(appH(), "vaultPlain", emptyVaultPlain())
        }
        setStatus("Unlocked new vault")
    }
    doText(get(appH(), "lockState"), "Unlocked local session")
    doEnable(get(appH(), "addButton"))
    doEnable(get(appH(), "copyButton"))
    doEnable(get(appH(), "copyMatchButton"))
    doEnable(get(appH(), "deleteMatchButton"))
    doEnable(get(appH(), "findButton"))
    doEnable(get(appH(), "lockButton"))
    emit "1"
}

func onLock(self, cmd, sender) {
    doText(get(appH(), "master"), "")
    doText(get(appH(), "lockState"), "Locked")
    doDisable(get(appH(), "addButton"))
    doDisable(get(appH(), "copyButton"))
    doDisable(get(appH(), "copyMatchButton"))
    doDisable(get(appH(), "deleteMatchButton"))
    doDisable(get(appH(), "findButton"))
    doDisable(get(appH(), "lockButton"))
    doSet(appH(), "vaultPlain", "")
    doTextBox(get(appH(), "vault"), "No vault items in this local session.\n")
    doSet(appH(), "itemCount", "0")
    clearEntryFields()
    setStatus("Locked")
    emit "1"
}

func onAdd(self, cmd, sender) {
    let titleValue = trim(fieldText("itemTitle"))
    let userValue = trim(fieldText("itemUser"))
    let urlValue = trim(fieldText("itemUrl"))
    let passValue = fieldText("itemPassword")
    if titleValue == "" {
        alert("Krypton Vault", "Add a title for this item.")
        emit "1"
    }
    if passValue == "" {
        alert("Krypton Vault", "Add a password before saving this item.")
        emit "1"
    }
    let plain = get(appH(), "vaultPlain")
    if plain == "" { plain = emptyVaultPlain() }
    if startsWith(plain, "KVPLAIN1\n") {
        plain = emptyVaultPlain()
    }
    plain = vaultJsonAppend(plain, itemJson(titleValue, userValue, urlValue, passValue))
    doSet(appH(), "vaultPlain", plain)
    appendVaultLine(entryLine(titleValue, userValue, urlValue))
    clearEntryFields()
    setStatus("Added in memory")
    emit "1"
}

func onCopyPassword(self, cmd, sender) {
    let passValue = fieldText("itemPassword")
    if passValue == "" {
        alert("Krypton Vault", "There is no password in the editor to copy.")
        emit "1"
    }
    doCopyText(passValue)
    setStatus("Password copied")
    emit "1"
}

func onCopyMatch(self, cmd, sender) {
    let query = fieldText("search")
    let passValue = vaultFindPassword(get(appH(), "vaultPlain"), query)
    if passValue == "" {
        alert("Krypton Vault", "No unlocked vault item matches that search.")
        setStatus("No match")
        emit "1"
    }
    doCopyText(passValue)
    setStatus("Matched password copied")
    emit "1"
}

func onFind(self, cmd, sender) {
    let plain = get(appH(), "vaultPlain")
    if plain == "" {
        alert("Krypton Vault", "Unlock a vault before searching.")
        emit "1"
    }
    renderVaultWithFilter(plain, fieldText("search"))
    setStatus("Filtered")
    emit "1"
}

func onDeleteMatch(self, cmd, sender) {
    let plain = get(appH(), "vaultPlain")
    if plain == "" {
        alert("Krypton Vault", "Unlock a vault before deleting.")
        emit "1"
    }
    let nextPlain = vaultRemoveMatch(plain, fieldText("search"))
    if nextPlain == plain {
        alert("Krypton Vault", "No unlocked vault item matches that search.")
        setStatus("No match")
        emit "1"
    }
    doSet(appH(), "vaultPlain", nextPlain)
    renderVaultWithFilter(nextPlain, "")
    setStatus("Deleted in memory")
    emit "1"
}

func onSync(self, cmd, sender) {
    let base = normalizeBaseUrl(fieldText("syncUrl"))
    let user = trim(fieldText("syncUser"))
    let token = fieldText("syncToken")
    if base == "" {
        alert("Krypton Vault", "Add the VPS sync URL first.")
        setStatus("Sync not configured")
        emit "1"
    }
    let out = cleanLine(exec("curl -fsS " + shellQuote(base + "/health") + " 2>&1"))
    if contains(out, "krypton-vault-sync") {
        let sealedPath = localVaultPath()
        let sealed = readFile(sealedPath)
        if sealed == "" {
            if user == "" || token == "" {
                alert("Krypton Vault", "Add account and token before restoring an encrypted vault.")
                setStatus("Sync credentials missing")
                emit "1"
            }
            let tmp = "/tmp/krypton_vault_restore.kv"
            let getCmd = "curl -fsS -G " + shellQuote(base + "/v1/vault/blob") +
                " --data-urlencode " + shellQuote("user=" + user) +
                " --data-urlencode " + shellQuote("token=" + token) +
                " -o " + shellQuote(tmp) + " 2>&1"
            let fetched = cleanLine(exec(getCmd))
            let restored = readFile(tmp)
            if startsWith(restored, "KV2\n") {
                exec("mkdir -p " + shellQuote(environ("HOME") + "/.config/krypton-vault"))
                writeFile(sealedPath, restored)
                let master = fieldText("master")
                let opened = openLocalVault(master)
                if opened != "" {
                    doSet(appH(), "vaultPlain", opened)
                    renderVaultPlain(opened)
                    setStatus("Encrypted vault restored")
                    emit "1"
                }
                setStatus("Restored; unlock failed")
                alert("Krypton Vault", "The encrypted vault was restored, but this master password did not open it.")
                emit "1"
            }
            if fetched != "" { alert("Krypton Vault", fetched) }
            setStatus("No remote vault")
            emit "1"
        }
        if user == "" || token == "" {
            alert("Krypton Vault", "Add account and token before uploading the encrypted vault.")
            setStatus("Sync credentials missing")
            emit "1"
        }
        let post = "curl -fsS -X POST " + shellQuote(base + "/v1/vault") +
            " --data-urlencode " + shellQuote("user=" + user) +
            " --data-urlencode " + shellQuote("token=" + token) +
            " --data-urlencode " + shellQuote("rev=1") +
            " --data-urlencode " + shellQuote("blob@" + sealedPath) + " 2>&1"
        let posted = cleanLine(exec(post))
        if contains(posted, "\"ok\":true") {
            setStatus("Encrypted vault uploaded")
            emit "1"
        }
        alert("Krypton Vault", "The VPS was reachable, but upload failed.")
        setStatus("Upload failed")
        emit "1"
    }
    alert("Krypton Vault", "Could not reach the sync endpoint.")
    setStatus("Sync check failed")
    emit "1"
}

func onPersist(self, cmd, sender) {
    let master = fieldText("master")
    if len(master) < 12 {
        alert("Krypton Vault", "Unlock with a longer master password before saving.")
        setStatus("Save blocked")
        emit "1"
    }
    let plain = get(appH(), "vaultPlain")
    if plain == "" || plain == emptyVaultPlain() || plain == "KVPLAIN1\n" {
        alert("Krypton Vault", "There are no vault items to save.")
        emit "1"
    }
    if sealLocalVault(master, plain) == "1" {
        setStatus("Encrypted vault saved")
        emit "1"
    }
    alert("Krypton Vault", "Encrypted save failed. Check the native crypto bridge.")
    setStatus("Save failed")
    emit "1"
}

func putLabel(win, textValue, x, y, w) {
    let lbl = label(win, textValue, area(x, y, w, 22))
    tintMuted(lbl)
    emit lbl
}

func wire(btn, key, handler) {
    doClick(btn, key, handler)
    emit "1"
}

func setupMenus(application) {
    let bar = menuBar()
    let edit = menu(bar, "Edit")
    menuSelector(edit, "Cut", "x", "cut:")
    menuSelector(edit, "Copy", "c", "copy:")
    menuSelector(edit, "Paste", "v", "paste:")
    menuSeparator(edit)
    menuSelector(edit, "Select All", "a", "selectAll:")
    emit "1"
}

just run {
    let application = app("Krypton Vault")
    setupMenus(application)

    let win = window("Krypton Vault", 920, 620)
    minSize(win, 820, 560)
    doWindowBackground(win, vaultBg())
    doTransparentTitlebar(win)

    let headline = title(win, "Krypton Vault", area(24, 570, 260, 28))
    tint(headline)
    let status = label(win, "Locked", area(760, 570, 136, 22))
    tintMuted(status)

    putLabel(win, "Master password", 24, 526, 140)
    let master = password(win, area(166, 522, 384, 28))
    tint(master)
    doPlaceholder(master, "Unlock local vault")
    let unlockBtn = button(win, "Unlock", area(566, 522, 96, 30))
    tintButton(unlockBtn)
    let lockBtn = button(win, "Lock", area(674, 522, 86, 30))
    tintButton(lockBtn)
    let lockState = label(win, "Locked", area(774, 526, 122, 22))
    tintMuted(lockState)

    putLabel(win, "Search", 24, 484, 90)
    let search = field(win, area(166, 480, 298, 28))
    tint(search)
    doPlaceholder(search, "Search title, user, or site")
    let findBtn = button(win, "Find", area(478, 480, 72, 30))
    tintButton(findBtn)
    let syncBtn = button(win, "Sync", area(566, 480, 96, 30))
    tintButton(syncBtn)
    let persistBtn = button(win, "Save", area(674, 480, 86, 30))
    tintButton(persistBtn)

    putLabel(win, "VPS URL", 24, 446, 90)
    let syncUrl = field(win, area(166, 442, 300, 28))
    tint(syncUrl)
    doPlaceholder(syncUrl, "https://vault.example.com")

    putLabel(win, "Account", 488, 446, 90)
    let syncUser = field(win, area(582, 442, 132, 28))
    tint(syncUser)
    doPlaceholder(syncUser, "email")
    let syncToken = password(win, area(724, 442, 172, 28))
    tint(syncToken)
    doPlaceholder(syncToken, "token")

    putLabel(win, "Title", 24, 394, 90)
    let itemTitle = field(win, area(166, 390, 300, 28))
    tint(itemTitle)
    doPlaceholder(itemTitle, "GitHub")

    putLabel(win, "Username", 488, 394, 90)
    let itemUser = field(win, area(582, 390, 314, 28))
    tint(itemUser)
    doPlaceholder(itemUser, "name@example.com")

    putLabel(win, "Website", 24, 354, 90)
    let itemUrl = field(win, area(166, 350, 300, 28))
    tint(itemUrl)
    doPlaceholder(itemUrl, "https://example.com")

    putLabel(win, "Password", 488, 354, 90)
    let itemPassword = password(win, area(582, 350, 314, 28))
    tint(itemPassword)
    doPlaceholder(itemPassword, "Stored only in memory")

    let addButton = button(win, "Add Item", area(166, 304, 108, 32))
    tintButton(addButton)
    let copyButton = button(win, "Copy Password", area(288, 304, 132, 32))
    tintButton(copyButton)
    let copyMatchButton = button(win, "Copy Match", area(434, 304, 132, 32))
    tintButton(copyMatchButton)
    let deleteMatchButton = button(win, "Delete Match", area(580, 304, 132, 32))
    tintButton(deleteMatchButton)

    putLabel(win, "Vault", 24, 270, 90)
    let vault = textBox(win, area(24, 32, 872, 230))
    doFont(vault, mono(12))
    doNoWrap(vault)
    doTextBox(vault, "No vault items in this local session.\n")
    doTextColor(vault, vaultText())
    doBackground(vault, textBackground())

    doSet(application, "status", status)
    doSet(application, "master", master)
    doSet(application, "lockState", lockState)
    doSet(application, "search", search)
    doSet(application, "syncUrl", syncUrl)
    doSet(application, "syncUser", syncUser)
    doSet(application, "syncToken", syncToken)
    doSet(application, "itemTitle", itemTitle)
    doSet(application, "itemUser", itemUser)
    doSet(application, "itemUrl", itemUrl)
    doSet(application, "itemPassword", itemPassword)
    doSet(application, "vault", vault)
    doSet(application, "itemCount", "0")
    doSet(application, "vaultPlain", "")
    doSet(application, "findButton", findBtn)
    doSet(application, "addButton", addButton)
    doSet(application, "copyButton", copyButton)
    doSet(application, "copyMatchButton", copyMatchButton)
    doSet(application, "deleteMatchButton", deleteMatchButton)
    doSet(application, "lockButton", lockBtn)

    doDisable(addButton)
    doDisable(copyButton)
    doDisable(copyMatchButton)
    doDisable(deleteMatchButton)
    doDisable(findBtn)
    doDisable(lockBtn)

    wire(unlockBtn, "vault.unlock", funcptr(onUnlock))
    wire(lockBtn, "vault.lock", funcptr(onLock))
    wire(addButton, "vault.add", funcptr(onAdd))
    wire(copyButton, "vault.copy", funcptr(onCopyPassword))
    wire(copyMatchButton, "vault.copyMatch", funcptr(onCopyMatch))
    wire(deleteMatchButton, "vault.deleteMatch", funcptr(onDeleteMatch))
    wire(findBtn, "vault.find", funcptr(onFind))
    wire(syncBtn, "vault.sync", funcptr(onSync))
    wire(persistBtn, "vault.persist", funcptr(onPersist))

    doShow(win)
    doRun()
}
