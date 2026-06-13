// examples/win_modern_demo.k -- Win11-modern chrome on top of stdlib/gui.k.
//
// Demonstrates the 2026-06-13 frontend modernization:
//   guiEnableModernChrome()    -- per-monitor v2 DPI + Segoe UI 9pt cached
//   guiEnableDarkTitle(win)    -- DWMWA_USE_IMMERSIVE_DARK_MODE=20
//   guiApplyExplorerTheme(c)   -- modern theme on widgets
//   guiApplyFont(hwnd)         -- swap in Segoe UI 9pt
//
// Build (once x64_host is regenerated):
//   kcc.exe examples/win_modern_demo.k -o win_modern_demo.exe
//   .\win_modern_demo.exe
//
// For the Common-Controls v6 manifest -- the last piece needed for the
// fully modern button/listview chrome -- drop a sidecar
// `win_modern_demo.exe.manifest` next to the binary with the
// <assembly>...<dependentAssembly Microsoft.Windows.Common-Controls
// version=6.0.0.0...>.../assembly> payload until x64.k learns to embed
// it directly in the PE rsrc section.

import "k:gui"

just run {
    guiEnableModernChrome()

    let win = guiWindow("Modern Krypton GUI", 480, 280)
    guiEnableDarkTitle(win)

    let lbl = guiLabel(win, "Per-monitor v2 DPI + Segoe UI + dark title bar.", 20, 20, 440, 24)
    guiApplyFont(lbl)

    let txt = guiTextInput(win, 20, 60, 440, 28)
    guiApplyFont(txt)
    guiApplyExplorerTheme(txt)

    let btn = guiButton(win, "Themed Button", 20, 110, 200, 32)
    guiApplyFont(btn)
    guiApplyExplorerTheme(btn)

    guiShow(win)
    guiRun()
}
