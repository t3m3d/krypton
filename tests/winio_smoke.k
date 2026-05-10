// 2.0: Krypton-side stdio via Win32 IAT.
// stdlib/winio.k uses GetStdHandle + WriteFile/ReadFile directly —
// no cfunc body, no setvbuf+fread. Smoke-tests the writes (reads
// would need a piped stdin, harder to arrange in a regression).

import "k:winio"

just run {
    let out = winioStdout()
    let ok1 = winioWrite(out, "[PASS] winioWrite OK")
    winioWrite(out, fromCharCode(10))
    let ok2 = winioWriteLine(out, "[PASS] winioWriteLine OK")

    if toInt(ok1) > "0" {
        winioWriteLine(out, "[PASS] winioWrite returned non-zero")
    } else {
        winioWriteLine(out, "[FAIL] winioWrite returned zero")
    }
}
