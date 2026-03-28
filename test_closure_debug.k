func makeAdder(n) {
    emit func(x) { emit toInt(x) + toInt(n) + "" }
}

just run {
    let add5 = makeAdder("5")
    kp("add5 value: " + add5)
    let result = add5("3")
    kp("result: " + result)
}
