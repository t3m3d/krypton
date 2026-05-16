just run {
    let buf = bufNew(8)
    bufSetByte(buf, 0, 65)
    bufSetByte(buf, 1, 66)
    print("direct bufGetByte(buf, 0) = " + bufGetByte(buf, 0))
    print("direct bufGetByte(buf, 1) = " + bufGetByte(buf, 1))
}
