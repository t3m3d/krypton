import "k:cocoa"
import "k:objc"
import "head:cocoa"
import "head:objc"

func dsRows(self, cmd, tv) { emit 6 }
func dsValue(self, cmd, tv, col, row) { emit nsString("  src/file_" + row + ".k") }
func dsSelect(self, cmd, notif) {
  let tv = msg(notif, "object")
  let row = msg(tv, "selectedRow")
  let editor = cocoaGetAssoc(self)
  cocoaTVSetString(editor, "// src/file_" + row + ".k  (loaded by a pure-Krypton delegate)\nfunc f" + row + "() {\n    kp(\"this is file " + row + "\")\n}\n")
}

just run {
  let app = cocoaInit()
  let bar = cocoaMenuBar(app)
  let appMenu = cocoaMenuAdd(bar, "kcode")
  let win = cocoaWindow(app, "kcode shell — pure Krypton on objk", 760, 460)
  let table = cocoaTable(win, 0, 0, 240, 460)
  let editor = cocoaScrollText(win, 240, 0, 520, 460)
  cocoaSetFont(editor, cocoaMonoFont(13))
  cocoaTVSetString(editor, "// click a file on the left.\n")
  let dsc = cocoaClassNew("KShellDelegate")
  cocoaClassAddMethod(dsc, "numberOfRowsInTableView:", funcptr(dsRows), "q@:@")
  cocoaClassAddMethod(dsc, "tableView:objectValueForTableColumn:row:", funcptr(dsValue), "@@:@@q")
  cocoaClassAddMethod(dsc, "tableViewSelectionDidChange:", funcptr(dsSelect), "v@:@")
  cocoaClassRegister(dsc)
  let ds = cocoaNew(dsc)
  cocoaSetAssoc(ds, editor)
  cocoaSetDataSource(table, ds)
  msg_1(table, "setDelegate:", ds)
  cocoaReload(table)
  cocoaShow(win, app)
  cocoaRun(app)
}
