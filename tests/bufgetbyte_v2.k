just main {
    let s = "ABCD"
    print("before call")
    let n = 0
    print("about to call bufGetByte")
    let b = bufGetByte(s, n)
    print("after call: " + b)
}
