objk
protocol Named {
    require label() -> text
}

objk protocol Scoreable extends Named {
    require score() -> int
    require adjust(amount: int) -> int
}

objk object Focus conforms Scoreable {
    method label() -> text = focusLabel
    method score() -> int = focusScore
    method adjust(amount: int) -> int = focusAdjust
}

objk object DoubleFocus extends Focus {
    method score() -> int = doubleScore
}

func focusLabel(runtime, self) { emit okKGet(runtime, self, "label") }
func focusScore(runtime, self) { emit okKGet(runtime, self, "score") }
func focusAdjust(runtime, self, amount) {
    emit doKSet(runtime, self, "score", focusScore(runtime, self) + amount)
}
func doubleScore(runtime, self) { emit focusScore(runtime, self) * 2 }

func check(name, expected, actual) {
    if expected != actual { kp("[FAIL] " + name); exit("1") }
    kp("[PASS] " + name)
}

just run {
    let object = okKNew(__objkRuntime, DoubleFocus)
    let label = okKText(__objkRuntime, "Compiler syntax")
    doKText(__objkRuntime, object, "label", label)
    doKReleaseText(__objkRuntime, label)
    doKSet(__objkRuntime, object, "score", 20)
    check("protocol parent", 1, okKConforms(__objkRuntime, object, Named))
    check("class protocol", 1, okKConforms(__objkRuntime, object, Scoreable))
    check("typed text", "Compiler syntax", okKTextValue(__objkRuntime, okKSend(__objkRuntime, object, "label")))
    check("inherited method", 25, okKSend1(__objkRuntime, object, "adjust", 5))
    check("override", 50, okKSend(__objkRuntime, object, "score"))
    doKRelease(__objkRuntime, object)
}
