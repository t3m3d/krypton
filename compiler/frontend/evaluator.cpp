#include "evaluator.hpp"
#include <iostream>
#include <variant>
#include <optional>

namespace k {

<<<<<<< HEAD
std::optional<Value> Evaluator::evaluate(const ModuleDecl& module) {
    // try to pick a "run" process if one exists
=======
static Value literalToValue(const ExprPtr& expr) {
    switch (expr->litKind) {
        case LiteralKind::Int:
            return Value(std::to_string(expr->litInt));

        case LiteralKind::Float:
            return Value(std::to_string(expr->litFloat));

        case LiteralKind::String:
            return Value(expr->litString);

        case LiteralKind::Bool:
            return Value(expr->litBool ? "true" : "false");
    }
    return Value("");
}

void Evaluator::evaluate(const ModuleDecl& module) {
>>>>>>> 55f12d0ac9096b1e646be66ac223353da7762815
    for (const auto& declVariant : module.decls) {
        if (std::holds_alternative<ProcessDeclPtr>(declVariant)) {
            auto process = std::get<ProcessDeclPtr>(declVariant);
            if (process && process->name == "run") {
                return evalProcess(process);
            }
        }
    }

<<<<<<< HEAD
    // fallback: just evaluate the first process encountered
=======
>>>>>>> 55f12d0ac9096b1e646be66ac223353da7762815
    for (const auto& declVariant : module.decls) {
        if (std::holds_alternative<ProcessDeclPtr>(declVariant)) {
            auto process = std::get<ProcessDeclPtr>(declVariant);
            if (process) {
                return evalRun(process);
            }
        }
    }

    std::cout << "No run block found. -eval\n";
    return std::nullopt;
}

std::optional<Value> Evaluator::evalRun(const ProcessDeclPtr& process) {
    if (!process || !process->body) {
        std::cout << "Run block has no body. -eval\n";
        return std::nullopt;
    }
    return evalBlock(process->body);
}

std::optional<Value> Evaluator::evalBlock(const BlockPtr& block) {
    if (!block) return std::nullopt;
    for (const auto& stmt : block->statements) {
        auto maybe = evalStmt(stmt);
        if (maybe.has_value())
            return maybe;
    }
    return std::nullopt;
}

std::optional<Value> Evaluator::evalStmt(const StmtPtr& stmt) {
    if (!stmt) return std::nullopt;

    switch (stmt->kind) {
    case StmtKind::Let: {
        Value v = evalExpr(stmt->expr);
        variables[stmt->name] = v;
        return std::nullopt;
    }
    case StmtKind::Emit: {
        Value result = evalExpr(stmt->expr);
        return result;
    }
    case StmtKind::If: {
        Value cond = evalExpr(stmt->condition);
        if (cond.isTruthy()) {
            return evalBlock(stmt->thenBlock);
        }
        return std::nullopt;
    }
    case StmtKind::Expr: {
        (void)evalExpr(stmt->expr);
        return std::nullopt;
    }
    }
    return std::nullopt;
}

Value Evaluator::evalExpr(const ExprPtr& expr) {
    if (!expr) return Value("");

    switch (expr->kind) {

    case ExprKind::Literal:
        return literalToValue(expr);

    case ExprKind::Identifier: {
        auto it = variables.find(expr->identifier);
        if (it != variables.end()) return it->second;
        std::cout << "[Evaluator] Undefined variable: " << expr->identifier << "\n";
        return Value("");
    }

    case ExprKind::Binary: {
        Value left = evalExpr(expr->left);
        Value right = evalExpr(expr->right);

        if (expr->op == "+") {
            return Value(left.toString() + right.toString());
        }

        std::cout << "[Evaluator] Unsupported binary op: " << expr->op << "\n";
        return Value("");
    }

    case ExprKind::Unary:
        std::cout << "[Evaluator] Unary not implemented yet.\n";
        return Value("");

    case ExprKind::Call:
        return evalCall(*expr);

    case ExprKind::Prepare:
        std::cout << "[Evaluator] Prepare not implemented yet.\n";
        return Value("");

    case ExprKind::Measure:
        std::cout << "[Evaluator] Measure not implemented yet.\n";
        return Value("");

    case ExprKind::Grouping:
        return evalExpr(expr->inner);
    }

    std::cout << "[Evaluator] Unknown expression kind.\n";
    return Value("");
}

Value Evaluator::evalCall(const Expr& callExpr) {
    const std::string& name = callExpr.identifier;

    if (name == "print" || name == "p") {
        for (const auto& arg : callExpr.args) {
            Value v = evalExpr(arg);
            std::cout << v.toString();
        }
        std::cout << "\n";
        return Value("");
    }

    std::cout << "[Evaluator] Unknown function: " << name << "\n";
    return Value("");
}

// simple implementation for now, forwards to run entrypoint
std::optional<Value> Evaluator::evalProcess(const ProcessDeclPtr& process) {
    return evalRun(process);
}

}