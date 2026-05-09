// bufGetByte smoke test — verify the 1.8.1 builtin reads the right
// byte from a string treated as a byte buffer. Compares each byte
// against charCode(s[i]) which is the existing slow path.

just run {
    let s = "ABCDxyz!"
    let i = 0
    while i < 8 {
        let b = bufGetByte(s, i)
        let c = charCode(s[i])
        if b != c {
            print("FAIL at " + i + ": bufGetByte=" + b + " charCode=" + c)
            exit(1)
        }
        i += 1
    }
    print("OK 8/8 bytes match")
}
