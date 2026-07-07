#!/usr/bin/env kr
// examples/objk/windows_controls.ks -- Objective-K facade on Windows.

import "stdlib/objkwin.k"

let g_name = ""
let g_value = ""
let g_secure = ""
let g_mode = ""
let g_bar = ""
let g_notes = ""
let g_status = ""
let g_level = 42

func setStatus(text) {
    okSetText(g_status, text)
    okAppend(g_notes, text + "\r\n")
}

func onBuild(self, cmd, sender) {
    let name = okText(g_name)
    if len(name) == 0 {
        setStatus("Project name missing")
        emit "1"
    }
    g_level += 10
    if g_level > 100 { g_level = 100 }
    okSetProgress(g_bar, g_level)
    setStatus("Built " + name + " with " + okComboText(g_mode) + " from " + sender)
    emit "1"
}

func onToggleSecure(self, cmd, sender) {
    if okState(g_secure) == "1" {
        setStatus("Secure deploy on")
        emit "1"
    }
    setStatus("Secure deploy off")
    emit "1"
}

func onOpenSite(self, cmd, sender) {
    okOpenURL("https://krypton-lang.org")
    setStatus("Opened krypton-lang.org")
    emit "1"
}

func onClear(self, cmd, sender) {
    okSetText(g_name, "")
    okSetText(g_value, "")
    okSetTextView(g_notes, "")
    g_level = 0
    okSetProgress(g_bar, g_level)
    okSetText(g_status, "Ready")
    emit "1"
}

just run {
    let app = okApp()
    let win = okWindow(app, "Objective-K Windows Controls", 680, 460)
    okTransparentTitlebar(win)
    okSetWindowBg(win, okSystemWindowBg())
    okSetFont(win, "Segoe UI")

    okLabel(win, "Objective-K on Windows", 28, 24, 260, 24)
    g_status = okLabel(win, "Ready", 520, 24, 120, 24)

    okLabel(win, "Project", 28, 72, 100, 22)
    g_name = okField(win, 128, 68, 340, 28)
    okSetText(g_name, "krypton")

    okLabel(win, "Value", 28, 112, 100, 22)
    g_value = okField(win, 128, 108, 340, 28)

    okLabel(win, "Mode", 28, 154, 100, 22)
    g_mode = okCombo(win, 128, 150, 180, 160)
    okComboAdd(g_mode, "debug")
    okComboAdd(g_mode, "release")
    okComboAdd(g_mode, "deploy")
    okComboSelect(g_mode, 1)

    g_secure = okCheckbox(win, "Use secure deploy path", 336, 151, 220, 24)

    let build = okButton(win, "Build", 128, 202, 110, 34)
    let open = okButton(win, "Open site", 252, 202, 110, 34)
    let clear = okButton(win, "Clear", 376, 202, 110, 34)

    g_bar = okProgress(win, 128, 252, 358, 18)
    okSetProgress(g_bar, g_level)

    okLabel(win, "Activity", 28, 286, 100, 22)
    g_notes = okTextView(win, 128, 284, 500, 112)
    okSetTextView(g_notes, "Objective-K Windows facade ready.\r\n")

    okClick(build, funcptr(onBuild))
    okClick(open, funcptr(onOpenSite))
    okClick(clear, funcptr(onClear))
    okClick(g_secure, funcptr(onToggleSecure))

    okShow(win, app)
    okRun(app)
}
