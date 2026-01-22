#include "runtime.hpp"
#include <iostream>

namespace k {

void Runtime::runProcess(const ProcessDecl &proc) {
  std::cout << "Running process: " << proc.name << "\n";

  // For now, just print the AST
  for (const auto &stmt : proc.body->statements) {
    std::cout << "  stmt kind = " << (int)stmt->kind << "\n";
  }

  // Later:
  // 1. Lower AST -> IR
  // 2. classical.run(classicalIR)
  // 3. quantum.run(quantumIR)
}

} // namespace k