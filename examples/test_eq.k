just run {
    let val = 42
    kp("val=" + val)
    kp("eq42=" + (val == 42))
    kp("eq0=" + (val == 0))
    kp("eq_str=" + (val == "42"))
    emit "ok"
}
