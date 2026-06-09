import "k:cocoa"
import "k:objc"
import "head:cocoa"
import "head:objc"

// colour every occurrence of `word` in `src`
func hlWord(tv, src, word, color) {
  let n = len(src)
  let wl = len(word)
  let pos = 0
  while pos < n {
    let i = indexOf(substring(src, pos, n), word)
    if i < 0 { emit "1" }
    cocoaTVColorRange(tv, color, pos + i, wl)
    pos = pos + i + wl
  }
  emit "1"
}

// colour // line comments grey
func hlComments(tv, src, color) {
  let n = len(src)
  let pos = 0
  while pos < n {
    let i = indexOf(substring(src, pos, n), "//")
    if i < 0 { emit "1" }
    let start = pos + i
    let rest = substring(src, start, n)
    let nl = indexOf(rest, "\n")
    let end = n
    if nl >= 0 { end = start + nl }
    cocoaTVColorRange(tv, color, start, end - start)
    pos = end + 1
  }
  emit "1"
}

func onSave(self, cmd, sender) {
  let tv = cocoaGetAssoc(sender)
  let path = arg(0)
  writeFile(path, cocoaTVGetString(tv))
  kp("saved: " + path)
}

just run {
  let path = arg(0)
  let src = readFile(path)
  if len(src) == 0 { src = "// kryedit — pure-Krypton editor on objk\nfunc hello() {\n    kp(\"hi\")\n}\n" }

  let app = cocoaInit()
  let win = cocoaWindow(app, "kryedit — " + path, 760, 560)
  let tv = cocoaScrollText(win, 0, 44, 760, 516)
  cocoaSetFont(tv, cocoaMonoFont(13))
  cocoaTVSetString(tv, src)

  let kw = cocoaColorNamed("purpleColor")
  hlWord(tv, src, "func", kw)
  hlWord(tv, src, "let", kw)
  hlWord(tv, src, "if", kw)
  hlWord(tv, src, "while", kw)
  hlWord(tv, src, "return", kw)
  hlWord(tv, src, "emit", kw)
  hlWord(tv, src, "import", kw)
  hlWord(tv, src, "just", kw)
  hlWord(tv, src, "run", kw)
  hlComments(tv, src, cocoaColorNamed("grayColor"))

  let btn = cocoaButton(win, "Save", 10, 8, 80, 30)
  cocoaSetAssoc(btn, tv)
  cocoaOnClick(btn, funcptr(onSave))
  cocoaShow(win, app)
  cocoaRun(app)
}
