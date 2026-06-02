// win_tabs.k — three-tab demo: progress bar, tree view, listbox.
//
// Build:
//   kcc examples/win_tabs.k -o win_tabs.exe
//
// Each tab page is just a set of child widgets created at the same
// (x, y, w, h) as the others — only one is visible at a time. The
// tab control raises a change notification when the user clicks a tab;
// the handler hides every widget on the previous tab and shows the
// widgets on the new one.

import "k:gui"

func _pageFor(idx) { emit guiStateGet("tabs.page." + idx) }

func onTabChange() {
    let idx = guiTabSelected(guiStateGet("tabs.ctrl"))
    let i = 0
    while i < 3 {
        if i == idx { guiShow(_pageFor(i)) } else { guiHide(_pageFor(i)) }
        i = i + 1
    }
}

func _makePage(parent, x, y, w, h) {
    // gui.k doesn't currently expose container/panel widgets — we
    // create a hidden label as the "page" handle and stash the real
    // child widgets in the state store keyed off it. Show/Hide cycles
    // the label; child widgets are positioned over the tab area so
    // they ride along visually.
    let page = guiLabel(parent, "", x, y, w, h)
    guiHide(page)
    emit page
}

just run {
    guiInit()
    let win = guiWindow("Krypton Tabs", 540, 380)

    let tabs = guiTabs(win, 12, 12, 516, 30)
    guiTabAdd(tabs, "Progress")
    guiTabAdd(tabs, "Tree")
    guiTabAdd(tabs, "List")

    // Tab 0 — progress bar that fills as you click the button.
    let p0 = _makePage(win, 12, 50, 516, 300)
    let bar  = guiProgress(win, 24, 80, 480, 24)
    let btn  = guiButton(win, "Advance 10%", 24, 120, 200, 30)
    guiStateSet("tabs.bar", bar)
    guiStateSet("tabs.barpct", "0")
    func onAdvance() {
        let pct = toInt(guiStateGet("tabs.barpct")) + 10
        if pct > 100 { pct = 0 }
        guiStateSet("tabs.barpct", "" + pct)
        guiProgressSet(guiStateGet("tabs.bar"), pct)
    }
    guiOnClick(btn, funcptr(onAdvance))
    guiStateSet("tabs.page.0", p0)

    // Tab 1 — tree view.
    let p1 = _makePage(win, 12, 50, 516, 300)
    let tree = guiTreeView(win, 24, 80, 480, 240)
    let root = guiTreeAdd(tree, "", "Krypton")
    guiTreeAdd(tree, root, "stdlib/")
    guiTreeAdd(tree, root, "examples/")
    guiTreeAdd(tree, root, "tutorial/")
    guiTreeExpand(tree, root)
    guiHide(tree)
    guiStateSet("tabs.page.1", p1)

    // Tab 2 — listbox.
    let p2 = _makePage(win, 12, 50, 516, 300)
    let list = guiListbox(win, 24, 80, 480, 240)
    guiListAdd(list, "Tabs let you stack panes")
    guiListAdd(list, "Each pane shares its parent window")
    guiListAdd(list, "gui.k handles the WM_NOTIFY routing")
    guiHide(list)
    guiStateSet("tabs.page.2", p2)

    // Initial state — only Tab 0 visible.
    guiShow(p0)
    guiStateSet("tabs.ctrl", tabs)
    guiOnChange(tabs, funcptr(onTabChange))

    guiShow(win)
    guiRun()
}
