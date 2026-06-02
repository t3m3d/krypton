// win_counter.k — counter window with + / − buttons and a live label.
//
// Build:
//   kcc examples/win_counter.k -o win_counter.exe
//
// Pattern: stash the count + the label handle in the gui.k state
// store (module-level mutable globals are a known footgun on the
// native pipeline — guiStateSet/Get is GC-safe and survives across
// `funcptr` click handlers).

import "k:gui"

func _count()        { emit toInt(guiStateGet("counter.value")) }
func _setCount(n)    { guiStateSet("counter.value", "" + n) }
func _label()        { emit guiStateGet("counter.label") }
func _refresh()      { guiSetText(_label(), "Count: " + _count()) }

func onInc() { _setCount(_count() + 1)  _refresh() }
func onDec() { _setCount(_count() - 1)  _refresh() }

just run {
    guiInit()
    let win = guiWindow("Krypton Counter", 340, 180)

    let lbl = guiLabel(win, "Count: 0", 40, 30, 240, 32)
    guiStateSet("counter.label", lbl)
    _setCount(0)

    let dec = guiButton(win, "-", 40, 80, 100, 36)
    let inc = guiButton(win, "+", 180, 80, 100, 36)
    guiOnClick(dec, funcptr(onDec))
    guiOnClick(inc, funcptr(onInc))

    guiShow(win)
    guiRun()
}
