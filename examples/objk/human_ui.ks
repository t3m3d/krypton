#!/usr/bin/env kr
// examples/objk/human_ui.ks -- programmer-facing Objective-K style.

import "k:okui"

func copyName(self, cmd, sender) {
    let nameField = get(sender, "name")
    let status = get(sender, "status")
    doCopyText(text(nameField))
    doText(status, "Copied")
    emit done()
}

func saveName(self, cmd, sender) {
    let nameField = get(sender, "name")
    let status = get(sender, "status")
    doSetting("okui.human.name", text(nameField))
    doText(status, "Saved")
    emit done()
}

func openSite(self, cmd, sender) {
    doOpenURL("https://krypton-lang.org")
    emit done()
}

just run {
    app("Human Objective-K")
    let win = window("Human Objective-K", 540, 300)
    minSize(win, 500, 280)

    let root = page(540, 300, 24)
    title(win, "Native UI without platform ceremony", top(root, 32))

    let first = row(root, 1, 30, 14)
    let name = field(win, left(first, 320))
    doPlaceholder(name, "Name")
    let saved = setting("okui.human.name")
    if len(saved) > 0 { doText(name, saved) }

    let save = button(win, "Save", rightOf(left(first, 320), 14, 80))
    let copy = button(win, "Copy", right(first, 80))

    let second = row(root, 2, 28, 14)
    let deploy = checkbox(win, "Deploy after build", left(second, 220))
    doState(deploy, 1)

    let target = choices(win, right(second, 160))
    doAddChoice(target, "ftp")
    doAddChoice(target, "sftp")
    doChoose(target, 0)

    let third = row(root, 3, 18, 14)
    let bar = progress(win, third)
    doProgress(bar, 64)

    let open = button(win, "Open site", right(row(root, 4, 30, 14), 120))
    let status = label(win, "Ready", bottom(root, 24))

    doSet(save, "name", name)
    doSet(save, "status", status)
    doClick(save, "human.save", funcptr(saveName))

    doSet(copy, "name", name)
    doSet(copy, "status", status)
    doClick(copy, "human.copy", funcptr(copyName))

    doClick(open, "human.open", funcptr(openSite))

    doShow(win)
    doRun()
}
