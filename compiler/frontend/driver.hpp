#pragma once
#include "compiler/ast/ast.hpp"
#include <string>

namespace k {

class Driver {
public:
  // Return ModuleDecl by value, matching driver.cpp and parser.cpp
  ModuleDecl loadAndParse(const std::string &path);
};

} // namespace k