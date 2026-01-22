#pragma once
#include "classical_interpreter.hpp"
#include "compiler/ast/ast.hpp"
#include "compiler/middle/lowering/lowerer.hpp"
#include "quantum_simulator.hpp"
#include <string>


namespace k {

class Runtime {
public:
  Runtime() = default;

  void runModule(const ModuleDecl &module);

private:
  ClassicalInterpreter classical;
  QuantumSimulator quantum;
  Lowerer lowerer;
};

} // namespace k