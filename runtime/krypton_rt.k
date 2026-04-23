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

export func kr_sbnew() {
    emit sbNew()
}

export func kr_sbappend(sb, s) {
    emit sbAppend(sb, s)
}

export func kr_sbtostring(sb) {
    emit sbToString(sb)
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
