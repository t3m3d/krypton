// macho_arm64_self.k — self-hosted arm64 Mach-O hello-world emitter.
//
// Goal: produce a runnable arm64 Mach-O for macOS Tahoe with NO external
// assembler/linker. Calls _puts from libSystem via dyld stubs. Runs after
// `codesign -s - --force` (in-Krypton ad-hoc signing is the next slice).
//
// This is v0.1: hardcoded "Hi\n" greeting, fixed _puts import, no IR.
// Once it runs, we generalize: parameterize the message, then wire to IR.
//
// Output binary layout (file offsets):
//   0x0000  mach_header_64 (32 B)
//   0x0020  load commands (12 LCs, sizeofcmds = 880)
//   0x0390  zero pad to 0x0460
//   0x0460  __TEXT,__text    : 8 arm64 instructions for _main (32 B)
//   0x0480  __TEXT,__stubs   : 1 stub for _puts (12 B)
//   0x048c  __TEXT,__cstring : "Hi\0" (3 B)
//   0x048f  zero pad to 0x4000
//   0x4000  __DATA_CONST,__got : 1 chained-bind ptr (8 B)
//   0x4008  zero pad to 0x8000
//   0x8000  __LINKEDIT
//           0x8000 chained_fixups (96 B, hardcoded for import "_puts")
//           0x8060 symtab          (3 nlist_64, 48 B; computed)
//           0x8090 indirect_symtab (2 × uint32, 8 B)
//           0x8098 strtab          (40 B, hardcoded)
//           0x80c0 code signature placeholder (256 B, filled by external codesign)
//   end
//
// Usage: kcc compiler/macos_arm64/macho_arm64_self.k <output_path>
// Then:  codesign -s - --force <output_path>
// Then:  <output_path>   → prints "Hi"

// ── byte/hex helpers (same idiom as elf.k) ──────────────────────────────────

// g_hexLUT: 256 fixed-width "xHH" entries (3 chars each, 768 total), built once
// by buildHexLUT() at startup. Lets hexByte() do a single O(3) substring instead
// of two INDEX allocs + two concats — the per-instruction hex encoding was the
// dominant heap churn during a full self-compile (no allocator reclaim).
let g_hexLUT = ""

func hexByte(n) {
    let v = toInt(n)
    if v < 0 { v = v + 256 }
    if v > 255 { v = v % 256 }
    if len(g_hexLUT) >= 768 {
        emit substring(g_hexLUT, v * 3, v * 3 + 3)
    }
    let HEX = "0123456789ABCDEF"
    emit "x" + HEX[v / 16] + HEX[v % 16]
}

// Build the 256-entry hex lookup table using the cold (concat) path.
func buildHexLUT() {
    let sb = sbNew()
    let i = 0
    while i < 256 {
        sb = sbAppend(sb, hexByte(i))
        i += 1
    }
    emit sbToString(sb)
}

func hexWord(n) {
    let v = toInt(n)
    emit hexByte(v % 256) + hexByte((v / 256) % 256)
}

func hexDword(n) {
    let v = toInt(n)
    let b0 = v % 256
    if b0 < 0 { b0 = b0 + 256 }
    let q1 = v / 256
    if v % 256 != 0 && v < 0 { q1 = q1 - 1 }
    let b1 = q1 % 256
    if b1 < 0 { b1 = b1 + 256 }
    let q2 = q1 / 256
    if q1 % 256 != 0 && q1 < 0 { q2 = q2 - 1 }
    let b2 = q2 % 256
    if b2 < 0 { b2 = b2 + 256 }
    let q3 = q2 / 256
    if q2 % 256 != 0 && q2 < 0 { q3 = q3 - 1 }
    let b3 = q3 % 256
    if b3 < 0 { b3 = b3 + 256 }
    emit hexByte(b0) + hexByte(b1) + hexByte(b2) + hexByte(b3)
}

// hexQword: low 32 bits via hexDword(lo), then high 32 bits via hexDword(hi).
// All our 64-bit fields fit in either low-32 (offsets) or have a known high-32.
func hexQword2(lo, hi) { emit hexDword(lo) + hexDword(hi) }
func hexQword(n) { emit hexDword(n) + hexDword(0) }

func hexPad(n) {
    // Build n zero bytes using fixed-size blocks (avoids O(N²) byte-by-byte concat).
    let b1   = "x00"
    let b2   = b1   + b1
    let b4   = b2   + b2
    let b8   = b4   + b4
    let b16  = b8   + b8
    let b32  = b16  + b16
    let b64  = b32  + b32
    let b128 = b64  + b64
    let b256 = b128 + b128
    let out = ""
    let rem = n
    while rem >= 256 {
        out = out + b256
        rem = rem - 256
    }
    if rem >= 128 {
        out = out + b128
        rem = rem - 128
    }
    if rem >= 64 {
        out = out + b64
        rem = rem - 64
    }
    if rem >= 32 {
        out = out + b32
        rem = rem - 32
    }
    if rem >= 16 {
        out = out + b16
        rem = rem - 16
    }
    if rem >= 8 {
        out = out + b8
        rem = rem - 8
    }
    if rem >= 4 {
        out = out + b4
        rem = rem - 4
    }
    if rem >= 2 {
        out = out + b2
        rem = rem - 2
    }
    if rem >= 1 {
        out = out + b1
    }
    emit out
}

func hexStr(s) {
    let out = ""
    let i = 0
    while i < len(s) {
        out = out + hexByte(charCode(s[i]))
        i += 1
    }
    emit out
}

func hexBytesLen(s) { emit len(s) / 3 }

// ── Mach-O constants ────────────────────────────────────────────────────────

func MH_MAGIC_64() { emit (0xfeed * 0x10000 + 0xfacf) }
func CPU_TYPE_ARM64() { emit 0x0100000c }      // = 16777228
func MH_EXECUTE() { emit 2 }
func MH_NOUNDEFS() { emit 0x1 }
func MH_DYLDLINK() { emit 0x4 }
func MH_TWOLEVEL() { emit 0x80 }
func MH_PIE() { emit 0x200000 }

// LC_REQ_DYLD = 0x80000000; some commands OR it in
func LC_SEGMENT_64() { emit 0x19 }
func LC_SYMTAB() { emit 0x2 }
func LC_DYSYMTAB() { emit 0xb }
func LC_LOAD_DYLIB() { emit 0xc }
func LC_LOAD_DYLINKER() { emit 0xe }
func LC_BUILD_VERSION() { emit 0x32 }
func LC_MAIN() { emit (0x8000 * 0x10000 + 0x28) }
func LC_DYLD_CHAINED_FIXUPS() { emit (0x8000 * 0x10000 + 0x34) }
func LC_CODE_SIGNATURE() { emit 0x1d }

// VM protections
func VM_PROT_READ() { emit 1 }
func VM_PROT_WRITE() { emit 2 }
func VM_PROT_EXECUTE() { emit 4 }

// Section flags
func S_REGULAR() { emit 0x0 }
func S_CSTRING_LITERALS() { emit 0x2 }
func S_NON_LAZY_SYMBOL_POINTERS() { emit 0x6 }
func S_SYMBOL_STUBS() { emit 0x8 }
func S_ATTR_SOME_INSTRUCTIONS() { emit 0x00000400 }
func S_ATTR_PURE_INSTRUCTIONS() { emit (0x8000 * 0x10000 + 0x0) }
// __text:   PURE | SOME = 0x80000400 (type S_REGULAR)
// __stubs:  PURE | SOME | type S_SYMBOL_STUBS = 0x80000408
// __cstring: type S_CSTRING_LITERALS = 0x00000002
// __got:    type S_NON_LAZY_SYMBOL_POINTERS = 0x00000006

// ── Layout constants (file offsets and vaddrs) ──────────────────────────────
// Globals come first (lets), then funcs that read them. Krypton's compile.k
// emits one C declaration per let in source order, so funcs can't forward-ref.

let g_TEXT_SIZE       = 32          // bytes of __text (computed from IR)
let g_CSTRING_SIZE    = 3           // total bytes of __cstring (computed)
// Cache of function start line numbers within `parsed` — set by the driver
// after parse to avoid O(F²) walks in funcStartLine. One int per line.
let g_funcStartCache  = ""
let g_ENTRY_OFF       = 0x460       // file offset of `_main`'s first instruction
// Dynamic layout — recomputed by computeLayout() in the driver.
let g_TEXT_VMSIZE         = 0x4000
let g_DATA_CONST_FILE_OFF = 0x4000
let g_DATA_FILE_OFF       = 0x8000
let g_LINKEDIT_FILE_OFF   = 0xC000
let g_DATA_VADDR          = 0x8000
let g_LINKEDIT_VADDR      = 0x408000
let g_CODESIG_OFF         = 0xC0C0
let g_CODESIG_SIZE        = 244
let g_FILE_TOTAL_SIZE     = 0xC0C0 + 244

// objk FFI: foreign (dylib-imported) symbols used by the program.
// g_NFOREIGN==0 ⇒ pure syscall-only binary (byte-identical to pre-objk output).
let g_NFOREIGN  = 0
let g_FORSYMS   = ""    // newline-sep import symbols, with leading "_" (e.g. "_getpid")
let g_FORLIB    = ""    // newline-sep 1-based dylib ordinal, parallel to g_FORSYMS
let g_DYLIBS    = ""    // newline-sep dylib paths (ordinal = index+1)
// N-import layout (set by computeLayout when g_NFOREIGN>0; all 0 otherwise)
let g_TEXT_OFF      = 0x460   // file offset of __text (bumped to 0x800 when N>0 for LC headroom)
let g_STUBS_SZ      = 0
let g_GOT_SZ        = 0
let g_FIXUPS_SZ     = 56
let g_SYMTAB_OFF2   = 0
let g_SYMTAB_SZ     = 32
let g_INDIRECT_OFF  = 0
let g_INDIRECT_SZ   = 0
let g_STRTAB_OFF2   = 0
let g_STRTAB_SZ2    = 32

// symbols sub-blob length inside chained-fixups: leading NUL + each "_sym\0".
func foreignSymbolsBlobLen() {
    let n = 1  let i = 0
    while i < g_NFOREIGN { n = n + len(getLine(g_FORSYMS, i)) + 1  i += 1 }
    emit n
}
// strtab bytes: " \0__mh_execute_header\0_main\0" (28) + each "_sym\0".
func strtabUnpadded() {
    let n = 28  let i = 0
    while i < g_NFOREIGN { n = n + len(getLine(g_FORSYMS, i)) + 1  i += 1 }
    emit n
}

// Backend-side symbol→dylib table (step 2a; moves to the jxt `lib` directive later).
func _isMsgSend(name) {
    if len(name) >= 12 { if substring(name, 0, 12) == "objc_msgSend" { emit 1 } }
    emit 0
}
func foreignLibFor(name) {
    if name == "getpid"          { emit "/usr/lib/libSystem.B.dylib" }
    if _isMsgSend(name) == 1     { emit "/usr/lib/libobjc.A.dylib" }
    if name == "objc_getClass"   { emit "/usr/lib/libobjc.A.dylib" }
    if name == "objc_lookUpClass"{ emit "/usr/lib/libobjc.A.dylib" }
    if name == "class_getName"   { emit "/usr/lib/libobjc.A.dylib" }
    if name == "sel_registerName"{ emit "/usr/lib/libobjc.A.dylib" }
    if name == "objc_retain"     { emit "/usr/lib/libobjc.A.dylib" }
    if name == "objc_release"    { emit "/usr/lib/libobjc.A.dylib" }
    if name == "objc_setAssociatedObject" { emit "/usr/lib/libobjc.A.dylib" }
    if name == "objc_getAssociatedObject" { emit "/usr/lib/libobjc.A.dylib" }
    if name == "objc_allocateClassPair"   { emit "/usr/lib/libobjc.A.dylib" }
    if name == "objc_registerClassPair"   { emit "/usr/lib/libobjc.A.dylib" }
    if name == "class_addMethod"          { emit "/usr/lib/libobjc.A.dylib" }
    // libc/posix (libSystem) — explicit allowlist so non-foreign user funcs
    // (cls, msg, …) keep falling through to "" and are filtered out of imports.
    if name == "posix_openpt" { emit "/usr/lib/libSystem.B.dylib" }
    if name == "grantpt"      { emit "/usr/lib/libSystem.B.dylib" }
    if name == "unlockpt"     { emit "/usr/lib/libSystem.B.dylib" }
    if name == "ptsname"      { emit "/usr/lib/libSystem.B.dylib" }
    if name == "fork"         { emit "/usr/lib/libSystem.B.dylib" }
    if name == "setsid"       { emit "/usr/lib/libSystem.B.dylib" }
    if name == "dup2"         { emit "/usr/lib/libSystem.B.dylib" }
    if name == "execl"        { emit "/usr/lib/libSystem.B.dylib" }
    if name == "execvp"       { emit "/usr/lib/libSystem.B.dylib" }
    if name == "open"         { emit "/usr/lib/libSystem.B.dylib" }
    if name == "close"        { emit "/usr/lib/libSystem.B.dylib" }
    if name == "ioctl"        { emit "/usr/lib/libSystem.B.dylib" }
    if name == "_exit"        { emit "/usr/lib/libSystem.B.dylib" }
    if name == "kill"         { emit "/usr/lib/libSystem.B.dylib" }
    emit ""
}
// Krypton call name → the C import symbol. The objc_msgSend_N/fpret wrappers all
// collapse to the single libobjc symbol _objc_msgSend (arm64 has no separate fpret).
func foreignSymFor(name) {
    if _isMsgSend(name) == 1 { emit "_objc_msgSend" }
    emit "_" + name
}
func _forHas(sym) {
    let i = 0  let n = lineCount(g_FORSYMS)
    while i < n { if getLine(g_FORSYMS, i) == sym { emit 1 }  i += 1 }
    emit 0
}
// arm64 SCVTF Dd, Xn — signed 64-bit int -> double (objk NSRect float args).
func arm64_scvtf_d_x(dd, xn) { emit hexDword((0x9e62 * 0x10000 + 0x0) + xn * 32 + dd) }
// FDIV Dd, Dn, Dm (scalar double): 0x1E601800 | Dm<<16 | Dn<<5 | Dd
func arm64_fdiv_d(dd, dn, dm) { emit hexDword(0x1E601800 + dm * 0x10000 + dn * 32 + dd) }
// instruction count for a CALL_FUNC (must match the byte emitter). The NSRect
// window-init special form is 15 instrs (3 GP pops + 4×(pop+scvtf) + 2 GP pops + bl + push).
func cfCount(cname, argc) {
    if cname == "objc_msgSend_rect" { emit 15 }
    if cname == "objc_msgSend_frame" { emit 12 }   // (obj,sel,x,y,w,h): rect-only NSRect arg
    if cname == "objc_msgSend_d1" { emit 6 }        // (obj,sel,n): one CGFloat arg -> d0
    if cname == "objc_msgSend_rectp" { emit 13 }    // (obj,sel,x,y,w,h,p): NSRect d0..d3 + ptr x2
    if cname == "objc_msgSend_timer" { emit 13 }    // (self,sel,ms,target,actsel,info,rep): ms/1000->d0 + x2..x5
    if cname == "objc_msgSend_rgb" { emit 17 }      // (self,sel,r,g,b): r/g/b/255->d0..d2, 1.0->d3 (colorWithRed:green:blue:alpha:)
    emit argc + 2
}
// 0-based index of foreign symbol "_"+name in g_FORSYMS, or -1 if not foreign.
func foreignIdx(name) {
    let sym = foreignSymFor(name)  let i = 0
    while i < g_NFOREIGN { if getLine(g_FORSYMS, i) == sym { emit i }  i += 1 }
    emit 0 - 1
}
// find-or-add a dylib path; return its 1-based ordinal.
func _dylibOrd(lib) {
    let i = 0  let n = lineCount(g_DYLIBS)
    while i < n { if getLine(g_DYLIBS, i) == lib { emit i + 1 }  i += 1 }
    if len(g_DYLIBS) > 0 { g_DYLIBS = g_DYLIBS + "\n" }
    g_DYLIBS = g_DYLIBS + lib
    emit lineCount(g_DYLIBS)
}
// Scan parsed IR for CALLs to known foreign symbols; build g_FORSYMS/g_FORLIB/g_DYLIBS.
func detectForeign(parsed) {
    g_NFOREIGN = 0  g_FORSYMS = ""  g_FORLIB = ""  g_DYLIBS = ""
    let nL = lineCount(parsed)  let i = 0
    while i < nL {
        let ln = getLine(parsed, i)
        if len(ln) > 10 && substring(ln, 0, 10) == "CALL_FUNC " {
            let rest = substring(ln, 10, len(ln))
            let sp = 0
            while sp < len(rest) && rest[sp] != " " { sp += 1 }
            let nm = substring(rest, 0, sp)
            let lib = foreignLibFor(nm)
            if len(lib) > 0 {
                let sym = foreignSymFor(nm)
                if _forHas(sym) == 0 {
                    let ord = _dylibOrd(lib)
                    if len(g_FORSYMS) > 0 { g_FORSYMS = g_FORSYMS + "\n"  g_FORLIB = g_FORLIB + "\n" }
                    g_FORSYMS = g_FORSYMS + sym
                    g_FORLIB = g_FORLIB + ("" + ord)
                    g_NFOREIGN = g_NFOREIGN + 1
                }
            }
        }
        i += 1
    }
    // objc classes (NSString, NSWindow, ...) live in Foundation/AppKit, not libobjc.
    // Force-load them (no imported symbol) so objc_getClass finds them at runtime.
    let usesObjc = 0  let d = 0
    while d < lineCount(g_DYLIBS) { if getLine(g_DYLIBS, d) == "/usr/lib/libobjc.A.dylib" { usesObjc = 1 }  d += 1 }
    if usesObjc == 1 {
        _dylibOrd("/System/Library/Frameworks/Foundation.framework/Foundation")
        _dylibOrd("/System/Library/Frameworks/AppKit.framework/AppKit")
    }
    emit 0
}

func TEXT_VADDR()         { emit 0 }
func DATA_CONST_VADDR()   { emit 0 + g_TEXT_VMSIZE }
func LINKEDIT_VADDR()     { emit g_LINKEDIT_VADDR }
func PAGEZERO_VMSIZE()    { emit 0 }
func SEG_PAGE_SIZE()      { emit 0x4000 }       // 16 KB

func TEXT_FILE_OFF()      { emit 0 }
func DATA_CONST_FILE_OFF() { emit g_DATA_CONST_FILE_OFF }
func DATA_FILE_OFF()      { emit g_DATA_FILE_OFF }
func LINKEDIT_FILE_OFF()  { emit g_LINKEDIT_FILE_OFF }
func DATA_VADDR()         { emit g_DATA_VADDR }
func DATA_VMSIZE()        { emit 0x70000000 }  // 1.75 GB virtual heap (clear of dyld shared cache; < 2^32)
func DATA_FILESIZE()      { emit 0x4000 }    // 16 KB file backing (1 page; rest zero-fill)

// Computes layout from g_TEXT_SIZE / g_CSTRING_SIZE. LINKEDIT meta = 192 B.
// __TEXT vmsize = 16 KB-aligned (0x460 + text + stubs(12) + cstring).
func computeLayout() {
    let pageSize = 0x4000
    let nF = g_NFOREIGN
    g_TEXT_OFF = 0x460
    if nF > 0 { g_TEXT_OFF = 0x800 }            // headroom for extra LCs (dylibs, __stubs/__got sects)
    g_STUBS_SZ = nF * 12
    g_GOT_SZ   = nF * 8
    // __TEXT file layout: __text, [__stubs], __cstring
    let textEnd = g_TEXT_OFF + g_TEXT_SIZE + g_STUBS_SZ + g_CSTRING_SIZE
    let textVmsize = ((textEnd + pageSize - 1) / pageSize) * pageSize
    if textVmsize < pageSize { textVmsize = pageSize }
    g_TEXT_VMSIZE = textVmsize
    g_DATA_CONST_FILE_OFF = textVmsize          // __got lives here when nF>0
    g_DATA_FILE_OFF = textVmsize + 0x4000
    g_LINKEDIT_FILE_OFF = textVmsize + 0x8000
    g_DATA_VADDR = 0 + textVmsize + 0x4000
    g_LINKEDIT_VADDR = g_DATA_VADDR + DATA_VMSIZE()
    // LINKEDIT meta: chained-fixups, symtab, [indirect symtab], strtab.
    if nF == 0 {
        g_FIXUPS_SZ = 56  g_SYMTAB_SZ = 32  g_INDIRECT_SZ = 0  g_STRTAB_SZ2 = 32
    } else {
        let fx = 32 + 24 + 24 + nF * 4 + foreignSymbolsBlobLen()   // hdr+image+seg+imports+symbols
        g_FIXUPS_SZ = ((fx + 7) / 8) * 8
        g_SYMTAB_SZ = (2 + nF) * 16
        g_INDIRECT_SZ = (2 * nF) * 4
        let st = strtabUnpadded()
        g_STRTAB_SZ2 = ((st + 7) / 8) * 8
    }
    g_SYMTAB_OFF2  = g_LINKEDIT_FILE_OFF + g_FIXUPS_SZ
    g_INDIRECT_OFF = g_SYMTAB_OFF2 + g_SYMTAB_SZ
    g_STRTAB_OFF2  = g_INDIRECT_OFF + g_INDIRECT_SZ
    let leEnd = g_STRTAB_OFF2 + g_STRTAB_SZ2
    if nF == 0 { g_CODESIG_OFF = g_LINKEDIT_FILE_OFF + 120 }   // exact pre-objk layout
    else { g_CODESIG_OFF = ((leEnd + 15) / 16) * 16 }
    let nCodeSlots = (g_CODESIG_OFF + pageSize - 1) / pageSize
    g_CODESIG_SIZE = 216 + nCodeSlots * 32
    g_FILE_TOTAL_SIZE = g_CODESIG_OFF + g_CODESIG_SIZE
    emit 0
}

func TEXT_OFF()           { emit g_TEXT_OFF }
func TEXT_SIZE()          { emit g_TEXT_SIZE }
func STUBS_OFF()          { emit g_TEXT_OFF + g_TEXT_SIZE }
func STUBS_SIZE()         { emit g_STUBS_SZ }
func GOT_OFF()            { emit g_DATA_CONST_FILE_OFF }
func GOT_SIZE()           { emit g_GOT_SZ }
func CSTRING_OFF()        { emit g_TEXT_OFF + g_TEXT_SIZE + g_STUBS_SZ }
func CSTRING_SIZE()       { emit g_CSTRING_SIZE }

func CHAINED_FIXUPS_OFF() { emit g_LINKEDIT_FILE_OFF }
func CHAINED_FIXUPS_SIZE() { emit g_FIXUPS_SZ }
func SYMTAB_OFF()         { emit g_SYMTAB_OFF2 }
func NSYMS()              { emit 2 + g_NFOREIGN }
func SYMTAB_SIZE()        { emit g_SYMTAB_SZ }
func INDIRECT_OFF()       { emit g_INDIRECT_OFF }
func NINDIRECT()          { emit 2 * g_NFOREIGN }
func STRTAB_OFF()         { emit g_STRTAB_OFF2 }
func STRTAB_SIZE()        { emit g_STRTAB_SZ2 }

func CODESIG_OFF()        { emit g_CODESIG_OFF }
func CODESIG_SIZE()       { emit g_CODESIG_SIZE }
func FILE_TOTAL_SIZE()    { emit g_FILE_TOTAL_SIZE }

func STRX_MH()    { emit 2 }   // "__mh_execute_header"
func STRX_MAIN()  { emit 22 }  // "_main"
// strtab byte offset of foreign symbol i (names follow _main\0 at offset 28).
func STRX_FOR(i)  {
    let off = 28  let k = 0
    while k < i { off = off + len(getLine(g_FORSYMS, k)) + 1  k += 1 }
    emit off
}

// ── byte/word readers over the "xHH"-encoded byte string ───────────────────
// hexByte() returns "xHH" (3 chars). To read a byte at byte-index i, we look
// at chars [i*3+1 .. i*3+2] and parse as hex.

func hexCharVal(c) {
    if c == "0" { emit 0 }
    if c == "1" { emit 1 }
    if c == "2" { emit 2 }
    if c == "3" { emit 3 }
    if c == "4" { emit 4 }
    if c == "5" { emit 5 }
    if c == "6" { emit 6 }
    if c == "7" { emit 7 }
    if c == "8" { emit 8 }
    if c == "9" { emit 9 }
    if c == "A" { emit 10 }
    if c == "B" { emit 11 }
    if c == "C" { emit 12 }
    if c == "D" { emit 13 }
    if c == "E" { emit 14 }
    if c == "F" { emit 15 }
    emit 0
}

func byteAtHex(hex, i) {
    let p = i * 3
    let hi = hexCharVal(hex[p + 1])
    let lo = hexCharVal(hex[p + 2])
    emit hi * 16 + lo
}

// 32-bit big-endian word at byte index i. Krypton ints are 32-bit signed but
// the bit pattern is what matters; bitAnd/bitShr/bitShl from compile.k cast
// to unsigned int internally so this works for high-bit-set values too.
func u32BeAtHex(hex, i) {
    let b0 = byteAtHex(hex, i)
    let b1 = byteAtHex(hex, i + 1)
    let b2 = byteAtHex(hex, i + 2)
    let b3 = byteAtHex(hex, i + 3)
    emit b0 * 0x1000000 + b1 * 0x10000 + b2 * 0x100 + b3
}

// Emit a 32-bit BE word as 4 hex bytes (for SHA-256 output and for big-endian
// fields in CodeDirectory / SuperBlob).
func hexDwordBe(n) {
    let b3 = bitAnd(bitShr(n, 24), 0xff)
    let b2 = bitAnd(bitShr(n, 16), 0xff)
    let b1 = bitAnd(bitShr(n, 8),  0xff)
    let b0 = bitAnd(n, 0xff)
    emit hexByte(b3) + hexByte(b2) + hexByte(b1) + hexByte(b0)
}

// ── unsigned 32-bit primitives (use language builtins; runtime casts to uint) ─
// rotr — bitwise rotate right by n in [1, 31]
func u32_rotr(v, n) { emit bitOr(bitShr(v, n), bitShl(v, 32 - n)) }
// shr — logical right shift (already unsigned via kr_bitshr)
func u32_shr(v, n) { emit bitShr(v, n) }
// add wrapping mod 2^32 — Krypton's signed add naturally wraps in 32 bits
func u32_add(a, b) { emit a + b }

// ── SHA-256 ────────────────────────────────────────────────────────────────
// Hashes byteCount bytes of `hex` starting at byte index `byteOff`.
// Returns the 32-byte digest as 96 hex chars (xHH × 32).

// Round constants K[0..63]
func sha256_K(i) {
    if i == 0  { emit 0x428a2f98 }
    if i == 1  { emit 0x71374491 }
    if i == 2  { emit (0xb5c0 * 0x10000 + 0xfbcf) }
    if i == 3  { emit (0xe9b5 * 0x10000 + 0xdba5) }
    if i == 4  { emit 0x3956c25b }
    if i == 5  { emit 0x59f111f1 }
    if i == 6  { emit (0x923f * 0x10000 + 0x82a4) }
    if i == 7  { emit (0xab1c * 0x10000 + 0x5ed5) }
    if i == 8  { emit (0xd807 * 0x10000 + 0xaa98) }
    if i == 9  { emit 0x12835b01 }
    if i == 10 { emit 0x243185be }
    if i == 11 { emit 0x550c7dc3 }
    if i == 12 { emit 0x72be5d74 }
    if i == 13 { emit (0x80de * 0x10000 + 0xb1fe) }
    if i == 14 { emit (0x9bdc * 0x10000 + 0x6a7) }
    if i == 15 { emit (0xc19b * 0x10000 + 0xf174) }
    if i == 16 { emit (0xe49b * 0x10000 + 0x69c1) }
    if i == 17 { emit (0xefbe * 0x10000 + 0x4786) }
    if i == 18 { emit 0x0fc19dc6 }
    if i == 19 { emit 0x240ca1cc }
    if i == 20 { emit 0x2de92c6f }
    if i == 21 { emit 0x4a7484aa }
    if i == 22 { emit 0x5cb0a9dc }
    if i == 23 { emit 0x76f988da }
    if i == 24 { emit (0x983e * 0x10000 + 0x5152) }
    if i == 25 { emit (0xa831 * 0x10000 + 0xc66d) }
    if i == 26 { emit (0xb003 * 0x10000 + 0x27c8) }
    if i == 27 { emit (0xbf59 * 0x10000 + 0x7fc7) }
    if i == 28 { emit (0xc6e0 * 0x10000 + 0xbf3) }
    if i == 29 { emit (0xd5a7 * 0x10000 + 0x9147) }
    if i == 30 { emit 0x06ca6351 }
    if i == 31 { emit 0x14292967 }
    if i == 32 { emit 0x27b70a85 }
    if i == 33 { emit 0x2e1b2138 }
    if i == 34 { emit 0x4d2c6dfc }
    if i == 35 { emit 0x53380d13 }
    if i == 36 { emit 0x650a7354 }
    if i == 37 { emit 0x766a0abb }
    if i == 38 { emit (0x81c2 * 0x10000 + 0xc92e) }
    if i == 39 { emit (0x9272 * 0x10000 + 0x2c85) }
    if i == 40 { emit (0xa2bf * 0x10000 + 0xe8a1) }
    if i == 41 { emit (0xa81a * 0x10000 + 0x664b) }
    if i == 42 { emit (0xc24b * 0x10000 + 0x8b70) }
    if i == 43 { emit (0xc76c * 0x10000 + 0x51a3) }
    if i == 44 { emit (0xd192 * 0x10000 + 0xe819) }
    if i == 45 { emit (0xd699 * 0x10000 + 0x624) }
    if i == 46 { emit (0xf40e * 0x10000 + 0x3585) }
    if i == 47 { emit 0x106aa070 }
    if i == 48 { emit 0x19a4c116 }
    if i == 49 { emit 0x1e376c08 }
    if i == 50 { emit 0x2748774c }
    if i == 51 { emit 0x34b0bcb5 }
    if i == 52 { emit 0x391c0cb3 }
    if i == 53 { emit 0x4ed8aa4a }
    if i == 54 { emit 0x5b9cca4f }
    if i == 55 { emit 0x682e6ff3 }
    if i == 56 { emit 0x748f82ee }
    if i == 57 { emit 0x78a5636f }
    if i == 58 { emit (0x84c8 * 0x10000 + 0x7814) }
    if i == 59 { emit (0x8cc7 * 0x10000 + 0x208) }
    if i == 60 { emit (0x90be * 0x10000 + 0xfffa) }
    if i == 61 { emit (0xa450 * 0x10000 + 0x6ceb) }
    if i == 62 { emit (0xbef9 * 0x10000 + 0xa3f7) }
    if i == 63 { emit (0xc671 * 0x10000 + 0x78f2) }
    emit 0
}

// Build a 16-line "h0\nh1\n...h7" string holding the running hash state.
// Initial values (FIPS 180-4 §5.3.3):
func sha256_initState() {
    let s = ""
    s = s + "1779033703\n"      // 0x6a09e667
    s = s + "3144134277\n"      // 0xbb67ae85 (unsigned; TOINT stops at '-')
    s = s + "1013904242\n"      // 0x3c6ef372
    s = s + "2773480762\n"      // 0xa54ff53a (unsigned)
    s = s + "1359893119\n"      // 0x510e527f
    s = s + "2600822924\n"      // 0x9b05688c (unsigned)
    s = s + "528734635\n"       // 0x1f83d9ab
    s = s + "1541459225"        // 0x5be0cd19
    emit s
}

// Process one 512-bit (64-byte) chunk. `chunkHex` is 192 hex chars (64 × 3).
// `state` is the 8-word state (newline-separated as decimals).
// Returns the updated state in the same format.
func sha256_processChunk(state, chunkHex) {
    // Load 16 words from chunk (BE) and extend to 64 words.
    // We store W[i] in local vars W0..W63 conceptually, but Krypton has no
    // arrays of integers — use a newline-separated string of decimals.
    let W = sbNew()
    let i = 0
    while i < 16 {
        let w = u32BeAtHex(chunkHex, i * 4)
        if i > 0 { W = sbAppend(W, "\n") }
        W = sbAppend(W, "" + w)
        i += 1
    }
    while i < 64 {
        let Ws = sbToString(W)
        let w15 = toInt(getLine(Ws, i - 15))
        let w2  = toInt(getLine(Ws, i - 2))
        let w16 = toInt(getLine(Ws, i - 16))
        let w7  = toInt(getLine(Ws, i - 7))
        // sigma0(x) = ROTR(x,7) XOR ROTR(x,18) XOR SHR(x,3)
        let s0 = bitXor(bitXor(u32_rotr(w15, 7), u32_rotr(w15, 18)), bitShr(w15, 3))
        // sigma1(x) = ROTR(x,17) XOR ROTR(x,19) XOR SHR(x,10)
        let s1 = bitXor(bitXor(u32_rotr(w2, 17), u32_rotr(w2, 19)), bitShr(w2, 10))
        let wi = w16 + s0 + w7 + s1
        W = sbAppend(W, "\n" + ("" + wi))
        i += 1
    }
    // Init working vars
    let a = toInt(getLine(state, 0))
    let b = toInt(getLine(state, 1))
    let c = toInt(getLine(state, 2))
    let d = toInt(getLine(state, 3))
    let e = toInt(getLine(state, 4))
    let f = toInt(getLine(state, 5))
    let g = toInt(getLine(state, 6))
    let h = toInt(getLine(state, 7))
    // 64 rounds
    let r = 0
    while r < 64 {
        let S1 = bitXor(bitXor(u32_rotr(e, 6), u32_rotr(e, 11)), u32_rotr(e, 25))
        let ch = bitXor(bitAnd(e, f), bitAnd(bitNot(e), g))
        let wr = toInt(getLine(sbToString(W), r))
        let T1 = h + S1 + ch + sha256_K(r) + wr
        let S0 = bitXor(bitXor(u32_rotr(a, 2), u32_rotr(a, 13)), u32_rotr(a, 22))
        let mj = bitXor(bitXor(bitAnd(a, b), bitAnd(a, c)), bitAnd(b, c))
        let T2 = S0 + mj
        h = g
        g = f
        f = e
        e = d + T1
        d = c
        c = b
        b = a
        a = T1 + T2
        r += 1
    }
    // Update state
    let h0 = toInt(getLine(state, 0)) + a
    let h1 = toInt(getLine(state, 1)) + b
    let h2 = toInt(getLine(state, 2)) + c
    let h3 = toInt(getLine(state, 3)) + d
    let h4 = toInt(getLine(state, 4)) + e
    let h5 = toInt(getLine(state, 5)) + f
    let h6 = toInt(getLine(state, 6)) + g
    let h7 = toInt(getLine(state, 7)) + h
    emit ("" + h0) + "\n" + ("" + h1) + "\n" + ("" + h2) + "\n" + ("" + h3) + "\n" + ("" + h4) + "\n" + ("" + h5) + "\n" + ("" + h6) + "\n" + ("" + h7)
}

// Hash byteCount bytes of `data` (a hex-encoded byte string) starting at byteOff.
// Returns 32-byte SHA-256 digest as 96 hex chars.
func sha256_hex(data, byteOff, byteCount) {
    // FIPS 180-4 §5.1.1 padding: data || 0x80 || zeros || 64-bit-BE-bitlen.
    // Compute padded length WITHOUT building the full padded message string
    // (avoids O(N²) heap allocations from byte-by-byte concatenation).
    let padLen = byteCount + 1
    while (padLen % 64) != 56 {
        padLen += 1
    }
    let totalBytes = padLen + 8
    let bits = byteCount * 8
    let state = sha256_initState()
    let off = 0
    while off < totalBytes {
        // Build one 64-byte chunk directly, computing each padded byte on-the-fly.
        // Use a StringBuilder: this runs ~36K times during a self-compile sign,
        // and the old `chunkHex = chunkHex + ...` concat was O(n^2) garbage.
        let chunkSb = sbNew()
        let cb = 0
        while cb < 64 {
            let pos = off + cb
            let b = 0
            if pos < byteCount {
                b = byteAtHex(data, byteOff + pos)
            } else if pos == byteCount {
                b = 0x80
            } else if pos < (totalBytes - 8) {
                b = 0
            } else {
                // 8-byte big-endian bit-count field: 4 zero bytes then hexDwordBe(bits).
                // bi = byte index within the 8-byte field (0=MSB).
                let bi = pos - (totalBytes - 8)
                if bi == 5 { b = (bits / 65536) % 256 }
                else if bi == 6 { b = (bits / 256) % 256 }
                else if bi == 7 { b = bits % 256 }
            }
            chunkSb = sbAppend(chunkSb, hexByte(b))
            cb += 1
        }
        state = sha256_processChunk(state, sbToString(chunkSb))
        off += 64
    }
    let out = ""
    let si = 0
    while si < 8 {
        out = out + hexDwordBe(toInt(getLine(state, si)))
        si += 1
    }
    emit out
}

// ── arm64 instruction encodings (32-bit little-endian) ──────────────────────
// Each emit returns 4 hex bytes via hexDword.

// stp x29, x30, [sp, #-16]!   →  0xa9bf7bfd
func arm64_stp_fp_lr_pre16()    { emit hexDword((0xa9bf * 0x10000 + 0x7bfd)) }
// mov x29, sp                  →  0x910003fd
func arm64_mov_fp_sp()          { emit hexDword((0x9100 * 0x10000 + 0x3fd)) }
// adrp Rd, #imm21 (page rel)
func arm64_adrp(rd, imm21) {
    let i = imm21
    if i < 0 { i = i + 0x200000 }       // 2's complement into 21 bits
    let immlo = i % 4
    let immhi = i / 4
    let insn = (0x9000 * 0x10000 + 0x0)
    insn = insn + (immlo * 0x20000000)   // bits[30:29]
    insn = insn + (immhi * 0x20)         // bits[23:5]
    insn = insn + rd                     // bits[4:0]
    emit hexDword(insn)
}
// add Rd, Rn, #imm12 (64-bit, no shift)
func arm64_add_imm(rd, rn, imm12) {
    let insn = (0x9100 * 0x10000 + 0x0)
    insn = insn + (imm12 * 0x400)        // bits[21:10]
    insn = insn + (rn * 0x20)            // bits[9:5]
    insn = insn + rd
    emit hexDword(insn)
}
// bl rel26 (rel26 = byte_delta / 4, in instruction units)
func arm64_bl(rel26) {
    let mask = 0x03ffffff
    let r = rel26
    if r < 0 { r = r + 0x04000000 }      // 2's complement into 26 bits
    r = r % 0x04000000
    emit hexDword((0x9400 * 0x10000 + 0x0) + r)
}
// movz w0, #0   →  0x52800000
func arm64_movz_w0_zero()       { emit hexDword(0x52800000) }
// ldp x29, x30, [sp], #16   →  0xa8c17bfd
func arm64_ldp_fp_lr_post16()   { emit hexDword((0xa8c1 * 0x10000 + 0x7bfd)) }
// ret                       →  0xd65f03c0
func arm64_ret()                { emit hexDword((0xd65f * 0x10000 + 0x3c0)) }

// ldr Xt, [Xn, #imm12_scaled]  (64-bit, unsigned offset)
func arm64_ldr_imm(rt, rn, imm12_scaled) {
    let insn = (0xf940 * 0x10000 + 0x0)
    insn = insn + (imm12_scaled * 0x400) // bits[21:10]
    insn = insn + (rn * 0x20)
    insn = insn + rt
    emit hexDword(insn)
}
// br Xn  →  0xd61f0000 | (Xn << 5)
func arm64_br(rn) { emit hexDword((0xd61f * 0x10000 + 0x0) + rn * 0x20) }

// str Xt, [sp, #-16]!   (push Xt to eval stack)  → 0xf81f0fe0 | Rt
func arm64_push(rt) { emit hexDword((0xf81f * 0x10000 + 0xfe0) + rt) }
// ldr Xt, [sp], #16     (pop top of eval stack into Xt) → 0xf84107e0 | Rt
func arm64_pop(rt)  { emit hexDword((0xf841 * 0x10000 + 0x7e0) + rt) }
// Convenience aliases for x0 (most common usage)
func arm64_push_x0() { emit arm64_push(0) }
func arm64_pop_x0()  { emit arm64_pop(0) }

// sub sp, sp, #imm12 (64-bit)  → 0xd10003ff | (imm12 << 10)
func arm64_sub_sp(imm12) {
    let insn = (0xd100 * 0x10000 + 0x3ff)
    insn = insn + (imm12 * 0x400)
    emit hexDword(insn)
}
// add sp, sp, #imm12 (64-bit)  → 0x910003ff | (imm12 << 10)
func arm64_add_sp(imm12) {
    let insn = (0x9100 * 0x10000 + 0x3ff)
    insn = insn + (imm12 * 0x400)
    emit hexDword(insn)
}

// stur Xt, [Xn, #imm9]  (signed 9-bit unscaled offset, 64-bit)
//   encoding: 0xf8000000 | (imm9 << 12) | (Rn << 5) | Rt
func arm64_stur(rt, rn, imm9) {
    let i = imm9
    if i < 0 { i = i + 512 }   // 9-bit two's complement
    i = i % 512
    let insn = (0xf800 * 0x10000 + 0x0)
    insn = insn + (i * 0x1000)
    insn = insn + (rn * 0x20)
    insn = insn + rt
    emit hexDword(insn)
}
// ldur Xt, [Xn, #imm9]  → 0xf8400000 | (imm9 << 12) | (Rn << 5) | Rt
func arm64_ldur(rt, rn, imm9) {
    let i = imm9
    if i < 0 { i = i + 512 }
    i = i % 512
    let insn = (0xf840 * 0x10000 + 0x0)
    insn = insn + (i * 0x1000)
    insn = insn + (rn * 0x20)
    insn = insn + rt
    emit hexDword(insn)
}

// movz Wd, #imm16  (32-bit, no shift)  → 0x52800000 | (imm16 << 5) | Rd
func arm64_movz_w_imm(rd, imm16) {
    let insn = 0x52800000
    insn = insn + (imm16 * 0x20)
    insn = insn + rd
    emit hexDword(insn)
}
// movz Xd, #imm16 (64-bit, no shift)  → 0xd2800000 | (imm16 << 5) | Rd
func arm64_movz_x_imm(rd, imm16) {
    let insn = (0xd280 * 0x10000 + 0x0)
    insn = insn + (imm16 * 0x20)
    insn = insn + rd
    emit hexDword(insn)
}
// movz Xd, #imm16, LSL #16  → 0xd2a00000 | (imm16 << 5) | Rd
func arm64_movz_x_imm_lsl16(rd, imm16) {
    emit hexDword((0xd2a0 * 0x10000 + 0x0) + (imm16 * 0x20) + rd)
}
// movn Xd, #imm16 (64-bit, no shift) — Rd = ~(imm16) sign-extended → 0x92800000 | (imm16 << 5) | Rd
func arm64_movn_x_imm(rd, imm16) {
    let insn = (0x9280 * 0x10000 + 0x0)
    insn = insn + (imm16 * 0x20)
    insn = insn + rd
    emit hexDword(insn)
}

// add Xd, Xn, Xm (64-bit, no shift) → 0x8b000000 | (Rm<<16) | (Rn<<5) | Rd
func arm64_add_xxx(rd, rn, rm) {
    let insn = (0x8b00 * 0x10000 + 0x0) + (rm * 0x10000) + (rn * 0x20) + rd
    emit hexDword(insn)
}
func arm64_add_www(rd, rn, rm) {
    let insn = 0x0b000000 + (rm * 0x10000) + (rn * 0x20) + rd
    emit hexDword(insn)
}
// sub Xd, Xn, Xm (64-bit, no shift) → 0xcb000000 | (Rm<<16) | (Rn<<5) | Rd
func arm64_sub_xxx(rd, rn, rm) {
    let insn = (0xcb00 * 0x10000 + 0x0) + (rm * 0x10000) + (rn * 0x20) + rd
    emit hexDword(insn)
}
// mul Xd, Xn, Xm (madd Xd, Xn, Xm, xzr) → 0x9b007c00 | (Rm<<16) | (Rn<<5) | Rd
func arm64_mul_xxx(rd, rn, rm) {
    let insn = (0x9b00 * 0x10000 + 0x7c00) + (rm * 0x10000) + (rn * 0x20) + rd
    emit hexDword(insn)
}
// sdiv Xd, Xn, Xm (signed divide) → 0x9ac00c00 | (Rm<<16) | (Rn<<5) | Rd
func arm64_sdiv_xxx(rd, rn, rm) {
    let insn = (0x9ac0 * 0x10000 + 0xc00) + (rm * 0x10000) + (rn * 0x20) + rd
    emit hexDword(insn)
}
// msub Xd, Xn, Xm, Xa  →  Rd = Ra - Rn*Rm   → 0x9b008000 | (Rm<<16) | (Ra<<10) | (Rn<<5) | Rd
func arm64_msub_xxxx(rd, rn, rm, ra) {
    let insn = (0x9b00 * 0x10000 + 0x8000) + (rm * 0x10000) + (ra * 0x400) + (rn * 0x20) + rd
    emit hexDword(insn)
}
// svc #imm16 → 0xd4000001 | (imm16 << 5)
func arm64_svc(imm16) {
    let insn = (0xd400 * 0x10000 + 0x1) + (imm16 * 0x20)
    emit hexDword(insn)
}

// cmp Xn, Xm  (alias for `subs xzr, Xn, Xm`) → 0xeb00001f | (Rm<<16) | (Rn<<5)
func arm64_cmp_xx(rn, rm) {
    emit hexDword((0xeb00 * 0x10000 + 0x1f) + (rm * 0x10000) + (rn * 0x20))
}
// cset Xd, <cond>  (alias for `csinc Xd, xzr, xzr, invert(cond)`)
//   csinc encoding: 0x9a800400 | (Rm<<16) | (cond<<12) | (Rn<<5) | Rd
//   For CSET we set Rm=Rn=xzr(31) and use invert(cond) — flipping bit 0 of cond inverts.
// AArch64 cond codes used here: EQ=0, NE=1, GE=0xA, LT=0xB, GT=0xC, LE=0xD.
func arm64_cset(rd, cond) {
    let inv = cond
    if (cond % 2) == 0 { inv = cond + 1 } else { inv = cond - 1 }
    emit hexDword((0x9a80 * 0x10000 + 0x400) + (31 * 0x10000) + (inv * 0x1000) + (31 * 0x20) + rd)
}
// b <imm26>  (unconditional branch, signed 26-bit in instruction units)
//   encoding: 0x14000000 | (imm26 & 0x3ffffff)
func arm64_b(rel) {
    let r = rel
    if r < 0 { r = r + 0x4000000 }
    r = r % 0x4000000
    emit hexDword(0x14000000 + r)
}
// cbz Xt, <imm19>  (compare and branch on zero, signed 19-bit)
//   encoding: 0xb4000000 | ((imm19 & 0x7ffff) << 5) | Rt
func arm64_cbz(rt, rel) {
    let r = rel
    if r < 0 { r = r + 0x80000 }
    r = r % 0x80000
    emit hexDword((0xb400 * 0x10000 + 0x0) + (r * 0x20) + rt)
}
// cbnz Xt, <imm19>  → 0xb5000000 | ((imm19 & 0x7ffff) << 5) | Rt
func arm64_cbnz(rt, rel) {
    let r = rel
    if r < 0 { r = r + 0x80000 }
    r = r % 0x80000
    emit hexDword((0xb500 * 0x10000 + 0x0) + (r * 0x20) + rt)
}
// cmp Xn, #imm12  (alias for `subs xzr, Xn, #imm12`) → 0xf100001f | (imm12 << 10) | (Rn << 5)
func arm64_cmp_imm(rn, imm12) {
    emit hexDword((0xf100 * 0x10000 + 0x1f) + (imm12 * 0x400) + (rn * 0x20))
}
// mov Xd, Xm  (alias for `orr Xd, xzr, Xm`) → 0xaa0003e0 | (Rm << 16) | Rd
func arm64_mov_xx(rd, rm) {
    emit hexDword((0xaa00 * 0x10000 + 0x3e0) + (rm * 0x10000) + rd)
}
// ldrb Wt, [Xn], #imm9  (post-indexed byte load) → 0x38400400 | (imm9<<12) | (Rn<<5) | Rt
func arm64_ldrb_post(rt, rn, imm9) {
    let i = imm9
    if i < 0 { i = i + 512 }
    i = i % 512
    emit hexDword(0x38400400 + (i * 0x1000) + (rn * 0x20) + rt)
}
// ldrb Wt, [Xn]  (zero offset) → 0x39400000 | (Rn<<5) | Rt
func arm64_ldrb_zero(rt, rn) {
    emit hexDword(0x39400000 + (rn * 0x20) + rt)
}
// sub Xd, Xn, #imm12 (64-bit, no shift) → 0xd1000000 | (imm12<<10) | (Rn<<5) | Rd
func arm64_sub_imm(rd, rn, imm12) {
    emit hexDword((0xd100 * 0x10000 + 0x0) + (imm12 * 0x400) + (rn * 0x20) + rd)
}
// str Xt, [Xn, #imm12_scaled] (unsigned offset, 64-bit) → 0xf9000000 | ...
func arm64_str_imm(rt, rn, imm12_scaled) {
    emit hexDword((0xf900 * 0x10000 + 0x0) + (imm12_scaled * 0x400) + (rn * 0x20) + rt)
}
// strb Wt, [Xn, #imm12]  (unscaled byte store)
func arm64_strb_imm(rt, rn, imm12) {
    emit hexDword(0x39000000 + (imm12 * 0x400) + (rn * 0x20) + rt)
}
// ldrb Wt, [Xn, Xm, LSL #0]  (register-offset byte load, 32-bit)
func arm64_ldrb_reg(rt, rn, rm) {
    emit hexDword(0x38606800 + (rm * 0x10000) + (rn * 0x20) + rt)
}
// strb Wt, [Xn, Xm, LSL #0]  (register-offset byte store, 32-bit)
func arm64_strb_reg(rt, rn, rm) {
    emit hexDword(0x38206800 + (rm * 0x10000) + (rn * 0x20) + rt)
}
// ldr Xt, [Xn, Xm, LSL #3]  (register-offset 64-bit load with index*8)
func arm64_ldr_reg_lsl3(rt, rn, rm) {
    emit hexDword((0xf860 * 0x10000 + 0x7800) + (rm * 0x10000) + (rn * 0x20) + rt)
}
// str Xt, [Xn, Xm, LSL #3]  (register-offset 64-bit store with index*8)
// Encoding differs from LDR only in bit 22 (load=1 → store=0).
func arm64_str_reg_lsl3(rt, rn, rm) {
    emit hexDword((0xf820 * 0x10000 + 0x7800) + (rm * 0x10000) + (rn * 0x20) + rt)
}
// movz Xd, #imm16, LSL #48  (load constant into high 16 bits, zero rest)
// Encoding: 0xd2e00000 | (imm16 << 5) | Rd  (sf=1, opc=10 movz, hw=11 LSL #48)
// Used to construct the 1<<63 mark-bit mask for the GC.
func arm64_movz_x_imm_lsl48(rd, imm16) {
    emit hexDword((0xd2e0 * 0x10000 + 0x0) + (imm16 * 0x20) + rd)
}
// movz Xd, #imm16, LSL #32 — hw=10 → 0xd2c00000 base. Used for the 1<<32
// boundary between small ints and pointers in BUILTIN_KP's dispatch.
func arm64_movz_x_imm_lsl32(rd, imm16) {
    emit hexDword((0xd2c0 * 0x10000 + 0x0) + (imm16 * 0x20) + rd)
}
// movk Xd, #imm16, LSL #16 — preserves other bits (unlike movz). Used to
// load the high 16 bits of a 32-bit positive constant after a movz of the low.
// Encoding: 0xf2a00000 | (imm16 << 5) | Rd  (sf=1, opc=11 movk, hw=01 LSL #16)
func arm64_movk_x_imm_lsl16(rd, imm16) {
    emit hexDword((0xf2a0 * 0x10000 + 0x0) + (imm16 * 0x20) + rd)
}
// movk Xd, #imm16          — keep-insert bits [15:0], hw=00
// Encoding: 0xf2800000 | (imm16 << 5) | Rd
func arm64_movk_x_imm(rd, imm16) {
    emit hexDword((0xf280 * 0x10000 + 0x0) + (imm16 * 0x20) + rd)
}
// movk Xd, #imm16, LSL #32 — keep-insert bits [47:32], hw=10
// Encoding: 0xf2c00000 | (imm16 << 5) | Rd
func arm64_movk_x_imm_lsl32(rd, imm16) {
    emit hexDword((0xf2c0 * 0x10000 + 0x0) + (imm16 * 0x20) + rd)
}
// movk Xd, #imm16, LSL #48 — keep-insert bits [63:48], hw=11
// Encoding: 0xf2e00000 | (imm16 << 5) | Rd
func arm64_movk_x_imm_lsl48(rd, imm16) {
    emit hexDword((0xf2e0 * 0x10000 + 0x0) + (imm16 * 0x20) + rd)
}
// nop — does nothing. 0xd503201f.
func arm64_nop() { emit hexDword((0xd503 * 0x10000 + 0x201f)) }
// orr Xd, Xn, Xm  (bitwise OR, no shift) → 0xaa000000 | (Rm<<16) | (Rn<<5) | Rd
func arm64_orr_xxx(rd, rn, rm) {
    emit hexDword((0xaa00 * 0x10000 + 0x0) + (rm * 0x10000) + (rn * 0x20) + rd)
}
// eor Xd, Xn, Xm  (bitwise XOR, no shift) → 0xca000000 | (Rm<<16) | (Rn<<5) | Rd
func arm64_eor_xxx(rd, rn, rm) {
    emit hexDword((0xca00 * 0x10000 + 0x0) + (rm * 0x10000) + (rn * 0x20) + rd)
}
// and Xd, Xn, Xm  (64-bit bitwise AND) → 0x8a000000 | (Rm<<16) | (Rn<<5) | Rd
func arm64_and_xxx(rd, rn, rm) {
    emit hexDword((0x8a00 * 0x10000 + 0x0) + (rm * 0x10000) + (rn * 0x20) + rd)
}
// and Wd, Wn, Wm  (32-bit bitwise AND, zero-extends to Xd) → 0x0a000000 | ...
func arm64_and_www(rd, rn, rm) {
    emit hexDword(0x0a000000 + (rm * 0x10000) + (rn * 0x20) + rd)
}
// orr Wd, Wn, Wm  (32-bit bitwise OR, zero-extends to Xd) → 0x2a000000 | ...
func arm64_orr_www(rd, rn, rm) {
    emit hexDword(0x2a000000 + (rm * 0x10000) + (rn * 0x20) + rd)
}
// eor Wd, Wn, Wm  (32-bit bitwise XOR, zero-extends to Xd) → 0x4a000000 | ...
func arm64_eor_www(rd, rn, rm) {
    emit hexDword(0x4a000000 + (rm * 0x10000) + (rn * 0x20) + rd)
}
// lsl Wd, Wn, Wm  (32-bit variable shift left; LSLV W alias) → 0x1AC02000
func arm64_lsl_w(rd, rn, rm) {
    emit hexDword(0x1ac02000 + (rm * 0x10000) + (rn * 0x20) + rd)
}
// lsr Wd, Wn, Wm  (32-bit variable shift right; LSRV W alias) → 0x1AC02400
func arm64_lsr_w(rd, rn, rm) {
    emit hexDword(0x1ac02400 + (rm * 0x10000) + (rn * 0x20) + rd)
}
// lsl Xd, Xn, Xm  (64-bit variable shift left; LSLV alias) → 0x9AC02000
func arm64_lsl_var(rd, rn, rm) {
    emit hexDword((0x9ac0 * 0x10000 + 0x2000) + (rm * 0x10000) + (rn * 0x20) + rd)
}
// lsr Xd, Xn, Xm  (64-bit variable shift right; LSRV alias) → 0x9AC02400
func arm64_lsr_var(rd, rn, rm) {
    emit hexDword((0x9ac0 * 0x10000 + 0x2400) + (rm * 0x10000) + (rn * 0x20) + rd)
}
// mvn Xd, Xm  (64-bit bitwise NOT; ORN Xd, XZR, Xm) → 0xAA200000 | (Rm<<16) | (31<<5) | Rd
func arm64_mvn_x(rd, rm) {
    emit hexDword((0xaa20 * 0x10000 + 0x0) + (rm * 0x10000) + 0x3e0 + rd)
}
// mvn Wd, Wm  (32-bit bitwise NOT, zero-extends to Xd; ORN Wd, WZR, Wm) → 0x2A200000 | ...
func arm64_mvn_w(rd, rm) {
    emit hexDword(0x2a200000 + (rm * 0x10000) + 0x3e0 + rd)
}
// lsr Xd, Xn, #32  (logical right shift by 32; alias for ubfm)
//   ubfm 64-bit: 0xd3400000 | (immr<<16) | (imms<<10) | (Rn<<5) | Rd
//   For LSR #N: immr=N, imms=63. For N=32: 0xd3400000 + (32<<16) + (63<<10) = 0xd360FC00
func arm64_lsr_imm32(rd, rn) {
    emit hexDword((0xd360 * 0x10000 + 0xfc00) + (rn * 0x20) + rd)
}
// neg Xd, Xn  (alias for sub Xd, xzr, Xn)
func arm64_neg(rd, rn) {
    emit hexDword((0xcb00 * 0x10000 + 0x3e0) + (rn * 0x10000) + rd)
}
// stp Xt1, Xt2, [sp, #-16]!  (push pair, pre-indexed, 16-byte block)
//   encoding: 0xa9bf0000 | (Rt2<<10) | (Rn=31<<5) | Rt
//   We hardcode sp(31) as base, imm7=-1 (= 0x7f in 7-bit).
//   General STP pre-indexed 64-bit: 0xa9800000 | (imm7 << 15) | (Rt2<<10) | (Rn<<5) | Rt
//   For pre-indexed -16 (= imm7 -2 since scale 8): imm7 = -2 = 0x7e
//   Actually wait: stp x29,x30,[sp,#-16]! is 0xa9bf7bfd which means imm7=0x7e? Let me verify:
//   0xa9bf7bfd = 1010_1001_1011_1111_0111_1011_1111_1101
//   bits[30:23] = 10101001 (stp pre-indexed)
//   bit[22] = 1 (load not store? wait no — stp store)
//   Hmm let me recheck. STP (signed offset, pre-indexed):
//   bits[31:23]: 1010_1001_1 (store/load encoded by bit?)
//   For this op we already have arm64_stp_fp_lr_pre16; just generalizing.
//   Actually let me just expose a general stp_pre helper for arbitrary pair.
func arm64_stp_pre16(rt1, rt2) {
    // stp Xt1, Xt2, [sp, #-16]! ; imm7 = -2 (encoded as 0x7e in 7 bits)
    emit hexDword((0xa9bf * 0x10000 + 0x0) + ((rt2 % 32) * 0x400) + (31 * 0x20) + (rt1 % 32))
}
// ldp Xt1, Xt2, [sp], #16  (post-indexed pop pair)
func arm64_ldp_post16(rt1, rt2) {
    emit hexDword((0xa8c1 * 0x10000 + 0x0) + ((rt2 % 32) * 0x400) + (31 * 0x20) + (rt1 % 32))
}
// stp Xt1, Xt2, [Xn, #imm7_scaled]  (signed offset, scale 8)
func arm64_stp_off(rt1, rt2, rn, imm7_scaled) {
    let i = imm7_scaled
    if i < 0 { i = i + 128 }
    i = i % 128
    emit hexDword((0xa900 * 0x10000 + 0x0) + (i * 0x8000) + ((rt2 % 32) * 0x400) + ((rn % 32) * 0x20) + (rt1 % 32))
}
// ldp Xt1, Xt2, [Xn, #imm7_scaled]
func arm64_ldp_off(rt1, rt2, rn, imm7_scaled) {
    let i = imm7_scaled
    if i < 0 { i = i + 128 }
    i = i % 128
    emit hexDword((0xa940 * 0x10000 + 0x0) + (i * 0x8000) + ((rt2 % 32) * 0x400) + ((rn % 32) * 0x20) + (rt1 % 32))
}
// udiv Xd, Xn, Xm
func arm64_udiv_xxx(rd, rn, rm) {
    emit hexDword((0x9ac0 * 0x10000 + 0x800) + (rm * 0x10000) + (rn * 0x20) + rd)
}
// b.cond #imm19  (conditional branch, signed 19-bit, 4-byte units)
//   encoding: 0x54000000 | ((imm19 & 0x7ffff) << 5) | cond
func arm64_b_cond(cond, rel) {
    let r = rel
    if r < 0 { r = r + 0x80000 }
    r = r % 0x80000
    emit hexDword(0x54000000 + (r * 0x20) + cond)
}
// brk #imm16  (software breakpoint trap) → 0xd4200000 | (imm16 << 5)
func arm64_brk(imm16) {
    emit hexDword((0xd420 * 0x10000 + 0x0) + (imm16 * 0x20))
}
// add Xd, Xn, Xm (64-bit, no shift, register form) — alias for the 3-reg add.
// Already covered by arm64_add_xxx; just alias here.
//
// Variable-size bump allocator. Size in x4 (clobbered for rounding). Returns
// pointer in x0. Uses x1 (cell ptr), x2 (new bump). 7 instructions.
// Note: no 8-byte alignment of allocations — caller may waste a few bytes
// per call but bump pointer eventually drifts. Acceptable for our heap sizes.
// 21 instructions; size in x4 (preserved across the call). Uses x5 for limit
// (instead of x4 like emitAllocN) so the size register isn't clobbered.
// Adds 16-byte header per alloc; returns user_ptr = header_ptr + 16.
func emitAllocVar(instrIdx, textVaddr, textOff) {
    // Use page offsets relative to TEXT base to avoid 0 arithmetic on
    // native binary (where values >= threshold are treated as string pointers).
    let imm21 = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + instrIdx * 4) / 4096
    let s = ""
    s = s + arm64_adrp(1, imm21)                        // 0
    s = s + arm64_add_imm(1, 1, 0)                      // 1: bumpVaddr is page-aligned, pageoff=0
    s = s + arm64_ldr_imm(9, 1, 3)                      // 2: ldr x9, [x1, #24] (alloc_total)
    s = s + arm64_add_xxx(9, 9, 4)                      // 3: x9 += x4 (user size)
    s = s + arm64_str_imm(9, 1, 3)                      // 4: str x9, [x1, #24]
    s = s + arm64_ldr_imm(5, 1, 4)                      // 5: ldr x5, [x1, #32] (alloc_limit)
    s = s + arm64_cbz(5, 4)                             // 6: if limit==0 skip 3
    s = s + arm64_cmp_xx(9, 5)                          // 7: cmp x9, x5
    s = s + arm64_b_cond(0x09, 2)                       // 8: b.ls +2 (skip brk)
    s = s + arm64_brk(99)                               // 9: brk #99 (limit exceeded)
    s = s + arm64_ldr_imm(0, 1, 0)                      // 10
    s = s + arm64_cbnz(0, 2)                            // 11
    s = s + arm64_add_imm(0, 1, 96)                     // 12: first-time init (heap @ +96; +56/64/72 = getLine cache)
    s = s + arm64_add_xxx(2, 0, 4)                      // 13: x2 = x0 + size
    s = s + arm64_add_imm(2, 2, 16)                     // 14: x2 += 16 (header)
    s = s + arm64_str_imm(2, 1, 0)                      // 15: advance bump
    s = s + arm64_ldr_imm(11, 1, 6)                     // 16: x11 = gcAllocsHead
    s = s + arm64_str_imm(11, 0, 0)                     // 17: header.next = old head
    s = s + arm64_str_imm(4, 0, 1)                      // 18: header.size_flags = x4 (size)
    s = s + arm64_str_imm(0, 1, 6)                      // 19: gcAllocsHead = header
    s = s + arm64_add_imm(0, 0, 16)                     // 20: user_ptr past header
    emit s
}

// Bump allocator. Allocates `n` bytes (rounded up to 8-byte alignment) from the
// heap. Returns address in x0. Uses x1 (bump cell ptr), x2 (new bump value).
// 7 instructions; the caller must add 7 to its instrIdx. The adrp imm21 is
// computed from the caller-provided absolute instruction index.
//
// **Layout note** — the bump cell lives in the *zero-fill* portion of __DATA
// (past DATA_FILESIZE). macOS marks the file-backed portion of __DATA as
// effectively read-only on code-signed binaries (the strb to a file-backed
// page SIGSEGVs even though initprot=R+W). The zero-fill region (anonymous
// pages mapped by the kernel) IS writable. So:
//   bump cell @ DATA_VADDR + DATA_FILESIZE  (= 0x10000_C000)
//   heap     @ DATA_VADDR + DATA_FILESIZE + 8 .. DATA_VADDR + DATA_VMSIZE
// The cell starts at zero (zero-fill default). The cbnz dance handles the
// first-time case: if loaded ptr is 0, treat the cell address + 8 as the
// initial heap pointer.
// 21 instructions: alloc-tracking + limit-check + bump + 16-byte header +
// gcAllocsHead linked-list push.
// System-area layout in __DATA zero-fill (per emitAllocN/Var convention):
//   +0   bump_cell        current free pointer (points to next header location)
//   +8   argc save        (set by __main__ prologue, read by argCount())
//   +16  argv save        (set by __main__ prologue, read by arg())
//   +24  alloc_total      bytes allocated cumulative (user bytes only, not header)
//   +32  alloc_limit      soft cap (0 = no limit; brk #99 on overflow)
//   +40  gcShadowCount    shadow-stack live count (read/written by gcShadowPush/Pop/Count)
//   +48  gcAllocsHead     head of singly-linked alloc list (for mark-sweep)
//   +56  reserved
//   +64..  heap (each alloc: 16-byte header [next:8B][size_flags:8B] + user bytes)
//   +0x2000000.. shadow stack (entries at 8 B each, written by gcShadowPush)
// User-facing pointer returned in x0 = header_ptr + 16.
func emitAllocN(n, instrIdx, textVaddr, textOff) {
    let imm21 = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + instrIdx * 4) / 4096
    let nAligned = ((n + 7) / 8) * 8
    let nWithHdr = nAligned + 16
    let s = ""
    s = s + arm64_adrp(1, imm21)                        // 0: adrp x1, bump_cell@PAGE
    s = s + arm64_add_imm(1, 1, 0)                      // 1: bump_cell@PAGEOFF=0 (page-aligned)
    s = s + arm64_ldr_imm(9, 1, 3)                      // 2: ldr  x9, [x1, #24]   (alloc_total)
    s = s + arm64_add_imm(9, 9, nAligned)               // 3: x9 += nAligned (user bytes)
    s = s + arm64_str_imm(9, 1, 3)                      // 4: str  x9, [x1, #24]
    s = s + arm64_ldr_imm(10, 1, 4)                     // 5: ldr  x10, [x1, #32]  (alloc_limit)
    s = s + arm64_cbz(10, 4)                            // 6: if limit==0 skip cmp/b.ls/brk
    s = s + arm64_cmp_xx(9, 10)                         // 7: cmp x9, x10
    s = s + arm64_b_cond(0x09, 2)                       // 8: b.ls +2 (if total <= limit, skip brk)
    s = s + arm64_brk(99)                               // 9: brk #99 (limit exceeded)
    s = s + arm64_ldr_imm(0, 1, 0)                      // 10: ldr  x0, [x1]   ; current free
    s = s + arm64_cbnz(0, 2)                            // 11: if x0 != 0 skip first-time init
    s = s + arm64_add_imm(0, 1, 96)                     // 12: x0 = bump_cell + 96 (heap; +56/64/72 = getLine cache)
    s = s + arm64_add_imm(2, 0, nWithHdr)               // 13: x2 = x0 + (nAligned+16)  new bump
    s = s + arm64_str_imm(2, 1, 0)                      // 14: str x2, [x1]    ; advance bump
    s = s + arm64_ldr_imm(11, 1, 6)                     // 15: ldr x11, [x1, #48]  (old gcAllocsHead)
    s = s + arm64_str_imm(11, 0, 0)                     // 16: str x11, [x0]   ; header.next = old head
    s = s + arm64_movz_x_imm(12, nAligned)              // 17: x12 = nAligned (user size)
    s = s + arm64_str_imm(12, 0, 1)                     // 18: str x12, [x0, #8]  ; header.size_flags
    s = s + arm64_str_imm(0, 1, 6)                      // 19: str x0, [x1, #48]  ; gcAllocsHead = header
    s = s + arm64_add_imm(0, 0, 16)                     // 20: x0 += 16 ; user_ptr past header
    emit s
}

// Polymorphic string concat — emits 111 arm64 instructions assuming the two
// operands are already in x3 (a) and x6 (b). Either may be an int (raw, less
// than 0) or a pointer to a NUL-terminated string. Ints are itoa'd
// into a 64-byte stack scratch buffer. Result is alloc'd via emitAllocVar and
// pushed onto the eval stack. Shared by both CAT and ADD's concat path.
func emitPolyConcat(instrIdx, textVaddr, textOff) {
    let s = ""
    s = s + arm64_sub_imm(31, 31, 64)             // 0: reserve 64B scratch (2×24-byte bufs + pad)
    s = s + arm64_movz_x_imm_lsl32(14, 1)         // 1: 0 ptr/int boundary
    s = s + arm64_cmp_xx(3, 14)                   // 2
    s = s + arm64_b_cond(0xa, 27)                 // 3: b.ge A_AFTER (idx 30)
    // itoa a → buf [sp..sp+23] (26 instr)
    s = s + arm64_add_imm(4, 31, 23)              // 4: p = sp+23
    s = s + arm64_strb_imm(31, 4, 0)              // 5: *p = NUL
    s = s + arm64_movz_x_imm(5, 0)                // 6: neg = 0
    s = s + arm64_cmp_imm(3, 0)                   // 7
    s = s + arm64_b_cond(0xa, 3)                  // 8: b.ge A_POS (idx 11)
    s = s + arm64_movz_x_imm(5, 1)                // 9
    s = s + arm64_neg(3, 3)                       // 10
    // A_POS @ 11:
    s = s + arm64_cbnz(3, 5)                      // 11: → A_LOOP (idx 16)
    s = s + arm64_sub_imm(4, 4, 1)                // 12: zero path
    s = s + arm64_movz_w_imm(7, 0x30)             // 13
    s = s + arm64_strb_imm(7, 4, 0)               // 14
    s = s + arm64_b(10)                           // 15: → A_SIGN (idx 25)
    // A_LOOP @ 16:
    s = s + arm64_cbz(3, 9)                       // 16: → A_SIGN (idx 25)
    s = s + arm64_movz_x_imm(7, 10)               // 17
    s = s + arm64_udiv_xxx(8, 3, 7)               // 18
    s = s + arm64_msub_xxxx(9, 8, 7, 3)           // 19
    s = s + arm64_add_imm(9, 9, 0x30)             // 20
    s = s + arm64_sub_imm(4, 4, 1)                // 21
    s = s + arm64_strb_imm(9, 4, 0)               // 22
    s = s + arm64_mov_xx(3, 8)                    // 23
    s = s + arm64_b(0 - 8)                        // 24: → A_LOOP
    // A_SIGN @ 25:
    s = s + arm64_cbz(5, 4)                       // 25: → A_DONE (idx 29)
    s = s + arm64_sub_imm(4, 4, 1)                // 26
    s = s + arm64_movz_w_imm(7, 0x2D)             // 27: '-'
    s = s + arm64_strb_imm(7, 4, 0)               // 28
    // A_DONE @ 29:
    s = s + arm64_mov_xx(3, 4)                    // 29: x3 = stack-buf ptr
    // A_AFTER @ 30:
    s = s + arm64_cmp_xx(6, 14)                   // 30
    s = s + arm64_b_cond(0xa, 27)                 // 31: b.ge B_AFTER (idx 58)
    // itoa b → buf [sp+32..sp+55] (26 instr)
    s = s + arm64_add_imm(4, 31, 55)              // 32
    s = s + arm64_strb_imm(31, 4, 0)              // 33
    s = s + arm64_movz_x_imm(5, 0)                // 34
    s = s + arm64_cmp_imm(6, 0)                   // 35
    s = s + arm64_b_cond(0xa, 3)                  // 36: b.ge B_POS (idx 39)
    s = s + arm64_movz_x_imm(5, 1)                // 37
    s = s + arm64_neg(6, 6)                       // 38
    // B_POS @ 39:
    s = s + arm64_cbnz(6, 5)                      // 39: → B_LOOP (idx 44)
    s = s + arm64_sub_imm(4, 4, 1)                // 40
    s = s + arm64_movz_w_imm(7, 0x30)             // 41
    s = s + arm64_strb_imm(7, 4, 0)               // 42
    s = s + arm64_b(10)                           // 43: → B_SIGN (idx 53)
    // B_LOOP @ 44:
    s = s + arm64_cbz(6, 9)                       // 44: → B_SIGN (idx 53)
    s = s + arm64_movz_x_imm(7, 10)               // 45
    s = s + arm64_udiv_xxx(8, 6, 7)               // 46
    s = s + arm64_msub_xxxx(9, 8, 7, 6)           // 47
    s = s + arm64_add_imm(9, 9, 0x30)             // 48
    s = s + arm64_sub_imm(4, 4, 1)                // 49
    s = s + arm64_strb_imm(9, 4, 0)               // 50
    s = s + arm64_mov_xx(6, 8)                    // 51
    s = s + arm64_b(0 - 8)                        // 52: → B_LOOP
    // B_SIGN @ 53:
    s = s + arm64_cbz(5, 4)                       // 53: → B_DONE (idx 57)
    s = s + arm64_sub_imm(4, 4, 1)                // 54
    s = s + arm64_movz_w_imm(7, 0x2D)             // 55
    s = s + arm64_strb_imm(7, 4, 0)               // 56
    // B_DONE @ 57:
    s = s + arm64_mov_xx(6, 4)                    // 57: x6 = stack-buf ptr
    // B_AFTER @ 58: strlen a (5 instr)
    s = s + arm64_mov_xx(1, 3)                    // 58
    s = s + arm64_ldrb_post(13, 1, 1)             // 59
    s = s + arm64_cbnz(13, 0 - 1)                 // 60
    s = s + arm64_sub_xxx(7, 1, 3)                // 61
    s = s + arm64_sub_imm(7, 7, 1)                // 62: la
    // strlen b (5 instr)
    s = s + arm64_mov_xx(1, 6)                    // 63
    s = s + arm64_ldrb_post(13, 1, 1)             // 64
    s = s + arm64_cbnz(13, 0 - 1)                 // 65
    s = s + arm64_sub_xxx(8, 1, 6)                // 66
    s = s + arm64_sub_imm(8, 8, 1)                // 67: lb
    // alloc size = la + lb + 1
    s = s + arm64_add_xxx(4, 7, 8)                // 68
    s = s + arm64_add_imm(4, 4, 1)                // 69
    // emitAllocVar at absolute idx (instrIdx + 70)
    s = s + emitAllocVar(instrIdx + 70, textVaddr, textOff)
    // Copy + NUL + sp restore + push (relative 91..110)
    s = s + arm64_movz_x_imm(13, 0)               // 91: i = 0
    // LOOP_A @ rel 92:
    s = s + arm64_cmp_xx(13, 7)                   // 92
    s = s + arm64_b_cond(0xa, 5)                  // 93: b.ge → AFTER_A (rel 98)
    s = s + arm64_ldrb_reg(14, 3, 13)             // 94
    s = s + arm64_strb_reg(14, 0, 13)             // 95
    s = s + arm64_add_imm(13, 13, 1)              // 96
    s = s + arm64_b(0 - 5)                        // 97
    // AFTER_A @ 98:
    s = s + arm64_movz_x_imm(13, 0)               // 98
    s = s + arm64_add_xxx(15, 0, 7)               // 99: x15 = dest + la
    // LOOP_B @ 100:
    s = s + arm64_cmp_xx(13, 8)                   // 100
    s = s + arm64_b_cond(0xa, 5)                  // 101: → AFTER_B (rel 106)
    s = s + arm64_ldrb_reg(14, 6, 13)             // 102
    s = s + arm64_strb_reg(14, 15, 13)            // 103
    s = s + arm64_add_imm(13, 13, 1)              // 104
    s = s + arm64_b(0 - 5)                        // 105
    // AFTER_B @ 106:
    s = s + arm64_add_xxx(15, 0, 7)               // 106
    s = s + arm64_add_xxx(15, 15, 8)              // 107: dest+la+lb
    s = s + arm64_strb_imm(31, 15, 0)             // 108: NUL terminator
    s = s + arm64_add_imm(31, 31, 64)             // 109: restore sp
    s = s + arm64_push_x0()                       // 110
    emit s
}

// ── full IR parser (slice 3e: multi-function) ──────────────────────────────
// Supports: FUNC <name> <argc> / PARAM <name> / LOCAL <name> / PUSH "literal"
// or PUSH <int> / STORE <name> / LOAD <name> / arithmetic / comparisons /
// LABEL / JUMP / JUMPIFNOT / BUILTIN kp/exit / CALL <name> <argc> / RETURN /
// POP / END.
//
// Output format:
//   line 0:  nFunctions
//   line 1:  nStrings
//   lines 2..1+nStrings:  each unique global string
//   then for each function (in declaration order), one block:
//     header line:  <name>\t<nParams>\t<nLocals>\t<nOps>
//     nParams lines:  param names
//     nLocals lines:  non-param local names (params excluded)
//     nOps lines:     normalized ops, one per line
//
// LOAD/STORE are normalized to LOAD_SLOT <i> / STORE_SLOT <i> where
// slot 0..nParams-1 = params, slot nParams..nParams+nLocals-1 = locals.

// Helper: find or add a name to a newline-separated list. Returns 0-based idx
// (the result is the modified list with the new entry appended if not found,
// followed by "|" then the index, allowing the caller to extract both).
func internIntoList(list, count, name) {
    let i = 0
    while i < count {
        if getLine(list, i) == name {
            emit list + "|" + i
        }
        i += 1
    }
    let newList = list
    if count > 0 { newList = newList + "\n" }
    newList = newList + name
    emit newList + "|" + count
}

// Find name in newline-separated list of `count` entries. Returns idx or -1.
func findInList(list, count, name) {
    // Single linear pass: O(total length). The old getLine(list,i) per index
    // rescanned from the start each time → O(count^2) per call, which made
    // per-op LOAD/STORE resolution O(K * L^2) and blew up on big functions.
    let i = 0
    let start = 0
    let n = len(list)
    while i < count {
        let e = start
        while e < n && list[e] != "\n" { e += 1 }
        if substring(list, start, e) == name { emit i }
        i += 1
        start = e + 1
    }
    emit 0 - 1
}

// sb-backed intern: search current sb content for `name`; if missing, append.
// Returns the index. Avoids the O(N²) list-copy cost of internIntoList.
func internSb(sbHandle, count, name) {
    let snap = sbToString(sbHandle)
    let i = 0
    while i < count {
        if getLine(snap, i) == name { emit i }
        i += 1
    }
    if count > 0 { sbAppend(sbHandle, "\n") }
    sbAppend(sbHandle, name)
    emit count
}

// Append a function block (header + params + locals + ops) to a sb.
func appendFunc(sb, name, params, nParams, locals, nLocals, opsStr, nOps) {
    sb = sbAppend(sb, name + "\t" + nParams + "\t" + nLocals + "\t" + nOps + "\n")
    let pi = 0
    while pi < nParams {
        sb = sbAppend(sb, getLine(params, pi) + "\n")
        pi += 1
    }
    let li = 0
    while li < nLocals {
        sb = sbAppend(sb, getLine(locals, li) + "\n")
        li += 1
    }
    sb = sbAppend(sb, opsStr)
    if len(opsStr) > 0 {
        if opsStr[len(opsStr) - 1] != "\n" { sb = sbAppend(sb, "\n") }
    }
    emit sb
}

// Collect unique LOCAL variable names from __main__ — these are module globals
// shared across all functions. Returns a newline-separated list of names.
func collectModuleGlobals(ir) {
    let sb = sbNew()
    let n = 0
    let nl = lineCount(ir)
    let i = 0
    let inMain = "0"
    while i < nl {
        let line = trim(getLine(ir, i))
        if len(line) > 0 && line[0] != ";" {
            let j = 0
            while j < len(line) && line[j] != " " { j += 1 }
            let op = substring(line, 0, j)
            let rest = ""
            if j < len(line) { rest = trim(substring(line, j + 1, len(line))) }
            if op == "FUNC" {
                let sp = 0
                while sp < len(rest) && rest[sp] != " " { sp += 1 }
                let fname = substring(rest, 0, sp)
                if fname == "__main__" { inMain = "1" }
                else { inMain = "0" }
            } else if op == "LOCAL" && inMain == "1" {
                // Skip compiler-generated names (start with "__") — e.g. __sh_save.
                // Only user-declared module-level `let` variables become globals.
                if len(rest) < 2 || rest[0] != "_" || rest[1] != "_" {
                    let idx = internSb(sb, n, rest)
                    if idx == n { n += 1 }
                }
            }
        }
        i += 1
    }
    emit sbToString(sb)
}

func parseFullIR(ir) {
    // Collect module globals (all LOCALs declared in __main__). These are
    // shared across functions via x28-relative addressing instead of frame slots.
    let globalsStr = collectModuleGlobals(ir)
    let numGlobals = 0
    if len(globalsStr) > 0 { numGlobals = lineCount(globalsStr) }

    // sbStrings holds interned globals as a newline-separated string. Using sb
    // for O(name_length) append (vs O(total_strings_length) for string concat).
    let sbStrings = sbNew()
    let nStrings = 0
    let funcsSb = sbNew()
    let nFunctions = 0

    // Per-function state (resets at each FUNC line)
    let inFunc = "0"
    let curName = ""
    let sbParams = sbNew()
    let nParams = 0
    let sbLocals = sbNew()
    let nLocals = 0
    let curOps = sbNew()
    let nOps = 0

    let nl = lineCount(ir)
    let i = 0
    while i < nl {
        let line = trim(getLine(ir, i))
        if len(line) > 0 {
            if line[0] != ";" {
                let j = 0
                while j < len(line) && line[j] != " " { j += 1 }
                let op = substring(line, 0, j)
                let rest = ""
                if j < len(line) { rest = trim(substring(line, j + 1, len(line))) }

                if op == "FUNC" {
                    // Finalize previous function (if any)
                    if inFunc == "1" {
                        funcsSb = appendFunc(funcsSb, curName, sbToString(sbParams), nParams, sbToString(sbLocals), nLocals, sbToString(curOps), nOps)
                        nFunctions += 1
                    }
                    // Start new function: parse "FUNC <name> <argc>"
                    let sp = 0
                    while sp < len(rest) && rest[sp] != " " { sp += 1 }
                    curName = substring(rest, 0, sp)
                    nParams = 0
                    sbParams = sbNew()
                    nLocals = 0
                    sbLocals = sbNew()
                    curOps = sbNew()
                    nOps = 0
                    inFunc = "1"
                } else if op == "PARAM" {
                    if nParams > 0 { sbAppend(sbParams, "\n") }
                    sbAppend(sbParams, rest)
                    nParams += 1
                } else if op == "LOAD" {
                    let paramSnap = sbToString(sbParams)
                    let pIdx = findInList(paramSnap, nParams, rest)
                    if pIdx >= 0 {
                        curOps = sbAppend(curOps, "LOAD_SLOT " + pIdx + "\n")
                        nOps += 1
                    } else {
                        let localSnap = sbToString(sbLocals)
                        let lIdx = findInList(localSnap, nLocals, rest)
                        if lIdx >= 0 {
                            curOps = sbAppend(curOps, "LOAD_SLOT " + (nParams + lIdx) + "\n")
                            nOps += 1
                        } else {
                            let gIdx = findInList(globalsStr, numGlobals, rest)
                            if gIdx >= 0 {
                                curOps = sbAppend(curOps, "LOAD_GLOBAL " + gIdx + "\n")
                                nOps += 1
                            } else {
                                if nLocals > 0 { sbAppend(sbLocals, "\n") }
                                sbAppend(sbLocals, rest)
                                curOps = sbAppend(curOps, "LOAD_SLOT " + (nParams + nLocals) + "\n")
                                nLocals += 1
                                nOps += 1
                            }
                        }
                    }
                } else if op == "STORE" {
                    let paramSnap = sbToString(sbParams)
                    let pIdx = findInList(paramSnap, nParams, rest)
                    if pIdx >= 0 {
                        curOps = sbAppend(curOps, "STORE_SLOT " + pIdx + "\n")
                        nOps += 1
                    } else {
                        let localSnap = sbToString(sbLocals)
                        let lIdx = findInList(localSnap, nLocals, rest)
                        if lIdx >= 0 {
                            curOps = sbAppend(curOps, "STORE_SLOT " + (nParams + lIdx) + "\n")
                            nOps += 1
                        } else {
                            let gIdx = findInList(globalsStr, numGlobals, rest)
                            if gIdx >= 0 {
                                curOps = sbAppend(curOps, "STORE_GLOBAL " + gIdx + "\n")
                                nOps += 1
                            } else {
                                if nLocals > 0 { sbAppend(sbLocals, "\n") }
                                sbAppend(sbLocals, rest)
                                curOps = sbAppend(curOps, "STORE_SLOT " + (nParams + nLocals) + "\n")
                                nLocals += 1
                                nOps += 1
                            }
                        }
                    }
                } else if op == "CALL" {
                    let sp = 0
                    while sp < len(rest) && rest[sp] != " " { sp += 1 }
                    let cname = substring(rest, 0, sp)
                    let cargc = "0"
                    if sp < len(rest) { cargc = trim(substring(rest, sp + 1, len(rest))) }
                    if cname == "bitAnd"    { curOps = sbAppend(curOps, "BUILTIN_BITAND\n") }
                    else if cname == "bitOr"  { curOps = sbAppend(curOps, "BUILTIN_BITOR\n") }
                    else if cname == "bitXor" { curOps = sbAppend(curOps, "BUILTIN_BITXOR\n") }
                    else if cname == "bitShr" { curOps = sbAppend(curOps, "BUILTIN_BITSHR\n") }
                    else if cname == "bitShl" { curOps = sbAppend(curOps, "BUILTIN_BITSHL\n") }
                    else if cname == "bitNot" { curOps = sbAppend(curOps, "BUILTIN_BITNOT\n") }
                    else if cname == "writeBytes" { curOps = sbAppend(curOps, "BUILTIN_WRITEBYTES\n") }
                    else { curOps = sbAppend(curOps, "CALL_FUNC " + cname + " " + cargc + "\n") }
                    nOps += 1
                } else if op == "RETURN" {
                    curOps = sbAppend(curOps, "RETURN\n")
                    nOps += 1
                } else if op == "FUNCPTR" {
                    curOps = sbAppend(curOps, "FUNCPTR " + rest + "\n")   // objk: push a func's code addr (objc IMP)
                    nOps += 1
                } else if op == "PUSH" {
                    if len(rest) > 0 {
                        if rest[0] == "\"" {
                            // Decode the IR-text escape sequences. The IR uses
                            // single-backslash escapes (verified via od -c):
                            //   \n / \t / \r → newline / tab / CR
                            //   \\           → single backslash
                            //   \"           → literal quote
                            //   \0           → skipped (null escape)
                            // Any other \X falls through as a literal backslash.
                            let contentSb = sbNew()
                            let k = 1
                            while k < len(rest) && rest[k] != "\"" {
                                if rest[k] == "\\" && (k + 1) < len(rest) {
                                    let nxt = rest[k + 1]
                                    if nxt == "n"       { contentSb = sbAppend(contentSb, "\n"); k += 2 }
                                    else if nxt == "t"  { contentSb = sbAppend(contentSb, "\t"); k += 2 }
                                    else if nxt == "r"  { contentSb = sbAppend(contentSb, "\r"); k += 2 }
                                    else if nxt == "\\" { contentSb = sbAppend(contentSb, "\\"); k += 2 }
                                    else if nxt == "\"" { contentSb = sbAppend(contentSb, "\""); k += 2 }
                                    else if nxt == "0"  { k += 2 }
                                    else {
                                        contentSb = sbAppend(contentSb, "\\")
                                        k += 1
                                    }
                                } else {
                                    contentSb = sbAppend(contentSb, rest[k])
                                    k += 1
                                }
                            }
                            // Store strings as hex-encoded (xHH...) so resolved
                            // escape bytes (newlines, tabs) don't collide with
                            // the line-based parsed format.
                            let content = asciiToHex(sbToString(contentSb))
                            let idx = internSb(sbStrings, nStrings, content)
                            if idx == nStrings { nStrings += 1 }
                            curOps = sbAppend(curOps, "PUSH_STR " + idx + "\n")
                            nOps += 1
                        } else {
                            curOps = sbAppend(curOps, "PUSH_INT " + rest + "\n")
                            nOps += 1
                        }
                    }
                } else if op == "ADD" || op == "SUB" || op == "MUL" || op == "DIV" || op == "MOD" || op == "LT" || op == "GT" || op == "EQ" || op == "CAT" {
                    curOps = sbAppend(curOps, op + "\n")
                    nOps += 1
                } else if op == "LTE" {
                    curOps = sbAppend(curOps, "LE\n")
                    nOps += 1
                } else if op == "GTE" {
                    curOps = sbAppend(curOps, "GE\n")
                    nOps += 1
                } else if op == "NEQ" {
                    curOps = sbAppend(curOps, "NE\n")
                    nOps += 1
                } else if op == "LABEL" {
                    curOps = sbAppend(curOps, "LABEL " + rest + "\n")
                    nOps += 1
                } else if op == "JUMP" {
                    curOps = sbAppend(curOps, "JUMP " + rest + "\n")
                    nOps += 1
                } else if op == "JUMPIFNOT" {
                    curOps = sbAppend(curOps, "JUMPIFNOT " + rest + "\n")
                    nOps += 1
                } else if op == "JUMPIF" {
                    curOps = sbAppend(curOps, "JUMPIF " + rest + "\n")
                    nOps += 1
                } else if op == "BREAK" {
                    // Resolve to a JUMP to the next LABEL _wend_* in the remaining IR
                    // (innermost enclosing while loop's end label).
                    let target = ""
                    let scan = i + 1
                    while scan < nl {
                        let sl = trim(getLine(ir, scan))
                        if startsWith(sl, "LABEL _wend_") {
                            target = trim(substring(sl, 6, len(sl)))
                            scan = nl
                        }
                        scan += 1
                    }
                    curOps = sbAppend(curOps, "JUMP " + target + "\n")
                    nOps += 1
                } else if op == "NEG" {
                    curOps = sbAppend(curOps, "NEG\n")
                    nOps += 1
                } else if op == "NOT" {
                    curOps = sbAppend(curOps, "NOT\n")
                    nOps += 1
                } else if op == "INDEX" {
                    curOps = sbAppend(curOps, "INDEX\n")
                    nOps += 1
                } else if op == "LOCAL" {
                    // Module globals are __main__'s LOCALs — in __main__ they have
                    // no frame slot (accessed as globals). But in ANY OTHER function
                    // a LOCAL whose name matches a global is a SHADOWING local and
                    // MUST get a frame slot. Skipping it (the old behavior) made the
                    // local ALIAS the global → stores corrupted shared state (the
                    // self-host `tokens` bug: a `let tokens` in a helper clobbered
                    // the module-global tokens). Only __main__ skips the slot.
                    let gIdx = findInList(globalsStr, numGlobals, rest)
                    if gIdx < 0 || curName != "__main__" {
                        // Add to function-local frame slots (shadows any global).
                        let pIdx = findInList(sbToString(sbParams), nParams, rest)
                        if pIdx < 0 {
                            let lIdx = findInList(sbToString(sbLocals), nLocals, rest)
                            if lIdx < 0 {
                                if nLocals > 0 { sbAppend(sbLocals, "\n") }
                                sbAppend(sbLocals, rest)
                                nLocals += 1
                            }
                        }
                    }
                } else if op == "BUILTIN" {
                    let bj = 0
                    while bj < len(rest) && rest[bj] != " " { bj += 1 }
                    let bname = substring(rest, 0, bj)
                    if bname == "kp" {
                        curOps = sbAppend(curOps, "BUILTIN_KP\n")
                        nOps += 1
                    } else if bname == "exit" {
                        curOps = sbAppend(curOps, "BUILTIN_EXIT\n")
                        nOps += 1
                    } else if bname == "len" {
                        curOps = sbAppend(curOps, "BUILTIN_LEN\n")
                        nOps += 1
                    } else if bname == "charCode" {
                        curOps = sbAppend(curOps, "BUILTIN_CHARCODE\n")
                        nOps += 1
                    } else if bname == "substring" {
                        curOps = sbAppend(curOps, "BUILTIN_SUBSTRING\n")
                        nOps += 1
                    } else if bname == "startsWith" {
                        curOps = sbAppend(curOps, "BUILTIN_STARTSWITH\n")
                        nOps += 1
                    } else if bname == "isDigit" {
                        curOps = sbAppend(curOps, "BUILTIN_ISDIGIT\n")
                        nOps += 1
                    } else if bname == "toInt" {
                        curOps = sbAppend(curOps, "BUILTIN_TOINT\n")
                        nOps += 1
                    } else if bname == "indexOf" {
                        curOps = sbAppend(curOps, "BUILTIN_INDEXOF\n")
                        nOps += 1
                    } else if bname == "sbNew" {
                        curOps = sbAppend(curOps, "BUILTIN_SBNEW\n")
                        nOps += 1
                    } else if bname == "sbAppend" {
                        curOps = sbAppend(curOps, "BUILTIN_SBAPPEND\n")
                        nOps += 1
                    } else if bname == "sbToString" {
                        curOps = sbAppend(curOps, "BUILTIN_SBTOSTRING\n")
                        nOps += 1
                    } else if bname == "length" {
                        // length(list) — counts comma-separated elements (empty → 0).
                        curOps = sbAppend(curOps, "BUILTIN_LENGTH\n")
                        nOps += 1
                    } else if bname == "range" {
                        curOps = sbAppend(curOps, "BUILTIN_RANGE\n")
                        nOps += 1
                    } else if bname == "split" {
                        // split(list, idx) — i-th comma-separated element.
                        curOps = sbAppend(curOps, "BUILTIN_SPLIT\n")
                        nOps += 1
                    } else if bname == "count" {
                        // count(s) — like length but base case is 1 (even for empty string).
                        curOps = sbAppend(curOps, "BUILTIN_COUNT\n")
                        nOps += 1
                    } else if bname == "isTruthy" {
                        // isTruthy(v) — returns 1 if v is truthy, 0 otherwise.
                        curOps = sbAppend(curOps, "BUILTIN_ISTRUTHY\n")
                        nOps += 1
                    } else if bname == "lineCount" {
                        // lineCount(s) — count of \n-separated lines.
                        curOps = sbAppend(curOps, "BUILTIN_LINECOUNT\n")
                        nOps += 1
                    } else if bname == "getLine" {
                        // getLine(s, idx) — extract the idx-th \n-separated line.
                        curOps = sbAppend(curOps, "BUILTIN_GETLINE\n")
                        nOps += 1
                    } else if bname == "replace" {
                        // replace(s, old, new) — substitute every occurrence.
                        curOps = sbAppend(curOps, "BUILTIN_REPLACE\n")
                        nOps += 1
                    } else if bname == "contains" {
                        curOps = sbAppend(curOps, "BUILTIN_CONTAINS\n")
                        nOps += 1
                    } else if bname == "print" {
                        curOps = sbAppend(curOps, "BUILTIN_PRINT\n")
                        nOps += 1
                    } else if bname == "printErr" {
                        curOps = sbAppend(curOps, "BUILTIN_PRINTERR\n")
                        nOps += 1
                    } else if bname == "pow" {
                        curOps = sbAppend(curOps, "BUILTIN_POW\n")
                        nOps += 1
                    } else if bname == "endsWith" {
                        curOps = sbAppend(curOps, "BUILTIN_ENDSWITH\n")
                        nOps += 1
                    } else if bname == "arg" {
                        curOps = sbAppend(curOps, "BUILTIN_ARG\n")
                        nOps += 1
                    } else if bname == "argCount" {
                        curOps = sbAppend(curOps, "BUILTIN_ARGCOUNT\n")
                        nOps += 1
                    } else if bname == "readFile" {
                        curOps = sbAppend(curOps, "BUILTIN_READFILE\n")
                        nOps += 1
                    } else if bname == "writeFile" {
                        curOps = sbAppend(curOps, "BUILTIN_WRITEFILE\n")
                        nOps += 1
                    } else if bname == "trim" {
                        curOps = sbAppend(curOps, "BUILTIN_TRIM\n")
                        nOps += 1
                    } else if bname == "toLower" {
                        curOps = sbAppend(curOps, "BUILTIN_TOLOWER\n")
                        nOps += 1
                    } else if bname == "toUpper" {
                        curOps = sbAppend(curOps, "BUILTIN_TOUPPER\n")
                        nOps += 1
                    } else if bname == "environ" {
                        curOps = sbAppend(curOps, "BUILTIN_ENVIRON\n")
                        nOps += 1
                    } else if bname == "gcAllocated" {
                        curOps = sbAppend(curOps, "BUILTIN_GCALLOCATED\n")
                        nOps += 1
                    } else if bname == "gcLimit" {
                        curOps = sbAppend(curOps, "BUILTIN_GCLIMIT\n")
                        nOps += 1
                    } else if bname == "gcSetLimit" {
                        curOps = sbAppend(curOps, "BUILTIN_GCSETLIMIT\n")
                        nOps += 1
                    } else if bname == "gcReset" {
                        curOps = sbAppend(curOps, "BUILTIN_GCRESET\n")
                        nOps += 1
                    } else if bname == "gcCollect" {
                        curOps = sbAppend(curOps, "BUILTIN_GCCOLLECT\n")
                        nOps += 1
                    } else if bname == "gcShadowPush" {
                        curOps = sbAppend(curOps, "BUILTIN_GCSHADOWPUSH\n")
                        nOps += 1
                    } else if bname == "gcShadowPop" {
                        curOps = sbAppend(curOps, "BUILTIN_GCSHADOWPOP\n")
                        nOps += 1
                    } else if bname == "gcShadowCount" {
                        curOps = sbAppend(curOps, "BUILTIN_GCSHADOWCOUNT\n")
                        nOps += 1
                    } else if bname == "gcMark" {
                        curOps = sbAppend(curOps, "BUILTIN_GCMARK\n")
                        nOps += 1
                    } else if bname == "gcSweep" {
                        curOps = sbAppend(curOps, "BUILTIN_GCSWEEP\n")
                        nOps += 1
                    } else if bname == "gcFreelistCount" {
                        curOps = sbAppend(curOps, "BUILTIN_GCFREELISTCOUNT\n")
                        nOps += 1
                    } else if bname == "gcAllocCount" {
                        curOps = sbAppend(curOps, "BUILTIN_GCALLOCCOUNT\n")
                        nOps += 1
                    } else if bname == "gcWalkAllocs" {
                        curOps = sbAppend(curOps, "BUILTIN_GCWALKALLOCS\n")
                        nOps += 1
                    } else if bname == "gcCheckpoint" {
                        curOps = sbAppend(curOps, "BUILTIN_GCCHECKPOINT\n")
                        nOps += 1
                    } else if bname == "gcRestore" {
                        curOps = sbAppend(curOps, "BUILTIN_GCRESTORE\n")
                        nOps += 1
                    } else if bname == "gcSlabCount" {
                        curOps = sbAppend(curOps, "BUILTIN_GCSLABCOUNT\n")
                        nOps += 1
                    } else if bname == "gcSlabBytes" {
                        curOps = sbAppend(curOps, "BUILTIN_GCSLABBYTES\n")
                        nOps += 1
                    } else if bname == "fromCharCode" {
                        curOps = sbAppend(curOps, "BUILTIN_FROMCHARCODE\n")
                        nOps += 1
                    } else if bname == "readLine" {
                        curOps = sbAppend(curOps, "BUILTIN_READLINE\n")
                        nOps += 1
                    } else if bname == "shellRun" {
                        curOps = sbAppend(curOps, "BUILTIN_SHELLRUN\n")
                        nOps += 1
                    } else if bname == "exec" {
                        curOps = sbAppend(curOps, "BUILTIN_EXEC\n")
                        nOps += 1
                    } else if bname == "mapHas" {
                        curOps = sbAppend(curOps, "BUILTIN_MAPHAS\n")
                        nOps += 1
                    } else if bname == "mapGet" {
                        curOps = sbAppend(curOps, "BUILTIN_MAPGET\n")
                        nOps += 1
                    } else if bname == "mapSet" {
                        curOps = sbAppend(curOps, "BUILTIN_MAPSET\n")
                        nOps += 1
                    } else if bname == "sockMake" {
                        // C-free BSD sockets via direct syscalls.
                        // See docs/proto/MACOS_SOCKET_SYSCALLS.md.
                        curOps = sbAppend(curOps, "BUILTIN_SOCKMAKE\n")
                        nOps += 1
                    } else if bname == "sockBind" {
                        curOps = sbAppend(curOps, "BUILTIN_SOCKBIND\n")
                        nOps += 1
                    } else if bname == "sockListen" {
                        curOps = sbAppend(curOps, "BUILTIN_SOCKLISTEN\n")
                        nOps += 1
                    } else if bname == "sockAccept" {
                        curOps = sbAppend(curOps, "BUILTIN_SOCKACCEPT\n")
                        nOps += 1
                    } else if bname == "sockRecv" {
                        curOps = sbAppend(curOps, "BUILTIN_SOCKRECV\n")
                        nOps += 1
                    } else if bname == "sockSend" {
                        curOps = sbAppend(curOps, "BUILTIN_SOCKSEND\n")
                        nOps += 1
                    } else if bname == "sockClose" {
                        curOps = sbAppend(curOps, "BUILTIN_SOCKCLOSE\n")
                        nOps += 1
                    } else if bname == "sockRecvStr" {
                        // recv into a fresh heap buffer, NUL-terminate, return
                        // as a Krypton string (like readFile, minus open/close).
                        curOps = sbAppend(curOps, "BUILTIN_SOCKRECVSTR\n")
                        nOps += 1
                    } else if bname == "sockConnect" {
                        // connect(fd, &sockaddr_in, 16) #98 — client side.
                        curOps = sbAppend(curOps, "BUILTIN_SOCKCONNECT\n")
                        nOps += 1
                    } else if bname == "fdRead" {
                        // read(fd, buf, maxlen) #3 into a fresh string. For ptys/pipes.
                        curOps = sbAppend(curOps, "BUILTIN_FDREAD\n")
                        nOps += 1
                    } else if bname == "fdWrite" {
                        // write(fd, buf, len) #4. Works on any fd (pty master, pipe).
                        curOps = sbAppend(curOps, "BUILTIN_FDWRITE\n")
                        nOps += 1
                    } else if bname == "fdClose" {
                        // close(fd) #6.
                        curOps = sbAppend(curOps, "BUILTIN_FDCLOSE\n")
                        nOps += 1
                    } else if bname == "fdSetNonblock" {
                        // fcntl(fd, F_SETFL, O_NONBLOCK) #92 — non-blocking reads.
                        curOps = sbAppend(curOps, "BUILTIN_FDSETNONBLOCK\n")
                        nOps += 1
                    } else if bname == "sleepUs" {
                        // select(0,0,0,0,{sec,usec}) #93 — poll-loop pacing.
                        curOps = sbAppend(curOps, "BUILTIN_SLEEPUS\n")
                        nOps += 1
                    } else if bname == "ptyMaster" {
                        // open(ptmxPath, O_RDWR) + TIOCPTYGRANT + TIOCPTYUNLK; ret master fd.
                        curOps = sbAppend(curOps, "BUILTIN_PTYMASTER\n")
                        nOps += 1
                    } else if bname == "ptySlaveName" {
                        // ioctl(master, TIOCPTYGNAME, buf); return slave path string.
                        curOps = sbAppend(curOps, "BUILTIN_PTYSLAVENAME\n")
                        nOps += 1
                    } else if bname == "ptyForkExec" {
                        // fork; child: setsid+open(slave)+TIOCSCTTY+dup2x3+execve; parent: ret pid.
                        curOps = sbAppend(curOps, "BUILTIN_PTYFORKEXEC\n")
                        nOps += 1
                    } else if bname == "ptySetSize" {
                        // ioctl(fd, TIOCSWINSZ, &{rows,cols}) — tell the pty its size.
                        curOps = sbAppend(curOps, "BUILTIN_PTYSETSIZE\n")
                        nOps += 1
                    } else if bname == "procAlive" {
                        // kill(pid, 0) #37 — 1 if the process exists, else 0.
                        curOps = sbAppend(curOps, "BUILTIN_PROCALIVE\n")
                        nOps += 1
                    } else if bname == "waitChild" {
                        // wait4(pid, 0, WNOHANG, 0) #7 — reap + report a child's exit.
                        curOps = sbAppend(curOps, "BUILTIN_WAITCHILD\n")
                        nOps += 1
                    }
                } else if op == "POP" {
                    curOps = sbAppend(curOps, "POP\n")
                    nOps += 1
                } else if op == "END" {
                    curOps = sbAppend(curOps, "END\n")
                    nOps += 1
                }
            }
        }
        i += 1
    }
    // Finalize last function
    if inFunc == "1" {
        funcsSb = appendFunc(funcsSb, curName, sbToString(sbParams), nParams, sbToString(sbLocals), nLocals, sbToString(curOps), nOps)
        nFunctions += 1
    }
    // Build final output: nFunctions, nStrings, strings, then function blocks
    let r = ("" + nFunctions) + "\n" + ("" + nStrings) + "\n"
    if nStrings > 0 { r = r + sbToString(sbStrings) + "\n" }
    r = r + sbToString(funcsSb)
    emit r
}

// New parsed format (slice 3e):
//   line 0: nFunctions
//   line 1: nStrings
//   lines 2..1+nStrings: each unique string (global)
//   then per-function blocks: header line + nParams param names + nLocals
//   local names + nOps op lines.

func irStringStart() { emit 2 }

// Strings in `parsed` are hex-encoded (xHH...) — each "byte" of content takes
// 3 chars in the stored form. hexBytesLen converts back.

func computeStringOffsets(parsed) {
    let nStrings = toInt(getLine(parsed, 1))
    let r = ""
    let off = 0
    let si = 0
    while si < nStrings {
        if si > 0 { r = r + "\n" }
        r = r + ("" + off)
        let s = getLine(parsed, irStringStart() + si)
        off = off + hexBytesLen(s) + 1   // +1 for NUL terminator
        si += 1
    }
    emit r
}

func computeCStringSize(parsed) {
    let nStrings = toInt(getLine(parsed, 1))
    let off = 0
    let si = 0
    while si < nStrings {
        let s = getLine(parsed, irStringStart() + si)
        off = off + hexBytesLen(s) + 1
        si += 1
    }
    emit off
}

func emitCStringFromIR(parsed) {
    let nStrings = toInt(getLine(parsed, 1))
    let s = ""
    let si = 0
    while si < nStrings {
        let strHex = getLine(parsed, irStringStart() + si)
        s = s + strHex + hexByte(0)       // already hex-encoded; just append NUL byte
        si += 1
    }
    emit s
}

// ── per-function accessors ─────────────────────────────────────────────────

// Convert a function header "name\tnP\tnL\tnO" into a 4-line sub-string.
func parseFuncHeader(h) {
    let out = ""
    let i = 0
    while i < len(h) {
        if h[i] == "\t" { out = out + "\n" } else { out = out + h[i] }
        i += 1
    }
    emit out
}

func funcCount(parsed) { emit toInt(getLine(parsed, 0)) }

// Return the line number in `parsed` of the header for function fIdx.
// Uses g_funcStartCache when populated (set by buildFuncStartCache).
func funcStartLine(parsed, fIdx) {
    if len(g_funcStartCache) > 0 {
        emit toInt(getLine(g_funcStartCache, fIdx))
    }
    // Cold path (no cache): linear walk.
    let nStrings = toInt(getLine(parsed, 1))
    let pos = 2 + nStrings
    let i = 0
    while i < fIdx {
        let h = getLine(parsed, pos)
        let parts = parseFuncHeader(h)
        let nP = toInt(getLine(parts, 1))
        let nL = toInt(getLine(parts, 2))
        let nO = toInt(getLine(parts, 3))
        pos = pos + 1 + nP + nL + nO
        i += 1
    }
    emit pos
}

// Build the function-start cache (newline-separated start lines, one per func).
func buildFuncStartCache(parsed) {
    let nF = funcCount(parsed)
    let nStrings = toInt(getLine(parsed, 1))
    let pos = 2 + nStrings
    let sb = sbNew()
    let i = 0
    while i < nF {
        if i > 0 { sbAppend(sb, "\n") }
        sbAppend(sb, "" + pos)
        let h = getLine(parsed, pos)
        let parts = parseFuncHeader(h)
        let nP = toInt(getLine(parts, 1))
        let nL = toInt(getLine(parts, 2))
        let nO = toInt(getLine(parts, 3))
        pos = pos + 1 + nP + nL + nO
        i += 1
    }
    emit sbToString(sb)
}

func funcName(parsed, fIdx) {
    let h = getLine(parsed, funcStartLine(parsed, fIdx))
    let i = 0
    while i < len(h) && h[i] != "\t" { i += 1 }
    emit substring(h, 0, i)
}
func funcNParams(parsed, fIdx) {
    let parts = parseFuncHeader(getLine(parsed, funcStartLine(parsed, fIdx)))
    emit toInt(getLine(parts, 1))
}
func funcNLocals(parsed, fIdx) {
    let parts = parseFuncHeader(getLine(parsed, funcStartLine(parsed, fIdx)))
    emit toInt(getLine(parts, 2))
}
func funcNOps(parsed, fIdx) {
    let parts = parseFuncHeader(getLine(parsed, funcStartLine(parsed, fIdx)))
    emit toInt(getLine(parts, 3))
}
func funcOp(parsed, fIdx, oIdx) {
    let s = funcStartLine(parsed, fIdx)
    let nP = funcNParams(parsed, fIdx)
    let nL = funcNLocals(parsed, fIdx)
    emit getLine(parsed, s + 1 + nP + nL + oIdx)
}

// Per-function frame size (8 B per param+local, rounded up to 16).
func computeFrameSizeF(parsed, fIdx) {
    let total = funcNParams(parsed, fIdx) + funcNLocals(parsed, fIdx)
    if total == 0 { emit 0 }
    emit ((total + 1) / 2) * 16
}

// Per-op instruction count under the slice 3b/3c eval-stack model.
//   PUSH_STR     : 3  (adrp + add + str push)
//   PUSH_INT     : 2  (movz/movn + str push)  [for 16-bit values]
//   LOAD_LOCAL   : 2  (ldur + str push)
//   STORE_LOCAL  : 2  (ldr pop + stur)
//   ADD/SUB/MUL/DIV : 4 (ldr pop b + ldr pop a + op x0,x1,x0 + str push)
//   MOD          : 5  (ldr + ldr + sdiv + msub + str)
//   BUILTIN_KP   : 4  (ldr pop + bl + movz + str push 0)
//   BUILTIN_EXIT : 5  (ldr pop + movz x16 + svc + movz dead + str dead)
//   POP          : 1  (ldr discard)
//   END          : 3  + 1 if frame (movz w0 0 + ldp + ret + maybe add sp first)
//   prologue     : 2  + 1 if frame (stp + mov fp sp + maybe sub sp)
// Per-op instruction count (frame-independent ops only — RETURN/END/CALL_FUNC
// are handled at the caller because they depend on frame size or argc).
func opInstrCount(opTok) {
    if opTok == "PUSH_STR"     { emit 3 }
    if opTok == "FUNCPTR"      { emit 3 }   // adrp + add (func vaddr) + push
    if opTok == "PUSH_INT"     { emit 3 }   // movz low / movk high or nop / push
    if opTok == "LOAD_SLOT"    { emit 2 }
    if opTok == "STORE_SLOT"   { emit 2 }
    if opTok == "LOAD_GLOBAL"  { emit 4 }
    if opTok == "STORE_GLOBAL" { emit 4 }
    if opTok == "ADD"          { emit 193 } // int+int(8)|numstr+int(71)|concat(111)
    if opTok == "CAT"          { emit 113 } // 2 pops + emitPolyConcat (111)
    if opTok == "SUB"          { emit 4 }
    if opTok == "MUL"          { emit 4 }
    if opTok == "DIV"          { emit 4 }
    if opTok == "MOD"          { emit 5 }
    if opTok == "LT"           { emit 19 }  // polymorphic: int/mixed raw cmp / ptr+ptr strcmp-order
    if opTok == "GT"           { emit 19 }
    if opTok == "LE"           { emit 19 }
    if opTok == "GE"           { emit 19 }
    if opTok == "EQ"           { emit 25 }  // polymorphic: int+int cmp / ptr+ptr strcmp / mixed=unequal
    if opTok == "NE"           { emit 25 }  // same code path with EQ-cond → NE-cond + flipped results
    if opTok == "JUMP"             { emit 1 }
    if opTok == "JUMPIFNOT"        { emit 3 }  // pop, cbnz+2 (skip B if truthy), b target
    if opTok == "JUMPIF"           { emit 3 }  // pop, cbz+2 (skip B if falsy),  b target
    if opTok == "LABEL"            { emit 0 }
    if opTok == "NEG"              { emit 3 }   // pop, neg, push
    if opTok == "NOT"              { emit 4 }   // pop, cmp, cset, push
    if opTok == "INDEX"            { emit 27 }  // pop i, pop s, alloc(21), ldrb, strb char, strb NUL, push
    if opTok == "BUILTIN_KP"       { emit 69 }  // string or int dispatch; inline itoa for ints
    if opTok == "BUILTIN_EXIT"     { emit 13 }  // atoi(str arg) then exit(code)
    if opTok == "BUILTIN_LEN"      { emit 7 }   // pop, mov, ldrb-post, cbnz, sub-reg, sub-imm, push
    if opTok == "BUILTIN_CHARCODE" { emit 3 }   // pop, ldrb, push
    if opTok == "BUILTIN_SUBSTRING"{ emit 37 }  // alloc(21) bumped from 15 → +6
    if opTok == "BUILTIN_STARTSWITH"{ emit 14 }
    if opTok == "BUILTIN_ISDIGIT"  { emit 10 }
    if opTok == "BUILTIN_TOINT"    { emit 30 }  // signed parse (handles leading '-')
    if opTok == "BUILTIN_INDEXOF"  { emit 21 }
    if opTok == "BUILTIN_SBNEW"        { emit 52 }   // stable handle + buffer (2 allocs)
    if opTok == "BUILTIN_SBAPPEND"     { emit 84 }   // grow-in-place via handle indirection
    if opTok == "BUILTIN_SBTOSTRING"   { emit 4 }    // handle → buf+16
    if opTok == "BUILTIN_CONTAINS"     { emit 23 }   // indexOf core (20) + cmp + cset + push
    if opTok == "BUILTIN_PRINT"        { emit 52 }
    if opTok == "BUILTIN_PRINTERR"     { emit 52 }
    if opTok == "BUILTIN_BITAND"       { emit 4 }  // pop x1, pop x0, and, push
    if opTok == "BUILTIN_BITOR"        { emit 4 }  // pop x1, pop x0, orr, push
    if opTok == "BUILTIN_BITXOR"       { emit 4 }  // pop x1, pop x0, eor, push
    if opTok == "BUILTIN_BITSHR"       { emit 4 }  // pop x1, pop x0, lsr, push
    if opTok == "BUILTIN_BITSHL"       { emit 4 }  // pop x1, pop x0, lsl, push
    if opTok == "BUILTIN_BITNOT"       { emit 3 }  // pop x0, mvn, push
    if opTok == "BUILTIN_POW"          { emit 8 }
    if opTok == "BUILTIN_ENDSWITH"     { emit 29 }
    if opTok == "BUILTIN_ARG"          { emit 25 }  // inline-toInt + load argv + index
    if opTok == "BUILTIN_ARGCOUNT"     { emit 5 }
    if opTok == "BUILTIN_READFILE"     { emit 41 }   // alloc(21) +6 from 35
    if opTok == "BUILTIN_WRITEFILE"    { emit 22 }
    if opTok == "BUILTIN_WRITEBYTES"   { emit 54 }
    if opTok == "BUILTIN_TRIM"         { emit 56 }   // alloc(21) +6 from 50
    if opTok == "BUILTIN_TOLOWER"      { emit 42 }   // strlen(7)+alloc(21)+xform copy(14)
    if opTok == "BUILTIN_TOUPPER"      { emit 42 }   // strlen(7)+alloc(21)+xform copy(14)
    if opTok == "BUILTIN_ENVIRON"      { emit 21 }   // scan saved envp (cell+80) for name= ; value ptr or ""
    if opTok == "BUILTIN_LENGTH"       { emit 13 }   // empty-check + comma-counter loop
    if opTok == "BUILTIN_SPLIT"        { emit 50 }   // scan + alloc(21) + copy + NUL + push
    if opTok == "BUILTIN_RANGE"        { emit 75 }   // alloc(21) + inline itoa loop with stack scratch
    if opTok == "BUILTIN_COUNT"        { emit 10 }   // walk string, cnt = 1 + commas
    if opTok == "BUILTIN_ISTRUTHY"     { emit 35 }   // int=nonzero / ptr: empty / "0" / "false" → falsy, else truthy
    if opTok == "BUILTIN_LINECOUNT"    { emit 18 }   // \n counter with trailing-NL adjustment (matches C kr_linecount)
    if opTok == "BUILTIN_GETLINE"      { emit 65 }   // SPLIT-style \n scan + pointer-keyed cache (O(1) sequential)
    if opTok == "BUILTIN_REPLACE"      { emit 95 }   // strlens + occurrence count + alloc(21) + substituting copy
    if opTok == "BUILTIN_GCALLOCATED"  { emit 4 }   // adrp + add + ldr [x1,#24] + push
    if opTok == "BUILTIN_GCLIMIT"      { emit 4 }   // adrp + add + ldr [x1,#32] + push
    if opTok == "BUILTIN_GCSETLIMIT"   { emit 5 }   // pop + adrp + add + str [x1,#32] + push
    if opTok == "BUILTIN_GCRESET"      { emit 8 }   // adrp + add + 4 stores (bump, alloc_total, shadow_count, gcAllocsHead) + movz + push
    if opTok == "BUILTIN_GCCOLLECT"    { emit 43 }  // real: mark + sweep inline, returns swept count
    // 2.0 GC builtins (stub-only; real impl pending mark-sweep port). Each
    // either takes 0 args + pushes 0 (count/checkpoint/walk), or takes 1 arg,
    // discards it, and pushes 0 (push/pop/restore). Tier-3 calling convention:
    // BUILTIN n means n args came in via eval-stack pops; we pop them so the
    // stack stays balanced, then push our scalar result.
    if opTok == "BUILTIN_GCSHADOWPUSH"     { emit 8 }   // count-only: pop+adrp+add+ldr+add+str+movz+push (no root store)
    if opTok == "BUILTIN_GCSHADOWPOP"      { emit 8 }   // real: pop+adrp+add+ldr+sub+str+movz+push
    if opTok == "BUILTIN_GCSHADOWCOUNT"    { emit 4 }   // real: adrp+add+ldr+push
    if opTok == "BUILTIN_GCMARK"           { emit 27 }  // shadow-walk + mark-bit set
    if opTok == "BUILTIN_GCSWEEP"          { emit 22 }  // alloc-list walk + unlink unmarked
    if opTok == "BUILTIN_GCFREELISTCOUNT"  { emit 2 }
    if opTok == "BUILTIN_GCALLOCCOUNT"     { emit 10 }  // real: walk gcAllocsHead, count
    if opTok == "BUILTIN_GCWALKALLOCS"     { emit 3 }   // takes 1 (callback ptr)
    if opTok == "BUILTIN_GCCHECKPOINT"     { emit 4 }   // real: snapshot gcShadowCount
    if opTok == "BUILTIN_GCRESTORE"        { emit 6 }   // real: gcShadowCount = arg
    if opTok == "BUILTIN_GCSLABCOUNT"      { emit 2 }
    if opTok == "BUILTIN_GCSLABBYTES"      { emit 2 }
    if opTok == "BUILTIN_FROMCHARCODE" { emit 26 }
    if opTok == "BUILTIN_READLINE"     { emit 46 }
    if opTok == "BUILTIN_SHELLRUN"     { emit 84 }
    if opTok == "BUILTIN_EXEC"         { emit 98 }
    if opTok == "BUILTIN_MAPHAS"       { emit 32 }
    if opTok == "BUILTIN_MAPGET"       { emit 93 }
    if opTok == "BUILTIN_MAPSET"       { emit 150 }
    if opTok == "BUILTIN_SOCKMAKE"     { emit 6 }   // movz x0,x1,x2,x16=97; svc; push
    if opTok == "BUILTIN_SOCKBIND"     { emit 49 }  // pop fd,hi,lo; alloc(21) sockaddr; fill 16B; bind(104)
    if opTok == "BUILTIN_SOCKLISTEN"   { emit 5 }   // pop backlog,fd; x16=106; svc; push
    if opTok == "BUILTIN_SOCKACCEPT"   { emit 6 }   // pop fd; x1=0;x2=0;x16=30; svc; push
    if opTok == "BUILTIN_SOCKRECV"     { emit 9 }   // pop len,buf,fd; x3=x4=x5=0;x16=29; svc; push
    if opTok == "BUILTIN_SOCKSEND"     { emit 6 }   // pop len,buf,fd; x16=4(write); svc; push
    if opTok == "BUILTIN_SOCKCLOSE"    { emit 4 }   // pop fd; x16=6; svc; push
    if opTok == "BUILTIN_SOCKRECVSTR"  { emit 36 }  // pop fd; alloc(21) 64K; recvfrom; NUL-term; return buf
    if opTok == "BUILTIN_SOCKCONNECT"  { emit 53 }  // pop lo,hi,d,c,b,a,fd(7); alloc(21) sockaddr; fill 16B w/IP; connect(98)
    if opTok == "BUILTIN_FDWRITE"      { emit 6 }   // pop len,buf,fd; x16=4(write); svc; push
    if opTok == "BUILTIN_FDCLOSE"      { emit 4 }   // pop fd; x16=6(close); svc; push
    if opTok == "BUILTIN_FDREAD"       { emit 36 }  // pop maxlen,fd; alloc(21) buf; read(3); carry-clamp; NUL-term; return buf
    if opTok == "BUILTIN_FDSETNONBLOCK"{ emit 6 }   // pop fd; fcntl(fd,F_SETFL=4,O_NONBLOCK=4) #92; push
    if opTok == "BUILTIN_SLEEPUS"      { emit 34 }  // pop usec,sec; alloc(21) timeval; select(0,0,0,0,&tv) #93; push
    if opTok == "BUILTIN_PTYMASTER"    { emit 20 }  // open(ptmx); TIOCPTYGRANT; TIOCPTYUNLK; ret master
    if opTok == "BUILTIN_PTYSLAVENAME" { emit 32 }  // alloc(21) 128B; ioctl TIOCPTYGNAME; ret slave path
    if opTok == "BUILTIN_PTYFORKEXEC"  { emit 68 }  // fork; child setsid+open+TIOCSCTTY+dup2x3+execve(inherited envp); parent ret pid
    if opTok == "BUILTIN_PTYSETSIZE"   { emit 40 }  // pop cols,rows,fd; alloc(21) winsize; ioctl TIOCSWINSZ; push
    if opTok == "BUILTIN_PROCALIVE"    { emit 8 }   // pop pid; kill(pid,0) #37; carry-clear->1 else 0; push
    if opTok == "BUILTIN_WAITCHILD"    { emit 7 }   // pop pid; wait4(pid,0,WNOHANG=1,0) #7; push x0 (pid reaped/0 running)
    if opTok == "POP"              { emit 1 }
    emit 0
}

// Look up a "name=value" entry in a newline-separated table. Returns value
// (parsed as int) or -1 if not found. Used for both label tables and the
// function table.
func findLabel(table, name) {
    let nl = lineCount(table)
    let i = 0
    while i < nl {
        let line = getLine(table, i)
        let eq = 0
        while eq < len(line) && line[eq] != "=" { eq += 1 }
        if substring(line, 0, eq) == name {
            emit toInt(substring(line, eq + 1, len(line)))
        }
        i += 1
    }
    emit 0 - 1
}

// Compute the total instruction count of one function (frame-aware).
func computeFunctionInstrs(parsed, fIdx) {
    let frame = computeFrameSizeF(parsed, fIdx)
    let nP = funcNParams(parsed, fIdx)
    let nO = funcNOps(parsed, fIdx)
    let n = 2                      // prologue: stp + mov fp sp
    if frame > 0 { n = n + 1 }     // sub sp
    n = n + nP                     // save each param
    // __main__ also saves argc/argv to fixed cells (4 instr)
    if funcName(parsed, fIdx) == "__main__" { n = n + 19 }  // 5 argc/argv/envp save + 14 mmap-heap seed
    let oi = 0
    while oi < nO {
        let opLine = funcOp(parsed, fIdx, oi)
        let sp = 0
        while sp < len(opLine) && opLine[sp] != " " { sp += 1 }
        let tok = substring(opLine, 0, sp)
        if tok == "CALL_FUNC" {
            let s2 = sp + 1
            while s2 < len(opLine) && opLine[s2] != " " { s2 += 1 }
            let argc = 0
            if s2 < len(opLine) { argc = toInt(trim(substring(opLine, s2 + 1, len(opLine)))) }
            n = n + cfCount(substring(opLine, sp + 1, s2), argc)
        } else if tok == "RETURN" {
            n = n + 3
            if frame > 0 { n = n + 1 }
        } else if tok == "END" {
            n = n + 3
            if frame > 0 { n = n + 1 }
        } else if tok == "LOAD_SLOT" {
            let slotNum = toInt(trim(substring(opLine, sp + 1, len(opLine))))
            let slotOff = 0 - (8 + slotNum * 8)
            if slotOff < (0 - 256) { n = n + 3 } else { n = n + 2 }
        } else if tok == "STORE_SLOT" {
            let slotNum = toInt(trim(substring(opLine, sp + 1, len(opLine))))
            let slotOff = 0 - (8 + slotNum * 8)
            if slotOff < (0 - 256) { n = n + 3 } else { n = n + 2 }
        } else {
            n = n + opInstrCount(tok)
        }
        oi += 1
    }
    emit n
}

// Build per-function label table. instrIdx is "absolute" within __text (so
// callers can compute jump deltas without separate per-function bias).
func buildFunctionLabelTable(parsed, fIdx, funcStartInstr) {
    let frame = computeFrameSizeF(parsed, fIdx)
    let nP = funcNParams(parsed, fIdx)
    let nO = funcNOps(parsed, fIdx)
    let tableSb = sbNew()
    let nTable = 0
    let n = funcStartInstr + 2
    if frame > 0 { n = n + 1 }
    n = n + nP
    if funcName(parsed, fIdx) == "__main__" { n = n + 19 }  // 5 argc/argv/envp save + 14 mmap-heap seed
    let opBase = funcStartLine(parsed, fIdx) + 1 + nP + funcNLocals(parsed, fIdx)
    let oi = 0
    while oi < nO {
        let opLine = getLine(parsed, opBase + oi)
        let sp = 0
        while sp < len(opLine) && opLine[sp] != " " { sp += 1 }
        let tok = substring(opLine, 0, sp)
        if tok == "LABEL" {
            let name = trim(substring(opLine, sp + 1, len(opLine)))
            if nTable > 0 { tableSb = sbAppend(tableSb, "\n") }
            tableSb = sbAppend(tableSb, name + "=" + ("" + n))
            nTable = nTable + 1
        } else if tok == "CALL_FUNC" {
            let s2 = sp + 1
            while s2 < len(opLine) && opLine[s2] != " " { s2 += 1 }
            let argc = 0
            if s2 < len(opLine) { argc = toInt(trim(substring(opLine, s2 + 1, len(opLine)))) }
            n = n + cfCount(substring(opLine, sp + 1, s2), argc)
        } else if tok == "RETURN" {
            n = n + 3
            if frame > 0 { n = n + 1 }
        } else if tok == "END" {
            n = n + 3
            if frame > 0 { n = n + 1 }
        } else if tok == "LOAD_SLOT" {
            let slotNum = toInt(trim(substring(opLine, sp + 1, len(opLine))))
            let slotOff = 0 - (8 + slotNum * 8)
            if slotOff < (0 - 256) { n = n + 3 } else { n = n + 2 }
        } else if tok == "STORE_SLOT" {
            let slotNum = toInt(trim(substring(opLine, sp + 1, len(opLine))))
            let slotOff = 0 - (8 + slotNum * 8)
            if slotOff < (0 - 256) { n = n + 3 } else { n = n + 2 }
        } else {
            n = n + opInstrCount(tok)
        }
        oi += 1
    }
    emit sbToString(tableSb)
}

// Find the function index of __main__ (or -1 if absent).
func mainFuncIndex(parsed) {
    let nF = funcCount(parsed)
    let i = 0
    while i < nF {
        if funcName(parsed, i) == "__main__" { emit i }
        i += 1
    }
    emit 0 - 1
}

// Emission order: __main__ first (so its code is at TEXT_OFF, matching
// LC_MAIN's entryoff), then other functions in declaration order.
func emitOrder(parsed) {
    let nF = funcCount(parsed)
    let mainIdx = mainFuncIndex(parsed)
    let r = ""
    if mainIdx >= 0 { r = "" + mainIdx }
    let i = 0
    while i < nF {
        if i != mainIdx {
            if len(r) > 0 { r = r + "\n" }
            r = r + ("" + i)
        }
        i += 1
    }
    emit r
}

// Function table: name → starting instruction index in __text. Uses emitOrder
// (__main__ first), so the entry point at TEXT_OFF is always __main__.
func buildFunctionTable(parsed) {
    let order = emitOrder(parsed)
    let nF = funcCount(parsed)
    let r = ""
    let cur = 0
    let oi = 0
    while oi < nF {
        let fIdx = toInt(getLine(order, oi))
        if oi > 0 { r = r + "\n" }
        r = r + funcName(parsed, fIdx) + "=" + ("" + cur)
        cur = cur + computeFunctionInstrs(parsed, fIdx)
        oi += 1
    }
    emit r
}

// Map IR comparison op token → AArch64 cond code.
func irCmpToCond(opTok) {
    if opTok == "EQ" { emit 0x0 }
    if opTok == "NE" { emit 0x1 }
    if opTok == "GE" { emit 0xa }
    if opTok == "LT" { emit 0xb }
    if opTok == "GT" { emit 0xc }
    if opTok == "LE" { emit 0xd }
    emit 0
}

// Total __text size in bytes — sum of all functions.
func computeTextSize(parsed) {
    let nF = funcCount(parsed)
    let total = 0
    let i = 0
    while i < nF {
        total = total + computeFunctionInstrs(parsed, i)
        i += 1
    }
    emit total * 4
}

// Emit one function: prologue (with param save) + ops + epilogue. instrIdx is
// absolute within __text (so jumps can use absolute deltas).
func emitOneFunction(parsed, fIdx, funcStartInstr, funcTable, strOffsets, textSz) {
    let frame = computeFrameSizeF(parsed, fIdx)
    let nP = funcNParams(parsed, fIdx)
    let nO = funcNOps(parsed, fIdx)
    let labels = buildFunctionLabelTable(parsed, fIdx, funcStartInstr)

    let textVaddr = 0
    let textOff = g_TEXT_OFF                 // 0x460, or 0x800 when N foreign imports present
    // __cstring follows __text + __stubs (objk: g_STUBS_SZ bytes of import stubs).
    let cstringOff = textOff + textSz + g_STUBS_SZ
    let stubVaddr = textVaddr + cstringOff

    let s = sbNew()
    let instrIdx = funcStartInstr

    s = sbAppend(s, arm64_stp_fp_lr_pre16())
    s = sbAppend(s, arm64_mov_fp_sp())
    instrIdx = instrIdx + 2
    if frame > 0 {
        s = sbAppend(s, arm64_sub_sp(frame))
        instrIdx = instrIdx + 1
    }
    // Save params x0..x(nP-1) into local slots
    let pi = 0
    while pi < nP {
        let off = 0 - (8 + pi * 8)
        s = sbAppend(s, arm64_stur(pi, 29, off))
        instrIdx = instrIdx + 1
        pi += 1
    }
    // __main__ saves argc/argv to fixed __DATA cells so arg()/argCount() can read.
    // Layout: bump cell @ +0, argc save @ +8, argv save @ +16, heap from +64.
    if funcName(parsed, fIdx) == "__main__" {
        let imm21 = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + instrIdx * 4) / 4096
        s = sbAppend(s, arm64_adrp(9, imm21))
        s = sbAppend(s, arm64_add_imm(9, 9, 0))  // bump cell is page-aligned, pageoff=0
        s = sbAppend(s, arm64_str_imm(0, 9, 1))  // str x0 (argc), [x9, #8]
        s = sbAppend(s, arm64_str_imm(1, 9, 2))  // str x1 (argv), [x9, #16]
        s = sbAppend(s, arm64_str_imm(2, 9, 10)) // str x2 (envp), [x9, #80] — for environ() (before mmap clobbers x2)
        instrIdx = instrIdx + 5
        // mmap a large anonymous heap and seed the bump pointer with it. The
        // __DATA zero-fill heap caps at 0x70000000 (dyld shared cache sits at
        // ~0x180000000 right above it), too small to self-compile compile.k.
        // An anon mmap lands high (~0x300000000) with room to spare. emitAllocVar
        // reads bump_cell+0 and uses it when non-zero, so seeding it = heap moves
        // off __DATA. On mmap failure (x0 < 4GB) we leave it 0 → default __DATA
        // heap (unchanged behavior). 14 instr.
        s = sbAppend(s, arm64_movz_x_imm(0, 0))          // 0: addr = 0 (kernel picks)
        s = sbAppend(s, arm64_movz_x_imm_lsl32(1, 2))    // 1: len = 2<<32 = 8 GB
        s = sbAppend(s, arm64_movz_x_imm(2, 3))          // 2: prot = PROT_READ|WRITE
        s = sbAppend(s, arm64_movz_x_imm(3, 0x1002))     // 3: flags = MAP_ANON|MAP_PRIVATE
        s = sbAppend(s, arm64_movn_x_imm(4, 0))          // 4: fd = -1
        s = sbAppend(s, arm64_movz_x_imm(5, 0))          // 5: offset = 0
        s = sbAppend(s, arm64_movz_x_imm(16, 197))       // 6: SYS_mmap
        s = sbAppend(s, arm64_svc(0x80))                 // 7: x0 = base or error
        let imm21m = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + (instrIdx + 8) * 4) / 4096
        s = sbAppend(s, arm64_adrp(9, imm21m))           // 8: re-derive cell (svc may clobber x9)
        s = sbAppend(s, arm64_add_imm(9, 9, 0))          // 9
        s = sbAppend(s, arm64_movz_x_imm_lsl32(14, 1))   // 10: x14 = 0 (4 GB)
        s = sbAppend(s, arm64_cmp_xx(0, 14))             // 11: cmp base, 4GB
        s = sbAppend(s, arm64_b_cond(0x3, 2))            // 12: b.lo SKIP (mmap failed → keep 0)
        s = sbAppend(s, arm64_str_imm(0, 9, 0))          // 13: bump_cell+0 = mmap base
        instrIdx = instrIdx + 14
    }

    // Cache the op-block base line once (funcOp re-derived it per op, re-parsing
    // the header and re-scanning the multi-MB parsed string each time — the
    // dominant heap churn and the O(n^2) time during a self-compile).
    let opBase = funcStartLine(parsed, fIdx) + 1 + nP + funcNLocals(parsed, fIdx)
    let oi = 0
    while oi < nO {
        let opLine = getLine(parsed, opBase + oi)
        let spIdx = 0
        while spIdx < len(opLine) && opLine[spIdx] != " " { spIdx += 1 }
        let opTok = substring(opLine, 0, spIdx)
        let restTok = ""
        if spIdx < len(opLine) { restTok = trim(substring(opLine, spIdx + 1, len(opLine))) }

        if opTok == "PUSH_STR" {
            let strIdx = toInt(restTok)
            let strOff = toInt(getLine(strOffsets, strIdx))
            let strOffInText = cstringOff + strOff
            let imm21 = strOffInText / 4096 - (textOff + instrIdx * 4) / 4096
            s = sbAppend(s, arm64_adrp(0, imm21))
            s = sbAppend(s, arm64_add_imm(0, 0, strOffInText % 4096))
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 3
        } else if opTok == "FUNCPTR" {
            // push the __text vaddr of function `restTok` (objk: use as an objc IMP).
            let fOff = textOff + findLabel(funcTable, restTok) * 4
            let fImm = fOff / 4096 - (textOff + instrIdx * 4) / 4096
            s = sbAppend(s, arm64_adrp(0, fImm))
            s = sbAppend(s, arm64_add_imm(0, 0, fOff % 4096))
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 3
        } else if opTok == "PUSH_INT" {
            // Load 32-bit signed int into x0 then push. movz only handles 16 bits,
            // so for any positive >= 65536 we need movk for the high 16. Negative
            // values stay in the small-magnitude range (movn handles -65536..-1);
            // beyond that, values aren't correctly representable without sign extension.
            // Always 3 instructions for layout consistency (3rd is nop when not needed).
            let n = toInt(restTok)
            if n >= 0 {
                s = sbAppend(s, arm64_movz_x_imm(0, n % 65536))
                if n >= 65536 {
                    s = sbAppend(s, arm64_movk_x_imm_lsl16(0, (n / 65536) % 65536))
                } else {
                    s = sbAppend(s, arm64_nop())
                }
            } else {
                // Negative 32-bit: 4294967296 wraps to 0 in Krypton so we can't add
                // it to get unsigned. Instead extract unsigned 16-bit halves via
                // modular arithmetic: lo16 = n%65536 adjusted to [0,65535]; hi16 from
                // (n - lo16)/65536 + 65536. Both stay within 32-bit signed range.
                let lo16 = n % 65536
                if lo16 < 0 { lo16 = lo16 + 65536 }
                let hi16 = (n - lo16) / 65536 + 65536
                s = sbAppend(s, arm64_movz_x_imm(0, lo16))
                s = sbAppend(s, arm64_movk_x_imm_lsl16(0, hi16))
            }
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 3
        } else if opTok == "ADD" {
            // Polymorphic ADD — 193 instructions. Three paths:
            //   INT+INT (0-9):   both < threshold → integer add → push
            //   NUMSTR+INT (10-81): a=ptr, b=int, a-string is all-digits →
            //                       alloc 24B heap, itoa(parse(a)+b), push string
            //   CONCAT (82-192): fallback string concat via emitPolyConcat
            //
            // Layout:
            //   0:pop x6  1:pop x3  2:movz x14  3:cmp a,thr  4:b.ge→A_PTR@10
            //   5:cmp b,thr  6:b.ge→CONCAT@82  7:add  8:push  9:b→DONE@193
            //   A_PTR(10): 10:cmp b,thr  11:b.ge→CONCAT@82
            //   SCAN(12-21): 12:movz x4=0  13:LOOP:ldrb  14:cbz→@21  15:cmp48
            //     16:b.lt→CONCAT  17:cmp57  18:b.gt→CONCAT  19:add x4  20:b→LOOP
            //     21:cbz x4→CONCAT(empty)
            //   PARSE(22-31): 22:movz x15=0  23:movz x4=0  24:LOOP:ldrb
            //     25:cbz→@32  26:sub#48  27:movz x10=10  28:mul  29:add  30:add x4  31:b→LOOP
            //   ALLOC(32-52): emitAllocN(24) → x0=heapbuf (21 instr)
            //   ITOA(53-81): 53:add x13=x15+x6  54:add x4=x0+22  55:strb NUL
            //     56:movz x5=0  57:cmp x13,0  58:b.ge→@61  59:movz x5=1  60:neg x13
            //     61:cbnz x13,+5→@66  62:sub x4  63:movz'0'  64:strb  65:b→@75
            //     66:cbz x13,+9→@75  67:movz x7=10  68:udiv  69:msub  70:add#48
            //     71:sub x4  72:strb  73:mov x13=quot  74:b→@66
            //     75:cbz x5,+4→@79  76:sub x4  77:movz'-'  78:strb
            //     79:mov x0,x4  80:push  81:b→DONE@193
            //   CONCAT(82-192): emitPolyConcat
            s = sbAppend(s, arm64_pop(6))  // 0: b
            s = sbAppend(s, arm64_pop(3))  // 1: a
            s = sbAppend(s, arm64_movz_x_imm_lsl32(14, 1))  // 2: threshold
            s = sbAppend(s, arm64_cmp_xx(3, 14))  // 3
            s = sbAppend(s, arm64_b_cond(0xa, 6))  // 4: b.ge → A_PTR@10
            s = sbAppend(s, arm64_cmp_xx(6, 14))  // 5
            s = sbAppend(s, arm64_b_cond(0xa, 76))  // 6: b.ge → CONCAT@82
            // INT_INT @ 7: 32-bit add so result wraps at 2^32 (SHA-256 requires mod 2^32)
            s = sbAppend(s, arm64_add_www(0, 3, 6))  // 7
            s = sbAppend(s, arm64_push_x0())  // 8
            s = sbAppend(s, arm64_b(184))  // 9: → ADD_DONE@193
            // A_PTR @ 10: a is ptr
            s = sbAppend(s, arm64_cmp_xx(6, 14))  // 10
            s = sbAppend(s, arm64_b_cond(0xa, 71))  // 11: b.ge → CONCAT@82
            // SCAN: a-string all digits?
            s = sbAppend(s, arm64_movz_x_imm(4, 0))  // 12: i = 0
            // SCAN_LOOP @ 13:
            s = sbAppend(s, arm64_ldrb_reg(5, 3, 4))  // 13
            s = sbAppend(s, arm64_cbz(5, 7))  // 14: NUL → NUM_CHECK@21
            s = sbAppend(s, arm64_cmp_imm(5, 48))  // 15
            s = sbAppend(s, arm64_b_cond(0xb, 66))  // 16: b.lt → CONCAT@82
            s = sbAppend(s, arm64_cmp_imm(5, 57))  // 17
            s = sbAppend(s, arm64_b_cond(0xc, 64))  // 18: b.gt → CONCAT@82
            s = sbAppend(s, arm64_add_imm(4, 4, 1))  // 19
            s = sbAppend(s, arm64_b(0 - 7))  // 20: → SCAN_LOOP@13
            // NUM_CHECK @ 21:
            s = sbAppend(s, arm64_cbz(4, 61))  // 21: empty → CONCAT@82
            // PARSE a → x15
            s = sbAppend(s, arm64_movz_x_imm(15, 0))  // 22
            s = sbAppend(s, arm64_movz_x_imm(4, 0))  // 23
            // PARSE_LOOP @ 24:
            s = sbAppend(s, arm64_ldrb_reg(7, 3, 4))  // 24
            s = sbAppend(s, arm64_cbz(7, 7))  // 25: → PARSED@32
            s = sbAppend(s, arm64_sub_imm(7, 7, 48))  // 26
            s = sbAppend(s, arm64_movz_x_imm(10, 10))  // 27
            s = sbAppend(s, arm64_mul_xxx(15, 15, 10))  // 28
            s = sbAppend(s, arm64_add_xxx(15, 15, 7))  // 29
            s = sbAppend(s, arm64_add_imm(4, 4, 1))  // 30
            s = sbAppend(s, arm64_b(0 - 7))  // 31: → PARSE_LOOP@24
            // PARSED @ 32: allocate 24-byte heap buffer → x0 (21 instr)
            instrIdx = instrIdx + 32
            s = sbAppend(s, emitAllocN(24, instrIdx, textVaddr, textOff))
            instrIdx = instrIdx + 21   // now at 53
            // ITOA: sum x15+x6 → x13, write into heap buf at x0 backward from p=x0+22
            s = sbAppend(s, arm64_add_xxx(13, 15, 6))  // 53: x13 = parsed_a + b
            s = sbAppend(s, arm64_add_imm(4, 0, 22))  // 54: p = buf+22
            s = sbAppend(s, arm64_strb_imm(31, 4, 0))  // 55: buf[22] = NUL (bzr)
            s = sbAppend(s, arm64_movz_x_imm(5, 0))  // 56: neg = 0
            s = sbAppend(s, arm64_cmp_imm(13, 0))  // 57
            s = sbAppend(s, arm64_b_cond(0xa, 3))  // 58: b.ge → IPOS@61
            s = sbAppend(s, arm64_movz_x_imm(5, 1))  // 59
            s = sbAppend(s, arm64_neg(13, 13))  // 60
            // IPOS @ 61:
            s = sbAppend(s, arm64_cbnz(13, 5))  // 61: → ILOOP@66
            s = sbAppend(s, arm64_sub_imm(4, 4, 1))  // 62: zero → write '0'
            s = sbAppend(s, arm64_movz_w_imm(7, 0x30))  // 63
            s = sbAppend(s, arm64_strb_imm(7, 4, 0))  // 64
            s = sbAppend(s, arm64_b(10))  // 65: → ISIGN@75
            // ILOOP @ 66:
            s = sbAppend(s, arm64_cbz(13, 9))  // 66: → ISIGN@75
            s = sbAppend(s, arm64_movz_x_imm(7, 10))  // 67
            s = sbAppend(s, arm64_udiv_xxx(8, 13, 7))  // 68
            s = sbAppend(s, arm64_msub_xxxx(9, 8, 7, 13))  // 69: rem
            s = sbAppend(s, arm64_add_imm(9, 9, 0x30))  // 70
            s = sbAppend(s, arm64_sub_imm(4, 4, 1))  // 71
            s = sbAppend(s, arm64_strb_imm(9, 4, 0))  // 72
            s = sbAppend(s, arm64_mov_xx(13, 8))  // 73: quotient
            s = sbAppend(s, arm64_b(0 - 8))  // 74: → ILOOP@66
            // ISIGN @ 75:
            s = sbAppend(s, arm64_cbz(5, 4))  // 75: → IDONE@79
            s = sbAppend(s, arm64_sub_imm(4, 4, 1))  // 76
            s = sbAppend(s, arm64_movz_w_imm(7, 0x2D))  // 77: '-'
            s = sbAppend(s, arm64_strb_imm(7, 4, 0))  // 78
            // IDONE @ 79:
            s = sbAppend(s, arm64_mov_xx(0, 4))  // 79: x0 = start of number string
            s = sbAppend(s, arm64_push_x0())  // 80
            s = sbAppend(s, arm64_b(112))  // 81: → ADD_DONE@193
            // CONCAT @ idx 82: shared polymorphic concat body
            instrIdx = instrIdx + 29   // advance from 53 by 29 to reach 82
            s = sbAppend(s, emitPolyConcat(instrIdx, textVaddr, textOff))  // emits 111 instr
            instrIdx = instrIdx + 111
            // ADD_DONE @ idx 193
        } else if opTok == "CAT" {
            // String concatenation IR op — compile.k emits this for known
            // string contexts (backtick interpolation, etc.). Body is the same
            // polymorphic concat as ADD's else branch. 113 instructions.
            s = sbAppend(s, arm64_pop(6))  // 0: b
            s = sbAppend(s, arm64_pop(3))  // 1: a
            instrIdx = instrIdx + 2
            s = sbAppend(s, emitPolyConcat(instrIdx, textVaddr, textOff))
            instrIdx = instrIdx + 111
        } else if opTok == "SUB" {
            s = sbAppend(s, arm64_pop(0))
            s = sbAppend(s, arm64_pop(1))
            s = sbAppend(s, arm64_sub_xxx(0, 1, 0))
            s = sbAppend(s, arm64_push(0))
            instrIdx = instrIdx + 4
        } else if opTok == "MUL" {
            s = sbAppend(s, arm64_pop(0))
            s = sbAppend(s, arm64_pop(1))
            s = sbAppend(s, arm64_mul_xxx(0, 1, 0))
            s = sbAppend(s, arm64_push(0))
            instrIdx = instrIdx + 4
        } else if opTok == "DIV" {
            s = sbAppend(s, arm64_pop(0))
            s = sbAppend(s, arm64_pop(1))
            s = sbAppend(s, arm64_sdiv_xxx(0, 1, 0))
            s = sbAppend(s, arm64_push(0))
            instrIdx = instrIdx + 4
        } else if opTok == "MOD" {
            s = sbAppend(s, arm64_pop(0))
            s = sbAppend(s, arm64_pop(1))
            s = sbAppend(s, arm64_sdiv_xxx(2, 1, 0))
            s = sbAppend(s, arm64_msub_xxxx(0, 2, 0, 1))
            s = sbAppend(s, arm64_push(0))
            instrIdx = instrIdx + 5
        } else if opTok == "BUILTIN_EXIT" {
            // exit(code): the arg is a STRING ("1"), so atoi it before the
            // exit syscall. Popping the pointer straight into x0 (old behavior)
            // passed a heap pointer as the code -> bogus 71. 13 instr.
            //   0:pop x6=str  1:x0=0(acc)  2:x8=10
            //   3(LOOP):ldrb post w7,[x6]  4:cbz w7 DONE(+5)
            //   5:sub w7,#48  6:x0*=10  7:x0+=w7  8:b LOOP(-5)
            //   9(DONE):x16=1  10:svc  11:dead movz  12:dead push
            s = sbAppend(s, arm64_pop(6))
            s = sbAppend(s, arm64_movz_x_imm(0, 0))
            s = sbAppend(s, arm64_movz_x_imm(8, 10))
            s = sbAppend(s, arm64_ldrb_post(7, 6, 1))
            s = sbAppend(s, arm64_cbz(7, 5))
            s = sbAppend(s, arm64_sub_imm(7, 7, 48))
            s = sbAppend(s, arm64_mul_xxx(0, 0, 8))
            s = sbAppend(s, arm64_add_xxx(0, 0, 7))
            s = sbAppend(s, arm64_b(0 - 5))
            s = sbAppend(s, arm64_movz_x_imm(16, 1))
            s = sbAppend(s, arm64_svc(0x80))
            s = sbAppend(s, arm64_movz_w_imm(0, 0))
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 13
        } else if opTok == "LT" || opTok == "GT" || opTok == "LE" || opTok == "GE" {
            // Polymorphic ordering. int/mixed → raw value cmp (old behavior);
            // ptr+ptr (strings) → byte-by-byte strcmp ordering (NUL = least), so
            // `c >= "a"` etc. work — compile.k's tokenizer (charIsAlpha) depends
            // on this. Was int-only (compared heap pointers for strings → garbage,
            // which broke the native self-host: tokenizer dropped identifiers). 19 instr.
            let cnd = irCmpToCond(opTok)
            s = sbAppend(s, arm64_pop(4))                 // 0: b
            s = sbAppend(s, arm64_pop(3))                 // 1: a
            s = sbAppend(s, arm64_movz_x_imm_lsl32(14, 1))// 2: threshold 0
            s = sbAppend(s, arm64_cmp_xx(3, 14))          // 3
            s = sbAppend(s, arm64_b_cond(0xb, 12))        // 4: b.lt RAW(16) — a is int
            s = sbAppend(s, arm64_cmp_xx(4, 14))          // 5
            s = sbAppend(s, arm64_b_cond(0xb, 10))        // 6: b.lt RAW(16) — b is int (mixed)
            s = sbAppend(s, arm64_mov_xx(5, 3))           // 7: pa
            s = sbAppend(s, arm64_mov_xx(6, 4))           // 8: pb
            s = sbAppend(s, arm64_ldrb_post(7, 5, 1))     // 9: SLOOP  w7=*pa++
            s = sbAppend(s, arm64_ldrb_post(8, 6, 1))     // 10: w8=*pb++
            s = sbAppend(s, arm64_cmp_xx(7, 8))           // 11
            s = sbAppend(s, arm64_b_cond(0x1, 2))         // 12: b.ne SDONE(14)
            s = sbAppend(s, arm64_cbnz(7, 0 - 4))         // 13: w7!=0 → SLOOP(9); NUL falls to SDONE
            s = sbAppend(s, arm64_cset(0, cnd))           // 14: SDONE — flags hold deciding bytes (or equal)
            s = sbAppend(s, arm64_b(3))                   // 15: → PUSH(18)
            s = sbAppend(s, arm64_cmp_xx(3, 4))           // 16: RAW — raw value cmp
            s = sbAppend(s, arm64_cset(0, cnd))           // 17
            s = sbAppend(s, arm64_push(0))                // 18: PUSH
            instrIdx = instrIdx + 19
        } else if opTok == "EQ" || opTok == "NE" {
            // Polymorphic equality: int+int → cmp; ptr+ptr → strcmp byte-by-byte;
            // mixed (int vs ptr) → always unequal. The opTok-driven branches pick
            // EQ-cond (0x0) vs NE-cond (0x1) so the same code emits both flavors.
            // 25 instructions for either EQ or NE.
            let eqCond = 0x0   // cond for cset (default EQ)
            let unequalResult = 0    // mismatch path result for EQ
            let equalResult = 1      // match path result for EQ
            if opTok == "NE" {
                eqCond = 0x1
                unequalResult = 1
                equalResult = 0
            }
            s = sbAppend(s, arm64_pop(4))  // 0: b
            s = sbAppend(s, arm64_pop(3))  // 1: a
            s = sbAppend(s, arm64_movz_x_imm_lsl32(14, 1))  // 2: threshold
            s = sbAppend(s, arm64_cmp_xx(3, 14))  // 3
            s = sbAppend(s, arm64_b_cond(0xa, 6))  // 4: b.ge PTR_PATH (idx 10)
            // INT path — a is int. Check b.
            s = sbAppend(s, arm64_cmp_xx(4, 14))  // 5
            s = sbAppend(s, arm64_b_cond(0xa, 16))  // 6: b.ge UNEQUAL (idx 22)
            // Both int — direct cmp + cset
            s = sbAppend(s, arm64_cmp_xx(3, 4))  // 7
            s = sbAppend(s, arm64_cset(0, eqCond))  // 8: x0 = (a cmp b)
            s = sbAppend(s, arm64_b(15))  // 9: → PUSH (idx 24)
            // PTR_PATH @ 10:
            s = sbAppend(s, arm64_cmp_xx(4, 14))  // 10
            s = sbAppend(s, arm64_b_cond(0xb, 11))  // 11: b.lt UNEQUAL (idx 22) — b is int, mixed
            // Both ptr — strcmp inline
            s = sbAppend(s, arm64_mov_xx(5, 3))  // 12: pa
            s = sbAppend(s, arm64_mov_xx(6, 4))  // 13: pb
            // STRCMP_LOOP @ 14:
            s = sbAppend(s, arm64_ldrb_post(7, 5, 1))  // 14
            s = sbAppend(s, arm64_ldrb_post(8, 6, 1))  // 15
            s = sbAppend(s, arm64_cmp_xx(7, 8))  // 16
            s = sbAppend(s, arm64_b_cond(0x1, 5))  // 17: b.ne UNEQUAL (idx 22, rel +5)
            s = sbAppend(s, arm64_cbz(7, 2))  // 18: w7 NUL → EQUAL (idx 20, rel +2)
            s = sbAppend(s, arm64_b(0 - 5))  // 19: → STRCMP_LOOP
            // EQUAL @ 20:
            s = sbAppend(s, arm64_movz_x_imm(0, equalResult))  // 20
            s = sbAppend(s, arm64_b(3))  // 21: → PUSH (idx 24, rel +3)
            // UNEQUAL @ 22:
            s = sbAppend(s, arm64_movz_x_imm(0, unequalResult))  // 22
            s = sbAppend(s, arm64_nop())  // 23: pad (so PUSH always at idx 24)
            // PUSH @ 24:
            s = sbAppend(s, arm64_push_x0())  // 24
            instrIdx = instrIdx + 25
        } else if opTok == "LABEL" {
            // No instructions
        } else if opTok == "JUMP" {
            let target = findLabel(labels, restTok)
            let delta = target - instrIdx
            s = sbAppend(s, arm64_b(delta))
            instrIdx = instrIdx + 1
        } else if opTok == "JUMPIFNOT" {
            s = sbAppend(s, arm64_pop_x0())
            instrIdx = instrIdx + 1
            let target = findLabel(labels, restTok)
            s = sbAppend(s, arm64_cbnz(0, 2))
            instrIdx = instrIdx + 1
            s = sbAppend(s, arm64_b(target - instrIdx))
            instrIdx = instrIdx + 1
        } else if opTok == "JUMPIF" {
            s = sbAppend(s, arm64_pop_x0())
            instrIdx = instrIdx + 1
            let target = findLabel(labels, restTok)
            s = sbAppend(s, arm64_cbz(0, 2))
            instrIdx = instrIdx + 1
            s = sbAppend(s, arm64_b(target - instrIdx))
            instrIdx = instrIdx + 1
        } else if opTok == "NEG" {
            s = sbAppend(s, arm64_pop_x0())
            s = sbAppend(s, arm64_sub_xxx(0, 31, 0))  // sub x0, xzr, x0  (negate)
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 3
        } else if opTok == "NOT" {
            s = sbAppend(s, arm64_pop_x0())
            s = sbAppend(s, arm64_cmp_imm(0, 0))  // cmp x0, #0
            s = sbAppend(s, arm64_cset(0, 0x0))  // x0 = (x0 == 0) ? 1 : 0
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 4
        } else if opTok == "BUILTIN_LEN" {
            // len(s): pop string ptr, compute strlen inline, push int.
            //   mov  x1, x0           ; saved start
            //   ldrb w2, [x0], #1     ; load byte, post-inc
            //   cbnz w2, prev         ; loop back to ldrb if non-zero
            //   sub  x0, x0, x1       ; end - start
            //   sub  x0, x0, #1       ; subtract the NUL we counted past
            s = sbAppend(s, arm64_pop_x0())
            s = sbAppend(s, arm64_mov_xx(1, 0))
            s = sbAppend(s, arm64_ldrb_post(2, 0, 1))
            s = sbAppend(s, arm64_cbnz(2, 0 - 1))  // back 1 instruction (to ldrb)
            s = sbAppend(s, arm64_sub_xxx(0, 0, 1))
            s = sbAppend(s, arm64_sub_imm(0, 0, 1))
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 7
        } else if opTok == "BUILTIN_CHARCODE" {
            // charCode(s): pop string ptr, ldrb first byte, push as int.
            s = sbAppend(s, arm64_pop_x0())
            s = sbAppend(s, arm64_ldrb_zero(0, 0))  // ldrb w0, [x0]
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 3
        } else if opTok == "INDEX" {
            // s[i]: pop i (x3), pop s (x4), alloc 2 bytes (→ x0), copy s[i], NUL, push x0.
            s = sbAppend(s, arm64_pop(3))  // x3 = i
            s = sbAppend(s, arm64_pop(4))  // x4 = s
            instrIdx = instrIdx + 2
            s = sbAppend(s, emitAllocN(2, instrIdx, textVaddr, textOff))
            instrIdx = instrIdx + 21
            s = sbAppend(s, arm64_ldrb_reg(5, 4, 3))  // ldrb w5, [x4, x3]
            s = sbAppend(s, arm64_strb_imm(5, 0, 0))  // strb w5, [x0]
            s = sbAppend(s, arm64_strb_imm(31, 0, 1))  // strb wzr, [x0, #1]
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 4
        } else if opTok == "BUILTIN_SUBSTRING" {
            // substring(s, start, end): args on eval stack — TOS = end.
            s = sbAppend(s, arm64_pop(6))  // x6 = end
            s = sbAppend(s, arm64_pop(7))  // x7 = start
            s = sbAppend(s, arm64_pop(8))  // x8 = s
            s = sbAppend(s, arm64_sub_xxx(4, 6, 7))  // x4 = end - start (len_data)
            s = sbAppend(s, arm64_add_imm(4, 4, 1))  // x4 = len_data + 1 (alloc room for NUL)
            instrIdx = instrIdx + 5
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))
            instrIdx = instrIdx + 21
            s = sbAppend(s, arm64_add_xxx(9, 8, 7))  // x9 = src = s + start
            s = sbAppend(s, arm64_movz_x_imm(5, 0))  // x5 = i = 0
            s = sbAppend(s, arm64_sub_imm(4, 4, 1))  // x4 = len_data
            s = sbAppend(s, arm64_cmp_xx(5, 4))  // cmp i, len_data
            s = sbAppend(s, arm64_b_cond(0xa, 5))  // b.ge done (+5: ldrb,strb,add,b,strb_NUL)
            s = sbAppend(s, arm64_ldrb_reg(10, 9, 5))  // ldrb w10, [x9, x5]
            s = sbAppend(s, arm64_strb_reg(10, 0, 5))  // strb w10, [x0, x5]
            s = sbAppend(s, arm64_add_imm(5, 5, 1))  // i++
            s = sbAppend(s, arm64_b(0 - 5))  // back to cmp
            s = sbAppend(s, arm64_strb_reg(31, 0, 4))  // strb wzr, [x0, x4] (NUL terminator)
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 11
        } else if opTok == "BUILTIN_STARTSWITH" {
            // startsWith(s, prefix): returns 1 if s starts with prefix, 0 otherwise.
            // Stack TOS = prefix, then s.
            s = sbAppend(s, arm64_pop(6))  // x6 = prefix
            s = sbAppend(s, arm64_pop(7))  // x7 = s
            s = sbAppend(s, arm64_movz_x_imm(5, 0))  // i = 0
            // LOOP_HEAD (instr 3 within op):
            s = sbAppend(s, arm64_ldrb_reg(8, 6, 5))  // w8 = prefix[i]
            s = sbAppend(s, arm64_cbz(8, 8))  // if prefix[i]==0 → SUCCESS at instr 12 (+8)
            s = sbAppend(s, arm64_ldrb_reg(9, 7, 5))  // w9 = s[i]
            s = sbAppend(s, arm64_cmp_xx(8, 9))
            s = sbAppend(s, arm64_b_cond(0x1, 3))  // b.ne FAIL at instr 10 (+3)
            s = sbAppend(s, arm64_add_imm(5, 5, 1))  // i++
            s = sbAppend(s, arm64_b(0 - 6))  // back to LOOP_HEAD
            // FAIL (after the back-jump, +1):
            s = sbAppend(s, arm64_movz_x_imm(0, 0))
            s = sbAppend(s, arm64_b(2))  // skip success branch (+2 to push)
            // SUCCESS:
            s = sbAppend(s, arm64_movz_x_imm(0, 1))
            // END:
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 14
        } else if opTok == "BUILTIN_ISDIGIT" {
            // isDigit(s): returns 1 if s[0] is '0'..'9', 0 otherwise.
            s = sbAppend(s, arm64_pop(6))  // x6 = s
            s = sbAppend(s, arm64_ldrb_zero(0, 6))  // w0 = s[0]
            s = sbAppend(s, arm64_cmp_imm(0, 48))  // '0'
            s = sbAppend(s, arm64_b_cond(0xb, 5))  // b.lt notdigit (+5)
            s = sbAppend(s, arm64_cmp_imm(0, 57))  // '9'
            s = sbAppend(s, arm64_b_cond(0xc, 3))  // b.gt notdigit (+3)
            s = sbAppend(s, arm64_movz_x_imm(0, 1))  // yes
            s = sbAppend(s, arm64_b(2))  // skip notdigit
            // NOTDIGIT:
            s = sbAppend(s, arm64_movz_x_imm(0, 0))
            // END:
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 10
        } else if opTok == "BUILTIN_TOINT" {
            // toInt(s): parse a signed decimal string → int. 30 instructions.
            // If arg is already an int (< 0), return as-is. Otherwise
            // parse, honoring a leading '-' (KIR encodes large/negative constants
            // like 0xfeedfacf as the signed value -17958193, so the sign MUST be
            // handled or self-compile mis-encodes every such PUSH_INT).
            // Regs: x7=s x0=result x4=10 x8=neg x5=i x6=char x9=scratch
            s = sbAppend(s, arm64_pop(7))  // 0
            s = sbAppend(s, arm64_movz_x_imm_lsl32(3, 1))  // 1: x3 = 0
            s = sbAppend(s, arm64_cmp_xx(7, 3))  // 2
            s = sbAppend(s, arm64_b_cond(0x3, 25))  // 3: b.lo INT_MOV@28
            s = sbAppend(s, arm64_movz_x_imm(0, 0))  // 4: result = 0
            s = sbAppend(s, arm64_movz_x_imm(4, 10))  // 5: ten
            s = sbAppend(s, arm64_movz_x_imm(8, 0))  // 6: neg = 0
            s = sbAppend(s, arm64_movz_x_imm(5, 0))  // 7: i = 0
            s = sbAppend(s, arm64_ldrb_reg(6, 7, 5))  // 8: c = s[0]
            s = sbAppend(s, arm64_cmp_imm(6, 0x2D))  // 9: '-' ?
            s = sbAppend(s, arm64_b_cond(0x1, 3))  // 10: b.ne LOOP@13
            s = sbAppend(s, arm64_movz_x_imm(8, 1))  // 11: neg = 1
            s = sbAppend(s, arm64_add_imm(5, 5, 1))  // 12: skip '-'
            // LOOP @13:
            s = sbAppend(s, arm64_ldrb_reg(6, 7, 5))  // 13
            s = sbAppend(s, arm64_cbz(6, 10))  // 14: → DONE@24
            s = sbAppend(s, arm64_cmp_imm(6, 48))  // 15
            s = sbAppend(s, arm64_b_cond(0xb, 8))  // 16: b.lt → DONE@24
            s = sbAppend(s, arm64_cmp_imm(6, 57))  // 17
            s = sbAppend(s, arm64_b_cond(0xc, 6))  // 18: b.gt → DONE@24
            s = sbAppend(s, arm64_sub_imm(6, 6, 48))  // 19
            s = sbAppend(s, arm64_mul_xxx(0, 0, 4))  // 20
            s = sbAppend(s, arm64_add_xxx(0, 0, 6))  // 21
            s = sbAppend(s, arm64_add_imm(5, 5, 1))  // 22
            s = sbAppend(s, arm64_b(0 - 10))  // 23: → LOOP@13
            // DONE @24: apply sign
            s = sbAppend(s, arm64_cbz(8, 2))  // 24: neg==0 → PUSH@26
            s = sbAppend(s, arm64_sub_xxx(0, 31, 0))  // 25: x0 = -x0
            // PUSH @26:
            s = sbAppend(s, arm64_push_x0())  // 26
            s = sbAppend(s, arm64_b(3))  // 27: → END@30
            // INT_MOV @28:
            s = sbAppend(s, arm64_mov_xx(0, 7))  // 28
            s = sbAppend(s, arm64_push_x0())  // 29
            // END @30
            instrIdx = instrIdx + 30
        } else if opTok == "BUILTIN_SBNEW" {
            // sbNew(): a STABLE handle pointing at a growable buffer.
            //   handle (16 B): [+0] = current buffer pointer
            //   buffer:        [+0]=cap  [+8]=len  [+16..]=data
            // sbAppend updates handle[+0] on realloc, so the handle address never
            // moves — callers may use `sbAppend(h, x)` without reassigning h. This
            // matters because the bump allocator never frees: a small (256 B) start
            // keeps the many tiny builders cheap while big ones grow by doubling.
            // 52 instructions.
            s = sbAppend(s, arm64_movz_x_imm(4, 16))  // 0: handle size
            instrIdx = instrIdx + 1
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))  // 1-21: x0 = handle
            instrIdx = instrIdx + 21
            s = sbAppend(s, arm64_mov_xx(10, 0))  // 22: x10 = handle (survives next alloc)
            s = sbAppend(s, arm64_movz_x_imm(4, 256))  // 23: buffer size
            instrIdx = instrIdx + 2
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))  // 24-44: x0 = buffer
            instrIdx = instrIdx + 21
            s = sbAppend(s, arm64_sub_imm(5, 4, 16))  // 45: cap = 256-16
            s = sbAppend(s, arm64_str_imm(5, 0, 0))  // 46: buf.cap
            s = sbAppend(s, arm64_str_imm(31, 0, 1))  // 47: buf.len = 0
            s = sbAppend(s, arm64_strb_imm(31, 0, 16))  // 48: data[0] = NUL
            s = sbAppend(s, arm64_str_imm(0, 10, 0))  // 49: handle.buf = buffer
            s = sbAppend(s, arm64_mov_xx(0, 10))  // 50: return handle
            s = sbAppend(s, arm64_push_x0())  // 51
            instrIdx = instrIdx + 7
        } else if opTok == "BUILTIN_SBAPPEND" {
            // sbAppend(handle, str): append str to the handle's buffer, growing it
            // (doubling) if needed; on realloc, update handle[+0] so the handle
            // stays valid. Returns handle. 84 instructions.
            // Regs: x6=str x7=handle x9=buf x4=cap x12=len x5=strlen x8=writepos
            //       x10=loopidx x11=byte/newdata x13=needed x3=oldbuf
            s = sbAppend(s, arm64_pop(6))  // 0: str
            s = sbAppend(s, arm64_pop(7))  // 1: handle
            s = sbAppend(s, arm64_ldr_imm(9, 7, 0))  // 2: x9 = buffer
            s = sbAppend(s, arm64_ldr_imm(4, 9, 0))  // 3: cap
            s = sbAppend(s, arm64_ldr_imm(12, 9, 1))  // 4: len
            s = sbAppend(s, arm64_movz_x_imm(5, 0))  // 5: strlen idx
            // STRLEN_LOOP @6:
            s = sbAppend(s, arm64_ldrb_reg(11, 6, 5))  // 6
            s = sbAppend(s, arm64_cbz(11, 3))  // 7: → @10
            s = sbAppend(s, arm64_add_imm(5, 5, 1))  // 8
            s = sbAppend(s, arm64_b(0 - 3))  // 9: → @6
            instrIdx = instrIdx + 10
            // DONE_STRLEN @10:
            s = sbAppend(s, arm64_add_xxx(13, 12, 5))  // 10: needed = len+strlen
            s = sbAppend(s, arm64_add_imm(13, 13, 1))  // 11: +NUL
            s = sbAppend(s, arm64_cmp_xx(13, 4))  // 12
            s = sbAppend(s, arm64_b_cond(0x8, 15))  // 13: b.hi → REALLOC @28
            // FAST @14:
            s = sbAppend(s, arm64_add_imm(8, 9, 16))  // 14: data start
            s = sbAppend(s, arm64_add_xxx(8, 8, 12))  // 15: write pos
            s = sbAppend(s, arm64_movz_x_imm(10, 0))  // 16: j=0
            // COPY @17:
            s = sbAppend(s, arm64_cmp_xx(10, 5))  // 17
            s = sbAppend(s, arm64_b_cond(0xa, 5))  // 18: b.ge → @23
            s = sbAppend(s, arm64_ldrb_reg(11, 6, 10))  // 19
            s = sbAppend(s, arm64_strb_reg(11, 8, 10))  // 20
            s = sbAppend(s, arm64_add_imm(10, 10, 1))  // 21
            s = sbAppend(s, arm64_b(0 - 5))  // 22: → @17
            // POST @23:
            s = sbAppend(s, arm64_add_xxx(12, 12, 5))  // 23: new len
            s = sbAppend(s, arm64_str_imm(12, 9, 1))  // 24: buf.len
            s = sbAppend(s, arm64_strb_reg(31, 8, 5))  // 25: NUL
            s = sbAppend(s, arm64_push(7))  // 26: return handle
            s = sbAppend(s, arm64_b(57))  // 27: → END @84
            instrIdx = instrIdx + 18
            // REALLOC @28:
            s = sbAppend(s, arm64_sub_imm(31, 31, 16))  // 28: reserve scratch
            s = sbAppend(s, arm64_str_imm(5, 31, 0))  // 29: save strlen
            s = sbAppend(s, arm64_str_imm(9, 31, 1))  // 30: save old buffer
            s = sbAppend(s, arm64_add_xxx(4, 4, 4))  // 31: 2*cap
            s = sbAppend(s, arm64_add_xxx(4, 4, 5))  // 32: +strlen
            s = sbAppend(s, arm64_add_imm(4, 4, 17))  // 33: +17
            instrIdx = instrIdx + 6
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))  // 34-54: x0 = new buffer
            instrIdx = instrIdx + 21
            s = sbAppend(s, arm64_ldr_imm(5, 31, 0))  // 55: restore strlen
            s = sbAppend(s, arm64_ldr_imm(3, 31, 1))  // 56: x3 = old buffer
            s = sbAppend(s, arm64_add_imm(31, 31, 16))  // 57: release scratch
            s = sbAppend(s, arm64_sub_imm(4, 4, 16))  // 58: new cap
            s = sbAppend(s, arm64_str_imm(4, 0, 0))  // 59: newbuf.cap
            s = sbAppend(s, arm64_str_imm(12, 0, 1))  // 60: newbuf.len = old len
            s = sbAppend(s, arm64_add_imm(11, 0, 16))  // 61: new data dest
            s = sbAppend(s, arm64_add_imm(3, 3, 16))  // 62: old data src
            s = sbAppend(s, arm64_movz_x_imm(10, 0))  // 63: k=0
            instrIdx = instrIdx + 9
            // OLDCOPY @64:
            s = sbAppend(s, arm64_cmp_xx(10, 12))  // 64
            s = sbAppend(s, arm64_b_cond(0xa, 5))  // 65: b.ge → @70
            s = sbAppend(s, arm64_ldrb_reg(9, 3, 10))  // 66
            s = sbAppend(s, arm64_strb_reg(9, 11, 10))  // 67
            s = sbAppend(s, arm64_add_imm(10, 10, 1))  // 68
            s = sbAppend(s, arm64_b(0 - 5))  // 69: → @64
            // OLDCOPY_DONE @70:
            s = sbAppend(s, arm64_str_imm(0, 7, 0))  // 70: handle.buf = new buffer
            s = sbAppend(s, arm64_add_imm(8, 0, 16))  // 71: data
            s = sbAppend(s, arm64_add_xxx(8, 8, 12))  // 72: write pos
            s = sbAppend(s, arm64_movz_x_imm(10, 0))  // 73: j=0
            instrIdx = instrIdx + 10
            // NEWCOPY @74:
            s = sbAppend(s, arm64_cmp_xx(10, 5))  // 74
            s = sbAppend(s, arm64_b_cond(0xa, 5))  // 75: b.ge → @80
            s = sbAppend(s, arm64_ldrb_reg(9, 6, 10))  // 76
            s = sbAppend(s, arm64_strb_reg(9, 8, 10))  // 77
            s = sbAppend(s, arm64_add_imm(10, 10, 1))  // 78
            s = sbAppend(s, arm64_b(0 - 5))  // 79: → @74
            // POST_NEW @80:
            s = sbAppend(s, arm64_add_xxx(12, 12, 5))  // 80: new len
            s = sbAppend(s, arm64_str_imm(12, 0, 1))  // 81: newbuf.len
            s = sbAppend(s, arm64_strb_reg(31, 8, 5))  // 82: NUL
            s = sbAppend(s, arm64_push(7))  // 83: return handle
            instrIdx = instrIdx + 10
            // END @84
        } else if opTok == "BUILTIN_SBTOSTRING" {
            // sbToString(handle): return data ptr = handle.buf + 16. 4 instructions.
            s = sbAppend(s, arm64_pop(7))  // 0: handle
            s = sbAppend(s, arm64_ldr_imm(0, 7, 0))  // 1: buffer
            s = sbAppend(s, arm64_add_imm(0, 0, 16))  // 2: data
            s = sbAppend(s, arm64_push_x0())  // 3
            instrIdx = instrIdx + 4
        } else if opTok == "BUILTIN_CONTAINS" {
            // contains(s, sub): same logic as indexOf but returns bool (1 / 0).
            // 23 instructions. Stack TOS = sub, then s.
            // Layout: indexOf core (instrs 0..19) computes idx in x0 (or -1).
            // Then cmp x0, #0; cset x0, ge; push x0.
            //
            // The core exactly mirrors INDEXOF's emit BUT we drop the final push
            // and replace mov_xx (FOUND case) and movn (NOT_FOUND) with x0
            // setting = idx or -1 — then the final cmp/cset converts to bool.
            //   0:pop sub  1:pop s  2:movz x5
            //   3:ldrb s[i]  4:cbz→NOT_FOUND(+15)  5:movz j
            //   6:ldrb sub[j]  7:cbz→FOUND(+10)  8:add x10  9:ldrb s[i+j]  10:cbz→NOT_FOUND(+9)
            //   11:cmp  12:b.ne→NEXT_OUTER(+3)  13:add j++  14:b INNER(-8)
            //   15:add i++ (NEXT_OUTER)  16:b OUTER(-13)
            //   17:mov x0,x5 (FOUND)  18:b CONV(+2)
            //   19:movn x0 (NOT_FOUND)
            //   20 (CONV): cmp x0, #0  21:cset x0, ge  22:push x0
            s = sbAppend(s, arm64_pop(6))
            s = sbAppend(s, arm64_pop(7))
            s = sbAppend(s, arm64_movz_x_imm(5, 0))
            s = sbAppend(s, arm64_ldrb_reg(8, 7, 5))
            s = sbAppend(s, arm64_cbz(8, 15))
            s = sbAppend(s, arm64_movz_x_imm(4, 0))
            s = sbAppend(s, arm64_ldrb_reg(9, 6, 4))
            s = sbAppend(s, arm64_cbz(9, 10))
            s = sbAppend(s, arm64_add_xxx(10, 5, 4))
            s = sbAppend(s, arm64_ldrb_reg(11, 7, 10))
            s = sbAppend(s, arm64_cbz(11, 9))
            s = sbAppend(s, arm64_cmp_xx(9, 11))
            s = sbAppend(s, arm64_b_cond(0x1, 3))
            s = sbAppend(s, arm64_add_imm(4, 4, 1))
            s = sbAppend(s, arm64_b(0 - 8))
            s = sbAppend(s, arm64_add_imm(5, 5, 1))
            s = sbAppend(s, arm64_b(0 - 13))
            s = sbAppend(s, arm64_mov_xx(0, 5))
            s = sbAppend(s, arm64_b(2))
            s = sbAppend(s, arm64_movn_x_imm(0, 0))
            s = sbAppend(s, arm64_cmp_imm(0, 0))
            s = sbAppend(s, arm64_cset(0, 0xa))  // x0 = (x0 >= 0) ? 1 : 0
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 23
        } else if opTok == "BUILTIN_PRINT" {
            // print(v): write v to stdout. Handles strings and ints (no newline).
            // Dispatch: if v < 0 it's an int; else a pointer.
            // String path = 10 instr, int path = itoa + write. 52 total.
            s = sbAppend(s, arm64_pop(3))  // 0: x3 = arg
            s = sbAppend(s, arm64_movz_x_imm_lsl32(14, 1))  // 1: x14 = 1<<32
            s = sbAppend(s, arm64_cmp_xx(3, 14))  // 2
            s = sbAppend(s, arm64_b_cond(0xb, 11))  // 3: b.lt INT_PATH (idx 14)
            // ── STRING PATH (idx 4..13) ──
            s = sbAppend(s, arm64_mov_xx(1, 3))  // 4
            s = sbAppend(s, arm64_ldrb_post(4, 1, 1))  // 5
            s = sbAppend(s, arm64_cbnz(4, 0 - 1))  // 6: scan NUL
            s = sbAppend(s, arm64_sub_xxx(2, 1, 3))  // 7
            s = sbAppend(s, arm64_sub_imm(2, 2, 1))  // 8: len
            s = sbAppend(s, arm64_movz_x_imm(0, 1))  // 9: stdout
            s = sbAppend(s, arm64_mov_xx(1, 3))  // 10
            s = sbAppend(s, arm64_movz_x_imm(16, 4))  // 11: SYS_write
            s = sbAppend(s, arm64_svc(0x80))  // 12
            s = sbAppend(s, arm64_b(37))  // 13: → DONE (idx 50)
            // ── INT PATH @ idx 14 ── itoa to stack buffer, then write ──
            s = sbAppend(s, arm64_sub_imm(31, 31, 32))  // 14: alloc buf
            s = sbAppend(s, arm64_add_imm(4, 31, 23))  // 15: x4 = sp+23 (end)
            s = sbAppend(s, arm64_strb_imm(31, 4, 0))  // 16: *p = NUL (xzr)
            s = sbAppend(s, arm64_movz_x_imm(5, 0))  // 17: neg = 0
            s = sbAppend(s, arm64_cmp_imm(3, 0))  // 18: cmp n, 0
            s = sbAppend(s, arm64_b_cond(0xa, 3))  // 19: b.ge POSITIVE (idx 22)
            s = sbAppend(s, arm64_movz_x_imm(5, 1))  // 20: neg = 1
            s = sbAppend(s, arm64_neg(3, 3))  // 21: n = -n
            // POSITIVE @ idx 22:
            s = sbAppend(s, arm64_cbnz(3, 5))  // 22: → INT_LOOP (idx 27)
            // n == 0: write '0'
            s = sbAppend(s, arm64_sub_imm(4, 4, 1))  // 23
            s = sbAppend(s, arm64_movz_w_imm(6, 0x30))  // 24: '0'
            s = sbAppend(s, arm64_strb_imm(6, 4, 0))  // 25
            s = sbAppend(s, arm64_b(10))  // 26: → INT_SIGN (idx 36)
            // INT_LOOP @ idx 27:
            s = sbAppend(s, arm64_cbz(3, 9))  // 27: → INT_SIGN (idx 36)
            s = sbAppend(s, arm64_movz_x_imm(7, 10))  // 28
            s = sbAppend(s, arm64_udiv_xxx(8, 3, 7))  // 29: q = n / 10
            s = sbAppend(s, arm64_msub_xxxx(9, 8, 7, 3))  // 30: r = n - q*10
            s = sbAppend(s, arm64_add_imm(9, 9, 0x30))  // 31: r += '0'
            s = sbAppend(s, arm64_sub_imm(4, 4, 1))  // 32
            s = sbAppend(s, arm64_strb_imm(9, 4, 0))  // 33
            s = sbAppend(s, arm64_mov_xx(3, 8))  // 34: n = q
            s = sbAppend(s, arm64_b(0 - 8))  // 35: → INT_LOOP
            // INT_SIGN @ idx 36:
            s = sbAppend(s, arm64_cbz(5, 4))  // 36: → INT_PRINT (idx 40)
            s = sbAppend(s, arm64_sub_imm(4, 4, 1))  // 37
            s = sbAppend(s, arm64_movz_w_imm(6, 0x2D))  // 38: '-'
            s = sbAppend(s, arm64_strb_imm(6, 4, 0))  // 39
            // INT_PRINT @ idx 40:
            s = sbAppend(s, arm64_mov_xx(1, 4))  // 40: scan from buf start
            s = sbAppend(s, arm64_ldrb_post(6, 1, 1))  // 41
            s = sbAppend(s, arm64_cbnz(6, 0 - 1))  // 42: scan to NUL
            s = sbAppend(s, arm64_sub_xxx(2, 1, 4))  // 43
            s = sbAppend(s, arm64_sub_imm(2, 2, 1))  // 44: real len
            s = sbAppend(s, arm64_movz_x_imm(0, 1))  // 45: stdout
            s = sbAppend(s, arm64_mov_xx(1, 4))  // 46
            s = sbAppend(s, arm64_movz_x_imm(16, 4))  // 47
            s = sbAppend(s, arm64_svc(0x80))  // 48: write digits
            s = sbAppend(s, arm64_add_imm(31, 31, 32))  // 49: restore sp
            // DONE @ idx 50:
            s = sbAppend(s, arm64_movz_w_imm(0, 0))  // 50
            s = sbAppend(s, arm64_push_x0())  // 51
            instrIdx = instrIdx + 52
        } else if opTok == "BUILTIN_POW" {
            // pow(b, e): result = b^e (signed int). 8 instructions. TOS = e.
            //   0:pop x4=e  1:pop x5=b  2:movz x0=1
            //   3:cbz x4→DONE(+4)  4:mul x0,x0,x5  5:sub x4,x4,#1  6:b LOOP(-3)
            //   7:push x0
            s = sbAppend(s, arm64_pop(4))
            s = sbAppend(s, arm64_pop(5))
            s = sbAppend(s, arm64_movz_x_imm(0, 1))
            s = sbAppend(s, arm64_cbz(4, 4))
            s = sbAppend(s, arm64_mul_xxx(0, 0, 5))
            s = sbAppend(s, arm64_sub_imm(4, 4, 1))
            s = sbAppend(s, arm64_b(0 - 3))
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 8
        } else if opTok == "BUILTIN_ENDSWITH" {
            // endsWith(s, suffix): 29 instructions. TOS = suffix.
            // strlen both, check if len_p > len_s (→ 0), else compare last len_p bytes.
            //   0:pop x6=suffix  1:pop x7=s
            //   2:mov x8=x6  3:ldrb post (PLOOP)  4:cbnz back(-1)
            //   5:sub x4=x8-x6  6:sub x4,#1   ; len_p in x4
            //   7:mov x8=x7  8:ldrb post (SLOOP)  9:cbnz back(-1)
            //   10:sub x5=x8-x7  11:sub x5,#1  ; len_s in x5
            //   12:cmp x4, x5  13:b.gt FAIL(+14)
            //   14:sub x10=x5-x4  ; start
            //   15:movz x9=0  ; i
            //   16:cmp x9, x4 (CLOOP)  17:b.ge SUCCESS(+8)
            //   18:add x11=x10+x9  19:ldrb w12=s[x11]  20:ldrb w13=suffix[x9]  21:cmp x12,x13  22:b.ne FAIL(+5)
            //   23:add x9,#1  24:b CLOOP(-8)
            //   25:movz x0=1 (SUCCESS)  26:b END(+2)
            //   27:movz x0=0 (FAIL)
            //   28:push (END)
            s = sbAppend(s, arm64_pop(6))
            s = sbAppend(s, arm64_pop(7))
            s = sbAppend(s, arm64_mov_xx(8, 6))
            s = sbAppend(s, arm64_ldrb_post(9, 8, 1))
            s = sbAppend(s, arm64_cbnz(9, 0 - 1))
            s = sbAppend(s, arm64_sub_xxx(4, 8, 6))
            s = sbAppend(s, arm64_sub_imm(4, 4, 1))
            s = sbAppend(s, arm64_mov_xx(8, 7))
            s = sbAppend(s, arm64_ldrb_post(9, 8, 1))
            s = sbAppend(s, arm64_cbnz(9, 0 - 1))
            s = sbAppend(s, arm64_sub_xxx(5, 8, 7))
            s = sbAppend(s, arm64_sub_imm(5, 5, 1))
            s = sbAppend(s, arm64_cmp_xx(4, 5))
            s = sbAppend(s, arm64_b_cond(0xc, 14))
            s = sbAppend(s, arm64_sub_xxx(10, 5, 4))
            s = sbAppend(s, arm64_movz_x_imm(9, 0))
            s = sbAppend(s, arm64_cmp_xx(9, 4))  // CLOOP
            s = sbAppend(s, arm64_b_cond(0xa, 8))
            s = sbAppend(s, arm64_add_xxx(11, 10, 9))
            s = sbAppend(s, arm64_ldrb_reg(12, 7, 11))
            s = sbAppend(s, arm64_ldrb_reg(13, 6, 9))
            s = sbAppend(s, arm64_cmp_xx(12, 13))
            s = sbAppend(s, arm64_b_cond(0x1, 5))  // b.ne FAIL
            s = sbAppend(s, arm64_add_imm(9, 9, 1))
            s = sbAppend(s, arm64_b(0 - 8))
            s = sbAppend(s, arm64_movz_x_imm(0, 1))  // SUCCESS
            s = sbAppend(s, arm64_b(2))
            s = sbAppend(s, arm64_movz_x_imm(0, 0))  // FAIL
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 29
        } else if opTok == "BUILTIN_ARG" {
            // arg(i): i may be an integer literal (common) or a string like "0".
            // 25 instructions. Int passthrough prefix + inline-toInt + load argv.
            //   0:pop x4  1:movz x3=0  2:cmp x4,x3  3:b.lo→INT_ENTRY@18
            //   4:movz x6=0  5:movz x5=0  6:movz x10=10
            //   7:LOOP:ldrb w7  8:cbz→DONE@19(+11)  9:cmp48  10:b.lt→DONE@19(+9)
            //   11:cmp57  12:b.gt→DONE@19(+7)  13:sub  14:mul  15:add x6  16:add x5
            //   17:b→LOOP(-10)  18:INT_ENTRY:mov x6,x4
            //   19(DONE):adrp x9  20:add  21:ldr argv  22:add x6,#1  23:ldr x0  24:push
            s = sbAppend(s, arm64_pop(4))  // 0
            s = sbAppend(s, arm64_movz_x_imm_lsl32(3, 1))  // 1: x3 = 0
            s = sbAppend(s, arm64_cmp_xx(4, 3))  // 2
            s = sbAppend(s, arm64_b_cond(0x3, 15))  // 3: b.lo → INT_ENTRY@18
            s = sbAppend(s, arm64_movz_x_imm(6, 0))  // 4
            s = sbAppend(s, arm64_movz_x_imm(5, 0))  // 5
            s = sbAppend(s, arm64_movz_x_imm(10, 10))  // 6
            s = sbAppend(s, arm64_ldrb_reg(7, 4, 5))  // 7: LOOP
            s = sbAppend(s, arm64_cbz(7, 11))  // 8: → DONE@19
            s = sbAppend(s, arm64_cmp_imm(7, 48))  // 9
            s = sbAppend(s, arm64_b_cond(0xb, 9))  // 10: b.lt → DONE@19
            s = sbAppend(s, arm64_cmp_imm(7, 57))  // 11
            s = sbAppend(s, arm64_b_cond(0xc, 7))  // 12: b.gt → DONE@19
            s = sbAppend(s, arm64_sub_imm(7, 7, 48))  // 13
            s = sbAppend(s, arm64_mul_xxx(6, 6, 10))  // 14
            s = sbAppend(s, arm64_add_xxx(6, 6, 7))  // 15
            s = sbAppend(s, arm64_add_imm(5, 5, 1))  // 16
            s = sbAppend(s, arm64_b(0 - 10))  // 17: → LOOP@7
            s = sbAppend(s, arm64_mov_xx(6, 4))  // 18: INT_ENTRY: x6 = x4
            // DONE@19 — load argv from save cell
            let imm21 = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + (instrIdx + 19) * 4) / 4096
            s = sbAppend(s, arm64_adrp(9, imm21))  // 19
            s = sbAppend(s, arm64_add_imm(9, 9, 0))  // 20: pageoff=0
            s = sbAppend(s, arm64_ldr_imm(9, 9, 2))  // 21: ldr x9, [x9, #16] (argv)
            s = sbAppend(s, arm64_add_imm(6, 6, 1))  // 22: idx + 1 (skip program name)
            s = sbAppend(s, arm64_ldr_reg_lsl3(0, 9, 6))  // 23: x0 = argv[idx+1]
            s = sbAppend(s, arm64_push_x0())  // 24
            instrIdx = instrIdx + 25
        } else if opTok == "BUILTIN_ARGCOUNT" {
            // argCount(): return argc - 1 (excluding program name). 5 instr.
            let imm21 = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + instrIdx * 4) / 4096
            s = sbAppend(s, arm64_adrp(5, imm21))
            s = sbAppend(s, arm64_add_imm(5, 5, 0))
            s = sbAppend(s, arm64_ldr_imm(0, 5, 1))  // ldr x0, [x5, #8] (argc)
            s = sbAppend(s, arm64_sub_imm(0, 0, 1))  // -1 for program name
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 5
        } else if opTok == "BUILTIN_READFILE" {
            // readFile(path): open, alloc 1 MB buf, read, close, NUL-terminate, return.
            // 27 instructions. macOS arm64 syscalls: open=5, read=3, close=6.
            // Uses x19 (saved fd), x20 (saved buf ptr), x21 (saved bytes_read).
            s = sbAppend(s, arm64_pop(10))  // x10 = path
            s = sbAppend(s, arm64_mov_xx(0, 10))
            s = sbAppend(s, arm64_movz_x_imm(1, 0))  // O_RDONLY
            s = sbAppend(s, arm64_movz_x_imm(16, 5))  // sys_open
            s = sbAppend(s, arm64_svc(0x80))
            s = sbAppend(s, arm64_mov_xx(19, 0))  // save fd
            s = sbAppend(s, arm64_movz_x_imm_lsl16(4, 0x10))  // x4 = 1 MB (DATA_VMSIZE = 1 GB; heap has 32 MB before shadow stack)
            instrIdx = instrIdx + 7
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))
            instrIdx = instrIdx + 21
            s = sbAppend(s, arm64_mov_xx(20, 0))  // save buf
            s = sbAppend(s, arm64_mov_xx(0, 19))  // fd
            s = sbAppend(s, arm64_mov_xx(1, 20))  // buf
            s = sbAppend(s, arm64_mov_xx(2, 4))  // size
            s = sbAppend(s, arm64_movz_x_imm(16, 3))  // sys_read
            s = sbAppend(s, arm64_svc(0x80))
            s = sbAppend(s, arm64_mov_xx(21, 0))  // save bytes_read
            s = sbAppend(s, arm64_mov_xx(0, 19))
            s = sbAppend(s, arm64_movz_x_imm(16, 6))  // sys_close
            s = sbAppend(s, arm64_svc(0x80))
            s = sbAppend(s, arm64_strb_reg(31, 20, 21))  // strb wzr, [buf, bytes_read]  (NUL)
            s = sbAppend(s, arm64_mov_xx(0, 20))  // return buf
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 13
        } else if opTok == "BUILTIN_TRIM" {
            // trim(s): strip leading/trailing whitespace — any byte <=32
            // (space, tab \t=9, nl \n=10, cr \r=13, other controls). 42 instr.
            // Layout (0-indexed within this op):
            //   0:pop x6=s  1:movz x12=0
            //   2:ldrb w7 (LOOP1)  3:cbz→ALL_WS(+19)  4:cmp w7,#32  5:b.ne LOOP1_DONE(+3)
            //   6:add x12++  7:b LOOP1(-5)
            //   8 (LOOP1_DONE): mov x8=x6
            //   9:ldrb post w7,[x8],#1 (STRLEN)  10:cbnz back(-1)
            //   11:sub x5=x8-x6  12:sub x5,#1
            //   13 (LOOP2): sub x9=x5-1  14:ldrb w7,[x6,x9]
            //   15:cmp w7,#32  16:b.ne LOOP2_DONE(+4)
            //   17:sub x5,#1  18:cmp x5,x12  19:b.gt LOOP2(-6)
            //   20 (LOOP2_DONE): sub x10=x5-x12  21:b ALLOC(+2)
            //   22 (ALL_WS): movz x10=0  23:movz x12=0
            //   24 (ALLOC): add x4=x10+1
            //   25..31: emitAllocVar (7)
            //   32:add x9=x6+x12 (src)  33:movz x11=0 (i)
            //   34 (LOOP3): cmp x11,x10  35:b.ge LOOP3_DONE(+5)
            //   36:ldrb w13=[x9,x11]  37:strb w13=[x0,x11]  38:add x11++  39:b LOOP3(-5)
            //   40 (LOOP3_DONE): strb wzr=[x0,x10]  41:push
            s = sbAppend(s, arm64_pop(6))
            s = sbAppend(s, arm64_movz_x_imm(12, 0))
            s = sbAppend(s, arm64_ldrb_reg(7, 6, 12))
            s = sbAppend(s, arm64_cbz(7, 19))
            s = sbAppend(s, arm64_cmp_imm(7, 32))
            s = sbAppend(s, arm64_b_cond(0xc, 3))  // b.gt: stop when char>32, so we trim all c<=32 (space/tab/nl/cr)
            s = sbAppend(s, arm64_add_imm(12, 12, 1))
            s = sbAppend(s, arm64_b(0 - 5))
            s = sbAppend(s, arm64_mov_xx(8, 6))
            s = sbAppend(s, arm64_ldrb_post(7, 8, 1))
            s = sbAppend(s, arm64_cbnz(7, 0 - 1))
            s = sbAppend(s, arm64_sub_xxx(5, 8, 6))
            s = sbAppend(s, arm64_sub_imm(5, 5, 1))
            s = sbAppend(s, arm64_sub_imm(9, 5, 1))  // LOOP2
            s = sbAppend(s, arm64_ldrb_reg(7, 6, 9))
            s = sbAppend(s, arm64_cmp_imm(7, 32))
            s = sbAppend(s, arm64_b_cond(0xc, 4))  // b.gt: trim trailing c<=32 (space/tab/nl/cr)
            s = sbAppend(s, arm64_sub_imm(5, 5, 1))
            s = sbAppend(s, arm64_cmp_xx(5, 12))
            s = sbAppend(s, arm64_b_cond(0xc, 0 - 6))  // b.gt LOOP2
            s = sbAppend(s, arm64_sub_xxx(10, 5, 12))  // LOOP2_DONE
            s = sbAppend(s, arm64_b(3))  // skip ALL_WS branch (3 instrs ahead to ALLOC)
            s = sbAppend(s, arm64_movz_x_imm(10, 0))  // ALL_WS
            s = sbAppend(s, arm64_movz_x_imm(12, 0))
            s = sbAppend(s, arm64_add_imm(4, 10, 1))  // ALLOC
            instrIdx = instrIdx + 25
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))
            instrIdx = instrIdx + 21
            s = sbAppend(s, arm64_add_xxx(9, 6, 12))
            s = sbAppend(s, arm64_movz_x_imm(11, 0))
            s = sbAppend(s, arm64_cmp_xx(11, 10))  // LOOP3
            s = sbAppend(s, arm64_b_cond(0xa, 5))  // b.ge LOOP3_DONE (+5)
            s = sbAppend(s, arm64_ldrb_reg(13, 9, 11))
            s = sbAppend(s, arm64_strb_reg(13, 0, 11))
            s = sbAppend(s, arm64_add_imm(11, 11, 1))
            s = sbAppend(s, arm64_b(0 - 5))
            s = sbAppend(s, arm64_strb_reg(31, 0, 10))
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 10
        } else if opTok == "BUILTIN_TOLOWER" {
            // toLower(s): ASCII A-Z -> a-z (+32), copy into a fresh buffer. 42 instr.
            // len kept in x10 (survives alloc; emitAllocVar clobbers x0/1/2/5/9/11).
            //   0:pop x6=s  1:mov x8=x6
            //   2(LOOP0):ldrb post w7,[x8]  3:cbnz -1
            //   4:sub x10=x8-x6  5:sub x10,#1  6:add x4=x10+1
            //   7..27: emitAllocVar -> x0=buf
            //   28:movz x11=0  29(LOOP):cmp x11,x10  30:b.ge DONE(+10)
            //   31:ldrb w13=[x6,x11]  32:cmp w13,#65  33:b.lt NOADD(+4)
            //   34:cmp w13,#90  35:b.gt NOADD(+2)  36:add w13,#32
            //   37(NOADD):strb w13=[x0,x11]  38:add x11++  39:b LOOP(-10)
            //   40(DONE):strb wzr=[x0,x10]  41:push
            s = sbAppend(s, arm64_pop(6))
            s = sbAppend(s, arm64_mov_xx(8, 6))
            s = sbAppend(s, arm64_ldrb_post(7, 8, 1))
            s = sbAppend(s, arm64_cbnz(7, 0 - 1))
            s = sbAppend(s, arm64_sub_xxx(10, 8, 6))
            s = sbAppend(s, arm64_sub_imm(10, 10, 1))
            s = sbAppend(s, arm64_add_imm(4, 10, 1))
            instrIdx = instrIdx + 7
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))
            instrIdx = instrIdx + 21
            s = sbAppend(s, arm64_movz_x_imm(11, 0))
            s = sbAppend(s, arm64_cmp_xx(11, 10))
            s = sbAppend(s, arm64_b_cond(0xa, 10))   // b.ge DONE
            s = sbAppend(s, arm64_ldrb_reg(13, 6, 11))
            s = sbAppend(s, arm64_cmp_imm(13, 65))
            s = sbAppend(s, arm64_b_cond(0xb, 4))    // b.lt NOADD
            s = sbAppend(s, arm64_cmp_imm(13, 90))
            s = sbAppend(s, arm64_b_cond(0xc, 2))    // b.gt NOADD
            s = sbAppend(s, arm64_add_imm(13, 13, 32))
            s = sbAppend(s, arm64_strb_reg(13, 0, 11))
            s = sbAppend(s, arm64_add_imm(11, 11, 1))
            s = sbAppend(s, arm64_b(0 - 10))
            s = sbAppend(s, arm64_strb_reg(31, 0, 10))
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 14
        } else if opTok == "BUILTIN_TOUPPER" {
            // toUpper(s): ASCII a-z -> A-Z (-32). Same shape as TOLOWER. 42 instr.
            s = sbAppend(s, arm64_pop(6))
            s = sbAppend(s, arm64_mov_xx(8, 6))
            s = sbAppend(s, arm64_ldrb_post(7, 8, 1))
            s = sbAppend(s, arm64_cbnz(7, 0 - 1))
            s = sbAppend(s, arm64_sub_xxx(10, 8, 6))
            s = sbAppend(s, arm64_sub_imm(10, 10, 1))
            s = sbAppend(s, arm64_add_imm(4, 10, 1))
            instrIdx = instrIdx + 7
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))
            instrIdx = instrIdx + 21
            s = sbAppend(s, arm64_movz_x_imm(11, 0))
            s = sbAppend(s, arm64_cmp_xx(11, 10))
            s = sbAppend(s, arm64_b_cond(0xa, 10))   // b.ge DONE
            s = sbAppend(s, arm64_ldrb_reg(13, 6, 11))
            s = sbAppend(s, arm64_cmp_imm(13, 97))
            s = sbAppend(s, arm64_b_cond(0xb, 4))    // b.lt NOSUB
            s = sbAppend(s, arm64_cmp_imm(13, 122))
            s = sbAppend(s, arm64_b_cond(0xc, 2))    // b.gt NOSUB
            s = sbAppend(s, arm64_sub_imm(13, 13, 32))
            s = sbAppend(s, arm64_strb_reg(13, 0, 11))
            s = sbAppend(s, arm64_add_imm(11, 11, 1))
            s = sbAppend(s, arm64_b(0 - 10))
            s = sbAppend(s, arm64_strb_reg(31, 0, 10))
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 14
        } else if opTok == "BUILTIN_ENVIRON" {
            // environ(name): scan saved envp (bump_cell+80, set in __main__) for
            // an entry "name=value"; return a pointer to value (into envp, a live
            // NUL-terminated C string) or "" (the envp NULL slot, 8 zero bytes).
            // Was a no-op passthrough natively → installRoot wrong → imports broke. 21 instr.
            let imm21e = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + (instrIdx + 1) * 4) / 4096
            s = sbAppend(s, arm64_pop(6))             // 0: name
            s = sbAppend(s, arm64_adrp(9, imm21e))    // 1: cell
            s = sbAppend(s, arm64_add_imm(9, 9, 0))   // 2
            s = sbAppend(s, arm64_ldr_imm(7, 9, 10))  // 3: x7 = envp (cell+80)
            // ENTRY_LOOP @4:
            s = sbAppend(s, arm64_ldr_imm(10, 7, 0))  // 4: x10 = envp[i]
            s = sbAppend(s, arm64_add_imm(7, 7, 8))   // 5: x7 → next
            s = sbAppend(s, arm64_cbz(10, 13))        // 6: NULL → NOTFOUND (→19)
            s = sbAppend(s, arm64_mov_xx(11, 6))      // 7: name scan
            s = sbAppend(s, arm64_mov_xx(12, 10))     // 8: entry scan
            // CMP_LOOP @9:
            s = sbAppend(s, arm64_ldrb_post(13, 11, 1)) // 9: *name++
            s = sbAppend(s, arm64_ldrb_post(14, 12, 1)) // 10: *entry++
            s = sbAppend(s, arm64_cbz(13, 4))         // 11: name end → NAME_END (→15)
            s = sbAppend(s, arm64_cmp_xx(13, 14))     // 12
            s = sbAppend(s, arm64_b_cond(0x1, 0 - 9)) // 13: b.ne → ENTRY_LOOP (→4)
            s = sbAppend(s, arm64_b(0 - 5))           // 14: → CMP_LOOP (→9)
            // NAME_END @15:
            s = sbAppend(s, arm64_cmp_imm(14, 0x3d))  // 15: entry char == '='?
            s = sbAppend(s, arm64_b_cond(0x1, 0 - 12))// 16: b.ne → ENTRY_LOOP (→4)
            s = sbAppend(s, arm64_mov_xx(0, 12))      // 17: MATCH value = x12 (past '=')
            s = sbAppend(s, arm64_b(2))               // 18: → PUSH (skip NOTFOUND@19)
            // NOTFOUND @19:
            s = sbAppend(s, arm64_sub_imm(0, 7, 8))   // 19: x0 = NULL-slot addr → "" (8 zero bytes)
            // PUSH @20:
            s = sbAppend(s, arm64_push_x0())          // 20
            instrIdx = instrIdx + 21
        } else if opTok == "BUILTIN_LENGTH" {
            // length(list): count comma-separated elements.
            //  ""           → 0
            //  "hello"      → 1
            //  "1,2,3"      → 3
            // 13 instructions.
            s = sbAppend(s, arm64_pop(3))  // 0: x3 = list ptr
            s = sbAppend(s, arm64_ldrb_zero(4, 3))  // 1: w4 = first byte
            s = sbAppend(s, arm64_cbz(4, 9))  // 2: empty → EMPTY (idx 11)
            s = sbAppend(s, arm64_movz_x_imm(0, 1))  // 3: cnt = 1
            s = sbAppend(s, arm64_mov_xx(1, 3))  // 4: scan = list
            // LOOP @ 5:
            s = sbAppend(s, arm64_ldrb_post(4, 1, 1))  // 5: load byte, post-inc
            s = sbAppend(s, arm64_cbz(4, 6))  // 6: NUL → DONE (idx 12)
            s = sbAppend(s, arm64_cmp_imm(4, 0x2c))  // 7
            s = sbAppend(s, arm64_b_cond(0x1, 0 - 3))  // 8: b.ne LOOP (back 3 → idx 5)
            s = sbAppend(s, arm64_add_imm(0, 0, 1))  // 9: cnt++
            s = sbAppend(s, arm64_b(0 - 5))  // 10: b LOOP (back 5 → idx 5)
            // EMPTY @ 11:
            s = sbAppend(s, arm64_movz_x_imm(0, 0))  // 11: x0 = 0
            // DONE @ 12:
            s = sbAppend(s, arm64_push_x0())  // 12
            instrIdx = instrIdx + 13
        } else if opTok == "BUILTIN_SPLIT" {
            // split(list, idx) → idx-th comma-element as a new heap string.
            // TOS = idx (int), next = list (ptr). 50 instructions.
            s = sbAppend(s, arm64_pop(4))  // 0: x4 = idx
            s = sbAppend(s, arm64_pop(3))  // 1: x3 = list
            s = sbAppend(s, arm64_movz_x_imm(5, 0))  // 2: count = 0
            s = sbAppend(s, arm64_mov_xx(10, 3))  // 3: start = list (x10 — preserved across emitAllocVar)
            s = sbAppend(s, arm64_mov_xx(1, 3))  // 4: scan = list
            // SCAN @ 5:
            s = sbAppend(s, arm64_ldrb_zero(6, 1))  // 5
            s = sbAppend(s, arm64_cbz(6, 9))  // 6: NUL → END_SCAN (idx 15, rel +9)
            s = sbAppend(s, arm64_cmp_imm(6, 0x2c))  // 7
            s = sbAppend(s, arm64_b_cond(0x1, 5))  // 8: b.ne NEXT_CHAR (idx 13)
            // comma hit
            s = sbAppend(s, arm64_cmp_xx(5, 4))  // 9: count == idx?
            s = sbAppend(s, arm64_b_cond(0x0, 8))  // 10: b.eq FOUND (idx 18)
            s = sbAppend(s, arm64_add_imm(5, 5, 1))  // 11: count++
            s = sbAppend(s, arm64_add_imm(10, 1, 1))  // 12: start = p+1
            // NEXT_CHAR @ 13:
            s = sbAppend(s, arm64_add_imm(1, 1, 1))  // 13
            s = sbAppend(s, arm64_b(0 - 9))  // 14: → SCAN (back 9 = idx 5)
            // END_SCAN @ 15: check last
            s = sbAppend(s, arm64_cmp_xx(5, 4))  // 15
            s = sbAppend(s, arm64_b_cond(0x0, 2))  // 16: b.eq FOUND (idx 18, rel +2)
            s = sbAppend(s, arm64_mov_xx(10, 1))  // 17: not found → start = scan_end (len 0)
            // FOUND @ 18:
            s = sbAppend(s, arm64_sub_xxx(7, 1, 10))  // 18: len = p - start
            s = sbAppend(s, arm64_add_imm(4, 7, 1))  // 19: alloc size = len+1
            instrIdx = instrIdx + 20
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))  // x0 = dest (21 instr)
            instrIdx = instrIdx + 21
            // Copy + NUL + push (9 instr, relative)
            s = sbAppend(s, arm64_movz_x_imm(13, 0))  // 0: i = 0
            // COPY @ rel 1:
            s = sbAppend(s, arm64_cmp_xx(13, 7))  // 1
            s = sbAppend(s, arm64_b_cond(0xa, 5))  // 2: b.ge AFTER (rel 7)
            s = sbAppend(s, arm64_ldrb_reg(14, 10, 13))  // 3
            s = sbAppend(s, arm64_strb_reg(14, 0, 13))  // 4
            s = sbAppend(s, arm64_add_imm(13, 13, 1))  // 5
            s = sbAppend(s, arm64_b(0 - 5))  // 6
            // AFTER @ rel 7:
            s = sbAppend(s, arm64_strb_reg(31, 0, 7))  // 7: NUL at dest+len
            s = sbAppend(s, arm64_push_x0())  // 8
            instrIdx = instrIdx + 9
        } else if opTok == "BUILTIN_RANGE" {
            // range(s, e): produce comma-separated decimal string for [s..e).
            // s >= e returns empty string. Allocates (e-s)*12 bytes (max
            // for 64-bit decimals + commas). 75 instructions.
            s = sbAppend(s, arm64_pop(6))  // 0: end
            s = sbAppend(s, arm64_pop(3))  // 1: start
            s = sbAppend(s, arm64_cmp_xx(3, 6))  // 2
            s = sbAppend(s, arm64_b_cond(0xb, 3))  // 3: b.lt NONEMPTY (idx 6)
            s = sbAppend(s, arm64_movz_x_imm(4, 1))  // 4: empty path, size=1
            s = sbAppend(s, arm64_b(4))  // 5: → ALLOC (idx 9, rel +4)
            // NONEMPTY @ 6:
            s = sbAppend(s, arm64_sub_xxx(9, 6, 3))  // 6: n = end-start
            s = sbAppend(s, arm64_movz_x_imm(10, 12))  // 7
            s = sbAppend(s, arm64_mul_xxx(4, 9, 10))  // 8: size = n*12
            // ALLOC @ 9:
            instrIdx = instrIdx + 9
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))  // 21 instr → x0 = dest
            instrIdx = instrIdx + 21
            // POST_ALLOC @ 30: empty check again
            s = sbAppend(s, arm64_cmp_xx(3, 6))  // 30
            s = sbAppend(s, arm64_b_cond(0xa, 42))  // 31: b.ge JUST_NUL (idx 73)
            s = sbAppend(s, arm64_sub_imm(31, 31, 32))  // 32: reserve stack scratch
            s = sbAppend(s, arm64_mov_xx(8, 0))  // 33: write_ptr = dest
            s = sbAppend(s, arm64_mov_xx(9, 3))  // 34: cur = start
            // OUTER @ 35:
            s = sbAppend(s, arm64_cmp_xx(9, 6))  // 35
            s = sbAppend(s, arm64_b_cond(0xa, 34))  // 36: b.ge OUTER_END (idx 70, rel +34)
            s = sbAppend(s, arm64_cmp_xx(9, 3))  // 37
            s = sbAppend(s, arm64_b_cond(0x0, 4))  // 38: b.eq SKIP_COMMA (idx 42)
            s = sbAppend(s, arm64_movz_w_imm(13, 0x2c))  // 39
            s = sbAppend(s, arm64_strb_imm(13, 8, 0))  // 40: store ','
            s = sbAppend(s, arm64_add_imm(8, 8, 1))  // 41: write_ptr++
            // SKIP_COMMA @ 42:
            s = sbAppend(s, arm64_add_imm(11, 31, 23))  // 42: p = sp+23
            s = sbAppend(s, arm64_strb_imm(31, 11, 0))  // 43: *p = NUL
            s = sbAppend(s, arm64_mov_xx(12, 9))  // 44: tmp = cur
            s = sbAppend(s, arm64_cbnz(12, 5))  // 45: nonzero → ITOA_BODY (idx 50)
            // tmp == 0 case
            s = sbAppend(s, arm64_sub_imm(11, 11, 1))  // 46
            s = sbAppend(s, arm64_movz_w_imm(13, 0x30))  // 47
            s = sbAppend(s, arm64_strb_imm(13, 11, 0))  // 48
            s = sbAppend(s, arm64_b(10))  // 49: → ITOA_COPY (idx 59)
            // ITOA_BODY @ 50:
            s = sbAppend(s, arm64_cbz(12, 9))  // 50: → ITOA_COPY (idx 59)
            s = sbAppend(s, arm64_movz_x_imm(13, 10))  // 51
            s = sbAppend(s, arm64_udiv_xxx(14, 12, 13))  // 52
            s = sbAppend(s, arm64_msub_xxxx(15, 14, 13, 12))  // 53
            s = sbAppend(s, arm64_add_imm(15, 15, 0x30))  // 54
            s = sbAppend(s, arm64_sub_imm(11, 11, 1))  // 55
            s = sbAppend(s, arm64_strb_imm(15, 11, 0))  // 56
            s = sbAppend(s, arm64_mov_xx(12, 14))  // 57
            s = sbAppend(s, arm64_b(0 - 8))  // 58: → ITOA_BODY (back 8)
            // ITOA_COPY @ 59:
            s = sbAppend(s, arm64_add_imm(13, 31, 23))  // 59: x13 = sp+23 (end+1)
            s = sbAppend(s, arm64_sub_xxx(14, 13, 11))  // 60: copy_len = end - start_ptr
            // COPY_LOOP @ 61:
            s = sbAppend(s, arm64_cbz(14, 7))  // 61: → COPY_END (idx 68)
            s = sbAppend(s, arm64_ldrb_zero(15, 11))  // 62
            s = sbAppend(s, arm64_strb_imm(15, 8, 0))  // 63
            s = sbAppend(s, arm64_add_imm(11, 11, 1))  // 64
            s = sbAppend(s, arm64_add_imm(8, 8, 1))  // 65
            s = sbAppend(s, arm64_sub_imm(14, 14, 1))  // 66
            s = sbAppend(s, arm64_b(0 - 6))  // 67: → COPY_LOOP (back 6 to 61)
            // COPY_END @ 68:
            s = sbAppend(s, arm64_add_imm(9, 9, 1))  // 68: cur++
            s = sbAppend(s, arm64_b(0 - 34))  // 69: → OUTER (back 34 to 35)
            // OUTER_END @ 70:
            s = sbAppend(s, arm64_strb_imm(31, 8, 0))  // 70: final NUL
            s = sbAppend(s, arm64_add_imm(31, 31, 32))  // 71: restore sp
            s = sbAppend(s, arm64_b(2))  // 72: → PUSH (idx 74)
            // JUST_NUL @ 73:
            s = sbAppend(s, arm64_strb_imm(31, 0, 0))  // 73: NUL at dest
            // PUSH @ 74:
            s = sbAppend(s, arm64_push_x0())  // 74
            instrIdx = instrIdx + 45
        } else if opTok == "BUILTIN_COUNT" {
            // count(s): 1 + comma-count. Always at least 1, even for empty. 10 instr.
            s = sbAppend(s, arm64_pop(3))  // 0
            s = sbAppend(s, arm64_movz_x_imm(0, 1))  // 1: cnt = 1
            s = sbAppend(s, arm64_mov_xx(1, 3))  // 2: scan = list
            // LOOP @ 3:
            s = sbAppend(s, arm64_ldrb_post(4, 1, 1))  // 3
            s = sbAppend(s, arm64_cbz(4, 5))  // 4: NUL → DONE (idx 9, rel +5)
            s = sbAppend(s, arm64_cmp_imm(4, 0x2c))  // 5
            s = sbAppend(s, arm64_b_cond(0x1, 0 - 3))  // 6: b.ne LOOP (idx 3, rel -3)
            s = sbAppend(s, arm64_add_imm(0, 0, 1))  // 7: cnt++
            s = sbAppend(s, arm64_b(0 - 5))  // 8: b LOOP (idx 3, rel -5)
            // DONE @ 9:
            s = sbAppend(s, arm64_push_x0())  // 9
            instrIdx = instrIdx + 10
        } else if opTok == "BUILTIN_ISTRUTHY" {
            // isTruthy(v) — full semantics matching the C runtime kr_istruthy:
            //   int 0 → falsy, int nonzero → truthy
            //   ""        → falsy
            //   "0"       → falsy
            //   "false"   → falsy
            //   anything else (ptr) → truthy
            // Uses x5 as a scratch ptr to byte-walk the string.  35 instructions.
            s = sbAppend(s, arm64_pop(3))  // 0: v
            s = sbAppend(s, arm64_movz_x_imm_lsl32(14, 1))  // 1: 0
            s = sbAppend(s, arm64_cmp_xx(3, 14))  // 2
            s = sbAppend(s, arm64_b_cond(0xa, 4))  // 3: b.ge PTR_PATH (idx 7)
            // INT path
            s = sbAppend(s, arm64_cbz(3, 29))  // 4: zero → FALSY (idx 33, rel +29)
            s = sbAppend(s, arm64_movz_x_imm(0, 1))  // 5
            s = sbAppend(s, arm64_b(28))  // 6: → PUSH (idx 34)
            // PTR_PATH @ 7:
            s = sbAppend(s, arm64_mov_xx(5, 3))  // 7: scan ptr
            s = sbAppend(s, arm64_ldrb_post(4, 5, 1))  // 8: first byte (scan++)
            s = sbAppend(s, arm64_cbz(4, 24))  // 9: NUL → FALSY (idx 33, rel +24)
            // Check "0\0"
            s = sbAppend(s, arm64_cmp_imm(4, 0x30))  // 10: '0'?
            s = sbAppend(s, arm64_b_cond(0x1, 3))  // 11: b.ne CHECK_FALSE (idx 14)
            s = sbAppend(s, arm64_ldrb_zero(6, 5))  // 12: next byte ([sp+1])
            s = sbAppend(s, arm64_cbz(6, 20))  // 13: NUL → FALSY (idx 33, rel +20)
            // CHECK_FALSE @ 14:
            s = sbAppend(s, arm64_cmp_imm(4, 0x66))  // 14: 'f'?
            s = sbAppend(s, arm64_b_cond(0x1, 16))  // 15: b.ne TRUTHY (idx 31)
            s = sbAppend(s, arm64_ldrb_post(6, 5, 1))  // 16: 'a'?
            s = sbAppend(s, arm64_cmp_imm(6, 0x61))
            s = sbAppend(s, arm64_b_cond(0x1, 13))  // 18: b.ne TRUTHY
            s = sbAppend(s, arm64_ldrb_post(6, 5, 1))  // 19: 'l'?
            s = sbAppend(s, arm64_cmp_imm(6, 0x6c))
            s = sbAppend(s, arm64_b_cond(0x1, 10))  // 21: b.ne TRUTHY
            s = sbAppend(s, arm64_ldrb_post(6, 5, 1))  // 22: 's'?
            s = sbAppend(s, arm64_cmp_imm(6, 0x73))
            s = sbAppend(s, arm64_b_cond(0x1, 7))  // 24: b.ne TRUTHY
            s = sbAppend(s, arm64_ldrb_post(6, 5, 1))  // 25: 'e'?
            s = sbAppend(s, arm64_cmp_imm(6, 0x65))
            s = sbAppend(s, arm64_b_cond(0x1, 4))  // 27: b.ne TRUTHY
            s = sbAppend(s, arm64_ldrb_zero(6, 5))  // 28: byte after "false"?
            s = sbAppend(s, arm64_cbnz(6, 2))  // 29: not NUL → TRUTHY (idx 31)
            // Falls through to FALSY since matched "false\0"
            s = sbAppend(s, arm64_b(3))  // 30: → FALSY (idx 33, rel +3)
            // TRUTHY @ 31:
            s = sbAppend(s, arm64_movz_x_imm(0, 1))  // 31
            s = sbAppend(s, arm64_b(2))  // 32 — wait, this was FALSY idx
            // The above two are at idx 31 (TRUTHY movz) and idx 32 (b PUSH).
            // FALSY @ 32 then conflicts. Let me re-layout below.
            s = sbAppend(s, arm64_movz_x_imm(0, 0))  // 33: FALSY
            s = sbAppend(s, arm64_push_x0())  // 34: PUSH
            instrIdx = instrIdx + 35
        } else if opTok == "BUILTIN_LINECOUNT" {
            // lineCount(s): 0 if empty, else 1 + \n-count, minus 1 if last char
            // was \n (matches C kr_linecount). 18 instructions.
            s = sbAppend(s, arm64_pop(3))  // 0
            s = sbAppend(s, arm64_ldrb_zero(4, 3))  // 1
            s = sbAppend(s, arm64_cbz(4, 14))  // 2: empty → EMPTY (idx 16)
            s = sbAppend(s, arm64_movz_x_imm(0, 1))  // 3: cnt = 1
            s = sbAppend(s, arm64_mov_xx(1, 3))  // 4: scan
            s = sbAppend(s, arm64_movz_x_imm(5, 0))  // 5: last_was_nl = 0
            // LOOP @ 6:
            s = sbAppend(s, arm64_ldrb_post(4, 1, 1))  // 6
            s = sbAppend(s, arm64_cbz(4, 7))  // 7: NUL → DONE (idx 14)
            s = sbAppend(s, arm64_movz_x_imm(5, 0))  // 8: reset flag
            s = sbAppend(s, arm64_cmp_imm(4, 0x0a))  // 9
            s = sbAppend(s, arm64_b_cond(0x1, 0 - 4))  // 10: b.ne LOOP (rel -4)
            s = sbAppend(s, arm64_add_imm(0, 0, 1))  // 11: cnt++
            s = sbAppend(s, arm64_movz_x_imm(5, 1))  // 12: last_was_nl = 1
            s = sbAppend(s, arm64_b(0 - 7))  // 13: b LOOP (rel -7)
            // DONE @ 14:
            s = sbAppend(s, arm64_sub_xxx(0, 0, 5))  // 14: cnt -= last_was_nl
            s = sbAppend(s, arm64_b(2))  // 15: → PUSH (idx 17)
            // EMPTY @ 16:
            s = sbAppend(s, arm64_movz_x_imm(0, 0))  // 16
            // PUSH @ 17:
            s = sbAppend(s, arm64_push_x0())  // 17
            instrIdx = instrIdx + 18
        } else if opTok == "BUILTIN_GETLINE" {
            // getLine(s, idx) → idx-th \n-separated line. Pointer-keyed cache at
            // bump_cell +56(ptr)/+64(idx)/+72(off): same string & cached_idx<=idx
            // resumes the scan from the cached line start → O(1) for sequential
            // access (tokAt loops) instead of O(idx) rescans → kills the O(n^2)
            // that stalled self-host. Cache miss (other string or idx<cached)
            // rescans from 0, so always correct. 65 instr.
            s = sbAppend(s, arm64_pop(4))   // 0: idx
            s = sbAppend(s, arm64_pop(3))   // 1: s
            let imm21gl = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + (instrIdx + 2) * 4) / 4096
            s = sbAppend(s, arm64_adrp(9, imm21gl))   // 2: x9 = bump_cell page
            s = sbAppend(s, arm64_add_imm(9, 9, 0))   // 3
            s = sbAppend(s, arm64_ldr_imm(11, 9, 7))  // 4: cache_ptr (+56)
            s = sbAppend(s, arm64_ldr_imm(12, 9, 8))  // 5: cache_idx (+64)
            s = sbAppend(s, arm64_ldr_imm(13, 9, 9))  // 6: cache_off (+72)
            s = sbAppend(s, arm64_cmp_xx(11, 3))      // 7: cache_ptr == s?
            s = sbAppend(s, arm64_b_cond(0x1, 6))     // 8: b.ne MISS (→14)
            s = sbAppend(s, arm64_cmp_xx(12, 4))      // 9: cache_idx <= idx?
            s = sbAppend(s, arm64_b_cond(0x8, 4))     // 10: b.hi MISS (→14)
            s = sbAppend(s, arm64_mov_xx(5, 12))      // 11: HIT count = cache_idx
            s = sbAppend(s, arm64_mov_xx(10, 13))     // 12: start = cache_off
            s = sbAppend(s, arm64_b(3))               // 13: → SCAN_INIT (→16)
            s = sbAppend(s, arm64_movz_x_imm(5, 0))   // 14: MISS count = 0
            s = sbAppend(s, arm64_mov_xx(10, 3))      // 15: start = s
            s = sbAppend(s, arm64_mov_xx(1, 10))      // 16: SCAN_INIT scan = start
            // SCAN @ 17:
            s = sbAppend(s, arm64_ldrb_zero(6, 1))    // 17
            s = sbAppend(s, arm64_cbz(6, 9))          // 18: NUL → END_SCAN (→27)
            s = sbAppend(s, arm64_cmp_imm(6, 0x0a))   // 19
            s = sbAppend(s, arm64_b_cond(0x1, 5))     // 20: b.ne NEXT (→25)
            s = sbAppend(s, arm64_cmp_xx(5, 4))       // 21
            s = sbAppend(s, arm64_b_cond(0x0, 8))     // 22: b.eq FOUND (→30)
            s = sbAppend(s, arm64_add_imm(5, 5, 1))   // 23
            s = sbAppend(s, arm64_add_imm(10, 1, 1))  // 24: start = p+1
            // NEXT @ 25:
            s = sbAppend(s, arm64_add_imm(1, 1, 1))   // 25
            s = sbAppend(s, arm64_b(0 - 9))           // 26: → SCAN (→17)
            // END_SCAN @ 27:
            s = sbAppend(s, arm64_cmp_xx(5, 4))       // 27
            s = sbAppend(s, arm64_b_cond(0x0, 2))     // 28: → FOUND (→30)
            s = sbAppend(s, arm64_mov_xx(10, 1))      // 29: not found → len 0
            // FOUND @ 30: update cache (x9 = cell), then build the line string
            s = sbAppend(s, arm64_str_imm(3, 9, 7))   // 30: cache_ptr = s
            s = sbAppend(s, arm64_str_imm(4, 9, 8))   // 31: cache_idx = idx
            s = sbAppend(s, arm64_str_imm(10, 9, 9))  // 32: cache_off = start
            s = sbAppend(s, arm64_sub_xxx(7, 1, 10))  // 33: len = p - start
            s = sbAppend(s, arm64_add_imm(4, 7, 1))   // 34: alloc size
            instrIdx = instrIdx + 35
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))
            instrIdx = instrIdx + 21
            s = sbAppend(s, arm64_movz_x_imm(13, 0))    // 0: i
            s = sbAppend(s, arm64_cmp_xx(13, 7))        // 1
            s = sbAppend(s, arm64_b_cond(0xa, 5))       // 2: b.ge AFTER (rel 7)
            s = sbAppend(s, arm64_ldrb_reg(14, 10, 13)) // 3
            s = sbAppend(s, arm64_strb_reg(14, 0, 13))  // 4
            s = sbAppend(s, arm64_add_imm(13, 13, 1))   // 5
            s = sbAppend(s, arm64_b(0 - 5))             // 6
            s = sbAppend(s, arm64_strb_reg(31, 0, 7))   // 7
            s = sbAppend(s, arm64_push_x0())            // 8
            instrIdx = instrIdx + 9
        } else if opTok == "BUILTIN_REPLACE" {
            // replace(s, old, new): substitute every occurrence of `old` in `s`
            // with `new`. Returns a new heap-allocated string. Three-arg builtin —
            // TOS = new, next = old, next = s. 95 instructions.
            // Registers preserved across emitAllocVar (which clobbers x0/1/2/4/5/9/11):
            //   x3=s, x6=new, x7=old, x8=rlen, x10=olen, x12=slen, x13=count
            s = sbAppend(s, arm64_pop(6))  // 0: new
            s = sbAppend(s, arm64_pop(7))  // 1: old
            s = sbAppend(s, arm64_pop(3))  // 2: s
            // strlen new → x8 (5 instr)
            s = sbAppend(s, arm64_mov_xx(1, 6))  // 3
            s = sbAppend(s, arm64_ldrb_post(14, 1, 1))  // 4
            s = sbAppend(s, arm64_cbnz(14, 0 - 1))  // 5
            s = sbAppend(s, arm64_sub_xxx(8, 1, 6))  // 6
            s = sbAppend(s, arm64_sub_imm(8, 8, 1))  // 7: rlen
            // strlen old → x10 (5 instr)
            s = sbAppend(s, arm64_mov_xx(1, 7))  // 8
            s = sbAppend(s, arm64_ldrb_post(14, 1, 1))  // 9
            s = sbAppend(s, arm64_cbnz(14, 0 - 1))  // 10
            s = sbAppend(s, arm64_sub_xxx(10, 1, 7))  // 11
            s = sbAppend(s, arm64_sub_imm(10, 10, 1))  // 12: olen
            // strlen s → x12 (5 instr)
            s = sbAppend(s, arm64_mov_xx(1, 3))  // 13
            s = sbAppend(s, arm64_ldrb_post(14, 1, 1))  // 14
            s = sbAppend(s, arm64_cbnz(14, 0 - 1))  // 15
            s = sbAppend(s, arm64_sub_xxx(12, 1, 3))  // 16
            s = sbAppend(s, arm64_sub_imm(12, 12, 1))  // 17: slen
            // olen == 0 fast path → push s and jump past everything
            s = sbAppend(s, arm64_cbnz(10, 4))  // 18: olen != 0 → CONTINUE (idx 22)
            s = sbAppend(s, arm64_mov_xx(0, 3))  // 19
            s = sbAppend(s, arm64_push_x0())  // 20
            s = sbAppend(s, arm64_b(74))  // 21: → DONE (idx 95, rel +74)
            // CONTINUE @ 22: count occurrences
            s = sbAppend(s, arm64_movz_x_imm(13, 0))  // 22: count = 0
            s = sbAppend(s, arm64_mov_xx(1, 3))  // 23: p = s
            // COUNT_LOOP @ 24:
            s = sbAppend(s, arm64_ldrb_zero(14, 1))  // 24: *p
            s = sbAppend(s, arm64_cbz(14, 15))  // 25: NUL → COUNT_DONE (idx 40, rel +15)
            s = sbAppend(s, arm64_movz_x_imm(2, 0))  // 26: j = 0
            // INNER @ 27: strncmp p with old
            s = sbAppend(s, arm64_cmp_xx(2, 10))  // 27
            s = sbAppend(s, arm64_b_cond(0xa, 7))  // 28: b.ge MATCH (idx 35)
            s = sbAppend(s, arm64_ldrb_reg(14, 1, 2))  // 29: p[j]
            s = sbAppend(s, arm64_ldrb_reg(15, 7, 2))  // 30: old[j]
            s = sbAppend(s, arm64_cmp_xx(14, 15))  // 31
            s = sbAppend(s, arm64_b_cond(0x1, 6))  // 32: b.ne NO_MATCH (idx 38)
            s = sbAppend(s, arm64_add_imm(2, 2, 1))  // 33: j++
            s = sbAppend(s, arm64_b(0 - 7))  // 34: → INNER (rel -7)
            // MATCH @ 35:
            s = sbAppend(s, arm64_add_imm(13, 13, 1))  // 35: count++
            s = sbAppend(s, arm64_add_xxx(1, 1, 10))  // 36: p += olen
            s = sbAppend(s, arm64_b(0 - 13))  // 37: → COUNT_LOOP (rel -13)
            // NO_MATCH @ 38:
            s = sbAppend(s, arm64_add_imm(1, 1, 1))  // 38: p++
            s = sbAppend(s, arm64_b(0 - 15))  // 39: → COUNT_LOOP (rel -15)
            // COUNT_DONE @ 40:
            s = sbAppend(s, arm64_sub_xxx(4, 8, 10))  // 40: rlen - olen (may be negative)
            s = sbAppend(s, arm64_mul_xxx(4, 13, 4))  // 41: count * (rlen - olen)
            s = sbAppend(s, arm64_add_xxx(4, 12, 4))  // 42: slen + delta
            s = sbAppend(s, arm64_add_imm(4, 4, 1))  // 43: + NUL
            instrIdx = instrIdx + 44
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))  // 21 instr, x0 = out
            instrIdx = instrIdx + 21
            // POST_ALLOC @ rel 0 = absolute idx 65:
            s = sbAppend(s, arm64_mov_xx(1, 0))  // 0: dst = out
            s = sbAppend(s, arm64_mov_xx(2, 3))  // 1: sp = s
            // COPY_LOOP @ rel 2:
            s = sbAppend(s, arm64_ldrb_zero(14, 2))  // 2: *sp
            s = sbAppend(s, arm64_cbz(14, 25))  // 3: NUL → COPY_DONE (rel +25 → rel 28)
            s = sbAppend(s, arm64_movz_x_imm(5, 0))  // 4: j = 0
            // ICOPY @ rel 5: match-check
            s = sbAppend(s, arm64_cmp_xx(5, 10))  // 5
            s = sbAppend(s, arm64_b_cond(0xa, 7))  // 6: b.ge DO_REPLACE (rel 13)
            s = sbAppend(s, arm64_ldrb_reg(14, 2, 5))  // 7
            s = sbAppend(s, arm64_ldrb_reg(15, 7, 5))  // 8
            s = sbAppend(s, arm64_cmp_xx(14, 15))  // 9
            s = sbAppend(s, arm64_b_cond(0x1, 13))  // 10: b.ne CHAR_COPY (rel 23)
            s = sbAppend(s, arm64_add_imm(5, 5, 1))  // 11
            s = sbAppend(s, arm64_b(0 - 7))  // 12: → ICOPY (rel -7)
            // DO_REPLACE @ rel 13:
            s = sbAppend(s, arm64_movz_x_imm(5, 0))  // 13
            // RCOPY @ rel 14:
            s = sbAppend(s, arm64_cmp_xx(5, 8))  // 14
            s = sbAppend(s, arm64_b_cond(0xa, 5))  // 15: b.ge AFTER_REPLACE (rel 20)
            s = sbAppend(s, arm64_ldrb_reg(14, 6, 5))  // 16
            s = sbAppend(s, arm64_strb_reg(14, 1, 5))  // 17
            s = sbAppend(s, arm64_add_imm(5, 5, 1))  // 18
            s = sbAppend(s, arm64_b(0 - 5))  // 19: → RCOPY
            // AFTER_REPLACE @ rel 20:
            s = sbAppend(s, arm64_add_xxx(1, 1, 8))  // 20: dst += rlen
            s = sbAppend(s, arm64_add_xxx(2, 2, 10))  // 21: sp += olen
            s = sbAppend(s, arm64_b(0 - 20))  // 22: → COPY_LOOP (rel -20)
            // CHAR_COPY @ rel 23:
            s = sbAppend(s, arm64_ldrb_zero(14, 2))  // 23
            s = sbAppend(s, arm64_strb_imm(14, 1, 0))  // 24
            s = sbAppend(s, arm64_add_imm(1, 1, 1))  // 25
            s = sbAppend(s, arm64_add_imm(2, 2, 1))  // 26
            s = sbAppend(s, arm64_b(0 - 25))  // 27: → COPY_LOOP (rel -25)
            // COPY_DONE @ rel 28: write NUL, push
            s = sbAppend(s, arm64_strb_imm(31, 1, 0))  // 28
            s = sbAppend(s, arm64_push_x0())  // 29
            // DONE @ rel 30 (= absolute 95). Landing point for the cbnz olen==0 path.
            instrIdx = instrIdx + 30
        } else if opTok == "BUILTIN_GCALLOCATED" {
            // Read alloc_total at bump_cell + 24, push as int. 4 instructions.
            let imm21 = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + instrIdx * 4) / 4096
            s = sbAppend(s, arm64_adrp(1, imm21))
            s = sbAppend(s, arm64_add_imm(1, 1, 0))
            s = sbAppend(s, arm64_ldr_imm(0, 1, 3))  // ldr x0, [x1, #24] (alloc_total)
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 4
        } else if opTok == "BUILTIN_GCLIMIT" {
            // Read alloc_limit at bump_cell + 32, push as int. 4 instructions.
            let imm21 = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + instrIdx * 4) / 4096
            s = sbAppend(s, arm64_adrp(1, imm21))
            s = sbAppend(s, arm64_add_imm(1, 1, 0))
            s = sbAppend(s, arm64_ldr_imm(0, 1, 4))  // ldr x0, [x1, #32] (alloc_limit)
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 4
        } else if opTok == "BUILTIN_GCSETLIMIT" {
            // Pop value, store at alloc_limit, push back. 5 instructions.
            s = sbAppend(s, arm64_pop_x0())
            instrIdx = instrIdx + 1
            let imm21 = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + instrIdx * 4) / 4096
            s = sbAppend(s, arm64_adrp(1, imm21))
            s = sbAppend(s, arm64_add_imm(1, 1, 0))
            s = sbAppend(s, arm64_str_imm(0, 1, 4))  // str x0, [x1, #32] (alloc_limit = arg)
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 4
        } else if opTok == "BUILTIN_GCRESET" {
            // Zero bump_cell, alloc_total, gcShadowCount, gcAllocsHead.
            // Full heap + roots + alloc-list reset. Push 0. 8 instructions.
            let imm21 = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + instrIdx * 4) / 4096
            s = sbAppend(s, arm64_adrp(1, imm21))
            s = sbAppend(s, arm64_add_imm(1, 1, 0))
            s = sbAppend(s, arm64_str_imm(31, 1, 0))  // bump_cell = 0
            s = sbAppend(s, arm64_str_imm(31, 1, 3))  // alloc_total = 0 (offset +24)
            s = sbAppend(s, arm64_str_imm(31, 1, 5))  // gcShadowCount = 0 (offset +40)
            s = sbAppend(s, arm64_str_imm(31, 1, 6))  // gcAllocsHead = 0 (offset +48)
            s = sbAppend(s, arm64_movz_x_imm(0, 0))
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 8
        } else if opTok == "BUILTIN_GCCOLLECT" {
            // gcCollect: run mark phase + sweep phase inline; return swept count.
            // 43 instructions = MARK (idx 2..22) + SWEEP (idx 23..40) + return (41..42).
            let imm21 = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + instrIdx * 4) / 4096
            s = sbAppend(s, arm64_adrp(1, imm21))  // 0
            s = sbAppend(s, arm64_add_imm(1, 1, 0))  // 1
            // ── MARK PHASE ──
            s = sbAppend(s, arm64_ldr_imm(2, 1, 5))  // 2: shadow count
            s = sbAppend(s, arm64_cbz(2, 21))  // 3: → MARK_DONE @ 23+1=... wait
                                                                // 3 + 20 = 23 ✓ (lands at MARK_DONE)
            // hmm reconsidering: cbz at idx 3, target idx 23 → rel = 20
            s = sbAppend(s, arm64_movz_x_imm_lsl16(9, 0x5000))  // x9 = 0x50000000 (shadow base offset, 1.25GB)
            s = sbAppend(s, arm64_add_xxx(3, 1, 9))  // 5: x3 = bump_cell + 0x20000000
            s = sbAppend(s, arm64_add_imm(9, 1, 80))  // 6: min user_ptr
            s = sbAppend(s, arm64_ldr_imm(10, 1, 0))  // 7: heap top (bump)
            s = sbAppend(s, arm64_movz_x_imm(6, 0))  // 8: i = 0
            // MARK_LOOP @ idx 9:
            s = sbAppend(s, arm64_cmp_xx(6, 2))  // 9
            s = sbAppend(s, arm64_b_cond(0xa, 13))  // 10: b.ge → MARK_DONE (+13 = 23)
            s = sbAppend(s, arm64_ldr_reg_lsl3(4, 3, 6))  // 11: v = shadow[i]
            s = sbAppend(s, arm64_cmp_xx(4, 9))  // 12
            s = sbAppend(s, arm64_b_cond(0xb, 8))  // 13: b.lt → MARK_SKIP (+8 = 21)
            s = sbAppend(s, arm64_cmp_xx(4, 10))  // 14
            s = sbAppend(s, arm64_b_cond(0xa, 6))  // 15: b.ge → MARK_SKIP (+6 = 21)
            s = sbAppend(s, arm64_sub_imm(7, 4, 8))  // 16
            s = sbAppend(s, arm64_ldr_imm(8, 7, 0))  // 17
            s = sbAppend(s, arm64_movz_x_imm_lsl48(12, 0x8000))  // 18
            s = sbAppend(s, arm64_orr_xxx(8, 8, 12))  // 19
            s = sbAppend(s, arm64_str_imm(8, 7, 0))  // 20
            // MARK_SKIP @ idx 21:
            s = sbAppend(s, arm64_add_imm(6, 6, 1))  // 21: i++
            s = sbAppend(s, arm64_b(0 - 13))  // 22: → MARK_LOOP (idx 9)
            // MARK_DONE @ idx 23 — start SWEEP:
            s = sbAppend(s, arm64_ldr_imm(10, 1, 6))  // 23: current = head
            s = sbAppend(s, arm64_add_imm(11, 1, 48))  // 24: prev_next = &head
            s = sbAppend(s, arm64_movz_x_imm(5, 0))  // 25: swept = 0
            // SWEEP_LOOP @ idx 26:
            s = sbAppend(s, arm64_cbz(10, 15))  // 26: → SWEEP_DONE (+15 = 41)
            s = sbAppend(s, arm64_ldr_imm(4, 10, 1))  // 27: size_flags
            s = sbAppend(s, arm64_cmp_imm(4, 0))  // 28
            s = sbAppend(s, arm64_b_cond(0xb, 6))  // 29: b.lt → SWEEP_MARKED (+6 = 35)
            // UNMARKED — unlink
            s = sbAppend(s, arm64_ldr_imm(12, 10, 0))  // 30: next
            s = sbAppend(s, arm64_str_imm(12, 11, 0))  // 31: *prev_next = next
            s = sbAppend(s, arm64_mov_xx(10, 12))  // 32: current = next
            s = sbAppend(s, arm64_add_imm(5, 5, 1))  // 33: swept++
            s = sbAppend(s, arm64_b(0 - 8))  // 34: → SWEEP_LOOP (idx 26)
            // SWEEP_MARKED @ idx 35:
            s = sbAppend(s, arm64_movz_x_imm_lsl48(12, 0x8000))  // 35
            s = sbAppend(s, arm64_eor_xxx(4, 4, 12))  // 36: clear mark
            s = sbAppend(s, arm64_str_imm(4, 10, 1))  // 37
            s = sbAppend(s, arm64_mov_xx(11, 10))  // 38: prev_next = &cur.next
            s = sbAppend(s, arm64_ldr_imm(10, 10, 0))  // 39: current = cur.next
            s = sbAppend(s, arm64_b(0 - 14))  // 40: → SWEEP_LOOP (idx 26)
            // SWEEP_DONE @ idx 41:
            s = sbAppend(s, arm64_mov_xx(0, 5))  // 41: x0 = swept count
            s = sbAppend(s, arm64_push_x0())  // 42: push
            instrIdx = instrIdx + 43
        } else if opTok == "BUILTIN_GCALLOCCOUNT" {
            // Walk gcAllocsHead linked list, count entries. 10 instructions.
            let imm21 = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + instrIdx * 4) / 4096
            s = sbAppend(s, arm64_adrp(1, imm21))  // 0
            s = sbAppend(s, arm64_add_imm(1, 1, 0))  // 1
            s = sbAppend(s, arm64_ldr_imm(10, 1, 6))  // 2: current = head
            s = sbAppend(s, arm64_movz_x_imm(5, 0))  // 3: count = 0
            // LOOP @ idx 4:
            s = sbAppend(s, arm64_cbz(10, 4))  // 4: → END (+4 = 8)
            s = sbAppend(s, arm64_add_imm(5, 5, 1))  // 5
            s = sbAppend(s, arm64_ldr_imm(10, 10, 0))  // 6: current = next
            s = sbAppend(s, arm64_b(0 - 3))  // 7: → LOOP (idx 4)
            // END @ idx 8:
            s = sbAppend(s, arm64_mov_xx(0, 5))  // 8
            s = sbAppend(s, arm64_push_x0())  // 9
            instrIdx = instrIdx + 10
        } else if opTok == "BUILTIN_GCSHADOWPUSH" {
            // gcShadowPush(value): increment the shadow count only. We deliberately
            // do NOT store the value into a shadow array: no GC pass is currently
            // triggered (the bump allocator never calls collect), so stored roots
            // are never read. Storing them grew memory without bound — every
            // loop-iteration local pushed a root that was only popped at function
            // exit, so a long loop leaked millions of entries and eventually ran
            // off the end of __DATA. Keeping just the count preserves the
            // gcShadowCount/gcShadowPop save-restore balance the IR depends on
            // while costing zero heap. (Re-add a real, bounded root store here if
            // a live GC pass is wired up.)  8 instructions.
            s = sbAppend(s, arm64_pop_x0())  // 0: discard value
            let imm21 = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + (instrIdx + 1) * 4) / 4096
            s = sbAppend(s, arm64_adrp(1, imm21))  // 1: adrp x1, bump_cell@PAGE
            s = sbAppend(s, arm64_add_imm(1, 1, 0))  // 2: pageoff=0
            s = sbAppend(s, arm64_ldr_imm(2, 1, 5))  // 3: x2 = count [x1, #40]
            s = sbAppend(s, arm64_add_imm(2, 2, 1))  // 4: count += 1
            s = sbAppend(s, arm64_str_imm(2, 1, 5))  // 5: store count
            s = sbAppend(s, arm64_movz_x_imm(0, 0))  // 6: x0 = 0
            s = sbAppend(s, arm64_push_x0())  // 7: push 0
            instrIdx = instrIdx + 8
        } else if opTok == "BUILTIN_GCSHADOWPOP" {
            // gcShadowPop(n): count -= n. 8 instructions.
            s = sbAppend(s, arm64_pop_x0())  // 0: x0 = n
            let imm21 = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + (instrIdx + 1) * 4) / 4096
            s = sbAppend(s, arm64_adrp(1, imm21))  // 1
            s = sbAppend(s, arm64_add_imm(1, 1, 0))  // 2
            s = sbAppend(s, arm64_ldr_imm(2, 1, 5))  // 3: x2 = count (offset +40)
            s = sbAppend(s, arm64_sub_xxx(2, 2, 0))  // 4: x2 -= n
            s = sbAppend(s, arm64_str_imm(2, 1, 5))  // 5: store count
            s = sbAppend(s, arm64_movz_x_imm(0, 0))  // 6: x0 = 0
            s = sbAppend(s, arm64_push_x0())  // 7: push 0
            instrIdx = instrIdx + 8
        } else if opTok == "BUILTIN_GCSHADOWCOUNT" {
            // gcShadowCount(): return count. 4 instructions.
            let imm21 = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + instrIdx * 4) / 4096
            s = sbAppend(s, arm64_adrp(1, imm21))  // 0
            s = sbAppend(s, arm64_add_imm(1, 1, 0))  // 1
            s = sbAppend(s, arm64_ldr_imm(0, 1, 5))  // 2: x0 = count (offset +40)
            s = sbAppend(s, arm64_push_x0())  // 3: push
            instrIdx = instrIdx + 4
        } else if opTok == "BUILTIN_GCMARK" {
            // Mark phase: walk gcShadowCount entries of the shadow stack at
            // bump_cell+0x2000000. For each value v in [bump_cell+80, bump_cell+heap_top),
            // treat (v-16) as a header_ptr and set bit 63 of its size_flags word.
            // Range filter is conservative — may over-mark on false positives
            // (which is safe; only under-marking is unsafe). 27 instructions.
            let imm21 = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + instrIdx * 4) / 4096
            s = sbAppend(s, arm64_adrp(1, imm21))  // 0
            s = sbAppend(s, arm64_add_imm(1, 1, 0))  // 1
            s = sbAppend(s, arm64_ldr_imm(2, 1, 5))  // 2: x2 = gcShadowCount (+40)
            s = sbAppend(s, arm64_cbz(2, 22))  // 3: → END if count==0
            s = sbAppend(s, arm64_movz_x_imm_lsl16(9, 0x5000))  // x9 = 0x50000000 (shadow base offset, 1.25GB)
            s = sbAppend(s, arm64_add_xxx(3, 1, 9))  // 5: x3 = bump_cell + 0x20000000
            s = sbAppend(s, arm64_add_imm(9, 1, 80))  // 6: x9 = bump_cell+80 (min user_ptr)
            s = sbAppend(s, arm64_ldr_imm(10, 1, 0))  // 7: x10 = bump (heap top)
            s = sbAppend(s, arm64_movz_x_imm(6, 0))  // 8: i = 0
            s = sbAppend(s, arm64_movz_x_imm(5, 0))  // 9: marked = 0
            // LOOP @ instrIdx+10:
            s = sbAppend(s, arm64_cmp_xx(6, 2))  // 10: cmp i, count
            s = sbAppend(s, arm64_b_cond(0xa, 14))  // 11: b.ge → END (+14)
            s = sbAppend(s, arm64_ldr_reg_lsl3(4, 3, 6))  // 12: x4 = shadow[i]
            s = sbAppend(s, arm64_cmp_xx(4, 9))  // 13: cmp v, min_user
            s = sbAppend(s, arm64_b_cond(0xb, 9))  // 14: b.lt → SKIP (+9)
            s = sbAppend(s, arm64_cmp_xx(4, 10))  // 15: cmp v, heap_top
            s = sbAppend(s, arm64_b_cond(0xa, 7))  // 16: b.ge → SKIP (+7)
            s = sbAppend(s, arm64_sub_imm(7, 4, 8))  // 17: x7 = v - 8 (size_flags addr)
            s = sbAppend(s, arm64_ldr_imm(8, 7, 0))  // 18: x8 = size_flags
            s = sbAppend(s, arm64_movz_x_imm_lsl48(12, 0x8000))  // 19: x12 = 1<<63
            s = sbAppend(s, arm64_orr_xxx(8, 8, 12))  // 20: x8 |= mark bit
            s = sbAppend(s, arm64_str_imm(8, 7, 0))  // 21: store size_flags
            s = sbAppend(s, arm64_add_imm(5, 5, 1))  // 22: marked++
            // SKIP @ instrIdx+23:
            s = sbAppend(s, arm64_add_imm(6, 6, 1))  // 23: i++
            s = sbAppend(s, arm64_b(0 - 14))  // 24: back to LOOP
            // END @ instrIdx+25:
            s = sbAppend(s, arm64_mov_xx(0, 5))  // 25: x0 = marked
            s = sbAppend(s, arm64_push_x0())  // 26: push
            instrIdx = instrIdx + 27
        } else if opTok == "BUILTIN_GCSWEEP" {
            // Sweep phase: walk gcAllocsHead linked list. For each header:
            //   - if bit 63 of size_flags is set → clear it (kept)
            //   - else → unlink from list (swept; not actually freed yet —
            //     freelist comes in a later session).
            // Returns the swept count. 23 instructions.
            let imm21 = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + instrIdx * 4) / 4096
            s = sbAppend(s, arm64_adrp(1, imm21))  // 0
            s = sbAppend(s, arm64_add_imm(1, 1, 0))  // 1
            s = sbAppend(s, arm64_ldr_imm(10, 1, 6))  // 2: x10 = current = head
            s = sbAppend(s, arm64_add_imm(11, 1, 48))  // 3: x11 = &head (prev next-loc)
            s = sbAppend(s, arm64_movz_x_imm(5, 0))  // 4: swept = 0
            // LOOP @ instrIdx+5:
            s = sbAppend(s, arm64_cbz(10, 15))  // 5: while current != null
            s = sbAppend(s, arm64_ldr_imm(4, 10, 1))  // 6: x4 = size_flags ([cur+8])
            s = sbAppend(s, arm64_cmp_imm(4, 0))  // 7: cmp x4, #0
            s = sbAppend(s, arm64_b_cond(0xb, 6))  // 8: b.lt → MARKED (+6)
            // UNMARKED — unlink current
            s = sbAppend(s, arm64_ldr_imm(12, 10, 0))  // 9: x12 = current.next
            s = sbAppend(s, arm64_str_imm(12, 11, 0))  // 10: *prev_next = next
            s = sbAppend(s, arm64_mov_xx(10, 12))  // 11: current = next
            s = sbAppend(s, arm64_add_imm(5, 5, 1))  // 12: swept++
            s = sbAppend(s, arm64_b(0 - 8))  // 13: back to LOOP
            // MARKED @ instrIdx+14: clear mark bit, advance
            s = sbAppend(s, arm64_movz_x_imm_lsl48(12, 0x8000))  // 14: bit-63 mask
            s = sbAppend(s, arm64_eor_xxx(4, 4, 12))  // 15: clear bit (XOR — known set)
            s = sbAppend(s, arm64_str_imm(4, 10, 1))  // 16: store size_flags
            s = sbAppend(s, arm64_mov_xx(11, 10))  // 17: prev_next_loc = &cur.next
            s = sbAppend(s, arm64_ldr_imm(10, 10, 0))  // 18: current = current.next
            s = sbAppend(s, arm64_b(0 - 14))  // 19: back to LOOP
            // END @ instrIdx+20:
            s = sbAppend(s, arm64_mov_xx(0, 5))  // 20: x0 = swept
            s = sbAppend(s, arm64_push_x0())  // 21: push
            instrIdx = instrIdx + 22
        } else if opTok == "BUILTIN_GCCHECKPOINT" {
            // gcCheckpoint: snapshot the current shadow-stack count; return it.
            // gcRestore uses the snapshot to truncate the shadow stack later.
            // Used by compile.k around pure_ functions and try-catch blocks.
            // 4 instructions.
            let imm21 = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + instrIdx * 4) / 4096
            s = sbAppend(s, arm64_adrp(1, imm21))
            s = sbAppend(s, arm64_add_imm(1, 1, 0))
            s = sbAppend(s, arm64_ldr_imm(0, 1, 5))  // x0 = gcShadowCount (+40)
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 4
        } else if opTok == "BUILTIN_GCRESTORE" {
            // gcRestore(snapshot): set gcShadowCount = snapshot. 6 instructions.
            s = sbAppend(s, arm64_pop_x0())  // 0: x0 = snapshot
            let imm21 = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + (instrIdx + 1) * 4) / 4096
            s = sbAppend(s, arm64_adrp(1, imm21))  // 1
            s = sbAppend(s, arm64_add_imm(1, 1, 0))  // 2
            s = sbAppend(s, arm64_str_imm(0, 1, 5))  // 3: gcShadowCount = snapshot
            s = sbAppend(s, arm64_movz_x_imm(0, 0))  // 4
            s = sbAppend(s, arm64_push_x0())  // 5
            instrIdx = instrIdx + 6
        } else if opTok == "BUILTIN_GCFREELISTCOUNT" || opTok == "BUILTIN_GCSLABCOUNT" ||
                  opTok == "BUILTIN_GCSLABBYTES" {
            // STUB: 0-arg, returns 0. Freelist + slab tracking not implemented.
            s = sbAppend(s, arm64_movz_x_imm(0, 0))
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 2
        } else if opTok == "BUILTIN_GCWALKALLOCS" {
            // STUB: 1-arg (callback), discard, return 0. Real impl would invoke
            // callback per alloc — needs function-pointer-call infrastructure.
            s = sbAppend(s, arm64_pop_x0())
            s = sbAppend(s, arm64_movz_x_imm(0, 0))
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 3
        } else if opTok == "BUILTIN_WRITEFILE" {
            // writeFile(path, content): open(path, O_WRONLY|O_CREAT|O_TRUNC, 0644),
            // strlen(content), write, close, return 0. 22 instructions.
            // O_WRONLY=1, O_CREAT=0x200, O_TRUNC=0x400 → flags = 0x601.
            s = sbAppend(s, arm64_pop(10))  // content
            s = sbAppend(s, arm64_pop(11))  // path
            s = sbAppend(s, arm64_mov_xx(0, 11))
            s = sbAppend(s, arm64_movz_x_imm(1, 0x601))
            s = sbAppend(s, arm64_movz_x_imm(2, 0x1a4))  // mode 0644
            s = sbAppend(s, arm64_movz_x_imm(16, 5))  // sys_open
            s = sbAppend(s, arm64_svc(0x80))
            s = sbAppend(s, arm64_mov_xx(19, 0))  // save fd
            s = sbAppend(s, arm64_mov_xx(4, 10))  // x4 = walk ptr
            s = sbAppend(s, arm64_ldrb_post(5, 4, 1))  // STRLEN_LOOP
            s = sbAppend(s, arm64_cbnz(5, 0 - 1))
            s = sbAppend(s, arm64_sub_xxx(2, 4, 10))  // len+1
            s = sbAppend(s, arm64_sub_imm(2, 2, 1))  // len
            s = sbAppend(s, arm64_mov_xx(0, 19))  // fd
            s = sbAppend(s, arm64_mov_xx(1, 10))  // content
            s = sbAppend(s, arm64_movz_x_imm(16, 4))  // sys_write
            s = sbAppend(s, arm64_svc(0x80))
            s = sbAppend(s, arm64_mov_xx(0, 19))
            s = sbAppend(s, arm64_movz_x_imm(16, 6))  // sys_close
            s = sbAppend(s, arm64_svc(0x80))
            s = sbAppend(s, arm64_movz_x_imm(0, 0))  // return 0
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 22
        } else if opTok == "BUILTIN_WRITEBYTES" {
            // writeBytes(path, hexstr): decode xHH hex pairs to raw bytes, write file.
            // Uses a 256-byte stack buffer; flushes every 256 bytes. 54 instructions.
            // Uppercase hex only (hexByte emits A-F). Register map:
            //   x10=hexstr ptr, x11=path, x19=fd, x20=buf_base, x21=write_ptr
            //   w4=hi nibble/byte, w5=lo nibble, w13=shift(4), w14=scratch/cmp
            // Instruction layout: 0-10 setup, 11-41 decode loop + flush, 42-53 tail+close.
            s = sbAppend(s, arm64_pop(10))  // 0: x10 = hexstr
            s = sbAppend(s, arm64_pop(11))  // 1: x11 = path
            s = sbAppend(s, arm64_mov_xx(0, 11))  // 2: x0 = path
            s = sbAppend(s, arm64_movz_x_imm(1, 0x601))  // 3: O_WRONLY|O_CREAT|O_TRUNC
            s = sbAppend(s, arm64_movz_x_imm(2, 0x1a4))  // 4: mode 0644
            s = sbAppend(s, arm64_movz_x_imm(16, 5))  // 5: SYS_open
            s = sbAppend(s, arm64_svc(0x80))  // 6
            s = sbAppend(s, arm64_mov_xx(19, 0))  // 7: x19 = fd
            s = sbAppend(s, arm64_sub_sp(256))  // 8: allocate 256-byte stack buffer
            s = sbAppend(s, arm64_add_imm(20, 31, 0))  // 9: x20 = sp (buf_base)
            s = sbAppend(s, arm64_add_imm(21, 31, 0))  // 10: x21 = sp (write_ptr)
            // DECODE_LOOP @ 11:
            s = sbAppend(s, arm64_ldrb_post(14, 10, 1))  // 11: w14 = *x10++ (scan char)
            s = sbAppend(s, arm64_cbz(14, 30))  // 12: NUL → DONE@42
            s = sbAppend(s, arm64_cmp_imm(14, 0x78))  // 13: cmp 'x'
            s = sbAppend(s, arm64_b_cond(0x1, 0 - 3))  // 14: b.ne → DECODE_LOOP@11
            s = sbAppend(s, arm64_ldrb_post(4, 10, 1))  // 15: w4 = *x10++ (hi nibble char)
            s = sbAppend(s, arm64_cbz(4, 26))  // 16: NUL → DONE@42
            s = sbAppend(s, arm64_sub_imm(4, 4, 0x30))  // 17: w4 -= '0'
            s = sbAppend(s, arm64_cmp_imm(4, 9))  // 18: digit check
            s = sbAppend(s, arm64_b_cond(0xd, 2))  // 19: b.le → HI_DONE@21
            s = sbAppend(s, arm64_sub_imm(4, 4, 7))  // 20: A-F: 17-22 → 10-15
            // HI_DONE @ 21:
            s = sbAppend(s, arm64_ldrb_post(5, 10, 1))  // 21: w5 = *x10++ (lo nibble char)
            s = sbAppend(s, arm64_cbz(5, 20))  // 22: NUL → DONE@42
            s = sbAppend(s, arm64_sub_imm(5, 5, 0x30))  // 23: w5 -= '0'
            s = sbAppend(s, arm64_cmp_imm(5, 9))  // 24: digit check
            s = sbAppend(s, arm64_b_cond(0xd, 2))  // 25: b.le → LO_DONE@27
            s = sbAppend(s, arm64_sub_imm(5, 5, 7))  // 26: A-F: 17-22 → 10-15
            // LO_DONE @ 27:
            s = sbAppend(s, arm64_movz_x_imm(13, 4))  // 27: x13 = 4 (shift amount)
            s = sbAppend(s, arm64_lsl_w(4, 4, 13))  // 28: w4 = hi << 4
            s = sbAppend(s, arm64_orr_www(4, 4, 5))  // 29: w4 = (hi<<4)|lo
            s = sbAppend(s, arm64_strb_imm(4, 21, 0))  // 30: *write_ptr = byte
            s = sbAppend(s, arm64_add_imm(21, 21, 1))  // 31: write_ptr++
            s = sbAppend(s, arm64_sub_xxx(14, 21, 20))  // 32: x14 = bytes_used
            s = sbAppend(s, arm64_cmp_imm(14, 256))  // 33: buffer full?
            s = sbAppend(s, arm64_b_cond(0x1, 0 - 23))  // 34: b.ne → DECODE_LOOP@11
            // FLUSH @ 35:
            s = sbAppend(s, arm64_mov_xx(0, 19))  // 35: fd
            s = sbAppend(s, arm64_mov_xx(1, 20))  // 36: buf
            s = sbAppend(s, arm64_movz_x_imm(2, 256))  // 37: count=256
            s = sbAppend(s, arm64_movz_x_imm(16, 4))  // 38: SYS_write
            s = sbAppend(s, arm64_svc(0x80))  // 39
            s = sbAppend(s, arm64_mov_xx(21, 20))  // 40: reset write_ptr
            s = sbAppend(s, arm64_b(11 - 41))  // 41: → DECODE_LOOP@11
            // DONE @ 42:
            s = sbAppend(s, arm64_sub_xxx(2, 21, 20))  // 42: remaining bytes
            s = sbAppend(s, arm64_cbz(2, 5))  // 43: 0 → CLOSE@48
            s = sbAppend(s, arm64_mov_xx(0, 19))  // 44: fd
            s = sbAppend(s, arm64_mov_xx(1, 20))  // 45: buf
            s = sbAppend(s, arm64_movz_x_imm(16, 4))  // 46: SYS_write
            s = sbAppend(s, arm64_svc(0x80))  // 47
            // CLOSE @ 48:
            s = sbAppend(s, arm64_mov_xx(0, 19))  // 48: fd
            s = sbAppend(s, arm64_movz_x_imm(16, 6))  // 49: SYS_close
            s = sbAppend(s, arm64_svc(0x80))  // 50
            s = sbAppend(s, arm64_add_sp(256))  // 51: restore stack
            s = sbAppend(s, arm64_movz_x_imm(0, 0))  // 52: return 0
            s = sbAppend(s, arm64_push_x0())  // 53
            instrIdx = instrIdx + 54
        } else if opTok == "BUILTIN_PRINTERR" {
            // printErr(v): write v to stderr. Same as BUILTIN_PRINT but fd=2.
            s = sbAppend(s, arm64_pop(3))  // 0: x3 = arg
            s = sbAppend(s, arm64_movz_x_imm_lsl32(14, 1))  // 1: x14 = 1<<32
            s = sbAppend(s, arm64_cmp_xx(3, 14))  // 2
            s = sbAppend(s, arm64_b_cond(0xb, 11))  // 3: b.lt INT_PATH (idx 14)
            // ── STRING PATH (idx 4..13) ──
            s = sbAppend(s, arm64_mov_xx(1, 3))  // 4
            s = sbAppend(s, arm64_ldrb_post(4, 1, 1))  // 5
            s = sbAppend(s, arm64_cbnz(4, 0 - 1))  // 6: scan NUL
            s = sbAppend(s, arm64_sub_xxx(2, 1, 3))  // 7
            s = sbAppend(s, arm64_sub_imm(2, 2, 1))  // 8: len
            s = sbAppend(s, arm64_movz_x_imm(0, 2))  // 9: stderr
            s = sbAppend(s, arm64_mov_xx(1, 3))  // 10
            s = sbAppend(s, arm64_movz_x_imm(16, 4))  // 11: SYS_write
            s = sbAppend(s, arm64_svc(0x80))  // 12
            s = sbAppend(s, arm64_b(37))  // 13: → DONE (idx 50)
            // ── INT PATH @ idx 14 ── itoa to stack buffer, then write ──
            s = sbAppend(s, arm64_sub_imm(31, 31, 32))  // 14: alloc buf
            s = sbAppend(s, arm64_add_imm(4, 31, 23))  // 15: x4 = sp+23 (end)
            s = sbAppend(s, arm64_strb_imm(31, 4, 0))  // 16: *p = NUL (xzr)
            s = sbAppend(s, arm64_movz_x_imm(5, 0))  // 17: neg = 0
            s = sbAppend(s, arm64_cmp_imm(3, 0))  // 18: cmp n, 0
            s = sbAppend(s, arm64_b_cond(0xa, 3))  // 19: b.ge POSITIVE (idx 22)
            s = sbAppend(s, arm64_movz_x_imm(5, 1))  // 20: neg = 1
            s = sbAppend(s, arm64_neg(3, 3))  // 21: n = -n
            // POSITIVE @ idx 22:
            s = sbAppend(s, arm64_cbnz(3, 5))  // 22: → INT_LOOP (idx 27)
            // n == 0: write '0'
            s = sbAppend(s, arm64_sub_imm(4, 4, 1))  // 23
            s = sbAppend(s, arm64_movz_w_imm(6, 0x30))  // 24: '0'
            s = sbAppend(s, arm64_strb_imm(6, 4, 0))  // 25
            s = sbAppend(s, arm64_b(10))  // 26: → INT_SIGN (idx 36)
            // INT_LOOP @ idx 27:
            s = sbAppend(s, arm64_cbz(3, 9))  // 27: → INT_SIGN (idx 36)
            s = sbAppend(s, arm64_movz_x_imm(7, 10))  // 28
            s = sbAppend(s, arm64_udiv_xxx(8, 3, 7))  // 29: q = n / 10
            s = sbAppend(s, arm64_msub_xxxx(9, 8, 7, 3))  // 30: r = n - q*10
            s = sbAppend(s, arm64_add_imm(9, 9, 0x30))  // 31: r += '0'
            s = sbAppend(s, arm64_sub_imm(4, 4, 1))  // 32
            s = sbAppend(s, arm64_strb_imm(9, 4, 0))  // 33
            s = sbAppend(s, arm64_mov_xx(3, 8))  // 34: n = q
            s = sbAppend(s, arm64_b(0 - 8))  // 35: → INT_LOOP
            // INT_SIGN @ idx 36:
            s = sbAppend(s, arm64_cbz(5, 4))  // 36: → INT_PRINT (idx 40)
            s = sbAppend(s, arm64_sub_imm(4, 4, 1))  // 37
            s = sbAppend(s, arm64_movz_w_imm(6, 0x2D))  // 38: '-'
            s = sbAppend(s, arm64_strb_imm(6, 4, 0))  // 39
            // INT_PRINT @ idx 40:
            s = sbAppend(s, arm64_mov_xx(1, 4))  // 40: scan from buf start
            s = sbAppend(s, arm64_ldrb_post(6, 1, 1))  // 41
            s = sbAppend(s, arm64_cbnz(6, 0 - 1))  // 42: scan to NUL
            s = sbAppend(s, arm64_sub_xxx(2, 1, 4))  // 43
            s = sbAppend(s, arm64_sub_imm(2, 2, 1))  // 44: real len
            s = sbAppend(s, arm64_movz_x_imm(0, 2))  // 45: stderr
            s = sbAppend(s, arm64_mov_xx(1, 4))  // 46
            s = sbAppend(s, arm64_movz_x_imm(16, 4))  // 47
            s = sbAppend(s, arm64_svc(0x80))  // 48: write digits
            s = sbAppend(s, arm64_add_imm(31, 31, 32))  // 49: restore sp
            // DONE @ idx 50:
            s = sbAppend(s, arm64_movz_w_imm(0, 0))  // 50
            s = sbAppend(s, arm64_push_x0())  // 51
            instrIdx = instrIdx + 52
        } else if opTok == "BUILTIN_INDEXOF" {
            // indexOf(s, sub): 21 instructions. Stack TOS = sub, then s.
            // Layout (0-indexed within this op):
            //   0:pop sub  1:pop s  2:movz x5
            //   3:ldrb s[i]  4:cbz→NOT_FOUND(+15)  5:movz x4=0
            //   6:ldrb sub[j]  7:cbz→FOUND(+10)  8:add x10=i+j  9:ldrb s[i+j]  10:cbz→NOT_FOUND(+9)
            //   11:cmp  12:b.ne→NEXT_OUTER(+3)  13:add j++  14:b INNER(-8)
            //   15:add i++ (NEXT_OUTER)  16:b OUTER(-13)
            //   17:mov x0,x5 (FOUND)  18:b END(+2)
            //   19:movn x0 (NOT_FOUND)
            //   20:push (END)
            s = sbAppend(s, arm64_pop(6))
            s = sbAppend(s, arm64_pop(7))
            s = sbAppend(s, arm64_movz_x_imm(5, 0))
            s = sbAppend(s, arm64_ldrb_reg(8, 7, 5))
            s = sbAppend(s, arm64_cbz(8, 15))
            s = sbAppend(s, arm64_movz_x_imm(4, 0))
            s = sbAppend(s, arm64_ldrb_reg(9, 6, 4))
            s = sbAppend(s, arm64_cbz(9, 10))
            s = sbAppend(s, arm64_add_xxx(10, 5, 4))
            s = sbAppend(s, arm64_ldrb_reg(11, 7, 10))
            s = sbAppend(s, arm64_cbz(11, 9))
            s = sbAppend(s, arm64_cmp_xx(9, 11))
            s = sbAppend(s, arm64_b_cond(0x1, 3))
            s = sbAppend(s, arm64_add_imm(4, 4, 1))
            s = sbAppend(s, arm64_b(0 - 8))
            s = sbAppend(s, arm64_add_imm(5, 5, 1))
            s = sbAppend(s, arm64_b(0 - 13))
            s = sbAppend(s, arm64_mov_xx(0, 5))
            s = sbAppend(s, arm64_b(2))
            s = sbAppend(s, arm64_movn_x_imm(0, 0))
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 21
        } else if opTok == "BUILTIN_FROMCHARCODE" {
            // fromCharCode(n): 1-char heap string. 26 instrs.
            // 0:pop x3  1:movz x4,#2  2-22:emitAllocVar  23:strb w3,[x0,0]  24:strb wzr,[x0,1]  25:push
            s = sbAppend(s, arm64_pop(3))
            s = sbAppend(s, arm64_movz_x_imm(4, 2))
            s = sbAppend(s, emitAllocVar(instrIdx + 2, textVaddr, textOff))
            s = sbAppend(s, arm64_strb_imm(3, 0, 0))
            s = sbAppend(s, arm64_strb_imm(31, 0, 1))
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 26
        } else if opTok == "BUILTIN_READLINE" {
            // readLine(prompt): write prompt stdout, read stdin, strip \n. 46 instrs.
            s = sbAppend(s, arm64_pop(10))  // 0: prompt
            s = sbAppend(s, arm64_mov_xx(1, 10))  // 1: strlen walk
            s = sbAppend(s, arm64_ldrb_post(2, 1, 1))  // 2: STRLEN_LOOP
            s = sbAppend(s, arm64_cbnz(2, 0 - 1))  // 3: → 2
            s = sbAppend(s, arm64_sub_xxx(2, 1, 10))  // 4: len+1
            s = sbAppend(s, arm64_sub_imm(2, 2, 1))  // 5: len
            s = sbAppend(s, arm64_movz_x_imm(0, 1))  // 6: stdout fd
            s = sbAppend(s, arm64_mov_xx(1, 10))  // 7: prompt ptr
            s = sbAppend(s, arm64_movz_x_imm(16, 4))  // 8: SYS_write
            s = sbAppend(s, arm64_svc(0x80))  // 9
            s = sbAppend(s, arm64_movz_x_imm(4, 0x1000))  // 10: alloc 4096
            s = sbAppend(s, emitAllocVar(instrIdx + 11, textVaddr, textOff))  // 11-31
            s = sbAppend(s, arm64_mov_xx(20, 0))  // 32: save buf
            s = sbAppend(s, arm64_movz_x_imm(0, 0))  // 33: stdin
            s = sbAppend(s, arm64_mov_xx(1, 20))  // 34
            s = sbAppend(s, arm64_movz_x_imm(2, 0x1000))  // 35: count
            s = sbAppend(s, arm64_movz_x_imm(16, 3))  // 36: SYS_read
            s = sbAppend(s, arm64_svc(0x80))  // 37
            s = sbAppend(s, arm64_cbz(0, 7))  // 38: → DONE@45
            s = sbAppend(s, arm64_add_xxx(1, 20, 0))  // 39: one-past-last
            s = sbAppend(s, arm64_sub_imm(1, 1, 1))  // 40: last byte
            s = sbAppend(s, arm64_ldrb_zero(2, 1))  // 41
            s = sbAppend(s, arm64_cmp_imm(2, 0x0a))  // 42: '\n'?
            s = sbAppend(s, arm64_b_cond(0x1, 2))  // 43: b.ne DONE@45
            s = sbAppend(s, arm64_strb_imm(31, 1, 0))  // 44: strip \n
            s = sbAppend(s, arm64_push(20))  // 45: DONE
            instrIdx = instrIdx + 46
        } else if opTok == "BUILTIN_SHELLRUN" {
            // shellRun(cmd): fork+execve /bin/sh -c cmd, wait, return real exit code. 84 instrs.
            s = sbAppend(s, arm64_pop(3))  // 0: cmd
            s = sbAppend(s, arm64_sub_sp(64))  // 1
            s = sbAppend(s, arm64_movz_x_imm(0, 0x622f))  // 2: "/bin/sh\0" low
            s = sbAppend(s, arm64_movk_x_imm_lsl16(0, 0x6e69))  // 3
            s = sbAppend(s, arm64_movk_x_imm_lsl32(0, 0x732f))  // 4
            s = sbAppend(s, arm64_movk_x_imm_lsl48(0, 0x0068))  // 5
            s = sbAppend(s, arm64_str_imm(0, 31, 0))  // 6: [sp,#0]
            s = sbAppend(s, arm64_movz_x_imm(0, 0x632d))  // 7: "-c\0"
            s = sbAppend(s, arm64_str_imm(0, 31, 1))  // 8: [sp,#8]
            s = sbAppend(s, arm64_add_imm(0, 31, 0))  // 9: x0=sp
            s = sbAppend(s, arm64_str_imm(0, 31, 2))  // 10: argv[0]@[sp,#16]
            s = sbAppend(s, arm64_add_imm(0, 31, 8))  // 11: x0=sp+8
            s = sbAppend(s, arm64_str_imm(0, 31, 3))  // 12: argv[1]@[sp,#24]
            s = sbAppend(s, arm64_str_imm(3, 31, 4))  // 13: argv[2]=cmd@[sp,#32]
            s = sbAppend(s, arm64_str_imm(31, 31, 5))  // 14: argv[3]=NULL@[sp,#40]
            let bumpVaddr_sr = g_DATA_VADDR + 0x4000
            let pcAtAdrp_sr = textVaddr + textOff + (instrIdx + 15) * 4
            let adrpImm21_sr = (bumpVaddr_sr / 4096) - (pcAtAdrp_sr / 4096)
            s = sbAppend(s, arm64_adrp(5, adrpImm21_sr))  // 15
            s = sbAppend(s, arm64_add_imm(5, 5, bumpVaddr_sr % 4096))  // 16
            s = sbAppend(s, arm64_ldr_imm(6, 5, 1))  // 17: argc=[bumpVaddr+8]
            s = sbAppend(s, arm64_ldr_imm(7, 5, 2))  // 18: argv_saved=[+16]
            s = sbAppend(s, arm64_add_imm(6, 6, 1))  // 19: argc+1
            s = sbAppend(s, arm64_movz_x_imm(8, 8))  // 20
            s = sbAppend(s, arm64_mul_xxx(6, 6, 8))  // 21: (argc+1)*8
            s = sbAppend(s, arm64_add_xxx(5, 7, 6))  // 22: envp in x5
            s = sbAppend(s, arm64_movz_x_imm(16, 2))  // 23: SYS_fork
            s = sbAppend(s, arm64_svc(0x80))  // 24
            s = sbAppend(s, arm64_cbnz(1, 51))  // 25: → CHILD@76
            // PARENT: wait4 with status capture, then itoa exit code
            s = sbAppend(s, arm64_add_imm(1, 31, 48))  // 26: x1=&status@[sp+48]
            s = sbAppend(s, arm64_movz_x_imm(2, 0))  // 27: options=0
            s = sbAppend(s, arm64_movz_x_imm(3, 0))  // 28: rusage=NULL
            s = sbAppend(s, arm64_movz_x_imm(16, 7))  // 29: SYS_wait4
            s = sbAppend(s, arm64_svc(0x80))  // 30
            s = sbAppend(s, arm64_ldr_imm(8, 31, 6))  // 31: x8=status@[sp+48]
            s = sbAppend(s, hexDword((0xd348 * 0x10000 + 0xfd08)))  // 32: lsr x8,x8,#8
            s = sbAppend(s, hexDword(0x12001d08))  // 33: and w8,w8,#0xff (WEXITSTATUS)
            s = sbAppend(s, arm64_add_sp(64))  // 34: clean stack
            s = sbAppend(s, emitAllocN(4, instrIdx + 35, textVaddr, textOff))  // 35-55: heap buf→x0
            s = sbAppend(s, arm64_mov_xx(4, 0))  // 56: x4=buf
            s = sbAppend(s, arm64_strb_imm(31, 4, 3))  // 57: buf[3]='\0'
            s = sbAppend(s, arm64_movz_x_imm(9, 10))  // 58: divisor=10
            s = sbAppend(s, arm64_udiv_xxx(10, 8, 9))  // 59: x10=x8/10
            s = sbAppend(s, arm64_msub_xxxx(11, 10, 9, 8))  // 60: x11=ones digit
            s = sbAppend(s, arm64_add_imm(11, 11, 0x30))  // 61: +'0'
            s = sbAppend(s, arm64_strb_imm(11, 4, 2))  // 62: buf[2]=ones
            s = sbAppend(s, arm64_add_imm(5, 4, 2))  // 63: start=buf+2
            s = sbAppend(s, arm64_cbz(10, 10))  // 64: x10==0 → PUSH@74
            s = sbAppend(s, arm64_udiv_xxx(8, 10, 9))  // 65: x8=hundreds
            s = sbAppend(s, arm64_msub_xxxx(12, 8, 9, 10))  // 66: x12=tens digit
            s = sbAppend(s, arm64_add_imm(12, 12, 0x30))  // 67: +'0'
            s = sbAppend(s, arm64_strb_imm(12, 4, 1))  // 68: buf[1]=tens
            s = sbAppend(s, arm64_add_imm(5, 4, 1))  // 69: start=buf+1
            s = sbAppend(s, arm64_cbz(8, 4))  // 70: x8==0 → PUSH@74
            s = sbAppend(s, arm64_add_imm(8, 8, 0x30))  // 71: hundreds+'0'
            s = sbAppend(s, arm64_strb_imm(8, 4, 0))  // 72: buf[0]=hundreds
            s = sbAppend(s, arm64_mov_xx(5, 4))  // 73: start=buf+0
            // PUSH@74:
            s = sbAppend(s, arm64_push(5))  // 74: push result string
            s = sbAppend(s, arm64_b(9))  // 75: → SHELLRUN_DONE@84
            // CHILD path (76-83):
            s = sbAppend(s, arm64_add_imm(0, 31, 0))  // 76: x0=sp="/bin/sh"
            s = sbAppend(s, arm64_add_imm(1, 31, 16))  // 77: x1=argv@sp+16
            s = sbAppend(s, arm64_mov_xx(2, 5))  // 78: x2=envp (x5 from fork)
            s = sbAppend(s, arm64_movz_x_imm(16, 59))  // 79: SYS_execve
            s = sbAppend(s, arm64_svc(0x80))  // 80
            s = sbAppend(s, arm64_movz_x_imm(0, 1))  // 81: exit(1) if execve fails
            s = sbAppend(s, arm64_movz_x_imm(16, 1))  // 82: SYS_exit
            s = sbAppend(s, arm64_svc(0x80))  // 83
            // SHELLRUN_DONE@84
            instrIdx = instrIdx + 84
        } else if opTok == "BUILTIN_MAPHAS" {
            // mapHas(map, key): scan flat "k1,v1,..." pairs. Return 1 if found, 0 if not. 32 instrs.
            s = sbAppend(s, arm64_pop(6))  // 0: key
            s = sbAppend(s, arm64_pop(7))  // 1: map
            // TOKEN_START @ 2:
            s = sbAppend(s, arm64_ldrb_zero(8, 7))  // 2
            s = sbAppend(s, arm64_cbz(8, 27))  // 3: → NOT_FOUND@30
            s = sbAppend(s, arm64_mov_xx(10, 6))  // 4: key ptr
            s = sbAppend(s, arm64_mov_xx(11, 7))  // 5: map cmp ptr
            // CMP_LOOP @ 6:
            s = sbAppend(s, arm64_ldrb_zero(9, 10))  // 6
            s = sbAppend(s, arm64_ldrb_zero(12, 11))  // 7
            s = sbAppend(s, arm64_cmp_xx(9, 12))  // 8
            s = sbAppend(s, arm64_b_cond(0x1, 10))  // 9: b.ne SKIP_K@19
            s = sbAppend(s, arm64_add_imm(10, 10, 1))  // 10
            s = sbAppend(s, arm64_add_imm(11, 11, 1))  // 11
            s = sbAppend(s, arm64_ldrb_zero(9, 10))  // 12
            s = sbAppend(s, arm64_cbz(9, 2))  // 13: → CHK_MAP_DELIM@15
            s = sbAppend(s, arm64_b(0 - 8))  // 14: → CMP_LOOP@6
            // CHK_MAP_DELIM @ 15:
            s = sbAppend(s, arm64_ldrb_zero(12, 11))  // 15
            s = sbAppend(s, arm64_cbz(12, 12))  // 16: → FOUND@28
            s = sbAppend(s, arm64_cmp_imm(12, 0x2c))  // 17
            s = sbAppend(s, arm64_b_cond(0x0, 10))  // 18: b.eq FOUND@28
            // SKIP_K @ 19:
            s = sbAppend(s, arm64_ldrb_post(8, 7, 1))  // 19
            s = sbAppend(s, arm64_cbz(8, 10))  // 20: → NOT_FOUND@30
            s = sbAppend(s, arm64_cmp_imm(8, 0x2c))  // 21
            s = sbAppend(s, arm64_b_cond(0x1, 0 - 3))  // 22: b.ne SKIP_K@19
            // SKIP_V @ 23:
            s = sbAppend(s, arm64_ldrb_post(8, 7, 1))  // 23
            s = sbAppend(s, arm64_cbz(8, 6))  // 24: → NOT_FOUND@30
            s = sbAppend(s, arm64_cmp_imm(8, 0x2c))  // 25
            s = sbAppend(s, arm64_b_cond(0x1, 0 - 3))  // 26: b.ne SKIP_V@23
            s = sbAppend(s, arm64_b(0 - 25))  // 27: → TOKEN_START@2
            // FOUND @ 28:
            s = sbAppend(s, arm64_movz_x_imm(0, 1))  // 28
            s = sbAppend(s, arm64_b(2))  // 29: → DONE@31
            // NOT_FOUND @ 30:
            s = sbAppend(s, arm64_movz_x_imm(0, 0))  // 30
            // DONE @ 31:
            s = sbAppend(s, arm64_push_x0())  // 31
            instrIdx = instrIdx + 32
        } else if opTok == "BUILTIN_EXEC" {
            // exec(cmd): fork+pipe+execve /bin/sh -c cmd, capture stdout. 98 instrs.
            // Instrs 0-35 emitted before emitAllocVar, then 57-97 after.
            s = sbAppend(s, arm64_pop(3))  // 0: cmd
            s = sbAppend(s, arm64_sub_sp(64))  // 1
            s = sbAppend(s, arm64_movz_x_imm(0, 0x622f))  // 2: "/bin/sh\0"
            s = sbAppend(s, arm64_movk_x_imm_lsl16(0, 0x6e69))  // 3
            s = sbAppend(s, arm64_movk_x_imm_lsl32(0, 0x732f))  // 4
            s = sbAppend(s, arm64_movk_x_imm_lsl48(0, 0x0068))  // 5
            s = sbAppend(s, arm64_str_imm(0, 31, 0))  // 6
            s = sbAppend(s, arm64_movz_x_imm(0, 0x632d))  // 7: "-c\0"
            s = sbAppend(s, arm64_str_imm(0, 31, 1))  // 8
            s = sbAppend(s, arm64_add_imm(0, 31, 0))  // 9: x0=sp
            s = sbAppend(s, arm64_str_imm(0, 31, 2))  // 10: argv[0]
            s = sbAppend(s, arm64_add_imm(0, 31, 8))  // 11
            s = sbAppend(s, arm64_str_imm(0, 31, 3))  // 12: argv[1]
            s = sbAppend(s, arm64_str_imm(3, 31, 4))  // 13: argv[2]=cmd
            s = sbAppend(s, arm64_str_imm(31, 31, 5))  // 14: argv[3]=NULL
            let bumpVaddr_ex = g_DATA_VADDR + 0x4000
            let pcAtAdrp_ex = textVaddr + textOff + (instrIdx + 15) * 4
            let adrpImm21_ex = (bumpVaddr_ex / 4096) - (pcAtAdrp_ex / 4096)
            s = sbAppend(s, arm64_adrp(5, adrpImm21_ex))  // 15
            s = sbAppend(s, arm64_add_imm(5, 5, bumpVaddr_ex % 4096))  // 16
            s = sbAppend(s, arm64_ldr_imm(6, 5, 1))  // 17: argc
            s = sbAppend(s, arm64_ldr_imm(7, 5, 2))  // 18: argv_saved
            s = sbAppend(s, arm64_add_imm(6, 6, 1))  // 19: argc+1
            s = sbAppend(s, arm64_movz_x_imm(8, 8))  // 20
            s = sbAppend(s, arm64_mul_xxx(6, 6, 8))  // 21: (argc+1)*8
            s = sbAppend(s, arm64_add_xxx(5, 7, 6))  // 22: envp in x5
            s = sbAppend(s, arm64_movz_x_imm(16, 42))  // 23: SYS_pipe
            s = sbAppend(s, arm64_svc(0x80))  // 24: x0=read_fd x1=write_fd
            s = sbAppend(s, arm64_mov_xx(19, 0))  // 25: save read_fd
            s = sbAppend(s, arm64_mov_xx(20, 1))  // 26: save write_fd
            s = sbAppend(s, arm64_movz_x_imm(16, 2))  // 27: SYS_fork
            s = sbAppend(s, arm64_svc(0x80))  // 28
            s = sbAppend(s, arm64_cbnz(1, 50))  // 29: → CHILD@79
            s = sbAppend(s, arm64_mov_xx(21, 0))  // 30: save child_pid
            s = sbAppend(s, arm64_mov_xx(0, 20))  // 31: close write_fd
            s = sbAppend(s, arm64_movz_x_imm(16, 6))  // 32: SYS_close
            s = sbAppend(s, arm64_svc(0x80))  // 33
            s = sbAppend(s, arm64_add_sp(64))  // 34: restore stack
            s = sbAppend(s, arm64_movz_x_imm_lsl16(4, 1))  // 35: x4=0x10000 (64KB)
            s = sbAppend(s, emitAllocVar(instrIdx + 36, textVaddr, textOff))  // 36-56
            s = sbAppend(s, arm64_mov_xx(22, 0))  // 57: buf ptr
            s = sbAppend(s, arm64_movz_x_imm(23, 0))  // 58: total_read=0
            // READ_LOOP @ 59:
            s = sbAppend(s, arm64_mov_xx(0, 19))  // 59: fd=read_fd
            s = sbAppend(s, arm64_add_xxx(1, 22, 23))  // 60: buf+offset
            s = sbAppend(s, arm64_movz_x_imm(2, 0x1000))  // 61
            s = sbAppend(s, arm64_movz_x_imm(16, 3))  // 62: SYS_read
            s = sbAppend(s, arm64_svc(0x80))  // 63
            s = sbAppend(s, arm64_cbz(0, 3))  // 64: → READ_DONE@67
            s = sbAppend(s, arm64_add_xxx(23, 23, 0))  // 65: total+=bytes
            s = sbAppend(s, arm64_b(0 - 7))  // 66: → READ_LOOP@59
            // READ_DONE @ 67:
            s = sbAppend(s, arm64_mov_xx(0, 19))  // 67: close read_fd
            s = sbAppend(s, arm64_movz_x_imm(16, 6))  // 68
            s = sbAppend(s, arm64_svc(0x80))  // 69
            s = sbAppend(s, arm64_mov_xx(0, 21))  // 70: wait4 pid
            s = sbAppend(s, arm64_movz_x_imm(1, 0))  // 71
            s = sbAppend(s, arm64_movz_x_imm(2, 0))  // 72
            s = sbAppend(s, arm64_movz_x_imm(3, 0))  // 73
            s = sbAppend(s, arm64_movz_x_imm(16, 7))  // 74: SYS_wait4
            s = sbAppend(s, arm64_svc(0x80))  // 75
            s = sbAppend(s, arm64_strb_reg(31, 22, 23))  // 76: NUL@buf[total]
            s = sbAppend(s, arm64_mov_xx(0, 22))  // 77: result=buf
            s = sbAppend(s, arm64_b(19))  // 78: → DONE@97
            // CHILD @ 79:
            s = sbAppend(s, arm64_mov_xx(0, 20))  // 79: dup2(write→stdout)
            s = sbAppend(s, arm64_movz_x_imm(1, 1))  // 80
            s = sbAppend(s, arm64_movz_x_imm(16, 90))  // 81: SYS_dup2
            s = sbAppend(s, arm64_svc(0x80))  // 82
            s = sbAppend(s, arm64_mov_xx(0, 19))  // 83: close read_fd
            s = sbAppend(s, arm64_movz_x_imm(16, 6))  // 84
            s = sbAppend(s, arm64_svc(0x80))  // 85
            s = sbAppend(s, arm64_mov_xx(0, 20))  // 86: close write_fd
            s = sbAppend(s, arm64_movz_x_imm(16, 6))  // 87
            s = sbAppend(s, arm64_svc(0x80))  // 88
            s = sbAppend(s, arm64_add_imm(0, 31, 0))  // 89: x0=sp (path)
            s = sbAppend(s, arm64_add_imm(1, 31, 16))  // 90: x1=argv
            s = sbAppend(s, arm64_mov_xx(2, 5))  // 91: envp
            s = sbAppend(s, arm64_movz_x_imm(16, 59))  // 92: SYS_execve
            s = sbAppend(s, arm64_svc(0x80))  // 93
            s = sbAppend(s, arm64_movz_x_imm(0, 1))  // 94: exit(1)
            s = sbAppend(s, arm64_movz_x_imm(16, 1))  // 95: SYS_exit
            s = sbAppend(s, arm64_svc(0x80))  // 96
            // DONE @ 97:
            s = sbAppend(s, arm64_push_x0())  // 97
            instrIdx = instrIdx + 98
        } else if opTok == "BUILTIN_MAPGET" {
            // mapGet(map, key): scan flat "k1,v1,..." return value or "". 93 instrs.
            s = sbAppend(s, arm64_pop(6))  // 0: key
            s = sbAppend(s, arm64_pop(7))  // 1: map
            // TOKEN_START @ 2:
            s = sbAppend(s, arm64_ldrb_zero(8, 7))  // 2
            s = sbAppend(s, arm64_cbz(8, 66))  // 3: → NOT_FOUND@69
            s = sbAppend(s, arm64_mov_xx(10, 6))  // 4
            s = sbAppend(s, arm64_mov_xx(11, 7))  // 5
            // CMP_LOOP @ 6:
            s = sbAppend(s, arm64_ldrb_zero(9, 10))  // 6
            s = sbAppend(s, arm64_ldrb_zero(12, 11))  // 7
            s = sbAppend(s, arm64_cmp_xx(9, 12))  // 8
            s = sbAppend(s, arm64_b_cond(0x1, 11))  // 9: b.ne SKIP_K@20
            s = sbAppend(s, arm64_add_imm(10, 10, 1))  // 10
            s = sbAppend(s, arm64_add_imm(11, 11, 1))  // 11
            s = sbAppend(s, arm64_ldrb_zero(9, 10))  // 12
            s = sbAppend(s, arm64_cbz(9, 2))  // 13: → CHK_MAP_DELIM@15
            s = sbAppend(s, arm64_b(0 - 8))  // 14: → CMP_LOOP@6
            // CHK_MAP_DELIM @ 15:
            s = sbAppend(s, arm64_ldrb_zero(12, 11))  // 15
            s = sbAppend(s, arm64_cbz(12, 53))  // 16: → NOT_FOUND@69
            s = sbAppend(s, arm64_cmp_imm(12, 0x2c))  // 17
            s = sbAppend(s, arm64_b_cond(0x1, 2))  // 18: b.ne SKIP_K@20
            s = sbAppend(s, arm64_b(10))  // 19: → FOUND_VALUE@29
            // SKIP_K @ 20:
            s = sbAppend(s, arm64_ldrb_post(8, 7, 1))  // 20
            s = sbAppend(s, arm64_cbz(8, 48))  // 21: → NOT_FOUND@69
            s = sbAppend(s, arm64_cmp_imm(8, 0x2c))  // 22
            s = sbAppend(s, arm64_b_cond(0x1, 0 - 3))  // 23: b.ne SKIP_K@20
            // SKIP_V @ 24:
            s = sbAppend(s, arm64_ldrb_post(8, 7, 1))  // 24
            s = sbAppend(s, arm64_cbz(8, 44))  // 25: → NOT_FOUND@69
            s = sbAppend(s, arm64_cmp_imm(8, 0x2c))  // 26
            s = sbAppend(s, arm64_b_cond(0x1, 0 - 3))  // 27: b.ne SKIP_V@24
            s = sbAppend(s, arm64_b(0 - 26))  // 28: → TOKEN_START@2
            // FOUND_VALUE @ 29:
            s = sbAppend(s, arm64_add_imm(11, 11, 1))  // 29: skip comma
            s = sbAppend(s, arm64_mov_xx(20, 11))  // 30: save val start
            // VAL_SCAN @ 31:
            s = sbAppend(s, arm64_ldrb_zero(9, 11))  // 31
            s = sbAppend(s, arm64_cbz(9, 5))  // 32: → VAL_END@37
            s = sbAppend(s, arm64_cmp_imm(9, 0x2c))  // 33
            s = sbAppend(s, arm64_b_cond(0x0, 3))  // 34: b.eq VAL_END@37
            s = sbAppend(s, arm64_add_imm(11, 11, 1))  // 35
            s = sbAppend(s, arm64_b(0 - 5))  // 36: → VAL_SCAN@31
            // VAL_END @ 37:
            s = sbAppend(s, arm64_sub_xxx(13, 11, 20))  // 37: len=end-start
            s = sbAppend(s, arm64_add_imm(4, 13, 1))  // 38: x4=len+1
            instrIdx = instrIdx + 39
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))  // 39-59: x0=dest
            instrIdx = instrIdx + 21
            // COPY @ 60:
            s = sbAppend(s, arm64_movz_x_imm(14, 0))  // 60: i=0
            // COPY_LOOP @ 61:
            s = sbAppend(s, arm64_cmp_xx(14, 13))  // 61
            s = sbAppend(s, arm64_b_cond(0xa, 5))  // 62: b.ge COPY_DONE@67
            s = sbAppend(s, arm64_ldrb_reg(15, 20, 14))  // 63
            s = sbAppend(s, arm64_strb_reg(15, 0, 14))  // 64
            s = sbAppend(s, arm64_add_imm(14, 14, 1))  // 65
            s = sbAppend(s, arm64_b(0 - 5))  // 66: → COPY_LOOP@61
            // COPY_DONE @ 67:
            s = sbAppend(s, arm64_strb_reg(31, 0, 13))  // 67: NUL@dest[len]
            s = sbAppend(s, arm64_b(24))  // 68: → DONE@92
            instrIdx = instrIdx + 9
            // NOT_FOUND @ 69:
            s = sbAppend(s, arm64_movz_x_imm(4, 1))  // 69: alloc 1 byte
            instrIdx = instrIdx + 1
            s = sbAppend(s, emitAllocN(1, instrIdx, textVaddr, textOff))  // 70-90
            instrIdx = instrIdx + 21
            s = sbAppend(s, arm64_strb_imm(31, 0, 0))  // 91: NUL→empty string
            // DONE @ 92:
            s = sbAppend(s, arm64_push_x0())  // 92
            instrIdx = instrIdx + 2
        } else if opTok == "BUILTIN_MAPSET" {
            // mapSet(map, key, value): update/insert key in flat "k1,v1,..." map. 150 instrs.
            // Stack: TOS=value, next=key, next=map
            s = sbAppend(s, arm64_pop(6))  // 0: value
            s = sbAppend(s, arm64_pop(7))  // 1: key
            s = sbAppend(s, arm64_pop(8))  // 2: map
            s = sbAppend(s, arm64_mov_xx(11, 8))  // 3: strlen(map)
            s = sbAppend(s, arm64_ldrb_post(12, 11, 1))  // 4: STRLEN_MAP
            s = sbAppend(s, arm64_cbnz(12, 0 - 1))  // 5: → 4
            s = sbAppend(s, arm64_sub_xxx(9, 11, 8))  // 6
            s = sbAppend(s, arm64_sub_imm(9, 9, 1))  // 7: map_len
            s = sbAppend(s, arm64_mov_xx(11, 7))  // 8: strlen(key)
            s = sbAppend(s, arm64_ldrb_post(12, 11, 1))  // 9: STRLEN_KEY
            s = sbAppend(s, arm64_cbnz(12, 0 - 1))  // 10: → 9
            s = sbAppend(s, arm64_sub_xxx(10, 11, 7))  // 11
            s = sbAppend(s, arm64_sub_imm(10, 10, 1))  // 12: key_len
            s = sbAppend(s, arm64_mov_xx(11, 6))  // 13: strlen(val)
            s = sbAppend(s, arm64_ldrb_post(12, 11, 1))  // 14: STRLEN_VAL
            s = sbAppend(s, arm64_cbnz(12, 0 - 1))  // 15: → 14
            s = sbAppend(s, arm64_sub_xxx(13, 11, 6))  // 16
            s = sbAppend(s, arm64_sub_imm(13, 13, 1))  // 17: val_len
            s = sbAppend(s, arm64_add_xxx(4, 9, 10))  // 18: map_len+key_len
            s = sbAppend(s, arm64_add_xxx(4, 4, 13))  // 19: +val_len
            s = sbAppend(s, arm64_add_imm(4, 4, 3))  // 20: +3 (commas+NUL)
            instrIdx = instrIdx + 21
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))  // 21-41: x0=buf
            instrIdx = instrIdx + 21
            s = sbAppend(s, arm64_mov_xx(20, 0))  // 42: buf start
            s = sbAppend(s, arm64_mov_xx(21, 0))  // 43: write ptr
            s = sbAppend(s, arm64_mov_xx(22, 8))  // 44: map read ptr
            s = sbAppend(s, arm64_movz_x_imm(23, 0))  // 45: found=0
            // PAIR_LOOP @ 46:
            s = sbAppend(s, arm64_ldrb_zero(12, 22))  // 46
            s = sbAppend(s, arm64_cbz(12, 77))  // 47: → AFTER_MAP@124
            // leading comma if output non-empty:
            s = sbAppend(s, arm64_cmp_xx(21, 20))  // 48
            s = sbAppend(s, arm64_b_cond(0x0, 4))  // 49: b.eq NO_COMMA@53
            s = sbAppend(s, arm64_movz_x_imm(14, 0x2c))  // 50
            s = sbAppend(s, arm64_strb_imm(14, 21, 0))  // 51
            s = sbAppend(s, arm64_add_imm(21, 21, 1))  // 52
            // NO_COMMA @ 53: compare token at x22 with key x7
            s = sbAppend(s, arm64_mov_xx(10, 7))  // 53
            s = sbAppend(s, arm64_mov_xx(11, 22))  // 54
            // CMP_LOOP @ 55:
            s = sbAppend(s, arm64_ldrb_zero(14, 10))  // 55
            s = sbAppend(s, arm64_ldrb_zero(15, 11))  // 56
            s = sbAppend(s, arm64_cmp_xx(14, 15))  // 57
            s = sbAppend(s, arm64_b_cond(0x1, 10))  // 58: b.ne COPY_PAIR@68
            s = sbAppend(s, arm64_add_imm(10, 10, 1))  // 59
            s = sbAppend(s, arm64_add_imm(11, 11, 1))  // 60
            s = sbAppend(s, arm64_ldrb_zero(14, 10))  // 61
            s = sbAppend(s, arm64_cbz(14, 2))  // 62: → CHK_MAP_D3@64
            s = sbAppend(s, arm64_b(0 - 8))  // 63: → CMP_LOOP@55
            // CHK_MAP_D3 @ 64:
            s = sbAppend(s, arm64_ldrb_zero(15, 11))  // 64
            s = sbAppend(s, arm64_cbz(15, 26))  // 65: → MATCHED@91
            s = sbAppend(s, arm64_cmp_imm(15, 0x2c))  // 66
            s = sbAppend(s, arm64_b_cond(0x0, 24))  // 67: b.eq MATCHED@91
            // COPY_PAIR @ 68: copy old key+value to output
            s = sbAppend(s, arm64_ldrb_zero(14, 22))  // 68: COPY_KEY
            s = sbAppend(s, arm64_cbz(14, 54))  // 69: → PAIR_LOOP_BACK@123
            s = sbAppend(s, arm64_cmp_imm(14, 0x2c))  // 70
            s = sbAppend(s, arm64_b_cond(0x0, 5))  // 71: b.eq CP_KEY_COMMA@76
            s = sbAppend(s, arm64_strb_imm(14, 21, 0))  // 72
            s = sbAppend(s, arm64_add_imm(21, 21, 1))  // 73
            s = sbAppend(s, arm64_add_imm(22, 22, 1))  // 74
            s = sbAppend(s, arm64_b(0 - 7))  // 75: → COPY_KEY@68
            // CP_KEY_COMMA @ 76:
            s = sbAppend(s, arm64_add_imm(22, 22, 1))  // 76: skip comma
            s = sbAppend(s, arm64_movz_x_imm(14, 0x2c))  // 77: write ','
            s = sbAppend(s, arm64_strb_imm(14, 21, 0))  // 78
            s = sbAppend(s, arm64_add_imm(21, 21, 1))  // 79
            // COPY_VAL @ 80:
            s = sbAppend(s, arm64_ldrb_zero(14, 22))  // 80
            s = sbAppend(s, arm64_cbz(14, 42))  // 81: → PAIR_LOOP_BACK@123
            s = sbAppend(s, arm64_cmp_imm(14, 0x2c))  // 82
            s = sbAppend(s, arm64_b_cond(0x0, 5))  // 83: b.eq CP_VAL_COMMA@88
            s = sbAppend(s, arm64_strb_imm(14, 21, 0))  // 84
            s = sbAppend(s, arm64_add_imm(21, 21, 1))  // 85
            s = sbAppend(s, arm64_add_imm(22, 22, 1))  // 86
            s = sbAppend(s, arm64_b(0 - 7))  // 87: → COPY_VAL@80
            // CP_VAL_COMMA @ 88:
            s = sbAppend(s, arm64_add_imm(22, 22, 1))  // 88: skip comma
            s = sbAppend(s, arm64_b(0 - 43))  // 89: → PAIR_LOOP@46
            // (gap @ 90 — unreachable, pad for alignment)
            s = sbAppend(s, arm64_nop())  // 90
            // MATCHED @ 91: write new key+comma+value, skip old pair
            s = sbAppend(s, arm64_movz_x_imm(23, 1))  // 91: found=1
            s = sbAppend(s, arm64_mov_xx(10, 7))  // 92: key src
            // WRITE_KEY_LOOP @ 93:
            s = sbAppend(s, arm64_ldrb_zero(14, 10))  // 93
            s = sbAppend(s, arm64_cbz(14, 5))  // 94: → WRITE_KEY_DONE@99
            s = sbAppend(s, arm64_strb_imm(14, 21, 0))  // 95
            s = sbAppend(s, arm64_add_imm(21, 21, 1))  // 96
            s = sbAppend(s, arm64_add_imm(10, 10, 1))  // 97
            s = sbAppend(s, arm64_b(0 - 5))  // 98: → WRITE_KEY_LOOP@93
            // WRITE_KEY_DONE @ 99:
            s = sbAppend(s, arm64_movz_x_imm(14, 0x2c))  // 99
            s = sbAppend(s, arm64_strb_imm(14, 21, 0))  // 100
            s = sbAppend(s, arm64_add_imm(21, 21, 1))  // 101
            s = sbAppend(s, arm64_mov_xx(10, 6))  // 102: value src
            // WRITE_VAL_LOOP @ 103:
            s = sbAppend(s, arm64_ldrb_zero(14, 10))  // 103
            s = sbAppend(s, arm64_cbz(14, 5))  // 104: → WRITE_VAL_DONE@109
            s = sbAppend(s, arm64_strb_imm(14, 21, 0))  // 105
            s = sbAppend(s, arm64_add_imm(21, 21, 1))  // 106
            s = sbAppend(s, arm64_add_imm(10, 10, 1))  // 107
            s = sbAppend(s, arm64_b(0 - 5))  // 108: → WRITE_VAL_LOOP@103
            // WRITE_VAL_DONE @ 109: skip old key in map (x22 at old key start)
            s = sbAppend(s, arm64_ldrb_zero(14, 22))  // 109: SKIP_OLD_KEY
            s = sbAppend(s, arm64_cbz(14, 13))  // 110: → PAIR_LOOP_BACK@123
            s = sbAppend(s, arm64_cmp_imm(14, 0x2c))  // 111
            s = sbAppend(s, arm64_b_cond(0x0, 3))  // 112: b.eq PAST_KEY_COMMA@115
            s = sbAppend(s, arm64_add_imm(22, 22, 1))  // 113
            s = sbAppend(s, arm64_b(0 - 5))  // 114: → SKIP_OLD_KEY@109
            // PAST_KEY_COMMA @ 115:
            s = sbAppend(s, arm64_add_imm(22, 22, 1))  // 115
            // SKIP_OLD_VAL @ 116:
            s = sbAppend(s, arm64_ldrb_zero(14, 22))  // 116
            s = sbAppend(s, arm64_cbz(14, 6))  // 117: → PAIR_LOOP_BACK@123
            s = sbAppend(s, arm64_cmp_imm(14, 0x2c))  // 118
            s = sbAppend(s, arm64_b_cond(0x0, 3))  // 119: b.eq PAST_VAL_COMMA@122
            s = sbAppend(s, arm64_add_imm(22, 22, 1))  // 120
            s = sbAppend(s, arm64_b(0 - 5))  // 121: → SKIP_OLD_VAL@116
            // PAST_VAL_COMMA @ 122:
            s = sbAppend(s, arm64_add_imm(22, 22, 1))  // 122
            // PAIR_LOOP_BACK @ 123:
            s = sbAppend(s, arm64_b(0 - 77))  // 123: → PAIR_LOOP@46
            // AFTER_MAP @ 124:
            s = sbAppend(s, arm64_cbnz(23, 23))  // 124: → NUL_DONE@147
            s = sbAppend(s, arm64_cmp_xx(21, 20))  // 125
            s = sbAppend(s, arm64_b_cond(0x0, 4))  // 126: b.eq NO_COMMA_APPEND@130
            s = sbAppend(s, arm64_movz_x_imm(14, 0x2c))  // 127
            s = sbAppend(s, arm64_strb_imm(14, 21, 0))  // 128
            s = sbAppend(s, arm64_add_imm(21, 21, 1))  // 129
            // NO_COMMA_APPEND @ 130:
            s = sbAppend(s, arm64_mov_xx(10, 7))  // 130
            // WRITE_KEY2_LOOP @ 131:
            s = sbAppend(s, arm64_ldrb_zero(14, 10))  // 131
            s = sbAppend(s, arm64_cbz(14, 5))  // 132: → WRITE_K2_DONE@137
            s = sbAppend(s, arm64_strb_imm(14, 21, 0))  // 133
            s = sbAppend(s, arm64_add_imm(21, 21, 1))  // 134
            s = sbAppend(s, arm64_add_imm(10, 10, 1))  // 135
            s = sbAppend(s, arm64_b(0 - 5))  // 136: → WRITE_KEY2_LOOP@131
            // WRITE_K2_DONE @ 137:
            s = sbAppend(s, arm64_movz_x_imm(14, 0x2c))  // 137
            s = sbAppend(s, arm64_strb_imm(14, 21, 0))  // 138
            s = sbAppend(s, arm64_add_imm(21, 21, 1))  // 139
            s = sbAppend(s, arm64_mov_xx(10, 6))  // 140
            // WRITE_VAL2_LOOP @ 141:
            s = sbAppend(s, arm64_ldrb_zero(14, 10))  // 141
            s = sbAppend(s, arm64_cbz(14, 5))  // 142: → NUL_DONE@147
            s = sbAppend(s, arm64_strb_imm(14, 21, 0))  // 143
            s = sbAppend(s, arm64_add_imm(21, 21, 1))  // 144
            s = sbAppend(s, arm64_add_imm(10, 10, 1))  // 145
            s = sbAppend(s, arm64_b(0 - 5))  // 146: → WRITE_VAL2_LOOP@141
            // NUL_DONE @ 147:
            s = sbAppend(s, arm64_strb_imm(31, 21, 0))  // 147: NUL-terminate
            s = sbAppend(s, arm64_mov_xx(0, 20))  // 148: result=buf
            s = sbAppend(s, arm64_push_x0())  // 149
            instrIdx = instrIdx + 108
        } else if opTok == "LOAD_SLOT" {
            let slot = toInt(restTok)
            let off = 0 - (8 + slot * 8)
            if off >= 0 - 256 {
                s = sbAppend(s, arm64_ldur(0, 29, off))
                s = sbAppend(s, arm64_push_x0())
                instrIdx = instrIdx + 2
            } else {
                s = sbAppend(s, arm64_sub_imm(9, 29, 0 - off))
                s = sbAppend(s, arm64_ldr_imm(0, 9, 0))
                s = sbAppend(s, arm64_push_x0())
                instrIdx = instrIdx + 3
            }
        } else if opTok == "STORE_SLOT" {
            let slot = toInt(restTok)
            let off = 0 - (8 + slot * 8)
            s = sbAppend(s, arm64_pop_x0())
            if off >= 0 - 256 {
                s = sbAppend(s, arm64_stur(0, 29, off))
                instrIdx = instrIdx + 2
            } else {
                s = sbAppend(s, arm64_sub_imm(9, 29, 0 - off))
                s = sbAppend(s, arm64_str_imm(0, 9, 0))
                instrIdx = instrIdx + 3
            }
        } else if opTok == "LOAD_GLOBAL" {
            let gIdx = toInt(restTok)
            let glbOffFromText = g_TEXT_VMSIZE + 0x6F004000 + gIdx * 8  // globals near top of DATA, above the bump heap
            let imm21lg = glbOffFromText / 4096 - (textOff + instrIdx * 4) / 4096
            s = sbAppend(s, arm64_adrp(0, imm21lg))
            s = sbAppend(s, arm64_add_imm(0, 0, (gIdx * 8) % 4096))
            s = sbAppend(s, arm64_ldr_imm(0, 0, 0))
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 4
        } else if opTok == "STORE_GLOBAL" {
            let gIdx = toInt(restTok)
            let glbOffFromText = g_TEXT_VMSIZE + 0x6F004000 + gIdx * 8  // globals near top of DATA, above the bump heap
            s = sbAppend(s, arm64_pop_x0())
            instrIdx = instrIdx + 1
            let imm21sg = glbOffFromText / 4096 - (textOff + instrIdx * 4) / 4096
            s = sbAppend(s, arm64_adrp(1, imm21sg))
            s = sbAppend(s, arm64_add_imm(1, 1, (gIdx * 8) % 4096))
            s = sbAppend(s, arm64_str_imm(0, 1, 0))
            instrIdx = instrIdx + 3
        } else if opTok == "BUILTIN_BITAND" {
            s = sbAppend(s, arm64_pop(1))
            s = sbAppend(s, arm64_pop(0))
            s = sbAppend(s, arm64_and_www(0, 0, 1))
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 4
        } else if opTok == "BUILTIN_BITOR" {
            s = sbAppend(s, arm64_pop(1))
            s = sbAppend(s, arm64_pop(0))
            s = sbAppend(s, arm64_orr_www(0, 0, 1))
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 4
        } else if opTok == "BUILTIN_BITXOR" {
            s = sbAppend(s, arm64_pop(1))
            s = sbAppend(s, arm64_pop(0))
            s = sbAppend(s, arm64_eor_www(0, 0, 1))
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 4
        } else if opTok == "BUILTIN_BITSHR" {
            s = sbAppend(s, arm64_pop(1))
            s = sbAppend(s, arm64_pop(0))
            s = sbAppend(s, arm64_lsr_w(0, 0, 1))
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 4
        } else if opTok == "BUILTIN_BITSHL" {
            s = sbAppend(s, arm64_pop(1))
            s = sbAppend(s, arm64_pop(0))
            s = sbAppend(s, arm64_lsl_w(0, 0, 1))
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 4
        } else if opTok == "BUILTIN_BITNOT" {
            s = sbAppend(s, arm64_pop(0))
            s = sbAppend(s, arm64_mvn_w(0, 0))
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 3
        } else if opTok == "BUILTIN_KP" {
            // kp(v): write v to stdout + newline. Handles both strings and ints.
            // Dispatch: if v < 0 it's an int; else a pointer (heap or __TEXT).
            // String path = 19 instr (was 21 — same as before, sans pop).
            // Int path = inline itoa + write. 69 instructions total.
            s = sbAppend(s, arm64_pop(3))  // 0: x3 = arg
            s = sbAppend(s, arm64_movz_x_imm_lsl32(14, 1))  // 1: x14 = 1<<32
            s = sbAppend(s, arm64_cmp_xx(3, 14))  // 2
            s = sbAppend(s, arm64_b_cond(0xb, 20))  // 3: b.lt INT_PATH (idx 23)
            // ── STRING PATH (idx 4..22) ──
            s = sbAppend(s, arm64_mov_xx(1, 3))  // 4
            s = sbAppend(s, arm64_ldrb_post(4, 1, 1))  // 5
            s = sbAppend(s, arm64_cbnz(4, 0 - 1))  // 6: scan NUL
            s = sbAppend(s, arm64_sub_xxx(2, 1, 3))  // 7
            s = sbAppend(s, arm64_sub_imm(2, 2, 1))  // 8: len
            s = sbAppend(s, arm64_movz_x_imm(0, 1))  // 9: stdout
            s = sbAppend(s, arm64_mov_xx(1, 3))  // 10
            s = sbAppend(s, arm64_movz_x_imm(16, 4))  // 11: SYS_write
            s = sbAppend(s, arm64_svc(0x80))  // 12
            s = sbAppend(s, arm64_movz_w_imm(4, 0x0A))  // 13: '\n'
            s = sbAppend(s, arm64_sub_imm(31, 31, 16))  // 14: sub sp, sp, #16
            s = sbAppend(s, arm64_strb_imm(4, 31, 0))  // 15: strb '\n', [sp]
            s = sbAppend(s, arm64_add_imm(1, 31, 0))  // 16: x1 = sp
            s = sbAppend(s, arm64_movz_x_imm(2, 1))  // 17
            s = sbAppend(s, arm64_movz_x_imm(0, 1))  // 18
            s = sbAppend(s, arm64_movz_x_imm(16, 4))  // 19
            s = sbAppend(s, arm64_svc(0x80))  // 20: write \n
            s = sbAppend(s, arm64_add_imm(31, 31, 16))  // 21: restore sp
            s = sbAppend(s, arm64_b(46))  // 22: → DONE (idx 68)
            // ── INT PATH @ idx 23 ── itoa to stack buffer, then print ──
            s = sbAppend(s, arm64_sub_imm(31, 31, 32))  // 23: 24-byte buf + 16B align
            s = sbAppend(s, arm64_add_imm(4, 31, 23))  // 24: x4 = sp+23 (end-1)
            s = sbAppend(s, arm64_strb_imm(31, 4, 0))  // 25: *p = NUL (Rt=31 = xzr)
            s = sbAppend(s, arm64_movz_x_imm(5, 0))  // 26: neg = 0
            s = sbAppend(s, arm64_cmp_imm(3, 0))  // 27: cmp n, 0
            s = sbAppend(s, arm64_b_cond(0xa, 3))  // 28: b.ge POSITIVE (idx 31)
            s = sbAppend(s, arm64_movz_x_imm(5, 1))  // 29: neg = 1
            s = sbAppend(s, arm64_neg(3, 3))  // 30: n = -n
            // POSITIVE @ idx 31:
            s = sbAppend(s, arm64_cbnz(3, 5))  // 31: → INT_LOOP (idx 36)
            // n == 0 case: write single '0'
            s = sbAppend(s, arm64_sub_imm(4, 4, 1))  // 32
            s = sbAppend(s, arm64_movz_w_imm(6, 0x30))  // 33: '0'
            s = sbAppend(s, arm64_strb_imm(6, 4, 0))  // 34
            s = sbAppend(s, arm64_b(10))  // 35: → INT_SIGN (idx 45)
            // INT_LOOP @ idx 36:
            s = sbAppend(s, arm64_cbz(3, 9))  // 36: → INT_SIGN (idx 45)
            s = sbAppend(s, arm64_movz_x_imm(7, 10))  // 37
            s = sbAppend(s, arm64_udiv_xxx(8, 3, 7))  // 38: q = n / 10
            s = sbAppend(s, arm64_msub_xxxx(9, 8, 7, 3))  // 39: r = n - q*10
            s = sbAppend(s, arm64_add_imm(9, 9, 0x30))  // 40: r += '0'
            s = sbAppend(s, arm64_sub_imm(4, 4, 1))  // 41
            s = sbAppend(s, arm64_strb_imm(9, 4, 0))  // 42
            s = sbAppend(s, arm64_mov_xx(3, 8))  // 43: n = q
            s = sbAppend(s, arm64_b(0 - 8))  // 44: → INT_LOOP
            // INT_SIGN @ idx 45:
            s = sbAppend(s, arm64_cbz(5, 4))  // 45: → INT_PRINT (idx 49)
            s = sbAppend(s, arm64_sub_imm(4, 4, 1))  // 46
            s = sbAppend(s, arm64_movz_w_imm(6, 0x2D))  // 47: '-'
            s = sbAppend(s, arm64_strb_imm(6, 4, 0))  // 48
            // INT_PRINT @ idx 49: x4 = start of string
            s = sbAppend(s, arm64_mov_xx(1, 4))  // 49: scan from buf start
            s = sbAppend(s, arm64_ldrb_post(6, 1, 1))  // 50
            s = sbAppend(s, arm64_cbnz(6, 0 - 1))  // 51: scan to NUL
            s = sbAppend(s, arm64_sub_xxx(2, 1, 4))  // 52
            s = sbAppend(s, arm64_sub_imm(2, 2, 1))  // 53: real len
            s = sbAppend(s, arm64_movz_x_imm(0, 1))  // 54: stdout
            s = sbAppend(s, arm64_mov_xx(1, 4))  // 55
            s = sbAppend(s, arm64_movz_x_imm(16, 4))  // 56
            s = sbAppend(s, arm64_svc(0x80))  // 57: write digits
            // newline (reuse NUL byte at buf[23])
            s = sbAppend(s, arm64_movz_w_imm(6, 0x0A))  // 58
            s = sbAppend(s, arm64_add_imm(10, 31, 23))  // 59: x10 = sp+23
            s = sbAppend(s, arm64_strb_imm(6, 10, 0))  // 60: *(sp+23) = '\n'
            s = sbAppend(s, arm64_mov_xx(1, 10))  // 61
            s = sbAppend(s, arm64_movz_x_imm(2, 1))  // 62
            s = sbAppend(s, arm64_movz_x_imm(0, 1))  // 63
            s = sbAppend(s, arm64_movz_x_imm(16, 4))  // 64
            s = sbAppend(s, arm64_svc(0x80))  // 65: write \n
            s = sbAppend(s, arm64_add_imm(31, 31, 32))  // 66: restore sp
            // DONE @ idx 67:
            s = sbAppend(s, arm64_movz_w_imm(0, 0))  // 67
            s = sbAppend(s, arm64_push_x0())  // 68
            instrIdx = instrIdx + 69
        } else if opTok == "CALL_FUNC" {
            // restTok = "<name> <argc>"
            let s2 = 0
            while s2 < len(restTok) && restTok[s2] != " " { s2 += 1 }
            let cname = substring(restTok, 0, s2)
            let argc = 0
            if s2 < len(restTok) { argc = toInt(trim(substring(restTok, s2 + 1, len(restTok)))) }
            // objk NSRect form: objc_msgSend_rect(obj, sel, x, y, w, h, mask, backing, defer)
            // arm64 AAPCS: self x0, sel x1, NSRect{x,y,w,h} -> d0..d3, mask x2, backing x3, defer x4.
            if cname == "objc_msgSend_rect" {
                s = sbAppend(s, arm64_pop(4))  instrIdx = instrIdx + 1   // defer
                s = sbAppend(s, arm64_pop(3))  instrIdx = instrIdx + 1   // backing
                s = sbAppend(s, arm64_pop(2))  instrIdx = instrIdx + 1   // mask
                s = sbAppend(s, arm64_pop(9))  instrIdx = instrIdx + 1   // h
                s = sbAppend(s, arm64_scvtf_d_x(3, 9))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_pop(9))  instrIdx = instrIdx + 1   // w
                s = sbAppend(s, arm64_scvtf_d_x(2, 9))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_pop(9))  instrIdx = instrIdx + 1   // y
                s = sbAppend(s, arm64_scvtf_d_x(1, 9))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_pop(9))  instrIdx = instrIdx + 1   // x
                s = sbAppend(s, arm64_scvtf_d_x(0, 9))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_pop(1))  instrIdx = instrIdx + 1   // sel
                s = sbAppend(s, arm64_pop(0))  instrIdx = instrIdx + 1   // obj
                let rti = textSz / 4 + foreignIdx("objc_msgSend_rect") * 3
                s = sbAppend(s, arm64_bl(rti - instrIdx))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_push(0))  instrIdx = instrIdx + 1
            } else if cname == "objc_msgSend_frame" {
                // (obj,sel,x,y,w,h): NSRect{x,y,w,h} -> d0..d3 (initWithFrame:)
                s = sbAppend(s, arm64_pop(9))  instrIdx = instrIdx + 1   // h
                s = sbAppend(s, arm64_scvtf_d_x(3, 9))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_pop(9))  instrIdx = instrIdx + 1   // w
                s = sbAppend(s, arm64_scvtf_d_x(2, 9))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_pop(9))  instrIdx = instrIdx + 1   // y
                s = sbAppend(s, arm64_scvtf_d_x(1, 9))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_pop(9))  instrIdx = instrIdx + 1   // x
                s = sbAppend(s, arm64_scvtf_d_x(0, 9))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_pop(1))  instrIdx = instrIdx + 1   // sel
                s = sbAppend(s, arm64_pop(0))  instrIdx = instrIdx + 1   // obj
                let fti = textSz / 4 + foreignIdx("objc_msgSend_frame") * 3
                s = sbAppend(s, arm64_bl(fti - instrIdx))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_push(0))  instrIdx = instrIdx + 1
            } else if cname == "objc_msgSend_d1" {
                // (obj,sel,n): n -> d0 (CGFloat), self x0, sel x1
                s = sbAppend(s, arm64_pop(9))  instrIdx = instrIdx + 1   // n
                s = sbAppend(s, arm64_scvtf_d_x(0, 9))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_pop(1))  instrIdx = instrIdx + 1   // sel
                s = sbAppend(s, arm64_pop(0))  instrIdx = instrIdx + 1   // obj
                let dti = textSz / 4 + foreignIdx("objc_msgSend_d1") * 3
                s = sbAppend(s, arm64_bl(dti - instrIdx))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_push(0))  instrIdx = instrIdx + 1
            } else if cname == "objc_msgSend_rectp" {
                // (obj,sel,x,y,w,h,p): NSRect{x,y,w,h} -> d0..d3, ptr -> x2 (drawInRect:withAttributes:)
                s = sbAppend(s, arm64_pop(2))  instrIdx = instrIdx + 1   // p
                s = sbAppend(s, arm64_pop(9))  instrIdx = instrIdx + 1   // h
                s = sbAppend(s, arm64_scvtf_d_x(3, 9))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_pop(9))  instrIdx = instrIdx + 1   // w
                s = sbAppend(s, arm64_scvtf_d_x(2, 9))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_pop(9))  instrIdx = instrIdx + 1   // y
                s = sbAppend(s, arm64_scvtf_d_x(1, 9))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_pop(9))  instrIdx = instrIdx + 1   // x
                s = sbAppend(s, arm64_scvtf_d_x(0, 9))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_pop(1))  instrIdx = instrIdx + 1   // sel
                s = sbAppend(s, arm64_pop(0))  instrIdx = instrIdx + 1   // obj
                let pti = textSz / 4 + foreignIdx("objc_msgSend_rectp") * 3
                s = sbAppend(s, arm64_bl(pti - instrIdx))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_push(0))  instrIdx = instrIdx + 1
            } else if cname == "objc_msgSend_timer" {
                // (self,sel,ms,target,actsel,info,rep): ms/1000.0 -> d0 (TimeInterval),
                // target x2, actsel x3, info x4, rep x5
                s = sbAppend(s, arm64_pop(5))  instrIdx = instrIdx + 1   // repeats
                s = sbAppend(s, arm64_pop(4))  instrIdx = instrIdx + 1   // userInfo
                s = sbAppend(s, arm64_pop(3))  instrIdx = instrIdx + 1   // actsel
                s = sbAppend(s, arm64_pop(2))  instrIdx = instrIdx + 1   // target
                s = sbAppend(s, arm64_pop(9))  instrIdx = instrIdx + 1   // ms
                s = sbAppend(s, arm64_scvtf_d_x(0, 9))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_movz_x_imm(10, 1000))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_scvtf_d_x(1, 10))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_fdiv_d(0, 0, 1))  instrIdx = instrIdx + 1   // d0 = ms/1000.0
                s = sbAppend(s, arm64_pop(1))  instrIdx = instrIdx + 1   // sel
                s = sbAppend(s, arm64_pop(0))  instrIdx = instrIdx + 1   // self
                let tti = textSz / 4 + foreignIdx("objc_msgSend_timer") * 3
                s = sbAppend(s, arm64_bl(tti - instrIdx))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_push(0))  instrIdx = instrIdx + 1
            } else if cname == "objc_msgSend_rgb" {
                // (self,sel,r,g,b): r/255->d0, g/255->d1, b/255->d2, alpha 1.0->d3
                s = sbAppend(s, arm64_pop(9))  instrIdx = instrIdx + 1   // b
                s = sbAppend(s, arm64_scvtf_d_x(2, 9))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_pop(9))  instrIdx = instrIdx + 1   // g
                s = sbAppend(s, arm64_scvtf_d_x(1, 9))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_pop(9))  instrIdx = instrIdx + 1   // r
                s = sbAppend(s, arm64_scvtf_d_x(0, 9))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_movz_x_imm(10, 255))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_scvtf_d_x(3, 10))  instrIdx = instrIdx + 1   // d3 = 255.0
                s = sbAppend(s, arm64_fdiv_d(0, 0, 3))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_fdiv_d(1, 1, 3))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_fdiv_d(2, 2, 3))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_movz_x_imm(10, 1))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_scvtf_d_x(3, 10))  instrIdx = instrIdx + 1   // d3 = 1.0 (alpha)
                s = sbAppend(s, arm64_pop(1))  instrIdx = instrIdx + 1   // sel
                s = sbAppend(s, arm64_pop(0))  instrIdx = instrIdx + 1   // self
                let rgi = textSz / 4 + foreignIdx("objc_msgSend_rgb") * 3
                s = sbAppend(s, arm64_bl(rgi - instrIdx))  instrIdx = instrIdx + 1
                s = sbAppend(s, arm64_push(0))  instrIdx = instrIdx + 1
            } else {
            // Pop args in reverse: x(argc-1) first (TOS), down to x0 (deepest)
            let ai = argc - 1
            while ai >= 0 {
                s = sbAppend(s, arm64_pop(ai))
                instrIdx = instrIdx + 1
                ai = ai - 1
            }
            // bl <target> — foreign symbol routes to its __stubs entry (C ABI: args already in x0..xN)
            let fidx = foreignIdx(cname)
            let targetInstr = findLabel(funcTable, cname)
            if fidx >= 0 { targetInstr = textSz / 4 + fidx * 3 }   // stub i at __text_end + i*12
            let delta = targetInstr - instrIdx
            s = sbAppend(s, arm64_bl(delta))
            instrIdx = instrIdx + 1
            s = sbAppend(s, arm64_push(0))
            instrIdx = instrIdx + 1
            }
        } else if opTok == "RETURN" {
            s = sbAppend(s, arm64_pop_x0())
            instrIdx = instrIdx + 1
            if frame > 0 {
                s = sbAppend(s, arm64_add_sp(frame))
                instrIdx = instrIdx + 1
            }
            s = sbAppend(s, arm64_ldp_fp_lr_post16())
            s = sbAppend(s, arm64_ret())
            instrIdx = instrIdx + 2
        } else if opTok == "BUILTIN_SOCKMAKE" {
            // sockMake() -> socket(AF_INET=2, SOCK_STREAM=1, 0) syscall #97. 6 instr.
            s = sbAppend(s, arm64_movz_x_imm(0, 2))   // 0: domain
            s = sbAppend(s, arm64_movz_x_imm(1, 1))   // 1: type
            s = sbAppend(s, arm64_movz_x_imm(2, 0))   // 2: proto
            s = sbAppend(s, arm64_movz_x_imm(16, 97)) // 3: SYS_socket
            s = sbAppend(s, arm64_svc(0x80))          // 4
            s = sbAppend(s, arm64_push_x0())          // 5: push fd
            instrIdx = instrIdx + 6
        } else if opTok == "BUILTIN_SOCKLISTEN" {
            // sockListen(fd, backlog) -> listen #106. TOS=backlog, next=fd. 5 instr.
            s = sbAppend(s, arm64_pop(1))             // 0: x1 = backlog
            s = sbAppend(s, arm64_pop(0))             // 1: x0 = fd
            s = sbAppend(s, arm64_movz_x_imm(16, 106))// 2: SYS_listen
            s = sbAppend(s, arm64_svc(0x80))          // 3
            s = sbAppend(s, arm64_push_x0())          // 4
            instrIdx = instrIdx + 5
        } else if opTok == "BUILTIN_SOCKACCEPT" {
            // sockAccept(fd) -> accept(fd,0,0) #30. TOS=fd. 6 instr.
            s = sbAppend(s, arm64_pop(0))             // 0: x0 = fd
            s = sbAppend(s, arm64_movz_x_imm(1, 0))   // 1: addr=NULL
            s = sbAppend(s, arm64_movz_x_imm(2, 0))   // 2: addrlen=NULL
            s = sbAppend(s, arm64_movz_x_imm(16, 30)) // 3: SYS_accept
            s = sbAppend(s, arm64_svc(0x80))          // 4
            s = sbAppend(s, arm64_push_x0())          // 5: push client fd
            instrIdx = instrIdx + 6
        } else if opTok == "BUILTIN_SOCKRECV" {
            // sockRecv(fd, buf, len) -> recvfrom(fd,buf,len,0,0,0) #29.
            // TOS=len, next=buf, next=fd. 9 instr.
            s = sbAppend(s, arm64_pop(2))             // 0: x2 = len
            s = sbAppend(s, arm64_pop(1))             // 1: x1 = buf
            s = sbAppend(s, arm64_pop(0))             // 2: x0 = fd
            s = sbAppend(s, arm64_movz_x_imm(3, 0))   // 3: flags=0
            s = sbAppend(s, arm64_movz_x_imm(4, 0))   // 4: from=NULL
            s = sbAppend(s, arm64_movz_x_imm(5, 0))   // 5: fromlen=NULL
            s = sbAppend(s, arm64_movz_x_imm(16, 29)) // 6: SYS_recvfrom
            s = sbAppend(s, arm64_svc(0x80))          // 7
            s = sbAppend(s, arm64_push_x0())          // 8: push nbytes
            instrIdx = instrIdx + 9
        } else if opTok == "BUILTIN_SOCKSEND" {
            // sockSend(fd, buf, len) -> write(fd,buf,len) #4. Works for
            // blocking TCP. TOS=len, next=buf, next=fd. 6 instr.
            s = sbAppend(s, arm64_pop(2))             // 0: x2 = len
            s = sbAppend(s, arm64_pop(1))             // 1: x1 = buf
            s = sbAppend(s, arm64_pop(0))             // 2: x0 = fd
            s = sbAppend(s, arm64_movz_x_imm(16, 4))  // 3: SYS_write
            s = sbAppend(s, arm64_svc(0x80))          // 4
            s = sbAppend(s, arm64_push_x0())          // 5: push nbytes
            instrIdx = instrIdx + 6
        } else if opTok == "BUILTIN_SOCKBIND" {
            // sockBind(fd, portHi, portLo) -> bind(fd, &sockaddr_in, 16) #104.
            // Caller passes the port pre-split into big-endian bytes (computed
            // in Krypton) to avoid shifts in hand-asm.
            // TOS=portLo, next=portHi, next=fd. 47 instr (incl alloc 21).
            s = sbAppend(s, arm64_pop(7))             // 0: x7 = portLo
            s = sbAppend(s, arm64_pop(6))             // 1: x6 = portHi
            s = sbAppend(s, arm64_pop(19))            // 2: x19 = fd (survives alloc)
            s = sbAppend(s, arm64_movz_x_imm(4, 16))  // 3: alloc size = 16
            instrIdx = instrIdx + 4
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))  // x0 = sockaddr (21)
            instrIdx = instrIdx + 21
            s = sbAppend(s, arm64_movz_x_imm(9, 16))  // sin_len = 16
            s = sbAppend(s, arm64_strb_imm(9, 0, 0))
            s = sbAppend(s, arm64_movz_x_imm(9, 2))   // AF_INET
            s = sbAppend(s, arm64_strb_imm(9, 0, 1))
            s = sbAppend(s, arm64_strb_imm(6, 0, 2))  // port hi (BE)
            s = sbAppend(s, arm64_strb_imm(7, 0, 3))  // port lo
            s = sbAppend(s, arm64_strb_imm(31, 0, 4))   // zero [4..15]
            s = sbAppend(s, arm64_strb_imm(31, 0, 5))
            s = sbAppend(s, arm64_strb_imm(31, 0, 6))
            s = sbAppend(s, arm64_strb_imm(31, 0, 7))
            s = sbAppend(s, arm64_strb_imm(31, 0, 8))
            s = sbAppend(s, arm64_strb_imm(31, 0, 9))
            s = sbAppend(s, arm64_strb_imm(31, 0, 10))
            s = sbAppend(s, arm64_strb_imm(31, 0, 11))
            s = sbAppend(s, arm64_strb_imm(31, 0, 12))
            s = sbAppend(s, arm64_strb_imm(31, 0, 13))
            s = sbAppend(s, arm64_strb_imm(31, 0, 14))
            s = sbAppend(s, arm64_strb_imm(31, 0, 15))
            s = sbAppend(s, arm64_mov_xx(1, 0))       // x1 = sockaddr
            s = sbAppend(s, arm64_mov_xx(0, 19))      // x0 = fd
            s = sbAppend(s, arm64_movz_x_imm(2, 16))  // addrlen = 16
            s = sbAppend(s, arm64_movz_x_imm(16, 104))// SYS_bind
            s = sbAppend(s, arm64_svc(0x80))
            s = sbAppend(s, arm64_push_x0())          // push result
            instrIdx = instrIdx + 24
        } else if opTok == "BUILTIN_SOCKCONNECT" {
            // sockConnect(fd, a, b, c, d, portHi, portLo)
            //   -> connect(fd, &sockaddr_in, 16) #98. Client side.
            // IP as 4 octets (a.b.c.d) + port pre-split big-endian, computed in
            // Krypton (no hand-asm shifts). 53 instr (alloc 21).
            // ALLOC FIRST, then pop args — so we touch ONLY caller-saved scratch
            // (x0-x16) and never callee-saved x19+. (An earlier version popped
            // into x19-x23 and corrupted the caller's locals → crash.)
            // emitAllocVar clobbers x0,x1,x2,x5,x9,x11 but data stack is untouched,
            // and buf stays in x0 since pops target x6,x7,x9-x13.
            s = sbAppend(s, arm64_movz_x_imm(4, 16))  // 0: alloc size = 16
            instrIdx = instrIdx + 1
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))  // x0 = sockaddr (21)
            instrIdx = instrIdx + 21
            // pop args (data stack intact across alloc). LIFO: TOS=portLo..fd.
            s = sbAppend(s, arm64_pop(7))             // x7  = portLo
            s = sbAppend(s, arm64_pop(6))             // x6  = portHi
            s = sbAppend(s, arm64_pop(13))            // x13 = ip d
            s = sbAppend(s, arm64_pop(12))            // x12 = ip c
            s = sbAppend(s, arm64_pop(11))            // x11 = ip b
            s = sbAppend(s, arm64_pop(10))            // x10 = ip a
            s = sbAppend(s, arm64_pop(9))             // x9  = fd
            // fill sockaddr_in at [x0]
            s = sbAppend(s, arm64_movz_x_imm(5, 16))  // sin_len = 16
            s = sbAppend(s, arm64_strb_imm(5, 0, 0))
            s = sbAppend(s, arm64_movz_x_imm(5, 2))   // AF_INET
            s = sbAppend(s, arm64_strb_imm(5, 0, 1))
            s = sbAppend(s, arm64_strb_imm(6, 0, 2))  // port hi (BE)
            s = sbAppend(s, arm64_strb_imm(7, 0, 3))  // port lo
            s = sbAppend(s, arm64_strb_imm(10, 0, 4)) // ip a
            s = sbAppend(s, arm64_strb_imm(11, 0, 5)) // ip b
            s = sbAppend(s, arm64_strb_imm(12, 0, 6)) // ip c
            s = sbAppend(s, arm64_strb_imm(13, 0, 7)) // ip d
            s = sbAppend(s, arm64_strb_imm(31, 0, 8)) // zero [8..15]
            s = sbAppend(s, arm64_strb_imm(31, 0, 9))
            s = sbAppend(s, arm64_strb_imm(31, 0, 10))
            s = sbAppend(s, arm64_strb_imm(31, 0, 11))
            s = sbAppend(s, arm64_strb_imm(31, 0, 12))
            s = sbAppend(s, arm64_strb_imm(31, 0, 13))
            s = sbAppend(s, arm64_strb_imm(31, 0, 14))
            s = sbAppend(s, arm64_strb_imm(31, 0, 15))
            s = sbAppend(s, arm64_mov_xx(1, 0))       // x1 = sockaddr
            s = sbAppend(s, arm64_mov_xx(0, 9))       // x0 = fd
            s = sbAppend(s, arm64_movz_x_imm(2, 16))  // addrlen = 16
            s = sbAppend(s, arm64_movz_x_imm(16, 98)) // SYS_connect
            s = sbAppend(s, arm64_svc(0x80))
            s = sbAppend(s, arm64_push_x0())          // push result
            instrIdx = instrIdx + 31
        } else if opTok == "BUILTIN_SOCKCLOSE" {
            // sockClose(fd) -> close(fd) #6. TOS=fd. 4 instr.
            s = sbAppend(s, arm64_pop(0))             // 0: x0 = fd
            s = sbAppend(s, arm64_movz_x_imm(16, 6))  // 1: SYS_close
            s = sbAppend(s, arm64_svc(0x80))          // 2
            s = sbAppend(s, arm64_push_x0())          // 3
            instrIdx = instrIdx + 4
        } else if opTok == "BUILTIN_SOCKRECVSTR" {
            // sockRecvStr(fd): recvfrom(fd, buf, 64K, 0,0,0) into a fresh heap
            // buffer, NUL-terminate at bytes_read, return as a string. Mirrors
            // BUILTIN_READFILE minus open/close. TOS=fd. 36 instr (incl alloc 21).
            // x19=fd, x20=buf, x21=bytes_read (saved across alloc).
            s = sbAppend(s, arm64_pop(19))            // 0: x19 = fd
            s = sbAppend(s, arm64_movz_x_imm_lsl16(4, 0x1)) // 1: x4 = 0x10000 = 64 KB
            instrIdx = instrIdx + 2
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))  // x0 = buf (21)
            instrIdx = instrIdx + 21
            s = sbAppend(s, arm64_mov_xx(20, 0))      // buf
            s = sbAppend(s, arm64_mov_xx(0, 19))      // x0 = fd
            s = sbAppend(s, arm64_mov_xx(1, 20))      // x1 = buf
            s = sbAppend(s, arm64_mov_xx(2, 4))       // x2 = size
            s = sbAppend(s, arm64_movz_x_imm(3, 0))   // flags = 0
            s = sbAppend(s, arm64_movz_x_imm(4, 0))   // from = NULL
            s = sbAppend(s, arm64_movz_x_imm(5, 0))   // fromlen = NULL
            s = sbAppend(s, arm64_movz_x_imm(16, 29)) // SYS_recvfrom
            s = sbAppend(s, arm64_svc(0x80))
            s = sbAppend(s, arm64_mov_xx(21, 0))      // bytes_read
            s = sbAppend(s, arm64_strb_reg(31, 20, 21)) // NUL at buf[bytes_read]
            s = sbAppend(s, arm64_mov_xx(0, 20))      // return buf
            s = sbAppend(s, arm64_push_x0())
            instrIdx = instrIdx + 13
        } else if opTok == "BUILTIN_FDWRITE" {
            // fdWrite(fd, buf, len) -> write(fd,buf,len) #4. Works on any fd
            // (pty master, pipe, file). TOS=len, next=buf, next=fd. 6 instr.
            s = sbAppend(s, arm64_pop(2))             // 0: x2 = len
            s = sbAppend(s, arm64_pop(1))             // 1: x1 = buf
            s = sbAppend(s, arm64_pop(0))             // 2: x0 = fd
            s = sbAppend(s, arm64_movz_x_imm(16, 4))  // 3: SYS_write
            s = sbAppend(s, arm64_svc(0x80))          // 4
            s = sbAppend(s, arm64_push_x0())          // 5: push nbytes
            instrIdx = instrIdx + 6
        } else if opTok == "BUILTIN_FDCLOSE" {
            // fdClose(fd) -> close(fd) #6. TOS=fd. 4 instr.
            s = sbAppend(s, arm64_pop(0))             // 0: x0 = fd
            s = sbAppend(s, arm64_movz_x_imm(16, 6))  // 1: SYS_close
            s = sbAppend(s, arm64_svc(0x80))          // 2
            s = sbAppend(s, arm64_push_x0())          // 3
            instrIdx = instrIdx + 4
        } else if opTok == "BUILTIN_FDREAD" {
            // fdRead(fd, maxlen) -> read(fd, buf, maxlen) #3 into a fresh heap
            // buffer, NUL-terminate at bytes_read, return as a string. TOS=maxlen,
            // next=fd. x19=maxlen, x22=fd, x20=buf, x21=bytes (saved across alloc).
            // 36 instr (incl alloc 21). On macOS a syscall sets the carry flag on
            // error (x0 = +errno, e.g. EAGAIN=35 on a non-blocking fd, EIO after the
            // child exits) — so check carry and treat any error as 0 bytes (-> "").
            s = sbAppend(s, arm64_pop(19))            // 0: x19 = maxlen
            s = sbAppend(s, arm64_pop(22))            // 1: x22 = fd
            s = sbAppend(s, arm64_add_imm(4, 19, 1))  // 2: x4 = maxlen + 1 (alloc size)
            instrIdx = instrIdx + 3
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))  // x0 = buf (21)
            instrIdx = instrIdx + 21
            s = sbAppend(s, arm64_mov_xx(20, 0))      // 0: buf -> x20
            s = sbAppend(s, arm64_mov_xx(0, 22))      // 1: x0 = fd
            s = sbAppend(s, arm64_mov_xx(1, 20))      // 2: x1 = buf
            s = sbAppend(s, arm64_mov_xx(2, 19))      // 3: x2 = maxlen
            s = sbAppend(s, arm64_movz_x_imm(16, 3))  // 4: SYS_read
            s = sbAppend(s, arm64_svc(0x80))          // 5
            s = sbAppend(s, arm64_mov_xx(21, 0))      // 6: x21 = bytes_read (or errno)
            s = sbAppend(s, arm64_b_cond(3, 2))       // 7: b.cc +2 (carry clear=ok, skip clamp)
            s = sbAppend(s, arm64_movz_x_imm(21, 0))  // 8: error -> 0 bytes
            s = sbAppend(s, arm64_strb_reg(31, 20, 21)) // 9: NUL at buf[bytes_read]
            s = sbAppend(s, arm64_mov_xx(0, 20))      // 10: return buf
            s = sbAppend(s, arm64_push_x0())          // 11
            instrIdx = instrIdx + 12
        } else if opTok == "BUILTIN_FDSETNONBLOCK" {
            // fdSetNonblock(fd) -> fcntl(fd, F_SETFL=4, O_NONBLOCK=4) #92. F_SETFL
            // only touches status flags (O_NONBLOCK), leaves O_RDWR intact. TOS=fd. 6 instr.
            s = sbAppend(s, arm64_pop(0))             // 0: x0 = fd
            s = sbAppend(s, arm64_movz_x_imm(1, 4))   // 1: F_SETFL
            s = sbAppend(s, arm64_movz_x_imm(2, 4))   // 2: O_NONBLOCK
            s = sbAppend(s, arm64_movz_x_imm(16, 92)) // 3: SYS_fcntl
            s = sbAppend(s, arm64_svc(0x80))          // 4
            s = sbAppend(s, arm64_push_x0())          // 5
            instrIdx = instrIdx + 6
        } else if opTok == "BUILTIN_SLEEPUS" {
            // sleepUs(sec, usec) -> select(0, NULL, NULL, NULL, &{tv_sec=sec,
            // tv_usec=usec}) #93. The classic portable sub-second sleep (Darwin has
            // no plain nanosleep syscall). Builds timeval in a fresh 16-byte cell.
            // TOS=usec, next=sec. 34 instr (incl alloc 21).
            s = sbAppend(s, arm64_pop(20))            // 0: x20 = usec
            s = sbAppend(s, arm64_pop(19))            // 1: x19 = sec
            s = sbAppend(s, arm64_movz_x_imm(4, 16))  // 2: alloc 16 bytes
            instrIdx = instrIdx + 3
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))  // x0 = tv (21)
            instrIdx = instrIdx + 21
            s = sbAppend(s, arm64_str_imm(19, 0, 0))  // 0: tv.tv_sec = sec
            s = sbAppend(s, arm64_str_imm(20, 0, 1))  // 1: tv.tv_usec = usec (offset 8)
            s = sbAppend(s, arm64_mov_xx(4, 0))       // 2: x4 = &tv (5th arg)
            s = sbAppend(s, arm64_movz_x_imm(0, 0))   // 3: nfds = 0
            s = sbAppend(s, arm64_movz_x_imm(1, 0))   // 4: readfds = NULL
            s = sbAppend(s, arm64_movz_x_imm(2, 0))   // 5: writefds = NULL
            s = sbAppend(s, arm64_movz_x_imm(3, 0))   // 6: errorfds = NULL
            s = sbAppend(s, arm64_movz_x_imm(16, 93)) // 7: SYS_select
            s = sbAppend(s, arm64_svc(0x80))          // 8
            s = sbAppend(s, arm64_push_x0())          // 9
            instrIdx = instrIdx + 10
        } else if opTok == "BUILTIN_PTYMASTER" {
            // ptyMaster(ptmxPath): open(path, O_RDWR=2, 0) #5; then grant + unlock
            // the pty via ioctl #54: TIOCPTYGRANT=0x20007454, TIOCPTYUNLK=0x20007452.
            // Return the master fd. TOS=path. x19=master. 20 instr.
            s = sbAppend(s, arm64_pop(0))             // 0: x0 = path
            s = sbAppend(s, arm64_movz_x_imm(1, 2))   // 1: O_RDWR
            s = sbAppend(s, arm64_movz_x_imm(2, 0))   // 2: mode 0
            s = sbAppend(s, arm64_movz_x_imm(16, 5))  // 3: SYS_open
            s = sbAppend(s, arm64_svc(0x80))          // 4
            s = sbAppend(s, arm64_mov_xx(19, 0))      // 5: x19 = master fd
            // ioctl(master, TIOCPTYGRANT, 0)
            s = sbAppend(s, arm64_mov_xx(0, 19))      // 6
            s = sbAppend(s, arm64_movz_x_imm(1, 0x7454)) // 7
            s = sbAppend(s, arm64_movk_x_imm_lsl16(1, 0x2000)) // 8: x1 = 0x20007454
            s = sbAppend(s, arm64_movz_x_imm(2, 0))   // 9
            s = sbAppend(s, arm64_movz_x_imm(16, 54)) // 10: SYS_ioctl
            s = sbAppend(s, arm64_svc(0x80))          // 11
            // ioctl(master, TIOCPTYUNLK, 0)
            s = sbAppend(s, arm64_mov_xx(0, 19))      // 12
            s = sbAppend(s, arm64_movz_x_imm(1, 0x7452)) // 13
            s = sbAppend(s, arm64_movk_x_imm_lsl16(1, 0x2000)) // 14: x1 = 0x20007452
            s = sbAppend(s, arm64_movz_x_imm(2, 0))   // 15
            s = sbAppend(s, arm64_movz_x_imm(16, 54)) // 16
            s = sbAppend(s, arm64_svc(0x80))          // 17
            s = sbAppend(s, arm64_mov_xx(0, 19))      // 18: return master
            s = sbAppend(s, arm64_push_x0())          // 19
            instrIdx = instrIdx + 20
        } else if opTok == "BUILTIN_PTYSLAVENAME" {
            // ptySlaveName(master): ioctl(master, TIOCPTYGNAME=0x40807453, buf) #54
            // — kernel writes the slave path (e.g. "/dev/ttys003", NUL-term) into a
            // fresh 128-byte buffer. Return it as a string. TOS=master. 32 instr.
            s = sbAppend(s, arm64_pop(19))            // 0: x19 = master
            s = sbAppend(s, arm64_movz_x_imm(4, 128)) // 1: alloc size
            instrIdx = instrIdx + 2
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))  // x0 = buf (21)
            instrIdx = instrIdx + 21
            s = sbAppend(s, arm64_mov_xx(20, 0))      // 0: x20 = buf
            s = sbAppend(s, arm64_mov_xx(0, 19))      // 1: x0 = master
            s = sbAppend(s, arm64_movz_x_imm(1, 0x7453)) // 2
            s = sbAppend(s, arm64_movk_x_imm_lsl16(1, 0x4080)) // 3: x1 = 0x40807453
            s = sbAppend(s, arm64_mov_xx(2, 20))      // 4: x2 = buf
            s = sbAppend(s, arm64_movz_x_imm(16, 54)) // 5: SYS_ioctl
            s = sbAppend(s, arm64_svc(0x80))          // 6
            s = sbAppend(s, arm64_mov_xx(0, 20))      // 7: return buf (kernel NUL-termed)
            s = sbAppend(s, arm64_push_x0())          // 8
            instrIdx = instrIdx + 9
        } else if opTok == "BUILTIN_PTYFORKEXEC" {
            // ptyForkExec(slaveName, shellPath): fork; CHILD becomes the shell on
            // the pty slave (setsid, open slave, TIOCSCTTY, dup2 0/1/2, execve);
            // PARENT returns the child pid. macOS fork: x0=child pid in BOTH, and
            // x1==1 marks the child (x1==0 parent). TOS=shellPath, next=slaveName.
            // x20=slaveName, x21=shellPath, x22=slave fd. 66 instr (alloc 21).
            s = sbAppend(s, arm64_pop(21))            // 0: x21 = shellPath
            s = sbAppend(s, arm64_pop(20))            // 1: x20 = slaveName
            s = sbAppend(s, arm64_movz_x_imm(16, 2))  // 2: SYS_fork
            s = sbAppend(s, arm64_svc(0x80))          // 3
            s = sbAppend(s, arm64_cbnz(1, 3))         // 4: x1!=0 -> CHILD @7
            s = sbAppend(s, arm64_push_x0())          // 5: PARENT: return child pid
            s = sbAppend(s, arm64_b(62))              // 6: -> END @68
            // CHILD @7:
            s = sbAppend(s, arm64_movz_x_imm(16, 147))// 7: SYS_setsid
            s = sbAppend(s, arm64_svc(0x80))          // 8
            s = sbAppend(s, arm64_mov_xx(0, 20))      // 9: x0 = slaveName
            s = sbAppend(s, arm64_movz_x_imm(1, 2))   // 10: O_RDWR
            s = sbAppend(s, arm64_movz_x_imm(2, 0))   // 11: mode 0
            s = sbAppend(s, arm64_movz_x_imm(16, 5))  // 12: SYS_open
            s = sbAppend(s, arm64_svc(0x80))          // 13
            s = sbAppend(s, arm64_mov_xx(22, 0))      // 14: x22 = slave fd
            // ioctl(slave, TIOCSCTTY=0x20007461, 0) — become controlling tty
            s = sbAppend(s, arm64_mov_xx(0, 22))      // 15
            s = sbAppend(s, arm64_movz_x_imm(1, 0x7461)) // 16
            s = sbAppend(s, arm64_movk_x_imm_lsl16(1, 0x2000)) // 17: x1 = 0x20007461
            s = sbAppend(s, arm64_movz_x_imm(2, 0))   // 18
            s = sbAppend(s, arm64_movz_x_imm(16, 54)) // 19: SYS_ioctl
            s = sbAppend(s, arm64_svc(0x80))          // 20
            // dup2(slave, 0/1/2) #90
            s = sbAppend(s, arm64_mov_xx(0, 22))      // 21
            s = sbAppend(s, arm64_movz_x_imm(1, 0))   // 22
            s = sbAppend(s, arm64_movz_x_imm(16, 90)) // 23
            s = sbAppend(s, arm64_svc(0x80))          // 24
            s = sbAppend(s, arm64_mov_xx(0, 22))      // 25
            s = sbAppend(s, arm64_movz_x_imm(1, 1))   // 26
            s = sbAppend(s, arm64_movz_x_imm(16, 90)) // 27
            s = sbAppend(s, arm64_svc(0x80))          // 28
            s = sbAppend(s, arm64_mov_xx(0, 22))      // 29
            s = sbAppend(s, arm64_movz_x_imm(1, 2))   // 30
            s = sbAppend(s, arm64_movz_x_imm(16, 90)) // 31
            s = sbAppend(s, arm64_svc(0x80))          // 32
            // build argv = [shellPath, NULL]
            s = sbAppend(s, arm64_movz_x_imm(4, 16))  // 33: alloc 16 bytes (2 ptrs)
            instrIdx = instrIdx + 34
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))  // 34-54: x0 = argv (21)
            instrIdx = instrIdx + 21
            // envp = inherited envp saved at bump_cell+80 (so the shell gets $PATH
            // etc). adrp is at index 60 → imm21 uses instrIdx+5 (instrIdx is base+55).
            let imm21pe = (g_TEXT_VMSIZE + 0x8000) / 4096 - (textOff + (instrIdx + 5) * 4) / 4096
            s = sbAppend(s, arm64_str_imm(21, 0, 0))  // 55: argv[0] = shellPath
            s = sbAppend(s, arm64_movz_x_imm(9, 0))   // 56: x9 = 0
            s = sbAppend(s, arm64_str_imm(9, 0, 1))   // 57: argv[1] = NULL (offset 8)
            s = sbAppend(s, arm64_mov_xx(1, 0))       // 58: x1 = argv
            s = sbAppend(s, arm64_mov_xx(0, 21))      // 59: x0 = shellPath
            s = sbAppend(s, arm64_adrp(9, imm21pe))   // 60: x9 = bump_cell page
            s = sbAppend(s, arm64_add_imm(9, 9, 0))   // 61
            s = sbAppend(s, arm64_ldr_imm(2, 9, 10))  // 62: x2 = envp (cell+80)
            s = sbAppend(s, arm64_movz_x_imm(16, 59)) // 63: SYS_execve
            s = sbAppend(s, arm64_svc(0x80))          // 64
            // execve only returns on failure -> exit(1)
            s = sbAppend(s, arm64_movz_x_imm(0, 1))   // 65
            s = sbAppend(s, arm64_movz_x_imm(16, 1))  // 66: SYS_exit
            s = sbAppend(s, arm64_svc(0x80))          // 67
            instrIdx = instrIdx + 13
            // END @68
        } else if opTok == "BUILTIN_PTYSETSIZE" {
            // ptySetSize(fd, rows, cols) -> ioctl(fd, TIOCSWINSZ=0x80087467,
            // &winsize{ws_row=rows, ws_col=cols, 0, 0}) #54. Tells the pty its
            // size so the shell/programs use the real width. TOS=cols, next=rows,
            // next=fd. rows/cols stored as the low byte (<=255). 40 instr (alloc 21).
            s = sbAppend(s, arm64_pop(20))            // 0: x20 = cols
            s = sbAppend(s, arm64_pop(21))            // 1: x21 = rows
            s = sbAppend(s, arm64_pop(19))            // 2: x19 = fd
            s = sbAppend(s, arm64_movz_x_imm(4, 8))   // 3: alloc 8 bytes (winsize)
            instrIdx = instrIdx + 4
            s = sbAppend(s, emitAllocVar(instrIdx, textVaddr, textOff))  // 4-24: x0 = ws (21)
            instrIdx = instrIdx + 21
            s = sbAppend(s, arm64_strb_imm(21, 0, 0)) // 0: ws_row low = rows
            s = sbAppend(s, arm64_strb_imm(31, 0, 1)) // 1: ws_row high = 0
            s = sbAppend(s, arm64_strb_imm(20, 0, 2)) // 2: ws_col low = cols
            s = sbAppend(s, arm64_strb_imm(31, 0, 3)) // 3: ws_col high = 0
            s = sbAppend(s, arm64_strb_imm(31, 0, 4)) // 4: ws_xpixel = 0
            s = sbAppend(s, arm64_strb_imm(31, 0, 5)) // 5
            s = sbAppend(s, arm64_strb_imm(31, 0, 6)) // 6: ws_ypixel = 0
            s = sbAppend(s, arm64_strb_imm(31, 0, 7)) // 7
            s = sbAppend(s, arm64_mov_xx(2, 0))       // 8: x2 = &ws
            s = sbAppend(s, arm64_mov_xx(0, 19))      // 9: x0 = fd
            s = sbAppend(s, arm64_movz_x_imm(1, 0x7467))       // 10
            s = sbAppend(s, arm64_movk_x_imm_lsl16(1, 0x8008)) // 11: x1 = 0x80087467
            s = sbAppend(s, arm64_movz_x_imm(16, 54)) // 12: SYS_ioctl
            s = sbAppend(s, arm64_svc(0x80))          // 13
            s = sbAppend(s, arm64_push_x0())          // 14
            instrIdx = instrIdx + 15
        } else if opTok == "BUILTIN_PROCALIVE" {
            // procAlive(pid) -> kill(pid, 0) #37. sig 0 = probe existence/perm.
            // macOS sets the carry flag on error (ESRCH if the process is gone),
            // so carry-clear = alive. Returns 1 alive, 0 dead. TOS=pid. 8 instr.
            s = sbAppend(s, arm64_pop(0))             // 0: x0 = pid
            s = sbAppend(s, arm64_movz_x_imm(1, 0))   // 1: x1 = 0 (sig 0)
            s = sbAppend(s, arm64_movz_x_imm(16, 37)) // 2: SYS_kill
            s = sbAppend(s, arm64_svc(0x80))          // 3
            s = sbAppend(s, arm64_movz_x_imm(0, 1))   // 4: assume alive (movz leaves flags)
            s = sbAppend(s, arm64_b_cond(3, 2))       // 5: b.cc +2 (carry clear=alive -> skip)
            s = sbAppend(s, arm64_movz_x_imm(0, 0))   // 6: error -> dead
            s = sbAppend(s, arm64_push_x0())          // 7
            instrIdx = instrIdx + 8
        } else if opTok == "BUILTIN_WAITCHILD" {
            // waitChild(pid) -> wait4(pid, NULL, WNOHANG=1, NULL) #7. Reaps a
            // child that has exited (clears the zombie) and returns its pid; 0 if
            // the child is still running; errno if no such child. TOS=pid. 7 instr.
            s = sbAppend(s, arm64_pop(0))             // 0: x0 = pid
            s = sbAppend(s, arm64_movz_x_imm(1, 0))   // 1: x1 = NULL (status)
            s = sbAppend(s, arm64_movz_x_imm(2, 1))   // 2: x2 = WNOHANG
            s = sbAppend(s, arm64_movz_x_imm(3, 0))   // 3: x3 = NULL (rusage)
            s = sbAppend(s, arm64_movz_x_imm(16, 7))  // 4: SYS_wait4
            s = sbAppend(s, arm64_svc(0x80))          // 5
            s = sbAppend(s, arm64_push_x0())          // 6
            instrIdx = instrIdx + 7
        } else if opTok == "POP" {
            s = sbAppend(s, arm64_pop_x0())
            instrIdx = instrIdx + 1
        } else if opTok == "END" {
            if frame > 0 {
                s = sbAppend(s, arm64_add_sp(frame))
                instrIdx = instrIdx + 1
            }
            s = sbAppend(s, arm64_movz_w0_zero())
            s = sbAppend(s, arm64_ldp_fp_lr_post16())
            s = sbAppend(s, arm64_ret())
            instrIdx = instrIdx + 3
        }
        oi += 1
    }
    emit sbToString(s)
}

// Top-level emitter: walk all functions in emission order (__main__ first)
// and concatenate.
func emitTextFromIR(parsed, strOffsets, textSz) {
    let order = emitOrder(parsed)
    let nF = funcCount(parsed)
    let funcTable = buildFunctionTable(parsed)
    let s = sbNew()
    let oi = 0
    while oi < nF {
        let fIdx = toInt(getLine(order, oi))
        let funcStartInstr = findLabel(funcTable, funcName(parsed, fIdx))
        let fcode = emitOneFunction(parsed, fIdx, funcStartInstr, funcTable, strOffsets, textSz)
        s = sbAppend(s, fcode)
        oi += 1
    }
    emit sbToString(s)
}

// ── _main code (8 instructions, 32 bytes) ───────────────────────────────────
// _main vaddr = 0x100000460. "Hi" vaddr = 0x10000048C. Stub vaddr = 0x100000480.
//
//   stp x29, x30, [sp, #-16]!
//   mov x29, sp
//   adrp x0, "Hi"@PAGE                ; PC=0x...468, page_rel=0
//   add  x0, x0, "Hi"@PAGEOFF         ; +0x48c
//   bl   _puts$stub                   ; PC=0x...470 → 0x...480, rel26=4
//   mov  w0, #0
//   ldp  x29, x30, [sp], #16
//   ret
func emitMainCode() {
    let s = ""
    s = s + arm64_stp_fp_lr_pre16()
    s = s + arm64_mov_fp_sp()
    s = s + arm64_adrp(0, 0)                 // "Hi" is on same page as _main
    s = s + arm64_add_imm(0, 0, 0x48c)       // page-offset of "Hi"
    s = s + arm64_bl(4)                      // (0x480 - 0x470) / 4 = 4
    s = s + arm64_movz_w0_zero()
    s = s + arm64_ldp_fp_lr_post16()
    s = s + arm64_ret()
    emit s
}

// ── _puts$stub (3 instructions, 12 bytes) ───────────────────────────────────
// stub vaddr = 0x100000480. __got slot vaddr = 0x100004000.
//
//   adrp x16, __got@PAGE               ; PC=0x...480, page_rel=4
//   ldr  x16, [x16, #__got@PAGEOFF]    ; offset 0 (got is at page base)
//   br   x16
func emitStubCode() {
    let s = ""
    s = s + arm64_adrp(16, 4)
    s = s + arm64_ldr_imm(16, 16, 0)
    s = s + arm64_br(16)
    emit s
}

// ── __cstring "Hi\0" (3 bytes) ──────────────────────────────────────────────
func emitCString() { emit hexStr("Hi") + hexByte(0) }

// ── __got slot (8 bytes) ────────────────────────────────────────────────────
// dyld_chained_ptr_64_bind: bind=1, next=0, reserved=0, addend=0, ordinal=0.
// Encoded: bit 63 = 1, all other bits 0. 8-byte LE: 00 00 00 00 00 00 00 80.
func emitGotSlot() { emit hexDword(0) + hexDword((0x8000 * 0x10000 + 0x0)) }

// ── empty chained_fixups payload (56 bytes) ─────────────────────────────────
// dyld requires LC_DYLD_CHAINED_FIXUPS present, but this binary has nothing to
// bind (no imports — libSystem/_puts gone) and nothing to rebase (non-PIE,
// absolute vaddrs). So: header with imports_count=0, and a starts_in_image
// whose every segment offset is 0 (no segment carries a fixup chain).
//   header (32B): version=0, starts_offset=32, imports_offset=56,
//     symbols_offset=56, imports_count=0, imports_format=1, symbols_format=0
//   starts_in_image (24B): seg_count=5, then 5 × uint32 seg_info_offset = 0
func emitChainedFixups() {
    if g_NFOREIGN > 0 { emit emitChainedFixupsN() }
    let s = ""
    s = s + hexDword(0)              // fixups_version
    s = s + hexDword(32)             // starts_offset
    s = s + hexDword(56)             // imports_offset (== end; no imports)
    s = s + hexDword(56)             // symbols_offset (== end; no symbols)
    s = s + hexDword(0)              // imports_count = 0
    s = s + hexDword(1)              // imports_format
    s = s + hexDword(0)              // symbols_format
    s = s + hexDword(0)              // pad to 32B
    // starts_in_image — 24 B: seg_count + 5 × seg_info_offset (all 0)
    s = s + hexDword(5)              // seg_count (PAGEZERO/TEXT/DATA_CONST/DATA/LINKEDIT)
    s = s + hexDword(0)              // [0] __PAGEZERO  — no fixups
    s = s + hexDword(0)              // [1] __TEXT      — no fixups
    s = s + hexDword(0)              // [2] __DATA_CONST — no fixups
    s = s + hexDword(0)              // [3] __DATA      — no fixups
    s = s + hexDword(0)              // [4] __LINKEDIT  — no fixups
    emit s
}

// chained fixups with N imports — DATA_CONST __got carries the bind chain.
func emitChainedFixupsN() {
    let nF = g_NFOREIGN
    let importsOff = 80                        // 32(hdr)+24(image)+24(seg)
    let symbolsOff = 80 + nF * 4
    let s = ""
    s = s + hexDword(0) + hexDword(32) + hexDword(importsOff) + hexDword(symbolsOff)
    s = s + hexDword(nF) + hexDword(1) + hexDword(0) + hexDword(0)        // imports_count, fmt=1, sym_fmt=0, pad
    // starts_in_image (24 B): seg_count=5, only DATA_CONST([2]) carries a chain @ +24
    s = s + hexDword(5) + hexDword(0) + hexDword(0) + hexDword(24) + hexDword(0) + hexDword(0)
    // starts_in_segment (24 B): ptr_format 6, seg_offset = DATA_CONST vaddr-base, 1 page, first slot @ off 0
    s = s + hexDword(24) + hexWord(0x4000) + hexWord(6) + hexQword(g_DATA_CONST_FILE_OFF) + hexDword(0) + hexWord(1) + hexWord(0)
    // imports: lib_ordinal:8 | weak:1 | name_offset:23  (name_offset << 9)
    let off = 1  let i = 0
    while i < nF {
        let ord = toInt(getLine(g_FORLIB, i))
        s = s + hexDword(ord + off * 512)
        off = off + len(getLine(g_FORSYMS, i)) + 1
        i += 1
    }
    // symbols: leading NUL + each "_sym\0"
    s = s + hexByte(0)
    i = 0
    while i < nF { s = s + hexStr(getLine(g_FORSYMS, i)) + hexByte(0)  i += 1 }
    s = s + hexPad(g_FIXUPS_SZ - hexBytesLen(s))
    emit s
}

// __stubs: N × 12-byte stub (adrp x16,gotpage / ldr x16,[x16,#off] / br x16)
func emitStubsN() {
    let s = ""  let i = 0
    while i < g_NFOREIGN {
        // vaddr base 0x100000000 is page-aligned, so it cancels in the page delta;
        // compute from file offsets to stay under the 0x7EFFFFFF literal limit.
        let stubFoff = g_TEXT_OFF + g_TEXT_SIZE + i * 12
        let gotFoff  = g_DATA_CONST_FILE_OFF + i * 8
        let adrpImm = (gotFoff / 0x1000) - (stubFoff / 0x1000)
        let ldrOff  = (gotFoff % 0x1000) / 8
        s = s + arm64_adrp(16, adrpImm) + arm64_ldr_imm(16, 16, ldrOff) + arm64_br(16)
        i += 1
    }
    emit s
}

// __got: N × 8-byte dyld_chained_ptr_64_bind {ordinal=i, next=(2 unless last), bind=1}
func emitGotN() {
    let s = ""  let i = 0
    while i < g_NFOREIGN {
        let nxt = 2
        if i == g_NFOREIGN - 1 { nxt = 0 }
        s = s + hexDword(i) + hexDword(nxt * 0x80000 + 0x8000 * 0x10000)   // bind bit 63
        i += 1
    }
    emit s
}

// indirect symtab: N (for __stubs) + N (for __got), each -> symtab index (2+i)
func emitIndirectN() {
    let s = ""  let pass = 0
    while pass < 2 {
        let i = 0
        while i < g_NFOREIGN { s = s + hexDword(2 + i)  i += 1 }
        pass += 1
    }
    emit s
}

// ── symtab (32 B = 2 × nlist_64) ────────────────────────────────────────────
// Symbols (in declaration order, matches strtab layout):
//   0: __mh_execute_header  (defined, sect 1, value = TEXT_VADDR)
//   1: _main                (defined, sect 1, value = TEXT_VADDR + TEXT_OFF)
// (_puts was removed — the runtime imports nothing.)
func emitSymtab() {
    let s = ""
    // sym 0: __mh_execute_header
    s = s + hexDword(STRX_MH())                 // n_strx = 2
    s = s + hexByte(0x0f)                       // n_type = N_EXT | N_SECT
    s = s + hexByte(1)                          // n_sect = 1 (__text)
    s = s + hexWord(0x10)                       // n_desc = REFERENCED_DYNAMICALLY (matches clang)
    s = s + hexQword2(TEXT_VADDR(), 1)          // n_value = 0
    // sym 1: _main
    s = s + hexDword(STRX_MAIN())
    s = s + hexByte(0x0f)
    s = s + hexByte(1)
    s = s + hexWord(0)
    s = s + hexQword2(TEXT_VADDR() + g_ENTRY_OFF, 1) // _main vaddr (entry point)
    // syms 2..2+N: undefined foreign imports (n_type N_UNDF|N_EXT, lib ordinal in n_desc high byte)
    let i = 0
    while i < g_NFOREIGN {
        s = s + hexDword(STRX_FOR(i))
        s = s + hexByte(0x01) + hexByte(0)
        s = s + hexWord(toInt(getLine(g_FORLIB, i)) * 256)
        s = s + hexQword2(0, 0)
        i += 1
    }
    emit s
}

// ── strtab (32 B padded) ────────────────────────────────────────────────────
// Layout:
//   [0]  ' '              (1 B, "space" sentinel some strtabs use)
//   [1]  NUL              (1 B, empty string at idx 1)
//   [2]  "__mh_execute_header\0"  (20 B)
//   [22] "_main\0"        (6 B)
//   [28] pad to 32        (4 NULs)
func emitStrtab() {
    let s = ""
    s = s + hexByte(0x20)            // ' '
    s = s + hexByte(0)               // NUL @ offset 1
    s = s + hexStr("__mh_execute_header") + hexByte(0)
    s = s + hexStr("_main") + hexByte(0)
    if g_NFOREIGN > 0 {
        let i = 0
        while i < g_NFOREIGN { s = s + hexStr(getLine(g_FORSYMS, i)) + hexByte(0)  i += 1 }
        s = s + hexPad(g_STRTAB_SZ2 - strtabUnpadded())
        emit s
    }
    s = s + hexPad(4)                // pad to 32 bytes
    emit s
}

// ── ad-hoc code signature builder ───────────────────────────────────────────
// All code-signing fields are BIG-endian.
//
// SuperBlob structure (20 B header + 1 BlobIndex):
//   magic   = 0xfade0cc0
//   length  = 20 + len(CodeDirectory)
//   count   = 1
//   index[0]: type = 0 (CSSLOT_CODEDIRECTORY), offset = 20
//   then CodeDirectory blob.
//
// CodeDirectory (version 0x20400 = SUPPORTSEXECSEG, ad-hoc flag):
//   88 B header — see field-by-field comments below.
//   identifier — UTF-8 string + NUL (we use "krypton\0" = 8 B).
//   special slots — none for our minimal binary.
//   code slots — SHA-256 of each pageSize-byte page of the file from offset 0
//                up to codeLimit. Last page may be partial.

// 64-bit BE qword: just two BE dwords (we use only low 32 bits in our fields).
func hexQwordBe(hi, lo) { emit hexDwordBe(hi) + hexDwordBe(lo) }

// Build the CodeDirectory blob. fileBytes is the hex-encoded file content
// from offset 0 to codeLimit (the bytes the kernel verifies against).
// Empty requirements blob (CSMAGIC_REQUIREMENTS, count 0). 12 bytes, "xHH" hex.
// Matches what `codesign -s -` emits; the kernel on Apple Silicon expects this
// blob (and its hash in special slot -2) for an ad-hoc signature to be valid.
func buildRequirementsBlob() {
    emit hexDwordBe((0xfade * 0x10000 + 0xc01)) + hexDwordBe(12) + hexDwordBe(0)
}

// Empty CMS signature blob (CSMAGIC_BLOBWRAPPER, no payload). 8 bytes.
func buildCmsBlob() {
    emit hexDwordBe((0xfade * 0x10000 + 0xb01)) + hexDwordBe(8)
}

func buildCodeDirectory(fileBytes, codeLimit, identifier) {
    let pageSize = 0x4000          // 16 KB
    let pageLog2 = 14
    let hashSize = 32              // SHA-256
    let hashType = 2
    // Two special slots: -1 = Info.plist (absent → zero hash), -2 = Requirements.
    let nSpecialSlots = 2
    let nCodeSlots = (codeLimit + pageSize - 1) / pageSize
    let identLen = len(identifier) + 1   // include trailing NUL
    let identOffset = 88
    let hashOffset = identOffset + identLen + nSpecialSlots * hashSize
    let cdLength = hashOffset + nCodeSlots * hashSize

    let cd = ""
    cd = cd + hexDwordBe((0xfade * 0x10000 + 0xc02))         // magic CSMAGIC_CODEDIRECTORY
    cd = cd + hexDwordBe(cdLength)
    cd = cd + hexDwordBe(0x00020400)         // version (SUPPORTSEXECSEG)
    cd = cd + hexDwordBe(0x00000002)         // flags = adhoc
    cd = cd + hexDwordBe(hashOffset)
    cd = cd + hexDwordBe(identOffset)
    cd = cd + hexDwordBe(nSpecialSlots)
    cd = cd + hexDwordBe(nCodeSlots)
    cd = cd + hexDwordBe(codeLimit)
    cd = cd + hexByte(hashSize) + hexByte(hashType)
    cd = cd + hexByte(0) + hexByte(pageLog2) // platform=0, log2(pageSize)
    cd = cd + hexDwordBe(0)                  // spare2
    cd = cd + hexDwordBe(0)                  // scatterOffset
    cd = cd + hexDwordBe(0)                  // teamOffset
    cd = cd + hexDwordBe(0)                  // spare3
    cd = cd + hexQwordBe(0, 0)               // codeLimit64 = 0 (using 32-bit)
    cd = cd + hexQwordBe(0, 0)               // execSegBase = 0 (file off of __TEXT)
    cd = cd + hexQwordBe(0, g_TEXT_VMSIZE)   // execSegLimit = __TEXT vmsize
    cd = cd + hexQwordBe(0, 1)               // execSegFlags = MAIN_BINARY

    // Identifier string with trailing NUL
    cd = cd + asciiToHex(identifier) + hexByte(0)

    // Special slot hashes, stored most-negative first (slot -2, then slot -1):
    //   slot -2 = CSSLOT_REQUIREMENTS → SHA-256 of the requirements blob
    //   slot -1 = CSSLOT_INFOSLOT     → no Info.plist, so a 32-byte zero hash
    let reqBlob = buildRequirementsBlob()
    cd = cd + sha256_hex(reqBlob, 0, hexBytesLen(reqBlob))   // slot -2
    let z = 0
    while z < hashSize { cd = cd + hexByte(0) z += 1 }       // slot -1 (zeros)

    // Code slot hashes — SHA-256 of each page
    let p = 0
    while p < nCodeSlots {
        let pageOff = p * pageSize
        let pageLen = pageSize
        if pageOff + pageLen > codeLimit {
            pageLen = codeLimit - pageOff
        }
        cd = cd + sha256_hex(fileBytes, pageOff, pageLen)
        p += 1
    }
    emit cd
}

// Wrap the CodeDirectory in a SuperBlob with three slots — matching what
// `codesign -s -` emits, which the Apple-Silicon kernel requires:
//   CSSLOT_CODEDIRECTORY (0)        → the CodeDirectory
//   CSSLOT_REQUIREMENTS  (2)        → empty requirements blob
//   CSSLOT_SIGNATURESLOT (0x10000)  → empty CMS blob wrapper
// Returns the full signature bytes (hex-encoded).
func buildSuperBlob(cdHex) {
    let reqBlob = buildRequirementsBlob()
    let cmsBlob = buildCmsBlob()
    let cdLen = hexBytesLen(cdHex)
    let reqLen = hexBytesLen(reqBlob)
    let cmsLen = hexBytesLen(cmsBlob)
    let hdrLen = 12 + 3 * 8                 // SuperBlob header + 3 blob indices
    let cdOff = hdrLen
    let reqOff = cdOff + cdLen
    let cmsOff = reqOff + reqLen
    let totalLen = cmsOff + cmsLen
    let s = ""
    s = s + hexDwordBe((0xfade * 0x10000 + 0xcc0))         // magic CSMAGIC_EMBEDDED_SIGNATURE
    s = s + hexDwordBe(totalLen)
    s = s + hexDwordBe(3)                  // count = 3
    s = s + hexDwordBe(0) + hexDwordBe(cdOff)        // CSSLOT_CODEDIRECTORY
    s = s + hexDwordBe(2) + hexDwordBe(reqOff)       // CSSLOT_REQUIREMENTS
    s = s + hexDwordBe(0x10000) + hexDwordBe(cmsOff) // CSSLOT_SIGNATURESLOT
    s = s + cdHex + reqBlob + cmsBlob
    emit s
}

// ── load commands ───────────────────────────────────────────────────────────

// LC_SEGMENT_64 __PAGEZERO (72 B, no sections)
func emitLcPagezero() {
    let s = ""
    s = s + hexDword(LC_SEGMENT_64()) + hexDword(72)
    s = s + hexStr("__PAGEZERO") + hexPad(6)        // 16-byte segname
    s = s + hexQword2(0, 0)                         // vmaddr
    s = s + hexQword2(0, 1)                         // vmsize = 0
    s = s + hexQword(0)                             // fileoff
    s = s + hexQword(0)                             // filesize
    s = s + hexDword(0)                             // maxprot
    s = s + hexDword(0)                             // initprot
    s = s + hexDword(0)                             // nsects
    s = s + hexDword(0)                             // flags
    emit s
}

// LC_SEGMENT_64 __TEXT (with 2 sections: __text, __cstring)
// cmdsize = 72 + 2*80 = 232. (__stubs removed with the dead _puts import.)
func emitLcSegText() {
    let nsects = 2  let cmdsz = 232
    if g_NFOREIGN > 0 { nsects = 3  cmdsz = 312 }
    let s = ""
    s = s + hexDword(LC_SEGMENT_64()) + hexDword(cmdsz)
    s = s + hexStr("__TEXT") + hexPad(10)
    s = s + hexQword2(0, 1)                         // vmaddr = 0
    s = s + hexQword(g_TEXT_VMSIZE)                 // vmsize = TEXT_VMSIZE
    s = s + hexQword(0)                             // fileoff
    s = s + hexQword(g_TEXT_VMSIZE)                 // filesize = same
    s = s + hexDword(5)                             // maxprot = R+X
    s = s + hexDword(5)                             // initprot = R+X
    s = s + hexDword(nsects)                        // nsects
    s = s + hexDword(0)                             // flags
    // Section 1: __text
    s = s + hexStr("__text") + hexPad(10)
    s = s + hexStr("__TEXT") + hexPad(10)
    s = s + hexQword2(TEXT_VADDR() + TEXT_OFF(), 1) // addr
    s = s + hexQword(TEXT_SIZE())                   // size
    s = s + hexDword(TEXT_OFF())                    // file offset
    s = s + hexDword(2)                             // align = 2^2 = 4
    s = s + hexDword(0)                             // reloff
    s = s + hexDword(0)                             // nreloc
    s = s + hexDword((0x8000 * 0x10000 + 0x400))                    // flags = PURE | SOME (S_REGULAR)
    s = s + hexDword(0)                             // reserved1
    s = s + hexDword(0)                             // reserved2
    s = s + hexDword(0)                             // reserved3
    if g_NFOREIGN > 0 {
        // Section: __stubs (S_SYMBOL_STUBS, reserved1=indirect start 0, reserved2=stub size 12)
        s = s + hexStr("__stubs") + hexPad(9) + hexStr("__TEXT") + hexPad(10)
        s = s + hexQword2(TEXT_VADDR() + STUBS_OFF(), 1) + hexQword(STUBS_SIZE())
        s = s + hexDword(STUBS_OFF()) + hexDword(2) + hexDword(0) + hexDword(0)
        s = s + hexDword((0x8000 * 0x10000 + 0x408)) + hexDword(0) + hexDword(12) + hexDword(0)
    }
    // Section: __cstring
    s = s + hexStr("__cstring") + hexPad(7)
    s = s + hexStr("__TEXT") + hexPad(10)
    s = s + hexQword2(TEXT_VADDR() + CSTRING_OFF(), 1)
    s = s + hexQword(CSTRING_SIZE())
    s = s + hexDword(CSTRING_OFF())
    s = s + hexDword(0)                             // align 1
    s = s + hexDword(0)
    s = s + hexDword(0)
    s = s + hexDword(0x00000002)                    // S_CSTRING_LITERALS
    s = s + hexDword(0)
    s = s + hexDword(0)
    s = s + hexDword(0)
    emit s
}

// LC_SEGMENT_64 __DATA_CONST (0 sections — empty reserved page)
// Kept (as an R-only zero page) only so __DATA and the heap keep their file
// offsets / vaddrs after the __got removal. cmdsize = 72.
func emitLcSegDataConst() {
    let nsects = 0  let cmdsz = 72
    if g_NFOREIGN > 0 { nsects = 1  cmdsz = 152 }
    let s = ""
    s = s + hexDword(LC_SEGMENT_64()) + hexDword(cmdsz)
    s = s + hexStr("__DATA_CONST") + hexPad(4)
    s = s + hexQword2(g_TEXT_VMSIZE, 1)             // vmaddr = TEXT_VADDR + TEXT_VMSIZE
    s = s + hexQword(0x4000)                        // vmsize (one page)
    s = s + hexQword(g_DATA_CONST_FILE_OFF)         // fileoff
    s = s + hexQword(0x4000)                        // filesize
    // When N>0 dyld must write bound pointers into __got, so the segment needs
    // R+W prot during fixups (SG_READ_ONLY re-protects it to R afterwards).
    let prot = 1
    if g_NFOREIGN > 0 { prot = 3 }
    s = s + hexDword(prot)                          // maxprot
    s = s + hexDword(prot)                          // initprot
    s = s + hexDword(nsects)                        // nsects
    s = s + hexDword(0x10)                          // SG_READ_ONLY
    if g_NFOREIGN > 0 {
        // Section: __got (S_NON_LAZY_SYMBOL_POINTERS=6, reserved1=indirect start N)
        s = s + hexStr("__got") + hexPad(11) + hexStr("__DATA_CONST") + hexPad(4)
        s = s + hexQword2(g_TEXT_VMSIZE, 1) + hexQword(GOT_SIZE())
        s = s + hexDword(GOT_OFF()) + hexDword(3) + hexDword(0) + hexDword(0)
        s = s + hexDword(6) + hexDword(g_NFOREIGN) + hexDword(0) + hexDword(0)
    }
    emit s
}

// LC_SEGMENT_64 __DATA (1 section: __bump for the heap bump pointer + heap)
//   File backs the first 16 KB; 64 KB virtual is zero-fill.
//   First 8 bytes of __DATA = the bump pointer cell (initial value =
//   DATA_VADDR + 8, i.e. the first allocatable byte).
// cmdsize = 72 + 80 = 152
func emitLcSegData() {
    let s = ""
    s = s + hexDword(LC_SEGMENT_64()) + hexDword(152)
    s = s + hexStr("__DATA") + hexPad(10)
    s = s + hexQword2(g_TEXT_VMSIZE + 0x4000, 1)    // vmaddr = TEXT_VADDR + TEXT_VMSIZE + 16 KB
    s = s + hexQword(DATA_VMSIZE())
    s = s + hexQword(DATA_FILE_OFF())
    s = s + hexQword(DATA_FILESIZE())
    s = s + hexDword(3)                             // maxprot = R+W
    s = s + hexDword(3)                             // initprot = R+W
    s = s + hexDword(1)                             // nsects
    s = s + hexDword(0)                             // flags
    // Section: __bump  (size matches filesize; vmsize beyond that is kernel zero-fill)
    s = s + hexStr("__bump") + hexPad(10)
    s = s + hexStr("__DATA") + hexPad(10)
    s = s + hexQword2(g_TEXT_VMSIZE + 0x4000, 1)    // addr = same as segment vmaddr
    s = s + hexQword(DATA_FILESIZE())               // size = filesize
    s = s + hexDword(DATA_FILE_OFF())               // file offset
    s = s + hexDword(3)                             // align 2^3 = 8
    s = s + hexDword(0)                             // reloff
    s = s + hexDword(0)                             // nreloc
    s = s + hexDword(0)                             // flags = S_REGULAR (kernel zero-fills vmsize > filesize at segment level)
    s = s + hexDword(0)
    s = s + hexDword(0)
    s = s + hexDword(0)
    emit s
}

// LC_SEGMENT_64 __LINKEDIT (no sections, 72 B)
func emitLcSegLinkedit() {
    let s = ""
    s = s + hexDword(LC_SEGMENT_64()) + hexDword(72)
    s = s + hexStr("__LINKEDIT") + hexPad(6)
    s = s + hexQword2(g_TEXT_VMSIZE + 0x4000 + DATA_VMSIZE(), 1) // vmaddr = DATA_VADDR + DATA_VMSIZE
    s = s + hexQword(0x4000)                        // vmsize
    s = s + hexQword(LINKEDIT_FILE_OFF())
    s = s + hexQword(FILE_TOTAL_SIZE() - LINKEDIT_FILE_OFF()) // filesize
    s = s + hexDword(1)                             // maxprot = R
    s = s + hexDword(1)                             // initprot = R
    s = s + hexDword(0)                             // nsects
    s = s + hexDword(0)
    emit s
}

// LC_DYLD_CHAINED_FIXUPS (16 B) — points at the empty fixups blob.
func emitLcChainedFixups() {
    let s = ""
    s = s + hexDword(LC_DYLD_CHAINED_FIXUPS()) + hexDword(16)
    s = s + hexDword(CHAINED_FIXUPS_OFF())
    s = s + hexDword(CHAINED_FIXUPS_SIZE())
    emit s
}

// LC_SYMTAB (24 B)
func emitLcSymtab() {
    let s = ""
    s = s + hexDword(LC_SYMTAB()) + hexDword(24)
    s = s + hexDword(SYMTAB_OFF())
    s = s + hexDword(NSYMS())
    s = s + hexDword(STRTAB_OFF())
    s = s + hexDword(STRTAB_SIZE())
    emit s
}

// LC_DYSYMTAB (80 B)
// nlocalsym=0, nextdefsym=2 (mh_execute_header, _main), nundefsym=0.
// No indirect symtab (the __stubs/__got that needed it are gone).
func emitLcDysymtab() {
    let s = ""
    s = s + hexDword(LC_DYSYMTAB()) + hexDword(80)
    s = s + hexDword(0)                             // ilocalsym
    s = s + hexDword(0)                             // nlocalsym
    s = s + hexDword(0)                             // iextdefsym
    s = s + hexDword(2)                             // nextdefsym
    s = s + hexDword(2)                             // iundefsym
    s = s + hexDword(g_NFOREIGN)                    // nundefsym
    s = s + hexDword(0)                             // tocoff
    s = s + hexDword(0)                             // ntoc
    s = s + hexDword(0)                             // modtaboff
    s = s + hexDword(0)                             // nmodtab
    s = s + hexDword(0)                             // extrefsymoff
    s = s + hexDword(0)                             // nextrefsyms
    s = s + hexDword(INDIRECT_OFF())                // indirectsymoff
    s = s + hexDword(NINDIRECT())                   // nindirectsyms
    s = s + hexDword(0)                             // extreloff
    s = s + hexDword(0)                             // nextrel
    s = s + hexDword(0)                             // locreloff
    s = s + hexDword(0)                             // nlocrel
    emit s
}

// One LC_LOAD_DYLIB per dylib (cmdsize = 24 + padded name length, 8-aligned).
func emitLcLoadDylibs() {
    let s = ""  let i = 0  let n = lineCount(g_DYLIBS)
    while i < n {
        let nm = getLine(g_DYLIBS, i)
        let nameLen = len(nm) + 1                   // include NUL
        let cmdsz = ((24 + nameLen + 7) / 8) * 8
        s = s + hexDword(LC_LOAD_DYLIB()) + hexDword(cmdsz) + hexDword(24)
        s = s + hexDword(2) + hexDword(0x054C0000) + hexDword(0x00010000)   // timestamp, current, compat
        s = s + hexStr(nm) + hexByte(0) + hexPad(cmdsz - 24 - nameLen)
        i += 1
    }
    emit s
}

// LC_LOAD_DYLINKER (32 B): cmd + cmdsize + name_offset + "/usr/lib/dyld\0" + pad
func emitLcLoadDylinker() {
    let s = ""
    s = s + hexDword(LC_LOAD_DYLINKER()) + hexDword(32)
    s = s + hexDword(12)                            // name offset (after 12-byte header)
    s = s + hexStr("/usr/lib/dyld") + hexByte(0)    // 14 B
    s = s + hexPad(6)                               // pad to 32 total
    emit s
}

// LC_BUILD_VERSION (24 B): platform=1 (MACOS), minos=14.0, sdk=14.0, ntools=0
func emitLcBuildVersion() {
    let s = ""
    s = s + hexDword(LC_BUILD_VERSION()) + hexDword(24)
    s = s + hexDword(1)                             // PLATFORM_MACOS
    s = s + hexDword(0x000e0000)                    // minos = 14.0.0
    s = s + hexDword(0x000e0000)                    // sdk = 14.0.0
    s = s + hexDword(0)                             // ntools
    emit s
}

// LC_MAIN (24 B): entry offset in __TEXT, stack size
func emitLcMain() {
    let s = ""
    s = s + hexDword(LC_MAIN()) + hexDword(24)
    s = s + hexQword(g_ENTRY_OFF)                   // entryoff (vaddr of _main)
    s = s + hexQword(0)                             // stacksize
    emit s
}

// (LC_LOAD_DYLIB libSystem removed — the runtime imports no C library.)

// LC_CODE_SIGNATURE (16 B)
func emitLcCodeSignature() {
    let s = ""
    s = s + hexDword(LC_CODE_SIGNATURE()) + hexDword(16)
    s = s + hexDword(CODESIG_OFF())
    s = s + hexDword(CODESIG_SIZE())
    emit s
}

// ── header (32 B) ───────────────────────────────────────────────────────────

func emitHeader(ncmds, sizeofcmds) {
    let s = ""
    s = s + hexDword(MH_MAGIC_64())
    s = s + hexDword(CPU_TYPE_ARM64())
    s = s + hexDword(0)                             // cpusubtype
    s = s + hexDword(MH_EXECUTE())
    s = s + hexDword(ncmds)
    s = s + hexDword(sizeofcmds)
    s = s + hexDword(MH_NOUNDEFS() + MH_DYLDLINK() + MH_TWOLEVEL() + MH_PIE())
    s = s + hexDword(0)                             // reserved
    emit s
}

// ── driver ──────────────────────────────────────────────────────────────────

// Encode an ASCII string as a hex-encoded byte sequence.
func asciiToHex(s) {
    let out = ""
    let i = 0
    while i < len(s) {
        out = out + hexByte(charCode(s[i]))
        i += 1
    }
    emit out
}

// ── objk import de-risk: emit a minimal 1-import Mach-O ──────────────────────
// Hand-lays a complete binary that imports `_getpid` from libSystem.B.dylib via
// a dyld stub + chained-bind GOT, calls it, and exits with the pid (low byte).
// Byte-for-byte mirrors a clang reference. Isolated from the production path —
// proves dyld on Tahoe accepts the generalized chained-fixups + LC_LOAD_DYLIB
// before that machinery is wired into the IR codegen. Reached via --objk-import-test.
func emitObjkTestBinary(outFile) {
    g_TEXT_VMSIZE = 0x4000                          // execSegLimit for the signer
    // ---- __text + __stubs (file 0x400) ----
    // _main @ 0x100000400: bl stub(+3); exit(x0): movz x16,#1; svc #0x80
    let mainCode = arm64_bl(3) + arm64_movz_x_imm(16, 1) + arm64_svc(0x80)
    let stubCode = arm64_adrp(16, 4) + arm64_ldr_imm(16, 16, 0) + arm64_br(16)
    let textBlob = mainCode + stubCode              // 24 B @ 0x400

    // ---- load commands ----
    let lcs = ""
    // 1: __PAGEZERO (72)
    lcs = lcs + hexDword(LC_SEGMENT_64()) + hexDword(72) + hexStr("__PAGEZERO") + hexPad(6)
    lcs = lcs + hexQword2(0,0) + hexQword2(0,1) + hexQword(0) + hexQword(0)
    lcs = lcs + hexDword(0) + hexDword(0) + hexDword(0) + hexDword(0)
    // 2: __TEXT (2 sects: __text, __stubs) (232)
    lcs = lcs + hexDword(LC_SEGMENT_64()) + hexDword(232) + hexStr("__TEXT") + hexPad(10)
    lcs = lcs + hexQword2(0,1) + hexQword(0x4000) + hexQword(0) + hexQword(0x4000)
    lcs = lcs + hexDword(5) + hexDword(5) + hexDword(2) + hexDword(0)
    //   sect __text @ 0x400, size 12
    lcs = lcs + hexStr("__text") + hexPad(10) + hexStr("__TEXT") + hexPad(10)
    lcs = lcs + hexQword2(0x400,1) + hexQword(12) + hexDword(0x400) + hexDword(2)
    lcs = lcs + hexDword(0) + hexDword(0) + hexDword((0x8000*0x10000+0x400)) + hexDword(0) + hexDword(0) + hexDword(0)
    //   sect __stubs @ 0x40c, size 12, S_SYMBOL_STUBS, reserved1=0(indirect idx), reserved2=12(stub size)
    lcs = lcs + hexStr("__stubs") + hexPad(9) + hexStr("__TEXT") + hexPad(10)
    lcs = lcs + hexQword2(0x40c,1) + hexQword(12) + hexDword(0x40c) + hexDword(2)
    lcs = lcs + hexDword(0) + hexDword(0) + hexDword((0x8000*0x10000+0x408)) + hexDword(0) + hexDword(12) + hexDword(0)
    // 3: __DATA_CONST (1 sect __got) (152)
    lcs = lcs + hexDword(LC_SEGMENT_64()) + hexDword(152) + hexStr("__DATA_CONST") + hexPad(4)
    lcs = lcs + hexQword2(0x4000,1) + hexQword(0x4000) + hexQword(0x4000) + hexQword(0x4000)
    lcs = lcs + hexDword(3) + hexDword(3) + hexDword(1) + hexDword(0x10)
    //   sect __got @ 0x100004000, size 8, S_NON_LAZY_SYMBOL_POINTERS, reserved1=1(indirect idx)
    lcs = lcs + hexStr("__got") + hexPad(11) + hexStr("__DATA_CONST") + hexPad(4)
    lcs = lcs + hexQword2(0x4000,1) + hexQword(8) + hexDword(0x4000) + hexDword(3)
    lcs = lcs + hexDword(0) + hexDword(0) + hexDword(6) + hexDword(1) + hexDword(0) + hexDword(0)
    // 4: __LINKEDIT (72) — fileoff 0x8000, filesize = total - 0x8000
    let leSize = (0x80c0 + 312) - 0x8000
    lcs = lcs + hexDword(LC_SEGMENT_64()) + hexDword(72) + hexStr("__LINKEDIT") + hexPad(6)
    lcs = lcs + hexQword2(0x8000,1) + hexQword(0x4000) + hexQword(0x8000) + hexQword(leSize)
    lcs = lcs + hexDword(1) + hexDword(1) + hexDword(0) + hexDword(0)
    // 5: LC_DYLD_CHAINED_FIXUPS (16) @ 0x8000, 96
    lcs = lcs + hexDword(LC_DYLD_CHAINED_FIXUPS()) + hexDword(16) + hexDword(0x8000) + hexDword(96)
    // 6: LC_SYMTAB (24): symoff 0x8060, nsyms 3, stroff 0x8098, strsize 40
    lcs = lcs + hexDword(LC_SYMTAB()) + hexDword(24) + hexDword(0x8060) + hexDword(3) + hexDword(0x8098) + hexDword(40)
    // 7: LC_DYSYMTAB (80): nlocalsym0, iextdef0 nextdef2, iundef2 nundef1, indirectsymoff 0x8090 nindirect2
    lcs = lcs + hexDword(LC_DYSYMTAB()) + hexDword(80)
    lcs = lcs + hexDword(0) + hexDword(0) + hexDword(0) + hexDword(2) + hexDword(2) + hexDword(1)
    lcs = lcs + hexDword(0) + hexDword(0) + hexDword(0) + hexDword(0) + hexDword(0) + hexDword(0)
    lcs = lcs + hexDword(0x8090) + hexDword(2) + hexDword(0) + hexDword(0) + hexDword(0) + hexDword(0)
    // 8: LC_LOAD_DYLINKER (32)
    lcs = lcs + hexDword(LC_LOAD_DYLINKER()) + hexDword(32) + hexDword(12) + hexStr("/usr/lib/dyld") + hexByte(0) + hexPad(6)
    // 9: LC_BUILD_VERSION (24)
    lcs = lcs + hexDword(LC_BUILD_VERSION()) + hexDword(24) + hexDword(1) + hexDword(0x000e0000) + hexDword(0x000e0000) + hexDword(0)
    // 10: LC_MAIN (24): entryoff 0x400
    lcs = lcs + hexDword(LC_MAIN()) + hexDword(24) + hexQword(0x400) + hexQword(0)
    // 11: LC_LOAD_DYLIB libSystem.B.dylib (56)
    lcs = lcs + hexDword(LC_LOAD_DYLIB()) + hexDword(56) + hexDword(24) + hexDword(2) + hexDword(0x054C0000) + hexDword(0x00010000)
    lcs = lcs + hexStr("/usr/lib/libSystem.B.dylib") + hexByte(0) + hexPad(5)
    // 12: LC_CODE_SIGNATURE (16): codesig @ 0x80c0
    lcs = lcs + hexDword(LC_CODE_SIGNATURE()) + hexDword(16) + hexDword(0x80c0) + hexDword(312)

    let header = emitHeader(12, hexBytesLen(lcs))
    let prefix = header + lcs                        // 32 + 800 = 832

    // ---- LINKEDIT blobs ----
    // chained fixups (96 B)
    let fx = ""
    fx = fx + hexDword(0) + hexDword(32) + hexDword(80) + hexDword(84)   // version, starts_off, imports_off, symbols_off
    fx = fx + hexDword(1) + hexDword(1) + hexDword(0) + hexDword(0)      // imports_count, imports_format=1, symbols_format=0, pad
    // starts_in_image @ +32: seg_count=4, offsets[PAGEZERO,TEXT,DATA_CONST,LINKEDIT]; [2]=24 (8-aligns the seg struct)
    fx = fx + hexDword(4) + hexDword(0) + hexDword(0) + hexDword(24) + hexDword(0)
    fx = fx + hexPad(4)                                                  // gap: 20-byte array -> seg struct at +24
    // starts_in_segment @ +56: size24, page_size 0x4000, ptr_format 6, seg_offset 0x4000, max_valid 0, page_count1, page_start[0]=0
    fx = fx + hexDword(24) + hexWord(0x4000) + hexWord(6) + hexQword(0x4000) + hexDword(0) + hexWord(1) + hexWord(0)
    // imports @ +80: dyld_chained_import = lib_ordinal1 | name_offset(1)<<9 = 0x201
    fx = fx + hexDword(0x201)
    // symbols @ +84: "\0_getpid\0", pad to 96
    fx = fx + hexByte(0) + hexStr("_getpid") + hexByte(0) + hexPad(3)
    // symtab (3 × nlist_64, 48 B)
    let sym = ""
    sym = sym + hexDword(2)  + hexByte(0x0f) + hexByte(1) + hexWord(0x10) + hexQword2(0,1)        // __mh_execute_header
    sym = sym + hexDword(22) + hexByte(0x0f) + hexByte(1) + hexWord(0)    + hexQword2(0x400,1)    // _main
    sym = sym + hexDword(28) + hexByte(0x01) + hexByte(0) + hexWord(0x100) + hexQword2(0,0)       // _getpid (undef, ordinal 1)
    // indirect symtab (2 × uint32) — __stubs[0] + __got[1] both -> sym idx 2
    let isym = hexDword(2) + hexDword(2)
    // strtab (40 B)
    let strt = hexByte(0x20) + hexByte(0) + hexStr("__mh_execute_header") + hexByte(0) + hexStr("_main") + hexByte(0) + hexStr("_getpid") + hexByte(0) + hexPad(4)
    // got slot (8 B) — dyld_chained_ptr_64_bind ordinal 0
    let got = hexDword(0) + hexDword((0x8000*0x10000+0x0))

    // ---- assemble body up to codesig ----
    let body = prefix + hexPad(0x400 - hexBytesLen(prefix))
    body = body + textBlob + hexPad(0x4000 - 0x400 - hexBytesLen(textBlob))
    body = body + got + hexPad(0x8000 - 0x4008)
    body = body + fx + sym + isym + strt                 // 96+48+8+40 = 192 = 0x8000..0x80c0
    let codeLimit = hexBytesLen(body)
    if codeLimit != 0x80c0 {
        printErr("objk-test: BUG body=" + codeLimit + " want 0x80c0=32960")
        exit("1")
    }
    let cd = buildCodeDirectory(body, codeLimit, "krypton")
    let sig = buildSuperBlob(cd)
    if hexBytesLen(sig) != 312 {
        printErr("objk-test: BUG sig=" + hexBytesLen(sig) + " want 312")
        exit("1")
    }
    writeBytes(outFile, body + sig)
    printErr("objk-test: wrote " + outFile + " (1 import _getpid@libSystem, ad-hoc signed)")
    emit "1"
}

just run {
    // Build the hex lookup table first so all subsequent hexByte/hexDword calls
    // take the cheap substring path (keeps self-compile heap in budget).
    g_hexLUT = buildHexLUT()
    if argCount() == 0 {
        printErr("usage: kcc compiler/macos_arm64/macho_arm64_self.k <output_path>")
        printErr("       kcc compiler/macos_arm64/macho_arm64_self.k --ir <input.kir> <output_path>")
        printErr("       kcc compiler/macos_arm64/macho_arm64_self.k --sha256-test")
        exit("1")
    }

    let arg0 = arg("0")
    let outFile = arg0

    // --ir <input.kir> <output_path>: compile the simple-subset IR to a
    // signed arm64 Mach-O. Sets globals from IR-derived layout, then falls
    // through to the same emission path as the hello-world default.
    let irOps = ""
    let irStrOffsets = ""
    let useIr = "0"
    if arg0 == "--ir" {
        let inFile = arg("1")
        outFile = arg("2")
        if len(inFile) == 0 || len(outFile) == 0 {
            printErr("usage: --ir <input.kir> <output_path>")
            exit("1")
        }
        let ir = readFile(inFile)
        if len(ir) == 0 {
            printErr("macho_arm64_self: cannot read " + inFile)
            exit("1")
        }
        irOps = parseFullIR(ir)
        detectForeign(irOps)
        if g_NFOREIGN > 0 { printErr("objk: " + g_NFOREIGN + " foreign sym(s) [" + g_FORSYMS + "] across " + lineCount(g_DYLIBS) + " dylib(s)") }
        g_funcStartCache = buildFuncStartCache(irOps)
        irStrOffsets = computeStringOffsets(irOps)
        g_TEXT_SIZE = computeTextSize(irOps)
        g_CSTRING_SIZE = computeCStringSize(irOps)
        // Now that text/cstring sizes are known, compute the dynamic layout
        // (g_TEXT_VMSIZE rounds up to 16 KB pages; downstream offsets follow).
        computeLayout()
        // Locate __main__ in the function table so LC_MAIN entryoff and the
        // _main symtab entry point at the right function (not blindly TEXT_OFF).
        let fTable = buildFunctionTable(irOps)
        let mainInstr = findLabel(fTable, "__main__")
        if mainInstr < 0 {
            printErr("macho_arm64_self: no __main__ function found in IR")
            exit("1")
        }
        g_ENTRY_OFF = TEXT_OFF() + mainInstr * 4
        useIr = "1"
    }

    // objk import de-risk (isolated; no IR, no production layout).
    if arg0 == "--objk-import-test" {
        let oOut = arg("1")
        if len(oOut) == 0 { printErr("usage: --objk-import-test <out>")  exit("1") }
        emitObjkTestBinary(oOut)
        exit("0")
    }

    // Always run computeLayout (default mode picks up the static defaults; IR
    // mode overrides g_TEXT_SIZE/g_CSTRING_SIZE first). Idempotent for default values.
    computeLayout()

    if arg0 == "--debug-parse" {
        let inFile = arg("1")
        let ir = readFile(inFile)
        let parsed = parseFullIR(ir)
        printErr("=== parsed ===")
        printErr(parsed)
        printErr("=== end ===")
        exit("0")
    }

    if arg0 == "--sha256-test" {
        // Verify SHA-256 against canonical test vectors before trusting the
        // impl in the signing path.
        let empty = ""
        let h0 = sha256_hex(empty, 0, 0)
        printErr("SHA-256(\"\")    = " + h0)
        printErr("expected         = xE3xB0xC4x42x98xFCx1Cx14x9AxFBxF4xC8x99x6FxB9x24x27xAEx41xE4x64x9Bx93x4CxA4x95x99x1Bx78x52xB8x55")

        let abc = asciiToHex("abc")
        let h1 = sha256_hex(abc, 0, 3)
        printErr("SHA-256(\"abc\") = " + h1)
        printErr("expected         = xBAx78x16xBFx8Fx01xCFxEAx41x41x40xDEx5DxAEx22x23xB0x03x61xA3x96x17x7Ax9CxB4x10xFFx61xF2x00x15xAD")

        // 56-byte boundary case (one chunk, all in one block w/ short pad)
        let s56 = asciiToHex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
        let h2 = sha256_hex(s56, 0, 56)
        printErr("SHA-256(56-byte) = " + h2)
        printErr("expected         = x24x8Dx6Ax61xD2x06x38xB8xE5xC0x26x93x0Cx3Ex60x39xA3x3CxE4x59x64xFFx21x67xF6xECxEDxD4x19xDBx06xC1")
        exit(0)
    }

    // Build all 12 load commands. The chained-fixups blob is EMPTY (no
    // imports), and there is no LC_LOAD_DYLIB: the runtime links no C library
    // (libSystem/_puts gone). dyld still requires the fixups command present.
    let lcs = ""
    lcs = lcs + emitLcPagezero()
    lcs = lcs + emitLcSegText()
    lcs = lcs + emitLcSegDataConst()
    lcs = lcs + emitLcSegData()
    lcs = lcs + emitLcSegLinkedit()
    lcs = lcs + emitLcChainedFixups()
    lcs = lcs + emitLcSymtab()
    lcs = lcs + emitLcDysymtab()
    lcs = lcs + emitLcLoadDylinker()
    lcs = lcs + emitLcBuildVersion()
    lcs = lcs + emitLcMain()
    lcs = lcs + emitLcLoadDylibs()              // objk: one LC_LOAD_DYLIB per dylib (empty when N=0)
    lcs = lcs + emitLcCodeSignature()

    let sizeofcmds = hexBytesLen(lcs)
    let header = emitHeader(12 + lineCount(g_DYLIBS), sizeofcmds)

    // Pre-text padding: from (32 + sizeofcmds) up to TEXT_OFF
    let prefix = header + lcs
    let prefixSize = hexBytesLen(prefix)
    let preTextPad = TEXT_OFF() - prefixSize

    let textCode = ""
    let cstrData = ""
    if useIr == "1" {
        let freshTextSz = computeTextSize(irOps)
        textCode = emitTextFromIR(irOps, irStrOffsets, freshTextSz)
        cstrData = emitCStringFromIR(irOps)
        // GC only scans the stack for roots, not BSS globals. During the large
        // emits above, GC may collect the string values of g_TEXT_SIZE /
        // g_CSTRING_SIZE (only referenced from BSS, not the stack), leaving them
        // as dangling pointers. Refresh from the already-built local strings —
        // these ARE on the stack and won't be collected.
        g_TEXT_SIZE = hexBytesLen(textCode)
        g_CSTRING_SIZE = hexBytesLen(cstrData)
        computeLayout()
    } else {
        textCode = emitMainCode()
        cstrData = emitCString()
    }
    // Pad after __cstring up to __DATA_CONST page boundary (file 0x4000)
    let textSegEnd = CSTRING_OFF() + CSTRING_SIZE()
    let postCstringPad = DATA_CONST_FILE_OFF() - textSegEnd

    // __DATA_CONST: empty reserved page — zero fill to the __DATA boundary.
    let dataConstPad = DATA_FILE_OFF() - DATA_CONST_FILE_OFF()

    // __DATA file backing — 16 KB of zeros (no useful initial data; the bump
    // cell lives in the zero-fill region past filesize, where pages are
    // anonymous-mapped and actually writable on code-signed binaries).
    let dataInit = ""
    let postDataPad = LINKEDIT_FILE_OFF() - DATA_FILE_OFF()

    // __LINKEDIT: empty chained fixups + symtab + strtab (no indirect symtab)
    let leChained = emitChainedFixups()
    let leSymtab = emitSymtab()
    let leIndirect = ""
    if g_NFOREIGN > 0 { leIndirect = emitIndirectN() }
    let leStrtab = emitStrtab()
    // Pad strtab end to CODESIG_OFF (16-byte align)
    let strtabEnd = STRTAB_OFF() + STRTAB_SIZE()
    let preCodesigPad = CODESIG_OFF() - strtabEnd

    // objk: __stubs (after __text, before __cstring) + __got (start of __DATA_CONST)
    let stubsB = ""
    let gotB = ""
    if g_NFOREIGN > 0 { stubsB = emitStubsN()  gotB = emitGotN() }

    // Build the file body up to (but NOT including) the code signature.
    // This is exactly `codeLimit` bytes — what the kernel hashes.
    let body = prefix + hexPad(preTextPad)
    body = body + textCode + stubsB + cstrData + hexPad(postCstringPad)
    body = body + gotB + hexPad(dataConstPad - hexBytesLen(gotB))
    body = body + dataInit + hexPad(postDataPad)
    body = body + leChained + leSymtab + leIndirect + leStrtab + hexPad(preCodesigPad)

    let codeLimit = hexBytesLen(body)
    if codeLimit != CODESIG_OFF() {
        printErr("macho_arm64_self: BUG: body size " + codeLimit + " != CODESIG_OFF " + CODESIG_OFF())
        printErr("  prefix=" + hexBytesLen(prefix) + " preTextPad=" + preTextPad + " textCode=" + hexBytesLen(textCode))
        printErr("  cstrData=" + hexBytesLen(cstrData) + " postCstringPad=" + postCstringPad + " dataConstPad=" + dataConstPad)
        printErr("  postDataPad=" + postDataPad)
        printErr("  leSymtab=" + hexBytesLen(leSymtab) + " leStrtab=" + hexBytesLen(leStrtab) + " preCodesigPad=" + preCodesigPad)
        printErr("  g_TEXT_SIZE=" + g_TEXT_SIZE + " g_CSTRING_SIZE=" + g_CSTRING_SIZE)
        exit("1")
    }

    // Compute ad-hoc code signature in Krypton — no external `codesign`.
    let cd = buildCodeDirectory(body, codeLimit, "krypton")
    let sig = buildSuperBlob(cd)
    let sigLen = hexBytesLen(sig)
    if sigLen != CODESIG_SIZE() {
        printErr("macho_arm64_self: BUG: sig size " + sigLen + " != CODESIG_SIZE " + CODESIG_SIZE())
        exit("1")
    }

    let machoBytes = body + sig
    writeBytes(outFile, machoBytes)
    printErr("macho_arm64_self: wrote " + outFile + " (" + (hexBytesLen(machoBytes)) + " bytes, ad-hoc signed)")
}
