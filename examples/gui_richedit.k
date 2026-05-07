// gui_richedit.k — smoke test for the RichEdit widget added for the
// kcode-win → Krypton port. Shows a few colored, bold runs.

import "stdlib/gui.k"

just run {
    guiInit()
    let win = guiWindow("RichEdit smoke", 720, 420)
    let r = guiRichEdit(win, 16, 16, 688, 360)
    guiRichSetMonoFont(r, "Consolas", 11)
    guiRichAppend(r, "func ",            "d96565", 1)
    guiRichAppend(r, "main",             "b392f0", 0)
    guiRichAppend(r, "() ",              "FFA657", 0)
    guiRichAppend(r, "{",                "4FC1FF", 0)
    guiRichAppend(r, "\r\n    let x ",   "d96565", 1)
    guiRichAppend(r, "= ",               "a01818", 1)
    guiRichAppend(r, "42",               "4FC1FF", 0)
    guiRichAppend(r, " // hello\r\n",    "9a9a9a", 0)
    guiRichAppend(r, "}",                "4FC1FF", 0)
    guiRichReadOnly(r, 1)
    guiShow(win)
    guiRun()
}
