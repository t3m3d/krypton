// macho.k — Krypton macOS backend.
//
// PHILOSOPHY (different from elf.k / x64.k by design):
//
// On Linux we emit the final ELF directly because the kernel will run any
// well-formed static binary. On Windows we emit the final PE directly because
// the loader is permissive too. On modern macOS — especially Tahoe (26.x)+ —
// AMFI rejects hand-rolled static binaries even when properly code-signed.
// Apple effectively requires dyld-linked Mach-Os built through their toolchain.
//
// Rather than reproduce all of dyld's scaffolding (chained fixups, exports
// trie, dyld linkage, symbol stubs — multi-day work without a Mac in the dev
// loop), this backend emits **assembly source** (`.s`). The macOS toolchain
// (clang internally invoking `as` + `ld64`) does the rest:
//   - Resolves libSystem references (`_puts`, `_exit`, etc.)
//   - Generates dyld scaffolding (`LC_LOAD_DYLINKER`, chained fixups, etc.)
//   - Signs the final binary
//
// External requirement: Xcode Command Line Tools (`xcode-select --install`).
//
// Usage:
//   kcc kompiler/macho.k --arch x86_64|arm64 <out.s>
//   then:
//   clang -arch <arch> <out.s> -o <out>
//
// First milestone: hardcoded hello-world. Once verified on Tahoe, expand to
// IR parsing the way elf.k did.

func charCodeOf(s, i) { emit charCode(s[i]) }

// ── x86_64 hello-world assembly ────────────────────────────────────────────
//
// Standard SysV-on-macOS calling convention:
//   RDI = arg1, return in RAX, stack 16-aligned at call boundary
//
//   pushq %rbp              ; save caller's frame ptr  (1 byte)
//   movq  %rsp, %rbp        ; new frame                (3 bytes)
//   leaq  L_msg(%rip), %rdi ; arg1 = msg               (7 bytes)
//   callq _puts             ; libSystem puts (adds \n) (5 bytes, ld relocates)
//   xorl  %eax, %eax        ; return 0                 (2 bytes)
//   popq  %rbp                                          (1 byte)
//   retq                                                (1 byte)
//
// Returning from `_main` triggers libSystem's exit handler — no explicit exit
// syscall needed.
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

// ── ARM64 hello-world assembly ─────────────────────────────────────────────
//
// AAPCS64 calling convention:
//   X0 = arg1, return in W0/X0, FP/LR pair must be saved on entry.
//
//   stp  x29, x30, [sp, #-16]! ; save FP+LR, allocate frame  (4B)
//   mov  x29, sp               ; new frame                    (4B)
//   adrp x0, L_msg@PAGE        ; page address of msg          (4B)
//   add  x0, x0, L_msg@PAGEOFF ; add page offset              (4B)
//   bl   _puts                 ; libSystem puts               (4B, relocated)
//   mov  w0, #0                ; return 0                     (4B)
//   ldp  x29, x30, [sp], #16   ; restore FP+LR, dealloc frame (4B)
//   ret                                                       (4B)
//
// ADRP+ADD is the standard PC-relative address load on ARM64 (mandatory for
// PIE binaries — and on Apple Silicon, all binaries are PIE).
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


// ── Main: write hello-world .s for the requested arch ──────────────────────

just run {
    let arch = "x86_64"
    let outPath = ""
    let ai = 0
    let n = argCount()
    while ai < n {
        let a = arg(ai)
        if a == "--arch" {
            ai += 1
            if ai < n { arch = arg(ai) }
        } else if startsWith(a, "--arch=") {
            arch = substring(a, 7, len(a))
        } else {
            outPath = a
        }
        ai += 1
    }

    if arch != "x86_64" {
        if arch != "arm64" {
            printErr("macho: unsupported --arch '" + arch + "' (use x86_64 or arm64)")
            exit(1)
        }
    }

    if len(outPath) == 0 {
        printErr("macho: usage: macho [--arch x86_64|arm64] <output.s>")
        exit(1)
    }

    let asmText = ""
    if arch == "arm64" {
        asmText = arm64HelloAsm()
    } else {
        asmText = x86_64HelloAsm()
    }

    writeFile(outPath, asmText)
    printErr("macho: wrote " + outPath + " (" + len(asmText) + " bytes of " + arch + " assembly)")
    printErr("       Build with: clang -arch " + arch + " " + outPath + " -o <output>")
}
