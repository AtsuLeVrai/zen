cmake_minimum_required(VERSION 3.31)
project(zen)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find LLVM package
find_package(LLVM REQUIRED CONFIG)

message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION}")
message(STATUS "Using LLVMConfig.cmake in: ${LLVM_DIR}")

# Set LLVM compilation flags
add_definitions(${LLVM_DEFINITIONS})

# Create directories if they don't exist
file(MAKE_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/src/lexer)
file(MAKE_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/src/parser)
file(MAKE_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/src/ast)
file(MAKE_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/src/codegen)

# Source files
set(SOURCES
        main.cpp
        src/lexer/lexer.cpp
        src/parser/parser.cpp
        src/codegen/llvm_codegen.cpp
)

# Header files
set(HEADERS
        src/lexer/token.h
        src/lexer/lexer.h
        src/parser/parser.h
        src/ast/ast_node.h
        src/codegen/llvm_codegen.h
)

add_executable(zen ${SOURCES} ${HEADERS})

# Include directories
target_include_directories(zen PRIVATE 
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${LLVM_INCLUDE_DIRS}
)

# Link LLVM libraries
llvm_map_components_to_libnames(llvm_libs 
    core
    support
    irreader
    target
    x86codegen
    x86asmparser
    x86disassembler
    executionengine
    mcjit
    interpreter
    native
)

target_link_libraries(zen ${llvm_libs})

# Compiler flags for better error reporting and debugging
if (CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(zen PRIVATE -Wall -Wextra -g)
    target_link_options(zen PRIVATE -static-libgcc -static-libstdc++)
elseif (MSVC)
    target_compile_options(zen PRIVATE /W4)
endif ()

# Enable modern C++ features
target_compile_features(zen PRIVATE cxx_std_17)
