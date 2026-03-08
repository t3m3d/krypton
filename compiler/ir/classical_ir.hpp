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
  SUBSTRING,
  // Control flow
  JUMP,
  JUMP_IF_FALSE,
  // Comparison
  CMP_EQ,
  CMP_NEQ,
  CMP_LT,
  CMP_GT,
  CMP_LTE,
  CMP_GTE,
  // Logical
  LOGIC_AND,
  LOGIC_OR,
  LOGIC_NOT,
  // String/collection
  INDEX,
  SPLIT,
  TO_INT,
  STARTS_WITH,
  COUNT,
  EXTRACT,
  FIND_SECOND,
  // IO / args
  READ_FILE,
  ARG,
  ARG_COUNT,
  // Misc
  POP
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