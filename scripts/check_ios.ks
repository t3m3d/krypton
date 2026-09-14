#!/usr/bin/env kr
// Focused iOS target smoke. Builds the core pure-Krypton bundles.

import "k:env"

func checkBundle(root, src, name) {
    let log = "/tmp/check_ios_" + name + ".log"
    let cmd = "KRYPTON_ROOT=\"" + root + "\" \"" +
        root + "/bootstrap/kcc_driver_macos_aarch64\" -r scripts/build-ios-app.ks " +
        src + " " + name + " >" + log + " 2>&1"
    let rc = shellRun(cmd)
    if rc != "0" {
        kp("FAIL iOS " + name + " rc=" + rc)
        kp(trim(exec("tail -20 " + log)))
        exit("1")
    }
    kp("OK iOS " + name)
}

just run {
    let root = trim(exec("pwd"))
    let developer = environ("DEVELOPER_DIR")
    if developer == "" {
        developer = trim(exec("ls -dt /Applications/Xcode*.app/Contents/Developer 2>/dev/null | head -1"))
    }
    let xcrun = "xcrun"
    if developer != "" { xcrun = "DEVELOPER_DIR=\"" + developer + "\" xcrun" }

    checkBundle(root, "examples/ios/hello.ks", "KryptonHello")
    checkBundle(root, "examples/ios/visual_scene.ks", "KryptonVisual")
    checkBundle(root, "examples/ios/visual_touch.ks", "KryptonTouch")

    if trim(exec(xcrun + " --find simctl 2>/dev/null")) == "" {
        kp("SKIP iOS launch: Simulator tools missing")
    }
}
