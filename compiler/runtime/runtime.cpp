#include "runtime.hpp"
#include <iostream>
#include <stdexcept>

namespace k {

void Runtime::runModule(const ModuleDecl &module) {
  // Lower all processes
  auto lowered = lowerer.lowerModule(module);

  // Find process main
  auto it = lowered.find("main");
  if (it == lowered.end()) {
    throw std::runtime_error("No process 'main' found in module");
  }

  const LoweredProcess &lp = it->second;

  std::cout << "[Runtime] Running classical IR...\n";
  classical.run(lp.classical);

  std::cout << "[Runtime] Running quantum IR...\n";
  quantum.run(lp.quantum);
}

} // namespace k