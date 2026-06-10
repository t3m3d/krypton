// brain — pure-Krypton IDE on objk: editor + real stem terminal (no Obj-C source).
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
  let m = cocoaNumberVal(cocoaGetAssocKey(appH(), "stem.master"))
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

func defaultConfig() {
  emit "# stem config — key = value, # comments. Restart stem to apply.\nshell = /bin/zsh\nfont = JetBrainsMono Nerd Font Mono\nfont_size = 13\ncols = 92\nrows = 28\nwidth = 760\nheight = 500\ntitle = stem\n# colours as #RRGGBB\nfg = #ffffff\nbg = #000000\ncolor0 = #000000\ncolor1 = #cd3131\ncolor2 = #0dbc79\ncolor3 = #e5e510\ncolor4 = #2472c8\ncolor5 = #bc3fbc\ncolor6 = #11a8cd\ncolor7 = #e5e5e5\ncolor8 = #666666\ncolor9 = #f14c4c\ncolor10 = #23d18b\ncolor11 = #f5f567\ncolor12 = #3b8eea\ncolor13 = #d670d6\ncolor14 = #29b8db\ncolor15 = #ffffff\n"
}

import "k:objc"
import "head:cocoa"
import "head:objc"

func projDir() { let d = "" + arg(0)  if len(d) == 0 { emit environ("HOME") }  emit d }
func baseName(p) { let n = len(p)  let i = n - 1  while i >= 0 { if p[i] == "/" { emit substring(p, i + 1, n) }  i = i - 1 }  emit p }

func nlines(s) { let n = len(s)  let c = 0  let i = 0  while i < n { if s[i] == "\n" { c = c + 1 }  i = i + 1 }  emit c }
func lineAt(s, idx) {
  let n = len(s)  let cur = 0  let start = 0  let i = 0
  while i < n { if s[i] == "\n" { if cur == idx { emit substring(s, start, i) }  cur = cur + 1  start = i + 1 }  i = i + 1 }
  emit ""
}

// ── syntax highlighting (operates on the storage the delegate receives) ──
func isIdentCh(c) {
  if c >= 48 { if c <= 57 { emit 1 } }
  if c >= 65 { if c <= 90 { emit 1 } }
  if c >= 97 { if c <= 122 { emit 1 } }
  if c == 95 { emit 1 }
  emit 0
}
func extOf(path) {
  let n = len(path)
  let i = n - 1
  while i >= 0 {
    let ch = substring(path, i, i + 1)
    if ch == "." { emit substring(path, i + 1, n) }
    if ch == "/" { emit "" }
    i = i - 1
  }
  emit ""
}
// keyword sets per file extension
func langKeywords(ext) {
  if ext == "k" { emit "func let if else while return emit import module const just run for break continue true false" }
  if ext == "ks" { emit "func let if else while return emit import module const just run for break continue true false" }
  if ext == "js" { emit "function let const var if else while for return class new this import export from default async await yield try catch finally throw typeof instanceof true false null undefined" }
  if ext == "ts" { emit "function let const var if else while for return class new this import export from default async await interface type enum public private readonly true false null undefined" }
  if ext == "py" { emit "def class if elif else while for return import from as try except finally with lambda async await pass break continue yield global nonlocal raise assert True False None and or not in is" }
  if ext == "c" { emit "int char void float double long short if else while for return struct typedef const static unsigned signed sizeof switch case break continue default enum union goto extern" }
  if ext == "h" { emit "int char void float double long short if else while for return struct typedef const static unsigned signed sizeof switch case break continue default enum union extern" }
  if ext == "go" { emit "func var const if else for range return package import type struct interface map chan go defer select switch case break continue true false nil" }
  if ext == "rs" { emit "fn let mut if else while for loop match return struct enum impl trait pub use mod crate self where as ref move true false" }
  if ext == "sh" { emit "if then else elif fi for while until do done case esac function return export local echo read source" }
  if ext == "bash" { emit "if then else elif fi for while until do done case esac function return export local echo read source" }
  if ext == "rb" { emit "def class module if elsif else end while for return require do begin rescue ensure yield true false nil" }
  if ext == "json" { emit "true false null" }
  if ext == "html" { emit "html head body div span script style link meta title a img" }
  if ext == "css" { emit "color background margin padding border font display position width height" }
  if ext == "sql" { emit "select from where insert update delete create table drop alter join on group by order having and or not null" }
  emit "func let if else while return import class def function"
}
func lineCommentPrefix(ext) {
  if ext == "py" { emit "#" }
  if ext == "sh" { emit "#" }
  if ext == "bash" { emit "#" }
  if ext == "rb" { emit "#" }
  if ext == "yml" { emit "#" }
  if ext == "yaml" { emit "#" }
  if ext == "lua" { emit "--" }
  if ext == "sql" { emit "--" }
  emit "//"
}
// word-boundary keyword colouring
func hlWordB(ts, src, word, color) {
  let n = len(src)
  let wl = len(word)
  let pos = 0
  while pos < n {
    let i = indexOf(substring(src, pos, n), word)
    if i < 0 { emit "1" }
    let at = pos + i
    let bOk = 1
    if at > 0 { if isIdentCh(charCode(substring(src, at - 1, at))) == 1 { bOk = 0 } }
    let aIdx = at + wl
    let aOk = 1
    if aIdx < n { if isIdentCh(charCode(substring(src, aIdx, aIdx + 1))) == 1 { aOk = 0 } }
    if bOk == 1 { if aOk == 1 { cocoaTSColorRange(ts, color, at, wl) } }
    pos = at + wl
  }
  emit "1"
}
func hlKeywords(ts, src, kws, color) {
  let n = len(kws)
  let start = 0
  let i = 0
  while i <= n {
    let sep = 0
    if i == n { sep = 1 }
    else { if substring(kws, i, i + 1) == " " { sep = 1 } }
    if sep == 1 { if i > start { hlWordB(ts, src, substring(kws, start, i), color) }  start = i + 1 }
    i = i + 1
  }
  emit "1"
}
func hlNumbers(ts, src, color) {
  let n = len(src)
  let i = 0
  while i < n {
    let c = charCode(substring(src, i, i + 1))
    let before = 0
    if i > 0 { before = charCode(substring(src, i - 1, i)) }
    if c >= 48 { if c <= 57 { if isIdentCh(before) == 0 {
      let j = i + 1
      let go = 1
      while go == 1 {
        if j >= n { go = 0 }
        else { let d = charCode(substring(src, j, j + 1))  if (d >= 48 && d <= 57) || d == 46 { j = j + 1 } else { go = 0 } }
      }
      cocoaTSColorRange(ts, color, i, j - i)
      i = j - 1
    } } }
    i = i + 1
  }
  emit "1"
}
// colour quoted strings, bounded to a SINGLE line — an unterminated quote
// (apostrophe in a comment, contraction, regex) must not green-out the rest
// of the file.
func hlDelim(ts, src, q, color) {
  let n = len(src)
  let pos = 0
  while pos < n {
    let i = indexOf(substring(src, pos, n), q)
    if i < 0 { emit "1" }
    let start = pos + i
    let rest = substring(src, start + 1, n)
    let j = indexOf(rest, q)
    let nl = indexOf(rest, "\n")
    let closeAbs = 0 - 1
    if j >= 0 { closeAbs = start + 1 + j }
    let nlAbs = 0 - 1
    if nl >= 0 { nlAbs = start + 1 + nl }
    let useClose = 0
    if closeAbs >= 0 {
      if nlAbs < 0 { useClose = 1 }
      else { if closeAbs < nlAbs { useClose = 1 } }
    }
    if useClose == 1 {
      let end = closeAbs + 1
      cocoaTSColorRange(ts, color, start, end - start)
      pos = end
    } else {
      let end = n
      if nlAbs >= 0 { end = nlAbs }
      cocoaTSColorRange(ts, color, start, end - start)
      pos = end + 1
    }
  }
  emit "1"
}
func hlLineComment(ts, src, prefix, color) {
  let n = len(src)
  let pos = 0
  while pos < n {
    let i = indexOf(substring(src, pos, n), prefix)
    if i < 0 { emit "1" }
    let start = pos + i
    let nl = indexOf(substring(src, start, n), "\n")
    let end = n
    if nl >= 0 { end = start + nl }
    cocoaTSColorRange(ts, color, start, end - start)
    pos = end + 1
  }
  emit "1"
}
func highlightLang(ts, src, ext) {
  hlKeywords(ts, src, langKeywords(ext), cocoaColorNamed("systemPurpleColor"))
  hlNumbers(ts, src, cocoaColorNamed("systemOrangeColor"))
  hlDelim(ts, src, "\"", cocoaColorNamed("systemGreenColor"))
  hlDelim(ts, src, "'", cocoaColorNamed("systemGreenColor"))
  hlLineComment(ts, src, lineCommentPrefix(ext), cocoaColorNamed("systemGrayColor"))
  emit "1"
}
func reHL(self, cmd, notif) {
  let ts = msg(notif, "object")
  if cocoaTSEditedChars(ts) == 0 { emit "1" }
  cocoaTSClearColor(ts)
  let lang = cocoaGetAssocKey(appH(), "brain.lang")
  let ext = ""
  if lang != 0 { ext = msg(lang, "UTF8String") }
  highlightLang(ts, cocoaTSString(ts), ext)
  emit "1"
}

// ── tabs ────────────────────────────────────────────────────────────────
func curTabIdx() {
  let n = cocoaGetAssocKey(appH(), "brain.curtab")
  if n == 0 { emit 0 - 1 }
  emit cocoaNumberVal(n)
}
func saveCurTab() {
  let idx = curTabIdx()
  if idx < 0 { emit "1" }
  let texts = cocoaGetAssocKey(appH(), "brain.tabtexts")
  if idx >= cocoaArrayCount(texts) { emit "1" }
  cocoaArraySet(texts, idx,
    nsString(cocoaTVGetString(cocoaGetAssocKey(appH(), "brain.editor"))))
  emit "1"
}
func rebuildTabs() {
  let app = appH()
  let win = cocoaGetAssocKey(app, "brain.win")
  let old = cocoaGetAssocKey(app, "brain.tabbtns")
  let oc = cocoaArrayCount(old)
  let oi = 0
  while oi < oc { msg(cocoaArrayGet(old, oi), "removeFromSuperview")  oi = oi + 1 }
  let btns = cocoaArray()
  cocoaSetAssocKey(app, "brain.tabbtns", btns)
  let paths = cocoaGetAssocKey(app, "brain.tabpaths")
  let n = cocoaArrayCount(paths)
  let cur = curTabIdx()
  let x = 244
  let i = 0
  while i < n {
    let nm = baseName(msg(cocoaArrayGet(paths, i), "UTF8String"))
    // tab width includes room for the ✕ on the right
    let w = 70 + len(nm) * 7 + 22
    if w > 220 { w = 220 }
    let nameb = cocoaButton(win, nm, x, 610, w, 26)
    msg_1(nameb, "setBezelStyle:", 1)
    msg_1(nameb, "setAlignment:", 0)
    if i == cur { msg_1(nameb, "setState:", 1) }
    cocoaSetAssocKey(nameb, "idx", cocoaNumber(i))
    cocoaOnClickKeyed(nameb, "tabsel", funcptr(onTabSelect))
    cocoaArrayAdd(btns, nameb)
    // round ✕ button overlaid on the tab's right edge (on top -> captures its clicks).
    // Layer-drawn circle (exact size) instead of NSBezelStyleCircular (fixed-min, too big).
    let closeb = cocoaButton(win, "✕", x + w - 26, 617, 16, 16)
    msg_1(closeb, "setBordered:", 0)
    cocoaSetFont(closeb, cocoaMonoFont(11))
    msg_1(closeb, "setWantsLayer:", 1)
    let lay = msg(closeb, "layer")
    msg_d1(lay, "setCornerRadius:", 8)
    msg_1(lay, "setBackgroundColor:", msg(cocoaColorNamed("grayColor"), "CGColor"))
    cocoaSetAssocKey(closeb, "idx", cocoaNumber(i))
    cocoaOnClickKeyed(closeb, "tabclose", funcptr(onTabClose))
    cocoaArrayAdd(btns, closeb)
    x = x + w + 6
    i = i + 1
  }
  emit "1"
}
func onTabSelect(self, cmd, sender) {
  saveCurTab()
  selectTab(cocoaNumberVal(cocoaGetAssocKey(sender, "idx")))
}
func onTabClose(self, cmd, sender) {
  let app = appH()
  let idx = cocoaNumberVal(cocoaGetAssocKey(sender, "idx"))
  let paths = cocoaGetAssocKey(app, "brain.tabpaths")
  let texts = cocoaGetAssocKey(app, "brain.tabtexts")
  if idx == curTabIdx() { saveCurTab() }
  cocoaArrayRemove(paths, idx)
  cocoaArrayRemove(texts, idx)
  cocoaSetAssocKey(app, "brain.curtab", cocoaNumber(0 - 1))
  let n = cocoaArrayCount(paths)
  if n == 0 {
    cocoaTVSetString(cocoaGetAssocKey(app, "brain.editor"), "// no file open\n")
    rebuildTabs()
    emit "1"
  }
  let pick = idx
  if pick >= n { pick = n - 1 }
  selectTab(pick)
}
func selectTab(idx) {
  let app = appH()
  let paths = cocoaGetAssocKey(app, "brain.tabpaths")
  let texts = cocoaGetAssocKey(app, "brain.tabtexts")
  if idx < 0 { emit "1" }
  if idx >= cocoaArrayCount(texts) { emit "1" }
  cocoaSetAssocKey(app, "brain.curtab", cocoaNumber(idx))
  cocoaSetAssocKey(app, "brain.curpath", cocoaArrayGet(paths, idx))
  cocoaSetAssocKey(app, "brain.lang", nsString(extOf(msg(cocoaArrayGet(paths, idx), "UTF8String"))))
  cocoaTVSetString(cocoaGetAssocKey(app, "brain.editor"), msg(cocoaArrayGet(texts, idx), "UTF8String"))
  msg_1(cocoaGetAssocKey(app, "brain.win"), "setTitle:", nsString("brain — " + msg(cocoaArrayGet(paths, idx), "UTF8String")))
  rebuildTabs()
  emit "1"
}
// ── recent files/folders (~/.config/brain/{files,folders}, newest first) ──
func recentAdd(name, path) {
  exec("mkdir -p \"" + environ("HOME") + "/.config/brain\"")
  let f = environ("HOME") + "/.config/brain/" + name
  let cur = readFile(f)
  let out = path + "\n"
  let n = nlines(cur)
  let i = 0
  let kept = 0
  while i < n {
    let ln = lineAt(cur, i)
    if ln != path { if len(ln) > 0 { if kept < 9 { out = out + ln + "\n"  kept = kept + 1 } } }
    i = i + 1
  }
  writeFile(f, out)
  emit "1"
}
func dirOf(p) { let n = len(p)  let i = n - 1  while i >= 0 { if p[i] == "/" { emit substring(p, 0, i) }  i = i - 1 }  emit p }

func openTab(path) {
  let app = appH()
  recentAdd("files", path)
  saveCurTab()
  let paths = cocoaGetAssocKey(app, "brain.tabpaths")
  let texts = cocoaGetAssocKey(app, "brain.tabtexts")
  let count = cocoaArrayCount(paths)
  let found = 0 - 1
  let i = 0
  while i < count { if msg(cocoaArrayGet(paths, i), "UTF8String") == path { found = i }  i = i + 1 }
  if found < 0 {
    cocoaArrayAdd(paths, nsString(path))
    cocoaArrayAdd(texts, nsString(readFile(path)))
    found = count
  }
  rebuildTabs()
  selectTab(found)
  emit "1"
}
func onTabChange(self, cmd, sender) {
  saveCurTab()
  selectTab(cocoaSegSelected(sender))
}

func onNew(self, cmd, sender) {
  let app = appH()
  saveCurTab()
  let paths = cocoaGetAssocKey(app, "brain.tabpaths")
  let texts = cocoaGetAssocKey(app, "brain.tabtexts")
  cocoaArrayAdd(paths, nsString(projDir() + "/untitled-" + cocoaArrayCount(paths) + ".k"))
  cocoaArrayAdd(texts, nsString("// new file\n"))
  rebuildTabs()
  selectTab(cocoaArrayCount(paths) - 1)
}
func onClose(self, cmd, sender) {
  let app = appH()
  let idx = curTabIdx()
  if idx < 0 { emit "1" }
  let paths = cocoaGetAssocKey(app, "brain.tabpaths")
  let texts = cocoaGetAssocKey(app, "brain.tabtexts")
  cocoaArrayRemove(paths, idx)
  cocoaArrayRemove(texts, idx)
  cocoaSetAssocKey(app, "brain.curtab", cocoaNumber(0 - 1))
  rebuildTabs()
  let n = cocoaArrayCount(paths)
  if n == 0 { cocoaTVSetString(cocoaGetAssocKey(app, "brain.editor"), "// no file open\n")  emit "1" }
  let pick = idx
  if pick >= n { pick = n - 1 }
  selectTab(pick)
}

// ── menu actions ──────────────────────────────────────────────────────
func onRun(self, cmd, sender) {
  let app = appH()
  let cp = cocoaGetAssocKey(app, "brain.curpath")
  if cp == 0 { cocoaAlert("Run", "Open a .k file first.")  emit "1" }
  let path = msg(cp, "UTF8String")
  saveCurTab()
  writeFile(path, cocoaTVGetString(cocoaGetAssocKey(app, "brain.editor")))
  cocoaAlert("Run output", exec("cd " + projDir() + " && kcc --native " + path + " -o /tmp/brainrun 2>&1 && /tmp/brainrun 2>&1"))
}
func onOpen(self, cmd, sender) { let f = chooseFile()  if len(f) > 0 { openTab(f) }  emit "1" }
func onSave(self, cmd, sender) {
  let app = appH()
  let cp = cocoaGetAssocKey(app, "brain.curpath")
  if cp == 0 { kp("brain: no file open")  emit "1" }
  let path = msg(cp, "UTF8String")
  saveCurTab()
  writeFile(path, cocoaTVGetString(cocoaGetAssocKey(app, "brain.editor")))
  kp("brain: saved " + path)
}

// ── integrated console (run shell commands, see output) ────────────────
func onCmd(self, cmd, sender) {
  let app = appH()
  let line = msg(msg(sender, "stringValue"), "UTF8String")
  let console = cocoaGetAssocKey(app, "brain.console")
  let out = exec("cd " + projDir() + " && " + line + " 2>&1")
  cocoaTVSetString(console, cocoaTVGetString(console) + "$ " + line + "\n" + out)
  msg_1(sender, "setStringValue:", nsString(""))
  msg_1(console, "scrollToEndOfDocument:", 0)
}

// ── file tree ──────────────────────────────────────────────────────────
func dsRows(self, cmd, tv) { emit cocoaArrayCount(cocoaGetAssocKey(self, "files")) }
func dsValue(self, cmd, tv, col, row) { emit cocoaArrayGet(cocoaGetAssocKey(self, "files"), row) }
// fill a tree array: ".." then `ls -1p` (dirs end with '/').
func fillFiles(files, d) {
  cocoaArrayAdd(files, nsString(".."))
  let listing = exec("ls -1p \"" + d + "\"")
  let n = nlines(listing)
  let i = 0
  while i < n { let ln = lineAt(listing, i)  if len(ln) > 0 { cocoaArrayAdd(files, nsString(ln)) }  i = i + 1 }
  emit "1"
}
func dsSelect(self, cmd, notif) {
  let row = msg(msg(notif, "object"), "selectedRow")
  if row < 0 { emit "1" }
  let fname = msg(cocoaArrayGet(cocoaGetAssocKey(self, "files"), row), "UTF8String")
  let dir = msg(cocoaGetAssocKey(self, "dir"), "UTF8String")
  if fname == ".." { loadFolder(dirOf(dir))  emit "1" }
  let last = substring(fname, len(fname) - 1, len(fname))
  if last == "/" { loadFolder(dir + "/" + substring(fname, 0, len(fname) - 1))  emit "1" }
  openTab(dir + "/" + fname)
}

// ── File-menu handlers ──────────────────────────────────────────────────
func newUntitled(ext) {
  let app = appH()
  saveCurTab()
  let paths = cocoaGetAssocKey(app, "brain.tabpaths")
  let texts = cocoaGetAssocKey(app, "brain.tabtexts")
  cocoaArrayAdd(paths, nsString(projDir() + "/untitled-" + cocoaArrayCount(paths) + ext))
  cocoaArrayAdd(texts, nsString(""))
  rebuildTabs()
  selectTab(cocoaArrayCount(paths) - 1)
  emit "1"
}
func onNewText(self, cmd, sender)  { newUntitled(".txt") }
func onNewFile(self, cmd, sender)  { newUntitled(".k") }
func onNewWindow(self, cmd, sender){ exec("open -n /Applications/brain.app")  emit "1" }
// reload the file tree in-place to folder `d`
func loadFolder(d) {
  let app = appH()
  recentAdd("folders", d)
  let ds = cocoaGetAssocKey(app, "brain.ds")
  let files = cocoaArray()
  fillFiles(files, d)
  cocoaSetAssocKey(ds, "files", files)
  cocoaSetAssocKey(ds, "dir", nsString(d))
  cocoaSetAssocKey(app, "brain.dir", nsString(d))
  cocoaReload(cocoaGetAssocKey(app, "brain.table"))
  msg_1(cocoaGetAssocKey(app, "brain.win"), "setTitle:", nsString("brain — " + d))
  emit "1"
}
// native pickers via osascript — NSOpenPanel.runModal does not display in a
// manual event-loop app, so shell out to the system chooser (run-loop independent).
func chooseFolder() { emit trim(exec("osascript -e 'try' -e 'POSIX path of (choose folder)' -e 'end try' 2>/dev/null")) }
func chooseFile()   { emit trim(exec("osascript -e 'try' -e 'POSIX path of (choose file)' -e 'end try' 2>/dev/null")) }
func chooseSave()   { emit trim(exec("osascript -e 'try' -e 'POSIX path of (choose file name)' -e 'end try' 2>/dev/null")) }

func onOpenFolder(self, cmd, sender) { let d = chooseFolder()  if len(d) > 0 { loadFolder(d) }  emit "1" }
func onOpenWorkspace(self, cmd, sender) { let f = chooseFile()  if len(f) > 0 { loadFolder(dirOf(f)) }  emit "1" }
func onOpenRecentFolder(self, cmd, sender) { loadFolder(msg(msg(sender, "title"), "UTF8String")) }
func onOpenRecentFile(self, cmd, sender) { openTab(msg(msg(sender, "title"), "UTF8String")) }

// workspace (brain's "workspace" = the opened folder)
func onAddFolder(self, cmd, sender) { onOpenFolder(self, cmd, sender) }
func onDupWorkspace(self, cmd, sender) {
  exec("open -n /Applications/brain.app --args \"" + msg(cocoaGetAssocKey(appH(), "brain.dir"), "UTF8String") + "\"")
  emit "1"
}
func onSaveWorkspaceAs(self, cmd, sender) {
  let path = chooseSave()
  if len(path) > 0 { writeFile(path, msg(cocoaGetAssocKey(appH(), "brain.dir"), "UTF8String") + "\n") }
  emit "1"
}
// save group
func onSaveAs(self, cmd, sender) {
  let app = appH()
  let path = chooseSave()
  if len(path) > 0 {
    saveCurTab()
    writeFile(path, cocoaTVGetString(cocoaGetAssocKey(app, "brain.editor")))
    cocoaSetAssocKey(app, "brain.curpath", nsString(path))
    recentAdd("files", path)
  }
  emit "1"
}
func onSaveAll(self, cmd, sender) {
  let app = appH()
  saveCurTab()
  let paths = cocoaGetAssocKey(app, "brain.tabpaths")
  let texts = cocoaGetAssocKey(app, "brain.tabtexts")
  let n = cocoaArrayCount(paths)
  let i = 0
  while i < n {
    let p = msg(cocoaArrayGet(paths, i), "UTF8String")
    if indexOf(p, "untitled-") < 0 { writeFile(p, msg(cocoaArrayGet(texts, i), "UTF8String")) }
    i = i + 1
  }
  emit "1"
}
func onAutoSave(self, cmd, sender) {
  let app = appH()
  let cur = cocoaGetAssocKey(app, "brain.autosave")
  let v = 0
  if cur != 0 { v = cocoaNumberVal(cur) }
  let nv = 1
  if v == 1 { nv = 0 }
  cocoaSetAssocKey(app, "brain.autosave", cocoaNumber(nv))
  msg_1(sender, "setState:", nv)
  emit "1"
}
func onRevert(self, cmd, sender) {
  let app = appH()
  let cp = cocoaGetAssocKey(app, "brain.curpath")
  if cp == 0 { emit "1" }
  cocoaTVSetString(cocoaGetAssocKey(app, "brain.editor"), readFile(msg(cp, "UTF8String")))
  emit "1"
}
func onCloseEditor(self, cmd, sender) { onClose(self, cmd, sender) }
func onCloseWindow(self, cmd, sender) { msg_1(cocoaGetAssocKey(appH(), "brain.win"), "performClose:", 0)  emit "1" }

// ── View: toggle sidebar / terminal ─────────────────────────────────────
func brainFlag(key, def) {
  let v = cocoaGetAssocKey(appH(), key)
  if v == 0 { emit def }
  emit cocoaNumberVal(v)
}
func relayout() {
  let app = appH()
  let sb = brainFlag("brain.sidebar", 1)
  let tm = brainFlag("brain.terminal", 1)
  let sbw = 240
  if sb == 0 { sbw = 0 }
  let topB = 252
  if tm == 0 { topB = 0 }
  let treeHidden = 1
  if sb == 1 { treeHidden = 0 }
  msg_1(cocoaGetAssocKey(app, "brain.treesv"), "setHidden:", treeHidden)
  msg_frame(cocoaGetAssocKey(app, "brain.treesv"), "setFrame:", 0, topB, 240, 640 - topB)
  let termHidden = 1
  if tm == 1 { termHidden = 0 }
  msg_1(cocoaGetAssocKey(app, "brain.termsv"), "setHidden:", termHidden)
  msg_1(cocoaGetAssocKey(app, "brain.kview"), "setHidden:", termHidden)
  msg_frame(cocoaGetAssocKey(app, "brain.editorsv"), "setFrame:", sbw, topB, 940 - sbw, 608 - topB)
  emit "1"
}
func onToggleSidebar(self, cmd, sender) {
  let v = brainFlag("brain.sidebar", 1)
  let nv = 0
  if v == 0 { nv = 1 }
  cocoaSetAssocKey(appH(), "brain.sidebar", cocoaNumber(nv))
  relayout()
  emit "1"
}
func onToggleTerminal(self, cmd, sender) {
  let v = brainFlag("brain.terminal", 1)
  let nv = 0
  if v == 0 { nv = 1 }
  cocoaSetAssocKey(appH(), "brain.terminal", cocoaNumber(nv))
  relayout()
  emit "1"
}
func brainSetFontSize(sz) {
  cocoaSetAssocKey(appH(), "brain.fontsize", cocoaNumber(sz))
  cocoaSetFont(cocoaGetAssocKey(appH(), "brain.editor"), cocoaMonoFont(sz))
  emit "1"
}
func onZoomIn(self, cmd, sender)    { let s = brainFlag("brain.fontsize", 13) + 1  if s > 40 { s = 40 }  brainSetFontSize(s) }
func onZoomOut(self, cmd, sender)   { let s = brainFlag("brain.fontsize", 13) - 1  if s < 7 { s = 7 }  brainSetFontSize(s) }
func onZoomReset(self, cmd, sender) { brainSetFontSize(13) }

just run {
  let dir = projDir()
  recentAdd("folders", dir)
  let cfg = readFile(environ("HOME") + "/.config/stem/config")

  // terminal pty (bottom pane)
  let m = ptyMaster("/dev/ptmx")
  let slave = ptySlaveName(m)
  ptyForkExec(slave, "/bin/zsh")
  let cols = 112
  let rows = 14
  let tries = 0
  let szd = 0
  while tries < 60 {
    if szd == 0 { if ptySetSize(m, rows, cols) == 0 { szd = 1 } else { sleepUs(0, 10000)  tries = tries + 1 } }
    else { tries = 60 }
  }
  fdSetNonblock(m)
  let setup = "cd \"" + dir + "\"; export TERM=xterm-256color; export TERM_PROGRAM=stem; export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\"; clear\n"
  fdWrite(m, setup, len(setup))

  let app = cocoaInit()
  let bar = cocoaMenuBar(app)

  // terminal colour palette
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

  let win = cocoaWindow(app, "brain — " + dir, 940, 640)
  msg_1(win, "setAppearance:", msg_1(cls("NSAppearance"), "appearanceNamed:", nsString("NSAppearanceNameDarkAqua")))

  // top: tree + editor + tabs ; bottom: terminal
  let table = cocoaTable(win, 0, 252, 240, 388)
  let editor = cocoaScrollText(win, 240, 252, 700, 356)
  cocoaSetFont(editor, cocoaMonoFont(13))
  cocoaSetBg(editor, cocoaRGB(168, 206, 184))
  msg_1(editor, "setAllowsUndo:", 1)
  msg_1(editor, "setUsesFindBar:", 1)

  let term = cocoaScrollText(win, 0, 0, 940, 246)
  msg_1(term, "setEditable:", 0)
  msg_1(term, "setSelectable:", 0)
  let tmono = cocoaFontFamily(cocoaMonoFont(12), "JetBrainsMono Nerd Font Mono")
  cocoaSetFont(term, tmono)
  let tfg = cocoaColorNamed("whiteColor")
  cocoaSetBg(term, cocoaColorNamed("blackColor"))
  cocoaSetTextColor(term, tfg)
  let kc = cocoaViewClassNew("BrainTermKeys")
  cocoaClassAddMethod(kc, "keyDown:", funcptr(onKey), "v@:@")
  cocoaClassAddMethod(kc, "acceptsFirstResponder", funcptr(acceptsFR), "c@:")
  cocoaClassRegister(kc)
  let kview = cocoaCustomView(win, kc, 0, 0, 940, 246)
  cocoaSetAssocKey(app, "stem.master", cocoaNumber(m))
  // view refs for View-menu toggles
  cocoaSetAssocKey(app, "brain.treesv", msg(table, "enclosingScrollView"))
  cocoaSetAssocKey(app, "brain.editorsv", msg(editor, "enclosingScrollView"))
  cocoaSetAssocKey(app, "brain.termsv", msg(term, "enclosingScrollView"))
  cocoaSetAssocKey(app, "brain.kview", kview)

  // file tree data
  let files = cocoaArray()
  fillFiles(files, dir)

  let dsc = cocoaClassNew("BrainDelegate")
  cocoaClassAddMethod(dsc, "numberOfRowsInTableView:", funcptr(dsRows), "q@:@")
  cocoaClassAddMethod(dsc, "tableView:objectValueForTableColumn:row:", funcptr(dsValue), "@@:@@q")
  cocoaClassAddMethod(dsc, "tableViewSelectionDidChange:", funcptr(dsSelect), "v@:@")
  cocoaClassAddMethod(dsc, "textStorageDidProcessEditing:", funcptr(reHL), "v@:@")
  cocoaClassRegister(dsc)
  let ds = cocoaNew(dsc)
  cocoaSetAssocKey(app, "brain.ds", ds)
  cocoaSetAssocKey(app, "brain.table", table)
  cocoaSetAssocKey(ds, "files", files)
  cocoaSetAssocKey(ds, "dir", nsString(dir))
  cocoaSetDataSource(table, ds)
  msg_1(table, "setDelegate:", ds)
  cocoaTVSetStorageDelegate(editor, ds)

  cocoaSetAssocKey(app, "brain.editor", editor)
  cocoaSetAssocKey(app, "brain.dir", nsString(dir))
  cocoaSetAssocKey(app, "brain.win", win)
  cocoaSetAssocKey(app, "brain.tabbtns", cocoaArray())
  cocoaSetAssocKey(app, "brain.tabpaths", cocoaArray())
  cocoaSetAssocKey(app, "brain.tabtexts", cocoaArray())

  let fileMenu = cocoaMenuAdd(bar, "File")
  cocoaMenuItem(fileMenu, "New Text File", "t", funcptr(onNewText))
  cocoaMenuItem(fileMenu, "New File", "n", funcptr(onNewFile))
  cocoaMenuItem(fileMenu, "New Window", "N", funcptr(onNewWindow))
  cocoaMenuSeparator(fileMenu)
  cocoaMenuItem(fileMenu, "Open", "o", funcptr(onOpen))
  cocoaMenuItem(fileMenu, "Open Folder", "O", funcptr(onOpenFolder))
  cocoaMenuItem(fileMenu, "Open Workspace from File", "", funcptr(onOpenWorkspace))
  let recentMenu = cocoaSubmenuIn(fileMenu, "Open Recent")
  let rf = readFile(environ("HOME") + "/.config/brain/folders")
  let rfn = nlines(rf)
  let ri = 0
  while ri < rfn { let ln = lineAt(rf, ri)  if len(ln) > 0 { cocoaMenuItem(recentMenu, ln, "", funcptr(onOpenRecentFolder)) }  ri = ri + 1 }
  cocoaMenuSeparator(recentMenu)
  let rfiles = readFile(environ("HOME") + "/.config/brain/files")
  let rfin = nlines(rfiles)
  if rfin > 3 { rfin = 3 }
  let rfi = 0
  while rfi < rfin { let lnf = lineAt(rfiles, rfi)  if len(lnf) > 0 { cocoaMenuItem(recentMenu, lnf, "", funcptr(onOpenRecentFile)) }  rfi = rfi + 1 }
  cocoaMenuSeparator(fileMenu)
  cocoaMenuItem(fileMenu, "Add Folder to Workspace", "", funcptr(onAddFolder))
  cocoaMenuItem(fileMenu, "Save Workspace As", "", funcptr(onSaveWorkspaceAs))
  cocoaMenuItem(fileMenu, "Duplicate Workspace", "", funcptr(onDupWorkspace))
  cocoaMenuSeparator(fileMenu)
  cocoaMenuItem(fileMenu, "Save", "s", funcptr(onSave))
  cocoaMenuItem(fileMenu, "Save As", "S", funcptr(onSaveAs))
  cocoaMenuItem(fileMenu, "Save All", "", funcptr(onSaveAll))
  cocoaMenuSeparator(fileMenu)
  cocoaMenuItem(fileMenu, "Auto Save", "", funcptr(onAutoSave))
  cocoaMenuSeparator(fileMenu)
  cocoaMenuItem(fileMenu, "Revert File", "", funcptr(onRevert))
  cocoaMenuItem(fileMenu, "Close Editor", "w", funcptr(onCloseEditor))
  cocoaMenuItem(fileMenu, "Close Window", "W", funcptr(onCloseWindow))
  let editMenu = cocoaMenuAdd(bar, "Edit")
  cocoaMenuItemSel(editMenu, "Undo", "z", "undo:")
  cocoaMenuItemSel(editMenu, "Redo", "Z", "redo:")
  cocoaMenuSeparator(editMenu)
  cocoaMenuItemSel(editMenu, "Cut", "x", "cut:")
  cocoaMenuItemSel(editMenu, "Copy", "c", "copy:")
  cocoaMenuItemSel(editMenu, "Paste", "v", "paste:")
  cocoaMenuItemSel(editMenu, "Delete", "", "delete:")
  cocoaMenuItemSel(editMenu, "Select All", "a", "selectAll:")
  cocoaMenuSeparator(editMenu)
  // NSTextFinder actions (tag = NSTextFinderAction): 1 showFind, 2 next, 3 prev, 12 showReplace
  cocoaMenuItemSelTag(editMenu, "Find", "f", "performTextFinderAction:", 1)
  cocoaMenuItemSelTag(editMenu, "Find Next", "g", "performTextFinderAction:", 2)
  cocoaMenuItemSelTag(editMenu, "Find Previous", "G", "performTextFinderAction:", 3)
  cocoaMenuItemSelTag(editMenu, "Find and Replace", "F", "performTextFinderAction:", 12)
  let viewMenu = cocoaMenuAdd(bar, "View")
  cocoaMenuItem(viewMenu, "Toggle Sidebar", "b", funcptr(onToggleSidebar))
  cocoaMenuItem(viewMenu, "Toggle Terminal", "j", funcptr(onToggleTerminal))
  cocoaMenuSeparator(viewMenu)
  cocoaMenuItem(viewMenu, "Zoom In", "=", funcptr(onZoomIn))
  cocoaMenuItem(viewMenu, "Zoom Out", "-", funcptr(onZoomOut))
  cocoaMenuItem(viewMenu, "Reset Zoom", "0", funcptr(onZoomReset))
  let runMenu = cocoaMenuAdd(bar, "Run")
  cocoaMenuItem(runMenu, "Run File", "r", funcptr(onRun))

  cocoaTVSetString(editor, "// brain — click a file on the left; terminal below\n")
  cocoaReload(table)
  cocoaShow(win, app)
  cocoaMakeFirstResponder(win, kview)
  cocoaFinishLaunching(app)

  // manual loop: pump UI events + stream the pty into the terminal grid
  let ts = msg(term, "textStorage")
  let st = gridNew(cols, rows)
  let pending = ""
  let i = 0
  while i < 2000000000 {
    cocoaPumpEvents(app)
    let chunk = fdRead(m, 4096)
    if len(chunk) > 0 {
      let buf = pending + chunk
      let safe = gridSafeLen(buf)
      pending = substring(buf, safe, len(buf))
      st = gridFeed(st, substring(buf, 0, safe), cols, rows)
      let curp = gridCursor(st, cols, rows)
      let ci2 = indexOf(curp, ",")
      msg_1(ts, "setAttributedString:", renderSnapshot(gridRender(st, cols, rows), tfg, tmono, toInt(substring(curp, 0, ci2)), toInt(substring(curp, ci2 + 1, len(curp)))))
      msg_1(term, "scrollToEndOfDocument:", 0)
    }
    // auto save: every ~5s if enabled, write the current tab to disk
    if i - (i / 625) * 625 == 0 {
      let asv = cocoaGetAssocKey(app, "brain.autosave")
      if asv != 0 { if cocoaNumberVal(asv) == 1 {
        let cp = cocoaGetAssocKey(app, "brain.curpath")
        if cp != 0 {
          let cpath = msg(cp, "UTF8String")
          if indexOf(cpath, "untitled-") < 0 {
            saveCurTab()
            writeFile(cpath, cocoaTVGetString(cocoaGetAssocKey(app, "brain.editor")))
          }
        }
      } }
    }
    sleepUs(0, 8000)
    i = i + 1
  }
}
