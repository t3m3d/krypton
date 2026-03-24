go eval {

    func eval(ast) {

        if startsWith(ast, "(num ") {
            let n = substring(ast, 5, len(ast) - 1);
            emit toInt(n);
        }

        if startsWith(ast, "(add ") {
            let a = extract(ast, 5);
            let b = extract(ast, findSecond(ast));
            emit eval(a) + eval(b);
        }

        if startsWith(ast, "(sub ") {
            let a = extract(ast, 5);
            let b = extract(ast, findSecond(ast));
            emit eval(a) - eval(b);
        }

        if startsWith(ast, "(mul ") {
            let a = extract(ast, 5);
            let b = extract(ast, findSecond(ast));
            emit eval(a) * eval(b);
        }

        if startsWith(ast, "(div ") {
            let a = extract(ast, 5);
            let b = extract(ast, findSecond(ast));
            emit eval(a) / eval(b);
        }

            // Comparison operations
            if startsWith(ast, "(eq ") {
                let a = extract(ast, 4);
                let b = extract(ast, findSecond(ast));
                emit eval(a) == eval(b);
            }
            if startsWith(ast, "(neq ") {
                let a = extract(ast, 5);
                let b = extract(ast, findSecond(ast));
                emit eval(a) != eval(b);
            }
            if startsWith(ast, "(lt ") {
                let a = extract(ast, 4);
                let b = extract(ast, findSecond(ast));
                emit eval(a) < eval(b);
            }
            if startsWith(ast, "(gt ") {
                let a = extract(ast, 4);
                let b = extract(ast, findSecond(ast));
                emit eval(a) > eval(b);
            }
            if startsWith(ast, "(le ") {
                let a = extract(ast, 4);
                let b = extract(ast, findSecond(ast));
                emit eval(a) <= eval(b);
            }
            if startsWith(ast, "(ge ") {
                let a = extract(ast, 4);
                let b = extract(ast, findSecond(ast));
                emit eval(a) >= eval(b);
            }

            // Logical operations
            if startsWith(ast, "(and ") {
                let a = extract(ast, 5);
                let b = extract(ast, findSecond(ast));
                emit eval(a) && eval(b);
            }
            if startsWith(ast, "(or ") {
                let a = extract(ast, 4);
                let b = extract(ast, findSecond(ast));
                emit eval(a) || eval(b);
            }
            if startsWith(ast, "(not ") {
                let a = extract(ast, 5);
                emit !eval(a);
            }

            // Fallback: emit error or default value
            emit 0; // Could be improved to emit an error message
    }
}