#pragma once
#include <string>
#include <vector>


namespace k {

enum class OpCode {
  LOAD_CONST,
  LOAD_VAR,
  STORE_VAR,
  ADD,
  SUB,
  MUL,
  DIV,
  JUMP,
  JUMP_IF_FALSE,
  CALL,
  RETURN
};

struct Instruction {
  OpCode op;
  std::string arg; // variable name, literal, or label
};

struct ClassicalIR {
  std::vector<Instruction> instructions;

  void emit(OpCode op, const std::string &arg = "") {
    instructions.push_back({op, arg});
  }
};

} // namespace k