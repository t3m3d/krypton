#pragma once
#include "compiler/ir/classical_ir.hpp"
#include <string>
#include <unordered_map>


namespace k {

class ClassicalInterpreter {
public:
  ClassicalInterpreter() = default;

  // Execute a sequence of classical IR instructions
  void run(const ClassicalIR &ir);

private:
  std::unordered_map<std::string, int> vars;
  int ip = 0; // instruction pointer

  int getValue(const std::string &arg);
};

} // namespace k