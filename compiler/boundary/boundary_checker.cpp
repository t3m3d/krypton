#include "boundary_checker.hpp"
#include <stdexcept>

namespace k {

void BoundaryChecker::checkQputeBlock(const QputeDecl &qp) {
  ensureNoClassicalBranching(qp.body);
  ensureNoClassicalSideEffects(qp.body);
  ensureMeasurementRules(qp.body);
}

void BoundaryChecker::ensureNoClassicalBranching(const BlockPtr &block) {
  for (const auto &stmt : block->statements) {
    if (stmt->kind == StmtKind::If) {
      throw std::runtime_error(
          "qpute blocks cannot contain classical branching");
    }
  }
}

void BoundaryChecker::ensureNoClassicalSideEffects(const BlockPtr &block) {
  for (const auto &stmt : block->statements) {
    if (stmt->kind == StmtKind::Let) {
      throw std::runtime_error(
          "qpute blocks cannot declare classical variables");
    }
  }
}

void BoundaryChecker::ensureMeasurementRules(const BlockPtr &block) {
  for (const auto &stmt : block->statements) {
    if (stmt->kind == StmtKind::Expr && stmt->expr->kind == ExprKind::Measure) {
      // measurement is allowed
    }
  }
}

} // namespace k