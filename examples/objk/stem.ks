// stem v2 — pure-Krypton terminal on objk, term.k grid render. No Obj-C source.
import "k:cocoa"
import "k:objc"
import "head:cocoa"
import "head:objc"

// term.k — stem grid driver (pure Krypton terminal core, phase 4).
//
// Maintains a rows×cols cell grid with a cursor and ACTS on the common VT
// sequences — cursor positioning (CUP/CUU/CUD/CUF/CUB), erase (ED/EL), CR/LF/
// BS/TAB, SGR fg+bg colour, scroll-on-overflow — then renders the grid back to
// text (re-emitting ANSI colour). Krypton port of brain/terk's Grid + applyEscape.
//
// Two representations of state:
//   - one-shot:    renderGrid(s, cols, rows)            -> text
//   - incremental: gridNew(cols,rows) -> state          (a packed string)
//                  gridFeed(state, bytes, cols, rows)   -> state
//                  gridRender(state, cols, rows)        -> text
// The interactive loop keeps `state` across frames and feeds only the new bytes,
// so it never re-processes the whole stream (renderGrid is O(input×gridsize)).
//
// The CHARACTER grid uses 5-byte slots per cell: [width][b0][b1][b2][b3], width
// 1-4 = how many following bytes are the cell's UTF-8 character (rest SOH-padded)
// — so a multi-byte glyph occupies one display column. `attr` (fg) and `battr`
// (bg) grids are 1 byte/cell (SGR colour code, sentinel 1 = default). The packed
// state string is grid+attr+battr+"|"+cr+","+cc+","+pen. Every byte is non-NUL
// (widths 1-4, SOH pad, colour codes >=30, UTF-8 >=0x20, header is ASCII). Uses
// only charCode/substring/len/sbAppend/fromCharCode — verified native builtins
// (k:map is broken on macho). No C, no FFI, no maps.


// _isLetter(code) — CSI final byte is an ASCII letter.
func _isLetter(c) {
    emit (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
}

// _leadInt(s, def) — leading non-negative integer in s; `def` if none.
func _leadInt(s, def) {
    let n = len(s)
    let i = 0
    let v = 0
    let any = 0
    while i < n {
        let c = charCode(substring(s, i, i + 1))
        if c >= 48 && c <= 57 { v = v * 10 + (c - 48)  any = 1  i = i + 1 }
        else { i = n }
    }
    if any == 0 { emit def }
    emit v
}

// _afterSemi(s) — substring after the first ';' (empty if none). For ESC[r;cH.
func _afterSemi(s) {
    let n = len(s)
    let i = 0
    while i < n {
        if charCode(substring(s, i, i + 1)) == 59 { emit substring(s, i + 1, n) }
        i = i + 1
    }
    emit ""
}

// _clamp(v, lo, hi)
func _clamp(v, lo, hi) {
    if v < lo { emit lo }
    if v > hi { emit hi }
    emit v
}

// _cf(s, k) — the k-th comma-separated non-negative integer field of s (0 if none).
func _cf(s, k) {
    let n = len(s)
    let i = 0
    let field = 0
    let v = 0
    while i < n {
        let c = charCode(substring(s, i, i + 1))
        if c == 44 { if field == k { emit v }  field = field + 1  v = 0 }
        else { if c >= 48 && c <= 57 { v = v * 10 + (c - 48) } }
        i = i + 1
    }
    if field == k { emit v }
    emit 0
}

// _fill1(size) — a string of `size` SOH bytes (the default-colour sentinel).
func _fill1(size) {
    let sb = sbNew()
    let one = fromCharCode(1)
    let i = 0
    while i < size { sb = sbAppend(sb, one)  i = i + 1 }
    emit sbToString(sb)
}

// _cellBlank() — one blank char-grid slot: width 1, a space, 3 SOH pad bytes.
func _cellBlank() {
    emit fromCharCode(1) + " " + fromCharCode(1) + fromCharCode(1) + fromCharCode(1)
}

// _blankRow(cols) — `cols` blank char-grid slots (cols*5 bytes).
func _blankRow(cols) {
    let sb = sbNew()
    let b = _cellBlank()
    let i = 0
    while i < cols { sb = sbAppend(sb, b)  i = i + 1 }
    emit sbToString(sb)
}

// _putCell(g, cellIdx, chstr) — store the (1-4 byte) UTF-8 char in slot cellIdx.
func _putCell(g, cellIdx, chstr) {
    let w = len(chstr)
    let pad = ""
    let k = w
    while k < 4 { pad = pad + fromCharCode(1)  k = k + 1 }
    let off = cellIdx * 5
    emit substring(g, 0, off) + fromCharCode(w) + chstr + pad + substring(g, off + 5, len(g))
}

// _put1(g, idx, ch) — replace the 1-byte cell at idx (attr/battr grids).
func _put1(g, idx, ch) {
    emit substring(g, 0, idx) + ch + substring(g, idx + 1, len(g))
}

// _scrollUp(g, stride, gtotal, fillRow) — drop the top row, append a fresh
// bottom row (generic over byte-stride: char grid = cols*5, attr = cols).
func _scrollUp(g, stride, gtotal, fillRow) {
    emit substring(g, stride, gtotal) + fillRow
}

// _applySgr(pen, params) — fold an SGR list (e.g. "1;31;44") into the colour pen
// (fg*256+bg, sentinel 1 each): fg 30-37/39/90-97, bg 40-47/49/100-107.
// _lvl(v) — an 8-bit channel -> nearest xterm-256 cube level (0-5).
func _lvl(v) {
    if v < 48 { emit 0 }
    if v < 115 { emit 1 }
    if v < 155 { emit 2 }
    if v < 195 { emit 3 }
    if v < 235 { emit 4 }
    emit 5
}
// _rgb256(r,g,b) — nearest xterm-256 colour-cube index (16-231). Truecolor
// (38;2/48;2) is folded to 256 so it fits the 1-byte-per-cell colour model.
func _rgb256(r, g, b) {
    emit 16 + 36 * _lvl(r) + 6 * _lvl(g) + _lvl(b)
}

func _applySgr(pen, params) {
    let n = len(params)
    if n == 0 { emit 257 }
    let fg = pen / 256
    let bg = pen - fg * 256
    let i = 0
    let cur = 0
    let any = 0
    // fg/bg encoded as a 256-colour index: 1 = default, 2..255 = index 0..253.
    // stage drives the 38;5;N / 48;5;N (256) and 38;2;r;g;b / 48;2;r;g;b (true-
    // colour) sub-sequences. tr/tg hold r,g while collecting a truecolor triple.
    let stage = 0    // 0 norm; 1 got38; 2 got38;5; 3 got48; 4 got48;5;
                     // 5/6/7 = 38;2 r/g/b ; 8/9/10 = 48;2 r/g/b
    let tr = 0
    let tg = 0
    while i <= n {
        let sep = 0
        if i == n { sep = 1 }
        else { if charCode(substring(params, i, i + 1)) == 59 { sep = 1 } }
        if sep == 1 {
            if any == 1 {
                if stage == 2 { let x = cur  if x > 253 { x = 253 }  fg = x + 2  stage = 0 }
                else { if stage == 4 { let x = cur  if x > 253 { x = 253 }  bg = x + 2  stage = 0 }
                else { if stage == 5 { tr = cur  stage = 6 }
                else { if stage == 6 { tg = cur  stage = 7 }
                else { if stage == 7 { let x = _rgb256(tr, tg, cur)  if x > 253 { x = 253 }  fg = x + 2  stage = 0 }
                else { if stage == 8 { tr = cur  stage = 9 }
                else { if stage == 9 { tg = cur  stage = 10 }
                else { if stage == 10 { let x = _rgb256(tr, tg, cur)  if x > 253 { x = 253 }  bg = x + 2  stage = 0 }
                else { if stage == 1 { if cur == 5 { stage = 2 } else { if cur == 2 { stage = 5 } else { stage = 0 } } }
                else { if stage == 3 { if cur == 5 { stage = 4 } else { if cur == 2 { stage = 8 } else { stage = 0 } } }
                else {
                    if cur == 0 { fg = 1  bg = 1 }
                    if cur == 38 { stage = 1 }
                    if cur == 48 { stage = 3 }
                    if cur == 39 { fg = 1 }
                    if cur >= 30 && cur <= 37 { fg = cur - 28 }      // index 0-7
                    if cur >= 90 && cur <= 97 { fg = cur - 80 }      // index 8-15
                    if cur == 49 { bg = 1 }
                    if cur >= 40 && cur <= 47 { bg = cur - 38 }      // index 0-7
                    if cur >= 100 && cur <= 107 { bg = cur - 90 }    // index 8-15
                } } } } } } } } } }
            }
            cur = 0
            any = 0
        } else {
            let c = charCode(substring(params, i, i + 1))
            if c >= 48 && c <= 57 { cur = cur * 10 + (c - 48)  any = 1 }
        }
        i = i + 1
    }
    emit fg * 256 + bg
}

// _sgrPair(fg, bg) — ANSI to set (fg,bg); 1 = default, else 256-colour index+2.
// Re-emitted as 256-colour so the shim renders the exact palette. Reset-then-set.
func _sgrPair(fg, bg) {
    let e = fromCharCode(27)
    let s = e + "[0m"
    if fg != 1 { s = s + e + "[38;5;" + (fg - 2) + "m" }
    if bg != 1 { s = s + e + "[48;5;" + (bg - 2) + "m" }
    emit s
}

// _utf8Len(c) — byte length of a UTF-8 char from its lead byte (1 if invalid).
func _utf8Len(c) {
    if c >= 240 && c <= 247 { emit 4 }
    if c >= 224 && c <= 239 { emit 3 }
    if c >= 192 && c <= 223 { emit 2 }
    emit 1
}

// gridNew(cols, rows) — a fresh blank packed grid state.
func gridNew(cols, rows) {
    let total = cols * rows
    let grid = _blankRow(cols)
    let rr = 1
    while rr < rows { grid = grid + _blankRow(cols)  rr = rr + 1 }
    emit grid + _fill1(total) + _fill1(total) + "|0,0,257,0,0,257,0,0,0,0,0,0,0,1,0,0,0" + fromCharCode(1) + fromCharCode(1)
}

// gridFeed(state, s, cols, rows) — process byte string s against the packed
// state (cursor/erase/colour/scroll), return the new packed state.
func gridFeed(state, s, cols, rows) {
    let total = cols * rows
    let g5 = 5 * total
    let gtotal = g5
    let stride = cols * 5
    let grid = substring(state, 0, g5)
    let attr = substring(state, g5, g5 + total)
    let battr = substring(state, g5 + total, g5 + 2 * total)
    let tailFull = substring(state, g5 + 2 * total + 1, len(state))
    let sohp = indexOf(tailFull, fromCharCode(1))
    let tail = substring(tailFull, 0, sohp)
    let afterSoh = substring(tailFull, sohp + 1, len(tailFull))   // scrolled <SOH> savedGrids
    let soh2 = indexOf(afterSoh, fromCharCode(1))
    let savedGrids = ""                  // saved MAIN planes while the alt screen is active
    if soh2 >= 0 { savedGrids = substring(afterSoh, soh2 + 1, len(afterSoh)) }
    let cr = _cf(tail, 0)
    let cc = _cf(tail, 1)
    let pen = _cf(tail, 2)
    let scr = _cf(tail, 3)               // saved cursor row (ESC7/ESC8)
    let scc = _cf(tail, 4)               // saved cursor col
    let spen = _cf(tail, 5)              // saved colour pen
    let pw = _cf(tail, 6)                // pending wrap (deferred auto-margin)
    let mlevel = _cf(tail, 8)            // mouse tracking: 0 off, 1 click, 2 drag, 3 any-motion
    let msgr = _cf(tail, 9)              // mouse SGR(1006) encoding on/off (persist)
    let altActive = _cf(tail, 10)        // alt screen (1049/1047/47) currently active
    let savedAltCr = _cf(tail, 11)       // main cursor saved on alt-enter
    let savedAltCc = _cf(tail, 12)
    let cvis = _cf(tail, 13)             // cursor visible (DECSET 25); 0 = hidden
    let cshape = _cf(tail, 14)           // app cursor shape (DECSCUSR): 0 config, 1 bar, 2 block, 3 underline
    let pasteMode = _cf(tail, 15)        // bracketed paste enabled (DECSET 2004)
    let focusMode = _cf(tail, 16)        // focus reporting enabled (DECSET 1004)
    let scrolled = ""                    // rows scrolled off THIS feed (reset each call)
    let bell = 0                         // bare BEL (0x07) seen THIS feed (reset each call)
    let n = len(s)
    let i = 0

    while i < n {
        let c = charCode(substring(s, i, i + 1))

        if c == 27 {                                   // ESC
            if i + 1 >= n { i = n }
            else {
                let k = charCode(substring(s, i + 1, i + 2))
                if k == 91 {                           // '[' → CSI
                    let j = i + 2
                    while j < n && _isLetter(charCode(substring(s, j, j + 1))) == 0 { j = j + 1 }
                    if j >= n { i = n }
                    else {
                        let fin = charCode(substring(s, j, j + 1))
                        let params = substring(s, i + 2, j)
                        let p0 = _leadInt(params, 1)
                        if fin >= 65 && fin <= 72 { pw = 0 }    // any cursor move/CUP clears pending wrap
                        if fin == 72 || fin == 102 {     // 'H'/'f' CUP row;col (1-based)
                            cr = _clamp(p0 - 1, 0, rows - 1)
                            cc = _clamp(_leadInt(_afterSemi(params), 1) - 1, 0, cols - 1)
                        }
                        if fin == 65 { cr = _clamp(cr - p0, 0, rows - 1) }   // up
                        if fin == 66 { cr = _clamp(cr + p0, 0, rows - 1) }   // down
                        if fin == 67 { cc = _clamp(cc + p0, 0, cols - 1) }   // forward
                        if fin == 68 { cc = _clamp(cc - p0, 0, cols - 1) }   // back
                        if fin == 109 { pen = _applySgr(pen, params) }       // 'm' SGR colour
                        if fin == 115 { scr = cr  scc = cc  spen = pen }     // 's' save cursor
                        if fin == 117 { cr = scr  cc = scc  pen = spen }     // 'u' restore cursor
                        if fin == 113 {                  // 'q' DECSCUSR — app cursor shape
                            let ps = _leadInt(params, 0)
                            if ps == 0 { cshape = 0 }                  // reset -> config default
                            if ps == 1 || ps == 2 { cshape = 2 }       // block
                            if ps == 3 || ps == 4 { cshape = 3 }       // underline
                            if ps == 5 || ps == 6 { cshape = 1 }       // bar
                        }
                        if fin == 74 {                   // 'J' erase in display (honour param)
                            let pj = _leadInt(params, 0)
                            let ja = 0
                            let jb = total
                            if pj == 0 { ja = cr * cols + cc }       // cursor → end of screen
                            if pj == 1 { jb = cr * cols + cc + 1 }    // start → cursor
                            // pj >= 2: whole screen
                            let jcnt = jb - ja
                            grid = substring(grid, 0, ja * 5) + _blankRow(jcnt) + substring(grid, ja * 5 + jcnt * 5, gtotal)
                            attr = substring(attr, 0, ja) + _fill1(jcnt) + substring(attr, ja + jcnt, total)
                            battr = substring(battr, 0, ja) + _fill1(jcnt) + substring(battr, ja + jcnt, total)
                            if pj >= 2 { cr = 0  cc = 0 }            // clear-all homes (matches kryofetch)
                        }
                        if fin == 75 {                   // 'K' erase in line (honour param)
                            let pk = _leadInt(params, 0)
                            let a = 0
                            let b = cols
                            if pk == 0 { a = cc }                    // cursor → end
                            if pk == 1 { b = cc + 1 }                // start → cursor
                            // pk == 2 (or other): whole line (a=0, b=cols)
                            let cnt = b - a
                            let o5 = (cr * cols + a) * 5
                            grid = substring(grid, 0, o5) + _blankRow(cnt) + substring(grid, o5 + cnt * 5, gtotal)
                            let o1 = cr * cols + a
                            attr = substring(attr, 0, o1) + _fill1(cnt) + substring(attr, o1 + cnt, total)
                            battr = substring(battr, 0, o1) + _fill1(cnt) + substring(battr, o1 + cnt, total)
                        }
                        if fin == 104 || fin == 108 {    // 'h' DECSET / 'l' DECRST (private '?' modes)
                            if len(params) > 0 && charCode(substring(params, 0, 1)) == 63 {
                                let mode = _leadInt(substring(params, 1, len(params)), 0)
                                let on = 0
                                if fin == 104 { on = 1 }
                                if mode == 1000 { if on == 1 { mlevel = 1 } else { mlevel = 0 } }  // click
                                if mode == 1002 { if on == 1 { mlevel = 2 } else { mlevel = 0 } }  // button-drag
                                if mode == 1003 { if on == 1 { mlevel = 3 } else { mlevel = 0 } }  // any-motion
                                if mode == 1006 { msgr = on }                                      // SGR encoding
                                if mode == 25 { cvis = on }                                        // cursor show/hide
                                if mode == 2004 { pasteMode = on }                                 // bracketed paste
                                if mode == 1004 { focusMode = on }                                 // focus reporting
                                if mode == 1049 || mode == 1047 || mode == 47 {                    // alt screen
                                    if on == 1 {
                                        if altActive == 0 {
                                            savedGrids = grid + attr + battr     // save the main planes
                                            savedAltCr = cr  savedAltCc = cc
                                            grid = _blankRow(total)  attr = _fill1(total)  battr = _fill1(total)
                                            cr = 0  cc = 0  pw = 0
                                            altActive = 1
                                        }
                                    } else {
                                        if altActive == 1 {
                                            grid = substring(savedGrids, 0, g5)             // restore main
                                            attr = substring(savedGrids, g5, g5 + total)
                                            battr = substring(savedGrids, g5 + total, g5 + 2 * total)
                                            cr = savedAltCr  cc = savedAltCc  pw = 0
                                            savedGrids = ""
                                            altActive = 0
                                        }
                                    }
                                }
                            }
                        }
                        i = j + 1
                    }
                } else {
                    if k == 93 {                         // ']' → OSC: skip to BEL/ST
                        let j = i + 2
                        let done = 0
                        while j < n && done == 0 {
                            let cj = charCode(substring(s, j, j + 1))
                            if cj == 7 { done = 1  i = j + 1 }
                            else {
                                if cj == 27 && j + 1 < n && charCode(substring(s, j + 1, j + 2)) == 92 { done = 1  i = j + 2 }
                                else { j = j + 1 }
                            }
                        }
                        if done == 0 { i = n }
                    } else {
                        if k == 55 { scr = cr  scc = cc  spen = pen }    // ESC 7 save cursor
                        if k == 56 { cr = scr  cc = scc  pen = spen }    // ESC 8 restore cursor
                        i = i + 2                        // ESC x (2-byte)
                    }
                }
            }
        } else {
            if c == 10 {                                                         // LF → newline
                cr = cr + 1  cc = 0  pw = 0
                if cr >= rows {
                    if altActive == 0 { scrolled = scrolled + _renderRow(grid, attr, battr, 0, cols) + fromCharCode(10) }
                    grid = _scrollUp(grid, stride, gtotal, _blankRow(cols))
                    attr = _scrollUp(attr, cols, total, _fill1(cols))
                    battr = _scrollUp(battr, cols, total, _fill1(cols))
                    cr = rows - 1
                }
                i = i + 1
            }
            else {
                if c == 13 { cc = 0  pw = 0  i = i + 1 }                         // CR
                else {
                    if c == 8 { if cc > 0 { cc = cc - 1 }  pw = 0  i = i + 1 }   // BS
                    else {
                        if c == 9 {                                              // TAB
                            cc = ((cc / 8) + 1) * 8
                            if cc >= cols { cc = cols - 1 }
                            i = i + 1
                        } else {
                            if c >= 32 {                                         // printable (incl UTF-8)
                                let clen = _utf8Len(c)
                                if i + clen > n { clen = n - i }
                                if pw == 1 {                                     // deferred wrap from last col
                                    cc = 0  cr = cr + 1  pw = 0
                                    if cr >= rows {
                                        if altActive == 0 { scrolled = scrolled + _renderRow(grid, attr, battr, 0, cols) + fromCharCode(10) }
                                        grid = _scrollUp(grid, stride, gtotal, _blankRow(cols))
                                        attr = _scrollUp(attr, cols, total, _fill1(cols))
                                        battr = _scrollUp(battr, cols, total, _fill1(cols))
                                        cr = rows - 1
                                    }
                                }
                                let idx = cr * cols + cc
                                let pfg = pen / 256
                                grid = _putCell(grid, idx, substring(s, i, i + clen))
                                attr = _put1(attr, idx, fromCharCode(pfg))
                                battr = _put1(battr, idx, fromCharCode(pen - pfg * 256))
                                if cc >= cols - 1 { pw = 1 }                     // at last column -> defer wrap
                                else { cc = cc + 1 }
                                i = i + clen
                            } else { if c == 7 { bell = 1 }  i = i + 1 }          // BEL (bell) / other control byte
                        }
                    }
                }
            }
        }
    }

    emit grid + attr + battr + "|" + cr + "," + cc + "," + pen + "," + scr + "," + scc + "," + spen + "," + pw + "," + bell + "," + mlevel + "," + msgr + "," + altActive + "," + savedAltCr + "," + savedAltCc + "," + cvis + "," + cshape + "," + pasteMode + "," + focusMode + fromCharCode(1) + scrolled + fromCharCode(1) + savedGrids
}

// _renderRow(grid, attr, battr, base, cols) — one cell-row (base = row*cols)
// rendered to text: trailing blanks trimmed, fg+bg re-emitted, no trailing \n.
func _renderRow(grid, attr, battr, base, cols) {
    let e = cols
    let trimming = 1
    while e > 0 && trimming == 1 {
        let off = (base + e - 1) * 5
        let w = charCode(substring(grid, off, off + 1))
        if w == 1 && substring(grid, off + 1, off + 2) == " " { e = e - 1 }
        else { trimming = 0 }
    }
    let out = sbNew()
    let lastFg = 1
    let lastBg = 1
    let col = 0
    while col < e {
        let cellFg = charCode(substring(attr, base + col, base + col + 1))
        let cellBg = charCode(substring(battr, base + col, base + col + 1))
        if cellFg != lastFg || cellBg != lastBg {
            out = sbAppend(out, _sgrPair(cellFg, cellBg))
            lastFg = cellFg
            lastBg = cellBg
        }
        let off = (base + col) * 5
        let w = charCode(substring(grid, off, off + 1))
        out = sbAppend(out, substring(grid, off + 1, off + 1 + w))
        col = col + 1
    }
    if lastFg != 1 || lastBg != 1 { out = sbAppend(out, fromCharCode(27) + "[0m") }
    emit sbToString(out)
}

// gridRender(state, cols, rows) — render the packed state to text (rows joined
// by \n, trailing blanks trimmed, fg+bg colour re-emitted as ANSI).
func gridRender(state, cols, rows) {
    let total = cols * rows
    let g5 = 5 * total
    let grid = substring(state, 0, g5)
    let attr = substring(state, g5, g5 + total)
    let battr = substring(state, g5 + total, g5 + 2 * total)
    let out = sbNew()
    let r = 0
    while r < rows {
        out = sbAppend(out, _renderRow(grid, attr, battr, r * cols, cols))
        if r < rows - 1 { out = sbAppend(out, fromCharCode(10)) }
        r = r + 1
    }
    emit sbToString(out)
}

// gridSafeLen(s) — length of the prefix of s safe to feed: excludes a trailing
// INCOMPLETE escape sequence or UTF-8 char. The interactive bridge reads the pty
// in arbitrary chunks that can split a sequence mid-way; feeding the partial
// would corrupt the grid. The caller feeds s[0..gridSafeLen(s)] and carries the
// rest over to prepend to the next chunk.
func gridSafeLen(s) {
    let n = len(s)
    if n == 0 { emit 0 }

    // (1) trailing partial escape: find the last ESC; cut there if incomplete.
    let escCut = n
    let p = n - 1
    let lastEsc = 0 - 1
    while p >= 0 {
        if charCode(substring(s, p, p + 1)) == 27 { lastEsc = p  p = 0 - 1 }
        else { p = p - 1 }
    }
    if lastEsc >= 0 {
        let q = lastEsc + 1
        if q >= n { escCut = lastEsc }                  // lone trailing ESC
        else {
            let k = charCode(substring(s, q, q + 1))
            if k == 91 {                                // CSI: needs a final letter
                let j = q + 1
                let done = 0
                while j < n {
                    if _isLetter(charCode(substring(s, j, j + 1))) == 1 { done = 1  j = n }
                    else { j = j + 1 }
                }
                if done == 0 { escCut = lastEsc }
            }
            if k == 93 {                                // OSC: needs BEL
                let j = q + 1
                let done = 0
                while j < n {
                    if charCode(substring(s, j, j + 1)) == 7 { done = 1  j = n }
                    else { j = j + 1 }
                }
                if done == 0 { escCut = lastEsc }
            }
        }
    }

    // (2) trailing partial UTF-8 char.
    let utfCut = n
    let last = charCode(substring(s, n - 1, n))
    if last >= 192 { utfCut = n - 1 }                   // lead byte at end -> incomplete
    else {
        if last >= 128 {                                // continuation -> find the lead
            let lpos = n - 1
            while lpos > 0 && charCode(substring(s, lpos, lpos + 1)) >= 128 && charCode(substring(s, lpos, lpos + 1)) <= 191 { lpos = lpos - 1 }
            let lead = charCode(substring(s, lpos, lpos + 1))
            if lead >= 192 {
                if lpos + _utf8Len(lead) > n { utfCut = lpos }
            }
        }
    }

    if escCut < utfCut { emit escCut }
    emit utfCut
}

// oscTitle(s, old) — the window title from an OSC 0/2 (`ESC]0;…BEL` / `ESC]2;…`)
// in s, else `old`. Used by the bridge to track the shell-set title.
func oscTitle(s, old) {
    let e = fromCharCode(27)
    let m = indexOf(s, e + "]0;")
    if m < 0 { m = indexOf(s, e + "]2;") }
    if m < 0 { emit old }
    let rest = substring(s, m + 4, len(s))   // after "ESC]N;"
    let bel = indexOf(rest, fromCharCode(7))  // BEL terminator
    let st = indexOf(rest, e + fromCharCode(92))   // or ST (ESC \)
    let stop = bel
    if stop < 0 { stop = st }
    else { if st >= 0 && st < stop { stop = st } }
    if stop < 0 { emit old }                  // incomplete -> keep old
    emit substring(rest, 0, stop)
}

// gridCursor(state, cols, rows) — the cursor position as "row,col" (0-based).
func gridCursor(state, cols, rows) {
    let total = cols * rows
    let tailFull = substring(state, 7 * total + 1, len(state))
    let tail = substring(tailFull, 0, indexOf(tailFull, fromCharCode(1)))
    if _cf(tail, 13) == 0 { emit "9999,0" }      // cursor hidden (DECSET 25 off)
    emit _cf(tail, 0) + "," + _cf(tail, 1)
}

// gridMouse(state, cols, rows) — "mlevel,msgr": the app's mouse tracking level
// (0 off / 1 click / 2 drag / 3 any-motion) and SGR(1006) encoding flag.
func gridMouse(state, cols, rows) {
    let total = cols * rows
    let tailFull = substring(state, 7 * total + 1, len(state))
    let sohp = indexOf(tailFull, fromCharCode(1))
    let tail = substring(tailFull, 0, sohp)
    emit _cf(tail, 8) + "," + _cf(tail, 9)
}

// gridShape(state, cols, rows) — app-requested cursor shape (DECSCUSR):
// 0 = use config default, 1 = bar, 2 = block, 3 = underline.
func gridShape(state, cols, rows) {
    let total = cols * rows
    let tailFull = substring(state, 7 * total + 1, len(state))
    let tail = substring(tailFull, 0, indexOf(tailFull, fromCharCode(1)))
    emit _cf(tail, 14)
}

// gridPaste(state, cols, rows) — 1 if the app enabled bracketed paste (DECSET 2004).
func gridPaste(state, cols, rows) {
    let total = cols * rows
    let tailFull = substring(state, 7 * total + 1, len(state))
    let tail = substring(tailFull, 0, indexOf(tailFull, fromCharCode(1)))
    emit _cf(tail, 15)
}

// gridAlt(state, cols, rows) — 1 if the alternate screen is active.
func gridAlt(state, cols, rows) {
    let total = cols * rows
    let tailFull = substring(state, 7 * total + 1, len(state))
    let tail = substring(tailFull, 0, indexOf(tailFull, fromCharCode(1)))
    emit _cf(tail, 10)
}

// gridFocus(state, cols, rows) — 1 if the app enabled focus reporting (DECSET 1004).
func gridFocus(state, cols, rows) {
    let total = cols * rows
    let tailFull = substring(state, 7 * total + 1, len(state))
    let tail = substring(tailFull, 0, indexOf(tailFull, fromCharCode(1)))
    emit _cf(tail, 16)
}

// gridBell(state, cols, rows) — 1 if a bare BEL (0x07) arrived during the last
// gridFeed, else 0. The bridge raises a one-shot bell from this.
func gridBell(state, cols, rows) {
    let total = cols * rows
    let tailFull = substring(state, 7 * total + 1, len(state))
    let sohp = indexOf(tailFull, fromCharCode(1))
    emit _cf(substring(tailFull, 0, sohp), 7)
}

// gridScrolled(state, cols, rows) — the rows that scrolled off the top during the
// last gridFeed (rendered text, one per \n). Empty if nothing scrolled. The
// bridge drains this into its scrollback history.
func gridScrolled(state, cols, rows) {
    let total = cols * rows
    let tailFull = substring(state, 7 * total + 1, len(state))
    let sohp = indexOf(tailFull, fromCharCode(1))
    let afterSoh = substring(tailFull, sohp + 1, len(tailFull))   // scrolled <SOH> savedGrids
    let soh2 = indexOf(afterSoh, fromCharCode(1))
    if soh2 >= 0 { emit substring(afterSoh, 0, soh2) }            // just the scrolled part
    emit afterSoh
}

// _stripSgrLine(s) — drop ESC[…<final> sequences so a line is searchable plain text.
func _stripSgrLine(s) {
    let out = sbNew()
    let i = 0
    let n = len(s)
    while i < n {
        let c = charCode(substring(s, i, i + 1))
        if c == 27 {
            i = i + 1
            if i < n && charCode(substring(s, i, i + 1)) == 91 { i = i + 1 }   // '['
            let done = 0
            while i < n && done == 0 {
                let k = charCode(substring(s, i, i + 1))
                i = i + 1
                if k >= 64 && k <= 126 { done = 1 }                            // CSI final byte
            }
        } else {
            out = sbAppend(out, substring(s, i, i + 1))
            i = i + 1
        }
    }
    emit sbToString(out)
}

// gridFind(scrollback, gridText, rows, query, matchIdx) — find the matchIdx-th
// occurrence of query (counting from the most recent line up), wrapping. Returns
// "scrollOff,matchRow,matchCol,matchLen" to bring it into view + highlight it, or
// "-1,-1,-1,-1" if no match / empty query.
func gridFind(scrollback, gridText, rows, query, matchIdx) {
    if len(query) == 0 { emit "-1,-1,-1,-1,0,0" }
    let combined = scrollback + gridText
    let nLines = lineCount(combined)
    let total = 0
    let li = nLines - 1
    while li >= 0 {
        if indexOf(_stripSgrLine(getLine(combined, li)), query) >= 0 { total = total + 1 }
        li = li - 1
    }
    if total == 0 { emit "-1,-1,-1,-1,0,0" }
    let mi = matchIdx
    while mi >= total { mi = mi - total }
    while mi < 0 { mi = mi + total }
    let seen = 0
    let foundLine = 0 - 1
    let foundCol = 0
    li = nLines - 1
    while li >= 0 && foundLine < 0 {
        let pos = indexOf(_stripSgrLine(getLine(combined, li)), query)
        if pos >= 0 {
            if seen == mi { foundLine = li  foundCol = pos }
            seen = seen + 1
        }
        li = li - 1
    }
    // Place the match ~1/3 down the view. NOTE: macho integer subtraction
    // underflows unsigned, so a-b is only safe when a>b — guard every step.
    let smax = 0
    if nLines > rows { smax = nLines - rows }
    let third = rows / 3
    let viewStart = 0
    if foundLine > third { viewStart = foundLine - third }
    if viewStart > smax { viewStart = smax }
    let scrollOff = 0
    if smax > viewStart { scrollOff = smax - viewStart }
    let matchRow = 0
    if foundLine > viewStart { matchRow = foundLine - viewStart }
    emit scrollOff + "," + matchRow + "," + foundCol + "," + len(query) + "," + (mi + 1) + "," + total
}

// gridScrollView(scrollback, gridText, rows, scrollOff) — `rows` lines of the
// combined (scrollback ++ live grid) buffer, scrolled `scrollOff` lines up from
// the bottom. scrollOff 0 = the live screen.
func gridScrollView(scrollback, gridText, rows, scrollOff) {
    let combined = scrollback + gridText
    let nLines = lineCount(combined)
    let start = nLines - rows - scrollOff
    if start < 0 { start = 0 }
    let out = sbNew()
    let i = 0
    while i < rows {
        let li = start + i
        if li >= 0 && li < nLines { out = sbAppend(out, getLine(combined, li)) }
        if i < rows - 1 { out = sbAppend(out, fromCharCode(10)) }
        i = i + 1
    }
    emit sbToString(out)
}

// renderGrid(s, cols, rows) — one-shot: feed s into a fresh grid, render to text.
func renderGrid(s, cols, rows) {
    emit gridRender(gridFeed(gridNew(cols, rows), s, cols, rows), cols, rows)
}

// ── objk GUI over the term.k grid ──────────────────────────────────────
func appH() { emit msg(cls("NSApplication"), "sharedApplication") }
func acceptsFR(self, cmd) { emit 1 }
func isDarkMode(app) { emit indexOf(msg(msg(msg(app, "effectiveAppearance"), "name"), "UTF8String"), "Dark") >= 0 }
func isCsiFinal(ch) { emit indexOf("@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~", ch) >= 0 }

// Raw key -> pty (arrows -> ESC[ABCD).
func onKey(self, cmd, event) {
  let pf = cocoaGetAssocKey(self, "ptyfd")
  let m = cocoaNumberVal(cocoaGetAssocKey(appH(), "stem.master"))
  if pf != 0 { m = cocoaNumberVal(pf) }
  cocoaSetAssocKey(appH(), "stem.focusidx", cocoaGetAssocKey(self, "paneidx"))
  let esc = fromCharCode(27)
  let kc = msg(event, "keyCode")
  let seq = ""
  if kc == 126 { seq = esc + "[A" }
  if kc == 125 { seq = esc + "[B" }
  if kc == 124 { seq = esc + "[C" }
  if kc == 123 { seq = esc + "[D" }
  if seq == "" { seq = msg(msg(event, "characters"), "UTF8String") }
  fdWrite(m, seq, len(seq))
}

// xterm-256 cube channel level (0->0, 1..5 -> 95,135,175,215,255).
func cubeLvl(v) { if v == 0 { emit 0 }  emit v * 40 + 55 }

// True 256-colour index -> NSColor (exact RGB): 0-15 ANSI palette, 16-231 the
// 6x6x6 cube, 232-255 greyscale ramp.
// ── config (~/.config/stem/config, simple key = value) ─────────────────
func cfgVal(cfg, key, def) {
  let n = len(cfg)  let i = 0  let ls = 0
  while i <= n {
    let brk = 0
    if i == n { brk = 1 }
    if brk == 0 { if cfg[i] == "\n" { brk = 1 } }
    if brk == 1 {
      let line = trim(substring(cfg, ls, i))
      let eq = indexOf(line, "=")
      if eq > 0 { if trim(substring(line, 0, eq)) == key { emit trim(substring(line, eq + 1, len(line))) } }
      ls = i + 1
    }
    i = i + 1
  }
  emit def
}
func hexNib(c) { emit indexOf("0123456789abcdef", toLower(c)) }
func hexByte(s, i) { emit hexNib(substring(s, i, i + 1)) * 16 + hexNib(substring(s, i + 1, i + 2)) }
// config colour (#RRGGBB) or fallback RGB.
func cfgRGB(cfg, key, r, g, b) {
  let v = cfgVal(cfg, key, "")
  if indexOf(v, "#") == 0 { emit cocoaRGB(hexByte(v, 1), hexByte(v, 3), hexByte(v, 5)) }
  emit cocoaRGB(r, g, b)
}
// palette lookup (built once into stem.pal; colours 0-15 overridable via config).
func color256(n) { emit cocoaArrayGet(cocoaGetAssocKey(appH(), "stem.pal"), n) }

func color256def(n) {
  if n == 0  { emit cocoaRGB(0, 0, 0) }
  if n == 1  { emit cocoaRGB(205, 49, 49) }
  if n == 2  { emit cocoaRGB(13, 188, 121) }
  if n == 3  { emit cocoaRGB(229, 229, 16) }
  if n == 4  { emit cocoaRGB(36, 114, 200) }
  if n == 5  { emit cocoaRGB(188, 63, 188) }
  if n == 6  { emit cocoaRGB(17, 168, 205) }
  if n == 7  { emit cocoaRGB(229, 229, 229) }
  if n == 8  { emit cocoaRGB(102, 102, 102) }
  if n == 9  { emit cocoaRGB(241, 76, 76) }
  if n == 10 { emit cocoaRGB(35, 209, 139) }
  if n == 11 { emit cocoaRGB(245, 245, 67) }
  if n == 12 { emit cocoaRGB(59, 142, 234) }
  if n == 13 { emit cocoaRGB(214, 112, 214) }
  if n == 14 { emit cocoaRGB(41, 184, 219) }
  if n == 15 { emit cocoaRGB(255, 255, 255) }
  if n >= 232 { let g = (n - 232) * 10 + 8  emit cocoaRGB(g, g, g) }
  let i = n - 16
  emit cocoaRGB(cubeLvl((i / 36) % 6), cubeLvl((i / 6) % 6), cubeLvl(i % 6))
}

// One ESC[...m body -> new fg colour (0 reset; 38;5;N -> 256; bg/other kept).
// 256 index from a "38;5;N" / "48;5;N" body (after the 5-char prefix).
func sgrIndex(body) {
  let rest = substring(body, 5, len(body))
  let semi = indexOf(rest, ";")
  if semi >= 0 { emit toInt(substring(rest, 0, semi)) }
  emit toInt(rest)
}

func appendRunTo(acc, text, fg, bg, font) {
  if len(text) == 0 { emit "1" }
  let start = msg(acc, "length")
  msg_1(acc, "appendAttributedString:", msg_1(msg(cls("NSAttributedString"), "alloc"), "initWithString:", nsString(text)))
  let span = msg(acc, "length") - start
  msg_4(acc, "addAttribute:value:range:", nsString("NSColor"), fg, start, span)
  msg_4(acc, "addAttribute:value:range:", nsString("NSFont"), font, start, span)
  if bg != 0 { msg_4(acc, "addAttribute:value:range:", nsString("NSBackgroundColor"), bg, start, span) }
  emit "1"
}

// Parse a gridRender snapshot (text + ESC[..m) -> a coloured NSMutableAttributedString.
// Tracks fg (NSColor) + bg (NSBackgroundColor, 0 = none) so powerline segments fill.
func renderSnapshot(snap, deflt, font, cr, cc) {
  let acc = msg(msg(cls("NSMutableAttributedString"), "alloc"), "init")
  let esc = fromCharCode(27)
  let nl = fromCharCode(10)
  let n = len(snap)
  let i = 0
  let run = ""
  let fg = deflt
  let bg = 0
  let vrow = 0
  let vcol = 0
  let curStart = 0 - 1
  while i < n {
    let c = snap[i]
    if c == esc {
      if len(run) > 0 { appendRunTo(acc, run, fg, bg, font)  run = "" }
      i = i + 1
      if i < n {
        if snap[i] == "[" {
          i = i + 1
          let body = ""
          let done = 0
          while done == 0 {
            if i >= n { done = 1 }
            if done == 0 {
              let ch = snap[i]
              i = i + 1
              if isCsiFinal(ch) {
                if ch == "m" {
                  if body == "0" { fg = deflt  bg = 0 }
                  if indexOf(body, "38;5;") == 0 { fg = color256(sgrIndex(body)) }
                  if indexOf(body, "48;5;") == 0 { bg = color256(sgrIndex(body)) }
                }
                done = 1
              }
              if done == 0 { body = body + ch }
            }
          }
        }
      }
    } else {
      if c == nl { run = run + c  vrow = vrow + 1  vcol = 0  i = i + 1 }
      else {
        let cont = 0
        let code = charCode(c)
        if code >= 128 { if code < 192 { cont = 1 } }
        let isCur = 0
        if cont == 0 { if vrow == cr { if vcol == cc { isCur = 1 } } }
        if isCur == 1 {
          if len(run) > 0 { appendRunTo(acc, run, fg, bg, font)  run = "" }
          appendRunTo(acc, "▏", fg, bg, font)
          curStart = 0
        } else { run = run + c }
        if cont == 0 { vcol = vcol + 1 }
        i = i + 1
      }
    }
  }
  if len(run) > 0 { appendRunTo(acc, run, fg, bg, font)  run = "" }
  // vertical bar cursor (ghostty-style). If not already drawn in-loop (curStart>=0),
  // the cursor was at end-of-line and got trimmed out of gridRender — pad to its
  // column on its row, draw the bar.
  if curStart < 0 {
    if vrow == cr {
      if cc >= vcol {
      let pad = ""
      let k = vcol
      while k < cc { pad = pad + " "  k = k + 1 }
      if len(pad) > 0 { appendRunTo(acc, pad, fg, bg, font) }
      appendRunTo(acc, "▏", fg, bg, font)
      }
    }
  }
  emit acc
}

// ── menu handlers ───────────────────────────────────────────────────────
func stemMaster() { emit cocoaNumberVal(cocoaGetAssocKey(appH(), "stem.master")) }
func onStemNewWin(self, cmd, sender) { exec("open -na stem")  emit "1" }
func onStemClear(self, cmd, sender)  { fdWrite(stemMaster(), fromCharCode(12), 1)  emit "1" }
func onStemPaste(self, cmd, sender)  { let s = exec("pbpaste")  fdWrite(stemMaster(), s, len(s))  emit "1" }
func onStemReset(self, cmd, sender)  { let s = "reset\n"  fdWrite(stemMaster(), s, len(s))  emit "1" }
func stemApplyFont() {
  let app = appH()
  let sz = cocoaNumberVal(cocoaGetAssocKey(app, "stem.fontsize"))
  let mono = cocoaFontFamily(cocoaMonoFont(sz), msg(cocoaGetAssocKey(app, "stem.fontfam"), "UTF8String"))
  cocoaSetAssocKey(app, "stem.mono", mono)
  cocoaSetFont(cocoaGetAssocKey(app, "stem.view"), mono)
  emit "1"
}
func onStemZoomIn(self, cmd, sender)    { let s = cocoaNumberVal(cocoaGetAssocKey(appH(), "stem.fontsize")) + 1  if s > 40 { s = 40 }  cocoaSetAssocKey(appH(), "stem.fontsize", cocoaNumber(s))  stemApplyFont() }
func onStemZoomOut(self, cmd, sender)   { let s = cocoaNumberVal(cocoaGetAssocKey(appH(), "stem.fontsize")) - 1  if s < 7 { s = 7 }  cocoaSetAssocKey(appH(), "stem.fontsize", cocoaNumber(s))  stemApplyFont() }
func onStemZoomReset(self, cmd, sender) { cocoaSetAssocKey(appH(), "stem.fontsize", cocoaNumber(13))  stemApplyFont() }
func onStemFull(self, cmd, sender)      { msg_1(cocoaGetAssocKey(appH(), "stem.win"), "toggleFullScreen:", 0)  emit "1" }
func onStemHelp(self, cmd, sender)      { exec("open https://krypton-lang.org/programs/stem.html")  emit "1" }
func onStemConfig(self, cmd, sender)    { exec("open -t \"" + environ("HOME") + "/.config/stem/config\"")  emit "1" }
func onStemReload(self, cmd, sender) {
  let cfg = readFile(environ("HOME") + "/.config/stem/config")
  cocoaSetAssocKey(appH(), "stem.fontsize", cocoaNumber(toInt(cfgVal(cfg, "font_size", "13"))))
  cocoaSetAssocKey(appH(), "stem.fontfam", nsString(cfgVal(cfg, "font", "JetBrainsMono Nerd Font Mono")))
  stemApplyFont()
  msg_1(cocoaGetAssocKey(appH(), "stem.win"), "setTitle:", nsString(cfgVal(cfg, "title", "stem")))
  emit "1"
}
func onStemAbout(self, cmd, sender) { exec("osascript -e 'display dialog \"stem " + fromCharCode(8212) + " a pure-Krypton terminal on the objk Objective-C FFI. No Obj-C source.\\n\\nkrypton-lang.org/programs/stem.html\" buttons {\"OK\"} default button \"OK\" with title \"About stem\"' >/dev/null 2>&1 &")  emit "1" }
// strip ANSI CSI sequences for plain-text copy
func stemStripAnsi(s) {
  let out = ""
  let n = len(s)
  let i = 0
  let esc = fromCharCode(27)
  while i < n {
    let ch = substring(s, i, i + 1)
    if ch == esc {
      i = i + 1
      if i < n { if substring(s, i, i + 1) == "[" {
        i = i + 1
        let go = 1
        while go == 1 {
          if i >= n { go = 0 }
          else { let c = charCode(substring(s, i, i + 1))  i = i + 1  if c >= 64 { if c <= 126 { go = 0 } } }
        }
      } }
    } else { out = out + ch  i = i + 1 }
  }
  emit out
}
func onStemCopy(self, cmd, sender) {
  let r = cocoaGetAssocKey(appH(), "stem.lastrender")
  if r == 0 { emit "1" }
  writeFile("/tmp/stemcopy", stemStripAnsi(msg(r, "UTF8String")))
  exec("pbcopy < /tmp/stemcopy")
  emit "1"
}
func onStemUpdate(self, cmd, sender) {
  exec("(brew update >/dev/null 2>&1; if brew outdated --cask t3m3d/krypton/stem | grep -q stem; then brew upgrade --cask t3m3d/krypton/stem >/dev/null 2>&1 && osascript -e 'display notification \"Updated stem to the latest version.\" with title \"stem\"'; else osascript -e 'display notification \"stem is up to date.\" with title \"stem\"'; fi) &")
  emit "1"
}
func onStemSecure(self, cmd, sender) {
  let cur = brainFlagS("stem.secure", 0)
  let nv = 1
  if cur == 1 { nv = 0 }
  cocoaSetAssocKey(appH(), "stem.secure", cocoaNumber(nv))
  msg_1(sender, "setState:", nv)
  emit "1"
}
func onStemDefault(self, cmd, sender) {
  exec("osascript -e 'display dialog \"macOS has no single default-terminal setting. To open shell scripts (.command/.tool) with stem, right-click one " + fromCharCode(8594) + " Get Info " + fromCharCode(8594) + " Open with: stem " + fromCharCode(8594) + " Change All.\" buttons {\"OK\"} default button \"OK\" with title \"Make stem Default Terminal\"' >/dev/null 2>&1 &")
  emit "1"
}
func brainFlagS(key, def) {
  let v = cocoaGetAssocKey(appH(), key)
  if v == 0 { emit def }
  emit cocoaNumberVal(v)
}

// ── panes / splits (2-pane) ─────────────────────────────────────────────
func stemKeyClass() {
  let c = objc_lookUpClass("StemKeys")
  if c == 0 {
    c = cocoaViewClassNew("StemKeys")
    cocoaClassAddMethod(c, "keyDown:", funcptr(onKey), "v@:@")
    cocoaClassAddMethod(c, "mouseDown:", funcptr(onMouse), "v@:@")
    cocoaClassAddMethod(c, "acceptsFirstResponder", funcptr(acceptsFR), "c@:")
    cocoaClassRegister(c)
  }
  emit c
}
func stemForkPty(pcols, prows, shell) {
  let m = ptyMaster("/dev/ptmx")
  let slave = ptySlaveName(m)
  ptyForkExec(slave, shell)
  let tries = 0
  let szd = 0
  while tries < 60 {
    if szd == 0 { if ptySetSize(m, prows, pcols) == 0 { szd = 1 } else { sleepUs(0, 10000)  tries = tries + 1 } }
    else { tries = 60 }
  }
  fdSetNonblock(m)
  // env + login handled by the wrapper script we exec (see just-run); nothing
  // typed into the pty, so the prompt comes up clean.
  emit m
}
func stemMakePaneView(m, x, y, w, h, pcols, prows) {
  let app = appH()
  let win = cocoaGetAssocKey(app, "stem.win")
  let view = cocoaScrollText(win, x, y, w, h)
  msg_1(view, "setEditable:", 0)
  msg_1(view, "setSelectable:", 0)
  cocoaSetFont(view, cocoaGetAssocKey(app, "stem.mono"))
  cocoaSetBg(view, cocoaGetAssocKey(app, "stem.bgc"))
  cocoaSetTextColor(view, cocoaGetAssocKey(app, "stem.fgc"))
  let kview = cocoaCustomView(win, stemKeyClass(), x, y, w, h)
  cocoaSetAssocKey(kview, "ptyfd", cocoaNumber(m))
  cocoaSetAssocKey(kview, "paneidx", cocoaNumber(cocoaArrayCount(cocoaGetAssocKey(app, "stem.pkviews"))))
  cocoaArrayAdd(cocoaGetAssocKey(app, "stem.pmasters"), cocoaNumber(m))
  cocoaArrayAdd(cocoaGetAssocKey(app, "stem.pscrolls"), msg(view, "enclosingScrollView"))
  cocoaArrayAdd(cocoaGetAssocKey(app, "stem.pviews"), msg(view, "textStorage"))
  cocoaArrayAdd(cocoaGetAssocKey(app, "stem.pdocs"), view)
  cocoaArrayAdd(cocoaGetAssocKey(app, "stem.pcols"), cocoaNumber(pcols))
  cocoaArrayAdd(cocoaGetAssocKey(app, "stem.prows"), cocoaNumber(prows))
  cocoaArrayAdd(cocoaGetAssocKey(app, "stem.pkviews"), kview)
  emit kview
}
func paneCount() { emit cocoaArrayCount(treeLeaves()) }
// set pane idx's frame + pty size + stored cols/rows
func setPane(idx, x, y, w, h) {
  let app = appH()
  let W = cocoaNumberVal(cocoaGetAssocKey(app, "stem.w"))
  let H = cocoaNumberVal(cocoaGetAssocKey(app, "stem.h"))
  let C = cocoaNumberVal(cocoaGetAssocKey(app, "stem.cols"))
  let R = cocoaNumberVal(cocoaGetAssocKey(app, "stem.rows"))
  let pcols = (C * w) / W
  let prows = (R * h) / H
  if pcols < 4 { pcols = 4 }
  if prows < 2 { prows = 2 }
  msg_frame(cocoaArrayGet(cocoaGetAssocKey(app, "stem.pscrolls"), idx), "setFrame:", x, y, w, h)
  msg_frame(cocoaArrayGet(cocoaGetAssocKey(app, "stem.pkviews"), idx), "setFrame:", x, y, w, h)
  ptySetSize(cocoaNumberVal(cocoaArrayGet(cocoaGetAssocKey(app, "stem.pmasters"), idx)), prows, pcols)
  cocoaArraySet(cocoaGetAssocKey(app, "stem.pcols"), idx, cocoaNumber(pcols))
  cocoaArraySet(cocoaGetAssocKey(app, "stem.prows"), idx, cocoaNumber(prows))
  emit "1"
}
// ── split tree ──────────────────────────────────────────────────────────
// node = NSArray. leaf: [0, paneIdx]. split: [1, axis, childA, childB]
// (axis 1 = side-by-side columns, 2 = stacked rows; A = left/top, B = right/bottom)
func mkLeaf(idx) { let a = cocoaArray()  cocoaArrayAdd(a, cocoaNumber(0))  cocoaArrayAdd(a, cocoaNumber(idx))  emit a }
func mkSplit(axis, na, nb) { let a = cocoaArray()  cocoaArrayAdd(a, cocoaNumber(1))  cocoaArrayAdd(a, cocoaNumber(axis))  cocoaArrayAdd(a, na)  cocoaArrayAdd(a, nb)  emit a }
func nodeType(n) { emit cocoaNumberVal(cocoaArrayGet(n, 0)) }
func leafIdx(n)  { emit cocoaNumberVal(cocoaArrayGet(n, 1)) }
func splitAxis(n){ emit cocoaNumberVal(cocoaArrayGet(n, 1)) }
func splitA(n)   { emit cocoaArrayGet(n, 2) }
func splitB(n)   { emit cocoaArrayGet(n, 3) }
func layoutTree(n, x, y, w, h) {
  if nodeType(n) == 0 { setPane(leafIdx(n), x, y, w, h)  emit "1" }
  if splitAxis(n) == 1 { layoutTree(splitA(n), x, y, w / 2, h)  layoutTree(splitB(n), x + w / 2, y, w / 2, h) }
  else { layoutTree(splitA(n), x, y + h / 2, w, h / 2)  layoutTree(splitB(n), x, y, w, h / 2) }
  emit "1"
}
func splitTree(n, target, axis, newIdx, before) {
  if nodeType(n) == 0 {
    if leafIdx(n) == target {
      if before == 1 { emit mkSplit(axis, mkLeaf(newIdx), mkLeaf(target)) }
      emit mkSplit(axis, mkLeaf(target), mkLeaf(newIdx))
    }
    emit n
  }
  emit mkSplit(splitAxis(n), splitTree(splitA(n), target, axis, newIdx, before), splitTree(splitB(n), target, axis, newIdx, before))
}
func closeTree(n, target) {
  if nodeType(n) == 0 { emit n }
  let a = splitA(n)
  let b = splitB(n)
  if nodeType(a) == 0 { if leafIdx(a) == target { emit b } }
  if nodeType(b) == 0 { if leafIdx(b) == target { emit a } }
  emit mkSplit(splitAxis(n), closeTree(a, target), closeTree(b, target))
}
func collectLeaves(n, arr) {
  if nodeType(n) == 0 { cocoaArrayAdd(arr, cocoaNumber(leafIdx(n)))  emit "1" }
  collectLeaves(splitA(n), arr)
  collectLeaves(splitB(n), arr)
  emit "1"
}
func treeLeaves() { let a = cocoaArray()  collectLeaves(cocoaGetAssocKey(appH(), "stem.tree"), a)  emit a }
func nextFreeIdx() {
  let leaves = treeLeaves()
  let n = cocoaArrayCount(leaves)
  let i = 0
  while i < 4 {
    let used = 0
    let j = 0
    while j < n { if cocoaNumberVal(cocoaArrayGet(leaves, j)) == i { used = 1 }  j = j + 1 }
    if used == 0 { emit i }
    i = i + 1
  }
  emit 0 - 1
}
// lay out the tree + show its leaves, hide the rest
func retile(axis) {
  let app = appH()
  let W = cocoaNumberVal(cocoaGetAssocKey(app, "stem.w"))
  let H = cocoaNumberVal(cocoaGetAssocKey(app, "stem.h"))
  layoutTree(cocoaGetAssocKey(app, "stem.tree"), 0, 0, W, H)
  let leaves = treeLeaves()
  let ln = cocoaArrayCount(leaves)
  let scrolls = cocoaGetAssocKey(app, "stem.pscrolls")
  let kviews = cocoaGetAssocKey(app, "stem.pkviews")
  let i = 0
  while i < 4 {
    let vis = 0
    let j = 0
    while j < ln { if cocoaNumberVal(cocoaArrayGet(leaves, j)) == i { vis = 1 }  j = j + 1 }
    let hid = 1
    if vis == 1 { hid = 0 }
    msg_1(cocoaArrayGet(scrolls, i), "setHidden:", hid)
    msg_1(cocoaArrayGet(kviews, i), "setHidden:", hid)
    i = i + 1
  }
  // repaint each visible pane's prompt at its new size (the grid was rebuilt)
  let masters = cocoaGetAssocKey(app, "stem.pmasters")
  let k = 0
  while k < ln { fdWrite(cocoaNumberVal(cocoaArrayGet(masters, cocoaNumberVal(cocoaArrayGet(leaves, k)))), fromCharCode(12), 1)  k = k + 1 }
  cocoaSetAssocKey(app, "stem.splitdirty", cocoaNumber(1))
  emit "1"
}
// dir: 1=right 2=left 3=top 4=bottom — splits ONLY the focused pane (nested)
func doSplit(dir) {
  let app = appH()
  let newIdx = nextFreeIdx()
  if newIdx < 0 { emit "1" }
  let fIdx = focusedIdx()
  let axis = 1
  if dir >= 3 { axis = 2 }
  let before = 0
  if dir == 2 { before = 1 }
  if dir == 3 { before = 1 }
  cocoaSetAssocKey(app, "stem.tree", splitTree(cocoaGetAssocKey(app, "stem.tree"), fIdx, axis, newIdx, before))
  retile(1)
  cocoaSetAssocKey(app, "stem.focusidx", cocoaNumber(newIdx))
  cocoaMakeFirstResponder(cocoaGetAssocKey(app, "stem.win"), cocoaArrayGet(cocoaGetAssocKey(app, "stem.pkviews"), newIdx))
  emit "1"
}
func onSplitRight(self, cmd, sender)  { doSplit(1)  emit "1" }
func onSplitLeft(self, cmd, sender)   { doSplit(2)  emit "1" }
func onSplitTop(self, cmd, sender)    { doSplit(3)  emit "1" }
func onSplitBottom(self, cmd, sender) { doSplit(4)  emit "1" }
func focusedIdx() {
  let f = cocoaGetAssocKey(appH(), "stem.focusidx")
  if f == 0 { emit 0 }
  emit cocoaNumberVal(f)
}
// click a pane -> focus it (so the next split targets it)
func onMouse(self, cmd, event) {
  cocoaSetAssocKey(appH(), "stem.focusidx", cocoaGetAssocKey(self, "paneidx"))
  cocoaMakeFirstResponder(cocoaGetAssocKey(appH(), "stem.win"), self)
  emit "1"
}
func onNewTab(self, cmd, sender)  { exec("open -na stem")  emit "1" }
func onCloseAll(self, cmd, sender){ msg(appH(), "terminate:")  emit "1" }
// close focused pane; if last pane, close the window
func onClosePane(self, cmd, sender) {
  let app = appH()
  if cocoaArrayCount(treeLeaves()) <= 1 { msg_1(cocoaGetAssocKey(app, "stem.win"), "performClose:", 0)  emit "1" }
  cocoaSetAssocKey(app, "stem.tree", closeTree(cocoaGetAssocKey(app, "stem.tree"), focusedIdx()))
  retile(1)
  let firstIdx = cocoaNumberVal(cocoaArrayGet(treeLeaves(), 0))
  cocoaSetAssocKey(app, "stem.focusidx", cocoaNumber(firstIdx))
  cocoaMakeFirstResponder(cocoaGetAssocKey(app, "stem.win"), cocoaArrayGet(cocoaGetAssocKey(app, "stem.pkviews"), firstIdx))
  emit "1"
}

func defaultConfig() {
  emit "# stem config — key = value, # comments. Restart stem to apply.\nshell = /bin/zsh\nfont = JetBrainsMono Nerd Font Mono\nfont_size = 13\ncols = 92\nrows = 28\nwidth = 760\nheight = 500\ntitle = stem\n# colours as #RRGGBB\nfg = #ffffff\nbg = #000000\ncolor0 = #000000\ncolor1 = #cd3131\ncolor2 = #0dbc79\ncolor3 = #e5e510\ncolor4 = #2472c8\ncolor5 = #bc3fbc\ncolor6 = #11a8cd\ncolor7 = #e5e5e5\ncolor8 = #666666\ncolor9 = #f14c4c\ncolor10 = #23d18b\ncolor11 = #f5f567\ncolor12 = #3b8eea\ncolor13 = #d670d6\ncolor14 = #29b8db\ncolor15 = #ffffff\n"
}

just run {
  // load config (create with defaults on first run)
  let cfgPath = environ("HOME") + "/.config/stem/config"
  let cfg = readFile(cfgPath)
  if len(cfg) == 0 {
    exec("mkdir -p \"" + environ("HOME") + "/.config/stem\"")
    cfg = defaultConfig()
    writeFile(cfgPath, cfg)
  }

  let cols  = toInt(cfgVal(cfg, "cols", "92"))
  let rows  = toInt(cfgVal(cfg, "rows", "28"))
  let width = toInt(cfgVal(cfg, "width", "760"))
  let height = toInt(cfgVal(cfg, "height", "500"))
  let shell = cfgVal(cfg, "shell", "/bin/zsh")

  // Finder-launched apps inherit launchd's minimal env (no Homebrew PATH), so a
  // plain shell sources ~/.zshrc with `$(brew --prefix)` failing -> bare prompt.
  // Write a tiny wrapper that exec's a LOGIN shell (sources ~/.zprofile -> PATH),
  // then fork the wrapper. No typed setup string in the pty -> no echo to clean.
  let wrapper = environ("HOME") + "/.config/stem/launch.zsh"
  writeFile(wrapper, "#!" + shell + "\nexport TERM=xterm-256color\nexport TERM_PROGRAM=stem\nexec " + shell + " -l\n")
  exec("/bin/chmod +x " + wrapper)

  // fork ALL 4 pane shells BEFORE cocoaInit + render them warm from frame 0
  // (only the original, warm, pre-init pane reflows correctly on resize). Split
  // just reveals + sizes a pre-warmed pane.
  let m0 = stemForkPty(cols, rows, wrapper)
  let m1 = stemForkPty(cols, rows, wrapper)
  let m2 = stemForkPty(cols, rows, wrapper)
  let m3 = stemForkPty(cols, rows, wrapper)

  let app = cocoaInit()
  let bar = cocoaMenuBar(app)
  // app menu (system bolds the first menu as the app name)
  let appMenu = cocoaMenuAdd(bar, "stem")
  cocoaMenuItem(appMenu, "About stem", "", funcptr(onStemAbout))
  cocoaMenuItem(appMenu, "Check for Updates", "", funcptr(onStemUpdate))
  cocoaMenuSeparator(appMenu)
  cocoaMenuItem(appMenu, "Settings", ",", funcptr(onStemConfig))
  cocoaMenuItem(appMenu, "Reload Configuration", "", funcptr(onStemReload))
  cocoaMenuItem(appMenu, "Secure Keyboard Entry", "", funcptr(onStemSecure))
  cocoaMenuItem(appMenu, "Make stem Default Terminal", "", funcptr(onStemDefault))
  cocoaMenuSeparator(appMenu)
  let svcMenu = cocoaSubmenuIn(appMenu, "Services")
  msg_1(app, "setServicesMenu:", svcMenu)
  cocoaMenuSeparator(appMenu)
  cocoaMenuItemSel(appMenu, "Hide stem", "h", "hide:")
  cocoaMenuItemSel(appMenu, "Hide Others", "", "hideOtherApplications:")
  cocoaMenuItemSel(appMenu, "Show All", "", "unhideAllApplications:")
  cocoaMenuSeparator(appMenu)
  cocoaMenuItemSel(appMenu, "Quit stem", "q", "terminate:")
  let fileMenu = cocoaMenuAdd(bar, "File")
  cocoaMenuItem(fileMenu, "New Window", "n", funcptr(onStemNewWin))
  cocoaMenuItem(fileMenu, "New Tab", "t", funcptr(onNewTab))
  cocoaMenuSeparator(fileMenu)
  cocoaMenuItem(fileMenu, "Split Right", "d", funcptr(onSplitRight))
  cocoaMenuItem(fileMenu, "Split Left", "D", funcptr(onSplitLeft))
  cocoaMenuItem(fileMenu, "Split Top", "", funcptr(onSplitTop))
  cocoaMenuItem(fileMenu, "Split Bottom", "", funcptr(onSplitBottom))
  cocoaMenuSeparator(fileMenu)
  cocoaMenuItem(fileMenu, "Close", "", funcptr(onClosePane))
  cocoaMenuItem(fileMenu, "Close Tab", "", funcptr(onClosePane))
  cocoaMenuItemSel(fileMenu, "Close Window", "w", "performClose:")
  cocoaMenuItem(fileMenu, "Close All Windows", "", funcptr(onCloseAll))
  let shMenu = cocoaMenuAdd(bar, "Shell")
  cocoaMenuItem(shMenu, "Clear", "k", funcptr(onStemClear))
  cocoaMenuItem(shMenu, "Reset", "", funcptr(onStemReset))
  let edMenu = cocoaMenuAdd(bar, "Edit")
  cocoaMenuItem(edMenu, "Copy", "c", funcptr(onStemCopy))
  cocoaMenuItem(edMenu, "Paste", "v", funcptr(onStemPaste))
  cocoaMenuItemSel(edMenu, "Select All", "a", "selectAll:")
  let viewMenu = cocoaMenuAdd(bar, "View")
  cocoaMenuItem(viewMenu, "Zoom In", "=", funcptr(onStemZoomIn))
  cocoaMenuItem(viewMenu, "Zoom Out", "-", funcptr(onStemZoomOut))
  cocoaMenuItem(viewMenu, "Reset Zoom", "0", funcptr(onStemZoomReset))
  cocoaMenuSeparator(viewMenu)
  cocoaMenuItem(viewMenu, "Enter Full Screen", "f", funcptr(onStemFull))
  let winMenu = cocoaMenuAdd(bar, "Window")
  cocoaMenuItemSel(winMenu, "Minimize", "m", "performMiniaturize:")
  cocoaMenuItemSel(winMenu, "Zoom", "", "performZoom:")
  let helpMenu = cocoaMenuAdd(bar, "Help")
  cocoaMenuItem(helpMenu, "stem on the web", "", funcptr(onStemHelp))

  // palette cache (0-15 from config, 16-255 computed)
  let pal = cocoaArray()
  let pn = 0
  while pn < 256 {
    let c = color256def(pn)
    if pn == 0  { c = cfgRGB(cfg, "color0",  0, 0, 0) }
    if pn == 1  { c = cfgRGB(cfg, "color1",  205, 49, 49) }
    if pn == 2  { c = cfgRGB(cfg, "color2",  13, 188, 121) }
    if pn == 3  { c = cfgRGB(cfg, "color3",  229, 229, 16) }
    if pn == 4  { c = cfgRGB(cfg, "color4",  36, 114, 200) }
    if pn == 5  { c = cfgRGB(cfg, "color5",  188, 63, 188) }
    if pn == 6  { c = cfgRGB(cfg, "color6",  17, 168, 205) }
    if pn == 7  { c = cfgRGB(cfg, "color7",  229, 229, 229) }
    if pn == 8  { c = cfgRGB(cfg, "color8",  102, 102, 102) }
    if pn == 9  { c = cfgRGB(cfg, "color9",  241, 76, 76) }
    if pn == 10 { c = cfgRGB(cfg, "color10", 35, 209, 139) }
    if pn == 11 { c = cfgRGB(cfg, "color11", 245, 245, 67) }
    if pn == 12 { c = cfgRGB(cfg, "color12", 59, 142, 234) }
    if pn == 13 { c = cfgRGB(cfg, "color13", 214, 112, 214) }
    if pn == 14 { c = cfgRGB(cfg, "color14", 41, 184, 219) }
    if pn == 15 { c = cfgRGB(cfg, "color15", 255, 255, 255) }
    cocoaArrayAdd(pal, c)
    pn = pn + 1
  }
  cocoaSetAssocKey(app, "stem.pal", pal)

  let win = cocoaWindow(app, cfgVal(cfg, "title", "stem"), width, height)
  cocoaSetAssocKey(app, "stem.win", win)
  let mono = cocoaFontFamily(cocoaMonoFont(toInt(cfgVal(cfg, "font_size", "13"))), cfgVal(cfg, "font", "JetBrainsMono Nerd Font Mono"))
  let fg = cfgRGB(cfg, "fg", 255, 255, 255)
  let bg = cfgRGB(cfg, "bg", 0, 0, 0)
  cocoaSetAssocKey(app, "stem.mono", mono)
  cocoaSetAssocKey(app, "stem.fontsize", cocoaNumber(toInt(cfgVal(cfg, "font_size", "13"))))
  cocoaSetAssocKey(app, "stem.fontfam", nsString(cfgVal(cfg, "font", "JetBrainsMono Nerd Font Mono")))
  cocoaSetAssocKey(app, "stem.fgc", fg)
  cocoaSetAssocKey(app, "stem.bgc", bg)
  cocoaSetAssocKey(app, "stem.w", cocoaNumber(width))
  cocoaSetAssocKey(app, "stem.h", cocoaNumber(height))
  cocoaSetAssocKey(app, "stem.cols", cocoaNumber(cols))
  cocoaSetAssocKey(app, "stem.rows", cocoaNumber(rows))
  cocoaSetAssocKey(app, "stem.shell", nsString(shell))
  cocoaSetAssocKey(app, "stem.tree", mkLeaf(0))
  msg_1(win, "setBackgroundColor:", bg)
  msg_1(win, "setTitlebarAppearsTransparent:", 1)
  msg_1(win, "setAppearance:", msg_1(cls("NSAppearance"), "appearanceNamed:", nsString("NSAppearanceNameDarkAqua")))
  cocoaSetAssocKey(app, "stem.pmasters", cocoaArray())
  cocoaSetAssocKey(app, "stem.pscrolls", cocoaArray())
  cocoaSetAssocKey(app, "stem.pviews", cocoaArray())
  cocoaSetAssocKey(app, "stem.pdocs", cocoaArray())
  cocoaSetAssocKey(app, "stem.pcols", cocoaArray())
  cocoaSetAssocKey(app, "stem.prows", cocoaArray())
  cocoaSetAssocKey(app, "stem.pkviews", cocoaArray())
  // all 4 panes created + warm; only pane 0 shown until split
  let kview = stemMakePaneView(m0, 0, 0, width, height, cols, rows)
  let kv1 = stemMakePaneView(m1, 0, 0, width, height, cols, rows)
  let kv2 = stemMakePaneView(m2, 0, 0, width, height, cols, rows)
  let kv3 = stemMakePaneView(m3, 0, 0, width, height, cols, rows)
  let pscrolls = cocoaGetAssocKey(app, "stem.pscrolls")
  let pkviews = cocoaGetAssocKey(app, "stem.pkviews")
  let hi = 1
  while hi < 4 {
    msg_1(cocoaArrayGet(pscrolls, hi), "setHidden:", 1)
    msg_1(cocoaArrayGet(pkviews, hi), "setHidden:", 1)
    hi = hi + 1
  }
  cocoaSetAssocKey(app, "stem.master", cocoaNumber(m0))
  cocoaSetAssocKey(app, "stem.focus", kview)
  cocoaShow(win, app)
  cocoaMakeFirstResponder(win, kview)
  cocoaFinishLaunching(app)

  // manual loop: up to 2 panes; grid state kept in locals (packed != UTF-8)
  let st0 = gridNew(cols, rows)
  let pend0 = ""
  let st1 = ""
  let pend1 = ""
  let st2 = ""
  let pend2 = ""
  let st3 = ""
  let pend3 = ""
  let p1init = 0
  let p2init = 0
  let p3init = 0
  let i = 0
  while i < 2000000000 {
    cocoaPumpEvents(app)
    let masters = cocoaGetAssocKey(app, "stem.pmasters")
    let pviews = cocoaGetAssocKey(app, "stem.pviews")
    let pdocs = cocoaGetAssocKey(app, "stem.pdocs")
    let pcolsA = cocoaGetAssocKey(app, "stem.pcols")
    let prowsA = cocoaGetAssocKey(app, "stem.prows")
    let pc = cocoaArrayCount(masters)
    if brainFlagS("stem.splitdirty", 0) == 1 {
      cocoaSetAssocKey(app, "stem.splitdirty", cocoaNumber(0))
      st0 = gridNew(cocoaNumberVal(cocoaArrayGet(pcolsA, 0)), cocoaNumberVal(cocoaArrayGet(prowsA, 0)))  pend0 = ""
      p1init = 0  p2init = 0  p3init = 0
    }
    let c0 = cocoaNumberVal(cocoaArrayGet(pcolsA, 0))
    let r0 = cocoaNumberVal(cocoaArrayGet(prowsA, 0))
    let chunk0 = fdRead(cocoaNumberVal(cocoaArrayGet(masters, 0)), 4096)
    if len(chunk0) > 0 {
      let buf = pend0 + chunk0
      let safe = gridSafeLen(buf)
      pend0 = substring(buf, safe, len(buf))
      st0 = gridFeed(st0, substring(buf, 0, safe), c0, r0)
      let curp = gridCursor(st0, c0, r0)
      let ci2 = indexOf(curp, ",")
      let rendered = gridRender(st0, c0, r0)
      cocoaSetAssocKey(app, "stem.lastrender", nsString(rendered))
      msg_1(cocoaArrayGet(pviews, 0), "setAttributedString:", renderSnapshot(rendered, fg, cocoaGetAssocKey(app, "stem.mono"), toInt(substring(curp, 0, ci2)), toInt(substring(curp, ci2 + 1, len(curp)))))
      msg_1(cocoaArrayGet(pdocs, 0), "scrollToEndOfDocument:", 0)
    }
    if pc >= 2 {
      let c1 = cocoaNumberVal(cocoaArrayGet(pcolsA, 1))
      let r1 = cocoaNumberVal(cocoaArrayGet(prowsA, 1))
      if p1init == 0 { st1 = gridNew(c1, r1)  pend1 = ""  p1init = 1 }
      let chunk1 = fdRead(cocoaNumberVal(cocoaArrayGet(masters, 1)), 4096)
      if len(chunk1) > 0 {
        let buf1 = pend1 + chunk1
        let safe1 = gridSafeLen(buf1)
        pend1 = substring(buf1, safe1, len(buf1))
        st1 = gridFeed(st1, substring(buf1, 0, safe1), c1, r1)
        let curp1 = gridCursor(st1, c1, r1)
        let cj = indexOf(curp1, ",")
        msg_1(cocoaArrayGet(pviews, 1), "setAttributedString:", renderSnapshot(gridRender(st1, c1, r1), fg, cocoaGetAssocKey(app, "stem.mono"), toInt(substring(curp1, 0, cj)), toInt(substring(curp1, cj + 1, len(curp1)))))
        msg_1(cocoaArrayGet(pdocs, 1), "scrollToEndOfDocument:", 0)
      }
    }
    if pc >= 3 {
      let c2 = cocoaNumberVal(cocoaArrayGet(pcolsA, 2))
      let r2 = cocoaNumberVal(cocoaArrayGet(prowsA, 2))
      if p2init == 0 { st2 = gridNew(c2, r2)  pend2 = ""  p2init = 1 }
      let chunk2 = fdRead(cocoaNumberVal(cocoaArrayGet(masters, 2)), 4096)
      if len(chunk2) > 0 {
        let buf2 = pend2 + chunk2
        let safe2 = gridSafeLen(buf2)
        pend2 = substring(buf2, safe2, len(buf2))
        st2 = gridFeed(st2, substring(buf2, 0, safe2), c2, r2)
        let curp2 = gridCursor(st2, c2, r2)
        let ck = indexOf(curp2, ",")
        msg_1(cocoaArrayGet(pviews, 2), "setAttributedString:", renderSnapshot(gridRender(st2, c2, r2), fg, cocoaGetAssocKey(app, "stem.mono"), toInt(substring(curp2, 0, ck)), toInt(substring(curp2, ck + 1, len(curp2)))))
        msg_1(cocoaArrayGet(pdocs, 2), "scrollToEndOfDocument:", 0)
      }
    }
    if pc >= 4 {
      let c3 = cocoaNumberVal(cocoaArrayGet(pcolsA, 3))
      let r3 = cocoaNumberVal(cocoaArrayGet(prowsA, 3))
      if p3init == 0 { st3 = gridNew(c3, r3)  pend3 = ""  p3init = 1 }
      let chunk3 = fdRead(cocoaNumberVal(cocoaArrayGet(masters, 3)), 4096)
      if len(chunk3) > 0 {
        let buf3 = pend3 + chunk3
        let safe3 = gridSafeLen(buf3)
        pend3 = substring(buf3, safe3, len(buf3))
        st3 = gridFeed(st3, substring(buf3, 0, safe3), c3, r3)
        let curp3 = gridCursor(st3, c3, r3)
        let cl = indexOf(curp3, ",")
        msg_1(cocoaArrayGet(pviews, 3), "setAttributedString:", renderSnapshot(gridRender(st3, c3, r3), fg, cocoaGetAssocKey(app, "stem.mono"), toInt(substring(curp3, 0, cl)), toInt(substring(curp3, cl + 1, len(curp3)))))
        msg_1(cocoaArrayGet(pdocs, 3), "scrollToEndOfDocument:", 0)
      }
    }
    sleepUs(0, 8000)
    i = i + 1
  }
}
