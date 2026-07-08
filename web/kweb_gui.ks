#!/usr/bin/env kr
// kweb_gui.ks — Objective-K GUI wrapper for the kweb deploy workflow.
//
// Pure Krypton/Objective-K: no C, no Obj-C source, no Swift.

import "k:okui"

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

func appH() { emit sharedApp() }

func fileExists(path) {
    emit cleanLine(exec("test -f " + shellQuote(path) + " && echo 1 || echo 0"))
}

func defaultKwebPath(cwd) {
    let local = cwd + "/web/kweb"
    if cwd != "/" && fileExists(local) == "1" { emit local }
    let installed = "/usr/local/krypton/web/kweb"
    if fileExists(installed) == "1" { emit installed }
    let repo = "/Users/t3m3d/Documents/GitHub/krypton/web/kweb"
    if fileExists(repo) == "1" { emit repo }
    emit "web/kweb"
}

func normalizeHost(host) {
    let h = trim(host)
    if startsWith(h, "ftp://") { h = substring(h, 6, len(h)) }
    if startsWith(h, "sftp://") { h = substring(h, 7, len(h)) }
    while len(h) > 0 && h[len(h) - 1] == "/" { h = substring(h, 0, len(h) - 1) }
    emit h
}

func normalizeRemoteFolder(folder) {
    let f = trim(folder)
    while len(f) > 0 && f[0] == "/" { f = substring(f, 1, len(f)) }
    while len(f) > 0 && f[len(f) - 1] == "/" { f = substring(f, 0, len(f) - 1) }
    emit f
}

func isDarkMode() {
    let mode = cleanLine(exec("defaults read -g AppleInterfaceStyle 2>/dev/null"))
    if contains(mode, "Dark") { emit 1 }
    emit 0
}

func kwebTextColor() {
    if isDarkMode() == 1 { emit rgb(184, 178, 198) }
    emit rgb(0, 0, 0)
}

func kwebLogTextColor() { emit kwebTextColor() }

func kwebLogBgColor() {
    if isDarkMode() == 1 { emit kwebWindowBgColor() }
    emit textBackground()
}

func kwebWindowBgColor() {
    if isDarkMode() == 1 { emit rgb(39, 24, 72) }
    emit windowBackground()
}

func recolorLog(tv) {
    doBackground(tv, kwebLogBgColor())
    doTextColor(tv, kwebLogTextColor())
    doTextRangeColor(tv, kwebLogTextColor(), 0, textLength(tv))
    emit "1"
}

func kwebLabelColor() {
    emit kwebTextColor()
}

func tintField(field) {
    doTextColor(field, kwebTextColor())
    emit field
}

func tintButton(button) {
    doButtonTextColor(button, kwebTextColor())
    emit button
}

func appendLog(tv, text) {
    let msg = text
    if len(msg) == 0 { emit "1" }
    doAppend(tv, msg)
    if msg[len(msg) - 1] != "\n" { doAppend(tv, "\n") }
    recolorLog(tv)
    emit "1"
}

func stateField(state, key) {
    emit cleanLine(text(get(appH(), key)))
}

func setStatus(state, text) {
    doText(get(appH(), "status"), text)
    emit "1"
}

func runInProject(state, name, args) {
    let project = stateField(state, "project")
    let kweb = stateField(state, "kweb")
    let log = get(appH(), "log")

    if project == "" {
        alert("kweb", "Choose a project folder first.")
        emit "1"
    }
    if kweb == "" {
        alert("kweb", "Choose the kweb binary first.")
        emit "1"
    }

    setStatus(state, name + " running")
    appendLog(log, "$ cd " + project)
    appendLog(log, "$ " + kweb + " " + args)

    let cmd = "cd " + shellQuote(project) + " && " + shellQuote(kweb) + " " + args + " 2>&1"
    let out = exec(cmd)
    appendLog(log, out)
    setStatus(state, name + " finished")
    emit "1"
}

func onBuild(self, cmd, sender) {
    runInProject(appH(), "Build", "build")
}

func onDeploy(self, cmd, sender) {
    let state = appH()
    let host = normalizeHost(stateField(state, "host"))
    let user = stateField(state, "user")
    let pass = stateField(state, "password")
    let remoteFolder = normalizeRemoteFolder(stateField(state, "remoteFolder"))
    let project = stateField(state, "project")
    let log = get(appH(), "log")
    if host == "" || user == "" || pass == "" {
        alert("kweb deploy", "Enter FTP host, username, and password.")
        emit "1"
    }
    if project == "" {
        alert("kweb deploy", "Choose a project folder first.")
        emit "1"
    }

    setStatus(state, "Deploy running")
    appendLog(log, "FTP deploy to " + host + " as " + user)
    if remoteFolder != "" { appendLog(log, "Remote folder: " + remoteFolder) }
    let files = exec("cd " + shellQuote(project) + " && find dist -type f 2>/dev/null")
    let n = lineCount(files)
    if n == 0 {
        appendLog(log, "No files found in dist/. Build first or choose a project with dist/.")
        setStatus(state, "Deploy failed")
        emit "1"
    }
    let i = 0
    let count = 0
    while i < n {
        let file = getLine(files, i)
        if len(file) > 0 {
            let rel = file
            if startsWith(rel, "dist/") { rel = substring(rel, 5, len(rel)) }
            let local = project + "/dist/" + rel
            let remoteRel = rel
            if remoteFolder != "" { remoteRel = remoteFolder + "/" + rel }
            let remote = "ftp://" + host + "/" + remoteRel
            appendLog(log, "upload " + rel)
            let curl = "curl --ftp-create-dirs -T " + shellQuote(local) + " " +
                shellQuote(remote) + " --user " + shellQuote(user + ":" + pass) + " --insecure 2>&1"
            let out = exec(curl)
            if len(out) > 0 { appendLog(log, out) }
            count = count + 1
        }
        i = i + 1
    }
    appendLog(log, "Deploy complete: " + count + " files")
    setStatus(state, "Deploy finished")
}

func onClear(self, cmd, sender) {
    let state = appH()
    let log = get(appH(), "log")
    doTextBox(log, "")
    recolorLog(log)
    setStatus(state, "Ready")
}

func onOpenDist(self, cmd, sender) {
    let state = appH()
    let project = stateField(state, "project")
    let log = get(appH(), "log")
    if project == "" {
        alert("kweb", "Choose a project folder first.")
        emit "1"
    }
    let cmd2 = "open " + shellQuote(project + "/dist") + " 2>&1"
    appendLog(log, "$ " + cmd2)
    appendLog(log, exec(cmd2))
}

func onChooseProject(self, cmd, sender) {
    let picked = chooseFolder("Choose kweb project folder")
    if picked == "" { emit "1" }
    doText(get(appH(), "project"), picked)
    appendLog(get(appH(), "log"), "Project set: " + picked)
    setStatus(appH(), "Project selected")
}

func putLabel(win, text, x, y, w) {
    let lbl = label(win, text, area(x, y, w, 22))
    doTextColor(lbl, kwebLabelColor())
    emit lbl
}

func wire(btn, key, handler) {
    doClick(btn, key, handler)
    emit "1"
}

func setupMenus(app) {
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
    let cwd = cleanLine(exec("pwd"))
    let application = app("kweb")
    setupMenus(application)
    let win = window("kweb deploy", 820, 560)
    doWindowBackground(win, kwebWindowBgColor())
    doTransparentTitlebar(win)

    putLabel(win, "Project", 24, 508, 76)
    let project = field(win, area(104, 506, 438, 26))
    tintField(project)
    doText(project, cwd)
    let chooseBtn = button(win, "Choose", area(554, 506, 108, 28))
    tintButton(chooseBtn)

    putLabel(win, "kweb", 24, 472, 76)
    let kweb = field(win, area(104, 470, 558, 26))
    tintField(kweb)
    doText(kweb, defaultKwebPath(cwd))

    putLabel(win, "Host", 24, 436, 76)
    let host = field(win, area(104, 434, 302, 26))
    tintField(host)

    putLabel(win, "User", 420, 436, 50)
    let user = field(win, area(474, 434, 188, 26))
    tintField(user)

    putLabel(win, "Pass", 24, 400, 76)
    let passField = password(win, area(104, 398, 558, 26))
    tintField(passField)

    putLabel(win, "Remote dir", 24, 364, 76)
    putLabel(win, "(root default)", 104, 364, 116)
    let remoteFolder = field(win, area(224, 362, 438, 26))
    tintField(remoteFolder)

    let buildBtn = button(win, "Build", area(686, 506, 108, 28))
    tintButton(buildBtn)
    let deployBtn = button(win, "Deploy", area(686, 470, 108, 28))
    tintButton(deployBtn)
    let distBtn = button(win, "Open dist", area(686, 434, 108, 28))
    tintButton(distBtn)
    let clearBtn = button(win, "Clear", area(686, 398, 108, 28))
    tintButton(clearBtn)

    let status = putLabel(win, "Ready", 24, 326, 770)
    let log = textBox(win, area(24, 24, 770, 290))
    doFont(log, mono(12))
    doNoWrap(log)
    doTextBox(log, "kweb GUI ready.\n")
    recolorLog(log)

    doSet(application, "project", project)
    doSet(application, "kweb", kweb)
    doSet(application, "host", host)
    doSet(application, "user", user)
    doSet(application, "password", passField)
    doSet(application, "remoteFolder", remoteFolder)
    doSet(application, "status", status)
    doSet(application, "log", log)

    wire(chooseBtn, "chooseProject", funcptr(onChooseProject))
    wire(buildBtn, "build", funcptr(onBuild))
    wire(deployBtn, "deploy", funcptr(onDeploy))
    wire(distBtn, "dist", funcptr(onOpenDist))
    wire(clearBtn, "clear", funcptr(onClear))

    doShow(win)
    doRun()
}
