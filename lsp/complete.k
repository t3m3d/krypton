// lsp/complete.k — Completion list builder.
//
// Returns a JSON array of CompletionItem for the open document.
// Sources, in order:
//   1. Krypton keywords         (CompletionItemKind.Keyword = 14)
//   2. Native builtins          (CompletionItemKind.Function = 3)
//   3. Functions in this buffer (CompletionItemKind.Function = 3)
//
// Position-insensitive for now — we return the same set regardless of
// where the cursor is. Refining for context (e.g. only show types
// after `:` ) is session-3 work.

module complete

func cpKindKeyword()  { emit "14" }
func cpKindFunction() { emit "3" }
func cpKindModule()   { emit "9" }

func cpItem(label, kind, detail) {
    emit jeObj3("label",  jeStr(label),
                "kind",   jeRaw(kind),
                "detail", jeStr(detail))
}

// Hand-curated keyword list. Mirrors lex.k's lxIsKW — both lists must
// be kept in sync. Pipe-separated for cheap iteration.
func cpKeywords() {
    emit "func|fn|let|const|if|else|while|for|in|do|loop|until|break|continue|match|emit|return|try|catch|throw|module|import|export|struct|class|type|callback|jxt|just|go|true|false|null|quantum|qpute|process|measure|prepare"
}

// Hand-curated builtins. Mirrors the regex in compile.k. Pipe-separated.
func cpBuiltins() {
    emit "kp|print|printErr|len|length|count|substring|toInt|toStr|parseInt|split|range|startsWith|endsWith|contains|indexOf|replace|trim|toUpper|toLower|reverse|repeat|padLeft|padRight|pow|abs|min|max|bin|hex|sign|clamp|charCode|fromCharCode|isDigit|isAlpha|isAlphaNum|isTruthy|readFile|writeFile|arg|argCount|getLine|lineCount|exit|tokenize|tokAt|tokVal|tokType|sbNew|sbAppend|sbToString|envNew|envSet|envGet|structNew|setField|getField|hasField|structFields|pairVal|pairPos|pairNew|join|slice|splitBy|sort|unique|fill|zip|keys|values|hasKey|mapGet|mapSet|remove|sumList|minList|maxList|countOf|listIndexOf|every|some|gcAllocated|gcLimit|gcSetLimit|gcCollect|gcReset|gcCheckpoint|gcRestore|gcSlabCount|gcSlabBytes|bufNew|bufStr|bufGetByte|bufGetWord|bufGetDword|bufGetQword|bufSetByte|bufSetDword|bitOr|bitAnd|bitXor|bitNot|shl|shr|str|type|assert"
}

// Append all `WORD` segments from a pipe-list `|w1|w2|w3|` (no leading
// or trailing pipe) as cpItems with the given kind+detail.
func cpAppendPipeList(parts, list, kind, detail) {
    let n = len(list)
    let i = 0
    let start = 0
    while i <= n {
        if i == n || list[i] == "|" {
            if i > start {
                let word = substring(list, start, i)
                let frag = cpItem(word, kind, detail)
                if parts == "" { parts = frag }
                else           { parts = parts + "\t" + frag }
            }
            start = i + 1
        }
        i += 1
    }
    emit parts
}

// Pull function names from the buffer's tokens (anywhere — even nested).
// Returns a TAB-separated CompletionItem list.
func cpBufferFuncs(toks) {
    let parts = ""
    let nLines = lineCount(toks)
    let i = 0
    while i < nLines {
        let row = getLine(toks, i)
        if len(row) > 0 {
            let typ = lxType(row)
            let val = lxVal(row)
            if typ == "KW" && (val == "func" || val == "fn" || val == "callback") {
                if i + 1 < nLines {
                    let nxt = getLine(toks, i + 1)
                    if lxType(nxt) == "ID" {
                        let name = lxVal(nxt)
                        let frag = cpItem(name, cpKindFunction(), "user function")
                        if parts == "" { parts = frag }
                        else           { parts = parts + "\t" + frag }
                    }
                }
            }
        }
        i += 1
    }
    emit parts
}

// Build the full completion array for an open document.
func completionJson(toks) {
    let parts = ""
    parts = cpAppendPipeList(parts, cpKeywords(), cpKindKeyword(),  "keyword")
    parts = cpAppendPipeList(parts, cpBuiltins(), cpKindFunction(), "builtin")
    let bufFuncs = cpBufferFuncs(toks)
    if bufFuncs != "" {
        if parts == "" { parts = bufFuncs }
        else           { parts = parts + "\t" + bufFuncs }
    }
    // Wrap in CompletionList (LSP allows either array or CompletionList).
    let items = jeArrFrom(parts)
    emit jeObj2("isIncomplete", jeRaw("false"), "items", items)
}
