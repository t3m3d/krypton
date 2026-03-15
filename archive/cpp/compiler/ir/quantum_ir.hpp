#pragma once
#include <string>
#include <vector>


namespace k {

enum class QOpCode { ALLOC_QBIT, APPLY_GATE, MEASURE, DEALLOC_QBIT };

struct QInstruction {
  QOpCode op;
  std::string arg; // gate name or qubit id
};

struct QuantumIR {
  std::vector<QInstruction> instructions;

  void emit(QOpCode op, const std::string &arg = "") {
    instructions.push_back({op, arg});
  }
};

} // namespace k