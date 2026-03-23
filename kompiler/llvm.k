// llvm.k — Krypton IR to LLVM IR backend v3
// Uses alloca-based stack (always SSA-safe across basic blocks)
// Usage: _llvmbe.exe source_opt.kir > source.ll
//        clang source.ll krypton_runtime.o -o program.exe

// ── IR helpers ───────────────────────────────────────────────────
func irGetOp(line) {
    let t = trim(line)
    let i = 0
    while i < len(t) && t[i] != " " { i += 1 }
    emit substring(t, 0, i)
}

func irGetArg1(line) {
    let t = trim(line)
    let i = 0
    while i < len(t) && t[i] != " " { i += 1 }
    if i >= len(t) { emit "" }
    i += 1
    let start = i
    while i < len(t) && t[i] != " " { i += 1 }
    emit trim(substring(t, start, i))
}

func irGetArg2(line) {
    let t = trim(line)
    let i = 0
    let sp = 0
    while i < len(t) {
        if t[i] == " " {
            sp += 1
            if sp == 2 {
                emit trim(substring(t, i + 1, len(t)))
            }
        }
        i += 1
    }
    emit ""
}

func irGetRest(line) {
    let t = trim(line)
    let i = 0
    while i < len(t) && t[i] != " " { i += 1 }
    if i >= len(t) { emit "" }
    emit trim(substring(t, i + 1, len(t)))
}

func llvmSanitize(s) {
    let result = ""
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == "\\" { result = result + "\\\\" }
        else if c == "\"" { result = result + "\\22" }
        else if c == "\n" { result = result + "\\0A" }
        else if c == "\t" { result = result + "\\09" }
        else { result = result + c }
        i += 1
    }
    emit result
}

// ── Pass 1: emit per-function string/numeric globals ──────────────
func emitGlobalsForFunc(fname, body) {
    let out = ""
    let lines = body
    let count = lineCount(lines)
    let pushIdx = 0
    let i = 0
    while i < count {
        let line = getLine(lines, i)
        let op = irGetOp(line)
        if op == "PUSH" {
            let val = trim(irGetRest(line))
            if startsWith(val, "\"") {
                let inner = substring(val, 1, len(val) - 1)
                let slen = len(inner) + 1
                let san = llvmSanitize(inner)
                out = out + "@kp_" + fname + "_" + pushIdx + " = private unnamed_addr constant [" + slen + " x i8] c\"" + san + "\\00\"\n"
            } else {
                let slen = len(val) + 1
                out = out + "@kp_" + fname + "_" + pushIdx + " = private unnamed_addr constant [" + slen + " x i8] c\"" + val + "\\00\"\n"
            }
            pushIdx += 1
        }
        i += 1
    }
    emit out
}

// ── Pass 2: emit function body using alloca stack slots ───────────
func emitFunc(fname, argc, body) {
    let paramCount = toInt(argc)
    let out = ""

    // Function header
    out = out + "define ptr @" + fname + "("
    let pi = 0
    while pi < paramCount {
        if pi > 0 { out = out + ", " }
        out = out + "ptr %p" + pi
        pi += 1
    }
    out = out + ") {\nentry:\n"

    // Pre-allocate 32 stack slots
    let si = 0
    while si < 32 {
        out = out + "  %stk" + si + " = alloca ptr\n"
        si += 1
    }
    out = out + "  %_empty_slot = alloca ptr\n"

    // Process instructions
    let lines = body
    let count = lineCount(lines)
    let stkDepth = 0   // stack depth (points to NEXT free slot)
    let reg = 0        // temp register counter
    let paramIdx = 0
    let gidx = 0       // push constant index
    let lastWasTerm = 0
    let i = 0

    while i < count {
        let line = getLine(lines, i)
        let op = irGetOp(line)

        if op == "PARAM" {
            let name = irGetArg1(line)
            out = out + "  %" + name + ".a = alloca ptr\n"
            out = out + "  store ptr %p" + paramIdx + ", ptr %" + name + ".a\n"
            paramIdx += 1
        }

        if op == "LOCAL" {
            let name = irGetArg1(line)
            out = out + "  %" + name + ".a = alloca ptr\n"
            let empReg = "%emp" + reg
            reg += 1
            out = out + "  " + empReg + " = getelementptr inbounds [1 x i8], ptr @.empty, i32 0, i32 0\n"
            out = out + "  store ptr " + empReg + ", ptr %" + name + ".a\n"
        }

        if op == "PUSH" {
            let val = trim(irGetRest(line))
            let r = "%tmp" + reg
            reg += 1
            if startsWith(val, "\"") {
                let inner = substring(val, 1, len(val) - 1)
                let slen = len(inner) + 1
                out = out + "  " + r + " = getelementptr inbounds [" + slen + " x i8], ptr @kp_" + fname + "_" + gidx + ", i32 0, i32 0\n"
            } else {
                let slen = len(val) + 1
                out = out + "  " + r + " = getelementptr inbounds [" + slen + " x i8], ptr @kp_" + fname + "_" + gidx + ", i32 0, i32 0\n"
            }
            gidx += 1
            out = out + "  store ptr " + r + ", ptr %stk" + stkDepth + "\n"
            stkDepth += 1
        }

        if op == "LOAD" {
            let name = irGetArg1(line)
            let r = "%tmp" + reg
            reg += 1
            out = out + "  " + r + " = load ptr, ptr %" + name + ".a\n"
            out = out + "  store ptr " + r + ", ptr %stk" + stkDepth + "\n"
            stkDepth += 1
        }

        if op == "STORE" {
            let name = irGetArg1(line)
            stkDepth -= 1
            let r = "%tmp" + reg
            reg += 1
            out = out + "  " + r + " = load ptr, ptr %stk" + stkDepth + "\n"
            out = out + "  store ptr " + r + ", ptr %" + name + ".a\n"
        }

        // Binary ops: pop b, pop a, compute, push result
        if op == "ADD" || op == "SUB" || op == "MUL" || op == "DIV" || op == "MOD" || op == "CAT" {
            stkDepth -= 1
            let rb = "%tmp" + reg
            reg += 1
            out = out + "  " + rb + " = load ptr, ptr %stk" + stkDepth + "\n"
            stkDepth -= 1
            let ra = "%tmp" + reg
            reg += 1
            out = out + "  " + ra + " = load ptr, ptr %stk" + stkDepth + "\n"
            let fn2 = "kr_plus"
            if op == "SUB" { fn2 = "kr_sub" }
            if op == "MUL" { fn2 = "kr_mul" }
            if op == "DIV" { fn2 = "kr_div" }
            if op == "MOD" { fn2 = "kr_mod" }
            if op == "CAT" { fn2 = "kr_cat" }
            let r = "%tmp" + reg
            reg += 1
            out = out + "  " + r + " = call ptr @" + fn2 + "(ptr " + ra + ", ptr " + rb + ")\n"
            out = out + "  store ptr " + r + ", ptr %stk" + stkDepth + "\n"
            stkDepth += 1
        }

        if op == "NEG" {
            stkDepth -= 1
            let ra = "%tmp" + reg
            reg += 1
            out = out + "  " + ra + " = load ptr, ptr %stk" + stkDepth + "\n"
            let r = "%tmp" + reg
            reg += 1
            out = out + "  " + r + " = call ptr @kr_neg(ptr " + ra + ")\n"
            out = out + "  store ptr " + r + ", ptr %stk" + stkDepth + "\n"
            stkDepth += 1
        }

        if op == "NOT" {
            stkDepth -= 1
            let ra = "%tmp" + reg
            reg += 1
            out = out + "  " + ra + " = load ptr, ptr %stk" + stkDepth + "\n"
            let r = "%tmp" + reg
            reg += 1
            out = out + "  " + r + " = call ptr @kr_not(ptr " + ra + ")\n"
            out = out + "  store ptr " + r + ", ptr %stk" + stkDepth + "\n"
            stkDepth += 1
        }

        if op == "EQ" || op == "NEQ" || op == "LT" || op == "GT" || op == "LTE" || op == "GTE" {
            stkDepth -= 1
            let rb = "%tmp" + reg
            reg += 1
            out = out + "  " + rb + " = load ptr, ptr %stk" + stkDepth + "\n"
            stkDepth -= 1
            let ra = "%tmp" + reg
            reg += 1
            out = out + "  " + ra + " = load ptr, ptr %stk" + stkDepth + "\n"
            let fn2 = "kr_eq"
            if op == "NEQ" { fn2 = "kr_neq" }
            if op == "LT"  { fn2 = "kr_lt" }
            if op == "GT"  { fn2 = "kr_gt" }
            if op == "LTE" { fn2 = "kr_lte" }
            if op == "GTE" { fn2 = "kr_gte" }
            let r = "%tmp" + reg
            reg += 1
            out = out + "  " + r + " = call ptr @" + fn2 + "(ptr " + ra + ", ptr " + rb + ")\n"
            out = out + "  store ptr " + r + ", ptr %stk" + stkDepth + "\n"
            stkDepth += 1
        }

        if op == "CALL" || op == "BUILTIN" {
            let fname2 = irGetArg1(line)
            let argc2 = toInt(irGetArg2(line))
            // Pop args in reverse (LIFO), so first arg popped is last arg
            // Build args: arg0 is deepest, argN-1 is top
            let argTemps = ""
            let ai = argc2 - 1
            while ai >= 0 {
                stkDepth -= 1
                let r = "%tmp" + reg
                reg += 1
                out = out + "  " + r + " = load ptr, ptr %stk" + stkDepth + "\n"
                if ai == 0 { argTemps = r + "," + argTemps }
                else { argTemps = r + "," + argTemps }
                ai -= 1
            }
            // argTemps is now "arg0,arg1,...,argN-1,"
            let result = "%tmp" + reg
            reg += 1
            let callArgs = ""
            let bi = 0
            while bi < argc2 {
                let argR = split(argTemps, bi)
                if bi > 0 { callArgs = callArgs + ", " }
                callArgs = callArgs + "ptr " + argR
                bi += 1
            }
            // map builtin short names to kr_ runtime names
            let rfname = fname2
            if fname2 == "kp"         { rfname = "kr_kp" }
            if fname2 == "print"      { rfname = "kr_print" }
            if fname2 == "len"        { rfname = "kr_len" }
            if fname2 == "toInt"      { rfname = "kr_toInt" }
            if fname2 == "contains"   { rfname = "kr_contains" }
            if fname2 == "startsWith" { rfname = "kr_startsWith" }
            if fname2 == "fadd"       { rfname = "kr_fadd" }
            if fname2 == "fsub"       { rfname = "kr_fsub" }
            if fname2 == "fmul"       { rfname = "kr_fmul" }
            if fname2 == "fdiv"       { rfname = "kr_fdiv" }
            if fname2 == "fsqrt"      { rfname = "kr_fsqrt" }
            out = out + "  " + result + " = call ptr @" + rfname + "(" + callArgs + ")\n"
            out = out + "  store ptr " + result + ", ptr %stk" + stkDepth + "\n"
            stkDepth += 1
        }

        if op == "POP" {
            stkDepth -= 1
        }

        if op == "RETURN" {
            stkDepth -= 1
            let r = "%tmp" + reg
            reg += 1
            out = out + "  " + r + " = load ptr, ptr %stk" + stkDepth + "\n"
            out = out + "  ret ptr " + r + "\n"
            lastWasTerm = 1
        }

        if op == "LABEL" {
            let lname = irGetArg1(line)
            // emit implicit fallthrough br if last instruction was not a terminator
            if lastWasTerm == 0 {
                out = out + "  br label %" + lname + "\n"
            }
            out = out + lname + ":\n"
            lastWasTerm = 0
        }

        if op == "JUMP" {
            let target = irGetArg1(line)
            out = out + "  br label %" + target + "\n"
            lastWasTerm = 1
        }

        if op == "JUMPIF" || op == "JUMPIFNOT" {
            let target = irGetArg1(line)
            stkDepth -= 1
            let rv = "%tmp" + reg
            reg += 1
            out = out + "  " + rv + " = load ptr, ptr %stk" + stkDepth + "\n"
            let cond = "%cond" + reg
            reg += 1
            let ft = "_ft" + reg
            reg += 1
            out = out + "  " + cond + " = call i1 @kr_truthy(ptr " + rv + ")\n"
            if op == "JUMPIF" {
                out = out + "  br i1 " + cond + ", label %" + target + ", label %" + ft + "\n"
            } else {
                out = out + "  br i1 " + cond + ", label %" + ft + ", label %" + target + "\n"
            }
            out = out + ft + ":\n"
            lastWasTerm = 0
        }

        if op == "END" {
            let empR = "%tmp" + reg
            reg += 1
            out = out + "  " + empR + " = getelementptr inbounds [1 x i8], ptr @.empty, i32 0, i32 0\n"
            out = out + "  ret ptr " + empR + "\n"
            out = out + "}\n\n"
        }

        i += 1
    }

    emit out
}

// ── Main ──────────────────────────────────────────────────────────
just run {
    let file = arg(0)
    let ir = readFile(file)
    if len(ir) == 0 {
        printErr("llvm: cannot read: " + file)
        emit 1
    }

    // Header
    kp("; Krypton LLVM IR v3 — opaque pointers")
            kp("")
    kp("declare ptr @kr_plus(ptr, ptr)")
    kp("declare ptr @kr_sub(ptr, ptr)")
    kp("declare ptr @kr_mul(ptr, ptr)")
    kp("declare ptr @kr_div(ptr, ptr)")
    kp("declare ptr @kr_mod(ptr, ptr)")
    kp("declare ptr @kr_neg(ptr)")
    kp("declare ptr @kr_not(ptr)")
    kp("declare ptr @kr_cat(ptr, ptr)")
    kp("declare ptr @kr_eq(ptr, ptr)")
    kp("declare ptr @kr_neq(ptr, ptr)")
    kp("declare ptr @kr_lt(ptr, ptr)")
    kp("declare ptr @kr_gt(ptr, ptr)")
    kp("declare ptr @kr_lte(ptr, ptr)")
    kp("declare ptr @kr_gte(ptr, ptr)")
    kp("declare i1  @kr_truthy(ptr)")
    kp("declare ptr @kr_kp(ptr)")
    kp("declare ptr @kr_print(ptr)")
    kp("declare ptr @kr_len(ptr)")
    kp("declare ptr @kr_toInt(ptr)")
    kp("declare ptr @kr_contains(ptr, ptr)")
    kp("declare ptr @kr_startsWith(ptr, ptr)")
    kp("declare ptr @kr_fadd(ptr, ptr)")
    kp("declare ptr @kr_fsub(ptr, ptr)")
    kp("declare ptr @kr_fmul(ptr, ptr)")
    kp("declare ptr @kr_fdiv(ptr, ptr)")
    kp("declare ptr @kr_fsqrt(ptr)")
    kp("")
    kp("@.empty = private unnamed_addr constant [1 x i8] zeroinitializer")
    kp("")

    // Collect clean lines (skip comments and C directives)
    let allLines = ir
    let total = lineCount(allLines)
    let clean = ""
    let ci = 0
    while ci < total {
        let ln = getLine(allLines, ci)
        let tln = trim(ln)
        if len(tln) > 0 {
            if tln[0] != ";" && tln[0] != "#" && tln[0] != "/" {
                if len(clean) > 0 { clean = clean + "\n" }
                clean = clean + tln
            }
        }
        ci += 1
    }

    // Process each function
    let blines = clean
    let bcount = lineCount(blines)
    let i = 0
    while i < bcount {
        let line = getLine(blines, i)
        let op = irGetOp(line)
        if op == "FUNC" {
            let fname = irGetArg1(line)
            let argc = irGetArg2(line)
            let body = ""
            i += 1
            while i < bcount {
                let bl = getLine(blines, i)
                if irGetOp(bl) == "END" {
                    if len(body) > 0 { body = body + "\n" }
                    body = body + bl
                    i += 1
                    break
                }
                if len(body) > 0 { body = body + "\n" }
                body = body + bl
                i += 1
            }
            // emit globals then function
            print(emitGlobalsForFunc(fname, body))
            print(emitFunc(fname, argc, body))
        } else {
            i += 1
        }
    }
}
