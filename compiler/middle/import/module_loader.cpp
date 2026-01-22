#include "module_loader.hpp"
#include <filesystem>
#include <stdexcept>


namespace fs = std::filesystem;

namespace k {

ModuleLoader::ModuleLoader(const std::string &root)
    : rootDir(root), resolver(root) {}

ModuleDecl ModuleLoader::load(const std::string &path) {
  return loadModule(path);
}

ModuleDecl ModuleLoader::loadModule(const std::string &path) {
  // Normalize path
  fs::path p = fs::absolute(path);
  std::string key = p.string();

  // Cached?
  if (cache.count(key)) {
    return cache[key];
  }

  // Cycle detection
  if (loading.count(key)) {
    throw std::runtime_error("Cyclic import detected at: " + key);
  }
  loading.insert(key);

  // Parse module
  ModuleDecl mod = driver.loadAndParse(key);

  // Resolve imports
  for (auto &decl : mod.decls) {
    if (std::holds_alternative<ImportDecl>(decl)) {
      auto imp = std::get<ImportDecl>(decl);
      std::string importedPath = resolver.resolve(imp);

      ModuleDecl imported = loadModule(importedPath);
      merge(mod, imported);
    }
  }

  // Done loading this module
  loading.erase(key);

  // Cache it
  cache[key] = mod;
  return mod;
}

void ModuleLoader::merge(ModuleDecl &into, const ModuleDecl &from) {
  for (auto &decl : from.decls) {
    // Skip import declarations — they are already resolved
    if (std::holds_alternative<ImportDecl>(decl))
      continue;

    into.decls.push_back(decl);
  }
}

} // namespace k