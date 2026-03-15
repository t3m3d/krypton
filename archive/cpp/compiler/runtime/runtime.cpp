#include "runtime.hpp"
#include <iostream>
#include <stdexcept>

namespace k {

void Runtime::runModule(const ModuleDecl &module) {
  // Lower processes
  auto loweredProcs = lowerer.lowerModule(module);

  // Lower functions
  FunctionIRTable fnTable = lowerer.lowerFunctions(module);
  classical.setFunctionTable(&fnTable);

  // Find process main
  auto it = loweredProcs.find("main");
  if (it == loweredProcs.end()) {
    throw std::runtime_error("No process 'main' found in module");
  }

  const LoweredProcess &lp = it->second;

  std::cout << "[Runtime] Running classical IR...\n";
  classical.run(lp.classical);

  std::cout << "[Runtime] Running quantum IR...\n";
  quantum.run(lp.quantum);
}

}