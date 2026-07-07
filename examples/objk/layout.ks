#!/usr/bin/env kr
// examples/objk/layout.ks -- Objective-K rect/layout smoke app.

import "k:objk"

func onCopy(self, cmd, sender) {
    let field = okGet(sender, "field")
    let status = okGet(sender, "status")
    okSetClipboard(okText(field))
    okSetText(status, "Copied")
    emit "1"
}

func onReveal(self, cmd, sender) {
    okReveal("/tmp")
    emit "1"
}

just run {
    let app = okApp()
    let win = okWindow(app, "Objective-K Layout", 520, 320)
    okMinSize(win, 480, 280)

    let root = okInset(okRect(0, 0, 520, 320), 24)
    let title = okTop(root, 30)
    okLabelR(win, "Backend-swappable Objective-K layout", title)

    let row1 = okBelow(title, 16, 30)
    let field = okFieldR(win, okLeft(row1, 300))
    okPlaceholder(field, "Text to copy")
    okSetText(field, "hello from ok layout")

    let copyBtn = okButtonR(win, "Copy", okRightOf(okLeft(row1, 300), 16, 96))
    let revealBtn = okButtonR(win, "Reveal /tmp", okRight(row1, 96))

    let row2 = okBelow(row1, 14, 28)
    let check = okCheckboxR(win, "Use system theme", okLeft(row2, 210))
    okSetState(check, 1)
    let combo = okComboR(win, okRight(row2, 150))
    okComboAdd(combo, "macOS")
    okComboAdd(combo, "future backend")
    okComboSelect(combo, 0)

    let row3 = okBelow(row2, 18, 18)
    let progress = okProgressR(win, row3)
    okSetProgress(progress, 72)

    let status = okLabelR(win, "Ready", okBottom(root, 24))
    okSet(copyBtn, "field", field)
    okSet(copyBtn, "status", status)
    okOn(copyBtn, "layout.copy", funcptr(onCopy))
    okOn(revealBtn, "layout.reveal", funcptr(onReveal))

    okShow(win, app)
    okRun(app)
}
