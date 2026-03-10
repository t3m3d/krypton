#pragma once
#include <string>

namespace k {
struct Value {
    bool isNum;
    int number;
    std::string str;

    Value() : isNum(true), number(0) {}
    Value(int n) : isNum(true), number(n) {}
    Value(const std::string &s) : isNum(false), number(0), str(s) {}
    Value(std::string &&s) : isNum(false), number(0), str(std::move(s)) {}

    bool isNumber() const { return isNum; }
    bool isTruthy() const { return isNum ? number != 0 : !str.empty() && str != "false"; }
    std::string toString() const {
        return isNum ? std::to_string(number) : str;
    }
};
}
