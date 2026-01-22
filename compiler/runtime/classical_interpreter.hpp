#pragma once
#include "compiler/ir/classical_ir.hpp"
#include "compiler/middle/lowering/lowerer.hpp" // for FunctionIRTable
#include <string>
#include <unordered_map>
#include <vector>


namespace k {

// A stack frame for CALL
struct Frame {
  const ClassicalIR *ir;
  int ip;
  std::unordered_map<std::string, int> vars;
};

class ClassicalInterpreter {
public:
  ClassicalInterpreter() = default;

  // Provide function table before running
  void setFunctionTable(const FunctionIRTable *table);

  // Execute a classical IR block
  void run(const ClassicalIR &ir);

private:
  const FunctionIRTable *functions = nullptr;
  std::vector<Frame> stack;

  int getValue(const Frame &frame, const std::string &arg);
};

} // namespace k