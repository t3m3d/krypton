// Sanity check buf.k parses + basic ops work.
import "buf.k"

just run {
    let b = bufNewEmpty()
    b = bufInsertChar(b, "h")
    b = bufInsertChar(b, "i")
    b = bufInsertNewline(b)
    b = bufInsertChar(b, "x")
    kp("text=[" + envGet(b, "text") + "]")
    kp("row=" + envGet(b, "row") + " col=" + envGet(b, "col") + " lines=" + bufNumLines(b))

    b = bufBackspace(b)
    kp("after bs: text=[" + envGet(b, "text") + "] row=" + envGet(b, "row") + " col=" + envGet(b, "col"))

    b = bufUndo(b)
    kp("undo: text=[" + envGet(b, "text") + "]")
    b = bufUndo(b)
    kp("undo2: text=[" + envGet(b, "text") + "]")
    b = bufRedo(b)
    kp("redo: text=[" + envGet(b, "text") + "]")
}
