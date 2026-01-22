#pragma once
#include "compiler/ast/ast.hpp"
#include <string>


namespace k {

class Driver {
public:
  ModuleDecl loadAndParse(const std::string &path);
};

} // namespace k