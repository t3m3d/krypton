Krypton Language Specification (Practical v1)
A living specification for the Krypton programming language.

1. Introduction
1.1 Purpose
Krypton (K) is a systems programming language designed for hybrid computation across classical and quantum boundaries. This specification defines the syntax, semantics, and execution model of the language at a practical, implementable level.
1.2 Design Philosophy
• 	Explicit over implicit
• 	Deterministic classical semantics
• 	Strict, typed quantum boundaries
• 	Minimal surface area
• 	Predictable execution
• 	Developer‑friendly syntax
• 	No hidden magic
1.3 Target Audience
Systems programmers, quantum developers, researchers, and engineers building hybrid classical–quantum systems.
1.4 Goals
• 	Provide a unified language for classical and quantum computation
• 	Enforce safe, explicit boundary semantics
• 	Support deterministic classical execution
• 	Enable backend‑agnostic quantum execution
• 	Offer a clean, modern syntax
1.5 Non‑Goals
• 	Being a general‑purpose scripting language
• 	Implicit quantum/classical interop
• 	Automatic optimization of quantum circuits
• 	Dynamic typing

2. Lexical Structure
2.1 Character Set
Krypton source files use UTF‑8 encoding.
2.2 Tokens
• 	Keywords
• 	Identifiers
• 	Literals
• 	Operators
• 	Punctuation
2.3 Keywords (v1)
```krypton
module
fn
quantum
qpute
process
let
return
measure
-prepare
true
false
```
2.4 Identifiers
- Start with a letter or underscore
- Followed by letters, digits, or underscores
- Case‑sensitive
2.5 Literals
- Integer literals
- Floating‑point literals
- Boolean literals
- String literals (UTF‑8)
2.6 Comments
```krypton
Single‑line: // comment
Multi‑line: /* comment */
```
2.7 Whitespace
Whitespace separates tokens but has no semantic meaning.

3. Modules
3.1 Module Declaration
```krypton
module name
```
3.2 File Layout
One module per file.
File name should match module name.
3.3 Visibility
All declarations are module‑scoped.
Visibility modifiers will be added in a future version.
3.4 Imports
Not yet implemented in v1.
4. Types
4.1 Primitive Classical Types
```krypton
int
float
bool
string
```
4.2 Quantum Types
```krypton
qbit
qarray<N> (future)
```
Quantum types follow linear ownership rules
4.3 Composite Types (Draft)
```krypton
Structs (future)
Tuples (future)
Arrays (classical arrays TBD)
```
4.4 Type Inference
Local inference allowed for let bindings.
Function signatures must be explicit.
4.5 Type Constraints
Quantum types cannot be copied, cloned, or implicitly duplicated.

5. Functions (Classical)
5.1 Syntax
```krypton
fn name(params) -> type {
    ...
}
fn name(params) -> type {
    ...
}
```
5.2 Parameters
Pass‑by‑value for classical types.
Quantum types cannot be passed to classical functions.
5.3 Return Types
Must be explicit.
5.4 Purity Model
Functions are deterministic.
Side effects are limited to:
- Local mutation
- Returning values
- Calling other classical functions
I/O is not allowed inside classical functions.
5.5 Error Handling
Error model TBD.
6. Quantum Blocks (qpute)
6.1 Syntax
```krypton
quantum qpute(x: qbit) -> bit {
    measure x
}
```
6.2 Inputs
Quantum parameters must be linear (single‑owner).
6.3 Outputs
Quantum blocks may return:
- Classical values (e.g., bit)
- Quantum values (future)
6.4 Allowed Operations
- Quantum gates (future)
- Measurement
- Quantum allocation (prepare qbit)
6.5 Restrictions
- No classical branching
- No loops
- No side effects
- No classical I/O
- No mutation of classical variables
6.6 Backend Model
Quantum blocks compile to a backend‑agnostic IR.

7. Processes
7.1 Syntax
```krypton
process main {
    ...
}
```
7.2 Purpose
Processes orchestrate classical and quantum execution.
7.3 Allowed Operations
- Classical computation
- Quantum block invocation
- Quantum preparation
- Printing/logging
- Control flow
- Variable binding
7.4 Execution Model
Processes run sequentially in v1.
Concurrency is a future feature.

8. Boundary Model
8.1 Classical → Quantum
Only explicit operations may cross the boundary:
- Passing quantum values into qpute
- Preparing new qubits
8.2 Quantum → Classical
Only measurement produces classical data.
8.3 Illegal Operations
- Implicit measurement
- Implicit quantum → classical conversion
- Passing classical values into quantum blocks unless explicitly allowed

9. Memory Model
9.1 Classical Memory
Deterministic, stack‑based, explicit lifetime.
9.2 Quantum Memory
Linear ownership:
- No copying
- No aliasing
- No implicit destruction
- Measurement consumes the quantum state
9.3 Scope
Quantum values cannot outlive their scope unless returned.
10. Expressions
10.1 Classical Expressions
- Arithmetic
- Boolean logic
- Function calls
- Variable references
10.2 Quantum Expressions
Restricted to:
- prepare qbit
- measure x
- Gate operations (future)
10.3 Precedence
Defined in Appendix A.

11. Statements
11.1 Variable Declarations
```krypton
let x = 5
let q = prepare qbit


11.2 Control Flow
if
while (future)
for (future)
```
11.3 Return
```krypton
return value
```

11.4 Block Rules
Classical blocks may contain any classical statements.
Quantum blocks have strict restrictions (see Section 6).

12. Standard Library (Draft)
12.1 Classical Utilities
```krypton
print
Basic math functions (future)
```
12.2 Quantum Primitives
```krypton
prepare qbit
measure x
```
12.3 I/O Model
Only processes may perform I/O.

13. Compiler Architecture (High‑Level)
13.1 Front‑End
- Lexer
- Parser
- AST builder
13.2 Type Checker
- Classical type checking
- Quantum linearity checking
- Boundary enforcement
13.3 IR
- Classical IR
- Quantum IR (backend‑agnostic)
13.4 Backends
- Classical interpreter (v1)
- Quantum simulator (v1)
- Hardware backends (future)
13.5 Error Reporting
Human‑readable, structured errors.

14. Runtime Model
14.1 Classical Runtime
Executes classical IR deterministically.
14.2 Quantum Runtime
Dispatches quantum IR to a simulator or hardware backend.
14.3 Process Scheduler
Sequential in v1.
Concurrency planned for future versions.

15. Examples (Normative)
15.1 Minimal Program
```krypton
module demo

process main {
    print("Hello, Krypton")
}


15.2 Classical Function
fn add(a: int, b: int) -> int {
    return a + b
}
```

15.3 Quantum Block
```krypton
quantum qpute(x: qbit) -> bit {
    measure x
}


15.4 Orchestration
process main {
    let q = prepare qbit
    let result = qpute(q)
    print(result)
}
```


16. Appendix
16.1 Grammar (EBNF Draft)
(We will expand this as we build the parser.)
Module      ::= "module" Identifier Decl*
Decl        ::= FnDecl | QputeDecl | ProcessDecl
FnDecl      ::= "fn" Identifier "(" Params? ")" "->" Type Block
QputeDecl   ::= "quantum" "qpute" "(" Params? ")" "->" Type Block
ProcessDecl ::= "process" Identifier Block
Block       ::= "{" Stmt* "}"
Stmt        ::= LetStmt | ExprStmt | ReturnStmt | IfStmt
LetStmt     ::= "let" Identifier "=" Expr
Expr        ::= Literal | Identifier | CallExpr | BinaryExpr


16.2 Reserved Words
module fn quantum qpute process let return measure prepare


16.3 Future Reserved Words
struct enum trait async await gate


16.4 Glossary
```krypton
qpute — a quantum execution block
boundary — the interface between classical and quantum semantics
linear type — a type that cannot be copied or aliased
```
- qpute — a quantum execution block
- boundary — the interface between classical and quantum semantics
- linear type — a type that cannot be copied or aliased
