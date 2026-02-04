#pragma once
#include "compiler/ast/ast.hpp"
#include <string>
#include <vector>


namespace k {

class ImportResolver {
public:
  // root = path to krypton-lang/src
  explicit ImportResolver(const std::string &root);

  // Resolve an import like backend.core → full file path
  std::string resolve(const ImportDecl &imp) const;

private:
  std::string rootDir;
};

}