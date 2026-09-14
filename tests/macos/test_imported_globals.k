import "../fixtures/module_globals.k"
import "../fixtures/module_globals.k"

let importedEntryNumber = importedReadNumber() + 2

func check(name, expected, actual) {
    if expected != actual {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
        exit("1")
    }
    kp("[PASS] " + name)
}

just run {
    check("imported initializer", 20, importedReadNumber())
    check("header constant", 17, importedHeaderNumber)
    check("computed string", "setTitle:ready", importedReadText())
    check("entry initializer order", 22, importedEntryNumber)
    check("initialized once", 1, importedReadCount())
    check("mutable global", 21, importedIncrement())
    check("global shared across calls", 21, importedReadNumber())
    check("local shadow", 99, importedShadow())
    check("parameter shadow", 123, importedParamShadow(123))
    check("shadow preserves global", 21, importedReadNumber())
}
