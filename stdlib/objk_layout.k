// stdlib/objk_layout.k -- shared Objective-K rect/layout helpers.
//
// Imported by both k:objk (macOS) and k:objkwin (Windows).
// Rects are plain strings: "x,y,w,h".

module objk_layout

func okRect(x, y, w, h)               { emit "" + x + "," + y + "," + w + "," + h }
func okX(r)                           { emit toInt(_okRectPart(r, 0)) }
func okY(r)                           { emit toInt(_okRectPart(r, 1)) }
func okW(r)                           { emit toInt(_okRectPart(r, 2)) }
func okH(r)                           { emit toInt(_okRectPart(r, 3)) }
func okInset(r, pad)                  { emit okRect(okX(r) + pad, okY(r) + pad, okW(r) - pad * 2, okH(r) - pad * 2) }
func okMove(r, x, y)                  { emit okRect(x, y, okW(r), okH(r)) }
func okResize(r, w, h)                { emit okRect(okX(r), okY(r), w, h) }
func okTop(r, h)                      { emit okRect(okX(r), okY(r) + okH(r) - h, okW(r), h) }
func okBottom(r, h)                   { emit okRect(okX(r), okY(r), okW(r), h) }
func okLeft(r, w)                     { emit okRect(okX(r), okY(r), w, okH(r)) }
func okRight(r, w)                    { emit okRect(okX(r) + okW(r) - w, okY(r), w, okH(r)) }
func okBelow(anchor, gap, h)          { emit okRect(okX(anchor), okY(anchor) - gap - h, okW(anchor), h) }
func okAbove(anchor, gap, h)          { emit okRect(okX(anchor), okY(anchor) + okH(anchor) + gap, okW(anchor), h) }
func okRightOf(anchor, gap, w)        { emit okRect(okX(anchor) + okW(anchor) + gap, okY(anchor), w, okH(anchor)) }
func okLeftOf(anchor, gap, w)         { emit okRect(okX(anchor) - gap - w, okY(anchor), w, okH(anchor)) }

func okFrameR(view, r)                { emit okFrame(view, okX(r), okY(r), okW(r), okH(r)) }
func okButtonR(win, label, r)         { emit okButton(win, label, okX(r), okY(r), okW(r), okH(r)) }
func okCheckboxR(win, label, r)       { emit okCheckbox(win, label, okX(r), okY(r), okW(r), okH(r)) }
func okFieldR(win, r)                 { emit okField(win, okX(r), okY(r), okW(r), okH(r)) }
func okPasswordR(win, r)              { emit okPassword(win, okX(r), okY(r), okW(r), okH(r)) }
func okLabelR(win, text, r)           { emit okLabel(win, text, okX(r), okY(r), okW(r), okH(r)) }
func okTextViewR(win, r)              { emit okTextView(win, okX(r), okY(r), okW(r), okH(r)) }
func okProgressR(win, r)              { emit okProgress(win, okX(r), okY(r), okW(r), okH(r)) }
func okSpinnerR(win, r)               { emit okSpinner(win, okX(r), okY(r), okW(r), okH(r)) }
func okSliderR(win, r, mn, mx, v)     { emit okSlider(win, okX(r), okY(r), okW(r), okH(r), mn, mx, v) }
func okComboR(win, r)                 { emit okCombo(win, okX(r), okY(r), okW(r), okH(r)) }

func _okRectPart(r, idx) {
    let cur = 0
    let start = 0
    let i = 0
    while i <= len(r) {
        if i == len(r) || substring(r, i, i + 1) == "," {
            if cur == idx { emit substring(r, start, i) }
            cur += 1
            start = i + 1
        }
        i += 1
    }
    emit "0"
}
