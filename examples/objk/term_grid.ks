import "k:cocoa"
import "k:objc"
import "head:cocoa"
import "head:objc"

func draw(self, cmd) {
  cocoaColorSet(cocoaColorNamed("blackColor"))
  cocoaFillRect(0, 0, 520, 300)
  let green = cocoaTextAttrs(cocoaMonoFont(15), cocoaColorNamed("greenColor"))
  cocoaDrawText("krypton$ echo pure-Krypton terminal grid", 10, 264, 500, 22, green)
  cocoaDrawText("pure-Krypton terminal grid", 10, 240, 500, 22, green)
  let cyan = cocoaTextAttrs(cocoaMonoFont(15), cocoaColorNamed("cyanColor"))
  cocoaDrawText("krypton$ ls", 10, 210, 500, 22, cyan)
  cocoaDrawText("README.md  src/  build.sh", 10, 186, 500, 22, green)
  let red = cocoaTextAttrs(cocoaMonoFont(15), cocoaColorNamed("redColor"))
  cocoaDrawText("krypton$ boom  -> error: drawn in red via objc", 10, 156, 500, 22, red)
  emit "1"
}

just run {
  let app = cocoaInit()
  let win = cocoaWindow(app, "kryoterm grid — pure Krypton (drawRect + text)", 520, 300)
  let vc = cocoaViewClassNew("KryptonTermView")
  cocoaClassAddMethod(vc, "drawRect:", funcptr(draw), "v@:{CGRect={CGPoint=dd}{CGSize=dd}}")
  cocoaClassRegister(vc)
  cocoaCustomView(win, vc, 0, 0, 520, 300)
  cocoaShow(win, app)
  cocoaRun(app)
}
