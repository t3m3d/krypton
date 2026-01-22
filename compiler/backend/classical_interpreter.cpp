#include "classical_interpreter.hpp"
#include <iostream>
#include <stdexcept>


namespace k {

int ClassicalInterpreter::getValue(const std::string &arg) {
  // literal?
  if (!arg.empty() && std::isdigit(arg[0])) {
    return std::stoi(arg);
  }
  // variable?
  if (vars.count(arg))
    return vars[arg];
  throw std::runtime_error("Unknown variable: " + arg);
}

void ClassicalInterpreter::run(const ClassicalIR &ir) {
  ip = 0;

  while (ip < (int)ir.instructions.size()) {
    const Instruction &inst = ir.instructions[ip];

    switch (inst.op) {
    case OpCode::LOAD_CONST:
      vars["_tmp"] = std::stoi(inst.arg);
      break;

    case OpCode::LOAD_VAR:
      vars["_tmp"] = getValue(inst.arg);
      break;

    case OpCode::STORE_VAR:
      vars[inst.arg] = vars["_tmp"];
      break;

    case OpCode::ADD:
      vars["_tmp"] += getValue(inst.arg);
      break;

    case OpCode::SUB:
      vars["_tmp"] -= getValue(inst.arg);
      break;

    case OpCode::MUL:
      vars["_tmp"] *= getValue(inst.arg);
      break;

    case OpCode::DIV:
      vars["_tmp"] /= getValue(inst.arg);
      break;

    case OpCode::RETURN:
      std::cout << "Return: " << vars["_tmp"] << "\n";
      return;

    default:
      throw std::runtime_error("Unsupported opcode");
    }

    ip++;
  }
}

} // namespace k