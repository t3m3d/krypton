// win_paint.k — placeholder for the paint/canvas demo.
//
// Build:
//   kcc examples/win_paint.k -o win_paint.exe
//
// The original cfunc-based version (pre-2.2) used a custom WindowProc
// + WM_LBUTTONDOWN / WM_MOUSEMOVE / WM_LBUTTONUP handlers to track drag
// strokes and BeginPaint/EndPaint to render them. `stdlib/gui.k`
// doesn't yet surface a 2D canvas / paint primitive, so a faithful
// port would still need raw Win32 GDI calls.
//
// Once a `guiCanvas` widget lands (planned alongside the wider
// "Krypton drives the DOM" / "Krypton drives Cocoa" frontend work),
// the drag-to-paint flow becomes ~25 lines:
//
//     let cv = guiCanvas(win, 0, 0, 600, 400)
//     guiOnPointer(cv, funcptr(onPointer))
//
// For now this file is a stub — running it opens a window with a
// "Paint canvas not yet wired" message, so it stays valid against
// the current native pipeline and contains no `cfunc` blocks.

import "k:gui"

just run {
    guiInit()
    let win = guiWindow("Krypton Paint (placeholder)", 600, 400)
    guiLabel(win, "guiCanvas / paint primitives are pending in stdlib/gui.k.",
             20, 30, 560, 40)
    guiLabel(win, "Track its progress in docs/krypton_gui_tiers.md.",
             20, 70, 560, 40)
    guiShow(win)
    guiRun()
}
