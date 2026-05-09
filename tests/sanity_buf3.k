just run {
    let buf = bufNew(8)
    print("buf as int: " + ptrToInt(buf))
    bufSetByte(buf, 0, 65)
    print("after set, buf as int: " + ptrToInt(buf))
}
