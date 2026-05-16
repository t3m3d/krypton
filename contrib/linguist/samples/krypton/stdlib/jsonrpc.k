// stdlib/jsonrpc.k — Content-Length framed JSON-RPC over stdio.
//
// Wire format (per LSP spec, mirroring vscode-jsonrpc):
//
//     Content-Length: <N>\r\n
//     \r\n
//     <N bytes of UTF-8 JSON body>
//
// 2.0+: pure Krypton via stdlib/winio.k. No cfunc body, no setvbuf+fread.
// Win32 ReadFile/WriteFile on the standard handles is byte-clean by
// definition — the CRT's CRLF translation never enters the picture.
// Works through both the native PE pipeline (KR32_FUNCS marshalling in
// x64.k) and the C+gcc pipeline (compileWin32IntArgs marshalling in
// compile.k).
//
// Public API:
//   jrInit()                  — cheap noop kept for source compatibility
//                               with the 1.x cfunc version.
//   jrReadFrame()             — blocks until next full frame, returns body.
//                               Returns "" on EOF.
//   jrWriteFrame(body)        — writes a Content-Length-prefixed frame.
//   jrLog(s)                  — writes "[kls] <s>\n" to stderr.

module jsonrpc

import "k:winio"

// 1.x compat shim — Win32 ReadFile/WriteFile don't need setmode.
func jrInit() { emit "1" }

// Strip trailing "\r\n" or "\n" from a line winioReadLine returned.
// Krypton C-emit escapes "\r" as literal backslash-r in some paths; use
// fromCharCode(13) to get the actual carriage return.
func _jr_chomp(line) {
    let CR = fromCharCode("13")
    let LF = fromCharCode("10")
    let n = len(line)
    if n == 0 { emit "" }
    let last = substring(line, n - 1, n)
    if last != LF { emit line }
    if n == 1 { emit "" }
    let prev = substring(line, n - 2, n - 1)
    if prev == CR { emit substring(line, 0, n - 2) }
    emit substring(line, 0, n - 1)
}

// Case-insensitive prefix check.
func _jr_hasPrefix(s, prefix) {
    if len(s) < len(prefix) { emit "0" }
    let a = toLower(substring(s, 0, len(prefix)))
    let b = toLower(prefix)
    if a == b { emit "1" }
    emit "0"
}

func jrReadFrame() {
    let h = winioStdin()
    let contentLen = -1
    let sawHeader  = 0
    let done       = 0
    while done == 0 {
        let raw = winioReadLine(h)
        if len(raw) == 0 {
            if sawHeader == 0 { emit "" }
            done = 1
        } else {
            let line = _jr_chomp(raw)
            sawHeader = 1
            if line == "" {
                done = 1
            } else {
                if _jr_hasPrefix(line, "Content-Length:") == "1" {
                    let rest = substring(line, len("Content-Length:"), len(line))
                    contentLen = toInt(trim(rest))
                }
            }
        }
    }

    if contentLen < 0 { emit "" }
    if contentLen == 0 { emit "" }
    emit winioReadBytes(h, contentLen + "")
}

func jrWriteFrame(body) {
    let h = winioStdout()
    let CRLF = fromCharCode("13") + fromCharCode("10")
    let HEADER_END = CRLF + CRLF
    if len(body) == 0 {
        winioWrite(h, "Content-Length: 0" + HEADER_END)
        emit "1"
    }
    let n = len(body)
    winioWrite(h, "Content-Length: " + n + HEADER_END)
    winioWrite(h, body)
    emit "1"
}

func jrLog(s) {
    let h = winioStderr()
    if len(s) == 0 {
        winioWriteLine(h, "[kls] (null)")
        emit "1"
    }
    winioWriteLine(h, "[kls] " + s)
    emit "1"
}
