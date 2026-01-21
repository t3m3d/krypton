#pragma once
#include <string>
#include <memory>
#include <vector>

struct Expr {
    virtual ~Expr() = default;
};

struct NumberExpr : Expr {
    double value;
};

struct IdentifierExpr : Expr {
    std::string name;
};