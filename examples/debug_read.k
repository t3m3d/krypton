just run {
    let a = arg(0)
    let src = readFile(a)
    let slen = len(src)
    print(slen)
    let i = 0
    while i < slen {
        let c = src[i]
        if c == "\n" {
            print("NL at " + i)
        }
        if c == "\r" {
            print("CR at " + i)
        }
        i = i + 1
    }
    print("done")
}
