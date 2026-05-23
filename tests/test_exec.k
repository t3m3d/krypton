// Test exec: capture child stdout.
just run {
    kp("before")
    let out = exec("echo captured")
    kp("captured = [" + out + "]")
    kp("after")
}
