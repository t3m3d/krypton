#pragma once
#include "../ast/ast.hpp"
#include "../value.hpp"
#include <string>
#include <unordered_map>
#include <optional>

namespace k {

class Evaluator {
public:
    Evaluator() = default;
    std::optional<Value> evaluate(const ModuleDecl& module);
private:
    std::unordered_map<std::string, Value> variables;
    std::optional<Value> evalProcess(const ProcessDeclPtr& process);
    std::optional<Value> evalRun(const ProcessDeclPtr& process);
    std::optional<Value> evalBlock(const BlockPtr& block);
    std::optional<Value> evalStmt(const StmtPtr& stmt);
    Value evalExpr(const ExprPtr& expr);
    Value evalCall(const Expr& callExpr);
};

} // namespace k