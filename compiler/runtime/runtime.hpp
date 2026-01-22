#pragma once
#include "compiler/ast/ast.hpp"
#include "compiler/backend/classical_interpreter.hpp"
#include "compiler/backend/quantum_simulator.hpp"
#include "compiler/lowering/lowerer.hpp"
#include <string>
#include <unordered_map>


namespace k {

class Runtime {
public:
  Runtime() = default;

  // Run a module: find process main, lower it, execute it
  void runModule(const ModuleDecl &module);

private:
  ClassicalInterpreter classical;
  QuantumSimulator quantum;
  Lowerer lowerer;

  void runProcess(const ProcessDecl &proc);
};

} // namespace k