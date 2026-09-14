#!/usr/bin/env kr
// kweb_gui_win.ks - Windows GUI wrapper for kweb build/deploy.
//
// Pure Krypton/Win32 via k:gui. No C source.

import "k:gui"

func dq() { emit fromCharCode(34) }
func bs() { emit fromCharCode(92) }

func shellQuote(s) {
    emit dq() + replace(s, dq(), bs() + dq()) + dq()
}

func cleanLine(s) {
    let t = trim(s)
    if t == "0" { emit "" }
    emit t
}

func trimSlashes(s) {
    let out = trim(s)
    while len(out) > 0 && (out[0] == "/" || out[0] == "\\") { out = substring(out, 1, len(out)) }
    while len(out) > 0 && (out[len(out) - 1] == "/" || out[len(out) - 1] == "\\") { out = substring(out, 0, len(out) - 1) }
    emit out
}

func normalizeHost(host) {
    let h = trim(host)
    if startsWith(h, "ftp://") { h = substring(h, 6, len(h)) }
    if startsWith(h, "sftp://") { h = substring(h, 7, len(h)) }
    while len(h) > 0 && h[len(h) - 1] == "/" { h = substring(h, 0, len(h) - 1) }
    emit h
}

func normalizeRemoteFolder(folder) {
    let f = replace(trim(folder), bs(), "/")
    let quotedEmpty = dq() + dq()
    if f == "" || f == "." || f == "./" || f == quotedEmpty || f == "''" { emit "" }
    while len(f) > 0 && f[0] == "/" { f = substring(f, 1, len(f)) }
    while len(f) > 0 && f[len(f) - 1] == "/" { f = substring(f, 0, len(f) - 1) }
    if f == "." || f == quotedEmpty || f == "''" { emit "" }
    emit f
}

func remoteFolderIsSafe(folder) {
    if contains(folder, dq()) { emit "0" }
    if folder == ".." || startsWith(folder, "../") || contains(folder, "/../") || endsWith(folder, "/..") { emit "0" }
    emit "1"
}

func defaultKwebPath() {
    let cwd = cleanLine(exec("cd"))
    emit cwd + "\\web\\kweb.exe"
}

func appendLog(msg) {
    if len(msg) == 0 { emit "1" }
    let log = guiStateGet("kw.log")
    let cur = guiGetText(log)
    guiSetText(log, cur + msg + "\r\n")
    emit "1"
}

func setStatus(msg) {
    guiSetText(guiStateGet("kw.status"), msg)
    emit "1"
}

func field(key) {
    emit cleanLine(guiGetText(guiStateGet(key)))
}

func projectDist(project) {
    emit trimSlashes(project) + "\\dist"
}

func runBuild() {
    let project = field("kw.project")
    let kweb = field("kw.kweb")
    if project == "" {
        guiMessageBox("kweb", "Choose a project folder first.")
        emit "1"
    }
    if kweb == "" {
        guiMessageBox("kweb", "Set the kweb.exe path first.")
        emit "1"
    }
    setStatus("Build running")
    appendLog("$ cd /d " + project)
    appendLog("$ " + kweb + " build")
    let cmd = "cmd /C cd /d " + shellQuote(project) + " && " + shellQuote(kweb) + " build 2>&1"
    let out = exec(cmd)
    if len(out) > 0 { appendLog(out) }
    setStatus("Build finished")
}

func onBuild() { runBuild() }

func onChoose() {
    let p = guiPickFolder("Choose kweb project folder")
    if p == "" { emit "1" }
    guiSetText(guiStateGet("kw.project"), p)
    appendLog("Project set: " + p)
}

func onOpenDist() {
    let project = field("kw.project")
    if project == "" {
        guiMessageBox("kweb", "Choose a project folder first.")
        emit "1"
    }
    let dist = projectDist(project)
    appendLog("$ explorer " + dist)
    exec("explorer " + shellQuote(dist))
}

func onClear() {
    guiSetText(guiStateGet("kw.log"), "")
    setStatus("Ready")
}

func deployRemote(host, folder, rel) {
    let remoteRel = rel
    if folder != "" { remoteRel = folder + "/" + rel }
    emit "ftp://" + host + "/" + remoteRel
}

func onDeploy() {
    let project = field("kw.project")
    let host = normalizeHost(field("kw.host"))
    let user = field("kw.user")
    let pass = guiGetText(guiStateGet("kw.pass"))
    let folder = normalizeRemoteFolder(field("kw.remote"))
    if project == "" {
        guiMessageBox("kweb deploy", "Choose a project folder first.")
        emit "1"
    }
    if host == "" || user == "" || pass == "" {
        guiMessageBox("kweb deploy", "Enter FTP host, username, and password.")
        emit "1"
    }
    if remoteFolderIsSafe(folder) != "1" {
        guiMessageBox("kweb deploy", "Invalid remote folder. Leave it blank or use . for the FTP root.")
        emit "1"
    }

    let dist = projectDist(project)
    let files = exec("cmd /C dir /b /s " + shellQuote(dist) + " 2>nul")
    let n = lineCount(files)
    if n == 0 {
        appendLog("No files found in dist/. Build first.")
        setStatus("Deploy failed")
        emit "1"
    }

    setStatus("Deploy running")
    appendLog("FTP deploy to " + host + " as " + user)
    if folder != "" { appendLog("Remote folder: " + folder) }

    let base = replace(dist, "/", "\\") + "\\"
    let i = 0
    let count = 0
    while i < n {
        let file = cleanLine(getLine(files, i))
        if len(file) > 0 {
            let local = replace(file, "/", "\\")
            let rel = local
            if startsWith(local, base) { rel = substring(local, len(base), len(local)) }
            rel = replace(rel, "\\", "/")
            let remote = deployRemote(host, folder, rel)
            appendLog("upload " + rel + " -> " + remote)
            let curl = "curl --ftp-create-dirs -T " + shellQuote(local) + " " +
                shellQuote(remote) + " --user " + shellQuote(user + ":" + pass) +
                " --insecure --silent --show-error"
            let rc = shellRun(curl)
            if rc != "0" {
                appendLog("Upload failed for " + rel + " (curl exit " + rc + ")")
                setStatus("Deploy failed")
                guiMessageBox("kweb deploy", "Upload failed for " + rel + ". The deploy was stopped.")
                emit "1"
            }
            count = count + 1
        }
        i = i + 1
    }
    appendLog("Deploy complete: " + count + " files")
    setStatus("Deploy finished")
}

just run {
    // guiEnableModernChrome disabled: current Win32 font/DPI path crashes this backend.
    let win = guiWindow("Krypton Web Deploy", 920, 600)
    guiEnableDarkTitle(win)
    guiSetWindowBg("3B1678")
    guiSetUiTextColor("D8D0E4")
    guiSetEditColors("2A1258", "D8D0E4")
    guiSetButtonColors("2A1258", "D8D0E4")

    guiLabel(win, "Krypton Web Deploy", 28, 22, 300, 24)
    let status = guiLabel(win, "Ready", 705, 24, 180, 24)

    guiLabel(win, "Project", 28, 72, 86, 24)
    let project = guiTextInputFlat(win, 124, 68, 585, 30)
    guiSetText(project, cleanLine(exec("cd")))
    let choose = guiFlatButton(win, "Choose", 730, 68, 150, 32)

    guiLabel(win, "kweb", 28, 114, 86, 24)
    let kweb = guiTextInputFlat(win, 124, 110, 756, 30)
    guiSetText(kweb, defaultKwebPath())

    guiLabel(win, "Host", 28, 166, 86, 24)
    let host = guiTextInputFlat(win, 124, 162, 285, 30)
    guiLabel(win, "User", 440, 166, 58, 24)
    let user = guiTextInputFlat(win, 505, 162, 375, 30)

    guiLabel(win, "Pass", 28, 208, 86, 24)
    let pass = guiTextInputFlat(win, 124, 204, 285, 30)
    SendMessageA(_guiResolveHwnd(pass), "204", "42", "0")
    guiLabel(win, "Remote dir", 440, 208, 84, 24)
    let remote = guiTextInputFlat(win, 535, 204, 345, 30)

    let build = guiFlatButton(win, "Build", 28, 260, 132, 34)
    let deploy = guiFlatButton(win, "Deploy", 174, 260, 132, 34)
    let openDist = guiFlatButton(win, "Open dist", 320, 260, 132, 34)
    let clear = guiFlatButton(win, "Clear", 466, 260, 132, 34)

    guiLabel(win, "Activity", 28, 318, 120, 24)
    let logFrame = guiPanel(win, 32, 340, 856, 218, "2A1258")
    let log = guiTextAreaFlat(win, 40, 348, 820, 202)
    guiSetText(log, "Krypton Web Deploy ready.\r\n")


    // Avoid guiApplyExplorerTheme here for now. The current uxtheme path can
    // crash this backend after the window is shown; plain Win32 controls are
    // stable and preserve copy/paste/edit behavior.

    guiStateSet("kw.project", project)
    guiStateSet("kw.kweb", kweb)
    guiStateSet("kw.host", host)
    guiStateSet("kw.user", user)
    guiStateSet("kw.pass", pass)
    guiStateSet("kw.remote", remote)
    guiStateSet("kw.status", status)
    guiStateSet("kw.log", log)

    guiOnClick(choose, funcptr(onChoose))
    guiOnClick(build, funcptr(onBuild))
    guiOnClick(deploy, funcptr(onDeploy))
    guiOnClick(openDist, funcptr(onOpenDist))
    guiOnClick(clear, funcptr(onClear))

    guiShow(win)
    guiRun()
}
