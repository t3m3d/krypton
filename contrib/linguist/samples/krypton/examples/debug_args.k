just run {
    let ac = argCount()
    kp("argCount: " + ac)
    if ac > 0 {
        let a = arg(0)
        kp("arg(0): " + a)
        let src = readFile(a)
        kp("len: " + len(src))
        kp("first50: " + substring(src, 0, 50))
    }
    emit "ok"
}
