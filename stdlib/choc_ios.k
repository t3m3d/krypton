// choc_ios.k -- UIKit backend for Objective-K. Pure Krypton source.

module choc_ios

import "k:objc"

func chocIosSharedApp() {
    emit msg(cls("UIApplication"), "sharedApplication")
}

func chocIosDelegate(name, didLaunchFn) {
    let c = objc_allocateClassPair(cls("NSObject"), name, 0)
    class_addMethod(c, sel("application:didFinishLaunchingWithOptions:"),
        didLaunchFn, "B@:@@")
    objc_registerClassPair(c)
    emit name
}

func chocIosRun(delegateName) {
    emit UIApplicationMain(0, 0, 0, nsString(delegateName))
}

func chocIosWindow(w, h) {
    let raw = msg(cls("UIWindow"), "alloc")
    emit msg_frame(raw, "initWithFrame:", 0, 0, w, h)
}

func chocIosController() {
    emit allocInit("UIViewController")
}

func chocIosSetRoot(win, controller) {
    msg_1(win, "setRootViewController:", controller)
    emit controller
}

func chocIosRootView(controller) {
    emit msg(controller, "view")
}

func chocIosLabel(parent, text, x, y, w, h) {
    let label = msg_frame(msg(cls("UILabel"), "alloc"), "initWithFrame:", x, y, w, h)
    msg_1(label, "setText:", nsString(text))
    msg_1(parent, "addSubview:", label)
    emit label
}

func chocIosButton(parent, text, x, y, w, h) {
    let button = msg_1(cls("UIButton"), "buttonWithType:", 1)
    msg_frame(button, "setFrame:", x, y, w, h)
    msg_2(button, "setTitle:forState:", nsString(text), 0)
    msg_1(parent, "addSubview:", button)
    emit button
}

func chocIosTextField(parent, x, y, w, h) {
    let field = msg_frame(msg(cls("UITextField"), "alloc"), "initWithFrame:", x, y, w, h)
    msg_1(field, "setBorderStyle:", 3)
    msg_1(parent, "addSubview:", field)
    emit field
}

func chocIosSetText(control, text) {
    msg_1(control, "setText:", nsString(text))
    emit 1
}

func chocIosSystemPurple() {
    emit msg(cls("UIColor"), "systemPurpleColor")
}

func chocIosWhite() {
    emit msg(cls("UIColor"), "whiteColor")
}

func chocIosSetBackground(view, color) {
    msg_1(view, "setBackgroundColor:", color)
    emit 1
}

func chocIosSetTextColor(control, color) {
    msg_1(control, "setTextColor:", color)
    emit 1
}

func chocIosGetText(control) {
    let value = msg(control, "text")
    emit msg(value, "UTF8String")
}

func chocIosKeep(owner, object) {
    objc_setAssociatedObject(owner, owner, object, 1)
    emit object
}

func chocIosShow(win) {
    msg(win, "makeKeyAndVisible")
    emit 1
}
