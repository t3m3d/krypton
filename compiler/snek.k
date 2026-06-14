// compiler/snek.k -- minimal Python-ish frontend for Krypton.
//
// Reads a .kp source file containing a small subset of Python:
//   - int + string literals
//   - names (variable references)
//   - assignment:           x = expr
//   - function call:        print(x), name(arg, arg, ...)
//   - binary arithmetic:    +  -  *  /  %
//   - comparison:           ==  !=  <  <=  >  >=
//   - one statement per line, top level only (no def, no if, no while yet)
//   - line comments:        # ...
//
// Emits equivalent Krypton source to stdout (or to a file via -o).  The
// caller then runs that through kcc.  Two-step pipeline keeps this
// translator focused -- no IR knowledge, no backend assumptions.
//
// Usage:
//   kcc -r compiler/snek.k examples/hello.kp           # write Krypton to stdout
//   kcc -r compiler/snek.k examples/hello.kp -o out.k  # write to file
//   kcc out.k -o hello.exe                              # then compile normally
//
// Naming:
//   *No* "py" or "python" inside identifiers / module names per house rule.
//   "snek" is the project codename; ".kp" is the source extension for now
//   (Brian to bless or rename later).
//
// Constraints + roadmap notes:
//   - Indentation-significant blocks (def / if / while) are deliberately
//     out of MVP scope; second commit will land an INDENT/DEDENT pass.
//   - Output is Krypton SOURCE text, not IR.  Cleanest bootstrap path:
//     keeps us decoupled from compile.k's IR ops until we want to do
//     direct-to-IR for perf.
//   - Compat matrix lives in docs/python_compat.md; this file's lowering
//     decisions track docs/python_to_kir.md (translated to source level).

module snek


// ──────────────────────────────────────────────────────────────────────
// Token types
// ──────────────────────────────────────────────────────────────────────
//
// A token is encoded as a 3-field comma-list: "kind,value,line".
// Token kinds (strings):
//   NUM      integer literal       value = digits
//   STR      string literal        value = raw bytes between quotes
//   NAME     identifier            value = name
//   KW       keyword               value = keyword text
//   OP       operator/punct        value = operator text
//   NL       newline (significant for statement termination)
//   EOF      end of input          value = ""
//
// Multi-token streams are joined with "\n" so we can use lineCount /
// getLine for iteration.

// Module-level `let` strings can read garbage inside functions on the
// Windows native pipeline (see feedback_module_mutable_globals.md and
// observed via snek_dbg6.k -- count(MYDATA) returns 1 instead of 4
// inside a func).  Wrap in a func so the value comes from the helper's
// own slot, not the read-broken module slot.
func snekKeywords() {
    emit "and,or,not,if,else,elif,while,def,return,True,False,None,pass,import,from,as,for,in"
}


// Tokens use TAB as the inter-field separator -- not comma -- because
// some token values are literally `,` (the comma operator) and others
// can contain `,` inside (STR, FSTR).  TAB is not produced anywhere by
// the lexer (whitespace gets skipped, not stored).
func tok(kind, val, line) {
    emit kind + "\t" + val + "\t" + line
}

// splitChar(s, sep, i): split s on single-char sep, return i-th segment.
// Used by tokKind/tokVal/tokLine since Krypton's built-in `split()` is
// hard-coded to comma.
func splitChar(s, sep, i) {
    let n = len(s)
    let cur = 0
    let segStart = 0
    let j = 0
    while j < n {
        if s[j] == sep {
            if cur == i { emit substring(s, segStart, j) }
            cur = cur + 1
            segStart = j + 1
        }
        j = j + 1
    }
    if cur == i { emit substring(s, segStart, n) }
    emit ""
}

func tokKind(t)  { emit splitChar(t, "\t", 0) }
func tokVal(t)   { emit splitChar(t, "\t", 1) }
func tokLine(t)  { emit splitChar(t, "\t", 2) }


// ──────────────────────────────────────────────────────────────────────
// Lexer
// ──────────────────────────────────────────────────────────────────────

func isAlpha(c) {
    let n = charCode(c)
    if n >= 65 && n <= 90  { emit "1" }
    if n >= 97 && n <= 122 { emit "1" }
    if c == "_"            { emit "1" }
    emit "0"
}

func isAlNum(c) {
    if isAlpha(c) == "1" { emit "1" }
    if isDigit(c) == "1" { emit "1" }
    emit "0"
}

func isKeyword(name) {
    let kw = snekKeywords()
    let n = count(kw)
    let i = 0
    while i < n {
        if split(kw, i) == name { emit "1" }
        i = i + 1
    }
    emit "0"
}

// indent stack helpers -- the stack is a comma-list of int levels,
// e.g. "0,4,8".  Top is the last element.
func indTop(stk)         { emit toInt(split(stk, count(stk) - 1)) }
func indPush(stk, lvl)   { emit stk + "," + toStr(lvl) }
func indPop(stk) {
    let n = count(stk)
    if n <= 1 { emit "0" }
    let out = ""
    let i = 0
    while i < n - 1 {
        if i > 0 { out = out + "," }
        out = out + split(stk, i)
        i = i + 1
    }
    emit out
}

// lex(src) -> "\n"-joined token list, terminated with EOF token.
// Emits INDENT/DEDENT around indented blocks (Python-style).  Tabs are
// counted as 8 spaces.
func lex(src) {
    let out  = sbNew()
    let line = 1
    let i    = 0
    let n    = len(src)
    let first = "1"
    let stk   = "0"           // indent stack, top is last entry
    let atLineStart = "1"     // true when next non-blank token starts a logical line

    while i < n {
        let c = src[i]

        // ── start-of-line whitespace: measure indent ──
        if atLineStart == "1" {
            let col = 0
            while i < n && (src[i] == " " || src[i] == "\t") {
                if src[i] == "\t" { col = col + 8 } else { col = col + 1 }
                i = i + 1
            }
            // blank or comment-only line: skip indent handling, eat to NL
            if i >= n { continue }
            if src[i] == "\n" {
                // blank line: emit NL but no indent change
                if first == "0" { out = sbAppend(out, "\n") }
                out = sbAppend(out, tok("NL", "", line))
                first = "0"
                line = line + 1
                i = i + 1
                continue
            }
            if src[i] == "#" {
                while i < n && src[i] != "\n" { i = i + 1 }
                continue
            }
            // Real token starts here at column `col`.
            let top = indTop(stk)
            if col > top {
                if first == "0" { out = sbAppend(out, "\n") }
                out = sbAppend(out, tok("INDENT", "", line))
                first = "0"
                stk = indPush(stk, col)
            }
            if col < top {
                while indTop(stk) > col && count(stk) > 1 {
                    if first == "0" { out = sbAppend(out, "\n") }
                    out = sbAppend(out, tok("DEDENT", "", line))
                    first = "0"
                    stk = indPop(stk)
                }
            }
            atLineStart = "0"
            continue
        }

        // ── whitespace (space / tab) inside a line ──
        if c == " " || c == "\t" {
            i = i + 1
            continue
        }

        // ── line comment ──
        if c == "#" {
            while i < n && src[i] != "\n" { i = i + 1 }
            continue
        }

        // ── newline ──
        if c == "\n" {
            if first == "0" { out = sbAppend(out, "\n") }
            out = sbAppend(out, tok("NL", "", line))
            first = "0"
            line = line + 1
            i = i + 1
            atLineStart = "1"
            continue
        }

        // ── f-string literal: `f"..."` or `f'...'` ──
        // Emits a single FSTR token containing the raw content (including
        // `{...}` interpolation markers).  Parser later splits into a
        // static-and-dynamic concat tree.
        if c == "f" && i + 1 < n {
            let nx = src[i + 1]
            if nx == "\"" || nx == "'" {
                i = i + 1                  // skip 'f'
                let quote = src[i]
                i = i + 1
                let start = i
                while i < n && src[i] != quote {
                    if src[i] == "\\" && i + 1 < n { i = i + 1 }
                    i = i + 1
                }
                let s = substring(src, start, i)
                if i < n { i = i + 1 }    // closing quote
                if first == "0" { out = sbAppend(out, "\n") }
                out = sbAppend(out, tok("FSTR", s, line))
                first = "0"
                continue
            }
        }

        // ── string literal (single or double quoted, no escapes yet) ──
        if c == "\"" || c == "'" {
            let quote = c
            i = i + 1
            let start = i
            while i < n && src[i] != quote {
                if src[i] == "\\" && i + 1 < n { i = i + 1 }   // skip next char
                i = i + 1
            }
            let s = substring(src, start, i)
            if i < n { i = i + 1 }    // closing quote
            if first == "0" { out = sbAppend(out, "\n") }
            out = sbAppend(out, tok("STR", s, line))
            first = "0"
            continue
        }

        // ── number literal ──
        if isDigit(c) == "1" {
            let start = i
            while i < n && isDigit(src[i]) == "1" { i = i + 1 }
            let s = substring(src, start, i)
            if first == "0" { out = sbAppend(out, "\n") }
            out = sbAppend(out, tok("NUM", s, line))
            first = "0"
            continue
        }

        // ── identifier / keyword ──
        if isAlpha(c) == "1" {
            let start = i
            while i < n && isAlNum(src[i]) == "1" { i = i + 1 }
            let s = substring(src, start, i)
            let kind = "NAME"
            if isKeyword(s) == "1" { kind = "KW" }
            if first == "0" { out = sbAppend(out, "\n") }
            out = sbAppend(out, tok(kind, s, line))
            first = "0"
            continue
        }

        // ── two-char operators ──
        if i + 1 < n {
            let two = substring(src, i, i + 2)
            if two == "==" || two == "!=" || two == "<=" || two == ">=" || two == "->" ||
               two == "+=" || two == "-=" || two == "*=" || two == "/=" || two == "%=" ||
               two == "**" || two == "//" {
                if first == "0" { out = sbAppend(out, "\n") }
                out = sbAppend(out, tok("OP", two, line))
                first = "0"
                i = i + 2
                continue
            }
        }

        // ── single-char operators / punctuation ──
        if c == "+" || c == "-" || c == "*" || c == "/" || c == "%" ||
           c == "(" || c == ")" || c == "," || c == ":" || c == "=" ||
           c == "<" || c == ">" || c == "." || c == "[" || c == "]" {
            if first == "0" { out = sbAppend(out, "\n") }
            out = sbAppend(out, tok("OP", c, line))
            first = "0"
            i = i + 1
            continue
        }

        // unknown character -- skip, surface a soft warning by emitting an OP
        // with the raw byte; emit avoids hard-failing on first bad input.
        if first == "0" { out = sbAppend(out, "\n") }
        out = sbAppend(out, tok("OP", c, line))
        first = "0"
        i = i + 1
    }

    // Flush any open indent levels with DEDENTs before EOF.
    while indTop(stk) > 0 && count(stk) > 1 {
        if first == "0" { out = sbAppend(out, "\n") }
        out = sbAppend(out, tok("DEDENT", "", line))
        first = "0"
        stk = indPop(stk)
    }
    if first == "0" { out = sbAppend(out, "\n") }
    out = sbAppend(out, tok("EOF", "", line))
    emit sbToString(out)
}


// ──────────────────────────────────────────────────────────────────────
// Parser state
// ──────────────────────────────────────────────────────────────────────
//
// The parser walks the token stream with a single integer cursor.  We
// store it in guiState (per Krypton's module-mutable-global workaround)
// keyed by a unique slot string.

// Parser state is threaded explicitly: every parser func takes
// (toks, pos) and returns a "result\nnewPos" string the caller splits
// via getLine.  guiState was the original design but it segfaults on
// CLI-only PEs (see feedback_guistate_cli_broken memory).

// Pair helpers: pack/unpack (node, pos) into a single string.
// Format: "<nodeLen>|<node><pos>"   where pos is the trailing slice.
// Length-prefixed so node can contain any byte including '\n' and '|'.
// `pos` is typically int but used for arbitrary tail strings too (e.g.
// emitStmt threads `decls` through the same channel).
func pkPair(node, pos) { emit toStr(len(node)) + "|" + node + toStr(pos) }
func pkNode(r) {
    let b = indexOf(r, "|")
    let l = toInt(substring(r, 0, b))
    emit substring(r, b + 1, b + 1 + l)
}
func pkPos(r) {
    let b = indexOf(r, "|")
    let l = toInt(substring(r, 0, b))
    emit toInt(substring(r, b + 1 + l, len(r)))
}
// pkTail: same as pkPos but returns string (for decls threading).
func pkTail(r) {
    let b = indexOf(r, "|")
    let l = toInt(substring(r, 0, b))
    emit substring(r, b + 1 + l, len(r))
}

// Length-prefixed list helpers.  Lists encode as "<n>|<l0>|<i0><l1>|<i1>..."
// where <n> is item count and each <l*> is the byte length of <i*>.  This
// lets items contain any byte (including '\n' and '|') without ambiguity.
func listEmpty()         { emit "0|" }
func listCount(s)        { emit toInt(substring(s, 0, indexOf(s, "|"))) }
func listStart(s)        { emit indexOf(s, "|") + 1 }
// listGet(s, cursor) -> "<newCursor>|<item>"
func listGet(s, cursor) {
    let rest = substring(s, cursor, len(s))
    let b = indexOf(rest, "|")
    let l = toInt(substring(rest, 0, b))
    let itemStart = cursor + b + 1
    let item = substring(s, itemStart, itemStart + l)
    emit toStr(itemStart + l) + "|" + item
}
// listGetCursor / listGetItem split the listGet result.
func lgCursor(g) { emit toInt(substring(g, 0, indexOf(g, "|"))) }
func lgItem(g)   {
    let b = indexOf(g, "|")
    emit substring(g, b + 1, len(g))
}

// Peek the token at `pos` without advancing.
func peekTok(toks, pos) { emit getLine(toks, pos) }

// Predicate helpers -- pure, no advance.
func atKind(toks, pos, k) {
    let t = peekTok(toks, pos)
    if tokKind(t) == k { emit "1" }
    emit "0"
}

func atOp(toks, pos, op) {
    let t = peekTok(toks, pos)
    if tokKind(t) == "OP" && tokVal(t) == op { emit "1" }
    emit "0"
}

func atKw(toks, pos, kw) {
    let t = peekTok(toks, pos)
    if tokKind(t) == "KW" && tokVal(t) == kw { emit "1" }
    emit "0"
}


// ──────────────────────────────────────────────────────────────────────
// AST nodes
// ──────────────────────────────────────────────────────────────────────
//
// Nodes are encoded with a leading kind tag + tagged fields.  Format:
//   "<KIND>|<field1>|<field2>|..."
//
// Kinds:
//   NUM|<value>
//   STR|<value>                       (value uses ; for any embedded |)
//   NAME|<name>
//   BOOL|<0|1>
//   NONE|
//   BIN|<op>|<left-node>|<right-node>
//   ASSIGN|<name>|<expr-node>
//   CALL|<name>|<arg-count>|<arg1>|<arg2>|...
//   EXPRSTMT|<expr>                   (bare expression as a statement)
//
// `|` chosen as separator because expressions don't contain | and we
// can grow toward nested nodes without comma collisions.

func astNum(v)            { emit "NUM|" + v }
func astStr(v)            { emit "STR|" + _escFld(v) }
func astName(v)           { emit "NAME|" + v }
func astBool(v)           { emit "BOOL|" + v }
func astNone()            { emit "NONE|" }
// BIN uses a length-prefix on the left child to dodge `|` collisions
// inside recursively-nested nodes.  Format: "BIN|<op>|<llen>|<left><right>"
func astBin(op, l, r)     { emit "BIN|" + op + "|" + toStr(len(l)) + "|" + l + r }
// ASSIGN length-prefixes the expr so any internal `|` or `,` in the
// expression node survives intact through the emitter.
func astAssign(name, e)   { emit "ASSIGN|" + name + "|" + toStr(len(e)) + "|" + e }
func astExprStmt(e)       { emit "EXPRSTMT|" + e }

// CALL encodes args as a length-prefixed list (same shape as the
// listGet helpers): "CALL|<name>|<n>|<l0>|<a0><l1>|<a1>...".  `argList`
// must already be in that format -- parsePrimary / parseCallArgs builds
// it directly to avoid CSV/comma collisions with STR contents.
func astCall(name, n, argList) {
    emit "CALL|" + name + "|" + toStr(n) + "|" + argList
}

// Block-introducing statements -- all use the length-prefixed-list
// format documented near pkPair / listGet for their bodies, so bodies
// can contain any byte.

// DEF: "DEF|<name>|<argsCSV>|<bodyLen>|<body>"
func astDef(name, args, body) {
    emit "DEF|" + name + "|" + args + "|" + toStr(len(body)) + "|" + body
}

// IF: "IF|<cLen>|<cond><tLen>|<then><eLen>|<else>"
// else is an encoded list -- may be listEmpty() if no else.
func astIf(cond, thenB, elseB) {
    emit "IF|" + toStr(len(cond)) + "|" + cond + toStr(len(thenB)) + "|" + thenB + toStr(len(elseB)) + "|" + elseB
}

// WHILE: "WHILE|<cLen>|<cond><bLen>|<body>"
func astWhile(cond, body) {
    emit "WHILE|" + toStr(len(cond)) + "|" + cond + toStr(len(body)) + "|" + body
}

func astReturn(e) { emit "RETURN|" + e }
func astPass()    { emit "PASS|" }

// FOR: "FOR|<var>|<iterLen>|<iter><bodyLen>|<body>"
func astFor(varName, iter, body) {
    emit "FOR|" + varName + "|" + toStr(len(iter)) + "|" + iter + toStr(len(body)) + "|" + body
}

// IMPORT: "IMPORT|<modName>"
// Python `import math` lowers to Krypton `import "k:math"` (assumes
// the module ships in stdlib).  No `from x import y` or `as` aliasing
// in MVP -- those come in phase 5.
func astImport(modName) { emit "IMPORT|" + modName }

// LIST: "LIST|<n>|<l0>|<e0><l1>|<e1>..."
// Lowered to a comma-string at emit time: toStr(e0) + "," + toStr(e1) + ...
// This matches Krypton's string-as-faux-list convention (count/split/getLine).
func astList(n, elemList) {
    emit "LIST|" + toStr(n) + "|" + elemList
}

// INDEX: "INDEX|<oLen>|<obj><iLen>|<idx>"
// `xs[i]` -> split(xs, i) for comma-strings; substring for plain strings.
func astIndex(obj, idx) {
    emit "INDEX|" + toStr(len(obj)) + "|" + obj + toStr(len(idx)) + "|" + idx
}

// SLICE: "SLICE|<oLen>|<obj><aLen>|<a><bLen>|<b>"
// `s[a:b]` -> substring(s, a, b)
func astSlice(obj, a, b) {
    emit "SLICE|" + toStr(len(obj)) + "|" + obj + toStr(len(a)) + "|" + a + toStr(len(b)) + "|" + b
}

// String-field escape: replace | with ; so it can ride inside a node.
func _escFld(s) {
    emit replace(s, "|", ";")
}
func _unescFld(s) {
    emit replace(s, ";", "|")
}


// ──────────────────────────────────────────────────────────────────────
// Parser -- recursive descent
// ──────────────────────────────────────────────────────────────────────

// program  := (statement | NL)* EOF
// statement := assignment | exprStmt
// assignment := NAME "=" expr NL
// exprStmt := expr NL
// expr := comparison
// comparison := addExpr (("==" | "!=" | "<" | "<=" | ">" | ">=") addExpr)*
// addExpr  := mulExpr (("+" | "-") mulExpr)*
// mulExpr  := unary (("*" | "/" | "%") unary)*
// unary    := ("-" unary) | primary
// primary  := NUM | STR | "True" | "False" | "None"
//           | NAME ( "(" args ")" )?
//           | "(" expr ")"
// args     := (expr ("," expr)*)?

// parseProgram returns a length-prefixed list of statement nodes.
func parseProgram(toks) {
    let body = sbNew()
    let n = 0
    let pos = 0
    while atKind(toks, pos, "EOF") == "0" {
        if atKind(toks, pos, "NL") == "1" {
            pos = pos + 1
            continue
        }
        let r = parseStatement(toks, pos)
        let stmt = pkNode(r)
        pos = pkPos(r)
        if stmt != "" {
            body = sbAppend(body, toStr(len(stmt)) + "|" + stmt)
            n = n + 1
        }
    }
    emit toStr(n) + "|" + sbToString(body)
}

// parseBlock consumes INDENT...DEDENT and returns a length-prefixed
// statement list as pkPair(list, newPos).
func parseBlock(toks, pos) {
    if atKind(toks, pos, "INDENT") != "1" { emit pkPair(listEmpty(), pos) }
    pos = pos + 1
    let body = sbNew()
    let n = 0
    while atKind(toks, pos, "DEDENT") == "0" && atKind(toks, pos, "EOF") == "0" {
        if atKind(toks, pos, "NL") == "1" { pos = pos + 1  continue }
        let r = parseStatement(toks, pos)
        let stmt = pkNode(r)
        pos = pkPos(r)
        if stmt != "" {
            body = sbAppend(body, toStr(len(stmt)) + "|" + stmt)
            n = n + 1
        }
    }
    if atKind(toks, pos, "DEDENT") == "1" { pos = pos + 1 }
    emit pkPair(toStr(n) + "|" + sbToString(body), pos)
}

func parseStatement(toks, pos) {
    // Block-introducing keywords.
    if atKw(toks, pos, "def")    == "1" { emit parseDef(toks, pos) }
    if atKw(toks, pos, "if")     == "1" { emit parseIf(toks, pos) }
    if atKw(toks, pos, "while")  == "1" { emit parseWhile(toks, pos) }
    if atKw(toks, pos, "for")    == "1" { emit parseFor(toks, pos) }
    if atKw(toks, pos, "return") == "1" { emit parseReturn(toks, pos) }
    if atKw(toks, pos, "pass")   == "1" {
        pos = pos + 1
        if atKind(toks, pos, "NL") == "1" { pos = pos + 1 }
        emit pkPair(astPass(), pos)
    }
    if atKw(toks, pos, "import") == "1" {
        pos = pos + 1
        let modT = peekTok(toks, pos)
        let modName = tokVal(modT)
        pos = pos + 1
        if atKind(toks, pos, "NL") == "1" { pos = pos + 1 }
        emit pkPair(astImport(modName), pos)
    }
    // `from MOD import N1, N2, ...` -- for MVP, just emit the bare import;
    // user accesses the names via `MOD.N1(...)` etc.  Real binding-aliases
    // come in a later pass.
    if atKw(toks, pos, "from") == "1" {
        pos = pos + 1
        let modT = peekTok(toks, pos)
        let modName = tokVal(modT)
        pos = pos + 1
        if atKw(toks, pos, "import") == "1" { pos = pos + 1 }
        // Skip the imported names list -- we don't bind them yet.
        while atKind(toks, pos, "NL") == "0" && atKind(toks, pos, "EOF") == "0" {
            pos = pos + 1
        }
        if atKind(toks, pos, "NL") == "1" { pos = pos + 1 }
        emit pkPair(astImport(modName), pos)
    }

    // Lookahead: NAME "=" ... is an assignment, NAME "+=" etc. an
    // augmented assignment that desugars to `NAME = NAME <op> expr`.
    if atKind(toks, pos, "NAME") == "1" {
        let nxt = peekTok(toks, pos + 1)
        let nxtKind = tokKind(nxt)
        let nxtVal = tokVal(nxt)
        if nxtKind == "OP" && nxtVal == "=" {
            let nameTok = peekTok(toks, pos)
            pos = pos + 2                          // consume NAME and "="
            let r = parseExpr(toks, pos)
            pos = pkPos(r)
            if atKind(toks, pos, "NL") == "1" { pos = pos + 1 }
            emit pkPair(astAssign(tokVal(nameTok), pkNode(r)), pos)
        }
        if nxtKind == "OP" && (nxtVal == "+=" || nxtVal == "-=" || nxtVal == "*=" || nxtVal == "/=" || nxtVal == "%=") {
            let nameTok = peekTok(toks, pos)
            let nameVal = tokVal(nameTok)
            let op = substring(nxtVal, 0, 1)         // strip the trailing '='
            pos = pos + 2                            // consume NAME and aug-op
            let r = parseExpr(toks, pos)
            pos = pkPos(r)
            if atKind(toks, pos, "NL") == "1" { pos = pos + 1 }
            // Build:  name = name <op> expr
            let rhs = astBin(op, astName(nameVal), pkNode(r))
            emit pkPair(astAssign(nameVal, rhs), pos)
        }
    }
    // Otherwise: bare expression statement.
    let r = parseExpr(toks, pos)
    pos = pkPos(r)
    if atKind(toks, pos, "NL") == "1" { pos = pos + 1 }
    emit pkPair(astExprStmt(pkNode(r)), pos)
}

// def NAME ( arg, arg ) : NL INDENT body DEDENT
func parseDef(toks, pos) {
    pos = pos + 1                                   // consume 'def'
    let nameT = peekTok(toks, pos)
    let name = tokVal(nameT)
    pos = pos + 1                                   // consume name
    if atOp(toks, pos, "(") == "1" { pos = pos + 1 }
    let args = ""
    while atOp(toks, pos, ")") == "0" && atKind(toks, pos, "EOF") == "0" {
        if atOp(toks, pos, ",") == "1" { pos = pos + 1 }
        if atOp(toks, pos, ")") == "1" { continue }
        let argT = peekTok(toks, pos)
        if args == "" { args = tokVal(argT) } else { args = args + "," + tokVal(argT) }
        pos = pos + 1
        // Eat optional type hint `: TYPE` (TYPE = NAME or dotted name).
        // Python allows arbitrarily complex annotations; we accept the
        // common case and skip until comma or close-paren.
        if atOp(toks, pos, ":") == "1" {
            pos = pos + 1
            while atOp(toks, pos, ",") == "0" && atOp(toks, pos, ")") == "0" && atKind(toks, pos, "EOF") == "0" {
                pos = pos + 1
            }
        }
    }
    if atOp(toks, pos, ")") == "1" { pos = pos + 1 }
    // Eat optional return type `-> TYPE` (any tokens up to the `:`).
    if atOp(toks, pos, "->") == "1" {
        pos = pos + 1
        while atOp(toks, pos, ":") == "0" && atKind(toks, pos, "EOF") == "0" && atKind(toks, pos, "NL") == "0" {
            pos = pos + 1
        }
    }
    if atOp(toks, pos, ":") == "1" { pos = pos + 1 }
    if atKind(toks, pos, "NL") == "1" { pos = pos + 1 }
    let br = parseBlock(toks, pos)
    let body = pkNode(br)
    pos = pkPos(br)
    emit pkPair(astDef(name, args, body), pos)
}

// if cond : block (elif cond : block)* (else : block)?
// elif is desugared to nested if in the else branch: each elif becomes
// `else { if elif_cond { ... } else { ... } }` -- this lets the emitter
// stay branchless about elif.
func parseIf(toks, pos) {
    pos = pos + 1                                   // consume 'if'
    emit parseIfTail(toks, pos)
}

func parseIfTail(toks, pos) {
    let ce = parseExpr(toks, pos)
    let cond = pkNode(ce)
    pos = pkPos(ce)
    if atOp(toks, pos, ":") == "1" { pos = pos + 1 }
    if atKind(toks, pos, "NL") == "1" { pos = pos + 1 }
    let tb = parseBlock(toks, pos)
    let thenB = pkNode(tb)
    pos = pkPos(tb)
    let elseB = listEmpty()
    // Skip any NL between blocks before checking for else/elif.
    while atKind(toks, pos, "NL") == "1" { pos = pos + 1 }
    if atKw(toks, pos, "elif") == "1" {
        pos = pos + 1
        // Desugar `elif cond:` as the contents of the else branch being
        // a single nested IF.  Recurse into parseIfTail with the elif
        // condition treated like a fresh `if`.
        let nested = parseIfTail(toks, pos)
        // Wrap the nested IF node in a 1-element list so emitStmtList
        // can render it as the else body.
        let nestedNode = pkNode(nested)
        pos = pkPos(nested)
        elseB = "1|" + toStr(len(nestedNode)) + "|" + nestedNode
        emit pkPair(astIf(cond, thenB, elseB), pos)
    }
    if atKw(toks, pos, "else") == "1" {
        pos = pos + 1
        if atOp(toks, pos, ":") == "1" { pos = pos + 1 }
        if atKind(toks, pos, "NL") == "1" { pos = pos + 1 }
        let eb = parseBlock(toks, pos)
        elseB = pkNode(eb)
        pos = pkPos(eb)
    }
    emit pkPair(astIf(cond, thenB, elseB), pos)
}

// for NAME in EXPR : NL INDENT body DEDENT
func parseFor(toks, pos) {
    pos = pos + 1                                   // consume 'for'
    let varT = peekTok(toks, pos)
    let varName = tokVal(varT)
    pos = pos + 1                                   // consume var name
    if atKw(toks, pos, "in") == "1" { pos = pos + 1 }
    let ie = parseExpr(toks, pos)
    let iter = pkNode(ie)
    pos = pkPos(ie)
    if atOp(toks, pos, ":") == "1" { pos = pos + 1 }
    if atKind(toks, pos, "NL") == "1" { pos = pos + 1 }
    let bb = parseBlock(toks, pos)
    let body = pkNode(bb)
    pos = pkPos(bb)
    emit pkPair(astFor(varName, iter, body), pos)
}

func parseWhile(toks, pos) {
    pos = pos + 1                                   // consume 'while'
    let ce = parseExpr(toks, pos)
    let cond = pkNode(ce)
    pos = pkPos(ce)
    if atOp(toks, pos, ":") == "1" { pos = pos + 1 }
    if atKind(toks, pos, "NL") == "1" { pos = pos + 1 }
    let bb = parseBlock(toks, pos)
    let body = pkNode(bb)
    pos = pkPos(bb)
    emit pkPair(astWhile(cond, body), pos)
}

func parseReturn(toks, pos) {
    pos = pos + 1                                   // consume 'return'
    // bare `return` -> empty expr
    if atKind(toks, pos, "NL") == "1" {
        pos = pos + 1
        emit pkPair(astReturn(""), pos)
    }
    let re = parseExpr(toks, pos)
    let expr = pkNode(re)
    pos = pkPos(re)
    if atKind(toks, pos, "NL") == "1" { pos = pos + 1 }
    emit pkPair(astReturn(expr), pos)
}

func parseExpr(toks, pos) {
    emit parseOr(toks, pos)
}

// Python: `or` has lower precedence than `and`, both lower than `not`,
// `not` higher than comparisons.  Mapping to Krypton: || && and a
// leading 0-comparison for `not`.
func parseOr(toks, pos) {
    let r = parseAnd(toks, pos)
    let left = pkNode(r)
    pos = pkPos(r)
    while atKw(toks, pos, "or") == "1" {
        pos = pos + 1
        let rr = parseAnd(toks, pos)
        let right = pkNode(rr)
        pos = pkPos(rr)
        // BIN encoding splits on `|`, so the op `||` would clash.
        // Use a textual alias and translate at emit time.
        left = astBin("OR", left, right)
    }
    emit pkPair(left, pos)
}

func parseAnd(toks, pos) {
    let r = parseNot(toks, pos)
    let left = pkNode(r)
    pos = pkPos(r)
    while atKw(toks, pos, "and") == "1" {
        pos = pos + 1
        let rr = parseNot(toks, pos)
        let right = pkNode(rr)
        pos = pkPos(rr)
        left = astBin("AND", left, right)
    }
    emit pkPair(left, pos)
}

func parseNot(toks, pos) {
    if atKw(toks, pos, "not") == "1" {
        pos = pos + 1
        let r = parseNot(toks, pos)
        // Render Python `not x` as `(x == "0")` -- Krypton's truthiness
        // model treats "0"/""/"false" as false; comparing for equality
        // against "0" gives a boolean inversion that survives the
        // common-case integer/string mix.
        emit pkPair(astBin("==", pkNode(r), astStr("0")), pkPos(r))
    }
    emit parseComparison(toks, pos)
}

func parseComparison(toks, pos) {
    let r = parseAddExpr(toks, pos)
    let left = pkNode(r)
    pos = pkPos(r)
    while atOp(toks, pos, "==") == "1" || atOp(toks, pos, "!=") == "1" ||
          atOp(toks, pos, "<")  == "1" || atOp(toks, pos, "<=") == "1" ||
          atOp(toks, pos, ">")  == "1" || atOp(toks, pos, ">=") == "1" ||
          atKw(toks, pos, "in") == "1" || atKw(toks, pos, "not") == "1" ||
          atKw(toks, pos, "is") == "1" {
        let t = peekTok(toks, pos)
        let op = tokVal(t)
        // KW "in" lowers via an "IN" op alias so emit can swap arg
        // order (Python: needle in haystack -> Krypton: contains(haystack, needle))
        if tokKind(t) == "KW" && op == "in" { op = "IN" }
        // "not in" -- two KW tokens treated as one op.
        if tokKind(t) == "KW" && op == "not" {
            if atKw(toks, pos + 1, "in") == "1" {
                op = "NOTIN"
                pos = pos + 1
            }
        }
        // "is" / "is not" -- Python identity ops; lowered to == / != for
        // our string-comparison semantics.
        if tokKind(t) == "KW" && op == "is" {
            op = "=="
            if atKw(toks, pos + 1, "not") == "1" {
                op = "!="
                pos = pos + 1
            }
        }
        pos = pos + 1
        let rr = parseAddExpr(toks, pos)
        let right = pkNode(rr)
        pos = pkPos(rr)
        left = astBin(op, left, right)
    }
    emit pkPair(left, pos)
}

func parseAddExpr(toks, pos) {
    let r = parseMulExpr(toks, pos)
    let left = pkNode(r)
    pos = pkPos(r)
    while atOp(toks, pos, "+") == "1" || atOp(toks, pos, "-") == "1" {
        let op = tokVal(peekTok(toks, pos))
        pos = pos + 1
        let rr = parseMulExpr(toks, pos)
        let right = pkNode(rr)
        pos = pkPos(rr)
        left = astBin(op, left, right)
    }
    emit pkPair(left, pos)
}

func parseMulExpr(toks, pos) {
    let r = parseUnary(toks, pos)
    let left = pkNode(r)
    pos = pkPos(r)
    while atOp(toks, pos, "*") == "1" || atOp(toks, pos, "/") == "1" || atOp(toks, pos, "%") == "1" ||
          atOp(toks, pos, "**") == "1" || atOp(toks, pos, "//") == "1" {
        let op = tokVal(peekTok(toks, pos))
        // Python `//` is integer division -- Krypton's `/` already does
        // that, so rewrite at parse time.  `**` lowers to a pow() call
        // at emit (POW alias since `**` would corrupt the BIN op slot).
        if op == "//" { op = "/" }
        if op == "**" { op = "POW" }
        pos = pos + 1
        let rr = parseUnary(toks, pos)
        let right = pkNode(rr)
        pos = pkPos(rr)
        left = astBin(op, left, right)
    }
    emit pkPair(left, pos)
}

func parseUnary(toks, pos) {
    if atOp(toks, pos, "-") == "1" {
        pos = pos + 1
        let r = parseUnary(toks, pos)
        // Encode -x as 0 - x for the source-emit path.
        emit pkPair(astBin("-", astNum("0"), pkNode(r)), pkPos(r))
    }
    emit parsePrimary(toks, pos)
}

// parseFstr(content) -- walks an f-string body and folds the static
// + dynamic chunks into a left-associative BIN(+) tree of:
//   astStr(staticPart) + astCall("toStr", [innerExpr]) + ...
// `content` is the raw bytes between the surrounding quotes.  Inner
// `{...}` regions are recursively lexed + parsed.
func parseFstr(content) {
    let n = len(content)
    let i = 0
    let staticBuf = sbNew()
    let parts = sbNew()
    let nParts = 0
    while i < n {
        let c = content[i]
        if c == "{" {
            let s = sbToString(staticBuf)
            if s != "" {
                let node = astStr(s)
                parts = sbAppend(parts, toStr(len(node)) + "|" + node)
                nParts = nParts + 1
                staticBuf = sbNew()
            }
            i = i + 1
            let exprStart = i
            let depth = 1
            while i < n && depth > 0 {
                if content[i] == "{" { depth = depth + 1 }
                if content[i] == "}" { depth = depth - 1 }
                if depth > 0 { i = i + 1 }
            }
            let exprStr = substring(content, exprStart, i)
            if i < n { i = i + 1 }
            let inner = lex(exprStr)
            let r = parseExpr(inner, 0)
            let exprNode = pkNode(r)
            // Wrap in toStr(...) so the result joins as a string.
            let argList = toStr(len(exprNode)) + "|" + exprNode
            let toStrNode = astCall("toStr", 1, argList)
            parts = sbAppend(parts, toStr(len(toStrNode)) + "|" + toStrNode)
            nParts = nParts + 1
        }
        if c != "{" {
            staticBuf = sbAppend(staticBuf, c)
            i = i + 1
        }
    }
    let s = sbToString(staticBuf)
    if s != "" {
        let node = astStr(s)
        parts = sbAppend(parts, toStr(len(node)) + "|" + node)
        nParts = nParts + 1
    }
    if nParts == 0 { emit astStr("") }
    let body = sbToString(parts)
    let cursor = 0
    let acc = ""
    let i2 = 0
    while i2 < nParts {
        let bar = indexOf(substring(body, cursor, len(body)), "|")
        let l = toInt(substring(body, cursor, cursor + bar))
        let nStart = cursor + bar + 1
        let node = substring(body, nStart, nStart + l)
        cursor = nStart + l
        if i2 == 0 { acc = node } else { acc = astBin("+", acc, node) }
        i2 = i2 + 1
    }
    emit acc
}

// Postfix chain: parses `[idx]` / `[a:b]` repeatedly against an
// already-built `node`.  Returns pkPair(wrappedNode, newPos).
func parsePostfix(toks, pos, node) {
    while atOp(toks, pos, "[") == "1" {
        pos = pos + 1
        let r1 = parseExpr(toks, pos)
        let a = pkNode(r1)
        pos = pkPos(r1)
        if atOp(toks, pos, ":") == "1" {
            pos = pos + 1
            let r2 = parseExpr(toks, pos)
            let b = pkNode(r2)
            pos = pkPos(r2)
            if atOp(toks, pos, "]") == "1" { pos = pos + 1 }
            node = astSlice(node, a, b)
        }
        if atOp(toks, pos, "]") == "1" {
            pos = pos + 1
            node = astIndex(node, a)
        }
    }
    emit pkPair(node, pos)
}

func parsePrimary(toks, pos) {
    let t = peekTok(toks, pos)
    let k = tokKind(t)
    let v = tokVal(t)

    if k == "NUM"  { emit parsePostfix(toks, pos + 1, astNum(v)) }
    if k == "STR"  { emit parsePostfix(toks, pos + 1, astStr(v)) }
    if k == "FSTR" { emit parsePostfix(toks, pos + 1, parseFstr(v)) }

    if k == "KW" {
        if v == "True"  { emit parsePostfix(toks, pos + 1, astBool("1")) }
        if v == "False" { emit parsePostfix(toks, pos + 1, astBool("0")) }
        if v == "None"  { emit parsePostfix(toks, pos + 1, astNone()) }
    }

    if k == "OP" && v == "(" {
        pos = pos + 1
        let r = parseExpr(toks, pos)
        pos = pkPos(r)
        if atOp(toks, pos, ")") == "1" { pos = pos + 1 }
        emit parsePostfix(toks, pos, pkNode(r))
    }

    // List literal: [e1, e2, ...]   (also supports empty list `[]`)
    if k == "OP" && v == "[" {
        pos = pos + 1
        let elems = sbNew()
        let nElems = 0
        while atOp(toks, pos, "]") == "0" && atKind(toks, pos, "EOF") == "0" {
            if atOp(toks, pos, ",") == "1" { pos = pos + 1 }
            if atOp(toks, pos, "]") == "1" { continue }
            let r = parseExpr(toks, pos)
            let e = pkNode(r)
            pos = pkPos(r)
            elems = sbAppend(elems, toStr(len(e)) + "|" + e)
            nElems = nElems + 1
        }
        if atOp(toks, pos, "]") == "1" { pos = pos + 1 }
        emit parsePostfix(toks, pos, astList(nElems, sbToString(elems)))
    }

    if k == "NAME" {
        pos = pos + 1
        // Build a dotted name (e.g. `math.sqrt`) into a single
        // module-qualified identifier.  Krypton accepts `mod.func`
        // call syntax natively when `mod` was imported.
        let callee = v
        while atOp(toks, pos, ".") == "1" {
            pos = pos + 1
            let dotT = peekTok(toks, pos)
            callee = callee + "." + tokVal(dotT)
            pos = pos + 1
        }
        // Followed by "("? -> call.
        if atOp(toks, pos, "(") == "1" {
            pos = pos + 1
            // Build a length-prefixed list of arg nodes directly so STR
            // contents containing ',' don't corrupt arg boundaries.
            let argList = sbNew()
            let nArgs = 0
            while atOp(toks, pos, ")") == "0" && atKind(toks, pos, "EOF") == "0" {
                if atOp(toks, pos, ",") == "1" { pos = pos + 1 }
                if atOp(toks, pos, ")") == "1" { continue }
                let r = parseExpr(toks, pos)
                let a = pkNode(r)
                pos = pkPos(r)
                argList = sbAppend(argList, toStr(len(a)) + "|" + a)
                nArgs = nArgs + 1
            }
            if atOp(toks, pos, ")") == "1" { pos = pos + 1 }
            emit parsePostfix(toks, pos, astCall(callee, nArgs, sbToString(argList)))
        }
        emit parsePostfix(toks, pos, astName(callee))
    }

    // Unknown -- emit a NAME with the raw token text to avoid hard fail.
    emit parsePostfix(toks, pos + 1, astName(v))
}


// ──────────────────────────────────────────────────────────────────────
// Emitter -- AST -> Krypton source text
// ──────────────────────────────────────────────────────────────────────
//
// Statements get wrapped in `just run { ... }` since Krypton requires
// an entry point.  The emitter walks each AST node and lowers it to a
// Krypton expression / statement.
//
// Python -> Krypton lowering for MVP:
//   print(x)           ->  print(x)              (same builtin)
//   x = expr           ->  let x = <expr>        (first occurrence)
//                          x = <expr>            (later occurrences)
//   "hello"            ->  "hello"
//   42                 ->  42
//   a + b              ->  a + b
//   True / False / None -> "1" / "0" / ""
//
// First-vs-later assignment tracking lives in a guiState set.

// `decls` is a comma-list of names already let-declared.  Threaded
// explicitly through the emitter -- same pattern as the parser uses
// for `pos`.

func declared(decls, name) {
    if decls == "" { emit "0" }
    let n = count(decls)
    let i = 0
    while i < n {
        if split(decls, i) == name { emit "1" }
        i = i + 1
    }
    emit "0"
}

func markDeclared(decls, name) {
    if decls == "" { emit name }
    emit decls + "," + name
}

func emitExpr(node) {
    let bar = indexOf(node, "|")
    if bar < 0 { emit node }
    let kind = substring(node, 0, bar)
    let rest = substring(node, bar + 1, len(node))

    if kind == "NUM"  { emit rest }
    if kind == "STR"  { emit "\"" + _unescFld(rest) + "\"" }
    if kind == "NAME" { emit rest }
    if kind == "BOOL" { emit "\"" + rest + "\"" }
    if kind == "NONE" { emit "\"\"" }

    if kind == "BIN" {
        // rest = "<op>|<llen>|<left><right>"  -- length-prefixed left
        let b1 = indexOf(rest, "|")
        let op = substring(rest, 0, b1)
        let after1 = substring(rest, b1 + 1, len(rest))
        let b2 = indexOf(after1, "|")
        let llen = toInt(substring(after1, 0, b2))
        let body = substring(after1, b2 + 1, len(after1))
        let lf = substring(body, 0, llen)
        let rt = substring(body, llen, len(body))
        // Aliases for ops whose literal form (||/&&) would corrupt the
        // pipe-based AST encoding -- translate back at render time.
        let opOut = op
        if op == "OR"  { opOut = "||" }
        if op == "AND" { opOut = "&&" }
        // `IN` is a Python operator that doesn't map to a Krypton infix
        // op; emit as contains(haystack, needle).
        if op == "IN" {
            emit "contains(" + emitExpr(rt) + ", " + emitExpr(lf) + ")"
        }
        // `not in` is the inverse -- compare against "0" since contains
        // returns "1"/"0" in our truthy-string world.
        if op == "NOTIN" {
            emit "(contains(" + emitExpr(rt) + ", " + emitExpr(lf) + ") == \"0\")"
        }
        // `**` lowers to pow(a, b) -- both args coerced via toInt() so
        // the Krypton pow builtin sees proper ints.
        if op == "POW" {
            emit "pow(toInt(" + emitExpr(lf) + "), toInt(" + emitExpr(rt) + "))"
        }
        emit "(" + emitExpr(lf) + " " + opOut + " " + emitExpr(rt) + ")"
    }

    if kind == "CALL" {
        // rest = "<name>|<n>|<l0>|<a0><l1>|<a1>..."
        let b1 = indexOf(rest, "|")
        let name = substring(rest, 0, b1)
        let aft1 = substring(rest, b1 + 1, len(rest))
        let b2 = indexOf(aft1, "|")
        let n = toInt(substring(aft1, 0, b2))
        let argBody = substring(aft1, b2 + 1, len(aft1))
        // Dotted call lowering -- two shapes:
        //   1. `mod.func(args)`   -> `<mod><func>k(args)`    (mod is a known stdlib module that uses
        //                                                     <module><func>k naming: math/os/sys)
        //   2. `value.method(args)` -> `<method>k(value, args)` (method-call style; matches
        //                                                       string/list-style flat stdlib)
        //
        // The differentiator is whether the LHS of the dot is a known
        // prefix-using module.  When in doubt we default to method-call
        // style since most stdlib modules drop the prefix (string,
        // list functional helpers, etc.).
        let nameOut = name
        let dot = indexOf(name, ".")
        if dot > 0 {
            let modPart = substring(name, 0, dot)
            let fnPart = substring(name, dot + 1, len(name))
            let isPrefixMod = "0"
            if modPart == "math" { isPrefixMod = "1" }
            if modPart == "os"   { isPrefixMod = "1" }
            if modPart == "sys"  { isPrefixMod = "1" }
            if isPrefixMod == "1" {
                nameOut = modPart + fnPart + "k"
            }
            if isPrefixMod == "0" {
                // Method-call form: prepend LHS as first arg, drop prefix.
                nameOut = fnPart + "k"
                let lhsNode = astName(modPart)
                argBody = toStr(len(lhsNode)) + "|" + lhsNode + argBody
                n = n + 1
            }
        }
        // Python builtin remaps: len -> count (works on both strings and
        // comma-list "lists"), range(n) -> range(0, n) (Krypton's range
        // takes start+stop, never just stop).
        if name == "len" { nameOut = "count" }
        if name == "range" && n == 1 {
            // Render: range(0, <arg0>) -- inline since we have one arg.
            let aBar = indexOf(argBody, "|")
            let aLen = toInt(substring(argBody, 0, aBar))
            let arg = substring(argBody, aBar + 1, aBar + 1 + aLen)
            emit "range(0, " + emitExpr(arg) + ")"
        }
        // Multi-arg `print(a, b, c)` lowers to `print(toStr(a) + " " + toStr(b) + " " + toStr(c))`
        // to match Python's space-separated default sep.
        if name == "print" && n > 1 {
            let acc = ""
            let i2 = 0
            let cursor2 = 0
            while i2 < n {
                let aBar = indexOf(substring(argBody, cursor2, len(argBody)), "|")
                let aLen = toInt(substring(argBody, cursor2, cursor2 + aBar))
                let aStart = cursor2 + aBar + 1
                let arg = substring(argBody, aStart, aStart + aLen)
                cursor2 = aStart + aLen
                let argSrc = "toStr(" + emitExpr(arg) + ")"
                if i2 == 0 { acc = argSrc } else { acc = acc + " + \" \" + " + argSrc }
                i2 = i2 + 1
            }
            emit "print(" + acc + ")"
        }
        let out = nameOut + "("
        let i = 0
        let cursor = 0
        while i < n {
            let aBar = indexOf(substring(argBody, cursor, len(argBody)), "|")
            let aLen = toInt(substring(argBody, cursor, cursor + aBar))
            let aStart = cursor + aBar + 1
            let arg = substring(argBody, aStart, aStart + aLen)
            cursor = aStart + aLen
            if i > 0 { out = out + ", " }
            out = out + emitExpr(arg)
            i = i + 1
        }
        emit out + ")"
    }

    if kind == "LIST" {
        // rest = "<n>|<l0>|<e0><l1>|<e1>..."
        // Lower to a comma-string: toStr(e0)+","+toStr(e1)+","+...
        let b1 = indexOf(rest, "|")
        let n = toInt(substring(rest, 0, b1))
        let body = substring(rest, b1 + 1, len(rest))
        if n == 0 { emit "\"\"" }
        let out = ""
        let cursor = 0
        let i = 0
        while i < n {
            let aBar = indexOf(substring(body, cursor, len(body)), "|")
            let aLen = toInt(substring(body, cursor, cursor + aBar))
            let aStart = cursor + aBar + 1
            let arg = substring(body, aStart, aStart + aLen)
            cursor = aStart + aLen
            let argSrc = "toStr(" + emitExpr(arg) + ")"
            if i == 0 { out = argSrc } else { out = out + " + \",\" + " + argSrc }
            i = i + 1
        }
        emit "(" + out + ")"
    }

    if kind == "INDEX" {
        // rest = "<oLen>|<obj><iLen>|<idx>"
        let b1 = indexOf(rest, "|")
        let oLen = toInt(substring(rest, 0, b1))
        let obj = substring(rest, b1 + 1, b1 + 1 + oLen)
        let aft1 = substring(rest, b1 + 1 + oLen, len(rest))
        let b2 = indexOf(aft1, "|")
        let iLen = toInt(substring(aft1, 0, b2))
        let idx = substring(aft1, b2 + 1, b2 + 1 + iLen)
        // For comma-string lists we want split(obj, idx); for plain
        // strings we want a single character.  Use split since lists
        // are the common case; users wanting a char should pass [i:i+1].
        emit "split(" + emitExpr(obj) + ", " + emitExpr(idx) + ")"
    }

    if kind == "SLICE" {
        // rest = "<oLen>|<obj><aLen>|<a><bLen>|<b>"
        let b1 = indexOf(rest, "|")
        let oLen = toInt(substring(rest, 0, b1))
        let obj = substring(rest, b1 + 1, b1 + 1 + oLen)
        let aft1 = substring(rest, b1 + 1 + oLen, len(rest))
        let b2 = indexOf(aft1, "|")
        let aLen = toInt(substring(aft1, 0, b2))
        let a = substring(aft1, b2 + 1, b2 + 1 + aLen)
        let aft2 = substring(aft1, b2 + 1 + aLen, len(aft1))
        let b3 = indexOf(aft2, "|")
        let bLen = toInt(substring(aft2, 0, b3))
        let b = substring(aft2, b3 + 1, b3 + 1 + bLen)
        emit "substring(" + emitExpr(obj) + ", " + emitExpr(a) + ", " + emitExpr(b) + ")"
    }

    // Fallback
    emit rest
}

// _splitTopBar(s, maxFields): split s on top-level "|", returning up to
// maxFields fields as a comma-list.  Top-level means depth 0; we
// increment depth on every `|` AFTER the first NUM|... etc.  This is a
// hack -- the real fix is a proper AST representation.  For MVP it
// works because all our nodes are flat-encoded with structured kids
// recursively encoded the same way; the only ambiguity is when a |
// inside a child collides with a top-level |.  We handle that by
// tracking a depth counter that increases on each known structured
// node-start keyword (BIN, CALL, ASSIGN, EXPRSTMT) and decreases on
// the matching number of child fields consumed.
//
// Simplification for MVP: encode children with a balanced bracket pair
// instead.  Defer the bracket rewrite to v2 (compile.k pre-IR pass);
// for now, the MVP only handles trivial expressions where children
// don't contain further | -- ie literals + names + flat calls.
func _splitTopBar(s, maxFields) {
    let out = sbNew()
    let depth = 0
    let n = len(s)
    let i = 0
    let cur = sbNew()
    let fields = 0
    let first = "1"
    while i < n {
        let c = s[i]
        if c == "|" && depth == 0 && fields < maxFields - 1 {
            if first == "0" { out = sbAppend(out, ",") }
            out = sbAppend(out, sbToString(cur))
            first = "0"
            cur = sbNew()
            fields = fields + 1
        } else {
            cur = sbAppend(cur, c)
        }
        i = i + 1
    }
    if first == "0" { out = sbAppend(out, ",") }
    out = sbAppend(out, sbToString(cur))
    emit sbToString(out)
}

// emitStmt(node, decls, indent) -> pkPair(rendered Krypton source, newDecls)
// `indent` is a string of spaces to prepend (4 per nesting level).
// Returns the full Krypton statement, possibly multi-line for blocks.
func emitStmt(node, decls, indent) {
    let bar = indexOf(node, "|")
    if bar < 0 { emit pkPair("", decls) }
    let kind = substring(node, 0, bar)
    let rest = substring(node, bar + 1, len(node))

    if kind == "ASSIGN" {
        // rest = "<name>|<exprLen>|<expr>"
        let b1 = indexOf(rest, "|")
        let name = substring(rest, 0, b1)
        let after1 = substring(rest, b1 + 1, len(rest))
        let b2 = indexOf(after1, "|")
        let eLen = toInt(substring(after1, 0, b2))
        let expr = substring(after1, b2 + 1, b2 + 1 + eLen)
        let exprSrc = emitExpr(expr)
        if declared(decls, name) == "1" {
            emit pkPair(indent + name + " = " + exprSrc, decls)
        }
        let nd = markDeclared(decls, name)
        emit pkPair(indent + "let " + name + " = " + exprSrc, nd)
    }

    if kind == "EXPRSTMT" {
        emit pkPair(indent + emitExpr(rest), decls)
    }

    if kind == "RETURN" {
        if rest == "" { emit pkPair(indent + "emit \"\"", decls) }
        emit pkPair(indent + "emit " + emitExpr(rest), decls)
    }

    if kind == "PASS" {
        emit pkPair(indent + "// pass", decls)
    }

    if kind == "IMPORT" {
        // `import math` -> `import "k:math"` (assumes stdlib namespace).
        // Renders at module scope; emitProgram routes imports above the
        // just-run block alongside funcs.
        emit pkPair(indent + "import \"k:" + rest + "\"", decls)
    }

    if kind == "DEF" {
        // rest = "<name>|<argsCSV>|<bodyLen>|<body>"
        let b1 = indexOf(rest, "|")
        let name = substring(rest, 0, b1)
        let after1 = substring(rest, b1 + 1, len(rest))
        let b2 = indexOf(after1, "|")
        let argsCSV = substring(after1, 0, b2)
        let after2 = substring(after1, b2 + 1, len(after1))
        let b3 = indexOf(after2, "|")
        let bodyLen = toInt(substring(after2, 0, b3))
        let body = substring(after2, b3 + 1, b3 + 1 + bodyLen)
        // Build Krypton func signature.  Python args become Krypton args 1:1.
        let sig = indent + "func " + name + "(" + argsCSV + ") {"
        // Seed body decls with the function params -- they're already
        // bound at function scope, so assignments to them should reuse
        // the binding instead of re-`let`-ing (which shadows on Krypton
        // and breaks `n = n - 1` style loop counters).
        let bodySrc = emitStmtList(body, argsCSV, indent + "    ")
        let close = indent + "}"
        emit pkPair(sig + "\n" + bodySrc + close, decls)
    }

    if kind == "IF" {
        // rest = "<cLen>|<cond><tLen>|<then><eLen>|<else>"
        let b1 = indexOf(rest, "|")
        let cLen = toInt(substring(rest, 0, b1))
        let cond = substring(rest, b1 + 1, b1 + 1 + cLen)
        let aft1 = substring(rest, b1 + 1 + cLen, len(rest))
        let b2 = indexOf(aft1, "|")
        let tLen = toInt(substring(aft1, 0, b2))
        let thenB = substring(aft1, b2 + 1, b2 + 1 + tLen)
        let aft2 = substring(aft1, b2 + 1 + tLen, len(aft1))
        let b3 = indexOf(aft2, "|")
        let eLen = toInt(substring(aft2, 0, b3))
        let elseB = substring(aft2, b3 + 1, b3 + 1 + eLen)
        let condSrc = emitExpr(cond)
        let thenSrc = emitStmtList(thenB, decls, indent + "    ")
        let head = indent + "if " + condSrc + " {"
        let close = indent + "}"
        // listCount("0|") == 0 -> no else.  Anything else -> emit else block.
        if listCount(elseB) == 0 {
            emit pkPair(head + "\n" + thenSrc + close, decls)
        }
        let elseSrc = emitStmtList(elseB, decls, indent + "    ")
        let elseHead = indent + "} else {"
        emit pkPair(head + "\n" + thenSrc + elseHead + "\n" + elseSrc + close, decls)
    }

    if kind == "WHILE" {
        let b1 = indexOf(rest, "|")
        let cLen = toInt(substring(rest, 0, b1))
        let cond = substring(rest, b1 + 1, b1 + 1 + cLen)
        let aft1 = substring(rest, b1 + 1 + cLen, len(rest))
        let b2 = indexOf(aft1, "|")
        let bLen = toInt(substring(aft1, 0, b2))
        let body = substring(aft1, b2 + 1, b2 + 1 + bLen)
        let condSrc = emitExpr(cond)
        let bodySrc = emitStmtList(body, decls, indent + "    ")
        emit pkPair(indent + "while " + condSrc + " {\n" + bodySrc + indent + "}", decls)
    }

    if kind == "FOR" {
        // rest = "<varName>|<iterLen>|<iter><bodyLen>|<body>"
        let b1 = indexOf(rest, "|")
        let varName = substring(rest, 0, b1)
        let after1 = substring(rest, b1 + 1, len(rest))
        let b2 = indexOf(after1, "|")
        let iLen = toInt(substring(after1, 0, b2))
        let iter = substring(after1, b2 + 1, b2 + 1 + iLen)
        let aft2 = substring(after1, b2 + 1 + iLen, len(after1))
        let b3 = indexOf(aft2, "|")
        let bLen = toInt(substring(aft2, 0, b3))
        let body = substring(aft2, b3 + 1, b3 + 1 + bLen)
        let iterSrc = emitExpr(iter)
        // Seed body decls with the loop var (it's bound by `for in`,
        // not user-let'd).  Don't `let` reassign inside the loop.
        let innerDecls = markDeclared(decls, varName)
        let bodySrc = emitStmtList(body, innerDecls, indent + "    ")
        emit pkPair(indent + "for " + varName + " in " + iterSrc + " {\n" + bodySrc + indent + "}", decls)
    }

    emit pkPair("", decls)
}

// emitStmtList walks a length-prefixed list of statement nodes and
// concatenates each rendered statement (with trailing newline) at the
// given indent.  Decls is local to this list (Python scoping rule:
// inner scopes have their own first-assignment-is-let semantics).
func emitStmtList(list, parentDecls, indent) {
    let n = listCount(list)
    let c = listStart(list)
    let out = sbNew()
    let decls = parentDecls
    let i = 0
    while i < n {
        let g = listGet(list, c)
        c = lgCursor(g)
        let stmt = lgItem(g)
        let r = emitStmt(stmt, decls, indent)
        let s = pkNode(r)
        decls = pkTail(r)
        if s != "" {
            out = sbAppend(out, s)
            out = sbAppend(out, "\n")
        }
        i = i + 1
    }
    emit sbToString(out)
}

func emitProgram(stmts) {
    let out = sbNew()
    out = sbAppend(out, "// generated by compiler/snek.k -- do not edit by hand\n\n")
    // First pass: any DEF emits BEFORE the just-run block so funcs are
    // defined at module scope.  Then a single just-run wraps the rest.
    let n = listCount(stmts)
    let c = listStart(stmts)
    let i = 0
    // Imports + defs hoist to module scope; everything else goes in just-run.
    let imports = sbNew()
    let defs = sbNew()
    let main = sbNew()
    let nImports = 0
    let nDefs = 0
    let nMain = 0
    while i < n {
        let g = listGet(stmts, c)
        c = lgCursor(g)
        let stmt = lgItem(g)
        let bar = indexOf(stmt, "|")
        let kind = substring(stmt, 0, bar)
        if kind == "IMPORT" {
            imports = sbAppend(imports, toStr(len(stmt)) + "|" + stmt)
            nImports = nImports + 1
        }
        if kind == "DEF" {
            defs = sbAppend(defs, toStr(len(stmt)) + "|" + stmt)
            nDefs = nDefs + 1
        }
        if kind != "IMPORT" && kind != "DEF" {
            main = sbAppend(main, toStr(len(stmt)) + "|" + stmt)
            nMain = nMain + 1
        }
        i = i + 1
    }
    let impList = toStr(nImports) + "|" + sbToString(imports)
    let defsList = toStr(nDefs) + "|" + sbToString(defs)
    let mainList = toStr(nMain) + "|" + sbToString(main)
    out = sbAppend(out, emitStmtList(impList, "", ""))
    if nImports > 0 { out = sbAppend(out, "\n") }
    out = sbAppend(out, emitStmtList(defsList, "", ""))
    if nDefs > 0 { out = sbAppend(out, "\n") }
    out = sbAppend(out, "just run {\n")
    out = sbAppend(out, emitStmtList(mainList, "", "    "))
    out = sbAppend(out, "}\n")
    emit sbToString(out)
}


// ──────────────────────────────────────────────────────────────────────
// Driver
// ──────────────────────────────────────────────────────────────────────

just run {
    let argc = argCount()
    if argc < 1 {
        printErr("usage: snek <input.kp> [-o output.k]")
        exit("1")
    }

    let inPath  = arg("0")
    let outPath = ""
    let dumpTokens = "0"
    let i = 1
    while i < argc {
        let a = arg(toStr(i))
        if a == "-o" && i + 1 < argc {
            outPath = arg(toStr(i + 1))
            i = i + 2
            continue
        }
        if a == "--tokens" { dumpTokens = "1" }
        i = i + 1
    }

    let src = readFile(inPath)
    if src == "" {
        printErr("snek: cannot read " + inPath)
        exit("1")
    }

    let tokens = lex(src)
    if dumpTokens == "1" {
        let nt = lineCount(tokens)
        let ti = 0
        while ti < nt {
            print(getLine(tokens, ti))
            ti = ti + 1
        }
        exit("0")
    }
    let stmts = parseProgram(tokens)
    let krSrc = emitProgram(stmts)

    if outPath == "" {
        print(krSrc)
    } else {
        writeFile(outPath, krSrc)
    }
}
