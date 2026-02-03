#pragma once

#include <string>
#include <unordered_map>
#include "../ast/ast.hpp"

namespace k {

struct Value {
    std::string str;

    Value() = default;
    Value(const std::string& s) : str(s) {}

    std::string toString() const { return str; }

    bool isTruthy() const {
        return !str.empty() && str != "0" && str != "false";
    }
};

class Evaluator {
public:
    Evaluator() = default;

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