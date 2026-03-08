just run {
    let ac = argCount()
    print("argCount: " + ac)
    if ac > 0 {
        let a = arg(0)
        print("arg(0): " + a)
        let src = readFile(a)
        print("len: " + len(src))
        print("first50: " + substring(src, 0, 50))
    }
}
