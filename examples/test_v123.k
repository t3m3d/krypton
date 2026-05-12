// v1.2.3 feature test

let greeting = "hello from global"
let count: int = 42

func logIt(msg) -> zero {
    printErr(msg)
}

func addInts(a, b) -> int {
    emit toInt(a) + toInt(b)
}

just run {
    logIt(greeting)
    printErr("count = " + count)
    let result = addInts("10", "32")
    printErr("10 + 32 = " + result)
}
