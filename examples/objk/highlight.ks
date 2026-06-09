import "k:cocoa"
import "k:objc"
import "head:cocoa"
import "head:objc"
just run {
  let app = cocoaInit()
  let win = cocoaWindow(app, "Syntax highlighting — pure Krypton on objk", 560, 360)
  let tv = cocoaScrollText(win, 10, 10, 540, 340)
  cocoaSetFont(tv, cocoaMonoFont(15))
  let src = "// a comment, in grey\nfunc greet(name) {\n    kp(name)\n}\n"
  cocoaTVSetString(tv, src)
  cocoaTVColorRange(tv, cocoaColorNamed("grayColor"), 0, indexOf(src, "\n"))
  cocoaTVColorRange(tv, cocoaColorNamed("purpleColor"), indexOf(src, "func"), 4)
  cocoaTVColorRange(tv, cocoaColorNamed("blueColor"), indexOf(src, "greet"), 5)
  cocoaTVColorRange(tv, cocoaColorNamed("redColor"), indexOf(src, "kp"), 2)
  cocoaShow(win, app)
  cocoaRun(app)
}
