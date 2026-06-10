// stem — a pure-Krypton terminal on objk (no Obj-C source).
// Real shell on a pseudo-terminal (native pty builtins). Raw keystrokes go
// straight to the pty (shell echoes them inline). The pty is read in a MANUAL
// event loop (fdRead inside a run-loop callback faults), and a small terminal
// filter handles backspace + strips CSI escapes so line editing reads cleanly.
// Replaces gui_shim.m.
import "k:cocoa"
import "k:objc"
import "head:cocoa"
import "head:objc"

func appH() { emit msg(cls("NSApplication"), "sharedApplication") }

func onKey(self, cmd, event) {
  let m = cocoaNumberVal(cocoaGetAssocKey(appH(), "stem.master"))
  let esc = fromCharCode(27)
  let kc = msg(event, "keyCode")
  let seq = ""
  if kc == 126 { seq = esc + "[A" }       // up
  if kc == 125 { seq = esc + "[B" }       // down
  if kc == 124 { seq = esc + "[C" }       // right
  if kc == 123 { seq = esc + "[D" }       // left
  if seq == "" { seq = msg(msg(event, "characters"), "UTF8String") }
  fdWrite(m, seq, len(seq))
}
func acceptsFR(self, cmd) { emit 1 }

// Dark mode? effectiveAppearance name contains "Dark".
func isDarkMode(app) {
  emit indexOf(msg(msg(msg(app, "effectiveAppearance"), "name"), "UTF8String"), "Dark") >= 0
}

// Is `ch` a CSI final byte (0x40..0x7e)? Ends an ESC[ … sequence.
func isCsiFinal(ch) { emit indexOf("@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~", ch) >= 0 }
// Index of the last newline in `s` (-1 if none).
func lastNl(s) { let i = len(s) - 1  while i >= 0 { if s[i] == "\n" { emit i }  i = i - 1 }  emit 0 - 1 }

// Apply a raw pty chunk to the on-screen string: backspace/DEL erase the last
// char, CR clears the current line (shells redraw the line after \r), ESC[ …
// CSI is stripped (ESC[2J clears the screen), everything else appends.
// (Line-mode terminal: handles shell editing; full-screen apps need a grid.)
func applyChunk(screen, chunk) {
  let bs = fromCharCode(8)
  let del = fromCharCode(127)
  let cr = fromCharCode(13)
  let esc = fromCharCode(27)
  let n = len(chunk)
  let out = screen
  let i = 0
  while i < n {
    let c = chunk[i]
    let handled = 0
    if c == bs  { if len(out) > 0 { out = substring(out, 0, len(out) - 1) }  handled = 1 }
    if c == del { if len(out) > 0 { out = substring(out, 0, len(out) - 1) }  handled = 1 }
    if c == cr  { handled = 1 }   // drop CR; in CRLF the LF makes the newline (clearing here ate kryofetch's text)
    if c == esc {
      handled = 1
      i = i + 1
      if i < n {
        if chunk[i] == "[" {
          i = i + 1
          let body = ""
          let done = 0
          while done == 0 {
            if i >= n { done = 1 }
            if done == 0 {
              let ch = chunk[i]
              i = i + 1
              if isCsiFinal(ch) {
                if ch == "J" { if indexOf(body, "2") >= 0 { out = "" } }
                done = 1
              }
              if done == 0 { body = body + ch }
            }
          }
          i = i - 1
        }
      }
    }
    if handled == 0 { out = out + c }
    i = i + 1
  }
  emit out
}

just run {
  let m = ptyMaster("/dev/ptmx")
  let slave = ptySlaveName(m)
  ptyForkExec(slave, "/bin/sh")
  fdSetNonblock(m)
  // GUI apps launch with a minimal PATH; add Homebrew + common bins, then clear.
  let setup = "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\"; clear\n"
  fdWrite(m, setup, len(setup))

  let app = cocoaInit()
  let win = cocoaWindow(app, "stem — pure-Krypton terminal on objk", 760, 500)
  let view = cocoaScrollText(win, 0, 0, 760, 500)
  msg_1(view, "setEditable:", 0)
  msg_1(view, "setSelectable:", 0)
  cocoaSetFont(view, cocoaMonoFont(13))
  // gloss black in dark mode, dark grey in light mode; light text on top
  let bg = cocoaColorNamed("darkGrayColor")
  if isDarkMode(app) == 1 { bg = cocoaColorNamed("blackColor") }
  cocoaSetBg(view, bg)
  cocoaSetTextColor(view, cocoaColorNamed("whiteColor"))
  // window chrome matches: dark-styled titlebar + border showing the bg colour
  msg_1(win, "setBackgroundColor:", bg)
  msg_1(win, "setTitlebarAppearsTransparent:", 1)
  msg_1(win, "setAppearance:", msg_1(cls("NSAppearance"), "appearanceNamed:", nsString("NSAppearanceNameDarkAqua")))

  let kc = cocoaViewClassNew("StemKeys")
  cocoaClassAddMethod(kc, "keyDown:", funcptr(onKey), "v@:@")
  cocoaClassAddMethod(kc, "acceptsFirstResponder", funcptr(acceptsFR), "c@:")
  cocoaClassRegister(kc)
  let kview = cocoaCustomView(win, kc, 0, 0, 760, 500)

  cocoaSetAssocKey(app, "stem.master", cocoaNumber(m))
  cocoaShow(win, app)
  cocoaMakeFirstResponder(win, kview)
  cocoaFinishLaunching(app)

  let screen = ""
  let running = 1
  while running == 1 {
    cocoaPumpEvents(app)
    let chunk = fdRead(m, 4096)
    if len(chunk) > 0 {
      screen = applyChunk(screen, chunk)
      if len(screen) > 12000 { screen = substring(screen, len(screen) - 12000, len(screen)) }
      cocoaTVSetString(view, screen + "█")    // block cursor at the input position
      msg_1(view, "scrollToEndOfDocument:", 0)
    }
    sleepUs(0, 8000)
  }
}
