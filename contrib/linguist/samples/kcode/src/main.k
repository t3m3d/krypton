// kcode — krypton-lang's terminal IDE.
//
// Usage:  kcode [path]
//
// All work lives in editor.k::kcodeMain. The body of `just run` here is
// intentionally a single statement: kcc 1.8.0 segfaults on 2+ `let`
// statements in the entry block when term/buf/tree/editor are all
// imported. Punting through a function wrapper sidesteps that bug.

import "term.k"
import "buf.k"
import "editor.k"

just run {
    kcodeMain()
}
