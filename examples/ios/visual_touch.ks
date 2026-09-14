#!/usr/bin/env kr
// Tap or drag to paint with white SpriteKit circles.

import "k:okui"
import "k:visual"

func touched(self, cmd, touches, event) {
    let touch = visualTouch(touches)
    visualPaintTouch(self, touch, 18, iosWhite())
    emit 0
}

func touchLaunch(self, cmd, app, options) {
    let win = iosWindow(390, 844)
    let controller = iosController()
    doIosRoot(win, controller)
    let root = iosRootView(controller)

    let view = visualView(root, 0, 0, 390, 844)
    let sceneClass = visualSceneClass("KryptonTouchScene", funcptr(touched))
    let scene = visualCustomScene(sceneClass, 390, 844)
    visualBackground(scene, iosPurple())

    let title = visualLabel("Touch to draw", 30, iosWhite())
    visualPosition(title, 195, 700)
    visualAdd(scene, title)
    visualShow(view, scene)

    doIosKeep(self, win)
    doIosShow(win)
    emit 1
}

just run {
    let delegate = iosDelegate("KryptonTouchDelegate", funcptr(touchLaunch))
    doIosRun(delegate)
}
