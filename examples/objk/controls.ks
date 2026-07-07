#!/usr/bin/env kr
// examples/objk/controls.ks -- Objective-K facade smoke app, pure Krypton.

import "k:objk"

func onToggle(self, cmd, sender) {
    let status = okGet(sender, "status")
    if okState(sender) == 1 {
        okSetText(status, "Checkbox on")
        emit "1"
    }
    okSetText(status, "Checkbox off")
    emit "1"
}

func onSave(self, cmd, sender) {
    let field = okGet(sender, "field")
    let status = okGet(sender, "status")
    okSetDefault("objk.controls.name", okText(field))
    okSetText(status, "Saved to defaults")
    emit "1"
}

func onCopy(self, cmd, sender) {
    let field = okGet(sender, "field")
    let status = okGet(sender, "status")
    okSetClipboard(okText(field))
    okSetText(status, "Copied to clipboard")
    emit "1"
}

func onOpenSite(self, cmd, sender) {
    okOpenURL("https://krypton-lang.org")
    emit "1"
}

just run {
    let app = okApp()
    let win = okWindow(app, "Obj-K Controls", 460, 300)
    okMinSize(win, 420, 260)

    let name = okField(win, 32, 230, 260, 28)
    okPlaceholder(name, "Saved name")
    let saved = okDefault("objk.controls.name")
    if len(saved) > 0 { okSetText(name, saved) }

    let save = okButton(win, "Save", 310, 230, 110, 28)
    let copy = okButton(win, "Copy", 310, 194, 110, 28)
    let link = okButton(win, "Open site", 310, 158, 110, 28)

    let cb = okCheckbox(win, "Use secure deploy", 32, 190, 220, 28)
    let combo = okCombo(win, 32, 150, 220, 28)
    okComboAdd(combo, "ftp")
    okComboAdd(combo, "sftp")
    okComboAdd(combo, "test")
    okComboSelect(combo, 0)

    let slider = okSlider(win, 32, 106, 220, 24, 0, 100, 66)
    let bar = okProgress(win, 32, 74, 220, 16)
    okSetProgress(bar, 66)
    let spin = okSpinner(win, 276, 72, 24, 24)
    okStart(spin)

    let status = okLabel(win, "Ready", 32, 34, 388, 24)
    okToolTip(status, "Status text")

    okSet(cb, "status", status)
    okOn(cb, "controls.toggle", funcptr(onToggle))

    okSet(save, "field", name)
    okSet(save, "status", status)
    okOn(save, "controls.save", funcptr(onSave))

    okSet(copy, "field", name)
    okSet(copy, "status", status)
    okOn(copy, "controls.copy", funcptr(onCopy))

    okOn(link, "controls.open", funcptr(onOpenSite))

    okShow(win, app)
    okRun(app)
}
