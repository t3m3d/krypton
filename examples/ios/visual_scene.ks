#!/usr/bin/env kr
// Animated SpriteKit scene through Krypton's visual API.

import "k:okui"
import "k:visual"

func visualLaunch(self, cmd, app, options) {
    let win = iosWindow(390, 844)
    let controller = iosController()
    doIosRoot(win, controller)
    let root = iosRootView(controller)

    let view = visualView(root, 0, 0, 390, 844)
    let scene = visualScene(390, 844)
    visualBackground(scene, iosPurple())

    let title = visualLabel("Krypton Visual", 32, iosWhite())
    visualPosition(title, 195, 680)
    visualAdd(scene, title)

    let ball = visualCircle(32, iosWhite())
    visualPosition(ball, 90, 420)
    visualAdd(scene, ball)
    visualMove(ball, 210, 0, 2)

    visualShow(view, scene)
    doIosKeep(self, win)
    doIosShow(win)
    emit 1
}

just run {
    let delegate = iosDelegate("KryptonVisualDelegate", funcptr(visualLaunch))
    doIosRun(delegate)
}
