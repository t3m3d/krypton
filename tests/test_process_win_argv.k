// Windows argv and command-line quoting acceptance tests.

import "k:process_win_argv"

func processArgvCheck(name, ok) {
    if ok { kp("[PASS] " + name) }
    else { kp("[FAIL] " + name)  exit("1") }
}

func processArgvByte(s, index) {
    emit toInt(charCode(substring(s, index, index + 1)))
}

just run {
    processArgvCheck("plain argument stays plain", processQuoteArg("plain") == "plain")
    processArgvCheck("empty argument quoted", processQuoteArg("") == "\"\"")
    processArgvCheck("space argument quoted", processQuoteArg("two words") == "\"two words\"")

    let embedded = processQuoteArg("a\"b")
    processArgvCheck("embedded quote length", len(embedded) == 6)
    processArgvCheck("embedded quote escaped", processArgvByte(embedded, 0) == 34 && processArgvByte(embedded, 2) == 92 && processArgvByte(embedded, 3) == 34 && processArgvByte(embedded, 5) == 34)

    let trailing = processQuoteArg("C:\\Program Files\\Tool\\")
    processArgvCheck("trailing slash quoted", processArgvByte(trailing, 0) == 34 && processArgvByte(trailing, len(trailing) - 1) == 34)
    processArgvCheck("trailing slash doubled", processArgvByte(trailing, len(trailing) - 2) == 92 && processArgvByte(trailing, len(trailing) - 3) == 92)

    let args = processArgsNew()
    args = processArgsAdd(args, "")
    args = processArgsAdd(args, "two words")
    args = processArgsAdd(args, "a\"b")
    args = processArgsAdd(args, "C:\\tail\\")
    processArgvCheck("argv count", processArgsCount(args) == 4)
    processArgvCheck("argv empty survives", processArgAt(args, 0) == "")
    processArgvCheck("argv spaces survive", processArgAt(args, 1) == "two words")
    processArgvCheck("argv quote survives", processArgAt(args, 2) == "a\"b")
    processArgvCheck("argv slash survives", processArgAt(args, 3) == "C:\\tail\\")

    let command = processCommandLine("C:\\Program Files\\Krypton\\tool.exe", args)
    processArgvCheck("executable path quoted", startsWith(command, "\"C:\\Program Files\\Krypton\\tool.exe\""))
    processArgvCheck("command keeps empty argv", contains(command, " \"\" "))
    kp("[PASS] Windows argv acceptance suite")
}