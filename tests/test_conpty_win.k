// Persistent PowerShell ConPTY integration smoke.

import "k:conpty_win"

func conptyCheck(name, ok) {
    if ok { kp("[PASS] " + name) }
    else { kp("[FAIL] " + name)  exit("1") }
}

just run {
    let powershell = "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
    let args = processArgsNew()
    args = processArgsAdd(args, "-NoLogo")
    args = processArgsAdd(args, "-NoProfile")

    let environment = processEnvironmentNew()
    let options = processOptionsNew()
    options = processOptionSet(options, "tree", "1")

    let terminal = conptySpawn(powershell, args, environment, "", 80, 24, options)
    conptyCheck("ConPTY spawn", conptyIsValid(terminal))
    if !conptyIsValid(terminal) {
        kp("ConPTY error=" + conptyLastError(terminal))
        exit("1")
    }

    conptyCheck("ConPTY resize", conptyResize(terminal, 100, 30))
    conptyCheck("ConPTY dimensions", conptyColumns(terminal) == 100 && conptyRows(terminal) == 30)

    let command = "[Console]::Out.Write('conpty-ok;TERM='+$env:TERM+';COLOR='+$env:COLORTERM+';NO='+$env:NO_COLOR); exit\r\n"
    let input = bytesFromUtf8(command)
    conptyCheck("ConPTY write", conptyWrite(terminal, input) == bytesLen(input))

    let code = conptyWait(terminal, 10000)
    if code == -2 {
        conptyKill(terminal, 1)
        conptyClose(terminal)
        kp("[FAIL] ConPTY timeout")
        exit("1")
    }
    conptyCheck("ConPTY child exit", code == 0)

    let output = conptyRead(terminal, 65536)
    let text = bytesToUtf8(output)
    conptyCheck("persistent shell output", contains(text, "conpty-ok"))
    conptyCheck("terminal environment", contains(text, "TERM=xterm-256color") && contains(text, "COLOR=truecolor"))
    conptyCheck("NO_COLOR removed", contains(text, "NO="))
    conptyClose(terminal)
    kp("[PASS] ConPTY integration smoke")
}