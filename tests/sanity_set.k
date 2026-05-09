just run {
    let buf = bufNew(8)
    print("buf len before set: " + len(buf))
    bufSetByte(buf, 0, 65)
    print("buf len after set: " + len(buf))
    bufSetByte(buf, 0, 0)
    bufSetByte(buf, 1, 65)
    print("buf len after set offset-1: " + len(buf))
}
