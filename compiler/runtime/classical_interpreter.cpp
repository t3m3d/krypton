#include "classical_interpreter.hpp"
#include <cctype>
#include <iostream>
#include <stdexcept>

namespace k {

static bool isNumber(const std::string &s) {
    if (s.empty()) return false;
    size_t start = 0;
    if (s[0] == '-' && s.size() > 1) start = 1;
    for (size_t i = start; i < s.size(); i++) {
        if (!std::isdigit(s[i])) return false;
    }
    return true;
}

void ClassicalInterpreter::setFunctionTable(const FunctionIRTable *table) {
    functions = table;
}

Value ClassicalInterpreter::getValue(const Frame &frame, const std::string &arg) {
    if (!arg.empty() && (std::isdigit(arg[0]) || (arg[0] == '-' && arg.size() > 1))) {
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
    stack.push_back(Frame{&entry, 0, {}});

    std::optional<Value> retVal;

    while (!stack.empty()) {
        Frame &frame = stack.back();
        const auto &ir = *frame.ir;

        if (frame.ip >= (int)ir.instructions.size()) {
            stack.pop_back();
            continue;
        }

        const Instruction &inst = ir.instructions[frame.ip];

        switch (inst.op) {

        case OpCode::LOAD_CONST: {
            if (isNumber(inst.arg)) {
                push(Value(std::stoi(inst.arg)));
            } else {
                push(Value(inst.arg));
            }
            break;
        }

        case OpCode::LOAD_VAR: {
            push(getValue(frame, inst.arg));
            break;
        }

        case OpCode::STORE_VAR: {
            frame.vars[inst.arg] = pop();
            break;
        }

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
            if (b.number == 0) throw std::runtime_error("Division by zero");
            push(Value(a.number / b.number));
            break;
        }

        case OpCode::PRINT: {
            if (!inst.arg.empty()) {
                std::cout << inst.arg << std::endl;
            } else {
                Value v = pop();
                std::cout << v.toString() << std::endl;
            }
            break;
        }

        case OpCode::CALL: {
            auto fit = functions->find(inst.arg);
            if (fit == functions->end()) {
                throw std::runtime_error("Unknown function: " + inst.arg);
            }
            std::unordered_map<std::string, Value> calleeVars;
            for (auto it_param = fit->second.params.rbegin();
                 it_param != fit->second.params.rend(); ++it_param) {
                if (valueStack.empty()) {
                    throw std::runtime_error("Not enough arguments for function: " + inst.arg);
                }
                calleeVars[*it_param] = pop();
            }
            // Increment caller IP BEFORE push_back (push may invalidate frame ref)
            frame.ip++;
            stack.push_back(Frame{&fit->second, 0, std::move(calleeVars)});
            continue;
        }

        case OpCode::RETURN: {
            if (!valueStack.empty()) {
                retVal = valueStack.back();
            }
            stack.pop_back();
            continue;
        }

        case OpCode::LEN: {
            Value v = pop();
            int n = static_cast<int>(v.toString().size());
            push(Value(n));
            break;
        }

        case OpCode::SUBSTRING: {
            Value endV = pop();
            Value startV = pop();
            Value strV = pop();
            std::string s = strV.toString();
            int start = startV.number;
            int end = endV.number;
            if (start < 0) start = 0;
            if (end > (int)s.size()) end = (int)s.size();
            if (start > end) start = end;
            push(Value(s.substr(start, end - start)));
            break;
        }

        // ---- Control flow ----

        case OpCode::JUMP: {
            frame.ip = std::stoi(inst.arg);
            continue;
        }

        case OpCode::JUMP_IF_FALSE: {
            Value cond = pop();
            if (!cond.isTruthy()) {
                frame.ip = std::stoi(inst.arg);
                continue;
            }
            break;
        }

        // ---- Comparisons ----

        case OpCode::CMP_EQ: {
            Value b = pop();
            Value a = pop();
            if (a.isNumber() && b.isNumber())
                push(Value(a.number == b.number ? 1 : 0));
            else
                push(Value(a.toString() == b.toString() ? 1 : 0));
            break;
        }

        case OpCode::CMP_NEQ: {
            Value b = pop();
            Value a = pop();
            if (a.isNumber() && b.isNumber())
                push(Value(a.number != b.number ? 1 : 0));
            else
                push(Value(a.toString() != b.toString() ? 1 : 0));
            break;
        }

        case OpCode::CMP_LT: {
            Value b = pop();
            Value a = pop();
            if (a.isNumber() && b.isNumber())
                push(Value(a.number < b.number ? 1 : 0));
            else
                push(Value(a.toString() < b.toString() ? 1 : 0));
            break;
        }

        case OpCode::CMP_GT: {
            Value b = pop();
            Value a = pop();
            if (a.isNumber() && b.isNumber())
                push(Value(a.number > b.number ? 1 : 0));
            else
                push(Value(a.toString() > b.toString() ? 1 : 0));
            break;
        }

        case OpCode::CMP_LTE: {
            Value b = pop();
            Value a = pop();
            if (a.isNumber() && b.isNumber())
                push(Value(a.number <= b.number ? 1 : 0));
            else
                push(Value(a.toString() <= b.toString() ? 1 : 0));
            break;
        }

        case OpCode::CMP_GTE: {
            Value b = pop();
            Value a = pop();
            if (a.isNumber() && b.isNumber())
                push(Value(a.number >= b.number ? 1 : 0));
            else
                push(Value(a.toString() >= b.toString() ? 1 : 0));
            break;
        }

        // ---- Logical ----

        case OpCode::LOGIC_AND: {
            Value b = pop();
            Value a = pop();
            push(Value((a.isTruthy() && b.isTruthy()) ? 1 : 0));
            break;
        }

        case OpCode::LOGIC_OR: {
            Value b = pop();
            Value a = pop();
            push(Value((a.isTruthy() || b.isTruthy()) ? 1 : 0));
            break;
        }

        case OpCode::LOGIC_NOT: {
            Value a = pop();
            push(Value(a.isTruthy() ? 0 : 1));
            break;
        }

        // ---- String/collection ops ----

        case OpCode::INDEX: {
            Value idx = pop();
            Value obj = pop();
            std::string s = obj.toString();
            int i = idx.number;
            if (i < 0 || i >= (int)s.size()) {
                push(Value(""));
            } else {
                push(Value(std::string(1, s[i])));
            }
            break;
        }

        case OpCode::SPLIT: {
            // split(str, idx) - split comma-delimited string, return idx-th part
            Value idxV = pop();
            Value strV = pop();
            std::string s = strV.toString();
            int idx = idxV.number;
            std::vector<std::string> parts;
            std::string part;
            for (char c : s) {
                if (c == ',') {
                    parts.push_back(part);
                    part.clear();
                } else {
                    part += c;
                }
            }
            parts.push_back(part);
            if (idx >= 0 && idx < (int)parts.size()) {
                push(Value(parts[idx]));
            } else {
                push(Value(""));
            }
            break;
        }

        case OpCode::TO_INT: {
            Value v = pop();
            std::string s = v.toString();
            try {
                push(Value(std::stoi(s)));
            } catch (...) {
                push(Value(0));
            }
            break;
        }

        case OpCode::STARTS_WITH: {
            Value prefix = pop();
            Value str = pop();
            std::string s = str.toString();
            std::string p = prefix.toString();
            bool result = s.size() >= p.size() && s.compare(0, p.size(), p) == 0;
            push(Value(result ? 1 : 0));
            break;
        }

        case OpCode::COUNT: {
            // count newline-delimited entries
            Value v = pop();
            std::string s = v.toString();
            if (s.empty()) {
                push(Value(0));
            } else {
                int cnt = 1;
                for (char c : s) {
                    if (c == '\n') cnt++;
                }
                // Remove trailing empty entry
                if (!s.empty() && s.back() == '\n') cnt--;
                push(Value(cnt));
            }
            break;
        }

        case OpCode::EXTRACT: {
            // extract(sexp, offset) - extract balanced s-expression starting at offset
            Value offV = pop();
            Value strV = pop();
            std::string s = strV.toString();
            int off = offV.number;
            if (off >= (int)s.size()) {
                push(Value(""));
                break;
            }
            // If starts with '(', find matching ')'
            if (s[off] == '(') {
                int depth = 0;
                int end = off;
                for (int i = off; i < (int)s.size(); i++) {
                    if (s[i] == '(') depth++;
                    if (s[i] == ')') depth--;
                    if (depth == 0) { end = i + 1; break; }
                }
                push(Value(s.substr(off, end - off)));
            } else {
                // Read until space or end or ')'
                int end = off;
                while (end < (int)s.size() && s[end] != ' ' && s[end] != ')') end++;
                push(Value(s.substr(off, end - off)));
            }
            break;
        }

        case OpCode::FIND_SECOND: {
            // findSecond(sexp) - find start of second sub-expression in s-expr
            // e.g. "(add (num 1) (num 2))" -> find start of "(num 2)"
            Value strV = pop();
            std::string s = strV.toString();
            // Skip the opening tag like "(add "
            int i = 1; // skip '('
            while (i < (int)s.size() && s[i] != ' ') i++; // skip op name
            i++; // skip space
            // Now skip the first sub-expression
            if (i < (int)s.size() && s[i] == '(') {
                int depth = 0;
                for (; i < (int)s.size(); i++) {
                    if (s[i] == '(') depth++;
                    if (s[i] == ')') depth--;
                    if (depth == 0) { i++; break; }
                }
            } else {
                while (i < (int)s.size() && s[i] != ' ' && s[i] != ')') i++;
            }
            // Skip space
            if (i < (int)s.size() && s[i] == ' ') i++;
            push(Value(i));
            break;
        }

        case OpCode::POP: {
            if (!valueStack.empty()) pop();
            break;
        }

        } // switch

        frame.ip++;
    }

    return retVal;
}

} // namespace k