// tests/x11_handshake_smoke.k — proves stdlib/x11.k speaks the X11
// wire protocol against a real (TCP-listening) X server.
//
// Run with:
//     /usr/sbin/Xvfb :1 -listen tcp -screen 0 800x600x24 &
//     kcc -r tests/x11_handshake_smoke.k
//
// Default target is display :1 (TCP port 6001) on 127.0.0.1.
//
// Exits 0 on a clean accepted handshake, prints [FAIL] + exits 1 otherwise.
// run_linux.sh treats [FAIL] in output as a failure regardless of rc.
//
// NOTE: This is the Phase A1 smoke. Once agent-l ports bufNew /
// bufSetByte / bufGet*At to elf.k (see LINUX_RELEASE_TODO.md →
// "Needed from agent-l"), stdlib/x11.k will gain x11Vendor /
// x11ResourceIdBase / etc. accessors and this test will print
// the full server-info dump.

import "k:x11"

just run {
    let display = 1
    let host = "127.0.0.1"
    let port = 6000 + display

    print("x11_handshake_smoke: connecting to " + host + ":" + port)
    let fd = x11Connect(host, display)
    if fd < 0 {
        print("[FAIL] x11Connect returned -1 — is Xvfb running on :" + display + "?")
        print("       try: /usr/sbin/Xvfb :" + display + " -listen tcp -screen 0 800x600x24 &")
        exit(1)
    }

    let r = x11Handshake(fd)
    print("server response byte: " + r + " (1=accept, 0=fail, 2=auth-needed, -1=closed)")

    if r == 1 {
        print("[PASS] x11 handshake accepted — wire protocol works")
        sockClose(fd)
        exit(0)
    }
    if r == 0 {
        print("[FAIL] x11 server refused handshake")
    } else if r == 2 {
        print("[FAIL] x11 server requires auth — restart Xvfb with -ac")
    } else {
        print("[FAIL] x11 server closed connection without reply (r=" + r + ")")
    }
    sockClose(fd)
    exit(1)
}
