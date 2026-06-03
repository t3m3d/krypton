// examples/arch_info.k — print the host CPU architecture using k:arch.
//
// Showcases stdlib/arch.k (host CPU detection in pure Krypton).
// Compile + run:
//     kcc -r examples/arch_info.k
//
// Output:
//     arch:        x86_64
//     archRaw():   x86_64
//     isX86():     1
//     isArm():     0
//     is64Bit():   1
//
// Behaviour by host:
//     Linux x86_64  -> arch=x86_64, isX86=1
//     Linux aarch64 -> arch=arm64,  isArm=1  (when the aarch64 backend
//                                              ships M4 string-concat)
//     macOS arm64   -> arch=arm64,  isArm=1
//     Windows x86_64-> arch=x86_64, isX86=1
//     Windows arm64 -> arch=arm64,  isArm=1  (once a Windows-on-ARM
//                                              backend exists)

import "k:arch"

just run {
    print("arch:        " + arch())
    print("archRaw():   " + archRaw())
    print("isX86():     " + isX86())
    print("isArm():     " + isArm())
    print("is64Bit():   " + is64Bit())

    if isArm() == 1 {
        print("")
        print("Running on ARM — would use the arm64 backend.")
    } else if isX86() == 1 {
        print("")
        print("Running on x86_64 — would use the x86_64 backend.")
    } else {
        print("")
        print("Unrecognised architecture; default backend.")
    }
}
