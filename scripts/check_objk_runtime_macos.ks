#!/usr/bin/env kr

import "k:env"

func q(s) {
    let quote = fromCharCode(39)
    emit quote + replace(s, quote, quote + "\\" + quote + quote) + quote
}

func compileCheck(root, work, source, name) {
    let binary = work + "/" + name
    let log = work + "/" + name + ".log"
    let cmd = "KRYPTON_ROOT=" + q(root) + " " +
        q(root + "/bootstrap/kcc_driver_macos_aarch64") + " " + q(source) +
        " -o " + q(binary) + " >" + q(log) + " 2>&1"
    if shellRun(cmd) != "0" {
        kp("FAIL compile " + name)
        kp(readFile(log))
        exit("1")
    }
    emit binary
}

func runCheck(binary, name, log) {
    let rc = shellRun(q(binary) + " >" + q(log) + " 2>&1")
    if rc != "0" || contains(readFile(log), "[FAIL]") {
        kp("FAIL " + name + " rc=" + rc)
        kp(readFile(log))
        exit("1")
    }
    kp("OK " + name)
}

func rejectCheck(binary, mode, expected, log) {
    let rc = shellRun(q(binary) + " " + q(mode) + " >" + q(log) + " 2>&1")
    if rc == "0" || !contains(readFile(log), "Objective-K: " + expected) {
        kp("FAIL rejection " + mode + " rc=" + rc)
        kp(readFile(log))
        exit("1")
    }
    kp("OK rejects " + mode)
}

func compileReject(root, source, binary, log) {
    let cmd = "KRYPTON_ROOT=" + q(root) + " " +
        q(root + "/bootstrap/kcc_driver_macos_aarch64") + " " + q(source) +
        " -o " + q(binary) + " >" + q(log) + " 2>&1"
    let rc = shellRun(cmd)
    if rc == "0" || !contains(readFile(log), "callPtr needs a pointer and 0..8 arguments") {
        kp("FAIL invalid function-pointer arity")
        kp(readFile(log))
        exit("1")
    }
    kp("OK rejects " + source)
}

just run {
    if trim(exec("uname -s")) != "Darwin" {
        kp("SKIP macOS Objective-K runtime")
        exit("0")
    }
    let root = trim(exec("pwd"))
    let work = trim(exec("mktemp -d /tmp/check_objk_macos.XXXXXX"))
    if work == "" { kp("FAIL temporary directory"); exit("1") }
    let log = work + "/run.log"
    let globals = compileCheck(root, work, "tests/macos/test_imported_globals.k", "globals")
    runCheck(globals, "imported globals", log)
    let pointers = compileCheck(root, work, "tests/macos/test_callptr.k", "pointers")
    runCheck(pointers, "native function pointers", log)
    compileReject(root, "tests/macos/fixtures/callptr_missing.k", work + "/bad", log)
    compileReject(root, "tests/macos/fixtures/callptr_too_many.k", work + "/bad", log)
    let nullPointer = compileCheck(root, work, "tests/macos/fixtures/callptr_null.k", "null")
    let nullRc = shellRun(q(nullPointer) + " >" + q(log) + " 2>&1")
    if nullRc != "133" { kp("FAIL null pointer guard rc=" + nullRc); exit("1") }
    kp("OK null pointer traps before call")
    let core = compileCheck(root, work, "tests/macos/test_objk_runtime.k", "core")
    runCheck(core, "K-owned object runtime", log)
    if shellRun("otool -L " + q(core) + " >" + q(log) + " 2>&1") != "0" {
        kp("FAIL inspect object-core dependencies")
        exit("1")
    }
    let dependencies = readFile(log)
    if contains(dependencies, "libobjc") || contains(dependencies, "Foundation.framework") ||
        contains(dependencies, "AppKit.framework") || contains(dependencies, "UIKit.framework") {
        kp("FAIL object core imports Apple object frameworks")
        exit("1")
    }
    kp("OK object core has no Apple object-runtime dependency")
    let lifetime = compileCheck(root, work, "tests/macos/test_objk_lifetime.k", "lifetime")
    runCheck(lifetime, "owned fields and cleanup", log)
    let weak = compileCheck(root, work, "tests/macos/test_objk_weak.k", "weak")
    runCheck(weak, "weak fields", log)

    let invalid = compileCheck(root, work, "tests/fixtures/objk_runtime_invalid.ks", "invalid")
    rejectCheck(invalid, "unregistered", "class not registered", log)
    rejectCheck(invalid, "parent", "parent class not registered", log)
    rejectCheck(invalid, "duplicate", "duplicate method", log)
    rejectCheck(invalid, "sealed", "class already registered", log)
    rejectCheck(invalid, "method", "unknown method", log)
    rejectCheck(invalid, "arity", "method argument count", log)
    rejectCheck(invalid, "field", "unknown field", log)
    rejectCheck(invalid, "handle", "invalid handle", log)
    rejectCheck(invalid, "interior", "invalid handle", log)
    rejectCheck(invalid, "kind", "wrong handle kind", log)
    rejectCheck(invalid, "pointer", "field needs integer or arena handle", log)
    rejectCheck(invalid, "capacity", "arena full", log)
    rejectCheck(invalid, "released", "object released", log)
    rejectCheck(invalid, "double-release", "object released", log)
    rejectCheck(invalid, "retain-dead", "object released", log)
    rejectCheck(invalid, "cleanup-null", "invalid cleanup callback", log)
    rejectCheck(invalid, "cleanup-duplicate", "cleanup already registered", log)
    rejectCheck(invalid, "cleanup-sealed", "class already registered", log)
    rejectCheck(invalid, "cleanup-retain", "object releasing", log)
    rejectCheck(invalid, "cleanup-release", "object releasing", log)
    rejectCheck(invalid, "cleanup-write", "object releasing", log)
    rejectCheck(invalid, "cleanup-own", "object releasing", log)
    rejectCheck(invalid, "own-class", "wrong handle kind", log)
    rejectCheck(invalid, "own-invalid", "invalid handle", log)
    rejectCheck(invalid, "own-dead", "object released", log)
    rejectCheck(invalid, "own-overwrite", "owned field needs doKOwn", log)
    rejectCheck(invalid, "weak-class", "wrong handle kind", log)
    rejectCheck(invalid, "weak-invalid", "invalid handle", log)
    rejectCheck(invalid, "weak-dead", "object released", log)
    rejectCheck(invalid, "weak-overwrite", "weak field needs doKWeak", log)
    rejectCheck(invalid, "weak-to-owned", "weak field needs doKWeak", log)
    rejectCheck(invalid, "owned-to-weak", "owned field needs doKOwn", log)
    if arg("0") == "--gui" {
        let gui = compileCheck(root, work, "examples/objk/k_owned_counter_macos.ks", "counter")
        let rc = shellRun(q(gui) + " --smoke >" + q(log) + " 2>&1")
        if rc != "0" || !contains(readFile(log), "[PASS] K model/native callback integration") {
            kp("FAIL native window/callback integration rc=" + rc)
            kp(readFile(log))
            exit("1")
        }
        kp("OK native window and K model callbacks")
    }
    kp("logs: " + work)
}
