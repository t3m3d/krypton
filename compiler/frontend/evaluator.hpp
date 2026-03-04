#pragma once
#include <string>
#include <unordered_map>
#include <optional>
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
    // evaluate the module and return the value produced by the run process (if
    // any).  The optional indicates whether an emit actually occurred.
    std::optional<Value> evaluate(const ModuleDecl& module);
private:
    std::unordered_map<std::string, Value> variables;
    std::optional<Value> evalProcess(const ProcessDeclPtr& process);
    // entry point for a "run" process block
    std::optional<Value> evalRun(const ProcessDeclPtr& process);
    std::optional<Value> evalBlock(const BlockPtr& block);
    // statements return an optional value when they are an emit
    std::optional<Value> evalStmt(const StmtPtr& stmt);
    Value evalExpr(const ExprPtr& expr);
    Value evalCall(const Expr& callExpr);
};
}