#pragma once
#include "compiler/ast/ast.hpp"

namespace k {

class BoundaryChecker {
public:
  void checkQputeBlock(const QputeDecl &qp);

private:
  void ensureNoClassicalBranching(const BlockPtr &block);
  void ensureNoClassicalSideEffects(const BlockPtr &block);
  void ensureMeasurementRules(const BlockPtr &block);
};

} // namespace k