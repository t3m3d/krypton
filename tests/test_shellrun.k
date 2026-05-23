// Test shellRun: spawn cmd.exe /C echo, wait, get "0".
just run {
    kp("before")
    let r = shellRun("echo from-shell")
    kp("returned: " + r)
    kp("after")
}
