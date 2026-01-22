#pragma once
#include "compiler/ir/quantum_ir.hpp"
#include <string>
#include <unordered_map>
#include <vector>

namespace k {

class QuantumSimulator {
public:
  void run(const QuantumIR &ir);

private:
  std::unordered_map<std::string, bool> qubits; // extremely simplified
};

} // namespace k