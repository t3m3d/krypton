// tests/arch_smoke.k — verify stdlib/arch.k reports a plausible
// architecture for the host. Doesn't pin the answer (so the test
// runs the same on x86_64 + aarch64 + arm64 macOS hosts), only
// checks that we get something in the allowed set and that the
// helper predicates agree.

import "k:arch"

just run {
    let a = arch()
    let r = archRaw()

    print("arch()    = " + a)
    print("archRaw() = " + r)
    print("isArm()   = " + isArm())
    print("isX86()   = " + isX86())
    print("is64Bit() = " + is64Bit())

    if a == "unknown" {
        print("[FAIL] arch() returned 'unknown' — uname -m and PROCESSOR_ARCHITECTURE both failed")
        exit(1)
    }

    // Sanity: x86_64 and arm64 must be mutually exclusive.
    if isX86() == 1 && isArm() == 1 {
        print("[FAIL] both isX86() and isArm() returned 1")
        exit(1)
    }

    // is64Bit must be consistent with arch.
    if a == "x86_64" && is64Bit() != 1 { print("[FAIL] x86_64 not flagged as 64-bit")  exit(1) }
    if a == "arm64"  && is64Bit() != 1 { print("[FAIL] arm64 not flagged as 64-bit")   exit(1) }

    print("[PASS] arch.k reports a plausible architecture")
    exit(0)
}
