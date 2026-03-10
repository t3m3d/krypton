just run {
    let a = 10
    let b = 5
    let li = toInt(a)
    let ri = toInt(b)
    kp("a=" + a)
    kp("b=" + b)
    kp("li=" + li)
    kp("ri=" + ri)
    let numL = li + "" == a
    let numR = ri + "" == b
    kp("numL=" + numL)
    kp("numR=" + numR)
    if li > ri {
        kp("li > ri")
    }
    if a > b {
        kp("a > b")
    }
    emit "ok"
}
