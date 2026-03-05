#include "classical_interpreter.hpp"
#include <cctype>
#include <iostream>
#include <stdexcept>

namespace k {

bool isNumber(const std::string &s) {
    if (s.empty()) return false;
    for (char c : s) {
        if (!std::isdigit(c)) return false;
    }
    return true;
}

void ClassicalInterpreter::setFunctionTable(const FunctionIRTable *table) {
    functions = table;
}

Value ClassicalInterpreter::getValue(const Frame &frame, const std::string &arg) {
    if (!arg.empty() && std::isdigit(arg[0])) {
        return Value(std::stoi(arg));
    }

    auto it = frame.vars.find(arg);
    if (it != frame.vars.end())
        return it->second;

    throw std::runtime_error("Unknown variable: " + arg);
}

std::optional<Value> ClassicalInterpreter::run(const ClassicalIR &entry) {
    if (!functions) {
        throw std::runtime_error("Function table not set in ClassicalInterpreter");
    }

    stack.clear();
    valueStack.clear();

    // Push initial frame
    stack.push_back(Frame{&entry, 0, {}});
    std::cerr << "interpreter started\n";
    std::cerr << "instructions size: " << entry.instructions.size() << "\n";
    for (size_t i = 0; i < entry.instructions.size(); ++i) {
        std::cerr << "inst " << i << ": " << (int)entry.instructions[i].op << " '" << entry.instructions[i].arg << "'\n";
    }

    std::optional<Value> retVal;
    std::cerr << "starting loop\n";
    while (!stack.empty()) {
        std::cerr << "loop iteration\n";
        Frame &frame = stack.back();
        std::cerr << "frame.ip = " << frame.ip << "\n";
        const auto &ir = *frame.ir;

        if (frame.ip >= (int)ir.instructions.size()) {
            stack.pop_back();
            continue;
        }

        const Instruction &inst = ir.instructions[frame.ip];

        switch (inst.op) {

        case OpCode::LOAD_CONST: {
            std::cerr << "in LOAD_CONST, arg='" << inst.arg << "'\n";
            // literal from lowerer
            if (isNumber(inst.arg)) {
                push(Value(std::stoi(inst.arg)));
            } else {
                std::cerr << "before push\n";
                push(Value(inst.arg));
            }
            break;
        }

        case OpCode::LOAD_VAR:
            // load variable from current frame
            push(getValue(frame, inst.arg));
            break;

        case OpCode::STORE_VAR:
            // store top of stack into variable
            frame.vars[inst.arg] = pop();
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
            // std::cerr << "PRINT arg='" << inst.arg << "' stackSize=" << valueStack.size() << "\n";
            // From lowerer:
            //  - PRINT "literal"  → inst.arg has text
            //  - PRINT ""         → print top of value stack
            if (!inst.arg.empty()) {
                // std::cout << inst.arg << std::endl;
            } else {
                Value v = pop();
                std::cout << v.toString() << std::endl;
            }
            break;
        }

        case OpCode::CALL: {
            auto it = functions->find(inst.arg);
            if (it == functions->end()) {
                throw std::runtime_error("Unknown function: " + inst.arg);
            }

            // Pop args from valueStack into new frame's vars
            std::unordered_map<std::string, Value> calleeVars;
            for (auto it_param = it->second.params.rbegin(); it_param != it->second.params.rend(); ++it_param) {
                if (valueStack.empty()) {
                    throw std::runtime_error("Not enough arguments for function: " + inst.arg);
                }
                Value arg = pop();
                calleeVars[*it_param] = arg;
            }

            // Push new frame for callee
            stack.push_back(Frame{&it->second, 0, std::move(calleeVars)});
            frame.ip++; // advance caller IP
            continue;   // start executing callee
        }

        case OpCode::RETURN: {
            std::cerr << "in RETURN\n";
            std::cerr << "valueStack.size() = " << valueStack.size() << "\n";
            // record top of valueStack if available
            if (!valueStack.empty()) {
                retVal = valueStack.back();
                std::cerr << "retVal set to " << retVal->toString() << "\n";
            }
            stack.pop_back();
            continue;
        }
        }

        frame.ip++;
    }
    std::cerr << "interpreter finished\n";
    return retVal;
}

} // namespace k