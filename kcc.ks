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
// SCOPE (prototype): macOS arm64 native pipeline + --version/--ir/-o/-r. Linux
// and Windows stubs point at their backends but aren't wired yet.
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
func findRoot() {
    let r = env("KRYPTON_ROOT")
    if r != "" {
        if exists(r + "/compiler/macos_arm64/kcc-arm64") == "1" { emit r }
    }
    let dev = home() + "/Documents/GitHub/krypton"
    if exists(dev + "/compiler/macos_arm64/kcc-arm64") == "1" { emit dev }
    if exists("/usr/local/krypton/compiler/macos_arm64/kcc-arm64") == "1" { emit "/usr/local/krypton" }
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
    if os != "Darwin" {
        kp("kcc-native prototype: only macOS wired up; this host is " + os)
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
