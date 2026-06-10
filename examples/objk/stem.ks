// stem — a pure-Krypton terminal on objk (no Obj-C source).
// Real shell on a pty (native pty builtins). Raw keys -> pty (shell echoes
// inline). The pty is read in a MANUAL event loop (fdRead in a run-loop callback
// faults) and parsed into coloured text runs (SGR) in the view's textStorage,
// with backspace + CSI handling. Replaces gui_shim.m.
import "k:cocoa"
import "k:objc"
import "head:cocoa"
import "head:objc"

func appH() { emit msg(cls("NSApplication"), "sharedApplication") }

// Raw key -> pty. Arrows become ESC[ABCD; other keys pass through.
func onKey(self, cmd, event) {
  let m = cocoaNumberVal(cocoaGetAssocKey(appH(), "stem.master"))
  let esc = fromCharCode(27)
  let kc = msg(event, "keyCode")
  let seq = ""
  if kc == 126 { seq = esc + "[A" }
  if kc == 125 { seq = esc + "[B" }
  if kc == 124 { seq = esc + "[C" }
  if kc == 123 { seq = esc + "[D" }
  if seq == "" { seq = msg(msg(event, "characters"), "UTF8String") }
  fdWrite(m, seq, len(seq))
}
func acceptsFR(self, cmd) { emit 1 }
func isDarkMode(app) { emit indexOf(msg(msg(msg(app, "effectiveAppearance"), "name"), "UTF8String"), "Dark") >= 0 }

func isCsiFinal(ch) { emit indexOf("@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~", ch) >= 0 }

// SGR params -> NSColor (deflt on reset/unknown).
func sgrColor(body, deflt) {
  if indexOf(body, "31") >= 0 { emit cocoaColorNamed("systemRedColor") }
  if indexOf(body, "32") >= 0 { emit cocoaColorNamed("systemGreenColor") }
  if indexOf(body, "33") >= 0 { emit cocoaColorNamed("systemYellowColor") }
  if indexOf(body, "34") >= 0 { emit cocoaColorNamed("systemBlueColor") }
  if indexOf(body, "35") >= 0 { emit cocoaColorNamed("systemPurpleColor") }
  if indexOf(body, "36") >= 0 { emit cocoaColorNamed("systemTealColor") }
  if indexOf(body, "37") >= 0 { emit cocoaColorNamed("whiteColor") }
  emit deflt
}

// Append `text` to the storage `ts` coloured `color` in `font` (mono — without
// a font attribute the run renders proportional and breaks column alignment).
func appendRun(ts, text, color, font) {
  if len(text) == 0 { emit "1" }
  let start = msg(ts, "length")
  msg_1(ts, "appendAttributedString:", msg_1(msg(cls("NSAttributedString"), "alloc"), "initWithString:", nsString(text)))
  let span = msg(ts, "length") - start
  msg_4(ts, "addAttribute:value:range:", nsString("NSColor"), color, start, span)
  msg_4(ts, "addAttribute:value:range:", nsString("NSFont"), font, start, span)
  emit "1"
}
func tsLen(ts) { emit msg(ts, "length") }
func delLast(ts) { let L = msg(ts, "length")  if L > 0 { msg_2(ts, "deleteCharactersInRange:", L - 1, 1) }  emit "1" }
func clearTs(ts) { msg_2(ts, "deleteCharactersInRange:", 0, msg(ts, "length"))  emit "1" }

// Parse a raw chunk into coloured runs appended to `ts`; returns the new colour.
func processChunk(ts, chunk, curColor, deflt, font) {
  let esc = fromCharCode(27)
  let bs = fromCharCode(8)
  let del = fromCharCode(127)
  let cr = fromCharCode(13)
  let n = len(chunk)
  let i = 0
  let run = ""
  let color = curColor
  while i < n {
    let c = chunk[i]
    if c == esc {
      if len(run) > 0 { appendRun(ts, run, color, font)  run = "" }
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
                if ch == "m" { color = sgrColor(body, deflt) }
                if ch == "J" { if indexOf(body, "2") >= 0 { clearTs(ts) } }
                done = 1
              }
              if done == 0 { body = body + ch }
            }
          }
        }
      }
    } else {
      let ctrl = 0
      if c == bs  { ctrl = 1 }
      if c == del { ctrl = 1 }
      if ctrl == 1 {
        if len(run) > 0 { run = substring(run, 0, len(run) - 1) }
        else { delLast(ts) }
        i = i + 1
      } else {
        if c == cr { i = i + 1 }
        else { run = run + c  i = i + 1 }
      }
    }
  }
  if len(run) > 0 { appendRun(ts, run, color, font) }
  emit color
}

just run {
  let m = ptyMaster("/dev/ptmx")
  let slave = ptySlaveName(m)
  ptyForkExec(slave, "/bin/sh")
  fdSetNonblock(m)
  let setup = "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\"; clear\n"
  fdWrite(m, setup, len(setup))

  let app = cocoaInit()
  let win = cocoaWindow(app, "stem — pure-Krypton terminal on objk", 760, 500)
  let view = cocoaScrollText(win, 0, 0, 760, 500)
  msg_1(view, "setEditable:", 0)
  msg_1(view, "setSelectable:", 0)
  let mono = cocoaMonoFont(13)
  cocoaSetFont(view, mono)
  let fg = cocoaColorNamed("whiteColor")
  let bg = cocoaColorNamed("darkGrayColor")
  if isDarkMode(app) == 1 { bg = cocoaColorNamed("blackColor") }
  cocoaSetBg(view, bg)
  cocoaSetTextColor(view, fg)
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

  let ts = msg(view, "textStorage")
  let curColor = fg
  let hasCursor = 0
  let running = 1
  while running == 1 {
    cocoaPumpEvents(app)
    let chunk = fdRead(m, 4096)
    if len(chunk) > 0 {
      if hasCursor == 1 { delLast(ts)  hasCursor = 0 }
      curColor = processChunk(ts, chunk, curColor, fg, mono)
      let L = tsLen(ts)
      if L > 16000 { msg_2(ts, "deleteCharactersInRange:", 0, L - 16000) }
      appendRun(ts, "█", fg, mono)
      hasCursor = 1
      msg_1(view, "scrollToEndOfDocument:", 0)
    }
    sleepUs(0, 8000)
  }
}
