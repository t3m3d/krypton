// gui_image.k — image widget demo.
//
// Build:
//   kcc.exe examples/gui_image.k > tmp.c
//   gcc tmp.c -o gui_image.exe -luser32 -lgdi32 -lcomctl32 -lcomdlg32 \
//       -lole32 -lshell32 -ldwmapi -luxtheme -ladvapi32 -lm -w
//
// Loads a .ico file into the window. The "Pick Image" button opens a
// file dialog; whatever you pick replaces the displayed image.
// Supported: .bmp / .ico (Win32 LoadImage) plus .png / .jpeg / .gif /
// .tiff (GDI+ via runtime LoadLibrary). No extra link flag needed —
// gdiplus.dll is resolved on first use.

import "stdlib/gui.k"


let g_image = ""
let g_label = ""


func onPick() {
    let path = guiOpenFile("Pick an image",
                           "Images|*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.ico,All|*.*")
    if len(path) > 0 {
        guiImageSet(g_image, path)
        guiSetText(g_label, path)
    }
}


just run {
    guiInit()
    let win = guiWindow("Image Widget Demo", 520, 320)

    g_image = guiImage(win, "assets/krypton.ico", 24, 24, 96, 96)

    let bPick = guiButton(win, "Pick Image", 140, 32, 200, 36)
    guiOnClick(bPick, funcptr(onPick))

    g_label = guiLabel(win, "assets/krypton.ico", 140, 80, 360, 22)

    guiShow(win)
    guiRun()
}
