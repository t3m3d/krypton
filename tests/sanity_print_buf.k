just run {
    let buf = bufNew(8)
    print(buf)
    print("after print, len=" + len(buf))
    let s = bufStr(buf)
    print("s len=" + len(s))
}
