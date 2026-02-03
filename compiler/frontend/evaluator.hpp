#pragma once
#include <string>
#include <unordered_map>
#include "../ast/ast.hpp"

namespace k {

// A simple runtime value type
struct Value {
    int intValue = 0;
    std::string strValue;
    bool isString = false;

    Value() = default;
    Value(int v) : intValue(v), isString(false) {}
    Value(const std::string& s) : strValue(s), isString(true) {}

    int asInt() const { return intValue; }
    std::string toString() const { return isString ? strValue : std::to_string(intValue); }
};

class Evaluator {
public:
    Evaluator();
    void evaluate(const ModuleDecl& module);

private:
    std::unordered_map<std::string, Value> variables;

    void evalStatement(Statement* stmt);
    Value evalExpr(Expression* expr);
    Value evalCall(CallExpr* call);
};

} // namespace k