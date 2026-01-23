#pragma once
#include <string>

#include "compiler/ast/ast.hpp"
#include "compiler/frontend/driver.hpp"

namespace k {

class ModuleLoader {
public:
  explicit ModuleLoader(const std::string &rootPath) : rootDir(rootPath) {}

  // Load a .k file and return a parsed module
  ModuleDecl load(const std::string &path) {
    Driver driver;
    return driver.loadAndParse(path);
  }

private:
  std::string rootDir;
};

} // namespace k