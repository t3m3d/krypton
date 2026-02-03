#pragma once

#include <string>
#include <unordered_map>
#include "../ast/ast.hpp"

namespace k {

// Simple runtime value
struct Value {
    std::string str;

    Value() = default;
    Value(const std::string& s) : str(s) {}

    // Later you can add int/float/bool, etc.
    std::string toString() const { return str; }

    bool isTruthy() const {
        // super simple truthiness for now
        return !str.empty() && str != "0" && str != "false";
    }
};

class Evaluator {
public:
    Evaluator() = default;

    // Entry point: run a whole module
    void evaluate(const ModuleDecl& module);

private:
    std::unordered_map<std::string, Value> variables;

    void evalProcess(const ProcessDeclPtr& process);
    void evalBlock(const BlockPtr& block);
    void evalStmt(const StmtPtr& stmt);
    Value evalExpr(const ExprPtr& expr);
    Value evalCall(const Expr& callExpr);
};

}