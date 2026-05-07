// 15_image.k — display an image.
//
// guiImage loads .bmp / .ico via Win32 LoadImage and PNG / JPEG /
// GIF / TIFF via GDI+ (resolved at runtime, no extra link flag).
// guiImageSet swaps the displayed image for a new path.
//
// Pair with guiOpenFile to make a "browse for image" flow.

import "stdlib/gui.k"


let g_image = ""
let g_label = ""


func onPick() {
    let p = guiOpenFile("Pick an image",
                        "Images|*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.ico,All|*.*")
    if len(p) > 0 {
        guiImageSet(g_image, p)
        guiSetText(g_label, p)
    }
}


just run {
    guiInit()
    let win = guiWindow("Image Tutorial", 480, 320)

    g_image = guiImage(win, "assets/krypton.ico", 24, 24, 96, 96)

    let bP = guiButton(win, "Pick image", 140, 32, 200, 36)
    guiOnClick(bP, funcptr(onPick))

    g_label = guiLabel(win, "assets/krypton.ico", 140, 80, 320, 22)

    guiShow(win)
    guiRun()
}
