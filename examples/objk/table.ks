import "k:cocoa"
import "k:objc"
import "head:cocoa"
import "head:objc"

func dsRows(self, cmd, tableView) { emit 4 }
func dsValue(self, cmd, tv, col, row) { emit nsString("  file_" + row + ".k") }

just run {
  let app = cocoaInit()
  let win = cocoaWindow(app, "Krypton table — pure objk data source", 420, 300)
  let table = cocoaTable(win, 0, 0, 420, 300)
  let dsc = cocoaClassNew("KryptonObjkDataSource")
  cocoaClassAddMethod(dsc, "numberOfRowsInTableView:", funcptr(dsRows), "q@:@")
  cocoaClassAddMethod(dsc, "tableView:objectValueForTableColumn:row:", funcptr(dsValue), "@@:@@q")
  cocoaClassRegister(dsc)
  let ds = cocoaNew(dsc)
  cocoaSetDataSource(table, ds)
  cocoaReload(table)
  cocoaShow(win, app)
  cocoaRun(app)
}
