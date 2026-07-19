// stdlib/bytes_file_win.k -- binary-safe Windows file I/O.

module bytes_file_win

import "k:bytes"
import "head:fileio"

func _bytesWinInvalidHandle(handle) {
    emit handle == "0" || handle == "-1" || handle == "18446744073709551615"
}

func bytesReadFileWin(path) {
    let empty = bytesNew(0)
    let handle = CreateFileA(path, "2147483648", 1, 0, 3, 128, 0)
    if _bytesWinInvalidHandle(handle) { emit empty }

    let sizePtr = bufNew(8)
    if GetFileSizeEx(handle, sizePtr) == "0" {
        CloseHandle(handle)
        emit empty
    }
    let size = toInt(bufGetQword(sizePtr))
    if size < 0 {
        CloseHandle(handle)
        emit empty
    }

    let output = bytesWithLength(size)
    let total = 0
    while total < size {
        let chunk = size - total
        if chunk > 16777216 { chunk = 16777216 }
        let readPtr = bufNew(8)
        if ReadFile(handle, ptrAdd(bytesRaw(output), total), chunk, readPtr, 0) == "0" {
            CloseHandle(handle)
            emit empty
        }
        let got = toInt(bufGetDword(readPtr))
        if got <= 0 { break }
        total += got
    }
    CloseHandle(handle)
    bytesSetLength(output, total)
    emit output
}

func bytesWriteFileWin(path, data) {
    let handle = CreateFileA(path, 1073741824, 0, 0, 2, 128, 0)
    if _bytesWinInvalidHandle(handle) { emit 0 }

    let total = 0
    while total < bytesLen(data) {
        let chunk = bytesLen(data) - total
        if chunk > 16777216 { chunk = 16777216 }
        let wrotePtr = bufNew(8)
        if WriteFile(handle, ptrAdd(bytesRaw(data), total), chunk, wrotePtr, 0) == "0" {
            CloseHandle(handle)
            emit 0
        }
        let wrote = toInt(bufGetDword(wrotePtr))
        if wrote <= 0 {
            CloseHandle(handle)
            emit 0
        }
        total += wrote
    }
    CloseHandle(handle)
    emit 1
}

func bytesDeleteFileWin(path) { emit DeleteFileA(path) }