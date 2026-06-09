// stem — a pure-Krypton terminal on objk (no Obj-C source).
// A real shell on a pseudo-terminal (native pty builtins). The pty is read in a
// MANUAL event loop (not a timer callback — fdRead inside a run-loop callback
// faults), and typed commands are written back over the master fd. Replaces
// gui_shim.m.
import "k:cocoa"
import "k:objc"
import "head:cocoa"
import "head:objc"

func appH() { emit msg(cls("NSApplication"), "sharedApplication") }

// Command entered: write it to the shell with a newline.
func onCmd(self, cmd, sender) {
  let app = appH()
  let master = cocoaNumberVal(cocoaGetAssocKey(app, "stem.master"))
  let line = msg(msg(sender, "stringValue"), "UTF8String") + "\n"
  fdWrite(master, line, len(line))
  msg_1(sender, "setStringValue:", nsString(""))
}

just run {
  // 1. real shell on a pty
  let m = ptyMaster("/dev/ptmx")
  let slave = ptySlaveName(m)
  ptyForkExec(slave, "/bin/sh")
  fdSetNonblock(m)

  // 2. window: terminal view + command input
  let app = cocoaInit()
  let win = cocoaWindow(app, "stem — pure-Krypton terminal on objk", 760, 520)
  let view = cocoaScrollText(win, 0, 40, 760, 480)
  msg_1(view, "setEditable:", 0)
  cocoaSetFont(view, cocoaMonoFont(13))
  let input = cocoaTextField(win, 0, 6, 760, 28)

  cocoaSetAssocKey(app, "stem.master", cocoaNumber(m))
  cocoaOnClick(input, funcptr(onCmd))
  cocoaShow(win, app)
  cocoaMakeFirstResponder(win, input)

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
