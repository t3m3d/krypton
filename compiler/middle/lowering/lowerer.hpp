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

// NEW: function IR table
using FunctionIRTable = std::unordered_map<std::string, ClassicalIR>;

class Lowerer {
public:
  std::unordered_map<std::string, LoweredProcess>
  lowerModule(const ModuleDecl &module);

  // NEW: lower all functions
  FunctionIRTable lowerFunctions(const ModuleDecl &module);

private:
  ClassicalIR *curClassical = nullptr;
  QuantumIR *curQuantum = nullptr;

  void lowerProcess(const ProcessDecl &proc, LoweredProcess &out);

  // NEW: lower a single function
  void lowerFunction(const FnDecl &fn, ClassicalIR &out);

  void lowerBlock(const BlockPtr &block);
  void lowerStmt(const StmtPtr &stmt);
  void lowerExpr(const ExprPtr &expr);
  void lowerBinary(const ExprPtr &expr);
  void lowerUnary(const ExprPtr &expr);

  // UPDATED: now emits CALL
  void lowerCall(const ExprPtr &expr);

  void lowerPrepare(const ExprPtr &expr);
  void lowerMeasure(const ExprPtr &expr);
};

} // namespace k