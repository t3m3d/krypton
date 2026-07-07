module choc_wrap

import "stdlib/choc.k"

func cwApp() { emit chocInit() }
func cwWindow(app, title, w, h) { emit chocWindow(app, title, w, h) }
func cwShow(win, app) { emit chocShow(win, app) }
func cwRun(app) { emit chocRun(app) }
