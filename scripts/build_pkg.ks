// build_pkg.ks — build a macOS .pkg installer for Krypton (arm64).
// KryptScript port of build_pkg.sh (orchestration via pkgbuild; runs after kcc
// exists). Output: releases/krypton-<version>-macos-arm64.pkg
//   Run from repo root:  kcc -r scripts/build_pkg.ks
//
// The postinstall it emits is BASH (Installer.app runs it as root to bootstrap
// kcc onto PATH) — it can't be KryptScript.

func isExec(p) { emit trim(exec("test -x \"" + p + "\" && echo yes || echo no")) }
func isFile(p) { emit trim(exec("test -f \"" + p + "\" && echo yes || echo no")) }
func isDir(p)  { emit trim(exec("test -d \"" + p + "\" && echo yes || echo no")) }
func has(c)    { emit trim(exec("command -v " + c + " >/dev/null 2>&1 && echo yes || echo no")) }
func die(m)    { kp(m)  exit("1") }
func envValue(name) { emit trim(exec("printenv " + name + " 2>/dev/null || true")) }

func signPayload(stage, identity) {
    let cmd = "find \"" + stage + "\" -type f -perm -111 -print0 | " +
        "while IFS= read -r -d '' f; do " +
        "if file \"$f\" | grep -q 'Mach-O'; then " +
        "name=$(basename \"$f\" | tr '_' '-' | tr -cd 'A-Za-z0-9.-'); " +
        "id=org.krypton-lang.$name; " +
        "case \"$f\" in */kweb.app/Contents/MacOS/kweb) id=org.krypton-lang.macos.kweb;; esac; " +
        "codesign --force --identifier \"$id\" --options runtime --timestamp " +
        "--sign \"" + identity + "\" \"$f\" || exit 1; " +
        "fi; done"
    if shellRun(cmd) != "0" { die("build_pkg.ks: Developer ID payload signing failed") }
    let app = stage + "/Applications/Krypton/kweb.app"
    if shellRun("codesign --force --options runtime --timestamp --sign \"" + identity + "\" \"" + app + "\"") != "0" {
        die("build_pkg.ks: Developer ID app signing failed")
    }
    if shellRun("codesign --verify --deep --strict --verbose=2 \"" + app + "\"") != "0" {
        die("build_pkg.ks: signed app verification failed")
    }
}

func cleanPkgAppleDouble(pkgFile) {
    let work = trim(exec("mktemp -d"))
    let pkgDir = work + "/pkg"
    let payloadRoot = work + "/payload"
    exec("pkgutil --expand \"" + pkgFile + "\" \"" + pkgDir + "\"")
    exec("mkdir -p \"" + payloadRoot + "\"")
    exec("(cd \"" + payloadRoot + "\" && gzip -dc \"" + pkgDir + "/Payload\" | cpio -idm --quiet)")
    exec("find \"" + payloadRoot + "\" -name '._*' -exec rm -f {} + 2>/dev/null || true")
    exec("(cd \"" + payloadRoot + "\" && find . | cpio -o --format odc --quiet | gzip -c > \"" + pkgDir + "/Payload\")")
    exec("mkbom \"" + payloadRoot + "\" \"" + pkgDir + "/Bom\"")
    exec("find \"" + pkgDir + "/Scripts\" -name '._*' -exec rm -f {} + 2>/dev/null || true")
    exec("rm -f \"" + pkgFile + "\"")
    exec("env COPYFILE_DISABLE=1 pkgutil --flatten \"" + pkgDir + "\" \"" + pkgFile + "\"")
    exec("rm -rf \"" + work + "\"")
}

just run {
    let root = trim(exec("pwd"))
    if trim(exec("uname -s")) != "Darwin" { die("build_pkg.ks: macOS only") }
    if trim(exec("uname -m")) != "arm64"  { die("build_pkg.ks: arm64 only (bundles the arm64 binaries)") }
    if has("pkgbuild") != "yes" { die("build_pkg.ks: pkgbuild not found (install Xcode Command Line Tools)") }
    let releaseSign = envValue("KRYPTON_RELEASE_SIGN") == "1"
    let appIdentity = envValue("KRYPTON_APP_SIGN_IDENTITY")
    let installerIdentity = envValue("KRYPTON_INSTALLER_SIGN_IDENTITY")
    if appIdentity == "" { appIdentity = "Developer ID Application: BRIAN KEITH THOMPSON (SD4X94BA97)" }
    if installerIdentity == "" { installerIdentity = "Developer ID Installer: BRIAN KEITH THOMPSON (SD4X94BA97)" }
    if releaseSign {
        if has("productsign") != "yes" { die("build_pkg.ks: productsign not found") }
        if shellRun("security find-identity -v | grep -F '\"" + appIdentity + "\"' >/dev/null") != "0" {
            die("build_pkg.ks: Developer ID Application identity not found")
        }
        if shellRun("security find-identity -v | grep -F '\"" + installerIdentity + "\"' >/dev/null") != "0" {
            die("build_pkg.ks: Developer ID Installer identity not found")
        }
    }

    let driver = "bootstrap/kcc_driver_macos_aarch64"
    let host   = "bootstrap/macho_host_macos_aarch64"
    if isExec("compiler/macos_arm64/kcc-arm64") != "yes" { die("build_pkg.ks: missing compiler/macos_arm64/kcc-arm64 — run ./build.sh first") }
    if isExec(driver) != "yes" { die("build_pkg.ks: missing " + driver + " (the kcc.ks driver seed) — run ./build.sh first") }
    if isExec(host) != "yes"   { die("build_pkg.ks: missing " + host + " (the macho backend host seed)") }
    if isExec("web/kweb") != "yes" { die("build_pkg.ks: missing web/kweb — build it first") }
    if isDir("dist/kweb.app") != "yes" { die("build_pkg.ks: missing dist/kweb.app — build it first") }
    let klsBin = ""
    if isExec("compiler/macos_arm64/kls") == "yes" { klsBin = "compiler/macos_arm64/kls" }
    else { if isExec("kls") == "yes" { klsBin = "kls" } }

    let version = trim(exec("KRYPTON_ROOT=\"" + root + "\" ./" + driver + " --version 2>&1 | sed -E 's/^kcc version //;s/[[:space:]]+.*$//'"))
    if version == "" { die("build_pkg.ks: could not detect kcc version") }

    let pkgId = "org.krypton-lang.krypton"
    let pkgFile = "releases/krypton-" + version + "-macos-arm64.pkg"

    let stage = trim(exec("mktemp -d"))
    let scriptsDir = trim(exec("mktemp -d"))
    let prefix = "/usr/local/krypton"
    let r = stage + prefix
    exec("mkdir -p \"" + r + "\"")

    kp("staging payload for " + version + " ...")
    exec("mkdir -p \"" + r + "/bootstrap\"")
    exec("install -m 0755 " + driver + " \"" + r + "/" + driver + "\"")
    exec("install -m 0755 kr \"" + r + "/kr\"")
    exec("install -m 0755 bootstrap/kcc_seed_macos_aarch64 \"" + r + "/bootstrap/kcc_seed_macos_aarch64\"")
    exec("mkdir -p \"" + r + "/compiler/macos_arm64\"")
    exec("install -m 0755 compiler/macos_arm64/kcc-arm64 \"" + r + "/compiler/macos_arm64/kcc-arm64\"")
    exec("install -m 0755 " + host + " \"" + r + "/compiler/macos_arm64/macho_host\"")
    exec("install -m 0644 compiler/macos_arm64/macho_arm64_self.k \"" + r + "/compiler/macos_arm64/macho_arm64_self.k\"")
    exec("install -m 0644 compiler/compile.k \"" + r + "/compiler/compile.k\"")
    if isFile("compiler/optimize.k") == "yes" { exec("install -m 0644 compiler/optimize.k \"" + r + "/compiler/optimize.k\"") }
    if klsBin != "" { exec("install -m 0755 " + klsBin + " \"" + r + "/compiler/macos_arm64/kls\"") }
    exec("env COPYFILE_DISABLE=1 ditto --norsrc stdlib \"" + r + "/stdlib\"")
    exec("env COPYFILE_DISABLE=1 ditto --norsrc headers \"" + r + "/headers\"")
    if isDir("examples") == "yes" {
        exec("env COPYFILE_DISABLE=1 ditto --norsrc examples \"" + r + "/examples\"")
        exec("git ls-files --others -z examples | xargs -0 -I{} rm -f \"" + r + "/{}\"")
        exec("rm -f \"" + r + "/examples/objk/objective-k-focus\"")
    }
    if isDir("lsp") == "yes" {
        exec("mkdir -p \"" + r + "/lsp\"")
        exec("for f in lsp/*.k lsp/README.md; do [ -f \"$f\" ] && install -m 0644 \"$f\" \"" + r + "/$f\"; done")
    }
    if isFile("LICENSE") == "yes" { exec("install -m 0644 LICENSE \"" + r + "/LICENSE\"") }
    exec("find \"" + r + "\" -type f -name '*.k' -exec chmod 0644 {} +")

    exec("mkdir -p \"" + r + "/web\"")
    exec("install -m 0755 web/kweb \"" + r + "/web/kweb\"")
    exec("install -m 0644 web/kweb.htk \"" + r + "/web/kweb.htk\"")
    exec("install -m 0644 web/kweb_gui.ks \"" + r + "/web/kweb_gui.ks\"")
    if isFile("web/README.md") == "yes" { exec("install -m 0644 web/README.md \"" + r + "/web/README.md\"") }
    exec("mkdir -p \"" + stage + "/Applications/Krypton\"")
    exec("env COPYFILE_DISABLE=1 ditto --norsrc dist/kweb.app \"" + stage + "/Applications/Krypton/kweb.app\"")
    if releaseSign { signPayload(stage, appIdentity) }

    // ── postinstall (BASH — Installer runs it as root) ────────────────────────
    let post = "#!/bin/bash\n" +
        "set -e\n" +
        "TARGET=\"${3:?Installer target volume missing}\"\n" +
        "TARGET=\"${TARGET%/}\"\n" +
        "ROOT=\"$TARGET/usr/local/krypton\"\n" +
        "BIN=\"$TARGET/usr/local/bin\"\n" +
        "mkdir -p \"$BIN\"\n" +
        "ln -sf /usr/local/krypton/bootstrap/kcc_driver_macos_aarch64 \"$BIN/kcc\"\n" +
        "ln -sf /usr/local/krypton/kr \"$BIN/kr\"\n" +
        "[[ -e \"$ROOT/compiler/macos_arm64/kls\" ]] && ln -sf /usr/local/krypton/compiler/macos_arm64/kls \"$BIN/kls\"\n" +
        "[[ -e \"$ROOT/web/kweb\" ]] && ln -sf /usr/local/krypton/web/kweb \"$BIN/kweb\"\n" +
        "touch \"$ROOT/bootstrap/kcc_driver_macos_aarch64\" \"$ROOT/compiler/macos_arm64/kcc-arm64\" \"$ROOT/compiler/macos_arm64/macho_host\" 2>/dev/null || true\n" +
        "exit 0\n"
    writeFile(scriptsDir + "/postinstall", post)
    exec("chmod 0755 \"" + scriptsDir + "/postinstall\"")

    exec("find \"" + stage + "\" \"" + scriptsDir + "\" -name '._*' -exec rm -f {} + 2>/dev/null || true")
    exec("xattr -cr \"" + stage + "\" \"" + scriptsDir + "\" 2>/dev/null || true")
    if releaseSign {
        let app = stage + "/Applications/Krypton/kweb.app"
        if shellRun("codesign --verify --deep --strict --verbose=2 \"" + app + "\"") != "0" {
            die("build_pkg.ks: staged app verification failed after metadata cleanup")
        }
    }

    exec("mkdir -p releases")
    exec("rm -f \"" + pkgFile + "\"")
    kp("building " + pkgFile + "...")
    let buildCmd = "env COPYFILE_DISABLE=1 pkgbuild --root \"" + stage + "\" --identifier \"" + pkgId + "\" --version \"" + version + "\" --scripts \"" + scriptsDir + "\" --install-location / --filter '(^|/)[.]_[^/]*$' --filter '(^|/)[.]DS_Store$' --filter '(^|/)CVS($|/)' --filter '(^|/)[.]svn($|/)' \"" + pkgFile + "\""
    if shellRun(buildCmd) != "0" { die("build_pkg.ks: pkgbuild failed") }
    cleanPkgAppleDouble(pkgFile)
    if releaseSign {
        let signedPkg = pkgFile + ".signed"
        exec("rm -f \"" + signedPkg + "\"")
        if shellRun("productsign --sign \"" + installerIdentity + "\" \"" + pkgFile + "\" \"" + signedPkg + "\"") != "0" {
            die("build_pkg.ks: Developer ID package signing failed")
        }
        if shellRun("pkgutil --check-signature \"" + signedPkg + "\" 2>&1 | grep -q 'Status: signed by a developer certificate issued by Apple'") != "0" {
            die("build_pkg.ks: temporary signed package verification failed")
        }
        exec("rm -f \"" + pkgFile + "\"")
        exec("mv \"" + signedPkg + "\" \"" + pkgFile + "\"")
        if shellRun("pkgutil --check-signature \"" + pkgFile + "\" 2>&1 | grep -q 'Status: signed by a developer certificate issued by Apple'") != "0" {
            die("build_pkg.ks: signed package verification failed")
        }
    }
    exec("rm -rf \"" + stage + "\" \"" + scriptsDir + "\"")

    kp("")
    kp("wrote " + pkgFile + " (" + trim(exec("stat -f%z \"" + pkgFile + "\"")) + " bytes)")
    kp("install:    sudo installer -pkg " + pkgFile + " -target /")
    kp("verify:     kcc --version   # -> kcc version " + version)
    kp("            kweb")
    kp("            open /Applications/Krypton/kweb.app")
}
