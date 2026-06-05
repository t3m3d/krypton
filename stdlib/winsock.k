// stdlib/winsock.k — Krypton wrappers over the Windows ws2_32.dll IAT.
//
// Mirrors the BSD-style API exposed by server_native on Linux/macOS,
// so a Krypton HTTP server can write to sockMake/sockBind/... and have
// it work on all three platforms.
//
// Adds (or maps existing names to) these Krypton-level functions:
//
//   wsInit()                 → "1" if WSAStartup succeeded, "0" otherwise
//   wsSocket()               → SOCKET fd, or -1 on failure
//   wsBind(fd, port)         → "0" on success (or non-zero error)
//   wsListen(fd, backlog)    → "0" on success
//   wsAccept(fd)             → client fd, or -1
//   wsRecv(fd, buf, len)     → bytes read, 0 = peer closed, -1 = error
//   wsSend(fd, str, len)     → bytes sent, -1 = error
//   wsClose(fd)              → 0/-1
//
// Pair with k:server_native — once that file's Linux/macOS sockMake/
// sockBind/etc. are aliased to these wsXxx wrappers on Windows, the
// example HTTP server runs unchanged across all three platforms.
//
// Implementation notes:
//   - sockaddr_in is 16 bytes laid out manually via a bufNew().
//   - AF_INET = 2, SOCK_STREAM = 1, INADDR_ANY = 0.
//   - htons() is called via the IAT to byte-swap the port to network order.
//   - WSAStartup gets a 512-byte WSADATA buffer (oversized; struct is ~400 B).

module winsock

func wsInit() {
    let wsa = bufNew(512)
    // MAKEWORD(2,2) = 0x0202 = 514
    let rc = WSAStartup("514", wsa)
    if toInt(rc) == 0 { emit "1" }
    emit "0"
}

func wsSocket() {
    // socket(AF_INET=2, SOCK_STREAM=1, 0)
    emit socket("2", "1", "0")
}

// Build a sockaddr_in for INADDR_ANY:port and call bind().
// Returns "0" on success, error code on failure.
func wsBind(fd, port) {
    let sa = bufNew(16)
    // sin_family = 2 (WORD)
    bufSetWordAt(sa, "0", "2")
    // sin_port = htons(port)
    let nport = htons(port + "")
    bufSetWordAt(sa, "2", nport)
    // sin_addr.s_addr = INADDR_ANY = 0 (DWORD)
    bufSetDwordAt(sa, "4", "0")
    // sin_zero[8] already zero from bufNew
    emit bind(fd + "", sa, "16")
}

func wsListen(fd, backlog) {
    emit listen(fd + "", backlog + "")
}

func wsAccept(fd) {
    emit accept(fd + "", "0", "0")
}

// recv with a caller-provided buffer (raw pointer / Krypton buf).
// Caller is responsible for sizing the buffer.
func wsRecv(fd, buf, maxLen) {
    emit recv(fd + "", buf, maxLen + "", "0")
}

// send the raw bytes of the Krypton string `s` (length len(s)).
func wsSend(fd, s, n) {
    emit send(fd + "", s, n + "", "0")
}

func wsClose(fd) {
    emit closesocket(fd + "")
}

// ── Aliases matching server_native naming (drop-in compat) ───────────

func sockMakeWin() {
    if wsInit() == "0" { emit "-1" }
    emit wsSocket()
}

func sockBindWin(fd, port)    { emit wsBind(fd, port) }
func sockListenWin(fd)        { emit wsListen(fd, "128") }
func sockAcceptWin(fd)        { emit wsAccept(fd) }
func sockSendWin(fd, s, n)    { emit wsSend(fd, s, n) }
func sockCloseWin(fd)         { emit wsClose(fd) }

// Read up to maxLen bytes from `fd` and return as a Krypton string.
// Reads until \r\n\r\n (end of HTTP headers) or buffer fills.
// Returns "" on disconnect / error.
func sockRecvStrWin(fd) {
    let maxLen = 16384
    let buf = bufNew(maxLen + 1)
    let total = 0
    while total < maxLen {
        let n = toInt(wsRecv(fd, buf, maxLen - total))
        if n <= 0 {
            if total == 0 { emit "" }
            // mark end
            bufSetByte(buf, total + "", "0")
            emit bufStr(buf)
        }
        total = total + n
        // Look for \r\n\r\n in the last 4 bytes received.
        if total >= 4 {
            let b0 = toInt(bufGetByte(buf, (total - 4) + ""))
            let b1 = toInt(bufGetByte(buf, (total - 3) + ""))
            let b2 = toInt(bufGetByte(buf, (total - 2) + ""))
            let b3 = toInt(bufGetByte(buf, (total - 1) + ""))
            if b0 == 13 && b1 == 10 && b2 == 13 && b3 == 10 {
                bufSetByte(buf, total + "", "0")
                emit bufStr(buf)
            }
        }
    }
    bufSetByte(buf, maxLen + "", "0")
    emit bufStr(buf)
}
