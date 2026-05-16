// 14_slider_spin.k — slider + spinbox numeric input.
//
// Slider drag fires onChange — your callback reads guiSliderValue.
// Spinbox is an EDIT + UpDown buddy; arrow buttons increment by 1,
// or you can type a number directly.
//
// Note: cross-handler state goes through `guiStateSet`/`guiStateGet`
// rather than module-level `let` (which is broken in the native
// pipeline — see Krypton's own --port-1to2 warning).

import "k:gui"


func updateLabel() {
    let slider = guiStateGet("demo.slider")
    let spin   = guiStateGet("demo.spin")
    let label  = guiStateGet("demo.label")
    let s = guiSliderValue(slider)
    let n = guiSpinboxValue(spin)
    guiSetText(label, "Slider: " + s + "    Spin: " + n)
}

func onSlide() { updateLabel() }


just run {
    guiInit()
    let win = guiWindow("Slider + Spinbox", 480, 240)

    guiLabel(win, "Volume:", 24, 24, 432, 22)
    let slider = guiSlider(win, 24, 50, 432, 32)
    guiSliderRange(slider, 0, 100)
    guiSliderSet(slider, 25)
    guiOnChange(slider, funcptr(onSlide))
    guiStateSet("demo.slider", slider)

    guiLabel(win, "Count:", 24, 100, 200, 22)
    let spin = guiSpinbox(win, 24, 124, 100, 28)
    guiSpinboxRange(spin, -50, 50)
    guiSpinboxSet(spin, 0)
    guiStateSet("demo.spin", spin)

    let label = guiLabel(win, "Slider: 25    Spin: 0", 24, 170, 432, 22)
    guiStateSet("demo.label", label)

    guiShow(win)
    guiRun()
}
