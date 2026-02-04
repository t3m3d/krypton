#include "lowerer.hpp"
#include <stdexcept>
#include <utility>

namespace k {

//  lowerModule — lowers all process declarations
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

//  lowerFunctions — lowers all fn declarations to ClassicalIR
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

//  lowerFunction — lowers a single fn body
void Lowerer::lowerFunction(const FnDecl &fn, ClassicalIR &out) {
    curClassical = &out;
    lowerBlock(fn.body);

    // Ensure a RETURN exists so functions always terminate
    out.emit(OpCode::RETURN);
}

//  lowerProcess — lowers a process body
void Lowerer::lowerProcess(const ProcessDecl &proc, LoweredProcess & /*out*/) {
    lowerBlock(proc.body);
}

//  lowerBlock — lowers all statements in a block
void Lowerer::lowerBlock(const BlockPtr &block) {
    if (!block) return;
    for (const auto &stmt : block->statements) {
        lowerStmt(stmt);
    }
}

//  lowerStmt — let, return, if, expr
void Lowerer::lowerStmt(const StmtPtr &stmt) {
    if (!stmt) return;

    switch (stmt->kind) {
    case StmtKind::Let: {
        lowerExpr(stmt->expr);
        curClassical->emit(OpCode::STORE_VAR, stmt->name);
        break;
    }
    case StmtKind::Return: {
        lowerExpr(stmt->expr);
        curClassical->emit(OpCode::RETURN);
        break;
    }
    case StmtKind::If: {
        // For now: just lower condition + thenBlock (no else yet)
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

//  lowerExpr — dispatch by expression kind
void Lowerer::lowerExpr(const ExprPtr &expr) {
    if (!expr) return;

    switch (expr->kind) {
    case ExprKind::Literal: {
        curClassical->emit(OpCode::LOAD_CONST, expr->literalValue);
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

//  lowerBinary — simple arithmetic lowering
void Lowerer::lowerBinary(const ExprPtr &expr) {
    // Evaluate LHS first
    lowerExpr(expr->left);

    // For now we special‑case RHS as literal or identifier
    if (expr->op == "+") {
        if (expr->right->kind == ExprKind::Literal)
            curClassical->emit(OpCode::ADD, expr->right->literalValue);
        else if (expr->right->kind == ExprKind::Identifier)
            curClassical->emit(OpCode::ADD, expr->right->identifier);
        else
            throw std::runtime_error("Unsupported RHS in binary '+' lowering");
    } else if (expr->op == "-") {
        if (expr->right->kind == ExprKind::Literal)
            curClassical->emit(OpCode::SUB, expr->right->literalValue);
        else if (expr->right->kind == ExprKind::Identifier)
            curClassical->emit(OpCode::SUB, expr->right->identifier);
        else
            throw std::runtime_error("Unsupported RHS in binary '-' lowering");
    } else if (expr->op == "*") {
        if (expr->right->kind == ExprKind::Literal)
            curClassical->emit(OpCode::MUL, expr->right->literalValue);
        else if (expr->right->kind == ExprKind::Identifier)
            curClassical->emit(OpCode::MUL, expr->right->identifier);
        else
            throw std::runtime_error("Unsupported RHS in binary '*' lowering");
    } else if (expr->op == "/") {
        if (expr->right->kind == ExprKind::Literal)
            curClassical->emit(OpCode::DIV, expr->right->literalValue);
        else if (expr->right->kind == ExprKind::Identifier)
            curClassical->emit(OpCode::DIV, expr->right->identifier);
        else
            throw std::runtime_error("Unsupported RHS in binary '/' lowering");
    } else {
        throw std::runtime_error("Unsupported binary operator in lowering: " +
                                 expr->op);
    }
}

void Lowerer::lowerUnary(const ExprPtr &expr) {
    lowerExpr(expr->right);
}

//  lowerCall — built‑ins (print) + normal function calls
void Lowerer::lowerCall(const ExprPtr &expr) {
    // print is a built-in function (kp)
    if (expr->identifier == "kp") {
        for (const auto &arg : expr->args) {
            if (arg->kind == ExprKind::Literal) {
                // Direct literal print
                curClassical->emit(OpCode::PRINT, arg->literalValue);
            } else {
                // Evaluate expression → result on stack
                lowerExpr(arg);
                // PRINT "" means: print top of stack
                curClassical->emit(OpCode::PRINT, "");
            }
        }
        return;
    }

    // Normal function call: evaluate args, then CALL
    for (const auto &arg : expr->args) {
        lowerExpr(arg);
    }

    curClassical->emit(OpCode::CALL, expr->identifier);
}

//  lowerPrepare — quantum stub
void Lowerer::lowerPrepare(const ExprPtr & /*expr*/) {
    if (!curQuantum) return;
    curQuantum->emit(QOpCode::ALLOC_QBIT, "q");
}

//  lowerMeasure — quantum stub
void Lowerer::lowerMeasure(const ExprPtr &expr) {
    if (!curQuantum) return;
    curQuantum->emit(QOpCode::MEASURE, expr->identifier);
}

}