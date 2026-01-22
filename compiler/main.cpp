#include "compiler/middle/import/module_loader.hpp"
#include "compiler/middle/typechecker/typechecker.hpp"
#include "compiler/runtime/runtime.hpp"


int main(int argc, char **argv) {
  if (argc < 2) {
    std::cout << "Usage: kcc <file.k>\n";
    return 1;
  }

  std::string path = argv[1];

  try {
    ModuleLoader loader("krypton-lang/src");
    ModuleDecl module = loader.load(path);

    TypeChecker tc;
    tc.checkModule(module);

    Runtime runtime;
    runtime.runModule(module);

  } catch (const std::exception &e) {
    std::cout << "Error: " << e.what() << "\n";
    return 1;
  }

  return 0;
}