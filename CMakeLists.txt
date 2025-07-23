cmake_minimum_required(VERSION 3.20)
project(zen C)

set(CMAKE_C_STANDARD 99)

# Add source files
set(SOURCES
        src/main.c
        src/lexer.c
        src/ast.c
        src/parser.c
        src/codegen.c
        src/native_codegen.c
)

# Add header files for IDE support
set(HEADERS
        src/lexer.h
        src/ast.h
        src/parser.h
        src/codegen.h
        src/native_codegen.h
)

# Create the zen compiler executable
add_executable(zen ${SOURCES} ${HEADERS})

# Set compiler flags for better debugging and warnings
target_compile_options(zen PRIVATE
        -Wall
        -Wextra
        -Werror
        -g
        -O0
)

# Include the src directory for headers
target_include_directories(zen PRIVATE src)
