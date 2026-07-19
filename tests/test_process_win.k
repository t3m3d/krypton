// Shell-free CreateProcessW integration smoke.

import "k:process_win"

func processWinCheck(name, ok) {
    if ok { kp("[PASS] " + name) }
    else { kp("[FAIL] " + name)  exit("1") }
}

just run {
    let powershell = "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
    let args = processArgsNew()
    args = processArgsAdd(args, "-NoLogo")
    args = processArgsAdd(args, "-NoProfile")
    args = processArgsAdd(args, "-NonInteractive")
    args = processArgsAdd(args, "-Command")
    args = processArgsAdd(args, "[Console]::OutputEncoding=[Text.UTF8Encoding]::new();[Console]::Out.Write($env:KRYPTON_PROCESS_TEST+'|'+(Get-Location).Path);[Console]::Error.Write('stderr-ok')")

    let euro = fromCharCode(226) + fromCharCode(130) + fromCharCode(172)
    let environment = processEnvironmentNew()
    environment = processEnvironmentSet(environment, "KRYPTON_PROCESS_TEST", "unicode-" + euro)
    let options = processOptionsNew()
    options = processOptionSet(options, "no_window", "1")
    options = processOptionSet(options, "tree", "1")

    let child = processSpawn(powershell, args, environment, "C:\\Windows", options)
    processWinCheck("CreateProcessW spawn", processIsValid(child))
    if !processIsValid(child) {
        kp("GetLastError=" + processLastError(child))
        exit("1")
    }

    let code = processWait(child, 10000)
    if code == -2 {
        processKill(child, 1)
        processClose(child)
        kp("[FAIL] process timeout")
        exit("1")
    }
    processWinCheck("process exit code", code == 0)

    let stdoutBytes = processReadStdout(child, 65536)
    let stderrBytes = processReadStderr(child, 65536)
    let stdoutText = bytesToUtf8(stdoutBytes)
    let stderrText = bytesToUtf8(stderrBytes)
    processWinCheck("UTF-8 environment override", contains(stdoutText, "unicode-" + euro))
    processWinCheck("explicit working directory", contains(toLower(stdoutText), "c:\\windows"))
    processWinCheck("stderr separate", stderrText == "stderr-ok")
    processClose(child)
    kp("[PASS] structured Windows process smoke")
}