// stdlib/shell.k -- ergonomic wrappers around shell32.dll.
//
// Wired through the IAT in compiler/windows_x86/x64.k 2026-06-13,
// so callers reach ShellExecuteA / SHBrowseForFolderA / SHGetFolderPathA
// directly -- no LoadLibrary dance, no curl-style "shell out to explorer".
//
// Usage:
//   import "k:shell"
//   shellOpen("readme.txt")             -- launch in default app
//   shellOpenUrl("https://krypton-lang.org")
//   shellRevealInExplorer("C:\\krypton")
//   let dir = shellPickFolder("Choose a folder")
//   let home = shellKnownFolder("profile")
//
// On the macOS side the same calls map onto NSWorkspace via Objective-K;
// keep the function names stable so cross-platform programs port cleanly.

module shell

import "head:shell32"

// SW_SHOWNORMAL=1, SW_SHOWMINIMIZED=2, SW_HIDE=0.
let SW_SHOWNORMAL = "1"

// Launch a file / URL / folder with the system default handler.
// Returns the raw HINSTANCE (>32 = success per MSDN).  Caller usually
// discards the value -- the side effect is the launch.
func shellOpen(target) {
    emit ShellExecuteA("0", "open", target, "0", "0", SW_SHOWNORMAL)
}

// Convenience: open a URL in the user's default browser.
func shellOpenUrl(url) {
    emit ShellExecuteA("0", "open", url, "0", "0", SW_SHOWNORMAL)
}

// Reveal a file or folder in Explorer (selects it when given a file).
func shellRevealInExplorer(path) {
    emit ShellExecuteA("0", "explore", path, "0", "0", SW_SHOWNORMAL)
}

// Run a file with the "print" verb (printers route through this).
func shellPrint(path) {
    emit ShellExecuteA("0", "print", path, "0", "0", SW_SHOWNORMAL)
}

// Classic folder picker.  Returns the chosen path, or "" if cancelled.
// title may be empty for a default caption.
func shellPickFolder(title) {
    let bi = bufNew("64")
    bufSetQwordAt(bi, "24", ptrToInt(title))
    // BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE = 0x41 = 65
    bufSetDwordAt(bi, "32", "65")
    let pidl = SHBrowseForFolderA(bi)
    if ptrToInt(pidl) == "0" { emit "" }
    let pathBuf = bufNew("260")
    SHGetPathFromIDListA(pidl, pathBuf)
    CoTaskMemFree(pidl)
    emit _shellBufToStr(pathBuf, 260)
}

// Known-folder paths via the CSIDL surface (good enough for the common
// cases; full IKnownFolderManager support deferred).  Recognised keys:
//   "desktop"        -> Desktop directory
//   "documents"      -> Documents folder
//   "downloads"      -> Downloads folder (synthesised: profile + "\\Downloads")
//   "appdata"        -> Roaming AppData
//   "local_appdata"  -> Local AppData
//   "profile"        -> User profile root
// Returns "" if the lookup fails.
func shellKnownFolder(kind) {
    let csidl = "-1"
    if kind == "desktop"        { csidl = "16" }
    if kind == "documents"      { csidl = "5"  }
    if kind == "appdata"        { csidl = "26" }
    if kind == "local_appdata"  { csidl = "28" }
    if kind == "profile"        { csidl = "40" }
    if kind == "downloads" {
        let prof = shellKnownFolder("profile")
        if prof == "" { emit "" }
        emit prof + "\\Downloads"
    }
    if csidl == "-1" { emit "" }
    let buf = bufNew("260")
    let rc = SHGetFolderPathA("0", csidl, "0", "0", buf)
    if rc != "0" { emit "" }
    emit _shellBufToStr(buf, 260)
}

func _shellBufToStr(buf, cap) {
    let out = sbNew()
    let i = 0
    while i < cap {
        let b = bufGetByte(buf, i)
        if b == "0" { emit sbToString(out) }
        out = sbAppend(out, chr(b))
        i += 1
    }
    emit sbToString(out)
}
