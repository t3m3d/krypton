// pairVal/pairPos defined inline (stdlib/pair.k auto-import doesn't yet
// resolve via the native pipeline — see test_pair_ops.k for the same dodge).
func _findLastComma(s) {
    let i = len(s) - 1
    while i >= 0 {
        if s[i] == "," { emit i }
        i = i - 1
    }
    emit -1
}

func pairVal(p) {
    let c = _findLastComma(p)
    if c < 0 { emit p }
    emit substring(p, 0, c)
}

func pairPos(p) {
    let c = _findLastComma(p)
    emit toInt(substring(p, c + 1, len(p)))
}

just run {
    let src = readFile("examples/hello.k")
    let paired = src + ",99"
    kp("paired len: " + len(paired))
    let v = pairVal(paired)
    let pos = pairPos(paired)
    kp("val len: " + len(v))
    kp("pos: " + pos)
    kp("val: " + v)
    emit "ok"
}
