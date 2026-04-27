// macho.k — Krypton macOS backend.
//
// PHILOSOPHY (different from elf.k / x64.k by design):
//
// On Linux we emit final ELF directly (kernel runs any well-formed static
// binary). On Windows we emit final PE directly (loader is permissive).
// On modern macOS — especially Tahoe (26.x)+ — AMFI rejects hand-rolled
// static binaries even when properly code-signed. Apple effectively requires
// dyld-linked Mach-Os built through their toolchain.
//
// So this backend emits **assembly source** (`.s`) and lets `clang` invoke
// `as` + `ld64` to handle dyld scaffolding, libSystem linkage, and signing.
//
// External requirement: Xcode Command Line Tools (`xcode-select --install`).
//
// Usage:
//   kcc kompiler/macho.k [--arch x86_64|arm64] <input.kir> <output.s>
//   clang -arch <arch> <output.s> -o <output>
//
// Or, for the hardcoded hello-world demo:
//   kcc kompiler/macho.k --hello-test [--arch x86_64|arm64] <output.s>
//
// IR ops supported in this version (matches elf.k v1):
//   FUNC __main__ N       - only __main__ recognized; treated as _main entry
//   PUSH "literal"        - push string ptr onto runtime stack
//   BUILTIN kp 1          - pop 1, call _puts (libSystem, prints + newline)
//   POP                   - drop top of stack
//   END                   - function epilogue (return 0 from _main)
//
// More ops (locals, arithmetic, control flow, other builtins) are planned.

func startsWithStr(s, prefix) {
    if len(s) < len(prefix) { emit 0 }
    let i = 0
    while i < len(prefix) {
        if s[i] != prefix[i] { emit 0 }
        i += 1
    }
    emit 1
}

// Extract the substring between the FIRST and LAST quote in line.
// E.g. `PUSH "Hello, world!"` → `Hello, world!`.
// Assumes IR's quote-escaping convention (no unescaped " inside).
func extractQuotedString(line) {
    let i = 0
    let n = len(line)
    while i < n {
        if line[i] == "\"" { i = i + 1  break }
        i += 1
    }
    let start = i
    let j = n - 1
    while j >= start {
        if line[j] == "\"" { break }
        j -= 1
    }
    if j <= start { emit "" }
    emit substring(line, start, j)
}


// ── Hardcoded hello-world (kept for the smoke test) ───────────────────────

func x86_64HelloAsm() {
    let s = ""
    s = s + "    .section __TEXT,__text,regular,pure_instructions" + fromCharCode(10)
    s = s + "    .globl _main" + fromCharCode(10)
    s = s + "    .p2align 4, 0x90" + fromCharCode(10)
    s = s + "_main:" + fromCharCode(10)
    s = s + "    pushq %rbp" + fromCharCode(10)
    s = s + "    movq %rsp, %rbp" + fromCharCode(10)
    s = s + "    leaq L_msg(%rip), %rdi" + fromCharCode(10)
    s = s + "    callq _puts" + fromCharCode(10)
    s = s + "    xorl %eax, %eax" + fromCharCode(10)
    s = s + "    popq %rbp" + fromCharCode(10)
    s = s + "    retq" + fromCharCode(10)
    s = s + fromCharCode(10)
    s = s + "    .section __TEXT,__cstring,cstring_literals" + fromCharCode(10)
    s = s + "L_msg:" + fromCharCode(10)
    s = s + "    .asciz \"Hello from Krypton on macOS!\"" + fromCharCode(10)
    emit s
}

func arm64HelloAsm() {
    let s = ""
    s = s + "    .section __TEXT,__text,regular,pure_instructions" + fromCharCode(10)
    s = s + "    .globl _main" + fromCharCode(10)
    s = s + "    .p2align 2" + fromCharCode(10)
    s = s + "_main:" + fromCharCode(10)
    s = s + "    stp x29, x30, [sp, #-16]!" + fromCharCode(10)
    s = s + "    mov x29, sp" + fromCharCode(10)
    s = s + "    adrp x0, L_msg@PAGE" + fromCharCode(10)
    s = s + "    add x0, x0, L_msg@PAGEOFF" + fromCharCode(10)
    s = s + "    bl _puts" + fromCharCode(10)
    s = s + "    mov w0, #0" + fromCharCode(10)
    s = s + "    ldp x29, x30, [sp], #16" + fromCharCode(10)
    s = s + "    ret" + fromCharCode(10)
    s = s + fromCharCode(10)
    s = s + "    .section __TEXT,__cstring,cstring_literals" + fromCharCode(10)
    s = s + "L_msg:" + fromCharCode(10)
    s = s + "    .asciz \"Hello from Krypton on macOS!\"" + fromCharCode(10)
    emit s
}


// ── IR-driven assembly compilation ─────────────────────────────────────────
//
// Walks the .kir text line by line and emits assembly. Strings are collected
// into per-occurrence labels (no deduplication yet — slight space waste but
// simpler and correct).
//
// Stack convention (matches elf.k's stack-machine model):
//   PUSH X                       → push value to runtime stack
//   BUILTIN <name> <argc>        → pop argc args, call helper, push result
//   POP                          → discard top of stack
//
// Native stack mapping:
//   x86_64: pushq/popq with rsp; callq aligns 16-byte at call boundary
//   arm64:  str x0,[sp,#-16]! / ldr x0,[sp],#16 (16-byte slots maintain SP align)

func compileIRToAsm(ir, arch) {
    let out = sbNew()
    out = sbAppend(out, "    .section __TEXT,__text,regular,pure_instructions\n")
    out = sbAppend(out, "    .globl _main\n")
    if arch == "arm64" {
        out = sbAppend(out, "    .p2align 2\n")
    } else {
        out = sbAppend(out, "    .p2align 4, 0x90\n")
    }

    let strDecls = sbNew()
    let strCounter = 0

    let n = len(ir)
    let curSb = sbNew()
    let i = 0

    while i <= n {
        let isLineEnd = 0
        if i == n { isLineEnd = 1 }
        if i < n {
            if ir[i] == "\n" { isLineEnd = 1 }
        }

        if isLineEnd == 1 {
            let line = sbToString(curSb)
            curSb = sbNew()

            let isComment = 0
            if len(line) > 0 {
                if line[0] == ";" { isComment = 1 }
            }

            if len(line) > 0 {
                if isComment == 0 {
                    if startsWithStr(line, "FUNC __main__") {
                        out = sbAppend(out, "_main:\n")
                        if arch == "arm64" {
                            out = sbAppend(out, "    stp x29, x30, [sp, #-16]!\n")
                            out = sbAppend(out, "    mov x29, sp\n")
                        } else {
                            out = sbAppend(out, "    pushq %rbp\n")
                            out = sbAppend(out, "    movq %rsp, %rbp\n")
                        }
                    } else if startsWithStr(line, "PUSH \"") {
                        let s = extractQuotedString(line)
                        let label = "L_str" + strCounter
                        if arch == "arm64" {
                            out = sbAppend(out, "    adrp x0, " + label + "@PAGE\n")
                            out = sbAppend(out, "    add x0, x0, " + label + "@PAGEOFF\n")
                            out = sbAppend(out, "    str x0, [sp, #-16]!\n")
                        } else {
                            out = sbAppend(out, "    leaq " + label + "(%rip), %rax\n")
                            out = sbAppend(out, "    pushq %rax\n")
                        }
                        strDecls = sbAppend(strDecls, label + ":\n    .asciz \"" + s + "\"\n")
                        strCounter += 1
                    } else if startsWithStr(line, "BUILTIN kp") {
                        // Pop arg, call _puts, push return for stack balance.
                        if arch == "arm64" {
                            out = sbAppend(out, "    ldr x0, [sp], #16\n")
                            out = sbAppend(out, "    bl _puts\n")
                            out = sbAppend(out, "    str x0, [sp, #-16]!\n")
                        } else {
                            out = sbAppend(out, "    popq %rdi\n")
                            out = sbAppend(out, "    callq _puts\n")
                            out = sbAppend(out, "    pushq %rax\n")
                        }
                    } else if line == "POP" {
                        if arch == "arm64" {
                            out = sbAppend(out, "    ldr x0, [sp], #16\n")
                        } else {
                            out = sbAppend(out, "    popq %rax\n")
                        }
                    } else if line == "END" {
                        if arch == "arm64" {
                            out = sbAppend(out, "    mov w0, #0\n")
                            out = sbAppend(out, "    ldp x29, x30, [sp], #16\n")
                            out = sbAppend(out, "    ret\n")
                        } else {
                            out = sbAppend(out, "    movq %rbp, %rsp\n")
                            out = sbAppend(out, "    popq %rbp\n")
                            out = sbAppend(out, "    xorl %eax, %eax\n")
                            out = sbAppend(out, "    retq\n")
                        }
                    }
                    // Unknown ops silently skipped — will surface as missing
                    // behavior at runtime; future op support gets added here.
                }
            }
        } else {
            curSb = sbAppend(curSb, ir[i])
        }
        i += 1
    }

    out = sbAppend(out, "\n    .section __TEXT,__cstring,cstring_literals\n")
    out = sbAppend(out, sbToString(strDecls))

    emit sbToString(out)
}


// ── Main ──────────────────────────────────────────────────────────────────

just run {
    let arch = "x86_64"
    let inFile = ""
    let outFile = ""
    let helloTest = 0
    let posCount = 0

    let ai = 0
    let n = argCount()
    while ai < n {
        let a = arg(ai)
        if a == "--arch" {
            ai += 1
            if ai < n { arch = arg(ai) }
        } else if startsWithStr(a, "--arch=") {
            arch = substring(a, 7, len(a))
        } else if a == "--hello-test" {
            helloTest = 1
        } else {
            if posCount == 0 { inFile = a } else { outFile = a }
            posCount += 1
        }
        ai += 1
    }

    // For --hello-test, the single positional arg is the output path.
    if helloTest == 1 {
        if posCount == 1 {
            outFile = inFile
            inFile = ""
        }
    }

    if arch != "x86_64" {
        if arch != "arm64" {
            printErr("macho: unsupported --arch '" + arch + "' (use x86_64 or arm64)")
            exit(1)
        }
    }

    if len(outFile) == 0 {
        printErr("usage: macho [--arch x86_64|arm64] <input.kir> <output.s>")
        printErr("       macho [--arch x86_64|arm64] --hello-test <output.s>")
        exit(1)
    }

    let asmText = ""
    if helloTest == 1 || len(inFile) == 0 {
        if arch == "arm64" {
            asmText = arm64HelloAsm()
        } else {
            asmText = x86_64HelloAsm()
        }
    } else {
        let ir = readFile(inFile)
        if len(ir) == 0 {
            printErr("macho: cannot read IR file: " + inFile)
            exit(1)
        }
        asmText = compileIRToAsm(ir, arch)
    }

    writeFile(outFile, asmText)
    printErr("macho: wrote " + outFile + " (" + len(asmText) + " bytes, " + arch + ")")
    if helloTest == 1 || len(inFile) == 0 {
        printErr("       (hardcoded hello-world; use without --hello-test for IR mode)")
    }
    printErr("       Build with: clang -arch " + arch + " " + outFile + " -o <output>")
}
