// 14_slider_spin.k — slider + spinbox numeric input.
//
// Slider drag fires onChange — your callback reads guiSliderValue.
// Spinbox is an EDIT + UpDown buddy; arrow buttons increment by 1,
// or you can type a number directly.

import "stdlib/gui.k"


let g_slider = ""
let g_spin   = ""
let g_label  = ""


func updateLabel() {
    let s = guiSliderValue(g_slider)
    let n = guiSpinboxValue(g_spin)
    guiSetText(g_label, "Slider: " + s + "    Spin: " + n)
}

func onSlide() { updateLabel() }


just run {
    guiInit()
    let win = guiWindow("Slider + Spinbox", 480, 240)

    guiLabel(win, "Volume:", 24, 24, 432, 22)
    g_slider = guiSlider(win, 24, 50, 432, 32)
    guiSliderRange(g_slider, 0, 100)
    guiSliderSet(g_slider, 25)
    guiOnChange(g_slider, funcptr(onSlide))

    guiLabel(win, "Count:", 24, 100, 200, 22)
    g_spin = guiSpinbox(win, 24, 124, 100, 28)
    guiSpinboxRange(g_spin, -50, 50)
    guiSpinboxSet(g_spin, 0)

    g_label = guiLabel(win, "Slider: 25    Spin: 0", 24, 170, 432, 22)

    guiShow(win)
    guiRun()
}
