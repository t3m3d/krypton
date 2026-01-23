#include "classical_interpreter.hpp"
#include <cctype>
#include <iostream>
#include <stdexcept>

namespace k {

void ClassicalInterpreter::setFunctionTable(const FunctionIRTable *table) {
  functions = table;
}

int ClassicalInterpreter::getValue(const Frame &frame, const std::string &arg) {
  if (!arg.empty() && std::isdigit(arg[0])) {
    return std::stoi(arg);
  }
  auto it = frame.vars.find(arg);
  if (it != frame.vars.end())
    return it->second;
  throw std::runtime_error("Unknown variable: " + arg);
}

void ClassicalInterpreter::run(const ClassicalIR &entry) {
  if (!functions) {
    throw std::runtime_error("Function table not set in ClassicalInterpreter");
  }

  stack.clear();
  stack.push_back(Frame{&entry, 0, {}});

  while (!stack.empty()) {
    Frame &frame = stack.back();
    const auto &ir = *frame.ir;

    if (frame.ip >= (int)ir.instructions.size()) {
      stack.pop_back();
      continue;
    }

    const Instruction &inst = ir.instructions[frame.ip];

    switch (inst.op) {
    case OpCode::LOAD_CONST:
      frame.vars["_tmp"] = std::stoi(inst.arg);
      break;

    case OpCode::LOAD_VAR:
      frame.vars["_tmp"] = getValue(frame, inst.arg);
      break;

    case OpCode::STORE_VAR:
      frame.vars[inst.arg] = frame.vars["_tmp"];
      break;

    case OpCode::ADD:
      frame.vars["_tmp"] += getValue(frame, inst.arg);
      break;

    case OpCode::SUB:
      frame.vars["_tmp"] -= getValue(frame, inst.arg);
      break;

    case OpCode::MUL:
      frame.vars["_tmp"] *= getValue(frame, inst.arg);
      break;

    case OpCode::DIV:
      frame.vars["_tmp"] /= getValue(frame, inst.arg);
      break;

    case OpCode::CALL: {
      auto it = functions->find(inst.arg);
      if (it == functions->end()) {
        throw std::runtime_error("Unknown function: " + inst.arg);
      }

      // Push new frame
      stack.push_back(Frame{&it->second, 0, {}});
      frame.ip++; // advance caller IP
      continue;   // start executing callee
    }

    case OpCode::RETURN:
      // Return value is in _tmp
      std::cout << "Return: " << frame.vars["_tmp"] << "\n";
      stack.pop_back();
      continue;
    }

    frame.ip++;
  }
}

} // namespace k