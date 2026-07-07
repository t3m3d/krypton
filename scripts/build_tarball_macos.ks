// build_tarball_macos.ks — build a self-contained macOS (arm64) release tarball.
// KryptScript port of build_tarball_macos.sh (orchestration; runs after kcc
// exists). Output: releases/krypton-<version>-macos-arm64.tar.gz
//   Run from repo root:  kcc -r scripts/build_tarball_macos.ks
//
// The install.sh it emits is BASH on purpose — it bootstraps kcc on the user's
// machine, so it can't itself be KryptScript (can't need kcc to install kcc).

func isExec(p) { emit trim(exec("test -x \"" + p + "\" && echo yes || echo no")) }
func isFile(p) { emit trim(exec("test -f \"" + p + "\" && echo yes || echo no")) }
func isDir(p)  { emit trim(exec("test -d \"" + p + "\" && echo yes || echo no")) }
func die(m)    { kp(m)  exit("1") }

just run {
    let root = trim(exec("pwd"))
    if trim(exec("uname -s")) != "Darwin" { die("build_tarball_macos: macOS only") }

    let arch = "arm64"
    let driver = "bootstrap/kcc_driver_macos_aarch64"
    let host   = "bootstrap/macho_host_macos_aarch64"
    if isExec(driver) != "yes" { die("build_tarball_macos: missing " + driver + " (run ./build.sh)") }
    if isExec(host) != "yes"   { die("build_tarball_macos: missing " + host) }
    if isExec("compiler/macos_arm64/kcc-arm64") != "yes" { die("build_tarball_macos: missing compiler/macos_arm64/kcc-arm64") }
    if isExec("web/kweb") != "yes" { die("build_tarball_macos: missing web/kweb") }
    if isDir("dist/kweb.app") != "yes" { die("build_tarball_macos: missing dist/kweb.app") }

    // Version from the driver: `kcc version 2.4.0` -> 2.4.0
    let version = trim(exec("KRYPTON_ROOT=\"" + root + "\" ./" + driver + " --version 2>&1 | sed -E 's/^kcc version //;s/[[:space:]].*$//'"))
    if version == "" { die("build_tarball_macos: could not detect version") }

    let name  = "krypton-" + version + "-macos-" + arch
    let stage = trim(exec("mktemp -d"))
    let rootd = stage + "/" + name
    exec("mkdir -p \"" + rootd + "\"")

    kp("staging payload for " + name + " ...")
    exec("mkdir -p \"" + rootd + "/bootstrap\" \"" + rootd + "/compiler/macos_arm64\"")
    // Driver + frontend seed
    exec("install -m 0755 " + driver + " \"" + rootd + "/" + driver + "\"")
    exec("install -m 0755 bootstrap/kcc_seed_macos_aarch64 \"" + rootd + "/bootstrap/kcc_seed_macos_aarch64\"")
    // Frontend + backend host + their sources
    exec("install -m 0755 compiler/macos_arm64/kcc-arm64 \"" + rootd + "/compiler/macos_arm64/kcc-arm64\"")
    exec("install -m 0755 " + host + " \"" + rootd + "/compiler/macos_arm64/macho_host\"")
    exec("install -m 0644 compiler/macos_arm64/macho_arm64_self.k \"" + rootd + "/compiler/macos_arm64/macho_arm64_self.k\"")
    exec("install -m 0644 compiler/compile.k \"" + rootd + "/compiler/compile.k\"")
    if isFile("compiler/optimize.k") == "yes" { exec("install -m 0644 compiler/optimize.k \"" + rootd + "/compiler/optimize.k\"") }
    if isExec("compiler/macos_arm64/kls") == "yes" { exec("install -m 0755 compiler/macos_arm64/kls \"" + rootd + "/compiler/macos_arm64/kls\"") }
    // Runtime trees
    exec("env COPYFILE_DISABLE=1 ditto --norsrc stdlib \"" + rootd + "/stdlib\"")
    exec("env COPYFILE_DISABLE=1 ditto --norsrc headers \"" + rootd + "/headers\"")
    if isDir("examples") == "yes" { exec("env COPYFILE_DISABLE=1 ditto --norsrc examples \"" + rootd + "/examples\"") }
    if isFile("LICENSE") == "yes" { exec("cp LICENSE \"" + rootd + "/LICENSE\"") }
    exec("find \"" + rootd + "\" -type f -name '*.k' -exec chmod 0644 {} +")
    exec("mkdir -p \"" + rootd + "/web\" \"" + rootd + "/apps\"")
    exec("install -m 0755 web/kweb \"" + rootd + "/web/kweb\"")
    exec("install -m 0644 web/kweb.htk \"" + rootd + "/web/kweb.htk\"")
    exec("install -m 0644 web/kweb_gui.ks \"" + rootd + "/web/kweb_gui.ks\"")
    if isFile("web/README.md") == "yes" { exec("install -m 0644 web/README.md \"" + rootd + "/web/README.md\"") }
    exec("env COPYFILE_DISABLE=1 ditto --norsrc dist/kweb.app \"" + rootd + "/apps/kweb.app\"")

    // ── install.sh (BASH — bootstraps kcc on the user's machine) ──────────────
    let inst = "#!/usr/bin/env bash\n" +
        "# Krypton macOS installer - copies the bundle, signs it, puts kcc on PATH.\n" +
        "set -euo pipefail\n" +
        "PREFIX=\"${1:-/usr/local/krypton}\"\n" +
        "BIN=\"${BINDIR:-/usr/local/bin}\"\n" +
        "APPDIR=\"${APPDIR:-/Applications/Krypton}\"\n" +
        "HERE=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\"\n" +
        "SUDO=\"\"; [[ -w \"$(dirname \"$PREFIX\")\" && -w \"$(dirname \"$BIN\")\" && -w \"$(dirname \"$APPDIR\")\" ]] || SUDO=\"sudo\"\n" +
        "echo \"installing Krypton to $PREFIX ...\"\n" +
        "$SUDO rm -rf \"$PREFIX\"; $SUDO mkdir -p \"$PREFIX\"; $SUDO cp -R \"$HERE\"/. \"$PREFIX\"/\n" +
        "$SUDO mkdir -p \"$APPDIR\"; $SUDO cp -R \"$HERE/apps/kweb.app\" \"$APPDIR/kweb.app\"\n" +
        "$SUDO xattr -dr com.apple.quarantine \"$PREFIX\" 2>/dev/null || true\n" +
        "$SUDO xattr -dr com.apple.quarantine \"$APPDIR/kweb.app\" 2>/dev/null || true\n" +
        "for b in bootstrap/kcc_driver_macos_aarch64 compiler/macos_arm64/kcc-arm64 compiler/macos_arm64/macho_host compiler/macos_arm64/kls web/kweb; do\n" +
        "    [[ -e \"$PREFIX/$b\" ]] && $SUDO codesign -s - -f \"$PREFIX/$b\" 2>/dev/null || true\n" +
        "done\n" +
        "[[ -e \"$APPDIR/kweb.app/Contents/MacOS/kweb\" ]] && $SUDO codesign -s - -f \"$APPDIR/kweb.app/Contents/MacOS/kweb\" 2>/dev/null || true\n" +
        "$SUDO touch \"$PREFIX/bootstrap/kcc_driver_macos_aarch64\" \"$PREFIX/compiler/macos_arm64/kcc-arm64\" \"$PREFIX/compiler/macos_arm64/macho_host\" 2>/dev/null || true\n" +
        "$SUDO mkdir -p \"$BIN\"\n" +
        "$SUDO ln -sf \"$PREFIX/bootstrap/kcc_driver_macos_aarch64\" \"$BIN/kcc\"\n" +
        "[[ -e \"$PREFIX/compiler/macos_arm64/kls\" ]] && $SUDO ln -sf \"$PREFIX/compiler/macos_arm64/kls\" \"$BIN/kls\"\n" +
        "$SUDO ln -sf \"$PREFIX/web/kweb\" \"$BIN/kweb\"\n" +
        "echo \"done. 'kcc --version':\"; \"$BIN/kcc\" --version\n"
    writeFile(rootd + "/install.sh", inst)
    exec("chmod 0755 \"" + rootd + "/install.sh\"")

    // ── README.txt ────────────────────────────────────────────────────────────
    let rme = "Krypton " + version + " - macOS " + arch + "\n" +
        "Install:  ./install.sh            (symlinks kcc into /usr/local/bin, ad-hoc signs)\n" +
        "Use:      kcc hello.k -o hello && ./hello\n" +
        "          kcc -r hello.ks\n" +
        "          kweb init mysite\n" +
        "          open /Applications/Krypton/kweb.app\n" +
        "          kcc --version\n" +
        "No clang, no clone needed - prebuilt binaries, self-signed on install.\n"
    writeFile(rootd + "/README.txt", rme)

    // Make binaries NEWER than the .k sources so the driver never triggers the
    // clang macho_host self-host rebuild on first run after extract.
    exec("find \"" + rootd + "\" -type f \\( -name macho_host -o -name 'kcc-*' -o -name 'kcc_*' -o -name kweb -o -name kweb_gui \\) -exec touch {} +")
    exec("sleep 1")
    exec("find \"" + rootd + "\" -type f \\( -name macho_host -o -name 'kcc-*' -o -name 'kcc_*' -o -name kweb -o -name kweb_gui \\) -exec touch {} +")
    exec("dot_clean -m \"" + rootd + "\" 2>/dev/null || true")
    exec("find \"" + rootd + "\" -name '._*' -exec rm -f {} + 2>/dev/null || true")

    exec("mkdir -p releases")
    let out = "releases/" + name + ".tar.gz"
    exec("tar -czf \"" + out + "\" -C \"" + stage + "\" \"" + name + "\"")
    exec("rm -rf \"" + stage + "\"")
    kp("wrote " + out + " (" + trim(exec("du -h \"" + out + "\" | cut -f1")) + ")")
    kp(trim(exec("shasum -a 256 \"" + out + "\"")))
}
