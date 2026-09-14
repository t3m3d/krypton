#!/usr/bin/env kr
// Build a pure-Krypton iOS .app bundle. Simulator first; device signs later.
//
// kcc -r scripts/build-ios-app.ks examples/ios/hello.ks KryptonHello

import "k:env"

func q(s) {
    let d = fromCharCode(34)
    emit d + replace(s, d, "\\" + d) + d
}

just run {
    let src = "examples/ios/hello.ks"
    let name = "KryptonHello"
    let launch = 0
    if argCount() >= 1 { if arg("0") != "" { src = arg("0") } }
    if argCount() >= 2 { if arg("1") != "" { name = arg("1") } }
    if argCount() >= 3 { if arg("2") == "--launch" { launch = 1 } }

    let root = trim(exec("pwd"))
    let app = root + "/dist-ios/" + name + ".app"
    let executable = app + "/" + name
    let bundleId = environ("IOS_BUNDLE_ID")
    if bundleId == "" { bundleId = "org.krypton-lang.ios." + name }
    let developer = environ("DEVELOPER_DIR")
    if developer == "" {
        developer = trim(exec("ls -dt /Applications/Xcode*.app/Contents/Developer 2>/dev/null | head -1"))
    }
    let xcrun = "xcrun"
    if developer != "" { xcrun = "DEVELOPER_DIR=" + q(developer) + " xcrun" }

    exec("mkdir -p " + q(root + "/dist-ios"))
    exec("rm -rf " + q(app))
    exec("mkdir -p " + q(app))

    let rc = shellRun(q(root + "/bootstrap/kcc_driver_macos_aarch64") +
        " --target ios-sim-arm64 " + q(src) + " -o " + q(executable))
    if rc != "0" {
        kp("build-ios-app: compiler failed rc=" + rc)
        exit("1")
    }

    let d = fromCharCode(34)
    let plist = "<?xml version=" + d + "1.0" + d + " encoding=" + d + "UTF-8" + d + "?>\n" +
        "<!DOCTYPE plist PUBLIC " + d + "-//Apple//DTD PLIST 1.0//EN" + d + " " +
        d + "http://www.apple.com/DTDs/PropertyList-1.0.dtd" + d + ">\n" +
        "<plist version=" + d + "1.0" + d + "><dict>\n" +
        "<key>CFBundleDisplayName</key><string>" + name + "</string>\n" +
        "<key>CFBundleExecutable</key><string>" + name + "</string>\n" +
        "<key>CFBundleIdentifier</key><string>" + bundleId + "</string>\n" +
        "<key>CFBundleName</key><string>" + name + "</string>\n" +
        "<key>CFBundlePackageType</key><string>APPL</string>\n" +
        "<key>CFBundleShortVersionString</key><string>0.1.0</string>\n" +
        "<key>CFBundleVersion</key><string>1</string>\n" +
        "<key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>\n" +
        "<key>MinimumOSVersion</key><string>15.0</string>\n" +
        "<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>\n" +
        "<key>UILaunchScreen</key><dict/>\n" +
        "</dict></plist>\n"
    writeFile(app + "/Info.plist", plist)

    let signRc = shellRun("codesign --force --sign - " + q(app))
    if signRc != "0" {
        kp("build-ios-app: ad-hoc signing failed rc=" + signRc)
        exit("1")
    }

    kp("built " + app)
    if launch == 1 {
        if trim(exec(xcrun + " --find simctl 2>/dev/null")) == "" {
            kp("build-ios-app: iOS Simulator tools missing; install Simulator runtime in Xcode")
            exit("1")
        }
        let installRc = shellRun(xcrun + " simctl install booted " + q(app))
        if installRc != "0" {
            kp("build-ios-app: simulator install failed rc=" + installRc)
            exit("1")
        }
        let launchRc = shellRun(xcrun + " simctl launch booted " + bundleId)
        if launchRc != "0" {
            kp("build-ios-app: simulator launch failed rc=" + launchRc)
            exit("1")
        }
        kp("launched " + bundleId)
    } else {
        kp("install: " + xcrun + " simctl install booted " + q(app))
        kp("launch:  " + xcrun + " simctl launch booted " + bundleId)
    }
}
