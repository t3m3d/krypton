// Test with regular import - does this also hang?
import "stdlib/result.k"

just run {
    let r = ok("regular import works")
    if isOk(r) { kp("PASS regular import") } else { kp("FAIL") }
    kp("done")
}
