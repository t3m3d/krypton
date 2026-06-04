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
// SCOPE: macOS arm64 + Linux x86-64 native, + Linux aarch64 cross-compile (--arm64).
// Modes: --version/--ir/-o/-r/-e/--c. (Windows not yet wired.) One KryptScript
// driver, no bash, no .bat.
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
import "k:arch"

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

// Ensure the Linux elf_host backend exists / is current. NO C compiler:
//   - user path:        cp the committed native seed (no build)
//   - backend-edit path: self-host — the seed elf_host compiles the edited
//                        elf.k's IR into a fresh elf_host (slow FE, but no gcc).
// "1" ok / "0" fail.
func ensureElfHost(root) {
    let host = root + "/compiler/linux_x86/elf_host"
    let src  = root + "/compiler/linux_x86/elf.k"
    let fe   = root + "/compiler/linux_x86/kcc-x64"
    let seed = root + "/bootstrap/elf_host_linux_x86_64"
    let need = "0"
    if exists(host) == "0" { need = "1" }
    else {
        if sh("test " + q(src) + " -nt " + q(host) + " && echo 1 || echo 0") == "1" { need = "1" }
    }
    if need == "0" { emit "1" }
    // Committed seed not older than elf.k → use it as-is (the user path, no build).
    if exists(seed) == "1" {
        if sh("test " + q(src) + " -nt " + q(seed) + " && echo 1 || echo 0") == "0" {
            exec("cp " + q(seed) + " " + q(host))
            exec("chmod +x " + q(host))
            emit "1"
        }
    }
    // elf.k edited past the seed → rebuild natively by self-hosting. No gcc.
    let boot = seed
    if exists(boot) == "0" { boot = host }
    if exists(boot) == "0" {
        kp("kcc: no elf_host seed to self-host from; cannot rebuild backend")
        emit "0"
    }
    kp("kcc: rebuilding elf_host natively (self-host, no C — slow on elf.k)...")
    let tmpir = sh("mktemp /tmp/_kccelf_XXXXXX.kir")
    exec("KRYPTON_ROOT=" + q(root) + " " + q(fe) + " --ir " + q(src) + " > " + q(tmpir))
    exec(q(boot) + " " + q(tmpir) + " " + q(host))
    rm(tmpir)
    exec("chmod +x " + q(host))
    if exists(host) == "0" { kp("kcc: elf_host self-host failed")  emit "0" }
    emit "1"
}

// Ensure the Linux optimizer host exists / is current. Best-effort: returns
// "1" if usable, "0" to skip optimization. NO C compiler: cp the seed, else
// the native elf_host compiles optimize.k.
func ensureOptHost(root) {
    let host = root + "/compiler/linux_x86/optimize_host"
    let src  = root + "/compiler/optimize.k"
    let fe   = root + "/compiler/linux_x86/kcc-x64"
    let elf  = root + "/compiler/linux_x86/elf_host"
    let seed = root + "/bootstrap/optimize_host_linux_x86_64"
    let need = "1"
    if exists(host) == "1" {
        if sh("test " + q(src) + " -nt " + q(host) + " && echo 1 || echo 0") == "0" { need = "0" }
    }
    if need == "0" { emit "1" }
    if exists(seed) == "1" {
        if sh("test " + q(src) + " -nt " + q(seed) + " && echo 1 || echo 0") == "0" {
            exec("cp " + q(seed) + " " + q(host))
            exec("chmod +x " + q(host))
            emit "1"
        }
    }
    // Native rebuild: elf_host compiles optimize.k's IR. No gcc.
    if exists(elf) == "0" { emit "0" }
    let tmpir = sh("mktemp /tmp/_kccopt_XXXXXX.kir")
    exec("KRYPTON_ROOT=" + q(root) + " " + q(fe) + " --ir " + q(src) + " > " + q(tmpir))
    exec(q(elf) + " " + q(tmpir) + " " + q(host))
    rm(tmpir)
    if exists(host) == "1" { emit "1" }
    emit "0"
}

// First non-flag source arg, skipping -o and its value. (positional() wrongly
// treats valueless flags like --arm64/--ir/--c/-r as consuming the next token.)
func linuxSrc() {
    let i = 0
    while i < argCount() {
        let a = arg(i)
        if a == "-o" { i = i + 2 }
        else {
            if startsWith(a, "-") { i = i + 1 }
            else { emit a }
        }
    }
    emit ""
}

// Ensure the aarch64 backend host (an x86 binary that EMITS arm64) is built from
// compiler/linux_arm64/elf.k. "1" ok / "0" fail.
func ensureArm64Host(root) {
    let host = root + "/compiler/linux_arm64/elf_host"
    let bsrc = root + "/compiler/linux_arm64/elf.k"
    let fe   = root + "/compiler/linux_x86/kcc-x64"
    let need = "1"
    if exists(host) == "1" {
        if sh("test " + q(bsrc) + " -nt " + q(host) + " && echo 1 || echo 0") == "0" { need = "0" }
    }
    if need == "0" { emit "1" }
    // The arm64 backend host is an x86 binary that EMITS arm64, so the x86
    // NATIVE pipeline builds it — no gcc. Ensure the x86 elf_host exists, then
    // it compiles linux_arm64/elf.k's IR into the arm64-emitter host.
    if ensureElfHost(root) == "0" { emit "0" }
    let elf = root + "/compiler/linux_x86/elf_host"
    kp("kcc: building arm64 backend host natively (self-host, no C)...")
    let tmpir = sh("mktemp /tmp/_kccarm_XXXXXX.kir")
    exec("KRYPTON_ROOT=" + q(root) + " " + q(fe) + " --ir " + q(bsrc) + " > " + q(tmpir))
    exec(q(elf) + " " + q(tmpir) + " " + q(host))
    rm(tmpir)
    exec("chmod +x " + q(host))
    if exists(host) == "1" { emit "1" }
    emit "0"
}

// Cross-compile to a static aarch64 ELF: x86 front-end IR -> arm64 backend.
// (No optimizer pass yet — the arm64 backend consumes the raw IR.) "1"/"0".
func compileArm64(root, src, out) {
    let fe = root + "/compiler/linux_x86/kcc-x64"
    let host = root + "/compiler/linux_arm64/elf_host"
    if ensureArm64Host(root) == "0" { emit "0" }
    let tmpir = sh("mktemp /tmp/_kcka_XXXXXX.kir")
    exec("KRYPTON_ROOT=" + q(root) + " " + q(fe) + " --ir " + q(src) + " > " + q(tmpir))
    if size(tmpir) == 0 {
        kp("kcc: IR emission failed for " + src)
        rm(tmpir)
        emit "0"
    }
    exec(q(host) + " " + q(tmpir) + " " + q(out))
    rm(tmpir)
    if exists(out) == "0" {
        kp("kcc: arm64 codegen failed")
        emit "0"
    }
    exec("chmod +x " + q(out))
    emit "1"
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

    // --print-arch: print the host CPU architecture and exit. Lets shell
    // scripts and PKGBUILDs branch on host arch without hardcoding `uname -m`
    // (which doesn't capture cleanly under Krypton's shellRun on Linux).
    //   x86_64 | arm64 | x86 | armv7 | unknown
    if first == "--print-arch" { kp(arch())  exit("0") }

    let root = findRoot()
    if root == "" {
        kp("kcc: cannot find install root (set KRYPTON_ROOT)")
        exit("1")
    }

    let os = sh("uname -s")

    // ── Linux native pipeline (x86-64 native, or --arm64 cross to aarch64) ────
    if os == "Linux" {
        // Auto-route to the right backend by host arch unless the user
        // overrides with an explicit --arm64 (force cross to aarch64) or
        // --x64 (force x86-64 even on an aarch64 host).
        //   host x86_64 + no flags   -> x86_64 backend (legacy default)
        //   host arm64  + no flags   -> arm64 backend (NEW)
        //   --arm64                  -> arm64 backend regardless of host
        //   --x64                    -> x86_64 backend regardless of host
        let toArm = "0"
        if hasFlag("--arm64") == "1" { toArm = "1" }
        else { if hasFlag("--x64") == "0" { if arch() == "arm64" { toArm = "1" } } }
        let fe = root + "/compiler/linux_x86/kcc-x64"   // x86 front-end emits arch-agnostic IR

        // --ir: stream IR (arch-agnostic).
        if hasFlag("--ir") {
            let s = linuxSrc()
            if s == "" { kp("kcc: --ir needs a source file")  exit("1") }
            kp(sh("KRYPTON_ROOT=" + q(root) + " " + q(fe) + " --ir " + q(s)))
            exit("0")
        }
        // --c: emit C source (front-end, no --ir).
        if hasFlag("--c") {
            let s = linuxSrc()
            if s == "" { kp("kcc: --c needs a source file")  exit("1") }
            let cout = optValue("-o", "")
            if cout == "" { kp(sh("KRYPTON_ROOT=" + q(root) + " " + q(fe) + " " + q(s))) }
            else { exec("KRYPTON_ROOT=" + q(root) + " " + q(fe) + " " + q(s) + " > " + q(cout)) }
            exit("0")
        }
        // --gcc is REMOVED — Krypton is C-free; native is the only path.
        if hasFlag("--gcc") {
            kp("kcc: --gcc was removed (Krypton compiles natively, no C). Building native.")
        }
        // --llvm / --wasm: non-functional upstream (kcc.sh's --llvm emits C; --wasm
        // is an unimplemented stub). Be honest instead of mimicking the bug.
        if hasFlag("--llvm") { kp("kcc: --llvm is not supported; use --c for C output, or native.")  exit("1") }
        if hasFlag("--wasm") { kp("kcc: --wasm is not wired into the Krypton-native driver yet.")  exit("1") }

        // -e CODE: wrap in `just run { ... }`, compile (x86 or arm64), run, delete.
        if first == "-e" {
            if argCount() < 2 { kp("kcc: -e needs code")  exit("1") }
            let ek = sh("mktemp /tmp/_kcceval_XXXXXX.ks")
            writeText(ek, "just run {\n" + arg(1) + "\n}\n")
            let ebin = sh("mktemp /tmp/_kcceval_XXXXXX")
            let oke = "0"
            if toArm == "1" { oke = compileArm64(root, ek, ebin) } else { oke = compileLinux(root, ek, ebin) }
            if oke == "0" { rm(ek)  exit("1") }
            kp(sh(q(ebin)))                      // arm64 runs via qemu binfmt
            rm(ek)  rm(ebin)
            exit("0")
        }

        // -r (compile+run) or default (compile to -o). --arm64 selects the backend.
        let s = linuxSrc()
        if s == "" { kp("kcc: no source file")  exit("1") }
        if hasFlag("-r") {
            let tmpbin = sh("mktemp /tmp/_kcckrun_XXXXXX")
            let okr = "0"
            if toArm == "1" { okr = compileArm64(root, s, tmpbin) } else { okr = compileLinux(root, s, tmpbin) }
            if okr == "0" { exit("1") }
            kp(sh(q(tmpbin)))                    // arm64 runs via qemu binfmt
            rm(tmpbin)
            exit("0")
        }
        let out = optValue("-o", baseName(s))
        let okc = "0"
        if toArm == "1" { okc = compileArm64(root, s, out) } else { okc = compileLinux(root, s, out) }
        if okc == "0" { exit("1") }
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
