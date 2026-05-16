just run {
    let p = rawAlloc(8)
    print("rawAlloc -> hex: " + hex(p) + " len: " + len(p))
    let buf = bufNew(8)
    print("bufNew -> hex: " + hex(buf) + " len: " + len(buf))
}
