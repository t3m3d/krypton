cmake_minimum_required(VERSION 3.16)
project(krypton LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ------------------------------------------------------------
# Collect ONLY the frontend sources
# ------------------------------------------------------------
file(GLOB FRONTEND_SOURCES
    "compiler/main.cpp"
    "compiler/ast/*.cpp"
    "compiler/lexer/*.cpp"
    "compiler/parser/*.cpp"
    "compiler/frontend/*.cpp"
    "compiler/lowering/*.cpp"
    "compiler/runtime/*.cpp"
)

# ------------------------------------------------------------
# Build the compiler
# ------------------------------------------------------------
add_executable(kcc ${FRONTEND_SOURCES})

# ------------------------------------------------------------
# Attach include directories DIRECTLY to the target
# ------------------------------------------------------------
target_include_directories(kcc PRIVATE
    ${CMAKE_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/compiler
    ${CMAKE_SOURCE_DIR}/compiler/ast
    ${CMAKE_SOURCE_DIR}/compiler/lexer
    ${CMAKE_SOURCE_DIR}/compiler/parser
    ${CMAKE_SOURCE_DIR}/compiler/frontend
    ${CMAKE_SOURCE_DIR}/compiler/middle
    ${CMAKE_SOURCE_DIR}/compiler/middle/import
    ${CMAKE_SOURCE_DIR}/compiler/middle/typechecker
    ${CMAKE_SOURCE_DIR}/compiler/runtime
    ${CMAKE_SOURCE_DIR}/compiler/lowering    
)