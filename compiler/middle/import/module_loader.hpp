#pragma once
#include <string>
#include <unordered_map>
#include <unordered_set>

#include "compiler/ast/ast.hpp"
#include "compiler/frontend/driver.hpp"
#include "resolver.hpp"

namespace k {

class ModuleLoader {
public:
    explicit ModuleLoader(const std::string &root);

    // Public entry point: load a module (with imports resolved)
    ModuleDecl load(const std::string &path);

private:
    // Internal recursive loader
    ModuleDecl loadModule(const std::string &path);

    // Merge declarations from imported modules
    void merge(ModuleDecl &into, const ModuleDecl &from);

    std::string rootDir;
    ImportResolver resolver;
    Driver driver;

    // Prevent reloading and detect cycles
    std::unordered_map<std::string, ModuleDecl> cache;
    std::unordered_set<std::string> loading;
};

}