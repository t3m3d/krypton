// krypton_rt.k — Krypton runtime implemented in Krypton (Phase 2)
// Build:
//   cp C:/krypton/krypton_rt.dll C:/krypton/krypton_rt_legacy.dll
//   kcc -o C:/krypton/krypton_rt.dll --headers C:/krypton/headers runtime/krypton_rt.k

// ── Type conversions ──────────────────────────────────────────────

export func kr_str(s) {
    emit s
}

export func kr_toint(s) {
    emit toInt(s) + ""
}

// ── Arithmetic ────────────────────────────────────────────────────

export func kr_plus(a, b) {
    emit a + b
}

export func kr_sub(a, b) {
    emit a - b
}

export func kr_mul(a, b) {
    emit a * b
}

export func kr_div(a, b) {
    emit a / b
}

export func kr_mod(a, b) {
    emit a % b
}

export func kr_neg(a) {
    emit 0 - toInt(a)
}

// ── Comparisons ───────────────────────────────────────────────────

export func kr_eq(a, b) {
    if a == b { emit "1" }
    emit "0"
}

export func kr_neq(a, b) {
    if a != b { emit "1" }
    emit "0"
}

export func kr_lt(a, b) {
    if a < b { emit "1" }
    emit "0"
}

export func kr_gt(a, b) {
    if a > b { emit "1" }
    emit "0"
}

export func kr_lte(a, b) {
    if a <= b { emit "1" }
    emit "0"
}

export func kr_gte(a, b) {
    if a >= b { emit "1" }
    emit "0"
}

export func kr_truthy(s) {
    if s == "" { emit "0" }
    if s == "0" { emit "0" }
    emit "1"
}

export func kr_not(s) {
    if s == "" { emit "1" }
    if s == "0" { emit "1" }
    emit "0"
}

// ── String operations ─────────────────────────────────────────────

export func kr_len(s) {
    emit len(s)
}

export func kr_substring(s, start, end) {
    emit substring(s, toInt(start), toInt(end))
}

export func kr_startswith(s, prefix) {
    if startsWith(s, prefix) { emit "1" }
    emit "0"
}

export func kr_contains(s, needle) {
    if contains(s, needle) { emit "1" }
    emit "0"
}

export func kr_trim(s) {
    emit trim(s)
}

export func kr_replace(s, from, to) {
    emit replace(s, from, to)
}

export func kr_split(s, idx) {
    emit split(s, toInt(idx))
}

export func kr_getline(s, idx) {
    emit getLine(s, toInt(idx))
}

export func kr_linecount(s) {
    emit lineCount(s)
}

export func kr_count(lst) {
    emit count(lst)
}

export func kr_length(lst) {
    emit count(lst)
}

// ── I/O ───────────────────────────────────────────────────────────

export func kr_print(s) {
    print(s)
    emit ""
}

export func kr_printerr(s) {
    printErr(s)
    emit ""
}

export func kr_printl(s) {
    print(s)
    emit ""
}

export func kr_exit(code) {
    exit(toInt(code))
    emit ""
}

// ── Lists ─────────────────────────────────────────────────────────

export func kr_range(start, end) {
    emit range(start, end)
}

// ── String builder ────────────────────────────────────────────────
//
// Real growing-capacity StringBuilder. Replaces the legacy stub that
// just called sbNew/sbAppend/sbToString builtins (which resolved to a
// 1-byte empty alloc and a strcat-based append → O(n²) for any program
// that accumulates a long sb).
//
// Layout (per allocation):
//   [base + 0 .. base + 7]   length qword  (count of data bytes; not NUL)
//   [base + 8 .. base + N-1] data buffer (NUL-terminated within capacity)
// User-facing pointer is `base + 8` — a normal NUL-terminated C-string
// so len(sb) / kp(sb) / sb + s / etc. all work without changes.
//
// Capacity is read from the stage-1.5 alloc header at `base - 8`
// (size+flags qword, low 2 bits masked off). On overflow, allocate a
// new buffer 2x the requested size and copy.
//
// Amortized O(1) per append; O(n) total for n appends of constant size.
// This drops compile.k's IR-emit RAM use by orders of magnitude.

export func kr_sbnew() {
    let buf = rawAlloc(64)
    bufSetQwordAt(buf, 0, 0)
    bufSetByte(buf, 8, 0)
    emit intToPtr(ptrToInt(buf) + 8)
}

export func kr_sbappend(sb, s) {
    let s_len = len(s)
    if s_len == 0 { emit sb }
    let base = intToPtr(ptrToInt(sb) - 8)
    let cur_len = bufGetQwordAt(base, 0)
    let needed = cur_len + s_len

    let cap_field = intToPtr(ptrToInt(base) - 8)
    let raw_cap = bufGetQwordAt(cap_field, 0)
    let alloc_total = bitAnd(raw_cap, 0 - 4)
    let data_cap = alloc_total - 24

    if needed + 1 > data_cap {
        let new_total = 2 * (needed + 1) + 8
        if new_total < 64 { new_total = 64 }
        let new_buf = rawAlloc(new_total)
        let i = 0
        while i < cur_len {
            bufSetByte(new_buf, i + 8, bufGetByte(sb, i))
            i = i + 1
        }
        let j = 0
        while j < s_len {
            bufSetByte(new_buf, cur_len + 8 + j, bufGetByte(s, j))
            j = j + 1
        }
        bufSetByte(new_buf, needed + 8, 0)
        bufSetQwordAt(new_buf, 0, needed)
        emit intToPtr(ptrToInt(new_buf) + 8)
    }

    let j = 0
    while j < s_len {
        bufSetByte(base, cur_len + 8 + j, bufGetByte(s, j))
        j = j + 1
    }
    bufSetByte(base, needed + 8, 0)
    bufSetQwordAt(base, 0, needed)
    emit sb
}

export func kr_sbtostring(sb) {
    let cur_len = bufGetQwordAt(intToPtr(ptrToInt(sb) - 8), 0)
    let dst = rawAlloc(cur_len + 1)
    let i = 0
    while i < cur_len {
        bufSetByte(dst, i, bufGetByte(sb, i))
        i = i + 1
    }
    bufSetByte(dst, cur_len, 0)
    emit dst
}

// ── File I/O ──────────────────────────────────────────────────────

export func kr_readfile(path) {
    emit readFile(path)
}

export func kr_writefile(path, data) {
    emit writeFile(path, data)
}

// ── Args ──────────────────────────────────────────────────────────

export func kr_argcount() {
    emit argCount()
}

export func kr_arg(idx) {
    emit arg(idx)
}

export func kr_init_args(argc, argv) {
    emit ""
}

// ── String / char builtins ────────────────────────────────────────

export func kr_idx(s, i) {
    let n = toInt(i)
    emit substring(s, n, n + 1)
}

export func kr_indexof(s, needle) {
    emit indexOf(s, needle)
}

export func kr_charcode(s) {
    emit charCode(s)
}

export func kr_isdigit(s) {
    emit isDigit(s)
}

export func kr_fromcharcode(n) {
    emit fromCharCode(n)
}

export func kr_tolower(s) {
    emit toLower(s)
}

export func kr_touppers(s) {
    emit toUpper(s)
}

export func kr_hex(n) {
    emit hex(n)
}

export func kr_div64(a, b) {
    emit div64(a, b)
}

export func kr_environ(name) {
    emit environ(name)
}

export func kr_sizeof(name) {
    emit sizeOf(name)
}

export func kr_tohandle(s) {
    emit toHandle(s)
}

export func kr_writebytes(path, hexstr) {
    emit writeBytes(path, hexstr)
}

// ── Bitwise builtins ──────────────────────────────────────────────

export func kr_bitor(a, b) {
    emit bitOr(a, b)
}

export func kr_bitand(a, b) {
    emit bitAnd(a, b)
}

export func kr_bitxor(a, b) {
    emit bitXor(a, b)
}

export func kr_bitnot(a) {
    emit bitNot(a)
}

export func kr_shl(a, b) {
    emit shl(a, b)
}

export func kr_shr(a, b) {
    emit shr(a, b)
}

// ── Buffer builtins ───────────────────────────────────────────────

export func kr_bufnew(size) {
    emit bufNew(size)
}

export func kr_bufstr(buf) {
    emit bufStr(buf)
}

export func kr_bufsetdword(buf, val) {
    emit bufSetDword(buf, val)
}

export func kr_bufgetdword(buf) {
    emit bufGetDword(buf)
}

export func kr_bufsetdwordat(buf, off, val) {
    emit bufSetDwordAt(buf, off, val)
}

export func kr_bufgetdwordat(buf, off) {
    emit bufGetDwordAt(buf, off)
}

export func kr_bufgetword(buf) {
    emit bufGetWord(buf)
}

export func kr_bufgetqword(buf) {
    emit bufGetQword(buf)
}

export func kr_bufgetqwordat(buf, off) {
    emit bufGetQwordAt(buf, off)
}

export func kr_bufsetbyte(buf, off, val) {
    emit bufSetByte(buf, off, val)
}

export func kr_bufgetbyte(buf, off) {
    emit bufGetByte(buf, off)
}

// ── Struct builtins ───────────────────────────────────────────────

export func kr_structnew(name) {
    emit structNew(name)
}

export func kr_structget(buf, sname, fname) {
    emit structGet(buf, sname, fname)
}

export func kr_structset(buf, sname, fname, val) {
    emit structSet(buf, sname, fname, val)
}

// ── Handle builtins ───────────────────────────────────────────────

export func kr_handleout() {
    emit handleOut()
}

export func kr_handleget(buf) {
    emit handleGet(buf)
}

export func kr_handlevalid(h) {
    emit handleValid(h)
}

export func kr_handleint(ptr) {
    emit handleInt(ptr)
}

// ── Pointer builtins ──────────────────────────────────────────────

export func kr_ptrderef(ptr) {
    emit ptrDeref(ptr)
}

export func kr_ptrindex(ptr, n) {
    emit ptrIndex(ptr, n)
}

// ── callPtr wrappers (1–4 args) ───────────────────────────────────

export func kr_callptr1(fn, a0) {
    emit callPtr(fn, a0)
}

export func kr_callptr2(fn, a0, a1) {
    emit callPtr(fn, a0, a1)
}

export func kr_callptr3(fn, a0, a1, a2) {
    emit callPtr(fn, a0, a1, a2)
}

export func kr_callptr4(fn, a0, a1, a2, a3) {
    emit callPtr(fn, a0, a1, a2, a3)
}

// ── Phase 1: Raw memory primitives ───────────────────────────────

export func kr_rawalloc(size) {
    emit rawAlloc(size)
}

export func kr_rawfree(ptr) {
    emit rawFree(ptr)
}

export func kr_rawrealloc(ptr, size) {
    emit rawRealloc(ptr, size)
}

export func kr_ptradd(ptr, n) {
    emit ptrAdd(ptr, n)
}

export func kr_ptrtoint(ptr) {
    emit ptrToInt(ptr)
}

export func kr_rawreadbyte(ptr, off) {
    emit rawReadByte(ptr, off)
}

export func kr_rawreadword(ptr, off) {
    emit rawReadWord(ptr, off)
}

export func kr_rawwriteword(ptr, off, val) {
    emit rawWriteWord(ptr, off, val)
}

export func kr_rawwriteqword(ptr, off, val) {
    emit rawWriteQword(ptr, off, val)
}
