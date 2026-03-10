just run {
    let src = readFile("examples/hello.k")
    kp(len(src))
    kp(src)
    emit "ok"
}
