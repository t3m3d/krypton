#pragma once
#include "compiler/ast/ast.hpp"
#include "compiler/frontend/driver.hpp"
#include "resolver.hpp"
#include <string>
#include <unordered_map>
#include <unordered_set>


namespace k {

class ModuleLoader {
public:
  ModuleLoader(const std::string &root);

  // Load a module from a file path (entry point)
  ModuleDecl load(const std::string &path);

private:
  std::string rootDir;
  ImportResolver resolver;
  Driver driver;

  // Cache: path → ModuleDecl
  std::unordered_map<std::string, ModuleDecl> cache;

  // Cycle detection
  std::unordered_set<std::string> loading;

  ModuleDecl loadModule(const std::string &path);
  void merge(ModuleDecl &into, const ModuleDecl &from);
};

} // namespace k