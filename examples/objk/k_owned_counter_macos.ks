#!/usr/bin/env kr

import "k:okui"
import "k:objk_runtime_macos"

let counterCleanupRuns = 0

func modelCleanup(runtime, self) {
    counterCleanupRuns += 1
    emit 0
}
func modelValue(runtime, self) {
    if !okKHas(runtime, self, "value") { emit 0 }
    emit okKGet(runtime, self, "value")
}
func modelAdd(runtime, self, amount) {
    emit doKSet(runtime, self, "value", modelValue(runtime, self) + amount)
}
func makeCounterClass(runtime) {
    let counter = okKClass(runtime, "Counter", 0)
    okKMethod(runtime, counter, "value", 0, funcptr(modelValue))
    okKMethod(runtime, counter, "add", 1, funcptr(modelAdd))
    doKCleanup(runtime, counter, funcptr(modelCleanup))
    emit doKRegister(runtime, counter)
}
func makeCounterState(runtime, model) {
    let stateClass = okKClass(runtime, "CounterState", 0)
    doKRegister(runtime, stateClass)
    let state = okKNew(runtime, stateClass)
    doKOwn(runtime, state, "model", model)
    doKRelease(runtime, model)
    emit state
}

let counterRuntime = okKRuntime(65536)
let counterClass = makeCounterClass(counterRuntime)
let counterModel = okKNew(counterRuntime, counterClass)
let counterState = makeCounterState(counterRuntime, counterModel)
let counterDisplay = 0

func currentModel() { emit okKGet(counterRuntime, counterState, "model") }
func refreshCounter() {
    doText(counterDisplay, "" + okKSend(counterRuntime, currentModel(), "value"))
    emit 0
}
func increment(self, cmd, sender) {
    okKSend1(counterRuntime, currentModel(), "add", 1)
    refreshCounter()
    emit done()
}
func decrement(self, cmd, sender) {
    okKSend1(counterRuntime, currentModel(), "add", 0 - 1)
    refreshCounter()
    emit done()
}
func quitCounter(self, cmd, sender) {
    doKRelease(counterRuntime, counterState)
    doQuit()
    emit done()
}

just run {
    app("Objective-K Counter")
    let bar = menuBar()
    let applicationMenu = menu(bar, "Objective-K Counter")
    menuAction(applicationMenu, "Quit", "q", funcptr(quitCounter))
    let win = window("Objective-K Counter", 320, 180)
    minSize(win, 320, 180)
    counterDisplay = label(win, "0", okRect(145, 100, 80, 32))
    let minus = button(win, "-", okRect(86, 42, 64, 32))
    let plus = button(win, "+", okRect(170, 42, 64, 32))
    doClick(plus, "kcore.increment", funcptr(increment))
    doClick(minus, "kcore.decrement", funcptr(decrement))

    if arg("0") == "--smoke" {
        // Exercise the native target/action callback without Accessibility.
        msg_1(plus, "performClick:", 0)
        msg_1(plus, "performClick:", 0)
        msg_1(minus, "performClick:", 0)
        if okKSend(counterRuntime, counterModel, "value") != 1 || text(counterDisplay) != "1" {
            kp("[FAIL] K model/native callback integration")
            exit("1")
        }
        doKRelease(counterRuntime, counterState)
        if okKRefCount(counterRuntime, counterModel) != 0 || counterCleanupRuns != 1 {
            kp("[FAIL] K model ownership cleanup")
            exit("1")
        }
        kp("[PASS] K model/native callback integration")
        exit("0")
    }

    doShow(win)
    doRun()
}
