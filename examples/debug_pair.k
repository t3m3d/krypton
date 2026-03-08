just run {
    let src = readFile("examples/hello.k")
    let paired = src + ",99"
    print("paired len: " + len(paired))
    let v = pairVal(paired)
    let pos = pairPos(paired)
    print("val len: " + len(v))
    print("pos: " + pos)
    print("val: " + v)
}
