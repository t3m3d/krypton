#!/usr/bin/env kr
// check_okui.ks -- focused Objective-K/OKUI smoke.

import "k:env"

func dq() { emit fromCharCode(34) }
func bs() { emit fromCharCode(92) }
func q(s) { emit dq() + replace(s, dq(), bs() + dq()) + dq() }

func runCheck(name, cmd) {
    kp("check " + name)
    let rc = shellRun(cmd)
    if rc != "0" {
        kp("FAIL " + name + " rc=" + rc)
        exit("1")
    }
    kp("OK " + name)
}

just run {
    let os = environ("OS")
    if os == "Windows_NT" {
        runCheck("okui import route", "kcc.exe --ir examples/objk/human_ui.ks > nul")
        runCheck("kweb gui win", "kcc.exe --ir web/kweb_gui_win.ks > nul")
        exit("0")
    }

    let root = trim(exec("pwd"))
    let envRoot = "KRYPTON_ROOT=" + q(root) + " "
    runCheck("okui smoke app", envRoot + "./bootstrap/kcc_driver_macos_aarch64 -r scripts/build-objk-app.ks examples/objk/human_ui.ks human_ui >/tmp/check_okui_human.log 2>&1")
    runCheck("kweb gui app", envRoot + "./bootstrap/kcc_driver_macos_aarch64 -r scripts/build-objk-app.ks web/kweb_gui.ks kweb >/tmp/check_okui_kweb.log 2>&1")
}
