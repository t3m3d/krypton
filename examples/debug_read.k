just run {
    let a = arg(0)
    let src = readFile(a)
    let slen = len(src)
    kp(slen)
    let i = 0
    while i < slen {
        let c = src[i]
        if c == "\n" {
            kp("NL at " + i)
        }
        if c == "\r" {
            kp("CR at " + i)
        }
        i += 1
    }
    kp("done")
    emit "ok"
}
