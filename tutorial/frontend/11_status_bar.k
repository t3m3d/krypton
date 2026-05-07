// 11_status_bar.k — the very expandable status bar.
//
// guiStatusBar attaches a bar to the bottom of a window.  Width specs
// recompute on every resize, so proportional cells (`*` or `%`) scale
// the way you'd expect:
//
//   guiStatusParts(bar, "*,*,*")        3 equal cells, all stretch
//   guiStatusParts(bar, "200,*,160")    fixed, stretch middle, fixed
//   guiStatusParts(bar, "30%,40%,30%")  proportional
//   guiStatusParts(bar, "200,200,-1")   absolute pixels, last to edge
//
// guiStatusSet / guiStatusGet read+write per cell.
// guiStatusIcon adds a system icon (info / warning / error / ok / question).
// guiStatusBgColor tints the whole bar (turns off the modern theme).

import "stdlib/gui.k"


let g_bar   = ""
let g_count = 0


func onInfo()  { guiStatusIcon(g_bar, 0, "info")    guiStatusSet(g_bar, 0, " Ready") }
func onWarn()  { guiStatusIcon(g_bar, 0, "warning") guiStatusSet(g_bar, 0, " Disk almost full") }
func onErr()   { guiStatusIcon(g_bar, 0, "error")   guiStatusSet(g_bar, 0, " Build failed") }
func onOk()    { guiStatusIcon(g_bar, 0, "ok")      guiStatusSet(g_bar, 0, " All tests passed") }

func onTick()  {
    g_count = g_count + 1
    guiStatusSet(g_bar, 1, " Ln " + g_count + ", Col 1")
}

func onTintBlue()  { guiStatusBgColor(g_bar, "0x264F78") }
func onTintReset() { guiStatusBgColor(g_bar, "0xF0F0F0") }


just run {
    guiInit()
    let win = guiWindow("Status Bar Tutorial", 600, 320)

    let b1 = guiButton(win, "Ready",     24, 24, 130, 32)
    let b2 = guiButton(win, "Warning",  166, 24, 130, 32)
    let b3 = guiButton(win, "Error",    308, 24, 130, 32)
    let b4 = guiButton(win, "OK",       450, 24, 130, 32)
    guiOnClick(b1, funcptr(onInfo))
    guiOnClick(b2, funcptr(onWarn))
    guiOnClick(b3, funcptr(onErr))
    guiOnClick(b4, funcptr(onOk))

    let b5 = guiButton(win, "Tick line", 24, 70, 270, 32)
    let b6 = guiButton(win, "Tint blue",      308, 70, 130, 32)
    let b7 = guiButton(win, "Tint reset",     450, 70, 130, 32)
    guiOnClick(b5, funcptr(onTick))
    guiOnClick(b6, funcptr(onTintBlue))
    guiOnClick(b7, funcptr(onTintReset))

    g_bar = guiStatusBar(win)
    guiStatusParts(g_bar, "*,*,*")        // resize the window — all 3 cells scale together
    guiStatusSet(g_bar, 0, " Ready")
    guiStatusIcon(g_bar, 0, "info")
    guiStatusSet(g_bar, 1, " Ln 1, Col 1")
    guiStatusSet(g_bar, 2, " UTF-8")

    guiShow(win)
    guiRun()
}
