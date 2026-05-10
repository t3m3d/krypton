// stdlib/mmap.k — memory-mapped files for Krypton.
//
// Reads happen on page-fault — no `readFile` copy of the entire file
// into the GC heap. Critical for tools that scan large files (LSP,
// log analyzers) where you only need a small window of bytes.
//
//   import "stdlib/mmap.k"
//   let m = mmapFile("big.log")           // m is an env handle
//   if mmapOk(m) == "1" {
//       let p = mmapPtr(m)
//       // p[i] reads byte i directly from the mapped pages
//       print("first byte: " + bufGetByte(p, 0))
//       mmapClose(m)
//   }
//
// State is stored as a Krypton env (envNew/envSet/envGet) — raw pointers
// round-trip cleanly through env (unlike string concat which calls
// strlen and truncates at the first NUL byte).
//
// Limitations:
// - Read-only. Writable mappings (PAGE_READWRITE + FILE_MAP_WRITE) are
//   a follow-up; the API shape stays the same.
// - Caller must mmapClose(m) — there's no GC integration for mmap regions.
// - Currently does not auto-fetch file size; size field is informational.

import "head:windows"
import "head:process"
import "head:mmap"

// Open `path` for read-only memory mapping. Returns an env on success
// (mmapOk == "1") with keys: "ptr", "h", "hMap"; or empty env on error.
func mmapFile(path) {
    let GENERIC_READ          = 2147483648   // 0x80000000 as decimal
    let FILE_SHARE_READ       = 1
    let OPEN_EXISTING         = 3
    let FILE_ATTRIBUTE_NORMAL = 128
    let PAGE_READONLY         = 2
    let FILE_MAP_READ         = 4

    let env = envNew()

    let h = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, "0",
                        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, "0")
    if toInt(h) == 0 { emit env }

    let hMap = CreateFileMappingA(h, "0", PAGE_READONLY, 0, 0, "0")
    if toInt(hMap) == 0 {
        CloseHandle(h)
        emit env
    }

    let view = MapViewOfFile(hMap, FILE_MAP_READ, 0, 0, 0)
    // view is a raw pointer (LPVOID) — store via envSet which preserves
    // the raw value.
    env = envSet(env, "h", h)
    env = envSet(env, "hMap", hMap)
    env = envSet(env, "ptr", view)
    emit env
}

func mmapOk(m)   { emit hasField(m, "ptr") }
func mmapPtr(m)  { emit envGet(m, "ptr") }

func mmapClose(m) {
    if mmapOk(m) == "0" { emit "0" }
    UnmapViewOfFile(envGet(m, "ptr"))
    CloseHandle(envGet(m, "hMap"))
    CloseHandle(envGet(m, "h"))
    emit "1"
}
