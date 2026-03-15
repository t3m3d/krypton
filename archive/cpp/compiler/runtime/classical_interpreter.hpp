#pragma once
#include "../value.hpp"
#include "../ir/classical_ir.hpp"
#include "../middle/lowering/lowerer.hpp"
#include <string>
#include <unordered_map>
#include <deque>
#include <vector>
#include <stdexcept>
#include <optional>

namespace k {

struct Frame {
  const ClassicalIR *ir;
  int ip;
  std::unordered_map<std::string, Value> vars;
};

class ClassicalInterpreter {
public:
  ClassicalInterpreter() = default;

  void setFunctionTable(const FunctionIRTable *table);
  void setArgs(const std::vector<std::string> &args);

  std::optional<Value> run(const ClassicalIR &ir);

private:
  const FunctionIRTable *functions = nullptr;
  std::vector<std::string> programArgs;
  std::vector<Frame> stack;

  Value getValue(const Frame &frame, const std::string &arg);
  std::deque<Value> valueStack;

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

} // namespace k