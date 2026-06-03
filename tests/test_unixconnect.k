// Test the unixConnect(path) builtin (Linux AF_UNIX socket connect).
//
// unixConnect does socket(AF_UNIX, SOCK_STREAM, 0) then connect() to a Unix
// domain socket path, returning the fd on success or a negative errno on
// failure. It's the transport for pure-Krypton X11 / Wayland clients (those
// display sockets are AF_UNIX, and the older sockConnect is AF_INET/TCP only).
//
// We can't assume a server socket exists in CI, so this verifies the failure
// path: connecting to a non-existent path must return a negative errno and
// must NOT segfault (the builtin builds a sockaddr_un on the stack — a bug
// there would crash rather than return cleanly).

func check(name, cond) {
    if cond { kp("[PASS] " + name) } else { kp("[FAIL] " + name) }
}

just run {
    kp("unixConnect Tests")
    kp("=================")
    let r = unixConnect("/tmp/.krypton-no-such-socket-zzzz")
    check("bogus path returns negative errno", r < 0)
    check("ENOENT (-2) for missing socket",    r == 0 - 2)
    check("survived the call (no segfault)",   1 == 1)
}
