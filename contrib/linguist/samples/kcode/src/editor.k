// editor.k — top-level editor: state, render, key dispatch, main loop.
//
// Layout (no tree pane in v0.1; would be added back when kcc lifts the
// global program-size limit that bit us at our previous size):
//
//   row 0..rows-3: editor pane (line-number gutter + content)
//   row rows-2:    status line
//   row rows-1:    minibuffer (prompt + transient messages)
//
// Focus is one of:
//   "editor" — keys go to the buffer
//   "prompt" — keys edit the minibuffer; Enter submits
// Build/run output overlays the screen and is dismissed with ESC.

module editor

import "term.k"
import "buf.k"

// ── ANSI helpers ────────────────────────────────────────────────

func _esc()           { emit fromCharCode(27) }
func _at(row, col)    { emit _esc() + "[" + (row + 1) + ";" + (col + 1) + "H" }
func _reset()         { emit _esc() + "[0m" }
func _clearEol()      { emit _esc() + "[K" }
func _hide()          { emit _esc() + "[?25l" }
func _show()          { emit _esc() + "[?25h" }
func _dim()           { emit _esc() + "[2m" }
func _statusBg()      { emit _esc() + "[48;5;236m" + _esc() + "[38;5;250m" }
func _statusBgActive(){ emit _esc() + "[48;5;24m"  + _esc() + "[38;5;230m" }
func _gutterFg()      { emit _esc() + "[38;5;240m" }
func _gutterFgActive(){ emit _esc() + "[38;5;220m" }
func _msgErrFg()      { emit _esc() + "[38;5;203m" }
func _msgOkFg()       { emit _esc() + "[38;5;108m" }

// ── Highlighter (single-line, .k aware) ─────────────────────────

func _hlReset()   { emit _esc() + "[0m" }
func _hlComment() { emit _esc() + "[38;5;245m" }
func _hlString()  { emit _esc() + "[38;5;142m" }
func _hlNumber()  { emit _esc() + "[38;5;175m" }
func _hlKeyword() { emit _esc() + "[38;5;167m" }
func _hlBuiltin() { emit _esc() + "[38;5;108m" }
func _hlType()    { emit _esc() + "[38;5;214m" }

func _isAlpha(c) {
    if c >= "a" && c <= "z" { emit 1 }
    if c >= "A" && c <= "Z" { emit 1 }
    if c == "_" { emit 1 }
    emit 0
}
func _isAlNum(c) {
    if _isAlpha(c) == 1 { emit 1 }
    if c >= "0" && c <= "9" { emit 1 }
    emit 0
}
func _isDigC(c) {
    if c >= "0" && c <= "9" { emit 1 }
    emit 0
}
func _kwTab() {
    emit "|just|go|run|func|fn|let|const|emit|return|if|else|while|do|loop|until|break|continue|for|in|match|struct|class|type|callback|try|catch|throw|module|import|export|jxt|cfunc|true|false|null|"
}
func _biTab() {
    emit "|print|kp|printErr|readFile|writeFile|arg|argCount|exit|readLine|input|deleteFile|shellRun|environ|len|substring|startsWith|endsWith|contains|indexOf|replace|trim|toUpper|toLower|reverse|repeat|charCode|fromCharCode|isDigit|isAlpha|toInt|parseInt|abs|pow|range|min|max|sqrt|sign|clamp|hex|bin|floor|ceil|round|random|timestamp|split|length|count|first|last|head|tail|append|slice|removeAt|replaceAt|remove|sort|unique|fill|zip|listIndexOf|every|some|countOf|sumList|minList|maxList|listMap|listFilter|mapGet|mapSet|mapDel|keys|values|hasKey|structNew|setField|getField|hasField|structFields|getLine|lineCount|sbNew|sbAppend|sbToString|envNew|envSet|envGet|toStr|isTruthy|type|assert|throw|"
}

func _hlLine(s, isK) {
    if isK == 0 { emit s }
    let n = len(s)
    if n == 0 { emit "" }
    let sb = sbNew()
    let i = 0
    let RESET = _hlReset()
    while i < n {
        let c = s[i]
        if c == "/" && i + 1 < n && s[i + 1] == "/" {
            sb = sbAppend(sb, _hlComment())
            sb = sbAppend(sb, substring(s, i, n))
            sb = sbAppend(sb, RESET)
            i = n
        } else if c == "\"" {
            sb = sbAppend(sb, _hlString())
            sb = sbAppend(sb, "\"")
            i += 1
            let closed = 0
            while i < n && closed == 0 {
                let cc = s[i]
                if cc == "\\" && i + 1 < n {
                    sb = sbAppend(sb, substring(s, i, i + 2))
                    i += 2
                } else if cc == "\"" {
                    sb = sbAppend(sb, "\"")
                    i += 1
                    closed = 1
                } else {
                    sb = sbAppend(sb, cc)
                    i += 1
                }
            }
            sb = sbAppend(sb, RESET)
        } else if c == "`" {
            sb = sbAppend(sb, _hlString())
            sb = sbAppend(sb, "`")
            i += 1
            let closed = 0
            while i < n && closed == 0 {
                let cc = s[i]
                if cc == "\\" && i + 1 < n {
                    sb = sbAppend(sb, substring(s, i, i + 2))
                    i += 2
                } else if cc == "`" {
                    sb = sbAppend(sb, "`")
                    i += 1
                    closed = 1
                } else {
                    sb = sbAppend(sb, cc)
                    i += 1
                }
            }
            sb = sbAppend(sb, RESET)
        } else if _isDigC(c) == 1 {
            sb = sbAppend(sb, _hlNumber())
            let start = i
            while i < n && _isDigC(s[i]) == 1 { i += 1 }
            sb = sbAppend(sb, substring(s, start, i))
            sb = sbAppend(sb, RESET)
        } else if _isAlpha(c) == 1 {
            let start = i
            while i < n && _isAlNum(s[i]) == 1 { i += 1 }
            let word = substring(s, start, i)
            if contains(_kwTab(), "|" + word + "|") == "1" {
                sb = sbAppend(sb, _hlKeyword())
                sb = sbAppend(sb, word)
                sb = sbAppend(sb, RESET)
            } else if contains(_biTab(), "|" + word + "|") == "1" {
                sb = sbAppend(sb, _hlBuiltin())
                sb = sbAppend(sb, word)
                sb = sbAppend(sb, RESET)
            } else if word[0] >= "A" && word[0] <= "Z" {
                sb = sbAppend(sb, _hlType())
                sb = sbAppend(sb, word)
                sb = sbAppend(sb, RESET)
            } else {
                sb = sbAppend(sb, word)
            }
        } else {
            sb = sbAppend(sb, c)
            i += 1
        }
    }
    emit sbToString(sb)
}

// ── Editor state ────────────────────────────────────────────────

func edNew(initialPath, treeRoot) {
    let e = envNew()
    let b = bufNewEmpty()
    if initialPath != "" { b = bufLoad(initialPath) }
    e = envSet(e, "buf", b)
    e = envSet(e, "rows", 24)
    e = envSet(e, "cols", 80)
    e = envSet(e, "focus", "editor")
    e = envSet(e, "prompt", "")
    e = envSet(e, "promptInput", "")
    e = envSet(e, "promptKind", "")
    e = envSet(e, "message", "")
    e = envSet(e, "messageKind", "")
    e = envSet(e, "lastSearch", "")
    e = envSet(e, "running", 1)
    e = envSet(e, "overlay", "")
    e = envSet(e, "overlayTitle", "")
    e = envSet(e, "overlayScroll", 0)
    e = envSet(e, "pkOpen", 0)
    e = envSet(e, "pkFiles", "")
    e = envSet(e, "pkQuery", "")
    e = envSet(e, "pkCursor", 0)
    e = envSet(e, "bufList", "")
    if initialPath != "" { e = envSet(e, "bufList", initialPath) }
    emit e
}

func _setMsg(e, msg, kind) {
    e = envSet(e, "message", msg)
    e = envSet(e, "messageKind", kind)
    emit e
}

func _gutterWidth(b) {
    let n = bufNumLines(b)
    let d = 1
    let v = n
    while v >= 10 { v = v / 10; d += 1 }
    if d < 3 { d = 3 }
    emit d + 2
}

func _padRight(s, width) {
    let cur = len(s)
    if cur >= width { emit s }
    let need = width - cur
    let pad = ""
    let i = 0
    while i < need { pad = pad + " "; i += 1 }
    emit s + pad
}

// ── Render ──────────────────────────────────────────────────────

func _renderEditor(e, sb, viewRowsCount) {
    let b = envGet(e, "buf")
    let cols = toInt(envGet(e, "cols"))
    let gutterW = _gutterWidth(b)
    let contentW = cols - gutterW
    if contentW < 4 { contentW = 4 }

    let scrollRow = toInt(envGet(b, "scrollRow"))
    let scrollCol = toInt(envGet(b, "scrollCol"))
    let cursorRow = toInt(envGet(b, "row"))
    let totalLines = bufNumLines(b)
    let path = envGet(b, "path")
    let isK = 0
    if endsWith(path, ".k") == "1" { isK = 1 }

    let i = 0
    while i < viewRowsCount {
        sb = sbAppend(sb, _at(i, 0))
        let bufRow = scrollRow + i
        if bufRow < totalLines {
            let lnStr = "" + (bufRow + 1)
            let pad = ""
            let need = gutterW - 2 - len(lnStr)
            let p = 0
            while p < need { pad = pad + " "; p += 1 }
            if bufRow == cursorRow {
                sb = sbAppend(sb, _gutterFgActive())
                sb = sbAppend(sb, pad + lnStr)
                sb = sbAppend(sb, _esc() + "[38;5;240m" + " │")
            } else {
                sb = sbAppend(sb, _gutterFg())
                sb = sbAppend(sb, pad + lnStr + " │")
            }
            sb = sbAppend(sb, _reset())

            let line = bufLine(b, bufRow)
            let llen = len(line)
            let from = scrollCol
            if from > llen { from = llen }
            let to = from + contentW
            if to > llen { to = llen }
            let slice = substring(line, from, to)
            slice = replace(slice, "\t", "    ")
            if len(slice) > contentW { slice = substring(slice, 0, contentW) }
            sb = sbAppend(sb, _hlLine(slice, isK))
            sb = sbAppend(sb, _reset())
            sb = sbAppend(sb, _padRight("", contentW - len(slice)))
        } else {
            sb = sbAppend(sb, _gutterFg())
            sb = sbAppend(sb, _padRight("~", gutterW))
            sb = sbAppend(sb, _padRight("", contentW))
            sb = sbAppend(sb, _reset())
        }
        i += 1
    }
    emit sb
}

func _renderStatus(e, sb) {
    let rows = toInt(envGet(e, "rows"))
    let cols = toInt(envGet(e, "cols"))
    let b = envGet(e, "buf")
    let path = envGet(b, "path")
    if path == "" { path = "[no name]" }
    let dirty = ""
    if toInt(envGet(b, "dirty")) == 1 { dirty = " ●" }
    let row = toInt(envGet(b, "row")) + 1
    let col = toInt(envGet(b, "col")) + 1
    let totalLines = bufNumLines(b)
    let mode = "EDIT"
    if envGet(e, "focus") == "prompt" { mode = "PROMPT" }
    let bufList = envGet(e, "bufList")
    let nBufs = lineCount(bufList)
    if bufList == "" { nBufs = 0 }
    let bufIdx = _bufListIndex(bufList, envGet(b, "path"))
    let bufTag = ""
    if nBufs > 1 { bufTag = "  [" + (bufIdx + 1) + "/" + nBufs + "]" }

    let left = " " + mode + " " + path + dirty + bufTag + " "
    let right = " L" + row + ":C" + col + "  " + row + "/" + totalLines + " "
    let mid = ""
    let need = cols - len(left) - len(right)
    if need < 0 { need = 0 }
    let p = 0
    while p < need { mid = mid + " "; p += 1 }
    sb = sbAppend(sb, _at(rows - 2, 0))
    sb = sbAppend(sb, _statusBgActive())
    sb = sbAppend(sb, left)
    sb = sbAppend(sb, _statusBg())
    sb = sbAppend(sb, mid)
    sb = sbAppend(sb, _statusBgActive())
    sb = sbAppend(sb, right)
    sb = sbAppend(sb, _reset())
    emit sb
}

func _renderMinibuffer(e, sb) {
    let rows = toInt(envGet(e, "rows"))
    let cols = toInt(envGet(e, "cols"))
    sb = sbAppend(sb, _at(rows - 1, 0))
    if envGet(e, "focus") == "prompt" {
        let prompt = envGet(e, "prompt")
        let inp = envGet(e, "promptInput")
        let txt = prompt + inp
        if len(txt) > cols - 1 { txt = substring(txt, len(txt) - (cols - 1), len(txt)) }
        sb = sbAppend(sb, txt)
        sb = sbAppend(sb, _clearEol())
    } else {
        let msg = envGet(e, "message")
        let kind = envGet(e, "messageKind")
        if kind == "err" { sb = sbAppend(sb, _msgErrFg()) }
        else if kind == "ok" { sb = sbAppend(sb, _msgOkFg()) }
        else { sb = sbAppend(sb, _dim()) }
        if len(msg) > cols - 1 { msg = substring(msg, 0, cols - 1) }
        sb = sbAppend(sb, msg)
        sb = sbAppend(sb, _reset())
        sb = sbAppend(sb, _clearEol())
    }
    emit sb
}

func _renderOverlay(e, sb) {
    let rows = toInt(envGet(e, "rows"))
    let cols = toInt(envGet(e, "cols"))
    let title = envGet(e, "overlayTitle")
    let body = envGet(e, "overlay")
    let scroll = toInt(envGet(e, "overlayScroll"))
    sb = sbAppend(sb, _at(0, 0))
    sb = sbAppend(sb, _statusBgActive())
    let header = "  " + title + "    [ESC dismiss · ↑↓ scroll]"
    if len(header) > cols { header = substring(header, 0, cols) }
    sb = sbAppend(sb, header)
    let hp = 0
    while hp < cols - len(header) { sb = sbAppend(sb, " "); hp += 1 }
    sb = sbAppend(sb, _reset())
    let viewRows = rows - 3
    let total = lineCount(body)
    if body == "" { total = 0 }
    let i = 0
    while i < viewRows {
        sb = sbAppend(sb, _at(i + 1, 0))
        let idx = scroll + i
        if idx < total {
            let line = getLine(body, idx)
            line = replace(line, "\t", "    ")
            if len(line) > cols { line = substring(line, 0, cols) }
            sb = sbAppend(sb, line)
        }
        sb = sbAppend(sb, _clearEol())
        i += 1
    }
    emit sb
}

// ── File picker (Ctrl-P) ────────────────────────────────────────

func _pkFilter(files, query) {
    if query == "" { emit files }
    let q = toLower(query)
    let n = lineCount(files)
    let i = 0
    let out = ""
    while i < n {
        let line = getLine(files, i)
        if contains(toLower(line), q) == "1" {
            if out == "" { out = line } else { out = out + "\n" + line }
        }
        i += 1
    }
    emit out
}

func _renderPicker(e, sb) {
    let rows = toInt(envGet(e, "rows"))
    let cols = toInt(envGet(e, "cols"))
    let q = envGet(e, "pkQuery")
    let files = envGet(e, "pkFiles")
    let filtered = _pkFilter(files, q)
    let total = lineCount(filtered)
    if filtered == "" { total = 0 }
    let cursor = toInt(envGet(e, "pkCursor"))
    if cursor >= total { cursor = total - 1 }
    if cursor < 0 { cursor = 0 }

    sb = sbAppend(sb, _at(0, 0))
    sb = sbAppend(sb, _statusBgActive())
    let header = "  open file    [type to filter · ↑↓ select · Enter open · ESC dismiss]"
    if len(header) > cols { header = substring(header, 0, cols) }
    sb = sbAppend(sb, header)
    let hp = 0
    while hp < cols - len(header) { sb = sbAppend(sb, " "); hp += 1 }
    sb = sbAppend(sb, _reset())

    sb = sbAppend(sb, _at(1, 0))
    sb = sbAppend(sb, _esc() + "[38;5;220m▸ " + _reset() + q)
    sb = sbAppend(sb, _dim() + "  (" + total + " match)" + _reset())
    sb = sbAppend(sb, _clearEol())

    let viewRows = rows - 4
    let i = 0
    while i < viewRows {
        sb = sbAppend(sb, _at(i + 2, 0))
        if i < total {
            let line = getLine(filtered, i)
            if i == cursor {
                sb = sbAppend(sb, _esc() + "[48;5;238m" + _esc() + "[38;5;230m  " + line)
                let pad = cols - len(line) - 2
                let pp = 0
                while pp < pad { sb = sbAppend(sb, " "); pp += 1 }
                sb = sbAppend(sb, _reset())
            } else {
                sb = sbAppend(sb, "  " + line)
                sb = sbAppend(sb, _clearEol())
            }
        } else {
            sb = sbAppend(sb, _clearEol())
        }
        i += 1
    }
    emit sb
}

// shellRun returns system(3)'s status, not stdout — capture via a temp file.
func _shellCapture(cmd) {
    shellRun(cmd + " > /tmp/_kcode_sh.out 2>&1")
    let r = readFile("/tmp/_kcode_sh.out")
    deleteFile("/tmp/_kcode_sh.out")
    emit r
}

func _pkOpen(e) {
    let listing = _shellCapture("find . -maxdepth 8 -type f -not -path '*/.*' | sed 's|^./||' | sort | head -5000")
    e = envSet(e, "pkOpen", 1)
    e = envSet(e, "pkFiles", listing)
    e = envSet(e, "pkQuery", "")
    e = envSet(e, "pkCursor", 0)
    emit e
}

func _pkClose(e) {
    e = envSet(e, "pkOpen", 0)
    e = envSet(e, "pkFiles", "")
    e = envSet(e, "pkQuery", "")
    e = envSet(e, "pkCursor", 0)
    emit e
}

// ── Multi-buffer ────────────────────────────────────────────────
//
// Storage: each non-current buffer lives at env key "buf:<path>".
// The current buffer stays at "buf". `bufList` is a \n-separated list
// of paths in the order buffers were opened.

func _bufListContains(list, path) {
    if list == "" { emit 0 }
    let n = lineCount(list)
    let i = 0
    while i < n {
        if getLine(list, i) == path { emit 1 }
        i += 1
    }
    emit 0
}

func _bufListIndex(list, path) {
    if list == "" { emit -1 }
    let n = lineCount(list)
    let i = 0
    while i < n {
        if getLine(list, i) == path { emit i }
        i += 1
    }
    emit -1
}

func _bufListAdd(list, path) {
    if list == "" { emit path }
    if _bufListContains(list, path) == 1 { emit list }
    emit list + "\n" + path
}

func _bufListRemove(list, path) {
    let n = lineCount(list)
    let i = 0
    let out = ""
    while i < n {
        let p = getLine(list, i)
        if p != path {
            if out == "" { out = p } else { out = out + "\n" + p }
        }
        i += 1
    }
    emit out
}

// Open `path` in a new buffer slot. If the current buffer is empty &
// unnamed, replace it instead of growing the list.
func edOpenBuffer(e, path) {
    if path == "" { emit e }
    let b = envGet(e, "buf")
    let curPath = envGet(b, "path")
    let curText = envGet(b, "text")
    if curPath == "" && curText == "" {
        e = envSet(e, "buf", bufLoad(path))
        e = envSet(e, "bufList", _bufListAdd(envGet(e, "bufList"), path))
        emit e
    }
    // Stash current under its path, then open new.
    if curPath != "" {
        e = envSet(e, "buf:" + curPath, b)
    }
    // bufList already contains `path` only if we've opened it before;
    // checking here avoids the noisy "undefined variable" envGet warning
    // for the first-open case.
    let known = _bufListContains(envGet(e, "bufList"), path)
    if known == 1 {
        e = envSet(e, "buf", envGet(e, "buf:" + path))
    } else {
        e = envSet(e, "buf", bufLoad(path))
    }
    e = envSet(e, "bufList", _bufListAdd(envGet(e, "bufList"), path))
    emit e
}

// Cycle to next/prev buffer in bufList. step = +1 or -1.
func edCycleBuffer(e, step) {
    let list = envGet(e, "bufList")
    let n = lineCount(list)
    if list == "" || n < 2 { emit e }
    let cur = envGet(envGet(e, "buf"), "path")
    let idx = _bufListIndex(list, cur)
    if idx < 0 { idx = 0 }
    let nextIdx = idx + step
    if nextIdx < 0 { nextIdx = n - 1 }
    if nextIdx >= n { nextIdx = 0 }
    let nextPath = getLine(list, nextIdx)
    if nextPath == cur { emit e }
    e = envSet(e, "buf:" + cur, envGet(e, "buf"))
    e = envSet(e, "buf", envGet(e, "buf:" + nextPath))
    emit e
}

// Close current buffer. If last, drop to an empty buffer.
func edCloseBuffer(e) {
    let b = envGet(e, "buf")
    let curPath = envGet(b, "path")
    let list = envGet(e, "bufList")
    if list == "" {
        e = envSet(e, "buf", bufNewEmpty())
        emit e
    }
    let newList = _bufListRemove(list, curPath)
    e = envSet(e, "bufList", newList)
    if newList == "" {
        e = envSet(e, "buf", bufNewEmpty())
        emit e
    }
    let nextPath = getLine(newList, 0)
    e = envSet(e, "buf", envGet(e, "buf:" + nextPath))
    emit e
}

func _handlePickerKey(e, k) {
    if k == "ESC" || k == "C-g" { e = _pkClose(e); emit e }
    if k == "ENTER" {
        let filtered = _pkFilter(envGet(e, "pkFiles"), envGet(e, "pkQuery"))
        let cursor = toInt(envGet(e, "pkCursor"))
        let total = lineCount(filtered)
        if filtered == "" { total = 0 }
        if cursor >= total { cursor = total - 1 }
        if cursor < 0 { e = _pkClose(e); emit e }
        let path = getLine(filtered, cursor)
        e = edOpenBuffer(e, path)
        e = _setMsg(e, "opened " + path, "ok")
        e = _pkClose(e); emit e
    }
    if k == "UP" {
        let c = toInt(envGet(e, "pkCursor"))
        if c > 0 { c -= 1 }
        e = envSet(e, "pkCursor", c); emit e
    }
    if k == "DOWN" {
        let c = toInt(envGet(e, "pkCursor"))
        c += 1
        e = envSet(e, "pkCursor", c); emit e
    }
    if k == "BACKSPACE" {
        let s = envGet(e, "pkQuery")
        if len(s) > 0 { e = envSet(e, "pkQuery", substring(s, 0, len(s) - 1)) }
        e = envSet(e, "pkCursor", 0); emit e
    }
    if len(k) == 1 {
        let cc = charCode(k)
        if cc >= 32 && cc < 127 {
            e = envSet(e, "pkQuery", envGet(e, "pkQuery") + k)
            e = envSet(e, "pkCursor", 0); emit e
        }
    } else {
        if charCode(k[0]) >= 128 {
            e = envSet(e, "pkQuery", envGet(e, "pkQuery") + k)
            e = envSet(e, "pkCursor", 0); emit e
        }
    }
    emit e
}

func edRender(e) {
    let sz = tSize()
    let comma = indexOf(sz, ",")
    let rows = toInt(substring(sz, 0, comma))
    let cols = toInt(substring(sz, comma + 1, len(sz)))
    if rows < 5 { rows = 5 }
    if cols < 20 { cols = 20 }
    e = envSet(e, "rows", rows)
    e = envSet(e, "cols", cols)
    let b = envGet(e, "buf")
    let gutterW = _gutterWidth(b)
    let contentW = cols - gutterW
    if contentW < 4 { contentW = 4 }
    b = bufScrollToCursor(b, rows - 2, contentW)
    e = envSet(e, "buf", b)

    let sb = sbNew()
    sb = sbAppend(sb, _hide())
    if toInt(envGet(e, "pkOpen")) == 1 {
        sb = _renderPicker(e, sb)
        sb = sbAppend(sb, _at(1, 2 + len(envGet(e, "pkQuery"))))
        sb = sbAppend(sb, _show())
    } else if envGet(e, "overlay") != "" {
        sb = _renderOverlay(e, sb)
        sb = _renderStatus(e, sb)
        sb = _renderMinibuffer(e, sb)
        sb = sbAppend(sb, _at(rows - 1, 0))
    } else {
        sb = _renderEditor(e, sb, rows - 2)
        sb = _renderStatus(e, sb)
        sb = _renderMinibuffer(e, sb)
        if envGet(e, "focus") == "prompt" {
            let cursorCol = len(envGet(e, "prompt")) + len(envGet(e, "promptInput"))
            if cursorCol > cols - 1 { cursorCol = cols - 1 }
            sb = sbAppend(sb, _at(rows - 1, cursorCol))
            sb = sbAppend(sb, _show())
        } else {
            let r2 = toInt(envGet(b, "row"))
            let c2 = toInt(envGet(b, "col"))
            let sr = toInt(envGet(b, "scrollRow"))
            let sc = toInt(envGet(b, "scrollCol"))
            sb = sbAppend(sb, _at(r2 - sr, gutterW + (c2 - sc)))
            sb = sbAppend(sb, _show())
        }
    }
    tWrite(sbToString(sb))
    tFlush()
    emit e
}

// ── Prompt helpers ──────────────────────────────────────────────

func _enterPrompt(e, kind, prompt, prefill) {
    e = envSet(e, "focus", "prompt")
    e = envSet(e, "promptKind", kind)
    e = envSet(e, "prompt", prompt)
    e = envSet(e, "promptInput", prefill)
    e = envSet(e, "message", "")
    emit e
}

func _exitPrompt(e) {
    e = envSet(e, "focus", "editor")
    e = envSet(e, "promptKind", "")
    e = envSet(e, "prompt", "")
    e = envSet(e, "promptInput", "")
    emit e
}

func _submitPrompt(e) {
    let kind = envGet(e, "promptKind")
    let inp = envGet(e, "promptInput")
    if kind == "save-as" {
        if inp == "" {
            e = _setMsg(e, "save-as cancelled", "err")
            e = _exitPrompt(e); emit e
        }
        let b = envGet(e, "buf")
        b = envSet(b, "path", inp)
        b = bufSave(b)
        e = envSet(e, "buf", b)
        e = _setMsg(e, "saved " + inp, "ok")
        e = _exitPrompt(e); emit e
    }
    if kind == "open" {
        if inp == "" { e = _exitPrompt(e); emit e }
        e = edOpenBuffer(e, inp)
        e = _setMsg(e, "opened " + inp, "ok")
        e = _exitPrompt(e); emit e
    }
    if kind == "search" {
        if inp == "" { e = _exitPrompt(e); emit e }
        e = envSet(e, "lastSearch", inp)
        let b3 = envGet(e, "buf")
        b3 = bufFind(b3, inp, toInt(envGet(b3, "row")), toInt(envGet(b3, "col")), 1)
        e = envSet(e, "buf", b3)
        e = _setMsg(e, "find: " + inp + " (Ctrl-G next)", "ok")
        e = _exitPrompt(e); emit e
    }
    if kind == "go-to-line" {
        if inp == "" { e = _exitPrompt(e); emit e }
        let b4 = envGet(e, "buf")
        b4 = bufGotoLine(b4, toInt(inp))
        e = envSet(e, "buf", b4)
        e = _exitPrompt(e); emit e
    }
    if kind == "quit-confirm" {
        if inp == "y" || inp == "Y" { e = envSet(e, "running", 0) }
        e = _exitPrompt(e); emit e
    }
    e = _exitPrompt(e); emit e
}

// ── Build / run ─────────────────────────────────────────────────

func _runBuild(e, alsoExecute) {
    let b = envGet(e, "buf")
    let path = envGet(b, "path")
    if path == "" { e = _setMsg(e, "no file path — save first", "err"); emit e }
    if endsWith(path, ".k") != "1" { e = _setMsg(e, "not a .k file", "err"); emit e }
    if toInt(envGet(b, "dirty")) == 1 {
        b = bufSave(b)
        e = envSet(e, "buf", b)
    }
    let bin = "/tmp/_kcode_run_bin"
    let buildOut = _shellCapture("kcc.sh " + path + " -o " + bin)
    let title = "BUILD: " + path
    let body = buildOut
    if alsoExecute == 1 {
        let runOut = _shellCapture("test -x " + bin + " && " + bin + "; echo \"[exit $?]\"")
        body = buildOut + "\n────────── output ──────────\n" + runOut
        title = "BUILD+RUN: " + path
    }
    if body == "" { body = "(no output)" }
    e = envSet(e, "overlay", body)
    e = envSet(e, "overlayTitle", title)
    e = envSet(e, "overlayScroll", 0)
    emit e
}

// ── Key dispatch ────────────────────────────────────────────────

func _confirmQuit(e) {
    let b = envGet(e, "buf")
    if toInt(envGet(b, "dirty")) == 1 {
        e = _enterPrompt(e, "quit-confirm", "unsaved changes — quit anyway? (y/N) ", "")
        emit e
    }
    e = envSet(e, "running", 0)
    emit e
}

func _handleEditorKey(e, k) {
    let b = envGet(e, "buf")
    if k == "LEFT"     { b = bufMoveLeft(b);  e = envSet(e, "buf", b); emit e }
    if k == "RIGHT"    { b = bufMoveRight(b); e = envSet(e, "buf", b); emit e }
    if k == "UP"       { b = bufMoveUp(b);    e = envSet(e, "buf", b); emit e }
    if k == "DOWN"     { b = bufMoveDown(b);  e = envSet(e, "buf", b); emit e }
    if k == "HOME"     { b = bufHome(b);      e = envSet(e, "buf", b); emit e }
    if k == "END"      { b = bufEnd(b);       e = envSet(e, "buf", b); emit e }
    if k == "PAGEUP"   {
        b = bufPageUp(b, toInt(envGet(e, "rows")) - 4)
        e = envSet(e, "buf", b); emit e
    }
    if k == "PAGEDOWN" {
        b = bufPageDown(b, toInt(envGet(e, "rows")) - 4)
        e = envSet(e, "buf", b); emit e
    }
    if k == "BACKSPACE" { b = bufBackspace(b);    e = envSet(e, "buf", b); emit e }
    if k == "DEL"       { b = bufDeleteForward(b); e = envSet(e, "buf", b); emit e }
    if k == "ENTER"     { b = bufInsertNewline(b); e = envSet(e, "buf", b); emit e }
    if k == "TAB"       { b = bufInsertChar(b, "    "); e = envSet(e, "buf", b); emit e }

    if k == "C-q" { e = _confirmQuit(e); emit e }
    if k == "C-s" {
        let p = envGet(b, "path")
        if p == "" { e = _enterPrompt(e, "save-as", "save as: ", ""); emit e }
        b = bufSave(b)
        e = envSet(e, "buf", b)
        e = _setMsg(e, "saved " + p, "ok"); emit e
    }
    if k == "C-o" { e = _enterPrompt(e, "open", "open: ", ""); emit e }
    if k == "C-f" { e = _enterPrompt(e, "search", "find: ", envGet(e, "lastSearch")); emit e }
    if k == "C-g" {
        let needle = envGet(e, "lastSearch")
        if needle == "" { emit e }
        b = bufFind(b, needle, toInt(envGet(b, "row")), toInt(envGet(b, "col")) + 1, 1)
        e = envSet(e, "buf", b)
        e = _setMsg(e, "find next: " + needle, "ok"); emit e
    }
    if k == "C-l" { e = _enterPrompt(e, "go-to-line", "goto line: ", ""); emit e }
    if k == "C-p" { e = _pkOpen(e); emit e }
    if k == "M-n" { e = edCycleBuffer(e, 1);  emit e }
    if k == "M-p" { e = edCycleBuffer(e, 0 - 1); emit e }
    if k == "C-w" {
        let bb = envGet(e, "buf")
        if toInt(envGet(bb, "dirty")) == 1 {
            e = _setMsg(e, "buffer is dirty — save (Ctrl-S) first or undo your changes", "err")
            emit e
        }
        e = edCloseBuffer(e); emit e
    }
    if k == "C-z" { b = bufUndo(b); e = envSet(e, "buf", b); e = _setMsg(e, "undo", ""); emit e }
    if k == "C-y" { b = bufRedo(b); e = envSet(e, "buf", b); e = _setMsg(e, "redo", ""); emit e }
    if k == "C-b" { e = _runBuild(e, 0); emit e }
    if k == "C-r" { e = _runBuild(e, 1); emit e }
    if k == "ESC" { e = envSet(e, "message", ""); emit e }

    // Mouse: scroll wheel works in editor mode regardless of focus.
    if k == "WHEEL-UP" {
        b = bufMoveUp(b); b = bufMoveUp(b); b = bufMoveUp(b)
        e = envSet(e, "buf", b); emit e
    }
    if k == "WHEEL-DOWN" {
        b = bufMoveDown(b); b = bufMoveDown(b); b = bufMoveDown(b)
        e = envSet(e, "buf", b); emit e
    }
    // MOUSE\t<row>\t<col>\t<btn>: position cursor at click target.
    if startsWith(k, "MOUSE\t") == "1" {
        let rows = toInt(envGet(e, "rows"))
        let tab1 = indexOf(k, "\t")
        let rest = substring(k, tab1 + 1, len(k))
        let tab2 = indexOf(rest, "\t")
        let mr = toInt(substring(rest, 0, tab2))
        let rest2 = substring(rest, tab2 + 1, len(rest))
        let tab3 = indexOf(rest2, "\t")
        let mc = toInt(substring(rest2, 0, tab3))
        // Ignore clicks on the status / minibuffer rows.
        if mr < rows - 2 {
            let gutterW = _gutterWidth(b)
            let scrollRow = toInt(envGet(b, "scrollRow"))
            let scrollCol = toInt(envGet(b, "scrollCol"))
            let targetRow = scrollRow + mr
            let nl = bufNumLines(b)
            if targetRow >= nl { targetRow = nl - 1 }
            if targetRow < 0 { targetRow = 0 }
            let targetCol = mc - gutterW + scrollCol
            if targetCol < 0 { targetCol = 0 }
            let ll = bufLineLen(b, targetRow)
            if targetCol > ll { targetCol = ll }
            b = envSet(b, "row", targetRow)
            b = envSet(b, "col", targetCol)
            b = envSet(b, "goalCol", targetCol)
            b = bufMarkBoundary(b)
            e = envSet(e, "buf", b)
        }
        emit e
    }

    if len(k) == 1 {
        let cc = charCode(k)
        if cc >= 32 && cc < 127 {
            b = bufInsertChar(b, k); e = envSet(e, "buf", b); emit e
        }
    } else {
        if charCode(k[0]) >= 128 {
            b = bufInsertChar(b, k); e = envSet(e, "buf", b); emit e
        }
    }
    emit e
}

func _handlePromptKey(e, k) {
    if k == "ESC"       { e = _exitPrompt(e); emit e }
    if k == "ENTER"     { e = _submitPrompt(e); emit e }
    if k == "BACKSPACE" {
        let s = envGet(e, "promptInput")
        if len(s) > 0 { e = envSet(e, "promptInput", substring(s, 0, len(s) - 1)) }
        emit e
    }
    if len(k) == 1 {
        let cc = charCode(k)
        if cc >= 32 && cc < 127 {
            e = envSet(e, "promptInput", envGet(e, "promptInput") + k); emit e
        }
    } else {
        if charCode(k[0]) >= 128 {
            e = envSet(e, "promptInput", envGet(e, "promptInput") + k); emit e
        }
    }
    emit e
}

func _handleOverlayKey(e, k) {
    if k == "ESC" || k == "q" || k == "C-c" {
        e = envSet(e, "overlay", ""); e = envSet(e, "overlayTitle", ""); emit e
    }
    if k == "DOWN" || k == "j" {
        e = envSet(e, "overlayScroll", toInt(envGet(e, "overlayScroll")) + 1); emit e
    }
    if k == "UP" || k == "k" {
        let s = toInt(envGet(e, "overlayScroll")) - 1
        if s < 0 { s = 0 }
        e = envSet(e, "overlayScroll", s); emit e
    }
    if k == "PAGEDOWN" {
        e = envSet(e, "overlayScroll", toInt(envGet(e, "overlayScroll")) + toInt(envGet(e, "rows")) - 4); emit e
    }
    if k == "PAGEUP" {
        let s = toInt(envGet(e, "overlayScroll")) - (toInt(envGet(e, "rows")) - 4)
        if s < 0 { s = 0 }
        e = envSet(e, "overlayScroll", s); emit e
    }
    emit e
}

// ── Main loop ───────────────────────────────────────────────────

func edRun(e) {
    while toInt(envGet(e, "running")) == 1 {
        e = edRender(e)
        let k = tReadKey()
        if k == "EOF" {
            e = envSet(e, "running", 0)
        } else if toInt(envGet(e, "pkOpen")) == 1 {
            e = _handlePickerKey(e, k)
        } else if envGet(e, "overlay") != "" {
            e = _handleOverlayKey(e, k)
        } else if envGet(e, "focus") == "prompt" {
            e = _handlePromptKey(e, k)
        } else {
            e = _handleEditorKey(e, k)
        }
    }
    emit e
}
