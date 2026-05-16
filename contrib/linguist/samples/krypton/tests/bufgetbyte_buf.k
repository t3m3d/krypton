just run {
    let b = bufNew(16)
    bufSetByte(b, 0, 65)   // 'A'
    bufSetByte(b, 1, 66)   // 'B'
    print("buf[0]=" + bufGetByte(b, 0))
    print("buf[1]=" + bufGetByte(b, 1))
}
