// objk_ios.k -- Objective-K facade for UIKit.

module objk_ios

func okIosSharedApp()                         { emit chocIosSharedApp() }
func okIosDelegate(name, didLaunchFn)         { emit chocIosDelegate(name, didLaunchFn) }
func okIosRun(delegateName)                   { emit chocIosRun(delegateName) }
func okIosWindow(w, h)                        { emit chocIosWindow(w, h) }
func okIosController()                        { emit chocIosController() }
func okIosSetRoot(win, controller)            { emit chocIosSetRoot(win, controller) }
func okIosRootView(controller)                { emit chocIosRootView(controller) }
func okIosLabel(parent, text, x, y, w, h)     { emit chocIosLabel(parent, text, x, y, w, h) }
func okIosButton(parent, text, x, y, w, h)    { emit chocIosButton(parent, text, x, y, w, h) }
func okIosField(parent, x, y, w, h)           { emit chocIosTextField(parent, x, y, w, h) }
func okIosSetText(control, text)               { emit chocIosSetText(control, text) }
func okIosSystemPurple()                       { emit chocIosSystemPurple() }
func okIosWhite()                              { emit chocIosWhite() }
func okIosSetBackground(view, color)           { emit chocIosSetBackground(view, color) }
func okIosSetTextColor(control, color)         { emit chocIosSetTextColor(control, color) }
func okIosText(control)                        { emit chocIosGetText(control) }
func okIosKeep(owner, object)                  { emit chocIosKeep(owner, object) }
func okIosShow(win)                            { emit chocIosShow(win) }
