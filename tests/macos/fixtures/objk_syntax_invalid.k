objk protocol Broken {
    require value(amount) -> int
}

just run { kp("[FAIL] expected syntax rejection") }
