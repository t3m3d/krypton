#include "quantum_simulator.hpp"
#include <iostream>

namespace k {

void QuantumSimulator::run(const QuantumIR &ir) {
  for (const auto &inst : ir.instructions) {
    switch (inst.op) {
    case QOpCode::ALLOC_QBIT:
      qubits[inst.arg] = false; // start in |0>
      break;

    case QOpCode::APPLY_GATE:
      std::cout << "Applying gate " << inst.arg << "\n";
      break;

    case QOpCode::MEASURE:
      std::cout << "Measured " << inst.arg << " -> " << qubits[inst.arg]
                << "\n";
      break;

    case QOpCode::DEALLOC_QBIT:
      qubits.erase(inst.arg);
      break;
    }
  }
}

} // namespace k