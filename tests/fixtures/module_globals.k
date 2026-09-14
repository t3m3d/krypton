module module_globals

import "module_globals_head.krh"

let importedModuleNumber = importedInitialize()
let importedModuleText = importedHeaderText + "ready"

func importedReadNumber() { emit importedModuleNumber }
func importedReadText() { emit importedModuleText }
func importedReadCount() { emit importedInitCount }
func importedIncrement() {
    importedModuleNumber = importedModuleNumber + 1
    emit importedModuleNumber
}
func importedShadow() {
    let importedModuleNumber = 99
    emit importedModuleNumber
}
func importedParamShadow(importedModuleNumber) { emit importedModuleNumber }
