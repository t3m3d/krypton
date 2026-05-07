// gui_slider_spin.k — Slider + Spinbox demo.
//
// Build:
//   kcc.exe examples/gui_slider_spin.k > tmp.c
//   gcc tmp.c -o gui_slider_spin.exe -luser32 -lgdi32 -lcomctl32 -lcomdlg32 \
//       -lole32 -lshell32 -ldwmapi -luxtheme -ladvapi32 -lm -w
//
// Slider drag fires a callback that updates a label live. Spinbox
// arrow buttons increment/decrement; Read button shows the current
// value.

import "stdlib/gui.k"


let g_slider = ""
let g_spin   = ""
let g_label  = ""


func onSliderChange() {
    let v = guiSliderValue(g_slider)
    guiSetText(g_label, "Slider: " + v + "    Spin: " + guiSpinboxValue(g_spin))
}

func onReadSpin() {
    let v = guiSpinboxValue(g_spin)
    guiMessageBox("Spinbox", "Current value: " + v)
}


just run {
    guiInit()
    let win = guiWindow("Slider + Spinbox", 520, 280)

    guiLabel(win, "Drag the slider:", 24, 24, 472, 22)
    g_slider = guiSlider(win, 24, 50, 472, 32)
    guiSliderRange(g_slider, 0, 200)
    guiSliderSet(g_slider, 50)
    guiOnChange(g_slider, funcptr(onSliderChange))

    guiLabel(win, "Spinbox:", 24, 100, 200, 22)
    g_spin = guiSpinbox(win, 24, 124, 100, 28)
    guiSpinboxRange(g_spin, -100, 100)
    guiSpinboxSet(g_spin, 7)

    let bRead = guiButton(win, "Read spin", 140, 124, 140, 30)
    guiOnClick(bRead, funcptr(onReadSpin))

    g_label = guiLabel(win, "Slider: 50    Spin: 7", 24, 180, 472, 22)

    guiShow(win)
    guiRun()
}
