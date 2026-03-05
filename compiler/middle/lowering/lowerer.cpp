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
        lowerBlock(stmt->thenBlock);
        break;
    }
    case StmtKind::Expr: {
        lowerExpr(stmt->expr);
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
    }
}

void Lowerer::lowerBinary(const ExprPtr &expr) {
    lowerExpr(expr->left);

    auto emitWithRhs = [&](OpCode op) {
        if (expr->right->kind == ExprKind::Literal)
            curClassical->emit(op, literalToString(expr->right));
        else if (expr->right->kind == ExprKind::Identifier)
            curClassical->emit(op, expr->right->identifier);
        else
            throw std::runtime_error("Unsupported RHS in binary lowering");
    };

    if (expr->op == "+") {
        emitWithRhs(OpCode::ADD);
    } else if (expr->op == "-") {
        emitWithRhs(OpCode::SUB);
    } else if (expr->op == "*") {
        emitWithRhs(OpCode::MUL);
    } else if (expr->op == "/") {
        emitWithRhs(OpCode::DIV);
    } else {
        throw std::runtime_error("Unsupported binary operator in lowering: " + expr->op);
    }
}

void Lowerer::lowerUnary(const ExprPtr &expr) {
    lowerExpr(expr->right);
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