#!/usr/bin/env kr
// kcc.ks — Krypton-native compiler driver (prototype). Replaces the bash kcc.sh.
//
// WHY: kcc.sh makes bash a hard dependency (Git Bash/MSYS on Windows), ironic
// for a language killing its C dependency. This driver is written IN Krypton —
// no bash, no .bat. Built on the native batteries: k:args k:fsx k:env k:sh.
//
// BOOTSTRAP (chicken-and-egg): compile this once with the existing bash driver,
// then use the binary:
//     kcc.sh kcc.ks -o kcc-native
//     ./kcc-native hello.k -o hello
//
// SCOPE: macOS arm64 + Linux x86-64 native pipelines, with --version/--ir/-o/-r.
// (Windows not yet wired.) Both share one KryptScript driver — no bash, no .bat.
//
// Usage:
//   kcc-native <src.k|src.ks> [-o OUT]   compile to native binary
//   kcc-native -r <src> [args...]        compile, run (pass args), delete
//   kcc-native --ir <src>                emit Krypton IR to stdout
//   kcc-native --version

import "k:args"
import "k:fsx"
import "k:env"
import "k:sh"

func VERSION() { emit "kcc-native 0.1 (krypton-driver prototype)" }

// Locate the install root: $KRYPTON_ROOT, else the dev repo, else the pkg
// install. The dev repo is preferred over /usr/local/krypton because the pkg
// install is often stale (missing newly-added stdlib). Returns "" if none.
// A valid root has at least one platform frontend (macOS arm64 or Linux x86).
func hasFrontend(root) {
    if exists(root + "/compiler/macos_arm64/kcc-arm64") == "1" { emit "1" }
    if exists(root + "/compiler/linux_x86/kcc-x64") == "1" { emit "1" }
    emit "0"
}
func findRoot() {
    let r = env("KRYPTON_ROOT")
    if r != "" {
        if hasFrontend(r) == "1" { emit r }
    }
    let dev = home() + "/Documents/GitHub/krypton"
    if hasFrontend(dev) == "1" { emit dev }
    if hasFrontend("/usr/local/krypton") == "1" { emit "/usr/local/krypton" }
    emit ""
}

// Ensure macho_host exists and is newer than its source; rebuild via the
// one-time clang bootstrap if not. (clang here = toolchain bootstrap only,
// never for user programs.) Returns "1" ok / "0" fail.
func ensureHost(root) {
    let host = root + "/compiler/macos_arm64/macho_host"
    let src  = root + "/compiler/macos_arm64/macho_arm64_self.k"
    let fe   = root + "/compiler/macos_arm64/kcc-arm64"
    let need = "0"
    if exists(host) == "0" { need = "1" }
    else {
        if sh("test " + q(src) + " -nt " + q(host) + " && echo 1 || echo 0") == "1" { need = "1" }
    }
    if need == "0" { emit "1" }
    if has("clang") == "0" {
        kp("kcc: macho_host needs a one-time clang build, but clang not found")
        emit "0"
    }
    kp("kcc: building macho_host (one-time)...")
    let tmpc = sh("mktemp /tmp/_kcchost_XXXXXX.c")
    exec("KRYPTON_ROOT=" + q(root) + " " + q(fe) + " " + q(src) + " > " + q(tmpc))
    exec("clang -O2 -w " + q(tmpc) + " -o " + q(host) + " -lm")
    rm(tmpc)
    if exists(host) == "0" { kp("kcc: macho_host build failed")  emit "0" }
    emit "1"
}

// strip a .ks or .k extension to derive the default output name.
func baseName(src) {
    if endsWith(src, ".ks") { emit substring(src, 0, len(src) - 3) }
    if endsWith(src, ".k")  { emit substring(src, 0, len(src) - 2) }
    emit src
}

// native macOS arm64 compile: src -> out. Returns "1" ok / "0" fail.
func compileMacos(root, src, out) {
    let fe = root + "/compiler/macos_arm64/kcc-arm64"
    let host = root + "/compiler/macos_arm64/macho_host"
    if ensureHost(root) == "0" { emit "0" }
    let tmpir = sh("mktemp /tmp/_kcck_XXXXXX.kir")
    // frontend: .k -> IR  (KRYPTON_ROOT must reach it for k: imports)
    exec("KRYPTON_ROOT=" + q(root) + " " + q(fe) + " --ir " + q(src) + " > " + q(tmpir))
    if size(tmpir) == 0 {
        kp("kcc: IR emission failed for " + src)
        rm(tmpir)
        emit "0"
    }
    // backend: IR -> Mach-O
    exec(q(host) + " --ir " + q(tmpir) + " " + q(out))
    rm(tmpir)
    if exists(out) == "0" {
        kp("kcc: native codegen failed")
        emit "0"
    }
    exec("chmod +x " + q(out))
    emit "1"
}

// Ensure the Linux elf_host backend exists / is current; rebuild once via gcc
// (gcc here = toolchain bootstrap only, never for user programs). "1" ok / "0" fail.
func ensureElfHost(root) {
    let host = root + "/compiler/linux_x86/elf_host"
    let src  = root + "/compiler/linux_x86/elf.k"
    let fe   = root + "/compiler/linux_x86/kcc-x64"
    let need = "0"
    if exists(host) == "0" { need = "1" }
    else {
        if sh("test " + q(src) + " -nt " + q(host) + " && echo 1 || echo 0") == "1" { need = "1" }
    }
    if need == "0" { emit "1" }
    if has("gcc") == "0" {
        kp("kcc: elf_host needs a one-time gcc build, but gcc not found")
        emit "0"
    }
    kp("kcc: building elf_host (one-time gcc bootstrap)...")
    let tmpc = sh("mktemp /tmp/_kccelf_XXXXXX.c")
    exec("KRYPTON_ROOT=" + q(root) + " " + q(fe) + " " + q(src) + " > " + q(tmpc))
    exec("gcc -O2 -w " + q(tmpc) + " -o " + q(host) + " -lm")
    rm(tmpc)
    if exists(host) == "0" { kp("kcc: elf_host build failed")  emit "0" }
    emit "1"
}

// Ensure the Linux optimizer host exists / is current. Best-effort: returns
// "1" if usable, "0" to skip optimization (mirrors kcc.sh's silent skip).
func ensureOptHost(root) {
    let host = root + "/compiler/linux_x86/optimize_host"
    let src  = root + "/compiler/optimize.k"
    let fe   = root + "/compiler/linux_x86/kcc-x64"
    let need = "1"
    if exists(host) == "1" {
        if sh("test " + q(src) + " -nt " + q(host) + " && echo 1 || echo 0") == "0" { need = "0" }
    }
    if need == "0" { emit "1" }
    if has("gcc") == "0" { emit "0" }
    let tmpc = sh("mktemp /tmp/_kccopt_XXXXXX.c")
    exec("KRYPTON_ROOT=" + q(root) + " " + q(fe) + " " + q(src) + " > " + q(tmpc))
    exec("gcc -O2 -w " + q(tmpc) + " -o " + q(host) + " -lm")
    rm(tmpc)
    if exists(host) == "1" { emit "1" }
    emit "0"
}

// native Linux x86-64 compile: src -> out. Returns "1" ok / "0" fail.
func compileLinux(root, src, out) {
    let fe = root + "/compiler/linux_x86/kcc-x64"
    let host = root + "/compiler/linux_x86/elf_host"
    if ensureElfHost(root) == "0" { emit "0" }
    let tmpir = sh("mktemp /tmp/_kcck_XXXXXX.kir")
    exec("KRYPTON_ROOT=" + q(root) + " " + q(fe) + " --ir " + q(src) + " > " + q(tmpir))
    if size(tmpir) == 0 {
        kp("kcc: IR emission failed for " + src)
        rm(tmpir)
        emit "0"
    }
    // optimizer pass (best-effort, IR->IR; mirrors kcc.sh)
    if ensureOptHost(root) == "1" {
        let tmpopt = sh("mktemp /tmp/_kckopt_XXXXXX.kir")
        exec(q(root + "/compiler/linux_x86/optimize_host") + " " + q(tmpir) + " > " + q(tmpopt) + " 2>/dev/null")
        if size(tmpopt) == 0 { rm(tmpopt) }
        else { exec("mv " + q(tmpopt) + " " + q(tmpir)) }
    }
    exec(q(host) + " " + q(tmpir) + " " + q(out))
    rm(tmpir)
    if exists(out) == "0" {
        kp("kcc: native codegen failed")
        emit "0"
    }
    exec("chmod +x " + q(out))
    emit "1"
}

just run {
    if argCount() < 1 {
        kp(VERSION())
        kp("usage: kcc-native <src> [-o OUT] | -r <src> [args] | --ir <src> | --version")
        exit("1")
    }

    let first = arg(0)
    if first == "--version" || first == "-v" { kp(VERSION())  exit("0") }

    let root = findRoot()
    if root == "" {
        kp("kcc: cannot find install root (set KRYPTON_ROOT)")
        exit("1")
    }

    let os = sh("uname -s")

    // ── Linux native pipeline (kcc-x64 frontend -> elf_host backend) ──────────
    if os == "Linux" {
        if first == "--ir" {
            if argCount() < 2 { kp("kcc: --ir needs a source file")  exit("1") }
            let fe = root + "/compiler/linux_x86/kcc-x64"
            kp(sh("KRYPTON_ROOT=" + q(root) + " " + q(fe) + " --ir " + q(arg(1))))
            exit("0")
        }
        // --c: emit C source (front-end with no --ir). Legacy/debug, kept for parity.
        if first == "--c" {
            if argCount() < 2 { kp("kcc: --c needs a source file")  exit("1") }
            let csrc = arg(1)
            let cfe = root + "/compiler/linux_x86/kcc-x64"
            let cout = optValue("-o", "")
            if cout == "" { kp(sh("KRYPTON_ROOT=" + q(root) + " " + q(cfe) + " " + q(csrc))) }
            else { exec("KRYPTON_ROOT=" + q(root) + " " + q(cfe) + " " + q(csrc) + " > " + q(cout)) }
            exit("0")
        }
        // -e CODE [args]: wrap in `just run { ... }`, compile, run, delete.
        // Write the wrapped source with writeText (NOT shell printf) so embedded
        // quotes/newlines in CODE survive.
        if first == "-e" {
            if argCount() < 2 { kp("kcc: -e needs code")  exit("1") }
            let ek = sh("mktemp /tmp/_kcceval_XXXXXX.ks")
            writeText(ek, "just run {\n" + arg(1) + "\n}\n")
            let ebin = sh("mktemp /tmp/_kcceval_XXXXXX")
            if compileLinux(root, ek, ebin) == "0" { rm(ek)  exit("1") }
            kp(sh(q(ebin) + " " + restFrom(2)))
            rm(ek)  rm(ebin)
            exit("0")
        }
        if first == "-r" {
            if argCount() < 2 { kp("kcc: -r needs a source file")  exit("1") }
            let tmpbin = sh("mktemp /tmp/_kcckrun_XXXXXX")
            if compileLinux(root, arg(1), tmpbin) == "0" { exit("1") }
            let passed = restFrom(2)
            kp(sh(q(tmpbin) + " " + passed))
            rm(tmpbin)
            exit("0")
        }
        let lsrc = positional(0)
        if lsrc == "" { kp("kcc: no source file")  exit("1") }
        let lout = optValue("-o", baseName(lsrc))
        if compileLinux(root, lsrc, lout) == "0" { exit("1") }
        exit("0")
    }

    if os != "Darwin" {
        kp("kcc-native: unsupported host " + os + " (macOS + Linux wired)")
        exit("1")
    }

    // --ir <src>: just stream IR from the frontend.
    if first == "--ir" {
        if argCount() < 2 { kp("kcc: --ir needs a source file")  exit("1") }
        let src = arg(1)
        let fe = root + "/compiler/macos_arm64/kcc-arm64"
        kp(sh("KRYPTON_ROOT=" + q(root) + " " + q(fe) + " --ir " + q(src)))
        exit("0")
    }

    // -r <src> [args...]: compile to temp, run, delete.
    if first == "-r" {
        if argCount() < 2 { kp("kcc: -r needs a source file")  exit("1") }
        let src = arg(1)
        let tmpbin = sh("mktemp /tmp/_kcckrun_XXXXXX")
        if compileMacos(root, src, tmpbin) == "0" { exit("1") }
        // pass through any args after the source. sh() chomps the trailing
        // newline so kp re-adds exactly one (shRaw would double it).
        let passed = restFrom(2)
        kp(sh(q(tmpbin) + " " + passed))
        rm(tmpbin)
        exit("0")
    }

    // default: compile src [-o OUT].
    let src = positional(0)
    if src == "" { kp("kcc: no source file")  exit("1") }
    let out = optValue("-o", baseName(src))
    // macho_host prints "wrote <out> (...signed)" itself; don't double-report.
    if compileMacos(root, src, out) == "0" { exit("1") }
}
