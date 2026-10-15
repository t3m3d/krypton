#!/usr/bin/env kr

func fail(message) {
    kp("build_macos_app_store: " + message)
    exit("1")
}

func q(value) { emit fromCharCode(34) + value + fromCharCode(34) }
func isFile(path) { emit trim(exec("test -f " + q(path) + " && echo yes || echo no")) }
func isDir(path) { emit trim(exec("test -d " + q(path) + " && echo yes || echo no")) }

just run {
    let root = trim(exec("pwd"))
    let name = "kweb"
    if argCount() > 0 && arg("0") != "" { name = arg("0") }

    let source = root + "/dist/" + name + ".app"
    if isDir(source) != "yes" { fail("missing " + source) }

    let outDir = root + "/dist/app-store"
    let app = outDir + "/" + name + ".app"
    let entitlements = root + "/scripts/macos_app_store.entitlements"
    let helperEntitlements = root + "/scripts/macos_app_store_helper.entitlements"
    if isFile(entitlements) != "yes" { fail("missing entitlements") }
    if isFile(helperEntitlements) != "yes" { fail("missing helper entitlements") }

    exec("rm -rf " + q(app))
    exec("mkdir -p " + q(outDir))
    exec("env COPYFILE_DISABLE=1 ditto --norsrc " + q(source) + " " + q(app))

    let profile = environ("KRYPTON_APP_STORE_PROFILE")
    if profile != "" {
        if isFile(profile) != "yes" { fail("provisioning profile not found") }
        exec("cp " + q(profile) + " " + q(app + "/Contents/embedded.provisionprofile"))
    }

    let identity = environ("KRYPTON_APP_STORE_IDENTITY")
    if identity == "" { identity = "-" }
    let nested = q(app + "/Contents/MacOS/kweb-cli") + " " +
        q(app + "/Contents/Resources/krypton/bootstrap/kcc_driver_macos_aarch64") + " " +
        q(app + "/Contents/Resources/krypton/bootstrap/kcc_seed_macos_aarch64") + " " +
        q(app + "/Contents/Resources/krypton/compiler/macos_arm64/kcc-arm64") + " " +
        q(app + "/Contents/Resources/krypton/compiler/macos_arm64/macho_host")
    let signNested = "for f in " + nested + "; do if [ -f \"$f\" ]; then codesign --force --sign " +
        q(identity) + " --entitlements " + q(helperEntitlements) + " \"$f\" || exit 1; fi; done"
    if shellRun(signNested) != "0" {
        fail("nested executable signing failed")
    }
    if shellRun("codesign --force --sign " + q(identity) + " --entitlements " + q(entitlements) + " " + q(app)) != "0" {
        fail("app signing failed")
    }
    if shellRun("codesign --verify --deep --strict --verbose=2 " + q(app)) != "0" {
        fail("signature verification failed")
    }

    kp("built " + app)
    if identity == "-" {
        kp("ad-hoc sandbox build; set KRYPTON_APP_STORE_IDENTITY and KRYPTON_APP_STORE_PROFILE for submission signing")
        emit "0"
    }

    let installer = environ("KRYPTON_APP_STORE_INSTALLER_IDENTITY")
    if installer == "" {
        kp("signed app ready; set KRYPTON_APP_STORE_INSTALLER_IDENTITY to build upload package")
        emit "0"
    }

    let version = trim(exec("/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' " + q(app + "/Contents/Info.plist")))
    let pkg = root + "/releases/" + name + "-" + version + "-macos-app-store.pkg"
    if shellRun("productbuild --component " + q(app) + " /Applications --sign " + q(installer) + " " + q(pkg)) != "0" {
        fail("package build failed")
    }
    kp("built " + pkg)
}
