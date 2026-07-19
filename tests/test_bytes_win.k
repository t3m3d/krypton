// Windows native binary file I/O acceptance test.

import "k:bytes"
import "k:bytes_file_win"

func bytesWinCheck(name, ok) {
    if ok { kp("[PASS] " + name) }
    else { kp("[FAIL] " + name)  exit("1") }
}

just run {
    let all = bytesWithLength(256)
    let i = 0
    while i < 256 { bytesSet(all, i, i)  i += 1 }

    let path = "_krypton_bytes_roundtrip.bin"
    bytesWinCheck("binary file write", bytesWriteFileWin(path, all))
    let loaded = bytesReadFileWin(path)
    bytesWinCheck("binary file length", bytesLen(loaded) == 256)
    i = 0
    while i < 256 {
        if bytesGet(loaded, i) != bytesGet(all, i) {
            bytesDeleteFileWin(path)
            kp("[FAIL] binary file byte " + i)
            exit("1")
        }
        i += 1
    }
    bytesDeleteFileWin(path)
    bytesWinCheck("binary file preserves 0x00-0xFF", 1)
}