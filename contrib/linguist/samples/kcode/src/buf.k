// buf.k — text buffer: load/save, cursor, insert/delete, undo/redo.
//
// Storage model: a single string `text` whose lines are separated by `\n`.
// Edits splice via substring + concat. O(file size) per keystroke is fine
// for files under a few hundred KB; the renderer's per-frame work dominates
// at editor sizes anyway.
//
// Undo: every "edit boundary" snapshots the buffer before the change.
// A boundary is the first edit after a non-edit action (cursor move,
// save, load) or after a configurable run of typing. Simple but works.

module buf

import "term.k"

// ── Construction ────────────────────────────────────────────────

func bufNewEmpty() {
    let b = envNew()
    b = envSet(b, "path", "")
    b = envSet(b, "text", "")
    b = envSet(b, "savedText", "")   // text last saved to disk (drives dirty flag)
    b = envSet(b, "row", 0)
    b = envSet(b, "col", 0)
    b = envSet(b, "scrollRow", 0)
    b = envSet(b, "scrollCol", 0)
    b = envSet(b, "dirty", 0)
    b = envSet(b, "goalCol", 0)
    b = envSet(b, "atBoundary", 1)   // next edit should snapshot
    b = envSet(b, "undo", "")        // \x01-separated snapshots
    b = envSet(b, "redo", "")
    emit b
}

func bufLoad(path) {
    let b = bufNewEmpty()
    let raw = readFile(path)
    b = envSet(b, "path", path)
    b = envSet(b, "text", raw)
    b = envSet(b, "savedText", raw)
    emit b
}

func bufSave(b) {
    let p = envGet(b, "path")
    if p == "" { emit b }
    let cur = envGet(b, "text")
    let ok = writeFile(p, cur)
    if ok == "1" {
        b = envSet(b, "savedText", cur)
        b = envSet(b, "dirty", 0)
        b = envSet(b, "atBoundary", 1)
    }
    emit b
}

// Recompute dirty by comparing against last-saved text. Cheap call.
func _recomputeDirty(b) {
    if envGet(b, "text") == envGet(b, "savedText") {
        b = envSet(b, "dirty", 0)
    } else {
        b = envSet(b, "dirty", 1)
    }
    emit b
}

// ── Helpers ─────────────────────────────────────────────────────

// Number of lines in the buffer. Always at least 1 (empty file = 1 empty line).
func bufNumLines(b) {
    let t = envGet(b, "text")
    if t == "" { emit 1 }
    let n = lineCount(t)
    // If the file ends in `\n`, lineCount counts the trailing empty line
    // when there's content on the last "line" — which is what we want.
    // If it doesn't end in `\n`, lineCount already includes the last line.
    emit n
}

func bufLine(b, i) {
    emit getLine(envGet(b, "text"), i)
}

// Convert (row, col) to absolute byte offset.
func bufRowColToOffset(b, row, col) {
    let t = envGet(b, "text")
    let i = 0
    let off = 0
    while i < row {
        let line = getLine(t, i)
        off = off + len(line) + 1   // +1 for \n
        i += 1
    }
    emit off + col
}

// Replace the buffer text with `newText`, set cursor to absolute offset `off`.
func bufReplaceText(b, newText, off) {
    b = envSet(b, "text", newText)
    // Convert offset back to (row, col).
    let i = 0
    let walked = 0
    let row = 0
    let col = 0
    let n = len(newText)
    while i < n && walked < off {
        if newText[i] == "\n" {
            row += 1
            col = 0
        } else {
            col += 1
        }
        walked += 1
        i += 1
    }
    b = envSet(b, "row", row)
    b = envSet(b, "col", col)
    b = envSet(b, "goalCol", col)
    emit b
}

// Splice: replace text[a..b] with `ins`, return new text.
func bufSplice(text, a, bend, ins) {
    let pre  = substring(text, 0, a)
    let post = substring(text, bend, len(text))
    emit pre + ins + post
}

// ── Cursor clamping ─────────────────────────────────────────────

func bufLineLen(b, row) {
    if row < 0 { emit 0 }
    if row >= bufNumLines(b) { emit 0 }
    emit len(bufLine(b, row))
}

func bufClampCursor(b) {
    let nl = bufNumLines(b)
    let r = toInt(envGet(b, "row"))
    if r < 0 { r = 0 }
    if r >= nl { r = nl - 1 }
    let ll = bufLineLen(b, r)
    let c = toInt(envGet(b, "col"))
    if c < 0 { c = 0 }
    if c > ll { c = ll }
    b = envSet(b, "row", r)
    b = envSet(b, "col", c)
    emit b
}

// ── Undo / redo ─────────────────────────────────────────────────
//
// Snapshot encoding: "row|col|<text>" with snapshots separated by \x01.
// The text itself can contain newlines and pipes, but never \x01 (we
// reserve the byte). row|col is followed by a single | then the text;
// to decode, split at the first two pipes.

func _undoSep() { emit fromCharCode(1) }

func _snapshot(b) {
    let row = envGet(b, "row")
    let col = envGet(b, "col")
    emit "" + row + "|" + col + "|" + envGet(b, "text")
}

func _restoreSnap(b, snap) {
    // find first |
    let n = len(snap)
    let p1 = -1
    let i = 0
    while i < n {
        if snap[i] == "|" { p1 = i; i = n }
        i += 1
    }
    if p1 < 0 { emit b }
    let p2 = -1
    i = p1 + 1
    while i < n {
        if snap[i] == "|" { p2 = i; i = n }
        i += 1
    }
    if p2 < 0 { emit b }
    let row = toInt(substring(snap, 0, p1))
    let col = toInt(substring(snap, p1 + 1, p2))
    let txt = substring(snap, p2 + 1, n)
    b = envSet(b, "text", txt)
    b = envSet(b, "row", row)
    b = envSet(b, "col", col)
    b = envSet(b, "goalCol", col)
    b = _recomputeDirty(b)
    emit b
}

func _pushUndo(b) {
    let snap = _snapshot(b)
    let prev = envGet(b, "undo")
    let sep = _undoSep()
    if prev == "" {
        b = envSet(b, "undo", snap)
    } else {
        b = envSet(b, "undo", prev + sep + snap)
    }
    // Clear redo on new edit.
    b = envSet(b, "redo", "")
    emit b
}

// Pop the last \x01-separated entry off `stack`. Returns "tail|popped".
// Encodes both as a single string with \x02 separator.
func _splitLastSnap(stack) {
    let sep = _undoSep()
    let n = len(stack)
    let i = n - 1
    let cut = -1
    while i >= 0 {
        if stack[i] == sep { cut = i; i = -1 }
        i -= 1
    }
    if cut < 0 {
        emit "" + fromCharCode(2) + stack
    }
    let head = substring(stack, 0, cut)
    let tail = substring(stack, cut + 1, n)
    emit head + fromCharCode(2) + tail
}

func bufUndo(b) {
    let stack = envGet(b, "undo")
    if stack == "" { emit b }
    let parts = _splitLastSnap(stack)
    // split at \x02
    let sep2 = fromCharCode(2)
    let i = 0
    let cut = -1
    let n = len(parts)
    while i < n {
        if parts[i] == sep2 { cut = i; i = n }
        i += 1
    }
    let head = substring(parts, 0, cut)
    let popped = substring(parts, cut + 1, n)

    // Push current state onto redo before restoring.
    let cur = _snapshot(b)
    let redo = envGet(b, "redo")
    let s1 = _undoSep()
    if redo == "" {
        b = envSet(b, "redo", cur)
    } else {
        b = envSet(b, "redo", redo + s1 + cur)
    }
    b = envSet(b, "undo", head)
    b = _restoreSnap(b, popped)
    b = envSet(b, "atBoundary", 1)
    emit b
}

func bufRedo(b) {
    let stack = envGet(b, "redo")
    if stack == "" { emit b }
    let parts = _splitLastSnap(stack)
    let sep2 = fromCharCode(2)
    let i = 0
    let cut = -1
    let n = len(parts)
    while i < n {
        if parts[i] == sep2 { cut = i; i = n }
        i += 1
    }
    let head = substring(parts, 0, cut)
    let popped = substring(parts, cut + 1, n)

    let cur = _snapshot(b)
    let undo = envGet(b, "undo")
    let s1 = _undoSep()
    if undo == "" {
        b = envSet(b, "undo", cur)
    } else {
        b = envSet(b, "undo", undo + s1 + cur)
    }
    b = envSet(b, "redo", head)
    b = _restoreSnap(b, popped)
    b = envSet(b, "atBoundary", 1)
    emit b
}

// Boundary helper: mark "next edit should snapshot" — called on any
// non-edit action (cursor move, save, etc.).
func bufMarkBoundary(b) {
    b = envSet(b, "atBoundary", 1)
    emit b
}

func _maybePushUndo(b) {
    let at = toInt(envGet(b, "atBoundary"))
    if at == 1 {
        b = _pushUndo(b)
        b = envSet(b, "atBoundary", 0)
    }
    emit b
}

// ── Edit operations ─────────────────────────────────────────────

func bufInsertChar(b, ch) {
    b = _maybePushUndo(b)
    let off = bufRowColToOffset(b, toInt(envGet(b, "row")), toInt(envGet(b, "col")))
    let t = envGet(b, "text")
    b = bufReplaceText(b, bufSplice(t, off, off, ch), off + len(ch))
    b = envSet(b, "dirty", 1)
    // Word-boundary breaks the undo group so each "word" lands on its own
    // undo step. Without this, undo rewinds an entire typing burst at once.
    if ch == " " || ch == "\n" || ch == "\t" {
        b = envSet(b, "atBoundary", 1)
    }
    emit b
}

func bufInsertNewline(b) {
    b = bufInsertChar(b, "\n")
    emit b
}

func bufBackspace(b) {
    let row = toInt(envGet(b, "row"))
    let col = toInt(envGet(b, "col"))
    if row == 0 && col == 0 { emit b }
    b = _maybePushUndo(b)
    let off = bufRowColToOffset(b, row, col)
    let t = envGet(b, "text")
    // Delete one byte before cursor. (UTF-8 friendly enough for the basic case;
    // we assume callers don't position the cursor mid-codepoint, since
    // tReadKey returns full codepoints.)
    let start = off - 1
    // For multi-byte UTF-8 walk back to the codepoint start.
    let walking = 1
    while walking == 1 && start > 0 {
        let bb = charCode(t[start])
        // Continuation bytes are 10xxxxxx (128..191).
        if bb >= 128 && bb < 192 {
            start -= 1
        } else {
            walking = 0
        }
    }
    b = bufReplaceText(b, bufSplice(t, start, off, ""), start)
    b = envSet(b, "dirty", 1)
    emit b
}

func bufDeleteForward(b) {
    let row = toInt(envGet(b, "row"))
    let col = toInt(envGet(b, "col"))
    let t = envGet(b, "text")
    let off = bufRowColToOffset(b, row, col)
    if off >= len(t) { emit b }
    b = _maybePushUndo(b)
    let endO = off + 1
    // Step over UTF-8 continuation bytes for full-codepoint delete.
    let advancing = 1
    while advancing == 1 && endO < len(t) {
        let bb = charCode(t[endO])
        if bb >= 128 && bb < 192 { endO += 1 }
        else { advancing = 0 }
    }
    b = bufReplaceText(b, bufSplice(t, off, endO, ""), off)
    b = envSet(b, "dirty", 1)
    emit b
}

// ── Movement ────────────────────────────────────────────────────

func bufMoveLeft(b) {
    b = bufMarkBoundary(b)
    let r = toInt(envGet(b, "row"))
    let c = toInt(envGet(b, "col"))
    if c > 0 {
        c -= 1
    } else if r > 0 {
        r -= 1
        c = bufLineLen(b, r)
    }
    b = envSet(b, "row", r)
    b = envSet(b, "col", c)
    b = envSet(b, "goalCol", c)
    emit b
}

func bufMoveRight(b) {
    b = bufMarkBoundary(b)
    let r = toInt(envGet(b, "row"))
    let c = toInt(envGet(b, "col"))
    let ll = bufLineLen(b, r)
    if c < ll {
        c += 1
    } else if r < bufNumLines(b) - 1 {
        r += 1
        c = 0
    }
    b = envSet(b, "row", r)
    b = envSet(b, "col", c)
    b = envSet(b, "goalCol", c)
    emit b
}

func bufMoveUp(b) {
    b = bufMarkBoundary(b)
    let r = toInt(envGet(b, "row"))
    if r == 0 { emit b }
    r -= 1
    let goal = toInt(envGet(b, "goalCol"))
    let ll = bufLineLen(b, r)
    let c = goal
    if c > ll { c = ll }
    b = envSet(b, "row", r)
    b = envSet(b, "col", c)
    emit b
}

func bufMoveDown(b) {
    b = bufMarkBoundary(b)
    let r = toInt(envGet(b, "row"))
    if r >= bufNumLines(b) - 1 { emit b }
    r += 1
    let goal = toInt(envGet(b, "goalCol"))
    let ll = bufLineLen(b, r)
    let c = goal
    if c > ll { c = ll }
    b = envSet(b, "row", r)
    b = envSet(b, "col", c)
    emit b
}

func bufHome(b) {
    b = bufMarkBoundary(b)
    b = envSet(b, "col", 0)
    b = envSet(b, "goalCol", 0)
    emit b
}

func bufEnd(b) {
    b = bufMarkBoundary(b)
    let r = toInt(envGet(b, "row"))
    let c = bufLineLen(b, r)
    b = envSet(b, "col", c)
    b = envSet(b, "goalCol", c)
    emit b
}

func bufPageDown(b, pageRows) {
    b = bufMarkBoundary(b)
    let r = toInt(envGet(b, "row"))
    let nl = bufNumLines(b)
    r += pageRows
    if r >= nl { r = nl - 1 }
    let goal = toInt(envGet(b, "goalCol"))
    let ll = bufLineLen(b, r)
    let c = goal
    if c > ll { c = ll }
    b = envSet(b, "row", r)
    b = envSet(b, "col", c)
    // Jump scroll along too.
    let s = toInt(envGet(b, "scrollRow"))
    s += pageRows
    if s >= nl { s = nl - 1 }
    if s < 0 { s = 0 }
    b = envSet(b, "scrollRow", s)
    emit b
}

func bufPageUp(b, pageRows) {
    b = bufMarkBoundary(b)
    let r = toInt(envGet(b, "row"))
    r -= pageRows
    if r < 0 { r = 0 }
    let goal = toInt(envGet(b, "goalCol"))
    let ll = bufLineLen(b, r)
    let c = goal
    if c > ll { c = ll }
    b = envSet(b, "row", r)
    b = envSet(b, "col", c)
    let s = toInt(envGet(b, "scrollRow"))
    s -= pageRows
    if s < 0 { s = 0 }
    b = envSet(b, "scrollRow", s)
    emit b
}

func bufGotoLine(b, line1based) {
    b = bufMarkBoundary(b)
    let nl = bufNumLines(b)
    let r = line1based - 1
    if r < 0 { r = 0 }
    if r >= nl { r = nl - 1 }
    b = envSet(b, "row", r)
    b = envSet(b, "col", 0)
    b = envSet(b, "goalCol", 0)
    emit b
}

// ── Scroll adjustment so cursor stays visible ───────────────────

func bufScrollToCursor(b, viewRows, viewCols) {
    let r = toInt(envGet(b, "row"))
    let c = toInt(envGet(b, "col"))
    let sr = toInt(envGet(b, "scrollRow"))
    let sc = toInt(envGet(b, "scrollCol"))
    if r < sr { sr = r }
    if r >= sr + viewRows { sr = r - viewRows + 1 }
    if sr < 0 { sr = 0 }
    if c < sc { sc = c }
    if c >= sc + viewCols { sc = c - viewCols + 1 }
    if sc < 0 { sc = 0 }
    b = envSet(b, "scrollRow", sr)
    b = envSet(b, "scrollCol", sc)
    emit b
}

// ── Search ──────────────────────────────────────────────────────

// Find `needle` starting from (row, col); on hit, move cursor there.
// `forward = 1` searches forward (incl. wrap), `0` searches backward.
// Returns the (possibly updated) buffer; sets row/col on success.
func bufFind(b, needle, fromRow, fromCol, forward) {
    if needle == "" { emit b }
    let t = envGet(b, "text")
    let startOff = bufRowColToOffset(b, fromRow, fromCol)
    if forward == 1 {
        let tail = substring(t, startOff, len(t))
        let p = indexOf(tail, needle)
        if p >= 0 {
            let abs = startOff + p
            b = bufReplaceText(b, t, abs)
            emit b
        }
        // Wrap.
        let head = substring(t, 0, startOff)
        let p2 = indexOf(head, needle)
        if p2 >= 0 {
            b = bufReplaceText(b, t, p2)
            emit b
        }
        emit b
    }
    // Backward: scan from start to startOff for the LAST occurrence.
    let head2 = substring(t, 0, startOff)
    let last = -1
    let scanFrom = 0
    while scanFrom <= len(head2) {
        let rest = substring(head2, scanFrom, len(head2))
        let p3 = indexOf(rest, needle)
        if p3 < 0 { break }
        last = scanFrom + p3
        scanFrom = last + 1
    }
    if last >= 0 {
        b = bufReplaceText(b, t, last)
        emit b
    }
    // Wrap from end.
    let scan2 = startOff
    let last2 = -1
    while scan2 <= len(t) {
        let rest2 = substring(t, scan2, len(t))
        let p4 = indexOf(rest2, needle)
        if p4 < 0 { break }
        last2 = scan2 + p4
        scan2 = last2 + 1
    }
    if last2 >= 0 {
        b = bufReplaceText(b, t, last2)
    }
    emit b
}
