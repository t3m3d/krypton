#include "lowerer.hpp"
#include <stdexcept>
#include <utility>

namespace k {

static std::string literalToString(const ExprPtr& e) {
    switch (e->litKind) {
    case LiteralKind::Int:
        return std::to_string(e->litInt);
    case LiteralKind::Float:
        return std::to_string(e->litFloat);
    case LiteralKind::String:
        return e->litString;
    case LiteralKind::Bool:
        return e->litBool ? "true" : "false";
    }
    throw std::runtime_error("Unknown literal kind in literalToString");
}

std::unordered_map<std::string, LoweredProcess>
Lowerer::lowerModule(const ModuleDecl &module) {
    std::unordered_map<std::string, LoweredProcess> result;

    for (const auto &v : module.decls) {
        if (std::holds_alternative<ProcessDeclPtr>(v)) {
            auto proc = std::get<ProcessDeclPtr>(v);
            if (!proc) continue;

            LoweredProcess lp;
            curClassical = &lp.classical;
            curQuantum   = &lp.quantum;

            lowerProcess(*proc, lp);

            result[proc->name] = std::move(lp);
            curClassical = nullptr;
            curQuantum   = nullptr;
        }
    }

    return result;
}

FunctionIRTable Lowerer::lowerFunctions(const ModuleDecl &module) {
    FunctionIRTable table;

    for (const auto &v : module.decls) {
        if (std::holds_alternative<FnDeclPtr>(v)) {
            auto fn = std::get<FnDeclPtr>(v);
            if (!fn) continue;

            ClassicalIR ir;
            curClassical = &ir;
            curQuantum   = nullptr;

            lowerFunction(*fn, ir);

            table[fn->name] = std::move(ir);
            curClassical = nullptr;
        }
    }

    return table;
}

void Lowerer::lowerFunction(const FnDecl &fn, ClassicalIR &out) {
    out.params.clear();
    for (const auto &p : fn.params) {
        out.params.push_back(p.name);
    }
    curClassical = &out;
    lowerBlock(fn.body);
    out.emit(OpCode::RETURN);
}

void Lowerer::lowerProcess(const ProcessDecl &proc, LoweredProcess & /*out*/) {
    lowerBlock(proc.body);
}

void Lowerer::lowerBlock(const BlockPtr &block) {
    if (!block) return;
    for (const auto &stmt : block->statements) {
        lowerStmt(stmt);
    }
}

void Lowerer::lowerStmt(const StmtPtr &stmt) {
    if (!stmt) return;

    switch (stmt->kind) {
    case StmtKind::Let: {
        lowerExpr(stmt->expr);
        curClassical->emit(OpCode::STORE_VAR, stmt->name);
        break;
    }
    case StmtKind::Emit: {
        // treat emit like a return in processes/functions
        lowerExpr(stmt->expr);
        curClassical->emit(OpCode::RETURN);
        break;
    }
    case StmtKind::Return: {
        lowerExpr(stmt->expr);
        curClassical->emit(OpCode::RETURN);
        break;
    }
    case StmtKind::If: {
        lowerExpr(stmt->condition);
        int jumpFalse = (int)curClassical->instructions.size();
        curClassical->emit(OpCode::JUMP_IF_FALSE, "0");
        lowerBlock(stmt->thenBlock);
        if (stmt->elseBlock) {
            int jumpOver = (int)curClassical->instructions.size();
            curClassical->emit(OpCode::JUMP, "0");
            int elseStart = (int)curClassical->instructions.size();
            curClassical->instructions[jumpFalse].arg = std::to_string(elseStart);
            lowerBlock(stmt->elseBlock);
            int afterElse = (int)curClassical->instructions.size();
            curClassical->instructions[jumpOver].arg = std::to_string(afterElse);
        } else {
            int afterThen = (int)curClassical->instructions.size();
            curClassical->instructions[jumpFalse].arg = std::to_string(afterThen);
        }
        break;
    }
    case StmtKind::Expr: {
        lowerExpr(stmt->expr);
        break;
    }
    case StmtKind::While: {
        // Record loop start
        int loopStart = (int)curClassical->instructions.size();
        // Evaluate condition
        lowerExpr(stmt->condition);
        // Placeholder for JUMP_IF_FALSE (will patch)
        int jumpOut = (int)curClassical->instructions.size();
        curClassical->emit(OpCode::JUMP_IF_FALSE, "0");
        // Lower body
        lowerBlock(stmt->thenBlock);
        // Jump back to loop start
        curClassical->emit(OpCode::JUMP, std::to_string(loopStart));
        // Patch the JUMP_IF_FALSE to jump here
        int loopEnd = (int)curClassical->instructions.size();
        curClassical->instructions[jumpOut].arg = std::to_string(loopEnd);
        // Patch any break jumps (marked with "__break__") to loopEnd
        for (int i = jumpOut; i < loopEnd; i++) {
            if (curClassical->instructions[i].op == OpCode::JUMP &&
                curClassical->instructions[i].arg == "__break__") {
                curClassical->instructions[i].arg = std::to_string(loopEnd);
            }
        }
        break;
    }
    case StmtKind::Break: {
        // Emit a JUMP with special marker; the enclosing while will patch it
        curClassical->emit(OpCode::JUMP, "__break__");
        break;
    }
    case StmtKind::Assign: {
        lowerExpr(stmt->expr);
        curClassical->emit(OpCode::STORE_VAR, stmt->name);
        break;
    }
    }
}

void Lowerer::lowerExpr(const ExprPtr &expr) {
    if (!expr) return;

    switch (expr->kind) {
    case ExprKind::Literal: {
        curClassical->emit(OpCode::LOAD_CONST, literalToString(expr));
        break;
    }
    case ExprKind::Identifier: {
        curClassical->emit(OpCode::LOAD_VAR, expr->identifier);
        break;
    }
    case ExprKind::Binary: {
        lowerBinary(expr);
        break;
    }
    case ExprKind::Unary: {
        lowerUnary(expr);
        break;
    }
    case ExprKind::Call: {
        lowerCall(expr);
        break;
    }
    case ExprKind::Prepare: {
        lowerPrepare(expr);
        break;
    }
    case ExprKind::Measure: {
        lowerMeasure(expr);
        break;
    }
    case ExprKind::Grouping: {
        lowerExpr(expr->inner);
        break;
    }
    case ExprKind::Index: {
        lowerExpr(expr->left);
        lowerExpr(expr->right);
        curClassical->emit(OpCode::INDEX);
        break;
    }
    }
}

void Lowerer::lowerBinary(const ExprPtr &expr) {
    lowerExpr(expr->left);
    lowerExpr(expr->right);

    if (expr->op == "+") {
        curClassical->emit(OpCode::ADD);
    } else if (expr->op == "-") {
        curClassical->emit(OpCode::SUB);
    } else if (expr->op == "*") {
        curClassical->emit(OpCode::MUL);
    } else if (expr->op == "/") {
        curClassical->emit(OpCode::DIV);
    } else if (expr->op == "==") {
        curClassical->emit(OpCode::CMP_EQ);
    } else if (expr->op == "!=") {
        curClassical->emit(OpCode::CMP_NEQ);
    } else if (expr->op == "<") {
        curClassical->emit(OpCode::CMP_LT);
    } else if (expr->op == ">") {
        curClassical->emit(OpCode::CMP_GT);
    } else if (expr->op == "<=") {
        curClassical->emit(OpCode::CMP_LTE);
    } else if (expr->op == ">=") {
        curClassical->emit(OpCode::CMP_GTE);
    } else if (expr->op == "&&") {
        curClassical->emit(OpCode::LOGIC_AND);
    } else if (expr->op == "||") {
        curClassical->emit(OpCode::LOGIC_OR);
    } else {
        throw std::runtime_error("Unsupported binary operator in lowering: " + expr->op);
    }
}

void Lowerer::lowerUnary(const ExprPtr &expr) {
    if (expr->op == "-") {
        curClassical->emit(OpCode::LOAD_CONST, "0");
        lowerExpr(expr->right);
        curClassical->emit(OpCode::SUB);
    } else if (expr->op == "!") {
        lowerExpr(expr->right);
        curClassical->emit(OpCode::LOGIC_NOT);
    } else {
        // unary +, no-op
        lowerExpr(expr->right);
    }
}

void Lowerer::lowerCall(const ExprPtr &expr) {
    if (expr->identifier == "print" || expr->identifier == "kp") {
        for (const auto &arg : expr->args) {
            if (arg->kind == ExprKind::Literal) {
                curClassical->emit(OpCode::PRINT, literalToString(arg));
            } else {
                lowerExpr(arg);
                curClassical->emit(OpCode::PRINT, "");
            }
        }
        return;
    }

    if (expr->identifier == "len") {
        if (expr->args.size() != 1) {
            throw std::runtime_error("len() expects exactly one argument");
        }
        lowerExpr(expr->args[0]);
        curClassical->emit(OpCode::LEN);
        return;
    }

    if (expr->identifier == "substring") {
        if (expr->args.size() != 3) {
            throw std::runtime_error("substring() expects 3 arguments");
        }
        lowerExpr(expr->args[0]);
        lowerExpr(expr->args[1]);
        lowerExpr(expr->args[2]);
        curClassical->emit(OpCode::SUBSTRING);
        return;
    }

    if (expr->identifier == "split") {
        if (expr->args.size() != 2) {
            throw std::runtime_error("split() expects 2 arguments");
        }
        lowerExpr(expr->args[0]);
        lowerExpr(expr->args[1]);
        curClassical->emit(OpCode::SPLIT);
        return;
    }

    if (expr->identifier == "toInt") {
        if (expr->args.size() != 1) {
            throw std::runtime_error("toInt() expects 1 argument");
        }
        lowerExpr(expr->args[0]);
        curClassical->emit(OpCode::TO_INT);
        return;
    }

    if (expr->identifier == "startsWith") {
        if (expr->args.size() != 2) {
            throw std::runtime_error("startsWith() expects 2 arguments");
        }
        lowerExpr(expr->args[0]);
        lowerExpr(expr->args[1]);
        curClassical->emit(OpCode::STARTS_WITH);
        return;
    }

    if (expr->identifier == "count") {
        if (expr->args.size() != 1) {
            throw std::runtime_error("count() expects 1 argument");
        }
        lowerExpr(expr->args[0]);
        curClassical->emit(OpCode::COUNT);
        return;
    }

    if (expr->identifier == "extract") {
        if (expr->args.size() != 2) {
            throw std::runtime_error("extract() expects 2 arguments");
        }
        lowerExpr(expr->args[0]);
        lowerExpr(expr->args[1]);
        curClassical->emit(OpCode::EXTRACT);
        return;
    }

    if (expr->identifier == "findSecond") {
        if (expr->args.size() != 1) {
            throw std::runtime_error("findSecond() expects 1 argument");
        }
        lowerExpr(expr->args[0]);
        curClassical->emit(OpCode::FIND_SECOND);
        return;
    }

    if (expr->identifier == "readFile") {
        if (expr->args.size() != 1) {
            throw std::runtime_error("readFile() expects 1 argument");
        }
        lowerExpr(expr->args[0]);
        curClassical->emit(OpCode::READ_FILE);
        return;
    }

    if (expr->identifier == "arg") {
        if (expr->args.size() != 1) {
            throw std::runtime_error("arg() expects 1 argument");
        }
        lowerExpr(expr->args[0]);
        curClassical->emit(OpCode::ARG);
        return;
    }

    if (expr->identifier == "argCount") {
        curClassical->emit(OpCode::ARG_COUNT);
        return;
    }

    if (expr->identifier == "getLine") {
        if (expr->args.size() != 2) {
            throw std::runtime_error("getLine() expects 2 arguments");
        }
        lowerExpr(expr->args[0]);
        lowerExpr(expr->args[1]);
        curClassical->emit(OpCode::GET_LINE);
        return;
    }

    if (expr->identifier == "lineCount") {
        if (expr->args.size() != 1) {
            throw std::runtime_error("lineCount() expects 1 argument");
        }
        lowerExpr(expr->args[0]);
        curClassical->emit(OpCode::LINE_COUNT);
        return;
    }

    if (expr->identifier == "envGet") {
        if (expr->args.size() != 2) {
            throw std::runtime_error("envGet() expects 2 arguments");
        }
        lowerExpr(expr->args[0]);
        lowerExpr(expr->args[1]);
        curClassical->emit(OpCode::ENV_GET);
        return;
    }

    if (expr->identifier == "envSet") {
        if (expr->args.size() != 3) {
            throw std::runtime_error("envSet() expects 3 arguments");
        }
        lowerExpr(expr->args[0]);
        lowerExpr(expr->args[1]);
        lowerExpr(expr->args[2]);
        curClassical->emit(OpCode::ENV_SET);
        return;
    }

    if (expr->identifier == "pairVal") {
        if (expr->args.size() != 1) {
            throw std::runtime_error("pairVal() expects 1 argument");
        }
        lowerExpr(expr->args[0]);
        curClassical->emit(OpCode::PAIR_VAL);
        return;
    }

    if (expr->identifier == "pairPos") {
        if (expr->args.size() != 1) {
            throw std::runtime_error("pairPos() expects 1 argument");
        }
        lowerExpr(expr->args[0]);
        curClassical->emit(OpCode::PAIR_POS);
        return;
    }

    if (expr->identifier == "tokType") {
        if (expr->args.size() != 1) {
            throw std::runtime_error("tokType() expects 1 argument");
        }
        lowerExpr(expr->args[0]);
        curClassical->emit(OpCode::TOK_TYPE);
        return;
    }

    if (expr->identifier == "tokVal") {
        if (expr->args.size() != 1) {
            throw std::runtime_error("tokVal() expects 1 argument");
        }
        lowerExpr(expr->args[0]);
        curClassical->emit(OpCode::TOK_VAL);
        return;
    }

    if (expr->identifier == "findLastComma") {
        if (expr->args.size() != 1) {
            throw std::runtime_error("findLastComma() expects 1 argument");
        }
        lowerExpr(expr->args[0]);
        curClassical->emit(OpCode::FIND_LAST_COMMA);
        return;
    }

    for (const auto &arg : expr->args) {
        lowerExpr(arg);
    }

    curClassical->emit(OpCode::CALL, expr->identifier);
}

void Lowerer::lowerPrepare(const ExprPtr & /*expr*/) {
    if (!curQuantum) return;
    curQuantum->emit(QOpCode::ALLOC_QBIT, "q");
}

void Lowerer::lowerMeasure(const ExprPtr &expr) {
    if (!curQuantum) return;
    curQuantum->emit(QOpCode::MEASURE, expr->identifier);
}

} // namespace k