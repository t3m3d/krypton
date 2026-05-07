// 09_tabs.k — tab control as a top strip.
//
// guiTabs returns a handle. guiTabAdd appends a tab and returns its
// index. guiOnChange fires when the user clicks a different tab —
// guiTabSelected returns the active index.

import "stdlib/gui.k"


let g_tabs  = ""
let g_label = ""


func onTabChange() {
    let idx = guiTabSelected(g_tabs)
    guiSetText(g_label, "Active tab index: " + idx)
}


just run {
    guiInit()
    let win = guiWindow("Tabs Demo", 480, 220)

    g_tabs = guiTabs(win, 12, 12, 456, 28)
    guiTabAdd(g_tabs, "General")
    guiTabAdd(g_tabs, "Network")
    guiTabAdd(g_tabs, "Advanced")
    guiOnChange(g_tabs, funcptr(onTabChange))

    g_label = guiLabel(win, "Click a tab.", 12, 60, 456, 22)

    guiShow(win)
    guiRun()
}
