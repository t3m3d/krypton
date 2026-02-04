#include "classical_interpreter.hpp"
#include <cctype>
#include <iostream>
#include <stdexcept>

namespace k {

void ClassicalInterpreter::setFunctionTable(const FunctionIRTable *table) {
    functions = table;
}

int ClassicalInterpreter::getValue(const Frame &frame, const std::string &arg) {
    // Literal integer?
    if (!arg.empty() && std::isdigit(arg[0])) {
        return std::stoi(arg);
    }

    // Variable lookup
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

        // End of function → pop frame
        if (frame.ip >= (int)ir.instructions.size()) {
            stack.pop_back();
            continue;
        }

        const Instruction &inst = ir.instructions[frame.ip];

        switch (inst.op) {

        case OpCode::LOAD_CONST:
            push(Value(std::stoi(inst.arg)));
            break;

        case OpCode::LOAD_VAR:
            push(Value(getValue(frame, inst.arg)));
            break;

        case OpCode::STORE_VAR:
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

        case OpCode::PRINT:
            if (!inst.arg.empty()) {
                std::cout << inst.arg;
            } else {
                std::cout << pop().toString();
            }
            break;

        case OpCode::CALL: {
            auto it = functions->find(inst.arg);
            if (it == functions->end()) {
                throw std::runtime_error("Unknown function: " + inst.arg);
            }

            // Push new frame
            stack.push_back(Frame{&it->second, 0, {}});
            frame.ip++; // advance caller IP
            continue;   // begin executing callee
        }

        case OpCode::RETURN:
            stack.pop_back();
            continue;
        }

        frame.ip++;
    }
}

}