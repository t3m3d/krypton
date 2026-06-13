// stdlib/iphlp.k -- ergonomic wrappers around iphlpapi.dll.
//
// Wired through the IAT in compiler/windows_x86/x64.k 2026-06-13.
//
// Usage:
//   import "k:iphlp"
//   let names = adapterNames()       -- newline-joined "Local Area Connection"...
//   let ips = adapterIPv4s()         -- one IPv4 per adapter (dotted quad)
//   let rtt = ping("8.8.8.8", 1000)  -- ms, or "-1" on failure
//
// On macOS the parallel calls come off SystemConfiguration + getifaddrs.
// Names are platform-agnostic so cross-platform tooling shares one surface.

module iphlp

import "head:iphlpapi"

// IP_ADAPTER_INFO is 640 bytes (typedef MAX_ADAPTER_NAME_LENGTH=256,
// MAX_ADAPTER_DESCRIPTION_LENGTH=128 ...).  We grab 16 KB of buffer up
// front -- enough for ~25 adapters which is far past any real machine.
let _IPHLP_BUF_BYTES = "16384"

// Returns newline-joined adapter friendly names ("Ethernet", "Wi-Fi", ...).
// Uses the legacy GetAdaptersInfo for compactness; GetAdaptersAddresses
// is wired too if a caller needs IPv6 or modern metadata.
func adapterNames() {
    let buf = bufNew(_IPHLP_BUF_BYTES)
    let sizeBuf = bufNew("4")
    bufSetDwordAt(sizeBuf, "0", _IPHLP_BUF_BYTES)
    let rc = GetAdaptersInfo(buf, sizeBuf)
    if rc != "0" { emit "" }

    // IP_ADAPTER_INFO layout (relevant offsets, x64 alignment):
    //   +0   Next             (PIP_ADAPTER_INFO, 8 bytes)
    //   +8   ComboIndex       (DWORD)
    //   +12  AdapterName[260]
    //   +272 Description[132]
    let out = sbNew()
    let cur = bufGetQwordAt(buf, "0")
    let first = "1"
    let baseAddr = ptrToInt(buf)
    let curAddr = baseAddr
    while toInt(curAddr) != 0 {
        if first == "0" { out = sbAppend(out, "\n") }
        first = "0"
        let nameOff = toInt(curAddr) - toInt(baseAddr) + 272
        out = sbAppend(out, _iphlpCStr(buf, nameOff, 132))
        let nextPtr = bufGetQwordAt(buf, toStr(toInt(curAddr) - toInt(baseAddr)))
        curAddr = nextPtr
    }
    emit sbToString(out)
}

// Returns newline-joined dotted-quad IPv4 addresses, one per adapter.
// Adapters without an IPv4 yield "0.0.0.0".
func adapterIPv4s() {
    let buf = bufNew(_IPHLP_BUF_BYTES)
    let sizeBuf = bufNew("4")
    bufSetDwordAt(sizeBuf, "0", _IPHLP_BUF_BYTES)
    let rc = GetAdaptersInfo(buf, sizeBuf)
    if rc != "0" { emit "" }

    // IP_ADDR_STRING (IPv4 list head) at +416:
    //   +0  Next (PIP_ADDR_STRING)
    //   +8  IpAddress.String[16]   -- "192.168.1.10"
    let out = sbNew()
    let baseAddr = ptrToInt(buf)
    let curAddr = baseAddr
    let first = "1"
    while toInt(curAddr) != 0 {
        if first == "0" { out = sbAppend(out, "\n") }
        first = "0"
        let curOff = toInt(curAddr) - toInt(baseAddr)
        let ipOff = curOff + 416 + 8
        out = sbAppend(out, _iphlpCStr(buf, ipOff, 16))
        let nextPtr = bufGetQwordAt(buf, toStr(curOff))
        curAddr = nextPtr
    }
    emit sbToString(out)
}

// Ping a dotted-quad IPv4 once with the given timeout (ms).
// Returns round-trip time in ms, or "-1" on any failure.
func ping(ipv4, timeoutMs) {
    let h = IcmpCreateFile()
    if ptrToInt(h) == "0" { emit "-1" }
    // inet_addr lives in ws2_32 -- but we only need to parse the dotted
    // quad to a little-endian DWORD.  Do it inline.
    let addr = _iphlpParseIPv4(ipv4)
    if addr == "-1" {
        IcmpCloseHandle(h)
        emit "-1"
    }
    let req = bufNew("32")
    let i = 0
    while i < 32 { bufSetByte(req, toStr(i), "65")  i += 1 }
    // ICMP_ECHO_REPLY is 28 bytes + payload + ip-options + slop.
    let reply = bufNew("128")
    let rc = IcmpSendEcho(h, addr, req, "32", "0", reply, "128", timeoutMs)
    IcmpCloseHandle(h)
    if rc == "0" { emit "-1" }
    // Reply layout: +0 Address(DWORD) +4 Status(DWORD) +8 RoundTripTime(DWORD)
    let rtt = bufGetDwordAt(reply, "8")
    emit rtt
}

func _iphlpParseIPv4(s) {
    let parts = sbNew()
    let i = 0
    let cur = sbNew()
    let n = 0
    let acc = 0
    while i <= len(s) {
        if i == len(s) || s[i] == "." {
            let part = toInt(sbToString(cur))
            if part < 0 || part > 255 { emit "-1" }
            acc = acc + part * (256 ** n)  // little-endian network byte order
            n += 1
            cur = sbNew()
            if n > 4 { emit "-1" }
        } else {
            cur = sbAppend(cur, s[i])
        }
        i += 1
    }
    if n != 4 { emit "-1" }
    emit toStr(acc)
}

func _iphlpCStr(buf, off, cap) {
    let out = sbNew()
    let i = 0
    while i < cap {
        let b = bufGetByte(buf, toStr(off + i))
        if b == "0" { emit sbToString(out) }
        out = sbAppend(out, chr(b))
        i += 1
    }
    emit sbToString(out)
}
