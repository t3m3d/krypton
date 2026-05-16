// Smoke test for term.k. Press q to quit; everything else echoes its key token.
import "term.k"

just run {
    let ok = tInit()
    if ok != "1" {
        printErr("tInit failed (not a tty?)")
        emit 1
    }
    let sz = tSize()
    tWrite("kcode term smoke — terminal: ")
    tWrite(sz)
    tWrite(" — press q to quit\r\n")
    tFlush()

    let running = 1
    while running == 1 {
        let k = tReadKey()
        tWrite("key: [")
        tWrite(k)
        tWrite("]\r\n")
        tFlush()
        if k == "q" { running = 0 }
        if k == "C-c" { running = 0 }
        if k == "EOF" { running = 0 }
    }
    tRestore()
}
