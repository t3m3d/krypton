// brain — a pure-Krypton IDE on objk (no Obj-C source).
// File tree + multi-file tabs + live syntax highlighting + Open/Save/Run +
// standard Edit menu. Pairs with the brain terminal.
import "k:cocoa"
import "k:objc"
import "head:cocoa"
import "head:objc"

func appH() { emit msg(cls("NSApplication"), "sharedApplication") }
func baseName(p) { let n = len(p)  let i = n - 1  while i >= 0 { if p[i] == "/" { emit substring(p, i + 1, n) }  i = i - 1 }  emit p }

func nlines(s) { let n = len(s)  let c = 0  let i = 0  while i < n { if s[i] == "\n" { c = c + 1 }  i = i + 1 }  emit c }
func lineAt(s, idx) {
  let n = len(s)  let cur = 0  let start = 0  let i = 0
  while i < n { if s[i] == "\n" { if cur == idx { emit substring(s, start, i) }  cur = cur + 1  start = i + 1 }  i = i + 1 }
  emit ""
}

// ── syntax highlighting (operates on the storage the delegate receives) ──
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
func hlStrings(ts, src, color) {
  let n = len(src)  let pos = 0
  while pos < n {
    let i = indexOf(substring(src, pos, n), "\"")
    if i < 0 { emit "1" }
    let start = pos + i
    let j = indexOf(substring(src, start + 1, n), "\"")
    if j < 0 { emit "1" }
    let end = start + 1 + j + 1
    cocoaTSColorRange(ts, color, start, end - start)
    pos = end
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
  hlStrings(ts, src, cocoaColorNamed("greenColor"))
  hlComments(ts, src, cocoaColorNamed("grayColor"))
  emit "1"
}
func reHL(self, cmd, notif) {
  let ts = msg(notif, "object")
  if cocoaTSEditedChars(ts) == 0 { emit "1" }
  cocoaTSClearColor(ts)
  highlightTS(ts, cocoaTSString(ts))
}

// ── tabs ────────────────────────────────────────────────────────────────
func curTabIdx() {
  let n = cocoaGetAssocKey(appH(), "brain.curtab")
  if n == 0 { emit 0 - 1 }
  emit cocoaNumberVal(n)
}
func saveCurTab() {
  let idx = curTabIdx()
  if idx < 0 { emit "1" }
  cocoaArraySet(cocoaGetAssocKey(appH(), "brain.tabtexts"), idx,
    nsString(cocoaTVGetString(cocoaGetAssocKey(appH(), "brain.editor"))))
  emit "1"
}
func rebuildTabs() {
  let seg = cocoaGetAssocKey(appH(), "brain.tabseg")
  let paths = cocoaGetAssocKey(appH(), "brain.tabpaths")
  let n = cocoaArrayCount(paths)
  cocoaSegCount(seg, n)
  let i = 0
  while i < n { cocoaSegLabel(seg, baseName(msg(cocoaArrayGet(paths, i), "UTF8String")), i)  i = i + 1 }
  emit "1"
}
func selectTab(idx) {
  let app = appH()
  cocoaSegSelect(cocoaGetAssocKey(app, "brain.tabseg"), idx)
  let paths = cocoaGetAssocKey(app, "brain.tabpaths")
  let texts = cocoaGetAssocKey(app, "brain.tabtexts")
  cocoaTVSetString(cocoaGetAssocKey(app, "brain.editor"), msg(cocoaArrayGet(texts, idx), "UTF8String"))
  cocoaSetAssocKey(app, "brain.curtab", cocoaNumber(idx))
  cocoaSetAssocKey(app, "brain.curpath", cocoaArrayGet(paths, idx))
  msg_1(cocoaGetAssocKey(app, "brain.win"), "setTitle:", nsString("brain — " + msg(cocoaArrayGet(paths, idx), "UTF8String")))
  emit "1"
}
func openTab(path) {
  let app = appH()
  saveCurTab()
  let paths = cocoaGetAssocKey(app, "brain.tabpaths")
  let texts = cocoaGetAssocKey(app, "brain.tabtexts")
  let count = cocoaArrayCount(paths)
  let found = 0 - 1
  let i = 0
  while i < count { if msg(cocoaArrayGet(paths, i), "UTF8String") == path { found = i }  i = i + 1 }
  if found < 0 {
    cocoaArrayAdd(paths, nsString(path))
    cocoaArrayAdd(texts, nsString(readFile(path)))
    found = count
  }
  rebuildTabs()
  selectTab(found)
  emit "1"
}
func onTabChange(self, cmd, sender) {
  saveCurTab()
  selectTab(cocoaSegSelected(sender))
}

func onNew(self, cmd, sender) {
  let app = appH()
  saveCurTab()
  let paths = cocoaGetAssocKey(app, "brain.tabpaths")
  let texts = cocoaGetAssocKey(app, "brain.tabtexts")
  cocoaArrayAdd(paths, nsString(arg(0) + "/untitled-" + cocoaArrayCount(paths) + ".k"))
  cocoaArrayAdd(texts, nsString("// new file\n"))
  rebuildTabs()
  selectTab(cocoaArrayCount(paths) - 1)
}
func onClose(self, cmd, sender) {
  let app = appH()
  let idx = curTabIdx()
  if idx < 0 { emit "1" }
  let paths = cocoaGetAssocKey(app, "brain.tabpaths")
  let texts = cocoaGetAssocKey(app, "brain.tabtexts")
  cocoaArrayRemove(paths, idx)
  cocoaArrayRemove(texts, idx)
  cocoaSetAssocKey(app, "brain.curtab", cocoaNumber(0 - 1))
  rebuildTabs()
  let n = cocoaArrayCount(paths)
  if n == 0 { cocoaTVSetString(cocoaGetAssocKey(app, "brain.editor"), "// no file open\n")  emit "1" }
  let pick = idx
  if pick >= n { pick = n - 1 }
  selectTab(pick)
}

// ── menu actions ──────────────────────────────────────────────────────
func onRun(self, cmd, sender) {
  let app = appH()
  let cp = cocoaGetAssocKey(app, "brain.curpath")
  if cp == 0 { cocoaAlert("Run", "Open a .k file first.")  emit "1" }
  let path = msg(cp, "UTF8String")
  saveCurTab()
  writeFile(path, cocoaTVGetString(cocoaGetAssocKey(app, "brain.editor")))
  cocoaAlert("Run output", exec("cd " + arg(0) + " && kcc --native " + path + " -o /tmp/brainrun 2>&1 && /tmp/brainrun 2>&1"))
}
func onOpen(self, cmd, sender) {
  let panel = msg(cls("NSOpenPanel"), "openPanel")
  if msg(panel, "runModal") == 1 {
    let url = msg_1(msg(panel, "URLs"), "objectAtIndex:", 0)
    openTab(msg(msg(url, "path"), "UTF8String"))
  }
}
func onSave(self, cmd, sender) {
  let app = appH()
  let cp = cocoaGetAssocKey(app, "brain.curpath")
  if cp == 0 { kp("brain: no file open")  emit "1" }
  let path = msg(cp, "UTF8String")
  saveCurTab()
  writeFile(path, cocoaTVGetString(cocoaGetAssocKey(app, "brain.editor")))
  kp("brain: saved " + path)
}

// ── integrated console (run shell commands, see output) ────────────────
func onCmd(self, cmd, sender) {
  let app = appH()
  let line = msg(msg(sender, "stringValue"), "UTF8String")
  let console = cocoaGetAssocKey(app, "brain.console")
  let out = exec("cd " + arg(0) + " && " + line + " 2>&1")
  cocoaTVSetString(console, cocoaTVGetString(console) + "$ " + line + "\n" + out)
  msg_1(sender, "setStringValue:", nsString(""))
  msg_1(console, "scrollToEndOfDocument:", 0)
}

// ── file tree ──────────────────────────────────────────────────────────
func dsRows(self, cmd, tv) { emit cocoaArrayCount(cocoaGetAssocKey(self, "files")) }
func dsValue(self, cmd, tv, col, row) { emit cocoaArrayGet(cocoaGetAssocKey(self, "files"), row) }
func dsSelect(self, cmd, notif) {
  let row = msg(msg(notif, "object"), "selectedRow")
  if row < 0 { emit "1" }
  let fname = msg(cocoaArrayGet(cocoaGetAssocKey(self, "files"), row), "UTF8String")
  openTab(msg(cocoaGetAssocKey(self, "dir"), "UTF8String") + "/" + fname)
}

just run {
  let dir = arg(0)
  let listing = exec("ls -1 " + dir)
  let app = cocoaInit()
  let bar = cocoaMenuBar(app)
  let win = cocoaWindow(app, "brain — pure-Krypton IDE on objk", 900, 600)
  let table = cocoaTable(win, 0, 170, 240, 430)
  let tabseg = cocoaSegmented(win, 240, 574, 660, 24)
  let editor = cocoaScrollText(win, 240, 170, 660, 400)
  let console = cocoaScrollText(win, 0, 32, 900, 132)
  msg_1(console, "setEditable:", 0)
  let cmdfield = cocoaTextField(win, 0, 4, 900, 24)
  cocoaSetFont(editor, cocoaMonoFont(13))
  msg_1(editor, "setAllowsUndo:", 1)
  msg_1(editor, "setUsesFindBar:", 1)

  let files = cocoaArray()
  let nf = nlines(listing)
  let i = 0
  while i < nf { cocoaArrayAdd(files, nsString(lineAt(listing, i)))  i = i + 1 }

  let dsc = cocoaClassNew("BrainDelegate")
  cocoaClassAddMethod(dsc, "numberOfRowsInTableView:", funcptr(dsRows), "q@:@")
  cocoaClassAddMethod(dsc, "tableView:objectValueForTableColumn:row:", funcptr(dsValue), "@@:@@q")
  cocoaClassAddMethod(dsc, "tableViewSelectionDidChange:", funcptr(dsSelect), "v@:@")
  cocoaClassAddMethod(dsc, "textStorageDidProcessEditing:", funcptr(reHL), "v@:@")
  cocoaClassRegister(dsc)
  let ds = cocoaNew(dsc)
  cocoaSetAssocKey(ds, "files", files)
  cocoaSetAssocKey(ds, "dir", nsString(dir))
  cocoaSetDataSource(table, ds)
  msg_1(table, "setDelegate:", ds)
  cocoaTVSetStorageDelegate(editor, ds)

  cocoaSetAssocKey(app, "brain.editor", editor)
  cocoaSetAssocKey(app, "brain.win", win)
  cocoaSetAssocKey(app, "brain.tabseg", tabseg)
  cocoaSetAssocKey(app, "brain.tabpaths", cocoaArray())
  cocoaSetAssocKey(app, "brain.tabtexts", cocoaArray())
  cocoaSegOnChange(tabseg, funcptr(onTabChange))
  cocoaSetAssocKey(app, "brain.console", console)
  cocoaTVSetString(console, "stem — integrated terminal. type a command, press Enter.\n")
  cocoaSetFont(console, cocoaMonoFont(12))
  cocoaOnClick(cmdfield, funcptr(onCmd))

  let fileMenu = cocoaMenuAdd(bar, "File")
  cocoaMenuItem(fileMenu, "New", "n", funcptr(onNew))
  cocoaMenuItem(fileMenu, "Open", "o", funcptr(onOpen))
  cocoaMenuItem(fileMenu, "Close Tab", "w", funcptr(onClose))
  cocoaMenuItem(fileMenu, "Save", "s", funcptr(onSave))
  cocoaMenuItem(fileMenu, "Run", "r", funcptr(onRun))
  let editMenu = cocoaMenuAdd(bar, "Edit")
  cocoaMenuItemSel(editMenu, "Undo", "z", "undo:")
  cocoaMenuItemSel(editMenu, "Cut", "x", "cut:")
  cocoaMenuItemSel(editMenu, "Copy", "c", "copy:")
  cocoaMenuItemSel(editMenu, "Paste", "v", "paste:")
  cocoaMenuItemSel(editMenu, "Select All", "a", "selectAll:")
  cocoaMenuItemSel(editMenu, "Find", "f", "performTextFinderAction:")

  cocoaTVSetString(editor, "// brain — pure-Krypton IDE. click a file on the left.\n")
  cocoaReload(table)
  cocoaShow(win, app)
  cocoaRun(app)
}
