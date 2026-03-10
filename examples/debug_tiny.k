just run {
    let src = readFile("examples/tiny.k")
    kp(len(src))
    kp(src)
    emit "ok"
}
