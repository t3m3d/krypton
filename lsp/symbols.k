// lsp/symbols.k — DocumentSymbol producer.
//
// Walks the token stream from lex.k and emits a JSON array of LSP
// DocumentSymbol objects, one per top-level declaration. We catch:
//   - func / fn / callback   → SymbolKind.Function (12)
//   - struct                 → SymbolKind.Struct   (23)
//   - module                 → SymbolKind.Module   (2)
//   - const / let (top-level only) → SymbolKind.Variable (13)
//
// Range vs selectionRange:
//   - selectionRange covers just the identifier
//   - range spans from the keyword to the end of the identifier (we
//     don't track block extents — would require matching the body's
//     RBRACE which isn't free here)

module symbols

func smKindFunc()    { emit "12" }
func smKindStruct()  { emit "23" }
func smKindModule()  { emit "2" }
func smKindVar()     { emit "13" }

// Build one DocumentSymbol JSON fragment.
func smDocSymbol(name, kind, line, col, nameLen) {
    let r = jeRange(line, col, line, col + nameLen)
    let sel = jeRange(line, col, line, col + nameLen)
    emit jeObj4("name", jeStr(name),
                "kind", jeRaw(kind),
                "range", r,
                "selectionRange", sel)
}

// Walk tokens, return TAB-separated DocumentSymbol JSON fragments.
func collectSymbols(toks) {
    let nLines = lineCount(toks)
    let parts = ""
    let i = 0
    let depth = 0       // brace depth — only emit at depth 0 for top-level

    while i < nLines {
        let row = getLine(toks, i)
        if len(row) == 0 { i += 1  continue }
        let typ = lxType(row)
        let val = lxVal(row)

        if typ == "LBRACE" { depth += 1 }
        if typ == "RBRACE" { depth -= 1 }

        // We look for keyword followed by ID. Only consider depth==0 so
        // we don't catch local lets / nested types.
        if depth == 0 && typ == "KW" {
            let isFn      = (val == "func" || val == "fn" || val == "callback")
            let isStruct  = (val == "struct")
            let isModule  = (val == "module")
            let isVar     = (val == "const" || val == "let")

            if isFn || isStruct || isModule || isVar {
                if i + 1 < nLines {
                    let nxt = getLine(toks, i + 1)
                    if lxType(nxt) == "ID" {
                        let name = lxVal(nxt)
                        let nLn  = lxLine(nxt)
                        let nCol = lxCol(nxt)
                        let kind = smKindVar()
                        if isFn     { kind = smKindFunc() }
                        if isStruct { kind = smKindStruct() }
                        if isModule { kind = smKindModule() }
                        let frag = smDocSymbol(name, kind, nLn, nCol, len(name))
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

// Build the full LSP response array (or "[]" if no symbols).
func documentSymbolJson(toks) {
    let parts = collectSymbols(toks)
    emit jeArrFrom(parts)
}
