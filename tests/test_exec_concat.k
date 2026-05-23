just run {
    kp("before")
    let out = exec("echo captured")
    kp("got: " + out)
    kp("after")
}
