just run {
    let buf = bufNew(8)
    bufSetByte(buf, 0, 65)
    bufSetByte(buf, 1, 66)
    bufSetByte(buf, 2, 67)
    bufSetByte(buf, 3, 0)
    print("via bufStr: " + bufStr(buf))
    print("via bufGetByte 0: " + bufGetByte(buf, 0))
    print("via bufGetDwordAt 0: " + bufGetDwordAt(buf, 0))
}
