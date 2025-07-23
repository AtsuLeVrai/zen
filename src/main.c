#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "lexer.h"
#include "parser.h"
#include "ast.h"
#include "codegen.h"
#include "native_codegen.h"

static char* read_file(const char* path) {
    FILE* file = fopen(path, "rb");
    if (file == NULL) {
        fprintf(stderr, "Could not open file \"%s\".\n", path);
        return NULL;
    }
    
    fseek(file, 0L, SEEK_END);
    size_t file_size = ftell(file);
    rewind(file);
    
    char* buffer = malloc(file_size + 1);
    if (buffer == NULL) {
        fprintf(stderr, "Not enough memory to read \"%s\".\n", path);
        fclose(file);
        return NULL;
    }
    
    size_t bytes_read = fread(buffer, sizeof(char), file_size, file);
    if (bytes_read < file_size) {
        fprintf(stderr, "Could not read file \"%s\".\n", path);
        free(buffer);
        fclose(file);
        return NULL;
    }
    
    buffer[bytes_read] = '\0';
    fclose(file);
    return buffer;
}

static void print_usage(const char* program_name) {
    printf("Usage: %s [command] [options] <source-file>\n", program_name);
    printf("Commands:\n");
    printf("  run <file>     Compile and run the program\n");
    printf("  compile <file> Compile the program (default)\n");
    printf("Options:\n");
    printf("  -h, --help     Show this help message\n");
    printf("  -o <file>      Output file (default: a.out)\n");
    printf("  --target <t>   Target platform (native, wasm)\n");
    printf("  --backend <b>  Code generator (c, native) [default: native]\n");
    printf("  --tokens       Show lexer tokens\n");
    printf("  --ast          Show abstract syntax tree\n");
    printf("  --code         Show generated code\n");
}

static void print_tokens(const char* source) {
    Lexer lexer;
    lexer_init(&lexer, source);
    
    printf("=== TOKENS ===\n");
    Token token;
    do {
        token = lexer_next_token(&lexer);
        printf("%-15s ", token_type_to_string(token.type));
        
        if (token.type == TOKEN_IDENTIFIER || token.type == TOKEN_NUMBER || 
            token.type == TOKEN_STRING) {
            printf("'%.*s' ", token.length, token.start);
        }
        
        printf("(line %d, column %d)\n", token.line, token.column);
    } while (token.type != TOKEN_EOF);
    printf("\n");
}

typedef enum {
    BACKEND_C,
    BACKEND_NATIVE
} CodegenBackend;

typedef enum {
    CMD_COMPILE,
    CMD_RUN
} Command;

int main(int argc, char* argv[]) {
    const char* source_file = NULL;
    const char* output_file = "a.out";
    CompileTarget target = TARGET_NATIVE;
    CodegenBackend backend = BACKEND_NATIVE;
    bool show_tokens = false;
    bool show_ast = false;
    bool show_code = false;
    Command command = CMD_COMPILE;
    
    // Parse command line arguments
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "run") == 0) {
            command = CMD_RUN;
            // For run command, use native backend to generate executable directly
            backend = BACKEND_NATIVE;
            output_file = ".zen_temp_executable";
        } else if (strcmp(argv[i], "compile") == 0) {
            command = CMD_COMPILE;
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        } else if (strcmp(argv[i], "-o") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Error: -o requires an output file\n");
                return 1;
            }
            output_file = argv[++i];
        } else if (strcmp(argv[i], "--target") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Error: --target requires a target platform\n");
                return 1;
            }
            const char* target_str = argv[++i];
            if (strcmp(target_str, "native") == 0) {
                target = TARGET_NATIVE;
            } else if (strcmp(target_str, "wasm") == 0) {
                target = TARGET_WASM;
            } else {
                fprintf(stderr, "Error: Unknown target '%s'\n", target_str);
                return 1;
            }
        } else if (strcmp(argv[i], "--backend") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Error: --backend requires a backend type\n");
                return 1;
            }
            const char* backend_str = argv[++i];
            if (strcmp(backend_str, "c") == 0) {
                backend = BACKEND_C;
            } else if (strcmp(backend_str, "native") == 0) {
                backend = BACKEND_NATIVE;
            } else {
                fprintf(stderr, "Error: Unknown backend '%s'\n", backend_str);
                return 1;
            }
        } else if (strcmp(argv[i], "--tokens") == 0) {
            show_tokens = true;
        } else if (strcmp(argv[i], "--ast") == 0) {
            show_ast = true;
        } else if (strcmp(argv[i], "--code") == 0) {
            show_code = true;
        } else if (argv[i][0] != '-') {
            if (source_file != NULL) {
                fprintf(stderr, "Error: Multiple source files not supported\n");
                return 1;
            }
            source_file = argv[i];
        } else {
            fprintf(stderr, "Error: Unknown option '%s'\n", argv[i]);
            return 1;
        }
    }
    
    if (source_file == NULL) {
        fprintf(stderr, "Error: No source file specified\n");
        print_usage(argv[0]);
        return 1;
    }
    
    // Read source file
    char* source = read_file(source_file);
    if (source == NULL) {
        return 1;
    }
    
    // Show tokens if requested
    if (show_tokens) {
        print_tokens(source);
    }
    
    // Initialize lexer and AST arena
    Lexer lexer;
    lexer_init(&lexer, source);
    
    ASTArena* arena = ast_arena_create();
    if (!arena) {
        fprintf(stderr, "Error: Could not create AST arena\n");
        free(source);
        return 1;
    }
    
    // Parse the source code
    Parser parser;
    parser_init(&parser, &lexer, arena);
    
    ASTNode* program = parse_program(&parser);
    
    if (parser.had_error || !program) {
        fprintf(stderr, "Parsing failed\n");
        parser_cleanup(&parser);
        ast_arena_destroy(arena);
        free(source);
        return 1;
    }
    
    // Show AST if requested
    if (show_ast) {
        printf("=== ABSTRACT SYNTAX TREE ===\n");
        ast_print(program, 0);
        printf("\n");
    }
    
    // Generate code based on backend choice
    if (backend == BACKEND_NATIVE) {
        // Use native code generator
        NativeCodeGen* native_codegen = native_codegen_create();
        if (!native_codegen) {
            fprintf(stderr, "Error: Could not create native code generator\n");
            parser_cleanup(&parser);
            ast_arena_destroy(arena);
            free(source);
            return 1;
        }
        
        if (!native_codegen_generate(native_codegen, program)) {
            fprintf(stderr, "Native code generation failed: %s\n", 
                    native_codegen->error_message ? native_codegen->error_message : "Unknown error");
            native_codegen_destroy(native_codegen);
            parser_cleanup(&parser);
            ast_arena_destroy(arena);
            free(source);
            return 1;
        }
        
        // Show generated instructions if requested
        if (show_code) {
            printf("=== GENERATED NATIVE CODE ===\n");
            Instruction* inst = native_codegen->instructions;
            while (inst) {
                if (inst->label) {
                    printf("%s:\n", inst->label);
                }
                
                switch (inst->opcode) {
                    case INST_MOV:
                        printf("    mov ");
                        break;
                    case INST_PUSH:
                        printf("    push ");
                        break;
                    case INST_POP:
                        printf("    pop ");
                        break;
                    case INST_ADD:
                        printf("    add ");
                        break;
                    case INST_SUB:
                        printf("    sub ");
                        break;
                    case INST_CALL:
                        printf("    call ");
                        break;
                    case INST_RET:
                        printf("    ret\n");
                        inst = inst->next;
                        continue;
                    case INST_SYSCALL:
                        printf("    syscall\n");
                        inst = inst->next;
                        continue;
                    case INST_NOP:
                        inst = inst->next;
                        continue;
                    default:
                        printf("    ??? ");
                        break;
                }
                
                // Print operands
                for (int i = 0; i < inst->operand_count; i++) {
                    if (i > 0) printf(", ");
                    
                    switch (inst->operands[i].type) {
                        case OPERAND_REGISTER:
                            printf("%%%s", register_name(inst->operands[i].value.reg));
                            break;
                        case OPERAND_IMMEDIATE:
                            printf("$%lld", (long long)inst->operands[i].value.immediate);
                            break;
                        case OPERAND_MEMORY:
                            printf("%d(%%%s)", inst->operands[i].value.memory.offset, 
                                   register_name(inst->operands[i].value.memory.base));
                            break;
                        case OPERAND_LABEL:
                            printf("%s", inst->operands[i].value.label);
                            break;
                    }
                }
                printf("\n");
                
                inst = inst->next;
            }
            printf("\n");
        }
        
        // Generate ELF executable
        if (!generate_elf_executable(native_codegen, output_file)) {
            fprintf(stderr, "Error: Could not generate executable '%s'\n", output_file);
            native_codegen_destroy(native_codegen);
            parser_cleanup(&parser);
            ast_arena_destroy(arena);
            free(source);
            return 1;
        }
        
        if (command == CMD_RUN) {
            printf("Running program:\n");
            printf("==================\n");
            
            // For native backend, the executable is already generated
            char run_cmd[256];
#ifdef _WIN32
            snprintf(run_cmd, sizeof(run_cmd), "%s", output_file);
#else
            snprintf(run_cmd, sizeof(run_cmd), "./%s", output_file);
#endif
            int run_result = system(run_cmd);
            printf("==================\n");
            printf("Program exited with code %d\n", run_result);
            
            // Clean up temporary executable for run command
            if (strcmp(output_file, ".zen_temp_executable") == 0) {
                remove(output_file);
            }
        } else {
            printf("Native compilation successful. Executable written to '%s'\n", output_file);
        }
        
        native_codegen_destroy(native_codegen);
        
    } else {
        // Use C code generator (existing implementation)
        CodeGen* codegen = codegen_create(target);
        if (!codegen) {
            fprintf(stderr, "Error: Could not create code generator\n");
            parser_cleanup(&parser);
            ast_arena_destroy(arena);
            free(source);
            return 1;
        }
        
        if (!codegen_generate(codegen, program)) {
            fprintf(stderr, "Code generation failed: %s\n", 
                    codegen->error_message ? codegen->error_message : "Unknown error");
            codegen_destroy(codegen);
            parser_cleanup(&parser);
            ast_arena_destroy(arena);
            free(source);
            return 1;
        }
        
        // Show generated code if requested
        if (show_code) {
            printf("=== GENERATED C CODE ===\n");
            printf("%s\n", codegen->output_buffer);
        }
        
        // Write output file
        FILE* output = fopen(output_file, "w");
        if (!output) {
            fprintf(stderr, "Error: Could not create output file '%s'\n", output_file);
            codegen_destroy(codegen);
            parser_cleanup(&parser);
            ast_arena_destroy(arena);
            free(source);
            return 1;
        }
        
        fprintf(output, "%s", codegen->output_buffer);
        fclose(output);
        
        // C backend is only used for explicit compile command now
        printf("C compilation successful. Output written to '%s'\n", output_file);
        
        codegen_destroy(codegen);
    }
    parser_cleanup(&parser);
    ast_arena_destroy(arena);
    free(source);
    
    return 0;
}