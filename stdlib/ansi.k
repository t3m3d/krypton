// stdlib/ansi.k — ANSI terminal colors & styles in PURE KRYPTON. No C.
//
// Builds SGR escape sequences (ESC = charCode 27, safely < 128). Wrap text so
// it auto-resets, or grab raw codes for manual control.
//
//   kp(red("error"))             // red text, auto-reset
//   kp(bold(green("ok")))        // nest styles
//   kp(color256(208, "orange"))  // 256-color palette
//   kp(ansiClear())              // clear screen + home cursor
//
// All wrappers append RESET, so nesting works left-to-right.

module ansi

func _esc() { emit fromCharCode(27) + "[" }
func _sgr(code) { emit _esc() + code + "m" }

func reset()     { emit _sgr("0") }
func _wrap(code, s) { emit _sgr(code) + s + _sgr("0") }

// ── foreground colors ────────────────────────────────────────────────
func black(s)   { emit _wrap("30", s) }
func red(s)     { emit _wrap("31", s) }
func green(s)   { emit _wrap("32", s) }
func yellow(s)  { emit _wrap("33", s) }
func blue(s)    { emit _wrap("34", s) }
func magenta(s) { emit _wrap("35", s) }
func cyan(s)    { emit _wrap("36", s) }
func white(s)   { emit _wrap("37", s) }
func gray(s)    { emit _wrap("90", s) }

// ── bright foreground ────────────────────────────────────────────────
func brightRed(s)    { emit _wrap("91", s) }
func brightGreen(s)  { emit _wrap("92", s) }
func brightYellow(s) { emit _wrap("93", s) }
func brightBlue(s)   { emit _wrap("94", s) }
func brightCyan(s)   { emit _wrap("96", s) }

// ── background colors ────────────────────────────────────────────────
func bgRed(s)    { emit _wrap("41", s) }
func bgGreen(s)  { emit _wrap("42", s) }
func bgYellow(s) { emit _wrap("43", s) }
func bgBlue(s)   { emit _wrap("44", s) }

// ── styles ───────────────────────────────────────────────────────────
func bold(s)      { emit _wrap("1", s) }
func dim(s)       { emit _wrap("2", s) }
func italic(s)    { emit _wrap("3", s) }
func underline(s) { emit _wrap("4", s) }
func blink(s)     { emit _wrap("5", s) }
func inverse(s)   { emit _wrap("7", s) }
func strike(s)    { emit _wrap("9", s) }

// ── 256-color & truecolor ────────────────────────────────────────────
// color256(n, s): foreground from the xterm 256-color palette (0-255).
func color256(n, s) { emit _esc() + "38;5;" + toStr(n) + "m" + s + _sgr("0") }
func bg256(n, s)    { emit _esc() + "48;5;" + toStr(n) + "m" + s + _sgr("0") }
// rgb(r,g,b, s): 24-bit truecolor foreground.
func rgb(r, g, b, s) {
    emit _esc() + "38;2;" + toStr(r) + ";" + toStr(g) + ";" + toStr(b) + "m" + s + _sgr("0")
}

// ── screen / cursor control ──────────────────────────────────────────
func ansiClear()    { emit _esc() + "2J" + _esc() + "H" }   // clear + home
func cursorHome()   { emit _esc() + "H" }
func cursorTo(row, col) { emit _esc() + toStr(row) + ";" + toStr(col) + "H" }
func cursorUp(n)    { emit _esc() + toStr(n) + "A" }
func cursorDown(n)  { emit _esc() + toStr(n) + "B" }
func clearLine()    { emit _esc() + "2K" }
func hideCursor()   { emit _esc() + "?25l" }
func showCursor()   { emit _esc() + "?25h" }

// strip(s): remove all SGR/CSI escape sequences from a string (for logging
// to files where color codes are noise).
func strip(s) {
    let out = ""
    let i = 0
    let n = len(s)
    while i < n {
        if toInt(charCode(s[i])) == 27 {
            // skip until a letter (the CSI final byte)
            i += 1
            while i < n {
                let c = toInt(charCode(s[i]))
                i += 1
                if (c >= 64 && c <= 90) || (c >= 97 && c <= 122) { break }
            }
        } else {
            out = out + s[i]
            i += 1
        }
    }
    emit out
}

// ── Cursor save/restore + clear variants not in the base set ─────────

func cursorSave()     { emit _esc() + "s" }
func cursorRestore()  { emit _esc() + "u" }
func clearScrollback(){ emit _esc() + "3J" }
func clearLineLeft()  { emit _esc() + "1K" }
func clearLineRight() { emit _esc() + "0K" }
func clearBelow()     { emit _esc() + "0J" }
func clearAbove()     { emit _esc() + "1J" }

// Background truecolor (foreground rgb() already exists).
func bgRgb(r, g, b, s) {
    let prefix = sbNew()
    prefix = sbAppend(prefix, _esc())
    prefix = sbAppend(prefix, "48;2;")
    prefix = sbAppend(prefix, r + "")
    prefix = sbAppend(prefix, ";")
    prefix = sbAppend(prefix, g + "")
    prefix = sbAppend(prefix, ";")
    prefix = sbAppend(prefix, b + "")
    prefix = sbAppend(prefix, "m")
    let b2 = sbNew()
    b2 = sbAppend(b2, sbToString(prefix))
    b2 = sbAppend(b2, s)
    b2 = sbAppend(b2, _sgr("0"))
    emit sbToString(b2)
}

// OSC-8 clickable hyperlink. Renders in modern terminals (Windows
// Terminal, iTerm2, kitty, recent VTE) as underlined clickable text.
func hyperlink(url, text) {
    let ESC = fromCharCode(27)
    let b = sbNew()
    b = sbAppend(b, ESC)
    b = sbAppend(b, "]8;;")
    b = sbAppend(b, url)
    b = sbAppend(b, ESC)
    b = sbAppend(b, "\\")
    b = sbAppend(b, text)
    b = sbAppend(b, ESC)
    b = sbAppend(b, "]8;;")
    b = sbAppend(b, ESC)
    b = sbAppend(b, "\\")
    emit sbToString(b)
}
