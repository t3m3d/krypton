just run {
    let src = readFile("examples/hello.k")
    let paired = src + ",99"
    kp("paired len: " + len(paired))
    let v = pairVal(paired)
    let pos = pairPos(paired)
    kp("val len: " + len(v))
    kp("pos: " + pos)
    kp("val: " + v)
    emit "ok"
}
