// stdlib/okui.k -- human Objective-K UI layer.
//
// Choc is backend. Obj-K is facade. okui is programmer-facing wording:
// plain nouns create things; do* verbs perform actions.

module okui

import "k:objk"

// App/window
func app(name)                  { emit okApp() }
func sharedApp()                { emit okSharedApp() }
func window(title, w, h)        { emit okWindow(okSharedApp(), title, w, h) }
func minSize(win, w, h)         { emit okMinSize(win, w, h) }
func doShow(win)                { emit okShow(win, okSharedApp()) }
func doRun()                    { emit okRun(okSharedApp()) }
func doQuit()                   { emit okQuit(okSharedApp()) }

// Layout words
func area(x, y, w, h)           { emit okRect(x, y, w, h) }
func page(w, h, pad)            { emit okInset(okRect(0, 0, w, h), pad) }
func inside(r, pad)             { emit okInset(r, pad) }
func move(r, x, y)              { emit okMove(r, x, y) }
func resize(r, w, h)            { emit okResize(r, w, h) }
func top(r, h)                  { emit okTop(r, h) }
func bottom(r, h)               { emit okBottom(r, h) }
func left(r, w)                 { emit okLeft(r, w) }
func right(r, w)                { emit okRight(r, w) }
func below(anchor, gap, h)      { emit okBelow(anchor, gap, h) }
func above(anchor, gap, h)      { emit okAbove(anchor, gap, h) }
func rightOf(anchor, gap, w)    { emit okRightOf(anchor, gap, w) }
func leftOf(anchor, gap, w)     { emit okLeftOf(anchor, gap, w) }
func row(root, index, h, gap)   { emit okRect(okX(root), okY(root) + okH(root) - h - index * (h + gap), okW(root), h) }

// Controls
func label(win, text, r)        { emit okLabelR(win, text, r) }
func title(win, text, r)        { emit okLabelR(win, text, r) }
func field(win, r)              { emit okFieldR(win, r) }
func password(win, r)           { emit okPasswordR(win, r) }
func button(win, text, r)       { emit okButtonR(win, text, r) }
func checkbox(win, text, r)     { emit okCheckboxR(win, text, r) }
func textBox(win, r)            { emit okTextViewR(win, r) }
func progress(win, r)           { emit okProgressR(win, r) }
func spinner(win, r)            { emit okSpinnerR(win, r) }
func slider(win, r, mn, mx, v)  { emit okSliderR(win, r, mn, mx, v) }
func choices(win, r)            { emit okComboR(win, r) }

// Values
func text(control)              { emit okText(control) }
func state(control)             { emit okState(control) }
func choice(combo)              { emit okComboText(combo) }
func choiceIndex(combo)         { emit okComboIndex(combo) }

// Action-only helpers
func doText(control, value)     { emit okSetText(control, value) }
func doAppend(box, value)       { emit okAppend(box, value) }
func doPlaceholder(control, v)  { emit okPlaceholder(control, v) }
func doEnable(control)          { emit okEnabled(control, 1) }
func doDisable(control)         { emit okEnabled(control, 0) }
func doHide(view)               { emit okHidden(view, 1) }
func doShowView(view)           { emit okHidden(view, 0) }
func doFrame(view, r)           { emit okFrameR(view, r) }
func doTip(view, value)         { emit okToolTip(view, value) }
func doEditable(control, yes)   { emit okEditable(control, yes) }
func doState(control, value)    { emit okSetState(control, value) }
func doProgress(p, value)       { emit okSetProgress(p, value) }
func doStart(p)                 { emit okStart(p) }
func doStop(p)                  { emit okStop(p) }
func doAddChoice(combo, value)  { emit okComboAdd(combo, value) }
func doChoose(combo, index)     { emit okComboSelect(combo, index) }
func doClick(control, key, fnPtr) { emit okOn(control, key, fnPtr) }
func doSet(obj, key, value)     { emit okSet(obj, key, value) }
func get(obj, key)              { emit okGet(obj, key) }

// System actions
func doCopyText(value)          { emit okSetClipboard(value) }
func clipboard()                { emit okClipboard() }
func setting(key)               { emit okDefault(key) }
func doSetting(key, value)      { emit okSetDefault(key, value) }
func doForgetSetting(key)       { emit okRemoveDefault(key) }
func doOpenURL(url)             { emit okOpenURL(url) }
func doOpenPath(path)           { emit okOpenPath(path) }
func doReveal(path)             { emit okReveal(path) }

// Theme
func color(name)                 { emit okColor(name) }
func rgb(r, g, b)                { emit okRGB(r, g, b) }
func windowBackground()          { emit okSystemWindowBg() }
func textColor()                 { emit okSystemText() }
func secondaryTextColor()        { emit okSystemSecondaryText() }
func textBackground()            { emit okSystemTextBg() }
func doBackground(view, c)       { emit okSetBg(view, c) }
func doTextColor(view, c)        { emit okSetTextColor(view, c) }
func doWindowBackground(win, c)  { emit okSetWindowBg(win, c) }
func mono(size)                  { emit okMonoFont(size) }
func fontFamily(base, family)    { emit okFontFamily(base, family) }
func doFont(view, font)          { emit okSetFont(view, font) }

func done()                      { emit "1" }
