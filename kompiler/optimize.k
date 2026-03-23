// optimize.k — Krypton IR Optimizer
// Reads .kir from a file, applies optimization passes, writes to stdout
// Usage: kcc_v095 kompiler/optimize.k source.kir > optimized.kir

// ── IR Instruction Helpers ────────────────────────────────────────

func irGetOp(line) {
    // Get opcode from instruction line (first word)
    let i = 0
    while i < len(line) && line[i] != " " {
        i += 1
    }
    emit substring(line, 0, i)
}

func irGetArg1(line) {
    // Get first argument after opcode
    let i = 0
    while i < len(line) && line[i] != " " { i += 1 }
    if i >= len(line) { emit "" }
    i += 1
    let start = i
    while i < len(line) && line[i] != " " { i += 1 }
    emit substring(line, start, i)
}

func irGetArg2(line) {
    // Get second argument
    let i = 0
    let spaces = 0
    while i < len(line) {
        if line[i] == " " {
            spaces += 1
            if spaces == 2 {
                let start = i + 1
                let j = start
                while j < len(line) { j += 1 }
                emit substring(line, start, j)
            }
        }
        i += 1
    }
    emit ""
}

func irIsNumeric(s) {
    if len(s) == 0 { emit 0 }
    let i = 0
    if s[0] == "-" { i = 1 }
    if i >= len(s) { emit 0 }
    while i < len(s) {
        if s[i] < "0" || s[i] > "9" { emit 0 }
        i += 1
    }
    emit 1
}

// ── Pass 1: Dead Code Elimination ────────────────────────────────
// Remove instructions after RETURN/JUMP until next LABEL/END

func passDeadCode(ir) {
    let lines = ir
    let count = lineCount(lines)
    let out = ""
    let dead = 0
    let i = 0
    while i < count {
        let line = getLine(lines, i)
        let op = irGetOp(line)
        // Reset dead flag at labels and END
        if op == "LABEL" || op == "END" || op == "FUNC" {
            dead = 0
        }
        if dead == 0 {
            if len(out) > 0 { out = out + "\n" }
            out = out + line
        }
        // Mark dead after unconditional jumps and returns
        if op == "RETURN" || op == "JUMP" {
            dead = 1
        }
        i += 1
    }
    emit out
}

// ── Pass 2: Constant Folding ──────────────────────────────────────
// PUSH a / PUSH b / ADD -> PUSH (a+b)  (for numeric literals)

func passFold(ir) {
    let lines = ir
    let count = lineCount(lines)
    let out = ""
    let i = 0
    while i < count {
        let line = getLine(lines, i)
        let op = irGetOp(line)
        // Look ahead for PUSH / PUSH / arithmetic
        if op == "PUSH" && i + 2 < count {
            let a = irGetArg1(line)
            let next = getLine(lines, i + 1)
            let nextOp = irGetOp(next)
            if nextOp == "PUSH" {
                let b = irGetArg1(next)
                let arith = getLine(lines, i + 2)
                let arithOp = irGetOp(arith)
                if irIsNumeric(a) && irIsNumeric(b) {
                    let av = toInt(a)
                    let bv = toInt(b)
                    let folded = ""
                    if arithOp == "ADD" { folded = av + bv + "" }
                    if arithOp == "SUB" { folded = av - bv + "" }
                    if arithOp == "MUL" { folded = av * bv + "" }
                    if arithOp == "DIV" && bv != 0 { folded = av / bv + "" }
                    if len(folded) > 0 {
                        if len(out) > 0 { out = out + "\n" }
                        out = out + "PUSH " + folded
                        i = i + 3
                        // don't add line, skip to next
                    } else {
                        if len(out) > 0 { out = out + "\n" }
                        out = out + line
                        i += 1
                    }
                } else {
                    if len(out) > 0 { out = out + "\n" }
                    out = out + line
                    i += 1
                }
            } else {
                if len(out) > 0 { out = out + "\n" }
                out = out + line
                i += 1
            }
        } else {
            if len(out) > 0 { out = out + "\n" }
            out = out + line
            i += 1
        }
    }
    emit out
}

// ── Pass 3: Strength Reduction ────────────────────────────────────
// Remove identity operations: x + 0, x * 1, x - 0

func passStrength(ir) {
    let lines = ir
    let count = lineCount(lines)
    let out = ""
    let i = 0
    while i < count {
        let line = getLine(lines, i)
        let op = irGetOp(line)
        let skip = 0
        if op == "PUSH" && i + 1 < count {
            let val = irGetArg1(line)
            let nextLine = getLine(lines, i + 1)
            let nextOp = irGetOp(nextLine)
            // x + 0 -> x  (PUSH 0 / ADD)
            if val == "0" && nextOp == "ADD" { skip = 1 }
            // x * 1 -> x  (PUSH 1 / MUL)
            if val == "1" && nextOp == "MUL" { skip = 1 }
            // x - 0 -> x  (PUSH 0 / SUB)
            if val == "0" && nextOp == "SUB" { skip = 1 }
        }
        if skip {
            // skip both PUSH and the op
            i = i + 2
        } else {
            if len(out) > 0 { out = out + "\n" }
            out = out + line
            i += 1
        }
    }
    emit out
}

// ── Pass 4: STORE/LOAD Elimination ───────────────────────────────
// STORE x / LOAD x -> STORE x / DUP  (keep value on stack)
// Actually: remove redundant LOAD immediately after STORE of same var

func passStoreLoad(ir) {
    let lines = ir
    let count = lineCount(lines)
    let out = ""
    let i = 0
    while i < count {
        let line = getLine(lines, i)
        let op = irGetOp(line)
        if op == "STORE" && i + 1 < count {
            let varName = irGetArg1(line)
            let nextLine = getLine(lines, i + 1)
            let nextOp = irGetOp(nextLine)
            let nextVar = irGetArg1(nextLine)
            // STORE x followed immediately by LOAD x -> STORE x (value stays)
            if nextOp == "LOAD" && nextVar == varName {
                // emit STORE, skip the LOAD
                if len(out) > 0 { out = out + "\n" }
                out = out + line
                i = i + 2
            } else {
                if len(out) > 0 { out = out + "\n" }
                out = out + line
                i += 1
            }
        } else {
            if len(out) > 0 { out = out + "\n" }
            out = out + line
            i += 1
        }
    }
    emit out
}

// ── Pass 5: Empty Block Elimination ──────────────────────────────
// Remove LABEL x / JUMP x patterns (jump to next label)

func passEmptyJump(ir) {
    let lines = ir
    let count = lineCount(lines)
    let out = ""
    let i = 0
    while i < count {
        let line = getLine(lines, i)
        let op = irGetOp(line)
        if op == "JUMP" && i + 1 < count {
            let target = irGetArg1(line)
            let nextLine = getLine(lines, i + 1)
            let nextOp = irGetOp(nextLine)
            let nextLabel = irGetArg1(nextLine)
            // JUMP x / LABEL x -> just LABEL x
            if nextOp == "LABEL" && nextLabel == target {
                i += 1
            } else {
                if len(out) > 0 { out = out + "\n" }
                out = out + line
                i += 1
            }
        } else {
            if len(out) > 0 { out = out + "\n" }
            out = out + line
            i += 1
        }
    }
    emit out
}

// ── Pass 6: Unused LOCAL Removal ─────────────────────────────────
// Remove LOCAL declarations for variables never STOREd or LOADed

func passUnusedLocals(ir) {
    // First pass: collect all LOADs and STOREs
    let lines = ir
    let count = lineCount(lines)
    let used = ""
    let i = 0
    while i < count {
        let line = getLine(lines, i)
        let op = irGetOp(line)
        if op == "LOAD" || op == "STORE" {
            let varName = irGetArg1(line)
            if !contains(used, "," + varName + ",") {
                used = used + "," + varName + ","
            }
        }
        i += 1
    }
    // Second pass: emit everything except unused LOCALs
    let out = ""
    i = 0
    while i < count {
        let line = getLine(lines, i)
        let op = irGetOp(line)
        let keep = 1
        if op == "LOCAL" {
            let varName = irGetArg1(line)
            if !contains(used, "," + varName + ",") {
                keep = 0
            }
        }
        if keep {
            if len(out) > 0 { out = out + "\n" }
            out = out + line
        }
        i += 1
    }
    emit out
}

// ── Optimizer Pipeline ────────────────────────────────────────────

func optimize(ir) {
    // Run passes multiple times for convergence (folding enables more dead code etc)
    let result = ir
    let pass = 0
    while pass < 3 {
        result = passDeadCode(result)
        result = passFold(result)
        result = passStrength(result)
        result = passStoreLoad(result)
        result = passEmptyJump(result)
        pass += 1
    }
    result = passUnusedLocals(result)
    emit result
}

// ── Stats Reporter ────────────────────────────────────────────────

func countInstructions(ir) {
    let count = lineCount(ir)
    let real = 0
    let i = 0
    while i < count {
        let line = getLine(ir, i)
        if len(line) > 0 {
            let first = line[0]
            if first != ";" && first != " " {
                real += 1
            }
        }
        i += 1
    }
    emit real + ""
}

// ── Entry Point ───────────────────────────────────────────────────

just run {
    let file = arg(0)
    let ir = readFile(file)

    if len(ir) == 0 {
        printErr("optimize: cannot read file: " + file)
        emit 1
    }

    let before = countInstructions(ir)
    let optimized = optimize(ir)
    let after = countInstructions(optimized)

    // Print stats to stderr
    printErr("; optimizer: " + before + " -> " + after + " instructions (" + (toInt(before) - toInt(after)) + " removed)")

    print(optimized)
}
