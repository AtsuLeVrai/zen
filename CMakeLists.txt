cmake_minimum_required(VERSION 3.20)

project(zen 
    VERSION 0.1.0
    DESCRIPTION "Zen Programming Language Compiler"
    LANGUAGES C
)

# =============================================================================
# PROJECT CONFIGURATION
# =============================================================================

# C Standard
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)  # Pure C99, no extensions

# Default build type
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug)
endif()

# Project options
option(ZEN_BUILD_TESTS "Build unit tests" ON)
option(ZEN_BUILD_TOOLS "Build development tools" ON)
option(ZEN_ENABLE_SANITIZERS "Enable AddressSanitizer and UBSan in Debug" ON)
option(ZEN_ENABLE_COVERAGE "Enable code coverage" OFF)
option(ZEN_TARGET_WASM "Enable WebAssembly target support" OFF)

# =============================================================================
# COMPILER FLAGS
# =============================================================================

# Strict warnings (more robust than simple if check)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    add_compile_options(
        -Wall
        -Wextra
        -Wpedantic
        -Werror
        -Wstrict-prototypes
        -Wmissing-prototypes
        -Wold-style-definition
        -Wshadow
        -Wpointer-arith
        -Wcast-qual
        -Wwrite-strings
        -Wmissing-declarations
        # Zen-specific: memory safety warnings
        -Wformat-security
        -Warray-bounds
        -Wnull-dereference
    )
endif()

# Build-specific flags
set(CMAKE_C_FLAGS_DEBUG "-g -O0 -DDEBUG -DZEN_DEBUG")
set(CMAKE_C_FLAGS_RELEASE "-O3 -DNDEBUG -DZEN_RELEASE")
set(CMAKE_C_FLAGS_RELWITHDEBINFO "-O2 -g -DNDEBUG")

# Sanitizers for Debug builds
if(ZEN_ENABLE_SANITIZERS AND CMAKE_BUILD_TYPE STREQUAL "Debug")
    if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
        add_compile_options(-fsanitize=address -fsanitize=undefined -fno-omit-frame-pointer)
        add_link_options(-fsanitize=address -fsanitize=undefined)
    endif()
endif()

# Code coverage
if(ZEN_ENABLE_COVERAGE AND CMAKE_BUILD_TYPE STREQUAL "Debug")
    if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
        add_compile_options(-fprofile-arcs -ftest-coverage)
        add_link_options(-fprofile-arcs -ftest-coverage)
    endif()
endif()

# =============================================================================
# SOURCES (More robust than GLOB_RECURSE)
# =============================================================================

# Main compiler sources
set(ZEN_COMPILER_SOURCES
    # Frontend
    compiler/src/frontend/lexer/lexer.c
    compiler/src/frontend/parser/parser.c
    compiler/src/frontend/ast/ast.c
    
    # Analysis (to be added when created)
    # compiler/src/analysis/types/type_system.c
    # compiler/src/analysis/types/optionals.c
    # compiler/src/analysis/types/arrays.c
    # compiler/src/analysis/error_system/result_types.c
    
    # Code generation
    compiler/src/codegen/codegen.c
    compiler/src/codegen/native_codegen.c
    
    # Targets (to be added)
    # compiler/src/targets/target_system.c
    
    # Integrations (to be added)
    # compiler/src/integrations/typescript/dts_generator.c
    
    # Utils (to be created)
    # compiler/src/utils/memory.c
    # compiler/src/utils/vector.c
    # compiler/src/utils/hashmap.c
    
    # Main
    compiler/src/main.c
)

# Headers (for IDE support)
set(ZEN_COMPILER_HEADERS
    compiler/src/frontend/lexer/lexer.h
    compiler/src/frontend/parser/parser.h
    compiler/src/frontend/ast/ast.h
    compiler/src/codegen/codegen.h
    compiler/src/codegen/native_codegen.h
    # Add new headers here
)

# =============================================================================
# MAIN EXECUTABLE
# =============================================================================

add_executable(zen ${ZEN_COMPILER_SOURCES} ${ZEN_COMPILER_HEADERS})

# Include directories (modern target-based approach)
target_include_directories(zen PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/src
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/src/frontend
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/src/frontend/ast
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/src/frontend/lexer
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/src/frontend/parser
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/src/analysis
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/src/codegen
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/src/targets
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/src/integrations
    ${CMAKE_CURRENT_SOURCE_DIR}/compiler/src/utils
)

# Compile definitions for Zen
target_compile_definitions(zen PRIVATE
    ZEN_VERSION_MAJOR=${PROJECT_VERSION_MAJOR}
    ZEN_VERSION_MINOR=${PROJECT_VERSION_MINOR}
    ZEN_VERSION_PATCH=${PROJECT_VERSION_PATCH}
    ZEN_VERSION_STRING="${PROJECT_VERSION}"
)

# Platform-specific libraries
if(UNIX AND NOT APPLE)
    target_link_libraries(zen PRIVATE dl)  # For dlopen (hot-patching)
endif()

# =============================================================================
# TOOLS
# =============================================================================

if(ZEN_BUILD_TOOLS)
    add_subdirectory(tools/zen-fmt)
    add_subdirectory(tools/zen-doc)
    add_subdirectory(tools/zen-test)
    add_subdirectory(tools/zen-pkg)
endif()

# =============================================================================
# TESTS
# =============================================================================

if(ZEN_BUILD_TESTS)
    enable_testing()
    
    # Unit tests
    set(ZEN_TEST_SOURCES
        tests/unit/test_lexer.c
        tests/unit/test_parser.c
        tests/unit/test_ast.c
        tests/unit/test_type_system.c
        tests/unit/test_codegen.c
        # Simple test framework
        tests/framework/zen_test.c
    )
    
    add_executable(zen_tests 
        ${ZEN_TEST_SOURCES}
        ${ZEN_COMPILER_SOURCES}
    )
    
    # Remove main.c from tests (avoid duplicate main)
    list(REMOVE_ITEM ZEN_COMPILER_SOURCES compiler/src/main.c)
    
    target_include_directories(zen_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/compiler/src
        ${CMAKE_CURRENT_SOURCE_DIR}/tests/framework
    )
    
    target_compile_definitions(zen_tests PRIVATE ZEN_TESTING)
    
    # Register tests
    add_test(NAME unit_tests COMMAND zen_tests)
    
    # Integration tests with .zen files
    if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/examples/hello-world/main.zen)
        add_test(NAME hello_world_test 
            COMMAND zen run ${CMAKE_CURRENT_SOURCE_DIR}/examples/hello-world/main.zen
        )
    endif()
    
    # Performance tests
    if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/tests/benchmarks/)
        add_test(NAME benchmark_compilation 
            COMMAND zen compile --benchmark ${CMAKE_CURRENT_SOURCE_DIR}/tests/benchmarks/large_program.zen
        )
    endif()
endif()

# =============================================================================
# INSTALLATION
# =============================================================================

# Install executable
install(TARGETS zen DESTINATION bin)

# Install standard library (when it exists)
if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/stdlib/)
    install(DIRECTORY stdlib/ DESTINATION share/zen/stdlib)
endif()

# Install examples
if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/examples/)
    install(DIRECTORY examples/ DESTINATION share/zen/examples)
endif()

# =============================================================================
# PACKAGING
# =============================================================================

set(CPACK_PACKAGE_NAME "zen")
set(CPACK_PACKAGE_VERSION ${PROJECT_VERSION})
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Zen Programming Language")
set(CPACK_PACKAGE_VENDOR "Zen Development Team")
set(CPACK_PACKAGE_CONTACT "zen@example.com")

# Platform-specific packages
if(WIN32)
    set(CPACK_GENERATOR "ZIP;NSIS")
elseif(APPLE)
    set(CPACK_GENERATOR "TGZ;productbuild")
else()
    set(CPACK_GENERATOR "TGZ;DEB;RPM")
endif()

# DEB-specific
set(CPACK_DEBIAN_PACKAGE_MAINTAINER "Zen Team")
set(CPACK_DEBIAN_PACKAGE_SECTION "devel")
set(CPACK_DEBIAN_PACKAGE_PRIORITY "optional")

# RPM-specific  
set(CPACK_RPM_PACKAGE_LICENSE "MIT")
set(CPACK_RPM_PACKAGE_GROUP "Development/Languages")

include(CPack)

# =============================================================================
# DEVELOPMENT HELPERS
# =============================================================================

# Format target (if clang-format available)
find_program(CLANG_FORMAT clang-format)
if(CLANG_FORMAT)
    add_custom_target(format
        COMMAND ${CLANG_FORMAT} -i -style=file ${ZEN_COMPILER_SOURCES} ${ZEN_COMPILER_HEADERS}
        COMMENT "Formatting source code"
    )
endif()

# Documentation target (if doxygen available)
find_package(Doxygen QUIET)
if(DOXYGEN_FOUND)
    add_custom_target(docs
        COMMAND ${DOXYGEN_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/Doxyfile
        COMMENT "Generating documentation"
    )
endif()

# Static analysis (if cppcheck available)
find_program(CPPCHECK cppcheck)
if(CPPCHECK)
    add_custom_target(check
        COMMAND ${CPPCHECK} --enable=all --std=c99 --language=c 
                ${CMAKE_CURRENT_SOURCE_DIR}/compiler/src/
        COMMENT "Running static analysis"
    )
endif()

# =============================================================================
# STATUS REPORT
# =============================================================================

message(STATUS "")
message(STATUS "Zen Configuration Summary:")
message(STATUS "  Version: ${PROJECT_VERSION}")
message(STATUS "  Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "  C Compiler: ${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION}")
message(STATUS "  Install prefix: ${CMAKE_INSTALL_PREFIX}")
message(STATUS "")
message(STATUS "Options:")
message(STATUS "  Build tests: ${ZEN_BUILD_TESTS}")
message(STATUS "  Build tools: ${ZEN_BUILD_TOOLS}")
message(STATUS "  Enable sanitizers: ${ZEN_ENABLE_SANITIZERS}")
message(STATUS "  Enable coverage: ${ZEN_ENABLE_COVERAGE}")
message(STATUS "  WebAssembly target: ${ZEN_TARGET_WASM}")
message(STATUS "")