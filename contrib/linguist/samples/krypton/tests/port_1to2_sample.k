// Sample program with 1.x patterns that --port-1to2 should flag.
// Run: `kcc --port-1to2 tests/port_1to2_sample.k` and verify all 8
// warning categories fire.
//
// This is NOT meant to compile/run — it deliberately uses patterns
// that future-2.0-Krypton wants to discourage.

let g_state = ""        // file-scope let

func setX(v) {
    g_state = v          // mutable global reassign — port-1to2 should warn
}

just run {
    let buf = bufNew(64)              // port-1to2: bufNew warning
    let raw = rawAlloc(128)           // port-1to2: rawAlloc warning
    let p = ptrAdd(buf, 16)           // port-1to2: ptrAdd warning
    let v = rawReadByte(raw, 0)       // port-1to2: rawReadByte warning
    rawWriteWord(raw, 8, 1234)        // port-1to2: rawWriteWord warning
    rawFree(raw)                       // port-1to2: rawFree warning
    setX("hello")
    print("done")
}

cfunc {                                // port-1to2: cfunc warning
    char* myFn(char* x) { return x; }
}
