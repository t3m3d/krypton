#include "compiler/frontend/driver.hpp"
#include "compiler/middle/import/resolver.hpp"
#include "compiler/middle/lowering/lowerer.hpp"
#include "compiler/middle/typechecker/typechecker.hpp"
#include "compiler/repl/repl.hpp"
#include "compiler/runtime/runtime.hpp"
#include <iostream>


using namespace k;

int main(int argc, char **argv) {
  if (argc == 2 && std::string(argv[1]) == "--repl") {
    REPL repl;
    repl.start();
    return 0;
  }

  if (argc < 2) {
    std::cout << "Usage: kcc <file.k> or kcc --repl\n";
    return 1;
  }

  std::string path = argv[1];

  try {
    Driver driver;
    ModuleDecl module = driver.loadAndParse(path);

    // Resolve imports
    ImportResolver resolver("krypton-lang/src");
    // (You already have this logic in your import system)

    // Typecheck
    TypeChecker tc;
    tc.checkModule(module);

    // Run
    Runtime runtime;
    runtime.runModule(module);

  } catch (const std::exception &e) {
    std::cout << "Error: " << e.what() << "\n";
    return 1;
  }

  return 0;
}