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
    valueStack.clear();

    // Push initial frame
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
            // literal number (from lowerer)
            push(Value(std::stoi(inst.arg)));
            break;

        case OpCode::LOAD_VAR:
            // load variable from current frame
            push(Value(getValue(frame, inst.arg)));
            break;

        case OpCode::STORE_VAR:
            // store top of stack into variable
            frame.vars[inst.arg] = pop().number;
            break;

        case OpCode::ADD: {
            Value b = pop();
            Value a = pop();

            if (a.isNumber() && b.isNumber()) {
                push(Value(a.number + b.number));
            } else {
                push(Value(a.toString() + b.toString()));
            }
            break;
        }

        case OpCode::SUB: {
            Value b = pop();
            Value a = pop();
            push(Value(a.number - b.number));
            break;
        }

        case OpCode::MUL: {
            Value b = pop();
            Value a = pop();
            push(Value(a.number * b.number));
            break;
        }

        case OpCode::DIV: {
            Value b = pop();
            Value a = pop();
            push(Value(a.number / b.number));
            break;
        }

        case OpCode::PRINT: {
            // From lowerer:
            //  - PRINT "literal"  → inst.arg has text
            //  - PRINT ""         → print top of value stack
            if (!inst.arg.empty()) {
                std::cout << inst.arg << std::endl;
            } else {
                std::cout << pop().toString() << std::endl;
            }
            break;
        }

        case OpCode::CALL: {
            auto it = functions->find(inst.arg);
            if (it == functions->end()) {
                throw std::runtime_error("Unknown function: " + inst.arg);
            }

            // Push new frame for callee
            stack.push_back(Frame{&it->second, 0, {}});
            frame.ip++; // advance caller IP
            continue;   // start executing callee
        }

        case OpCode::RETURN: {
            // For now: just pop the frame.
            // Any return value should already be on valueStack if you use it.
            stack.pop_back();
            continue;
        }
        }

        frame.ip++;
    }
}

} // namespace k