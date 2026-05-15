import "head:windows"
import "head:fileio"

func kfcls() {
    let E = fromCharCode(27)
    kp(E + "[2J" + E + "[H")
    emit ""
}

func kfstdout() {
    emit GetStdHandle("4294967285")
}

func kfinit() {
    SetConsoleOutputCP("65001")
    let h       = kfstdout()
    let modeBuf = bufNew("4")
    bufSetDword(modeBuf, "0")
    GetConsoleMode(h, modeBuf)
    let m    = toInt(bufGetDword(modeBuf))
    let newm = bitOr(m + "", "4")
    SetConsoleMode(h, newm)
    emit ""
}

import "utils.k"
import "cpu.k"
import "os.k"
import "mem.k"
import "disk.k"
import "gpu.k"

func run() {
    kfcls()
    kfinit()

    let E     = fromCharCode(27)
    let GRN   = E + "[32;1m"
    let CYN   = E + "[36;1m"
    let RST   = E + "[0m"

    let usr  = sysuser()
    let host = syshost()
    let arch = sysarch()
    let os   = osver()

    kp("User: " + usr)
    kp("Host: " + host)
    kp("OS: " + os + " " + arch)
}
