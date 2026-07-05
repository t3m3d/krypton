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
    let folder = trimSlashes(field("kw.remote"))
    if project == "" {
        guiMessageBox("kweb deploy", "Choose a project folder first.")
        emit "1"
    }
    if host == "" || user == "" || pass == "" {
        guiMessageBox("kweb deploy", "Enter FTP host, username, and password.")
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
                " --insecure --silent --show-error 2>&1"
            let out = exec(curl)
            if len(out) > 0 { appendLog(out) }
            count = count + 1
        }
        i = i + 1
    }
    appendLog("Deploy complete: " + count + " files")
    setStatus("Deploy finished")
}

just run {
    guiEnableModernChrome()
    let win = guiWindow("kweb deploy", 860, 560)
    guiEnableDarkTitle(win)

    guiLabel(win, "Project", 20, 20, 80, 24)
    let project = guiTextInput(win, 110, 18, 510, 28)
    guiSetText(project, cleanLine(exec("cd")))
    let choose = guiButton(win, "Choose", 635, 18, 95, 30)

    guiLabel(win, "kweb", 20, 58, 80, 24)
    let kweb = guiTextInput(win, 110, 56, 620, 28)
    guiSetText(kweb, defaultKwebPath())

    guiLabel(win, "Host", 20, 96, 80, 24)
    let host = guiTextInput(win, 110, 94, 270, 28)
    guiLabel(win, "User", 400, 96, 50, 24)
    let user = guiTextInput(win, 455, 94, 275, 28)

    guiLabel(win, "Pass", 20, 134, 80, 24)
    let pass = guiTextInput(win, 110, 132, 270, 28)
    SendMessageA(_guiResolveHwnd(pass), "204", "42", "0")
    guiLabel(win, "Remote dir", 400, 134, 80, 24)
    let remote = guiTextInput(win, 490, 132, 240, 28)

    let build = guiButton(win, "Build", 750, 18, 80, 30)
    let deploy = guiButton(win, "Deploy", 750, 56, 80, 30)
    let openDist = guiButton(win, "Open dist", 750, 94, 80, 30)
    let clear = guiButton(win, "Clear", 750, 132, 80, 30)

    let status = guiLabel(win, "Ready", 20, 176, 810, 24)
    let log = guiTextArea(win, 20, 210, 810, 300)
    guiSetText(log, "kweb Windows GUI ready.\r\n")

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