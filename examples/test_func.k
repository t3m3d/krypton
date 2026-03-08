func add(a, b) {
    emit a + b
}

go run {
    let x = add(3, 4)
    kp(x)
    emit "ok"
}
