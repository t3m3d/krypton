// gui_statusbar.k - status bar showcase.
//
// Build:
//   kcc.exe examples/gui_statusbar.k > tmp.c
//   gcc tmp.c -o gui_statusbar.exe -luser32 -lgdi32 -lcomctl32 -ldwmapi \
//       -luxtheme -ladvapi32 -lm -w
//
// Three-part status bar:
//   [info icon | message]  [Ln/Col]   [encoding]
// Buttons mutate each part to demonstrate guiStatusSet / guiStatusIcon.

import "stdlib/gui.k"


let g_bar = ""
let g_input = ""
let g_count = 0


func onInfo()    { guiStatusIcon(g_bar, 0, "info")     guiStatusSet(g_bar, 0, " Ready") }
func onWarn()    { guiStatusIcon(g_bar, 0, "warning")  guiStatusSet(g_bar, 0, " Disk almost full") }
func onErr()     { guiStatusIcon(g_bar, 0, "error")    guiStatusSet(g_bar, 0, " Build failed") }
func onOk()      { guiStatusIcon(g_bar, 0, "ok")       guiStatusSet(g_bar, 0, " All tests passed") }
func onClear()   { guiStatusIcon(g_bar, 0, "")         guiStatusSet(g_bar, 0, "") }

func onTick() {
    g_count = g_count + 1
    guiStatusSet(g_bar, 1, " Ln " + g_count + ", Col 1")
}

func onTintBlue()  { guiStatusBgColor(g_bar, "0x264F78") }
func onTintGreen() { guiStatusBgColor(g_bar, "0x2E7D32") }
func onTintReset() { guiStatusBgColor(g_bar, "0xF0F0F0") }


just run {
    guiInit()
    let win = guiWindow("Krypton Status Bar Demo", 640, 360)

    guiLabel(win, "Click a button. Status bar at the bottom updates.",
             24, 24, 600, 20)

    guiButton(win, "Ready info",    24,  60, 140, 32)
    guiButton(win, "Warning",      168,  60, 140, 32)
    guiButton(win, "Error",        312,  60, 140, 32)
    guiButton(win, "OK",           456,  60, 140, 32)

    guiButton(win, "Tick line",     24, 100, 140, 32)
    guiButton(win, "Clear",        168, 100, 140, 32)

    guiButton(win, "Tint blue",     24, 140, 140, 32)
    guiButton(win, "Tint green",   168, 140, 140, 32)
    guiButton(win, "Tint reset",   312, 140, 140, 32)

    // Buttons by ID order: 1000..1008 — register handlers in the same
    // order so each button does the right thing.
    guiOnClick("1000", funcptr(onInfo))
    guiOnClick("1001", funcptr(onWarn))
    guiOnClick("1002", funcptr(onErr))
    guiOnClick("1003", funcptr(onOk))
    guiOnClick("1004", funcptr(onTick))
    guiOnClick("1005", funcptr(onClear))
    guiOnClick("1006", funcptr(onTintBlue))
    guiOnClick("1007", funcptr(onTintGreen))
    guiOnClick("1008", funcptr(onTintReset))

    g_bar = guiStatusBar(win)
    // Spec syntax (per cell, comma-separated):
    //   N    fixed pixel width
    //   N%   percent of bar width
    //   *    stretch — leftover divided equally among * cells
    //   -1   legacy alias for *
    // Stretchers + percentages re-evaluate on every WM_SIZE so the
    // status bar actually scales when you resize the window.
    guiStatusParts(g_bar, "*,*,*")
    guiStatusSet(g_bar, 0, " Ready")
    guiStatusIcon(g_bar, 0, "info")
    guiStatusSet(g_bar, 1, " Ln 1, Col 1")
    guiStatusSet(g_bar, 2, " UTF-8")

    guiShow(win)
    guiRun()
}
