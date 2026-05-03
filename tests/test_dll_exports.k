// test_dll_exports.k — minimal DLL export test
// Compile: kcc -o test_exports.dll --headers headers tests/test_dll_exports.k

export func kr_testfn(a, b) {
    emit a + " " + b
}

export func kr_testmul(a, b) {
    emit a * b
}
