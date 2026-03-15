#pragma once
#include "compiler/ir/quantum_ir.hpp"
#include <string>
#include <unordered_map>


namespace k {

class QuantumSimulator {
public:
  QuantumSimulator() = default;

  // Execute quantum IR instructions
  void run(const QuantumIR &ir);

private:
  // Extremely simplified qubit model
  std::unordered_map<std::string, bool> qubits;
};

} // namespace k