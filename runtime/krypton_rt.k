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
