// build-objk-app.ks — build a pure-Krypton objk GUI app (.app bundle). No Obj-C
// source. KryptScript port of build-objk-app.sh (orchestration only; runs after
// kcc exists, so it's not a bootstrap script).
//
//   kcc -r scripts/build-objk-app.ks examples/objk/term_grid.ks termgrid
//   (args: <source.ks> [appName] ; defaults examples/objk/brain.ks / brain)

func isExec(p) { emit trim(exec("test -x \"" + p + "\" && echo yes || echo no")) }
func isFile(p) { emit trim(exec("test -f \"" + p + "\" && echo yes || echo no")) }
func newer(a, b) { emit trim(exec("test \"" + a + "\" -nt \"" + b + "\" && echo yes || echo no")) }
func dirname(p) { emit trim(exec("dirname \"" + p + "\"")) }

just run {
    // Repo root = parent of scripts/. The driver runs us from CWD; assume repo root.
    let root = trim(exec("pwd"))
    let src = "examples/objk/brain.ks"
    let name = "brain"
    if argCount() >= 1 { if arg("0") != "" { src = arg("0") } }
    if argCount() >= 2 { if arg("1") != "" { name = arg("1") } }

    let fe = root + "/compiler/macos_arm64/kcc-arm64"
    let host = root + "/compiler/macos_arm64/macho_host"
    let seedHost = root + "/bootstrap/macho_host_macos_aarch64"
    let backend = root + "/compiler/macos_arm64/macho_arm64_self.k"

    // 1. ensure the macho codegen host is built from the current backend
    if isExec(host) != "yes" {
        if isExec(seedHost) == "yes" {
            kp("==> using bundled macho_host seed")
            host = seedHost
        } else {
            kp("==> building macho_host from macho_arm64_self.k")
            exec("kcc --native \"" + backend + "\" -o \"" + host + "\"")
        }
    } else {
        if newer(backend, host) == "yes" {
            kp("==> rebuilding macho_host (backend changed)")
            exec("kcc --native \"" + backend + "\" -o \"" + host + "\"")
        }
    }

    kp("==> compiling " + src + " (dev stdlib via KRYPTON_ROOT)")
    exec("env KRYPTON_ROOT=\"" + root + "\" \"" + fe + "\" \"" + src + "\" > /tmp/" + name + ".kir")
    exec("\"" + host + "\" --ir /tmp/" + name + ".kir /tmp/" + name + ".bin >/dev/null")

    let app = root + "/dist/" + name + ".app"
    exec("rm -rf \"" + app + "\"")
    exec("mkdir -p \"" + app + "/Contents/MacOS\"")
    exec("cp /tmp/" + name + ".bin \"" + app + "/Contents/MacOS/" + name + "\"")
    exec("chmod +x \"" + app + "/Contents/MacOS/" + name + "\"")

    if name == "kweb" && isExec(root + "/web/kweb") == "yes" {
        exec("cp \"" + root + "/web/kweb\" \"" + app + "/Contents/MacOS/kweb-cli\"")
        exec("chmod +x \"" + app + "/Contents/MacOS/kweb-cli\"")

        let payload = app + "/Contents/Resources/krypton"
        exec("mkdir -p \"" + payload + "/bootstrap\" \"" + payload + "/compiler/macos_arm64\"")
        exec("install -m 0755 \"" + root + "/bootstrap/kcc_driver_macos_aarch64\" \"" + payload + "/bootstrap/kcc_driver_macos_aarch64\"")
        exec("install -m 0755 \"" + root + "/bootstrap/kcc_seed_macos_aarch64\" \"" + payload + "/bootstrap/kcc_seed_macos_aarch64\"")
        exec("install -m 0755 \"" + root + "/compiler/macos_arm64/kcc-arm64\" \"" + payload + "/compiler/macos_arm64/kcc-arm64\"")
        exec("install -m 0755 \"" + root + "/bootstrap/macho_host_macos_aarch64\" \"" + payload + "/compiler/macos_arm64/macho_host\"")
        exec("install -m 0644 \"" + root + "/compiler/macos_arm64/macho_arm64_self.k\" \"" + payload + "/compiler/macos_arm64/macho_arm64_self.k\"")
        exec("install -m 0644 \"" + root + "/compiler/compile.k\" \"" + payload + "/compiler/compile.k\"")
        if isFile(root + "/compiler/optimize.k") == "yes" {
            exec("install -m 0644 \"" + root + "/compiler/optimize.k\" \"" + payload + "/compiler/optimize.k\"")
        }
        exec("env COPYFILE_DISABLE=1 ditto --norsrc \"" + root + "/stdlib\" \"" + payload + "/stdlib\"")
        exec("env COPYFILE_DISABLE=1 ditto --norsrc \"" + root + "/headers\" \"" + payload + "/headers\"")
        exec("touch \"" + payload + "/bootstrap/kcc_driver_macos_aarch64\" \"" + payload + "/bootstrap/kcc_seed_macos_aarch64\" \"" + payload + "/compiler/macos_arm64/kcc-arm64\" \"" + payload + "/compiler/macos_arm64/macho_host\"")
    }

    let q = fromCharCode(34)
    let bundleId = "org.krypton-lang.macos." + name
    let appVersion = trim(exec("env KRYPTON_ROOT=\"" + root + "\" \"" + fe + "\" --version 2>&1 | sed -E 's/^kcc version //;s/[[:space:]]+.*$//'"))
    if appVersion == "" { appVersion = "0.1.0" }
    let plist = "<?xml version=" + q + "1.0" + q + " encoding=" + q + "UTF-8" + q + "?>\n" +
        "<!DOCTYPE plist PUBLIC " + q + "-//Apple//DTD PLIST 1.0//EN" + q + " " + q + "http://www.apple.com/DTDs/PropertyList-1.0.dtd" + q + ">\n" +
        "<plist version=" + q + "1.0" + q + "><dict>\n" +
        "  <key>CFBundleName</key><string>" + name + "</string>\n" +
        "  <key>CFBundleDisplayName</key><string>" + name + "</string>\n" +
        "  <key>CFBundleExecutable</key><string>" + name + "</string>\n" +
        "  <key>CFBundleIdentifier</key><string>" + bundleId + "</string>\n" +
        "  <key>CFBundlePackageType</key><string>APPL</string>\n" +
        "  <key>CFBundleShortVersionString</key><string>" + appVersion + "</string>\n" +
        "  <key>CFBundleVersion</key><string>" + appVersion + "</string>\n" +
        "  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>\n" +
        "  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>\n" +
        "  <key>LSMinimumSystemVersion</key><string>14.0</string>\n" +
        "  <key>NSHighResolutionCapable</key><true/>\n" +
        "  <key>CFBundleIconFile</key><string>" + name + "</string>\n" +
        "  <key>NSDocumentsFolderUsageDescription</key><string>" + name + " edits files in your Documents.</string>\n" +
        "</dict></plist>\n"
    writeFile(app + "/Contents/Info.plist", plist)

    // bundle icon if present next to the source, else examples/objk/<name>.icns
    let icns = root + "/" + dirname(src) + "/" + name + ".icns"
    if isFile(icns) != "yes" { icns = root + "/examples/objk/" + name + ".icns" }
    if isFile(icns) == "yes" {
        exec("mkdir -p \"" + app + "/Contents/Resources\"")
        exec("cp \"" + icns + "\" \"" + app + "/Contents/Resources/" + name + ".icns\"")
    }
    exec("codesign -s - -f --deep \"" + app + "\" >/dev/null 2>&1")
    kp("==> built " + app + " (pure Krypton, no Obj-C source)")
}
