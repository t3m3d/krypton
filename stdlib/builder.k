// Builder pattern utilities for Krypton
// String building helpers for generating output

go builder {

    // Create a new builder context (just a wrapper around sbNew)
    func builderNew() {
        emit sbNew()
    }

    // Append text to builder
    func builderAdd(b, text) {
        emit sbAppend(b, text)
    }

    // Append text with newline
    func builderLine(b, text) {
        let b2 = sbAppend(b, text)
        emit sbAppend(b2, "\n")
    }

    // Append indented line
    func builderIndentLine(b, indent, text) {
        let b2 = b
        let i = 0
        while i < indent {
            b2 = sbAppend(b2, "    ")
            i += 1
        }
        b2 = sbAppend(b2, text)
        emit sbAppend(b2, "\n")
    }

    // Append blank line
    func builderBlank(b) {
        emit sbAppend(b, "\n")
    }

    // Append a comment line
    func builderComment(b, text) {
        let b2 = sbAppend(b, "// ")
        b2 = sbAppend(b2, text)
        emit sbAppend(b2, "\n")
    }

    // Finalize builder to string
    func builderFinish(b) {
        emit sbToString(b)
    }

    // Build a repeated line
    func builderRepeatLine(b, text, n) {
        let b2 = b
        let i = 0
        while i < n {
            b2 = sbAppend(b2, text)
            b2 = sbAppend(b2, "\n")
            i += 1
        }
        emit b2
    }

    // Build a header block
    func builderHeader(b, title) {
        let border = ""
        let i = 0
        while i < len(title) + 6 {
            border = border + "="
            i += 1
        }
        let b2 = sbAppend(b, border + "\n")
        b2 = sbAppend(b2, "   " + title + "\n")
        emit sbAppend(b2, border + "\n")
    }
}
