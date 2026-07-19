// Binary-safe ByteBuffer and Unicode acceptance tests.

import "k:bytes"

func bytesCheck(name, ok) {
    if ok { kp("[PASS] " + name) }
    else { kp("[FAIL] " + name)  exit("1") }
}

func byteAt(s, i) { emit toInt(charCode(substring(s, i, i + 1))) }

just run {
    let all = bytesWithLength(256)
    let i = 0
    while i < 256 { bytesSet(all, i, i)  i += 1 }
    i = 0
    while i < 256 {
        if toInt(bytesGet(all, i)) != i { kp("[FAIL] all byte values at " + i)  exit("1") }
        i += 1
    }
    bytesCheck("all 256 byte values survive", 1)
    bytesCheck("embedded NUL preserves following byte", bytesGet(all, 0) == "0" && bytesGet(all, 1) == "1")


    let typed = bytesWithLength(16)
    bytesWriteU16LE(typed, 0, 4660)
    bytesWriteU32LE(typed, 2, 305419896)
    bytesWriteU64LE(typed, 6, "72623859790382856")
    bytesCheck("little-endian u16", bytesReadU16LE(typed, 0) == "4660")
    bytesCheck("little-endian u32", bytesReadU32LE(typed, 2) == "305419896")
    bytesCheck("little-endian u64", bytesReadU64LE(typed, 6) == "72623859790382856")
    bytesWriteI8(typed, 0, -1)
    bytesWriteI16LE(typed, 1, -32768)
    let signed32 = 0 - (1073741824 * 2 - 1)
    let signed64 = (0 - (1073741824 * 4)) - 1
    bytesWriteI32LE(typed, 3, signed32)
    bytesWriteI64LE(typed, 7, signed64)
    bytesCheck("signed i8", bytesReadI8(typed, 0) == -1)
    bytesCheck("signed i16", bytesReadI16LE(typed, 1) == -32768)
    bytesCheck("signed i32", bytesReadI32LE(typed, 3) == signed32)
    bytesCheck("signed i64", bytesReadI64LE(typed, 7) == signed64)

    let part = bytesSlice(all, 252, 256)
    bytesCheck("slice length", bytesLen(part) == 4)
    bytesCheck("slice copy", bytesGet(part, 0) == "252" && bytesGet(part, 3) == "255")
    bytesZero(part, 1, 2)
    bytesCheck("zero range", bytesGet(part, 0) == "252" && bytesGet(part, 1) == "0" && bytesGet(part, 2) == "0" && bytesGet(part, 3) == "255")
    bytesCopy(all, 1, all, 0, 5)
    bytesCheck("overlapping copy", bytesGet(all, 1) == "0" && bytesGet(all, 2) == "1" && bytesGet(all, 5) == "4")

    let env = utf16leEnvironmentBlock("TERM=xterm-256color\nCOLORTERM=truecolor\n")
    bytesCheck("UTF-16LE environment block length", bytesLen(env) == 82)
    bytesCheck("UTF-16LE embedded separator", bytesReadU16LE(env, 38) == "0")
    bytesCheck("UTF-16LE double terminator", bytesReadU16LE(env, 78) == "0" && bytesReadU16LE(env, 80) == "0")
    let emptyEnv = utf16leEnvironmentBlock("")
    bytesCheck("empty environment has double NUL", bytesLen(emptyEnv) == 4 && bytesReadU16LE(emptyEnv, 0) == "0" && bytesReadU16LE(emptyEnv, 2) == "0")

    let appended = bytesNew(0)
    appended = bytesAppendU32LE(appended, 305419896)
    appended = bytesAppendUPtrLE(appended, "72623859790382856")
    bytesCheck("append u32", bytesReadU32LE(appended, 0) == "305419896")
    bytesCheck("pointer-sized roundtrip", bytesReadUPtrLE(appended, 4) == "72623859790382856")

    let euroA = bytesWithLength(2)
    bytesSet(euroA, 0, 226)
    bytesSet(euroA, 1, 130)
    let euroB = bytesWithLength(1)
    bytesSet(euroB, 0, 172)
    let decoder = utf8DecoderNew()
    let first = utf8DecodeChunk(decoder, euroA, 0)
    let second = utf8DecodeChunk(decoder, euroB, 1)
    bytesCheck("split UTF-8 waits for completion", first == "")
    bytesCheck("split UTF-8 rune", len(second) == 3 && byteAt(second, 0) == 226 && byteAt(second, 1) == 130 && byteAt(second, 2) == 172)

    let malformed = bytesWithLength(3)
    bytesSet(malformed, 0, 226)
    bytesSet(malformed, 1, 40)
    bytesSet(malformed, 2, 161)
    let repaired = bytesToUtf8(malformed)
    bytesCheck("malformed UTF-8 replacement length", len(repaired) == 7)
    bytesCheck("malformed UTF-8 replacement bytes", byteAt(repaired, 0) == 239 && byteAt(repaired, 1) == 191 && byteAt(repaired, 2) == 189 && byteAt(repaired, 3) == 40)

    let emoji = fromCharCode(240) + fromCharCode(159) + fromCharCode(152) + fromCharCode(128)
    let wide = utf16leEncode(emoji, 1)
    bytesCheck("UTF-16LE surrogate pair", bytesReadU16LE(wide, 0) == "55357" && bytesReadU16LE(wide, 2) == "56832")
    let roundtrip = utf16leDecode(wide, 1)
    bytesCheck("UTF-16LE supplementary roundtrip", len(roundtrip) == 4 && byteAt(roundtrip, 0) == 240 && byteAt(roundtrip, 3) == 128)

    kp("[PASS] binary buffer acceptance suite")
}
