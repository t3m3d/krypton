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

just run {
    let root = trim(exec("pwd"))
    if trim(exec("uname -s")) != "Darwin" { die("build_pkg.ks: macOS only") }
    if trim(exec("uname -m")) != "arm64"  { die("build_pkg.ks: arm64 only (bundles the arm64 binaries)") }
    if has("pkgbuild") != "yes" { die("build_pkg.ks: pkgbuild not found (install Xcode Command Line Tools)") }

    let driver = "bootstrap/kcc_driver_macos_aarch64"
    let host   = "bootstrap/macho_host_macos_aarch64"
    if isExec("compiler/macos_arm64/kcc-arm64") != "yes" { die("build_pkg.ks: missing compiler/macos_arm64/kcc-arm64 — run ./build.sh first") }
    if isExec(driver) != "yes" { die("build_pkg.ks: missing " + driver + " (the kcc.ks driver seed) — run ./build.sh first") }
    if isExec(host) != "yes"   { die("build_pkg.ks: missing " + host + " (the macho backend host seed)") }
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
    exec("install -m 0755 bootstrap/kcc_seed_macos_aarch64 \"" + r + "/bootstrap/kcc_seed_macos_aarch64\"")
    exec("mkdir -p \"" + r + "/compiler/macos_arm64\"")
    exec("install -m 0755 compiler/macos_arm64/kcc-arm64 \"" + r + "/compiler/macos_arm64/kcc-arm64\"")
    exec("install -m 0755 " + host + " \"" + r + "/compiler/macos_arm64/macho_host\"")
    exec("install -m 0644 compiler/macos_arm64/macho_arm64_self.k \"" + r + "/compiler/macos_arm64/macho_arm64_self.k\"")
    exec("install -m 0644 compiler/compile.k \"" + r + "/compiler/compile.k\"")
    if isFile("compiler/optimize.k") == "yes" { exec("install -m 0644 compiler/optimize.k \"" + r + "/compiler/optimize.k\"") }
    if klsBin != "" { exec("install -m 0755 " + klsBin + " \"" + r + "/compiler/macos_arm64/kls\"") }
    exec("cp -R stdlib \"" + r + "/stdlib\"")
    exec("cp -R headers \"" + r + "/headers\"")
    if isDir("examples") == "yes" { exec("cp -R examples \"" + r + "/examples\"") }
    if isDir("lsp") == "yes" {
        exec("mkdir -p \"" + r + "/lsp\"")
        exec("for f in lsp/*.k lsp/README.md; do [ -f \"$f\" ] && install -m 0644 \"$f\" \"" + r + "/$f\"; done")
    }
    if isFile("LICENSE") == "yes" { exec("install -m 0644 LICENSE \"" + r + "/LICENSE\"") }
    exec("find \"" + r + "\" -type f -name '*.k' -exec chmod 0644 {} +")

    // ── postinstall (BASH — Installer runs it as root) ────────────────────────
    let post = "#!/bin/bash\n" +
        "set -e\n" +
        "ROOT=/usr/local/krypton\n" +
        "mkdir -p /usr/local/bin\n" +
        "ln -sf \"$ROOT/bootstrap/kcc_driver_macos_aarch64\" /usr/local/bin/kcc\n" +
        "[[ -e \"$ROOT/compiler/macos_arm64/kls\" ]] && ln -sf \"$ROOT/compiler/macos_arm64/kls\" /usr/local/bin/kls\n" +
        "for b in \"$ROOT/bootstrap/kcc_driver_macos_aarch64\" \"$ROOT/compiler/macos_arm64/kcc-arm64\" \"$ROOT/compiler/macos_arm64/macho_host\" \"$ROOT/compiler/macos_arm64/kls\"; do\n" +
        "    [[ -e \"$b\" ]] && codesign -s - -f \"$b\" 2>/dev/null || true\n" +
        "done\n" +
        "touch \"$ROOT/bootstrap/kcc_driver_macos_aarch64\" \"$ROOT/compiler/macos_arm64/kcc-arm64\" \"$ROOT/compiler/macos_arm64/macho_host\" 2>/dev/null || true\n" +
        "exit 0\n"
    writeFile(scriptsDir + "/postinstall", post)
    exec("chmod 0755 \"" + scriptsDir + "/postinstall\"")

    exec("xattr -cr \"" + stage + "\" 2>/dev/null")

    exec("mkdir -p releases")
    exec("rm -f \"" + pkgFile + "\"")
    kp("building " + pkgFile + "...")
    exec("COPYFILE_DISABLE=1 pkgbuild --root \"" + stage + "\" --identifier \"" + pkgId + "\" --version \"" + version + "\" --scripts \"" + scriptsDir + "\" --install-location / \"" + pkgFile + "\"")
    exec("rm -rf \"" + stage + "\" \"" + scriptsDir + "\"")

    kp("")
    kp("wrote " + pkgFile + " (" + trim(exec("stat -f%z \"" + pkgFile + "\"")) + " bytes)")
    kp("install:    sudo installer -pkg " + pkgFile + " -target /")
    kp("verify:     kcc --version   # -> kcc version " + version)
}
