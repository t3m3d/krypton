just run {
    let r1 = shellRun("exit 0")
    kp("ok: " + r1)
    let r2 = shellRun("exit 7")
    kp("err: " + r2)
    let r3 = shellRun("exit 42")
    kp("err2: " + r3)
}
