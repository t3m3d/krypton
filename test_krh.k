// test_krh.k — test .krh native header system
// Tests that jxt { func ... } declarations work correctly

import "headers/windows.krh"

just run {
    // GetTickCount64 declared in windows.krh via jxt { func ... }
    let ticks = GetTickCount64()
    kp("PASS: GetTickCount64 returned: " + ticks)

    // environ still works
    let user = environ("USERNAME")
    kp("PASS: USERNAME = " + user)

    kp("ALL .krh TESTS PASSED")
}
