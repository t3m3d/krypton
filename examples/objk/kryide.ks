import "k:cocoa"
import "k:objc"
import "head:cocoa"
import "head:objc"

func nlines(s) { let n = len(s)  let c = 0  let i = 0  while i < n { if s[i] == "\n" { c = c + 1 }  i = i + 1 }  emit c }
func lineAt(s, idx) {
  let n = len(s)  let cur = 0  let start = 0  let i = 0
  while i < n {
    if s[i] == "\n" { if cur == idx { emit substring(s, start, i) }  cur = cur + 1  start = i + 1 }
    i = i + 1
  }
  emit ""
}

func hlWord(tv, src, word, color) {
  let n = len(src)  let wl = len(word)  let pos = 0
  while pos < n {
    let i = indexOf(substring(src, pos, n), word)
    if i < 0 { emit "1" }
    cocoaTVColorRange(tv, color, pos + i, wl)
    pos = pos + i + wl
  }
  emit "1"
}
func hlComments(tv, src, color) {
  let n = len(src)  let pos = 0
  while pos < n {
    let i = indexOf(substring(src, pos, n), "//")
    if i < 0 { emit "1" }
    let start = pos + i
    let nl = indexOf(substring(src, start, n), "\n")
    let end = n
    if nl >= 0 { end = start + nl }
    cocoaTVColorRange(tv, color, start, end - start)
    pos = end + 1
  }
  emit "1"
}
func highlight(tv, src) {
  let kw = cocoaColorNamed("purpleColor")
  hlWord(tv, src, "func", kw)  hlWord(tv, src, "let", kw)  hlWord(tv, src, "if", kw)
  hlWord(tv, src, "while", kw) hlWord(tv, src, "return", kw) hlWord(tv, src, "emit", kw)
  hlWord(tv, src, "import", kw) hlWord(tv, src, "module", kw) hlWord(tv, src, "const", kw)
  hlComments(tv, src, cocoaColorNamed("grayColor"))
  emit "1"
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
  let editor = cocoaGetAssocKey(self, "editor")
  let src = readFile(path)
  cocoaTVSetString(editor, src)
  highlight(editor, src)
}

just run {
  let dir = arg(0)
  let listing = exec("ls -1 " + dir)
  let app = cocoaInit()
  cocoaMenuBar(app)
  let win = cocoaWindow(app, "kryide — pure-Krypton IDE on objk", 880, 560)
  let table = cocoaTable(win, 0, 0, 240, 560)
  let editor = cocoaScrollText(win, 240, 0, 640, 560)
  cocoaSetFont(editor, cocoaMonoFont(13))
  cocoaTVSetString(editor, "// kryide — click a file on the left\n")

  // build the file list ONCE into an NSArray (no exec inside callbacks)
  let files = cocoaArray()
  let nf = nlines(listing)
  let i = 0
  while i < nf { cocoaArrayAdd(files, nsString(lineAt(listing, i)))  i = i + 1 }

  let dsc = cocoaClassNew("KryIDEDelegate")
  cocoaClassAddMethod(dsc, "numberOfRowsInTableView:", funcptr(dsRows), "q@:@")
  cocoaClassAddMethod(dsc, "tableView:objectValueForTableColumn:row:", funcptr(dsValue), "@@:@@q")
  cocoaClassAddMethod(dsc, "tableViewSelectionDidChange:", funcptr(dsSelect), "v@:@")
  cocoaClassRegister(dsc)
  let ds = cocoaNew(dsc)
  cocoaSetAssocKey(ds, "files", files)
  cocoaSetAssocKey(ds, "editor", editor)
  cocoaSetAssocKey(ds, "dir", nsString(dir))
  cocoaSetDataSource(table, ds)
  msg_1(table, "setDelegate:", ds)
  cocoaReload(table)
  cocoaShow(win, app)
  cocoaRun(app)
}
