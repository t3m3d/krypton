// _minimal_rich.ks — smallest possible RichEdit visibility test.
// No module globals, no ANSI parser, no theme: just open window,
// drop one RichEdit, push one line of text in white. If the line
// shows up, gui.k path works and stem_win has a higher-level bug.
// If it stays blank, gui.k's guiRichAppend isn't painting and the
// blocker is below my code.

import "k:gui"

just run {
    guiSetWindowBg("0x0a0a0a")
    guiInit()
    let win   = guiWindow("min-rich-test-0xprefix", 800, 400)
    let edit  = guiRichEdit(win, 0, 0, 800, 400)
    guiRichSetMonoFont(edit, "Cascadia Mono", 14)
    guiRichSetBg(edit, "0x0a0a0a")
    guiRichSetFgDefault(edit, "0xe8e8e8")
    guiRichAppend(edit, "HELLO ON DARK BG\n",          "0xffffff", "0")
    guiRichAppend(edit, "second line, red\n",          "0xff4040", "0")
    guiRichAppend(edit, "third line, green bold\n",    "0x40ff40", "1")
    guiShow(win)
    guiRun()
}
