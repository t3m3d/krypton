just run {
    let out = exec("echo hello from exec")
    kp("Result: " + out)
    if out == "hello from exec" {
        kp("PASS exec builtin works")
    } else {
        kp("FAIL got: '" + out + "'")
    }
}
