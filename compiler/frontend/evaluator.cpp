#include "evaluator.hpp"
#include <iostream>

namespace k {

// ------------------------------------------------------------
// Constructor
// ------------------------------------------------------------
Evaluator::Evaluator() {
    // You can register built-in functions here later if you want.
}

// ------------------------------------------------------------
// Entry point: evaluate a whole module
// ------------------------------------------------------------
void Evaluator::evaluate(const ModuleDecl& module) {
    for (auto& stmt : module.statements) {
        evalStatement(stmt.get());
    }
}

// ------------------------------------------------------------
// Evaluate a statement
// ------------------------------------------------------------
void Evaluator::evalStatement(Statement* stmt) {
    if (!stmt) return;

    // Variable declaration:  let x = expr;
    if (auto* v = dynamic_cast<VarDeclStmt*>(stmt)) {
        Value val = evalExpr(v->value.get());
        variables[v->name] = val;
        return;
    }

    // Expression as a statement (e.g., print("hi"))
    if (auto* expr = dynamic_cast<Expression*>(stmt)) {
        evalExpr(expr);
        return;
    }

    std::cerr << "[Evaluator] Unknown statement type\n";
}

// ------------------------------------------------------------
// Evaluate an expression and return a Value
// ------------------------------------------------------------
Value Evaluator::evalExpr(Expression* expr) {
    if (!expr) return Value();

    // Literal: numbers, strings, etc.
    if (auto* lit = dynamic_cast<LiteralExpr*>(expr)) {
        return Value(lit->value);
    }

    // Identifier: variable lookup
    if (auto* id = dynamic_cast<IdentifierExpr*>(expr)) {
        if (variables.contains(id->name)) {
            return variables[id->name];
        }
        std::cerr << "[Evaluator] Undefined variable: " << id->name << "\n";
        return Value();
    }

    // Binary expression: a + b, a - b, etc.
    if (auto* bin = dynamic_cast<BinaryExpr*>(expr)) {
        Value left = evalExpr(bin->left.get());
        Value right = evalExpr(bin->right.get());

        switch (bin->op) {
            case '+': return Value(left.asInt() + right.asInt());
            case '-': return Value(left.asInt() - right.asInt());
            case '*': return Value(left.asInt() * right.asInt());
            case '/': return Value(left.asInt() / right.asInt());
        }

        std::cerr << "[Evaluator] Unknown binary operator\n";
        return Value();
    }

    // Function call: print(expr)
    if (auto* call = dynamic_cast<CallExpr*>(expr)) {
        return evalCall(call);
    }

    std::cerr << "[Evaluator] Unknown expression type\n";
    return Value();
}

// ------------------------------------------------------------
// Evaluate a function call (built-ins only for now)
// ------------------------------------------------------------
Value Evaluator::evalCall(CallExpr* call) {
    if (call->callee == "print" || call->callee == "p") {
        for (auto& arg : call->args) {
            Value v = evalExpr(arg.get());
            std::cout << v.toString();
        }
        std::cout << "\n";
        return Value();
    }

    std::cerr << "[Evaluator] Unknown function: " << call->callee << "\n";
    return Value();
}

}