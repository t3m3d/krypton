#pragma once
#include "compiler/ir/classical_ir.hpp"
#include "compiler/middle/lowering/lowerer.hpp"
#include <string>
#include <unordered_map>
#include <vector>
#include <stdexcept>

namespace k {

struct Frame {
  const ClassicalIR *ir;
  int ip;
  std::unordered_map<std::string, int> vars;
};

struct Value {
    bool isNum;
    int number;
    std::string str;

    Value() : isNum(true), number(0) {}
    Value(int n) : isNum(true), number(n) {}
    Value(std::string s) : isNum(false), number(0), str(std::move(s)) {}

    bool isNumber() const { return isNum; }

    std::string toString() const {
        return isNum ? std::to_string(number) : str;
    }
};

class ClassicalInterpreter {
public:
  ClassicalInterpreter() = default;

  void setFunctionTable(const FunctionIRTable *table);

  void run(const ClassicalIR &ir);

private:
  const FunctionIRTable *functions = nullptr;
  std::vector<Frame> stack;

  int getValue(const Frame &frame, const std::string &arg);
  std::vector<Value> valueStack;

  Value pop() {
      if (valueStack.empty()) throw std::runtime_error("Stack underflow");
      Value v = valueStack.back();
      valueStack.pop_back();
      return v;
}

void push(const Value& v) {
    valueStack.push_back(v);
}
};

}