#include "evaluator.hpp"
#include <iostream>
#include <variant>

namespace k {

// ------------------------------------------------------------
// Entry point: evaluate a whole module
// ------------------------------------------------------------
void Evaluator::evaluate(const ModuleDecl& module) {
    // For now: run the first ProcessDecl we find.
    // Later you can choose by name (e.g., "main").
    for (const auto& declVariant : module.decls) {
        if (std::holds_alternative<ProcessDeclPtr>(declVariant)) {
            auto process = std::get<ProcessDeclPtr>(declVariant);
            evalProcess(process);
            return;
        }
    }

    std::cerr << "[Evaluator] No process found to run.\n";
}

// ------------------------------------------------------------
// Run a process: just execute its body block
// ------------------------------------------------------------
void Evaluator::evalProcess(const ProcessDeclPtr& process) {
    if (!process || !process->body) {
        std::cerr << "[Evaluator] Process has no body.\n";
        return;
    }

    evalBlock(process->body);
}

// ------------------------------------------------------------
// Run a block: execute each statement in order
// ------------------------------------------------------------
void Evaluator::evalBlock(const BlockPtr& block) {
    if (!block) return;

    for (const auto& stmt : block->statements) {
        evalStmt(stmt);
    }
}

// ------------------------------------------------------------
// Evaluate a statement
// ------------------------------------------------------------
void Evaluator::evalStmt(const StmtPtr& stmt) {
    if (!stmt) return;

    switch (stmt->kind) {
    case StmtKind::Let: {
        Value v = evalExpr(stmt->expr);
        variables[stmt->name] = v;
        break;
    }

    case StmtKind::Return: {
        // You don't have a function call stack yet,
        // so for now we just evaluate and ignore.
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

// ------------------------------------------------------------
// Evaluate an expression
// ------------------------------------------------------------
Value Evaluator::evalExpr(const ExprPtr& expr) {
    if (!expr) return Value();

    switch (expr->kind) {
    case ExprKind::Literal:
        return Value(expr->literalValue);

    case ExprKind::Identifier: {
        auto it = variables.find(expr->identifier);
        if (it != variables.end()) {
            return it->second;
        }
        std::cerr << "[Evaluator] Undefined variable: " << expr->identifier << "\n";
        return Value();
    }

    case ExprKind::Binary: {
        Value left = evalExpr(expr->left);
        Value right = evalExpr(expr->right);

        // For now, treat as string concatenation for '+'
        if (expr->op == "+") {
            return Value(left.toString() + right.toString());
        }

        std::cerr << "[Evaluator] Unsupported binary op: " << expr->op << "\n";
        return Value();
    }

    case ExprKind::Unary: {
        // You can add unary ops later (e.g., '-', '!')
        std::cerr << "[Evaluator] Unary not implemented yet.\n";
        return Value();
    }

    case ExprKind::Call:
        return evalCall(*expr);

    case ExprKind::Prepare:
        // Quantum stuff later
        std::cerr << "[Evaluator] Prepare not implemented yet.\n";
        return Value();

    case ExprKind::Measure:
        std::cerr << "[Evaluator] Measure not implemented yet.\n";
        return Value();

    case ExprKind::Grouping:
        return evalExpr(expr->inner);
    }

    std::cerr << "[Evaluator] Unknown expression kind.\n";
    return Value();
}

// ------------------------------------------------------------
// Evaluate a call expression (built-ins only for now)
// ------------------------------------------------------------
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

    std::cerr << "[Evaluator] Unknown function: " << name << "\n";
    return Value();
}

}