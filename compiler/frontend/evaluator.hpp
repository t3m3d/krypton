// evaluator.hpp
#pragma once
#include "ast.hpp"
#include <unordered_map>
#include <string>
#include <iostream>

namespace k {

class Evaluator {
public:
    void evaluate(const ModuleDecl& module) {
        for (auto& stmt : module.statements) {
            evalStatement(stmt.get());
        }
    }

private:
    std::unordered_map<std::string, int> variables;

    void evalStatement(Statement* stmt) {
        if (auto* v = dynamic_cast<VarDeclStmt*>(stmt)) {
            int value = evalExpr(v->value.get());
            variables[v->name] = value;
            return;
        }

        if (auto* expr = dynamic_cast<Expression*>(stmt)) {
            evalExpr(expr);
            return;
        }

        std::cerr << "Unknown statement type\n";
    }

    int evalExpr(Expression* expr) {
        if (auto* lit = dynamic_cast<LiteralExpr*>(expr)) {
            return lit->value;
        }

        if (auto* id = dynamic_cast<IdentifierExpr*>(expr)) {
            return variables[id->name];
        }

        if (auto* bin = dynamic_cast<BinaryExpr*>(expr)) {
            int left = evalExpr(bin->left.get());
            int right = evalExpr(bin->right.get());
            switch (bin->op) {
                case '+': return left + right;
                case '-': return left - right;
                case '*': return left * right;
                case '/': return left / right;
            }
        }

        if (auto* call = dynamic_cast<CallExpr*>(expr)) {
            if (call->callee == "print") {
                for (auto& arg : call->args) {
                    std::cout << evalExpr(arg.get());
                }
                std::cout << "\n";
                return 0;
            }
        }

        std::cerr << "Unknown expression type\n";
        return 0;
    }
};

}