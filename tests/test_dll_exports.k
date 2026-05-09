// test_dll_exports.k — minimal DLL export test
// Build as DLL: kcc -o test_exports.dll tests/test_dll_exports.k
// The `just run` block also exercises the exported funcs in-process so
// the standard regression runner (builds as EXE) covers them too.

export func kr_testfn(a, b) {
    emit a + " " + b
}

export func kr_testmul(a, b) {
    emit a * b
}

just run {
    let s = kr_testfn("hello", "world")
    print("kr_testfn=" + s)
    let p = kr_testmul(6, 7)
    print("kr_testmul=" + p)
}
