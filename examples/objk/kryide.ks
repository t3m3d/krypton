import "k:cocoa"
import "k:objc"
import "head:cocoa"
import "head:objc"

func nlines(s) { let n = len(s)  let c = 0  let i = 0  while i < n { if s[i] == "\n" { c = c + 1 }  i = i + 1 }  emit c }
func lineAt(s, idx) {
  let n = len(s)  let cur = 0  let start = 0  let i = 0
  while i < n { if s[i] == "\n" { if cur == idx { emit substring(s, start, i) }  cur = cur + 1  start = i + 1 }  i = i + 1 }
  emit ""
}

func hlWord(ts, src, word, color) {
  let n = len(src)  let wl = len(word)  let pos = 0
  while pos < n {
    let i = indexOf(substring(src, pos, n), word)
    if i < 0 { emit "1" }
    cocoaTSColorRange(ts, color, pos + i, wl)
    pos = pos + i + wl
  }
  emit "1"
}
func hlComments(ts, src, color) {
  let n = len(src)  let pos = 0
  while pos < n {
    let i = indexOf(substring(src, pos, n), "//")
    if i < 0 { emit "1" }
    let start = pos + i
    let nl = indexOf(substring(src, start, n), "\n")
    let end = n
    if nl >= 0 { end = start + nl }
    cocoaTSColorRange(ts, color, start, end - start)
    pos = end + 1
  }
  emit "1"
}
func highlightTS(ts, src) {
  let kw = cocoaColorNamed("purpleColor")
  hlWord(ts, src, "func", kw)  hlWord(ts, src, "let", kw)  hlWord(ts, src, "if", kw)
  hlWord(ts, src, "else", kw)  hlWord(ts, src, "while", kw) hlWord(ts, src, "return", kw)
  hlWord(ts, src, "emit", kw)  hlWord(ts, src, "import", kw) hlWord(ts, src, "module", kw)
  hlWord(ts, src, "const", kw) hlWord(ts, src, "just", kw)   hlWord(ts, src, "run", kw)
  hlWord(ts, src, "kp", cocoaColorNamed("blueColor"))
  hlComments(ts, src, cocoaColorNamed("grayColor"))
  emit "1"
}

func reHL(self, cmd, notif) {
  let ts = msg(notif, "object")
  if cocoaTSEditedChars(ts) == 0 { emit "1" }
  cocoaTSClearColor(ts)
  highlightTS(ts, cocoaTSString(ts))
}

func onSave(self, cmd, sender) {
  let app = msg(cls("NSApplication"), "sharedApplication")
  let cp = cocoaGetAssocKey(app, "kryide.curpath")
  if cp == 0 { kp("kryide: no file open")  emit "1" }
  let path = msg(cp, "UTF8String")
  writeFile(path, cocoaTVGetString(cocoaGetAssocKey(app, "kryide.editor")))
  kp("kryide: saved " + path)
}

func dsRows(self, cmd, tv) { emit cocoaArrayCount(cocoaGetAssocKey(self, "files")) }
func dsValue(self, cmd, tv, col, row) { emit cocoaArrayGet(cocoaGetAssocKey(self, "files"), row) }
func dsSelect(self, cmd, notif) {
  let tbl = msg(notif, "object")
  let row = msg(tbl, "selectedRow")
  if row < 0 { emit "1" }
  let fname = msg(cocoaArrayGet(cocoaGetAssocKey(self, "files"), row), "UTF8String")
  let dir = msg(cocoaGetAssocKey(self, "dir"), "UTF8String")
  let path = dir + "/" + fname
  cocoaTVSetString(cocoaGetAssocKey(self, "editor"), readFile(path))
  cocoaSetAssocKey(msg(cls("NSApplication"), "sharedApplication"), "kryide.curpath", nsString(path))
}

just run {
  let dir = arg(0)
  let listing = exec("ls -1 " + dir)
  let app = cocoaInit()
  let bar = cocoaMenuBar(app)
  let win = cocoaWindow(app, "kryide — pure-Krypton IDE (live highlight) on objk", 880, 560)
  let table = cocoaTable(win, 0, 0, 240, 560)
  let editor = cocoaScrollText(win, 240, 0, 640, 560)
  cocoaSetFont(editor, cocoaMonoFont(13))

  let files = cocoaArray()
  let nf = nlines(listing)
  let i = 0
  while i < nf { cocoaArrayAdd(files, nsString(lineAt(listing, i)))  i = i + 1 }

  let dsc = cocoaClassNew("KryIDEDelegate")
  cocoaClassAddMethod(dsc, "numberOfRowsInTableView:", funcptr(dsRows), "q@:@")
  cocoaClassAddMethod(dsc, "tableView:objectValueForTableColumn:row:", funcptr(dsValue), "@@:@@q")
  cocoaClassAddMethod(dsc, "tableViewSelectionDidChange:", funcptr(dsSelect), "v@:@")
  cocoaClassAddMethod(dsc, "textStorageDidProcessEditing:", funcptr(reHL), "v@:@")
  cocoaClassRegister(dsc)
  let ds = cocoaNew(dsc)
  cocoaSetAssocKey(ds, "files", files)
  cocoaSetAssocKey(ds, "editor", editor)
  cocoaSetAssocKey(ds, "dir", nsString(dir))
  cocoaSetDataSource(table, ds)
  msg_1(table, "setDelegate:", ds)
  cocoaTVSetStorageDelegate(editor, ds)
  cocoaTVSetString(editor, "// kryide — click a file on the left; live syntax highlighting\nfunc demo() {\n    let x = 1\n    return x\n}\n")
  cocoaSetAssocKey(app, "kryide.editor", editor)
  let fileMenu = cocoaMenuAdd(bar, "File")
  cocoaMenuItem(fileMenu, "Save", "s", funcptr(onSave))
  cocoaReload(table)
  cocoaShow(win, app)
  cocoaRun(app)
}
