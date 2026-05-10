// 2.0-alpha-3 mmap: read-only memory-mapped file via Win32
// CreateFileMappingA + MapViewOfFile. Useful for LSP / log scanners
// that need byte-level access without slurping the whole file into the
// GC heap.

import "k:mmap"

just run {
    let path = "c:/tmp/mmap_smoke.bin"
    writeFile(path, "Hello, mmap world!")

    let m = mmapFile(path)
    if mmapOk(m) == "1" {
        let p = mmapPtr(m)
        // Spot-check known bytes
        if bufGetByte(p, 0) == "72" {
            print("[PASS] byte 0 = 'H'")
        } else {
            print("[FAIL] byte 0 wrong: " + bufGetByte(p, 0))
        }
        if bufGetByte(p, 7) == "109" {
            print("[PASS] byte 7 = 'm'")
        } else {
            print("[FAIL] byte 7 wrong: " + bufGetByte(p, 7))
        }
        if bufGetByte(p, 17) == "33" {
            print("[PASS] byte 17 = '!'")
        } else {
            print("[FAIL] byte 17 wrong: " + bufGetByte(p, 17))
        }
        mmapClose(m)
        print("[PASS] closed cleanly")
    } else {
        print("[FAIL] mmapOk returned 0")
    }
}
