import "stdlib/objkwin.k"

just run {
    let app = okApp()
    let win = okWindow(app, "ObjK Min", 320, 180)
    okLabel(win, "ObjK min ready", 24, 24, 180, 24)
    okShow(win, app)
    okRun(app)
}
