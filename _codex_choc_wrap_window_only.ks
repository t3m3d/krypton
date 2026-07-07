import "_codex_choc_wrap.k"

just run {
    let app = cwApp()
    let win = cwWindow(app, "Wrapped Choc Window Only", 320, 180)
    cwShow(win, app)
    cwRun(app)
}
