#!/usr/bin/env kr

import "k:okui"
import "k:objk_runtime_macos"

let focusCleanupRuns = 0
let scoreableProtocol = 0

func focusCleanup(runtime, self) {
    focusCleanupRuns += 1
    emit 0
}

func focusScore(runtime, self) {
    if !okKHas(runtime, self, "score") { emit 0 }
    emit okKGet(runtime, self, "score")
}

func focusAdjust(runtime, self, amount) {
    let next = focusScore(runtime, self) + amount
    if next < 0 { next = 0 }
    emit doKSet(runtime, self, "score", next)
}

func focusCombine(runtime, self, other) {
    focusAdjust(runtime, self, focusScore(runtime, other))
    emit self
}

func makeFocusClass(runtime) {
    scoreableProtocol = okKProtocol(runtime, "Scoreable", 0)
    doKRequireMethod(runtime, scoreableProtocol, "score", 0, 0, 0, 0)
    doKRequireMethod(runtime, scoreableProtocol, "adjust", 1, 0, 0, 0)
    doKRegisterProtocol(runtime, scoreableProtocol)

    let focus = okKClass(runtime, "Focus", 0)
    okKMethod(runtime, focus, "score", 0, funcptr(focusScore))
    okKMethod(runtime, focus, "adjust", 1, funcptr(focusAdjust))
    okKObjectMethod(runtime, focus, "combine", 1, funcptr(focusCombine), focus, 0, focus)
    doKCleanup(runtime, focus, funcptr(focusCleanup))
    doKConform(runtime, focus, scoreableProtocol)
    doKRegister(runtime, focus)
    emit focus
}

func makeFocusState(runtime, first, second) {
    let stateClass = okKClass(runtime, "FocusState", 0)
    doKRegister(runtime, stateClass)
    let state = okKNew(runtime, stateClass)
    doKOwn(runtime, state, "work", first)
    doKOwn(runtime, state, "rest", second)
    doKWeak(runtime, first, "peer", second)
    doKWeak(runtime, second, "peer", first)
    doKRelease(runtime, first)
    doKRelease(runtime, second)
    emit state
}

let focusRuntime = okKRuntime(65536)
let focusClass = makeFocusClass(focusRuntime)
let focusState = makeFocusState(
    focusRuntime,
    okKNew(focusRuntime, focusClass),
    okKNew(focusRuntime, focusClass)
)
let workLabel = 0
let restLabel = 0
let focusStatus = 0

func workModel() { emit okKGet(focusRuntime, focusState, "work") }
func restModel() { emit okKGet(focusRuntime, focusState, "rest") }

func refreshFocus() {
    doText(workLabel, "Work  " + okKSend(focusRuntime, workModel(), "score"))
    doText(restLabel, "Rest  " + okKSend(focusRuntime, restModel(), "score"))
    emit 0
}

func addWork(self, cmd, sender) {
    okKSend1(focusRuntime, workModel(), "adjust", 1)
    doText(focusStatus, "Work score updated")
    refreshFocus()
    emit done()
}

func addRest(self, cmd, sender) {
    okKSend1(focusRuntime, restModel(), "adjust", 1)
    doText(focusStatus, "Rest score updated")
    refreshFocus()
    emit done()
}

func combineFocus(self, cmd, sender) {
    okKSend1(focusRuntime, workModel(), "combine", restModel())
    doText(focusStatus, "Rest score added to work")
    refreshFocus()
    emit done()
}

func resetFocus(self, cmd, sender) {
    doKSet(focusRuntime, workModel(), "score", 0)
    doKSet(focusRuntime, restModel(), "score", 0)
    doText(focusStatus, "Scores reset")
    refreshFocus()
    emit done()
}

func quitFocus(self, cmd, sender) {
    doKRelease(focusRuntime, focusState)
    doQuit()
    emit done()
}

just run {
    app("Objective-K Focus")
    let bar = menuBar()
    let applicationMenu = menu(bar, "Objective-K Focus")
    menuAction(applicationMenu, "Quit", "q", funcptr(quitFocus))

    let win = window("Objective-K Focus", 520, 300)
    minSize(win, 520, 300)
    let root = page(520, 300, 28)
    title(win, "Focus score", top(root, 32))
    workLabel = label(win, "Work  0", left(row(root, 1, 44, 18), 180))
    restLabel = label(win, "Rest  0", right(row(root, 1, 44, 18), 180))

    let controls = row(root, 2, 34, 14)
    let workButton = button(win, "+ Work", left(controls, 100))
    let restButton = button(win, "+ Rest", rightOf(left(controls, 100), 16, 100))
    let combineButton = button(win, "Combine", rightOf(left(controls, 216), 16, 110))
    let resetButton = button(win, "Reset", right(controls, 90))
    focusStatus = label(win, "Ready", bottom(root, 24))

    doClick(workButton, "focus.work", funcptr(addWork))
    doClick(restButton, "focus.rest", funcptr(addRest))
    doClick(combineButton, "focus.combine", funcptr(combineFocus))
    doClick(resetButton, "focus.reset", funcptr(resetFocus))

    if arg("0") == "--smoke" {
        msg_1(workButton, "performClick:", 0)
        msg_1(workButton, "performClick:", 0)
        msg_1(restButton, "performClick:", 0)
        msg_1(combineButton, "performClick:", 0)
        if okKSend(focusRuntime, workModel(), "score") != 3 ||
            okKSend(focusRuntime, restModel(), "score") != 1 ||
            okKConforms(focusRuntime, workModel(), scoreableProtocol) != 1 ||
            okKGet(focusRuntime, workModel(), "peer") != restModel() ||
            text(workLabel) != "Work  3" || text(restLabel) != "Rest  1" {
            kp("[FAIL] Objective-K Focus integration")
            exit("1")
        }
        doKRelease(focusRuntime, focusState)
        if focusCleanupRuns != 2 { kp("[FAIL] Objective-K Focus cleanup"); exit("1") }
        kp("[PASS] Objective-K Focus integration")
        exit("0")
    }

    doShow(win)
    doRun()
}
