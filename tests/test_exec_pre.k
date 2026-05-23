just run {
    kp("before")
    let out = exec("echo captured")
    kp(out)
    kp("after")
}
