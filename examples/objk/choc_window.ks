#!/usr/bin/env kr
// examples/objk/choc_window.ks -- native Windows Choc smoke app.

import "stdlib/choc.k"

just run {
    let app = chocInit()
    let win = chocWindow(app, "Choc Window", 320, 180)
    chocLabel(win, "Choc ready", 24, 24, 180, 24)
    chocShow(win, app)
    chocRun(app)
}
