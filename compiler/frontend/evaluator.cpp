#include "evaluator.hpp"
#include <iostream>
#include <variant>

namespace k {

void Evaluator::evaluate(const ModuleDecl& module) {
    // Prefer a process named "main"
    for (const auto& declVariant : module.decls) {
        if (std::holds_alternative<ProcessDeclPtr>(declVariant)) {
            auto process = std::get<ProcessDeclPtr>(declVariant);
            if (process && process->name == "main") {
                evalProcess(process);
                return;
            }
        }
    }

    // Fallback: run the first process, if any
    for (const auto& declVariant : module.decls) {
        if (std::holds_alternative<ProcessDeclPtr>(declVariant)) {
            auto process = std::get<ProcessDeclPtr>(declVariant);
            if (process) {
                evalProcess(process);
                return;
            }
        }
    }

    std::cout << "[Evaluator] No process found to run.\n";
}

void Evaluator::evalProcess(const ProcessDeclPtr& process) {
    if (!process || !process->body) {
        std::cout << "[Evaluator] Process has no body.\n";
        return;
    }
    evalBlock(process->body);
}

void Evaluator::evalBlock(const BlockPtr& block) {
    if (!block) return;
    for (const auto& stmt : block->statements) {
        evalStmt(stmt);
    }
}

void Evaluator::evalStmt(const StmtPtr& stmt) {
    if (!stmt) return;

    switch (stmt->kind) {
    case StmtKind::Let: {
        Value v = evalExpr(stmt->expr);
        variables[stmt->name] = v;
        break;
    }
    case StmtKind::Return: {
        (void)evalExpr(stmt->expr);
        break;
    }
    case StmtKind::If: {
        Value cond = evalExpr(stmt->condition);
        if (cond.isTruthy()) {
            evalBlock(stmt->thenBlock);
        }
        break;
    }
    case StmtKind::Expr: {
        (void)evalExpr(stmt->expr);
        break;
    }
    }
}

Value Evaluator::evalExpr(const ExprPtr& expr) {
    if (!expr) return Value();

    switch (expr->kind) {
    case ExprKind::Literal:
        return Value(expr->literalValue);

    case ExprKind::Identifier: {
        auto it = variables.find(expr->identifier);
        if (it != variables.end()) return it->second;
        std::cout << "[Evaluator] Undefined variable: " << expr->identifier << "\n";
        return Value();
    }

    case ExprKind::Binary: {
        Value left = evalExpr(expr->left);
        Value right = evalExpr(expr->right);
        if (expr->op == "+") {
            return Value(left.toString() + right.toString());
        }
        std::cout << "[Evaluator] Unsupported binary op: " << expr->op << "\n";
        return Value();
    }

    case ExprKind::Unary:
        std::cout << "[Evaluator] Unary not implemented yet.\n";
        return Value();

    case ExprKind::Call:
        return evalCall(*expr);

    case ExprKind::Prepare:
        std::cout << "[Evaluator] Prepare not implemented yet.\n";
        return Value();

    case ExprKind::Measure:
        std::cout << "[Evaluator] Measure not implemented yet.\n";
        return Value();

    case ExprKind::Grouping:
        return evalExpr(expr->inner);
    }

    std::cout << "[Evaluator] Unknown expression kind.\n";
    return Value();
}

Value Evaluator::evalCall(const Expr& callExpr) {
    const std::string& name = callExpr.identifier;

    if (name == "print" || name == "p") {
        for (const auto& arg : callExpr.args) {
            Value v = evalExpr(arg);
            std::cout << v.toString();
        }
        std::cout << "\n";
        return Value();
    }

    std::cout << "[Evaluator] Unknown function: " << name << "\n";
    return Value();
}

}