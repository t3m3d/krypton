// stem — a pure-Krypton terminal on objk (no Obj-C source).
// A real shell on a pseudo-terminal (native pty builtins). Raw keystrokes are
// written straight to the pty; the shell echoes them, so input appears inline
// after the prompt (a real terminal, not a separate input box). The pty is read
// in a MANUAL event loop — fdRead inside a run-loop callback faults. Replaces
// gui_shim.m.
import "k:cocoa"
import "k:objc"
import "head:cocoa"
import "head:objc"

func appH() { emit msg(cls("NSApplication"), "sharedApplication") }

// Raw key -> pty. The shell echoes it back into the output stream.
func onKey(self, cmd, event) {
  let chars = msg(msg(event, "characters"), "UTF8String")
  let master = cocoaNumberVal(cocoaGetAssocKey(appH(), "stem.master"))
  fdWrite(master, chars, len(chars))
}
func acceptsFR(self, cmd) { emit 1 }

just run {
  // 1. real shell on a pty
  let m = ptyMaster("/dev/ptmx")
  let slave = ptySlaveName(m)
  ptyForkExec(slave, "/bin/sh")
  fdSetNonblock(m)

  // 2. window: an output text view + a transparent key-capture view on top
  let app = cocoaInit()
  let win = cocoaWindow(app, "stem — pure-Krypton terminal on objk", 760, 500)
  let view = cocoaScrollText(win, 0, 0, 760, 500)
  msg_1(view, "setEditable:", 0)
  msg_1(view, "setSelectable:", 0)
  cocoaSetFont(view, cocoaMonoFont(13))

  let kc = cocoaViewClassNew("StemKeys")
  cocoaClassAddMethod(kc, "keyDown:", funcptr(onKey), "v@:@")
  cocoaClassAddMethod(kc, "acceptsFirstResponder", funcptr(acceptsFR), "c@:")
  cocoaClassRegister(kc)
  let kview = cocoaCustomView(win, kc, 0, 0, 760, 500)

  cocoaSetAssocKey(app, "stem.master", cocoaNumber(m))
  cocoaSetAssocKey(app, "stem.view", view)
  cocoaShow(win, app)
  cocoaMakeFirstResponder(win, kview)

  // 3. manual loop: pump events, read the pty, append — all in the main flow
  cocoaFinishLaunching(app)
  let running = 1
  while running == 1 {
    cocoaPumpEvents(app)
    let chunk = fdRead(m, 4096)
    if len(chunk) > 0 { cocoaTVAppend(view, chunk) }
    sleepUs(0, 8000)
  }
}
