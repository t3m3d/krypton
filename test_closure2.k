func makeAdder(n) {
    emit func(x) { emit toInt(x) + toInt(n) + "" }
}

just run {
    let add5 = makeAdder("5")
    let result = add5("3")
    kp(result)
    if result == "8" { kp("PASS closure works!") } else { kp("FAIL got: " + result) }
}
