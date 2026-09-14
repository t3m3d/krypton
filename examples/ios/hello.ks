#!/usr/bin/env kr
// First UIKit lifecycle smoke. Build through scripts/build-ios-app.ks.

import "k:okui"

func didLaunch(self, cmd, app, options) {
    let win = iosWindow(390, 844)
    let controller = iosController()
    doIosRoot(win, controller)
    let root = iosRootView(controller)
    doIosBackground(root, iosPurple())
    let title = iosLabel(root, "Hello from Krypton", 32, 120, 326, 44)
    let detail = iosLabel(root, "Pure Krypton + Objective-K + UIKit", 32, 170, 326, 32)
    doIosTextColor(title, iosWhite())
    doIosTextColor(detail, iosWhite())
    doIosKeep(self, win)
    doIosShow(win)
    emit 1
}

just run {
    let delegate = iosDelegate("KryptonHelloDelegate", funcptr(didLaunch))
    doIosRun(delegate)
}
