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
  CALL,
  RETURN,
  PRINT,
  LEN,
  SUBSTRING
};

struct Instruction {
  OpCode op;
  std::string arg;
};

struct ClassicalIR {
  std::vector<Instruction> instructions;
  std::vector<std::string> params;  // parameter names for functions

  void emit(OpCode op, const std::string &arg = "") {
    instructions.push_back({op, arg});
  }
};

}