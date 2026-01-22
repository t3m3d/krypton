#include "runtime.hpp"
#include <iostream>
#include <stdexcept>

namespace k {

void Runtime::runModule(const ModuleDecl &module) {
  // Lower all processes in the module
  auto lowered = lowerer.lowerModule(module);

  // Find process main
  auto it = lowered.find("main");
  if (it == lowered.end()) {
    throw std::runtime_error("No process 'main' found in module");
  }

  const LoweredProcess &lp = it->second;

  // Execute classical IR
  std::cout << "[Runtime] Running classical IR...\n";
  classical.run(lp.classical);

  // Execute quantum IR
  std::cout << "[Runtime] Running quantum IR...\n";
  quantum.run(lp.quantum);
}

void Runtime::runProcess(const ProcessDecl &proc) {
  // Deprecated: now handled by runModule
  (void)proc;
}

} // namespace k