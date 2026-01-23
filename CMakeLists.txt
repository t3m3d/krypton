cmake_minimum_required(VERSION 3.16)
project(krypton LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Enable folders in IDEs
set_property(GLOBAL PROPERTY USE_FOLDERS ON)

# ------------------------------------------------------------
# Collect all compiler source files
# ------------------------------------------------------------
file(GLOB_RECURSE COMPILER_SOURCES
    "compiler/*.cpp"
)

# ------------------------------------------------------------
# Include directories
# ------------------------------------------------------------
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/ast
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/frontend
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/lexer
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/parser
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/middle
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/middle/boundary
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/middle/import
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/middle/lowering
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/middle/typechecker
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/ir
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/repl
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/runtime
)

# ------------------------------------------------------------
# Build the compiler executable
# ------------------------------------------------------------
add_executable(kcc
    ${COMPILER_SOURCES}
)

# ------------------------------------------------------------
# Tests
# ------------------------------------------------------------
enable_testing()

file(GLOB TEST_SOURCES
    "tests/*.cpp"
)

add_executable(krypton_tests
    ${TEST_SOURCES}
)

target_include_directories(krypton_tests PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler
)

add_test(NAME krypton_tests COMMAND krypton_tests)