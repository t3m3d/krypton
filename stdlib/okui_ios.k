// okui_ios.k -- iOS OKUI wrapper. Alpha API grows toward okui_core parity.

module okui

import "head:objc"
import "head:foundation_ios"
import "head:uikit"
import "k:objc"
import "k:choc_ios"
import "k:objk_ios"

func iosApp()                                  { emit okIosSharedApp() }
func iosDelegate(name, didLaunchFn)            { emit okIosDelegate(name, didLaunchFn) }
func doIosRun(delegateName)                    { emit okIosRun(delegateName) }
func iosWindow(w, h)                           { emit okIosWindow(w, h) }
func iosController()                           { emit okIosController() }
func doIosRoot(win, controller)                { emit okIosSetRoot(win, controller) }
func iosRootView(controller)                   { emit okIosRootView(controller) }
func iosLabel(parent, text, x, y, w, h)        { emit okIosLabel(parent, text, x, y, w, h) }
func iosButton(parent, text, x, y, w, h)       { emit okIosButton(parent, text, x, y, w, h) }
func iosField(parent, x, y, w, h)              { emit okIosField(parent, x, y, w, h) }
func doIosText(control, text)                  { emit okIosSetText(control, text) }
func iosPurple()                               { emit okIosSystemPurple() }
func iosWhite()                                { emit okIosWhite() }
func doIosBackground(view, color)              { emit okIosSetBackground(view, color) }
func doIosTextColor(control, color)             { emit okIosSetTextColor(control, color) }
func iosText(control)                          { emit okIosText(control) }
func doIosKeep(owner, object)                  { emit okIosKeep(owner, object) }
func doIosShow(win)                            { emit okIosShow(win) }
