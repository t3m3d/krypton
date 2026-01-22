#pragma once
#include "compiler/ast/ast.hpp"
#include "compiler/backend/classical_interpreter.hpp"
#include "compiler/backend/quantum_simulator.hpp"


namespace k {

class Runtime {
public:
  Runtime() = default;

  void runProcess(const ProcessDecl &proc);

private:
  ClassicalInterpreter classical;
  QuantumSimulator quantum;
};

} // namespace k