// tests/x11_handshake_smoke.k — proves stdlib/x11.k speaks the X11
// wire protocol against a real (TCP-listening) X server, and parses
// the full server-info reply via the Linux Phase C buffer machinery.
//
// Run with:
//     /usr/sbin/Xvfb :1 -listen tcp -screen 0 800x600x24 &
//     kcc -r tests/x11_handshake_smoke.k
//
// Default target is display :1 (TCP port 6001) on 127.0.0.1.
// Exits 0 on a clean accepted handshake, prints [FAIL] + exits 1 otherwise.
// run_linux.sh treats [FAIL] in output as a failure regardless of rc.

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

    let info = x11Handshake(fd)
    let r = x11ResponseByte(info)
    print("server response byte: " + r + " (1=accept, 0=fail, 2=auth-needed)")

    if x11Failed(info) {
        print("[FAIL] x11 server refused handshake: " + x11FailReason(info))
        sockClose(fd)
        exit(1)
    }
    if x11NeedsAuth(info) {
        print("[FAIL] x11 server requires auth — restart Xvfb with -ac")
        sockClose(fd)
        exit(1)
    }
    if x11Accepted(info) == 0 {
        print("[FAIL] unexpected response byte " + r)
        sockClose(fd)
        exit(1)
    }

    print("[PASS] x11 handshake accepted")
    print("vendor:           " + x11Vendor(info))
    print("proto:            " + x11ProtoMajor(info) + "." + x11ProtoMinor(info))
    print("release:          " + x11ReleaseNumber(info))
    print("rid base:         " + x11ResourceIdBase(info))
    print("rid mask:         " + x11ResourceIdMask(info))
    print("max-request-len:  " + x11MaxRequestLen(info) + " * 4 bytes")
    print("num-screens:      " + x11NumScreens(info))
    print("num-formats:      " + x11NumFormats(info))
    print("image-byte-order: " + x11ImageByteOrder(info) + " (0=LSB)")
    print("keycode range:    " + x11MinKeycode(info) + " .. " + x11MaxKeycode(info))

    sockClose(fd)
    exit(0)
}
