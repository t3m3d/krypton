#pragma once
#include "compiler/ast/ast.hpp"
#include "compiler/ir/classical_ir.hpp"
#include "compiler/ir/quantum_ir.hpp"
#include <string>
#include <unordered_map>


namespace k {

struct LoweredProcess {
  ClassicalIR classical;
  QuantumIR quantum;
};

class Lowerer {
public:
  // Lower a whole module into per-process IR
  std::unordered_map<std::string, LoweredProcess>
  lowerModule(const ModuleDecl &module);

private:
  // Current IR targets while lowering a process
  ClassicalIR *curClassical = nullptr;
  QuantumIR *curQuantum = nullptr;

  void lowerProcess(const ProcessDecl &proc, LoweredProcess &out);

  // Statements / blocks
  void lowerBlock(const BlockPtr &block);
  void lowerStmt(const StmtPtr &stmt);

  // Expressions
  void lowerExpr(const ExprPtr &expr);
  void lowerBinary(const ExprPtr &expr);
  void lowerUnary(const ExprPtr &expr);
  void lowerCall(const ExprPtr &expr);
  void lowerPrepare(const ExprPtr &expr);
  void lowerMeasure(const ExprPtr &expr);
};

} // namespace k