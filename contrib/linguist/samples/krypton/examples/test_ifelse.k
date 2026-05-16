just run {
    let val = 42
    kp("val=" + val)
    if val == 42 {
        kp("found it")
    }
    if val == 42 {
        kp("match")
    } else {
        kp("no match")
    }
    if val == 42 {
        kp("yes")
    } else if val == 0 {
        kp("zero")
    } else {
        kp("other")
    }
    emit "ok"
}
